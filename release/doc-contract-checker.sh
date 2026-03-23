#!/usr/bin/env bash
# =============================================================================
# TT-Production — Documentation Contract Gate — v14.0
# Verifies that every script, file, and path referenced in documentation
# actually exists in the package. Prevents dead reference regressions.
#
# Usage:
#   bash release/doc-contract-checker.sh [--root /path] [--strict]
#
# Exit codes:
#   0 = all contract checks passed
#   1 = one or more referenced items are missing (RELEASE BLOCKED)
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STRICT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)   ROOT="$2";  shift 2 ;;
    --strict) STRICT=true; shift  ;;
    *)        shift ;;
  esac
done

FAILS=0; PASSES=0; WARNS=0

pass() { PASSES=$((PASSES+1)); echo -e "  \033[32m[PASS]\033[0m $*"; }
fail() { FAILS=$((FAILS+1));   echo -e "  \033[31m[FAIL]\033[0m $*"; }
warn() {
  WARNS=$((WARNS+1))
  echo -e "  \033[1;33m[WARN]\033[0m $*"
  [[ "$STRICT" == "true" ]] && FAILS=$((FAILS+1))
}

PKG_VER=$(python3 -c "import json; print(json.load(open('$ROOT/release/version.json'))['package_version'])" 2>/dev/null || echo "v14.0")

echo ""
echo -e "\033[36m── Doc Contract Gate — TT-Production $PKG_VER ─────────────\033[0m"
echo ""

# ── Phase 1: Script references in documentation ───────────────────────────────
echo "Phase 1: Script references in documentation"
SCRIPTS_MENTIONED=$(grep -rh 'scripts-linux/[a-zA-Z0-9_-]*\.sh' \
  "$ROOT/tt-core/docs/" "$ROOT/MASTER_GUIDE.md" "$ROOT/FULL_PACKAGE_GUIDE.md" \
  2>/dev/null | grep -oP 'scripts-linux/[a-zA-Z0-9_-]+\.sh' | sort -u || true)

for ref in $SCRIPTS_MENTIONED; do
  full_path="$ROOT/tt-core/$ref"
  if [[ -f "$full_path" ]]; then
    pass "$ref exists"
  else
    fail "$ref — mentioned in docs but NOT FOUND at $full_path"
  fi
done

# PowerShell scripts referenced in docs
PS_MENTIONED=$(grep -rh 'scripts\\[a-zA-Z0-9_\\-]*\.ps1' \
  "$ROOT/tt-core/docs/" "$ROOT/MASTER_GUIDE.md" 2>/dev/null | \
  grep -oP 'scripts\\\\[a-zA-Z0-9_\\\\.-]+' | sort -u || true)
for ref in $PS_MENTIONED; do
  ref_unix="${ref//\\//}"
  [[ -f "$ROOT/tt-core/$ref_unix" ]] && pass "$ref exists" || warn "$ref mentioned but not found"
done

# ── Phase 2: Key file references ──────────────────────────────────────────────
echo ""
echo "Phase 2: Key file existence"
KEY_FILES=(
  "tt-core/compose/tt-core/docker-compose.yml"
  "tt-core/scripts-linux/preflight-check.sh"
  "tt-core/scripts-linux/init.sh"
  "tt-core/scripts-linux/backup.sh"
  "tt-core/scripts-linux/smoke-test.sh"
  "tt-core/scripts-linux/start-core.sh"
  "release/signoff.json"
  "release/version.json"
  "release/smoke-results.json"
  "COMMERCIAL_HANDOFF.md"
  "MASTER_GUIDE.md"
  "LICENSE.md"
  "RELEASE_NOTES_${PKG_VER}.md"
  "tt-core/docs/KNOWN_LIMITATIONS.md"
  "tt-core/docs/QA-LINUX.md"
  "tt-core/docs/IMAGE_PINNING.md"
  "tt-core/docs/SECRET_MANAGEMENT.md"
  "release/validate-shell.sh"
  "release/doc-contract-checker.sh"
)
for f in "${KEY_FILES[@]}"; do
  [[ -f "$ROOT/$f" ]] && pass "$f" || fail "$f — MISSING"
done

# ── Phase 3: No stale RELEASE_NOTES refs in active files ─────────────────────
echo ""
echo "Phase 3: No stale RELEASE_NOTES refs in active non-history files"
_STALE_COUNT=0
while IFS= read -r -d '' _f; do
  [[ "$_f" == *"/release/history/"* ]] && continue
  [[ "$_f" == *"/.git/"* ]] && continue
  _fn=$(basename "$_f")
  # Allow audit summaries and changelogs (they document bug history)
  case "$_fn" in RELEASE_AUDIT_SUMMARY.md|CHANGELOG.md) continue ;; esac
  # File contains a reference to some old release notes
  if grep -q "RELEASE_NOTES_v" "$_f" 2>/dev/null; then
    # If it also references the current version, it is OK
    if grep -q "RELEASE_NOTES_${PKG_VER}" "$_f" 2>/dev/null; then
      continue
    fi
    # Check if it is clearly a historical/prose context
    if grep -qi "prior version\|previous release\|history\|changelog" "$_f" 2>/dev/null; then
      continue
    fi
    fail "Stale RELEASE_NOTES ref (no current-version ref) in: ${_f#$ROOT/}"
    _STALE_COUNT=$((_STALE_COUNT+1))
  fi
done < <(find "$ROOT" -type f \( -name "*.md" -o -name "*.sh" \) -print0 2>/dev/null)
[[ $_STALE_COUNT -eq 0 ]] && pass "No stale RELEASE_NOTES refs in active files"

# ── Phase 4: Version string consistency ──────────────────────────────────────
echo ""
echo "Phase 4: Version consistency"
STALE_VERSIONS=$(grep -rl "Version: TT-Production v1[01]\." \
  "$ROOT/tt-core/env/" "$ROOT/tt-core/compose/" "$ROOT/tt-supabase/env/" \
  2>/dev/null | wc -l || echo 0)
STALE_VERSIONS="${STALE_VERSIONS//[[:space:]]/}"
if [[ "$STALE_VERSIONS" -eq 0 ]]; then
  pass "No stale version headers in .env.example files"
else
  fail "$STALE_VERSIONS .env.example files have stale version headers"
fi

# ── Phase 5: COMMERCIAL_HANDOFF status ───────────────────────────────────────
echo ""
echo "Phase 5: Commercial handoff status"
if grep -q "General Availability" "$ROOT/COMMERCIAL_HANDOFF.md" 2>/dev/null; then
  pass "COMMERCIAL_HANDOFF.md says General Availability"
else
  fail "COMMERCIAL_HANDOFF.md does not say General Availability"
fi
if grep -q "Release Candidate" "$ROOT/COMMERCIAL_HANDOFF.md" 2>/dev/null; then
  fail "COMMERCIAL_HANDOFF.md still contains 'Release Candidate' — RELEASE BLOCKED"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "\033[36m──────────────────────────────────────────────────────\033[0m"
echo "  Results: $PASSES PASS, $WARNS WARN, $FAILS FAIL"

if [[ $FAILS -gt 0 ]]; then
  echo -e "\033[31m  DOC CONTRACT: FAIL ($FAILS failure(s) — release blocked)\033[0m"
  exit 1
fi

echo -e "\033[32m  DOC CONTRACT: PASS\033[0m"
echo ""
