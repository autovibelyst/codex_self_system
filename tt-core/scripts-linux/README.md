# scripts-linux/ — TT-Production v14.0 (Linux / VPS / macOS)

All scripts require Bash 4.0+ and Docker with Compose v2 plugin.  
Run from the `tt-core/` directory: `bash scripts-linux/<script>.sh`

---

## First-Run (Required)

| Script | Purpose |
|--------|---------|
| `init.sh` | Creates `.env` from template, generates all secrets, creates volume dirs |
| `preflight-check.sh` | Validates config before first start (14 checks) |

## Start / Stop / Status

| Script | Purpose |
|--------|---------|
| `start-core.sh` | Start the core stack |
| `stop-core.sh` | Stop the core stack |
| `start-tunnel.sh` | Start the Cloudflare Tunnel container |
| `status.sh` | Show container status and resource usage |
| `status.sh --json` | Machine-readable JSON output (for Uptime Kuma / Datadog) |

## Health and Monitoring

| Script | Purpose |
|--------|---------|
| `smoke-test.sh` | Post-start health verification |
| `monitor.sh` | Continuous health monitor with webhook alerts |
| `bump-version.sh` | Version governance — updates all version markers in one operation (`OLD NEW` args) |
| `support-bundle.sh` | Safe diagnostics bundle (no secrets) for support handoff |

## Backup and Restore

| Script | Purpose |
|--------|---------|
| `backup.sh` | Full backup (postgres dumps + volumes) with webhook notification |
| `restore.sh` | Restore from backup with SHA256 verification |
| `verify-restore.sh` | **(legacy marker)** — Verify backup recoverability (schema-only, no live data) |
| `cleanup-backups.sh` | **(legacy marker)** — Remove backups older than retention period (`--dry-run` safe) |
| `apply-profile.sh` | **(legacy marker)** — Apply deployment profile preset to services.select.json (`--list`, `--dry-run`) |
| `setup-backup-schedule.sh` | Install / remove cron backup schedule |

## Secrets and Security

| Script | Purpose |
|--------|---------|
| `rotate-secrets.sh` | Semi-automated secret rotation with `--dry-run` |
| `secrets-strength.sh` | Grade each secret A–F; `--strict` mode exits 1 on any FAIL |
| `update-tunnel-urls.sh` | Sync tunnel URLs from `config/services.select.json` to `.env` |

## Release and Maintenance

| Script | Purpose |
|--------|---------|
| `lock-image-digests.sh` | Pin all image tags to SHA256 digests |
| `preflight-supabase.sh` | Preflight check for tt-supabase component |

---

## Common Workflows

### Fresh Install
```bash
bash scripts-linux/init.sh
bash scripts-linux/preflight-check.sh
bash scripts-linux/start-core.sh
bash scripts-linux/smoke-test.sh
```

### Daily Operations
```bash
bash scripts-linux/status.sh           # check health
bash scripts-linux/backup.sh           # manual backup
bash scripts-linux/monitor.sh --once   # one-shot health check
```

### Before Shipping to Customer
```bash
bash scripts-linux/secrets-strength.sh --strict    # all secrets must pass
bash scripts-linux/preflight-check.sh              # all 14 checks must pass
bash scripts-linux/smoke-test.sh                   # all containers healthy
bash scripts-linux/verify-restore.sh               # backup is recoverable
```

### Backup Maintenance (monthly)
```bash
bash scripts-linux/cleanup-backups.sh --dry-run    # preview what would be deleted
bash scripts-linux/cleanup-backups.sh --keep-days 30
```

