#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_ENV_LIB="$ROOT_DIR/scripts-linux/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"
TUNNEL_DIR="$ROOT_DIR/compose/tt-tunnel"
TUNNEL_ENV="$(tt_resolve_tunnel_env_path "$ROOT_DIR")"

if [[ ! -f "$TUNNEL_ENV" ]]; then
  echo "ERROR: Tunnel .env not found: $TUNNEL_ENV"
  echo "Create runtime tunnel env from env/tunnel.env.example and set CF_TUNNEL_TOKEN."
  exit 1
fi

get_env() {
  local key="$1"
  grep -E "^${key}=" "$TUNNEL_ENV" | head -n1 | cut -d'=' -f2-
}

TOKEN="$(get_env CF_TUNNEL_TOKEN)"
if [[ -z "$TOKEN" || "$TOKEN" == __* ]]; then
  echo "ERROR: CF_TUNNEL_TOKEN is not set in: $TUNNEL_ENV"
  exit 1
fi

(
  cd "$TUNNEL_DIR"
  docker compose --env-file "$TUNNEL_ENV" up -d
)

echo "OK: Tunnel started (token mode)."
echo "Review desired public routes with: scripts/Show-TunnelPlan.ps1"
