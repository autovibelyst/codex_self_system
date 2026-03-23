param(
  [Parameter(Mandatory = $true)]
  [ValidateSet(
    "postgres", "redis", "n8n", "pgadmin", "redisinsight", "metabase",
    "kanboard", "wordpress", "mariadb", "qdrant", "ollama", "openwebui",
    "uptime-kuma", "portainer", "openclaw"
  )]
  [string] $Service,

  [string] $Root = (Join-Path $env:USERPROFILE 'stacks\tt-core')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_compose_args.ps1"
. "$PSScriptRoot\_profiles.ps1"
. "$PSScriptRoot\lib\RuntimeEnv.ps1"

$coreDir = Join-Path $Root "compose\tt-core"
$profiles = Get-TTProfilesForService -Service $Service

$composeArgs  = Get-TTComposeArgs -ComposeDir $coreDir
$coreEnvFile = Resolve-TTCoreEnvPath -RootPath $Root
$composeArgs += "--env-file", $coreEnvFile
foreach ($p in $profiles) { $composeArgs += "--profile", $p }

Push-Location $coreDir
try {
  # Stop only the specific service (does not cascade-stop dependencies)
  $stopArgs = $composeArgs + @("stop", $Service)
  docker compose @stopArgs

  $rmArgs   = $composeArgs + @("rm", "-f", $Service)
  docker compose @rmArgs
} finally {
  Pop-Location
}

Write-Host "OK: Service '$Service' stopped and removed." -ForegroundColor Green
