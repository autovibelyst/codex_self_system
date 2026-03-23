# Disaster Recovery Playbook - TT-Core (TT-Production v14.0)

**RTO target:** <= 30 minutes  
**RPO target:** <= 24 hours (default nightly backups)

---

## Scenario 1: Single Service Crash

```bash
bash scripts-linux/status.sh
docker logs tt-core-<service> --tail 100
docker compose -f compose/tt-core/docker-compose.yml restart <service>
bash scripts-linux/smoke-test.sh
```

---

## Scenario 2: Corrupted Service Database

```bash
ls -lt backups/ | head -5

# Dry-run restore plan
bash scripts-linux/restore.sh --backup-dir backups/<latest_stamp>

# Restore with confirmation
bash scripts-linux/restore.sh --backup-dir backups/<latest_stamp> --confirm
bash scripts-linux/smoke-test.sh
```

---

## Scenario 3: Full Host Loss

```bash
# New host setup
unzip TT-Production-v14.0.zip
cd TT-Production-v14.0/tt-core
bash scripts-linux/init.sh

# Resolve runtime env path
source scripts-linux/lib/runtime-env.sh
CORE_ENV="$(tt_runtime_core_env_path "$(pwd)")"

# Restore env from backup payload
cp /path/to/backup/<stamp>/.env.backup "$CORE_ENV"
chmod 600 "$CORE_ENV"

# Start and restore
bash scripts-linux/preflight-check.sh
bash scripts-linux/start-core.sh
bash scripts-linux/restore.sh --backup-dir /path/to/backup/<stamp> --confirm --force
bash scripts-linux/smoke-test.sh
```

---

## Scenario 4: Runtime Env Corruption or Deletion

Symptoms: services fail to start, secrets missing, auth failures.

```bash
source scripts-linux/lib/runtime-env.sh
CORE_ENV="$(tt_resolve_core_env_path "$(pwd)")"

# Option A (preferred): restore from backup
cp backups/<latest_stamp>/.env.backup "$CORE_ENV"
chmod 600 "$CORE_ENV"

# Option B: regenerate (changes secrets)
bash scripts-linux/init.sh

bash scripts-linux/stop-core.sh
bash scripts-linux/start-core.sh
bash scripts-linux/smoke-test.sh
```

---

## Scenario 5: n8n-worker Unhealthy

```bash
docker logs tt-core-n8n-worker --tail 80

docker inspect tt-core-n8n-worker \
  --format '{{range .Config.Env}}{{println .}}{{end}}' | grep N8N_QUEUE_HEALTH_CHECK_ACTIVE

source scripts-linux/lib/runtime-env.sh
CORE_ENV="$(tt_resolve_core_env_path "$(pwd)")"
grep 'N8N_QUEUE_HEALTH_CHECK_ACTIVE' "$CORE_ENV" || \
  echo 'TT_N8N_QUEUE_HEALTH_CHECK_ACTIVE=true' >> "$CORE_ENV"

docker compose -f compose/tt-core/docker-compose.yml --env-file "$CORE_ENV" restart n8n-worker
```

---

## Scenario 6: Redis AOF Corruption

```bash
docker run --rm \
  -v "$(pwd)/compose/tt-core/volumes/redis/data:/data" \
  redis:7.4-alpine \
  redis-check-aof --fix /data/appendonlydir/appendonly.aof.1.incr.aof

bash scripts-linux/smoke-test.sh
```

If repair fails, restore Redis data from a known-good backup.

---

## Monthly DR Validation

```bash
# Check backup integrity only
cd backups/<stamp>
sha256sum -c checksums.sha256

# Timed restore drill
START=$(date +%s)
bash ../../scripts-linux/restore.sh --backup-dir . --confirm
bash ../../scripts-linux/smoke-test.sh
END=$(date +%s)
echo "RTO seconds: $((END-START))"
```

---

## Escalation Matrix

| Severity | Description | Action |
|---|---|---|
| P0 | Full stack down / data unavailable | Execute Scenario 3 immediately |
| P1 | Critical service down | Execute Scenario 1 or 2 |
| P2 | Partial degradation | Repair affected service + monitor |
| P3 | Non-critical issue | Schedule maintenance window |
