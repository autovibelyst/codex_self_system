# Profiles and Add-ons — TT-Production v14.0

TT-Production uses a profile and add-on system to control which optional services run.  
Core services always run. Everything else is opt-in.

---

## Service Tiers

| Tier | Meaning |
|------|---------|
| **core** | Always runs — cannot be disabled |
| **optional** | Enabled via profile flag or `services.select.json` |
| **addon** | Loaded from `compose/tt-core/addons/` as separate compose override |

---

## Profile-Based Services

Profiles are enabled by setting the corresponding key to `true` in `config/services.select.json`:

```json
{
  "profiles": {
    "metabase":   false,
    "kanboard":   false,
    "qdrant":     false,
    "ollama":     false,
    "openwebui":  false,
    "wordpress":  false,
    "portainer":  false,
    "openclaw":   false,
    "monitoring": false
  }
}
```

| Profile Key | Service | RAM (~) | Purpose |
|-------------|---------|---------|---------|
| `metabase` | Metabase | 600MB | Business intelligence / dashboards |
| `kanboard` | Kanboard | 64MB | Project management / Kanban |
| `qdrant` | Qdrant | 200MB | Vector DB for RAG / embeddings |
| `ollama` | Ollama | 4GB+ | Local LLM runtime |
| `openwebui` | Open WebUI | 200MB | Chat UI for Ollama |
| `wordpress` | WordPress + MariaDB | 256MB | Website / CMS |
| `portainer` | Portainer | 64MB | Docker management UI |
| `openclaw` | OpenClaw | 256MB | AI agent framework |
| `monitoring` | Uptime Kuma | 128MB | Uptime monitoring dashboard |

---

## Customer Deployment Profiles

Four ready-to-use deployment presets are included in `config/profiles/`:

| File | Use Case | Services Enabled |
|------|----------|-----------------|
| `local-private.json` | Private dev / personal server | Core only, no tunnel |
| `small-business.json` | Small business operations | n8n + Metabase + Kanboard via tunnel |
| `ai-workstation.json` | AI / automation workstation | n8n + Qdrant + Ollama + Open WebUI |
| `public-productivity.json` | Public-facing productivity | n8n + Metabase + Kanboard + Monitoring via tunnel |

To apply a profile, copy the profile's JSON content into `config/services.select.json`.

---

## Tunnel Exposure Control

Services that can be exposed via Cloudflare Tunnel are controlled per-route:

```json
{
  "tunnel": {
    "enabled": true,
    "routes": {
      "n8n":          true,
      "metabase":     false,
      "kanboard":     false,
      "pgadmin":      false,
      "portainer":    false,
      "openclaw":     false,
      "openwebui":    false,
      "wordpress":    false,
      "monitoring":   false
    }
  }
}
```

**Restricted admin routes** (`pgadmin`, `portainer`, `openclaw`) additionally require:
```json
{ "security": { "allow_restricted_admin_tunnel_routes": true } }
```
This explicit acknowledgment prevents accidental admin surface exposure.

---

## Add-on System

Custom services can be added without modifying `docker-compose.yml`.  
Place a `.yml` file in `compose/tt-core/addons/` following the template:

```
tt-core/templates/addon.service.template.yml
```

Requirements for all addon files:
- `restart: unless-stopped`
- `logging:` section defined
- Joined to `tt_shared_net` or `tt_core_internal` (never both unless required)

The preflight check validates all addon files for these requirements.

---

## Profiles Authority

The canonical source for which profiles are active is `config/services.select.json`.  
This file is read by:
- `Start-Service.ps1` (Windows)
- `start-core.sh` (Linux)
- `preflight-check.sh` (validates selection)
- `update-tunnel-urls.sh` (syncs tunnel URLs)
- `generate-exposure.sh` (generates public-exposure.policy.json)
