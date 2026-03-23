#Requires -Version 5.1
# =============================================================================
# Init-TTCore.ps1 — TT-Core First-Run Initialization  (TT-Production v14.0)
#
# SAFE TO RE-RUN — idempotent, never overwrites existing secrets.
#
# WHAT IT DOES:
#   1) Copies .env.example to the external runtime core env when absent
#   2) Generates all secrets via Ensure-EnvSecret  (never overwrites)
#   3) Writes non-secret defaults via Ensure-EnvKey (never overwrites)
#      — TT_N8N_EXECUTIONS_MODE  (default: queue)
#      — TT_PG_SHARED_BUFFERS    (default: 256MB)
#      — TT_PG_MAX_CONNECTIONS   (default: 200)
#      — TT_PG_WORK_MEM          (default: 4MB)
#   4) Updates install metadata in services.select.json
#
# REQUIRES: Env.ps1 (dot-sourced below)
#   Ensure-EnvSecret: supported formats — base64 | hex | alphanumeric
#   Ensure-EnvKey:    writes plain defaults safely
# =============================================================================

param(
  [string] $EnvTarget      = '',
  [switch] $IncludeSupabase,
  [string] $SupabaseRoot   = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptRoot\lib\Env.ps1"
. "$ScriptRoot\lib\RuntimeEnv.ps1"

function Test-IsPlaceholderOrEmpty {
  param([string]$Value)
  return ([string]::IsNullOrWhiteSpace($Value) -or $Value -match '^__.*__$')
}

$TTRoot = Split-Path -Parent $ScriptRoot

if ([string]::IsNullOrWhiteSpace($EnvTarget)) {
  $EnvTarget = Get-TTRuntimeCoreEnvPath -RootPath $TTRoot
}
$envExample = Join-Path $TTRoot 'compose\tt-core\.env.example'
$runtimeDir = Split-Path -Parent (Get-TTRuntimeCoreEnvPath -RootPath $TTRoot)

# Banner
Write-Host ''
Write-Host '===============================================' -ForegroundColor Cyan
Write-Host '  TT-Core Init - v14.0' -ForegroundColor Cyan
Write-Host '===============================================' -ForegroundColor Cyan
Write-Host ''

# Step 1: Bootstrap .env
if (-not (Test-Path $EnvTarget)) {
  if (!(Test-Path $runtimeDir)) {
    New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
  }
  if (Test-Path $envExample) {
    Copy-Item $envExample $EnvTarget
    Write-Host '  [OK]   Created runtime env from .env.example' -ForegroundColor Green
  } else {
    Write-Error ".env.example not found at: $envExample"
    exit 1
  }
} else {
  Write-Host '  [OK]   Runtime env exists — secrets will only fill empty slots' -ForegroundColor DarkGray
}

# ── Step 2: Generate secrets ──────────────────────────────────────────────────
Write-Host ''
Write-Host '  Generating secrets (idempotent — skips non-empty keys)...' -ForegroundColor Cyan

# Database
Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_POSTGRES_PASSWORD'       -Format 'base64'       -Bytes 32 | Out-Null
Write-Host '    TT_POSTGRES_PASSWORD      ✓' -ForegroundColor DarkGray

Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_N8N_DB_PASSWORD'         -Format 'base64'       -Bytes 24 | Out-Null
Write-Host '    TT_N8N_DB_PASSWORD        ✓' -ForegroundColor DarkGray

Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_METABASE_DB_PASSWORD'    -Format 'base64'       -Bytes 24 | Out-Null
Write-Host '    TT_METABASE_DB_PASSWORD   ✓' -ForegroundColor DarkGray

Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_KANBOARD_DB_PASSWORD'    -Format 'base64'       -Bytes 24 | Out-Null
Write-Host '    TT_KANBOARD_DB_PASSWORD   ✓' -ForegroundColor DarkGray

Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_WP_DB_PASSWORD'          -Format 'base64'       -Bytes 24 | Out-Null
Write-Host '    TT_WP_DB_PASSWORD         ✓' -ForegroundColor DarkGray

Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_WP_ROOT_PASSWORD'        -Format 'base64'       -Bytes 24 | Out-Null
Write-Host '    TT_WP_ROOT_PASSWORD       ✓' -ForegroundColor DarkGray

# Cache
Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_REDIS_PASSWORD'          -Format 'hex'          -Bytes 24 | Out-Null
Write-Host '    TT_REDIS_PASSWORD         ✓' -ForegroundColor DarkGray

# Admin UIs
Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_PGADMIN_PASSWORD'        -Format 'base64'       -Bytes 24 | Out-Null
Write-Host '    TT_PGADMIN_PASSWORD       ✓' -ForegroundColor DarkGray

# RedisInsight — alphanumeric REQUIRED: RI_APP_PASSWORD rejects base64 special chars
Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_REDISINSIGHT_PASSWORD'   -Format 'alphanumeric' -Bytes 18 | Out-Null
Write-Host '    TT_REDISINSIGHT_PASSWORD  ✓  (alphanumeric — RI_APP_PASSWORD safe)' -ForegroundColor DarkGray

# Optional add-ons (generated when enabled later; safe to keep pre-generated)
Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_MINIO_PASSWORD'          -Format 'base64'       -Bytes 24 | Out-Null
Write-Host '    TT_MINIO_PASSWORD         ✓' -ForegroundColor DarkGray

Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_GRAFANA_PASSWORD'        -Format 'base64'       -Bytes 24 | Out-Null
Write-Host '    TT_GRAFANA_PASSWORD       ✓' -ForegroundColor DarkGray

# Automation
Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_N8N_ENCRYPTION_KEY'      -Format 'base64'       -Bytes 32 | Out-Null
Write-Host '    TT_N8N_ENCRYPTION_KEY     ✓' -ForegroundColor DarkGray

# Project Management
Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_KANBOARD_ADMIN_PASSWORD' -Format 'base64'       -Bytes 24 | Out-Null
Write-Host '    TT_KANBOARD_ADMIN_PASSWORD ✓' -ForegroundColor DarkGray

# Tunnel/Gateway
Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_OPENCLAW_TOKEN'          -Format 'hex'          -Bytes 32 | Out-Null
Write-Host '    TT_OPENCLAW_TOKEN         ✓' -ForegroundColor DarkGray

# Backup encryption
Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_BACKUP_ENCRYPTION_KEY'   -Format 'base64'       -Bytes 32 | Out-Null
Write-Host '    TT_BACKUP_ENCRYPTION_KEY  ✓' -ForegroundColor DarkGray

# Vector DB
Ensure-EnvSecret -EnvPath $EnvTarget -Key 'TT_QDRANT_API_KEY'          -Format 'hex'          -Bytes 24 | Out-Null
Write-Host '    TT_QDRANT_API_KEY         ✓' -ForegroundColor DarkGray

# ── Step 3: Non-secret operational defaults ───────────────────────────────────
Write-Host ''
Write-Host '  Writing operational defaults (idempotent — skips if already set)...' -ForegroundColor Cyan

# n8n execution mode — override with "regular" for single-process dev setups
Ensure-EnvKey -EnvPath $EnvTarget -Key 'TT_N8N_EXECUTIONS_MODE'  -Value 'queue'   | Out-Null
Write-Host '    TT_N8N_EXECUTIONS_MODE = queue      (override: regular for dev)' -ForegroundColor DarkGray

# PostgreSQL tuning — adjust for available RAM:
#   TT_PG_SHARED_BUFFERS: ~25% of total RAM (e.g. 1GB RAM → 256MB, 4GB → 1GB)
#   TT_PG_MAX_CONNECTIONS: reduce for low-RAM hosts to free memory
#   TT_PG_WORK_MEM: per-operation RAM; peak = max_connections × work_mem
Ensure-EnvKey -EnvPath $EnvTarget -Key 'TT_PG_SHARED_BUFFERS'    -Value '256MB'  | Out-Null
Write-Host '    TT_PG_SHARED_BUFFERS    = 256MB     (~25% of 1GB; scale with RAM)' -ForegroundColor DarkGray

Ensure-EnvKey -EnvPath $EnvTarget -Key 'TT_PG_MAX_CONNECTIONS'   -Value '200'    | Out-Null
Write-Host '    TT_PG_MAX_CONNECTIONS   = 200' -ForegroundColor DarkGray

Ensure-EnvKey -EnvPath $EnvTarget -Key 'TT_PG_WORK_MEM'          -Value '4MB'    | Out-Null
Write-Host '    TT_PG_WORK_MEM          = 4MB       (per sort/hash op)' -ForegroundColor DarkGray

# Optional integration defaults (avoid compose warnings on older runtime envs)
Ensure-EnvKey -EnvPath $EnvTarget -Key 'TT_QDRANT_HOST_PORT'     -Value '16333' | Out-Null
Ensure-EnvKey -EnvPath $EnvTarget -Key 'TT_QDRANT_GRPC_PORT'     -Value '16334' | Out-Null
Ensure-EnvKey -EnvPath $EnvTarget -Key 'TT_OPENCLAW_HOST_PORT'   -Value '18789' | Out-Null
Ensure-EnvKey -EnvPath $EnvTarget -Key 'TT_OPENCLAW_MODE'        -Value 'setup' | Out-Null
Ensure-EnvKey -EnvPath $EnvTarget -Key 'TT_OPENCLAW_MODEL'       -Value 'ollama/llama3.2' | Out-Null
Ensure-EnvKey -EnvPath $EnvTarget -Key 'TT_OPENCLAW_SOURCE_REF'  -Value '__PIN_GIT_TAG_OR_COMMIT__' | Out-Null
# ── Step 4: Sync check ────────────────────────────────────────────────────────
Write-Host ''
Write-Host '  Checking .env against .env.example...' -ForegroundColor Cyan
$null = Sync-EnvKeys -EnvPath $EnvTarget -ExamplePath $envExample -Quiet

# ── Step 5: Meta tracking in services.select.json ────────────────────────────
Write-Host ''
Write-Host '  Updating install metadata in services.select.json...' -ForegroundColor Cyan

$selectPath = Join-Path $TTRoot 'config\services.select.json'
if (Test-Path $selectPath) {
  try {
    $sel  = Get-Content $selectPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $now  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $who  = "$env:COMPUTERNAME\$env:USERNAME"
    $ver  = 'v14.0'

    # Auto-fill client identity defaults when placeholders are still present.
    if ($null -eq $sel.PSObject.Properties['client']) {
      $sel | Add-Member -MemberType NoteProperty -Name 'client' -Value ([pscustomobject]@{}) -Force
    }
    $clientObj = $sel.client
    $machineSlug = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { 'tt-client' } else { ([string]$env:COMPUTERNAME).ToLower() }
    $defaultClientName = "Client-$machineSlug"
    $defaultClientDomain = "$machineSlug.local"
    $defaultTimezone = try { [System.TimeZoneInfo]::Local.Id } catch { 'UTC' }

    $clientName = if ($clientObj.PSObject.Properties['name']) { [string]$clientObj.name } else { '' }
    if (Test-IsPlaceholderOrEmpty -Value $clientName) {
      $clientObj | Add-Member -MemberType NoteProperty -Name 'name' -Value $defaultClientName -Force
      Write-Host "    client.name auto-set to $defaultClientName" -ForegroundColor DarkGray
    }

    $clientDomain = if ($clientObj.PSObject.Properties['domain']) { [string]$clientObj.domain } else { '' }
    if (Test-IsPlaceholderOrEmpty -Value $clientDomain) {
      $clientObj | Add-Member -MemberType NoteProperty -Name 'domain' -Value $defaultClientDomain -Force
      Write-Host "    client.domain auto-set to $defaultClientDomain" -ForegroundColor DarkGray
    }

    $clientTimezone = if ($clientObj.PSObject.Properties['timezone']) { [string]$clientObj.timezone } else { '' }
    if (Test-IsPlaceholderOrEmpty -Value $clientTimezone) {
      $clientObj | Add-Member -MemberType NoteProperty -Name 'timezone' -Value $defaultTimezone -Force
      Write-Host "    client.timezone auto-set to $defaultTimezone" -ForegroundColor DarkGray
    }
    # Preserve installed_at on re-runs
    $installedProp = $sel.meta.PSObject.Properties['installed_at']
    $wasInstalled = if ($null -ne $installedProp) { [string]$installedProp.Value } else { '' }
    if ([string]::IsNullOrWhiteSpace($wasInstalled)) {
      $sel.meta | Add-Member -MemberType NoteProperty -Name 'installed_at' -Value $now -Force
      $sel.meta | Add-Member -MemberType NoteProperty -Name 'installed_by' -Value $who -Force
    }
    $sel.meta | Add-Member -MemberType NoteProperty -Name 'last_updated_at' -Value $now -Force
    $sel.meta | Add-Member -MemberType NoteProperty -Name 'last_updated_by' -Value $who -Force
    $sel.meta | Add-Member -MemberType NoteProperty -Name 'package_version' -Value $ver -Force

    $sel | ConvertTo-Json -Depth 10 | Set-Content $selectPath -Encoding UTF8
    Write-Host "    package_version = $ver, last_updated_by = $who" -ForegroundColor DarkGray
  } catch {
    Write-Host "  [WARN] Could not update services.select.json: $_" -ForegroundColor Yellow
  }
}

# ── Supabase init (opt-in) ────────────────────────────────────────────────────
if ($IncludeSupabase) {
  Write-Host ''
  Write-Host '  Supabase init...' -ForegroundColor Cyan
  $sbScript = Join-Path $ScriptRoot 'Init-Supabase.ps1'
  if (Test-Path $sbScript) {
    $sbArgs = @{}
    if (-not [string]::IsNullOrWhiteSpace($SupabaseRoot)) { $sbArgs['SupabaseRoot'] = $SupabaseRoot }
    & $sbScript @sbArgs
  } else {
    Write-Host '  [WARN] Init-Supabase.ps1 not found — skipping Supabase init' -ForegroundColor Yellow
  }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '═══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  Init complete. Next steps:' -ForegroundColor Cyan
Write-Host "    1) Edit runtime env: $EnvTarget" -ForegroundColor White
Write-Host '    2) .\scripts\Preflight-Check.ps1' -ForegroundColor White
Write-Host '    3) .\scripts\Start-Core.ps1' -ForegroundColor White
Write-Host '═══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''
