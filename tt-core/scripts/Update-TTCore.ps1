#Requires -Version 5.1
<#
.SYNOPSIS
    Update TT-Core Docker images with automatic snapshot/rollback support.

.DESCRIPTION
    1. Creates a snapshot of current image digests before pulling
    2. Pulls latest pinned images
    3. Restarts services with new images
    4. On failure: automatically restores from snapshot

.PARAMETER Root
    TT-Core root folder. Default: %USERPROFILE%\stacks\tt-core

.PARAMETER PullOnly
    Pull images without restarting services.

.PARAMETER NoLock
    Skip updating the image lock file after pull.

.PARAMETER Rollback
    Restore the last saved snapshot (undo last update).

.EXAMPLE
    .\Update-TTCore.ps1                    # Full update with rollback protection
    .\Update-TTCore.ps1 -PullOnly          # Pull images only
    .\Update-TTCore.ps1 -Rollback          # Undo last update
#>
param(
  [string]$Root     = (Join-Path $env:USERPROFILE 'stacks\tt-core'),
  [switch]$PullOnly,
  [switch]$NoLock,
  [switch]$Rollback
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\Env.ps1"

$compose     = Join-Path $Root "compose\tt-core\docker-compose.yml"
$snapshotDir = Join-Path $Root "compose\.snapshots"
$snapshotFile = Join-Path $snapshotDir "last-update-snapshot.json"

if (!(Test-Path $compose)) { throw "Compose not found: $compose" }

# ── ROLLBACK mode ────────────────────────────────────────────────────────────
if ($Rollback) {
  if (!(Test-Path $snapshotFile)) {
    throw "No snapshot found at: $snapshotFile`nNo previous update to roll back."
  }

  $snap = Get-Content $snapshotFile -Raw | ConvertFrom-Json
  Write-Host "== TT-Core Rollback ==" -ForegroundColor Cyan
  Write-Host "  Snapshot from: $($snap.timestamp)" -ForegroundColor DarkGray
  Write-Host "  Restoring $($snap.services.Count) image pinnings..." -ForegroundColor DarkGray

  # Restore docker-compose.yml from snapshot backup
  $backupCompose = $snap.compose_backup
  if ($backupCompose -and (Test-Path $backupCompose)) {
    Copy-Item $backupCompose $compose -Force
    Write-Host "OK: Compose file restored from backup." -ForegroundColor Green
  } else {
    Write-Host "WARNING: Compose backup not found. Restarting with current compose only." -ForegroundColor Yellow
  }

  docker compose -f $compose up -d
  Write-Host "OK: Rollback complete." -ForegroundColor Green
  exit 0
}

# ── SNAPSHOT current state ───────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $snapshotDir | Out-Null

$stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$backupCompose = Join-Path $snapshotDir "docker-compose.yml.$stamp.bak"
Copy-Item $compose $backupCompose -Force

$snapshot = @{
  timestamp      = (Get-Date).ToString("o")
  compose_backup = $backupCompose
  services       = @{}
}

try {
  $psOutput = docker compose -f $compose ps --format json 2>$null | ConvertFrom-Json
  foreach ($svc in $psOutput) {
    $snapshot.services[$svc.Name] = $svc.Image
  }
} catch {
  Write-Host "INFO: Could not capture running image list (services may not be running)." -ForegroundColor DarkGray
}

$snapshot | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $snapshotFile
Write-Host "  Snapshot saved: $snapshotFile" -ForegroundColor DarkGray

# ── PULL images ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "== TT-Core Update ==" -ForegroundColor Cyan
Write-Host "  Pulling images..."

try {
  docker compose -f $compose pull
} catch {
  Write-Host "ERROR: Pull failed. No changes made." -ForegroundColor Red
  throw
}

# ── RESTART services ─────────────────────────────────────────────────────────
if (-not $PullOnly) {
  Write-Host "  Restarting services..."
  try {
    docker compose -f $compose up -d
  } catch {
    Write-Host ""
    Write-Host "ERROR: Restart failed! Rolling back automatically..." -ForegroundColor Red
    if (Test-Path $backupCompose) {
      Copy-Item $backupCompose $compose -Force
      docker compose -f $compose up -d
      Write-Host "OK: Automatic rollback complete." -ForegroundColor Yellow
    }
    throw
  }
}

# ── LOCK image digests ───────────────────────────────────────────────────────
if (-not $NoLock) {
  $lockScript = Join-Path $PSScriptRoot "Lock-ComposeImages.ps1"
  if (Test-Path $lockScript) {
    & $lockScript -ComposeFile $compose -ProjectName "tt-core" -OutDir (Join-Path $Root "compose\.locks")
  }
}

Write-Host ""
Write-Host "OK: Update complete." -ForegroundColor Green
Write-Host "  To undo: scripts\Update-TTCore.ps1 -Rollback" -ForegroundColor DarkGray
