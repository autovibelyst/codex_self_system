# Credential Rotation - TT-Core (TT-Production v14.0)

This document covers safe rotation of production secrets with minimal downtime.

---

## Before Any Rotation

```bash
bash scripts-linux/backup.sh
bash scripts-linux/smoke-test.sh
```

Prepare runtime env path helper:

```bash
ROOT="$(pwd)"
source "$ROOT/scripts-linux/lib/runtime-env.sh"
CORE_ENV="$(tt_resolve_core_env_path "$ROOT")"
```

---

## Secret Inventory

| Variable | Services Affected | Downtime |
|---|---|---|
| `TT_POSTGRES_PASSWORD` | postgres + DB clients | brief restart |
| `TT_REDIS_PASSWORD` | redis, n8n, n8n-worker | brief restart |
| `TT_N8N_ENCRYPTION_KEY` | n8n credentials | high risk |
| `TT_N8N_DB_PASSWORD` | n8n, n8n-worker | brief restart |
| `TT_PGADMIN_PASSWORD` | pgadmin | service-only restart |
| `TT_REDISINSIGHT_PASSWORD` | redisinsight | service-only restart |
| `TT_METABASE_DB_PASSWORD` | metabase | brief restart |
| `TT_KANBOARD_DB_PASSWORD` | kanboard | brief restart |
| `TT_WP_DB_PASSWORD` | wordpress/mariadb | brief restart |
| `TT_WP_ROOT_PASSWORD` | mariadb | brief restart |
| `TT_QDRANT_API_KEY` | qdrant | service-only restart |
| `TT_OPENCLAW_TOKEN` | openclaw | service-only restart |

---

## Rotate `TT_POSTGRES_PASSWORD`

```bash
NEW_PG_PASS=$(openssl rand -hex 24)
OLD_PG_PASS=$(grep '^TT_POSTGRES_PASSWORD=' "$CORE_ENV" | cut -d= -f2-)
PG_USER=$(grep '^TT_POSTGRES_USER=' "$CORE_ENV" | cut -d= -f2-)

docker exec -e PGPASSWORD="$OLD_PG_PASS" tt-core-postgres \
  psql -U "$PG_USER" -c "ALTER ROLE \"$PG_USER\" PASSWORD '${NEW_PG_PASS}';"

sed -i "s|^TT_POSTGRES_PASSWORD=.*|TT_POSTGRES_PASSWORD=${NEW_PG_PASS}|" "$CORE_ENV"

bash scripts-linux/stop-core.sh
bash scripts-linux/start-core.sh
bash scripts-linux/smoke-test.sh
```

---

## Rotate `TT_REDIS_PASSWORD`

```bash
NEW_REDIS_PASS=$(openssl rand -hex 24)
OLD_REDIS_PASS=$(grep '^TT_REDIS_PASSWORD=' "$CORE_ENV" | cut -d= -f2-)

docker exec tt-core-redis redis-cli -a "$OLD_REDIS_PASS" CONFIG SET requirepass "$NEW_REDIS_PASS"
sed -i "s|^TT_REDIS_PASSWORD=.*|TT_REDIS_PASSWORD=${NEW_REDIS_PASS}|" "$CORE_ENV"

docker compose -f compose/tt-core/docker-compose.yml --env-file "$CORE_ENV" restart n8n n8n-worker
```

---

## Rotate `TT_N8N_ENCRYPTION_KEY` (High Risk)

DATA LOSS WARNING: Changing this key without credential re-export/re-import makes n8n stored credentials unreadable and can cause permanent credential loss.

```bash
NEW_ENC_KEY=$(openssl rand -base64 32 | tr -d '=+/')
sed -i "s|^TT_N8N_ENCRYPTION_KEY=.*|TT_N8N_ENCRYPTION_KEY=${NEW_ENC_KEY}|" "$CORE_ENV"
docker compose -f compose/tt-core/docker-compose.yml --env-file "$CORE_ENV" restart n8n n8n-worker
```

Required manual flow:
1. Export credentials/workflows first.
2. Rotate key.
3. Re-enter credentials in n8n.

---

## Rotate Per-Service DB Passwords

Example (`TT_N8N_DB_PASSWORD`):

```bash
NEW_N8N_DB_PASS=$(openssl rand -hex 20)
PG_PASS=$(grep '^TT_POSTGRES_PASSWORD=' "$CORE_ENV" | cut -d= -f2-)
PG_USER=$(grep '^TT_POSTGRES_USER=' "$CORE_ENV" | cut -d= -f2-)
N8N_DB_USER=$(grep '^TT_N8N_DB_USER=' "$CORE_ENV" | cut -d= -f2-)

docker exec -e PGPASSWORD="$PG_PASS" tt-core-postgres \
  psql -U "$PG_USER" -c "ALTER ROLE \"${N8N_DB_USER}\" PASSWORD '${NEW_N8N_DB_PASS}';"

sed -i "s|^TT_N8N_DB_PASSWORD=.*|TT_N8N_DB_PASSWORD=${NEW_N8N_DB_PASS}|" "$CORE_ENV"
docker compose -f compose/tt-core/docker-compose.yml --env-file "$CORE_ENV" restart n8n n8n-worker
```

Use same pattern for `TT_METABASE_DB_PASSWORD` and `TT_KANBOARD_DB_PASSWORD`.

---

## Rotate Service-Only Secrets

```bash
# pgAdmin
NEW_PGADMIN_PASS=$(openssl rand -base64 18 | tr -d '=+/')
sed -i "s|^TT_PGADMIN_PASSWORD=.*|TT_PGADMIN_PASSWORD=${NEW_PGADMIN_PASS}|" "$CORE_ENV"
docker compose -f compose/tt-core/docker-compose.yml --env-file "$CORE_ENV" restart pgadmin

# RedisInsight
NEW_RI_PASS=$(openssl rand -hex 16)
sed -i "s|^TT_REDISINSIGHT_PASSWORD=.*|TT_REDISINSIGHT_PASSWORD=${NEW_RI_PASS}|" "$CORE_ENV"
docker compose -f compose/tt-core/docker-compose.yml --env-file "$CORE_ENV" restart redisinsight

# Qdrant
NEW_QDRANT_KEY=$(openssl rand -hex 24)
sed -i "s|^TT_QDRANT_API_KEY=.*|TT_QDRANT_API_KEY=${NEW_QDRANT_KEY}|" "$CORE_ENV"
docker compose -f compose/tt-core/docker-compose.yml --env-file "$CORE_ENV" restart qdrant

# OpenClaw
NEW_OPENCLAW_TOKEN=$(openssl rand -hex 24)
sed -i "s|^TT_OPENCLAW_TOKEN=.*|TT_OPENCLAW_TOKEN=${NEW_OPENCLAW_TOKEN}|" "$CORE_ENV"
docker compose -f compose/tt-core/docker-compose.yml --env-file "$CORE_ENV" restart openclaw
```

---

## WordPress/MariaDB Rotation

```bash
NEW_WP_DB_PASS=$(openssl rand -hex 20)
NEW_WP_ROOT_PASS=$(openssl rand -hex 20)
OLD_WP_ROOT_PASS=$(grep '^TT_WP_ROOT_PASSWORD=' "$CORE_ENV" | cut -d= -f2-)
WP_DB_USER=$(grep '^TT_WP_DB_USER=' "$CORE_ENV" | cut -d= -f2-)

docker exec -e MYSQL_PWD="$OLD_WP_ROOT_PASS" tt-core-mariadb \
  mysql -u root -e "ALTER USER '${WP_DB_USER}'@'%' IDENTIFIED BY '${NEW_WP_DB_PASS}'; FLUSH PRIVILEGES;"
docker exec -e MYSQL_PWD="$OLD_WP_ROOT_PASS" tt-core-mariadb \
  mysql -u root -e "ALTER USER 'root'@'%' IDENTIFIED BY '${NEW_WP_ROOT_PASS}'; FLUSH PRIVILEGES;"

sed -i "s|^TT_WP_DB_PASSWORD=.*|TT_WP_DB_PASSWORD=${NEW_WP_DB_PASS}|" "$CORE_ENV"
sed -i "s|^TT_WP_ROOT_PASSWORD=.*|TT_WP_ROOT_PASSWORD=${NEW_WP_ROOT_PASS}|" "$CORE_ENV"

docker compose -f compose/tt-core/docker-compose.yml --env-file "$CORE_ENV" restart wordpress mariadb
```

---

## Rotation Schedule

| Secret Class | Recommended Interval | Notes |
|---|---|---|
| Infrastructure passwords | every 90 days | PostgreSQL, Redis, admin UI credentials |
| External/API tokens | every 60-90 days | Qdrant, OpenClaw, and similar service tokens |
| Break-glass / high-impact keys | planned only | `TT_N8N_ENCRYPTION_KEY` requires export and re-entry planning |

## Automated Helper

```bash
bash scripts-linux/rotate-secrets.sh --dry-run
bash scripts-linux/rotate-secrets.sh --secret TT_PGADMIN_PASSWORD
```

Always run `bash scripts-linux/smoke-test.sh` after any rotation.

