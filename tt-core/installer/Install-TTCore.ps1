#Requires -Version 5.1
<#!
.SYNOPSIS
    TT-Core Installer (TT-Production v14.0)

.DESCRIPTION
    Catalog-driven installer for TT-Core. Copies package files, generates secrets,
    creates volume directories, applies installer defaults from config\services.select.json,
    and enforces safer exposure handling for restricted admin surfaces.
#>
param(
  [string] $RootPath     = (Join-Path $env:USERPROFILE 'stacks\tt-core'),
  [ValidateSet('local-private', 'small-business', 'ai-workstation', 'public-productivity')]
  [string] $ProfileName  = '',
  [string] $Timezone     = '',
  [string] $Domain       = '',
  [switch] $WithTunnel,
  [switch] $NoWordPress,
  [switch] $WithMetabase,
  [switch] $WithKanboard,
  [switch] $WithQdrant,
  [switch] $WithOllama,
  [switch] $WithOpenWebUI,
  [switch] $WithMonitoring,
  [switch] $WithPortainer,
  [switch] $WithOpenClaw,
  [switch] $NoStart
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Ensure-Dir([string]$Path) {
  if (!(Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Set-EnvVar([string]$Key, [string]$Value, [System.Collections.ArrayList]$Lines) {
  $pattern = "^\s*$([Regex]::Escape($Key))\s*="
  $found   = $false
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match $pattern) { $Lines[$i] = "$Key=$Value"; $found = $true; break }
  }
  if (-not $found) { [void]$Lines.Add("$Key=$Value") }
  return $Lines
}

function Prompt-YesNo([string]$Question, [bool]$Default = $true) {
  $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
  while ($true) {
    $a = (Read-Host "$Question $hint").Trim().ToLower()
    if ($a -eq '')          { return $Default }
    if ($a -in 'y', 'yes')  { return $true }
    if ($a -in 'n', 'no')   { return $false }
  }
}

function Prompt-Value([string]$Question, [string]$Default) {
  $a = (Read-Host "$Question [$Default]").Trim()
  if ($a -eq '') { return $Default }
  return $a
}

function Get-JsonFile([string]$Path) {
  if (!(Test-Path $Path)) { throw "JSON file not found: $Path" }
  return (Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-BoolOrDefault($Value, [bool]$Default = $false) {
  if ($null -eq $Value) { return $Default }
  try { return [bool]$Value } catch { return $Default }
}

function Apply-ProfilePreset {
  param(
    [Parameter(Mandatory = $true)]$Config,
    [Parameter(Mandatory = $true)][string]$ProfilesDir,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if ([string]::IsNullOrWhiteSpace($Name)) { return $Config }

  $profilePath = Join-Path $ProfilesDir "$Name.json"
  if (!(Test-Path $profilePath)) {
    throw "Profile preset not found: $profilePath"
  }

  $profile = Get-JsonFile $profilePath
  if ($null -eq $Config.profiles) {
    $Config | Add-Member -MemberType NoteProperty -Name profiles -Value ([pscustomobject]@{})
  }
  if ($null -eq $Config.tunnel) {
    $Config | Add-Member -MemberType NoteProperty -Name tunnel -Value ([pscustomobject]@{})
  }
  if ($null -eq $Config.tunnel.routes) {
    $Config.tunnel | Add-Member -MemberType NoteProperty -Name routes -Value ([pscustomobject]@{})
  }

  if ($null -ne $profile.profiles) {
    foreach ($prop in $profile.profiles.PSObject.Properties) {
      if ($Config.profiles.PSObject.Properties.Name -contains $prop.Name) {
        $Config.profiles.$($prop.Name) = [bool]$prop.Value
      }
    }
  }

  if ($null -ne $profile.tunnel) {
    if ($null -ne $profile.tunnel.enabled) {
      $Config.tunnel.enabled = [bool]$profile.tunnel.enabled
    }
    if ($null -ne $profile.tunnel.routes) {
      foreach ($prop in $profile.tunnel.routes.PSObject.Properties) {
        if ($Config.tunnel.routes.PSObject.Properties.Name -contains $prop.Name) {
          $Config.tunnel.routes.$($prop.Name) = [bool]$prop.Value
        }
      }
    }
  }

  return $Config
}

function Is-PlaceholderValue([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
  return ($Value -match '^__.+__$')
}

function Normalize-TextValue([string]$Value, [string]$Fallback = '') {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $Fallback }
  return $Value.Trim()
}

function Get-RouteName($Entry) {
  if ($Entry.route_name) { return [string]$Entry.route_name }
  if ([string]$Entry.service -eq 'uptime-kuma') { return 'monitoring' }
  return [string]$Entry.service
}

function Get-ProfileDefault($Config, [string]$Name, [bool]$Fallback = $false) {
  if ($null -ne $Config.profiles -and $Config.profiles.PSObject.Properties.Name -contains $Name) {
    return Get-BoolOrDefault $Config.profiles.$Name $Fallback
  }
  return $Fallback
}

function Resolve-EnableFlag([string]$ParamName, [bool]$ConfigDefault) {
  if ($PSBoundParameters.ContainsKey($ParamName)) { return $true }
  return $ConfigDefault
}

function Save-SelectionConfig {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)]$Config,
    [Parameter(Mandatory = $true)][hashtable]$ProfileSelections,
    [Parameter(Mandatory = $true)][hashtable]$RouteSelections,
    [Parameter(Mandatory = $true)][hashtable]$SubdomainSelections,
    [Parameter(Mandatory = $true)][bool]$TunnelEnabled,
    [Parameter(Mandatory = $true)][string]$TokenValue,
    [Parameter(Mandatory = $true)][string]$DomainValue,
    [Parameter(Mandatory = $true)][bool]$AllowRestrictedAdminRoutes
  )

  if ($null -eq $Config.security) {
    $Config | Add-Member -MemberType NoteProperty -Name security -Value ([pscustomobject]@{})
  }
  $Config.client.domain = $DomainValue
  $Config.tunnel.enabled = $TunnelEnabled
  # TokenValue no longer persisted — CF_TUNNEL_TOKEN is a runtime secret stored only in the runtime tunnel env
  $Config.security.allow_restricted_admin_tunnel_routes = $AllowRestrictedAdminRoutes

  foreach ($key in $ProfileSelections.Keys) {
    if ($Config.profiles.PSObject.Properties.Name -contains $key) {
      $Config.profiles.$key = [bool]$ProfileSelections[$key]
    }
  }
  foreach ($key in $RouteSelections.Keys) {
    if ($Config.tunnel.routes.PSObject.Properties.Name -contains $key) {
      $Config.tunnel.routes.$key = [bool]$RouteSelections[$key]
    }
  }
  foreach ($key in $SubdomainSelections.Keys) {
    if ($Config.tunnel.subdomains.PSObject.Properties.Name -contains $key) {
      $Config.tunnel.subdomains.$key = [string]$SubdomainSelections[$key]
    }
  }

  $json = $Config | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host ''
Write-Host '╔══════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║ TT-Core Installer  v14.0 ║' -ForegroundColor Cyan
Write-Host '╚══════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host "  Target: $RootPath"
if (-not [string]::IsNullOrWhiteSpace($ProfileName)) {
  Write-Host "  Profile: $ProfileName"
}
Write-Host ''

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw 'Docker not found. Install Docker Desktop first: https://www.docker.com/products/docker-desktop/'
}

$pkgRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $pkgRoot 'config\service-catalog.json'
$selectPath  = Join-Path $pkgRoot 'config\services.select.json'
$profilesPath = Join-Path $pkgRoot 'config\profiles'
$catalog = Get-JsonFile $catalogPath
$selectionConfig = Get-JsonFile $selectPath
$selectionConfig = Apply-ProfilePreset -Config $selectionConfig -ProfilesDir $profilesPath -Name $ProfileName
$profileMode = -not [string]::IsNullOrWhiteSpace($ProfileName)

$enableTunnel = if ($PSBoundParameters.ContainsKey('WithTunnel')) { $true } else { Get-BoolOrDefault $selectionConfig.tunnel.enabled $false }
$enableWordPress = if ($PSBoundParameters.ContainsKey('NoWordPress')) { $false } elseif ($profileMode) { Get-ProfileDefault $selectionConfig 'wordpress' $false } else { Prompt-YesNo 'Enable WordPress + MariaDB add-on?' (Get-ProfileDefault $selectionConfig 'wordpress' $false) }
$enableMetabase   = Resolve-EnableFlag 'WithMetabase'   (Get-ProfileDefault $selectionConfig 'metabase' $false)
$enableKanboard   = Resolve-EnableFlag 'WithKanboard'   (Get-ProfileDefault $selectionConfig 'kanboard' $false)
$enableQdrant     = Resolve-EnableFlag 'WithQdrant'     (Get-ProfileDefault $selectionConfig 'qdrant' $false)
$enableOllama     = Resolve-EnableFlag 'WithOllama'     (Get-ProfileDefault $selectionConfig 'ollama' $false)
$enableOpenWebUI  = Resolve-EnableFlag 'WithOpenWebUI'  (Get-ProfileDefault $selectionConfig 'openwebui' $false)
$enableMonitoring = Resolve-EnableFlag 'WithMonitoring' (Get-ProfileDefault $selectionConfig 'monitoring' $true)
$enablePortainer  = Resolve-EnableFlag 'WithPortainer'  (Get-ProfileDefault $selectionConfig 'portainer' $false)
$enableOpenClaw   = Resolve-EnableFlag 'WithOpenClaw'   (Get-ProfileDefault $selectionConfig 'openclaw' $false)
if ($enableOpenWebUI) { $enableOllama = $true }

$selectedProfiles = [ordered]@{
  metabase   = $enableMetabase
  monitoring = $enableMonitoring
  wordpress  = $enableWordPress
  kanboard   = $enableKanboard
  qdrant     = $enableQdrant
  ollama     = $enableOllama
  openwebui  = $enableOpenWebUI
  portainer  = $enablePortainer
  openclaw   = $enableOpenClaw
}

Ensure-Dir $RootPath
foreach ($folder in @('compose', 'docs', 'templates', 'scripts', 'scripts-linux', 'env', 'bin', 'cloudflared', 'release', 'config')) {
  $src = Join-Path $pkgRoot $folder
  if (Test-Path $src) {
    Copy-Item -Path $src -Destination $RootPath -Recurse -Force
  }
}
Write-Host "OK: Package copied → $RootPath" -ForegroundColor Green

& (Join-Path $RootPath 'scripts\Init-TTCore.ps1') -Root $RootPath
. (Join-Path $RootPath 'scripts\lib\RuntimeEnv.ps1')
$coreEnv = Resolve-TTCoreEnvPath -RootPath $RootPath
if (!(Test-Path $coreEnv)) {
  throw 'Runtime core env was not created by Init-TTCore.ps1. Check errors above.'
}
Write-Host "OK: Runtime core env ready -> $coreEnv" -ForegroundColor Green

# Validate timezone: must be explicitly set — no silent fallback allowed
$clientTimezone = if ([string]::IsNullOrWhiteSpace($Timezone)) { [string]$selectionConfig.client.timezone } else { [string]$Timezone }
if ([string]::IsNullOrWhiteSpace($clientTimezone) -or $clientTimezone -like '__*__') {
  throw "INSTALL BLOCKED: config\services.select.json .client.timezone is not set.`nSet a real timezone value (e.g. 'Asia/Riyadh', 'Europe/London', 'UTC') before running Install-TTCore.ps1."
}
$clientBindIp   = Normalize-TextValue ([string]$selectionConfig.client.bind_ip) '127.0.0.1'
$selectionConfig.client.timezone = $clientTimezone
$selectionConfig.client.bind_ip = $clientBindIp
$coreLines = [System.Collections.ArrayList](Get-Content $coreEnv -Encoding UTF8)
$coreLines = Set-EnvVar 'TT_TZ' $clientTimezone $coreLines
$coreLines = Set-EnvVar 'TT_BIND_IP' $clientBindIp $coreLines
[System.IO.File]::WriteAllLines($coreEnv, [string[]]$coreLines, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "OK: Applied client timezone/bind_ip → TT_TZ=$clientTimezone, TT_BIND_IP=$clientBindIp" -ForegroundColor Green

$allowRestrictedAdminRoutesByDefault = Get-BoolOrDefault $selectionConfig.security.allow_restricted_admin_tunnel_routes $false
$routeSelections = [ordered]@{}
$subSelections = [ordered]@{}
$anyRestrictedAdminRoute = $false
$baseDomain = if ($selectionConfig.client.domain -and $selectionConfig.client.domain -notlike '__*__') { [string]$selectionConfig.client.domain } else { '' }
if ($Domain) { $baseDomain = $Domain }

if ($enableTunnel) {
  $tunnelEnv    = Get-TTRuntimeTunnelEnvPath -RootPath $RootPath
  $tunnelEnvTpl = Join-Path $RootPath 'env\tunnel.env.example'
  if (!(Test-Path $tunnelEnvTpl)) { $tunnelEnvTpl = Join-Path $RootPath 'compose\tt-tunnel\.env.example' }
  if (!(Test-Path $tunnelEnvTpl)) { throw "Missing tunnel env template: $tunnelEnvTpl" }

  if ($profileMode) {
    if ([string]::IsNullOrWhiteSpace($baseDomain) -or $baseDomain -like '__*__') {
      throw 'Domain is required when tunnel is enabled in profile mode. Re-run with -Domain example.com.'
    }
  } else {
    $baseDomain = Prompt-Value 'Base domain for Cloudflare Tunnel (e.g. example.com)' $baseDomain
  }
  if ($baseDomain -eq '') { throw 'Domain is required when tunnel is enabled.' }

  $routeEntries = @($catalog.services | Where-Object { $_.public_capable -eq $true -and $_.tunnel })
  foreach ($entry in $routeEntries) {
    $svc = [string]$entry.service
    $displayName = if ($entry.display_name) { [string]$entry.display_name } else { $svc }
    $routeName = Get-RouteName $entry
    $serviceProfileName = if ($entry.profile) { [string]$entry.profile } else { $null }
    $isInstalled = $true
    if ($serviceProfileName) {
      $isInstalled = ($selectedProfiles.Contains($serviceProfileName) -and [bool]$selectedProfiles[$serviceProfileName])
    }

    $subDefault = if ($selectionConfig.tunnel.subdomains.PSObject.Properties.Name -contains $routeName) { [string]$selectionConfig.tunnel.subdomains.$routeName } else { $routeName }
    if (-not $isInstalled) {
      $routeSelections[$routeName] = $false
      $subSelections[$routeName] = $subDefault
      continue
    }

    $routeDefault = if ($selectionConfig.tunnel.routes.PSObject.Properties.Name -contains $routeName) { Get-BoolOrDefault $selectionConfig.tunnel.routes.$routeName $false } else { $false }
    if ([string]$entry.tier -eq 'restricted_admin' -and -not $allowRestrictedAdminRoutesByDefault -and $routeDefault) {
      Write-Host "WARN: $displayName is a restricted admin surface; default route forced to disabled until you explicitly acknowledge the risk." -ForegroundColor Yellow
      $routeDefault = $false
    }

    if ($profileMode) {
      $enabled = $routeDefault
      if ($enabled -and [string]$entry.tier -eq 'restricted_admin') {
        $anyRestrictedAdminRoute = $true
      }
      $routeSelections[$routeName] = $enabled
      $subSelections[$routeName] = $subDefault
      continue
    }

    $enabled = Prompt-YesNo "Expose $displayName via tunnel?" $routeDefault
    if ($enabled -and [string]$entry.tier -eq 'restricted_admin') {
      Write-Host ''
      Write-Host "SECURITY WARNING: $displayName is classified as a restricted admin surface." -ForegroundColor Yellow
      Write-Host '  Only expose it behind strong Cloudflare Access policies and only when you truly need it.' -ForegroundColor Yellow
      $ack = Prompt-YesNo "I acknowledge the risk and still want to expose $displayName via tunnel." $false
      if (-not $ack) { $enabled = $false }
      if ($ack) { $anyRestrictedAdminRoute = $true }
    }

    $routeSelections[$routeName] = $enabled
    $subSelections[$routeName] = if ($enabled) { Prompt-Value "$displayName subdomain" $subDefault } else { $subDefault }
  }

  $tunnelRuntimeDir = Split-Path -Parent $tunnelEnv
  Ensure-Dir $tunnelRuntimeDir
  Copy-Item -Force $tunnelEnvTpl $tunnelEnv
  $lines = [System.Collections.ArrayList](Get-Content $tunnelEnv -Encoding UTF8)
  $lines = Set-EnvVar 'TT_TZ' $clientTimezone $lines
  # CF_TUNNEL_TOKEN must be set directly in the runtime tunnel env by the operator.
  # It is NOT read from services.select.json — tokens are runtime secrets, not config values.
  # The installer sets CF_TUNNEL_TOKEN to empty; operator fills it before starting the tunnel.
  $lines = Set-EnvVar 'CF_TUNNEL_TOKEN' '' $lines
  [System.IO.File]::WriteAllLines($tunnelEnv, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "OK: Tunnel env written → $tunnelEnv" -ForegroundColor Green

  if ($routeSelections.Contains('n8n') -and $routeSelections['n8n']) {
    $n8nUrl      = "https://$($subSelections['n8n']).$baseDomain"
    $coreContent = Get-Content $coreEnv -Raw
    $coreContent = $coreContent -replace '(?m)^TT_N8N_HOST=.*$',            "TT_N8N_HOST=$($subSelections['n8n']).$baseDomain"
    $coreContent = $coreContent -replace '(?m)^TT_N8N_PROTOCOL=.*$',        'TT_N8N_PROTOCOL=https'
    $coreContent = $coreContent -replace '(?m)^TT_N8N_WEBHOOK_URL=.*$',     "TT_N8N_WEBHOOK_URL=$n8nUrl/"
    $coreContent = $coreContent -replace '(?m)^TT_N8N_EDITOR_BASE_URL=.*$', "TT_N8N_EDITOR_BASE_URL=$n8nUrl"
    [IO.File]::WriteAllText($coreEnv, $coreContent, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "OK: n8n URLs set for tunnel → $n8nUrl" -ForegroundColor Green
  }

  Write-Host ''
  Write-Host "ACTION REQUIRED: Edit runtime tunnel env and set CF_TUNNEL_TOKEN=<your-token> before starting tunnel." -ForegroundColor Yellow
  Write-Host "          Review desired dashboard routes with: scripts\Show-TunnelPlan.ps1" -ForegroundColor Yellow
} else {
  foreach ($entry in @($catalog.services | Where-Object { $_.public_capable -eq $true -and $_.tunnel })) {
    $routeName = Get-RouteName $entry
    $routeSelections[$routeName] = $false
    $subSelections[$routeName] = if ($selectionConfig.tunnel.subdomains.PSObject.Properties.Name -contains $routeName) { [string]$selectionConfig.tunnel.subdomains.$routeName } else { $routeName }
  }
}

$existingNets = docker network ls --format '{{.Name}}'
if ($existingNets -notcontains 'tt_shared_net') {
  docker network create tt_shared_net | Out-Null
  Write-Host 'OK: Network created: tt_shared_net' -ForegroundColor Green
}
if ($existingNets -notcontains 'tt_core_internal') {
  docker network create --internal tt_core_internal | Out-Null
  Write-Host 'OK: Network created: tt_core_internal (internal)' -ForegroundColor Green
}

$installedSelectPath = Join-Path $RootPath 'config\services.select.json'
Save-SelectionConfig -Path $installedSelectPath -Config $selectionConfig -ProfileSelections $selectedProfiles -RouteSelections $routeSelections -SubdomainSelections $subSelections -TunnelEnabled $enableTunnel -TokenValue '' -DomainValue $baseDomain -AllowRestrictedAdminRoutes $anyRestrictedAdminRoute
Write-Host "OK: Installer selection snapshot written → $installedSelectPath" -ForegroundColor Green

if ($NoStart) {
  Write-Host ''
  Write-Host 'OK: Setup complete (NoStart — services not started).' -ForegroundColor Green
  Write-Host '  Run: scripts\Start-Core.ps1  to start.' -ForegroundColor Cyan
  exit 0
}

$profiles = [System.Collections.ArrayList]@()
foreach ($pair in $selectedProfiles.GetEnumerator()) {
  if ($pair.Value) { [void]$profiles.Add([string]$pair.Key) }
}

$composeFile = Join-Path $RootPath 'compose\tt-core\docker-compose.yml'
$addonFiles  = Get-ChildItem (Join-Path $RootPath 'compose\tt-core\addons') -Filter '*.yml' |
               Where-Object { $_.Name -notlike '00-template*' } | Sort-Object Name

$composeArgs = @('-f', $composeFile)
foreach ($a in $addonFiles) { $composeArgs += '-f', $a.FullName }
foreach ($p in $profiles)   { $composeArgs += '--profile', $p }
$composeArgs += 'up', '-d'

Write-Host ''
Write-Host 'Starting TT-Core services...' -ForegroundColor Cyan
if ($profiles.Count -gt 0) { Write-Host "  Optional profiles: $($profiles -join ', ')" -ForegroundColor DarkGray }
docker compose @composeArgs

if ($enableTunnel) {
  Write-Host ''
  Write-Host 'Starting TT-Tunnel...' -ForegroundColor Cyan
  $tunnelCompose = Join-Path $RootPath 'compose\tt-tunnel\docker-compose.yml'
  docker compose -f $tunnelCompose --env-file (Resolve-TTTunnelEnvPath -RootPath $RootPath) up -d
}

Write-Host ''
Write-Host '╔══════════════════════════════════════╗' -ForegroundColor Green
Write-Host '║    Installation Complete ✓           ║' -ForegroundColor Green
Write-Host '╚══════════════════════════════════════╝' -ForegroundColor Green
Write-Host "  Runtime env : $coreEnv"
Write-Host "  Volumes     : $(Join-Path $RootPath 'compose\tt-core\volumes\')"
Write-Host "  Scripts     : $(Join-Path $RootPath 'scripts\')"
Write-Host ''
Write-Host 'Quick commands:'
Write-Host '  Status       : scripts\Status-Core.ps1' -ForegroundColor Cyan
Write-Host '  Logs         : scripts\Logs-Core.ps1'   -ForegroundColor Cyan
Write-Host '  Smoke test   : scripts\Smoke-Test.ps1'  -ForegroundColor Cyan
if ($enableTunnel) {
  Write-Host '  Tunnel token : stored in runtime tunnel env (review before first start)' -ForegroundColor Yellow
  Write-Host '  Preflight    : run scripts\Preflight-Check.ps1 before first production start' -ForegroundColor Yellow
  Write-Host '  Route plan   : scripts\Show-TunnelPlan.ps1'                         -ForegroundColor Cyan
  Write-Host '  Start tunnel : scripts\Start-Tunnel.ps1'                           -ForegroundColor Cyan
}
if ($profiles -contains 'metabase') {
  Write-Host '  Metabase     : http://127.0.0.1:13010' -ForegroundColor DarkGray
}
if ($profiles -contains 'wordpress') {
  Write-Host '  WordPress    : http://127.0.0.1:18081' -ForegroundColor DarkGray
}
if ($profiles -contains 'monitoring') {
  Write-Host '  Monitoring   : http://127.0.0.1:13001  (create admin on first access)' -ForegroundColor DarkGray
}
if ($profiles -contains 'portainer') {
  Write-Host '  Portainer    : http://127.0.0.1:19000  (create admin within 5 min)'    -ForegroundColor DarkGray
}
if ($profiles -contains 'openclaw') {
  Write-Host ''
  Write-Host '  OpenClaw AI Agent installed in SETUP MODE.' -ForegroundColor Yellow
  Write-Host '  Complete agent setup by running:' -ForegroundColor Yellow
  Write-Host '    scripts\Init-OpenClaw.ps1' -ForegroundColor Cyan
  Write-Host '  Docs: docs\OPENCLAW.md' -ForegroundColor DarkGray
}

