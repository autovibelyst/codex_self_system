# TT-Core Port Reference  (TT-Production v14.0)

All ports bind to `TT_BIND_IP` (default: `127.0.0.1` — local only).
Change `TT_BIND_IP=0.0.0.0` in `.env` only if you need LAN access.

## Core Services

| Env Variable               | Default Port | Service       | Protocol |
|----------------------------|-------------|---------------|----------|
| `TT_POSTGRES_HOST_PORT`    | 15432       | PostgreSQL    | TCP      |
| `TT_REDIS_HOST_PORT`       | 16379       | Redis         | TCP      |
| `TT_N8N_HOST_PORT`         | 15678       | n8n           | HTTP     |
| `TT_PGADMIN_HOST_PORT`     | 15050       | pgAdmin       | HTTP     |
| `TT_REDISINSIGHT_HOST_PORT`| 15540       | RedisInsight  | HTTP     |
| `TT_METABASE_HOST_PORT`    | 13010       | Metabase      | HTTP     |

## Optional Add-ons

| Env Variable               | Default Port | Service       | Protocol |
|----------------------------|-------------|---------------|----------|
| `TT_WORDPRESS_HOST_PORT`   | 18081       | WordPress     | HTTP     |
| `TT_KANBOARD_HOST_PORT`    | 18082       | Kanboard      | HTTP     |
| `TT_OLLAMA_HOST_PORT`      | 11434       | Ollama API    | HTTP     |
| `TT_OPENWEBUI_HOST_PORT`   | 13000       | Open WebUI    | HTTP     |
| `TT_QDRANT_HOST_PORT`      | 16333       | Qdrant HTTP   | HTTP     |
| `TT_QDRANT_GRPC_PORT | 16334       | Qdrant gRPC   | gRPC     |
| `TT_UPTIME_KUMA_HOST_PORT` | 13001       | Uptime Kuma   | HTTP     |
| `TT_PORTAINER_HOST_PORT`   | 19000       | Portainer     | HTTP     |
| `TT_OPENCLAW_HOST_PORT`    | 18789       | OpenClaw      | HTTP     |

## Internal Ports (Docker network only — never exposed)

| Service  | Internal Port | Used by              |
|----------|---------------|----------------------|
| Postgres | 5432          | n8n, metabase, kanboard, pgadmin |
| Redis    | 6379          | n8n                  |
| MariaDB  | 3306          | WordPress            |
| Qdrant   | 6333 / 6334   | n8n (http://qdrant:6333) |
| Ollama   | 11434         | Open WebUI           |

## Port Range Policy
- `13xxx` — web UIs (Metabase, OpenWebUI, Uptime Kuma)
- `15xxx` — core data services (Postgres, n8n, pgAdmin, Redis, RedisInsight)
- `16xxx` — secondary data services (Redis port, Qdrant)
- `18xxx` — add-on services (WordPress, Kanboard)
- `19xxx` — management tools (Portainer)
- `11434` — Ollama (keeps standard port for compatibility)

All ports are in safe ranges above 10000 to avoid conflicts with common system services.
