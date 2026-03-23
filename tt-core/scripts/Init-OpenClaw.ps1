#Requires -Version 5.1
<#
.SYNOPSIS
    Initialize and configure the TT-Core OpenClaw AI Agent addon.

.DESCRIPTION
    Guides through the complete OpenClaw setup process:
    1. Verifies openclaw_source exists (or clones it)
    2. Ensures volume directories exist
    3. Copies openclaw_template.json for reference
    4. Builds the Docker image
    5. Starts the container in SETUP MODE
    6. Guides through the onboarding wizard
    7. Validates openclaw.json after wizard
    8. Switches to PRODUCTION MODE

.PARAMETER Root
    TT-Core root folder. Default: %USERPROFILE%\stacks\tt-core

.PARAMETER SkipBuild
    Skip Docker image build (use cached image).

.PARAMETER SkipClone
    Skip git clone check (if you already have openclaw_source).

.EXAMPLE
    .\Init-OpenClaw.ps1
    .\Init-OpenClaw.ps1 -Root "C:\projects\tt-core" -SkipBuild
#>
param(
    [string]$Root      = (Join-Path $env:USERPROFILE 'stacks\tt-core'),
    [switch]$SkipBuild,
    [switch]$SkipClone
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. "$PSScriptRoot\lib\Env.ps1"
. "$PSScriptRoot\lib\RuntimeEnv.ps1"

$coreDir     = Join-Path $Root "compose\tt-core"
$envFile     = Resolve-TTCoreEnvPath -RootPath $Root
$sourceDir   = Join-Path $coreDir "openclaw_source"
$sourceRef   = Get-EnvValue -EnvPath $envFile -Key "TT_OPENCLAW_SOURCE_REF" -ErrorAction SilentlyContinue
$volDataDir  = Join-Path $coreDir "volumes\openclaw\data"
$volCfgDir   = Join-Path $coreDir "volumes\openclaw\config"
$templateSrc = Join-Path $volCfgDir "openclaw_template.json"
$configDst   = Join-Path $volDataDir "openclaw.json"

# ── Header ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   TT-Core OpenClaw Setup Wizard v14.0     ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Check prerequisites ─────────────────────────────────────────────
Write-Host "── Step 1: Prerequisites ─────────────────────────────────" -ForegroundColor Cyan

if (!(Test-Path $envFile)) {
    Write-Host "  [ERR] .env not found at $envFile" -ForegroundColor Red
    Write-Host "        Run Init-TTCore.ps1 first." -ForegroundColor Yellow
    exit 1
}

if (!(Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker not found. Install Docker Desktop first."
}
Write-Host "  [OK]  Docker available" -ForegroundColor Green

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  [WARN] git not found — you'll need to clone openclaw_source manually." -ForegroundColor Yellow
} else {
    Write-Host "  [OK]  git available" -ForegroundColor Green
}

# ── Step 2: Clone OpenClaw source (if not present) ──────────────────────────
Write-Host ""
Write-Host "── Step 2: OpenClaw Source ───────────────────────────────" -ForegroundColor Cyan

if (Test-Path $sourceDir) {
    Write-Host "  [OK]  openclaw_source found at $sourceDir" -ForegroundColor Green
} elseif ($SkipClone) {
    Write-Host "  [WARN] -SkipClone set but openclaw_source missing at $sourceDir" -ForegroundColor Yellow
    Write-Host "         Build will fail unless source exists." -ForegroundColor Yellow
} else {
    if (!(Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "  [ERR] openclaw_source not found and git is unavailable." -ForegroundColor Red
        Write-Host ""
        Write-Host "  Manual steps:" -ForegroundColor Yellow
        Write-Host "    1. Install git: https://git-scm.com/downloads" -ForegroundColor Yellow
        Write-Host "    2. Run: git clone https://github.com/openclaw/openclaw.git `"$sourceDir`"" -ForegroundColor Yellow
        Write-Host "    3. Re-run this script." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "  Cloning OpenClaw source..." -ForegroundColor DarkGray
    git clone "https://github.com/openclaw/openclaw.git" $sourceDir
    if ($LASTEXITCODE -ne 0) { throw "git clone failed. Check your internet connection." }
    Write-Host "  [OK]  Cloned to $sourceDir" -ForegroundColor Green
}

if ([string]::IsNullOrWhiteSpace($sourceRef) -or $sourceRef -eq "__PIN_GIT_TAG_OR_COMMIT__") {
    Write-Host "  [WARN] TT_OPENCLAW_SOURCE_REF is not pinned yet." -ForegroundColor Yellow
    Write-Host "         Set a real git tag or commit in the runtime core env before enabling OpenClaw in production." -ForegroundColor Yellow
} elseif ($sourceRef -eq "openclaw/main-unpinned") {
    Write-Host "  [WARN] openclaw/main-unpinned is a development-only value and must not be used for commercial production." -ForegroundColor Yellow
    Write-Host "         Replace it with a real tag or commit before continuing." -ForegroundColor Yellow
} elseif (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "  Pinning source checkout to: $sourceRef" -ForegroundColor DarkGray
    git -C $sourceDir fetch --all --tags
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed for openclaw_source." }
    git -C $sourceDir checkout $sourceRef
    if ($LASTEXITCODE -ne 0) { throw "git checkout failed for TT_OPENCLAW_SOURCE_REF=$sourceRef" }
    Write-Host "  [OK]  OpenClaw source pinned to $sourceRef" -ForegroundColor Green
} else {
    Write-Host "  [WARN] git is unavailable — cannot enforce TT_OPENCLAW_SOURCE_REF=$sourceRef automatically." -ForegroundColor Yellow
}

# ── Step 3: Ensure volume directories ───────────────────────────────────────
Write-Host ""
Write-Host "── Step 3: Volume Directories ────────────────────────────" -ForegroundColor Cyan

foreach ($d in @($volDataDir, "$volDataDir\state", "$volDataDir\workspace", $volCfgDir)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
Write-Host "  [OK]  Volume dirs ready: $volDataDir" -ForegroundColor Green

# ── Step 4: Ensure TT_OPENCLAW_TOKEN is generated ───────────────────────────
Write-Host ""
Write-Host "── Step 4: Secrets ───────────────────────────────────────" -ForegroundColor Cyan

$token = Get-EnvValue -EnvPath $envFile -Key "TT_OPENCLAW_TOKEN" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($token) -or $token -like "*GENERATE*") {
    $token = New-RandomSecret -Format "hex" -Bytes 32
    Upsert-EnvLine -EnvPath $envFile -Key "TT_OPENCLAW_TOKEN" -Value $token
    Write-Host "  [OK]  Generated TT_OPENCLAW_TOKEN" -ForegroundColor Green
} else {
    Write-Host "  [OK]  TT_OPENCLAW_TOKEN already set" -ForegroundColor Green
}

# ── Step 5: Build Docker image ───────────────────────────────────────────────
Write-Host ""
Write-Host "── Step 5: Build Docker Image ────────────────────────────" -ForegroundColor Cyan

if ($SkipBuild) {
    Write-Host "  [SKIP] -SkipBuild set — using cached image." -ForegroundColor DarkGray
} else {
    Write-Host "  Building OpenClaw image (this takes 2-5 minutes on first run)..." -ForegroundColor DarkGray
    Push-Location $coreDir
    try {
        docker compose -f docker-compose.yml -f addons\50-openclaw.addon.yml --env-file $envFile build --no-cache openclaw
        if ($LASTEXITCODE -ne 0) { throw "docker compose build failed." }
        Write-Host "  [OK]  Image built successfully." -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

# ── Step 6: Ensure SETUP MODE, start container ──────────────────────────────
Write-Host ""
Write-Host "── Step 6: Start in Setup Mode ───────────────────────────" -ForegroundColor Cyan

# Ensure mode is "setup" for wizard
Upsert-EnvLine -EnvPath $envFile -Key "TT_OPENCLAW_MODE" -Value "setup"

Push-Location $coreDir
try {
    docker compose -f docker-compose.yml -f addons\50-openclaw.addon.yml --env-file $envFile --profile openclaw up -d openclaw
    if ($LASTEXITCODE -ne 0) { throw "Failed to start openclaw container." }
} finally {
    Pop-Location
}

Start-Sleep -Seconds 3
Write-Host "  [OK]  Container tt-core-openclaw started in SETUP MODE." -ForegroundColor Green

# ── Step 7: Onboarding wizard instructions ───────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║              WIZARD — MANUAL STEPS REQUIRED                 ║" -ForegroundColor Yellow
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Yellow
Write-Host "║                                                              ║" -ForegroundColor Yellow
Write-Host "║  Run this command NOW in a NEW terminal:                     ║" -ForegroundColor Yellow
Write-Host "║                                                              ║" -ForegroundColor Yellow
Write-Host "║  docker exec -it tt-core-openclaw openclaw onboard --install-daemon" -ForegroundColor White
Write-Host "║                                                              ║" -ForegroundColor Yellow
Write-Host "║  Wizard prompts:                                             ║" -ForegroundColor Yellow
Write-Host "║    Gateway  → select: Local                                  ║" -ForegroundColor Yellow
if ((Get-EnvValue -EnvPath $envFile -Key "TT_OPENCLAW_GEMINI_KEY" -ErrorAction SilentlyContinue) -ne "") {
    Write-Host "║    Model    → select: Gemini → paste key → gemini-2.5-flash  ║" -ForegroundColor Yellow
} else {
    Write-Host "║    Model    → select: Ollama → URL: http://tt-core-ollama:11434║" -ForegroundColor Yellow
}
Write-Host "║    Channel  → select: Telegram → paste your Bot Token       ║" -ForegroundColor Yellow
Write-Host "║    Username → enter your Telegram @username                  ║" -ForegroundColor Yellow
Write-Host "║                                                              ║" -ForegroundColor Yellow
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Press ENTER here after the wizard completes..." -ForegroundColor Cyan
Read-Host | Out-Null

# ── Step 8: Validate and fix openclaw.json ───────────────────────────────────
Write-Host ""
Write-Host "── Step 8: Validate Config ───────────────────────────────" -ForegroundColor Cyan

if (!(Test-Path $configDst)) {
    Write-Host "  [ERR] openclaw.json not found at $configDst" -ForegroundColor Red
    Write-Host "        The wizard may not have completed. Re-run Step 6." -ForegroundColor Yellow
    exit 1
}

$cfg = Get-Content $configDst -Raw | ConvertFrom-Json

$issues = @()

# Check 1: bind must be "lan"
if ($cfg.gateway.bind -ne "lan") {
    $issues += "gateway.bind must be 'lan' (currently: '$($cfg.gateway.bind)')"
}

# Check 2: auth token must match TT_OPENCLAW_TOKEN
$envToken = Get-EnvValue -EnvPath $envFile -Key "TT_OPENCLAW_TOKEN"
if ($cfg.gateway.auth.token -ne $envToken) {
    $issues += "gateway.auth.token doesn't match TT_OPENCLAW_TOKEN in .env"
}

# Check 3: model must have provider prefix
$model = $cfg.agents.defaults.model.primary
if ($model -notmatch "^(google/|ollama/)") {
    $issues += "Model '$model' missing provider prefix (use 'google/' or 'ollama/')"
}

if ($issues.Count -gt 0) {
    Write-Host "  [WARN] Config needs manual fixes:" -ForegroundColor Yellow
    foreach ($i in $issues) {
        Write-Host "    → $i" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  Edit: $configDst" -ForegroundColor Cyan
    Write-Host "  Reference template: $templateSrc" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Press ENTER after fixing openclaw.json..." -ForegroundColor Cyan
    Read-Host | Out-Null
} else {
    Write-Host "  [OK]  openclaw.json is valid." -ForegroundColor Green
}

# ── Step 9: Switch to production mode ────────────────────────────────────────
Write-Host ""
Write-Host "── Step 9: Switch to Production Mode ─────────────────────" -ForegroundColor Cyan

Upsert-EnvLine -EnvPath $envFile -Key "TT_OPENCLAW_MODE" -Value "production"

Push-Location $coreDir
try {
    docker compose -f docker-compose.yml -f addons\50-openclaw.addon.yml --env-file $envFile --profile openclaw restart openclaw
} finally {
    Pop-Location
}

Start-Sleep -Seconds 5

# ── Step 10: Final status ────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║           OpenClaw Setup Complete ✓                         ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  Dashboard: http://127.0.0.1:$(Get-EnvValue -EnvPath $envFile -Key 'TT_OPENCLAW_HOST_PORT')/#token=$token" -ForegroundColor White
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  Next: Pair your Telegram account                            ║" -ForegroundColor Green
Write-Host "║    1. Message /start to your bot                             ║" -ForegroundColor Green
Write-Host "║    2. Note the numeric auth ID it replies with              ║" -ForegroundColor Green
Write-Host "║    3. Run: scripts\Approve-Telegram.ps1 -AuthId <ID>         ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║  Full docs: docs\OPENCLAW.md                                 ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
