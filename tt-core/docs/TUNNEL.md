# Cloudflare Tunnel Stack (TT-Tunnel)

## Objective
Optional internet exposure for selected TT-Core services through a single Cloudflare Tunnel.
The production runtime is **token-only** and is driven by the bundle policy files.

## Canonical control model
The live routing decision is derived from these files:
- `config/service-catalog.json` → service metadata and tunnel capability
- `config/public-exposure.policy.json` → generated exposure policy
- `config/services.select.json` → customer-specific enablement and domain choices
- `.../runtime/<stack>/tunnel.env` -> runtime secret `CF_TUNNEL_TOKEN`

`public-exposure.policy.json` is generated compatibility data and should not become a hand-edited source of truth.

## Operations
- Review the planned public routes: `scripts\Show-TunnelPlan.ps1`
- Start the tunnel: `scripts\Start-Tunnel.ps1`
- Stop the tunnel: `scripts\Stop-Tunnel.ps1`
- View logs: `docker compose -f compose/tt-tunnel/docker-compose.yml logs -f`

## How routing works
1. The operator enables Tunnel for the customer in `config/services.select.json`.
2. The operator adds `CF_TUNNEL_TOKEN` to runtime tunnel env (`.../runtime/<stack>/tunnel.env`).
3. `Show-TunnelPlan.ps1` shows which services are eligible for exposure.
4. Cloudflare-side public hostnames are then configured to match the approved plan.

## Naming convention
Recommended hostname format:
- `<service>.<client-domain>`
- examples: `n8n.example.com`, `metabase.example.com`

The exact public service list must match the policy/catalog pair, not a legacy ingress template.

## Important constraints
- TT-Production does **not** use config.yml / ingress template mode as the production path.
- Tunnel exposure does **not** require publishing internal database ports publicly.
- Restricted admin services must remain behind explicit policy approval and Cloudflare Access.
- `redisinsight` remains local-only by policy in this release.
