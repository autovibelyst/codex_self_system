#Requires -Version 5.1
# =============================================================================
# ServiceCatalog.ps1 — TT-Core Canonical Service Metadata Library  (TT-Production v14.0)
#
# Dot-source this file:  . "$PSScriptRoot\lib\ServiceCatalog.ps1"
#
# CANONICAL SCHEMA (service-catalog.json):
#   Each service entry uses these fields:
#     service           : string — unique service key
#     compose_service   : string — docker-compose service name
#     kind              : "core" | "addon"
#     profile           : string | null — primary Docker Compose profile
#     additional_profiles: string[] (optional) — extra profiles required
#     tier              : "local_only" | "public_app" | "restricted_admin"
#     public_capable    : bool
#     auto_start_tunnel : bool
#     route_name        : string (present only when public_capable=true)
#     tunnel            : { toggle, subdomain_var, placeholder, rule_key }
#     health            : { port_env, probe_path, expected_codes,
#                           probe_required, probe_skip_unless_env? }
#     display_name      : string
#
# REGION 1 — Loaders           : catalog JSON, service entry, selection
# REGION 2 — Profile Helpers   : primary + additional_profiles (canonical)
# REGION 3 — Route / Tier      : route_name, tier filter, capable services, health
# REGION 4 — Security Gate     : Test-TTAdminRouteGateOpen (fail-closed)
#                                 Test-TTRouteEnabledForService (4-layer)
#
# SECURITY GATE CONTRACT (Test-TTAdminRouteGateOpen):
#   This function is the SINGLE SOURCE OF TRUTH for restricted_admin
#   tunnel route authorization. It is fail-closed by design:
#     Absent security key  → CLOSED
#     Absent property      → CLOSED
#     Explicit false       → CLOSED
#     Explicit true        → OPEN (operator explicitly acknowledged)
#   Callers MUST NOT invert or short-circuit this check.
#
# SCHEMA AUTHORITY:
#   Route name     → catalog entry field: route_name
#   Health targets → catalog entry field: health.probe_path (not health_endpoint)
#   Restricted check → catalog entry field: tier == "restricted_admin"
#   Profiles       → catalog entry fields: profile + additional_profiles[]
# =============================================================================

Set-StrictMode -Version Latest

# ── REGION 1 — Loaders ────────────────────────────────────────────────────────

function Get-TTServiceCatalog {
<#
.SYNOPSIS Returns the full parsed service catalog from config/service-catalog.json.
#>
  param([Parameter(Mandatory)][string]$Root)
  $path = Join-Path $Root 'config/service-catalog.json'
  if (!(Test-Path $path)) { throw "service-catalog.json not found at: $path" }
  return (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-TTServiceEntry {
<#
.SYNOPSIS Returns a single catalog entry by service name, or $null if not found.
#>
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Service
  )
  $catalog = Get-TTServiceCatalog -Root $Root
  return ($catalog.services | Where-Object { $_.service -eq $Service } | Select-Object -First 1)
}

function Get-TTServiceSelection {
<#
.SYNOPSIS Returns the parsed services.select.json selection object.
#>
  param([Parameter(Mandatory)][string]$Root)
  $path = Join-Path $Root 'config/services.select.json'
  if (!(Test-Path $path)) { throw "services.select.json not found at: $path" }
  return (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

# ── REGION 2 — Profile Helpers ────────────────────────────────────────────────

function Get-TTAllProfilesFromCatalog {
<#
.SYNOPSIS Returns all unique profile names defined across all catalog entries
         (primary profiles only — does not include additional_profiles).
#>
  param([Parameter(Mandatory)][string]$Root)
  $catalog = Get-TTServiceCatalog -Root $Root
  return @($catalog.services | Where-Object { -not [string]::IsNullOrWhiteSpace($_.profile) } |
           Select-Object -ExpandProperty profile -Unique)
}

function Get-TTProfilesForServiceFromCatalog {
<#
.SYNOPSIS Canonical: returns ALL profiles required by a service.
         Includes both the primary 'profile' field and 'additional_profiles' array.
         Returns an empty array for always-on (core) services with no profile.

.NOTES
  Canonical profile schema:
    profile            : string | null — primary Docker Compose profile
    additional_profiles: string[]      — optional extra profiles (e.g. ollama for openwebui)

  Both fields are included. De-duplicated. Empty strings ignored.
#>
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Service
  )
  $entry = Get-TTServiceEntry -Root $Root -Service $Service
  if ($null -eq $entry) { return @() }

  $result = [System.Collections.Generic.List[string]]::new()

  # Primary profile
  $p = [string]$entry.profile
  if (-not [string]::IsNullOrWhiteSpace($p)) { $result.Add($p) }

  # Additional profiles (e.g. openwebui requires ollama)
  $apProp = $entry.PSObject.Properties['additional_profiles']
  if ($null -ne $apProp -and $null -ne $apProp.Value) {
    foreach ($extra in @($apProp.Value)) {
      $es = [string]$extra
      if (-not [string]::IsNullOrWhiteSpace($es) -and -not $result.Contains($es)) {
        $result.Add($es)
      }
    }
  }

  return @($result)
}

function Get-TTProfilesForService {
<#
.SYNOPSIS Public wrapper for Get-TTProfilesForServiceFromCatalog.
         Returns ALL profiles (primary + additional) for a service.
         Call this — do not duplicate profile-resolution logic elsewhere.
#>
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Service
  )
  return Get-TTProfilesForServiceFromCatalog -Root $Root -Service $Service
}

# ── REGION 3 — Route / Tier / Health Helpers ──────────────────────────────────

function Get-TTRouteNameFromCatalogEntry {
<#
.SYNOPSIS Returns the tunnel route name for a catalog entry, or empty string.

.NOTES
  Canonical field: route_name
  This is the name used as the key in services.select.json tunnel.routes.
  Returns empty string if the entry has no route_name (local_only services).
#>
  param([Parameter(Mandatory)][psobject]$Entry)
  if ($null -eq $Entry) { return '' }
  $prop = $Entry.PSObject.Properties['route_name']
  if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
    return [string]$prop.Value
  }
  return ''
}

function Get-TTServicesByTierFromCatalog {
<#
.SYNOPSIS Returns all catalog entries matching a given tier value.
         Valid tiers: "local_only", "public_app", "restricted_admin"
#>
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Tier
  )
  $catalog = Get-TTServiceCatalog -Root $Root
  return @($catalog.services | Where-Object { [string]$_.tier -eq $Tier })
}

function Get-TTRouteCapableServicesFromCatalog {
<#
.SYNOPSIS Returns all catalog entries where public_capable = true.
#>
  param([Parameter(Mandatory)][string]$Root)
  $catalog = Get-TTServiceCatalog -Root $Root
  return @($catalog.services | Where-Object { $_.public_capable -eq $true })
}

function Get-TTServiceHealthTargets {
<#
.SYNOPSIS Returns services that have a defined health probe structure.

.NOTES
  Canonical health schema:
    health.port_env      : env var name holding host port (e.g. TT_N8N_HOST_PORT)
    health.probe_path    : HTTP path to probe (e.g. /healthz)
    health.expected_codes: array of acceptable HTTP codes
    health.probe_required: bool — if true, failure is an error (not a warning)
    health.probe_skip_unless_env: optional "KEY=VALUE" condition

  This function returns entries that have a 'health' object with a non-empty
  probe_path. Legacy field 'health_endpoint' is NOT used.
#>
  param([Parameter(Mandatory)][string]$Root)
  $catalog = Get-TTServiceCatalog -Root $Root
  return @($catalog.services | Where-Object {
    $h = $_.PSObject.Properties['health']
    if ($null -eq $h -or $null -eq $h.Value) { return $false }
    $pp = $h.Value.PSObject.Properties['probe_path']
    return ($null -ne $pp -and -not [string]::IsNullOrWhiteSpace([string]$pp.Value))
  })
}

# ── REGION 4 — Security Gate ──────────────────────────────────────────────────

function Test-TTAdminRouteGateOpen {
<#
.SYNOPSIS
  Returns $true ONLY when the operator has explicitly acknowledged
  security.allow_restricted_admin_tunnel_routes = true in services.select.json.

.NOTES
  FAIL-CLOSED contract — all paths default to CLOSED:
    Missing $Root / file unreadable  → CLOSED
    Absent  security section          → CLOSED
    Absent  property                  → CLOSED
    Explicit false                    → CLOSED
    Explicit true                     → OPEN  (operator intent confirmed)

  This is the single source of truth. Do NOT duplicate this logic.
  Do NOT invert or short-circuit the return value at call sites.
#>
  param([Parameter(Mandatory)][string]$Root)
  try {
    $selection = Get-TTServiceSelection -Root $Root
  } catch { return $false }
  if ($null -eq $selection.security) { return $false }
  $prop = $selection.security.PSObject.Properties['allow_restricted_admin_tunnel_routes']
  if ($null -eq $prop) { return $false }
  return ([bool]$prop.Value -eq $true)
}

function Test-TTRouteEnabledForService {
<#
.SYNOPSIS
  Returns $true only when ALL FOUR layers pass for a given service:
    Layer 1 — Capability    : catalog entry exists AND public_capable = true
    Layer 2 — Security Gate : if tier == "restricted_admin", Test-TTAdminRouteGateOpen must pass
    Layer 3 — Tunnel On     : selection.tunnel.enabled = true
    Layer 4 — Route On      : selection.tunnel.routes[route_name] = true

.NOTES
  Short-circuits at first failing layer — returns $false immediately.
  Layer 2 checks catalog tier field: tier == "restricted_admin" (not a boolean property).
  Layer 4 resolves route name from canonical catalog field: route_name.
#>
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Service
  )

  # Layer 1 — Capability
  $entry = Get-TTServiceEntry -Root $Root -Service $Service
  if ($null -eq $entry -or $entry.public_capable -ne $true) { return $false }

  # Layer 2 — Security Gate (tier == "restricted_admin")
  if ([string]$entry.tier -eq 'restricted_admin') {
    if (-not (Test-TTAdminRouteGateOpen -Root $Root)) { return $false }
  }

  # Layer 3 — Tunnel enabled
  $selection = Get-TTServiceSelection -Root $Root
  if ($null -eq $selection.tunnel -or $selection.tunnel.enabled -ne $true) { return $false }
  if ($null -eq $selection.tunnel.routes) { return $false }

  # Layer 4 — Specific route enabled (uses canonical route_name field)
  $routeName = Get-TTRouteNameFromCatalogEntry -Entry $entry
  if ([string]::IsNullOrWhiteSpace($routeName)) { return $false }
  $prop = $selection.tunnel.routes.PSObject.Properties[$routeName]
  if ($null -eq $prop) { return $false }
  return ([bool]$prop.Value -eq $true)
}
