#!/usr/bin/env bash
# secret-scan.sh — TT-Production v14.0
# Standalone secret and forbidden-file scanner for the delivery bundle.
# Called by release-pipeline.sh Stage 0. Can also be run independently.
# Exit: 0 = CLEAN, 1 = violations found

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(dirname "$SCRIPT_DIR")}"
VIOLATIONS=0

while [[ $# -gt 0 ]]; do
  case "$1" in --root) ROOT="$2"; shift 2 ;; *) shift ;; esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
echo "Secret & Forbidden-File Scan — $(date +%Y-%m-%dT%H:%M:%SZ)"
echo "Scanning: $ROOT"
echo ""

check_fail() { echo -e "  ${RED}[FAIL] $1${NC}"; ((VIOLATIONS++)) || true; }
check_pass() { echo -e "  ${GREEN}[OK]   $1${NC}"; }
check_warn() { echo -e "  ${YELLOW}[WARN] $1${NC}"; }

# 1. No .git
find "$ROOT" -name ".git" -type d 2>/dev/null | grep -q . \
  && check_fail ".git directory present in bundle" \
  || check_pass ".git not present"

# 2. No real .env runtime files
REAL_ENV=$(find "$ROOT" \( -name "*.env" -o -name ".env" -o -name ".env.*" \) \
  -not -name "*.example" -not -name "*.template" \
  -not -name "env.addon.template.env" 2>/dev/null || true)
[[ -n "$REAL_ENV" ]] && { check_fail "Real .env file(s): $REAL_ENV"; } \
  || check_pass "No real .env files"

# 3. No key/cert/credential files
KEYS=$(find "$ROOT" \( -name "*.pem" -o -name "*.key" -o -name "*.pfx" \
  -o -name "*.secrets" -o -name "*.token" -o -name "id_rsa" \) \
  -not -path "*/.git/*" 2>/dev/null || true)
[[ -n "$KEYS" ]] && check_fail "Key/cert files: $KEYS" || check_pass "No key/cert files"

# 4. Content scan for high-entropy patterns
HITS=0
while IFS= read -r f; do
  [[ "$f" == *.example ]] && continue
  [[ "$f" == *.template ]] && continue
  [[ "$(basename "$f")" == "redis.conf" ]] && continue
  if grep -qE '(Bearer [A-Za-z0-9_\-\.]{40,}|eyJ[A-Za-z0-9_\-]{100,})' "$f" 2>/dev/null; then
    check_warn "Probable secret pattern in: $(realpath --relative-to="$ROOT" "$f")"
    ((HITS++)) || true
  fi
done < <(find "$ROOT" -type f \( -name "*.json" -o -name "*.yml" -o -name "*.sh" \
  -o -name "*.ps1" -o -name "*.md" \) -not -path "*/.git/*" -not -path "*/history/*" 2>/dev/null)
[[ $HITS -eq 0 ]] && check_pass "Content scan: no high-entropy patterns" \
  || check_warn "$HITS file(s) flagged — manual review required"

# 5. No dev residue
RESIDUE=$(find "$ROOT" \( -name "*.tmp" -o -name "*.bak" -o -name "*.log" \
  -o -name ".DS_Store" -o -name "Thumbs.db" -o -name "*.pyc" \
  -o -name "SCRATCH*" \) -not -path "*/.git/*" 2>/dev/null || true)
[[ -n "$RESIDUE" ]] && check_fail "Dev residue: $RESIDUE" || check_pass "No dev/temp residue"

echo ""
if [[ $VIOLATIONS -eq 0 ]]; then
  echo -e "${GREEN}SCAN RESULT: CLEAN — no violations found${NC}"
  exit 0
else
  echo -e "${RED}SCAN RESULT: $VIOLATIONS VIOLATION(S) — bundle must not be shipped${NC}"
  exit 1
fi

