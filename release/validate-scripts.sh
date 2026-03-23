#!/usr/bin/env bash
# =============================================================================
# validate-scripts.sh — TT-Production v14.0
# Shell syntax validation gate (bash -n) for all .sh scripts.
# Integrates with release pipeline as a hard-fail gate.
#
# Usage: bash release/validate-scripts.sh [--root /path] [--shellcheck]
# Exit:  0 = all pass | 1 = syntax failure(s) detected
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(dirname "$SCRIPT_DIR")}"
USE_SHELLCHECK=false

while [[ $# -gt 0 ]]; do
  case "$1" in --root) ROOT="$2"; shift 2 ;; --shellcheck) USE_SHELLCHECK=true; shift ;; *) shift ;; esac
done

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
SYNTAX_FAIL=0; SYNTAX_PASS=0; SC_FAIL=0; SC_PASS=0

echo -e "${CYAN}${BOLD}── Shell Script Validation — TT-Production v14.0 ────${NC}"

# 1. bash -n syntax check on all .sh files
echo -e "${CYAN}── 1. bash -n Syntax Check ───────────────────────────────────${NC}"
while IFS= read -r f; do
  rel="${f#$ROOT/}"
  if bash -n "$f" 2>/dev/null; then
    ((SYNTAX_PASS++)) || true
  else
    ERR=$(bash -n "$f" 2>&1 | head -1)
    echo -e "  ${RED}[FAIL]${NC} $rel"
    echo -e "         ${YELLOW}$ERR${NC}"
    ((SYNTAX_FAIL++)) || true
  fi
done < <(find "$ROOT" -name "*.sh" \
  ! -path "*/.git/*" ! -path "*/history/*" ! -path "*/__pycache__/*" \
  | sort)

[[ $SYNTAX_FAIL -eq 0 ]] \
  && echo -e "  ${GREEN}[PASS]${NC} All $SYNTAX_PASS shell scripts pass bash -n" \
  || echo -e "  ${RED}[FAIL]${NC} $SYNTAX_FAIL / $((SYNTAX_PASS+SYNTAX_FAIL)) scripts have syntax errors"

# 2. shellcheck (if available or requested)
echo -e "${CYAN}── 2. shellcheck Integration ─────────────────────────────────${NC}"
if command -v shellcheck &>/dev/null; then
  while IFS= read -r f; do
    rel="${f#$ROOT/}"
    if shellcheck -S warning "$f" &>/dev/null; then
      ((SC_PASS++)) || true
    else
      WARN_COUNT=$(shellcheck -S warning "$f" 2>&1 | grep -c "^In" || true)
      echo -e "  ${YELLOW}[WARN]${NC} $rel — $WARN_COUNT shellcheck warning(s)"
      ((SC_FAIL++)) || true
    fi
  done < <(find "$ROOT" -name "*.sh" \
    ! -path "*/.git/*" ! -path "*/history/*" | sort)
  [[ $SC_FAIL -eq 0 ]] \
    && echo -e "  ${GREEN}[PASS]${NC} All $SC_PASS scripts pass shellcheck" \
    || echo -e "  ${YELLOW}[WARN]${NC} $SC_FAIL scripts have shellcheck warnings (non-blocking)"
else
  echo -e "  ${YELLOW}[INFO]${NC} shellcheck not installed — skipping (install: apt-get install shellcheck)"
  echo -e "         Syntax validation via bash -n completed above."
fi

echo ""
echo -e "${CYAN}${BOLD}━━━ Script Validation Summary ━━━${NC}"
echo "  bash -n: ${SYNTAX_PASS} pass / ${SYNTAX_FAIL} fail"
[[ "$USE_SHELLCHECK" == "true" ]] && echo "  shellcheck: ${SC_PASS} pass / ${SC_FAIL} warn"
echo ""

if [[ $SYNTAX_FAIL -gt 0 ]]; then
  echo -e "${RED}${BOLD}  SCRIPT VALIDATION: FAIL — $SYNTAX_FAIL syntax error(s). Must fix before release.${NC}"
  exit 1
else
  echo -e "${GREEN}${BOLD}  SCRIPT VALIDATION: PASS — all $SYNTAX_PASS scripts syntactically valid${NC}"
  exit 0
fi


