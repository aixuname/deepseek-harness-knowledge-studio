[CmdletBinding()]
param(
  [string]$HarnessRoot,
  [string]$DshHome,
  [string]$KnowledgeRoot,
  [string]$Profile = 'web',
  [switch]$AllowUnsupportedHarnessVersion,
  [switch]$SkipRunningCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PluginVersion = '0.1.0-rc.5'
$SupportedHarnessVersions = @('0.1.2-rc.1')
$PackageFiles = @(
  'deepseek-ai-dsh-client-ui-knowledge-0.1.0-rc.5.tgz',
  'deepseek-ai-dsh-client-ui-surface-0.1.0-rc.5.tgz',
  'deepseek-ai-dsh-knowledge-0.1.0-rc.5.tgz',
  'deepseek-ai-dsh-knowledge-ai-0.1.0-rc.5.tgz',
  'deepseek-ai-dsh-knowledge-local-0.1.0-rc.5.tgz',
  'deepseek-ai-dsh-knowledge-studio-0.1.0-rc.5.tgz'
)
$MarkerStart = '# BEGIN KNOWLEDGE-STUDIO-INSTALLER'
$MarkerEnd = '# END KNOWLEDGE-STUDIO-INSTALLER'

function Resolve-FullPath([string]$Path) {
  return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Find-HarnessRoot([string]$Requested) {
  $candidates = [Collections.Generic.List[string]]::new()
  if (-not [string]::IsNullOrWhiteSpace($Requested)) { $candidates.Add($Requested) }
  if (-not [string]::IsNullOrWhiteSpace($env:DSH_INSTALL)) { $candidates.Add($env:DSH_INSTALL) }
  $candidates.Add('G:\DeepSeek Harness')
  if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
    $candidates.Add((Join-Path $env:ProgramFiles 'DeepSeek Harness'))
  }
  if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
    $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'DeepSeek Harness'))
  }
  foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
    $full = Resolve-FullPath $candidate
    $node = Join-Path $full 'resources\runtime\win32-x64\node.exe'
    $bin = Join-Path $full 'resources\harness\lib\bin.js'
    if ((Test-Path -LiteralPath $node -PathType Leaf) -and (Test-Path -LiteralPath $bin -PathType Leaf)) {
      return $full
    }
  }
  throw 'DeepSeek Harness was not found. Use -HarnessRoot to select the installation directory that contains resources.'
}

function Find-DshHome([string]$Requested, [string]$Root) {
  if (-not [string]::IsNullOrWhiteSpace($Requested)) { return Resolve-FullPath $Requested }
  if (-not [string]::IsNullOrWhiteSpace($env:DSH_HOME)) { return Resolve-FullPath $env:DSH_HOME }
  $portable = Join-Path $Root 'data\dsh-home'
  if (Test-Path -LiteralPath $portable) { return Resolve-FullPath $portable }
  return Resolve-FullPath (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh')
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  $encoding = [Text.UTF8Encoding]::new($false)
  [IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Escape-YamlSingle([string]$Text) {
  return $Text.Replace("'", "''")
}

function Test-PackageHashes([string]$PackageRoot) {
  $checksumFile = Join-Path $PSScriptRoot 'checksums.sha256'
  if (-not (Test-Path -LiteralPath $checksumFile -PathType Leaf)) {
    throw "Checksum file is missing: $checksumFile"
  }
  $expected = @{}
  foreach ($line in Get-Content -LiteralPath $checksumFile) {
    if ($line -match '^([0-9A-Fa-f]{64})\s+\*?(.+)$') {
      $expected[$matches[2].Replace('/', '\')] = $matches[1].ToUpperInvariant()
    }
  }
  foreach ($name in $PackageFiles) {
    $relative = "packages\$name"
    $path = Join-Path $PackageRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Plugin archive is missing: $name" }
    if (-not $expected.ContainsKey($relative)) { throw "Checksum manifest entry is missing: $relative" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actual -ne $expected[$relative]) { throw "Plugin archive hash mismatch: $name" }
  }
}

function Set-PortableCacheEnvironment([string]$DshHomePath) {
  $map = [ordered]@{
    DSH_HOME = $DshHomePath
    NPM_CONFIG_CACHE = (Join-Path $DshHomePath '.cache\npm')
    PNPM_HOME = (Join-Path $DshHomePath '.cache\pnpm-home')
    PNPM_STORE_DIR = (Join-Path $DshHomePath '.cache\pnpm-store')
    COREPACK_HOME = (Join-Path $DshHomePath '.cache\corepack')
    XDG_CACHE_HOME = (Join-Path $DshHomePath '.cache\xdg')
    TEMP = (Join-Path $DshHomePath 'temp')
    TMP = (Join-Path $DshHomePath 'temp')
  }
  foreach ($entry in $map.GetEnumerator()) {
    New-Item -ItemType Directory -Path $entry.Value -Force | Out-Null
    [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
  }
}

function Set-KnowledgePatch([string]$PatchPath, [string]$Root, [string]$ExampleRoot) {
  $drive = [IO.Path]::GetPathRoot($Root).TrimEnd('\')
  if ($drive -notmatch '^[A-Za-z]:$') {
    throw 'KnowledgeRoot must be on a local drive. UNC network paths are not supported by this release.'
  }
  $block = @"
$MarkerStart
# Added by the Knowledge Studio release installer. User notes are never removed.
- id: knowledge-local
  config:
    defaultRoot: '$(Escape-YamlSingle $Root)'
    roots:
      - '$(Escape-YamlSingle $ExampleRoot)'
    allowedDrives: ['$drive']
$MarkerEnd
"@
  $current = if (Test-Path -LiteralPath $PatchPath) { [IO.File]::ReadAllText($PatchPath) } else { '' }
  $pattern = [regex]::Escape($MarkerStart) + '.*?' + [regex]::Escape($MarkerEnd)
  if ([regex]::IsMatch($current, $pattern, [Text.RegularExpressions.RegexOptions]::Singleline)) {
    $updated = [regex]::Replace($current, $pattern, $block.Trim(), [Text.RegularExpressions.RegexOptions]::Singleline)
  } else {
    # A freshly initialized profile uses [] as its complete empty YAML document.
    # Remove only that standalone sentinel before appending the first list entry.
    $current = [regex]::Replace($current, '(?m)^\s*\[\]\s*$', '').TrimEnd()
    $updated = $current.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block.Trim() + [Environment]::NewLine
  }
  Write-Utf8NoBom $PatchPath $updated
}

if (-not $SkipRunningCheck) {
  $running = @(Get-Process -Name 'DeepSeek Harness Runtime' -ErrorAction SilentlyContinue)
  if ($running.Count -gt 0) { throw 'Close DeepSeek Harness completely, then run the installer again.' }
}

$HarnessRoot = Find-HarnessRoot $HarnessRoot
$DshHome = Find-DshHome $DshHome $HarnessRoot
$KnowledgeRoot = if ([string]::IsNullOrWhiteSpace($KnowledgeRoot)) {
  if (Test-Path -LiteralPath (Join-Path $HarnessRoot 'data')) {
    Resolve-FullPath (Join-Path $HarnessRoot 'data\knowledge')
  } else {
    Resolve-FullPath (Join-Path $DshHome 'knowledge')
  }
} else { Resolve-FullPath $KnowledgeRoot }

$harnessPackage = Join-Path $HarnessRoot 'resources\harness\package.json'
$harnessVersion = (Get-Content -LiteralPath $harnessPackage -Raw | ConvertFrom-Json).version
if (($SupportedHarnessVersions -notcontains $harnessVersion) -and -not $AllowUnsupportedHarnessVersion) {
  throw "Harness $harnessVersion is not verified. Supported: $($SupportedHarnessVersions -join ', '). Use -AllowUnsupportedHarnessVersion only if you accept the compatibility risk."
}

$sourcePackages = Join-Path $PSScriptRoot 'packages'
Test-PackageHashes $sourcePackages
New-Item -ItemType Directory -Path $DshHome,$KnowledgeRoot -Force | Out-Null
Set-PortableCacheEnvironment $DshHome

$profileDir = Join-Path $DshHome "profiles\$Profile"
$backupDir = Join-Path $DshHome ("knowledge-studio-backups\" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
foreach ($name in @('package.json','pnpm-lock.yaml','cordis.patch.yml')) {
  $source = Join-Path $profileDir $name
  if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-Item -LiteralPath $source -Destination $backupDir -Force }
}

$installedArchiveRoot = Join-Path $DshHome "packages\knowledge-studio\$PluginVersion"
New-Item -ItemType Directory -Path $installedArchiveRoot -Force | Out-Null
$installedArchives = foreach ($name in $PackageFiles) {
  $destination = Join-Path $installedArchiveRoot $name
  Copy-Item -LiteralPath (Join-Path $sourcePackages $name) -Destination $destination -Force
  $destination
}

$node = Join-Path $HarnessRoot 'resources\runtime\win32-x64\node.exe'
$bin = Join-Path $HarnessRoot 'resources\harness\lib\bin.js'
Write-Host "Installing Knowledge Studio $PluginVersion ..." -ForegroundColor Cyan
& $node $bin plugin --profile $Profile add @installedArchives
if ($LASTEXITCODE -ne 0) { throw "Harness plugin installation failed with exit code $LASTEXITCODE. Backup: $backupDir" }

$exampleSource = Join-Path $PSScriptRoot 'examples\starter-vault'
$exampleTarget = Join-Path $KnowledgeRoot 'Knowledge Studio Starter'
if (-not (Test-Path -LiteralPath $exampleTarget)) {
  Copy-Item -LiteralPath $exampleSource -Destination $exampleTarget -Recurse
}

$patchPath = Join-Path $profileDir 'cordis.patch.yml'
Set-KnowledgePatch $patchPath $KnowledgeRoot $exampleTarget

& $node $bin plugin --profile $Profile doctor
if ($LASTEXITCODE -ne 0) { throw "The plugin was installed but Harness doctor failed with exit code $LASTEXITCODE. Backup: $backupDir" }

Write-Host ''
Write-Host 'Knowledge Studio installation completed.' -ForegroundColor Green
Write-Host "Harness: $HarnessRoot"
Write-Host "Knowledge root: $KnowledgeRoot"
Write-Host "Backup: $backupDir"
Write-Host 'You can now restart DeepSeek Harness.'

