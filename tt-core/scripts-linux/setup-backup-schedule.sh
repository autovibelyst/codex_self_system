#!/usr/bin/env bash
# =============================================================================
# setup-backup-schedule.sh — Configure automated backup schedule
# TT-Production v14.0
#
# Reads auto_schedule configuration from services.select.json.
#           Previously, auto_schedule=true was dead config — nothing acted on it.
#           This script reads services.select.json and installs a real cron job.
#
# Usage:
#   bash scripts-linux/setup-backup-schedule.sh
#   bash scripts-linux/setup-backup-schedule.sh --dry-run
#   bash scripts-linux/setup-backup-schedule.sh --remove
#   bash scripts-linux/setup-backup-schedule.sh --root /opt/stacks/tt-core
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
DRY_RUN=false
REMOVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --remove)  REMOVE=true; shift ;;
    --root)    ROOT="$2"; shift 2 ;;
    *)         echo "Unknown argument: $1"; exit 1 ;;
  esac
done

SELECT_FILE="$ROOT/config/services.select.json"
BACKUP_SCRIPT="$ROOT/scripts-linux/backup.sh"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

# ── Remove existing TT-Core cron entry ───────────────────────────────────────
remove_cron() {
  local marker="# TT-Core backup"
  if crontab -l 2>/dev/null | grep -q "$marker"; then
    crontab -l 2>/dev/null | grep -v "$marker" | grep -v "backup.sh" | crontab -
    echo -e "${GREEN}✓ TT-Core backup cron entry removed.${NC}"
  else
    echo -e "${YELLOW}No TT-Core backup cron entry found.${NC}"
  fi
}

if [[ "$REMOVE" == "true" ]]; then
  remove_cron
  exit 0
fi

# ── Read config from services.select.json ────────────────────────────────────
if [[ ! -f "$SELECT_FILE" ]]; then
  echo -e "${RED}ERROR: services.select.json not found: $SELECT_FILE${NC}"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo -e "${RED}ERROR: python3 required to parse services.select.json${NC}"
  exit 1
fi

AUTO_SCHEDULE=$(python3 -c "
import json, sys
with open('$SELECT_FILE') as f:
    d = json.load(f)
print(str(d.get('backup', {}).get('auto_schedule', False)).lower())
" 2>/dev/null || echo "false")

if [[ "$AUTO_SCHEDULE" != "true" ]]; then
  echo -e "${YELLOW}auto_schedule is not enabled in services.select.json.${NC}"
  echo "  Set backup.auto_schedule=true to enable automated backups."
  exit 0
fi

RETAIN_DAYS=$(python3 -c "
import json
with open('$SELECT_FILE') as f:
    d = json.load(f)
print(d.get('backup', {}).get('retain_days', 7))
" 2>/dev/null || echo "7")

BACKUP_TIME=$(python3 -c "
import json
with open('$SELECT_FILE') as f:
    d = json.load(f)
print(d.get('backup', {}).get('backup_time', '02:00'))
" 2>/dev/null || echo "02:00")

HOUR=$(echo "$BACKUP_TIME" | cut -d: -f1 | sed 's/^0//')
MINUTE=$(echo "$BACKUP_TIME" | cut -d: -f2 | sed 's/^0//')
HOUR=${HOUR:-2}
MINUTE=${MINUTE:-0}

# ── Validate cron fields before installing ────────────────────────────────────
if ! [[ "$HOUR" =~ ^[0-9]+$ ]] || [[ "$HOUR" -gt 23 ]]; then
  echo -e "${RED}[ERROR] Invalid backup hour '$HOUR' — must be 0-23. Check backup.backup_time in services.select.json.${NC}"
  exit 1
fi
if ! [[ "$MINUTE" =~ ^[0-9]+$ ]] || [[ "$MINUTE" -gt 59 ]]; then
  echo -e "${RED}[ERROR] Invalid backup minute '$MINUTE' — must be 0-59. Check backup.backup_time in services.select.json.${NC}"
  exit 1
fi

CRON_LINE="$MINUTE $HOUR * * * $BACKUP_SCRIPT --root $ROOT >> $ROOT/backups/cron.log 2>&1 # TT-Core backup"
CLEANUP_LINE="0 3 * * * find $ROOT/backups -maxdepth 1 -type d -name 'backup_*' -mtime +${RETAIN_DAYS} -exec rm -rf {} + # TT-Core backup retention"

echo ""
echo -e "${CYAN}TT-Core Backup Schedule Setup${NC}"
echo "  Backup time:    $BACKUP_TIME (cron: $MINUTE $HOUR * * *)"
echo "  Retention:      $RETAIN_DAYS days"
echo "  Script:         $BACKUP_SCRIPT"
echo "  Log:            $ROOT/backups/cron.log"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}[DRY RUN] Would add to crontab:${NC}"
  echo "  $CRON_LINE"
  echo "  $CLEANUP_LINE"
  exit 0
fi

# ── Remove old entry and add new ─────────────────────────────────────────────
remove_cron 2>/dev/null || true

mkdir -p "$ROOT/backups"

(crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
(crontab -l 2>/dev/null; echo "$CLEANUP_LINE") | crontab -

echo -e "${GREEN}✓ Backup schedule installed.${NC}"
echo ""
echo "  Verify: crontab -l"
echo "  Remove: bash $SCRIPT_DIR/setup-backup-schedule.sh --remove"
echo ""
