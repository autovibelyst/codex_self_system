# Security - TT-Production v14.0

## Responsible Disclosure

If you discover a security vulnerability in TT-Production, report it privately.

**Contact:** security@tt-production.io  
**Response SLA:** 48 hours for acknowledgment, 14 days for initial assessment.

Do NOT open a public issue for security vulnerabilities.

---

## Secret Management

### Runtime Secrets Live Outside the Repository
TT-Production uses a single-authority runtime model:
- Core runtime secrets live in `${XDG_CONFIG_HOME:-$HOME/.config}/tt-production/runtime/<stack>/core.env`
- Tunnel runtime secrets live in `${XDG_CONFIG_HOME:-$HOME/.config}/tt-production/runtime/<stack>/tunnel.env`
- No secrets in `docker-compose.yml`, scripts, or committed config files
- No plaintext secrets under the repository tree

### Secret Strength Requirements
Use `scripts-linux/secrets-strength.sh` to verify minimum secret quality:

```bash
bash scripts-linux/secrets-strength.sh
bash scripts-linux/secrets-strength.sh --strict
```

Minimum requirements:
- `TT_N8N_ENCRYPTION_KEY` >= 32 characters
- Other service secrets >= 16-24 characters (depending on variable)

### Secret Rotation
See [CREDENTIAL_ROTATION.md](CREDENTIAL_ROTATION.md) for full procedures covering all 12 secrets.

```bash
bash scripts-linux/rotate-secrets.sh --dry-run
bash scripts-linux/rotate-secrets.sh --secret TT_REDIS_PASSWORD
```

Critical note: rotating `TT_N8N_ENCRYPTION_KEY` requires full credential re-export/re-import in n8n. Existing encrypted credentials become unreadable if rotated incorrectly.

---

## Network Security

### Isolation Model
| Network | Type | Accessible By |
|---|---|---|
| `tt_core_internal` | internal bridge | postgres, redis, n8n, n8n-worker, db-provisioner |
| `tt_admin_net` | internal bridge | pgAdmin, RedisInsight |
| `tt_shared_net` | external bridge | Services explicitly exposed through tunnel |

Postgres and Redis are not attached to `tt_shared_net`.

### Port Exposure Policy
By default (`TT_BIND_IP=127.0.0.1`), ports are localhost-only. For LAN/tunnel exposure, set `TT_BIND_IP=0.0.0.0` in runtime `core.env`.

Never expose pgAdmin or RedisInsight directly to public IP without an access gateway.

### n8n Webhook Abuse Protection
If exposed through tunnel, apply rate-limiting and access control at Cloudflare/WAF layer.

Recommended controls:
1. WAF rate limits for `/webhook/*`
2. Access policy for editor/admin routes
3. n8n webhook authentication where applicable
4. Traffic monitoring via `monitor.sh` and uptime checks

---

## Container Hardening

- Images pinned to explicit versions (digest locking available)
- `db-provisioner` uses least-privilege grants
- Redis password authentication enforced
- Admin services isolated on `tt_admin_net`
- Resource limits and healthchecks enabled for core services

---

## Backup Security

- Backups stored under local `backups/`
- SHA256 checksums generated and verified on restore
- Optional webhook notifications for backup outcomes
- Optional AES-256-CBC backup encryption via `TT_BACKUP_ENCRYPTION_KEY` in runtime `core.env`

Validation commands:

```bash
bash scripts-linux/verify-restore.sh
bash scripts-linux/cleanup-backups.sh --keep-days 30
```

See [BACKUP.md](BACKUP.md) for operational details.

---

## Disaster Recovery

See [DR_PLAYBOOK.md](DR_PLAYBOOK.md) for incident scenarios and timed recovery drills.

Targets:
- RTO <= 30 minutes
- RPO <= 24 hours (default nightly backup cadence)

---

## Cloudflare Tunnel Security

- Token-only mode (no tunnel UUID required in runtime)
- Tunnel token stored only in runtime `tunnel.env`
- Public routes controlled by `config/services.select.json`
- Restricted admin routes require explicit policy acknowledgment (`allow_restricted_admin_tunnel_routes=true`)

See [TUNNEL.md](TUNNEL.md) and [TUNNEL-SUBDOMAINS-POLICY.md](TUNNEL-SUBDOMAINS-POLICY.md).

---

## Upgrade Security

Follow [UPGRADE_GUIDE.md](UPGRADE_GUIDE.md) on every upgrade:
1. Full backup first
2. Preflight checks on new bundle
3. Keep previous bundle available for immediate rollback

---

## Known Security Limitations

1. Backup encryption is optional; if not set, dumps are stored plaintext on disk.
2. `TT_N8N_ENCRYPTION_KEY` loss means permanent loss of n8n credential decryptability.
3. PostgreSQL uses password auth only (no built-in mTLS).
4. Built-in script-level audit trail is limited; use host-level audit logging for regulated environments.
