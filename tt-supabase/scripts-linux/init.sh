#!/usr/bin/env bash
# =============================================================================
# TT-Supabase init.sh — Linux/VPS Initializer (TT-Production v14.0)
# M-3 FIX: Linux equivalent of Init-Supabase.ps1
# Generates proper HS256 JWT tokens for ANON_KEY and SERVICE_ROLE_KEY.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

ENV_FILE="$ROOT/compose/tt-supabase/.env"
ENV_EXAMPLE="$ROOT/env/tt-supabase.env.example"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; GRAY='\033[0;37m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]${NC}   $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
info() { echo -e "  ${GRAY}[INFO]${NC} $*"; }

echo ""
echo -e "${CYAN}TT-Supabase Init — TT-Production v14.0 (Linux)${NC}"
echo ""

[[ ! -d "$ROOT" ]]        && echo "ERROR: Root not found: $ROOT" && exit 1
[[ ! -f "$ENV_EXAMPLE" ]] && echo "ERROR: Missing env example: $ENV_EXAMPLE" && exit 1

# ── Create env file ───────────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  ok ".env created"
else
  info ".env already exists"
fi

get_val() { grep "^${1}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | xargs 2>/dev/null || true; }
set_val() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

# ── Generate base secrets ─────────────────────────────────────────────────────
POSTGRES_PASSWORD=$(get_val POSTGRES_PASSWORD)
if [[ -z "$POSTGRES_PASSWORD" || "$POSTGRES_PASSWORD" == "__GENERATE__" ]]; then
  POSTGRES_PASSWORD="$(openssl rand -base64 24 | tr -d '=+/')"
  set_val POSTGRES_PASSWORD "$POSTGRES_PASSWORD"
  ok "Generated POSTGRES_PASSWORD"
else info "POSTGRES_PASSWORD already set"; fi

DASHBOARD_PASSWORD=$(get_val DASHBOARD_PASSWORD)
if [[ -z "$DASHBOARD_PASSWORD" || "$DASHBOARD_PASSWORD" == "__GENERATE__" ]]; then
  DASHBOARD_PASSWORD="$(openssl rand -base64 18 | tr -d '=+/')"
  set_val DASHBOARD_PASSWORD "$DASHBOARD_PASSWORD"
  ok "Generated DASHBOARD_PASSWORD"
else info "DASHBOARD_PASSWORD already set"; fi

# ── JWT_SECRET ────────────────────────────────────────────────────────────────
JWT_SECRET=$(get_val JWT_SECRET)
NEEDS_JWT_REGEN=false
if [[ -z "$JWT_SECRET" || "$JWT_SECRET" == "__GENERATE__" ]]; then
  JWT_SECRET="$(openssl rand -base64 32 | tr -d '=+/')"
  set_val JWT_SECRET "$JWT_SECRET"
  NEEDS_JWT_REGEN=true
  ok "Generated JWT_SECRET"
else info "JWT_SECRET already set"; fi

# ── Generate proper HS256 JWT tokens ─────────────────────────────────────────
# Supabase requires role-bearing JWTs — random bytes will NOT work.
make_jwt() {
  local role="$1" secret="$2"
  local iat exp header payload sig input

  iat=$(date +%s)
  exp=$(( iat + 5*365*24*3600 ))

  b64url() { echo -n "$1" | openssl base64 -A | tr '+/' '-_' | tr -d '='; }
  hmac_sha256() {
    echo -n "$1" | openssl dgst -sha256 -hmac "$2" -binary | openssl base64 -A | tr '+/' '-_' | tr -d '='
  }

  header=$(b64url '{"alg":"HS256","typ":"JWT"}')
  payload=$(b64url "{\"role\":\"${role}\",\"iss\":\"supabase\",\"iat\":${iat},\"exp\":${exp}}")
  input="${header}.${payload}"
  sig=$(hmac_sha256 "$input" "$secret")
  echo "${input}.${sig}"
}

ANON_KEY=$(get_val ANON_KEY)
ANON_PARTS=$(echo "$ANON_KEY" | awk -F'.' '{print NF}')
if [[ "$NEEDS_JWT_REGEN" == "true" || -z "$ANON_KEY" || "$ANON_KEY" == "__GENERATE__" || "$ANON_PARTS" -ne 3 ]]; then
  ANON_KEY=$(make_jwt "anon" "$JWT_SECRET")
  set_val ANON_KEY "$ANON_KEY"
  ok "Generated ANON_KEY (HS256 JWT, role=anon)"
else info "ANON_KEY already set (JWT format)"; fi

SERVICE_ROLE_KEY=$(get_val SERVICE_ROLE_KEY)
SVC_PARTS=$(echo "$SERVICE_ROLE_KEY" | awk -F'.' '{print NF}')
if [[ "$NEEDS_JWT_REGEN" == "true" || -z "$SERVICE_ROLE_KEY" || "$SERVICE_ROLE_KEY" == "__GENERATE__" || "$SVC_PARTS" -ne 3 ]]; then
  SERVICE_ROLE_KEY=$(make_jwt "service_role" "$JWT_SECRET")
  set_val SERVICE_ROLE_KEY "$SERVICE_ROLE_KEY"
  ok "Generated SERVICE_ROLE_KEY (HS256 JWT, role=service_role)"
else info "SERVICE_ROLE_KEY already set (JWT format)"; fi

# ── Create volume dirs ────────────────────────────────────────────────────────
COMPOSE_DIR="$ROOT/compose/tt-supabase"
for vol in db/data storage/data functions/v1/logs; do
  mkdir -p "$COMPOSE_DIR/volumes/$vol"
done
ok "Volume directories created."

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  TT-Supabase initialized — v14.0        ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  File: $ENV_FILE${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}║  IMPORTANT: ANON_KEY and SERVICE_ROLE_KEY are JWT tokens ║${NC}"
echo -e "${GREEN}║  signed with JWT_SECRET. Never replace with random bytes.║${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}║  Next steps:                                             ║${NC}"
echo -e "${GREEN}║    1) Set SUPABASE_PUBLIC_URL / API_EXTERNAL_URL / SITE_URL in tt-supabase.env               ║${NC}"
echo -e "${GREEN}║    2) bash scripts-linux/preflight.sh                    ║${NC}"
echo -e "${GREEN}║    3) bash scripts-linux/start.sh                        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
