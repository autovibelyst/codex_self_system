#Requires -Version 5.1
<#
.SYNOPSIS
    TT-Core Full Backup — TT-Production v14.0
    Backs up all TT-Core data: PostgreSQL dumps, bind-mount volumes, .env.

.DESCRIPTION
    Backup sequence:
      1. PostgreSQL dumps (all known databases via pg_dump)
      2. Bind-mount volumes archive (ZIP, excludes ollama/models, postgres/data)
      3. .env backup (plaintext secrets — restrict permissions after backup)

    Optional: Sends a Telegram notification on backup failure.
    Set TT_NOTIFY_TELEGRAM_BOT_TOKEN and TT_NOTIFY_TELEGRAM_CHAT_ID in .env to enable.

.PARAMETER TTCoreComposeDir
    Path to compose/tt-core directory. Default: %USERPROFILE%\stacks\tt-core\compose\tt-core

.PARAMETER BackupsRoot
    Root directory for backup folders. Default: %USERPROFILE%\stacks\tt-core\_backups
#>
param(
    [string]$TTCoreComposeDir = (Join-Path $env:USERPROFILE 'stacks\tt-core\compose\tt-core'),
    [string]$BackupsRoot      = (Join-Path $env:USERPROFILE 'stacks\tt-core\_backups')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib\BackupLib.ps1')

# ── Telegram notification helper (opt-in) ─────────────────────────────────────
function Send-TelegramNotification {
    param([string]$Text)
    $envFile = Join-Path $TTCoreComposeDir '.env'
    if (-not (Test-Path $envFile)) { return }
    $envText = Get-Content $envFile -Raw -ErrorAction SilentlyContinue
    $botToken = ([regex]::Match($envText, '(?m)^TT_NOTIFY_TELEGRAM_BOT_TOKEN=(.+)$')).Groups[1].Value.Trim()
    $chatId   = ([regex]::Match($envText, '(?m)^TT_NOTIFY_TELEGRAM_CHAT_ID=(.+)$')).Groups[1].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($botToken) -or [string]::IsNullOrWhiteSpace($chatId)) { return }
    try {
        $encoded = [Uri]::EscapeDataString($Text)
        $url = "https://api.telegram.org/bot${botToken}/sendMessage?chat_id=${chatId}&text=${encoded}&parse_mode=Markdown"
        Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 10 | Out-Null
        Write-Info 'Telegram failure notification sent.'
    } catch {
        Write-Warn "Could not send Telegram notification: $($_.Exception.Message)"
    }
}

$backupDir = New-BackupFolder -BaseDir $BackupsRoot
Write-Info "Backup folder: $backupDir"
$backupErrors = [System.Collections.Generic.List[string]]::new()

# ── 1. PostgreSQL dumps ───────────────────────────────────────────────────────
try {
    & (Join-Path $PSScriptRoot 'Backup-PostgresDumps.ps1') `
        -TTCoreComposeDir $TTCoreComposeDir -BackupDir $backupDir
} catch {
    $msg = "Postgres dump failed: $($_.Exception.Message)"
    Write-Warn $msg
    $backupErrors.Add($msg)
}

# ── 2. Bind-mount volumes (ZIP, smart exclusions) ─────────────────────────────
$volDir = Join-Path $TTCoreComposeDir 'volumes'
if (Test-Path $volDir) {
    Write-Info "Archiving bind-mount volumes: $volDir"
    $archiveName = "volumes_{0}.zip" -f (Get-Date).ToString('yyyyMMdd_HHmmss')
    $archivePath = Join-Path $backupDir $archiveName
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::Open($archivePath, 'Create')
        $skipDirs = @(
            'volumes\postgres\data',
            'volumes\ollama\models',
            'volumes\openclaw\data\workspace'
        )
        $allFiles = Get-ChildItem -Recurse -File $volDir
        foreach ($file in $allFiles) {
            $rel = $file.FullName.Replace($TTCoreComposeDir + '\', '')
            $shouldSkip = $false
            foreach ($skip in $skipDirs) {
                if ($rel.StartsWith($skip)) { $shouldSkip = $true; break }
            }
            if (-not $shouldSkip) {
                [void]$zip.CreateEntryFromFile(
                    $file.FullName, $rel,
                    [System.IO.Compression.CompressionLevel]::Optimal
                )
            }
        }
        $zip.Dispose()
        Write-Ok "Volumes archived: $archivePath"
    } catch {
        $msg = "Volume archive failed: $($_.Exception.Message)"
        Write-Warn $msg
        Write-Warn 'Manual backup: copy the volumes/ directory to a safe location.'
        $backupErrors.Add($msg)
    }
} else {
    Write-Warn "volumes/ directory not found at: $volDir — skipping bind-mount backup"
}

# ── 3. .env backup ────────────────────────────────────────────────────────────
$envFile = Join-Path $TTCoreComposeDir '.env'
if (Test-Path $envFile) {
    $envBackup = Join-Path $backupDir '.env.backup'
    Copy-Item $envFile $envBackup -Force
    Write-Ok ".env backed up: $envBackup"
    Write-Warn 'SECURITY: .env.backup contains all secrets in plaintext. Restrict file permissions or move to an encrypted location.'
} else {
    Write-Warn ".env not found at: $envFile — skipping env backup"
}

# ── Results ───────────────────────────────────────────────────────────────────
Write-Host ''
if ($backupErrors.Count -gt 0) {
    $summary = "TT-Core backup completed with $($backupErrors.Count) error(s):`n" + ($backupErrors -join "`n")
    Write-Warn $summary
    Send-TelegramNotification -Text "*TT-Core Backup FAILED*`n$summary"
    exit 1
}

Write-Ok "Full backup complete: $backupDir"
