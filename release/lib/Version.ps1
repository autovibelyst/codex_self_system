# release/lib/Version.ps1 — Canonical version reader for TT-Production (PowerShell)
# Usage: . "$PSScriptRoot/../release/lib/Version.ps1"
$_versionFile = Join-Path $PSScriptRoot "../version.json"
if (-not (Test-Path $_versionFile)) {
    throw "FATAL: release/version.json not found at $_versionFile"
}
$_v = Get-Content $_versionFile -Raw | ConvertFrom-Json
$TT_VERSION      = $_v.package_version
$TT_BUNDLE       = $_v.bundle_name
$TT_RELEASE_DATE = $_v.release_date
