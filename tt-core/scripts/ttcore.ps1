param(
  [Parameter(Position = 0)]
  [ValidateSet("up", "down", "restart", "ps", "status", "logs", "diag", "config")]
  [string] $Action = "ps",

  [Parameter(Position = 1)] [string] $Mode = "",
  [Parameter(Position = 2)] [string] $Name = ""
)

$ErrorActionPreference = "Stop"

function Resolve-Root {
  $here = Split-Path -Parent $MyInvocation.ScriptName
  return (Resolve-Path (Join-Path $here "..")).Path
}

$ROOT     = Resolve-Root
$CORE     = Join-Path $ROOT "compose\tt-core"
$DEPS_FILE = Join-Path $ROOT "scripts\deps.json"

. "$ROOT\scripts\_compose_args.ps1"
. "$ROOT\scripts\_profiles.ps1"
. "$ROOT\scripts\lib\RuntimeEnv.ps1"

function DC([string[]]$CmdArgs) {
  $files = Get-TTComposeArgs -ComposeDir $CORE
  $coreEnvFile = Resolve-TTCoreEnvPath -RootPath $ROOT
  $base  = @("compose") + $files + @("--env-file", $coreEnvFile)
  Push-Location $CORE
  try {
    docker @($base + $CmdArgs)
  } finally {
    Pop-Location
  }
}

function Load-Deps {
  if (!(Test-Path $DEPS_FILE)) { return @{} }
  return (Get-Content $DEPS_FILE -Raw | ConvertFrom-Json)
}

function Resolve-ServiceChain([string]$svc) {
  $deps    = Load-Deps
  $visited = New-Object System.Collections.Generic.HashSet[string]
  $result  = New-Object System.Collections.Generic.List[string]

  function Visit([string]$s) {
    if ($visited.Contains($s)) { return }
    [void]$visited.Add($s)
    if ($deps.PSObject.Properties.Name -contains $s) {
      foreach ($d in $deps.$s) { Visit $d }
    }
    [void]$result.Add($s)
  }

  Visit $svc
  return $result
}

switch ($Action) {

  "ps"     { DC @("ps"); exit 0 }
  "status" { & "$ROOT\scripts\Status-Core.ps1"; exit 0 }
  "config" { DC @("config"); exit 0 }
  "diag"   { & "$ROOT\scripts\Diag.ps1"; exit 0 }

  "logs" {
    if (-not $Name) { throw "Usage: ttcore.ps1 logs <service-name>" }
    DC @("logs", "-f", "--tail", "200", $Name)
    exit 0
  }

  "restart" {
    if ($Mode -eq "" -or $Mode -eq "core") {
      & "$ROOT\scripts\Restart-Core.ps1"
      exit 0
    }
    throw "Usage: ttcore.ps1 restart core"
  }

  "up" {
    switch ($Mode) {
      "core" {
        & "$ROOT\scripts\Start-Core.ps1"
        exit 0
      }
      "profile" {
        if (-not $Name) { throw "Usage: ttcore.ps1 up profile <profilename>" }
        DC @("--profile", $Name, "up", "-d")
        exit 0
      }
      "service" {
        if (-not $Name) { throw "Usage: ttcore.ps1 up service <servicename>" }
        & "$ROOT\scripts\Start-Service.ps1" -Service $Name
        exit 0
      }
      default { throw "Usage: ttcore.ps1 up core | up profile <n> | up service <n>" }
    }
  }

  "down" {
    switch ($Mode) {
      "core" {
        & "$ROOT\scripts\Stop-Core.ps1"
        exit 0
      }
      "service" {
        if (-not $Name) { throw "Usage: ttcore.ps1 down service <servicename>" }
        & "$ROOT\scripts\Stop-Service.ps1" -Service $Name
        exit 0
      }
      default { throw "Usage: ttcore.ps1 down core | down service <n>" }
    }
  }
}
