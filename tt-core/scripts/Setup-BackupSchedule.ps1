<#
.SYNOPSIS
  Sets up automatic daily backups using Windows Task Scheduler.

.DESCRIPTION
  Creates a scheduled task that runs Backup-All.ps1 every day at the
  specified time. Backups are stored in the _backups folder under the
  TT-Core root.

  Also creates a cleanup task to delete backups older than RetentionDays.

  Run once after installation. Safe to re-run — updates the schedule if
  it already exists.

.PARAMETER Root
  TT-Core installation root (default: %USERPROFILE%\stacks\tt-core).

.PARAMETER Hour
  Hour to run backup (24-hour format, default: 3 = 3:00 AM).

.PARAMETER Minute
  Minute to run backup (default: 0).

.PARAMETER RetentionDays
  Delete backups older than this many days (default: 30).

.PARAMETER Remove
  Remove the scheduled tasks (disable automatic backups).

.EXAMPLE
  # Set up daily backup at 3:00 AM (default)
  scripts\Setup-BackupSchedule.ps1

  # Set up daily backup at 2:30 AM, keep 14 days
  scripts\Setup-BackupSchedule.ps1 -Hour 2 -Minute 30 -RetentionDays 14

  # Remove scheduled backup tasks
  scripts\Setup-BackupSchedule.ps1 -Remove
#>

param(
  [string] $Root          = (Join-Path $env:USERPROFILE 'stacks\tt-core'),
  [int]    $Hour          = 3,
  [int]    $Minute        = 0,
  [int]    $RetentionDays = 30,
  [switch] $Remove
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$TASK_BACKUP  = "TT-Core Daily Backup"
$TASK_CLEANUP = "TT-Core Backup Cleanup"

# ── Remove mode ───────────────────────────────────────────────────
if ($Remove) {
  foreach ($taskName in @($TASK_BACKUP, $TASK_CLEANUP)) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
      Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
      Write-Host "Removed scheduled task: $taskName" -ForegroundColor Green
    } else {
      Write-Host "Task not found (already removed): $taskName" -ForegroundColor Yellow
    }
  }
  exit 0
}

# ── Validate paths ────────────────────────────────────────────────
$backupScript  = Join-Path $Root "scripts\backup\Backup-All.ps1"
$composeDir    = Join-Path $Root "compose\tt-core"
$backupsRoot   = Join-Path $Root "_backups"

if (!(Test-Path $backupScript)) {
  throw "Backup script not found: $backupScript"
}
if (!(Test-Path $composeDir)) {
  throw "Compose directory not found: $composeDir"
}

New-Item -ItemType Directory -Force -Path $backupsRoot | Out-Null

# ── Build scheduled task (Backup) ────────────────────────────────
$backupAction = New-ScheduledTaskAction `
  -Execute "pwsh.exe" `
  -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$backupScript`" -TTCoreComposeDir `"$composeDir`" -BackupsRoot `"$backupsRoot`""

$backupTrigger = New-ScheduledTaskTrigger -Daily -At "$($Hour):$($Minute.ToString('D2'))"

$settings = New-ScheduledTaskSettingsSet `
  -StartWhenAvailable `
  -RunOnlyIfNetworkAvailable:$false `
  -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
  -MultipleInstances IgnoreNew

$principal = New-ScheduledTaskPrincipal `
  -UserId "SYSTEM" `
  -LogonType ServiceAccount `
  -RunLevel Highest

Register-ScheduledTask `
  -TaskName    $TASK_BACKUP `
  -Action      $backupAction `
  -Trigger     $backupTrigger `
  -Settings    $settings `
  -Principal   $principal `
  -Description "TT-Core automatic daily backup — installed by Setup-BackupSchedule.ps1" `
  -Force | Out-Null

Write-Host "OK: Backup task registered: '$TASK_BACKUP'" -ForegroundColor Green
Write-Host "    Schedule: daily at $($Hour):$($Minute.ToString('D2'))" -ForegroundColor DarkGray
Write-Host "    Output  : $backupsRoot" -ForegroundColor DarkGray

# ── Build scheduled task (Cleanup — runs 1h after backup) ────────
$cleanupScript = @"
Get-ChildItem -Path '$backupsRoot' -Directory |
  Where-Object { `$_.CreationTime -lt (Get-Date).AddDays(-$RetentionDays) } |
  ForEach-Object {
    Remove-Item -Recurse -Force `$_.FullName
    Write-Host "Deleted old backup: `$(`$_.FullName)"
  }
"@

$cleanupScriptPath = Join-Path $Root "scripts\backup\_cleanup-task.ps1"
[IO.File]::WriteAllText(
  $cleanupScriptPath,
  $cleanupScript,
  (New-Object System.Text.UTF8Encoding($false))
)

$cleanupHour = ($Hour + 1) % 24
$cleanupAction = New-ScheduledTaskAction `
  -Execute "pwsh.exe" `
  -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$cleanupScriptPath`""

$cleanupTrigger = New-ScheduledTaskTrigger -Daily -At "$($cleanupHour):$($Minute.ToString('D2'))"

Register-ScheduledTask `
  -TaskName    $TASK_CLEANUP `
  -Action      $cleanupAction `
  -Trigger     $cleanupTrigger `
  -Settings    $settings `
  -Principal   $principal `
  -Description "TT-Core backup cleanup — keeps last $RetentionDays days" `
  -Force | Out-Null

Write-Host "OK: Cleanup task registered: '$TASK_CLEANUP'" -ForegroundColor Green
Write-Host "    Schedule: daily at $($cleanupHour):$($Minute.ToString('D2'))" -ForegroundColor DarkGray
Write-Host "    Retention: $RetentionDays days" -ForegroundColor DarkGray

Write-Host ""
Write-Host "== Backup schedule active ==" -ForegroundColor Green
Write-Host "  View tasks      : Get-ScheduledTask | Where-Object TaskName -like 'TT-Core*'"
Write-Host "  Run now (test)  : Start-ScheduledTask -TaskName '$TASK_BACKUP'"
Write-Host "  Remove schedule : scripts\Setup-BackupSchedule.ps1 -Remove"
