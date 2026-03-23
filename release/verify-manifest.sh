#!/usr/bin/env bash
# =============================================================================
# verify-manifest.sh - TT-Production v14.0
# Verifies bundle-manifest.json truthfulness against actual bundle contents.
# Canonical schema: package_version/tt_version, generated_at, _generator, files.
#
# Usage: bash release/verify-manifest.sh [--root /path/to/bundle] [--strict]
# Exit: 0 = pass, 1 = issues found
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(dirname "$SCRIPT_DIR")}"
STRICT=false
while [[ $# -gt 0 ]]; do
  case "$1" in --root) ROOT="$2"; shift 2 ;; --strict) STRICT=true; shift ;; *) shift ;; esac
done

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
MANIFEST="$ROOT/release/bundle-manifest.json"
VERSION_FILE="$ROOT/release/version.json"
ISSUES=0; WARNINGS=0

pass()  { echo -e "  ${GREEN}[PASS]${NC} $*"; }
fail()  { echo -e "  ${RED}[FAIL]${NC} $*"; ((ISSUES++)) || true; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC} $*"; ((WARNINGS++)) || true; }

echo -e "${CYAN}${BOLD}-- Manifest Verification - TT-Production v14.0 ----${NC}"
[[ -f "$MANIFEST" ]] || { echo -e "${RED}ERROR: bundle-manifest.json not found${NC}"; exit 1; }
[[ -f "$VERSION_FILE" ]] || { echo -e "${RED}ERROR: version.json not found${NC}"; exit 1; }

echo -e "${CYAN}-- 1. Canonical Schema Verification ------------------------${NC}"
HAS_PKG_VER=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1], encoding=\"utf-8-sig\")); print(\"yes\" if any(k in d for k in (\"package_version\",\"tt_version\",\"version\")) else \"no\")" "$MANIFEST" 2>/dev/null)
HAS_GEN_AT=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1], encoding=\"utf-8-sig\")); print(\"yes\" if \"generated_at\" in d else \"no\")" "$MANIFEST" 2>/dev/null)
HAS_GENERATOR=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1], encoding=\"utf-8-sig\")); print(\"yes\" if \"_generator\" in d else \"no\")" "$MANIFEST" 2>/dev/null)
HAS_FILES=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1], encoding=\"utf-8-sig\")); print(\"yes\" if isinstance(d.get(\"files\"), list) else \"no\")" "$MANIFEST" 2>/dev/null)
[[ "$HAS_PKG_VER" == "yes" ]] && pass "manifest has version field alias (package_version/tt_version/version)" || fail "manifest missing version field alias"
[[ "$HAS_GEN_AT" == "yes" ]] && pass "manifest has generated_at" || fail "manifest missing generated_at"
[[ "$HAS_GENERATOR" == "yes" ]] && pass "manifest has _generator" || fail "manifest missing _generator"
[[ "$HAS_FILES" == "yes" ]] && pass "manifest has files[] array" || fail "manifest missing files[] array"

echo -e "${CYAN}-- 2. Version Consistency -----------------------------------${NC}"
MANIFEST_VER=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1], encoding=\"utf-8-sig\")); print(d.get(\"package_version\") or d.get(\"tt_version\") or d.get(\"version\") or \"\")" "$MANIFEST" 2>/dev/null || echo "")
VERSION_JSON_VER=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1], encoding=\"utf-8-sig\"))[\"package_version\"])" "$VERSION_FILE" 2>/dev/null || echo "")
[[ "$MANIFEST_VER" == "$VERSION_JSON_VER" ]] && pass "Manifest version matches version.json: $MANIFEST_VER" || fail "Version mismatch: manifest='$MANIFEST_VER' vs version.json='$VERSION_JSON_VER'"

echo -e "${CYAN}-- 3. Listed Files Exist ------------------------------------${NC}"
MANIFEST_CHECK=$(python3 - "$ROOT" "$MANIFEST" << 'PYEOF'
import json
import os
import sys

root, path = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8-sig') as fh:
    data = json.load(fh)

files = data.get('files', [])
paths = []
for item in files:
    if isinstance(item, dict):
        rel = item.get('path', '')
    else:
        rel = str(item)
    if rel:
        paths.append(rel)

missing = [rel for rel in paths if not os.path.isfile(os.path.join(root, rel.replace('/', os.sep)))]
dups = sorted({rel for rel in paths if paths.count(rel) > 1})
count = data.get('total_files', data.get('file_count'))
if count is None:
    print('FAIL_COUNT')
    sys.exit(0)
print(json.dumps({
    'count': int(count),
    'listed': len(paths),
    'missing': missing,
    'duplicates': dups,
}, ensure_ascii=False))
PYEOF
)
if [[ "$MANIFEST_CHECK" == "FAIL_COUNT" ]]; then
  fail "Manifest missing total_files/file_count"
else
  LISTED=$(python3 -c "import json; d=json.loads('''$MANIFEST_CHECK'''); print(d['listed'])")
  DECLARED=$(python3 -c "import json; d=json.loads('''$MANIFEST_CHECK'''); print(d['count'])")
  MISSING=$(python3 -c "import json; d=json.loads('''$MANIFEST_CHECK'''); print(len(d['missing']))")
  DUPS=$(python3 -c "import json; d=json.loads('''$MANIFEST_CHECK'''); print(len(d['duplicates']))")
  [[ "$DECLARED" == "$LISTED" ]] && pass "Declared file count matches files[] length ($DECLARED)" || fail "Declared count ($DECLARED) != files[] length ($LISTED)"
  [[ "$MISSING" == "0" ]] && pass "All listed files exist on disk" || fail "$MISSING listed file(s) missing on disk"
  [[ "$DUPS" == "0" ]] && pass "No duplicate manifest paths" || fail "$DUPS duplicate manifest path(s) detected"
fi

echo -e "${CYAN}-- 4. Disk Comparison ----------------------------------------${NC}"
LISTED_COUNT=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1], encoding=\"utf-8-sig\")); print(len(d.get(\"files\", [])))" "$MANIFEST" 2>/dev/null || echo 0)
DISK_COUNT=$(find "$ROOT" -type f ! -path "*/.git/*" ! -path "*/__pycache__/*" ! -name "*.tmp" ! -name "*.bak" ! -name "*.swp" | wc -l)
echo -e "  ${CYAN}files[] length: $LISTED_COUNT | disk count: $DISK_COUNT${NC}"
[[ "$LISTED_COUNT" == "$DISK_COUNT" ]] && pass "Manifest covers all files on disk" || warn "Manifest/files on disk differ by $((DISK_COUNT - LISTED_COUNT))"

echo -e "${CYAN}-- 5. Required Root Files ------------------------------------${NC}"
REQ_STATE=$(python3 - "$ROOT" "$MANIFEST" << 'PYEOF'
import json
import os
import sys

root, path = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8-sig') as fh:
    data = json.load(fh)
required = data.get('required_root_files', [])
missing = [rel for rel in required if not os.path.isfile(os.path.join(root, rel.replace('/', os.sep)))]
print(json.dumps({'count': len(required), 'missing': missing}, ensure_ascii=False))
PYEOF
)
REQ_COUNT=$(python3 -c "import json; d=json.loads('''$REQ_STATE'''); print(d['count'])")
REQ_MISSING=$(python3 -c "import json; d=json.loads('''$REQ_STATE'''); print(len(d['missing']))")
if [[ "$REQ_COUNT" == "0" ]]; then
  warn "Manifest has no required_root_files list"
else
  [[ "$REQ_MISSING" == "0" ]] && pass "All $REQ_COUNT required root files exist" || fail "$REQ_MISSING required root file(s) missing"
fi

echo ""
echo -e "${CYAN}${BOLD}=== Manifest Verification Summary ===${NC}"
echo "  Issues:   $ISSUES"
echo "  Warnings: $WARNINGS"
echo ""
if [[ $ISSUES -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}  MANIFEST VERIFICATION: PASS${NC}"
  exit 0
fi

echo -e "${RED}${BOLD}  MANIFEST VERIFICATION: FAIL - $ISSUES issue(s)${NC}"
[[ "$STRICT" == "true" ]] && exit 1
exit 1


