param(
  [string]$EnvFile = "..\env\tt-supabase.env",
  [string]$Service = "",
  [int]   $Tail    = 200
)
$ErrorActionPreference = "Stop"
$compose = "..\compose\tt-supabase\docker-compose.yml"
$args = @("compose", "--env-file", $EnvFile, "-f", $compose, "logs", "-f", "--tail", "$Tail")
if ($Service -ne "") { $args += $Service }
docker @args
