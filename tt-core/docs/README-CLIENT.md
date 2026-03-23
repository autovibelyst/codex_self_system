# TT-Production (TT-Core) — Client Guide

**Version:** TT-Production v14.0

This guide describes how to run, secure, backup, and upgrade the **TT-Core** Docker environment on:
- **Windows 11 (Docker Desktop / WSL2 backend)** — primary, fully supported
- **Linux (Ubuntu 22.04+ / Debian 12+ / VPS)** — fully supported
- **macOS (Docker Desktop for Mac)** — supported (Apple Silicon & Intel)

> Default install path (Windows): `%USERPROFILE%\stacks\tt-core`  
> Default install path (Linux/macOS): `~/stacks/tt-core`

---

## What you get

A modular Docker Compose system:
- **Core stack**: essential services (automation + database + admin tools)
- **Optional add-ons**: WordPress, Kanboard, OpenWebUI/Ollama, Qdrant, Metabase, and more
- **Tunnel stack** (optional): Cloudflare Tunnel routing per-service subdomain
- **AI Agent** (optional): OpenClaw autonomous AI over Telegram

---

## One-time setup (per machine)

### Windows (PowerShell)
```powershell
# 1. Install Docker Desktop + WSL2 backend (https://docker.com/products/docker-desktop)
# 2. Open PowerShell and navigate to the package folder:
cd %USERPROFILE%\stacks\TT-Production-v14.0\tt-core
# 3. Run the full installer (reads config/services.select.json):
.\installer\Install-TTCore.ps1
# 4. Preflight check (27 checks — all must pass):
.\scripts\Preflight-Check.ps1
```

### Linux (bash)
```bash
# 1. Install Docker Engine: https://docs.docker.com/engine/install/
# 2. Navigate to the package folder:
cd ~/stacks/TT-Production-v14.0/tt-core
# 3. Run the installer:
bash installer/Install-TTCore.sh
# 4. Preflight check:
bash scripts-linux/preflight-check.sh
```

### macOS (Docker Desktop for Mac)
```bash
# 1. Install Docker Desktop for Mac (https://docker.com/products/docker-desktop)
#    Works on both Apple Silicon (M1/M2/M3) and Intel.
# 2. Open Terminal and navigate to the package folder:
cd ~/stacks/TT-Production-v14.0/tt-core
# 3. Run the installer (same as Linux):
bash installer/Install-TTCore.sh
# 4. Preflight check:
bash scripts-linux/preflight-check.sh
# Note: Ollama GPU acceleration is NOT available on macOS Docker.
# Ollama runs on CPU — use a small model (e.g., llama3.2:3b).
```

---

## Daily operations

### Start / Stop (Windows — PowerShell)
```powershell
# Start core services:
scripts\Start-Core.ps1
# Stop core services:
scripts\Stop-Core.ps1
# Check status:
scripts\Status.ps1
# View logs for a service:
scripts\Logs-Core.ps1
# Full restart:
scripts\Restart-Core.ps1
```

### Start / Stop (Linux / macOS — bash)
```bash
# Start core services:
bash scripts-linux/start-core.sh
# Stop core services:
bash scripts-linux/stop-core.sh
# Check status:
bash scripts-linux/status.sh
# Health dashboard:
bash scripts-linux/health-dashboard.sh
```

### Start / Stop (Tunnel)

**Windows:**
```powershell
scripts\Start-Tunnel.ps1
scripts\Stop-Tunnel.ps1
```

**Linux / macOS:**
```bash
bash scripts-linux/start-tunnel.sh
```

### Optional add-ons

**Windows:**
```powershell
# Enable addon profile in config/services.select.json first, then:
scripts\ttcore.ps1 up profile metabase
scripts\ttcore.ps1 up profile openclaw
scripts\Start-Service.ps1 -Service wordpress
```

**Linux / macOS:**
```bash
bash scripts-linux/apply-profile.sh --profile metabase
```

---

## Access URLs (Local)

Ports are defined in `docs/PORTS.md`. Defaults:

| Service       | Default URL                        |
|---------------|------------------------------------|
| n8n           | http://127.0.0.1:15678             |
| pgAdmin       | http://127.0.0.1:15050             |
| RedisInsight  | http://127.0.0.1:15540             |
| Metabase      | http://127.0.0.1:13010             |
| OpenWebUI     | http://127.0.0.1:13000             |
| Uptime Kuma   | http://127.0.0.1:13001             |
| Portainer     | http://127.0.0.1:19000             |

---

## Access URLs (Online via Cloudflare)

Each published service gets its own subdomain when Tunnel is enabled.  
Example (client domain varies):
- n8n → `n8n.<CLIENT_DOMAIN>`
- Metabase → `metabase.<CLIENT_DOMAIN>`
- WordPress → `wp.<CLIENT_DOMAIN>`

See: `docs/TUNNEL.md`

---

## Diagnostics & Support Bundle

**Windows:**
```powershell
scripts\Diag.ps1
```

**Linux / macOS:**
```bash
bash scripts-linux/support-bundle.sh
```

---

## Next Documents

| Document | Purpose |
|----------|---------|
| `docs/SERVICES.md` | What each service does |
| `docs/PORTS.md` | Complete port inventory |
| `docs/SECURITY.md` | Security rules and hardening |
| `docs/BACKUP.md` | Backup / restore procedures |
| `docs/UPGRADE.md` | Upgrade policy and steps |
| `docs/TROUBLESHOOTING.md` | Common issues and fixes |
| `docs/OPENCLAW.md` | AI Agent setup guide |
| `docs/GPU_SETUP.md` | GPU acceleration (NVIDIA/AMD) |

