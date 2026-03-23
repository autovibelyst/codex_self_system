#!/usr/bin/env bash
# =============================================================================
# bump-version.sh — TT-Production Version Bump Utility (v14.0)
#
# Updates ALL active version markers in the bundle in a single operation.
# Run this before regenerating release artifacts for any new version.
#
# Usage:
#   bash release/bump-version.sh <OLD_VERSION> <NEW_VERSION>
#   bash release/bump-version.sh v14.0 v14.0
#
# What this changes:
#   - All *.sh, *.ps1, *.cmd, *.md, *.yml, *.json, *.toml, *.example files
#   - Skips archival history/ directories and prior RELEASE_NOTES files
#   - Reports total substitutions made and verifies zero residuals
#
# Exit codes:
#   0 = version bump clean
#   1 = residual stale markers detected after bump
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

OLD_VER="${1:-}"
NEW_VER="${2:-}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

if [[ -z "$OLD_VER" || -z "$NEW_VER" ]]; then
  echo "Usage: bash bump-version.sh <OLD_VERSION> <NEW_VERSION>"
  echo "  e.g: bash bump-version.sh v14.0 v14.0"
  exit 1
fi

if [[ "$OLD_VER" == "$NEW_VER" ]]; then
  echo -e "${YELLOW}OLD_VERSION and NEW_VERSION are identical — nothing to do.${NC}"
  exit 0
fi

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  TT-Production Version Bump: $OLD_VER → $NEW_VER${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo ""
echo "  Bundle root: $BUNDLE_ROOT"
echo ""

TOTAL_FILES=0
CHANGED_FILES=0

# Find all active (non-archival) text files
while IFS= read -r f; do
  TOTAL_FILES=$((TOTAL_FILES+1))
  if grep -qF "$OLD_VER" "$f" 2>/dev/null; then
    sed -i "s/${OLD_VER//./\\.}/${NEW_VER}/g" "$f"
    CHANGED_FILES=$((CHANGED_FILES+1))
    echo -e "  ${GREEN}[UPDATED]${NC} ${f#$BUNDLE_ROOT/}"
  fi
done < <(find "$BUNDLE_ROOT" -type f \( \
    -name "*.sh" -o -name "*.ps1" -o -name "*.cmd" \
    -o -name "*.md" -o -name "*.yml" -o -name "*.yaml" \
    -o -name "*.json" -o -name "*.toml" -o -name "*.txt" \
    -o -name "*.env" -o -name "*.example" -o -name "*.template" \
    -o -name "*.ts" \
  \) \
  -not -path "*/history/*" \
  -not -name "RELEASE_NOTES_v[0-9]*" \
  -not -name "*CHANGELOG*" \
  -not -name "root-CHANGELOG.md" \
  2>/dev/null)

echo ""
echo -e "  Files scanned : $TOTAL_FILES"
echo -e "  Files updated : ${GREEN}$CHANGED_FILES${NC}"
echo ""

# Verify — zero residuals
RESIDUALS=$(find "$BUNDLE_ROOT" -type f \( -name "*.sh" -o -name "*.ps1" -o -name "*.md" -o -name "*.yml" -o -name "*.json" \) \
  -not -path "*/history/*" -not -name "*CHANGELOG*" \
  | xargs grep -l "$OLD_VER" 2>/dev/null | wc -l || echo "0")

if [[ "$RESIDUALS" -gt 0 ]]; then
  echo -e "${RED}  [FAIL] $RESIDUALS file(s) still contain $OLD_VER after bump:${NC}"
  find "$BUNDLE_ROOT" -type f \( -name "*.sh" -o -name "*.ps1" -o -name "*.md" -o -name "*.yml" -o -name "*.json" \) \
    -not -path "*/history/*" -not -name "*CHANGELOG*" \
    | xargs grep -l "$OLD_VER" 2>/dev/null | sed "s|$BUNDLE_ROOT/|  |"
  exit 1
else
  echo -e "${GREEN}  ✓ Zero residual $OLD_VER markers — version bump clean.${NC}"
fi

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Version bump complete: $OLD_VER → $NEW_VER${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo ""
echo "  Next steps:"
echo "    1) Update release/version.json with new version"
echo "    2) Write release/RELEASE_NOTES_${NEW_VER}.md"
echo "    3) Run release/release-pipeline.sh to regenerate signoff"
echo ""
