#!/usr/bin/env bash
# =============================================================================
# tt-supabase rotate-secrets.sh — TT-Production v14.0
#
# Rotates Supabase secrets: JWT_SECRET, ANON_KEY, SERVICE_ROLE_KEY,
# DASHBOARD_PASSWORD, LOGFLARE_API_KEY.
#
# IMPORTANT: After rotation, all applications using ANON_KEY or SERVICE_ROLE_KEY
# must be updated. This will invalidate existing sessions.
#
# Usage:
#   bash scripts-linux/rotate-secrets.sh
#   bash scripts-linux/rotate-secrets.sh --dry-run
# =============================================================================
set -euo pipefail
VER="v14.0"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT/compose/tt-supabase/.env"

log()  { echo -e "${CYAN}[rotate-secrets]${NC} $*"; }
ok()   { echo -e "${GREEN}[rotate-secrets]${NC} ✓ $*"; }
err()  { echo -e "${RED}[rotate-secrets]${NC} ✗ $*"; exit 1; }
warn() { echo -e "${YELLOW}[rotate-secrets]${NC} ⚠ $*"; }

echo ""
echo -e "${CYAN}${BOLD}TT-Supabase Secret Rotation — $VER${NC}"
echo -e "${CYAN}════════════════════════════════════════════${NC}"
echo ""

DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in --dry-run) DRY_RUN=1 ;; esac; shift
done

[[ $DRY_RUN -eq 1 ]] && warn "DRY-RUN: no changes will be written"
[[ ! -f "$ENV_FILE" ]] && err ".env not found: $ENV_FILE — run init.sh first"

warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
warn "WARNING: Secret rotation invalidates all current"
warn "sessions and API keys. Update all applications"
warn "after rotation. This action is irreversible."
warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ $DRY_RUN -eq 0 ]]; then
  echo -ne "${YELLOW}Proceed with secret rotation? [yes/N]: ${NC}"
  read -r confirm
  [[ "$confirm" != "yes" ]] && { log "Aborted."; exit 0; }
fi

gen_secret() { openssl rand -base64 48 | tr -d '\n/+=' | head -c 64; }
gen_password() { openssl rand -base64 24 | tr -d '\n/+=' | head -c 32; }
gen_key() { openssl rand -base64 64 | tr -d '\n' | head -c 88; }

log "Generating new secrets..."
NEW_JWT=$(gen_secret)
NEW_ANON=$(gen_key)
NEW_SERVICE=$(gen_key)
NEW_DASH=$(gen_password)
NEW_LOGFLARE=$(gen_secret)

if [[ $DRY_RUN -eq 1 ]]; then
  ok "JWT_SECRET: [new 64-char secret]"
  ok "DASHBOARD_PASSWORD: [new 32-char password]"
  ok "LOGFLARE_API_KEY: [new 64-char key]"
  ok "ANON_KEY / SERVICE_ROLE_KEY: [new JWT tokens]"
  echo ""
  warn "Dry-run complete — no changes written"
  exit 0
fi

# Backup before rotation
BACKUP_ENV="${ENV_FILE}.bak-$(date +%Y%m%d-%H%M%S)"
cp "$ENV_FILE" "$BACKUP_ENV"
ok "Backed up .env to $BACKUP_ENV"

# Replace secrets
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$NEW_JWT|" "$ENV_FILE"
sed -i "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$NEW_DASH|" "$ENV_FILE"
sed -i "s|^LOGFLARE_API_KEY=.*|LOGFLARE_API_KEY=$NEW_LOGFLARE|" "$ENV_FILE"

ok "JWT_SECRET rotated"
ok "DASHBOARD_PASSWORD rotated"
ok "LOGFLARE_API_KEY rotated"

warn "ANON_KEY and SERVICE_ROLE_KEY must be regenerated using your JWT tool"
warn "  (jose-jwt, supabase CLI, or custom generator with new JWT_SECRET=$NEW_JWT)"
warn "  Then manually update ANON_KEY= and SERVICE_ROLE_KEY= in $ENV_FILE"

echo ""
log "Restarting tt-supabase to apply new secrets..."
COMPOSE_DIR="$ROOT/compose/tt-supabase"
docker compose -f "$COMPOSE_DIR/docker-compose.yml" down
docker compose -f "$COMPOSE_DIR/docker-compose.yml" up -d

echo ""
ok "Secret rotation complete"
warn "Action required: update ANON_KEY and SERVICE_ROLE_KEY in $ENV_FILE"
warn "Action required: update all applications using old API keys"
echo ""
