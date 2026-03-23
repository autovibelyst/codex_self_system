param([string]$Root = (Join-Path $env:USERPROFILE 'stacks\tt-core'))
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\RuntimeEnv.ps1"

$tunnelDir = Join-Path $Root "compose\tt-tunnel"
$envFile = Resolve-TTTunnelEnvPath -RootPath $Root

Push-Location $tunnelDir
try {
  docker compose --env-file $envFile down
} finally {
  Pop-Location
}

Write-Host "OK: Tunnel stopped." -ForegroundColor Green