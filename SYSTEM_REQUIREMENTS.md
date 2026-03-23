# System Requirements — TT-Production v14.0

---

## Minimum Requirements

### Linux (Recommended for Production)

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Ubuntu 20.04 LTS | Ubuntu 22.04+ LTS or Debian 11+ |
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8–16 GB |
| Storage | 20 GB SSD | 50+ GB SSD |
| Docker | 24.0+ | 25.0+ |
| Docker Compose | 2.20+ | 2.24+ |

### Windows (Development/Testing)

| Component | Minimum |
|-----------|---------|
| OS | Windows 11 (22H2+) or Windows 10 (21H2+) |
| RAM | 8 GB (16 GB recommended) |
| Docker Desktop | 4.25+ |
| WSL2 Backend | Required |
| WSL2 Distro | Ubuntu 22.04 LTS |

### macOS (Development/Testing)

| Component | Minimum |
|-----------|---------|
| macOS | 13 (Ventura) or later |
| RAM | 8 GB (16 GB recommended) |
| Docker Desktop | 4.25+ |
| Chip | Apple Silicon (M1+) or Intel x86_64 |

---

## Service Resource Requirements

| Service | Min RAM | Min Storage |
|---------|---------|-------------|
| PostgreSQL 16.6 | 512 MB | 5 GB (data) |
| Redis 7.4 | 256 MB | 1 GB |
| n8n 1.88.0 (main) | 512 MB | 2 GB |
| n8n-worker | 512 MB | — |
| pgAdmin 4.8.14 | 256 MB | 512 MB |
| RedisInsight 2.66 | 256 MB | 512 MB |
| **Core stack total** | **~2.5 GB** | **~9 GB** |

**Addons (optional):**

| Addon | Additional RAM |
|-------|----------------|
| Metabase | +512 MB |
| Qdrant | +512 MB |
| Ollama (CPU) | +1 GB |
| Ollama (GPU) | Depends on model |
| WordPress | +256 MB |
| Kanboard | +128 MB |
| Portainer | +128 MB |
| Uptime Kuma | +128 MB |

---

## Network Requirements

| Requirement | Detail |
|------------|--------|
| Outbound HTTPS | Required (Docker Hub, package registries) |
| Cloudflare Tunnel | Required for public exposure (no inbound ports needed) |
| DNS | Recommended for production |
| Port 80/443 | Not required (Cloudflare Tunnel handles TLS) |

---

## Backup Requirements

| Item | Requirement |
|------|------------|
| Local backup storage | 3× database size (minimum) |
| Offsite storage (optional) | rclone compatible (S3, Wasabi, Cloudflare R2, B2) |
| Encryption key | 32+ character passphrase |
| Webhook (optional) | HTTPS endpoint for backup notifications |

---

## Preflight Validation

Before first start, run:

```bash
bash tt-core/scripts-linux/preflight-check.sh
```

All 20 checks must pass before starting services.

---

## Version Compatibility

| Component | Version | Notes |
|-----------|---------|-------|
| PostgreSQL | 16.6-alpine | Pinned for stability |
| Redis | 7.4-alpine | Pinned for stability |
| n8n | 1.88.0 | Pinned for stability |
| pgAdmin | 8.14 | Pinned for stability |
| RedisInsight | 2.66 | Pinned for stability |
