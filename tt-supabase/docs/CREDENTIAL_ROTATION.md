# Credential Rotation — TT-Supabase (TT-Production v14.0)

This document covers safe rotation of all TT-Supabase secrets in production
without data loss. Always take a backup before any credential rotation.

---

## Before Any Rotation

```bash
# 1. Backup first
bash scripts-linux/backup.sh

# 2. Verify the stack is healthy
bash scripts-linux/smoke-test.sh
```

---

## Rotating DASHBOARD_PASSWORD

The Dashboard password protects the Supabase Studio UI via Kong basic-auth.
Rotation is safe and zero-downtime.

```bash
# 1. Generate new password
NEW_PASS=$(openssl rand -base64 18 | tr -d '=+/')
echo "New password: $NEW_PASS"

# 2. Update env file
sed -i "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=${NEW_PASS}|" compose/tt-supabase/.env

# 3. Restart Kong only (no DB downtime)
cd compose/tt-supabase
docker compose restart kong

# 4. Test login with new credentials
bash ../../scripts-linux/smoke-test.sh
```

---

## Rotating POSTGRES_PASSWORD

> ⚠️ This requires a brief service restart. Schedule a maintenance window.
> POSTGRES_PASSWORD is used by all internal Supabase service roles.

```bash
# 1. Backup
bash scripts-linux/backup.sh

# 2. Generate new password
NEW_PG_PASS=$(openssl rand -base64 32 | tr -d '=+/')

# 3. Update password inside PostgreSQL (while running)
docker exec -it supabase-db psql -U postgres -c \
  "ALTER ROLE postgres PASSWORD '${NEW_PG_PASS}';"
docker exec -it supabase-db psql -U postgres -c \
  "ALTER ROLE supabase_admin PASSWORD '${NEW_PG_PASS}';"
docker exec -it supabase-db psql -U postgres -c \
  "ALTER ROLE supabase_auth_admin PASSWORD '${NEW_PG_PASS}';"
docker exec -it supabase-db psql -U postgres -c \
  "ALTER ROLE authenticator PASSWORD '${NEW_PG_PASS}';"
docker exec -it supabase-db psql -U postgres -c \
  "ALTER ROLE supabase_storage_admin PASSWORD '${NEW_PG_PASS}';"

# 4. Update env file
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${NEW_PG_PASS}|" compose/tt-supabase/.env

# 5. Restart all services (they will pick up new password from env)
cd compose/tt-supabase
docker compose down && docker compose up -d

# 6. Verify
bash ../../scripts-linux/smoke-test.sh
```

---

## Rotating JWT_SECRET (+ ANON_KEY + SERVICE_ROLE_KEY)

> ⚠️ **High impact.** All active user sessions will be invalidated.
> All existing JWTs will be rejected immediately. Schedule a maintenance window
> and notify users that they will need to log in again.

```bash
# 1. Backup
bash scripts-linux/backup.sh

# 2. Run init.sh — it generates new JWT_SECRET and re-signs both JWTs
# WARNING: This WILL regenerate JWT_SECRET and invalidate all sessions.
bash scripts-linux/init.sh

# 3. Restart the full stack
cd compose/tt-supabase
docker compose down && docker compose up -d

# 4. Wait for health and verify
sleep 60
bash ../../scripts-linux/status.sh
bash ../../scripts-linux/smoke-test.sh

# 5. Update any client applications that have hardcoded ANON_KEY or SERVICE_ROLE_KEY
# The new keys are in compose/tt-supabase/.env:
grep -E "ANON_KEY|SERVICE_ROLE_KEY" ../../compose/tt-supabase/.env
```

---

## Rotating Realtime / Supavisor Keys

These keys are service-internal and can be rotated with a service restart.
User sessions are NOT affected.

```bash
# Generate new keys
NEW_RT_SKB=$(openssl rand -base64 32 | tr -d '=+/')
NEW_RT_ENC=$(openssl rand -base64 32 | tr -d '=+/')
NEW_SV_SKB=$(openssl rand -base64 32 | tr -d '=+/')
NEW_SV_VEK=$(openssl rand -base64 32 | tr -d '=+/')

# Update env file
sed -i "s|^REALTIME_SECRET_KEY_BASE=.*|REALTIME_SECRET_KEY_BASE=${NEW_RT_SKB}|" compose/tt-supabase/.env
sed -i "s|^REALTIME_DB_ENC_KEY=.*|REALTIME_DB_ENC_KEY=${NEW_RT_ENC}|" compose/tt-supabase/.env
sed -i "s|^SUPAVISOR_SECRET_KEY_BASE=.*|SUPAVISOR_SECRET_KEY_BASE=${NEW_SV_SKB}|" compose/tt-supabase/.env
sed -i "s|^SUPAVISOR_VAULT_ENC_KEY=.*|SUPAVISOR_VAULT_ENC_KEY=${NEW_SV_VEK}|" compose/tt-supabase/.env

# Restart affected services only
cd compose/tt-supabase
docker compose restart realtime supavisor

# Verify
bash ../../scripts-linux/smoke-test.sh
```

---

## Rotation Schedule (Recommended)

| Secret | Frequency | Notes |
|---|---|---|
| DASHBOARD_PASSWORD | Every 90 days | Low impact, zero downtime |
| POSTGRES_PASSWORD | Every 180 days | Brief restart required |
| JWT_SECRET | Only if compromised | Invalidates all sessions |
| Realtime/Supavisor keys | Every 180 days | Service restart only |


## Rotating Per-Service Secrets (REALTIME, SUPAVISOR)

```bash
# Regenerate REALTIME and SUPAVISOR secrets only
for key in REALTIME_SECRET_KEY_BASE REALTIME_DB_ENC_KEY SUPAVISOR_SECRET_KEY_BASE SUPAVISOR_VAULT_ENC_KEY; do
  sed -i "s/^${key}=.*/${key}=__GENERATE__/" compose/tt-supabase/.env
done
bash scripts-linux/init.sh

# Restart affected services
cd compose/tt-supabase
docker compose --env-file ../../compose/tt-supabase/.env restart realtime supavisor
cd ../..
bash scripts-linux/smoke-test.sh
```
