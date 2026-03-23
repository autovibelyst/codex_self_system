
#Requires -Version 5.1
<#
.SYNOPSIS
    TT-Supabase Preflight Check — TT-Production v14.0
    Validates TT-Supabase configuration before first start.
#>
param(
  [string]$SupabaseRoot = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tt-supabase')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues   = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$envFile = Join-Path $SupabaseRoot 'compose/tt-supabase/.env'

function Get-EnvVal([string]$Text, [string]$Key) {
  $m = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Key) + '=(.*)$')
  if ($m.Success) { return $m.Groups[1].Value.Trim() }
  return ''
}

Write-Host ""
Write-Host "── TT-Supabase Preflight Check — TT-Production v14.0 ─────────────────" -ForegroundColor Cyan

if (!(Test-Path $envFile)) {
  Write-Host "[FAIL] compose/tt-supabase/.env not found. Run: tt-core\scripts\Init-Supabase.ps1" -ForegroundColor Red
  exit 1
}

$envText = Get-Content $envFile -Raw
$jwtSecret = Get-EnvVal $envText 'JWT_SECRET'
$anonKey = Get-EnvVal $envText 'ANON_KEY'
$svcKey = Get-EnvVal $envText 'SERVICE_ROLE_KEY'
$pgPassword = Get-EnvVal $envText 'POSTGRES_PASSWORD'
$dashPassword = Get-EnvVal $envText 'DASHBOARD_PASSWORD'
$supabasePublicUrl = Get-EnvVal $envText 'SUPABASE_PUBLIC_URL'
$apiExternalUrl = Get-EnvVal $envText 'API_EXTERNAL_URL'
$siteUrl = Get-EnvVal $envText 'SITE_URL'

if ([string]::IsNullOrWhiteSpace($jwtSecret)) { $issues.Add('JWT_SECRET is not set. Run Init-Supabase.ps1.') }
elseif ($jwtSecret.Length -lt 32) { $issues.Add("JWT_SECRET is too short ($($jwtSecret.Length) chars). Must be >= 32 chars.") }
if ([string]::IsNullOrWhiteSpace($anonKey) -or ($anonKey -split '\.').Count -ne 3) { $issues.Add('ANON_KEY is not a valid JWT token. Run Init-Supabase.ps1.') }
if ([string]::IsNullOrWhiteSpace($svcKey) -or ($svcKey -split '\.').Count -ne 3) { $issues.Add('SERVICE_ROLE_KEY is not a valid JWT token. Run Init-Supabase.ps1.') }
if ([string]::IsNullOrWhiteSpace($pgPassword)) { $issues.Add('POSTGRES_PASSWORD is not set. Run Init-Supabase.ps1.') }
if ([string]::IsNullOrWhiteSpace($dashPassword)) { $issues.Add('DASHBOARD_PASSWORD is not set. Run Init-Supabase.ps1.') }
if ([string]::IsNullOrWhiteSpace($supabasePublicUrl) -or $supabasePublicUrl -like '*__SET_YOUR_SUPABASE_DOMAIN__*') { $warnings.Add('SUPABASE_PUBLIC_URL is not set to a real public URL.') }
if ([string]::IsNullOrWhiteSpace($apiExternalUrl) -or $apiExternalUrl -like '*__SET_YOUR_SUPABASE_DOMAIN__*') { $warnings.Add('API_EXTERNAL_URL is not set to a real public URL.') }
if ([string]::IsNullOrWhiteSpace($siteUrl) -or $siteUrl -like '*__SET_YOUR_APP_DOMAIN__*') { $warnings.Add('SITE_URL is not set to a real frontend URL.') }

if ($issues.Count -gt 0) {
  $issues | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
  $warnings | ForEach-Object { Write-Host "[WARN] $_" -ForegroundColor Yellow }
  Write-Host ""
  Write-Host "Supabase preflight FAILED — $($issues.Count) issue(s)." -ForegroundColor Red
  exit 1
}

Write-Host 'Supabase preflight checks passed.' -ForegroundColor Green
if ($warnings.Count -gt 0) {
  $warnings | ForEach-Object { Write-Host "[WARN] $_" -ForegroundColor Yellow }
} else {
  Write-Host 'No warnings.' -ForegroundColor Green
}
