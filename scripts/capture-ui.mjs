import assert from 'node:assert/strict'
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { spawn } from 'node:child_process'

const targetUrl = process.env.KNOWLEDGE_STUDIO_TEST_URL
if (!targetUrl) throw new Error('KNOWLEDGE_STUDIO_TEST_URL is required')

const chrome = process.env.CHROME_PATH ?? 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'
const repoRoot = resolve(new URL('..', import.meta.url).pathname.replace(/^\/(?:([A-Za-z]:))/, '$1').replaceAll('/', '\\'))
const outputDir = join(repoRoot, 'docs')
const tempRoot = resolve(process.env.KNOWLEDGE_STUDIO_TEST_TEMP ?? join(repoRoot, 'test-output'))
const profile = mkdtempSync(join(tempRoot, 'chrome-profile-'))
const pageErrors = []

const browser = spawn(chrome, [
  '--headless=new',
  '--remote-debugging-port=0',
  `--user-data-dir=${profile}`,
  '--no-first-run',
  '--no-default-browser-check',
  '--disable-background-networking',
  '--disable-sync',
  '--window-size=1680,1000',
  targetUrl,
], { stdio: 'ignore', windowsHide: true })

const delay = (ms) => new Promise((resolveDelay) => setTimeout(resolveDelay, ms))
const portFile = join(profile, 'DevToolsActivePort')
for (let count = 0; count < 150 && !existsSync(portFile); count += 1) await delay(100)
assert.ok(existsSync(portFile), 'Chrome did not expose DevToolsActivePort')
const [port] = readFileSync(portFile, 'utf8').trim().split(/\r?\n/)

let targets = []
for (let count = 0; count < 100; count += 1) {
  targets = await fetch(`http://127.0.0.1:${port}/json/list`).then((response) => response.json())
  if (targets.some((target) => target.type === 'page')) break
  await delay(100)
}
const page = targets.find((target) => target.type === 'page')
assert.ok(page?.webSocketDebuggerUrl, 'No Chrome page target was found')

const socket = new WebSocket(page.webSocketDebuggerUrl)
await new Promise((resolveOpen, rejectOpen) => {
  socket.addEventListener('open', resolveOpen, { once: true })
  socket.addEventListener('error', rejectOpen, { once: true })
})

let sequence = 0
const pending = new Map()
socket.addEventListener('message', (event) => {
  const message = JSON.parse(event.data)
  if (message.method === 'Runtime.exceptionThrown') pageErrors.push(message.params.exceptionDetails.text)
  if (!message.id) return
  const waiter = pending.get(message.id)
  if (!waiter) return
  pending.delete(message.id)
  if (message.error) waiter.reject(new Error(message.error.message))
  else waiter.resolve(message.result)
})

function command(method, params = {}) {
  const id = ++sequence
  socket.send(JSON.stringify({ id, method, params }))
  return new Promise((resolveCommand, rejectCommand) => pending.set(id, { resolve: resolveCommand, reject: rejectCommand }))
}

async function evaluate(expression) {
  const result = await command('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.text)
  return result.result.value
}

async function waitFor(expression, label, attempts = 160) {
  for (let count = 0; count < attempts; count += 1) {
    if (await evaluate(expression)) return
    await delay(100)
  }
  const body = await evaluate(`document.body?.innerText.slice(0, 1500) ?? ''`)
  throw new Error(`Timed out waiting for ${label}. Body: ${body}`)
}

async function clickText(label) {
  return evaluate(`(() => {
    const label = ${JSON.stringify(label)};
    const exact = [...document.querySelectorAll('body *')].filter((item) => item.textContent.trim() === label);
    const element = exact.find((item) => item.matches('button, a, [role="button"]'))
      ?? exact.find((item) => item.closest('button, a, [role="button"]'))?.closest('button, a, [role="button"]')
      ?? exact.at(-1);
    if (!element) return false;
    if (typeof element.click === 'function') element.click();
    else element.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
    return true;
  })()`)
}

async function screenshot(name) {
  const result = await command('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, fromSurface: true })
  writeFileSync(join(outputDir, name), Buffer.from(result.data, 'base64'))
}

try {
  await command('Page.enable')
  await command('Runtime.enable')
  await command('Emulation.setDeviceMetricsOverride', { width: 1680, height: 1000, deviceScaleFactor: 1, mobile: false })
  await waitFor(`document.readyState === 'complete'`, 'page load')
  await delay(1500)
  if (await evaluate(`document.body?.innerText.includes('Skip all') ?? false`)) await clickText('Skip all')
  if (await evaluate(`document.body?.innerText.includes('跳过全部') ?? false`)) await clickText('跳过全部')
  if (await evaluate(`document.body?.innerText.includes('Start using Harness') ?? false`)) await clickText('Start using Harness')
  if (await evaluate(`document.body?.innerText.includes('开始使用 Harness') ?? false`)) await clickText('开始使用 Harness')
  await delay(500)
  if (await evaluate(`document.body?.innerText.includes('开始体验') ?? false`)) await clickText('开始体验')
  await delay(300)
  if (await evaluate(`document.body?.innerText.includes('完成基础配置') ?? false`)) {
    await evaluate(`(() => {
      const modal = [...document.querySelectorAll('body *')].find((item) => item.textContent.includes('完成基础配置') && item.querySelectorAll('button').length > 0);
      const buttons = [...(modal?.querySelectorAll('button') ?? [])];
      const close = buttons.find((button) => /关闭|close/i.test((button.getAttribute('aria-label') ?? '') + ' ' + (button.getAttribute('title') ?? '')))
        ?? buttons.find((button) => button.querySelector('svg') && button.textContent.trim() === '');
      close?.click();
      return Boolean(close);
    })()`)
  }
  await waitFor(`!document.body?.innerText.includes('完成基础配置') && !document.body?.innerText.includes('已准备就绪')`, 'onboarding dismissal')

  await waitFor(`document.body?.innerText.includes('知识工作室') ?? false`, 'Knowledge Studio launcher')
  assert.ok(await clickText('知识工作室'), 'Could not open Knowledge Studio')
  await waitFor(`document.querySelector('select[aria-label="当前知识库"]') !== null`, 'vault selector')
  await waitFor(`(document.querySelector('select[aria-label="当前知识库"]')?.options.length ?? 0) > 0`, 'vault options')

  const vaultOptions = await evaluate(`[...document.querySelector('select[aria-label="当前知识库"]').options].map((item) => item.textContent.trim())`)
  assert.ok(vaultOptions.includes('入门示例'), `Starter vault missing: ${JSON.stringify(vaultOptions)}`)
  assert.ok(await evaluate(`(() => {
    const select = document.querySelector('select[aria-label="当前知识库"]');
    const option = [...select.options].find((item) => item.textContent.trim() === '入门示例');
    if (!option) return false;
    select.value = option.value;
    select.dispatchEvent(new Event('change', { bubbles: true }));
    return true;
  })()`), 'Could not select starter vault')

  await waitFor(`document.body?.innerText.includes('00 欢迎使用知识工作室') ?? false`, 'starter note')
  assert.ok(await clickText('00 欢迎使用知识工作室'), 'Could not open starter note')
  await waitFor(`document.body?.innerText.includes('Markdown 示例') ?? false`, 'rendered Markdown')
  await screenshot('knowledge-studio-note.png')

  assert.ok(await clickText('关系画布'), 'Could not open relationship canvas')
  await waitFor(`document.body?.innerText.includes('知识关系画布') ?? false`, 'relationship canvas')
  await waitFor(`document.querySelectorAll('svg').length > 0`, 'relationship graph SVG')
  await screenshot('knowledge-studio-graph.png')

  console.log(JSON.stringify({
    vaultOptions,
    markdownRendered: true,
    graphRendered: true,
    screenshots: ['docs/knowledge-studio-note.png', 'docs/knowledge-studio-graph.png'],
    pageErrors: pageErrors.length,
  }))
  assert.equal(pageErrors.length, 0, `Browser exceptions: ${pageErrors.join('; ')}`)
} finally {
  socket.close()
  browser.kill()
  await delay(300)
  rmSync(profile, { recursive: true, force: true })
}

