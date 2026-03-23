#!/usr/bin/env bash
# monitor.sh — TT-Core real-time health monitor (introduced v9.4+)
# Usage: bash scripts-linux/monitor.sh [--interval 30] [--once]
# Continuously checks container health, disk/memory, and alerts via webhook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
RUNTIME_ENV_LIB="$SCRIPT_DIR/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"
INTERVAL=30
ONCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval) INTERVAL="$2"; shift 2 ;;
    --once)     ONCE=true; shift ;;
    --root)     ROOT="$2"; shift 2 ;;
    *)          shift ;;
  esac
done

ENV_FILE="$(tt_resolve_core_env_path "$ROOT")"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BOLD='\033[1m'

get_env() {
  local key="$1" default="${2:-}"
  if [[ -f "$ENV_FILE" ]]; then
    local line
    line=$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 || true)
    [[ -n "$line" ]] && { echo "${line#*=}" | tr -d '\r'; return; }
  fi
  echo "$default"
}

notify_alert() {
  local msg="$1"
  local WEBHOOK_URL
  # v9.4: use dedicated TT_MONITOR_NOTIFY_WEBHOOK_URL if set,
  # fall back to TT_BACKUP_NOTIFY_WEBHOOK_URL for single-webhook setups
  WEBHOOK_URL=$(get_env TT_MONITOR_NOTIFY_WEBHOOK_URL "")
  if [[ -z "$WEBHOOK_URL" ]]; then
    WEBHOOK_URL=$(get_env TT_BACKUP_NOTIFY_WEBHOOK_URL "")
  fi
  if [[ -n "$WEBHOOK_URL" ]]; then
    curl -s -X POST "$WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"text\":\"🚨 TT-Core ALERT on $(hostname -s 2>/dev/null || echo host): ${msg}\"}" \
      >/dev/null 2>&1 || true
  fi
}

CORE_CONTAINERS=(
  "tt-core-postgres"
  "tt-core-redis"
  "tt-core-n8n"
  "tt-core-n8n-worker"
)

ADVISORY_CONTAINERS=(
  "tt-core-pgadmin"
  "tt-core-redisinsight"
)

print_header() {
  clear 2>/dev/null || echo "---"
  echo -e "${CYAN}${BOLD}TT-Core Monitor — $(date '+%Y-%m-%d %H:%M:%S')${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
  echo "  Interval: ${INTERVAL}s | Press Ctrl+C to stop"
  echo ""
}

check_containers() {
  local issues=0
  echo -e "${BOLD}Container Health:${NC}"

  for ctr in "${CORE_CONTAINERS[@]}"; do
    local state status
    state=$(docker inspect --format='{{.State.Status}}' "$ctr" 2>/dev/null || echo "not_found")
    status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-hc{{end}}' "$ctr" 2>/dev/null || echo "error")

    if [[ "$state" == "running" ]]; then
      if [[ "$status" == "healthy" || "$status" == "no-hc" ]]; then
        echo -e "  ${GREEN}✓${NC} ${ctr}: running (${status})"
      else
        echo -e "  ${RED}✗${NC} ${ctr}: running but ${RED}${status}${NC}"
        notify_alert "${ctr} is ${status}"
        ((issues++)) || true
      fi
    else
      echo -e "  ${RED}✗${NC} ${ctr}: ${RED}${state}${NC}"
      notify_alert "${ctr} is ${state} — expected running"
      ((issues++)) || true
    fi
  done

  for ctr in "${ADVISORY_CONTAINERS[@]}"; do
    local state
    state=$(docker inspect --format='{{.State.Status}}' "$ctr" 2>/dev/null || echo "not_found")
    if [[ "$state" == "running" ]]; then
      echo -e "  ${GREEN}✓${NC} ${ctr}: running"
    else
      echo -e "  ${YELLOW}⚠${NC} ${ctr}: ${state} (advisory only)"
    fi
  done

  return $issues
}

check_disk() {
  echo ""
  echo -e "${BOLD}Disk Usage:${NC}"
  local threshold=85
  while IFS= read -r line; do
    local pct mount
    pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $6}')
    if [[ "$pct" -ge "$threshold" ]]; then
      echo -e "  ${RED}✗${NC} ${mount}: ${RED}${pct}% used${NC} (>= ${threshold}% threshold)"
      notify_alert "Disk ${mount} at ${pct}% — approaching full"
    elif [[ "$pct" -ge 70 ]]; then
      echo -e "  ${YELLOW}⚠${NC} ${mount}: ${YELLOW}${pct}% used${NC}"
    else
      echo -e "  ${GREEN}✓${NC} ${mount}: ${pct}% used"
    fi
  done < <(df -h / /var 2>/dev/null | tail -n +2 | sort -u)
}

check_memory() {
  echo ""
  echo -e "${BOLD}Memory:${NC}"
  local total avail pct
  total=$(free -m | awk '/^Mem:/{print $2}')
  avail=$(free -m | awk '/^Mem:/{print $7}')
  if [[ -n "$total" && "$total" -gt 0 ]]; then
    pct=$(( (total - avail) * 100 / total ))
    if [[ "$pct" -ge 90 ]]; then
      echo -e "  ${RED}✗${NC} Memory: ${RED}${pct}% used${NC} — only ${avail}MB available"
      notify_alert "High memory usage: ${pct}% — only ${avail}MB free"
    elif [[ "$pct" -ge 75 ]]; then
      echo -e "  ${YELLOW}⚠${NC} Memory: ${YELLOW}${pct}% used${NC} — ${avail}MB available"
    else
      echo -e "  ${GREEN}✓${NC} Memory: ${pct}% used — ${avail}MB available"
    fi
  fi
}

check_backups() {
  echo ""
  echo -e "${BOLD}Last Backup:${NC}"
  local backup_dir="$ROOT/backups"
  if [[ -d "$backup_dir" ]]; then
    local latest
    latest=$(find "$backup_dir" -maxdepth 1 -type d -name "backup_*" | sort | tail -1)
    if [[ -n "$latest" ]]; then
      local age_h
      age_h=$(( ( $(date +%s) - $(stat -c %Y "$latest" 2>/dev/null || echo 0) ) / 3600 ))
      local bname; bname=$(basename "$latest")
      if [[ "$age_h" -gt 48 ]]; then
        echo -e "  ${RED}✗${NC} ${bname} — ${RED}${age_h}h ago${NC} (>48h — backup overdue!)"
        notify_alert "Last backup is ${age_h}h old — backup may be failing"
      elif [[ "$age_h" -gt 25 ]]; then
        echo -e "  ${YELLOW}⚠${NC} ${bname} — ${YELLOW}${age_h}h ago${NC}"
      else
        echo -e "  ${GREEN}✓${NC} ${bname} — ${age_h}h ago"
      fi
    else
      echo -e "  ${YELLOW}⚠${NC} No backups found in $backup_dir"
    fi
  else
    echo -e "  ${YELLOW}⚠${NC} Backup directory not found"
  fi
}

run_check() {
  print_header
  local ctr_issues=0
  check_containers || ctr_issues=$?
  check_disk
  check_memory
  check_backups
  echo ""
  echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
  if [[ "$ctr_issues" -gt 0 ]]; then
    echo -e "${RED}  ISSUES DETECTED: ${ctr_issues} — check above${NC}"
  else
    echo -e "${GREEN}  All core services healthy${NC}"
  fi
  echo ""
}

if $ONCE; then
  run_check
  exit 0
fi

echo -e "${CYAN}Starting TT-Core monitor (interval: ${INTERVAL}s) — Ctrl+C to stop${NC}"
while true; do
  run_check
  sleep "$INTERVAL"
done
