# Resource Requirements — TT-Production v14.0

## Core Stack (Always Running)

| Service        | RAM Limit | RAM Reserved | Notes                        |
|----------------|-----------|-------------|------------------------------|
| postgres       | 2 GB      | 256 MB      | TT_PG_SHARED_BUFFERS=256MB   |
| redis          | 512 MB    | 64 MB       | AOF persistence              |
| n8n (main)     | 2 GB      | 512 MB      | UI + webhooks                |
| n8n-worker     | 2 GB      | 512 MB      | Job execution (queue mode)   |
| pgAdmin        | 512 MB    | 128 MB      | Admin UI                     |
| redisinsight   | 512 MB    | 128 MB      | Admin UI                     |
| db-provisioner | ~50 MB    | —           | Exits after provisioning     |
| **Core Total** | **~7.5 GB** | **~1.6 GB** |                           |

**Minimum host RAM for core:** 4 GB (8 GB recommended for comfortable operation)

## Optional Addons (Add to Core Total)

| Profile    | Service           | RAM Limit | RAM Reserved |
|------------|------------------|-----------|-------------|
| metabase   | metabase         | 2 GB      | 512 MB      |
| kanboard   | kanboard         | 256 MB    | 64 MB       |
| wordpress  | wordpress        | 1 GB      | 256 MB      |
| wordpress  | mariadb          | 1 GB      | 128 MB      |
| qdrant     | qdrant           | 2 GB      | 512 MB      |
| ollama     | ollama           | 8 GB      | 1 GB        |
| openwebui  | openwebui        | 2 GB      | 512 MB      |
| monitoring | uptime-kuma      | 512 MB    | 128 MB      |
| portainer  | portainer        | 512 MB    | 128 MB      |
| openclaw   | openclaw         | 1 GB      | 256 MB      |

## RAM Requirements by Profile Combination

| Configuration                      | Minimum RAM | Recommended RAM |
|------------------------------------|------------|-----------------|
| Core only                          | 4 GB       | 8 GB            |
| Core + Metabase                    | 6 GB       | 10 GB           |
| Core + WordPress + Kanboard        | 6 GB       | 10 GB           |
| Core + Qdrant + OpenWebUI + Ollama | 12 GB      | 16 GB           |
| All addons enabled                 | 16 GB      | 24 GB+          |

> **Note:** Ollama without GPU requires significant extra RAM for model inference.
> See `docs/GPU_SETUP.md` for GPU configuration to offload to VRAM.

## Disk Requirements

| Data Type              | Min Disk     | Notes                           |
|-----------------------|-------------|----------------------------------|
| Docker images (pull)  | 10 GB       | All images combined              |
| n8n workflows + data  | 1–5 GB      | Grows with workflow history      |
| PostgreSQL data       | 2–20 GB     | Depends on usage                 |
| Ollama models         | 5–50 GB     | Per model: 2–40 GB              |
| Backups (_backups/)   | 2x data     | Retention policy dependent       |
| **Minimum total**     | **30 GB**   | Without Ollama                   |
| **With Ollama**       | **80 GB+**  | Depends on models downloaded     |

## CPU Requirements

| Configuration              | Minimum CPUs | Recommended    |
|---------------------------|-------------|----------------|
| Core only                 | 2           | 4              |
| Core + Metabase           | 2           | 4              |
| Core + Ollama (CPU mode)  | 4           | 8+             |
| Core + Ollama (GPU mode)  | 2           | 4 (GPU does LLM inference) |

## Network Ports (Default Configuration)

All ports bind to `TT_BIND_IP` (default: `127.0.0.1`).

| Service          | Port  | Profile    |
|-----------------|-------|-----------|
| PostgreSQL       | 15432 | core      |
| Redis            | 16379 | core      |
| n8n              | 15678 | core      |
| pgAdmin          | 15050 | core      |
| RedisInsight     | 15540 | core      |
| Metabase         | 13010 | metabase  |
| Kanboard         | 18082 | kanboard  |
| WordPress        | 18081 | wordpress |
| MariaDB          | 13306 | wordpress |
| Qdrant REST      | 16333 | qdrant    |
| Qdrant gRPC      | 16334 | qdrant    |
| OpenWebUI        | 13000 | openwebui |
| Uptime Kuma      | 13001 | monitoring|
| Portainer        | 19000 | portainer |
| OpenClaw         | 18789 | openclaw  |

No port conflicts with standard system ports or common applications.
