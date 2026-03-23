#Requires -Version 5.1
<#
.SYNOPSIS
    Delete backup folders older than N days.

.DESCRIPTION
    Scans BackupsRoot for date-stamped backup folders (format: backup_YYYYMMDD_HHMMSS)
    and removes those older than KeepDays.

.PARAMETER BackupsRoot
    Root directory containing backup folders. Default: %USERPROFILE%\stacks\tt-core\_backups

.PARAMETER KeepDays
    Number of days to keep backups. Default: 30

.PARAMETER WhatIf
    Preview what would be deleted without actually deleting.

.EXAMPLE
    .\Backup-Retention.ps1                          # Keep 30 days
    .\Backup-Retention.ps1 -KeepDays 14             # Keep 14 days
    .\Backup-Retention.ps1 -WhatIf                  # Preview only
#>
param(
  [string]$BackupsRoot = (Join-Path $env:USERPROFILE 'stacks\tt-core\_backups'),
  [int]   $KeepDays   = 30,
  [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (!(Test-Path $BackupsRoot)) {
  Write-Host "INFO: Backups root not found — nothing to clean: $BackupsRoot" -ForegroundColor DarkGray
  exit 0
}

$cutoff = (Get-Date).AddDays(-$KeepDays)
$deleted = 0
$kept    = 0

$folders = Get-ChildItem -Path $BackupsRoot -Directory | Where-Object { $_.Name -match "^backup_\d{8}_\d{6}$" }

foreach ($f in $folders) {
  if ($f.CreationTime -lt $cutoff) {
    if ($WhatIf) {
      Write-Host "WHATIF: Would delete: $($f.FullName)  ($([int]((Get-Date) - $f.CreationTime).TotalDays) days old)"
    } else {
      Remove-Item $f.FullName -Recurse -Force
      Write-Host "Deleted: $($f.FullName)" -ForegroundColor DarkGray
      $deleted++
    }
  } else {
    $kept++
  }
}

if ($WhatIf) {
  Write-Host "WhatIf: $($folders.Count) folders scanned. Run without -WhatIf to delete." -ForegroundColor Yellow
} else {
  Write-Host "OK: Retention complete. Deleted=$deleted  Kept=$kept  (threshold=${KeepDays}d)" -ForegroundColor Green
}
