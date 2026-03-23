param(
  [string] $Root = (Join-Path $env:USERPROFILE 'stacks\tt-core')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_compose_args.ps1"
. "$PSScriptRoot\lib\RuntimeEnv.ps1"

$coreDir = Join-Path $Root "compose\tt-core"

Push-Location $coreDir
try {
  $composeArgs = Get-TTComposeArgs -ComposeDir $coreDir
  $coreEnvFile = Resolve-TTCoreEnvPath -RootPath $Root
  $composeArgs += "--env-file", $coreEnvFile, "ps"
  docker compose @composeArgs
  ""
  docker ps --format "table {{.Names}}`t{{.Status}}`t{{.Ports}}"
} finally {
  Pop-Location
}
