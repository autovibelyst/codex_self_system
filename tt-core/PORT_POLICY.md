# Port Allocation Guide (TT-Core)

## Principles
- Avoid collisions by using dedicated non-default port ranges.
- Always bind on `127.0.0.1` for local-only access.
- Use Cloudflare Tunnel for internet exposure; never open DB ports externally.

## Canonical TT-Core ports (source of truth: env/.env.example)

| Service | Host Port | Container Port |
|---|---|---|
| n8n | 15678 | 5678 |
| pgAdmin | 15050 | 80 |
| Metabase | 13010 | 3000 |
| RedisInsight | 15540 | 5540 |
| WordPress | 18081 | 80 |
| Kanboard | 18082 | 80 |
| OpenWebUI | 13000 | 8080 |
| Ollama | 11434 | 11434 |
| Postgres | 15432 | 5432 |
| Redis | 16379 | 6379 |
| Qdrant | internal only | 6333/6334 |
| Uptime Kuma | 13001 | 3001 |
| Portainer | 19000 | 9000 |
| OpenClaw | 18789 | 18789 |

## Add-on port range (for future services)
- 20000–20999: Web UIs
- 21000–21999: APIs / gRPC
- 22000–22999: misc

See full policy: `docs/PORTS.md`
