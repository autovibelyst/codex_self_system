<#
.SYNOPSIS
    TT-Core Full Stack Restore — Windows — TT-Production v14.0

.DESCRIPTION
    Orchestrates a full restore from a TT-Core backup snapshot:
    1. Stop all running TT containers
    2. Restore Docker volumes from backup
    3. Restore PostgreSQL database dumps
    4. Restart the core stack
    5. Run smoke test to validate restoration

.PARAMETER SnapshotPath
    Full path to the backup snapshot directory (e.g., backups\backup_2026-03-13_12-00-00)

.PARAMETER SkipSmokeTest
    Skip post-restore smoke test (not recommended for production)

.EXAMPLE
    .\scripts\backup\Restore-All.ps1 -SnapshotPath ".\backups\backup_2026-03-13_12-00-00"

.NOTES
    Version: TT-Production v14.0
    Exit codes: 0 = success, 1 = error
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SnapshotPath,

    [Parameter(Mandatory=$false)]
    [switch]$SkipSmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Paths ──────────────────────────────────────────────────────────────────
$ScriptDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir '..' 'lib' 'RuntimeEnv.ps1')
$TTCoreDir     = Join-Path $ScriptDir ".." ".."
$ComposeDir    = Join-Path $TTCoreDir "compose" "tt-core"
$ComposeFile   = Join-Path $ComposeDir "docker-compose.yml"
$EnvFile       = Resolve-TTCoreEnvPath -RootPath $TTCoreDir

# ── Helpers ────────────────────────────────────────────────────────────────
function Write-OK  { param($msg) Write-Host "  [OK]  $msg" -ForegroundColor Green }
function Write-ERR { param($msg) Write-Host "  [ERR] $msg" -ForegroundColor Red }
function Write-HDR { param($msg) Write-Host "`n══════════════════════════════════════" -ForegroundColor Cyan; Write-Host "  $msg" -ForegroundColor Cyan; Write-Host "══════════════════════════════════════" -ForegroundColor Cyan }

# ── Validate snapshot ──────────────────────────────────────────────────────
Write-HDR "TT-Core Full Restore — v14.0"

if (-not (Test-Path $SnapshotPath)) {
    Write-ERR "Snapshot not found: $SnapshotPath"
    exit 1
}

$ChecksumFile = Join-Path $SnapshotPath "checksums.sha256"
if (-not (Test-Path $ChecksumFile)) {
    Write-ERR "Checksum file missing: $ChecksumFile — aborting for safety"
    exit 1
}
Write-OK "Snapshot found: $SnapshotPath"

# ── Confirm ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  WARNING: This will STOP all running TT containers and OVERWRITE" -ForegroundColor Yellow
Write-Host "  current data with the selected snapshot." -ForegroundColor Yellow
Write-Host ""
$confirm = Read-Host "  Type YES to proceed (anything else aborts)"
if ($confirm -ne "YES") {
    Write-Host "  Aborted." -ForegroundColor Yellow
    exit 0
}

# ── Step 1: Stop stack ──────────────────────────────────────────────────────
Write-HDR "Step 1 — Stopping TT-Core Stack"
Push-Location $ComposeDir
try {
    & docker compose --env-file $EnvFile down
    Write-OK "Stack stopped."
} finally {
    Pop-Location
}

# ── Step 2: Restore volumes ─────────────────────────────────────────────────
Write-HDR "Step 2 — Restoring Volume Snapshots"
$VolumeBackupDir = Join-Path $SnapshotPath "volumes"
if (Test-Path $VolumeBackupDir) {
    $VolumeDirs = Get-ChildItem -Path $VolumeBackupDir -Directory
    foreach ($v in $VolumeDirs) {
        $Target = Join-Path $ComposeDir "volumes" $v.Name
        Write-Host "  Restoring: $($v.Name) → $Target"
        if (Test-Path $Target) {
            Remove-Item -Recurse -Force $Target
        }
        Copy-Item -Recurse -Force $v.FullName $Target
        Write-OK "$($v.Name) restored"
    }
} else {
    Write-Host "  No volume backup directory found at $VolumeBackupDir — skipping volume restore"
}

# ── Step 3: Restore PostgreSQL dumps ────────────────────────────────────────
Write-HDR "Step 3 — Restoring PostgreSQL Databases"
$DumpDir = Join-Path $SnapshotPath "postgres"
if (Test-Path $DumpDir) {
    # Start postgres only for restore
    Push-Location $ComposeDir
    try {
        & docker compose --env-file $EnvFile up -d postgres
        Start-Sleep -Seconds 10

        $Dumps = Get-ChildItem -Path $DumpDir -Filter "*.sql.gz" 2>$null
        if (-not $Dumps) {
            $Dumps = Get-ChildItem -Path $DumpDir -Filter "*.sql" 2>$null
        }

        foreach ($dump in $Dumps) {
            $DbName = $dump.BaseName -replace '\.sql$', ''
            Write-Host "  Restoring database: $DbName from $($dump.Name)"
            if ($dump.Name -like "*.gz") {
                & docker exec -i tt-core-postgres sh -c "gunzip -c | psql -U $($env:TT_POSTGRES_USER ?? 'ttcore')" < $dump.FullName
            } else {
                & docker exec -i tt-core-postgres psql -U ($env:TT_POSTGRES_USER ?? 'ttcore') < $dump.FullName
            }
            Write-OK "$DbName restored"
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "  No postgres dump directory found — skipping database restore"
}

# ── Step 4: Restart full stack ───────────────────────────────────────────────
Write-HDR "Step 4 — Starting Core Stack"
Push-Location $ComposeDir
try {
    & docker compose --env-file $EnvFile up -d
    Write-OK "Core stack started."
    Write-Host "  Waiting 30 seconds for services to stabilize..."
    Start-Sleep -Seconds 30
} finally {
    Pop-Location
}

# ── Step 5: Smoke test ──────────────────────────────────────────────────────
if (-not $SkipSmokeTest) {
    Write-HDR "Step 5 — Post-Restore Smoke Test"
    $SmokeScript = Join-Path $TTCoreDir "scripts-linux" "smoke-test.sh"
    if (Test-Path $SmokeScript) {
        Write-Host "  Note: smoke-test.sh requires WSL2 or Git Bash on Windows."
        Write-Host "  Run manually: bash scripts-linux/smoke-test.sh"
    }

    # Windows-native container check
    $RequiredContainers = @(
        "tt-core-postgres", "tt-core-redis", "tt-core-n8n",
        "tt-core-n8n-worker", "tt-core-pgadmin", "tt-core-redisinsight"
    )
    $AllRunning = $true
    foreach ($c in $RequiredContainers) {
        $status = & docker inspect --format '{{.State.Status}}' $c 2>$null
        if ($status -eq "running") {
            Write-OK "$c — running"
        } else {
            Write-ERR "$c — $status (expected: running)"
            $AllRunning = $false
        }
    }
    if ($AllRunning) {
        Write-OK "All required containers running — restore successful!"
    } else {
        Write-ERR "Some containers not running — investigate before declaring restore complete."
        exit 1
    }
} else {
    Write-Host "  Smoke test skipped (--SkipSmokeTest)" -ForegroundColor Yellow
}

Write-HDR "Restore Complete"
Write-OK "Snapshot restored: $SnapshotPath"
Write-Host "  Next: verify application state via browser before resuming production traffic."
Write-Host ""
