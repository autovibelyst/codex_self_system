#!/usr/bin/env bash
# =============================================================================
# migrate-to-sops.sh — Migrate from plaintext .env to SOPS-encrypted secrets
# TT-Production v14.0
#
# Migrates an existing v12.x or earlier plaintext .env deployment to the
# v14.0 SOPS + age encrypted secrets model.
#
# Prerequisites:
#   - sops binary installed (brew/apt/manual)
#   - age binary installed
#   - Existing .env file at tt-core/compose/tt-core/.env
#   - Run installer/lib/sops-setup.sh first to generate age keypair
#
# What this script does:
#   1. Verifies SOPS and age are available
#   2. Reads .sops.yaml for the public key
#   3. Extracts secret values from existing .env
#   4. Creates core.secrets.enc.env (encrypted)
#   5. Creates tunnel.secrets.enc.env (encrypted)
#   6. Validates decryption works
#   7. Creates backup of original .env
#
# Usage:
#   bash tt-core/scripts-linux/migrate-to-sops.sh [--dry-run]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
RUNTIME_ENV_LIB="$SCRIPT_DIR/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# Align decrypt validation with installer-managed age key location.
TT_AGE_KEY_DEFAULT="$HOME/.config/tt-production/age/key.txt"
if [[ -z "${SOPS_AGE_KEY_FILE:-}" && -f "$TT_AGE_KEY_DEFAULT" ]]; then
  export SOPS_AGE_KEY_FILE="$TT_AGE_KEY_DEFAULT"
fi

ok()   { echo -e "  ${GREEN}[OK]${NC}    $*"; }
err()  { echo -e "  ${RED}[ERR]${NC}   $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC}  $*"; }
info() { echo -e "  ${CYAN}[INFO]${NC}  $*"; }

echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  TT-Production SOPS Migration Tool           ${NC}"
echo -e "${CYAN}  v12.x plaintext → v14.0 encrypted secrets   ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo ""
[[ "$DRY_RUN" == "true" ]] && warn "DRY-RUN mode — no files will be written"

# ── Step 1: Check prerequisites ───────────────────────────────────────────────
info "Step 1: Checking prerequisites..."

if ! command -v sops &>/dev/null; then
  err "sops not found. Run: bash tt-core/installer/lib/sops-setup.sh"
  exit 1
fi
ok "sops: $(sops --version 2>&1 | head -1)"

if ! command -v age &>/dev/null; then
  err "age not found. Run: bash tt-core/installer/lib/sops-setup.sh"
  exit 1
fi
ok "age: $(age --version 2>&1 | head -1)"

SOPS_YAML="$ROOT/secrets/.sops.yaml"
if [[ ! -f "$SOPS_YAML" ]]; then
  err ".sops.yaml not found at $SOPS_YAML"
  err "Run: bash tt-core/installer/lib/sops-setup.sh"
  exit 1
fi
ok ".sops.yaml: found"

ENV_FILE="$(tt_resolve_core_env_path "$ROOT")"
if [[ ! -f "$ENV_FILE" ]]; then
  err "No runtime env file found at $ENV_FILE"
  err "Cannot migrate — source runtime env must exist"
  exit 1
fi
ok "runtime env: found at $ENV_FILE"

# ── Step 2: Extract age public key ────────────────────────────────────────────
info "Step 2: Reading age public key from .sops.yaml..."
AGE_KEY=$(grep "age:" "$SOPS_YAML" | grep -Eo 'age1[a-z0-9]+' | head -1 || true)
if [[ -z "$AGE_KEY" ]]; then
  err "Could not extract age public key from $SOPS_YAML"
  exit 1
fi
ok "age public key: ${AGE_KEY:0:20}..."

# ── Step 3: Identify secrets to migrate ──────────────────────────────────────
info "Step 3: Extracting secrets from .env..."

SECRET_VARS=(
  TT_POSTGRES_PASSWORD TT_REDIS_PASSWORD TT_N8N_ENCRYPTION_KEY
  TT_N8N_DB_PASSWORD TT_PGADMIN_PASSWORD TT_QDRANT_API_KEY
  TT_OPENCLAW_TOKEN TT_BACKUP_ENCRYPTION_KEY
  TT_N8N_USER_PASSWORD TT_METABASE_DB_PASSWORD TT_KANBOARD_DB_PASSWORD
  TT_WORDPRESS_DB_PASSWORD TT_SMTP_PASSWORD
)

TUNNEL_VARS=(CF_TUNNEL_TOKEN)

declare -A SECRET_VALUES
for var in "${SECRET_VARS[@]}" "${TUNNEL_VARS[@]}"; do
  val=$(grep "^${var}=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' || true)
  if [[ -n "$val" ]]; then
    SECRET_VALUES[$var]="$val"
    ok "  Found: $var"
  else
    warn "  Not found: $var (skipping)"
  fi
done

# ── Step 4: Create encrypted files ────────────────────────────────────────────
info "Step 4: Creating encrypted secret files..."

CORE_SECRETS_FILE="$ROOT/secrets/core.secrets.enc.env"
TUNNEL_SECRETS_FILE="$ROOT/secrets/tunnel.secrets.enc.env"

if [[ "$DRY_RUN" == "true" ]]; then
  warn "DRY-RUN: Would create $CORE_SECRETS_FILE"
  warn "DRY-RUN: Would create $TUNNEL_SECRETS_FILE"
else
  # Build core secrets plaintext
  CORE_PLAIN=""
  for var in "${SECRET_VARS[@]}"; do
    [[ -n "${SECRET_VALUES[$var]:-}" ]] && CORE_PLAIN+="${var}=${SECRET_VALUES[$var]}\n"
  done

  # Encrypt core secrets
  printf "$CORE_PLAIN" | sops --encrypt --input-type dotenv --output-type dotenv \
    --age "$AGE_KEY" /dev/stdin > "$CORE_SECRETS_FILE"
  ok "Created: $CORE_SECRETS_FILE"

  # Build tunnel secrets
  TUNNEL_PLAIN=""
  for var in "${TUNNEL_VARS[@]}"; do
    [[ -n "${SECRET_VALUES[$var]:-}" ]] && TUNNEL_PLAIN+="${var}=${SECRET_VALUES[$var]}\n"
  done

  if [[ -n "$TUNNEL_PLAIN" ]]; then
    printf "$TUNNEL_PLAIN" | sops --encrypt --input-type dotenv --output-type dotenv \
      --age "$AGE_KEY" /dev/stdin > "$TUNNEL_SECRETS_FILE"
    ok "Created: $TUNNEL_SECRETS_FILE"
  fi

  # ── Step 5: Validate decryption ───────────────────────────────────────────
  info "Step 5: Validating decryption..."
  if sops --decrypt "$CORE_SECRETS_FILE" > /dev/null 2>&1; then
    ok "Decryption test: PASS"
  else
    err "Decryption test FAILED — check age key at ~/.config/tt-production/age/key.txt"
    exit 1
  fi

  # ── Step 6: Backup original .env ──────────────────────────────────────────
  info "Step 6: Backing up original .env..."
  cp "$ENV_FILE" "${ENV_FILE}.pre-sops-migration.bak"
  ok "Backup: ${ENV_FILE}.pre-sops-migration.bak"
fi

echo ""
ok "Migration complete."
echo ""
info "Next steps:"
echo "    1. Set TT_SECRET_MODE=sops in tt-core/config/services.select.json"
echo "    2. Verify: bash tt-core/scripts-linux/validate-sops.sh"
echo "    3. Test startup: bash tt-core/scripts-linux/preflight-check.sh"
echo "    4. Keep .env.pre-sops-migration.bak in a secure location"
echo "    5. After confirming everything works, remove any legacy plaintext .env left inside the repo"
echo ""

