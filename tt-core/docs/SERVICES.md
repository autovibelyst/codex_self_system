# TT-Core Services  (TT-Production v14.0)

All services use bind-mount volumes under `compose/tt-core/volumes/`.
Access all services through `scripts\Status-Core.ps1` or `scripts\ttcore.ps1 status`.

---

## Core Services (always-on)

| Service        | Container              | Port (default) | Purpose                        |
|----------------|------------------------|----------------|--------------------------------|
| n8n            | tt-core-n8n            | 15678          | Workflow automation            |
| Postgres       | tt-core-postgres       | 15432          | Primary database               |
| Redis          | tt-core-redis          | 16379          | Cache / queue                  |
| pgAdmin        | tt-core-pgadmin        | 15050          | Postgres web UI                |
| RedisInsight   | tt-core-redisinsight   | 15540          | Redis web UI                   |


**Note:** Metabase is an optional profile (`--profile metabase`) — saves ~600 MB RAM when not needed.

### Database Layout
Each service has a dedicated Postgres database:
- `ttcore` — main DB (reserved for future use)
- `n8n` — n8n workflows and credentials
- `metabase_db` — Metabase internal metadata
- `kanboard_db` — Kanboard projects (when kanboard profile active)

---

## Optional Add-ons (profiles)

### WordPress + MariaDB  (`--profile wordpress`)
Client website stack. MariaDB is isolated in `tt_core_internal` network.
WordPress is accessible externally via host port + tunnel.

| Service   | Container           | Port  |
|-----------|---------------------|-------|
| WordPress | tt-core-wordpress   | 18081 |
| MariaDB   | tt-core-mariadb     | —     |

### Kanboard  (`--profile kanboard`)
Project management board. Uses dedicated `kanboard_db` Postgres database.
Default admin password set via `TT_KANBOARD_ADMIN_PASSWORD` — change after first login.

| Service  | Container          | Port  |
|----------|--------------------|-------|
| Kanboard | tt-core-kanboard   | 18082 |

### Qdrant  (`--profile qdrant`)
Vector database for embeddings / RAG workflows.
Internal-only by default — n8n connects via `http://qdrant:6333`.
See `docs/RAG.md` for full RAG setup guide.

| Service | Container        | Port (if exposed) |
|---------|------------------|-------------------|
| Qdrant  | tt-core-qdrant   | 16333 / 16334     |

### Ollama + Open WebUI  (`--profile ollama` / `--profile openwebui`)
Local LLM runtime. Ollama activates with either `ollama` or `openwebui` profile.
Models folder `volumes/ollama/models/` is excluded from release zip (large files).
GPU support: uncomment `deploy` section in `docker-compose.yml` (NVIDIA only).

| Service    | Container           | Port  |
|------------|---------------------|-------|
| Ollama     | tt-core-ollama      | 11434 |
| Open WebUI | tt-core-openwebui   | 13000 |

### Uptime Kuma  (`--profile monitoring`)
Service health monitoring with web dashboard and multi-channel alerts
(email, Telegram, Slack, webhook, etc.).
Create admin account via web UI on first access.

| Service     | Container              | Port  |
|-------------|------------------------|-------|
| Uptime Kuma | tt-core-uptime-kuma    | 13001 |

### Portainer CE  (`--profile portainer`)
Web-based Docker management. View containers, images, volumes, networks,
and execute commands without the CLI.
Create admin account via `http://127.0.0.1:19000` within 5 minutes of first start.

| Service   | Container           | Port (HTTPS) |
|-----------|---------------------|--------------|
| Portainer | tt-core-portainer   | 19000 (HTTP) |

---

### Metabase  (`--profile metabase`)
Business intelligence and analytics dashboards. Uses dedicated `metabase_db` Postgres database.
Optional — not started by default to save RAM.

| Service  | Container          | Port  |
|----------|--------------------|-------|
| Metabase | tt-core-metabase   | 13010 |

### OpenClaw AI Agent  (`--profile openclaw`)
Autonomous AI agent: Telegram ↔ AI Brain ↔ n8n Skills. Requires `Init-OpenClaw.ps1` setup.
Optionally uses Ollama (local model) or Google Gemini (cloud model).
See `docs/OPENCLAW.md` for full setup guide.

| Service  | Container          | Port  |
|----------|--------------------|-------|
| OpenClaw | tt-core-openclaw   | 18789 |

---

## Supabase (separate product)
`tt-supabase` is an independent stack deployed separately.
See `tt-supabase/README.md` for setup instructions.

---

## Network Architecture

```
Internet
   │
   │ Cloudflare Tunnel (optional)
   │
 tt_shared_net  ← external-facing services (n8n, metabase, pgadmin, etc.)
       │
 tt_core_internal  ← data-only services (postgres, redis, mariadb, qdrant)
       │             (no host port bindings on internal network)
    Postgres
    Redis
    MariaDB
    Qdrant
```

Data services are NOT reachable from the tunnel or internet — only from services
on `tt_core_internal` (n8n, metabase, kanboard, wordpress, etc.).
