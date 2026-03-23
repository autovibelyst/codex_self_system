#Requires -Version 5.1
# =============================================================================
# Backup-OffsiteSync.ps1 — TT-Production v14.0
#
# Syncs the local backup directory to an S3-compatible remote using rclone.
# Mirrors the functionality of tt-core/scripts-linux/backup-offsite.sh.
#
# Prerequisites:
#   - rclone installed and in PATH
#   - TT_OFFSITE_REMOTE configured in the external runtime core env
#     Example: TT_OFFSITE_REMOTE=myS3:mybucket/tt-backups
#
# Usage:
#   scripts\backup\Backup-OffsiteSync.ps1
#   scripts\backup\Backup-OffsiteSync.ps1 -DryRun
#   scripts\backup\Backup-OffsiteSync.ps1 -EnvFile "C:\custom\.env"
#
# TT_OFFSITE_REMOTE format: <rclone-remote-name>:<bucket>/<path>
# Example remotes: myS3 (AWS S3), myWasabi (Wasabi), myCFR2 (Cloudflare R2), myB2 (Backblaze)
# =============================================================================
param(
  [switch]$DryRun,
  [string]$Root    = (Split-Path -Parent $PSScriptRoot),
  [string]$EnvFile = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Version banner
$VER = "v14.0"
Write-Host ""
Write-Host "TT-Production $VER — Backup Offsite Sync (Windows)" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════════" -ForegroundColor DarkGray
if ($DryRun) { Write-Host "[DRY-RUN] No files will be transferred." -ForegroundColor Yellow }
Write-Host ""

# ─── Locate .env ──────────────────────────────────────────────────
function Read-DotEnv([string]$Path) {
  $map = @{}
  if (!(Test-Path $Path)) { return $map }
  foreach ($raw in (Get-Content $Path -Encoding UTF8)) {
    $line = [string]$raw
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
    $idx = $line.IndexOf('='); if ($idx -lt 1) { continue }
    $map[$line.Substring(0, $idx).Trim()] = $line.Substring($idx + 1).Trim()
  }
  return $map
}

$coreRoot = $Root
. (Join-Path $coreRoot "scripts\lib\RuntimeEnv.ps1")
$envPath    = if ($EnvFile) { $EnvFile } else { Resolve-TTCoreEnvPath -RootPath $coreRoot }
$envEx      = Join-Path $coreRoot "compose/tt-core/.env.example"

if (!(Test-Path $envPath)) {
  Write-Host "[ERROR] Runtime core env not found at: $envPath" -ForegroundColor Red
  Write-Host "        Run Init-TTCore.ps1 first." -ForegroundColor Red
  exit 1
}
$env = Read-DotEnv $envPath

# ─── Read TT_OFFSITE_REMOTE ───────────────────────────────────────
$remote = if ($env.ContainsKey('TT_OFFSITE_REMOTE')) { [string]$env['TT_OFFSITE_REMOTE'] } else { '' }
if ([string]::IsNullOrWhiteSpace($remote) -or $remote.StartsWith('__')) {
  Write-Host "[ERROR] TT_OFFSITE_REMOTE is not set in runtime core env." -ForegroundColor Red
  Write-Host "        Add: TT_OFFSITE_REMOTE=myRemote:bucket/tt-backups" -ForegroundColor Yellow
  Write-Host "        Then configure the rclone remote with: rclone config" -ForegroundColor Yellow
  exit 1
}
Write-Host "Remote : $remote" -ForegroundColor Cyan

# ─── Locate local backup directory ───────────────────────────────
$backupBase = if ($env.ContainsKey('TT_BACKUP_DIR')) {
  [string]$env['TT_BACKUP_DIR']
} else {
  Join-Path $env:USERPROFILE "tt-backups"
}
if (!(Test-Path $backupBase)) {
  Write-Host "[ERROR] Local backup directory not found: $backupBase" -ForegroundColor Red
  Write-Host "        Run backup first: scripts\backup\Backup-All.ps1" -ForegroundColor Yellow
  exit 1
}
Write-Host "Local  : $backupBase" -ForegroundColor Cyan

# ─── Check rclone ─────────────────────────────────────────────────
try {
  $rcloneVer = & rclone version 2>&1 | Select-String "rclone v" | Select-Object -First 1
  Write-Host "rclone : $rcloneVer" -ForegroundColor DarkGray
} catch {
  Write-Host "[ERROR] rclone is not installed or not in PATH." -ForegroundColor Red
  Write-Host "        Install from https://rclone.org/downloads/" -ForegroundColor Yellow
  exit 1
}

# ─── Build rclone arguments ───────────────────────────────────────
$rcloneArgs = @(
  "sync", $backupBase, $remote,
  "--verbose",
  "--transfers", "4",
  "--checkers", "8",
  "--contimeout", "60s",
  "--timeout", "300s",
  "--retries", "3",
  "--low-level-retries", "10",
  "--stats", "30s"
)
if ($DryRun) { $rcloneArgs += "--dry-run" }

Write-Host ""
Write-Host "Starting sync: $backupBase → $remote" -ForegroundColor Cyan
Write-Host ""

$startTime = Get-Date
try {
  & rclone @rcloneArgs
  if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[ERROR] rclone exited with code $LASTEXITCODE" -ForegroundColor Red
    exit 1
  }
} catch {
  Write-Host "[ERROR] rclone failed: $_" -ForegroundColor Red
  exit 1
}

$elapsed = (Get-Date) - $startTime
Write-Host ""
if ($DryRun) {
  Write-Host "DRY-RUN complete. No files transferred. Elapsed: $($elapsed.ToString('mm\:ss'))" -ForegroundColor Yellow
} else {
  Write-Host "Offsite sync COMPLETE — $remote" -ForegroundColor Green
  Write-Host "Elapsed: $($elapsed.ToString('mm\:ss'))" -ForegroundColor DarkGray
}
Write-Host ""
