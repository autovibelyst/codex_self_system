#!/usr/bin/env bash
# =============================================================================
# release-pipeline.sh — TT-Production v14.0 Release Pipeline (8 Stages)
#
# EXIT: 0 = PASS or PASS_WITH_NOTES (export allowed)
#       1 = FAIL (blocking gate failed)
#       2 = BLOCKED (pipeline could not complete)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/version.sh"

ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRY_RUN="${1:-}"
STAGES=()
NOTES=()
BLOCKERS=()
OVERALL_VERDICT="PASS"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

run_stage() {
  local id="$1" name="$2" script="$3" blocking="${4:-true}"
  local start=$(($(date +%s%3N)))
  echo ""
  echo -e "${CYAN}── Stage $id: $name ──────────────────────────────────────${NC}"

  if [[ -f "$SCRIPT_DIR/$script" ]]; then
    if bash "$SCRIPT_DIR/$script" 2>&1; then
      duration=$(( $(date +%s%3N) - start ))
      echo -e "  ${GREEN}[PASS]${NC} Stage $id complete (${duration}ms)"
      STAGES+=("{\"stage_id\":$id,\"stage_name\":\"$name\",\"result\":\"PASS\",\"exit_code\":0,\"duration_ms\":$duration,\"message\":null}")
    else
      ec=$?
      duration=$(( $(date +%s%3N) - start ))
      echo -e "  ${RED}[FAIL]${NC} Stage $id failed (exit $ec)"
      if [[ "$blocking" == "true" ]]; then
        BLOCKERS+=("Stage $id ($name) failed")
        OVERALL_VERDICT="FAIL"
        STAGES+=("{\"stage_id\":$id,\"stage_name\":\"$name\",\"result\":\"FAIL\",\"exit_code\":$ec,\"duration_ms\":$duration,\"message\":\"blocking failure\"}")
      else
        NOTES+=("Stage $id ($name) had warnings — non-blocking")
        [[ "$OVERALL_VERDICT" == "PASS" ]] && OVERALL_VERDICT="PASS_WITH_NOTES"
        STAGES+=("{\"stage_id\":$id,\"stage_name\":\"$name\",\"result\":\"WARN\",\"exit_code\":$ec,\"duration_ms\":$duration,\"message\":\"non-blocking warning\"}")
      fi
    fi
  else
    echo -e "  ${YELLOW}[SKIP]${NC} $script not found — skipping"
    STAGES+=("{\"stage_id\":$id,\"stage_name\":\"$name\",\"result\":\"SKIPPED\",\"exit_code\":0,\"duration_ms\":0,\"message\":\"script not found\"}")
    [[ "$blocking" == "true" ]] && NOTES+=("Stage $id ($name) was skipped")
  fi
}

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  TT-Production Release Pipeline — v${TT_VERSION}${NC}"
echo -e "${CYAN}  $(date -u)${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"

# Stage 0 — Version Drift Gate (MUST PASS FIRST)
run_stage 0 "Version Drift Gate"       "drift-scan.sh"        "true"
[[ "$OVERALL_VERDICT" == "FAIL" ]] && { echo -e "\n${RED}PIPELINE ABORTED at Stage 0 — version drift detected${NC}"; exit 1; }

# Stage 1 — Schema Consistency Gate
run_stage 1 "Schema Consistency"       "consistency-gate.sh"  "true"

# Stage 2 — Image Governance Gate
run_stage 2 "Image Governance"         "generate-image-pins.sh" "true"

# Stage 3 — Secret Scan Gate
run_stage 3 "Secret Scan"              "secret-scan.sh"       "true"

# Stage 4 — Shell Validation Gate
run_stage 4 "Shell Validation"         "validate-shell.sh"    "true"

# Stage 5 — Documentation Contract (non-blocking for addon gaps)
run_stage 5 "Documentation Contract"   "doc-contract-checker.sh" "false"

# Stage 6 — Exposure Policy Regeneration
run_stage 6 "Exposure Policy"          "generate-exposure.sh" "true"

# Stage 7 — Bundle Assembly
run_stage 7 "Bundle Assembly"          "package-export.sh"    "true"

# Stage 8 — Signoff Generation
echo ""
echo -e "${CYAN}── Stage 8: Signoff Generation ────────────────────────${NC}"

EXPORT_ALLOWED="false"
HANDOFF_ALLOWED="false"
[[ "$OVERALL_VERDICT" == "PASS" || "$OVERALL_VERDICT" == "PASS_WITH_NOTES" ]] && EXPORT_ALLOWED="true" && HANDOFF_ALLOWED="true"

python3 - << PYEOF
import json
stages_raw = [$(printf "'%s'," "${STAGES[@]}" | sed 's/,$//')]
stages = []
for r in stages_raw:
    r = r.strip()
    if r:
        try: stages.append(json.loads(r))
        except: pass

notes    = $(python3 -c "import json; print(json.dumps([$(printf '"%s",' "${NOTES[@]:-}" | sed 's/,$//')]))" 2>/dev/null || echo "[]")
blockers = $(python3 -c "import json; print(json.dumps([$(printf '"%s",' "${BLOCKERS[@]:-}" | sed 's/,$//')]))" 2>/dev/null || echo "[]")

signoff = {
    "_schema": "tt-signoff/v1",
    "_generator": "release/release-pipeline.sh",
    "generated_at": "$TIMESTAMP",
    "tt_version": "$TT_VERSION",
    "verdict": "$OVERALL_VERDICT",
    "export_allowed": $EXPORT_ALLOWED,
    "handoff_allowed": $HANDOFF_ALLOWED,
    "stages": stages,
    "notes": notes,
    "blockers": blockers
}
with open("$SCRIPT_DIR/signoff.json", "w") as f:
    json.dump(signoff, f, indent=2)
print("  signoff.json written")
PYEOF

# Final verdict
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
case "$OVERALL_VERDICT" in
  PASS)
    echo -e "${GREEN}  VERDICT: PASS — Export and handoff permitted${NC}"
    EXIT_CODE=0 ;;
  PASS_WITH_NOTES)
    echo -e "${YELLOW}  VERDICT: PASS_WITH_NOTES — Export permitted, notes attached${NC}"
    for n in "${NOTES[@]}"; do echo -e "  ${YELLOW}[NOTE]${NC} $n"; done
    EXIT_CODE=0 ;;
  FAIL)
    echo -e "${RED}  VERDICT: FAIL — Export BLOCKED${NC}"
    for b in "${BLOCKERS[@]}"; do echo -e "  ${RED}[BLOCK]${NC} $b"; done
    EXIT_CODE=1 ;;
  BLOCKED)
    echo -e "${RED}  VERDICT: BLOCKED — Pipeline incomplete${NC}"
    EXIT_CODE=2 ;;
esac
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo ""
exit $EXIT_CODE
