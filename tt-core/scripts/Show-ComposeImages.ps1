param(
  [Parameter(Mandatory=$true)][string]$ComposeFile,
  [Parameter(Mandatory=$true)][string]$ProjectName
)

$ErrorActionPreference = "Stop"
$services = docker compose -f $ComposeFile -p $ProjectName config --services
if (-not $services) { throw "No services returned." }

foreach ($svc in $services) {
  $img = docker compose -f $ComposeFile -p $ProjectName config | Select-String -Pattern "^\s*$svc:\s*$" -Context 0,200 |
    ForEach-Object { $_.Context.PostContext } |
    Select-String -Pattern "^\s*image:\s*" |
    Select-Object -First 1 |
    ForEach-Object { ($_ -replace '^\s*image:\s*', '').Trim() }
  if ($img) {
    $digest = docker image inspect $img --format "{{index .RepoDigests 0}}" 2>$null
    "{0,-25} {1,-65} {2}" -f $svc, $img, $digest
  }
}
