#!/usr/bin/env bash
# =============================================================================
# cleanup-backups.sh — TT-Production v14.0
# Removes backup archives older than a configurable retention period.
# Safe by default: --dry-run shows what would be deleted without deleting.
#
# Usage:
#   bash scripts-linux/cleanup-backups.sh
#   bash scripts-linux/cleanup-backups.sh --dry-run
#   bash scripts-linux/cleanup-backups.sh --keep-days 30
#   bash scripts-linux/cleanup-backups.sh --root /opt/stacks/tt-core --keep-days 14
#
# Exit:  0 = success (or dry-run)
#        1 = error
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
DRY_RUN=false
KEEP_DAYS=30

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BOLD='\033[1m'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)      ROOT="$2";       shift 2 ;;
    --keep-days) KEEP_DAYS="$2";  shift 2 ;;
    --dry-run)   DRY_RUN=true;    shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# Try to read retain_days from services.select.json if not overridden
SELECT_FILE="$ROOT/config/services.select.json"
if [[ -f "$SELECT_FILE" ]] && command -v python3 &>/dev/null; then
  CONFIGURED_DAYS=$(python3 -c "
import json
try:
  d = json.load(open('$SELECT_FILE'))
  print(d.get('backup', {}).get('retain_days', ''))
except:
  print('')
" 2>/dev/null || true)
  if [[ -n "$CONFIGURED_DAYS" && "$CONFIGURED_DAYS" =~ ^[0-9]+$ ]]; then
    KEEP_DAYS="$CONFIGURED_DAYS"
  fi
fi

BACKUP_DIR="$ROOT/backups"

echo ""
echo -e "${BOLD}TT-Production v14.0 — Backup Cleanup${NC}"
echo -e "${CYAN}Backup directory: $BACKUP_DIR${NC}"
echo -e "${CYAN}Retention: ${KEEP_DAYS} days${NC}"
if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}DRY RUN — no files will be deleted${NC}"
fi
echo ""

if [[ ! -d "$BACKUP_DIR" ]]; then
  echo -e "${YELLOW}No backups directory found: $BACKUP_DIR${NC}"
  echo "Nothing to clean up."
  exit 0
fi

# Find backup directories and tarballs older than KEEP_DAYS
DELETED=0
KEPT=0
FREED_KB=0

while IFS= read -r -d '' item; do
  item_name=$(basename "$item")
  item_size_kb=$(du -sk "$item" 2>/dev/null | cut -f1 || echo 0)

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY-RUN DELETE]${NC} $item_name  (${item_size_kb}KB)"
    ((DELETED++)) || true
    ((FREED_KB += item_size_kb)) || true
  else
    echo -e "  ${RED}[DELETE]${NC} $item_name  (${item_size_kb}KB)"
    rm -rf "$item"
    ((DELETED++)) || true
    ((FREED_KB += item_size_kb)) || true
  fi
done < <(find "$BACKUP_DIR" -maxdepth 1 \
  \( -name "backup_*" -o -name "support-bundle-*" \) \
  -mtime "+${KEEP_DAYS}" -print0 2>/dev/null)

# Count remaining backups
REMAINING=$(find "$BACKUP_DIR" -maxdepth 1 -name "backup_*" 2>/dev/null | wc -l)

echo ""
echo "────────────────────────────────────────────────────"
if [[ $DELETED -eq 0 ]]; then
  echo -e "${GREEN}✓ No backups older than ${KEEP_DAYS} days found — nothing to clean.${NC}"
else
  FREED_MB=$(( FREED_KB / 1024 ))
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}Would delete: ${DELETED} item(s), ~${FREED_MB}MB freed${NC}"
    echo "  Run without --dry-run to apply."
  else
    echo -e "${GREEN}✓ Deleted: ${DELETED} item(s), ~${FREED_MB}MB freed${NC}"
  fi
fi
echo -e "  Remaining backups: ${REMAINING}"
echo ""
exit 0
