param(
  [string]$EnvFile = "..\compose\tt-supabase\.env"
)
$ErrorActionPreference = "Stop"
$compose = "..\compose\tt-supabase\docker-compose.yml"
docker compose --env-file $EnvFile -f $compose ps
""
docker ps --filter "name=supabase" --format "table {{.Names}}`t{{.Status}}`t{{.Ports}}"
