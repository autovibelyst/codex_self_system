param(
  [string]   $Root     = (Join-Path $env:USERPROFILE 'stacks\tt-core'),
  [string[]] $Profiles = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "Restarting TT-Core..." -ForegroundColor Cyan

& "$PSScriptRoot\Stop-Core.ps1"  -Root $Root
Start-Sleep -Seconds 3
& "$PSScriptRoot\Start-Core.ps1" -Root $Root -Profiles $Profiles
