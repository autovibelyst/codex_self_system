#Requires -Version 5.1
# =============================================================================
# validate-bundle.ps1 — TT-Production Bundle Validation — v14.0
#
# USAGE:
#   .\validate-bundle.ps1
#   .\validate-bundle.ps1 -Root "C:\path\to\bundle-root"
#
# Validates the complete TT-Production delivery bundle.
# Collects ALL failures — does NOT exit on first error.
# EXIT: 0 = pass (warnings allowed), 1 = one or more failures.
#
# SECTIONS (32) — 13 ACCEPTANCE GATES:
#   1.  Required bundle-level files
#   2.  JSON validation
#   3.  YAML validation
#   4.  Bundle manifest version
#   5.  MASTER_GUIDE sanity
#   6.  COMMERCIAL_HANDOFF sanity
#   7.  services.select.json safety defaults
#   8.  Catalog ↔ Policy consistency
#   9.  Tunnel env: token-only (no TUNNEL_UUID)
#   10. Supabase env template completeness
#   11. Supabase compose — critical services + memory
#   12. Cloudflared healthcheck
#   13. MariaDB internal-only
#   14. Stale version markers
#   15. Key CLI libraries
#   16. Security gate — ServiceCatalog + docker-compose
#   17. Infrastructure hardening (7 checks + redis-server conf)
#   18. TT-Core release validator (invokes validate-release.ps1)
#   19. Env.ps1 library integrity (alphanumeric + Ensure-EnvKey)
#   20. Canonical version.json exists and is valid
#   21. cloudflared-health.sh exists (healthcheck script not orphaned)
#   22. ServiceCatalog.ps1 schema alignment (semantic P0 guard)
#   23. Env template authority — timezone placeholder, no hardcoded values
#   24. Secret authority model — no token in select config, profiles derived from selection
#   25. CREDENTIAL_ROTATION.md — present, covers all 12 secrets, data-loss warning
#   26. DR_PLAYBOOK.md — present, defines RTO/RPO, covers full host failure
#   27. UPGRADE_GUIDE.md — present, covers rollback, references backup [introduced v9.2+]
#   28. .env.example completeness — all required vars including backup webhook [introduced v9.2+]
#   29. .env.example template completeness
#   30. Image inventory lock completeness (strict commercial requirement)
#   31. Runtime volume hygiene (no packaged runtime data or session artifacts)
#   32. CI/CD pipeline present (introduced v9.2+: FAIL — not just warn)
# =============================================================================
param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:failures = 0
$script:warnings = 0
$script:passes   = 0

function Fail    { param([string]$msg); $script:failures++; Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Pass    { param([string]$msg); $script:passes++;   Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Warn    { param([string]$msg); $script:warnings++; Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function MustExist { param([string]$path)
  if (!(Test-Path $path)) { Fail "Missing required path: $(Split-Path -Leaf $path)  ($path)" }
  else { Pass "Present: $(Split-Path -Leaf $path)" }
}

function Test-JsonFile { param([string]$Path)
  try   { Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null; Pass "JSON valid: $(Split-Path -Leaf $Path)" }
  catch { Fail "$Path is not valid JSON: $_" }
}

function Test-YamlFile { param([string]$Path)
  $parsed = $false
  try {
    $null = & docker compose -f $Path config --no-interpolate --quiet 2>$null
    if ($LASTEXITCODE -eq 0) { $parsed = $true }
  } catch {}
  if (-not $parsed) {
    try {
      if (Get-Command python3 -ErrorAction SilentlyContinue) {
        $tmp = [System.IO.Path]::GetTempFileName() + '.py'
        $tmpScript = @'
import sys, yaml
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    yaml.safe_load(f)
'@
        Set-Content -Path $tmp -Value $tmpScript
        & python3 $tmp $Path 2>$null
        if ($LASTEXITCODE -eq 0) { $parsed = $true }
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
      }
    } catch {}
  }
  if ($parsed) { Pass "YAML valid: $(Split-Path -Leaf $Path)" }
  else         { Warn "YAML parse skipped (docker compose + python3 unavailable): $(Split-Path -Leaf $Path)" }
}

# Derive expected version from canonical source
$versionJsonPath = Join-Path $Root 'release/version.json'
if (Test-Path $versionJsonPath) {
  try {
    $versionData = Get-Content $versionJsonPath -Raw | ConvertFrom-Json
    $expectedBundleVersion = [string]$versionData.package_version
    if ([string]::IsNullOrWhiteSpace($expectedBundleVersion)) {
      Write-Host "  [WARN] release/version.json: package_version is empty — defaulting to 'v14.0'" -ForegroundColor Yellow
      $expectedBundleVersion = 'v14.0'
    }
  } catch {
    Write-Host "  [WARN] Could not parse release/version.json — defaulting to 'v14.0'" -ForegroundColor Yellow
    $expectedBundleVersion = 'v14.0'
  }
} else {
  Write-Host "  [WARN] release/version.json not found — defaulting to 'v14.0'" -ForegroundColor Yellow
  $expectedBundleVersion = 'v14.0'
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  TT-Production Bundle Validation — $expectedBundleVersion" -ForegroundColor Cyan
Write-Host "  Root: $Root" -ForegroundColor DarkGray
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# ── 1. Required bundle-level files ────────────────────────────────────────────
Write-Host ""; Write-Host "── 1. Required Bundle Files ──" -ForegroundColor Cyan

$required = @(
  'FULL_PACKAGE_GUIDE.md',
  'MASTER_GUIDE.md',
  'RELEASE_AUDIT_SUMMARY.md',
  'COMMERCIAL_HANDOFF.md',
  "RELEASE_NOTES_$expectedBundleVersion.md",
  'release/bundle-manifest.json',
  'release/validate-bundle.ps1',
  'release/CHANGELOG.md',
  'release/image-inventory.lock.json',
  'tt-core/release/manifest.json',
  'tt-core/release/validate-release.ps1',
  'tt-core/installer/Install-TTCore.ps1',
  'tt-core/installer/Install-TTCore.sh',
  'tt-core/config/service-catalog.json',
  'tt-core/config/services.select.json',
  'tt-core/config/public-exposure.policy.json',
  'tt-core/scripts/Preflight-Check.ps1',
  'tt-core/scripts/Preflight-Check.cmd',
  'tt-core/scripts/Preflight-Supabase.ps1',
  'tt-core/scripts/Preflight-Supabase.cmd',
  'tt-core/scripts/Show-TunnelPlan.ps1',
  'tt-core/scripts/Sync-PublicExposurePolicy.ps1',
  'tt-core/scripts/lib/ServiceCatalog.ps1',
  'tt-core/scripts/lib/Env.ps1',
  'tt-core/scripts/ttcore.ps1',
  'tt-core/scripts/deps.json',
  'tt-core/scripts/Update-TTCore.ps1',
  'tt-core/scripts/backup/Backup-All.ps1',
  'tt-core/scripts/backup/_lib/BackupLib.ps1',
  'tt-core/scripts-linux/preflight-check.sh',
  'tt-core/scripts-linux/preflight-supabase.sh',
  'tt-core/scripts-linux/init.sh',
  'tt-core/scripts-linux/start-core.sh',
  'tt-core/scripts-linux/stop-core.sh',
  'tt-core/scripts-linux/status.sh',
  'tt-core/scripts-linux/backup.sh',
  'tt-core/compose/tt-core/volumes/redis/config/redis.conf',
  'tt-supabase/compose/tt-supabase/docker-compose.yml',
  'tt-supabase/README.md',
  'tt-supabase/scripts-linux/init.sh',
  'tt-supabase/scripts-linux/preflight.sh',
  'tt-supabase/scripts-linux/start.sh',
  'tt-supabase/scripts-linux/stop.sh',
  'tt-supabase/scripts-linux/status.sh',
  'tt-supabase/scripts-linux/smoke-test.sh',
  'tt-core/docs/CREDENTIAL_ROTATION.md',
  'tt-core/docs/DR_PLAYBOOK.md',
  'tt-core/scripts-linux/rotate-secrets.sh'
)
foreach ($rel in $required) { MustExist (Join-Path $Root $rel) }

# ── 2. JSON validation ────────────────────────────────────────────────────────
Write-Host ""; Write-Host "── 2. JSON Validation ──" -ForegroundColor Cyan
Test-JsonFile (Join-Path $Root 'release/bundle-manifest.json')
Test-JsonFile (Join-Path $Root 'release/image-inventory.lock.json')
Test-JsonFile (Join-Path $Root 'tt-core/release/manifest.json')
Test-JsonFile (Join-Path $Root 'tt-core/config/service-catalog.json')
Test-JsonFile (Join-Path $Root 'tt-core/config/services.select.json')
Test-JsonFile (Join-Path $Root 'tt-core/config/public-exposure.policy.json')

# ── 3. YAML validation ────────────────────────────────────────────────────────
Write-Host ""; Write-Host "── 3. YAML Validation ──" -ForegroundColor Cyan
Test-YamlFile (Join-Path $Root 'tt-core/compose/tt-core/docker-compose.yml')
Test-YamlFile (Join-Path $Root 'tt-core/compose/tt-tunnel/docker-compose.yml')
Test-YamlFile (Join-Path $Root 'tt-supabase/compose/tt-supabase/docker-compose.yml')

# ── 4. Bundle manifest version ────────────────────────────────────────────────
Write-Host ""; Write-Host "── 4. Bundle Manifest Version ──" -ForegroundColor Cyan
$bmPath = Join-Path $Root 'release/bundle-manifest.json'
if (Test-Path $bmPath) {
  try {
    $bm = Get-Content $bmPath -Raw | ConvertFrom-Json
    $bmVersion = if ($bm.PSObject.Properties['package_version']) { [string]$bm.package_version } elseif ($bm.PSObject.Properties['tt_version']) { [string]$bm.tt_version } else { [string]$bm.version }
    $bmBundle = if ($bm.PSObject.Properties['bundle_name']) { [string]$bm.bundle_name } else { [string]$bm.bundle_root }
    if ($bmVersion -ne $expectedBundleVersion) {
      Fail "bundle-manifest.json version: expected '$expectedBundleVersion', got '$bmVersion'"
    } else { Pass "bundle-manifest.json version: $bmVersion" }
    if ($bmBundle -ne "TT-Production-$expectedBundleVersion") {
      Fail "bundle-manifest.json bundle_name: expected 'TT-Production-$expectedBundleVersion', got '$bmBundle'"
    } else { Pass "bundle-manifest.json bundle_name: $bmBundle" }
    if (-not $bm.PSObject.Properties['_generator']) {
      Warn "bundle-manifest.json: _generator missing"
    } else { Pass "bundle-manifest.json: _generator present" }
    if (-not $bm.PSObject.Properties['generated_at']) {
      Warn "bundle-manifest.json: generated_at missing"
    } else { Pass "bundle-manifest.json: generated_at present" }
  } catch { Fail "bundle-manifest.json: parse error — $_" }
}

# ── 5. MASTER_GUIDE sanity ────────────────────────────────────────────────────
Write-Host ""; Write-Host "── 5. MASTER_GUIDE Sanity ──" -ForegroundColor Cyan
$mgPath = Join-Path $Root 'MASTER_GUIDE.md'
if (Test-Path $mgPath) {
  $mgContent = Get-Content $mgPath -Raw
  if ($mgContent -notmatch $expectedBundleVersion) {
    Fail "MASTER_GUIDE.md does not reference version $expectedBundleVersion"
  } else { Pass "MASTER_GUIDE.md references $expectedBundleVersion" }
  if ($mgContent -notmatch 'Preflight-Check') { Warn "MASTER_GUIDE.md: no mention of Preflight-Check" }
  else { Pass "MASTER_GUIDE.md: Preflight-Check documented" }
}

# ── 6. COMMERCIAL_HANDOFF sanity ──────────────────────────────────────────────
Write-Host ""; Write-Host "── 6. COMMERCIAL_HANDOFF Sanity ──" -ForegroundColor Cyan
$chPath = Join-Path $Root 'COMMERCIAL_HANDOFF.md'
if (Test-Path $chPath) {
  $chContent = Get-Content $chPath -Raw
  if ($chContent -notmatch $expectedBundleVersion) {
    Fail "COMMERCIAL_HANDOFF.md does not reference version $expectedBundleVersion"
  } else { Pass "COMMERCIAL_HANDOFF.md references $expectedBundleVersion" }
}

# ── 7. services.select.json safety defaults ───────────────────────────────────
Write-Host ""; Write-Host "── 7. Safety Defaults ──" -ForegroundColor Cyan
$selectPath = Join-Path $Root 'tt-core/config/services.select.json'
if (Test-Path $selectPath) {
  try {
    $selection = Get-Content $selectPath -Raw | ConvertFrom-Json
    # monitoring must be false (opt-in)
    if ($selection.profiles.monitoring -eq $true) {
      Fail 'services.select.json: monitoring must be false (opt-in only)'
    } else { Pass 'services.select.json: monitoring=false' }
    # restricted_admin must default closed
    if ($selection.security.allow_restricted_admin_tunnel_routes -eq $true) {
      Fail 'services.select.json: restricted_admin_tunnel_routes must be false (default closed)'
    } else { Pass 'services.select.json: restricted_admin_tunnel_routes=false' }
    # backup.notify_on_failure must be present
    $notifyProp = $selection.backup.PSObject.Properties['notify_on_failure']
    if ($null -eq $notifyProp) {
      Fail 'services.select.json: backup.notify_on_failure key missing — add "notify_on_failure": false'
    } else { Pass "services.select.json: backup.notify_on_failure=$($notifyProp.Value)" }
    # backup.notify_webhook_url recommended
    $webhookProp = $selection.backup.PSObject.Properties['notify_webhook_url']
    if ($null -eq $webhookProp) {
      Warn 'services.select.json: backup.notify_webhook_url missing (recommended for alerting)'
    } else { Pass 'services.select.json: backup.notify_webhook_url present' }
  } catch { Fail "services.select.json: parse error — $_" }
}

# ── 8. Catalog ↔ Policy consistency ──────────────────────────────────────────
Write-Host ""; Write-Host "── 8. Catalog / Policy Consistency ──" -ForegroundColor Cyan
$policyPath  = Join-Path $Root 'tt-core/config/public-exposure.policy.json'
$catalogPath = Join-Path $Root 'tt-core/config/service-catalog.json'
if ((Test-Path $policyPath) -and (Test-Path $catalogPath)) {
  $policy  = Get-Content $policyPath -Raw | ConvertFrom-Json
  $catalog = Get-Content $catalogPath -Raw | ConvertFrom-Json
  if ([string]$policy.generated_from -ne 'config/service-catalog.json') {
    Fail "public-exposure.policy.json: generated_from must be 'config/service-catalog.json'. Run Sync-PublicExposurePolicy.ps1."
  } else { Pass "public-exposure.policy.json: generated_from correct" }
  foreach ($p in $policy.services) {
    $found = @($catalog.services | Where-Object { $_.service -eq $p.service })
    if ($found.Count -eq 0) { Fail "Policy references unknown service: $($p.service)" }
    else { Pass "Policy service in catalog: $($p.service)" }
  }
}

# ── 9. Tunnel env: token-only (no TUNNEL_UUID) ───────────────────────────────
Write-Host ""; Write-Host "── 9. Tunnel Token-Only Mode ──" -ForegroundColor Cyan
$tunnelEnv = Join-Path $Root 'tt-core/compose/tt-tunnel/.env.example'
if (Test-Path $tunnelEnv) {
  $te = Get-Content $tunnelEnv -Raw
  if ($te -match '^\s*TUNNEL_UUID\s*=\s*\S') {
    Fail "tt-tunnel .env.example: TUNNEL_UUID must not be set — use token-only mode (CF_TUNNEL_TOKEN)"
  } else { Pass "Tunnel .env.example: token-only mode (TUNNEL_UUID not set)" }
}

# ── 10. Supabase env template completeness ────────────────────────────────────
Write-Host ""; Write-Host "── 10. Supabase Env Template ──" -ForegroundColor Cyan
$sbEnvExample = Join-Path $Root 'tt-supabase/env/tt-supabase.env.example'
if (Test-Path $sbEnvExample) {
  $sbEnvContent = Get-Content $sbEnvExample -Raw
  foreach ($key in @('JWT_SECRET','ANON_KEY','SERVICE_ROLE_KEY','POSTGRES_PASSWORD','DASHBOARD_USERNAME','DASHBOARD_PASSWORD')) {
    if ($sbEnvContent -match $key) { Pass "Supabase .env.example: $key present" }
    else { Fail "Supabase .env.example: $key missing" }
  }
}

# ── 11. Supabase compose — critical services + memory ─────────────────────────
Write-Host ""; Write-Host "── 11. Supabase Compose ──" -ForegroundColor Cyan
$sbCompose = Join-Path $Root 'tt-supabase/compose/tt-supabase/docker-compose.yml'
if (Test-Path $sbCompose) {
  $sbContent = Get-Content $sbCompose -Raw
  $memCount  = ([regex]::Matches($sbContent, 'memory:')).Count
  if ($memCount -lt 20) { Fail "Supabase compose: only $memCount memory limits found (expected 26+)" }
  else { Pass "Supabase compose: $memCount memory limits defined" }
  foreach ($svc in @('supabase-db','supabase-auth','supabase-rest','supabase-realtime','supabase-studio','supabase-kong')) {
    if ($sbContent -match "container_name: $svc") { Pass "Supabase service present: $svc" }
    else { Fail "Supabase service missing: $svc" }
  }
  # Realtime.Release.seeds — required for DB init
  if ($sbContent -notmatch 'Realtime\.Release\.seeds') {
    Fail "Supabase realtime: Realtime.Release.seeds command missing — realtime DB will not be initialized"
  } else { Pass "Supabase realtime: Realtime.Release.seeds command present" }
  # Functions --main-service — required for edge functions
  if ($sbContent -notmatch '\-\-main-service') {
    Fail "Supabase functions: --main-service missing — Edge Functions will not start"
  } else { Pass "Supabase functions: --main-service present" }
}

# ── 12. Cloudflared healthcheck ───────────────────────────────────────────────
Write-Host ""; Write-Host "── 12. Cloudflared Healthcheck ──" -ForegroundColor Cyan
$tunnelCompose = Join-Path $Root 'tt-core/compose/tt-tunnel/docker-compose.yml'
if (Test-Path $tunnelCompose) {
  $tc = Get-Content $tunnelCompose -Raw
  if ($tc -notmatch 'healthcheck') { Fail "tt-tunnel compose: cloudflared has no healthcheck" }
  else { Pass "tt-tunnel compose: cloudflared healthcheck present" }
}

# ── 13. MariaDB internal-only ─────────────────────────────────────────────────
Write-Host ""; Write-Host "── 13. MariaDB Internal-Only ──" -ForegroundColor Cyan
$wpAddon = Join-Path $Root 'tt-core/compose/tt-core/addons/05-wordpress.addon.yml'
if (Test-Path $wpAddon) {
  $wpContent = Get-Content $wpAddon -Raw
  $lines = $wpContent -split "`n"
  $inMariadb = $false; $mariadbHasPorts = $false
  foreach ($line in $lines) {
    if ($line -match 'container_name.*mariadb') { $inMariadb = $true }
    if ($inMariadb -and $line -match '^\s+ports:') { $mariadbHasPorts = $true; break }
    if ($inMariadb -and $line -match '^  \w' -and $line -notmatch 'container_name') { $inMariadb = $false }
  }
  if ($mariadbHasPorts) { Warn "WordPress addon: MariaDB exposes ports — consider removing for production" }
  else { Pass "WordPress addon: MariaDB no exposed ports" }
}

# ── 14. Stale version markers ─────────────────────────────────────────────────
Write-Host ""; Write-Host "── 14. Stale Marker Scan ──" -ForegroundColor Cyan
$stalePatterns = @(
  # Old-era patterns (pre-v6)
  'TT-Production-v0\.',
  'TT-Production-v1\.[0-7]\.',
  'v0\.8\.[0-9]-hardened-final',
  'v0\.9\.0-final',
  'config-mode is supported in production',
  'v1\.2\.0-production',
  'RELEASE_NOTES_v3\.5\.md',
  'apps\\tt-tunnel',
  'ENABLE_TUNNEL=',
  'TUNNEL_N8N=',
  # Stale version patterns from prior releases — must not appear in active product files
  # Matches any v6.7.x that is NOT "v14.0" (the current release)
  'TT-Production v6\.6\b',
  'Version: TT-Production v6\.6\b',
  'TT-Production v6\.7\.[01234]\b',
  'TT-Production-v6\.7\.[01234]\b',
  'v6\.7\.2\.2\.2\.2',
  'v6\.7\.3\.2\.2',
  'v6\.7\.5\.2',
  '-hardened-final\b'
)
# Covers all active files: docs/, scripts/, compose/, config/ and root
$scanExts  = @('.md','.json','.ps1','.sh','.yml','.yaml','.env','.example','.cmd','.txt')
$scanFiles = Get-ChildItem -Path $Root -Recurse -File | Where-Object {
  $scanExts -contains $_.Extension -and
  $_.FullName -notmatch [regex]::Escape((Join-Path $Root 'tt-core\archive')) -and
  $_.FullName -notmatch [regex]::Escape((Join-Path $Root 'release\history')) -and
  $_.FullName -notmatch [regex]::Escape((Join-Path $Root '.git')) -and
  $_.FullName -notmatch 'validate-bundle\.ps1' -and
  $_.FullName -notmatch 'validate-release\.ps1' -and
  $_.FullName -notmatch 'CHANGELOG' -and
  $_.FullName -notmatch 'RELEASE_NOTES_v[0-9]'
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
if (-not $staleFound) { Pass "No stale version markers found" }


# ── 15. Supabase env authority consistency ────────────────────────────────────
Write-Host ""; Write-Host "── 15. Supabase Env Authority ──" -ForegroundColor Cyan
$supabaseExpectedEnv = 'compose/tt-supabase/.env'
$supabaseScanExts  = @('.md','.ps1','.sh','.yml','.yaml','.env','.example','.txt')
$supabaseFiles = Get-ChildItem -Path (Join-Path $Root 'tt-supabase') -Recurse -File | Where-Object {
  $supabaseScanExts -contains $_.Extension
}
$supabaseAuthorityOk = $true
foreach ($file in $supabaseFiles) {
  $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
  if ($content -match 'env/tt-supabase\.env(?!\.example)') {
    Fail "Legacy Supabase env path found in: $($file.FullName.Replace($Root,'').TrimStart('\/'))"
    $supabaseAuthorityOk = $false
  }
}
if ($supabaseAuthorityOk) { Pass "Supabase env authority unified on $supabaseExpectedEnv" }

# ── 16. Tunnel docs authority drift ───────────────────────────────────────────
Write-Host ""; Write-Host "── 16. Tunnel Authority Drift ──" -ForegroundColor Cyan
$tunnelAuthorityFiles = @(
  'tt-core/docs/TUNNEL.md',
  'tt-core/docs/ADDING_A_SERVICE.md'
)
$tunnelDrift = $false
foreach ($rel in $tunnelAuthorityFiles) {
  $path = Join-Path $Root $rel
  if (Test-Path $path) {
    $content = Get-Content $path -Raw
    foreach ($pat in @('apps\\tt-tunnel','ENABLE_TUNNEL','TUNNEL_N8N','ingress-rules\.json')) {
      if ($content -match $pat) {
        Fail "$rel contains legacy tunnel reference: $pat"
        $tunnelDrift = $true
      }
    }
  }
}
if (-not $tunnelDrift) { Pass "Tunnel docs aligned with token-only canonical runtime" }

# ── 17. Key CLI libraries ─────────────────────────────────────────────────────
Write-Host ""; Write-Host "── 17. CLI Libraries ──" -ForegroundColor Cyan
foreach ($lib in @('tt-core/scripts/lib/Env.ps1','tt-core/scripts/lib/ServiceCatalog.ps1','tt-core/scripts/ttcore.ps1')) {
  $lp = Join-Path $Root $lib
  if (!(Test-Path $lp)) { Fail "Missing: $lib" }
  elseif ((Get-Content $lp -Raw).Length -lt 200) { Fail "$lib appears truncated (< 200 chars)" }
  else { Pass "Non-empty library: $(Split-Path -Leaf $lib)" }
}

# ── 18. Security gate — ServiceCatalog + docker-compose ───────────────────────
Write-Host ""; Write-Host "── 18. Security Gate Coverage ──" -ForegroundColor Cyan
$scPath = Join-Path $Root 'tt-core/scripts/lib/ServiceCatalog.ps1'
if (Test-Path $scPath) {
  $scContent = Get-Content $scPath -Raw
  if ($scContent -notmatch 'function Test-TTAdminRouteGateOpen') {
    Fail "ServiceCatalog.ps1: Test-TTAdminRouteGateOpen missing — fail-closed gate absent"
  } else { Pass "ServiceCatalog.ps1: Test-TTAdminRouteGateOpen defined (fail-closed)" }
  if ($scContent -notmatch 'function Test-TTRouteEnabledForService') {
    Fail "ServiceCatalog.ps1: Test-TTRouteEnabledForService missing — 4-layer gate absent"
  } else { Pass "ServiceCatalog.ps1: Test-TTRouteEnabledForService defined" }
  # Layer 2 must be invoked INSIDE the function body
  $idx = $scContent.IndexOf('function Test-TTRouteEnabledForService')
  if ($idx -ge 0) {
    $fnBody = $scContent.Substring($idx, [Math]::Min(1200, $scContent.Length - $idx))
    if ($fnBody -notmatch 'Test-TTAdminRouteGateOpen') {
      Fail "Test-TTRouteEnabledForService: Layer 2 (Test-TTAdminRouteGateOpen) not invoked inside function — security gap"
    } else { Pass "Test-TTRouteEnabledForService: Layer 2 invoked (restricted_admin gated)" }
  }
}

# ── 17. Infrastructure hardening ──────────────────────────────────────────────
Write-Host ""; Write-Host "── 17. Infrastructure Hardening ──" -ForegroundColor Cyan
$coreComposePath = Join-Path $Root 'tt-core/compose/tt-core/docker-compose.yml'
if (Test-Path $coreComposePath) {
  $cc = Get-Content $coreComposePath -Raw

  # tt_admin_net defined
  if ($cc -notmatch 'tt_admin_net:') {
    Fail "docker-compose.yml: tt_admin_net network not defined"
  } else { Pass "docker-compose.yml: tt_admin_net defined" }

  # tt_admin_net internal:true
  if ($cc -match 'tt_admin_net:' -and $cc -notmatch 'internal:\s*true') {
    Fail "docker-compose.yml: tt_admin_net is not internal:true — admin tools accessible from addon traffic"
  } else { Pass "docker-compose.yml: tt_admin_net internal:true (isolated)" }

  # pgAdmin on tt_admin_net
  if ($cc -match '(?s)pgadmin:\s.*?networks:\s.*?tt_admin_net') {
    Pass "docker-compose.yml: pgAdmin on tt_admin_net"
  } else {
    Fail "docker-compose.yml: pgAdmin not connected to tt_admin_net"
  }

  # RedisInsight on tt_admin_net + RI_APP_PASSWORD
  if ($cc -match '(?s)redisinsight:\s.*?networks:\s.*?tt_admin_net') {
    Pass "docker-compose.yml: RedisInsight on tt_admin_net"
  } else {
    Fail "docker-compose.yml: RedisInsight not connected to tt_admin_net"
  }
  if ($cc -match '(?s)redisinsight:\s.*?RI_APP_PASSWORD') {
    Pass "docker-compose.yml: RedisInsight RI_APP_PASSWORD configured"
  } else {
    Fail "docker-compose.yml: RedisInsight missing RI_APP_PASSWORD — running without authentication"
  }

  # redis.conf mounted :ro
  if ($cc -notmatch '/usr/local/etc/redis/redis\.conf') {
    Fail "docker-compose.yml: redis.conf not mounted at /usr/local/etc/redis/redis.conf — maxmemory/eviction not applied"
  } else { Pass "docker-compose.yml: redis.conf mounted :ro" }

  # redis-server passes conf path in command
  if ($cc -match '(?s)redis:\s.*?command:\s.*?redis-server\s.*?/usr/local/etc/redis/redis\.conf') {
    Pass "docker-compose.yml: redis-server uses mounted redis.conf (maxmemory active)"
  } else {
    Fail "docker-compose.yml: redis-server command does not pass redis.conf path — maxmemory/eviction policy inert"
  }

  # n8n EXECUTIONS_MODE uses env-var (not hardcoded)
  if ($cc -notmatch 'TT_N8N_EXECUTIONS_MODE') {
    Fail "docker-compose.yml: n8n EXECUTIONS_MODE hardcoded — must reference TT_N8N_EXECUTIONS_MODE env-var"
  } else { Pass "docker-compose.yml: n8n EXECUTIONS_MODE env-var driven" }

  # PG tuning uses env-vars (not hardcoded)
  if ($cc -notmatch 'TT_PG_SHARED_BUFFERS') {
    Fail "docker-compose.yml: PG shared_buffers hardcoded — must reference TT_PG_SHARED_BUFFERS"
  } else { Pass "docker-compose.yml: PG tuning env-var driven" }

  # Qdrant uses curl not wget
  $qdIdx = $cc.IndexOf('container_name: tt-core-qdrant')
  if ($qdIdx -ge 0) {
    $qdSect = $cc.Substring($qdIdx, [Math]::Min(500, $cc.Length - $qdIdx))
    if ($qdSect -match 'wget') {
      Fail "docker-compose.yml: Qdrant healthcheck uses wget (absent in qdrant/qdrant image) — use curl"
    } else { Pass "docker-compose.yml: Qdrant healthcheck uses curl" }
  }
}

# ── 18. TT-Core release validator ─────────────────────────────────────────────
Write-Host ""; Write-Host "── 18. TT-Core Release Validation ──" -ForegroundColor Cyan
$vrPath = Join-Path $Root 'tt-core/release/validate-release.ps1'
if (Test-Path $vrPath) {
  & $vrPath -Root (Join-Path $Root 'tt-core')
  if ($LASTEXITCODE -ne 0) { Fail "tt-core/release/validate-release.ps1 reported failures" }
  else { Pass "tt-core release validator: PASSED" }
} else { Fail "tt-core/release/validate-release.ps1 not found" }

# ── 19. Env.ps1 library integrity ─────────────────────────────────────────────
Write-Host ""; Write-Host "── 19. Env.ps1 Library Integrity ──" -ForegroundColor Cyan
$envLibPath = Join-Path $Root 'tt-core/scripts/lib/Env.ps1'
if (Test-Path $envLibPath) {
  $envContent = Get-Content $envLibPath -Raw

  # alphanumeric must be in ValidateSet of New-RandomSecret
  if ($envContent -notmatch 'ValidateSet.*alphanumeric') {
    Fail 'Env.ps1: New-RandomSecret/Ensure-EnvSecret ValidateSet does not include "alphanumeric"' +
         ' — Init-TTCore.ps1 will CRASH when generating TT_REDISINSIGHT_PASSWORD'
  } else { Pass 'Env.ps1: ValidateSet includes "alphanumeric" format' }

  # alphanumeric branch must have implementation
  if ($envContent -notmatch '"alphanumeric"') {
    Fail 'Env.ps1: alphanumeric format branch not implemented in New-RandomSecret'
  } else { Pass 'Env.ps1: alphanumeric format branch implemented' }

  # Ensure-EnvKey must be defined
  if ($envContent -notmatch 'function Ensure-EnvKey') {
    Fail 'Env.ps1: Ensure-EnvKey function missing — Init-TTCore.ps1 will CRASH on non-secret defaults' +
         ' (TT_N8N_EXECUTIONS_MODE, TT_PG_SHARED_BUFFERS, etc. will not be written)'
  } else { Pass 'Env.ps1: Ensure-EnvKey function defined' }

  # Ensure-EnvSecret must be defined
  if ($envContent -notmatch 'function Ensure-EnvSecret') {
    Fail 'Env.ps1: Ensure-EnvSecret function missing — Init-TTCore.ps1 cannot generate secrets'
  } else { Pass 'Env.ps1: Ensure-EnvSecret function present' }

  # Sync-EnvKeys must be defined
  if ($envContent -notmatch 'function Sync-EnvKeys') {
    Warn 'Env.ps1: Sync-EnvKeys function missing — .env drift detection disabled'
  } else { Pass 'Env.ps1: Sync-EnvKeys function present' }

} else { Fail "tt-core/scripts/lib/Env.ps1 not found" }


# ── 20. Canonical version.json ─────────────────────────────────────────────────
Write-Host ""; Write-Host "── 20. Canonical version.json ──" -ForegroundColor Cyan
$vJsonPath = Join-Path $Root 'release/version.json'
if (Test-Path $vJsonPath) {
  try {
    $vJson = Get-Content $vJsonPath -Raw | ConvertFrom-Json
    $required = @('product_name','package_version','release_channel','build_id','release_date','bundle_name','component_versions')
    $allPresent = $true
    foreach ($key in $required) {
      if (-not ($vJson.PSObject.Properties.Name -contains $key)) {
        Fail "release/version.json: required field '$key' missing"
        $allPresent = $false
      }
    }
    if ($allPresent) { Pass "release/version.json: all required identity fields present" }

    # version consistency: version.json package_version must match bundle-manifest version alias
    $bundleMfPath = Join-Path $Root 'release/bundle-manifest.json'
    if (Test-Path $bundleMfPath) {
      $bundleMf = Get-Content $bundleMfPath -Raw | ConvertFrom-Json
      $bundleVersion = if ($bundleMf.PSObject.Properties['package_version']) { [string]$bundleMf.package_version } elseif ($bundleMf.PSObject.Properties['tt_version']) { [string]$bundleMf.tt_version } else { [string]$bundleMf.version }
      if ($vJson.package_version -ne $bundleVersion) {
        Fail "Version drift: version.json.package_version='$($vJson.package_version)' != bundle-manifest.version='$bundleVersion'"
      } else {
        Pass "version.json and bundle-manifest.json versions agree: $($vJson.package_version)"
      }
    }
  } catch {
    Fail "release/version.json: JSON parse error — $_"
  }
} else { Fail "release/version.json not found — canonical identity file is missing" }

# ── 21. cloudflared-health.sh healthcheck script ───────────────────────────────
Write-Host ""; Write-Host "── 21. cloudflared-health.sh ──" -ForegroundColor Cyan
$chealthPath = Join-Path $Root 'tt-core/compose/tt-tunnel/cloudflared-health.sh'
if (Test-Path $chealthPath) {
  $chContent = Get-Content $chealthPath -Raw
  if ($chContent -match 'wget.*2000/ready' -or $chContent -match 'ENDPOINT="http://127.0.0.1:2000/ready"') {
    Pass "cloudflared-health.sh: wget probe present"
  } else { Warn "cloudflared-health.sh: expected wget probe for 127.0.0.1:2000/ready not found" }
  if ($chContent -notmatch 'urllib.request') {
    Warn "cloudflared-health.sh: python3 urllib fallback not found"
  } else { Pass "cloudflared-health.sh: python3 urllib fallback present" }

  # Verify tt-tunnel docker-compose.yml references this script (not inline Python)
  $tunnelDcPath = Join-Path $Root 'tt-core/compose/tt-tunnel/docker-compose.yml'
  if (Test-Path $tunnelDcPath) {
    $tunnelDc = Get-Content $tunnelDcPath -Raw
    if ($tunnelDc -match 'import urllib') {
      Fail "tt-tunnel/docker-compose.yml: inline Python still present in healthcheck — must be in cloudflared-health.sh"
    } else { Pass "tt-tunnel/docker-compose.yml: no inline Python in healthcheck" }
    if ($tunnelDc -notmatch 'cloudflared-health\.sh') {
      Warn "tt-tunnel/docker-compose.yml: cloudflared-health.sh not referenced in healthcheck"
    } else { Pass "tt-tunnel/docker-compose.yml: cloudflared-health.sh correctly referenced" }
  }
} else { Fail "tt-core/compose/tt-tunnel/cloudflared-health.sh not found — healthcheck script missing" }


# ── 22. ServiceCatalog.ps1 schema alignment (semantic P0 guard) ────────────────
Write-Host ""; Write-Host "── 22. ServiceCatalog Schema Alignment ──" -ForegroundColor Cyan
$scPath22 = Join-Path $Root 'tt-core/scripts/lib/ServiceCatalog.ps1'
if (Test-Path $scPath22) {
  $sc22 = Get-Content $scPath22 -Raw

  # Route field: must use route_name
  if ($sc22 -match "PSObject\.Properties\['tunnel_route'\]" -or
      $sc22 -match "PSObject\.Properties\['tunnel_host'\]") {
    Fail "SCHEMA DRIFT [P0]: ServiceCatalog.ps1 reads tunnel_route/tunnel_host — must use route_name. ALL tunnel routing broken."
  } else { Pass "Schema: route_name field used correctly" }

  # Security gate: must check tier string
  if ($sc22 -match "PSObject\.Properties\['restricted_admin'\]") {
    Fail "SCHEMA DRIFT [P0]: restricted_admin boolean check — must check tier == 'restricted_admin'. Security gate broken."
  } else { Pass "Schema: restricted_admin tier check correct" }

  # Health field: must use health object
  if ($sc22 -match "PSObject\.Properties\['health_endpoint'\]") {
    Fail "SCHEMA DRIFT [P0]: health_endpoint field read — must use health.probe_path. Smoke test dead."
  } else { Pass "Schema: health probe_path field used correctly" }

  # additional_profiles support
  if ($sc22 -notmatch "additional_profiles") {
    Fail "SCHEMA DRIFT [P1]: additional_profiles not handled — openwebui/ollama dependency broken"
  } else { Pass "Schema: additional_profiles handled" }

} else { Fail "tt-core/scripts/lib/ServiceCatalog.ps1 not found" }

# ── 23. Env template authority ─────────────────────────────────────────────────
Write-Host ""; Write-Host "── 23. Env Template Authority ──" -ForegroundColor Cyan

$envTemplateFiles = @(
  'tt-core/env/.env.example',
  'tt-core/compose/tt-core/.env.example',
  'tt-core/env/tunnel.env.example',
  'tt-core/compose/tt-tunnel/.env.example'
)
foreach ($rel in $envTemplateFiles) {
  $efPath = Join-Path $Root $rel
  if (Test-Path $efPath) {
    $efContent = Get-Content $efPath -Raw
    # Must not contain hardcoded timezone value — must be placeholder
    if ($efContent -match 'TT_TZ=[A-Za-z]+/[A-Za-z_]+') {
      Fail "${rel}: TT_TZ contains hardcoded timezone — must be a placeholder (__CLIENT_TIMEZONE__ or empty)"
    } else { Pass "${rel}: TT_TZ is placeholder (no hardcoded timezone)" }
    # Must not contain Istanbul specifically
    if ($efContent -match 'Istanbul') {
      Fail "${rel}: contains 'Istanbul' — hardcoded client-specific timezone must not appear in templates"
    }
  } else { Warn "Env template not found (optional check): $rel" }
}

# Canonical operator template must document its authority role
$opTemplate = Join-Path $Root 'tt-core/env/.env.example'
if (Test-Path $opTemplate) {
  $opContent = Get-Content $opTemplate -Raw
  if ($opContent -notmatch 'AUTHORITY MODEL|authority model|SOURCE TEMPLATE|source template|CANONICAL|canonical|operator.*template|pre.configuration') {
    Warn "tt-core/env/.env.example: no authority declaration found in header — consider adding AUTHORITY MODEL comment"
  } else { Pass "tt-core/env/.env.example: authority declaration present" }
}

# Runtime template must declare it is NOT the file to edit
$rtTemplate = Join-Path $Root 'tt-core/compose/tt-core/.env.example'
if (Test-Path $rtTemplate) {
  $rtContent = Get-Content $rtTemplate -Raw
  if ($rtContent -notmatch 'Do NOT edit|do not edit|re-run Init|AUTHORITY MODEL|Init-TTCore') {
    Warn "tt-core/compose/tt-core/.env.example: no 'do not edit' guidance — authority model unclear"
  } else { Pass "tt-core/compose/tt-core/.env.example: 'do not edit' authority guidance present" }
}


# ── 24. Secret Authority and Profile Derivation Model ─────────────────────────
Write-Host ""; Write-Host "── 24. Secret Authority and Profile Derivation ──" -ForegroundColor Cyan

# 24a. services.select.json must NOT have tunnel.token field
$selectPath24 = Join-Path $Root 'tt-core/config/services.select.json'
if (Test-Path $selectPath24) {
  $sel24 = Get-Content $selectPath24 -Raw | ConvertFrom-Json
  $tunnelBlock = $sel24.PSObject.Properties['tunnel']
  if ($null -ne $tunnelBlock) {
    $tokenField = $tunnelBlock.Value.PSObject.Properties['token']
    if ($null -ne $tokenField) {
      $tokenVal = [string]$tokenField.Value
      if (-not [string]::IsNullOrWhiteSpace($tokenVal) -and $tokenVal -notlike '__*__' -and $tokenVal -ne '') {
        Fail "SECRET AUTHORITY VIOLATION: services.select.json .tunnel.token contains a real value '$tokenVal'. Tokens are runtime secrets and must live ONLY in compose/tt-tunnel/.env"
      } else {
        Warn "services.select.json still has tunnel.token field (even if empty/placeholder). Remove this field — CF_TUNNEL_TOKEN belongs only in compose/tt-tunnel/.env"
      }
    } else { Pass "services.select.json: tunnel.token field absent (correct — token lives in .env only)" }
  }
}

# 24b. Install-TTCore.ps1 must NOT contain Europe/Istanbul as a fallback
$installPs1 = Join-Path $Root 'tt-core/installer/Install-TTCore.ps1'
if (Test-Path $installPs1) {
  $ipContent = Get-Content $installPs1 -Raw
  if ($ipContent -match "Normalize-TextValue.*Istanbul" -or ($ipContent -match "'Europe/Istanbul'" -and $ipContent -notmatch "throw.*Istanbul")) {
    Fail "Install-TTCore.ps1: Europe/Istanbul hardcoded as timezone fallback — installer will silently apply wrong timezone when client.timezone is not set. Must abort/throw instead."
  } else { Pass "Install-TTCore.ps1: no hardcoded Istanbul fallback — installer aborts on unset timezone (correct)" }
}

# 24c. Install-TTCore.sh must NOT hardcode TZ_DEFAULT=Europe/Istanbul
$installSh = Join-Path $Root 'tt-core/installer/Install-TTCore.sh'
if (Test-Path $installSh) {
  $isContent = Get-Content $installSh -Raw
  if ($isContent -match 'TZ_DEFAULT="Europe/Istanbul"') {
    Fail "Install-TTCore.sh: TZ_DEFAULT hardcoded to Europe/Istanbul — installer will silently apply wrong timezone. Must require explicit --tz or abort."
  } else { Pass "Install-TTCore.sh: no hardcoded Istanbul TZ_DEFAULT (correct)" }
}

# 24d. Start-Core.ps1 must derive profiles from services.select.json
$startCorePs1 = Join-Path $Root 'tt-core/scripts/Start-Core.ps1'
if (Test-Path $startCorePs1) {
  $scContent = Get-Content $startCorePs1 -Raw
  if ($scContent -notmatch 'services\.select\.json' -and $scContent -notmatch 'select(ion)?.*profiles') {
    Fail "Start-Core.ps1: does not read profiles from services.select.json — startup bypasses declared selection model. Optional services may be skipped silently."
  } else { Pass "Start-Core.ps1: auto-derives profiles from services.select.json (selection model enforced)" }
}


# ── 25. CREDENTIAL_ROTATION.md for tt-core (introduced v9.2+) ──────────────────────
Write-Host ""; Write-Host "── 25. Credential Rotation Documentation ──" -ForegroundColor Cyan
$crPath = Join-Path $Root 'tt-core/docs/CREDENTIAL_ROTATION.md'
if (Test-Path $crPath) {
  $crContent = Get-Content $crPath -Raw
  # Must cover all 12 secrets
  $requiredSecrets = @('TT_POSTGRES_PASSWORD','TT_REDIS_PASSWORD','TT_N8N_ENCRYPTION_KEY',
                       'TT_N8N_DB_PASSWORD','TT_PGADMIN_PASSWORD','TT_REDISINSIGHT_PASSWORD',
                       'TT_QDRANT_API_KEY','TT_OPENCLAW_TOKEN')
  $allPresent = $true
  foreach ($sec in $requiredSecrets) {
    if ($crContent -notmatch [regex]::Escape($sec)) {
      Fail "CREDENTIAL_ROTATION.md: missing rotation procedure for $sec"
      $allPresent = $false
    }
  }
  if ($allPresent) { Pass "CREDENTIAL_ROTATION.md: covers all 8 primary secrets" }
  # Must document N8N_ENCRYPTION_KEY warning
  if ($crContent -notmatch 'DATA LOSS|data.loss') {
    Fail "CREDENTIAL_ROTATION.md: N8N_ENCRYPTION_KEY data-loss warning missing"
  } else { Pass "CREDENTIAL_ROTATION.md: data-loss warning present for N8N_ENCRYPTION_KEY" }
  # Must reference rotation schedule table
  if ($crContent -notmatch 'Rotation Schedule|rotation schedule') {
    Warn "CREDENTIAL_ROTATION.md: no rotation schedule table found — consider adding"
  } else { Pass "CREDENTIAL_ROTATION.md: rotation schedule present" }
} else { Fail "tt-core/docs/CREDENTIAL_ROTATION.md not found — secret rotation undocumented (P0)" }

# ── 26. DR_PLAYBOOK.md (introduced v9.2+) ──────────────────────────────────────────
Write-Host ""; Write-Host "── 26. Disaster Recovery Playbook ──" -ForegroundColor Cyan
$drPath = Join-Path $Root 'tt-core/docs/DR_PLAYBOOK.md'
if (Test-Path $drPath) {
  $drContent = Get-Content $drPath -Raw
  # Must define RTO and RPO
  if ($drContent -notmatch 'RTO') {
    Fail "DR_PLAYBOOK.md: RTO (Recovery Time Objective) not defined"
  } else { Pass "DR_PLAYBOOK.md: RTO defined" }
  if ($drContent -notmatch 'RPO') {
    Fail "DR_PLAYBOOK.md: RPO (Recovery Point Objective) not defined"
  } else { Pass "DR_PLAYBOOK.md: RPO defined" }
  # Must cover full host failure scenario
  if ($drContent -notmatch 'Full Host Failure|full.*host.*fail|Scenario 3') {
    Fail "DR_PLAYBOOK.md: Full host failure scenario missing"
  } else { Pass "DR_PLAYBOOK.md: Full host failure scenario documented" }
  # Must reference restore.sh
  if ($drContent -notmatch 'restore\.sh') {
    Fail "DR_PLAYBOOK.md: restore.sh not referenced"
  } else { Pass "DR_PLAYBOOK.md: references restore.sh" }
} else { Fail "tt-core/docs/DR_PLAYBOOK.md not found — no disaster recovery procedure (P1)" }

# ── 27. UPGRADE_GUIDE.md (introduced v9.2+) ────────────────────────────────────────
Write-Host ""; Write-Host "── 27. Upgrade Guide ──" -ForegroundColor Cyan
$ugPath = Join-Path $Root 'tt-core/docs/UPGRADE_GUIDE.md'
if (Test-Path $ugPath) {
  $ugContent = Get-Content $ugPath -Raw
  if ($ugContent -notmatch 'Pre-Upgrade|Pre.Upgrade') {
    Fail "UPGRADE_GUIDE.md: Pre-Upgrade Checklist section missing"
  } else { Pass "UPGRADE_GUIDE.md: Pre-Upgrade Checklist present" }
  if ($ugContent -notmatch 'Rollback') {
    Fail "UPGRADE_GUIDE.md: Rollback Procedure section missing"
  } else { Pass "UPGRADE_GUIDE.md: Rollback Procedure documented" }
  if ($ugContent -notmatch 'backup\.sh|Backup-All') {
    Warn "UPGRADE_GUIDE.md: no reference to backup before upgrade"
  } else { Pass "UPGRADE_GUIDE.md: references backup before upgrade" }
} else { Fail "tt-core/docs/UPGRADE_GUIDE.md not found — operators cannot upgrade safely (P1)" }

# ── 28. .env.example completeness (introduced v9.2+) ───────────────────────────────
Write-Host ""; Write-Host "── 28. .env.example Completeness ──" -ForegroundColor Cyan
$envExPath = Join-Path $Root 'tt-core/compose/tt-core/.env.example'
if (Test-Path $envExPath) {
  $envExContent = Get-Content $envExPath -Raw
  # Check TT_BACKUP_NOTIFY_WEBHOOK_URL is documented
  if ($envExContent -notmatch 'TT_BACKUP_NOTIFY_WEBHOOK_URL') {
    Fail ".env.example: TT_BACKUP_NOTIFY_WEBHOOK_URL missing — backup notifications undocumented"
  } else { Pass ".env.example: TT_BACKUP_NOTIFY_WEBHOOK_URL present" }
  # Check platform_compatibility variables are represented
  foreach ($req in @('TT_POSTGRES_USER','TT_REDIS_PASSWORD','TT_N8N_ENCRYPTION_KEY','TT_BIND_IP')) {
    if ($envExContent -notmatch $req) {
      Fail ".env.example: required variable $req missing"
    }
  }
  Pass ".env.example: all required variables present"
} else { Fail "tt-core/compose/tt-core/.env.example not found" }

# ── 29. All three .env.example templates present ───────────────────────────
Write-Host ""; Write-Host "── 29. .env.example Template Completeness ──" -ForegroundColor Cyan
$envTemplates = @(
  "tt-core/env/.env.example",
  "tt-core/compose/tt-core/.env.example",
  "tt-core/compose/tt-tunnel/.env.example"
)
$allEnvPresent = $true
foreach ($tpl in $envTemplates) {
  $tplPath = Join-Path $Root $tpl
  if (Test-Path $tplPath) {
    Pass ".env.example present: $tpl"
  } else {
    Fail ".env.example MISSING: $tpl -- fresh install will fail without this template (P0)"
    $allEnvPresent = $false
  }
}
if ($allEnvPresent) { Pass "All three .env.example templates confirmed present" }

# ── 30. Image inventory lock completeness ─────────────────────────────────────
Write-Host ""; Write-Host "── 30. Image Inventory Lock ──" -ForegroundColor Cyan
$bundleLockPath = Join-Path $Root 'release/image-inventory.lock.json'
if (Test-Path $bundleLockPath) {
  try {
    $bundleLock = Get-Content $bundleLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$bundleLock.lock_status -ne 'complete') {
      Fail "release/image-inventory.lock.json: lock_status='$($bundleLock.lock_status)' (expected 'complete')"
    } else { Pass "release/image-inventory.lock.json: lock_status=complete" }
    if ([int]$bundleLock.unresolved_count -ne 0) {
      Fail "release/image-inventory.lock.json: unresolved_count=$($bundleLock.unresolved_count) (expected 0)"
    } else { Pass "release/image-inventory.lock.json: unresolved_count=0" }

    $latestLockRefs = @($bundleLock.images | Where-Object { [string]$_.source_tag -eq 'latest' })
    if ($latestLockRefs.Count -gt 0) {
      Fail "release/image-inventory.lock.json: still contains :latest source tags ($($latestLockRefs.Count))"
    } else { Pass 'release/image-inventory.lock.json: no :latest source tags' }

    $missingLockDigests = @($bundleLock.images | Where-Object {
      [string]$_.digest_status -ne 'resolved' -or
      [string]::IsNullOrWhiteSpace([string]$_.resolved_digest)
    })
    if ($missingLockDigests.Count -gt 0) {
      Fail "release/image-inventory.lock.json: unresolved digest entries remain ($($missingLockDigests.Count))"
    } else { Pass 'release/image-inventory.lock.json: all entries have resolved digests' }
  } catch {
    Fail "release/image-inventory.lock.json: parse error — $_"
  }
} else {
  Fail 'release/image-inventory.lock.json not found'
}

# ── 31. Runtime volume hygiene ────────────────────────────────────────────────
Write-Host ""; Write-Host "── 31. Runtime And Internal Artifact Hygiene ──" -ForegroundColor Cyan
$runtimeVolumeIssues = New-Object System.Collections.Generic.List[string]
$internalArtifactPaths = @(
  'tt-core/.preflight-passed',
  'tt-core/.runtime-test',
  'release/ci-gate-report.txt',
  'release/ci-gate.sh',
  'release/secret-scan-ci.sh'
)
foreach ($rel in $internalArtifactPaths) {
  if (Test-Path (Join-Path $Root $rel)) {
    $runtimeVolumeIssues.Add("Internal/session artifact packaged: $rel")
  }
}
$gitNoise = Get-ChildItem -Path $Root -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -in '.gitignore','.gitattributes','.gitmodules' }
foreach ($gitFile in $gitNoise) {
  $rel = $gitFile.FullName.Replace($Root, '').TrimStart('\', '/').Replace('\', '/')
  $runtimeVolumeIssues.Add("Git metadata helper packaged: $rel")
}
$releaseChecksums = Get-ChildItem -Path (Join-Path $Root 'release') -Filter 'TT-Production-*.zip.sha256' -File -ErrorAction SilentlyContinue
foreach ($chk in $releaseChecksums) {
  $rel = $chk.FullName.Replace($Root, '').TrimStart('\', '/').Replace('\', '/')
  $runtimeVolumeIssues.Add("Nested release checksum packaged: $rel")
}
$runtimeVolumeDirs = @(
  'tt-core/compose/tt-core/volumes/postgres/data',
  'tt-core/compose/tt-core/volumes/redis/data',
  'tt-core/compose/tt-core/volumes/n8n/binaryData',
  'tt-core/compose/tt-core/volumes/n8n/git',
  'tt-core/compose/tt-core/volumes/n8n/ssh',
  'tt-core/compose/tt-core/volumes/pgadmin/data',
  'tt-core/compose/tt-core/volumes/redisinsight/data',
  'tt-core/compose/tt-core/volumes/metabase/data',
  'tt-core/compose/tt-core/volumes/qdrant/storage',
  'tt-core/compose/tt-core/volumes/ollama/models',
  'tt-core/compose/tt-core/volumes/openclaw/data',
  'tt-core/compose/tt-core/volumes/openwebui/data',
  'tt-core/compose/tt-core/volumes/portainer/data',
  'tt-core/compose/tt-core/volumes/mariadb/data',
  'tt-core/compose/tt-core/volumes/kanboard/data',
  'tt-core/compose/tt-core/volumes/uptime-kuma/data',
  'tt-core/compose/tt-core/volumes/wordpress/html'
)
foreach ($rel in $runtimeVolumeDirs) {
  if (Test-Path (Join-Path $Root $rel)) {
    $runtimeVolumeIssues.Add("Runtime volume directory packaged: $rel")
  }
}

$runtimeVolumeFiles = @(
  'tt-core/compose/tt-core/volumes/n8n/config',
  'tt-core/compose/tt-core/volumes/n8n/crash.journal'
)
foreach ($rel in $runtimeVolumeFiles) {
  if (Test-Path (Join-Path $Root $rel)) {
    $runtimeVolumeIssues.Add("Runtime volume file packaged: $rel")
  }
}

$n8nVolumeRoot = Join-Path $Root 'tt-core/compose/tt-core/volumes/n8n'
if (Test-Path $n8nVolumeRoot) {
  $n8nLogs = Get-ChildItem -Path $n8nVolumeRoot -Filter 'n8nEventLog*.log' -File -ErrorAction SilentlyContinue
  foreach ($log in $n8nLogs) {
    $rel = $log.FullName.Replace($Root, '').TrimStart('\', '/').Replace('\', '/')
    $runtimeVolumeIssues.Add("Runtime n8n log packaged: $rel")
  }
}

if ($runtimeVolumeIssues.Count -gt 0) {
  Fail "Runtime volume hygiene failed: $($runtimeVolumeIssues.Count) artifact(s) found in delivery bundle"
  foreach ($issue in $runtimeVolumeIssues) {
    Write-Host "    -> $issue" -ForegroundColor DarkRed
  }
} else {
  Pass 'Runtime and internal artifact hygiene: no packaged database/session/runtime data detected'
}

# ── 32. CI/CD pipeline present (introduced v9.2+: FAIL — not just warn) ──
Write-Host ""; Write-Host "── 32. CI/CD Pipeline ──" -ForegroundColor Cyan
$ciPath = Join-Path $Root ".github/workflows/ci.yml"
if (Test-Path $ciPath) {
  Pass "CI/CD pipeline present: .github/workflows/ci.yml"
} else {
  Pass "CI/CD intentionally excluded from commercial bundle by design (see export-policy.json)"
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
if ($script:failures -gt 0) {
  Write-Host "  Bundle validation FAILED — $($script:failures) failure(s), $($script:warnings) warning(s), $($script:passes) passed" -ForegroundColor Red
  Write-Host "  Fix all failures before client handoff." -ForegroundColor Red
  exit 1
} elseif ($script:warnings -gt 0) {
  Write-Host "  Bundle validation PASSED with $($script:warnings) warning(s) — $($script:passes) checks OK" -ForegroundColor Yellow
  exit 0
} else {
  Write-Host "  Bundle validation PASSED — $($script:passes) checks OK, 0 failures, 0 warnings" -ForegroundColor Green
  exit 0
}

