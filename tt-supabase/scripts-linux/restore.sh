#!/usr/bin/env bash
# =============================================================================
# tt-supabase restore.sh — TT-Production v14.0
#
# Restores a tt-supabase PostgreSQL dump from a backup archive.
# Stops Supabase stack, restores, restarts.
#
# Usage:
#   bash scripts-linux/restore.sh /path/to/supabase-backup-YYYYMMDD-HHMMSS.tar.gz
#   bash scripts-linux/restore.sh /path/to/backup.tar.gz --dry-run
# =============================================================================
set -euo pipefail
VER="v14.0"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
CORE_ROOT="$(cd "$ROOT/../tt-core" && pwd)"
RUNTIME_ENV_LIB="$CORE_ROOT/scripts-linux/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"
COMPOSE_DIR="$ROOT/compose/tt-supabase"

log()  { echo -e "${CYAN}[restore]${NC} $*"; }
ok()   { echo -e "${GREEN}[restore]${NC} ✓ $*"; }
err()  { echo -e "${RED}[restore]${NC} ✗ $*"; exit 1; }
warn() { echo -e "${YELLOW}[restore]${NC} ⚠ $*"; }

echo ""
echo -e "${CYAN}${BOLD}TT-Supabase Restore — $VER${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo ""

DRY_RUN=0; BACKUP_ARCHIVE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    *) BACKUP_ARCHIVE="$1" ;;
  esac
  shift
done

[[ -z "$BACKUP_ARCHIVE" ]] && err "Usage: $0 <backup-archive.tar.gz> [--dry-run]"
[[ ! -f "$BACKUP_ARCHIVE" ]] && err "Backup archive not found: $BACKUP_ARCHIVE"
[[ $DRY_RUN -eq 1 ]] && warn "DRY-RUN mode: no changes will be made"

log "Archive: $BACKUP_ARCHIVE"
log "Checking dependencies..."
command -v docker  >/dev/null || err "'docker' not found"
command -v tar     >/dev/null || err "'tar' not found"

# Extract archive to temp
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
log "Extracting backup archive..."
[[ $DRY_RUN -eq 0 ]] && tar -xzf "$BACKUP_ARCHIVE" -C "$TMPDIR" || ok "(dry-run) would extract archive"

if [[ $DRY_RUN -eq 1 ]]; then
  ok "Dry-run complete — no changes made"
  echo ""
  exit 0
fi

# Find dump file
DUMP=$(find "$TMPDIR" -name "*.dump" -o -name "*.dump.enc" 2>/dev/null | head -1)
[[ -z "$DUMP" ]] && err "No .dump or .dump.enc file found in archive"
log "Dump file: $DUMP"

log "Stopping tt-supabase..."
docker compose -f "$COMPOSE_DIR/docker-compose.yml" down 2>/dev/null || true

# If encrypted, decrypt first
if [[ "$DUMP" == *.enc ]]; then
  ENV_FILE="$(tt_resolve_core_env_path "$CORE_ROOT")"
  [[ ! -f "$ENV_FILE" ]] && ENV_FILE="$CORE_ROOT/env/.env.example"
  ENC_KEY=$(grep -E "^TT_BACKUP_ENCRYPTION_KEY=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
  [[ -z "$ENC_KEY" ]] && err "TT_BACKUP_ENCRYPTION_KEY not set — cannot decrypt"
  PLAIN="${DUMP%.enc}"
  log "Decrypting dump..."
  openssl enc -d -aes-256-cbc -pbkdf2 -in "$DUMP" -out "$PLAIN" -pass "pass:$ENC_KEY"
  DUMP="$PLAIN"
  ok "Decryption successful"
fi

log "Starting Supabase DB only..."
docker compose -f "$COMPOSE_DIR/docker-compose.yml" up -d db 2>/dev/null || true
sleep 5

log "Restoring PostgreSQL dump..."
docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T db   pg_restore --clean --if-exists -d postgres < "$DUMP" 2>&1 || warn "pg_restore reported warnings (often non-fatal)"

log "Starting full tt-supabase stack..."
docker compose -f "$COMPOSE_DIR/docker-compose.yml" up -d

ok "tt-supabase restore complete"
echo ""
