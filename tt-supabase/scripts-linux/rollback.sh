#!/usr/bin/env bash
# =============================================================================
# tt-supabase rollback.sh — TT-Production v14.0
#
# Rolls back tt-supabase to the most recent snapshot backup.
# Verifies checksum before restoring.
#
# Usage:
#   bash scripts-linux/rollback.sh --latest
#   bash scripts-linux/rollback.sh --backup /path/to/backup-dir
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

log()  { echo -e "${CYAN}[rollback]${NC} $*"; }
ok()   { echo -e "${GREEN}[rollback]${NC} ✓ $*"; }
err()  { echo -e "${RED}[rollback]${NC} ✗ $*"; exit 1; }
warn() { echo -e "${YELLOW}[rollback]${NC} ⚠ $*"; }

echo ""
echo -e "${CYAN}${BOLD}TT-Supabase Rollback — $VER${NC}"
echo -e "${CYAN}═════════════════════════════════════════${NC}"
echo ""

BACKUP_DIR=""; USE_LATEST=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --latest)  USE_LATEST=1 ;;
    --backup)  BACKUP_DIR="$2"; shift ;;
    *) ;;
  esac
  shift
done

BACKUP_BASE="${TT_BACKUP_DIR:-$HOME/tt-backups}/tt-supabase"

if [[ $USE_LATEST -eq 1 ]]; then
  BACKUP_DIR=$(ls -1td "$BACKUP_BASE"/backup-* 2>/dev/null | head -1 || true)
  [[ -z "$BACKUP_DIR" ]] && err "No snapshots found in $BACKUP_BASE"
  log "Latest snapshot: $BACKUP_DIR"
fi

[[ -z "$BACKUP_DIR" ]] && err "Usage: $0 --latest | --backup <dir>"
[[ ! -d "$BACKUP_DIR" ]] && err "Backup directory not found: $BACKUP_DIR"

# Checksum verification
CHECKSUM_FILE="$BACKUP_DIR/checksums.sha256"
if [[ -f "$CHECKSUM_FILE" ]]; then
  log "Verifying checksums..."
  cd "$BACKUP_DIR"
  sha256sum -c checksums.sha256 >/dev/null 2>&1 && ok "Checksum verification PASSED" || err "Checksum MISMATCH — backup may be corrupt"
  cd "$OLDPWD"
else
  warn "No checksums.sha256 found — proceeding without verification"
fi

DUMP=$(find "$BACKUP_DIR" -name "*.dump" -o -name "*.dump.enc" 2>/dev/null | head -1)
[[ -z "$DUMP" ]] && err "No dump file found in $BACKUP_DIR"
log "Dump: $DUMP"

log "Stopping tt-supabase..."
docker compose -f "$COMPOSE_DIR/docker-compose.yml" down 2>/dev/null || true

log "Starting DB only..."
docker compose -f "$COMPOSE_DIR/docker-compose.yml" up -d db
sleep 5

if [[ "$DUMP" == *.enc ]]; then
  ENV_FILE="$(tt_resolve_core_env_path "$CORE_ROOT")"
  ENC_KEY=$(grep -E "^TT_BACKUP_ENCRYPTION_KEY=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
  [[ -z "$ENC_KEY" ]] && err "TT_BACKUP_ENCRYPTION_KEY not set"
  PLAIN="${DUMP%.enc}"
  openssl enc -d -aes-256-cbc -pbkdf2 -in "$DUMP" -out "$PLAIN" -pass "pass:$ENC_KEY"
  DUMP="$PLAIN"
  ok "Decrypted"
fi

log "Restoring..."
docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T db   pg_restore --clean --if-exists -d postgres < "$DUMP" 2>&1 || warn "pg_restore warnings (may be non-fatal)"

log "Restarting full stack..."
docker compose -f "$COMPOSE_DIR/docker-compose.yml" up -d

ok "Rollback complete from: $BACKUP_DIR"
echo ""
