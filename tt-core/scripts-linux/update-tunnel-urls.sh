#!/usr/bin/env bash
# update-tunnel-urls.sh — TT-Core "v14.0" (Linux/VPS)
# Syncs service URLs in runtime core env from canonical intent in
# config/services.select.json.
#
# SOURCE OF TRUTH MODEL:
#   Route intent  → config/services.select.json  (canonical)
#   Tunnel token  → runtime tunnel env              (runtime secret only)
#   Service URLs  → runtime core env                (written by this script)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
RUNTIME_ENV_LIB="$SCRIPT_DIR/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2 ;; *) shift ;; esac; done

CORE_ENV="$(tt_resolve_core_env_path "$ROOT")"
TUNNEL_ENV="$(tt_resolve_tunnel_env_path "$ROOT")"
SELECT="$ROOT/config/services.select.json"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

[[ -f "$CORE_ENV" ]]  || { echo -e "${RED}ERROR: core runtime env not found — run init.sh first${NC}"; exit 1; }
[[ -f "$SELECT" ]]    || { echo -e "${RED}ERROR: services.select.json not found at $SELECT${NC}"; exit 1; }

upsert_env() {
  local key="$1" val="$2" file="$3"
  if grep -qE "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$file"
  else
    echo "${key}=${val}" >> "$file"
  fi
}

get_env() {
  local key="$1" file="$2" default="${3:-}"
  local v; v=$(grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' || echo "")
  echo "${v:-$default}"
}

# Read from services.select.json (canonical intent source)
TUNNEL_ENABLED=$(python3 -c "import json; d=json.load(open('$SELECT')); print('true' if d['tunnel']['enabled'] else 'false')")
DOMAIN=$(python3 -c "import json; d=json.load(open('$SELECT')); print(d['client']['domain'])")
N8N_ROUTE=$(python3 -c "import json; d=json.load(open('$SELECT')); print('true' if d['tunnel']['routes'].get('n8n',False) else 'false')")
N8N_SUB=$(python3 -c "import json; d=json.load(open('$SELECT')); print(d['tunnel']['subdomains'].get('n8n','n8n'))")
WP_ROUTE=$(python3 -c "import json; d=json.load(open('$SELECT')); print('true' if d['tunnel']['routes'].get('wordpress',False) else 'false')")
WP_SUB=$(python3 -c "import json; d=json.load(open('$SELECT')); print(d['tunnel']['subdomains'].get('wordpress','wp'))")
ALLOW_RESTRICTED=$(python3 -c "import json; d=json.load(open('$SELECT')); print('true' if d['security']['allow_restricted_admin_tunnel_routes'] else 'false')")

# Domain fallback: read from tunnel .env
if [[ "$DOMAIN" == __* ]] || [[ -z "$DOMAIN" ]]; then
  [[ -f "$TUNNEL_ENV" ]] && DOMAIN=$(get_env "TT_DOMAIN" "$TUNNEL_ENV" "")
  if [[ -z "$DOMAIN" || "$DOMAIN" == __* ]]; then
    echo -e "${RED}ERROR: client.domain not set in services.select.json and TT_DOMAIN not in tunnel .env${NC}"
    exit 1
  fi
  echo -e "${YELLOW}  INFO: domain read from tunnel .env — set client.domain in services.select.json to make permanent${NC}"
fi

LOCAL_PORT=$(get_env "TT_N8N_HOST_PORT" "$CORE_ENV" "15678")
BIND_IP=$(get_env "TT_BIND_IP" "$CORE_ENV" "127.0.0.1")
WP_PORT=$(get_env "TT_WP_HOST_PORT" "$CORE_ENV" "18081")
LOCAL_IP="$([[ "$BIND_IP" == "0.0.0.0" ]] && echo "127.0.0.1" || echo "$BIND_IP")"

echo -e "${CYAN}Update-TunnelURLs — v9.4${NC}"
echo "  Source: config/services.select.json (canonical)"
echo "  Domain: $DOMAIN"
echo "  Tunnel: $TUNNEL_ENABLED"
echo ""

# n8n URL
if [[ "$TUNNEL_ENABLED" == "true" && "$N8N_ROUTE" == "true" ]]; then
  upsert_env "TT_N8N_HOST"             "$N8N_SUB.$DOMAIN" "$CORE_ENV"
  upsert_env "TT_N8N_PROTOCOL"        "https"             "$CORE_ENV"
  upsert_env "TT_N8N_WEBHOOK_URL"     "https://$N8N_SUB.$DOMAIN/" "$CORE_ENV"
  upsert_env "TT_N8N_EDITOR_BASE_URL" "https://$N8N_SUB.$DOMAIN"  "$CORE_ENV"
  echo -e "  ${GREEN}OK: n8n → TUNNEL: https://$N8N_SUB.$DOMAIN${NC}"
else
  upsert_env "TT_N8N_HOST"             "localhost"                     "$CORE_ENV"
  upsert_env "TT_N8N_PROTOCOL"        "http"                           "$CORE_ENV"
  upsert_env "TT_N8N_WEBHOOK_URL"     "http://$LOCAL_IP:$LOCAL_PORT/"  "$CORE_ENV"
  upsert_env "TT_N8N_EDITOR_BASE_URL" "http://$LOCAL_IP:$LOCAL_PORT"   "$CORE_ENV"
  echo "  OK: n8n → LOCAL: http://$LOCAL_IP:$LOCAL_PORT"
fi

# WordPress URL
if [[ "$TUNNEL_ENABLED" == "true" && "$WP_ROUTE" == "true" ]]; then
  upsert_env "TT_WP_PUBLIC_URL" "https://$WP_SUB.$DOMAIN" "$CORE_ENV"
  echo -e "  ${GREEN}OK: WordPress → TUNNEL: https://$WP_SUB.$DOMAIN${NC}"
else
  upsert_env "TT_WP_PUBLIC_URL" "http://$LOCAL_IP:$WP_PORT" "$CORE_ENV"
  echo "  OK: WordPress → LOCAL: http://$LOCAL_IP:$WP_PORT"
fi

echo ""
echo -e "${YELLOW}  Restart services to apply: bash scripts-linux/start-core.sh${NC}"
echo "  Regen exposure report:   bash release/generate-exposure.sh"
