param(
  [string]$EnvFile = "..\compose\tt-supabase\.env"
)
$ErrorActionPreference = "Stop"
$compose = "..\compose\tt-supabase\docker-compose.yml"
docker compose --env-file $EnvFile -f $compose down
Write-Host "TT-Supabase stopped." -ForegroundColor Green
