# _compose_args.ps1 - internal helper
# Returns a flat array of -f args for docker compose.
# Dot-source this file in other scripts: . "$PSScriptRoot\_compose_args.ps1"

function Get-TTComposeArgs {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ComposeDir,

    [string[]]$EnabledProfiles = @()
  )

  $base = Join-Path $ComposeDir 'docker-compose.yml'
  if (!(Test-Path $base)) { throw "Base compose not found: $base" }

  $argList = @('-f', $base)

  $enabled = @($EnabledProfiles | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -ne '' })
  $enabledSet = @{}
  foreach ($p in $enabled) {
    $enabledSet[$p] = $true
  }

  $baseComposeRaw = Get-Content $base -Raw
  $baseHasQdrantService = $baseComposeRaw -match '(?m)^\s{2}qdrant:\s*$'

  # Map legacy addon files to canonical profile names.
  $addonProfileMap = @{
    '05-pgbouncer.addon.yml'   = 'pgbouncer'
    '05-wordpress.addon.yml'   = 'wordpress'
    '10-kanboard.addon.yml'    = 'kanboard'
    '20-openwebui.addon.yml'   = 'openwebui'
    '30-uptime-kuma.addon.yml' = 'uptime_kuma'
    '40-portainer.addon.yml'   = 'portainer'
    '50-openclaw.addon.yml'    = 'openclaw'
    '60-minio.addon.yml'       = 'minio'
    '70-monitoring.addon.yml'  = 'monitoring'
    '80-qdrant.addon.yml'      = 'qdrant'
  }

  $addonsDir = Join-Path $ComposeDir 'addons'
  if (Test-Path $addonsDir) {
    $addonFiles = Get-ChildItem -Path $addonsDir -Filter '*.yml' -File |
      Where-Object { $_.Name -notlike '00-template*' } |
      Sort-Object Name

    foreach ($f in $addonFiles) {
      if ($f.Name -eq '80-qdrant.addon.yml' -and $baseHasQdrantService) {
        continue
      }

      $requiredProfile = $addonProfileMap[$f.Name]
      if (-not [string]::IsNullOrWhiteSpace($requiredProfile)) {
        if (-not $enabledSet.ContainsKey($requiredProfile)) {
          continue
        }
      }

      $argList += @('-f', $f.FullName)
    }
  }

  return $argList
}