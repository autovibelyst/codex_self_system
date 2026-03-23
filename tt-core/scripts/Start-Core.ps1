param(
  [string]   $Root     = (Join-Path $env:USERPROFILE 'stacks\tt-core'),
  # If -Profiles is not supplied, profiles are derived from config\services.select.json
  # (the canonical selection authority). Pass -Profiles to override for testing only.
  [string[]] $Profiles = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_compose_args.ps1"
. "$PSScriptRoot\lib\RuntimeEnv.ps1"

# Auto-derive profiles from services.select.json if not explicitly passed.
if ($Profiles.Count -eq 0) {
  $selectPath = Join-Path $Root 'config\services.select.json'
  if (Test-Path $selectPath) {
    try {
      $sel = Get-Content $selectPath -Raw | ConvertFrom-Json
      $derivedProfiles = @()
      foreach ($entry in $sel.profiles.PSObject.Properties) {
        if ([bool]$entry.Value -and -not $entry.Name.StartsWith('_')) {
          $derivedProfiles += $entry.Name
        }
      }
      if ($derivedProfiles.Count -gt 0) {
        $Profiles = $derivedProfiles
        Write-Host "  [INFO] Profiles derived from config\services.select.json: $($Profiles -join ', ')" -ForegroundColor DarkGray
      } else {
        Write-Host "  [INFO] No optional profiles enabled in config\services.select.json - starting core only." -ForegroundColor DarkGray
      }
    } catch {
      Write-Host "  [WARN] Could not read services.select.json for profiles: $_" -ForegroundColor Yellow
    }
  }
}

$coreDir = Join-Path $Root 'compose\tt-core'
if (!(Test-Path (Join-Path $coreDir 'docker-compose.yml'))) {
  throw "docker-compose.yml not found in: $coreDir"
}

$composeArgs = Get-TTComposeArgs -ComposeDir $coreDir -EnabledProfiles $Profiles
$coreEnvFile = Resolve-TTCoreEnvPath -RootPath $Root
if (!(Test-Path $coreEnvFile)) {
  throw "Core env file not found: $coreEnvFile. Run scripts\Init-TTCore.ps1 first."
}
$composeArgs += '--env-file', $coreEnvFile

foreach ($p in $Profiles) {
  $composeArgs += '--profile', $p
}

$composeArgs += 'up', '-d'

Push-Location $coreDir
$composeExit = 0
try {
  docker compose @composeArgs
  $composeExit = $LASTEXITCODE
} finally {
  Pop-Location
}

if ($composeExit -ne 0) {
  throw "docker compose up failed with exit code $composeExit"
}

Write-Host ''
Write-Host 'OK: TT-Core started.' -ForegroundColor Green
if ($Profiles.Count -gt 0) {
  Write-Host "  Active profiles: $($Profiles -join ', ')" -ForegroundColor DarkGray
}
Write-Host '  Check status: scripts\Status-Core.ps1'