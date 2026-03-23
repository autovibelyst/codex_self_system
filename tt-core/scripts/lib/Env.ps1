#Requires -Version 5.1
# =============================================================================
# Env.ps1 — TT-Core Environment Helper Library  (TT-Production v14.0)
#
# Dot-source:  . "$PSScriptRoot\lib\Env.ps1"
#
# PUBLIC API:
#   Write-FileUtf8NoBom  — write lines as UTF-8 without BOM
#   Ensure-EnvFile       — copy .env.example → .env when .env absent
#   Read-EnvLines        — read raw lines from .env file
#   Upsert-EnvLine       — add or update a key=value in .env (idempotent)
#   Get-EnvValue         — read a single value from .env file (or $null)
#   New-RandomSecret     — generate a cryptographically random secret
#                          Formats: base64 | hex | alphanumeric
#   Ensure-EnvSecret     — generate + save secret ONLY when key is absent / __GENERATE__
#                          Safe to re-run: never overwrites existing non-empty secrets.
#                          Supports all three formats.
#   Ensure-EnvKey        — write a plain (non-secret) default value ONLY when key is absent
#                          Use for TT_N8N_EXECUTIONS_MODE, TT_PG_SHARED_BUFFERS, etc.
#                          Safe to re-run: never overwrites.
#   Sync-EnvKeys         — warn about keys in .env.example that are missing from .env
#
# CHANGE LOG:
#   v14.0 — New-RandomSecret: includes "alphanumeric" format
#            FIX: Ensure-EnvSecret: ValidateSet extended to include "alphanumeric"
#            NEW: Ensure-EnvKey function — writes plain default, never overwrites
# =============================================================================

Set-StrictMode -Version Latest

# ── File I/O ──────────────────────────────────────────────────────────────────

function Write-FileUtf8NoBom {
<#
.SYNOPSIS Writes string array to file as UTF-8 without BOM. Always overwrites.
#>
  param(
    [Parameter(Mandatory)] [string]   $Path,
    [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]] $Lines
  )
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllLines($Path, $Lines, $utf8NoBom)
}

function Ensure-EnvFile {
<#
.SYNOPSIS Copies .env.example → .env when .env is absent. No-op when .env exists.
#>
  param(
    [Parameter(Mandatory)] [string] $EnvPath,
    [Parameter(Mandatory)] [string] $ExamplePath
  )
  if (Test-Path $EnvPath) { return }
  if (Test-Path $ExamplePath) {
    Copy-Item $ExamplePath $EnvPath -Force
  } else {
    Write-FileUtf8NoBom -Path $EnvPath -Lines @()
  }
}

function Read-EnvLines {
<#
.SYNOPSIS Returns the raw lines of the .env file, or an empty array when missing.
#>
  param([Parameter(Mandatory)] [string] $EnvPath)
  if (-not (Test-Path $EnvPath)) { return @() }
  return Get-Content -LiteralPath $EnvPath -ErrorAction Stop
}

function Upsert-EnvLine {
<#
.SYNOPSIS Adds or replaces a KEY=VALUE line in .env. Preserves all other lines.
         Writes UTF-8 without BOM.
#>
  param(
    [Parameter(Mandatory)] [string] $EnvPath,
    [Parameter(Mandatory)] [string] $Key,
    [Parameter(Mandatory)] [string] $Value
  )
  $lines = Read-EnvLines -EnvPath $EnvPath
  if ($null -eq $lines) {
    $lines = @()
  } elseif ($lines -is [string]) {
    if ([string]::IsNullOrWhiteSpace([string]$lines)) {
      $lines = @()
    } else {
      $lines = @([string]$lines)
    }
  } else {
    $lines = @($lines)
  }
  $escaped = [Regex]::Escape($Key)
  $pattern = "^\s*$escaped\s*="
  $newLine = "$Key=$Value"
  $found   = $false

    $normalized = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $pattern) {
      if (-not $found) {
        $normalized += $newLine
        $found = $true
      }
      continue
    }
    $normalized += $lines[$i]
  }

  if (-not $found) {
    $normalized += $newLine
  }

  Write-FileUtf8NoBom -Path $EnvPath -Lines $normalized
}

function Get-EnvValue {
<#
.SYNOPSIS Returns the value for KEY from .env, or $null when absent/unreadable.
#>
  param(
    [Parameter(Mandatory)] [string] $EnvPath,
    [Parameter(Mandatory)] [string] $Key
  )
  $lines   = Read-EnvLines -EnvPath $EnvPath
  $escaped = [Regex]::Escape($Key)
  foreach ($l in $lines) {
    if ($l -match "^\s*$escaped\s*=\s*(.*)\s*$") { return $Matches[1] }
  }
  return $null
}

# ── Secret generation ─────────────────────────────────────────────────────────

function New-RandomSecret {
<#
.SYNOPSIS
  Generates a cryptographically random secret.

.PARAMETER Format
  base64      — URL-safe Base64 (default). Good for general-purpose secrets.
  hex         — lowercase hexadecimal. Good for Redis passwords, tokens.
  alphanumeric — A-Z a-z 0-9 only. Use for RedisInsight RI_APP_PASSWORD and
                 other tools that reject special characters in passwords.

.PARAMETER Bytes
  Number of random bytes consumed. Actual output length varies by format:
    base64:      ceil(Bytes * 4/3) chars (padded)
    hex:         Bytes * 2 chars
    alphanumeric: Bytes chars (each byte maps to one character via modulo)

.NOTES
  Uses [System.Security.Cryptography.RandomNumberGenerator] — not Math.Random.
  The alphanumeric implementation uses rejection-less modulo; character set has
  62 members (2^6 - 2), so modulo bias is < 3% — acceptable for passwords.
#>
  param(
    [ValidateSet("base64","hex","alphanumeric")]
    [string] $Format = "base64",
    [int]    $Bytes  = 32
  )

  $buf = [byte[]]::new($Bytes)
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)

  switch ($Format) {
    "hex" {
      return ([BitConverter]::ToString($buf) -replace '-','').ToLower()
    }
    "alphanumeric" {
      $chars  = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
      $result = [System.Text.StringBuilder]::new($Bytes)
      foreach ($b in $buf) {
        $null = $result.Append($chars[$b % $chars.Length])
      }
      return $result.ToString()
    }
    default {
      return [Convert]::ToBase64String($buf)
    }
  }
}

function Ensure-EnvSecret {
<#
.SYNOPSIS
  Generates a random secret and writes it to .env ONLY when the key is absent
  or set to the placeholder __GENERATE__.

  SAFE TO RE-RUN — never overwrites existing non-empty secrets.

.PARAMETER Format
  base64 | hex | alphanumeric  (see New-RandomSecret for details)

.RETURNS  The existing or newly generated secret value.
#>
  param(
    [Parameter(Mandatory)] [string] $EnvPath,
    [Parameter(Mandatory)] [string] $Key,
    [ValidateSet("base64","hex","alphanumeric")]
    [string] $Format = "base64",
    [int]    $Bytes  = 32
  )
    $existing = Get-EnvValue -EnvPath $EnvPath -Key $Key
  if ([string]::IsNullOrWhiteSpace($existing) -or $existing -eq '__GENERATE__') {
    $secret = New-RandomSecret -Format $Format -Bytes $Bytes
    Upsert-EnvLine -EnvPath $EnvPath -Key $Key -Value $secret
    return $secret
  }

  # Keep file canonical: collapse duplicate key lines to one entry.
  Upsert-EnvLine -EnvPath $EnvPath -Key $Key -Value $existing
  return $existing
}

function Ensure-EnvKey {
<#
.SYNOPSIS
  Writes a plain (non-secret) default value to .env ONLY when the key is absent,
  empty, or set to the placeholder __GENERATE__.

  Use for non-secret operational defaults such as:
    TT_N8N_EXECUTIONS_MODE   (default: queue)
    TT_PG_SHARED_BUFFERS     (default: 256MB)
    TT_PG_MAX_CONNECTIONS    (default: 200)
    TT_PG_WORK_MEM           (default: 4MB)
    TT_BIND_IP               (default: 127.0.0.1)
    TT_TZ                    (default: UTC)

  SAFE TO RE-RUN — never overwrites an operator-set value.
  Does NOT generate secrets — use Ensure-EnvSecret for passwords / tokens.

.RETURNS  The existing or newly written default value.
#>
  param(
    [Parameter(Mandatory)] [string] $EnvPath,
    [Parameter(Mandatory)] [string] $Key,
    [Parameter(Mandatory)] [string] $Value
  )
    $existing = Get-EnvValue -EnvPath $EnvPath -Key $Key
  if (-not [string]::IsNullOrWhiteSpace($existing) -and $existing -ne '__GENERATE__') {
    # Keep file canonical: collapse duplicate key lines to one entry.
    Upsert-EnvLine -EnvPath $EnvPath -Key $Key -Value $existing
    return $existing
  }
  Upsert-EnvLine -EnvPath $EnvPath -Key $Key -Value $Value
  return $Value
}

# ── Key sync / audit ──────────────────────────────────────────────────────────

function Sync-EnvKeys {
<#
.SYNOPSIS
  Compares .env against .env.example and warns about missing keys.
  Returns $true when no keys are missing, $false otherwise.
#>
  param(
    [Parameter(Mandatory)] [string] $EnvPath,
    [Parameter(Mandatory)] [string] $ExamplePath,
    [switch] $Quiet
  )

  if (-not (Test-Path $ExamplePath)) {
    Write-Warning "Sync-EnvKeys: example file not found: $ExamplePath"
    return $true
  }

  $parseKeys = {
    param([string]$FilePath)
    $keys = @()
    foreach ($line in (Get-Content $FilePath -ErrorAction Stop)) {
      $line = $line.Trim()
      if ($line -eq '' -or $line.StartsWith('#')) { continue }
      $idx = $line.IndexOf('=')
      if ($idx -lt 1) { continue }
      $keys += $line.Substring(0, $idx).Trim()
    }
    return $keys
  }

  $exampleKeys = & $parseKeys $ExamplePath
  $currentKeys = if (Test-Path $EnvPath) { & $parseKeys $EnvPath } else { @() }

  $missing = @($exampleKeys | Where-Object { $_ -notin $currentKeys })

  if ($missing.Count -eq 0) {
    if (-not $Quiet) {
      Write-Host "  [ENV SYNC] All keys present." -ForegroundColor Green
    }
    return $true
  }

  Write-Host "" -ForegroundColor Yellow
  Write-Host "  [ENV SYNC] WARNING: Keys in .env.example but MISSING from .env:" -ForegroundColor Yellow
  foreach ($k in $missing) {
    Write-Host "    MISSING: $k" -ForegroundColor Yellow
  }
  Write-Host "  Run Init-TTCore.ps1 or manually add the missing keys." -ForegroundColor Yellow
  Write-Host ""
  return $false
}
