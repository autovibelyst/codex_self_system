param(
  [string]$EnvFile = "..\compose\tt-supabase\.env",
  [switch]$WithPooler
)
$ErrorActionPreference = "Stop"

$compose = "..\compose\tt-supabase\docker-compose.yml"
$args = @("compose", "--env-file", $EnvFile, "-f", $compose)

if ($WithPooler) { $args += "--profile", "optional" }

$args += "up", "-d"
docker @args

Write-Host "TT-Supabase started." -ForegroundColor Green
