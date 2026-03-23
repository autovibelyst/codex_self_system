#!/usr/bin/env bash
# =============================================================================
# health-dashboard.sh — TT-Core Live Health Dashboard (v14.0)
#
# Displays real-time health status of all TT-Core services, resource usage,
# last backup timestamp, and connectivity checks in a single terminal view.
#
# Usage:
#   bash scripts-linux/health-dashboard.sh
#   bash scripts-linux/health-dashboard.sh --watch      # refresh every 10s
#   bash scripts-linux/health-dashboard.sh --json       # machine-readable output
#   bash scripts-linux/health-dashboard.sh --root /path/to/tt-core
#
# Exit codes:
#   0 = all services healthy
#   1 = one or more services unhealthy or not running
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
WATCH=false
JSON_OUTPUT=false
REFRESH_INTERVAL=10

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch)         WATCH=true; shift ;;
    --json)          JSON_OUTPUT=true; shift ;;
    --root)          ROOT="$2"; shift 2 ;;
    --interval)      REFRESH_INTERVAL="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[0;33m"
CYAN="\033[0;36m"; BOLD="\033[1m"; NC="\033[0m"

# ── Helpers ───────────────────────────────────────────────────────────────────
container_status() {
  docker inspect --format='{{.State.Health.Status}}' "$1" 2>/dev/null || echo "absent"
}

container_state() {
  docker inspect --format='{{.State.Status}}' "$1" 2>/dev/null || echo "absent"
}

container_mem() {
  docker stats --no-stream --format "{{.MemUsage}}" "$1" 2>/dev/null || echo "n/a"
}

container_cpu() {
  docker stats --no-stream --format "{{.CPUPerc}}" "$1" 2>/dev/null || echo "n/a"
}

status_icon() {
  local health="$1" state="$2"
  if [[ "$state" == "absent" ]]; then echo "⊘"; return; fi
  if [[ "$state" != "running" ]]; then echo "✗"; return; fi
  case "$health" in
    healthy)   echo "✓" ;;
    unhealthy) echo "✗" ;;
    starting)  echo "↻" ;;
    *)         echo "~" ;;  # no healthcheck defined
  esac
}

status_color() {
  local health="$1" state="$2"
  if [[ "$state" == "absent" || "$state" != "running" ]]; then echo "$RED"; return; fi
  case "$health" in
    healthy)   echo "$GREEN" ;;
    unhealthy) echo "$RED" ;;
    starting)  echo "$YELLOW" ;;
    *)         echo "$CYAN" ;;
  esac
}

# ── Last backup info ──────────────────────────────────────────────────────────
last_backup_info() {
  local backup_dir
  backup_dir="$(docker inspect --format='{{range .Mounts}}{{if eq .Destination "/backups"}}{{.Source}}{{end}}{{end}}' tt-core-postgres 2>/dev/null || echo "")"
  if [[ -z "$backup_dir" ]]; then
    backup_dir="$ROOT/backups"
  fi
  if [[ -d "$backup_dir" ]]; then
    local last
    last=$(find "$backup_dir" -name "*.dump" -o -name "*.dump.enc" 2>/dev/null \
      | sort | tail -1)
    if [[ -n "$last" ]]; then
      echo "$(basename "$(dirname "$last")") — $(stat -c '%y' "$last" 2>/dev/null | cut -d. -f1)"
    else
      echo "No backups found"
    fi
  else
    echo "Backup directory not found"
  fi
}

# ── Render dashboard ──────────────────────────────────────────────────────────
render_dashboard() {
  local TIMESTAMP
  TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

  # Core services to monitor
  declare -A SERVICES=(
    ["tt-core-postgres"]="PostgreSQL"
    ["tt-core-redis"]="Redis"
    ["tt-core-n8n"]="n8n"
    ["tt-core-n8n-worker"]="n8n-worker"
    ["tt-core-pgadmin"]="pgAdmin"
    ["tt-core-redisinsight"]="RedisInsight"
  )

  # Optional services — ordered array for consistent display
  declare -a OPT_SERVICE_NAMES=("tt-core-metabase" "tt-core-qdrant" "tt-core-ollama" "tt-core-openwebui" "tt-core-uptime-kuma" "tt-core-portainer")
  declare -A OPT_SERVICE_LABELS=(
    ["tt-core-metabase"]="Metabase"
    ["tt-core-qdrant"]="Qdrant"
    ["tt-core-ollama"]="Ollama"
    ["tt-core-openwebui"]="Open WebUI"
    ["tt-core-uptime-kuma"]="Uptime Kuma"
    ["tt-core-portainer"]="Portainer"
  )

  if [[ "$JSON_OUTPUT" == "true" ]]; then
    local json_parts=()
    local all_healthy=true
    for cname in "${!SERVICES[@]}"; do
      local health state
      health="$(container_status "$cname")"
      state="$(container_state "$cname")"
      json_parts+=("{\"container\":\"$cname\",\"name\":\"${SERVICES[$cname]}\",\"state\":\"$state\",\"health\":\"$health\"}")
      [[ "$health" != "healthy" && "$state" == "running" ]] && all_healthy=false
      [[ "$state" != "running" && "$state" != "exited" ]] && all_healthy=false
    done
    echo "{\"timestamp\":\"$TIMESTAMP\",\"all_healthy\":$all_healthy,\"services\":[$(IFS=,; echo "${json_parts[*]}")]}"
    $all_healthy && return 0 || return 1
  fi

  # Terminal output
  echo ""
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║      TT-Production v14.0 — Health Dashboard                  ║${NC}"
  echo -e "${BOLD}${CYAN}║      $TIMESTAMP                              ║${NC}"
  echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
  echo ""

  echo -e "  ${BOLD}Core Services${NC}"
  echo -e "  $(printf '─%.0s' {1..58})"
  printf "  %-22s %-10s %-12s %-14s %-12s\n" "SERVICE" "STATUS" "HEALTH" "CPU" "MEMORY"
  echo -e "  $(printf '─%.0s' {1..58})"

  local exit_code=0
  for cname in tt-core-postgres tt-core-redis tt-core-n8n tt-core-n8n-worker tt-core-pgadmin tt-core-redisinsight; do
    local display_name="${SERVICES[$cname]}"
    local health state icon color mem cpu
    health="$(container_status "$cname")"
    state="$(container_state "$cname")"
    icon="$(status_icon "$health" "$state")"
    color="$(status_color "$health" "$state")"
    cpu="$(container_cpu "$cname")"
    mem="$(container_mem "$cname")"
    printf "  ${color}%-22s${NC} ${color}${BOLD}%-2s %-7s${NC} %-12s %-14s %-12s\n" \
      "$display_name" "$icon" "$state" "$health" "$cpu" "$mem"
    [[ "$health" != "healthy" && "$state" == "running" ]] && exit_code=1
    [[ "$state" == "absent" ]] && exit_code=1
  done

  echo ""
  echo -e "  ${BOLD}Optional Services${NC}"
  echo -e "  $(printf '─%.0s' {1..58})"
  for cname in "${OPT_SERVICE_NAMES[@]}"; do
    local display_name="${OPT_SERVICE_LABELS[$cname]}"
    local health state icon color
    health="$(container_status "$cname")"
    state="$(container_state "$cname")"
    if [[ "$state" == "absent" ]]; then
      printf "  %-22s  %-8s\n" "$display_name" "(not deployed)"
    else
      icon="$(status_icon "$health" "$state")"
      color="$(status_color "$health" "$state")"
      printf "  ${color}%-22s  %-2s %-7s %-12s${NC}\n" "$display_name" "$icon" "$state" "$health"
    fi
  done

  echo ""
  echo -e "  ${BOLD}System Info${NC}"
  echo -e "  $(printf '─%.0s' {1..58})"
  printf "  %-22s %s\n" "Last Backup:" "$(last_backup_info)"
  printf "  %-22s %s\n" "Docker Networks:" "$(docker network ls --format '{{.Name}}' 2>/dev/null | grep "^tt_" | tr '\n' ' ' || echo 'n/a')"
  printf "  %-22s %s\n" "Disk (/):" "$(df -h / 2>/dev/null | awk 'NR==2{print $3"/"$2" ("$5" used)"}' || echo 'n/a')"

  echo ""
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  return $exit_code
}

# ── Main ──────────────────────────────────────────────────────────────────────
if [[ "$WATCH" == "true" ]]; then
  while true; do
    clear
    render_dashboard
    echo "  Refreshing every ${REFRESH_INTERVAL}s — Ctrl+C to exit"
    sleep "$REFRESH_INTERVAL"
  done
else
  render_dashboard
fi
