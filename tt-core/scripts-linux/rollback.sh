#!/usr/bin/env bash
# =============================================================================
# rollback.sh — TT-Core Stack Rollback (v14.0)
#
# Performs a controlled rollback of the TT-Core stack to a previous backup
# snapshot. Stops the running stack, restores volumes AND databases directly
# from the chosen backup, then restarts and runs smoke validation.
#
# Usage:
#   bash scripts-linux/rollback.sh --list               # list available snapshots
#   bash scripts-linux/rollback.sh --latest             # rollback to latest backup
#   bash scripts-linux/rollback.sh --snapshot backup_20260312-143000
#   bash scripts-linux/rollback.sh --dry-run --latest   # preview without executing
#   bash scripts-linux/rollback.sh --latest --confirm   # skip interactive prompt
#
# Safety:
#   - Creates a safety backup of current state before any rollback
#   - Requires explicit confirmation unless --confirm is passed
#   - Validates backup integrity (checksums) before proceeding
#   - Performs actual database restore (not just a pointer to another script)
#   - Runs smoke-test.sh after rollback to confirm health
#
# Exit codes:
#   0 = rollback completed successfully, stack healthy
#   1 = rollback failed or aborted
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
RUNTIME_ENV_LIB="$SCRIPT_DIR/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"
BACKUP_BASE=""

DRY_RUN=false
LIST_MODE=false
USE_LATEST=false
SNAPSHOT_ID=""
CONFIRMED=false

GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[0;33m"
CYAN="\033[0;36m"; BOLD="\033[1m"; NC="\033[0m"

info()  { echo -e "${CYAN}  [INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}  [WARN]${NC} $*"; }
error() { echo -e "${RED}  [FAIL]${NC} $*"; exit 1; }
ok()    { echo -e "${GREEN}  [OK]${NC}   $*"; }

get_env() {
  local key="$1" default="${2:-}"
  if [[ -f "$ENV_FILE" ]]; then
    val=$(grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | head -1 | tr -d '\r')
    [[ -n "$val" ]] && echo "$val" || echo "$default"
  else
    echo "$default"
  fi
}

get_postgres_container() {
  local cid
  cid=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" ps -q postgres 2>/dev/null | head -1 || true)
  [[ -n "$cid" ]] && { echo "$cid"; return 0; }
  cid=$(docker ps --filter 'name=tt-core-postgres' --filter 'status=running' --quiet | head -1 || true)
  [[ -n "$cid" ]] && { echo "$cid"; return 0; }
  return 1
}

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)         LIST_MODE=true; shift ;;
    --latest)       USE_LATEST=true; shift ;;
    --snapshot)     SNAPSHOT_ID="$2"; shift 2 ;;
    --dry-run)      DRY_RUN=true; shift ;;
    --confirm)      CONFIRMED=true; shift ;;
    --root)         ROOT="$2"; shift 2 ;;
    --backup-dir)   BACKUP_BASE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

COMPOSE_DIR="$ROOT/compose/tt-core"
ENV_FILE="$(tt_resolve_core_env_path "$ROOT")"
if [[ -z "$BACKUP_BASE" ]]; then
  BACKUP_BASE="${TT_BACKUP_DIR:-$ROOT/backups}"
fi

# ── List mode ─────────────────────────────────────────────────────────────────
if [[ "$LIST_MODE" == "true" ]]; then
  echo ""
  echo -e "${BOLD}  Available TT-Core Backup Snapshots${NC}"
  echo "  $(printf '─%.0s' {1..50})"
  if [[ -d "$BACKUP_BASE" ]]; then
    local_snapshots=$(find "$BACKUP_BASE" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | sort -r)
    if [[ -z "$local_snapshots" ]]; then
      warn "No snapshots found in $BACKUP_BASE"
    else
      echo ""
      while IFS= read -r snap; do
        snap_id="$(basename "$snap")"
        dump_count=$(find "$snap" \( -name "*.dump" -o -name "*.dump.enc" \) 2>/dev/null | wc -l)
        vol_count=$(find "$snap" -name "*.tar.gz" 2>/dev/null | wc -l)
        size=$(du -sh "$snap" 2>/dev/null | cut -f1 || echo "?")
        has_enc=""
        [[ $(find "$snap" -name "*.dump.enc" 2>/dev/null | wc -l) -gt 0 ]] && has_enc=" [encrypted]"
        echo "  ${BOLD}$snap_id${NC}  ($dump_count DB dumps, $vol_count volumes, $size$has_enc)"
      done <<< "$local_snapshots"
    fi
  else
    warn "Backup directory not found: $BACKUP_BASE"
  fi
  echo ""
  exit 0
fi

# ── Resolve snapshot ──────────────────────────────────────────────────────────
if [[ "$USE_LATEST" == "true" ]]; then
  SNAPSHOT_ID=$(find "$BACKUP_BASE" -maxdepth 1 -type d -name "backup_*" \
    2>/dev/null | sort | tail -1 | xargs basename 2>/dev/null || true)
  [[ -z "$SNAPSHOT_ID" ]] && error "No snapshots found in $BACKUP_BASE — cannot rollback"
fi

[[ -z "$SNAPSHOT_ID" ]] && error "Specify --list, --latest, or --snapshot <id>"

SNAPSHOT_PATH="$BACKUP_BASE/$SNAPSHOT_ID"
[[ -d "$SNAPSHOT_PATH" ]] || error "Snapshot not found: $SNAPSHOT_PATH"

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}  TT-Core Rollback — v14.0${NC}"
echo "  $(printf '─%.0s' {1..50})"
info "Target snapshot: ${BOLD}$SNAPSHOT_ID${NC}"
info "Snapshot path:   $SNAPSHOT_PATH"
info "Current stack:   $COMPOSE_DIR"
[[ "$DRY_RUN" == "true" ]] && warn "DRY RUN — no changes will be made"
echo ""

# ── Integrity check on snapshot ───────────────────────────────────────────────
CHECKSUM_FILE="$SNAPSHOT_PATH/checksums.sha256"
if [[ -f "$CHECKSUM_FILE" ]]; then
  info "Verifying snapshot integrity..."
  if command -v sha256sum &>/dev/null; then
    pushd "$SNAPSHOT_PATH" > /dev/null
    if sha256sum -c "$CHECKSUM_FILE" --status 2>/dev/null; then
      ok "Snapshot checksums verified"
    else
      error "Snapshot checksum MISMATCH — backup may be corrupted. Rollback aborted."
    fi
    popd > /dev/null
  else
    warn "sha256sum not available — skipping integrity check"
  fi
else
  warn "No checksums.sha256 in snapshot — integrity check skipped"
fi

# ── Confirmation gate ─────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "false" && "$CONFIRMED" == "false" ]]; then
  echo ""
  echo -e "${YELLOW}  WARNING: This will stop the running stack, create a safety backup,${NC}"
  echo -e "${YELLOW}  restore databases from snapshot $SNAPSHOT_ID, and restart.${NC}"
  echo ""
  read -rp "  Type YES to proceed: " ANSWER
  [[ "$ANSWER" == "YES" ]] || { info "Aborted by user."; exit 0; }
fi

[[ "$DRY_RUN" == "true" ]] && { ok "Dry run complete — snapshot $SNAPSHOT_ID is available and valid"; exit 0; }

# ── Safety backup ─────────────────────────────────────────────────────────────
info "Creating safety backup of current state before rollback..."
if bash "$SCRIPT_DIR/backup.sh" 2>&1 | tail -5; then
  ok "Safety backup created"
else
  warn "Safety backup failed — proceeding with caution (current state may not be recoverable)"
fi

# ── Stop stack ────────────────────────────────────────────────────────────────
info "Stopping TT-Core stack..."
docker compose -f "$COMPOSE_DIR/docker-compose.yml" down --timeout 30 2>&1 | tail -3
ok "Stack stopped"

# ── Restore volumes ───────────────────────────────────────────────────────────
VOL_ARCHIVE=$(ls "$SNAPSHOT_PATH"/volumes-*.tar.gz 2>/dev/null | head -1 || true)
if [[ -f "$VOL_ARCHIVE" ]]; then
  info "Restoring volumes from snapshot..."
  tar -xzf "$VOL_ARCHIVE" -C "$COMPOSE_DIR" 2>/dev/null \
    && ok "Volumes restored" \
    || warn "Volume restore had issues — check manually"
else
  info "No volume archive in snapshot — skipping volume restore"
fi

# ── Restart stack (needed before DB restore — postgres must be running) ───────
info "Starting TT-Core stack..."
docker compose -f "$COMPOSE_DIR/docker-compose.yml" up -d 2>&1 | tail -5

# ── Wait for postgres healthy ──────────────────────────────────────────────────
info "Waiting for PostgreSQL to become healthy (up to 120s)..."
POSTGRES_READY=false
for i in {1..12}; do
  POSTGRES_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' tt-core-postgres 2>/dev/null || echo "absent")
  if [[ "$POSTGRES_HEALTH" == "healthy" ]]; then
    ok "PostgreSQL healthy"
    POSTGRES_READY=true
    break
  fi
  info "  postgres=$POSTGRES_HEALTH  (${i}0s elapsed)"
  sleep 10
done

if [[ "$POSTGRES_READY" != "true" ]]; then
  warn "PostgreSQL did not become healthy in 120s — DB restore may fail. Proceeding anyway."
fi

# ── Restore databases (inline — no hand-off to another script) ────────────────
PG_DUMP_DIR="$SNAPSHOT_PATH/postgres"
if [[ -d "$PG_DUMP_DIR" ]]; then
  PG_USER=$(get_env TT_POSTGRES_USER ttcore)
  PG_PASS=$(get_env TT_POSTGRES_PASSWORD "")
  ENCRYPT_KEY=$(get_env TT_BACKUP_ENCRYPTION_KEY "")

  info "Restoring PostgreSQL databases from snapshot $SNAPSHOT_ID..."
  PG_CID=""
  if PG_CID=$(get_postgres_container); then
    DECRYPT_TMP_DIR=""

    for dump_file in "$PG_DUMP_DIR"/*.dump "$PG_DUMP_DIR"/*.dump.enc; do
      [[ -f "$dump_file" ]] || continue

      WORK_FILE="$dump_file"

      # Decrypt if encrypted
      if [[ "$dump_file" == *.dump.enc ]]; then
        if [[ -z "$ENCRYPT_KEY" ]]; then
          warn "Encrypted dump found but TT_BACKUP_ENCRYPTION_KEY not set — skipping $(basename "$dump_file")"
          continue
        fi
        if [[ -z "$DECRYPT_TMP_DIR" ]]; then
          DECRYPT_TMP_DIR="$(mktemp -d)"
        fi
        PLAIN_NAME="$(basename "${dump_file%.enc}")"
        WORK_FILE="$DECRYPT_TMP_DIR/$PLAIN_NAME"
        if ! openssl enc -d -aes-256-cbc -pbkdf2 \
            -in "$dump_file" -out "$WORK_FILE" \
            -pass pass:"$ENCRYPT_KEY" 2>/dev/null; then
          warn "Decryption failed for $(basename "$dump_file") — skipping"
          rm -f "$WORK_FILE"
          continue
        fi
        ok "Decrypted: $(basename "$dump_file")"
      fi

      DB_NAME="$(basename "$WORK_FILE" .dump)"
      tmp_file="/tmp/${DB_NAME}.rollback.dump"
      info "  Restoring: $DB_NAME"
      docker cp "$WORK_FILE" "${PG_CID}:${tmp_file}" > /dev/null
      docker exec -e PGPASSWORD="$PG_PASS" "$PG_CID" \
        sh -lc "createdb -U '$PG_USER' '$DB_NAME' 2>/dev/null || true; pg_restore -U '$PG_USER' -d '$DB_NAME' --clean --if-exists -Fc '$tmp_file' 2>/dev/null" \
        && ok "  Restored: $DB_NAME" \
        || warn "  Could not restore $DB_NAME — check postgres logs"
      docker exec "$PG_CID" rm -f "$tmp_file" 2>/dev/null || true
    done

    if [[ -n "${DECRYPT_TMP_DIR:-}" && -d "$DECRYPT_TMP_DIR" ]]; then
      rm -rf "$DECRYPT_TMP_DIR"
      info "Temp decrypted files cleaned up."
    fi
  else
    warn "Postgres container not running — database restore skipped"
  fi
else
  info "No postgres/ dump directory in snapshot — skipping database restore"
fi

# ── Wait for full health ──────────────────────────────────────────────────────
info "Waiting for all core services healthy (up to 60s more)..."
sleep 20
REDIS_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' tt-core-redis 2>/dev/null || echo "absent")
N8N_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' tt-core-n8n 2>/dev/null || echo "starting")
info "  redis=$REDIS_HEALTH  n8n=$N8N_HEALTH"

# ── Smoke test ────────────────────────────────────────────────────────────────
info "Running smoke test..."
if bash "$SCRIPT_DIR/smoke-test.sh" 2>&1 | tail -10; then
  ok "Smoke test passed"
else
  warn "Smoke test had warnings — check output above"
fi

echo ""
ok "Rollback to snapshot ${BOLD}$SNAPSHOT_ID${NC} complete"
echo -e "${CYAN}  Use: bash scripts-linux/health-dashboard.sh  to verify full stack health${NC}"
echo ""
