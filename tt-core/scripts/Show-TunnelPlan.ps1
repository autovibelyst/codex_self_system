#Requires -Version 5.1
<#
.SYNOPSIS
    Show the intended Cloudflare dashboard routes for TT-Core.

.DESCRIPTION
    Reads config\services.select.json and config\service-catalog.json, then prints
    the public hostnames you should create in the Cloudflare dashboard.

.PARAMETER Root
    TT-Core root folder. Default: %USERPROFILE%\stacks\tt-core

.PARAMETER AsJson
    Output the route plan as JSON.
#>
param(
  [string]$Root = (Join-Path $env:USERPROFILE 'stacks\tt-core'),
  [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\ServiceCatalog.ps1"

$catalog = Get-TTServiceCatalog -Root $Root
$selectPath = Join-Path $Root 'config\services.select.json'
if (!(Test-Path $selectPath)) { throw "Selection snapshot not found: $selectPath" }
$select = Get-Content $selectPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $select.client.domain -or $select.client.domain -match '^__') {
  throw "config\services.select.json is missing a real client.domain value."
}

$domain = [string]$select.client.domain
$allowRestricted = [bool]$select.security.allow_restricted_admin_tunnel_routes
$routeEntries = @()
foreach ($svc in @($catalog.services | Where-Object { $_.public_capable -eq $true -and $_.tunnel })) {
  $routeName = Get-TTRouteNameFromCatalogEntry -Entry $svc
  $enabled = $false
  if ($select.tunnel.routes.PSObject.Properties.Name -contains $routeName) {
    $enabled = [bool]$select.tunnel.routes.$routeName
  }
  if (-not $enabled) { continue }
  $sub = if ($select.tunnel.subdomains.PSObject.Properties.Name -contains $routeName) { [string]$select.tunnel.subdomains.$routeName } else { $routeName }
  $routeEntries += [pscustomobject]@{
    service = [string]$svc.service
    display_name = if ($svc.display_name) { [string]$svc.display_name } else { [string]$svc.service }
    tier = [string]$svc.tier
    restricted_admin = ([string]$svc.tier -eq 'restricted_admin')
    hostname = "$sub.$domain"
  }
}

if ($AsJson) {
  $routeEntries | ConvertTo-Json -Depth 5
  exit 0
}

Write-Host "Cloudflare dashboard route plan for TT-Core" -ForegroundColor Cyan
Write-Host "Domain: $domain" -ForegroundColor DarkGray
Write-Host "Tunnel enabled in snapshot: $($select.tunnel.enabled)" -ForegroundColor DarkGray
Write-Host "Restricted admin routes acknowledged: $allowRestricted" -ForegroundColor DarkGray
Write-Host ""

if ($routeEntries.Count -eq 0) {
  Write-Host "No routes are currently enabled in config\services.select.json." -ForegroundColor Yellow
  exit 0
}

foreach ($entry in $routeEntries) {
  $line = "- {0}  [{1}]" -f $entry.hostname, $entry.display_name
  if ($entry.restricted_admin) {
    Write-Host $line -ForegroundColor Yellow
    Write-Host "    restricted admin surface — protect with Cloudflare Access before exposing." -ForegroundColor Yellow
  } else {
    Write-Host $line -ForegroundColor Green
  }
}
