#!/usr/bin/env bash
# =============================================================================
# Install-TTCore.sh — TT-Core Linux/VPS Full Installer (TT-Production v14.0)
# M-1 FIX: Complete Linux installer equivalent of Install-TTCore.ps1
#
# Usage:
#   bash installer/Install-TTCore.sh
#   bash installer/Install-TTCore.sh --root /opt/stacks/tt-core
#   bash installer/Install-TTCore.sh --profile local-private
#   bash installer/Install-TTCore.sh --domain example.com --with-tunnel --with-supabase
#
# Requirements: docker, bash 4+, python3 (for JSON parsing), openssl
# =============================================================================
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(dirname "$SCRIPT_DIR")"
ROOT="${HOME}/stacks/tt-core"
SUPABASE_ROOT="${HOME}/stacks/tt-supabase"
DOMAIN=""
WITH_TUNNEL=false
WITH_SUPABASE=false
NO_START=false
BIND_IP="127.0.0.1"
TZ_DEFAULT=""  # Must be supplied via --tz or services.select.json .client.timezone
PROFILE_NAME=""
WITH_TUNNEL_EXPLICIT=false
WITH_SUPABASE_EXPLICIT=false

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)           ROOT="$2";           shift 2 ;;
    --supabase-root)  SUPABASE_ROOT="$2";  shift 2 ;;
    --domain)         DOMAIN="$2";         shift 2 ;;
    --tz)             TZ_DEFAULT="$2";     shift 2 ;;
    --bind-ip)        BIND_IP="$2";        shift 2 ;;
    --profile)        PROFILE_NAME="$2";   shift 2 ;;
    --with-tunnel)    WITH_TUNNEL=true; WITH_TUNNEL_EXPLICIT=true; shift ;;
    --with-supabase)  WITH_SUPABASE=true; WITH_SUPABASE_EXPLICIT=true; shift ;;
    --no-start)       NO_START=true;       shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -n "$PROFILE_NAME" ]]; then
  case "$PROFILE_NAME" in
    local-private|small-business|ai-workstation|public-productivity) ;;
    *)
      echo "Invalid --profile value: $PROFILE_NAME"
      echo "Allowed profiles: local-private, small-business, ai-workstation, public-productivity"
      exit 1
      ;;
  esac
fi

# ── Validate required inputs ─────────────────────────────────────────────────
# Resolve TZ from --tz arg, then services.select.json, then abort
SELECT_JSON="$PKG_ROOT/config/services.select.json"
if [[ -z "$TZ_DEFAULT" ]] && [[ -f "$SELECT_JSON" ]]; then
  TZ_DEFAULT="$(python3 -c "import sys,json; d=json.load(open('$SELECT_JSON')); tz=d.get('client',{}).get('timezone',''); print(tz if tz and not tz.startswith('__') else '')" 2>/dev/null || true)"
fi
if [[ -z "$TZ_DEFAULT" ]] || [[ "$TZ_DEFAULT" == __*__ ]]; then
  echo ""
  echo "  [FAIL] INSTALL BLOCKED: client timezone is not set."
  echo "         Set config/services.select.json .client.timezone to a real timezone"
  echo "         (e.g. Asia/Riyadh, Europe/London, UTC) or pass --tz <timezone>"
  echo ""
  exit 1
fi

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
RED='\033[0;31m'; GRAY='\033[0;37m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]${NC}   $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
info() { echo -e "  ${GRAY}[INFO]${NC} $*"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; exit 1; }
yn_default() {
  [[ "${1:-false}" == "true" ]] && echo "y" || echo "n"
}
json_get_bool() {
  local path="$1" key="$2" default="${3:-false}"
  python3 - "$path" "$key" "$default" << 'PYEOF' 2>/dev/null || echo "$default"
import json, sys
path, key, default = sys.argv[1], sys.argv[2], sys.argv[3].lower() == "true"
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    cur = data
    for part in key.split("."):
        cur = cur[part]
    print("true" if bool(cur) else "false")
except Exception:
    print("true" if default else "false")
PYEOF
}
json_get_text() {
  local path="$1" key="$2"
  python3 - "$path" "$key" << 'PYEOF' 2>/dev/null || true
import json, sys
path, key = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    cur = data
    for part in key.split("."):
        cur = cur[part]
    text = str(cur).strip()
    if text and not text.startswith("__"):
        print(text)
except Exception:
    pass
PYEOF
}

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   TT-Core Installer  "v14.0" (Linux)             ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo -e "  Target: $ROOT"
if [[ -n "$PROFILE_NAME" ]]; then
  echo -e "  Profile: $PROFILE_NAME"
fi
echo ""

# ── Checks ────────────────────────────────────────────────────────────────────
command -v docker >/dev/null 2>&1 || fail "Docker not found. Install Docker: https://docs.docker.com/engine/install/"
command -v openssl >/dev/null 2>&1 || fail "openssl not found. Install with: apt install openssl"

# ── Copy package files ────────────────────────────────────────────────────────
mkdir -p "$ROOT"
for folder in compose docs templates scripts scripts-linux env release config installer; do
  src="$PKG_ROOT/$folder"
  [[ -d "$src" ]] && cp -r "$src" "$ROOT/"
done
ok "Package copied -> $ROOT"

SELECT_JSON_ROOT="$ROOT/config/services.select.json"
if [[ -n "$PROFILE_NAME" ]]; then
  PROFILE_APPLIER="$ROOT/scripts-linux/apply-profile.sh"
  [[ -f "$PROFILE_APPLIER" ]] || fail "Missing profile applicator: $PROFILE_APPLIER"
  bash "$PROFILE_APPLIER" --root "$ROOT" "$PROFILE_NAME" >/dev/null
  ok "Applied deployment profile preset -> $PROFILE_NAME"
fi

# ── Set executable permissions on scripts ──────────────────────
# Ensures scripts-linux/*.sh are always executable regardless of umask or zip
# extraction method used by the operator.
chmod +x "$ROOT/scripts-linux/"*.sh 2>/dev/null || true
ok "Script permissions set (+x on scripts-linux/*.sh)"
RUNTIME_ENV_LIB="$ROOT/scripts-linux/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"

# ── Initialize (secrets + volumes) ───────────────────────────────────────────
bash "$ROOT/scripts-linux/init.sh" --root "$ROOT"

# ── Apply client settings ─────────────────────────────────────────────────────
ENV_FILE="$(tt_runtime_core_env_path "$ROOT")"
sed -i "s|^TT_TZ=.*|TT_TZ=$TZ_DEFAULT|" "$ENV_FILE"
sed -i "s|^TT_BIND_IP=.*|TT_BIND_IP=$BIND_IP|" "$ENV_FILE"
ok "Applied TT_TZ=$TZ_DEFAULT, TT_BIND_IP=$BIND_IP"

# ── Interactive profile selection ─────────────────────────────────────────────
echo ""
echo -e "${CYAN}── Optional Services ──────────────────────────────────────${NC}"

prompt_yn() {
  local question="$1" default="${2:-n}"
  local hint="[y/N]"
  [[ "$default" == "y" ]] && hint="[Y/n]"
  read -r -p "  $question $hint: " answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy] ]]
}

PROFILES=()

METABASE_DEFAULT="$(json_get_bool "$SELECT_JSON_ROOT" "profiles.metabase" "false")"
WORDPRESS_DEFAULT="$(json_get_bool "$SELECT_JSON_ROOT" "profiles.wordpress" "false")"
KANBOARD_DEFAULT="$(json_get_bool "$SELECT_JSON_ROOT" "profiles.kanboard" "false")"
QDRANT_DEFAULT="$(json_get_bool "$SELECT_JSON_ROOT" "profiles.qdrant" "false")"
OLLAMA_DEFAULT="$(json_get_bool "$SELECT_JSON_ROOT" "profiles.ollama" "false")"
OPENWEBUI_DEFAULT="$(json_get_bool "$SELECT_JSON_ROOT" "profiles.openwebui" "false")"
MONITORING_DEFAULT="$(json_get_bool "$SELECT_JSON_ROOT" "profiles.monitoring" "false")"
PORTAINER_DEFAULT="$(json_get_bool "$SELECT_JSON_ROOT" "profiles.portainer" "false")"
TUNNEL_DEFAULT="$(json_get_bool "$SELECT_JSON_ROOT" "tunnel.enabled" "false")"

if [[ "$PROFILE_NAME" == "ai-workstation" ]]; then
  OLLAMA_DEFAULT="true"
  OPENWEBUI_DEFAULT="true"
fi

enable_profile() {
  local profile="$1" enabled="$2"
  [[ "$enabled" == "true" ]] && PROFILES+=("$profile")
}

if [[ -n "$PROFILE_NAME" ]]; then
  enable_profile "metabase" "$METABASE_DEFAULT"
  enable_profile "wordpress" "$WORDPRESS_DEFAULT"
  enable_profile "kanboard" "$KANBOARD_DEFAULT"
  enable_profile "qdrant" "$QDRANT_DEFAULT"
  enable_profile "ollama" "$OLLAMA_DEFAULT"
  enable_profile "openwebui" "$OPENWEBUI_DEFAULT"
  enable_profile "monitoring" "$MONITORING_DEFAULT"
  enable_profile "portainer" "$PORTAINER_DEFAULT"
else
  prompt_yn "Enable Metabase BI/Analytics?" "$(yn_default "$METABASE_DEFAULT")" && PROFILES+=("metabase")
  prompt_yn "Enable WordPress + MariaDB?" "$(yn_default "$WORDPRESS_DEFAULT")" && PROFILES+=("wordpress")
  prompt_yn "Enable Kanboard (project management)?" "$(yn_default "$KANBOARD_DEFAULT")" && PROFILES+=("kanboard")
  prompt_yn "Enable Qdrant (vector DB for AI/RAG)?" "$(yn_default "$QDRANT_DEFAULT")" && PROFILES+=("qdrant")
  if prompt_yn "Enable Ollama + Open WebUI (local LLM)?" "$(yn_default "$OPENWEBUI_DEFAULT")"; then
    PROFILES+=("ollama")
    PROFILES+=("openwebui")
  fi
  prompt_yn "Enable Uptime Kuma (monitoring)?" "$(yn_default "$MONITORING_DEFAULT")" && PROFILES+=("monitoring")
  prompt_yn "Enable Portainer (Docker management)?" "$(yn_default "$PORTAINER_DEFAULT")" && PROFILES+=("portainer")
fi

# ── Supabase ──────────────────────────────────────────────────────────────────
if [[ "$WITH_SUPABASE_EXPLICIT" == "false" ]] && [[ -z "$PROFILE_NAME" ]]; then
  prompt_yn "Install tt-supabase BaaS stack?" && WITH_SUPABASE=true
fi

# ── Tunnel setup ──────────────────────────────────────────────────────────────
if [[ "$WITH_TUNNEL_EXPLICIT" == "false" ]]; then
  if [[ -n "$PROFILE_NAME" ]]; then
    WITH_TUNNEL="$TUNNEL_DEFAULT"
  else
    prompt_yn "Enable Cloudflare Tunnel?" "$(yn_default "$TUNNEL_DEFAULT")" && WITH_TUNNEL=true
  fi
fi

if [[ "$WITH_TUNNEL" == "true" ]]; then
  if [[ -z "$DOMAIN" ]]; then
    DOMAIN="$(json_get_text "$SELECT_JSON_ROOT" "client.domain")"
  fi

  if [[ -z "$DOMAIN" ]]; then
    if [[ -n "$PROFILE_NAME" ]]; then
      fail "Tunnel profile requires a domain. Re-run with --domain example.com"
    fi
    read -r -p "  Base domain for Cloudflare Tunnel (e.g. example.com): " DOMAIN
  fi

  TUNNEL_ENV="$(tt_runtime_tunnel_env_path "$ROOT")"
  TUNNEL_ENV_TPL="$ROOT/env/tunnel.env.example"
  [[ ! -f "$TUNNEL_ENV_TPL" ]] && TUNNEL_ENV_TPL="$ROOT/compose/tt-tunnel/.env.example"
  [[ ! -f "$TUNNEL_ENV_TPL" ]] && fail "Missing tunnel env template"

  cp "$TUNNEL_ENV_TPL" "$TUNNEL_ENV"
  sed -i "s|^TT_TZ=.*|TT_TZ=$TZ_DEFAULT|" "$TUNNEL_ENV"

  # Set n8n URLs for tunnel
  N8N_SUBDOMAIN="n8n"
  N8N_URL="https://${N8N_SUBDOMAIN}.${DOMAIN}"
  sed -i "s|^TT_N8N_HOST=.*|TT_N8N_HOST=${N8N_SUBDOMAIN}.${DOMAIN}|" "$ENV_FILE"
  sed -i "s|^TT_N8N_PROTOCOL=.*|TT_N8N_PROTOCOL=https|" "$ENV_FILE"
  sed -i "s|^TT_N8N_WEBHOOK_URL=.*|TT_N8N_WEBHOOK_URL=${N8N_URL}/|" "$ENV_FILE"
  sed -i "s|^TT_N8N_EDITOR_BASE_URL=.*|TT_N8N_EDITOR_BASE_URL=${N8N_URL}|" "$ENV_FILE"
  ok "n8n URLs set for tunnel -> $N8N_URL"
  warn "ACTION REQUIRED: Set CF_TUNNEL_TOKEN=<your-token> in: $TUNNEL_ENV"
  warn "Get your token from: Cloudflare Zero Trust → Networks → Tunnels"
fi

# ── Supabase install ──────────────────────────────────────────────────────────
if [[ "$WITH_SUPABASE" == "true" ]]; then
  echo ""
  info "Installing tt-supabase..."
  SUP_PKG="$(dirname "$PKG_ROOT")/tt-supabase"
  if [[ -d "$SUP_PKG" ]]; then
    mkdir -p "$SUPABASE_ROOT"
    cp -r "$SUP_PKG/." "$SUPABASE_ROOT/"
    ok "tt-supabase copied -> $SUPABASE_ROOT"

    # Init Supabase (Bash version)
    SUPABASE_INIT="$SUPABASE_ROOT/scripts-linux/init.sh"
    if [[ -f "$SUPABASE_INIT" ]]; then
      bash "$SUPABASE_INIT" --root "$SUPABASE_ROOT"
    fi
  else
    warn "tt-supabase package not found at $SUP_PKG"
    warn "Run: bash $SUPABASE_ROOT/scripts-linux/init.sh --root $SUPABASE_ROOT"
  fi
fi

# ── Update services.select.json ───────────────────────────────────────────────
if command -v python3 &>/dev/null; then
  python3 - "$ROOT/config/services.select.json" "$TZ_DEFAULT" "$BIND_IP" "$DOMAIN" "$WITH_TUNNEL" "$(IFS=,; echo "${PROFILES[*]}")" << 'PYEOF'
import json, sys, datetime
path, tz, bind_ip, domain, with_tunnel, profile_csv = sys.argv[1:7]
active_profiles = {p.strip() for p in profile_csv.split(",") if p.strip()}
with open(path) as f:
  d = json.load(f)
d['client']['timezone'] = tz
d['client']['bind_ip']  = bind_ip
d.setdefault('tunnel', {})
d['tunnel']['enabled'] = (with_tunnel.lower() == 'true')
if domain:
  d['client']['domain'] = domain
if isinstance(d.get('profiles'), dict):
  for key in d['profiles'].keys():
    d['profiles'][key] = (key in active_profiles)
if 'meta' in d:
  d['meta']['installed_at'] = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
  # Read canonical version from release/version.json (single source of truth)
  import os
  ver_file = os.path.join(os.path.dirname(os.path.dirname(path)), 'release', 'version.json')
  canon_ver = json.load(open(ver_file)).get('package_version','v14.0') if os.path.exists(ver_file) else 'v14.0'
  d['meta']['package_version'] = canon_ver
with open(path, 'w') as f:
  json.dump(d, f, indent=2)
  f.write('\n')
PYEOF
  ok "services.select.json updated"
fi

# ── Preflight ─────────────────────────────────────────────────────────────────
echo ""
info "Running preflight check..."
bash "$ROOT/scripts-linux/preflight-check.sh" --root "$ROOT" || fail "Preflight check failed. Fix issues before starting."

# ── Start services ────────────────────────────────────────────────────────────
if [[ "$NO_START" == "true" ]]; then
  ok "Setup complete (--no-start). Run: bash $ROOT/scripts-linux/start-core.sh"
  exit 0
fi

echo ""
echo -e "${CYAN}Starting TT-Core services...${NC}"

COMPOSE_ARGS=("-f" "$ROOT/compose/tt-core/docker-compose.yml")
# Add addons
for addon in "$ROOT/compose/tt-core/addons"/*.yml; do
  fname="$(basename "$addon")"
  [[ "$fname" == "00-template"* ]] && continue
  COMPOSE_ARGS+=("-f" "$addon")
done
# Add profiles
for profile in "${PROFILES[@]}"; do
  COMPOSE_ARGS+=("--profile" "$profile")
done
COMPOSE_ARGS+=("up" "-d")

docker compose "${COMPOSE_ARGS[@]}"
ok "TT-Core services started"

if [[ "$WITH_TUNNEL" == "true" ]]; then
  echo ""
  echo -e "${CYAN}Starting TT-Tunnel...${NC}"
  docker compose -f "$ROOT/compose/tt-tunnel/docker-compose.yml" \
    --env-file "$(tt_runtime_tunnel_env_path "$ROOT")" up -d
  ok "TT-Tunnel started"
fi

if [[ "$WITH_SUPABASE" == "true" ]] && [[ -f "$SUPABASE_ROOT/scripts-linux/start.sh" ]]; then
  echo ""
  echo -e "${CYAN}Starting TT-Supabase...${NC}"
  bash "$SUPABASE_ROOT/scripts-linux/start.sh" --root "$SUPABASE_ROOT"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Installation Complete ✓  (TT-Production v14.0)     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo -e "${GRAY}  Core .env   : $ENV_FILE${NC}"
echo -e "${GRAY}  Volumes     : $ROOT/compose/tt-core/volumes/${NC}"
echo ""
echo "Quick commands:"
echo -e "  Status       : ${CYAN}bash $ROOT/scripts-linux/status.sh${NC}"
echo -e "  Smoke test   : ${CYAN}bash $ROOT/scripts-linux/smoke-test.sh${NC}"
echo -e "  Preflight    : ${CYAN}bash $ROOT/scripts-linux/preflight-check.sh${NC}"
echo -e "  Backup       : ${CYAN}bash $ROOT/scripts-linux/backup.sh${NC}"

