[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$Version = '0.1.0-rc.5'
$SourcePackageRoot = Join-Path $RepositoryRoot 'packages'
$PackageNames = @(
  'deepseek-ai-dsh-client-ui-knowledge-0.1.0-rc.5.tgz',
  'deepseek-ai-dsh-client-ui-surface-0.1.0-rc.5.tgz',
  'deepseek-ai-dsh-knowledge-0.1.0-rc.5.tgz',
  'deepseek-ai-dsh-knowledge-ai-0.1.0-rc.5.tgz',
  'deepseek-ai-dsh-knowledge-local-0.1.0-rc.5.tgz',
  'deepseek-ai-dsh-knowledge-studio-0.1.0-rc.5.tgz'
)
$ReleaseRoot = Join-Path $RepositoryRoot 'release'
$Stage = Join-Path $ReleaseRoot 'staging'
$Archive = Join-Path $ReleaseRoot "knowledge-studio-windows-x64-v$Version.zip"

if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $Stage 'packages') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Stage 'examples') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Stage 'LICENSES') -Force | Out-Null

foreach ($name in $PackageNames) {
  $source = Join-Path $SourcePackageRoot $name
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing source package: $source" }
  Copy-Item -LiteralPath $source -Destination (Join-Path $Stage 'packages') -Force
}

Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'install.ps1') -Destination $Stage
Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'install.cmd') -Destination $Stage
Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'uninstall.ps1') -Destination $Stage
Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'uninstall.cmd') -Destination $Stage
Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'README.md') -Destination $Stage
Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'README.en.md') -Destination $Stage
Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'LICENSE') -Destination $Stage
Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'NOTICE.md') -Destination $Stage
Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'LICENSES\DeepSeek-Knowledge-Studio-MIT.txt') -Destination (Join-Path $Stage 'LICENSES')
Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'examples\starter-vault') -Destination (Join-Path $Stage 'examples') -Recurse

$checksumLines = foreach ($name in $PackageNames) {
  $path = Join-Path $Stage "packages\$name"
  $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
  "$hash *packages/$name"
}
$encoding = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $Stage 'checksums.sha256'), ($checksumLines -join "`n") + "`n", $encoding)
[IO.File]::WriteAllText((Join-Path $RepositoryRoot 'checksums.sha256'), ($checksumLines -join "`n") + "`n", $encoding)

if (Test-Path -LiteralPath $Archive) { Remove-Item -LiteralPath $Archive -Force }
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
try {
  $env:TEMP = $ReleaseRoot
  $env:TMP = $ReleaseRoot
  Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $Archive -CompressionLevel Optimal
} finally {
  $env:TEMP = $oldTemp
  $env:TMP = $oldTmp
}

$archiveHash = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash
Write-Host "Built: $Archive"
Write-Host "SHA256: $archiveHash"

