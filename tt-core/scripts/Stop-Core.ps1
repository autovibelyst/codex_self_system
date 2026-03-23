param(
  [string] $Root = (Join-Path $env:USERPROFILE 'stacks\tt-core'),
  [switch] $Volumes   # pass -Volumes to also remove volume containers (DESTRUCTIVE)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_compose_args.ps1"
. "$PSScriptRoot\lib\RuntimeEnv.ps1"

$coreDir = Join-Path $Root "compose\tt-core"
$composeArgs = Get-TTComposeArgs -ComposeDir $coreDir
$coreEnvFile = Resolve-TTCoreEnvPath -RootPath $Root
$composeArgs += "--env-file", $coreEnvFile, "down"

if ($Volumes) {
  Write-Warning "WARNING: -Volumes flag removes Docker volumes. Bind-mount data in ./volumes/ is safe but named volumes (if any) will be deleted."
  $composeArgs += "-v"
}

Push-Location $coreDir
try {
  docker compose @composeArgs
} finally {
  Pop-Location
}

Write-Host "OK: TT-Core stopped." -ForegroundColor Green
