Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-BackupFolder {
  param([Parameter(Mandatory=$true)][string]$BaseDir)
  $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
  $path = Join-Path $BaseDir ("backup_{0}" -f $ts)
  New-Item -ItemType Directory -Force -Path $path | Out-Null
  return $path
}

function Write-Info($msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-Ok($msg)   { Write-Host $msg -ForegroundColor Green }

function Assert-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Missing required command: $name"
  }
}

function DockerCompose-Exec {
  param([Parameter(Mandatory=$true)][string]$ComposeDir,[Parameter(Mandatory=$true)][string[]]$Args)
  Push-Location $ComposeDir
  try {
    & docker compose @Args
    if ($LASTEXITCODE -ne 0) { throw "docker compose failed: $($Args -join ' ')" }
  } finally { Pop-Location }
}

function DockerCompose-ContainerId {
  param([Parameter(Mandatory=$true)][string]$ComposeDir,[Parameter(Mandatory=$true)][string]$Service)
  Push-Location $ComposeDir
  try { return (& docker compose ps -q $Service).Trim() }
  finally { Pop-Location }
}

function Get-EnvMap {
  param([Parameter(Mandatory=$true)][string]$EnvFile)
  $map = @{}
  if (!(Test-Path $EnvFile)) { return $map }
  foreach ($line in Get-Content $EnvFile) {
    if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { continue }
    $key = $line.Substring(0,$idx).Trim()
    $val = $line.Substring($idx+1).Trim()
    $map[$key] = $val
  }
  return $map
}

function Get-EnvOrDefault {
  param([hashtable]$Map,[string]$Key,[string]$Default='')
  if ($Map.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace($Map[$Key])) { return $Map[$Key] }
  return $Default
}
