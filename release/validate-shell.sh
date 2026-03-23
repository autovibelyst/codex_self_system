#!/usr/bin/env bash
# =============================================================================
# TT-Core Validate Shell Scripts — v14.0
# Runs bash -n syntax check on ALL .sh files in the package.
# Blocks release on any syntax error.
#
# Usage:
#   bash release/validate-shell.sh [--root /path]
#
# Exit codes:
#   0 = all scripts pass bash -n
#   1 = one or more scripts have syntax errors (RELEASE BLOCKED)
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

FAILED=0
PASSED=0
TOTAL=0

TMP_ERR=$(mktemp 2>/dev/null || echo "/tmp/tt-validate-shell-$$.err")
cleanup() {
  rm -f "$TMP_ERR"
}
trap cleanup EXIT

echo ""
echo -e "\033[36m── Shell Script Syntax Validation (bash -n) ──────────\033[0m"
echo ""

while IFS= read -r -d '' f; do
  TOTAL=$((TOTAL + 1))
  if bash -n "$f" 2>"$TMP_ERR"; then
    PASSED=$((PASSED + 1))
    echo -e "  \033[32m[OK]\033[0m  ${f#$ROOT/}"
  else
    FAILED=$((FAILED + 1))
    echo -e "  \033[31m[ERR]\033[0m SYNTAX ERROR: ${f#$ROOT/}"
    sed 's/^/         /' "$TMP_ERR"
  fi
done < <(find "$ROOT" -name "*.sh" -not -path "*/.git/*" -print0 | sort -z)

echo ""
echo "  Scanned: $TOTAL scripts"
echo "  Passed:  $PASSED"
echo "  Failed:  $FAILED"
echo ""

if [[ $FAILED -gt 0 ]]; then
  echo -e "\033[31m  RELEASE BLOCKED: $FAILED shell script(s) have syntax errors.\033[0m"
  echo "  Fix all syntax errors before packaging."
  exit 1
fi

if [[ $TOTAL -lt 10 ]]; then
  echo -e "\033[1;33m  WARNING: Only $TOTAL scripts found — expected >= 10.\033[0m"
fi

echo -e "\033[32m  PASS: All $TOTAL scripts passed bash -n.\033[0m"
echo ""
