<#
.SYNOPSIS
  Rolls back TT-Core containers to a previous snapshot (saved by Update-TTCore.ps1).

.DESCRIPTION
  Reads a snapshot JSON file, pulls the exact image digests recorded,
  and restarts containers with those images.

  Use this after an update breaks something.

.PARAMETER Root
  TT-Core installation root.

.PARAMETER SnapshotFile
  Path to the snapshot JSON file (output of Update-TTCore.ps1).
  Located at: compose\.snapshots\snapshot-YYYYMMDD-HHmm.json

.PARAMETER ListSnapshots
  Lists all available snapshots without rolling back.

.EXAMPLE
  # List available snapshots
  scripts\Restore-Snapshot.ps1 -ListSnapshots

  # Roll back to a specific snapshot
  scripts\Restore-Snapshot.ps1 -SnapshotFile "compose\.snapshots\snapshot-20260305-1430.json"
#>

param(
  [string] $Root           = (Join-Path $env:USERPROFILE 'stacks\tt-core'),
  [string] $SnapshotFile   = "",
  [switch] $ListSnapshots
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$snapshotsDir = Join-Path $Root "compose\.snapshots"

# ── List mode ─────────────────────────────────────────────────────
if ($ListSnapshots) {
  if (!(Test-Path $snapshotsDir)) {
    Write-Host "No snapshots found in: $snapshotsDir" -ForegroundColor Yellow
    exit 0
  }
  $files = Get-ChildItem $snapshotsDir -Filter "snapshot-*.json" | Sort-Object Name -Descending
  if ($files.Count -eq 0) {
    Write-Host "No snapshots available." -ForegroundColor Yellow
    exit 0
  }
  Write-Host "Available snapshots (newest first):" -ForegroundColor Cyan
  foreach ($f in $files) {
    $snap = Get-Content $f.FullName -Raw | ConvertFrom-Json
    Write-Host "  $($f.Name)  —  $($snap.createdAt)" -ForegroundColor White
  }
  Write-Host ""
  Write-Host "To restore: scripts\Restore-Snapshot.ps1 -SnapshotFile `"compose\.snapshots\<filename>`""
  exit 0
}

# ── Restore mode ──────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($SnapshotFile)) {
  throw "Specify -SnapshotFile or use -ListSnapshots to see available snapshots."
}

$snapPath = if ([System.IO.Path]::IsPathRooted($SnapshotFile)) {
  $SnapshotFile
} else {
  Join-Path $Root $SnapshotFile
}

if (!(Test-Path $snapPath)) { throw "Snapshot file not found: $snapPath" }

$snapshot = Get-Content $snapPath -Raw | ConvertFrom-Json

Write-Host ""
Write-Host "== TT-Core Rollback ==" -ForegroundColor Yellow
Write-Host "  Snapshot : $snapPath" -ForegroundColor DarkGray
Write-Host "  Created  : $($snapshot.createdAt)" -ForegroundColor DarkGray
Write-Host ""

. "$PSScriptRoot\_compose_args.ps1"
. "$PSScriptRoot\lib\RuntimeEnv.ps1"
$coreDir     = Join-Path $Root "compose\tt-core"
$composeArgs = Get-TTComposeArgs -ComposeDir $coreDir
$coreEnvFile = Resolve-TTCoreEnvPath -RootPath $Root
$composeArgs += "--env-file", $coreEnvFile

foreach ($item in $snapshot.items) {
  if ([string]::IsNullOrWhiteSpace($item.digest)) {
    Write-Host "  SKIP $($item.service): no digest recorded" -ForegroundColor Yellow
    continue
  }

  Write-Host "  Pulling: $($item.digest)" -ForegroundColor DarkGray
  docker pull $item.digest 2>$null

  # Re-tag with the original image name for compose to find it
  $img = $item.image -replace ":.*", ""
  docker tag $item.digest $item.image 2>$null
}

Write-Host ""
Write-Host "Restarting services with restored images..." -ForegroundColor Yellow

Push-Location $coreDir
try {
  docker compose @($composeArgs + @("up", "-d", "--remove-orphans"))
} finally {
  Pop-Location
}

Write-Host ""
Write-Host "OK: Rollback complete." -ForegroundColor Green
Write-Host "  Check status: scripts\Status-Core.ps1"
