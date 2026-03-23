#Requires -Version 5.1
<#
.SYNOPSIS
    Sync service URLs in core .env based on tunnel configuration in services.select.json.

.DESCRIPTION
    SOURCE OF TRUTH MODEL (v14.0):
    - Route INTENT comes from config/services.select.json (canonical authority)
    - Tunnel TOKEN comes from the external runtime tunnel env (runtime secret — never a source of truth)
    - Service URLs are DERIVED and written to the external runtime core env (runtime output)

    This script reads intent from services.select.json and domain from tunnel .env,
    then writes correct service URLs to the core runtime .env.

    Run this any time you change tunnel.enabled, tunnel.routes, tunnel.subdomains,
    or client.domain in services.select.json.

.PARAMETER Root
    TT-Core root folder. Default: %USERPROFILE%\stacks\tt-core

.EXAMPLE
    .\Update-TunnelURLs.ps1
    .\Update-TunnelURLs.ps1 -Root "C:\stacks\tt-core"
#>
param(
  [string]$Root = (Join-Path $env:USERPROFILE 'stacks\tt-core')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\Env.ps1"
. "$PSScriptRoot\lib\RuntimeEnv.ps1"

$coreEnv    = Resolve-TTCoreEnvPath -RootPath $Root
$tunnelEnv  = Resolve-TTTunnelEnvPath -RootPath $Root
$selectPath = Join-Path $Root "config\services.select.json"

if (!(Test-Path $coreEnv))    { throw "Core .env not found: $coreEnv`nRun Init-TTCore.ps1 first." }
if (!(Test-Path $selectPath)) { throw "services.select.json not found: $selectPath`nThis file is the canonical route authority." }

# ── Read canonical intent from services.select.json ──────────────────────────
$select = Get-Content $selectPath -Raw -Encoding UTF8 | ConvertFrom-Json

$tunnelEnabled   = [bool]$select.tunnel.enabled
$routes          = $select.tunnel.routes
$subdomains      = $select.tunnel.subdomains
$domain          = [string]$select.client.domain
$allowRestricted = [bool]$select.security.allow_restricted_admin_tunnel_routes

# Domain fallback: read from tunnel .env if not set in services.select.json
if (-not $domain -or $domain -match '^__') {
  if (Test-Path $tunnelEnv) {
    $domainFromEnv = Get-EnvValue -EnvPath $tunnelEnv -Key "TT_DOMAIN" -Default ""
    if ($domainFromEnv) {
      $domain = $domainFromEnv
      Write-Host "  INFO: domain read from tunnel .env (set client.domain in services.select.json to make permanent)" -ForegroundColor Yellow
    }
  }
  if (-not $domain -or $domain -match '^__') {
    throw "client.domain is not set in services.select.json and TT_DOMAIN not found in tunnel .env.`nSet client.domain in config/services.select.json first."
  }
}

$localPort = Get-EnvValue -EnvPath $coreEnv -Key "TT_N8N_HOST_PORT"   -Default "15678"
$bindIP    = Get-EnvValue -EnvPath $coreEnv -Key "TT_BIND_IP"          -Default "127.0.0.1"
$wpPort    = Get-EnvValue -EnvPath $coreEnv -Key "TT_WP_HOST_PORT"     -Default "18081"

Write-Host ""
Write-Host "Update-TunnelURLs — v14.0" -ForegroundColor Cyan
Write-Host "  Source:  config/services.select.json (canonical route intent)" -ForegroundColor DarkGray
Write-Host "  Domain:  $domain" -ForegroundColor DarkGray
Write-Host "  Tunnel:  $(if ($tunnelEnabled) { 'ENABLED' } else { 'DISABLED' })" -ForegroundColor $(if ($tunnelEnabled) { 'Green' } else { 'DarkGray' })
Write-Host ""

# ── n8n URL ───────────────────────────────────────────────────────────────────
$n8nRouteEnabled = $tunnelEnabled -and ($routes.n8n -eq $true)
if ($n8nRouteEnabled) {
  $sub   = if ($subdomains.n8n) { [string]$subdomains.n8n } else { "n8n" }
  $n8nUrl = "https://$sub.$domain"
  Upsert-EnvLine -EnvPath $coreEnv -Key "TT_N8N_HOST"            -Value "$sub.$domain"
  Upsert-EnvLine -EnvPath $coreEnv -Key "TT_N8N_PROTOCOL"        -Value "https"
  Upsert-EnvLine -EnvPath $coreEnv -Key "TT_N8N_WEBHOOK_URL"     -Value "$n8nUrl/"
  Upsert-EnvLine -EnvPath $coreEnv -Key "TT_N8N_EDITOR_BASE_URL" -Value "$n8nUrl"
  Write-Host "  OK: n8n → TUNNEL mode: $n8nUrl" -ForegroundColor Green
} else {
  $localIp = if ($bindIP -eq "0.0.0.0") { "127.0.0.1" } else { $bindIP }
  $localUrl = "http://${localIp}:${localPort}"
  Upsert-EnvLine -EnvPath $coreEnv -Key "TT_N8N_HOST"            -Value "localhost"
  Upsert-EnvLine -EnvPath $coreEnv -Key "TT_N8N_PROTOCOL"        -Value "http"
  Upsert-EnvLine -EnvPath $coreEnv -Key "TT_N8N_WEBHOOK_URL"     -Value "$localUrl/"
  Upsert-EnvLine -EnvPath $coreEnv -Key "TT_N8N_EDITOR_BASE_URL" -Value "$localUrl"
  Write-Host "  OK: n8n → LOCAL mode: $localUrl" -ForegroundColor DarkGray
}

# ── WordPress URL ─────────────────────────────────────────────────────────────
$wpRouteEnabled = $tunnelEnabled -and ($routes.wordpress -eq $true)
if ($wpRouteEnabled) {
  $sub  = if ($subdomains.wordpress) { [string]$subdomains.wordpress } else { "wp" }
  $wpUrl = "https://$sub.$domain"
  Upsert-EnvLine -EnvPath $coreEnv -Key "TT_WP_PUBLIC_URL" -Value $wpUrl
  Write-Host "  OK: WordPress → TUNNEL mode: $wpUrl" -ForegroundColor Green
} else {
  $localIp = if ($bindIP -eq "0.0.0.0") { "127.0.0.1" } else { $bindIP }
  Upsert-EnvLine -EnvPath $coreEnv -Key "TT_WP_PUBLIC_URL" -Value "http://${localIp}:${wpPort}"
  Write-Host "  OK: WordPress → LOCAL mode: http://${localIp}:${wpPort}" -ForegroundColor DarkGray
}

# ── Security: warn if restricted admin routes are active ─────────────────────
$restrictedActive = @()
foreach ($route in @('pgadmin', 'portainer', 'openclaw')) {
  if ($tunnelEnabled -and $routes.$route -eq $true) {
    $restrictedActive += $route
  }
}
if ($restrictedActive.Count -gt 0) {
  if ($allowRestricted) {
    Write-Host ""
    Write-Host "  WARN: Restricted admin routes are enabled: $($restrictedActive -join ', ')" -ForegroundColor Yellow
    Write-Host "        security.allow_restricted_admin_tunnel_routes = true is acknowledged." -ForegroundColor Yellow
    Write-Host "        Ensure Cloudflare Access policies are in place." -ForegroundColor Yellow
  } else {
    Write-Host ""
    Write-Host "  BLOCKED: Restricted admin routes ($($restrictedActive -join ', ')) are enabled in tunnel.routes" -ForegroundColor Red
    Write-Host "           but security.allow_restricted_admin_tunnel_routes = false." -ForegroundColor Red
    Write-Host "           These routes will be silently skipped by the tunnel generator." -ForegroundColor Red
  }
}

Write-Host ""
Write-Host "  Restart affected services to apply: scripts\ttcore.ps1 restart core" -ForegroundColor Yellow
Write-Host "  Regenerate exposure report:         bash release/generate-exposure.sh" -ForegroundColor DarkGray
Write-Host ""
