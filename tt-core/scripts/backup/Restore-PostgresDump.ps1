#Requires -Version 5.1
param(
  [string]$TTCoreComposeDir = (Join-Path $env:USERPROFILE 'stacks\tt-core\compose\tt-core'),
  [Parameter(Mandatory=$true)][string]$DumpFile,
  [string]$PostgresServiceName = 'postgres',
  [string]$TargetDb = '',
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib\BackupLib.ps1')
Assert-Command docker

if (!(Test-Path $DumpFile)) { throw "Dump file not found: $DumpFile" }
$envFile = Join-Path $TTCoreComposeDir '.env'
if (!(Test-Path $envFile)) { throw "TT-Core .env not found: $envFile" }
$envMap = Get-EnvMap -EnvFile $envFile
$pgUser = Get-EnvOrDefault $envMap 'TT_POSTGRES_USER' 'ttcore'
$pgPass = Get-EnvOrDefault $envMap 'TT_POSTGRES_PASSWORD' ''

$base = [System.IO.Path]::GetFileNameWithoutExtension($DumpFile)
if ([string]::IsNullOrWhiteSpace($TargetDb)) {
  switch -Regex ($base) {
    '^ttcore$'      { $TargetDb = Get-EnvOrDefault $envMap 'TT_POSTGRES_DB' 'ttcore'; break }
    '^n8n$'         { $TargetDb = Get-EnvOrDefault $envMap 'TT_N8N_DB' 'n8n'; break }
    '^metabase_db$' { $TargetDb = Get-EnvOrDefault $envMap 'TT_METABASE_DB' 'metabase_db'; break }
    '^kanboard_db$' { $TargetDb = Get-EnvOrDefault $envMap 'TT_KANBOARD_DB' 'kanboard_db'; break }
    default         { throw 'Unable to infer target database from dump filename. Pass -TargetDb explicitly.' }
  }
}

$cid = DockerCompose-ContainerId -ComposeDir $TTCoreComposeDir -Service $PostgresServiceName
if (-not $cid) { throw "Cannot find container for service '$PostgresServiceName' in $TTCoreComposeDir" }

Write-Warn "About to restore '$DumpFile' into database '$TargetDb'. Existing data in that database may be overwritten."
if (-not $Force) {
  $answer = Read-Host 'Type YES to continue'
  if ($answer -ne 'YES') { throw 'Restore cancelled.' }
}

$tmpFile = "/tmp/{0}.dump" -f $base
& docker cp $DumpFile "${cid}:$tmpFile" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'docker cp failed while uploading the dump.' }

& docker exec -e PGPASSWORD=$pgPass $cid sh -lc "pg_restore -U '$pgUser' -d '$TargetDb' --clean --if-exists --no-owner --no-privileges '$tmpFile'"
$rc = $LASTEXITCODE
& docker exec $cid rm -f $tmpFile | Out-Null
if ($rc -ne 0) { throw 'pg_restore failed.' }
Write-Ok "Restore completed into '$TargetDb'."
