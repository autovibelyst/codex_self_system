# Recovery Playbook - TT-Production v14.0

Step-by-step recovery procedures for common failures.
For full disaster recovery scenarios, see [DR_PLAYBOOK.md](DR_PLAYBOOK.md).

---

## Scenario 1: Service Fails to Start

```bash
docker compose -f compose/tt-core/docker-compose.yml logs --tail=80 <service>
bash scripts-linux/preflight-check.sh
bash scripts-linux/init.sh

docker compose -f compose/tt-core/docker-compose.yml up -d --force-recreate <service>
```

---

## Scenario 2: Database Unreachable

```bash
docker compose -f compose/tt-core/docker-compose.yml ps postgres
docker compose -f compose/tt-core/docker-compose.yml logs postgres

docker exec tt-core-postgres psql -U "${TT_POSTGRES_USER:-ttcore}" -c "SELECT 1;"

# If corruption suspected
bash scripts-linux/restore.sh --backup-dir backups/<stamp> --confirm
```

---

## Scenario 3: Redis Authentication Failure

```bash
source scripts-linux/lib/runtime-env.sh
CORE_ENV="$(tt_resolve_core_env_path "$(pwd)")"

grep '^TT_REDIS_PASSWORD=' "$CORE_ENV"
docker compose -f compose/tt-core/docker-compose.yml --env-file "$CORE_ENV" restart redis n8n n8n-worker
```

---

## Scenario 4: Full Stack Recovery from Backup

```bash
bash scripts-linux/stop-core.sh
bash scripts-linux/restore.sh --backup-dir backups/<stamp> --confirm --force
bash scripts-linux/verify-restore.sh
bash scripts-linux/start-core.sh
bash scripts-linux/smoke-test.sh
```

---

## Scenario 5: Tunnel Not Connecting

```bash
source scripts-linux/lib/runtime-env.sh
TUNNEL_ENV="$(tt_resolve_tunnel_env_path "$(pwd)")"

docker compose -f compose/tt-tunnel/docker-compose.yml --env-file "$TUNNEL_ENV" logs --tail=100

grep '^CF_TUNNEL_TOKEN=' "$TUNNEL_ENV"
docker compose -f compose/tt-tunnel/docker-compose.yml --env-file "$TUNNEL_ENV" restart
```

Then verify tunnel health in Cloudflare dashboard.

---

## Scenario 6: Disk Full

```bash
df -h
docker system df
docker system prune -f
bash scripts-linux/cleanup-backups.sh --keep-days 30
```

If logs are large, enforce Docker log rotation policy and rotate/restart affected services.
