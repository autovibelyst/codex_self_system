#Requires -Version 5.1
param(
  [string]$TTCoreComposeDir = (Join-Path $env:USERPROFILE 'stacks\tt-core\compose\tt-core'),
  [string]$BackupDir = (Join-Path $env:USERPROFILE 'stacks\tt-core\_backups\manual'),
  [string]$PostgresServiceName = 'postgres'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib\BackupLib.ps1')
Assert-Command docker

$envFile = Join-Path $TTCoreComposeDir '.env'
if (!(Test-Path $envFile)) { throw "TT-Core .env not found: $envFile" }
$envMap = Get-EnvMap -EnvFile $envFile

$pgUser = Get-EnvOrDefault $envMap 'TT_POSTGRES_USER' 'ttcore'
$pgPass = Get-EnvOrDefault $envMap 'TT_POSTGRES_PASSWORD' ''
$dbList = @(
  Get-EnvOrDefault $envMap 'TT_POSTGRES_DB'  'ttcore'
  Get-EnvOrDefault $envMap 'TT_N8N_DB'       'n8n'
  Get-EnvOrDefault $envMap 'TT_METABASE_DB'  'metabase_db'
  Get-EnvOrDefault $envMap 'TT_KANBOARD_DB'  'kanboard_db'
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

Write-Info "Postgres dumps → $BackupDir"
$dumpsDir = Join-Path $BackupDir 'postgres'
New-Item -ItemType Directory -Force -Path $dumpsDir | Out-Null

$cid = DockerCompose-ContainerId -ComposeDir $TTCoreComposeDir -Service $PostgresServiceName
if (-not $cid) { throw "Cannot find container for service '$PostgresServiceName' in $TTCoreComposeDir" }

foreach ($db in $dbList) {
  $dumpFile = Join-Path $dumpsDir ("{0}.dump" -f $db)
  $tmpFile = "/tmp/{0}.dump" -f $db
  Write-Info "Dumping $db from container $cid → $dumpFile"

  & docker exec -e PGPASSWORD=$pgPass $cid sh -lc "pg_dump -U '$pgUser' -Fc '$db' -f '$tmpFile'" 2>$null
  if ($LASTEXITCODE -ne 0) {
    Write-Warn "Skipped database '$db' (it may not exist or is not yet initialized)."
    continue
  }

  & docker cp "${cid}:$tmpFile" $dumpFile | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "docker cp failed while exporting '$db'." }

  & docker exec $cid rm -f $tmpFile | Out-Null
  Write-Ok "Done: $dumpFile"
}
