#Requires -Version 5.1
param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$catalogPath = Join-Path $Root 'config\service-catalog.json'
$policyPath  = Join-Path $Root 'config\public-exposure.policy.json'
if (!(Test-Path $catalogPath)) { throw "Service catalog not found: $catalogPath" }
$catalog = Get-Content $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json

$services = foreach ($svc in $catalog.services) {
  $obj = [ordered]@{
    service = [string]$svc.service
    profile = if ($null -ne $svc.profile) { [string]$svc.profile } else { $null }
    tier = [string]$svc.tier
    public_capable = [bool]$svc.public_capable
    auto_start_tunnel = [bool]$svc.auto_start_tunnel
    display_name = [string]$svc.display_name
  }
  if ($svc.tunnel) {
    $obj.toggle = [string]$svc.tunnel.toggle
    $obj.subdomain_var = [string]$svc.tunnel.subdomain_var
    $obj.placeholder = [string]$svc.tunnel.placeholder
    $obj.rule_key = [string]$svc.tunnel.rule_key
  }
  if ($svc.route_name) { $obj.route_name = [string]$svc.route_name }
  if ($null -ne $svc.requires_explicit_ack) { $obj.requires_explicit_ack = [bool]$svc.requires_explicit_ack }
  [pscustomobject]$obj
}

$payload = [ordered]@{
  _comment = 'Generated compatibility exposure policy derived from config/service-catalog.json — do not edit manually.'
  generated_from = 'config/service-catalog.json'
  services = @($services)
}
$json = $payload | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($policyPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Write-Host "Updated $policyPath" -ForegroundColor Green
