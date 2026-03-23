#!/usr/bin/env bash
# =============================================================================
# ttcore.sh — TT-Core Unified CLI — v14.0 (Linux/macOS)
# Linux/macOS equivalent of ttcore.ps1 (Windows PowerShell)
#
# Usage:
#   bash scripts-linux/ttcore.sh <command> [args...]
#
# Commands:
#   up core                   — Start the core stack
#   up profile <name>         — Start core + a named profile addon
#   down core                 — Stop and remove core containers
#   status                    — Show status of all TT containers
#   logs <service>            — Follow logs for a service
#   diag                      — Run diagnostics (preflight + docker info)
#   smoke                     — Run smoke test
#   restart <service>         — Restart a specific service
#   backup                    — Run backup
#   help                      — Show this help
#
# Exit codes:
#   0 = success
#   1 = error
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_DIR="$CORE_DIR/compose/tt-core"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
RUNTIME_ENV_LIB="$SCRIPT_DIR/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"
ENV_FILE="$(tt_resolve_core_env_path "$CORE_DIR")"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

hdr()  { echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════════════════${NC}\n"; }
ok()   { echo -e "  ${GREEN}[OK]${NC}  $*"; }
err()  { echo -e "  ${RED}[ERR]${NC} $*" >&2; }
info() { echo -e "  $*"; }

check_compose() {
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    err "docker-compose.yml not found at $COMPOSE_FILE"
    err "Run init.sh first."
    exit 1
  fi
  if [[ ! -f "$ENV_FILE" ]]; then
    err "core runtime env not found at $ENV_FILE"
    err "Run init.sh first."
    exit 1
  fi
}

cmd_up_core() {
  hdr "TT-Core — Start Core Stack"
  check_compose
  info "Running preflight check..."
  bash "$SCRIPT_DIR/preflight-check.sh" || { err "Preflight failed — fix issues before starting."; exit 1; }
  info "Starting core stack..."
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
  ok "Core stack started."
}

cmd_up_profile() {
  local profile="${1:-}"
  if [[ -z "$profile" ]]; then
    err "Usage: ttcore.sh up profile <name>"
    err "Available profiles: metabase, qdrant, ollama, openwebui, portainer"
    exit 1
  fi
  hdr "TT-Core — Start Profile: $profile"
  check_compose
  info "Starting core + profile $profile..."
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" --profile "$profile" up -d
  ok "Profile $profile started."
}

cmd_down() {
  hdr "TT-Core — Stop Core Stack"
  check_compose
  info "Stopping core stack..."
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down
  ok "Core stack stopped."
}

cmd_status() {
  hdr "TT-Core — Container Status"
  echo -e "  ${BOLD}Container${NC}                            ${BOLD}Status${NC}          ${BOLD}Health${NC}"
  echo "  ─────────────────────────────────────────────────────────"
  docker ps -a --filter "name=tt-" \
    --format "  {{.Names}}  \t{{.Status}}\t{{if .LocalVolumes}}{{end}}" 2>/dev/null || \
    docker ps -a --filter "name=tt-"
}

cmd_logs() {
  local service="${1:-n8n}"
  hdr "TT-Core — Logs: $service"
  check_compose
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs -f --tail=100 "$service"
}

cmd_diag() {
  hdr "TT-Core — Diagnostics"
  info "Docker version:"
  docker version --format '  Client: {{.Client.Version}} / Server: {{.Server.Version}}' 2>/dev/null || docker version
  echo ""
  info "Compose version:"
  docker compose version 2>/dev/null || echo "  not available"
  echo ""
  info "Running preflight check..."
  bash "$SCRIPT_DIR/preflight-check.sh"
}

cmd_smoke() {
  hdr "TT-Core — Smoke Test"
  bash "$SCRIPT_DIR/smoke-test.sh"
}

cmd_restart() {
  local service="${1:-}"
  if [[ -z "$service" ]]; then
    err "Usage: ttcore.sh restart <service>"
    exit 1
  fi
  hdr "TT-Core — Restart: $service"
  check_compose
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" restart "$service"
  ok "$service restarted."
}

cmd_backup() {
  hdr "TT-Core — Backup"
  bash "$SCRIPT_DIR/backup.sh"
}

cmd_help() {
  echo ""
  echo -e "${CYAN}  TT-Core Unified CLI — v14.0 (Linux/macOS)${NC}"
  echo ""
  echo "  Usage: bash scripts-linux/ttcore.sh <command> [args]"
  echo ""
  echo "  Commands:"
  echo "    up core                   Start the core stack"
  echo "    up profile <name>         Start core + named addon profile"
  echo "    down core                 Stop core stack"
  echo "    status                    Show all TT container status"
  echo "    logs <service>            Tail logs (default: n8n)"
  echo "    diag                      Run diagnostics"
  echo "    smoke                     Run smoke test"
  echo "    restart <service>         Restart a service"
  echo "    backup                    Run backup"
  echo "    help                      Show this help"
  echo ""
  echo "  Available profiles: metabase, qdrant, ollama, openwebui, portainer"
  echo ""
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
  up)
    SUBCOMMAND="${1:-}"
    shift || true
    case "$SUBCOMMAND" in
      core)    cmd_up_core ;;
      profile) cmd_up_profile "${1:-}" ;;
      *)       err "Unknown subcommand: up $SUBCOMMAND"; cmd_help; exit 1 ;;
    esac
    ;;
  down)        cmd_down ;;
  status)      cmd_status ;;
  logs)        cmd_logs "${1:-n8n}" ;;
  diag)        cmd_diag ;;
  smoke)       cmd_smoke ;;
  restart)     cmd_restart "${1:-}" ;;
  backup)      cmd_backup ;;
  help|--help) cmd_help ;;
  *)
    err "Unknown command: $COMMAND"
    cmd_help
    exit 1
    ;;
esac
