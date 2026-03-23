#!/usr/bin/env bash
# =============================================================================
# backup-offsite.sh — TT-Core Offsite Backup (v14.0)
#
# Syncs local backups/ directory to a remote destination using rclone.
# Supports: S3, Wasabi, Cloudflare R2, Backblaze B2, SFTP, and any
# rclone-compatible remote.
#
# Prerequisites:
#   - rclone installed: https://rclone.org/install/
#   - rclone configured: rclone config
#   - TT_OFFSITE_REMOTE set in runtime core env (e.g., "myS3:mybucket/tt-backups")
#
# Usage:
#   bash scripts-linux/backup-offsite.sh
#   bash scripts-linux/backup-offsite.sh --remote myS3:bucket/path
#   bash scripts-linux/backup-offsite.sh --dry-run
#   bash scripts-linux/backup-offsite.sh --root /path/to/tt-core
#
# Exit codes:
#   0 = sync completed successfully
#   1 = sync failed or prerequisites not met
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
RUNTIME_ENV_LIB="$SCRIPT_DIR/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"
REMOTE_OVERRIDE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote)  REMOTE_OVERRIDE="$2"; shift 2 ;;
    --root)    ROOT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) shift ;;
  esac
done

ENV_FILE="$(tt_resolve_core_env_path "$ROOT")"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]${NC}   $*"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; exit 1; }

get_env() {
  local key="$1" default="${2:-}"
  if [[ -f "$ENV_FILE" ]]; then
    local val
    val=$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' || true)
    [[ -n "$val" ]] && echo "$val" || echo "$default"
  else
    echo "$default"
  fi
}

BACKUP_DIR="${TT_BACKUP_DIR:-$ROOT/backups}"

# ── Resolve remote ────────────────────────────────────────────────────────────
REMOTE="${REMOTE_OVERRIDE:-$(get_env TT_OFFSITE_REMOTE "")}"

echo ""
echo -e "${CYAN}TT-Core Offsite Backup — v14.0 — $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo ""

# ── Prerequisite: rclone ──────────────────────────────────────────────────────
if ! command -v rclone &>/dev/null; then
  fail "rclone not found. Install from https://rclone.org/install/ then run: rclone config"
fi
ok "rclone found: $(rclone version --check 2>/dev/null | head -1 || rclone version 2>/dev/null | head -1)"

# ── Prerequisite: remote configured ──────────────────────────────────────────
if [[ -z "$REMOTE" ]]; then
  fail "TT_OFFSITE_REMOTE is not configured.\n  Set it in $ENV_FILE (runtime env):\n    TT_OFFSITE_REMOTE=myremote:mybucket/tt-backups\n  Then run: rclone config  (to add 'myremote')"
fi
info "Remote: $REMOTE"

# ── Prerequisite: local backups exist ─────────────────────────────────────────
if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
  warn "No local backups found at $BACKUP_DIR — run backup.sh first"
  exit 0
fi
info "Local backup dir: $BACKUP_DIR"

# ── Create log directory ──────────────────────────────────────────────────────
mkdir -p "$ROOT/logs"
LOG_FILE="$ROOT/logs/offsite-backup-$(date +%Y%m%d-%H%M%S).log"

# ── Dry run notice ────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
  warn "DRY RUN — no files will be transferred"
  DRY_ARGS="--dry-run"
else
  DRY_ARGS=""
fi

# ── Run rclone sync ───────────────────────────────────────────────────────────
echo ""
info "Starting sync to $REMOTE ..."
echo "  Log: $LOG_FILE"
echo ""

SYNC_EXIT=0
rclone sync "$BACKUP_DIR" "$REMOTE" \
  ${DRY_ARGS} \
  --transfers 4 \
  --checkers 8 \
  --retries 3 \
  --low-level-retries 10 \
  --log-file "$LOG_FILE" \
  --log-level INFO \
  --stats 30s \
  --stats-log-level NOTICE \
  2>&1 || SYNC_EXIT=$?

# ── Notify webhook on result ──────────────────────────────────────────────────
WEBHOOK_URL=$(get_env TT_BACKUP_NOTIFY_WEBHOOK_URL "")
if [[ -n "$WEBHOOK_URL" ]]; then
  if [[ $SYNC_EXIT -eq 0 ]]; then
    MSG="✅ TT-Core Offsite Backup OK — synced to ${REMOTE} — $(hostname -s 2>/dev/null || echo host)"
  else
    MSG="❌ TT-Core Offsite Backup FAILED — exit ${SYNC_EXIT} — $(hostname -s 2>/dev/null || echo host)"
  fi
  curl -s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{\"text\":\"$MSG\"}" \
    >/dev/null 2>&1 || true
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if [[ $SYNC_EXIT -eq 0 ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    ok "Dry run complete — no files transferred"
  else
    ok "Offsite sync complete → $REMOTE"
    ok "Log: $LOG_FILE"
  fi
else
  fail "rclone exited with code $SYNC_EXIT — check $LOG_FILE for details"
fi
