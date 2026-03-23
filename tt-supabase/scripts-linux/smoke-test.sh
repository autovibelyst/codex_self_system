#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2 ;; *) shift ;; esac; done
ENV_FILE="$ROOT/compose/tt-supabase/.env"
KONG_PORT=$(grep "^KONG_HTTP_PORT=" "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d '\r' || echo "18000")
echo ""
echo "── TT-Supabase Smoke Test ──────────────────────────────────"
echo ""
if curl -sf "http://127.0.0.1:${KONG_PORT}/rest/v1/" > /dev/null 2>&1; then
  echo -e "\033[32m[OK]\033[0m  Kong gateway reachable on port ${KONG_PORT}"
else
  echo -e "\033[31m[FAIL]\033[0m Kong gateway NOT reachable on port ${KONG_PORT}"
  echo "      Run status.sh to check container health"
  exit 1
fi
echo ""
echo "Supabase smoke test passed."
