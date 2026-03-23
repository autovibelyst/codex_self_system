# RuntimeEnv.ps1 - shared runtime env path resolution for TT-Core scripts
# Runtime secrets must live outside the repository tree.

Set-StrictMode -Version Latest

function Get-TTRuntimeSlug {
  param([Parameter(Mandatory = $true)][string]$RootPath)

  $normalized = $RootPath
  if ($normalized -match '^[A-Za-z]:\\') {
    $drive = $normalized.Substring(0,1).ToLower()
    $tail = $normalized.Substring(2).Replace('\\','/')
    $normalized = "/$drive$tail"
  } else {
    $normalized = $normalized.Replace('\\','/')
  }

  return ([regex]::Replace($normalized, '[/\\: ]', '_'))
}

function Get-TTRuntimeBaseDir {
  param([Parameter(Mandatory = $true)][string]$RootPath)

  if (-not [string]::IsNullOrWhiteSpace($env:TT_RUNTIME_DIR)) {
    return $env:TT_RUNTIME_DIR
  }

  $configHome = if (-not [string]::IsNullOrWhiteSpace($env:XDG_CONFIG_HOME)) {
    $env:XDG_CONFIG_HOME
  } else {
    Join-Path $HOME '.config'
  }

  $slug = Get-TTRuntimeSlug -RootPath $RootPath
  return (Join-Path (Join-Path $configHome 'tt-production\runtime') $slug)
}

function Get-TTRuntimeCoreEnvPath {
  param([Parameter(Mandatory = $true)][string]$RootPath)
  return (Join-Path (Get-TTRuntimeBaseDir -RootPath $RootPath) 'core.env')
}

function Get-TTRuntimeTunnelEnvPath {
  param([Parameter(Mandatory = $true)][string]$RootPath)
  return (Join-Path (Get-TTRuntimeBaseDir -RootPath $RootPath) 'tunnel.env')
}

function Get-TTLegacyCoreEnvPath {
  param([Parameter(Mandatory = $true)][string]$RootPath)
  return (Join-Path $RootPath 'compose\tt-core\.env')
}

function Get-TTLegacyTunnelEnvPath {
  param([Parameter(Mandatory = $true)][string]$RootPath)
  return (Join-Path $RootPath 'compose\tt-tunnel\.env')
}

function Test-TTPathExistsSafe {
  param([Parameter(Mandatory = $true)][string]$Path)

  try {
    return [bool](Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Stop)
  } catch {
    return $false
  }
}

function Resolve-TTCoreEnvPath {
  param([Parameter(Mandatory = $true)][string]$RootPath)

  $runtimePath = Get-TTRuntimeCoreEnvPath -RootPath $RootPath
  if (Test-TTPathExistsSafe -Path $runtimePath) {
    return $runtimePath
  }
  return (Get-TTLegacyCoreEnvPath -RootPath $RootPath)
}

function Resolve-TTTunnelEnvPath {
  param([Parameter(Mandatory = $true)][string]$RootPath)

  $runtimePath = Get-TTRuntimeTunnelEnvPath -RootPath $RootPath
  if (Test-TTPathExistsSafe -Path $runtimePath) {
    return $runtimePath
  }
  return (Get-TTLegacyTunnelEnvPath -RootPath $RootPath)
}
