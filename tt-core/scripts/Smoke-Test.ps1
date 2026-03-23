#Requires -Version 5.1
param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot),
  [switch]$SkipHttp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/ServiceCatalog.ps1')
. (Join-Path $PSScriptRoot 'lib/RuntimeEnv.ps1')

$errors = 0
$warnings = 0

function Check([string]$Group,[string]$Name,[bool]$Ok,[string]$Detail='') {
  if ($Ok) {
    Write-Host ("[OK]   [{0}] {1} {2}" -f $Group,$Name,$Detail) -ForegroundColor Green
  } else {
    $script:errors++
    Write-Host ("[FAIL] [{0}] {1} {2}" -f $Group,$Name,$Detail) -ForegroundColor Red
  }
}
function Warn([string]$Group,[string]$Name,[string]$Detail='') {
  $script:warnings++
  Write-Host ("[WARN] [{0}] {1} {2}" -f $Group,$Name,$Detail) -ForegroundColor Yellow
}
function Info([string]$Detail) {
  Write-Host ("[INFO] {0}" -f $Detail) -ForegroundColor Cyan
}
function Get-EnvValue([string]$EnvPath,[string]$Key) {
  if (!(Test-Path $EnvPath)) { return $null }
  $content = Get-Content $EnvPath -Raw
  $m = [regex]::Match($content, '(?m)^' + [regex]::Escape($Key) + '=(.*)$')
  if ($m.Success) { return $m.Groups[1].Value.Trim() }
  return $null
}
function Read-JsonFile([string]$Path) { Get-Content $Path -Raw | ConvertFrom-Json }
function Test-SelectionProfileEnabled($Selection, [string]$Profile) {
  if ([string]::IsNullOrWhiteSpace($Profile)) { return $true }
  $prop = $Selection.profiles.PSObject.Properties[$Profile]
  return ($null -ne $prop -and [bool]$prop.Value)
}

$envFile = Resolve-TTCoreEnvPath -RootPath $Root
$selectFile = Join-Path $Root 'config/services.select.json'
$catalog = Get-TTServiceCatalog -Root $Root
$selection = if (Test-Path $selectFile) { Read-JsonFile $selectFile } else { $null }

Write-Host 'TT-Core Smoke Test' -ForegroundColor Cyan
Write-Host "Root: $Root" -ForegroundColor DarkGray

Write-Host ''
Write-Host '--- Docker Compose Services -------------------------------' -ForegroundColor Cyan
$coreCompose = Join-Path $Root 'compose/tt-core/docker-compose.yml'
try {
  $services = docker compose --env-file $envFile -f $coreCompose ps --format json 2>$null | ConvertFrom-Json
  if ($services) {
    foreach ($svc in $services) {
      $isRunning = $svc.State -eq 'running'
      Check 'Compose' $svc.Service $isRunning "(state=$($svc.State))"
    }
  } else {
    Warn 'Compose' 'ps' 'No compose services returned. Stack may be down.'
  }
} catch {
  Warn 'Compose' 'ps' 'Unable to query docker compose status.'
}

if (-not $SkipHttp) {
  Write-Host ''
  Write-Host '--- HTTP Probes -------------------------------------------' -ForegroundColor Cyan
  if (!(Test-Path $envFile)) {
    Warn 'HTTP' 'env' 'Runtime core env missing; skipping HTTP probe stage.'
  } else {
    $httpServices = Get-TTServiceHealthTargets -Root $Root
    foreach ($svc in $httpServices) {
      $profileEnabled = $true
      if ($selection -and $svc.profile) {
        $profileEnabled = Test-SelectionProfileEnabled -Selection $selection -Profile ([string]$svc.profile)
      }
      if (-not $profileEnabled) {
        Info "$($svc.display_name) profile disabled in services.select.json - skipping"
        continue
      }

      $probeSkipProp = $svc.health.PSObject.Properties['probe_skip_unless_env']
      if ($null -ne $probeSkipProp -and -not [string]::IsNullOrWhiteSpace([string]$probeSkipProp.Value)) {
        $parts = ([string]$probeSkipProp.Value).Split('=',2)
        if ($parts.Count -eq 2) {
          $actual = Get-EnvValue -EnvPath $envFile -Key $parts[0]
          if ([string]$actual -ne [string]$parts[1]) {
            Info "$($svc.display_name) probe skipped unless $($parts[0])=$($parts[1])"
            continue
          }
        }
      }

      $port = Get-EnvValue -EnvPath $envFile -Key ([string]$svc.health.port_env)
      if ([string]::IsNullOrWhiteSpace($port)) {
        Info "$($svc.display_name) port key $($svc.health.port_env) not set - skipping"
        continue
      }

      $url = "http://127.0.0.1:$port$([string]$svc.health.probe_path)"
      $codes = @($svc.health.expected_codes | ForEach-Object { [int]$_ })
      $required = [bool]$svc.health.probe_required
      try {
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        $ok = $codes -contains [int]$resp.StatusCode
        if ($required) {
          Check 'HTTP' $svc.display_name $ok "HTTP $($resp.StatusCode) <- $url"
        } elseif ($ok) {
          Check 'HTTP' $svc.display_name $true "(optional) HTTP $($resp.StatusCode)"
        } else {
          Warn 'HTTP' $svc.display_name "HTTP $($resp.StatusCode) (unexpected) <- $url"
        }
      } catch {
        $msg = $_.Exception.Message -replace "`r?`n",' '
        if ($required) {
          Check 'HTTP' $svc.display_name $false "Not reachable: $msg"
        } else {
          Info "$($svc.display_name) (optional) not reachable - may not be running"
        }
      }
    }
  }
}

Write-Host ''
Write-Host '--- Port Listeners ----------------------------------------' -ForegroundColor Cyan
try {
  $ports = @()
  foreach ($svc in Get-TTServiceHealthTargets -Root $Root) {
    $portVal = Get-EnvValue -EnvPath $envFile -Key ([string]$svc.health.port_env)
    $tmp = 0
    if ([int]::TryParse([string]$portVal, [ref]$tmp)) { $ports += $tmp }
  }
  $ports = @($ports | Select-Object -Unique | Sort-Object)
  if ($ports.Count -eq 0) {
    Info 'No catalog ports found for port listener scan.'
  } else {
    $listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
      Where-Object { $ports -contains $_.LocalPort } |
      Select-Object LocalAddress, LocalPort | Sort-Object LocalPort
    if ($listening) {
      $listening | ForEach-Object { Info "Port $($_.LocalPort) listening on $($_.LocalAddress)" }
    } else {
      Info 'No TT-Core ports detected listening yet (services may still be starting)'
    }
    Check 'Ports' 'scan' $true 'Port scan complete'
  }
} catch {
  Info 'Get-NetTCPConnection unavailable (non-Windows) - skipping port scan'
}

Write-Host ''
Write-Host '-----------------------------------------------------------' -ForegroundColor Cyan
if ($errors -eq 0 -and $warnings -eq 0) {
  Write-Host 'RESULT: ALL CHECKS PASSED' -ForegroundColor Green
  exit 0
} elseif ($errors -eq 0) {
  Write-Host "RESULT: PASSED with $warnings warning(s)" -ForegroundColor Yellow
  exit 0
} else {
  Write-Host "RESULT: FAILED - $errors error(s), $warnings warning(s)" -ForegroundColor Red
  exit 1
}