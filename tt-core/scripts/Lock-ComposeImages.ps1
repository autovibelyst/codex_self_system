param(
  [Parameter(Mandatory=$true)][string]$ComposeFile,
  [Parameter(Mandatory=$true)][string]$ProjectName,
  [string]$OutDir = ".\compose\.locks"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path $ComposeFile)) { throw "Compose file not found: $ComposeFile" }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$services = docker compose -f $ComposeFile -p $ProjectName config --services
if (-not $services) { throw "No services returned from docker compose config --services" }

$rows = @()

foreach ($svc in $services) {
  $img = docker compose -f $ComposeFile -p $ProjectName config | Select-String -Pattern "^\s*$svc:\s*$" -Context 0,200 |
    ForEach-Object { $_.Context.PostContext } |
    Select-String -Pattern "^\s*image:\s*" |
    Select-Object -First 1 |
    ForEach-Object { ($_ -replace '^\s*image:\s*', '').Trim() }

  if (-not $img) { continue }

  $digest = docker image inspect $img --format "{{index .RepoDigests 0}}" 2>$null
  if (-not $digest) {
    $rows += [pscustomobject]@{ service=$svc; image=$img; repoDigest=$null; note="image not present locally (run compose pull)" }
    continue
  }

  $rows += [pscustomobject]@{ service=$svc; image=$img; repoDigest=$digest; note=$null }
}

$ts = Get-Date -Format "yyyyMMdd-HHmm"
$outFile = Join-Path $OutDir ("images-{0}-{1}.json" -f $ProjectName, $ts)

$payload = [pscustomobject]@{
  project = $ProjectName
  composeFile = (Resolve-Path $ComposeFile).Path
  createdAt = (Get-Date).ToString("o")
  items = $rows
}

$payload | ConvertTo-Json -Depth 6 | Out-File -FilePath $outFile -Encoding utf8
Write-Host "OK: wrote lock file -> $outFile"
