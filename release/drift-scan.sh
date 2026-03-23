#!/usr/bin/env bash
# =============================================================================
# drift-scan.sh — TT-Production v14.0 Package Identity Drift Scanner
# Version: reads from release/lib/version.sh
#
# SCOPE: Detects stale PACKAGE IDENTITY strings in active files.
#        Does NOT flag Docker image versions, dependency versions,
#        third-party software versions, or documentation examples
#        unless they explicitly carry a stale TT-Production package identity.
#
# WHAT IT SCANS FOR:
#   - "TT-Production v<old>" in any form
#   - "package_version: v<old>" in JSON/YAML
#   - "Version: TT-Production v<old>" in env headers
#   NOT: Docker image tags, npm versions, PostgreSQL versions, etc.
#
# EXIT: 0 = no package identity drift detected
#       1 = drift found (release blocker)
#       2 = tool error
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/version.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VIOLATIONS=()
EXIT_CODE=0

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; GRAY='\033[0;37m'; NC='\033[0m'

# Paths excluded from drift scan (historical references are allowed here)
EXCLUDED_PATHS=(
  "release/history/"
  "release/CHANGELOG.md"
  "tt-core/release/CHANGELOG.md"
  "tt-supabase/release/CHANGELOG.md"
  "tt-core/docs/UPGRADE_GUIDE.md"
  "tt-core/docs/UPGRADE.md"
  "RELEASE_NOTES_${TT_VERSION}.md"
  ".git/"
  "__pycache__/"
)

is_excluded() {
  local file="$1"
  for excl in "${EXCLUDED_PATHS[@]}"; do
    [[ "$file" == *"$excl"* ]] && return 0
  done
  return 1
}

# Package identity patterns to scan for (case-insensitive where appropriate)
# These patterns specifically identify TT-Production package version identity
# NOT general semver patterns
PATTERNS=(
  'TT-Production v[0-9]+\.[0-9]+'      # "TT-Production vX.Y"
  'TT-Production-v[0-9]+\.[0-9]+'      # "TT-Production-vX.Y"
  '"package_version"[[:space:]]*:[[:space:]]*"v[0-9]+\.[0-9]+'  # JSON package_version
  'package_version:[[:space:]]*v[0-9]+\.[0-9]+'                  # YAML package_version
  'Version:[[:space:]]*TT-Production v[0-9]+\.[0-9]+'           # env file headers
  'Version:[[:space:]]*v[0-9]+\.[0-9]+[[:space:]]*$'            # standalone version header
)

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  TT-Production Package Identity Drift Scan${NC}"
echo -e "${CYAN}  Canonical: ${TT_VERSION}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GRAY}Scope: Package identity strings only (not image tags or dependency versions)${NC}"
echo ""

while IFS= read -r -d '' file; do
  is_excluded "${file#$REPO_ROOT/}" && continue

  # Only scan text-based files that would carry package identity
  [[ "$file" =~ \.(sh|ps1|cmd|json|md|yml|yaml|env|txt|conf|toml|py|js)$ ]] || continue

  for pattern in "${PATTERNS[@]}"; do
    while IFS= read -r match_line; do
      [[ -z "$match_line" ]] && continue
      lineno=$(echo "$match_line" | cut -d: -f1)
      content=$(echo "$match_line" | cut -d: -f2-)

      # Extract the version that was found
      found_ver=$(echo "$content" | grep -Eo 'v[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || echo "")
      [[ -z "$found_ver" ]] && continue

      # Only flag if it's NOT the canonical version
      # Strip patch level for comparison (v13.0.1 and v13.0 are same major.minor)
      found_major_minor=$(echo "$found_ver" | grep -Eo 'v[0-9]+\.[0-9]+')
      canonical_major_minor=$(echo "$TT_VERSION" | grep -Eo 'v[0-9]+\.[0-9]+')

      if [[ "$found_major_minor" != "$canonical_major_minor" ]]; then
        rel_file="${file#$REPO_ROOT/}"
        VIOLATIONS+=("$rel_file:$lineno — stale '$found_ver' in package identity context (canonical: $TT_VERSION)")
        EXIT_CODE=1
      fi
    done < <(grep -En "$pattern" "$file" 2>/dev/null || true)
  done

done < <(find "$REPO_ROOT" -not -path "*/.git/*" -not -path "*/__pycache__/*" -type f -print0)

if [[ ${#VIOLATIONS[@]} -eq 0 ]]; then
  echo -e "  ${GREEN}[PASS]${NC}  No package identity drift detected."
  echo -e "  ${GRAY}        (Image tags, dependency versions, and third-party software versions are not scanned)${NC}"
else
  echo -e "  ${RED}[FAIL]${NC}  Package identity drift — ${#VIOLATIONS[@]} violation(s):"
  for v in "${VIOLATIONS[@]}"; do
    echo -e "    ${RED}✗${NC}  $v"
  done
  echo ""
  echo -e "  ${CYAN}Fix:${NC} Use shared version reader — never hardcode package version:"
  echo "    Bash:  source release/lib/version.sh && echo \$TT_VERSION"
  echo "    PS:    . release/lib/Version.ps1 ; \$TT_VERSION"
fi

echo ""
exit $EXIT_CODE


