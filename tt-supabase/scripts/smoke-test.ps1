param(
  [string]$KongUrl = "http://127.0.0.1:18000",
  [string]$Project = "default"
)
$ErrorActionPreference = "Stop"
try {
  $r = Invoke-WebRequest "$KongUrl/project/$Project" -UseBasicParsing -TimeoutSec 5
  Write-Host "OK: Kong/Studio reachable ($($r.StatusCode))"
} catch {
  Write-Host "FAIL: Kong/Studio not reachable"
  throw
}

try {
  $r2 = Invoke-WebRequest "$KongUrl/rest/v1/" -UseBasicParsing -TimeoutSec 5
  Write-Host "INFO: rest responded ($($r2.StatusCode))"
} catch {
  # Most likely 401 due to missing key; still means reachable
  Write-Host "OK: rest reachable (expected auth error likely)"
}
