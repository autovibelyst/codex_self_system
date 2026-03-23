# TT-Core Add-ons System
This package defines the **official** pattern for adding new services to TT-Core via:
- `compose/tt-core/addons/NN-service.addon.yml`
- `profiles` (profile name MUST match service name)
- centralized volumes under `volumes/` (single root)
- optional Cloudflare Tunnel routing (subdomain per service by default)

## Naming rules (approved)
- **service name** == **profile name** == **container_name suffix** (recommended)
  - Example: service `kanboard` -> profile `kanboard` -> container `tt-core-kanboard`
- Add-on file naming uses tens:
  - `10-kanboard.addon.yml`, `20-openwebui.addon.yml`, `30-metabase.addon.yml`, ...

## Where files go
- Core compose: `compose/tt-core/docker-compose.yml`
- Add-ons: `compose/tt-core/addons/NN-<service>.addon.yml`
- Central volumes root: `volumes/`
- Scripts: `apps/` (shortcuts) + `scripts/` (real logic)

## Port policy (approved)
**Goal:** zero conflicts by default + consistent ranges.

- Core ports are fixed/known.
- Add-ons MUST pick ports from an **Add-ons range**:
  - Suggested default: `20000-20999` for HTTP UIs, `21000-21999` for APIs, `22000-22999` for misc.
- Every add-on must expose ports **bound to 127.0.0.1** (local-only) unless explicitly intended for LAN.

### Env convention
Each add-on should add its own variables to `.env` (stack-specific):
- `TT_KANBOARD_HOST_PORT=18082`
- `TT_REDISINSIGHT_HOST_PORT=15540`
- etc.

Always keep defaults in `.env.example` and allow override in `.env`.

## Network policy (approved)
- Use shared external network: `tt_shared_net`
- Use internal-only network: `tt_core_internal` (internal: true)
- Public-exposed containers (to host) bind to 127.0.0.1 only.
- Services that should never be reachable from host do **not** publish ports and stay on `tt_core_internal` only.

## Tunnel policy (approved)
- Tunnel stack is separate: `compose/tt-tunnel/`
- Default behavior when tunnel enabled: **each service gets a subdomain**
- Override behavior: allow client to mark a service as `NO_TUNNEL=1` in env (per-service opt-out)

Routing lives in `compose/tt-tunnel/ingress/ingress.template.yml` (generated into `ingress.yml`).

## “Add a new service” checklist
1) Create `compose/tt-core/addons/NN-<service>.addon.yml`
2) Add `profile: ["<service>"]`
3) Ensure networks:
   - attach to `tt_shared_net` if other core services must reach it
   - attach to `tt_core_internal` if it’s internal-only
4) Put persistent data under `volumes/<service>/...`
5) Add ports as `127.0.0.1:${<SERVICE>_PORT}:<container_port>`
6) Add env keys to `.env.example`
7) Update `scripts/deps.json` (only if it has dependencies)
8) Add tunnel route entry (optional): `TUNNEL_<SERVICE>=1` (default) or `NO_TUNNEL_<SERVICE>=1`
9) Test with:
   - `scripts\ttcore.ps1 up profile <service>`
   - `scripts\ttcore.ps1 down profile <service>`

## Template files included
- `templates/addon.service.template.yml`
- `templates/addon.readme.template.md`
- `templates/env.addon.template.env`
- `templates/tunnel.route.snippet.yml`
