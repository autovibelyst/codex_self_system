param(
  [string]$Root = (Join-Path $env:USERPROFILE 'stacks\tt-supabase'),
  [switch]$ProfileOptional,
  [switch]$PullOnly,
  [switch]$NoLock
)

$ErrorActionPreference = "Stop"

$compose = Join-Path $Root "compose\tt-supabase\docker-compose.yml"
if (!(Test-Path $compose)) { throw "Compose not found: $compose" }

Write-Host "== TT-Supabase update =="
docker compose -f $compose -p ttsupabase pull

if (-not $PullOnly) {
  if ($ProfileOptional) {
    docker compose -f $compose -p ttsupabase --profile optional up -d
  } else {
    docker compose -f $compose -p ttsupabase up -d
  }
}

if (-not $NoLock) {
  $lock = Join-Path $PSScriptRoot "Lock-ComposeImages.ps1"
  & $lock -ComposeFile $compose -ProjectName "ttsupabase" -OutDir (Join-Path $Root "compose\.locks")
}

Write-Host "Done."
