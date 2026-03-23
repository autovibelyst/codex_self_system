param(
  [Parameter(Mandatory = $true)]
  [ValidateSet(
    "postgres", "redis", "n8n", "pgadmin", "redisinsight", "metabase",
    "kanboard", "wordpress", "mariadb", "qdrant", "ollama", "openwebui",
    "uptime-kuma", "portainer", "openclaw"
  )]
  [string]  $Service,

  [string]  $Root = (Join-Path $env:USERPROFILE 'stacks\tt-core'),

  # Automatically start Tunnel if configured (for public-facing services)
  [switch]  $WithTunnel
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_compose_args.ps1"
. "$PSScriptRoot\_profiles.ps1"
. "$PSScriptRoot\lib\ServiceCatalog.ps1"
. "$PSScriptRoot\lib\RuntimeEnv.ps1"

function Test-IsTunnelCapableService {
  param([string]$Root, [string]$Service)
  $entry = Get-TTServiceEntry -Root $Root -Service $Service
  if ($null -eq $entry) { return $false }
  if (-not ($entry.public_capable -eq $true -and $entry.auto_start_tunnel -eq $true)) { return $false }
  return (Test-TTRouteEnabledForService -Root $Root -Service $Service)
}

function Start-TunnelIfWanted {
  param([string]$Root, [switch]$WithTunnel)
  if (-not $WithTunnel) { return }
  $selection = Get-TTServiceSelection -Root $Root
  if ($selection.tunnel.enabled -ne $true) {
    Write-Host "  Tunnel: tunnel.enabled is false in config/services.select.json — skipping tunnel start." -ForegroundColor Yellow
    return
  }
  $tunnelDir = Join-Path $Root "compose\tt-tunnel"
  $tunnelEnv = Resolve-TTTunnelEnvPath -RootPath $Root
  if (!(Test-Path $tunnelEnv)) {
    Write-Host "  Tunnel: .env not found — skipping tunnel start." -ForegroundColor Yellow
    return
  }
  $tokenLine = Get-Content $tunnelEnv | Where-Object { $_ -match "^CF_TUNNEL_TOKEN=" -and $_ -notmatch "__PASTE_TOKEN_HERE__" }
  if (-not $tokenLine) {
    Write-Host "  Tunnel: CF_TUNNEL_TOKEN not set — skipping tunnel start." -ForegroundColor Yellow
    return
  }
  Push-Location $tunnelDir
  try { docker compose --env-file $tunnelEnv up -d } finally { Pop-Location }
  Write-Host "  Tunnel started." -ForegroundColor Green
}

$coreDir = Join-Path $Root "compose\tt-core"
$profiles = Get-TTProfilesForService -Root $Root -Service $Service

$composeArgs  = Get-TTComposeArgs -ComposeDir $coreDir
$coreEnvFile = Resolve-TTCoreEnvPath -RootPath $Root
$composeArgs += "--env-file", $coreEnvFile
foreach ($p in $profiles) { $composeArgs += "--profile", $p }
$composeArgs += "up", "-d", $Service

Push-Location $coreDir
try {
  docker compose @composeArgs
} finally {
  Pop-Location
}

if ($WithTunnel) {
  if (Test-IsTunnelCapableService -Root $Root -Service $Service) {
    Start-TunnelIfWanted -Root $Root -WithTunnel:$WithTunnel
  } else {
    Write-Host "  Tunnel: route not enabled for '$Service' in config/services.select.json — skipping tunnel start." -ForegroundColor Yellow
  }
}

Write-Host ""
Write-Host "OK: Service '$Service' started." -ForegroundColor Green
if ($profiles.Count -gt 0) {
  Write-Host "  Profiles activated: $($profiles -join ', ')" -ForegroundColor DarkGray
}
