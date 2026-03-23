#Requires -Version 5.1
# =============================================================================
# validate-release.ps1  (TT-Production v14.0)
# Schema Alignment Gate: Verifies ServiceCatalog.ps1 matches service-catalog.json — TT-Core Release Gate (TT-Production v14.0)
#
# USAGE:
#   .\validate-release.ps1
#   .\validate-release.ps1 -Root "C:\path\to\tt-core"
#
# Validates the tt-core/ sub-directory before bundle delivery.
# Collects ALL failures — does NOT exit on first error.
# EXIT: 0 = pass (warnings allowed), 1 = one or more failures.
# =============================================================================

param(
  [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
try { $Root = (Resolve-Path $Root -ErrorAction Stop).Path } catch {}

$script:FailCount = 0
$script:WarnCount = 0
$script:PassCount = 0

# ── Derive canonical version from bundle-level version.json ──────────────────
$bundleVersionJson = Join-Path (Split-Path $Root -Parent) 'release/version.json'
$ttCoreVersionJson = Join-Path $Root 'release/version.json'
$expectedVersion = 'v14.0'  # fallback only — canonical source is release/version.json
foreach ($vj in @($bundleVersionJson, $ttCoreVersionJson)) {
  if (Test-Path $vj) {
    try {
      $vd = Get-Content $vj -Raw | ConvertFrom-Json
      $ver = if ($vd.package_version) { [string]$vd.package_version } elseif ($vd.version) { [string]$vd.version } else { '' }
      if (-not [string]::IsNullOrWhiteSpace($ver)) {
        $expectedVersion = $ver
        break
      }
    } catch {}
  }
}


function Fail { param([string]$msg); $script:FailCount++; Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Warn { param([string]$msg); $script:WarnCount++; Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Pass { param([string]$msg); $script:PassCount++; Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Section { param([string]$t); Write-Host ''; Write-Host "── $t ──" -ForegroundColor Cyan }



# ── SEMANTIC GATE: ServiceCatalog.ps1 schema alignment ─────────────────────────
Write-Host ""; Write-Host "── Semantic Schema Alignment ──" -ForegroundColor Cyan
$scLibPath = Join-Path $Root 'scripts/lib/ServiceCatalog.ps1'
if (Test-Path $scLibPath) {
  $scContent = Get-Content $scLibPath -Raw

  # P0-1 guard: route resolution must use 'route_name' — not 'tunnel_route' or 'tunnel_host'
  if ($scContent -match "PSObject\.Properties\['tunnel_route'\]" -or
      $scContent -match "PSObject\.Properties\['tunnel_host'\]") {
    Fail "ServiceCatalog.ps1: Get-TTRouteNameFromCatalogEntry reads 'tunnel_route' or 'tunnel_host' — canonical field is 'route_name'. ALL route resolution is broken."
  } else { Pass "ServiceCatalog.ps1: route_name field used correctly (not tunnel_route/tunnel_host)" }

  # P0-2 guard: security gate must check tier string — not a boolean restricted_admin property
  if ($scContent -match "PSObject\.Properties\['restricted_admin'\]") {
    Fail "ServiceCatalog.ps1: restricted_admin check uses non-existent boolean property. Must check: [string]\$entry.tier -eq 'restricted_admin'"
  } else { Pass "ServiceCatalog.ps1: restricted_admin gate uses tier field correctly" }

  # P0-3 guard: health targets must use 'health' object — not legacy 'health_endpoint'
  if ($scContent -match "PSObject\.Properties\['health_endpoint'\]") {
    Fail "ServiceCatalog.ps1: Get-TTServiceHealthTargets reads 'health_endpoint' — canonical field is health.probe_path. Smoke test HTTP probes are dead."
  } else { Pass "ServiceCatalog.ps1: health probe uses health.probe_path correctly (not health_endpoint)" }

  # P1-1 guard: profile resolution must handle additional_profiles
  if ($scContent -notmatch "additional_profiles") {
    Fail "ServiceCatalog.ps1: Get-TTProfilesForServiceFromCatalog ignores additional_profiles array. openwebui will start without Ollama."
  } else { Pass "ServiceCatalog.ps1: additional_profiles handled in profile resolution" }

} else { Fail "scripts/lib/ServiceCatalog.ps1 not found" }

# Verify service-catalog.json canonical field presence
$catPath = Join-Path $Root 'config/service-catalog.json'
if (Test-Path $catPath) {
  $catContent = Get-Content $catPath -Raw | ConvertFrom-Json
  $routeCapable = @($catContent.services | Where-Object { $_.public_capable -eq $true })
  $missingRouteNames = @($routeCapable | Where-Object {
    $rn = $_.PSObject.Properties['route_name']
    $null -eq $rn -or [string]::IsNullOrWhiteSpace([string]$rn.Value)
  })
  if ($missingRouteNames.Count -gt 0) {
    $missing = ($missingRouteNames | ForEach-Object { [string]$_.service }) -join ', '
    Fail "service-catalog.json: public_capable services missing route_name: $missing"
  } else { Pass "service-catalog.json: all public_capable services have route_name" }

  $healthServices = @($catContent.services | Where-Object {
    $h = $_.PSObject.Properties['health']
    $null -ne $h -and $null -ne $h.Value
  })
  if ($healthServices.Count -eq 0) {
    Fail "service-catalog.json: no services have a health object — smoke test will probe nothing"
  } else { Pass "service-catalog.json: $($healthServices.Count) services have health probe definitions" }

  # Verify no stale version in catalog
  if ([string]$catContent.version -ne $expectedVersion) {
    Fail "service-catalog.json: version field is '$($catContent.version)' — expected '$expectedVersion'"
  } else { Pass "service-catalog.json: version field = $expectedVersion" }
} else { Fail "config/service-catalog.json not found" }

Write-Host ''
Write-Host '═══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host "  TT-Core Release Validator — TT-Production v14.0 (version: $expectedVersion)" -ForegroundColor Cyan
Write-Host "  Root: $Root" -ForegroundColor DarkGray
Write-Host '═══════════════════════════════════════════════════════════════' -ForegroundColor Cyan

# ── Required files ────────────────────────────────────────────────────────────
Section 'Required Files'

$required = @(
  'compose/tt-core/docker-compose.yml',
  'compose/tt-core/.env.example',
  'compose/tt-core/volumes/redis/config/redis.conf',
  'compose/tt-core/volumes/postgres/init/00-tt-core-init.sh',
  'compose/tt-tunnel/docker-compose.yml',
  'config/service-catalog.json',
  'config/services.select.json',
  'config/public-exposure.policy.json',
  'scripts/Preflight-Check.ps1',
  'scripts/Preflight-Check.cmd',
  'scripts/Preflight-Supabase.ps1',
  'scripts/Preflight-Supabase.cmd',
  'scripts/Init-TTCore.ps1',
  'scripts/lib/ServiceCatalog.ps1',
  'scripts/lib/Env.ps1',
  'scripts/ttcore.ps1',
  'scripts/Start-Core.ps1',
  'scripts/Stop-Core.ps1',
  'scripts/Status-Core.ps1',
  'scripts/backup/Backup-All.ps1',
  'scripts/backup/_lib/BackupLib.ps1',
  'scripts-linux/preflight-check.sh',
  'scripts-linux/preflight-supabase.sh',
  'scripts-linux/init.sh',
  'scripts-linux/start-core.sh',
  'scripts-linux/stop-core.sh',
  'scripts-linux/status.sh',
  'scripts-linux/backup.sh',
  'installer/lib/sops-setup.sh',
  'installer/Install-TTCore.sh',
  'installer/Install-TTCore.ps1',
  'release/manifest.json',
  'release/validate-release.ps1'
)

foreach ($rel in $required) {
  $path = Join-Path $Root $rel
  if (!(Test-Path $path)) { Fail "Missing required file: $rel" }
  else { Pass "Present: $rel" }
}

# ── service-catalog.json ──────────────────────────────────────────────────────
Section 'Service Catalog'

$catalogPath = Join-Path $Root 'config/service-catalog.json'
if (Test-Path $catalogPath) {
  try {
    $catalog = Get-Content $catalogPath -Raw | ConvertFrom-Json
    if ($null -eq $catalog.services -or $catalog.services.Count -eq 0) {
      Fail 'service-catalog.json: services array is empty'
    } else {
      Pass "service-catalog.json: $($catalog.services.Count) services defined"
    }
    $withProfiles = @($catalog.services | Where-Object { -not [string]::IsNullOrWhiteSpace($_.profile) })
    Pass "service-catalog.json: $($withProfiles.Count) services with profiles"
  } catch { Fail "service-catalog.json: JSON parse error — $_" }
}

# ── public-exposure.policy.json ───────────────────────────────────────────────
Section 'Public Exposure Policy'

$policyPath = Join-Path $Root 'config/public-exposure.policy.json'
if ((Test-Path $policyPath) -and (Test-Path $catalogPath)) {
  try {
    $policy = Get-Content $policyPath -Raw | ConvertFrom-Json
    if ([string]$policy.generated_from -ne 'config/service-catalog.json') {
      Fail "public-exposure.policy.json: generated_from must be 'config/service-catalog.json'. Run Sync-PublicExposurePolicy.ps1."
    } else { Pass 'public-exposure.policy.json: generated_from correct' }
    $catalog = Get-Content $catalogPath -Raw | ConvertFrom-Json
    foreach ($p in $policy.services) {
      $found = @($catalog.services | Where-Object { $_.service -eq $p.service })
      if ($found.Count -eq 0) { Fail "Policy references unknown service: $($p.service)" }
    }
    Pass 'All policy services found in catalog'
  } catch { Fail "public-exposure.policy.json: error — $_" }
}

# ── Tunnel: token-only (no TUNNEL_UUID) ───────────────────────────────────────
Section 'Tunnel Architecture'

$tunnelEnv = Join-Path $Root 'compose/tt-tunnel/.env.example'
if (Test-Path $tunnelEnv) {
  $tContent = Get-Content $tunnelEnv -Raw
  if ($tContent -match '^\s*TUNNEL_UUID\s*=\s*\S') {
    Fail 'tt-tunnel .env.example: TUNNEL_UUID must not be set — use token-only mode (TUNNEL_TOKEN).'
  } else { Pass 'Tunnel .env.example: token-only mode (no TUNNEL_UUID)' }
}

# ── services.select.json — required structure + safety defaults ───────────────
Section 'services.select.json'

$selectPath = Join-Path $Root 'config/services.select.json'
if (Test-Path $selectPath) {
  try {
    $sel = Get-Content $selectPath -Raw | ConvertFrom-Json
    foreach ($block in @('meta','client','core','profiles','tunnel','backup','security')) {
      $prop = $sel.PSObject.Properties[$block]
      if ($null -eq $prop) { Fail "services.select.json missing required block: '$block'" }
      else { Pass "services.select.json: block '$block' present" }
    }
    # Security gate must default closed
    if ($sel.security.allow_restricted_admin_tunnel_routes -eq $true) {
      Fail "services.select.json: security.allow_restricted_admin_tunnel_routes must be false (default)"
    } else { Pass 'services.select.json: restricted_admin_tunnel_routes=false (correct default)' }
    # backup.notify_on_failure must be present
    $notifyProp = $sel.backup.PSObject.Properties['notify_on_failure']
    if ($null -eq $notifyProp) {
      Fail "services.select.json: backup.notify_on_failure is missing — add it with value: false"
    } else { Pass "services.select.json: backup.notify_on_failure = $($notifyProp.Value)" }
    # backup.notify_webhook_url must be present
    $webhookProp = $sel.backup.PSObject.Properties['notify_webhook_url']
    if ($null -eq $webhookProp) {
      Warn 'services.select.json: backup.notify_webhook_url is missing — recommended for alerting'
    } else { Pass 'services.select.json: backup.notify_webhook_url present' }
  } catch { Fail "services.select.json: JSON parse error — $_" }
}

# ── Restart-Core must not force-start WordPress ───────────────────────────────
Section 'Script Safety'

$restartCore = Join-Path $Root 'scripts/Restart-Core.ps1'
if (Test-Path $restartCore) {
  $rcContent = Get-Content $restartCore -Raw
  if ($rcContent -match 'wordpress' -and $rcContent -notmatch 'profile') {
    Warn 'Restart-Core.ps1 may unconditionally start wordpress — verify it uses profiles'
  } else { Pass 'Restart-Core.ps1 does not force-start wordpress outside profiles' }
}

# ── ServiceCatalog: security gate (4-layer enforcement) ───────────────────────
Section 'Security Gate'

$scPath = Join-Path $Root 'scripts/lib/ServiceCatalog.ps1'
if (Test-Path $scPath) {
  $scContent = Get-Content $scPath -Raw

  if ($scContent -notmatch 'function Test-TTAdminRouteGateOpen') {
    Fail 'ServiceCatalog.ps1: Test-TTAdminRouteGateOpen missing — fail-closed gate not enforceable'
  } else { Pass 'ServiceCatalog.ps1: Test-TTAdminRouteGateOpen defined (fail-closed)' }

  if ($scContent -notmatch 'function Test-TTRouteEnabledForService') {
    Fail 'ServiceCatalog.ps1: Test-TTRouteEnabledForService missing — 4-layer gate missing'
  } else { Pass 'ServiceCatalog.ps1: Test-TTRouteEnabledForService defined' }

  # Layer 2 must be called INSIDE Test-TTRouteEnabledForService body
  $fnIdx = $scContent.IndexOf('function Test-TTRouteEnabledForService')
  if ($fnIdx -ge 0) {
    $fnBody = $scContent.Substring($fnIdx, [Math]::Min(1200, $scContent.Length - $fnIdx))
    if ($fnBody -notmatch 'Test-TTAdminRouteGateOpen') {
      Fail 'Test-TTRouteEnabledForService: Layer 2 (Test-TTAdminRouteGateOpen) not invoked — security hole'
    } else { Pass 'Test-TTRouteEnabledForService: Layer 2 invoked (restricted_admin gated)' }
  }
}

# ── Env.ps1: alphanumeric + Ensure-EnvKey ─────────────────────────────────────
Section 'Env.ps1 Library'

$envLibPath = Join-Path $Root 'scripts/lib/Env.ps1'
if (Test-Path $envLibPath) {
  $envContent = Get-Content $envLibPath -Raw
  if ($envContent -notmatch '"alphanumeric"') {
    Fail 'Env.ps1: New-RandomSecret does not support "alphanumeric" format — TT_REDISINSIGHT_PASSWORD generation will CRASH'
  } else { Pass 'Env.ps1: New-RandomSecret supports alphanumeric format' }
  if ($envContent -notmatch 'ValidateSet.*alphanumeric') {
    Fail 'Env.ps1: Ensure-EnvSecret ValidateSet does not include "alphanumeric" — Init-TTCore.ps1 will CRASH'
  } else { Pass 'Env.ps1: Ensure-EnvSecret ValidateSet includes alphanumeric' }
  if ($envContent -notmatch 'function Ensure-EnvKey') {
    Fail 'Env.ps1: Ensure-EnvKey function missing — Init-TTCore.ps1 will CRASH on non-secret defaults'
  } else { Pass 'Env.ps1: Ensure-EnvKey function defined' }
  if ($envContent -notmatch 'function Ensure-EnvSecret') {
    Fail 'Env.ps1: Ensure-EnvSecret function missing'
  } else { Pass 'Env.ps1: Ensure-EnvSecret function present' }
}

# ── Start-Service: catalog-driven route check ──────────────────────────────────
Section 'Start-Service Route Check'

$startSvc = Join-Path $Root 'scripts/Start-Service.ps1'
if (Test-Path $startSvc) {
  $ssContent = Get-Content $startSvc -Raw
  if ($ssContent -notmatch 'Test-TTRouteEnabledForService|Test-TTAdminRouteGateOpen') {
    Warn 'Start-Service.ps1 does not call Test-TTRouteEnabledForService — tunnel route validation may be skipped'
  } else { Pass 'Start-Service.ps1: catalog-driven route check present' }
}

# ── Add-on hardening ──────────────────────────────────────────────────────────
Section 'Add-on Hardening'

$addonsDir = Join-Path $Root 'compose/tt-core/addons'
if (Test-Path $addonsDir) {
  $addonFiles = Get-ChildItem $addonsDir -Filter '*.addon.yml' |
    Where-Object { $_.Name -ne '00-template.addon.yml' }
  foreach ($af in $addonFiles) {
    $ac = Get-Content $af.FullName -Raw
    if ($ac -notmatch 'memory:') {
      Warn "Add-on $($af.Name): missing deploy.resources memory limits"
    } else { Pass "Add-on $($af.Name): memory limits present" }
    if ($ac -notmatch 'restart:') {
      Warn "Add-on $($af.Name): missing restart policy"
    }
    if ($ac -notmatch 'logging:') {
      Warn "Add-on $($af.Name): missing logging section"
    }
  }
}

# ── OpenClaw hardening ────────────────────────────────────────────────────────
Section 'OpenClaw Hardening'

$ocTemplate = Join-Path $Root 'compose/tt-core/volumes/openclaw/config/openclaw_template.json'
if (Test-Path $ocTemplate) {
  $ocContent = Get-Content $ocTemplate -Raw
  if ($ocContent -match '"allowInsecureAuth"\s*:\s*true') {
    Fail 'openclaw_template.json: allowInsecureAuth=true — must be false'
  } else { Pass 'openclaw_template.json: allowInsecureAuth=false' }
}

$coreEnvExample = Get-Content (Join-Path $Root 'compose/tt-core/.env.example') -Raw -ErrorAction SilentlyContinue
if ($coreEnvExample) {
  if ($coreEnvExample -match 'TT_OPENCLAW_SOURCE_REF=openclaw/main-unpinned') {
    Fail '.env.example: TT_OPENCLAW_SOURCE_REF must not default to openclaw/main-unpinned.'
  }
  if ($coreEnvExample -match '__PIN_TAG_OR_COMMIT_BEFORE_PRODUCTION__|__PIN_GIT_TAG_OR_COMMIT__') {
    Pass '.env.example: OpenClaw source placeholder requires pin before deployment (supported placeholder present)'
  } else {
    Warn '.env.example: PIN_TAG placeholder not found — verify OpenClaw source is pinned'
  }
}

# ── Redis configuration ───────────────────────────────────────────────────────
Section 'Redis Configuration'

$redisConf = Join-Path $Root 'compose/tt-core/volumes/redis/config/redis.conf'
if (Test-Path $redisConf) {
  $rc = Get-Content $redisConf -Raw
  if ($rc -notmatch 'maxmemory\s+\d+')   { Fail 'redis.conf: maxmemory directive missing' }
  else { Pass 'redis.conf: maxmemory declared' }
  if ($rc -notmatch 'maxmemory-policy')   { Warn 'redis.conf: maxmemory-policy missing (recommend allkeys-lru)' }
  else { Pass 'redis.conf: maxmemory-policy set' }
  if ($rc -notmatch 'slowlog')            { Warn 'redis.conf: slowlog not configured' }
  else { Pass 'redis.conf: slowlog configured' }
} else { Fail 'redis.conf: file missing — volume mount will fail at container start' }

# Verify docker-compose uses redis.conf in redis-server command
$coreComposeR = Get-Content (Join-Path $Root 'compose/tt-core/docker-compose.yml') -Raw -ErrorAction SilentlyContinue
if ($coreComposeR) {
  if ($coreComposeR -notmatch '/usr/local/etc/redis/redis\.conf') {
    Fail 'docker-compose.yml: redis-server does not pass redis.conf path — maxmemory/eviction inert'
  } else { Pass 'docker-compose.yml: redis-server uses mounted redis.conf' }
}

# ── Database isolation ────────────────────────────────────────────────────────
Section 'Database Isolation'

$initSh = Join-Path $Root 'compose/tt-core/volumes/postgres/init/00-tt-core-init.sh'
if (Test-Path $initSh) {
  $initContent = Get-Content $initSh -Raw
  foreach ($svc in @('N8N','METABASE','KANBOARD')) {
    if ($initContent -match "TT_${svc}_DB_USER") { Pass "DB isolation: $svc has dedicated user" }
    else { Fail "DB isolation: $svc dedicated user not found in init script" }
  }
}

# ── Backup scripts ────────────────────────────────────────────────────────────
Section 'Backup Scripts'

$backupScripts = @(
  'scripts/backup/Backup-All.ps1',
  'scripts/backup/Backup-Volumes.ps1',
  'scripts/backup/Backup-PostgresDumps.ps1',
  'scripts/backup/Backup-Retention.ps1',
  'scripts/backup/_lib/BackupLib.ps1'
)
foreach ($bs in $backupScripts) {
  $bp = Join-Path $Root $bs
  if (!(Test-Path $bp)) { Fail "Backup script missing: $bs" }
  else { Pass "Backup script present: $(Split-Path -Leaf $bs)" }
}

# ── manifest.json ─────────────────────────────────────────────────────────────
Section 'Manifest'

$manifestPath = Join-Path $Root 'release/manifest.json'
if (Test-Path $manifestPath) {
  try {
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    if ([string]$manifest.version -ne $expectedVersion) {
      Fail "manifest.json: version does not match $expectedVersion (got: $($manifest.version))"
    } else { Pass "manifest.json: version = $($manifest.version) [expected: $expectedVersion]" }
  } catch { Fail 'manifest.json: JSON parse error' }
}

# ── Stale version markers ─────────────────────────────────────────────────────
Section 'Stale Version Markers'

$stalePatterns = @(
  'TT-Production-v0\.',
  'TT-Production-v1\.[0-6]\.',
  'v0\.8\.[0-9]-hardened',
  'v0\.9\.0-final',
  'config-mode is supported in production'
)
$scanExts  = @('.yml','.yaml','.ps1','.sh','.json','.md','.env','.example')
$scanFiles = Get-ChildItem -Path $Root -Recurse -File |
  Where-Object {
    $scanExts -contains $_.Extension -and
    $_.FullName -notmatch [regex]::Escape((Join-Path $Root 'archive')) -and
    $_.FullName -notmatch 'release\\validate-release\.ps1' -and
    $_.FullName -notmatch 'release\\CHANGELOG'
  }

$staleFound = $false
foreach ($file in $scanFiles) {
  $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
  foreach ($pat in $stalePatterns) {
    if ($content -match $pat) {
      Fail "Stale marker '$pat' in: $($file.FullName.Replace($Root,'').TrimStart('\/'))"
      $staleFound = $true
    }
  }
}
if (-not $staleFound) { Pass 'No stale version markers found' }

# ── GATE 1: Identity integrity — no stale version in active files ────────────
Section 'Gate 1 — Release Identity Integrity'

$staleVersionPatterns = @('v6\.7\.1', 'v6\.7\.2\.1', 'v6\.7\.2\.2\.2', 'v6\.7\.2\.3')
$activeFiles = Get-ChildItem -Path $Root -Recurse -File |
  Where-Object {
    $_.FullName -notmatch '\\history\\' -and
    $_.FullName -notmatch '\\archive\\' -and
    $_.FullName -notmatch 'CHANGELOG' -and
    $_.FullName -notmatch 'RELEASE_NOTES' -and
    $_.FullName -notmatch 'validate-release\.ps1'
  }

$identityFailed = $false
foreach ($file in $activeFiles) {
  $c = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
  foreach ($pat in $staleVersionPatterns) {
    if ($c -match $pat) {
      Fail "Gate 1 FAIL — Stale identity '$pat' in active file: $($file.FullName.Replace($Root,'').TrimStart('\/'))"
      $identityFailed = $true
    }
  }
}
if (-not $identityFailed) { Pass 'Gate 1: No stale identity strings in active files' }

# ── GATE 2: Required .env.example templates present ─────────────────────────
Section 'Gate 2 — Required .env.example Templates'

$requiredTemplates = @(
  'env/.env.example',
  'compose/tt-core/.env.example',
  'compose/tt-tunnel/.env.example'
)
foreach ($tpl in $requiredTemplates) {
  $tp = Join-Path $Root $tpl
  if (!(Test-Path $tp)) {
    Fail "Gate 2 FAIL — Required template missing: $tpl (breaks fresh install — init.sh will fail)"
  } else {
    Pass "Gate 2: Template present: $tpl"
  }
}

# ── Summary ───────────────────────────────────────────────────────────────────

# ── AUTO-CHECK 7: Env.ps1 alphanumeric format (prevents Init-TTCore crash) ──────────
Write-Host '  [AUTO] Env.ps1 alphanumeric format check...' -ForegroundColor DarkGray
$envLibPath = Join-Path $Root 'scripts/lib/Env.ps1'
if (Test-Path $envLibPath) {
  $envLibContent = Get-Content $envLibPath -Raw
  if ($envLibContent -notmatch 'ValidateSet.*alphanumeric') {
    Fail 'Env.ps1 ValidateSet does not include "alphanumeric" — Init-TTCore.ps1 CRASHES when generating TT_REDISINSIGHT_PASSWORD. Alphanumeric format is required in Env.ps1.'
  } else {
    Write-Host '    ✓ Env.ps1: ValidateSet includes alphanumeric format' -ForegroundColor DarkGray
  }
} else {
  Fail 'scripts/lib/Env.ps1 not found'
}

# ── AUTO-CHECK 8: Env.ps1 Ensure-EnvKey function (prevents Init-TTCore crash) ──────
Write-Host '  [AUTO] Env.ps1 Ensure-EnvKey function check...' -ForegroundColor DarkGray
if (Test-Path $envLibPath) {
  $envLibContent = Get-Content $envLibPath -Raw
  if ($envLibContent -notmatch 'function Ensure-EnvKey') {
    Fail 'Env.ps1 Ensure-EnvKey function missing — Init-TTCore.ps1 CRASHES on Ensure-EnvKey calls (TT_N8N_EXECUTIONS_MODE, TT_PG_* defaults not written). Ensure-EnvKey function is required in Env.ps1.'
  } else {
    Write-Host '    ✓ Env.ps1: Ensure-EnvKey function defined' -ForegroundColor DarkGray
  }
}
Write-Host '    ✓ All 8 regression guards passed' -ForegroundColor DarkGray


# ── GATE 12: UPGRADE_GUIDE.md present with rollback docs (NEW v9.2) ────────
Section 'Gate 12 — Upgrade Guide'
$ugPath = Join-Path $Root 'docs/UPGRADE_GUIDE.md'
if (!(Test-Path $ugPath)) {
  Fail 'Gate 12 FAIL — tt-core/docs/UPGRADE_GUIDE.md missing — operators cannot upgrade safely (P1)'
} else {
  $ugContent = Get-Content $ugPath -Raw
  if ($ugContent -notmatch 'Rollback') {
    Fail 'Gate 12 FAIL — UPGRADE_GUIDE.md has no Rollback Procedure — unacceptable for production release'
  } else {
    Pass 'Gate 12: UPGRADE_GUIDE.md present with rollback procedures'
  }
  if ($ugContent -notmatch 'backup') {
    Warn 'Gate 12 WARN — UPGRADE_GUIDE.md does not reference backup before upgrade'
  }
}

# ── GATE 13: backup.sh has notify_success (NEW v9.2) ───────────────────────
Section 'Gate 13 — Backup Notifications Complete'
$bkPath = Join-Path $Root 'scripts-linux/backup.sh'
if (!(Test-Path $bkPath)) {
  Fail 'Gate 13 FAIL — scripts-linux/backup.sh not found'
} else {
  $bkContent = Get-Content $bkPath -Raw
  if ($bkContent -notmatch 'notify_success') {
    Fail 'Gate 13 FAIL — backup.sh missing notify_success() — operators cannot observe successful backups (P2)'
  } else {
    Pass 'Gate 13: backup.sh has notify_success() webhook on success'
  }
  if ($bkContent -notmatch 'notify_failure') {
    Fail 'Gate 13 FAIL — backup.sh missing notify_failure() — operators not alerted on backup failures'
  } else {
    Pass 'Gate 13: backup.sh has notify_failure() webhook on failure'
  }
}



# -- GATE 14: Runtime env authority (no legacy compose .env refs) --
Section 'Gate 14 - Runtime Env Authority'

$authorityAllowList = @(
  'docs/ENV-STRATEGY.md',
  'scripts-linux/init.sh',
  'scripts-linux/migrate-to-sops.sh',
  'scripts-linux/lib/runtime-env.sh',
  'scripts/lib/RuntimeEnv.ps1',
  'release/validate-release.ps1'
)

$authorityScanRoots = @('docs', 'scripts', 'scripts-linux', 'installer')
$legacyEnvNeedles = @(
  'compose/tt-core/.env',
  'compose/tt-tunnel/.env',
  'compose\tt-core\.env',
  'compose\tt-tunnel\.env'
)

$authorityViolations = New-Object System.Collections.Generic.List[string]

foreach ($scanRoot in $authorityScanRoots) {
  $rootPath = Join-Path $Root $scanRoot
  if (!(Test-Path $rootPath)) { continue }

  $files = Get-ChildItem -Path $rootPath -Recurse -File -ErrorAction SilentlyContinue
  foreach ($file in $files) {
    $relPath = $file.FullName.Replace($Root, '').TrimStart('\', '/').Replace('\', '/')
    if ($authorityAllowList -contains $relPath) { continue }

    $fileLines = Get-Content -Path $file.FullName -ErrorAction SilentlyContinue
    if ($null -eq $fileLines) { continue }

    for ($i = 0; $i -lt $fileLines.Count; $i++) {
      $line = [string]$fileLines[$i]
      if ($line -match '\.env\.example') { continue }

      foreach ($needle in $legacyEnvNeedles) {
        if ($line -match [regex]::Escape($needle)) {
          $authorityViolations.Add(("{0}:{1}: {2}" -f $relPath, ($i+1), $line.Trim()))
          break
        }
      }
    }
  }
}

if ($authorityViolations.Count -gt 0) {
  Fail "Gate 14 FAIL - legacy compose .env references found outside allow-list: $($authorityViolations.Count)"
  foreach ($v in $authorityViolations) {
    Write-Host "    -> $v" -ForegroundColor DarkRed
  }
} else {
  Pass 'Gate 14: runtime env authority enforced (no disallowed legacy compose .env references)'
}

# -- GATE 15: secrets-strength.sh presence and functionality --
Section 'Gate 15 - secrets-strength.sh Presence and Functionality'
$strengthFile = Join-Path $Root 'scripts-linux/secrets-strength.sh'
if (-not (Test-Path $strengthFile)) {
  Fail 'Gate 15 FAIL - secrets-strength.sh missing: required for secret quality enforcement'
} else {
  $sContent = Get-Content $strengthFile -Raw
  if ($sContent -notmatch '--strict') {
    Fail 'Gate 15 FAIL - secrets-strength.sh missing --strict mode (required for CI/CD integration)'
  } elseif ($sContent -notmatch 'grade') {
    Fail 'Gate 15 FAIL - secrets-strength.sh missing grading logic'
  } else {
    Pass 'Gate 15: secrets-strength.sh present with --strict mode and grading logic'
  }
}

# -- GATE 16: restore verification + backup cleanup scripts --
Section 'Gate 16 - verify-restore.sh and cleanup-backups.sh Presence'
$vrFile = Join-Path $Root 'scripts-linux/verify-restore.sh'
$cbFile = Join-Path $Root 'scripts-linux/cleanup-backups.sh'
if (-not (Test-Path $vrFile)) {
  Fail 'Gate 16 FAIL - verify-restore.sh missing'
} elseif (-not (Test-Path $cbFile)) {
  Fail 'Gate 16 FAIL - cleanup-backups.sh missing'
} else {
  Pass 'Gate 16: verify-restore.sh and cleanup-backups.sh present'
}

# -- GATE 17: commercial bundle hygiene (no sensitive artifacts) --
Section 'Gate 17 - Commercial Bundle Hygiene'

$hygieneIssues = New-Object System.Collections.Generic.List[string]

$forbiddenVcsDirs = @('.git', '.svn', '.hg', '.history')
$vcsDirs = Get-ChildItem -Path $Root -Recurse -Force -Directory -ErrorAction SilentlyContinue |
  Where-Object { $forbiddenVcsDirs -contains $_.Name }
foreach ($d in $vcsDirs) {
  $rel = $d.FullName.Replace($Root, '').TrimStart('\', '/').Replace('\', '/')
  $hygieneIssues.Add("Forbidden VCS/history directory: $rel")
}

$dotEnvFiles = Get-ChildItem -Path $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -eq '.env' -or $_.Name -like '.env.*' -or $_.Name -like '*.env' }
foreach ($f in $dotEnvFiles) {
  $rel = $f.FullName.Replace($Root, '').TrimStart('\', '/').Replace('\', '/')
  if ($rel -match '\.env\.example$') { continue }
  if ($rel -match '^templates/.+\.template\.env$') { continue }
  $hygieneIssues.Add("Plaintext env-like file in bundle tree: $rel")
}

$encSecretFiles = Get-ChildItem -Path (Join-Path $Root 'secrets') -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '\.enc\.env$' }
foreach ($f in $encSecretFiles) {
  $rel = $f.FullName.Replace($Root, '').TrimStart('\', '/').Replace('\', '/')
  $hygieneIssues.Add("Encrypted secret payload should not ship in source/commercial bundle: $rel")
}

$sopsPath = Join-Path $Root 'secrets/.sops.yaml'
$forbiddenDevAgeKey = 'age1qprwg5fxspev023zhv2thdrl7k6gx5rkv9rfenc2k0w0txj5c9vs5hk7yc'
if (!(Test-Path $sopsPath)) {
  $hygieneIssues.Add('Missing secrets/.sops.yaml (required placeholder policy file).')
} else {
  $sopsText = Get-Content $sopsPath -Raw -Encoding UTF8
  if ($sopsText -match [regex]::Escape($forbiddenDevAgeKey)) {
    $hygieneIssues.Add('Forbidden developer age key found in secrets/.sops.yaml.')
  }
  if ($sopsText -notmatch '<OPERATOR_AGE_PUBLIC_KEY>') {
    $hygieneIssues.Add('secrets/.sops.yaml must ship with <OPERATOR_AGE_PUBLIC_KEY> placeholder only.')
  }
}

$coreTemplatePath = Join-Path $Root 'compose/tt-core/.env.example'
if (Test-Path $coreTemplatePath) {
  $coreTemplateText = Get-Content $coreTemplatePath -Raw -Encoding UTF8
  if ($coreTemplateText -match '(?m)^\s*TT_MINIO_PASSWORD\s*=\s*$') {
    $hygieneIssues.Add('compose/tt-core/.env.example has empty TT_MINIO_PASSWORD (must be __GENERATE__).')
  }
  if ($coreTemplateText -match '(?m)^\s*TT_GRAFANA_PASSWORD\s*=\s*$') {
    $hygieneIssues.Add('compose/tt-core/.env.example has empty TT_GRAFANA_PASSWORD (must be __GENERATE__).')
  }
}

$mutableImageFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]
$coreCompose = Join-Path $Root 'compose/tt-core/docker-compose.yml'
if (Test-Path $coreCompose) {
  $mutableImageFiles.Add((Get-Item $coreCompose)) | Out-Null
}
$addonsDir = Join-Path $Root 'compose/tt-core/addons'
if (Test-Path $addonsDir) {
  foreach ($f in Get-ChildItem -Path $addonsDir -Filter '*.addon.yml' -File -ErrorAction SilentlyContinue) {
    if ($f.Name -eq '00-template.addon.yml') { continue }
    $mutableImageFiles.Add($f) | Out-Null
  }
}
foreach ($f in $mutableImageFiles) {
  $lines = Get-Content $f.FullName -Encoding UTF8
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ([string]$lines[$i] -match '^\s*image:\s*[^#\s]+:latest(\s|$)') {
      $hygieneIssues.Add("Mutable image tag in $($f.Name):$($i + 1) (:latest not allowed)")
    }
  }
}

$privateKeyExts = @('.pem', '.p12', '.pfx', '.key')
$privateFiles = Get-ChildItem -Path $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
  Where-Object { $privateKeyExts -contains $_.Extension.ToLowerInvariant() }
foreach ($f in $privateFiles) {
  $rel = $f.FullName.Replace($Root, '').TrimStart('\', '/').Replace('\', '/')
  $hygieneIssues.Add("Private key/certificate artifact detected: $rel")
}

$noiseFiles = Get-ChildItem -Path $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Extension -match '^\.(log|tmp|swp|bak)$' }
foreach ($f in $noiseFiles) {
  $rel = $f.FullName.Replace($Root, '').TrimStart('\', '/').Replace('\', '/')
  if ($rel -match '^compose/tt-core/volumes/') { continue }
  $hygieneIssues.Add("Debug/noise artifact detected: $rel")
}

if ($hygieneIssues.Count -gt 0) {
  Fail "Gate 17 FAIL - bundle hygiene violations found: $($hygieneIssues.Count)"
  foreach ($i in $hygieneIssues) {
    Write-Host "    -> $i" -ForegroundColor DarkRed
  }
} else {
  Pass 'Gate 17: no forbidden env/key/vcs/noise artifacts detected in bundle tree'
}

# -- GATE 18: backup contract integrity --
Section 'Gate 18 - Backup Contract Integrity'
$backupScriptPath = Join-Path $Root 'scripts-linux/backup.sh'
$restoreScriptPath = Join-Path $Root 'scripts-linux/restore.sh'
$verifyRestorePath = Join-Path $Root 'scripts-linux/verify-restore.sh'
if (!(Test-Path $backupScriptPath) -or !(Test-Path $restoreScriptPath) -or !(Test-Path $verifyRestorePath)) {
  Fail 'Gate 18 FAIL - backup/restore verification scripts missing'
} else {
  $backupScript = Get-Content $backupScriptPath -Raw -Encoding UTF8
  $restoreScript = Get-Content $restoreScriptPath -Raw -Encoding UTF8
  $verifyRestore = Get-Content $verifyRestorePath -Raw -Encoding UTF8

  if ($backupScript -notmatch 'checksums\.sha256') {
    Fail 'Gate 18 FAIL - backup.sh does not generate checksums.sha256'
  } else { Pass 'Gate 18: backup.sh uses checksums.sha256' }

  if ($backupScript -notmatch '\.dump\.enc' -or $backupScript -notmatch 'wordpress\.sql') {
    Fail 'Gate 18 FAIL - backup.sh does not cover encrypted dumps and wordpress.sql in the backup contract'
  } else { Pass 'Gate 18: backup.sh contract includes .dump.enc and wordpress.sql' }

  if ($restoreScript -notmatch 'checksums\.sha256' -or $restoreScript -notmatch '\.dump\.enc') {
    Fail 'Gate 18 FAIL - restore.sh is not aligned with checksums.sha256 / .dump.enc backup artifacts'
  } else { Pass 'Gate 18: restore.sh aligned with backup artifact names' }

  if ($verifyRestore -notmatch 'checksums\.sha256' -or
      $verifyRestore -notmatch '\.dump\.enc' -or
      $verifyRestore -notmatch 'pg_restore' -or
      $verifyRestore -notmatch 'postgres:16\.6-alpine') {
    Fail 'Gate 18 FAIL - verify-restore.sh is not aligned with the PostgreSQL backup verification contract'
  } else { Pass 'Gate 18: verify-restore.sh validates .dump/.dump.enc via disposable PostgreSQL restore' }

  if ($verifyRestore -notmatch 'wordpress\.sql' -or $verifyRestore -notmatch 'mariadb:11\.8\.6') {
    Fail 'Gate 18 FAIL - verify-restore.sh does not validate wordpress.sql via disposable MariaDB'
  } else { Pass 'Gate 18: verify-restore.sh validates wordpress.sql via disposable MariaDB' }
}

# -- GATE 19: image lock + bootstrap integrity --
Section 'Gate 19 - Image Lock And Bootstrap Integrity'
$imageLockPath = Join-Path (Split-Path $Root -Parent) 'release/image-inventory.lock.json'
if (!(Test-Path $imageLockPath)) {
  Fail 'Gate 19 FAIL - release/image-inventory.lock.json missing'
} else {
  try {
    $imageLock = Get-Content $imageLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$imageLock.lock_status -ne 'complete') {
      Fail "Gate 19 FAIL - image lock status is '$($imageLock.lock_status)' (expected 'complete')"
    } else { Pass 'Gate 19: image lock status is complete' }
    if ([int]$imageLock.unresolved_count -ne 0) {
      Fail "Gate 19 FAIL - unresolved_count is $($imageLock.unresolved_count) (expected 0)"
    } else { Pass 'Gate 19: unresolved_count=0' }

    $latestLockRefs = @($imageLock.images | Where-Object { [string]$_.source_tag -eq 'latest' })
    if ($latestLockRefs.Count -gt 0) {
      Fail "Gate 19 FAIL - image lock still contains :latest tag(s): $($latestLockRefs.Count)"
    } else { Pass 'Gate 19: no :latest tags in image lock' }

    $missingDigests = @($imageLock.images | Where-Object {
      [string]$_.digest_status -ne 'resolved' -or
      [string]::IsNullOrWhiteSpace([string]$_.resolved_digest)
    })
    if ($missingDigests.Count -gt 0) {
      Fail "Gate 19 FAIL - image lock contains unresolved digest entries: $($missingDigests.Count)"
    } else { Pass 'Gate 19: all image lock entries have resolved digests' }
  } catch {
    Fail "Gate 19 FAIL - image lock JSON parse error: $_"
  }
}

$sopsSetupPath = Join-Path $Root 'installer/lib/sops-setup.sh'
if (!(Test-Path $sopsSetupPath)) {
  Fail 'Gate 19 FAIL - installer/lib/sops-setup.sh missing'
} else {
  $sopsSetupText = Get-Content $sopsSetupPath -Raw -Encoding UTF8
  if ($sopsSetupText -notmatch 'verify_download_checksum') {
    Fail 'Gate 19 FAIL - sops-setup.sh does not verify downloaded artifacts before install'
  } else { Pass 'Gate 19: sops-setup.sh has checksum verification helper' }
  if ($sopsSetupText -notmatch 'SOPS_SHA256_' -or $sopsSetupText -notmatch 'AGE_SHA256_') {
    Fail 'Gate 19 FAIL - sops-setup.sh is missing embedded SHA256 maps for SOPS/age artifacts'
  } else { Pass 'Gate 19: sops-setup.sh contains embedded SHA256 maps' }
  if ($sopsSetupText -notmatch 'Unsupported arch' -or $sopsSetupText -notmatch 'install manually') {
    Fail 'Gate 19 FAIL - sops-setup.sh does not fail closed with manual-install guidance for unsupported architectures'
  } else { Pass 'Gate 19: unsupported architectures fail closed with manual guidance' }
}
Write-Host '═══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
if ($script:FailCount -gt 0) {
  Write-Host "  FAILED — $($script:FailCount) failure(s), $($script:WarnCount) warning(s), $($script:PassCount) passed" -ForegroundColor Red
  Write-Host '  Fix all failures before client delivery.' -ForegroundColor Red
} elseif ($script:WarnCount -gt 0) {
  Write-Host "  PASSED with warnings — $($script:WarnCount) warning(s), $($script:PassCount) passed" -ForegroundColor Yellow
} else {
  Write-Host "  PASSED — $($script:PassCount) checks OK, 0 failures, 0 warnings" -ForegroundColor Green
}
Write-Host '═══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

if ($script:FailCount -gt 0) { exit 1 } else { exit 0 }






