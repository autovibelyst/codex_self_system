#!/usr/bin/env bash
# =============================================================================
# consistency-gate.sh — TT-Production Cross-File v14.0 Consistency Gate
# Version: reads from release/version.json via release/lib/version.sh
#
# Detects cross-file drift, authority ambiguity, stale identity, and
# naming mismatches BEFORE the release pipeline runs generation stages.
# Must pass before generate-signoff.sh, generate-exposure.sh,
# or bundle-manifest regeneration.
#
# Usage:
#   bash release/consistency-gate.sh
#   bash release/consistency-gate.sh --root /path/to/bundle
#   bash release/consistency-gate.sh --strict
#
# Exit codes:
#   0 = all checks passed (warnings may be present)
#   1 = one or more blocking issues found
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(dirname "$SCRIPT_DIR")}"
STRICT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)   ROOT="$2"; shift 2 ;;
    --strict) STRICT=true; shift ;;
    *)        shift ;;
  esac
done
RUNTIME_ENV_LIB="$ROOT/tt-core/scripts-linux/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"

# Load canonical version from single source of truth
source "$SCRIPT_DIR/lib/version.sh"
PKG_VER="$TT_VERSION"  # e.g. "v14.0"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ISSUES=0; WARNINGS=0; PASSES=0

pass() { ((PASSES++)) || true; echo -e "  ${GREEN}[PASS]${NC} $*"; }
fail() { ((ISSUES++)) || true; echo -e "  ${RED}[FAIL]${NC} $*"; }
warn() {
  ((WARNINGS++)) || true
  echo -e "  ${YELLOW}[WARN]${NC} $*"
  [[ "$STRICT" == "true" ]] && ((ISSUES++)) || true
}

echo ""
echo -e "${CYAN}${BOLD}TT-Production ${PKG_VER} v14.0 Consistency Gate${NC}"
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo ""

VERSION_FILE="$ROOT/release/version.json"
SIGNOFF_FILE="$ROOT/release/signoff.json"
MANIFEST_FILE="$ROOT/release/bundle-manifest.json"
SELECT_FILE="$ROOT/tt-core/config/services.select.json"
CATALOG_FILE="$ROOT/tt-core/config/service-catalog.json"
DC_FILE="$ROOT/tt-core/compose/tt-core/docker-compose.yml"

# ── 1. version.json authority model ─────────────────────────────────────────
echo "── 1. version.json Authority Model"
if [[ -f "$VERSION_FILE" ]]; then
  python3 - "$VERSION_FILE" << 'PYEOF'
import json, sys
path = sys.argv[1]
d = json.load(open(path, encoding='utf-8'))
errors = []
required = ['product_name','package_version','bundle_name','release_channel',
            'release_stage','base_version','release_date','ancestry']
for f in required:
    if f not in d:
        errors.append(f"Missing required field: '{f}'")
# Must NOT have verdict fields
forbidden = ['pipeline_verdict','production_ready','release_authorized',
             'validation_state','readiness']
for f in forbidden:
    if f in d:
        errors.append(f"version.json has verdict field '{f}' — must be identity-only")
pkg = d.get('package_version','?')
if not pkg.startswith('v'):
    errors.append(f"package_version '{pkg}' must start with 'v' prefix")
if errors:
    for e in errors: print(f"  GATE_FAIL: {e}")
    sys.exit(1)
else:
    print(f"  GATE_PASS: version.json identity-only — package_version={pkg}")
    print(f"  GATE_PASS: product_name={d['product_name']}, base_version={d['base_version']}")
    tail = str(d.get('ancestry',''))[-20:].replace('→','->')
    print(f"  GATE_PASS: ancestry tail: ...{tail}")
PYEOF
  [[ $? -eq 0 ]] && PASSES=$((PASSES+3)) || { ISSUES=$((ISSUES+1)); }
else
  fail "release/version.json not found"
fi

# ── 2. Version contract consistency ─────────────────────────────────────────
echo "── 2. Version Contract Consistency"

# services.select.json meta.package_version
SEL_VER=$(python3 - "$SELECT_FILE" << 'PYEOF' 2>/dev/null || echo "error"
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    d = json.load(f)
print(d.get('meta',{}).get('package_version','none'))
PYEOF
)
if [[ "$SEL_VER" == "$PKG_VER" ]]; then
  pass "services.select.json meta.package_version = $PKG_VER"
else
  fail "services.select.json meta.package_version = '$SEL_VER' (expected $PKG_VER)"
fi

# service-catalog.json _comment
CATALOG_COMMENT=$(python3 - "$CATALOG_FILE" << 'PYEOF' 2>/dev/null || echo ""
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    d = json.load(f)
print(d.get('_comment',''))
PYEOF
)
if [[ "$CATALOG_COMMENT" == *"$PKG_VER"* ]]; then
  pass "service-catalog.json _comment contains $PKG_VER"
else
  warn "service-catalog.json _comment does not reference $PKG_VER: '$CATALOG_COMMENT'"
fi

# ENV.EXAMPLE version headers
ENV_FILES=(
  "tt-core/env/.env.example"
  "tt-core/env/tunnel.env.example"
  "tt-core/compose/tt-core/.env.example"
  "tt-core/compose/tt-tunnel/.env.example"
  "tt-supabase/env/tt-supabase.env.example"
)
ENV_FAIL=0
for ef in "${ENV_FILES[@]}"; do
  fp="$ROOT/$ef"
  if [[ -f "$fp" ]]; then
    if grep -q "$PKG_VER" "$fp" 2>/dev/null; then
      pass "$(basename $ef): header = $PKG_VER"
    else
      fail "$(basename $ef): stale or missing version header (expected $PKG_VER)"
      ENV_FAIL=1
    fi
  else
    warn "$(basename $ef): file not found"
  fi
done

# ── 3. Signoff is readiness-only ─────────────────────────────────────────────
echo "── 3. Signoff File Authority"
if [[ -f "$SIGNOFF_FILE" ]]; then
  python3 - "$SIGNOFF_FILE" "$PKG_VER" << 'PYEOF'
import json, sys
path, expected_pkg = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as f:
    d = json.load(f)
errors = []
required = ['verdict','export_allowed','handoff_allowed','tt_version','stages']
for f in required:
    if f not in d:
        errors.append(f"signoff.json missing '{f}'")
pkg = d.get('tt_version','?')
if pkg != expected_pkg:
    errors.append(f"signoff.json tt_version='{pkg}' != canonical '{expected_pkg}'")
if errors:
    for e in errors: print(f"  GATE_FAIL: {e}")
    sys.exit(1)
else:
    print("  GATE_PASS: signoff.json has all required readiness fields (v2)")
    print(f"  GATE_PASS: verdict={d['verdict']}, stages={len(d.get('stages',[]))}")
PYEOF
  [[ $? -eq 0 ]] && PASSES=$((PASSES+2)) || { ISSUES=$((ISSUES+1)); }
else
  warn "release/signoff.json not found — will be generated by pipeline"
fi

# ── 4. Bundle manifest integrity ─────────────────────────────────────────────
echo "── 4. Bundle Manifest"
if [[ -f "$MANIFEST_FILE" ]]; then
  python3 - "$MANIFEST_FILE" "$PKG_VER" << 'PYEOF'
import json, sys
m_path, expected_pkg = sys.argv[1], sys.argv[2]
with open(m_path, encoding='utf-8') as f:
    m = json.load(f)
pkg = m.get('tt_version','?')
if pkg != expected_pkg:
    print(f"  GATE_FAIL: manifest tt_version='{pkg}' != '{expected_pkg}'")
    sys.exit(1)
fc = int(m.get('total_files',0))
fl = len(m.get('files',[]))
if fc != fl:
    print(f"  GATE_FAIL: total_files={fc} != len(files)={fl}")
    sys.exit(1)
print(f"  GATE_PASS: manifest valid — {fc} files, tt_version={pkg}")
PYEOF
  [[ $? -eq 0 ]] && PASSES=$((PASSES+1)) || { ISSUES=$((ISSUES+1)); }
else
  warn "bundle-manifest.json not found — regenerate before release"
fi

# ── 5. SMTP wiring correctness ───────────────────────────────────────────────
echo "── 5. SMTP Variable Alignment"
if [[ -f "$DC_FILE" ]]; then
  if grep -q "N8N_SMTP_HOST" "$DC_FILE" && grep -q "TT_SMTP_PASSWORD" "$DC_FILE"; then
    pass "SMTP: N8N_SMTP_HOST present, TT_SMTP_PASSWORD correctly mapped"
  else
    fail "SMTP not properly wired to n8n in docker-compose.yml"
  fi
  if grep -q "TT_QDRANT_GRPC_HOST_PORT" "$DC_FILE"; then
    fail "Stale TT_QDRANT_GRPC_HOST_PORT in compose — must be TT_QDRANT_GRPC_PORT"
  else
    pass "Qdrant gRPC port variable: TT_QDRANT_GRPC_PORT (correct)"
  fi
fi

# ── 6. security_opt coverage ─────────────────────────────────────────────────
echo "── 6. Runtime Hardening"
if [[ -f "$DC_FILE" ]] && command -v python3 &>/dev/null; then
  python3 - "$DC_FILE" << 'PYEOF'
import re
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    lines = [ln.rstrip('\n') for ln in f]

service_header = re.compile(r'^\s{2}([A-Za-z0-9_.-]+):\s*$')
in_services = False
current = None
blocks = {}

for line in lines:
    if not in_services:
        if re.match(r'^\s*services:\s*$', line):
            in_services = True
        continue

    if line and not line.startswith(' '):
        break

    m = service_header.match(line)
    if m:
        current = m.group(1)
        blocks[current] = []
        continue

    if current:
        blocks[current].append(line)

if not blocks:
    print("  GATE_FAIL: no services parsed from docker-compose.yml")
    sys.exit(1)

missing = []
for svc, block in blocks.items():
    has_security_opt = False
    for ln in block:
        s = ln.strip()
        if not s or s.startswith('#'):
            continue
        if re.match(r'^security_opt\s*:', s):
            has_security_opt = True
            break
    if not has_security_opt:
        missing.append(svc)

if missing:
    print(f"  GATE_FAIL: security_opt missing on: {missing}")
    sys.exit(1)

print(f"  GATE_PASS: security_opt present on all {len(blocks)} core services")
PYEOF
  [[ $? -eq 0 ]] && PASSES=$((PASSES+1)) || { ISSUES=$((ISSUES+1)); }
elif [[ ! -f "$DC_FILE" ]]; then
  warn "docker-compose.yml not found — skipping runtime hardening check"
else
  warn "python3 not installed — skipping runtime hardening check"
fi
# ── 7. Metabase network isolation ────────────────────────────────────────────
echo "── 7. Metabase Network Isolation"
if [[ -f "$DC_FILE" ]] && command -v python3 &>/dev/null; then
  python3 - "$DC_FILE" << 'PYEOF'
import re
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    lines = [ln.rstrip('\n') for ln in f]

service_header = re.compile(r'^\s{2}([A-Za-z0-9_.-]+):\s*$')
in_services = False
current = None
blocks = {}

for line in lines:
    if not in_services:
        if re.match(r'^\s*services:\s*$', line):
            in_services = True
        continue

    if line and not line.startswith(' '):
        break

    m = service_header.match(line)
    if m:
        current = m.group(1)
        blocks[current] = []
        continue

    if current:
        blocks[current].append(line)

block = blocks.get('metabase')
if block is None:
    print("  GATE_FAIL: metabase service not found in docker-compose.yml")
    sys.exit(1)

nets = []
in_networks = False
for ln in block:
    if re.match(r'^\s{4}networks:\s*$', ln):
        in_networks = True
        continue
    if not in_networks:
        continue

    if re.match(r'^\s{4}[A-Za-z0-9_.-]+:\s*$', ln):
        break

    m_list = re.match(r'^\s{6}-\s*([A-Za-z0-9_.-]+)\s*$', ln)
    if m_list:
        nets.append(m_list.group(1))
        continue

    m_map = re.match(r'^\s{6}([A-Za-z0-9_.-]+):\s*$', ln)
    if m_map:
        nets.append(m_map.group(1))
        continue

    s = ln.strip()
    if not s or s.startswith('#'):
        continue
    if not re.match(r'^\s{6,}', ln):
        break

nets = sorted(set(nets))
if 'tt_shared_net' in nets:
    print("  GATE_FAIL: metabase on tt_shared_net — security isolation violation")
    sys.exit(1)
if 'tt_analytics_net' not in nets:
    print(f"  GATE_FAIL: metabase not on tt_analytics_net — got: {nets}")
    sys.exit(1)

print("  GATE_PASS: metabase isolated on tt_analytics_net")
PYEOF
  [[ $? -eq 0 ]] && PASSES=$((PASSES+1)) || { ISSUES=$((ISSUES+1)); }
elif [[ ! -f "$DC_FILE" ]]; then
  warn "docker-compose.yml not found — skipping metabase isolation check"
else
  warn "python3 not installed — skipping metabase isolation check"
fi
# ── 8. Compose YAML validity ─────────────────────────────────────────────────
echo "── 8. Compose YAML Validity"
ENV_FILE="$(tt_runtime_core_env_path "$ROOT/tt-core")"
ENV_EXAMPLE_FILE="$ROOT/tt-core/compose/tt-core/.env.example"
if [[ -f "$DC_FILE" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    if docker compose -f "$DC_FILE" --env-file "$ENV_FILE" config --quiet 2>/dev/null; then
      pass "docker-compose.yml is valid YAML with runtime env"
    else
      fail "docker-compose.yml has errors with runtime env"
    fi
  elif [[ -f "$ENV_EXAMPLE_FILE" ]]; then
    if docker compose -f "$DC_FILE" --env-file "$ENV_EXAMPLE_FILE" config --quiet 2>/dev/null; then
      pass "docker-compose.yml is valid YAML with .env.example fallback"
    else
      warn "docker-compose.yml has errors when validated with .env.example fallback"
    fi
  else
    warn "docker-compose.yml validation skipped - no runtime env or .env.example available"
  fi
fi

# ── 9. COMMERCIAL_HANDOFF stage check ────────────────────────────────────────
echo "── 9. Commercial Stage Verification"
CH="$ROOT/COMMERCIAL_HANDOFF.md"
if [[ -f "$CH" ]]; then
  grep -q "General Availability" "$CH" && pass "COMMERCIAL_HANDOFF.md: General Availability confirmed" || fail "Missing GA declaration"
  grep -q "Release Candidate" "$CH" && fail "COMMERCIAL_HANDOFF.md contains 'Release Candidate'" || pass "No RC text in handoff"
  grep -q "$PKG_VER" "$CH" && pass "COMMERCIAL_HANDOFF.md references $PKG_VER" || fail "Stale version in COMMERCIAL_HANDOFF.md"
fi

# ── 10. n8n-worker in service catalog ────────────────────────────────────────
echo "── 10. Service Catalog Completeness"
if [[ -f "$CATALOG_FILE" ]]; then
  python3 - "$CATALOG_FILE" << 'PYEOF'
import json,sys
with open(sys.argv[1], encoding='utf-8') as f:
    cat = json.load(f)
svcs = [s['service'] for s in cat.get('services',[])]
if 'n8n-worker' not in svcs:
    print(f"  GATE_FAIL: n8n-worker missing from service-catalog.json (required for smoke-test)")
    sys.exit(1)
else:
    print(f"  GATE_PASS: service-catalog has {len(svcs)} services including n8n-worker")
PYEOF
  [[ $? -eq 0 ]] && PASSES=$((PASSES+1)) || { ISSUES=$((ISSUES+1)); }
fi

# ── 11. Release history ───────────────────────────────────────────────────────
echo "── 11. Release History"
HIST_DIR="$ROOT/release/history"
if [[ -d "$HIST_DIR" ]]; then
  HIST_COUNT=$(ls "$HIST_DIR"/*.md 2>/dev/null | wc -l)
  pass "release/history/ has $HIST_COUNT release notes"
else
  warn "release/history/ missing"
fi
# Only current RELEASE_NOTES at root
STALE_NOTES=0
for old_ver in v12.0 v11.2 v11.0 v10.6 v10.1; do
  [[ -f "$ROOT/RELEASE_NOTES_${old_ver}.md" ]] && { fail "Stale RELEASE_NOTES_${old_ver}.md at root"; STALE_NOTES=1; }
done
[[ $STALE_NOTES -eq 0 ]] && pass "Only current RELEASE_NOTES_${PKG_VER}.md at root"

# ── 12. License date alignment ───────────────────────────────────────────────
echo "── 12. License Date Alignment"
RELEASE_DATE=$(python3 - "$VERSION_FILE" << 'PYEOF' 2>/dev/null || echo ""
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    d = json.load(f)
print(d.get('release_date',''))
PYEOF
)
if [[ -f "$ROOT/LICENSE.md" && -n "$RELEASE_DATE" ]]; then
  grep -q "$RELEASE_DATE" "$ROOT/LICENSE.md" && \
    pass "LICENSE.md effective date = $RELEASE_DATE" || \
    fail "LICENSE.md effective date does not match release_date ($RELEASE_DATE)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}━━━ v14.0 Consistency Gate Summary ━━━${NC}"
echo "  Canonical version: $PKG_VER"
echo "  Passes:   $PASSES"
echo "  Warnings: $WARNINGS"
echo "  Issues:   $ISSUES"
echo ""

if [[ $ISSUES -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}  CONSISTENCY GATE: PASS — release pipeline may proceed${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}  CONSISTENCY GATE: FAIL — $ISSUES issue(s) must be resolved${NC}"
  exit 1
fi





