# TT-Core Production QA — Smoke Test Checklist (TT-Production v14.0)

TT-Core Production QA (Smoke Test Checklist)

This checklist validates that a **fresh install** of TT-Core is working correctly before handover to a customer.

> Scope: TT-Core bundle (core + mandatory add-ons) and optional add-ons if enabled.

## 0) Preconditions
- Docker Desktop installed and running (Windows / Linux).
- If Windows: WSL2 backend enabled.
- Project path exists (default): `%USERPROFILE%\stacks\tt-core`
- Runtime core env exists (resolved by scripts to external runtime path)

## 1) Start (core)
Run (PowerShell):
- `scripts\\Start-Core.ps1`

Expected:
- No compose errors.
- Containers start and stay **Up** (not restarting).

## 2) Quick health overview
Run:
- `docker ps --format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}"`

Check:
- `tt-core-postgres` is **Up**.
- `tt-core-n8n` is **Up**.
- `tt-core-pgadmin` is **Up**.
- `tt-core-metabase` is **Up** (only if `metabase` profile enabled).
- `tt-core-wordpress` and `tt-core-mariadb` are **Up** (only if WordPress profile enabled).
- No container is stuck in `Restarting`.

## 3) Port availability (host)
Validate there are **no conflicts** on required ports.

Windows PowerShell:
- `Get-NetTCPConnection -State Listen | ? { $_.LocalAddress -in @('127.0.0.1','0.0.0.0','::') } | Select LocalAddress,LocalPort,OwningProcess | Sort LocalPort`

Check:
- Ports match the TT-Core ports policy.
- Any port collision must be resolved by changing the runtime core env and re-up.

## 4) Local URLs (browser)
Open locally (examples; actual ports come from the runtime core env):
- n8n: `http://127.0.0.1:<N8N_PORT>/`
- pgAdmin: `http://127.0.0.1:<PGADMIN_PORT>/`
- Metabase: `http://127.0.0.1:<METABASE_PORT>/`
- WordPress: `http://127.0.0.1:<WP_HTTP_PORT>/`

Expected:
- Pages load without long blank screens.
- First-load can be slow once; subsequent loads should be normal.

## 5) DB connectivity (pgAdmin)
- Login to pgAdmin.
- Add server:
  - Host: `tt-core-postgres` (from within docker network) OR `127.0.0.1` (host-mapped)
  - Port: `<POSTGRES_PORT>`
  - User: from `.env`
  - Password: from `.env`

Expected:
- Successful connection.

## 6) Metabase connectivity
- In Metabase, add Postgres connection to TT-Core Postgres.
- Confirm Metabase internal schema exists (e.g. `metabase` schema if used).

Expected:
- Test connection succeeds.

## 7) Cloudflare Tunnel (if enabled)
Run:
- `scripts\\Start-Tunnel.ps1`

Expected:
- `tt-core-cloudflared` is **Up**.
- Each enabled service subdomain routes to the correct local service.

## 8) Optional add-ons
For each enabled add-on (Kanboard, Qdrant, OpenWebUI/Ollama, etc.):
- Start using its script or profile.
- Validate local URL loads.
- Validate it is not exposed externally unless tunnel routing explicitly enabled.

## 9) Shutdown
Run:
- `scripts\\Stop-Core.ps1`
- `scripts\\Stop-Tunnel.ps1` (if used)

Expected:
- Containers stop cleanly.
- Networks are removed if no container uses them.

---

## Troubleshooting quick map
- **Restart loops**: `docker logs <container> --tail 200`
- **Port conflict**: adjust `.env` host ports and re-up.
- **DNS/routing** (tunnel): verify ingress template and selected subdomains.
