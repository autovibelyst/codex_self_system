#!/usr/bin/env bash
# =============================================================================
# restore.sh — TT-Core restore (Linux/VPS/macOS)
# Version: v14.0
#
# Restores a backup created by backup.sh.
# Verifies SHA256 checksums before restoring any data.
# Supports both plain (.dump) and AES-256-CBC encrypted (.dump.enc) files.
# Requires explicit --confirm flag (or --force to skip countdown).
#
# Usage:
#   bash scripts-linux/restore.sh --backup-dir backups/backup_20260311-020000
#   bash scripts-linux/restore.sh --backup-dir backups/backup_20260311-020000 --confirm
#   bash scripts-linux/restore.sh --backup-dir backups/backup_20260311-020000 --force
#   bash scripts-linux/restore.sh --backup-dir backups/backup_20260311-020000 --root /opt/stacks/tt-core
#
# Exit codes:
#   0 = restore completed successfully
#   1 = fatal error (checksum mismatch, missing files, postgres not running)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
RUNTIME_ENV_LIB="$SCRIPT_DIR/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"
BACKUP_DIR=""
CONFIRM=false
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
    --root)       ROOT="$2"; shift 2 ;;
    --confirm)    CONFIRM=true; shift ;;
    --force)      FORCE=true; CONFIRM=true; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

COMPOSE_DIR="$ROOT/compose/tt-core"
ENV_FILE="$(tt_resolve_core_env_path "$ROOT")"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;37m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC}    $*"; }
err()  { echo -e "  ${RED}[ERR]${NC}   $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC}  $*"; }
info() { echo -e "  ${GRAY}[INFO]${NC}  $*"; }
die()  { echo -e "${RED}FATAL: $*${NC}"; exit 1; }

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN} TT-Core Restore — v14.0${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""

# ── Validate backup dir ───────────────────────────────────────────────────────
[[ -z "$BACKUP_DIR" ]] && die "--backup-dir is required. Run: bash scripts-linux/restore.sh --backup-dir backups/backup_<stamp>"
[[ "${BACKUP_DIR:0:1}" != "/" ]] && BACKUP_DIR="$ROOT/$BACKUP_DIR"
[[ ! -d "$BACKUP_DIR" ]] && die "Backup directory not found: $BACKUP_DIR"

MANIFEST="$BACKUP_DIR/backup-manifest.txt"
[[ ! -f "$MANIFEST" ]] && die "backup-manifest.txt not found in $BACKUP_DIR — is this a valid TT-Core backup?"

info "Backup directory: $BACKUP_DIR"
info "Manifest found: $MANIFEST"
echo ""

# ── Helper: load env value ────────────────────────────────────────────────────
get_env() {
  local key="$1" default="${2:-}"
  if [[ -f "$ENV_FILE" ]]; then
    val=$(grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | head -1 | tr -d '\r')
    [[ -n "$val" ]] && echo "$val" || echo "$default"
  else
    echo "$default"
  fi
}

checksum_tool() {
  if command -v sha256sum &>/dev/null; then
    echo "sha256sum"
  elif command -v shasum &>/dev/null; then
    echo "shasum"
  else
    return 1
  fi
}

calc_sha256() {
  local file="$1"
  case "$(checksum_tool)" in
    sha256sum) sha256sum "$file" | awk '{print $1}' ;;
    shasum)    shasum -a 256 "$file" | awk '{print $1}' ;;
  esac
}

verify_checksum_manifest() {
  local manifest="$1"
  local failed=0
  local line expected rel actual

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    if [[ ! "$line" =~ ^([A-Fa-f0-9]{64})[[:space:]]+(.+)$ ]]; then
      echo "Malformed checksum entry: $line"
      failed=1
      continue
    fi
    expected="${BASH_REMATCH[1],,}"
    rel="${BASH_REMATCH[2]}"
    if [[ ! -f "$rel" ]]; then
      echo "$rel: MISSING"
      failed=1
      continue
    fi
    actual="$(calc_sha256 "$rel" 2>/dev/null || true)"
    if [[ -z "$actual" || "${actual,,}" != "$expected" ]]; then
      echo "$rel: FAILED"
      failed=1
    fi
  done < "$manifest"

  return "$failed"
}

# ── Step 1: Checksum verification ─────────────────────────────────────────────
echo -e "[ 1 ] INTEGRITY CHECK"
CHECKSUM_FILE="$BACKUP_DIR/checksums.sha256"
if [[ -f "$CHECKSUM_FILE" ]]; then
  if checksum_tool &>/dev/null; then
    pushd "$BACKUP_DIR" > /dev/null
    if verify_checksum_manifest "$(basename "$CHECKSUM_FILE")"; then
      ok "All checksums verified"
    else
      echo ""
      err "CHECKSUM MISMATCH — backup may be corrupted:"
      verify_checksum_manifest "$(basename "$CHECKSUM_FILE")" || true
      die "Aborting restore — checksums do not match. Do not restore corrupted data."
    fi
    popd > /dev/null
  else
    die "No SHA-256 verification tool found (sha256sum or shasum). Cannot verify backup integrity."
  fi
else
  die "No checksums.sha256 found in backup. Strict restore mode requires checksum verification."
fi
echo ""

# ── Step 2: Confirmation gate ─────────────────────────────────────────────────
echo -e "[ 2 ] CONFIRMATION"
if [[ "$CONFIRM" != "true" ]]; then
  echo ""
  echo -e "${YELLOW}  ⚠ WARNING: This will OVERWRITE existing database data.${NC}"
  echo -e "${YELLOW}  ⚠ Backup being restored: $(basename "$BACKUP_DIR")${NC}"
  echo ""
  echo "  To confirm, re-run with --confirm flag:"
  echo "    bash scripts-linux/restore.sh --backup-dir $(basename "$BACKUP_DIR") --confirm"
  echo ""
  exit 0
fi

if [[ "$FORCE" != "true" ]]; then
  echo ""
  echo -e "${YELLOW}  ⚠ RESTORING: $(basename "$BACKUP_DIR")${NC}"
  echo -e "${YELLOW}  ⚠ This will overwrite existing database contents.${NC}"
  echo ""
  echo "  Press Ctrl+C to abort. Proceeding in 10 seconds..."
  sleep 10 || die "Aborted by user"
fi
ok "Confirmed. Starting restore..."
echo ""

PG_USER=$(get_env TT_POSTGRES_USER ttcore)
PG_PASS=$(get_env TT_POSTGRES_PASSWORD "")
WP_ROOT_PASS=$(get_env TT_WP_ROOT_PASSWORD "")
ENCRYPT_KEY=$(get_env TT_BACKUP_ENCRYPTION_KEY "")

# ── Step 3: PostgreSQL restore ────────────────────────────────────────────────
echo -e "[ 3 ] POSTGRESQL RESTORE"
PG_DUMP_DIR="$BACKUP_DIR/postgres"

get_postgres_container() {
  local cid
  cid=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" ps -q postgres 2>/dev/null | head -1 || true)
  [[ -n "$cid" ]] && { echo "$cid"; return 0; }
  cid=$(docker ps --filter 'name=tt-core-postgres' --filter 'status=running' --quiet | head -1 || true)
  [[ -n "$cid" ]] && { echo "$cid"; return 0; }
  return 1
}

if [[ -d "$PG_DUMP_DIR" ]]; then
  PG_CID=""
  if PG_CID=$(get_postgres_container); then
    DECRYPT_TMP_DIR=""

    # Process both plain .dump and encrypted .dump.enc files
    for dump_file in "$PG_DUMP_DIR"/*.dump "$PG_DUMP_DIR"/*.dump.enc; do
      [[ -f "$dump_file" ]] || continue

      # ── Decrypt if encrypted (.dump.enc) ──────────────────────────────────
      WORK_FILE="$dump_file"
      if [[ "$dump_file" == *.dump.enc ]]; then
        if [[ -z "$ENCRYPT_KEY" ]]; then
          err "Encrypted backup found ($(basename "$dump_file")) but TT_BACKUP_ENCRYPTION_KEY is not set in runtime env"
          err "Set TT_BACKUP_ENCRYPTION_KEY and retry."
          continue
        fi
        # Create temp dir for decrypted files on first encrypted file
        if [[ -z "$DECRYPT_TMP_DIR" ]]; then
          DECRYPT_TMP_DIR="$(mktemp -d)"
          info "Decrypting encrypted dump(s) to temp directory..."
        fi
        PLAIN_NAME="$(basename "${dump_file%.enc}")"
        WORK_FILE="$DECRYPT_TMP_DIR/$PLAIN_NAME"
        if openssl enc -d -aes-256-cbc -pbkdf2 \
            -in "$dump_file" -out "$WORK_FILE" \
            -pass pass:"$ENCRYPT_KEY" 2>/dev/null; then
          ok "Decrypted: $(basename "$dump_file") → $PLAIN_NAME"
        else
          err "Decryption failed for $(basename "$dump_file") — wrong key or corrupted file"
          rm -f "$WORK_FILE"
          continue
        fi
      fi

      DB_NAME="$(basename "$WORK_FILE" .dump)"
      tmp_file="/tmp/${DB_NAME}.restore.dump"
      echo "  Restoring database: $DB_NAME"
      docker cp "$WORK_FILE" "${PG_CID}:${tmp_file}" > /dev/null
      if docker exec -e PGPASSWORD="$PG_PASS" "$PG_CID" \
          sh -lc "pg_restore -U '$PG_USER' -d '$DB_NAME' --clean --if-exists -Fc '$tmp_file'" 2>/dev/null; then
        ok "Restored: $DB_NAME"
      else
        # Try create+restore if DB doesn't exist yet
        docker exec -e PGPASSWORD="$PG_PASS" "$PG_CID" \
          sh -lc "createdb -U '$PG_USER' '$DB_NAME' 2>/dev/null || true; pg_restore -U '$PG_USER' -d '$DB_NAME' --clean --if-exists -Fc '$tmp_file'" 2>/dev/null \
          && ok "Restored (recreated): $DB_NAME" \
          || warn "Could not restore $DB_NAME — it may not be initialized yet"
      fi
      docker exec "$PG_CID" rm -f "$tmp_file" 2>/dev/null || true
    done

    # Clean up decrypted temp files
    if [[ -n "$DECRYPT_TMP_DIR" && -d "$DECRYPT_TMP_DIR" ]]; then
      rm -rf "$DECRYPT_TMP_DIR"
      info "Temp decrypted files cleaned up."
    fi
  else
    warn "Postgres container not running — database restore skipped"
    warn "Start the stack first: bash scripts-linux/start-core.sh"
  fi
else
  info "No postgres/ dump directory in backup — skipping database restore"
fi
echo ""

# ── Step 4: MariaDB/WordPress restore ────────────────────────────────────────
echo -e "[ 4 ] MARIADB/WORDPRESS RESTORE"
WP_SQL="$BACKUP_DIR/wordpress.sql"
if [[ -f "$WP_SQL" ]]; then
  MARIA_CID=$(docker ps --filter 'name=tt-core-mariadb' --filter 'status=running' --quiet 2>/dev/null | head -1 || true)
  if [[ -n "$MARIA_CID" ]] && [[ -n "$WP_ROOT_PASS" ]]; then
    if docker exec -i -e MYSQL_PWD="$WP_ROOT_PASS" "$MARIA_CID" \
        mysql -u root wordpress < "$WP_SQL" 2>/dev/null; then
      ok "WordPress database restored"
    else
      warn "Could not restore WordPress database — MariaDB may need initialization first"
    fi
  else
    info "MariaDB not running or WP root password unavailable — WordPress restore skipped"
  fi
else
  info "No wordpress.sql in backup — WordPress restore skipped"
fi
echo ""

# ── Step 5: Volume restore ────────────────────────────────────────────────────
echo -e "[ 5 ] VOLUME RESTORE"
VOL_ARCHIVE=$(ls "$BACKUP_DIR"/volumes-*.tar.gz 2>/dev/null | head -1 || true)
if [[ -f "$VOL_ARCHIVE" ]]; then
  warn "Volume archive found: $(basename "$VOL_ARCHIVE")"
  warn "Volume restore overwrites all bind-mount data (n8n workflows, pgAdmin config, etc.)"
  echo ""
  if [[ "$FORCE" == "true" ]]; then
    echo "  Restoring volumes (--force mode)..."
    tar -xzf "$VOL_ARCHIVE" -C "$COMPOSE_DIR" 2>/dev/null \
      && ok "Volumes restored from archive" \
      || warn "Volume restore had issues — check manually"
  else
    echo -e "  ${YELLOW}Volume restore is OPTIONAL and potentially destructive.${NC}"
    echo "  To restore volumes, re-run with --force:"
    echo "    bash scripts-linux/restore.sh --backup-dir $(basename "$BACKUP_DIR") --confirm --force"
    info "Skipping volume restore (databases already restored above)"
  fi
else
  info "No volume archive in backup — skipping"
fi
echo ""

# ── Step 6: Summary ───────────────────────────────────────────────────────────
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN} Restore complete.${NC}"
echo ""
echo " Next steps:"
echo -e "  ${GRAY}1) Restart stack: bash scripts-linux/stop-core.sh && bash scripts-linux/start-core.sh${NC}"
echo -e "  ${GRAY}2) Smoke test:    bash scripts-linux/smoke-test.sh${NC}"
echo ""
