param(
  [Parameter(Mandatory=$true)][string]$BackupDir,
  [Parameter(Mandatory=$true)][string[]]$VolumeNames
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_lib\BackupLib.ps1")
Assert-Command docker

$volDir = Join-Path $BackupDir "volumes"
New-Item -ItemType Directory -Force -Path $volDir | Out-Null

foreach ($v in $VolumeNames) {
  $out = Join-Path $volDir ("{0}.tar" -f $v)
  Write-Info "Backing up volume $v → $out"
  & docker run --rm -v "${v}:/v:ro" -v "${volDir}:/out" alpine:3.20 sh -c "cd /v && tar -cf /out/$($v).tar ."
  if ($LASTEXITCODE -ne 0) { throw "Failed backing up volume: $v" }
}
Write-Ok "Volumes backup complete."
