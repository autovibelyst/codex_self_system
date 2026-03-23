#!/usr/bin/env bash
# lint-docs.sh — TT-Production v14.0
# Scans documentation for stale references, dead script mentions, and
# outdated workflow markers. Used in release pipeline and CI.
#
# Exit: 0 = clean, 1 = issues found
# Usage: bash release/lint-docs.sh [--root /path/to/bundle]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(dirname "$SCRIPT_DIR")}"
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2 ;; *) shift ;; esac; done

DOCS_DIR="$ROOT/tt-core/docs"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
FAILURES=0; WARNINGS=0

fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAILURES++)) || true; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; ((WARNINGS++)) || true; }
pass() { echo -e "  ${GREEN}[OK]${NC}  $1"; }

echo -e "${CYAN}TT-Production Doc Linter — v14.0${NC}"
echo ""

# ── 1. Stale version markers in normative docs ────────────────────────────────
echo "── 1. Stale version markers ──────────────────────────────────────────"
while IFS= read -r doc; do
  [[ "$doc" == */history/* || "$doc" == */archive/* ]] && continue
  # UPGRADE_GUIDE.md is exempted from ancestor-version checks (it legitimately
  # documents upgrade paths from older releases and must reference old versions)
  [[ "$(basename "$doc")" == "UPGRADE_GUIDE.md" || "$(basename "$doc")" == "CHANGELOG.md" ]] && continue
  FNAME=$(basename "$doc")
  while IFS= read -r pattern; do
    if grep -ql "$pattern" "$doc" 2>/dev/null; then
      fail "$FNAME: contains stale version '$pattern'"
    fi
  done < <(echo -e "v6.7.2.9\nv6.7.5\nv6.7.6\nv6.8.0\nv6.8.1\nv6.8.2\nv6.8.3\nv6.8.6\nv6.8.8")
done < <(find "$DOCS_DIR" -name "*.md")

# ── 2. Dead script references ─────────────────────────────────────────────────
echo "── 2. Dead script references ─────────────────────────────────────────"
SCRIPTS_LINUX="$ROOT/tt-core/scripts-linux"
SCRIPTS_WIN="$ROOT/tt-core/scripts"

# Extract script names mentioned in docs and verify they exist
while IFS= read -r doc; do
  [[ "$doc" == */history/* ]] && continue
  FNAME=$(basename "$doc")
  # Find patterns like: bash scripts-linux/SCRIPT.sh or .\scripts\SCRIPT.ps1
  while IFS= read -r script_ref; do
    # bash scripts-linux/X.sh pattern
    if [[ "$script_ref" =~ scripts-linux/([a-zA-Z0-9_-]+\.sh) ]]; then
      SNAME="${BASH_REMATCH[1]}"
      [[ -f "$SCRIPTS_LINUX/$SNAME" ]] || warn "$FNAME: references scripts-linux/$SNAME which does not exist"
    fi
    # .\scripts\X.ps1 pattern
    if [[ "$script_ref" =~ [Ss]cripts[/\\]([a-zA-Z0-9_.-]+\.ps1) ]]; then
      SNAME="${BASH_REMATCH[1]}"
      [[ -f "$SCRIPTS_WIN/$SNAME" ]] || warn "$FNAME: references scripts/$SNAME which does not exist"
    fi
  done < <(grep -oE '(scripts-linux/[a-zA-Z0-9_-]+\.sh|[Ss]cripts[/\\][a-zA-Z0-9_.-]+\.ps1)' "$doc" 2>/dev/null || true)
done < <(find "$DOCS_DIR" -name "*.md")

# ── 3. Conflicting tunnel token instructions ──────────────────────────────────
echo "── 3. Tunnel token placement ─────────────────────────────────────────"
# Docs must not tell users to put CF_TUNNEL_TOKEN in core .env
while IFS= read -r doc; do
  FNAME=$(basename "$doc")
  if grep -q "CF_TUNNEL_TOKEN" "$doc" 2>/dev/null; then
    # It's OK to mention it, but must point to tunnel .env only
    if grep -q "compose/tt-core/.env" "$doc" 2>/dev/null && \
       grep -A2 "CF_TUNNEL_TOKEN" "$doc" | grep "compose/tt-core" | grep -vq "must never\|never\|not\|forbidden\|wrong"; then
      fail "$FNAME: CF_TUNNEL_TOKEN instruction may point to wrong .env file (must be compose/tt-tunnel/.env)"
    else
      pass "$FNAME: CF_TUNNEL_TOKEN reference looks correct"
    fi
  fi
done < <(find "$DOCS_DIR" -name "*.md")

# ── 4. Generated file disclaimers ─────────────────────────────────────────────
echo "── 4. Generated file disclaimers ────────────────────────────────────"
for gf in \
  "$ROOT/tt-core/config/public-exposure.policy.json" \
  "$ROOT/release/exposure-summary.md" \
  "$ROOT/release/exposure-summary.json" \
  "$ROOT/release/signoff.json"; do
  if [[ -f "$gf" ]]; then
    FNAME=$(basename "$gf")
    if grep -qi "GENERATED\|do not edit" "$gf" 2>/dev/null; then
      pass "$FNAME: has GENERATED disclaimer"
    else
      fail "$FNAME: missing GENERATED disclaimer — may be mistaken for editable source"
    fi
  fi
done

# ── 5. Normative docs reference correct scripts ───────────────────────────────
echo "── 5. Core normative doc existence ─────────────────────────────────"
REQUIRED_DOCS=(
  "BACKUP.md" "SECURITY.md" "UPGRADE_GUIDE.md" "CREDENTIAL_ROTATION.md"
  "DR_PLAYBOOK.md" "PORTS.md" "SERVICES.md" "TUNNEL.md" "QUICKSTART.md"
  "TROUBLESHOOTING.md" "ENV-STRATEGY.md" "AUTHORITY_MODEL.md"
)
for doc in "${REQUIRED_DOCS[@]}"; do
  [[ -f "$DOCS_DIR/$doc" ]] && pass "$doc: present" || fail "$doc: MISSING from docs/"
done

# ── 6. RELEASE_AUDIT_SUMMARY must not contain static "needs runtime verification" ──
echo "── 6. Release audit clean ───────────────────────────────────────────"
AUDIT="$ROOT/RELEASE_AUDIT_SUMMARY.md"
if [[ -f "$AUDIT" ]]; then
  if grep -qi "needs runtime verification" "$AUDIT"; then
    fail "RELEASE_AUDIT_SUMMARY.md: still contains 'needs runtime verification' — outdated claim"
  else
    pass "RELEASE_AUDIT_SUMMARY.md: no stale verification warnings"
  fi
  if grep -qi "validation_state.*production.ready" "$AUDIT"; then
    warn "RELEASE_AUDIT_SUMMARY.md: contains static 'production-ready' claim — consider pointing to signoff.json"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
if [[ $FAILURES -gt 0 ]]; then
  echo -e "${RED}  Doc lint FAILED — $FAILURES failure(s), $WARNINGS warning(s)${NC}"
  exit 1
elif [[ $WARNINGS -gt 0 ]]; then
  echo -e "${YELLOW}  Doc lint PASSED with $WARNINGS warning(s)${NC}"
else
  echo -e "${GREEN}  Doc lint PASSED — 0 failures, 0 warnings${NC}"
fi


