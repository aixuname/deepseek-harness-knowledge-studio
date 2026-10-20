# Architecture

Knowledge Studio is shipped as six cooperating Harness packages:

```text
@deepseek-ai/dsh-knowledge-studio (bundle patch)
├── @deepseek-ai/dsh-knowledge             domain + Remote contract
├── @deepseek-ai/dsh-knowledge-local       local Markdown persistence
├── @deepseek-ai/dsh-knowledge-ai          bounded AI context service
├── @deepseek-ai/dsh-client-ui-surface     persistent top-level surface
└── @deepseek-ai/dsh-client-ui-knowledge   browser UI, graph, editor, canvas
```

The client bundle is intentionally not a conventional browser ESM entry. It
uses Harness's runtime contract:

```js
window.__ModuleLoader__.load({
  id: '@deepseek-ai/dsh-client-ui-knowledge',
  factory: (require) => { /* bundled module */ },
})
```

CSS and font routes are registered when that factory executes. The installer
delegates dependency mutation to `dsh plugin`, allowing Harness to perform its
own compatibility diagnostics and snapshot handling.

The release wrapper adds one marked override to the user's profile patch. This
replaces the developer machine's fixed knowledge path with a path selected on
the target machine. Uninstallation removes only that marked block.

