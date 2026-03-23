#Requires -Version 5.1
# =============================================================================
# Init-Supabase.ps1  (TT-Production v14.0)
#
# Initializes the TT-Supabase .env file with correct secrets.
#
# CRITICAL CORRECTNESS:
#   ANON_KEY and SERVICE_ROLE_KEY MUST be valid JWTs signed with JWT_SECRET.
#   Supabase does NOT accept arbitrary base64 strings for these keys.
#   This script generates properly-signed HS256 JWTs automatically.
#
# Usage:
#   # Default: looks for tt-supabase bundle next to tt-core
#   scripts\Init-Supabase.ps1
#
#   # Custom path:
#   scripts\Init-Supabase.ps1 -SupabaseRoot C:\stacks\tt-supabase
#
# After running:
#   1. Edit compose/tt-supabase/.env — set your domain, SMTP, org name
#   2. Run: scripts\Preflight-Check.ps1 -IncludeSupabase
#   3. Start: tt-supabase\scripts\start.ps1
# =============================================================================
param(
  [string]$SupabaseRoot = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tt-supabase')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Env.ps1')

$envFile  = Join-Path $SupabaseRoot 'compose\tt-supabase\.env'
$example  = Join-Path $SupabaseRoot 'env\tt-supabase.env.example'
$envDir   = Split-Path -Parent $envFile

if (!(Test-Path $SupabaseRoot)) { throw "TT-Supabase bundle not found at: $SupabaseRoot" }
if (!(Test-Path $example))      { throw "Env example not found: $example" }

# Ensure target directory exists
if (!(Test-Path $envDir)) { New-Item -ItemType Directory -Path $envDir -Force | Out-Null }

Ensure-EnvFile -EnvPath $envFile -ExamplePath $example

Write-Host ""
Write-Host "TT-Supabase Init: generating secrets..." -ForegroundColor Cyan

# ── Standard secrets ─────────────────────────────────────────────────────────
Ensure-EnvSecret -EnvPath $envFile -Key 'POSTGRES_PASSWORD' -Format 'base64' -Bytes 24 | Out-Null
Ensure-EnvSecret -EnvPath $envFile -Key 'LOGFLARE_API_KEY'  -Format 'hex'    -Bytes 20 | Out-Null
Ensure-EnvSecret -EnvPath $envFile -Key 'DASHBOARD_PASSWORD' -Format 'base64' -Bytes 18 | Out-Null

# ── JWT_SECRET must exist before we generate the JWT tokens ─────────────────
$jwtSecret = Ensure-EnvSecret -EnvPath $envFile -Key 'JWT_SECRET' -Format 'base64' -Bytes 40

# ── JWT token generation ──────────────────────────────────────────────────────
# ANON_KEY and SERVICE_ROLE_KEY are HS256 JWTs signed with JWT_SECRET.
# They must be valid JWTs — Supabase will reject arbitrary base64 strings.
function New-SupabaseJwt {
  param(
    [Parameter(Mandatory)] [string] $Secret,
    [Parameter(Mandatory)] [string] $Role
  )
  # HMAC-SHA256 signing in pure PowerShell
  function ConvertTo-Base64Url([byte[]]$Bytes) {
    return [Convert]::ToBase64String($Bytes).Replace('+','-').Replace('/','_').TrimEnd('=')
  }

  $now = [DateTimeOffset]::UtcNow
  $iat = $now.ToUnixTimeSeconds()
  # 10 years expiry — standard for anon/service_role tokens
  $exp = $now.AddYears(10).ToUnixTimeSeconds()

  $headerObj  = '{"alg":"HS256","typ":"JWT"}'
  $payloadObj = "{`"role`":`"$Role`",`"iss`":`"supabase`",`"iat`":$iat,`"exp`":$exp}"

  $headerB64  = ConvertTo-Base64Url ([System.Text.Encoding]::UTF8.GetBytes($headerObj))
  $payloadB64 = ConvertTo-Base64Url ([System.Text.Encoding]::UTF8.GetBytes($payloadObj))

  $sigInput = "$headerB64.$payloadB64"
  $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($Secret)
  $hmac     = New-Object System.Security.Cryptography.HMACSHA256
  $hmac.Key = $keyBytes
  $sigBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sigInput))
  $sigB64   = ConvertTo-Base64Url $sigBytes

  return "$sigInput.$sigB64"
}

# Only generate JWTs if they are still placeholder or missing
$existingAnon    = Get-EnvValue -EnvPath $envFile -Key 'ANON_KEY'
$existingService = Get-EnvValue -EnvPath $envFile -Key 'SERVICE_ROLE_KEY'

if ([string]::IsNullOrWhiteSpace($existingAnon) -or $existingAnon -eq '__GENERATE__') {
  $anonJwt = New-SupabaseJwt -Secret $jwtSecret -Role 'anon'
  Upsert-EnvLine -EnvPath $envFile -Key 'ANON_KEY' -Value $anonJwt
  Write-Host "  [OK] ANON_KEY        — JWT (anon role, HS256) generated" -ForegroundColor Green
} else {
  Write-Host "  [--] ANON_KEY        — already set, skipped" -ForegroundColor DarkGray
}

if ([string]::IsNullOrWhiteSpace($existingService) -or $existingService -eq '__GENERATE__') {
  $serviceJwt = New-SupabaseJwt -Secret $jwtSecret -Role 'service_role'
  Upsert-EnvLine -EnvPath $envFile -Key 'SERVICE_ROLE_KEY' -Value $serviceJwt
  Write-Host "  [OK] SERVICE_ROLE_KEY — JWT (service_role, HS256) generated" -ForegroundColor Green
} else {
  Write-Host "  [--] SERVICE_ROLE_KEY — already set, skipped" -ForegroundColor DarkGray
}

# ── Verify env completeness ───────────────────────────────────────────────────
Write-Host ""
Write-Host "TT-Supabase Init: checking for missing keys..." -ForegroundColor Cyan
Sync-EnvKeys -EnvPath $envFile -ExamplePath $example

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TT-Supabase secrets initialized." -ForegroundColor Green
Write-Host " Env file: $envFile"
Write-Host ""
Write-Host " REQUIRED: Edit the following before starting:" -ForegroundColor Yellow
Write-Host "   SUPABASE_PUBLIC_URL  — your real Supabase domain"
Write-Host "   API_EXTERNAL_URL     — usually same as SUPABASE_PUBLIC_URL"
Write-Host "   SITE_URL             — your frontend app URL"
Write-Host "   STUDIO_DEFAULT_ORGANIZATION / PROJECT — org and project name"
Write-Host "   SMTP_* keys          — for real email delivery (or leave empty for dev)"
Write-Host ""
Write-Host " Next step:"
Write-Host "   scripts\Preflight-Check.ps1 -IncludeSupabase"
Write-Host " Then start:"
Write-Host "   tt-supabase\scripts\start.ps1"
Write-Host "============================================================" -ForegroundColor Cyan
