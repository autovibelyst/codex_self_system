#!/usr/bin/env bash
# =============================================================================
# secrets-strength.sh — TT-Production v14.0
# Standalone secrets strength checker. Grades each configured secret A–F
# by length, character diversity, pattern detection, and repeating chars.
#
# Usage:
#   bash scripts-linux/secrets-strength.sh
#   bash scripts-linux/secrets-strength.sh --root /opt/stacks/tt-core
#   bash scripts-linux/secrets-strength.sh --env /path/to/.env
#   bash scripts-linux/secrets-strength.sh --strict    # exit 1 if any FAIL
#
# Exit:  0 = all pass or warnings only
#        1 = one or more FAIL (only with --strict)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
RUNTIME_ENV_LIB="$SCRIPT_DIR/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"
ENV_FILE=""
STRICT=false

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)   ROOT="$2";     shift 2 ;;
    --env)    ENV_FILE="$2"; shift 2 ;;
    --strict) STRICT=true;   shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$ENV_FILE" ]]; then
  ENV_FILE="$(tt_resolve_core_env_path "$ROOT")"
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo -e "${RED}ERROR: .env not found: $ENV_FILE${NC}"
  echo "  Run: bash scripts-linux/init.sh first"
  exit 1
fi

passes=0; warns=0; fails=0

get_val() { grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -n1 | cut -d'=' -f2- || true; }

check_secret() {
  local key="$1" label="$2" min_len="${3:-24}" required="${4:-true}"
  local val
  val="$(get_val "$key")"

  if [[ -z "$val" ]]; then
    if [[ "$required" == "true" ]]; then
      echo -e "  ${RED}[FAIL]${NC} $label ($key) — empty / not set"
      ((fails++)); return
    else
      echo -e "  ${YELLOW}[SKIP]${NC} $label ($key) — not configured (optional)"
      return
    fi
  fi

  if [[ "$val" == *"__GENERATE__"* || "$val" == *"__"* ]]; then
    echo -e "  ${RED}[FAIL]${NC} $label ($key) — still a placeholder: $val"
    echo -e "       Run: bash scripts-linux/init.sh"
    ((fails++)); return
  fi

  local len="${#val}"
  local has_lower=false has_upper=false has_digit=false has_special=false char_classes=0
  echo "$val" | grep -q '[a-z]' && has_lower=true && ((char_classes++)) || true
  echo "$val" | grep -q '[A-Z]' && has_upper=true && ((char_classes++)) || true
  echo "$val" | grep -q '[0-9]' && has_digit=true && ((char_classes++)) || true
  echo "$val" | grep -q '[^a-zA-Z0-9]' && has_special=true && ((char_classes++)) || true

  local grade="A" issues=""

  if (( len < min_len )); then
    grade="F"
    issues+=" length=${len}(need≥${min_len})"
  elif (( len < min_len + 8 )); then
    [[ "$grade" == "A" ]] && grade="B"
    issues+=" short(${len}chars)"
  fi

  if (( char_classes < 2 )); then
    grade="F"
    issues+=" single-class(${char_classes})"
  elif (( char_classes < 3 )); then
    [[ "$grade" == "A" ]] && grade="C"
    issues+=" low-entropy(${char_classes}classes)"
  fi

  if echo "$val" | grep -qiE '^(password|secret|admin|test|1234|qwerty|abc)'; then
    grade="F"
    issues+=" common-pattern"
  fi

  if echo "$val" | grep -qE '(.)\1{4,}'; then
    [[ "$grade" == "A" ]] && grade="C"
    issues+=" repeating-chars"
  fi

  case "$grade" in
    A)
      echo -e "  ${GREEN}[PASS]${NC} $label — grade A (len=${len}, classes=${char_classes})"
      ((passes++)) ;;
    B|C)
      echo -e "  ${YELLOW}[WARN]${NC} $label — grade $grade (${issues# })"
      ((warns++)) ;;
    F)
      echo -e "  ${RED}[FAIL]${NC} $label — grade F (${issues# })"
      echo -e "       Run: bash scripts-linux/rotate-secrets.sh --secret $key"
      ((fails++)) ;;
  esac
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}TT-Production v14.0 — Secrets Strength Report${NC}"
echo -e "${CYAN}File: $ENV_FILE${NC}"
echo "────────────────────────────────────────────────────"
echo ""
echo -e "${BOLD}Database Secrets${NC}"
check_secret "TT_POSTGRES_PASSWORD"       "PostgreSQL master password"    24
check_secret "TT_N8N_DB_PASSWORD"         "n8n database password"         20
check_secret "TT_WP_DB_ROOT_PASSWORD"     "WordPress MariaDB root"        20
check_secret "TT_WP_DB_PASSWORD"          "WordPress DB password"         20

echo ""
echo -e "${BOLD}Application Secrets${NC}"
check_secret "TT_N8N_ENCRYPTION_KEY"      "n8n encryption key (≥32)"      32
check_secret "TT_REDIS_PASSWORD"          "Redis password"                24
check_secret "TT_QDRANT_API_KEY"          "Qdrant API key"                20

echo ""
echo -e "${BOLD}UI & Access Secrets${NC}"
check_secret "TT_PGADMIN_PASSWORD"        "pgAdmin UI password"           16
check_secret "TT_REDISINSIGHT_PASSWORD"   "RedisInsight UI password"      16
check_secret "TT_OPENCLAW_TOKEN"          "OpenClaw API token"            20
check_secret "TT_WP_ADMIN_PASSWORD"       "WordPress admin password"      16

echo ""
echo "────────────────────────────────────────────────────"

total=$((passes + warns + fails))
echo -e "${BOLD}Summary:${NC} ${GREEN}${passes} PASS${NC} | ${YELLOW}${warns} WARN${NC} | ${RED}${fails} FAIL${NC} | Total: ${total}"
echo ""

if (( fails > 0 )); then
  echo -e "${RED}⚠  ${fails} secret(s) failed strength check.${NC}"
  echo "  To rotate:        bash scripts-linux/rotate-secrets.sh"
  echo "  To regenerate:    bash scripts-linux/init.sh (WARNING: changes live secrets)"
  echo ""
  if [[ "$STRICT" == "true" ]]; then exit 1; fi
elif (( warns > 0 )); then
  echo -e "${YELLOW}⚠  ${warns} secret(s) have weak but non-blocking grades.${NC}"
  echo "  Consider improving before production deployment."
  echo ""
else
  echo -e "${GREEN}✅ All secrets meet minimum strength requirements.${NC}"
  echo ""
fi

exit 0
