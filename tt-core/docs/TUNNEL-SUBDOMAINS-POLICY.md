# Tunnel Subdomain Policy — TT-Production v14.0

This document defines the naming convention, authority model, and security rules
for Cloudflare Tunnel subdomain assignment.

---

## Authority Model

| File | Role |
|------|------|
| `config/services.select.json` | **Canonical intent source** — which routes are enabled |
| `config/service-catalog.json` | **Route name definitions** — default subdomain per service |
| `scripts-linux/update-tunnel-urls.sh` | Syncs intent → `.env` tunnel URL variables |
| `scripts/Update-TunnelURLs.ps1` | Windows equivalent |
| `config/public-exposure.policy.json` | **Generated** — never edit directly |

The Cloudflare Tunnel UI/dashboard always takes precedence for actual routing.
The `.env` file and scripts only configure which URLs n8n and other services *use internally*.

---

## Default Subdomain Assignments

| Service | Default Subdomain Prefix | Example |
|---------|--------------------------|---------|
| n8n | `n8n` | `n8n.example.com` |
| Metabase | `metabase` | `metabase.example.com` |
| Kanboard | `kanboard` | `kanboard.example.com` |
| WordPress | `www` | `www.example.com` |
| Open WebUI | `chat` | `chat.example.com` |
| pgAdmin | `pgadmin` | `pgadmin.example.com` |
| Portainer | `portainer` | `portainer.example.com` |
| OpenClaw | `agent` | `agent.example.com` |
| Uptime Kuma | `status` | `status.example.com` |

Subdomains are configured via the `TT_*_PUBLIC_URL` variables in `.env`.

---

## Security Rules

### Rule 1: Restricted Admin Routes
pgAdmin, Portainer, and OpenClaw are **restricted admin routes**.  
They must not be tunnel-exposed unless `security.allow_restricted_admin_tunnel_routes: true`
is explicitly set in `services.select.json`.

The preflight check enforces this rule at startup.

### Rule 2: No Overlapping Subdomains
Each exposed service must use a unique subdomain on the same domain.  
Subdomain conflicts will cause Cloudflare Tunnel to route incorrectly.

### Rule 3: Admin Routes Behind Cloudflare Access
Any exposed admin route (pgAdmin, Portainer) must be protected by a
Cloudflare Access policy requiring authentication before the tunnel passes
traffic to the service. See Cloudflare Access documentation.

### Rule 4: Token Isolation
`CF_TUNNEL_TOKEN` lives only in runtime tunnel env (`.../runtime/<stack>/tunnel.env`).  
It must never be placed in core runtime env or any script.

---

## Updating Tunnel URLs

When you change which routes are enabled or change your domain:

```bash
# Linux
bash scripts-linux/update-tunnel-urls.sh

# Windows
scripts\Update-TunnelURLs.ps1
```

This reads from `config/services.select.json` and updates the URL variables in `.env`.  
After running, restart the core stack for the new URLs to take effect.

---

## Subdomain Customization

To use a different subdomain (e.g., `flows.example.com` instead of `n8n.example.com`):

1. Edit the `subdomains` field for the service in `config/services.select.json`
2. Re-run `update-tunnel-urls.sh`
3. Update the Cloudflare Tunnel routing in your Cloudflare dashboard to match
4. Restart the stack
