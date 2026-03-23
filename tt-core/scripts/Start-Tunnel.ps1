#Requires -Version 5.1
<#
.SYNOPSIS
    Start the Cloudflare Tunnel stack (token mode only).

.DESCRIPTION
    Starts the tt-tunnel Docker Compose stack using CF_TUNNEL_TOKEN.
    Public route intent is stored in config\services.select.json and can be
    reviewed with scripts\Show-TunnelPlan.ps1 before you configure routes in
    the Cloudflare dashboard.

.PARAMETER Root
    TT-Core root folder. Default: %USERPROFILE%\stacks\tt-core
#>
param(
  [string]$Root = (Join-Path $env:USERPROFILE 'stacks\tt-core'),
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\RuntimeEnv.ps1"

$tunnelDir  = Join-Path $Root "compose\tt-tunnel"
$envFile    = Resolve-TTTunnelEnvPath -RootPath $Root
$selectPath = Join-Path $Root "config\services.select.json"

if (!(Test-Path $envFile)) {
  throw "Tunnel runtime env not found: $envFile`nCreate it from env\tunnel.env.example and set CF_TUNNEL_TOKEN."
}

$token = (Get-Content $envFile | Where-Object { $_ -match "^CF_TUNNEL_TOKEN=" } | Select-Object -First 1) -replace "^CF_TUNNEL_TOKEN=", ""
if (!$token -or $token -match '^__' -or $token -match '^\s*$') {
  throw "CF_TUNNEL_TOKEN is not configured in: $envFile`nGet your token from Cloudflare Zero Trust -> Networks -> Tunnels."
}

if (Test-Path $selectPath) {
  try {
    $select = Get-Content $selectPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($select.tunnel -and $select.tunnel.enabled -ne $true) {
      if (-not $Force) {
        throw "config\services.select.json marks tunnel.enabled=false. Refusing to start the tunnel. Use -Force only for maintenance or emergency override."
      }
      Write-Host "WARN: tunnel.enabled=false in config\services.select.json; starting anyway because -Force was supplied." -ForegroundColor Yellow
    }
  } catch {
    Write-Host "WARN: Could not read config\services.select.json; continuing with token-only tunnel start." -ForegroundColor Yellow
  }
}

Push-Location $tunnelDir
try {
  docker compose --env-file $envFile up -d
} finally {
  Pop-Location
}

Write-Host ""
Write-Host "OK: Tunnel started (token mode, selection-driven)." -ForegroundColor Green

Write-Host ""
Write-Host "  Syncing service URLs with tunnel configuration..." -ForegroundColor Cyan
$updateScript = Join-Path $PSScriptRoot "Update-TunnelURLs.ps1"
if (Test-Path $updateScript) {
  try {
    & $updateScript -Root $Root
    Write-Host "  URL sync complete. Restart n8n if it is already running:" -ForegroundColor DarkGray
    Write-Host "    scripts\ttcore.ps1 restart core" -ForegroundColor DarkGray
  } catch {
    Write-Host "  WARN: URL sync failed: $_" -ForegroundColor Yellow
    Write-Host "  Run manually: scripts\Update-TunnelURLs.ps1" -ForegroundColor DarkGray
  }
}
Write-Host "  Review desired public routes with: scripts\Show-TunnelPlan.ps1" -ForegroundColor DarkGray
Write-Host "  Run 'docker logs tt-core-cloudflared' to verify connection." -ForegroundColor DarkGray
Write-Host "  Run 'scripts\Update-TunnelURLs.ps1' after changing n8n public route intent." -ForegroundColor DarkGray