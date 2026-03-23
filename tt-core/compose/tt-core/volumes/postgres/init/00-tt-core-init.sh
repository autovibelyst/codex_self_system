#!/bin/sh
# =============================================================================
# TT-Core — PostgreSQL initialization script
# Version: 1.3.0-production
# TT-Production v14.0
#
# Runs via db-provisioner on each stack start (idempotent — safe to re-run).
# Creates dedicated databases and isolated users for each service.
#
# SECURITY MODEL — Least Privilege (FIX P2-4):
#   Each service has its OWN database + its OWN user.
#   GRANT: CONNECT on DATABASE + CREATE/USAGE on SCHEMA public only.
#   No CREATEDB, no cross-service access, no superuser grants.
#   Compromise of one service cannot affect another service's data.
#
# Databases + users created:
#   n8n         → user: TT_N8N_DB_USER        password: TT_N8N_DB_PASSWORD
#   metabase_db → user: TT_METABASE_DB_USER   password: TT_METABASE_DB_PASSWORD
#   kanboard_db → user: TT_KANBOARD_DB_USER   password: TT_KANBOARD_DB_PASSWORD
#
# pgAdmin connects as superuser (TT_POSTGRES_USER) — full access by design.
# =============================================================================
set -eu

echo "TT-Core db-provisioner: initializing databases and isolated users..."

# Helper: provision one database+user with least-privilege grants
provision_db() {
  DB="$1"
  DBUSER="$2"
  DBPASS="$3"

  psql -v ON_ERROR_STOP=1 --username "$PGUSER" --dbname "postgres" <<-EOSQL
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DBUSER}') THEN
        CREATE USER "${DBUSER}" WITH PASSWORD '${DBPASS}';
      ELSE
        ALTER USER "${DBUSER}" WITH PASSWORD '${DBPASS}';
      END IF;
    END
    \$\$;

    SELECT 'CREATE DATABASE "${DB}" OWNER "${DBUSER}"'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB}')\gexec

    -- Least privilege: CONNECT only (no CREATEDB, no superuser)
    GRANT CONNECT ON DATABASE "${DB}" TO "${DBUSER}";
EOSQL

  psql -v ON_ERROR_STOP=1 --username "$PGUSER" --dbname "${DB}" <<-EOSQL
    -- Schema access: CREATE + USAGE only (no unnecessary privileges)
    GRANT CREATE, USAGE ON SCHEMA public TO "${DBUSER}";
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "${DBUSER}";
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "${DBUSER}";
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO "${DBUSER}";
EOSQL

  echo "TT-Core db-provisioner: database '${DB}' + user '${DBUSER}' ready (least-privilege)."
}

# ── n8n ───────────────────────────────────────────────────────────────────────
if [ -n "${TT_N8N_DB:-}" ]; then
  provision_db "${TT_N8N_DB}" "${TT_N8N_DB_USER}" "${TT_N8N_DB_PASSWORD}"
fi

# ── Metabase ──────────────────────────────────────────────────────────────────
if [ -n "${TT_METABASE_DB:-}" ]; then
  provision_db "${TT_METABASE_DB}" "${TT_METABASE_DB_USER}" "${TT_METABASE_DB_PASSWORD}"
fi

# ── Kanboard ──────────────────────────────────────────────────────────────────
if [ -n "${TT_KANBOARD_DB:-}" ]; then
  provision_db "${TT_KANBOARD_DB}" "${TT_KANBOARD_DB_USER}" "${TT_KANBOARD_DB_PASSWORD}"
fi

echo "TT-Core db-provisioner: initialization complete."
