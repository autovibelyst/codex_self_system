#Requires -Version 5.1
# =============================================================================
# TT-Core Preflight-Check  (TT-Production v14.0)
#
# Runs before first production start to catch misconfigurations early.
# Usage:
#   scripts\Preflight-Check.ps1
#   scripts\Preflight-Check.ps1 -IncludeSupabase
#   scripts\Preflight-Check.ps1 -Root C:\custom\path\tt-core
#
# Exit codes:
#   0 — All checks passed (warnings are informational only)
#   1 — One or more ERROR findings detected
#
# Check phases (in order):
#   Phase 0 — Host Readiness  (Docker, Compose V2, disk space, write access)
#   Phase 1 — Required Files  (JSON config files must exist)
#   Phase 2 — Config Checks   (security, routing, profiles, env, ports)
#   Phase 3 — Optional        (Supabase — only when -IncludeSupabase)
# =============================================================================
param(
  [string]$Root         = (Split-Path -Parent $PSScriptRoot),
  [switch]$IncludeSupabase,
  [string]$SupabaseRoot = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tt-supabase')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/ServiceCatalog.ps1')
. (Join-Path $PSScriptRoot 'lib/RuntimeEnv.ps1')

# =============================================================================
# Helpers
# =============================================================================

function Read-JsonFile([string]$Path) {
  if (!(Test-Path $Path)) { throw "Missing JSON file: $Path" }
  return (Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Read-DotEnv([string]$Path) {
  # Proper .env parser: handles comments, blank lines, KEY=VALUE
  $map = @{}
  if (!(Test-Path $Path)) { return $map }
  foreach ($raw in (Get-Content $Path -Encoding UTF8)) {
    $line = [string]$raw
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line.TrimStart().StartsWith('#'))   { continue }
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { continue }
    $map[$line.Substring(0, $idx).Trim()] = $line.Substring($idx + 1).Trim()
  }
  return $map
}

function Get-EnvValue([hashtable]$Map, [string]$Key) {
  if ($Map.ContainsKey($Key)) { return [string]$Map[$Key] }
  return ''
}

function Get-EnvText([string]$Path) {
  if (!(Test-Path $Path)) { return '' }
  return (Get-Content $Path -Raw -Encoding UTF8)
}

function Add-Issue([string]$Severity, [string]$Message) {
  $script:Findings.Add(
    [pscustomobject]@{ Severity = $Severity; Message = $Message }
  ) | Out-Null
}

$script:Findings = New-Object System.Collections.Generic.List[object]

# =============================================================================
# Phase 0 — Host Readiness
# Must pass before any config-level check can proceed.
# =============================================================================

Write-Host '[ Phase 0 ] Host Readiness' -ForegroundColor DarkGray

# 0a. Docker daemon
try {
  $null = & docker info 2>&1
  if ($LASTEXITCODE -ne 0) {
    Add-Issue 'ERROR' 'Docker daemon is not running or not accessible. Start Docker Desktop / Docker Engine before running Preflight.'
  }
} catch {
  Add-Issue 'ERROR' "'docker' command not found. Install Docker Desktop (Windows/Mac) or Docker Engine + Compose plugin (Linux)."
}

# 0b. Compose V2 (docker compose, NOT legacy docker-compose)
try {
  $null = & docker compose version 2>&1
  if ($LASTEXITCODE -ne 0) {
    Add-Issue 'ERROR' 'Docker Compose V2 is not available. Ensure Docker Desktop >= 3.6.0 or install the Compose plugin.'
  }
} catch {
  Add-Issue 'ERROR' "'docker compose' command failed. Compose V2 plugin may be missing."
}

# 0c. Disk space  (<5 GB = ERROR, <10 GB = WARNING)
try {
  $qualifier = Split-Path -Qualifier (Resolve-Path $Root -ErrorAction SilentlyContinue)
  if ($qualifier) {
    $drive = Get-PSDrive ($qualifier -replace ':', '') -ErrorAction SilentlyContinue
    if ($drive -and $drive.Free) {
      $freeGB = [math]::Round($drive.Free / 1GB, 1)
      if ($freeGB -lt 5) {
        Add-Issue 'ERROR' "Insufficient disk space: ${freeGB} GB free on ${qualifier}. Minimum 5 GB required."
      } elseif ($freeGB -lt 10) {
        Add-Issue 'WARNING' "Low disk space: ${freeGB} GB free on ${qualifier}. 10 GB+ recommended for stable operation."
      }
    }
  }
} catch {
  Add-Issue 'WARNING' "Could not determine available disk space. Verify manually."
}

# 0d. Write permissions on TT-Core root
try {
  $probe = Join-Path $Root '.preflight-write-test'
  [System.IO.File]::WriteAllText(
    $probe, 'ok',
    [System.Text.UTF8Encoding]::new($false))
  Remove-Item $probe -Force -ErrorAction SilentlyContinue
} catch {
  Add-Issue 'ERROR' "No write permission in TT-Core root: $Root — check folder ownership / ACLs."
}

# Emit Phase 0 results immediately (cannot continue without Docker)
$phase0Errors = @($script:Findings | Where-Object { $_.Severity -eq 'ERROR' })
if ($phase0Errors.Count -gt 0) {
  foreach ($f in $script:Findings) {
    $clr = if ($f.Severity -eq 'ERROR') { 'Red' } else { 'Yellow' }
    Write-Host "[$($f.Severity)] $($f.Message)" -ForegroundColor $clr
  }
  Write-Host ''
  Write-Host "Preflight FAILED at Phase 0 (Host Readiness). Fix the above before continuing." `
    -ForegroundColor Red
  exit 1
}

# =============================================================================
# Phase 1 — Required Files
# =============================================================================

Write-Host '[ Phase 1 ] Required Files' -ForegroundColor DarkGray

$coreEnvPath     = Resolve-TTCoreEnvPath -RootPath $Root
$tunnelEnvPath   = Resolve-TTTunnelEnvPath -RootPath $Root
$selectPath      = Join-Path $Root 'config/services.select.json'
$catalogPath     = Join-Path $Root 'config/service-catalog.json'
$policyPath      = Join-Path $Root 'config/public-exposure.policy.json'
$imageLockPath   = Join-Path (Split-Path -Parent $Root) 'release/image-inventory.lock.json'
$openClawTplPath = Join-Path $Root 'compose/tt-core/volumes/openclaw/config/openclaw_template.json'
$sopsYamlPath    = Join-Path $Root 'secrets/.sops.yaml'
$coreTplPath     = Join-Path $Root 'compose/tt-core/.env.example'
$forbiddenDevAgeKey = 'age1qprwg5fxspev023zhv2thdrl7k6gx5rkv9rfenc2k0w0txj5c9vs5hk7yc'
# SupabaseRoot: use -SupabaseRoot param if provided, otherwise default to sibling tt-supabase/
$supabaseRoot    = if (($PSBoundParameters.ContainsKey('SupabaseRoot')) -and (Test-Path $SupabaseRoot)) {
  $SupabaseRoot
} else {
  Join-Path (Split-Path -Parent $Root) 'tt-supabase'
}
$supabaseEnvPath = Join-Path $supabaseRoot 'compose/tt-supabase/.env'

foreach ($req in @($selectPath, $catalogPath, $policyPath)) {
  if (!(Test-Path $req)) { Add-Issue 'ERROR' "Missing required file: $req" }
}

$phase1Errors = @($script:Findings | Where-Object { $_.Severity -eq 'ERROR' })
if ($phase1Errors.Count -gt 0) {
  foreach ($f in $script:Findings) {
    Write-Host "[$($f.Severity)] $($f.Message)" -ForegroundColor Red
  }
  exit 1
}

$select      = Read-JsonFile $selectPath
$catalog     = Get-TTServiceCatalog -Root $Root
$coreEnv     = Read-DotEnv $coreEnvPath
$tunnelEnv   = Read-DotEnv $tunnelEnvPath
$coreEnvText = Get-EnvText $coreEnvPath

# =============================================================================
# Phase 2 — Configuration Checks
# =============================================================================


  # Security gate status
  . "$PSScriptRoot\lib\ServiceCatalog.ps1" 2>$null
  $gateOpen = Test-TTAdminRouteGateOpen -Root $Root
  if ($gateOpen) {
    Add-Issue 'WARNING' 'security.allow_restricted_admin_tunnel_routes = true — restricted admin routes are OPEN. Verify this is intentional.'
  } else {
    Write-Host "  [OK]   Security gate: restricted_admin routes CLOSED (correct default)" -ForegroundColor Green
  }

Write-Host '[ Phase 2 ] Configuration' -ForegroundColor DarkGray

# ── 2.1 Baseline profile safety ───────────────────────────────────────────────
if ($select.profiles.monitoring -eq $true) {
  Add-Issue 'ERROR' 'services.select.json must keep monitoring opt-in by default (profiles.monitoring=false).'
}
if ($select.profiles.wordpress -eq $true) {
  Add-Issue 'WARNING' 'WordPress is enabled. Confirm this is intentional for this deployment.'
}

# ── 2.2 Security section — presence and gate value ────────────────────────────
if (-not ($select.PSObject.Properties.Name -contains 'security') -or
    -not ($select.security.PSObject.Properties.Name -contains
          'allow_restricted_admin_tunnel_routes')) {
  Add-Issue 'ERROR' 'services.select.json is missing security.allow_restricted_admin_tunnel_routes.'
}
$allowRestrictedAdmin = [bool]$select.security.allow_restricted_admin_tunnel_routes

# ── 2.3 bind_ip safety ────────────────────────────────────────────────────────
$bindIp = if ($select.client.bind_ip) { [string]$select.client.bind_ip } else { '' }
if ($bindIp -eq '0.0.0.0') {
  Add-Issue 'WARNING' 'client.bind_ip is 0.0.0.0 — services bind on ALL interfaces. Use 127.0.0.1 unless LAN exposure is intentional.'
}

# ── 2.4 Client placeholder detection ─────────────────────────────────────────
$clientName   = if ($select.client.name)   { [string]$select.client.name }   else { '' }
$clientDomain = if ($select.client.domain) { [string]$select.client.domain } else { '' }
if ([string]::IsNullOrWhiteSpace($clientName)   -or $clientName   -match '^__') {
  Add-Issue 'WARNING' 'services.select.json client.name is still placeholder or empty.'
}
if ([string]::IsNullOrWhiteSpace($clientDomain) -or $clientDomain -match '^__') {
  Add-Issue 'WARNING' 'services.select.json client.domain is still placeholder or empty. Show-TunnelPlan.ps1 will not work.'
}

$openClawEnabled = [bool]$select.profiles.openclaw

# ── 2.5 Env placeholder scan ─────────────────────────────────────────────────
$criticalPlaceholders = @(
  '__CLIENT_NAME__', '__CLIENT_DOMAIN__',
  '__PIN_GIT_TAG_OR_COMMIT__', '__PIN_TAG_OR_COMMIT_BEFORE_PRODUCTION__'
)
foreach ($pat in $criticalPlaceholders) {
    foreach ($key in $coreEnv.Keys) {
    if ($key -eq 'TT_OPENCLAW_SOURCE_REF' -and -not $openClawEnabled) { continue }
    if ([string]$coreEnv[$key] -match [regex]::Escape($pat)) {
      Add-Issue 'WARNING' "Runtime core env contains placeholder value for '$key' ($pat)."
    }
  }
}

# ── 2.6 Tunnel readiness ──────────────────────────────────────────────────────
if ([bool]$select.tunnel.enabled -eq $true) {
  if (!(Test-Path $tunnelEnvPath)) {
    Add-Issue 'ERROR' 'Tunnel is enabled but runtime tunnel env is missing.'
  } else {
    $token = Get-EnvValue $tunnelEnv 'CF_TUNNEL_TOKEN'
    if ([string]::IsNullOrWhiteSpace($token) -or $token -match '^__') {
      Add-Issue 'ERROR' 'Tunnel is enabled but CF_TUNNEL_TOKEN is not configured in runtime tunnel env.'
    }
  }
}

# ── 2.7 OpenClaw readiness ───────────────────────────────────────────────────
if ($select.profiles.openclaw -eq $true) {
  $srcRef = Get-EnvValue $coreEnv 'TT_OPENCLAW_SOURCE_REF'
  if ([string]::IsNullOrWhiteSpace($srcRef) -or
      $srcRef -match '^__.*__$'             -or
      $srcRef -eq 'openclaw/main-unpinned') {
    Add-Issue 'ERROR' 'OpenClaw is enabled but TT_OPENCLAW_SOURCE_REF is not pinned to a real tag or commit.'
  }

  if (!(Test-Path $openClawTplPath)) {
    Add-Issue 'ERROR' 'OpenClaw is enabled but openclaw_template.json is missing. Run scripts\Init-OpenClaw.ps1.'
  } else {
    try {
      $tpl = Get-Content $openClawTplPath -Raw -Encoding UTF8 | ConvertFrom-Json

      if ($tpl.gateway.controlUi.allowInsecureAuth -eq $true) {
        Add-Issue 'ERROR' 'OpenClaw template still has allowInsecureAuth=true. This must not be used for production.'
      }

      # Token cross-check: template token must match .env token
      $tplToken = [string]$tpl.gateway.auth.token
      $envToken = Get-EnvValue $coreEnv 'TT_OPENCLAW_TOKEN'
      if ($tplToken -match '^__MUST_MATCH') {
        Add-Issue 'WARNING' 'openclaw_template.json gateway.auth.token is still placeholder. Update it to match TT_OPENCLAW_TOKEN in .env.'
      } elseif (-not [string]::IsNullOrWhiteSpace($tplToken) -and
                -not ($tplToken -match '^__')                -and
                -not [string]::IsNullOrWhiteSpace($envToken) -and
                -not ($envToken -match '^__')                -and
                $tplToken -ne $envToken) {
        Add-Issue 'ERROR' 'openclaw_template.json gateway.auth.token does not match TT_OPENCLAW_TOKEN in .env. Dashboard login will fail.'
      }
    } catch {
      Add-Issue 'WARNING' 'OpenClaw template JSON could not be parsed — verify allowInsecureAuth and token manually.'
    }
  }
}

# ── 2.8 Catalog / policy consistency ─────────────────────────────────────────
$policy = $null
try { $policy = Read-JsonFile $policyPath } catch {
  Add-Issue 'ERROR' 'config/public-exposure.policy.json is not valid JSON.'
}
if ($policy) {
  if ([string]$policy.generated_from -ne 'config/service-catalog.json') {
    Add-Issue 'ERROR' 'config/public-exposure.policy.json must declare generated_from=config/service-catalog.json. Run Sync-PublicExposurePolicy.ps1.'
  }
  $catalogByService = @{}
  foreach ($svc in $catalog.services) {
    $catalogByService[[string]$svc.service] = $svc
  }
  foreach ($svc in $policy.services) {
    $name = [string]$svc.service
    if (-not $catalogByService.ContainsKey($name)) {
      Add-Issue 'ERROR' "public-exposure.policy.json references service '$name' that does not exist in service-catalog.json."
    }
  }
}

# ── 2.9 Route / profile alignment ────────────────────────────────────────────
foreach ($routeProp in $select.tunnel.routes.PSObject.Properties) {
  if ([string]$routeProp.Name -eq '_comment') { continue }
  $routeName = [string]$routeProp.Name
  $enabled   = [bool]$routeProp.Value
  if (-not $enabled) { continue }

  $svc = @($catalog.services |
    Where-Object {
      $rnProp = $_.PSObject.Properties['route_name']
      (($null -ne $rnProp -and [string]$rnProp.Value -eq $routeName) -or ([string]$_.service -eq $routeName))
    }) | Select-Object -First 1

  if (-not $svc) {
    Add-Issue 'ERROR' "services.select.json enables tunnel route '$routeName' but no catalog service matches."
    continue
  }
  if ([string]$svc.tier -eq 'restricted_admin' -and -not $allowRestrictedAdmin) {
    Add-Issue 'ERROR' "Restricted admin route '$routeName' is enabled but security.allow_restricted_admin_tunnel_routes is false."
  }
  if ($svc.profile) {
    $profProp = $select.profiles.PSObject.Properties[[string]$svc.profile]
    if ($null -eq $profProp -or [bool]$profProp.Value -ne $true) {
      Add-Issue 'ERROR' "Tunnel route '$routeName' is enabled while required profile '$($svc.profile)' is disabled."
    }
  }
}

# ── 2.10 Addon structure integrity ───────────────────────────────────────────
$addonDir = Join-Path $Root 'compose/tt-core/addons'
if (Test-Path $addonDir) {
  foreach ($file in Get-ChildItem $addonDir -Filter '*.yml' -File) {
    if ($file.Name -eq '00-template.addon.yml') { continue }
    $text = Get-Content $file.FullName -Raw
    if ($text -notmatch '(?m)^\s+restart:\s+unless-stopped\s*$') {
      Add-Issue 'ERROR' "Addon '$($file.Name)' is missing 'restart: unless-stopped'."
    }
    if ($text -notmatch '(?m)^\s+logging:\s*$') {
      Add-Issue 'ERROR' "Addon '$($file.Name)' is missing a logging section."
    }
  }
}

# ── 2.11 Secret-template and SOPS policy checks ──────────────────────────────
if (Test-Path $sopsYamlPath) {
  $sopsText = Get-Content $sopsYamlPath -Raw -Encoding UTF8
  if ($sopsText -match [regex]::Escape($forbiddenDevAgeKey)) {
    Add-Issue 'ERROR' "secrets/.sops.yaml contains a forbidden developer age key. Reset to <OPERATOR_AGE_PUBLIC_KEY> and rerun installer/lib/sops-setup.sh."
  }
} else {
  Add-Issue 'WARNING' 'secrets/.sops.yaml is missing. SOPS mode cannot be validated.'
}

if (Test-Path $coreTplPath) {
  $coreTpl = Get-Content $coreTplPath -Raw -Encoding UTF8
  if ($coreTpl -match '(?m)^\s*TT_MINIO_PASSWORD\s*=\s*$') {
    Add-Issue 'ERROR' 'compose/tt-core/.env.example has empty TT_MINIO_PASSWORD. Use __GENERATE__ placeholder.'
  }
  if ($coreTpl -match '(?m)^\s*TT_GRAFANA_PASSWORD\s*=\s*$') {
    Add-Issue 'ERROR' 'compose/tt-core/.env.example has empty TT_GRAFANA_PASSWORD. Use __GENERATE__ placeholder.'
  }
}

# ── 2.12 Image tag immutability check ─────────────────────────────────────────
$latestScanFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]
$coreComposePath = Join-Path $Root 'compose/tt-core/docker-compose.yml'
if (Test-Path $coreComposePath) {
  $latestScanFiles.Add((Get-Item $coreComposePath)) | Out-Null
}
if (Test-Path $addonDir) {
  foreach ($addonFile in Get-ChildItem $addonDir -Filter '*.addon.yml' -File) {
    if ($addonFile.Name -eq '00-template.addon.yml') { continue }
    $latestScanFiles.Add($addonFile) | Out-Null
  }
}
foreach ($scanFile in $latestScanFiles) {
  $lines = Get-Content -Path $scanFile.FullName -Encoding UTF8
  for ($idx = 0; $idx -lt $lines.Count; $idx++) {
    $line = [string]$lines[$idx]
    if ($line -match '^\s*image:\s*[^#\s]+:latest(\s|$)') {
      Add-Issue 'ERROR' "$($scanFile.Name): mutable :latest image tag at line $($idx + 1). Pin to immutable version tag or digest."
    }
  }
}

# ── 2.12b Strict image lock completeness ─────────────────────────────────────
if (!(Test-Path $imageLockPath)) {
  Add-Issue 'ERROR' 'release/image-inventory.lock.json is missing. The bundle must ship with a complete image lock.'
} else {
  try {
    $imageLock = Get-Content $imageLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$imageLock.lock_status -ne 'complete') {
      Add-Issue 'ERROR' "release/image-inventory.lock.json lock_status='$($imageLock.lock_status)' — expected 'complete'."
    }
    if ([int]$imageLock.unresolved_count -ne 0) {
      Add-Issue 'ERROR' "release/image-inventory.lock.json unresolved_count=$($imageLock.unresolved_count) — expected 0."
    }
    $latestRefs = @($imageLock.images | Where-Object { [string]$_.source_tag -eq 'latest' })
    if ($latestRefs.Count -gt 0) {
      Add-Issue 'ERROR' "release/image-inventory.lock.json still contains :latest source tags ($($latestRefs.Count) image(s))."
    }
    $unresolvedRefs = @($imageLock.images | Where-Object {
      [string]$_.digest_status -ne 'resolved' -or
      [string]::IsNullOrWhiteSpace([string]$_.resolved_digest)
    })
    if ($unresolvedRefs.Count -gt 0) {
      Add-Issue 'ERROR' "release/image-inventory.lock.json contains $($unresolvedRefs.Count) image(s) without resolved digests."
    }
  } catch {
    Add-Issue 'ERROR' "release/image-inventory.lock.json is not valid JSON: $_"
  }
}

# ── 2.13 Duplicate host-port detection ───────────────────────────────────────
$portVars = @(
  'TT_N8N_HOST_PORT',        'TT_PGADMIN_HOST_PORT',    'TT_REDISINSIGHT_HOST_PORT',
  'TT_METABASE_HOST_PORT',   'TT_KANBOARD_HOST_PORT',   'TT_WORDPRESS_HOST_PORT',
  'TT_OPENWEBUI_HOST_PORT',  'TT_UPTIME_KUMA_HOST_PORT','TT_PORTAINER_HOST_PORT',
  'TT_OPENCLAW_HOST_PORT',   'TT_POSTGRES_HOST_PORT',   'TT_REDIS_HOST_PORT'
)
$ports = New-Object System.Collections.Generic.List[int]
foreach ($var in $portVars) {
  $parsed = 0
  if ([int]::TryParse((Get-EnvValue $coreEnv $var), [ref]$parsed) -and $parsed -gt 0) {
    $ports.Add($parsed)
  }
}
foreach ($dup in @($ports | Group-Object | Where-Object { $_.Count -gt 1 })) {
  Add-Issue 'ERROR' "Duplicate host port $($dup.Name) detected in runtime core env."
}

# ── 2.14 Qdrant authentication ────────────────────────────────────────────────
if ($select.profiles.qdrant -eq $true) {
  $qdrantKey = Get-EnvValue $coreEnv 'TT_QDRANT_API_KEY'
  if ([string]::IsNullOrWhiteSpace($qdrantKey) -or $qdrantKey -match '^__') {
    Add-Issue 'ERROR' 'Qdrant profile is enabled but TT_QDRANT_API_KEY is missing or placeholder. Qdrant will refuse to start.'
  }
}

# =============================================================================
# Phase 3 — Supabase (optional, only with -IncludeSupabase)
# =============================================================================


# ── 2.15 Backup encryption key advisory ────────────────────────────────────
# Non-blocking advisory: warn if TT_BACKUP_ENCRYPTION_KEY is missing.
# Matches Linux preflight-check.sh check #20.
$encKey = Get-EnvValue $coreEnv 'TT_BACKUP_ENCRYPTION_KEY'
if ([string]::IsNullOrWhiteSpace($encKey) -or $encKey -match '^__') {
  Add-Issue 'WARNING' 'TT_BACKUP_ENCRYPTION_KEY is not set. Backups will be stored unencrypted. Set a 32+ character passphrase in runtime core env to enable AES-256-CBC encryption.'
}

if ($IncludeSupabase) {
  Write-Host '[ Phase 3 ] Supabase' -ForegroundColor DarkGray

  if (!(Test-Path $supabaseRoot)) {
    Add-Issue 'WARNING' 'Supabase preflight requested but tt-supabase bundle directory is missing.'
  } elseif (!(Test-Path $supabaseEnvPath)) {
    Add-Issue 'WARNING' 'Supabase preflight: compose/tt-supabase/.env is missing. Run Init-Supabase.ps1.'
  } else {
    $supaEnv = Read-DotEnv $supabaseEnvPath

    # Required secrets — must be set and not placeholder
    foreach ($k in @('POSTGRES_PASSWORD', 'JWT_SECRET', 'ANON_KEY',
                      'SERVICE_ROLE_KEY', 'DASHBOARD_PASSWORD', 'LOGFLARE_API_KEY')) {
      $v = Get-EnvValue $supaEnv $k
      if ([string]::IsNullOrWhiteSpace($v) -or $v -match '^__') {
        Add-Issue 'WARNING' "Supabase: '$k' is missing or still placeholder."
      }
    }

    # JWT format validation (3 dot-separated parts)
    foreach ($k in @('ANON_KEY', 'SERVICE_ROLE_KEY')) {
      $v = Get-EnvValue $supaEnv $k
      if (-not [string]::IsNullOrWhiteSpace($v) -and
          -not ($v -match '^__') -and
          ($v -split '\.').Count -ne 3) {
        Add-Issue 'WARNING' "Supabase: '$k' does not look like a valid JWT (expected 3 dot-separated parts). Run Init-Supabase.ps1."
      }
    }

    # JWT_SECRET minimum length
    $jwtSecret = Get-EnvValue $supaEnv 'JWT_SECRET'
    if (-not [string]::IsNullOrWhiteSpace($jwtSecret) -and
        -not ($jwtSecret -match '^__') -and
        $jwtSecret.Length -lt 32) {
      Add-Issue 'WARNING' 'Supabase: JWT_SECRET is shorter than 32 characters. Regenerate with Init-Supabase.ps1.'
    }

    # Domain placeholders
    foreach ($k in @('API_EXTERNAL_URL', 'SITE_URL')) {
      $v = Get-EnvValue $supaEnv $k
      if ([string]::IsNullOrWhiteSpace($v) -or $v -match '^https?://example\.') {
        Add-Issue 'WARNING' "Supabase: '$k' still uses placeholder domain. Set your real production domain."
      }
    }
  }
}

# =============================================================================
# Emit Results
# =============================================================================

$errors   = @($script:Findings | Where-Object { $_.Severity -eq 'ERROR' })
$warnings = @($script:Findings | Where-Object { $_.Severity -eq 'WARNING' })
$infos    = @($script:Findings | Where-Object { $_.Severity -eq 'INFO' })

foreach ($item in $errors)   { Write-Host "[ERROR] $($item.Message)" -ForegroundColor Red }
foreach ($item in $warnings) { Write-Host "[WARN]  $($item.Message)" -ForegroundColor Yellow }
foreach ($item in $infos)    { Write-Host "[INFO]  $($item.Message)" -ForegroundColor Cyan }

Write-Host ''
Write-Host "Summary: $($errors.Count) error(s), $($warnings.Count) warning(s)." -ForegroundColor Cyan

if ($errors.Count -gt 0) {
  Write-Host 'Preflight checks FAILED.' -ForegroundColor Red
  exit 1
}
Write-Host 'Preflight checks PASSED.' -ForegroundColor Green
