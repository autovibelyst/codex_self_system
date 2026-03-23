#Requires -Version 5.1
<#
.SYNOPSIS
    Approve or revoke a Telegram user's access to the OpenClaw AI agent.

.DESCRIPTION
    Wraps the OpenClaw pairing CLI commands inside the container.
    Uses the Pairing Mode security pattern from OpenClaw:
    - The bot ignores all strangers by default
    - Users send /start → receive a numeric Auth ID
    - You run this script with that ID to approve them

.PARAMETER AuthId
    The numeric pairing ID returned by the bot when user sends /start.

.PARAMETER Action
    approve (default) or revoke.

.PARAMETER Username
    Optional: label for the approval (does not affect security, display only).

.PARAMETER ListPaired
    Show all currently paired users.

.EXAMPLE
    .\Approve-Telegram.ps1 -AuthId 123456789
    .\Approve-Telegram.ps1 -AuthId 123456789 -Action revoke
    .\Approve-Telegram.ps1 -ListPaired
#>
param(
    [string]$AuthId,
    [ValidateSet("approve", "revoke")]
    [string]$Action      = "approve",
    [string]$Username    = "",
    [switch]$ListPaired
)

$ErrorActionPreference = "Stop"

$ContainerName = "tt-core-openclaw"

# ── Check container is running ──────────────────────────────────────────────
$running = docker ps --filter "name=$ContainerName" --filter "status=running" --format "{{.Names}}" 2>$null
if ($running -notcontains $ContainerName) {
    Write-Host "[ERR] Container '$ContainerName' is not running." -ForegroundColor Red
    Write-Host "      Start it with: scripts\Start-Service.ps1 -Service openclaw" -ForegroundColor Yellow
    exit 1
}

# ── Check production mode ───────────────────────────────────────────────────
$mode = docker exec $ContainerName sh -c 'echo $TT_OPENCLAW_MODE' 2>$null
if ($mode.Trim() -ne "production") {
    Write-Host "[WARN] OpenClaw is in SETUP MODE, not production." -ForegroundColor Yellow
    Write-Host "       Complete Init-OpenClaw.ps1 first." -ForegroundColor Yellow
    exit 1
}

# ── List paired users ────────────────────────────────────────────────────────
if ($ListPaired) {
    Write-Host ""
    Write-Host "Currently paired Telegram users:" -ForegroundColor Cyan
    docker exec $ContainerName openclaw pairing list
    exit 0
}

# ── Validate AuthId ─────────────────────────────────────────────────────────
if ([string]::IsNullOrEmpty($AuthId)) {
    Write-Host "[ERR] -AuthId is required." -ForegroundColor Red
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  1. Message /start to your Telegram bot" -ForegroundColor Yellow
    Write-Host "  2. Note the numeric ID it responds with" -ForegroundColor Yellow
    Write-Host "  3. Run: .\Approve-Telegram.ps1 -AuthId <ID>" -ForegroundColor Yellow
    exit 1
}

# ── Execute pairing command ──────────────────────────────────────────────────
Write-Host ""
if ($Action -eq "approve") {
    Write-Host "Approving Telegram user (Auth ID: $AuthId)..." -ForegroundColor Cyan
    docker exec $ContainerName openclaw pairing approve telegram $AuthId
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "[OK]  User $AuthId approved." -ForegroundColor Green
        if ($Username) {
            Write-Host "      Label: $Username" -ForegroundColor DarkGray
        }
        Write-Host "      They can now chat with your OpenClaw bot on Telegram." -ForegroundColor DarkGray
    } else {
        Write-Host "[ERR] Approval failed. Check the Auth ID and try again." -ForegroundColor Red
    }
} else {
    Write-Host "Revoking Telegram access for user (Auth ID: $AuthId)..." -ForegroundColor Yellow
    docker exec $ContainerName openclaw pairing revoke telegram $AuthId
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK]  User $AuthId access revoked." -ForegroundColor Green
    } else {
        Write-Host "[ERR] Revoke failed. Check the Auth ID." -ForegroundColor Red
    }
}

Write-Host ""
