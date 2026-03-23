#!/usr/bin/env bash
# =============================================================================
# TT-Supabase backup.sh — Automated Backup (TT-Production v14.0)
#
# Creates timestamped backups of:
#   - PostgreSQL database (pg_dump inside container)
#   - Storage volumes (file uploads)
#
# Usage:
#   bash scripts-linux/backup.sh              # full backup
#   bash scripts-linux/backup.sh --db-only    # database only
#   bash scripts-linux/backup.sh --restore <TIMESTAMP>  # restore from backup
#
# Backup location: <ROOT>/backups/YYYY-MM-DD_HH-MM-SS/
# Retention: last 7 backups (configurable with BACKUP_KEEP=N)
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

# ── Parse arguments ───────────────────────────────────────────────────────────
DB_ONLY=false
RESTORE_TS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)      ROOT="$2"; shift 2 ;;
    --db-only)   DB_ONLY=true; shift ;;
    --restore)   RESTORE_TS="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

ENV_FILE="$ROOT/compose/tt-supabase/.env"
COMPOSE_DIR="$ROOT/compose/tt-supabase"
BACKUP_ROOT="$ROOT/backups"
BACKUP_KEEP="${BACKUP_KEEP:-7}"

get_val() { grep "^${1}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | xargs 2>/dev/null || true; }

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]${NC}   $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $*"; }

# ── Restore mode ──────────────────────────────────────────────────────────────
if [[ -n "$RESTORE_TS" ]]; then
  RESTORE_DIR="$BACKUP_ROOT/${RESTORE_TS}"
  echo ""
  echo -e "${CYAN}── TT-Supabase Restore — ${RESTORE_TS} ──────────────────────────${NC}"
  echo ""

  [[ ! -d "$RESTORE_DIR" ]] && fail "Backup not found: $RESTORE_DIR" && exit 1

  PG_PASS=$(get_val POSTGRES_PASSWORD)
  PG_DB=$(get_val POSTGRES_DB)
  PG_DB="${PG_DB:-postgres}"
  DUMP_FILE="$RESTORE_DIR/postgres.dump"

  [[ ! -f "$DUMP_FILE" ]] && fail "Dump file not found: $DUMP_FILE" && exit 1

  warn "This will OVERWRITE the current database. Press Ctrl+C to cancel. Continuing in 5s..."
  sleep 5

  info "Restoring database from $DUMP_FILE ..."
  docker exec -i supabase-db psql -U postgres -d "$PG_DB" < "$DUMP_FILE"
  ok "Database restored"

  echo ""
  echo -e "${GREEN}✓ Restore complete from ${RESTORE_TS}${NC}"
  exit 0
fi

# ── Backup mode ───────────────────────────────────────────────────────────────
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="$BACKUP_ROOT/${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"

echo ""
echo -e "${CYAN}── TT-Supabase Backup — ${TIMESTAMP} ──────────────────────────${NC}"
echo ""

# Check database container is running
if ! docker inspect supabase-db >/dev/null 2>&1; then
  fail "supabase-db container not found — is the stack running?"
  exit 1
fi
CONTAINER_STATE=$(docker inspect -f '{{.State.Running}}' supabase-db 2>/dev/null || echo "false")
if [[ "$CONTAINER_STATE" != "true" ]]; then
  fail "supabase-db is not running"
  exit 1
fi

# ── Database backup ───────────────────────────────────────────────────────────
PG_DB=$(get_val POSTGRES_DB)
PG_DB="${PG_DB:-postgres}"
DUMP_FILE="$BACKUP_DIR/postgres.dump"
DUMP_FILE_SQL="$BACKUP_DIR/postgres.sql"

info "Dumping PostgreSQL database '${PG_DB}' ..."
docker exec supabase-db pg_dump -U postgres -d "$PG_DB" --format=custom --compress=6 \
  --file=/tmp/backup.dump 2>/dev/null
docker cp supabase-db:/tmp/backup.dump "$DUMP_FILE"
docker exec supabase-db rm -f /tmp/backup.dump
ok "Database dump: $DUMP_FILE ($(du -sh "$DUMP_FILE" | cut -f1))"

# Human-readable SQL dump as well (for quick inspection)
docker exec supabase-db pg_dump -U postgres -d "$PG_DB" --format=plain --no-password \
  > "$DUMP_FILE_SQL" 2>/dev/null || true
ok "SQL dump: $DUMP_FILE_SQL ($(du -sh "$DUMP_FILE_SQL" | cut -f1))"

# ── Storage backup ────────────────────────────────────────────────────────────
if [[ "$DB_ONLY" == "false" ]]; then
  STORAGE_DIR="$COMPOSE_DIR/volumes/storage"
  if [[ -d "$STORAGE_DIR" ]]; then
    info "Archiving storage volumes ..."
    tar -czf "$BACKUP_DIR/storage.tar.gz" -C "$COMPOSE_DIR/volumes" storage 2>/dev/null || true
    ok "Storage archive: $BACKUP_DIR/storage.tar.gz ($(du -sh "$BACKUP_DIR/storage.tar.gz" | cut -f1))"
  else
    info "Storage directory not found — skipping"
  fi
fi

# ── Write backup manifest ─────────────────────────────────────────────────────
cat > "$BACKUP_DIR/backup-manifest.json" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "product": "TT-Supabase",
  "version": "v14.0",
  "database": "${PG_DB}",
  "db_only": ${DB_ONLY},
  "files": [
    "postgres.dump",
    "postgres.sql"$(if [[ "$DB_ONLY" == "false" ]]; then echo ',"storage.tar.gz"'; fi)
  ]
}
EOF
ok "Manifest: $BACKUP_DIR/backup-manifest.json"

# ── Retention policy: keep last N backups ────────────────────────────────────
BACKUP_COUNT=$(ls -1d "$BACKUP_ROOT"/[0-9]* 2>/dev/null | wc -l || echo 0)
if [[ "$BACKUP_COUNT" -gt "$BACKUP_KEEP" ]]; then
  DELETE_COUNT=$(( BACKUP_COUNT - BACKUP_KEEP ))
  info "Applying retention policy (keep=${BACKUP_KEEP}) — removing ${DELETE_COUNT} old backup(s)"
  ls -1dt "$BACKUP_ROOT"/[0-9]* | tail -n "$DELETE_COUNT" | xargs rm -rf
  ok "Old backups removed"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Backup complete — TT-Supabase v14.0   ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Location: ${BACKUP_DIR}${NC}"
echo -e "${GREEN}║  To restore: bash scripts-linux/backup.sh --restore ${TIMESTAMP} ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
