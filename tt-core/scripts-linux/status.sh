#!/usr/bin/env bash
# status.sh — TT-Production v14.0 — Container status and health check
# Usage: bash scripts-linux/status.sh [--json] [--root /path/to/tt-core]
#
# --json: Output machine-readable JSON (for Uptime Kuma, Datadog, monitoring tools)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
JSON_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_MODE=true; shift ;;
    --root) ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BOLD='\033[1m'

if [[ "$JSON_MODE" == "true" ]]; then
  # Machine-readable output for monitoring integrations
  TIMESTAMP=$(date -Iseconds)
  CONTAINERS=()
  ALL_HEALTHY=true

  while IFS= read -r line; do
    NAME=$(echo "$line" | cut -f1)
    STATUS=$(echo "$line" | cut -f2)
    HEALTH=$(echo "$line" | cut -f3)

    if [[ "$HEALTH" == "unhealthy" ]] || [[ "$STATUS" != *"Up"* ]]; then
      ALL_HEALTHY=false
    fi

    CONTAINERS+=("{\"name\":\"${NAME}\",\"status\":\"${STATUS}\",\"health\":\"${HEALTH}\"}")
  done < <(docker ps --filter "name=tt-core" --format "{{.Names}}\t{{.Status}}\t{{.Health}}" 2>/dev/null)

  CONTAINERS_JSON=$(IFS=,; echo "[${CONTAINERS[*]}]")
  VERDICT=$([[ "$ALL_HEALTHY" == "true" ]] && echo "healthy" || echo "degraded")

  printf '{"product":"TT-Production","version":"v14.0","timestamp":"%s","verdict":"%s","containers":%s}\n' \
    "$TIMESTAMP" "$VERDICT" "${CONTAINERS_JSON:-[]}"
  exit 0
fi

# ── Human-readable output ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}TT-Production v14.0 — Container Status${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""

docker ps --filter "name=tt-core" \
  --format "table {{.Names}}\t{{.Status}}\t{{.Health}}\t{{.Image}}" \
  2>/dev/null || echo "Docker not available"

echo ""
echo -e "${CYAN}── Resource Usage ─────────────────────────────────${NC}"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" \
  $(docker ps --filter "name=tt-core" -q 2>/dev/null) 2>/dev/null || true

echo ""
