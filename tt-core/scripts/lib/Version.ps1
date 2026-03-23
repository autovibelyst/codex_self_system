# tt-core/scripts/lib/Version.ps1 — Canonical version reader
# Sources release/lib/Version.ps1 for all PowerShell scripts
$_scriptRoot = $PSScriptRoot
$_releaseLib = Join-Path $_scriptRoot "../../../release/lib/Version.ps1"
if (Test-Path $_releaseLib) {
    . $_releaseLib
} else {
    throw "Cannot find release/lib/Version.ps1 — ensure bundle structure is intact"
}
