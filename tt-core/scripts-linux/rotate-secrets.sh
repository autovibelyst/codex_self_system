#!/usr/bin/env bash
# =============================================================================
# rotate-secrets.sh — TT-Core Secret Rotation Helper
# Version: v14.0
#
# Semi-automated helper for rotating individual secrets in .env without
# having to touch the file manually. Supports dry-run mode.
#
# Usage:
#   bash scripts-linux/rotate-secrets.sh
#   bash scripts-linux/rotate-secrets.sh --secret TT_PGADMIN_PASSWORD
#   bash scripts-linux/rotate-secrets.sh --dry-run
#   bash scripts-linux/rotate-secrets.sh --root /opt/stacks/tt-core
#
# EXIT: 0 = success, 1 = fatal error
#
# WARNING:
#   This script rotates .env values only. You must restart affected services
#   after rotation for the change to take effect.
#   See docs/CREDENTIAL_ROTATION.md for full per-secret procedures.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
RUNTIME_ENV_LIB="$SCRIPT_DIR/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"
DRY_RUN=false
TARGET_SECRET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=true; shift ;;
    --root)      ROOT="$2"; shift 2 ;;
    --secret)    TARGET_SECRET="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

ENV_FILE="$(tt_resolve_core_env_path "$ROOT")"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
RED='\033[0;31m'; GRAY='\033[0;37m'; NC='\033[0m'

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN} TT-Core Secret Rotation Helper — v14.0${NC}"
[[ "$DRY_RUN" == "true" ]] && echo -e "${YELLOW} DRY-RUN MODE — no changes will be written${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""

[[ ! -f "$ENV_FILE" ]] && echo -e "${RED}ERROR: .env not found: $ENV_FILE${NC}" && exit 1

gen_hex()    { openssl rand -hex 24; }
gen_b64()    { openssl rand -base64 32 | tr -d '=+/'; }
gen_alnum()  { openssl rand -hex 16; }

# List of rotatable low-risk secrets (no DB ALTER required)
# High-risk secrets (postgres, redis, n8n-db, n8n-enc-key) are documented
# in CREDENTIAL_ROTATION.md and require manual steps
LOW_RISK_SECRETS=(
  "TT_PGADMIN_PASSWORD"
  "TT_REDISINSIGHT_PASSWORD"
  "TT_QDRANT_API_KEY"
  "TT_OPENCLAW_TOKEN"
)

HIGH_RISK_SECRETS=(
  "TT_POSTGRES_PASSWORD"
  "TT_REDIS_PASSWORD"
  "TT_N8N_ENCRYPTION_KEY"
  "TT_N8N_DB_PASSWORD"
  "TT_METABASE_DB_PASSWORD"
  "TT_KANBOARD_DB_PASSWORD"
  "TT_WP_DB_PASSWORD"
  "TT_WP_ROOT_PASSWORD"
)

rotate_secret() {
  local key="$1"
  local format="${2:-hex}"
  local current_val
  current_val=$(grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | head -1 | tr -d '\r' || echo "")

  if [[ -z "$current_val" ]]; then
    echo -e "  ${YELLOW}[SKIP]${NC}  $key — not found in .env"
    return
  fi

  local new_val
  case "$format" in
    b64)   new_val=$(gen_b64) ;;
    alnum) new_val=$(gen_alnum) ;;
    *)     new_val=$(gen_hex) ;;
  esac

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} $key : would rotate (${#current_val} chars → ${#new_val} chars)"
    return
  fi

  sed -i "s|^${key}=.*|${key}=${new_val}|" "$ENV_FILE"
  echo -e "  ${GREEN}[ROTATED]${NC} $key : new value written to .env"
  echo "           Restart required: see docs/CREDENTIAL_ROTATION.md"
}

if [[ -n "$TARGET_SECRET" ]]; then
  # Single secret rotation
  echo "Rotating: $TARGET_SECRET"
  echo ""

  # Check if it's a high-risk secret
  for hr in "${HIGH_RISK_SECRETS[@]}"; do
    if [[ "$hr" == "$TARGET_SECRET" ]]; then
      echo -e "${RED}⛔ $TARGET_SECRET is a HIGH-RISK secret.${NC}"
      echo -e "${YELLOW}   Rotating it requires additional steps beyond just updating .env.${NC}"
      echo -e "${YELLOW}   Follow the full procedure in: docs/CREDENTIAL_ROTATION.md${NC}"
      echo ""
      echo "   To proceed with .env update only (you handle the DB/service steps):"
      echo "   Add --confirm-high-risk flag or edit .env manually."
      exit 1
    fi
  done

  # Format selection
  case "$TARGET_SECRET" in
    *REDISINSIGHT*) rotate_secret "$TARGET_SECRET" "alnum" ;;
    *ENCRYPTION*)   rotate_secret "$TARGET_SECRET" "b64" ;;
    *)              rotate_secret "$TARGET_SECRET" "hex" ;;
  esac

else
  # Show menu — only low-risk secrets
  echo "Low-risk secrets (restart only — no DB ALTER needed):"
  echo ""
  for secret in "${LOW_RISK_SECRETS[@]}"; do
    current=$(grep "^${secret}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | head -1 | tr -d '\r' || echo "")
    if [[ -n "$current" ]]; then
      echo -e "  ${GRAY}•${NC} $secret (current: ${#current} chars)"
    fi
  done
  echo ""

  echo "High-risk secrets (follow docs/CREDENTIAL_ROTATION.md for full procedure):"
  for secret in "${HIGH_RISK_SECRETS[@]}"; do
    echo -e "  ${RED}•${NC} $secret"
  done
  echo ""
  echo "To rotate a specific low-risk secret:"
  echo "  bash scripts-linux/rotate-secrets.sh --secret TT_PGADMIN_PASSWORD"
  echo ""
  echo "For high-risk rotation, read docs/CREDENTIAL_ROTATION.md first."
fi

echo ""
[[ "$DRY_RUN" == "true" ]] && echo -e "${YELLOW}DRY-RUN complete — no files were changed.${NC}"

# ── v14.0: SOPS Re-encryption (appended by v14.0 upgrade) ────────────────────
_tt_v13_sops_reencrypt() {
  local env_file
  env_file="$(tt_resolve_core_env_path "$ROOT")"
  local enc_file="$ROOT/secrets/core.secrets.enc.env"
  local sops_yaml="$ROOT/secrets/.sops.yaml"

  if [[ -z "${SOPS_AGE_KEY_FILE:-}" ]]; then
    local tt_age_key_default="$HOME/.config/tt-production/age/key.txt"
    [[ -f "$tt_age_key_default" ]] && export SOPS_AGE_KEY_FILE="$tt_age_key_default"
  fi

  if ! command -v sops &>/dev/null || grep -q "<OPERATOR_AGE_PUBLIC_KEY>" "$sops_yaml" 2>/dev/null; then
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY-RUN] Would re-encrypt secrets/core.secrets.enc.env with SOPS"
    return
  fi

  if [[ -f "$env_file" ]]; then
    echo "  Re-encrypting secrets with SOPS..."

    local tmp_plain
    tmp_plain=$(mktemp)
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$env_file" > "$tmp_plain"
    cp "$tmp_plain" "$enc_file"
    rm -f "$tmp_plain"

    if sops --encrypt --config "$sops_yaml" --input-type dotenv --output-type dotenv --in-place "$enc_file" 2>/dev/null; then
      echo -e "  ${GREEN}[OK]${NC}  SOPS re-encryption complete"
    else
      echo "  [WARN] SOPS re-encryption failed"
    fi
  fi
}

_tt_v13_sops_reencrypt

