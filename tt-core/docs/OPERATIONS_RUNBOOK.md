# Operations Runbook — TT-Production v14.0

Quick-reference for day-to-day operational tasks.
For full instructions see MASTER_GUIDE.md and DR_PLAYBOOK.md.

---

## Daily Operations

### Check Stack Health
```bash
bash scripts-linux/health-dashboard.sh
```

### View Service Logs
```bash
# All core services
docker compose -f compose/tt-core/docker-compose.yml logs -f

# Single service
docker compose -f compose/tt-core/docker-compose.yml logs -f n8n

# Tunnel logs
docker compose -f compose/tt-tunnel/docker-compose.yml logs -f
```

### Start / Stop Stack
```bash
# Start
bash scripts-linux/start-core.sh

# Stop (graceful)
bash scripts-linux/stop-core.sh

# Restart single service
docker compose -f compose/tt-core/docker-compose.yml restart n8n
```

---

## Backup

### Manual Backup
```bash
bash scripts-linux/backup.sh
```

### Verify Last Backup
```bash
bash scripts-linux/verify-restore.sh --dry-run
```

### Offsite Sync
```bash
bash scripts-linux/backup-offsite.sh
# Requires TT_OFFSITE_REMOTE set in env
```

---

## Secret Rotation

```bash
bash scripts-linux/rotate-secrets.sh
# Follow prompts. Services restart automatically after rotation.
```

---

## Preflight (before any upgrade or after install)

```bash
bash tt-core/scripts-linux/preflight-check.sh
# All checks must pass before starting. 
# Fix any [FAIL] items before proceeding.
```

---

## Smoke Test (after start)

```bash
bash scripts-linux/smoke-test.sh
# Validates: HTTP endpoints, DB connectivity, Redis, n8n API
```

---

## Support Bundle (for support tickets)

```bash
bash scripts-linux/support-bundle.sh
# Generates: /tmp/tt-support-bundle-TIMESTAMP.tar.gz
# Bundle contains: logs, config (no secrets), system info
# Review before sharing.
```

---

## Upgrade

1. Take backup: `bash scripts-linux/backup.sh`
2. Download new package
3. Run: `bash scripts-linux/stop-core.sh`
4. Replace package directory (preserve your external runtime env files)
5. Run: `bash tt-core/scripts-linux/preflight-check.sh`
6. Run: `bash scripts-linux/start-core.sh`
7. Run: `bash scripts-linux/smoke-test.sh`

See UPGRADE_GUIDE.md for version-specific notes.

---

## Rollback

```bash
bash scripts-linux/rollback.sh
# Restores last known-good backup.
# See DR_PLAYBOOK.md for full recovery procedures.
```

---

## Key File Locations

| Item | Path |
|------|------|
| Core env | external runtime path resolved by scripts (`scripts/lib/RuntimeEnv.ps1`) |
| Tunnel env | external runtime path resolved by scripts (`scripts/lib/RuntimeEnv.ps1`) |
| Service selection | `config/services.select.json` |
| Compose (core) | `compose/tt-core/docker-compose.yml` |
| Compose (supabase) | `tt-supabase/compose/tt-supabase/docker-compose.yml` |
| Backup dir | `$TT_BACKUP_DIR` (set in env) |
