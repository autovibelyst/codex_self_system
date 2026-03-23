param(
  [string] $Root    = (Join-Path $env:USERPROFILE 'stacks\tt-core'),
  [string] $Service = "",      # leave empty to show all services
  [int]    $Tail    = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_compose_args.ps1"
. "$PSScriptRoot\lib\RuntimeEnv.ps1"

$coreDir = Join-Path $Root "compose\tt-core"
$composeArgs = Get-TTComposeArgs -ComposeDir $coreDir
$coreEnvFile = Resolve-TTCoreEnvPath -RootPath $Root
$composeArgs += "--env-file", $coreEnvFile, "logs", "-f", "--tail", "$Tail"

if ($Service -ne "") {
  $composeArgs += $Service
}

Push-Location $coreDir
try {
  docker compose @composeArgs
} finally {
  Pop-Location
}
