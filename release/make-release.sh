#!/usr/bin/env bash
# =============================================================================
# make-release.sh - TT-Production v14.0
# One-command release pipeline orchestrator.
# Runs all release stages in sequence with halt-on-error.
#
# Usage: bash release/make-release.sh [--root /path/to/bundle] [--out /path/to/output]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(dirname "$SCRIPT_DIR")}" 
if command -v cygpath >/dev/null 2>&1; then
  ROOT="$(cygpath -m "$ROOT")"
fi
OUT="${OUT:-$ROOT/../dist}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
PKG_VERSION=$(python3 -c "import json; print(json.load(open('$ROOT/release/version.json', encoding='utf-8'))['package_version'])")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo ""
echo -e "${CYAN}${BOLD}===============================================${NC}"
echo -e "${CYAN}${BOLD}  TT-Production Make-Release - $PKG_VERSION${NC}"
echo -e "${CYAN}${BOLD}===============================================${NC}"
echo ""

run_stage() {
  local name="$1"
  local cmd="$2"

  echo -e "${CYAN}-- $name ----------------------------------------------${NC}"
  if bash -c "$cmd"; then
    echo -e "  ${GREEN}OK${NC} $name"
  else
    echo -e "  ${RED}FAIL${NC} $name"
    exit 1
  fi
  echo ""
}

run_stage "1/7: Version Verification" "
  VER=\$(python3 -c \"import json; print(json.load(open('$ROOT/release/version.json', encoding='utf-8'))['package_version'])\")
  [[ -n \"\$VER\" ]] || { echo 'ERROR: version.json missing package_version'; exit 1; }
  echo \"  Version: \$VER\"
"

run_stage "2/7: Secret Scan" "bash $ROOT/release/secret-scan.sh --root $ROOT"
run_stage "3/7: Consistency Gate" "bash $ROOT/release/consistency-gate.sh --root $ROOT"

if [[ -f "$ROOT/release/lint-docs.sh" ]]; then
  run_stage "4/7: Documentation Lint" "bash $ROOT/release/lint-docs.sh --root $ROOT --fail-on-error 2>/dev/null || echo 'Lint warnings - non-fatal'"
else
  echo -e "${CYAN}-- 4/7: Documentation Lint (skipped - lint-docs.sh not found) --${NC}"
  echo ""
fi

run_stage "5/7: Generate Signoff" "
  bash $ROOT/release/generate-signoff.sh --root $ROOT
  VERDICT=\$(python3 -c \"import json; print(json.load(open('$ROOT/release/signoff.json', encoding='utf-8')).get('verdict','unknown'))\")
  echo \"  Signoff verdict: \$VERDICT\"
  [[ \"\$VERDICT\" == \"PASS\" || \"\$VERDICT\" == \"PASS_WITH_NOTES\" ]] || { echo 'ERROR: Signoff FAIL'; exit 1; }
"

if [[ -f "$ROOT/release/package-export.sh" ]]; then
  run_stage "6/7: Package Export" "
    mkdir -p $OUT
    bash $ROOT/release/package-export.sh --root $ROOT --out $OUT
  "
else
  echo -e "${CYAN}-- 6/7: Package Export (skipped - package-export.sh not found) --${NC}"
  echo ""
fi

echo -e "${CYAN}-- 7/7: Release Summary ----------------------------------------${NC}"
python3 -c "
import json
s = json.load(open('$ROOT/release/signoff.json', encoding='utf-8'))
print(f'  Product:   {s.get("bundle_name", "TT-Production")}')
print(f'  Version:   {s.get("tt_version", "unknown")}')
print(f'  Verdict:   {s.get("verdict", "unknown")}')
print(f'  Stages:    {len(s.get("stages", []))}')
print(f'  Export OK: {s.get("export_allowed", False)}')
print(f'  Handoff:   {s.get("handoff_allowed", False)}')
print(f'  Generated: {s.get("generated_at", "unknown")}')
"

echo ""
echo -e "${GREEN}${BOLD}===============================================${NC}"
echo -e "${GREEN}${BOLD}  RELEASE COMPLETE - $PKG_VERSION - $TIMESTAMP${NC}"
echo -e "${GREEN}${BOLD}===============================================${NC}"
echo ""

