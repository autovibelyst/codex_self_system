#Requires -Version 5.1
<#
.SYNOPSIS
  TT-Production bootstrap installer for Windows.

.DESCRIPTION
  Downloads release assets from GitHub Releases, verifies SHA256, extracts the
  bundle, then delegates to tt-core\installer\Install-TTCore.ps1.
#>
param(
  [Parameter(Mandatory = $true)][string]$Owner,
  [string]$Repo = 'tt-production',
  [string]$Tag = 'v14.0',
  [string]$BundleName = 'TT-Production-v14.0',
  [ValidateSet('local-private', 'small-business', 'ai-workstation', 'public-productivity')]
  [string]$ProfileName = 'local-private',
  [string]$Timezone = '',
  [string]$RootPath = '',
  [string]$Domain = '',
  [switch]$WithTunnel,
  [switch]$NoStart
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function New-TempDir {
  $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tt-install-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $path | Out-Null
  return $path
}

function Get-ExpectedHash([string]$ShaFilePath) {
  $line = (Get-Content $ShaFilePath -Encoding UTF8 | Select-Object -First 1).Trim()
  if ([string]::IsNullOrWhiteSpace($line)) {
    throw "Checksum file is empty: $ShaFilePath"
  }
  return ($line -split '\s+')[0].Trim().ToLowerInvariant()
}

$assetZip = "$BundleName.zip"
$assetSha = "$assetZip.sha256"
$baseUrl = "https://github.com/$Owner/$Repo/releases/download/$Tag"

$workDir = New-TempDir
try {
  $zipPath = Join-Path $workDir $assetZip
  $shaPath = Join-Path $workDir $assetSha

  Write-Host "Downloading release assets from $Owner/$Repo@$Tag ..."
  Invoke-WebRequest -Uri "$baseUrl/$assetZip" -OutFile $zipPath
  Invoke-WebRequest -Uri "$baseUrl/$assetSha" -OutFile $shaPath

  $expectedHash = Get-ExpectedHash -ShaFilePath $shaPath
  $actualHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($expectedHash -ne $actualHash) {
    throw "SHA256 mismatch for $assetZip`nExpected: $expectedHash`nActual:   $actualHash"
  }
  Write-Host 'Checksum verified.' -ForegroundColor Green

  Expand-Archive -Path $zipPath -DestinationPath $workDir -Force
  $bundleRoot = Join-Path $workDir $BundleName
  $installer = Join-Path $bundleRoot 'tt-core\installer\Install-TTCore.ps1'
  if (!(Test-Path $installer)) {
    throw "Installer not found: $installer"
  }

  $installerArgs = @('-ProfileName', $ProfileName)
  if ($Timezone) { $installerArgs += @('-Timezone', $Timezone) }
  if ($RootPath) { $installerArgs += @('-RootPath', $RootPath) }
  if ($Domain) { $installerArgs += @('-Domain', $Domain) }
  if ($WithTunnel) { $installerArgs += '-WithTunnel' }
  if ($NoStart) { $installerArgs += '-NoStart' }

  Write-Host "Running installer with profile: $ProfileName"
  & $installer @installerArgs
}
finally {
  if (Test-Path $workDir) {
    Remove-Item -Path $workDir -Recurse -Force
  }
}
