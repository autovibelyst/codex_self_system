#!/usr/bin/env bash
# =============================================================================
# ci-gate.sh — TT-Production CI Quality + Security Gate
#
# Usage:
#   bash release/ci-gate.sh
#   bash release/ci-gate.sh --strict
#   TT_ALLOW_RUNTIME_ENV=1 bash release/ci-gate.sh --strict
#
# Exit codes:
#   0 = PASS / PASS_WITH_NOTES
#   1 = FAIL (blocking stage failed)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(dirname "$SCRIPT_DIR")}"
STRICT=false
SKIP_DOCS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --strict) STRICT=true; shift ;;
    --skip-docs) SKIP_DOCS=true; shift ;;
    *) shift ;;
  esac
done

STAGES=()
NOTES=()
BLOCKERS=()
OVERALL="PASS"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

stage() {
  local id="$1" name="$2" blocking="$3"
  shift 3

  local start end duration ec
  start=$(date +%s)

  echo ""
  echo -e "${CYAN}── CI Stage $id: $name ─────────────────────────────────${NC}"

  if "$@"; then
    end=$(date +%s)
    duration=$((end - start))
    echo -e "  ${GREEN}[PASS]${NC} Stage $id complete (${duration}s)"
    STAGES+=("$id|$name|PASS|0|$duration")
    return 0
  else
    ec=$?
    end=$(date +%s)
    duration=$((end - start))

    if [[ "$blocking" == "true" ]]; then
      echo -e "  ${RED}[FAIL]${NC} Stage $id failed (exit $ec)"
      BLOCKERS+=("Stage $id ($name) failed")
      OVERALL="FAIL"
      STAGES+=("$id|$name|FAIL|$ec|$duration")
      return 1
    fi

    echo -e "  ${YELLOW}[WARN]${NC} Stage $id returned non-zero (exit $ec)"
    NOTES+=("Stage $id ($name) produced warnings")
    [[ "$OVERALL" == "PASS" ]] && OVERALL="PASS_WITH_NOTES"
    STAGES+=("$id|$name|WARN|$ec|$duration")
    return 0
  fi
}

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  TT-Production CI Gate${NC}"
echo -e "${CYAN}  Strict mode: $STRICT${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"

stage 1 "Version Drift" true bash "$SCRIPT_DIR/drift-scan.sh" --root "$ROOT" || true
stage 2 "Shell Syntax Validation" true bash "$SCRIPT_DIR/validate-shell.sh" --root "$ROOT" || true

CONS_CHECK_TARGET="$ROOT/release/version.json"
if [[ -f "$CONS_CHECK_TARGET" ]]; then
  if [[ "$STRICT" == "true" ]]; then
    stage 3 "Cross-File Consistency" true bash "$SCRIPT_DIR/consistency-gate.sh" --root "$ROOT" --strict || true
  else
    stage 3 "Cross-File Consistency" true bash "$SCRIPT_DIR/consistency-gate.sh" --root "$ROOT" || true
  fi
else
  STAGES+=("3|Cross-File Consistency|SKIPPED|0|0")
  NOTES+=("Stage 3 skipped: missing $CONS_CHECK_TARGET")
  [[ "$OVERALL" == "PASS" ]] && OVERALL="PASS_WITH_NOTES"
fi

SEC_ARGS=(--root "$ROOT")
[[ "$STRICT" == "true" ]] && SEC_ARGS+=(--strict)
[[ "${TT_ALLOW_RUNTIME_ENV:-0}" == "1" ]] && SEC_ARGS+=(--allow-runtime-env)
stage 4 "Secret Exposure CI Scan" true bash "$SCRIPT_DIR/secret-scan-ci.sh" "${SEC_ARGS[@]}" || true

if [[ "$SKIP_DOCS" == "true" ]]; then
  NOTES+=("Docs stage skipped (--skip-docs)")
else
  if [[ "$STRICT" == "true" ]]; then
    stage 5 "Documentation Contract" true bash "$SCRIPT_DIR/doc-contract-checker.sh" --root "$ROOT" --strict || true
  else
    stage 5 "Documentation Contract" false bash "$SCRIPT_DIR/doc-contract-checker.sh" --root "$ROOT" || true
  fi
fi

REPORT_FILE="$SCRIPT_DIR/ci-gate-report.txt"
{
  echo "generated_at=$TIMESTAMP"
  if [[ "$STRICT" == "true" ]]; then
    echo "mode=strict"
  else
    echo "mode=standard"
  fi
  echo "verdict=$OVERALL"
  echo "stages=${#STAGES[@]}"
  for s in "${STAGES[@]}"; do
    echo "stage=$s"
  done
  for n in "${NOTES[@]:-}"; do
    [[ -n "$n" ]] && echo "note=$n"
  done
  for b in "${BLOCKERS[@]:-}"; do
    [[ -n "$b" ]] && echo "blocker=$b"
  done
} > "$REPORT_FILE"
echo "ci-gate-report.txt written"

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
if [[ "$OVERALL" == "FAIL" ]]; then
  echo -e "${RED}  VERDICT: FAIL${NC}"
  for b in "${BLOCKERS[@]:-}"; do
    [[ -n "$b" ]] && echo -e "  ${RED}[BLOCK]${NC} $b"
  done
  echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
  exit 1
fi

if [[ "$OVERALL" == "PASS_WITH_NOTES" ]]; then
  echo -e "${YELLOW}  VERDICT: PASS_WITH_NOTES${NC}"
  for n in "${NOTES[@]:-}"; do
    [[ -n "$n" ]] && echo -e "  ${YELLOW}[NOTE]${NC} $n"
  done
else
  echo -e "${GREEN}  VERDICT: PASS${NC}"
fi

echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
exit 0



