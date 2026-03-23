#!/usr/bin/env bash
# =============================================================================
# secret-scan-ci.sh — TT-Production CI Secret Exposure Gate
#
# Purpose:
#   CI-focused secret scan for source repositories (unlike bundle scanner).
#   Safe to run in repos that contain .git metadata.
#
# Exit codes:
#   0 = PASS (no blocking findings)
#   1 = FAIL (blocking findings)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(dirname "$SCRIPT_DIR")}"
STRICT=false
ALLOW_RUNTIME_ENV=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --strict) STRICT=true; shift ;;
    --allow-runtime-env) ALLOW_RUNTIME_ENV=true; shift ;;
    *) shift ;;
  esac
done

ISSUES=0
WARNINGS=0
SCANNED=0

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

pass() { echo -e "  ${GREEN}[PASS]${NC} $*"; }
fail() { ((ISSUES++)) || true; echo -e "  ${RED}[FAIL]${NC} $*"; }
warn() {
  ((WARNINGS++)) || true
  echo -e "  ${YELLOW}[WARN]${NC} $*"
  [[ "$STRICT" == "true" ]] && ((ISSUES++)) || true
}

is_ignored_file() {
  local f="$1"
  case "$f" in
    */.git/*|*/release/history/*|*/__pycache__/*|*/node_modules/*|*/.venv/*)
      return 0 ;;
    *.png|*.jpg|*.jpeg|*.gif|*.ico|*.svg|*.zip|*.tar|*.gz|*.pdf|*.db)
      return 0 ;;
  esac
  return 1
}

is_ignored_line() {
  local line="$1"
  [[ "$line" == *"__GENERATE__"* ]] && return 0
  [[ "$line" == *"example.com"* ]] && return 0
  [[ "$line" == *"noreply@example.local"* ]] && return 0
  [[ "$line" == *"placeholder"* ]] && return 0
  [[ "$line" == *"CHANGE_ME"* ]] && return 0
  [[ "$line" == *"YOUR_"* ]] && return 0
  return 1
}

echo ""
echo -e "${CYAN}── CI Secret Exposure Gate ───────────────────────────${NC}"
echo -e "  Root: $ROOT"
echo ""

if [[ "$ALLOW_RUNTIME_ENV" != "true" ]]; then
  RUNTIME_ENVS=$(find "$ROOT" -type f \( -name ".env" -o -name "*.env" -o -name ".env.*" \) \
    -not -name "*.example" -not -name "*.example.env" \
    -not -name "*.template" -not -name "*.template.env" -not -name "*.enc.env" \
    -not -path "*/.git/*" 2>/dev/null || true)
  if [[ -n "$RUNTIME_ENVS" ]]; then
    fail "Runtime .env files found in source tree (not allowed in CI): $RUNTIME_ENVS"
  else
    pass "No runtime .env files detected"
  fi
else
  pass "Runtime .env check bypassed via --allow-runtime-env (local CI mode)"
fi

declare -a RULES=(
  "PRIVATE_KEY:::-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----"
  "AWS_ACCESS_KEY:::AKIA[0-9A-Z]{16}"
  "JWT:::eyJ[A-Za-z0-9_-]{20,}\\.[A-Za-z0-9_-]{20,}\\.[A-Za-z0-9_-]{10,}"
  "BEARER_TOKEN:::Bearer [A-Za-z0-9._-]{30,}"
  "SLACK_TOKEN:::xox[baprs]-[A-Za-z0-9-]{10,}"
)

while IFS= read -r -d '' file; do
  rel="${file#$ROOT/}"
  is_ignored_file "$rel" && continue
  [[ "$file" =~ \.(sh|ps1|json|ya?ml|env|md|txt|toml|py|js|ts|ini|conf)$ ]] || continue

  ((SCANNED++)) || true

  for rule in "${RULES[@]}"; do
    label="${rule%%:::*}"
    regex="${rule#*:::}"

    while IFS= read -r hit; do
      [[ -z "$hit" ]] && continue
      line_no="${hit%%:*}"
      line_txt="${hit#*:}"
      is_ignored_line "$line_txt" && continue
      fail "$label in $rel:$line_no"
    done < <(grep -En "$regex" "$file" 2>/dev/null || true)
  done
done < <(find "$ROOT" -type f -print0)

pass "Scanned files: $SCANNED"
echo ""

if [[ $ISSUES -gt 0 ]]; then
  echo -e "${RED}CI SECRET GATE: FAIL (${ISSUES} issue(s))${NC}"
  exit 1
fi

if [[ $WARNINGS -gt 0 ]]; then
  echo -e "${YELLOW}CI SECRET GATE: PASS_WITH_WARNINGS (${WARNINGS})${NC}"
else
  echo -e "${GREEN}CI SECRET GATE: PASS${NC}"
fi

exit 0



