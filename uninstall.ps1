[CmdletBinding()]
param(
  [string]$HarnessRoot,
  [string]$DshHome,
  [string]$Profile = 'web',
  [switch]$SkipRunningCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PackageNames = @(
  '@deepseek-ai/dsh-client-ui-knowledge',
  '@deepseek-ai/dsh-client-ui-surface',
  '@deepseek-ai/dsh-knowledge',
  '@deepseek-ai/dsh-knowledge-ai',
  '@deepseek-ai/dsh-knowledge-local',
  '@deepseek-ai/dsh-knowledge-studio'
)
$MarkerStart = '# BEGIN KNOWLEDGE-STUDIO-INSTALLER'
$MarkerEnd = '# END KNOWLEDGE-STUDIO-INSTALLER'

function Resolve-FullPath([string]$Path) {
  return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Find-HarnessRoot([string]$Requested) {
  $candidates = @($Requested, $env:DSH_INSTALL, 'G:\DeepSeek Harness')
  if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) { $candidates += (Join-Path $env:ProgramFiles 'DeepSeek Harness') }
  foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
    $full = Resolve-FullPath $candidate
    if ((Test-Path -LiteralPath (Join-Path $full 'resources\runtime\win32-x64\node.exe')) -and
        (Test-Path -LiteralPath (Join-Path $full 'resources\harness\lib\bin.js'))) { return $full }
  }
  throw 'DeepSeek Harness was not found. Use -HarnessRoot to select the installation directory.'
}

function Find-DshHome([string]$Requested, [string]$Root) {
  if (-not [string]::IsNullOrWhiteSpace($Requested)) { return Resolve-FullPath $Requested }
  if (-not [string]::IsNullOrWhiteSpace($env:DSH_HOME)) { return Resolve-FullPath $env:DSH_HOME }
  $portable = Join-Path $Root 'data\dsh-home'
  if (Test-Path -LiteralPath $portable) { return Resolve-FullPath $portable }
  return Resolve-FullPath (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh')
}

if (-not $SkipRunningCheck) {
  $running = @(Get-Process -Name 'DeepSeek Harness Runtime' -ErrorAction SilentlyContinue)
  if ($running.Count -gt 0) { throw 'Close DeepSeek Harness completely, then run the uninstaller again.' }
}

$HarnessRoot = Find-HarnessRoot $HarnessRoot
$DshHome = Find-DshHome $DshHome $HarnessRoot
$env:DSH_HOME = $DshHome
$node = Join-Path $HarnessRoot 'resources\runtime\win32-x64\node.exe'
$bin = Join-Path $HarnessRoot 'resources\harness\lib\bin.js'
$profileDir = Join-Path $DshHome "profiles\$Profile"

$backupDir = Join-Path $DshHome ("knowledge-studio-backups\uninstall-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
foreach ($name in @('package.json','pnpm-lock.yaml','cordis.patch.yml')) {
  $source = Join-Path $profileDir $name
  if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-Item -LiteralPath $source -Destination $backupDir -Force }
}

& $node $bin plugin --profile $Profile remove @PackageNames
if ($LASTEXITCODE -ne 0) { throw "Plugin removal failed with exit code $LASTEXITCODE. Backup: $backupDir" }

$patchPath = Join-Path $profileDir 'cordis.patch.yml'
if (Test-Path -LiteralPath $patchPath) {
  $current = [IO.File]::ReadAllText($patchPath)
  $pattern = '(?s)\s*' + [regex]::Escape($MarkerStart) + '.*?' + [regex]::Escape($MarkerEnd) + '\s*'
  $updated = [regex]::Replace($current, $pattern, [Environment]::NewLine).TrimEnd() + [Environment]::NewLine
  $meaningful = @($updated -split "`r?`n" | Where-Object { $_.Trim() -ne '' -and -not $_.TrimStart().StartsWith('#') })
  if ($meaningful.Count -eq 0) { $updated = $updated.TrimEnd() + [Environment]::NewLine + '[]' + [Environment]::NewLine }
  [IO.File]::WriteAllText($patchPath, $updated, [Text.UTF8Encoding]::new($false))
}

Write-Host ''
Write-Host 'Knowledge Studio plugin removal completed.' -ForegroundColor Green
Write-Host 'Knowledge vaults, images, canvases, and backups were preserved.'
Write-Host "Pre-removal backup: $backupDir"

