#Requires -Version 5.1
# =============================================================================
# DEPRECATED — CONFIG MODE ONLY
#
# This script generates a cloudflared config.yml for LOCALLY-MANAGED tunnels
# (TUNNEL_UUID mode). The canonical production runtime for TT-Production v14.0
# is TOKEN-BASED only (CF_TUNNEL_TOKEN). Routes are configured in the
# Cloudflare Zero Trust dashboard, not via a generated config.yml.
#
# If TUNNEL_UUID is not set, this script exits cleanly with a TOKEN MODE note.
# This script is retained for operators who choose config-mode tunnels.
#
# CANONICAL PATH: Use scripts\\Start-Tunnel.ps1 with a valid CF_TUNNEL_TOKEN.
# =============================================================================
<#
.SYNOPSIS
    Generate cloudflared config.yml from tunnel .env toggle variables.

.DESCRIPTION
    Reads TUNNEL_ROUTE_* and SUB_* variables from the tunnel .env file and
    generates a legacy cloudflared config.yml for archived config-mode workflows only. Production runtime must use Start-Tunnel.ps1 with CF_TUNNEL_TOKEN.
    The single source of truth for tunnel-capable services is:
      config\public-exposure.policy.json

    Use this for LOCALLY-MANAGED tunnels (TUNNEL_UUID mode).
    For TOKEN-BASED tunnels, configure routes in the Cloudflare dashboard instead.

.PARAMETER TunnelEnvPath
    Path to runtime tunnel env (external; resolved by RuntimeEnv.ps1)

.PARAMETER OutPath
    Output path for config.yml (default: compose\tt-tunnel\volumes\cloudflared\config.yml)

.PARAMETER TemplatePath
    Path to config.yml.tpl

.PARAMETER RulesJsonPath
    Path to archived ingress-rules.json (legacy only)

.PARAMETER PolicyPath
    Path to config\public-exposure.policy.json
#>
param(
  [string]$TunnelEnvPath = "",
  [string]$OutPath       = "",
  [string]$TemplatePath  = "",
  [string]$RulesJsonPath = "",
  [string]$PolicyPath    = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\RuntimeEnv.ps1"

$scriptDir = $PSScriptRoot
$root      = Split-Path $scriptDir -Parent

if (!$TunnelEnvPath) { $TunnelEnvPath = Resolve-TTTunnelEnvPath -RootPath $root }
if (!$OutPath)       { $OutPath       = Join-Path $root "compose\tt-tunnel\volumes\cloudflared\config.yml" }
if (!$TemplatePath)  { $TemplatePath  = Join-Path $root "compose\tt-tunnel\templates\config.yml.tpl" }
if (!$RulesJsonPath) { $RulesJsonPath = Join-Path $root "compose\tt-tunnel\templates\ingress-rules.json" }
if (!$PolicyPath)    { $PolicyPath    = Join-Path $root "config\public-exposure.policy.json" }

function Read-DotEnv([string]$path) {
  $map = @{}
  if (!(Test-Path $path)) { throw "Env file not found: $path" }
  Get-Content $path | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $idx = $line.IndexOf("=")
    if ($idx -lt 1) { return }
    $k = $line.Substring(0, $idx).Trim()
    $v = $line.Substring($idx + 1).Trim()
    $map[$k] = $v
  }
  return $map
}

function Read-JsonFile([string]$path) {
  if (!(Test-Path $path)) { throw "JSON file not found: $path" }
  return (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

$env      = Read-DotEnv $TunnelEnvPath
$template = Get-Content $TemplatePath -Raw -Encoding UTF8
$rules    = Read-JsonFile $RulesJsonPath
$policy   = Read-JsonFile $PolicyPath

$domain = $env["TT_DOMAIN"]
if (!$domain) { throw "TT_DOMAIN is not set in: $TunnelEnvPath" }

$uuid = $env["TUNNEL_UUID"]
if (!$uuid) {
  Write-Host ""
  Write-Host "NOTE: TUNNEL_UUID is empty." -ForegroundColor Yellow
  Write-Host "  TOKEN MODE (Cloudflare dashboard routing): this is expected — no config.yml needed." -ForegroundColor DarkGray
  Write-Host "  CONFIG MODE (local config.yml): set TUNNEL_UUID= in $TunnelEnvPath" -ForegroundColor DarkGray
  Write-Host ""
  Write-Host "Skipping config.yml generation (TOKEN MODE detected)." -ForegroundColor Cyan
  exit 0
}

$routeEntries = @($policy.services | Where-Object {
  $_.public_capable -eq $true -and $_.toggle -and $_.subdomain_var -and $_.placeholder -and $_.rule_key
})
if ($routeEntries.Count -eq 0) {
  throw "No tunnel-capable services found in policy: $PolicyPath"
}

foreach ($r in $routeEntries) {
  if ($template.IndexOf([string]$r.placeholder) -lt 0) {
    throw "Template placeholder missing: $($r.placeholder)"
  }
  if (-not ($rules.PSObject.Properties.Name -contains [string]$r.rule_key)) {
    throw "Rule key missing in archived ingress-rules.json: $($r.rule_key)"
  }
}

foreach ($r in $routeEntries) {
  $toggle = [string]$r.toggle
  $subVar = [string]$r.subdomain_var
  $isEnabled = ($env.ContainsKey($toggle) -and $env[$toggle] -in @("true","1","yes"))

  if ($isEnabled) {
    if (-not $env.ContainsKey($subVar) -or [string]::IsNullOrWhiteSpace($env[$subVar])) {
      throw "Enabled route '$toggle' requires subdomain variable '$subVar' in: $TunnelEnvPath"
    }

    $ruleText = [string]$rules.($r.rule_key)
    foreach ($k in $env.Keys) {
      $ruleText = $ruleText -replace ([Regex]::Escape("`${$k}")), $env[$k]
    }
    $template = $template.Replace([string]$r.placeholder, $ruleText)
  } else {
    $template = $template.Replace([string]$r.placeholder, "")
  }
}

$template = $template -replace ([Regex]::Escape('${TUNNEL_UUID}')), $uuid
$template = $template -replace "(?m)^\s*$\n", ""

$outDir = Split-Path $OutPath -Parent
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutPath, $template, $utf8NoBom)

Write-Host "OK: Config generated → $OutPath" -ForegroundColor Green
$enabled = @($routeEntries | Where-Object { $env.ContainsKey([string]$_.toggle) -and $env[[string]$_.toggle] -in @("true","1","yes") })
Write-Host "  Active routes: $($enabled.Count)/$($routeEntries.Count)" -ForegroundColor DarkGray
foreach ($r in $enabled) {
  $sub = $env[[string]$r.subdomain_var]
  if ($sub) { Write-Host "    - $sub.$domain" -ForegroundColor DarkGray }
}
