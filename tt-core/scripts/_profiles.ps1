# _profiles.ps1 — internal helper
# Canonical profile metadata now lives in config\service-catalog.json.

. "$PSScriptRoot\lib\ServiceCatalog.ps1"

function Get-TTAllProfiles {
  param([string]$Root = (Split-Path $PSScriptRoot -Parent))
  return Get-TTAllProfilesFromCatalog -Root $Root
}

function Get-TTProfilesForService {
  param(
    [Parameter(Mandatory = $true)][string]$Service,
    [string]$Root = (Split-Path $PSScriptRoot -Parent)
  )
  return Get-TTProfilesForServiceFromCatalog -Root $Root -Service $Service
}
