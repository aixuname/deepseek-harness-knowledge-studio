[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$Stage = Join-Path $RepositoryRoot 'release\staging'
$RepositoryPackageRoot = Join-Path $RepositoryRoot 'packages'
$RequiredPackages = @(
  '@deepseek-ai/dsh-client-ui-knowledge',
  '@deepseek-ai/dsh-client-ui-surface',
  '@deepseek-ai/dsh-knowledge',
  '@deepseek-ai/dsh-knowledge-ai',
  '@deepseek-ai/dsh-knowledge-local',
  '@deepseek-ai/dsh-knowledge-studio'
)

function Read-Utf8([string]$Path) {
  return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

foreach ($script in @('install.ps1','uninstall.ps1','scripts\build-release.ps1','scripts\verify-release.ps1')) {
  $path = Join-Path $RepositoryRoot $script
  $tokens = $null
  $errors = $null
  [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) { throw "PowerShell parse errors in $script`: $($errors -join '; ')" }
}

$manifest = Read-Utf8 (Join-Path $RepositoryRoot 'examples\starter-vault\.dsh-knowledge\manifest.json') | ConvertFrom-Json
$links = Read-Utf8 (Join-Path $RepositoryRoot 'examples\starter-vault\.dsh-knowledge\links.json') | ConvertFrom-Json
$graph = Read-Utf8 (Join-Path $RepositoryRoot 'examples\starter-vault\.dsh-knowledge\graph.json') | ConvertFrom-Json
if (@($manifest.notes.PSObject.Properties).Count -ne 3) { throw 'Starter manifest must contain three notes.' }
if (@($links.notes.PSObject.Properties).Count -ne 3) { throw 'Starter link index must contain three notes.' }
if (@($graph.nodes).Count -ne 3 -or @($graph.edges).Count -ne 3) { throw 'Starter graph must contain three nodes and three edges.' }
foreach ($note in $manifest.notes.PSObject.Properties) {
  if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $RepositoryRoot 'examples\starter-vault') $note.Value.path))) {
    throw "Starter note missing: $($note.Value.path)"
  }
}

if (-not (Test-Path -LiteralPath $Stage)) { throw 'Release staging directory is missing. Run build-release.ps1 first.' }
$actualPackages = @()
foreach ($archive in Get-ChildItem -LiteralPath (Join-Path $Stage 'packages') -Filter '*.tgz') {
  $metadata = tar -xOf $archive.FullName package/package.json | ConvertFrom-Json
  if ($metadata.version -ne '0.1.0-rc.5') { throw "Unexpected package version: $($metadata.name) $($metadata.version)" }
  if ($metadata.license -ne 'MIT') { throw "Unexpected package license: $($metadata.name)" }
  $actualPackages += $metadata.name
  $licenseEntries = @(tar -tf $archive.FullName | Where-Object { $_ -eq 'package/LICENSE' })
  if ($licenseEntries.Count -ne 1) { throw "Package license missing: $($metadata.name)" }
}
foreach ($name in $RequiredPackages) {
  if ($actualPackages -notcontains $name) { throw "Release package missing: $name" }
}

foreach ($archive in Get-ChildItem -LiteralPath $RepositoryPackageRoot -Filter '*.tgz') {
  $staged = Join-Path (Join-Path $Stage 'packages') $archive.Name
  if (-not (Test-Path -LiteralPath $staged)) { throw "Staged archive missing: $($archive.Name)" }
  if ((Get-FileHash -LiteralPath $archive.FullName -Algorithm SHA256).Hash -ne
      (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash) {
    throw "Repository and staged archive differ: $($archive.Name)"
  }
}

$checksumFile = Join-Path $Stage 'checksums.sha256'
foreach ($line in Get-Content -LiteralPath $checksumFile) {
  if ($line -notmatch '^([0-9a-f]{64})\s+\*?(.+)$') { throw "Invalid checksum line: $line" }
  $path = Join-Path $Stage ($matches[2].Replace('/', '\'))
  $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $matches[1]) { throw "Checksum mismatch: $($matches[2])" }
}

$clientArchive = Join-Path $Stage 'packages\deepseek-ai-dsh-client-ui-knowledge-0.1.0-rc.5.tgz'
$prefix = (tar -xOf $clientArchive package/lib/client.js | Select-Object -First 1)
if ($prefix -ne 'window.__ModuleLoader__.load({') { throw 'Client package is not in Harness factory-CJS loader format.' }

$forbidden = @('gho_[A-Za-z0-9_]+','\?token=[A-Za-z0-9_-]+','C:\\Users\\[0-9]+','G:\\DeepSeek Harness\\data\\knowledge\\(agent|3DGS|动手)')
$textFiles = Get-ChildItem -LiteralPath $RepositoryRoot -File -Recurse | Where-Object {
  $_.FullName -notlike "$Stage*" -and $_.Extension -in @('.md','.ps1','.cmd','.json','.yml','.yaml','.txt','.sha256')
}
foreach ($file in $textFiles) {
  $text = Get-Content -LiteralPath $file.FullName -Raw
  foreach ($pattern in $forbidden) {
    if ($text -match $pattern) { throw "Sensitive or machine-specific value found in $($file.FullName): $pattern" }
  }
}

[ordered]@{
  powershellScripts = 4
  packages = $actualPackages.Count
  packageVersion = '0.1.0-rc.5'
  licenses = 'MIT'
  starterNotes = @($manifest.notes.PSObject.Properties).Count
  starterGraphNodes = @($graph.nodes).Count
  starterGraphEdges = @($graph.edges).Count
  checksumsVerified = (Get-Content -LiteralPath $checksumFile).Count
  harnessLoaderFormat = $true
  forbiddenValueMatches = 0
} | ConvertTo-Json

