# TT-Core — File Index (TT-Production v14.0)

Start with `docs/MASTER_PRODUCTION_GUIDE.md` for the primary operator guide.

**Key entry points:**
- `scripts/Init-TTCore.ps1` — Initialize secrets and environment
- `scripts/Preflight-Check.ps1` — Validate configuration before first start
- `scripts/Preflight-Supabase.ps1` — Validate Supabase configuration
- `release/validate-bundle.ps1` — Full bundle integrity check (22 sections)
- `scripts/ttcore.ps1` — Unified CLI (up/down/restart/logs/status/diag)
- `installer/Install-TTCore.ps1` — Windows installer
- `installer/Install-TTCore.sh` — Linux/VPS installer
