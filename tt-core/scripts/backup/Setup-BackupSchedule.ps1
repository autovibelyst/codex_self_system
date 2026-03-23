#Requires -Version 5.1
<#
.SYNOPSIS
    Schedule automatic daily backups using Windows Task Scheduler.

.DESCRIPTION
    Creates a Windows Scheduled Task that runs Backup-All.ps1 daily.
    Requires Administrator privileges.

.PARAMETER Root
    TT-Core root folder. Default: %USERPROFILE%\stacks\tt-core

.PARAMETER BackupsRoot
    Destination folder for backups. Default: %USERPROFILE%\stacks\tt-core\_backups

.PARAMETER Hour
    Hour of day to run backup (0-23). Default: 2 (2:00 AM)

.PARAMETER Minute
    Minute of hour to run backup (0-59). Default: 0

.PARAMETER Remove
    Remove the scheduled task instead of creating it.

.EXAMPLE
    .\Setup-BackupSchedule.ps1                        # Daily at 2:00 AM
    .\Setup-BackupSchedule.ps1 -Hour 3 -Minute 30     # Daily at 3:30 AM
    .\Setup-BackupSchedule.ps1 -Remove                # Remove schedule
#>
param(
  [string]$Root        = (Join-Path $env:USERPROFILE 'stacks\tt-core'),
  [string]$BackupsRoot = "",
  [int]   $Hour        = 2,
  [int]   $Minute      = 0,
  [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$TaskName = "TT-Core Daily Backup"

if ($Remove) {
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "OK: Scheduled task '$TaskName' removed." -ForegroundColor Green
  } else {
    Write-Host "INFO: Task '$TaskName' not found — nothing to remove." -ForegroundColor DarkGray
  }
  exit 0
}

# Require Administrator
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (!$currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw "This script requires Administrator privileges. Right-click PowerShell → Run as Administrator."
}

if (!$BackupsRoot) { $BackupsRoot = Join-Path $Root "_backups" }

$backupScript  = Join-Path $Root "scripts\backup\Backup-All.ps1"
$retentionScript = Join-Path $Root "scripts\backup\Backup-Retention.ps1"
$composeDir    = Join-Path $Root "compose\tt-core"

if (!(Test-Path $backupScript)) { throw "Backup script not found: $backupScript" }

# Build the command that the task will run
$scriptBlock = @"
try {
  & '$backupScript' -TTCoreComposeDir '$composeDir' -BackupsRoot '$BackupsRoot'
  if (Test-Path '$retentionScript') {
    & '$retentionScript' -BackupsRoot '$BackupsRoot' -KeepDays 30
  }
} catch {
  Write-Error "TT-Core backup failed: `$_"
  exit 1
}
"@

$action  = New-ScheduledTaskAction `
  -Execute "powershell.exe" `
  -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -Command `"$scriptBlock`""

$trigger = New-ScheduledTaskTrigger -Daily -At "$($Hour):$($Minute.ToString('00'))"

$settings = New-ScheduledTaskSettingsSet `
  -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
  -RestartCount 1 `
  -RestartInterval (New-TimeSpan -Minutes 30) `
  -RunOnlyIfNetworkAvailable $false

Register-ScheduledTask `
  -TaskName   $TaskName `
  -Action     $action `
  -Trigger    $trigger `
  -Settings   $settings `
  -RunLevel   Highest `
  -Force | Out-Null

Write-Host "OK: Scheduled task '$TaskName' created." -ForegroundColor Green
Write-Host "  Schedule   : Daily at $($Hour):$($Minute.ToString('00'))" -ForegroundColor DarkGray
Write-Host "  Backup dir : $BackupsRoot"                                 -ForegroundColor DarkGray
Write-Host "  Retention  : 30 days"                                      -ForegroundColor DarkGray
Write-Host ""
Write-Host "Verify in Windows Task Scheduler or run:" -ForegroundColor Cyan
Write-Host "  Get-ScheduledTask -TaskName '$TaskName'"
