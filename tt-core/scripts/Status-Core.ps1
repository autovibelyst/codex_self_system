param(
  [string] $Root = (Join-Path $env:USERPROFILE 'stacks\tt-core')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_compose_args.ps1"
. "$PSScriptRoot\lib\RuntimeEnv.ps1"

$coreDir = Join-Path $Root 'compose\tt-core'
$profiles = @()
$selectPath = Join-Path $Root 'config\services.select.json'
if (Test-Path $selectPath) {
  try {
    $sel = Get-Content $selectPath -Raw | ConvertFrom-Json
    foreach ($entry in $sel.profiles.PSObject.Properties) {
      if ([bool]$entry.Value -and -not $entry.Name.StartsWith('_')) {
        $profiles += $entry.Name
      }
    }
  } catch {
    Write-Host "[WARN] Could not read services.select.json for status profiles: $_" -ForegroundColor Yellow
  }
}

Write-Host ''
Write-Host '== TT-Core Status ==' -ForegroundColor Cyan

Push-Location $coreDir
try {
  $composeArgs = Get-TTComposeArgs -ComposeDir $coreDir -EnabledProfiles $profiles
  $coreEnvFile = Resolve-TTCoreEnvPath -RootPath $Root
  $composeArgs += '--env-file', $coreEnvFile, 'ps'
  docker compose @composeArgs
} finally {
  Pop-Location
}

Write-Host ''
Write-Host '== All TT containers ==' -ForegroundColor Cyan
docker ps --filter 'name=tt-core' --format 'table {{.Names}}`t{{.Status}}`t{{.Ports}}'

Write-Host ''
Write-Host '== TT Tunnel ==' -ForegroundColor Cyan
docker ps --filter 'name=tt-core-cloudflared' --format 'table {{.Names}}`t{{.Status}}'