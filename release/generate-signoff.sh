#!/usr/bin/env bash
# =============================================================================
# TT-Production — Generate Release Signoff — v14.0
# G00–G20 gates + full schema output with production_ready / release_authorized
#
# Usage:
#   cd TT-Production-v14.0
#   bash release/generate-signoff.sh
#
# Exit codes:
#   0 = all gates pass → signoff.json written as PASS
#   1 = one or more gates fail → signoff.json written as FAIL
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if command -v cygpath >/dev/null 2>&1; then
  ROOT="$(cygpath -m "$ROOT")"
fi
export ROOT
SIGNOFF_FILE="$ROOT/release/signoff.json"
VERSION_FILE="$ROOT/release/version.json"
STAMP=$(date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
HOST=$(hostname 2>/dev/null || echo "unknown")

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

PASSES=0; FAILURES=0; WARNINGS=0
CHECKS=()

pass_gate() {
  local id="$1"; local msg="${2:-OK}"
  PASSES=$((PASSES+1))
  CHECKS+=("{\"id\":\"$id\",\"result\":\"PASS\",\"message\":$(printf "%s" "$msg" | python3 -c "import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))")}")
  echo -e "  ${GREEN}[PASS]${NC} [$id] $msg"
}

fail_gate() {
  local id="$1"; local msg="${2:-FAILED}"
  FAILURES=$((FAILURES+1))
  CHECKS+=("{\"id\":\"$id\",\"result\":\"FAIL\",\"message\":$(printf "%s" "$msg" | python3 -c "import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))")}")
  echo -e "  ${RED}[FAIL]${NC} [$id] $msg"
}

warn_gate() {
  local id="$1"; local msg="${2:-WARNING}"
  WARNINGS=$((WARNINGS+1))
  CHECKS+=("{\"id\":\"$id\",\"result\":\"WARN\",\"message\":$(printf "%s" "$msg" | python3 -c "import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))")}")
  echo -e "  ${YELLOW}[WARN]${NC} [$id] $msg"
}

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  TT-Production — Release Signoff — v14.0 (G00–G20)          ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo ""

# ── Read version ──────────────────────────────────────────────────────────────
PKG_VERSION=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['package_version'])" 2>/dev/null || echo "unknown")
BASE_VERSION=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['base_version'])" 2>/dev/null || echo "unknown")
RELEASE_DATE=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['release_date'])" 2>/dev/null || echo "")

echo "  Package:  $PKG_VERSION"
echo "  Base:     $BASE_VERSION"
echo "  Date:     $RELEASE_DATE"
echo "  Host:     $HOST"
echo "  Stamp:    $STAMP"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# G00 — Baseline File Presence
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G00: Baseline File Presence ─────────────────────────────────${NC}"
REQUIRED_FILES=(
  "release/version.json"
  "release/signoff.json"
  "release/validate-shell.sh"
  "release/doc-contract-checker.sh"
  "release/consistency-gate.sh"
  "release/lint-docs.sh"
  "release/verify-manifest.sh"
  "release/bundle-manifest.json"
  "release/smoke-results.json"
  "release/exposure-summary.json"
  "COMMERCIAL_HANDOFF.md"
  "MASTER_GUIDE.md"
  "LICENSE.md"
  "RELEASE_NOTES_v14.0.md"
  "CUSTOMER_ACCEPTANCE_CHECKLIST.md"
  "SYSTEM_REQUIREMENTS.md"
  "tt-core/compose/tt-core/docker-compose.yml"
  "tt-core/scripts-linux/preflight-check.sh"
  "tt-core/scripts-linux/init.sh"
  "tt-core/scripts-linux/smoke-test.sh"
  "tt-core/scripts-linux/ttcore.sh"
  "tt-core/scripts/backup/Restore-All.ps1"
  "tt-core/docs/KNOWN_LIMITATIONS.md"
  "tt-core/docs/QA-LINUX.md"
  "tt-core/docs/IMAGE_PINNING.md"
  "tt-core/docs/SECRET_MANAGEMENT.md"
  "tt-core/docs/PLATFORM_SUPPORT.md"
)
G00_FAIL=0
for f in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "$ROOT/$f" ]]; then
    fail_gate "G00_file_$f" "MISSING: $f"
    G00_FAIL=$((G00_FAIL+1))
  fi
done
[[ $G00_FAIL -eq 0 ]] && pass_gate "G00_baseline_files" "All required files present"

# Check MUST NOT exist at root
MUST_NOT_EXIST=("RELEASE_NOTES_v13.0.md" "RELEASE_NOTES_v13.0.8.md" "RELEASE_NOTES_v12.0.md" "RELEASE_NOTES_v11.2.md")
for f in "${MUST_NOT_EXIST[@]}"; do
  if [[ -f "$ROOT/$f" ]]; then
    fail_gate "G00_stale_root_$f" "Stale file at root: $f (must be in release/history/)"
  fi
done

# ═══════════════════════════════════════════════════════════════════════════════
# G01 — Version Identity Consistency
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G01: Version Identity ───────────────────────────────────────${NC}"
if echo "$PKG_VERSION" | grep -qE '^v[0-9]+\.[0-9]+'; then
  pass_gate "G01_pkg_version" "package_version=$PKG_VERSION (well-formed)"
else
  fail_gate "G01_pkg_version" "package_version=${PKG_VERSION} not well-formed (expected vX.Y)"
fi
[[ "$BASE_VERSION" == "v13.0.8" ]] \
  && pass_gate "G01_base_version" "base_version=v13.0.8 (correct direct predecessor)" \
  || fail_gate "G01_base_version" "base_version=$BASE_VERSION (expected v13.0.8 for v14.0)"

ANCESTRY=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['ancestry'])" 2>/dev/null || echo "")
if echo "$ANCESTRY" | grep -q "→ v13.0.8 → v14.0$"; then
  pass_gate "G01_ancestry" "Ancestry ends → v13.0.8 → v14.0"
else
  fail_gate "G01_ancestry" "Ancestry does not end with → v13.0.8 → v14.0: $ANCESTRY"
fi

# No readiness fields in version.json
for prohibited in "pipeline_verdict" "production_ready" "release_authorized"; do
  if python3 -c "import json; d=json.load(open('$VERSION_FILE')); exit(0 if '$prohibited' not in d else 1)" 2>/dev/null; then
    pass_gate "G01_version_no_$prohibited" "version.json does not contain $prohibited"
  else
    fail_gate "G01_version_no_$prohibited" "version.json must NOT contain $prohibited — use signoff.json"
  fi
done

# ═══════════════════════════════════════════════════════════════════════════════
# G02 — Shell Script Syntax (bash -n)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G02: Shell Script Syntax ────────────────────────────────────${NC}"
SHELL_FAILED=0; SHELL_TOTAL=0
while IFS= read -r -d '' f; do
  SHELL_TOTAL=$((SHELL_TOTAL+1))
  if ! bash -n "$f" 2>/dev/null; then
    fail_gate "G02_syntax_$(basename $f)" "Syntax error in $f"
    SHELL_FAILED=$((SHELL_FAILED+1))
  fi
done < <(find "$ROOT" -name "*.sh" -not -path "*/.git/*" -print0)
[[ $SHELL_FAILED -eq 0 ]] \
  && pass_gate "G02_shell_syntax" "All $SHELL_TOTAL scripts pass bash -n" \
  || fail_gate "G02_shell_syntax_summary" "$SHELL_FAILED/$SHELL_TOTAL scripts have syntax errors"

# ═══════════════════════════════════════════════════════════════════════════════
# G03 — Env ↔ Compose Contract
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G03: Env ↔ Compose Contract ─────────────────────────────────${NC}"
ENV_FILE="$ROOT/tt-core/env/.env.example"
COMPOSE_FILE="$ROOT/tt-core/compose/tt-core/docker-compose.yml"
if [[ -f "$ENV_FILE" && -f "$COMPOSE_FILE" ]]; then
  ENV_VARS=$(grep -oP '^TT_\w+' "$ENV_FILE" | sort -u 2>/dev/null || true)
  EXCEPTIONS="TT_TZ TT_BIND_IP TT_POSTGRES_HOST_PORT TT_REDIS_HOST_PORT TT_N8N_HOST_PORT TT_PGADMIN_HOST_PORT TT_REDISINSIGHT_HOST_PORT TT_METABASE_HOST_PORT TT_WORDPRESS_HOST_PORT TT_MARIADB_HOST_PORT TT_KANBOARD_HOST_PORT TT_UPTIME_KUMA_HOST_PORT TT_PORTAINER_HOST_PORT TT_QDRANT_HOST_PORT TT_QDRANT_GRPC_PORT TT_OLLAMA_HOST_PORT TT_OPENWEBUI_HOST_PORT TT_PG_SHARED_BUFFERS TT_PG_MAX_CONNECTIONS TT_PG_WORK_MEM TT_POSTGRES_DB TT_BACKUP_NOTIFY_WEBHOOK_URL TT_MONITOR_NOTIFY_WEBHOOK_URL TT_MONITOR_DISK_WARN_THRESHOLD TT_MONITOR_MEM_WARN_THRESHOLD TT_N8N_API_KEY"
  ORPHANED=0
  for var in $ENV_VARS; do
    if ! grep -q "\${${var}" "$COMPOSE_FILE" 2>/dev/null && \
       ! grep -qr "\${${var}" "$ROOT/tt-core/compose/tt-core/addons/" 2>/dev/null; then
      if ! echo "$EXCEPTIONS" | grep -qw "$var"; then
        warn_gate "G03_orphan_$var" "$var declared in .env.example but not consumed in compose"
        ORPHANED=$((ORPHANED+1))
      fi
    fi
  done
  [[ $ORPHANED -eq 0 ]] && pass_gate "G03_env_compose_contract" "All env vars consumed (exceptions noted)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# G04 — SMTP Variable Alignment (DEFECT-01 gate)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G04: SMTP Variable Alignment ────────────────────────────────${NC}"
COMPOSE_FILE="$ROOT/tt-core/compose/tt-core/docker-compose.yml"
if grep -q 'TT_SMTP_PASS:-' "$COMPOSE_FILE" 2>/dev/null && ! grep -q 'TT_SMTP_PASSWORD:-' "$COMPOSE_FILE" 2>/dev/null; then
  fail_gate "G04_smtp_var" "compose still uses TT_SMTP_PASS — must be TT_SMTP_PASSWORD"
elif grep -q 'TT_SMTP_SENDER:-' "$COMPOSE_FILE" 2>/dev/null && ! grep -q 'TT_SMTP_FROM:-' "$COMPOSE_FILE" 2>/dev/null; then
  fail_gate "G04_smtp_sender" "compose still uses TT_SMTP_SENDER — must be TT_SMTP_FROM"
elif grep -q 'TT_SMTP_SSL:-' "$COMPOSE_FILE" 2>/dev/null && ! grep -q 'TT_SMTP_SECURE:-' "$COMPOSE_FILE" 2>/dev/null; then
  fail_gate "G04_smtp_ssl" "compose still uses TT_SMTP_SSL — must be TT_SMTP_SECURE"
else
  pass_gate "G04_smtp_var_alignment" "SMTP vars correctly mapped"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# G05 — .env.example Version Headers
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G05: .env.example Version Headers ──────────────────────────${NC}"
ENV_FILES=(
  "tt-core/env/.env.example"
  "tt-core/env/tunnel.env.example"
  "tt-core/compose/tt-core/.env.example"
  "tt-core/compose/tt-tunnel/.env.example"
  "tt-supabase/env/tt-supabase.env.example"
)
STALE_ENVS=0
for ef in "${ENV_FILES[@]}"; do
  if [[ -f "$ROOT/$ef" ]]; then
    if grep -q "Version: TT-Production v14.0\|Version: v14.0\|TT-Production v14.0" "$ROOT/$ef" 2>/dev/null; then
      pass_gate "G05_${ef//\//_}" "$ef has v14.0 header"
    else
      # Check for old versions
      OLD_VER=$(grep -oP 'v\d+\.\d+' "$ROOT/$ef" | head -1 || echo "none")
      fail_gate "G05_${ef//\//_}" "$ef has stale header (found $OLD_VER — expected v14.0)"
      STALE_ENVS=$((STALE_ENVS+1))
    fi
  else
    fail_gate "G05_missing_${ef//\//_}" "$ef not found"
    STALE_ENVS=$((STALE_ENVS+1))
  fi
done
[[ $STALE_ENVS -eq 0 ]] && pass_gate "G05_env_headers_all" "All 5 .env.example files have v14.0 headers"

# ═══════════════════════════════════════════════════════════════════════════════
# G06 — services.select.json and service-catalog.json version comment
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G06: Config JSON Version Comments ──────────────────────────${NC}"
for jf in "tt-core/config/services.select.json" "tt-core/config/service-catalog.json"; do
  if [[ -f "$ROOT/$jf" ]]; then
    COMMENT=$(python3 -c "import json; print(json.load(open('$ROOT/$jf')).get('_comment',''))" 2>/dev/null || echo "")
    if echo "$COMMENT" | grep -q "v14.0"; then
      pass_gate "G06_$(basename $jf)" "_comment contains v14.0"
    else
      fail_gate "G06_$(basename $jf)" "_comment does not contain v14.0: $COMMENT"
    fi
  fi
done

# ═══════════════════════════════════════════════════════════════════════════════
# G07 — Timestamp Freshness
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G07: Timestamp Freshness ────────────────────────────────────${NC}"
MIDNIGHT_COUNT=0
for art in deployment-cert.json restore-cert.json handoff-cert.json supportability-cert.json; do
  FULL_PATH="$ROOT/release/$art"
  if [[ -f "$FULL_PATH" ]]; then
    IS_TPL=$(python3 -c "import json; d=json.load(open('$FULL_PATH')); print(d.get('_is_template', False))" 2>/dev/null || echo "False")
    GEN_AT=$(python3 -c "import json; d=json.load(open('$FULL_PATH')); print(d.get('generated_at',''))" 2>/dev/null || echo "")
    if [[ "$IS_TPL" == "True" ]]; then
      pass_gate "G07_template_$art" "$art is_template=true (acceptable)"
    elif echo "$GEN_AT" | grep -q "T00:00:00Z"; then
      fail_gate "G07_midnight_$art" "$art has midnight hardcoded timestamp and is not marked _is_template"
      MIDNIGHT_COUNT=$((MIDNIGHT_COUNT+1))
    else
      pass_gate "G07_timestamp_$art" "$art has non-midnight timestamp"
    fi
  fi
done

# smoke-results.json — special rule: template is OK if marked
SR_PATH="$ROOT/release/smoke-results.json"
SR_TPL=$(python3 -c "import json; d=json.load(open('$SR_PATH')); print(d.get('_is_template',False))" 2>/dev/null || echo "True")
SR_AT=$(python3 -c "import json; d=json.load(open('$SR_PATH')); print(d.get('generated_at',''))" 2>/dev/null || echo "")
if [[ "$SR_TPL" == "True" ]]; then
  pass_gate "G07_smoke_template" "smoke-results.json is_template=true (operator must run smoke-test.sh)"
elif echo "$SR_AT" | grep -q "T00:00:00Z"; then
  fail_gate "G07_smoke_midnight" "smoke-results.json has midnight timestamp without _is_template"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# G08 — No Hardcoded Check Counts in Release Docs
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G08: No Hardcoded Check Counts ──────────────────────────────${NC}"
if grep -rE '\b1[0-9]{2,} checks?\b|\b1[0-9]{2,}-check' \
    "$ROOT/RELEASE_NOTES_v14.0.md" "$ROOT/CUSTOMER_ACCEPTANCE_CHECKLIST.md" 2>/dev/null | \
    grep -vE "release/signoff\.json|signoff\.json|total_checks" | head -5; then
  fail_gate "G08_hardcoded_counts" "Hardcoded check count found in release docs"
else
  pass_gate "G08_check_counts" "No hardcoded check counts in release docs"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# G09 — SHA-256 Checksum File
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G09: SHA-256 Checksum File ──────────────────────────────────${NC}"
if [[ -f "$ROOT/release/TT-Production-v14.0.zip.sha256" ]]; then
  pass_gate "G09_sha256_exists" "TT-Production-v14.0.zip.sha256 present"
else
  warn_gate "G09_sha256_missing" "TT-Production-v14.0.zip.sha256 not present — generate with make-release.sh"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# G10 — IMAGE_PINNING.md Present
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G10: IMAGE_PINNING.md ───────────────────────────────────────${NC}"
[[ -f "$ROOT/tt-core/docs/IMAGE_PINNING.md" ]] \
  && pass_gate "G10_image_pinning_doc" "tt-core/docs/IMAGE_PINNING.md exists" \
  || fail_gate "G10_image_pinning_doc" "tt-core/docs/IMAGE_PINNING.md MISSING"

# ═══════════════════════════════════════════════════════════════════════════════
# G11 — QA-LINUX.md Present
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G11: QA-LINUX.md ────────────────────────────────────────────${NC}"
[[ -f "$ROOT/tt-core/docs/QA-LINUX.md" ]] \
  && pass_gate "G11_qa_linux" "tt-core/docs/QA-LINUX.md exists" \
  || fail_gate "G11_qa_linux" "tt-core/docs/QA-LINUX.md MISSING"

# ═══════════════════════════════════════════════════════════════════════════════
# G12 — security_opt on all services
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G12: security_opt Complete ──────────────────────────────────${NC}"
python3 - "$ROOT" << 'PYEOF' && pass_gate "G12_security_opt" "security_opt present across compose services (core/supabase/tunnel/addons)" || fail_gate "G12_security_opt" "security_opt missing from one or more services"
import os
import re
import sys

root = sys.argv[1]
issues = []

service_header = re.compile(r'^\s{2}([A-Za-z0-9_.-]+):\s*$')

def load_service_blocks(path):
    if not os.path.exists(path):
        issues.append(f'missing compose file: {path}')
        return {}
    with open(path, encoding='utf-8') as f:
        lines = f.readlines()

    blocks = {}
    in_services = False
    current = None

    for raw in lines:
        line = raw.rstrip('\n')
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

        if current is not None:
            blocks[current].append(line)

    return blocks

def has_security_opt(block_lines):
    for line in block_lines:
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        if re.match(r'^security_opt\s*:', s):
            return True
    return False

compose_targets = [
    'tt-core/compose/tt-core/docker-compose.yml',
    'tt-supabase/compose/tt-supabase/docker-compose.yml',
    'tt-core/compose/tt-tunnel/docker-compose.yml',
]

for rel in compose_targets:
    path = os.path.join(root, rel)
    blocks = load_service_blocks(path)
    if not blocks:
        issues.append(f'no services found in {rel}')
        continue
    for svc, block in blocks.items():
        if not has_security_opt(block):
            issues.append(f'{rel}:{svc} missing security_opt')

addon_dir = os.path.join(root, 'tt-core/compose/tt-core/addons')
if not os.path.isdir(addon_dir):
    issues.append('addons directory missing: tt-core/compose/tt-core/addons')
else:
    addon_files = sorted([f for f in os.listdir(addon_dir) if f.endswith('.addon.yml')])
    for addon in addon_files:
        rel = f'tt-core/compose/tt-core/addons/{addon}'
        path = os.path.join(root, rel)
        blocks = load_service_blocks(path)
        if not blocks:
            issues.append(f'{rel}: no services found')
            continue
        for svc, block in blocks.items():
            if not has_security_opt(block):
                issues.append(f'{rel}:{svc} missing security_opt')

if issues:
    for item in issues[:30]:
        print(f'  FAIL: {item}')
    if len(issues) > 30:
        print(f'  ... and {len(issues)-30} more')
    sys.exit(1)

print('  OK: security_opt present for all parsed services')
PYEOF

# ═══════════════════════════════════════════════════════════════════════════════
# G13 — smoke-results.json schema
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G13: smoke-results.json Schema ──────────────────────────────${NC}"
python3 - "$ROOT/release/smoke-results.json" << 'PYEOF' && pass_gate "G13_smoke_schema" "smoke-results.json matches supported schema" || fail_gate "G13_smoke_schema" "smoke-results.json missing required fields"
import json
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    d = json.load(f)

base_required = ['_generator', 'generated_at']
missing_base = [k for k in base_required if k not in d]
if missing_base:
    print(f'  FAIL: missing base fields: {missing_base}')
    sys.exit(1)

is_v1 = all(k in d for k in ['tt_version', 'overall', 'services'])
is_legacy = all(k in d for k in ['passed', 'total_probes']) and ('package_version' in d or 'tt_version' in d)

if not (is_v1 or is_legacy):
    print('  FAIL: unsupported smoke-results schema (expected v1 or legacy)')
    sys.exit(1)

if is_v1:
    if not isinstance(d.get('services'), list):
        print('  FAIL: services must be an array')
        sys.exit(1)
    print(f"  OK: v1 schema, overall={d.get('overall')}, services={len(d.get('services', []))}")
else:
    print(f"  OK: legacy schema, passed={d.get('passed')}, total_probes={d.get('total_probes')}")
PYEOF

# ═══════════════════════════════════════════════════════════════════════════════
# G14 — n8n-worker in smoke-test required containers
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G14: n8n-worker in Smoke Test ───────────────────────────────${NC}"
SMOKE_SCRIPT="$ROOT/tt-core/scripts-linux/smoke-test.sh"
if [[ -f "$SMOKE_SCRIPT" ]]; then
  if grep -q "tt-core-n8n-worker" "$SMOKE_SCRIPT"; then
    pass_gate "G14_n8n_worker_smoke" "n8n-worker in smoke-test required containers"
  else
    fail_gate "G14_n8n_worker_smoke" "n8n-worker missing from smoke-test.sh required containers"
  fi
else
  fail_gate "G14_smoke_missing" "smoke-test.sh not found"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# G15 — metabase not on tt_shared_net
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G15: Metabase Network Isolation ─────────────────────────────${NC}"
python3 - "$ROOT/tt-core/compose/tt-core/docker-compose.yml" << 'PYEOF' && pass_gate "G15_metabase_isolation" "metabase on tt_analytics_net, not on tt_shared_net" || fail_gate "G15_metabase_isolation" "metabase network isolation FAILED"
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

if 'metabase' not in blocks:
    print('  OK: metabase service absent (profile-gated)')
    sys.exit(0)

block = blocks['metabase']
nets = []
in_networks = False
for line in block:
    if re.match(r'^\s{4}networks:\s*$', line):
        in_networks = True
        continue
    if in_networks:
        if re.match(r'^\s{4}[A-Za-z0-9_.-]+:\s*$', line):
            break
        m = re.match(r'^\s*[-]\s*([A-Za-z0-9_.-]+)\s*$', line)
        if m:
            nets.append(m.group(1))

if 'tt_shared_net' in nets:
    print('  FAIL: metabase on tt_shared_net — must be isolated')
    sys.exit(1)
if 'tt_analytics_net' not in nets:
    print(f'  FAIL: metabase not on tt_analytics_net (nets={nets})')
    sys.exit(1)

print(f'  OK: metabase networks={nets}')
PYEOF

# ═══════════════════════════════════════════════════════════════════════════════
# G16 — COMMERCIAL_HANDOFF says "General Availability"
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G16: Commercial Handoff Status ──────────────────────────────${NC}"
CH_FILE="$ROOT/COMMERCIAL_HANDOFF.md"
if [[ -f "$CH_FILE" ]]; then
  if grep -q "General Availability" "$CH_FILE"; then
    pass_gate "G16_handoff_ga" "COMMERCIAL_HANDOFF.md says General Availability"
  else
    fail_gate "G16_handoff_ga" "COMMERCIAL_HANDOFF.md missing General Availability"
  fi
  if grep -q "Release Candidate" "$CH_FILE"; then
    fail_gate "G16_handoff_no_rc" "COMMERCIAL_HANDOFF.md still contains 'Release Candidate'"
  else
    pass_gate "G16_handoff_no_rc" "COMMERCIAL_HANDOFF.md does not say Release Candidate"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# G17 — Preflight Count Consistency (must be 27)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G17: Preflight Count (must be 27) ───────────────────────────${NC}"
# G17: fail active docs that still advertise 19/22 checks without any 27-check reference.
STALE19=0
while IFS= read -r _stale_f; do
  [[ -z "$_stale_f" ]] && continue
  if ! grep -Eq "27[[:space:]]*فحص|27[[:space:]]*checks?" "$_stale_f" 2>/dev/null; then
    STALE19=$((STALE19+1))
    echo "  [DBG] Stale 19-count (no 27 ref): ${_stale_f#$ROOT/}"
  fi
done < <(grep -rEl "19[[:space:]]*فحص|19[[:space:]]*checks?" "$ROOT" --include="*.md" --exclude-dir=history 2>/dev/null || true)

STALE22=0
while IFS= read -r _stale_f; do
  [[ -z "$_stale_f" ]] && continue
  if ! grep -Eq "27[[:space:]]*فحص|27[[:space:]]*checks?" "$_stale_f" 2>/dev/null; then
    STALE22=$((STALE22+1))
    echo "  [DBG] Stale 22-count (no 27 ref): ${_stale_f#$ROOT/}"
  fi
done < <(grep -rEl "22[[:space:]]*فحص|22[[:space:]]*checks?" "$ROOT" --include="*.md" --exclude-dir=history 2>/dev/null || true)

if [[ "$STALE19" -eq 0 && "$STALE22" -eq 0 ]]; then
  pass_gate "G17_preflight_count" "No stale 19/22-check counts in active docs (historical references OK)"
else
  fail_gate "G17_preflight_count" "$((STALE19+STALE22)) active docs contain stale 19/22-check count (must be 27)"
fi

CORRECT27=$(grep -rEl "27[[:space:]]*فحص|27[[:space:]]*checks?" "$ROOT" --include="*.md" --exclude-dir=history 2>/dev/null | wc -l || echo 0)
CORRECT27="${CORRECT27//[[:space:]]/}"
if [[ "$CORRECT27" -gt 0 ]]; then
  pass_gate "G17_preflight_22" "Active docs correctly reference 27-check preflight"
else
  warn_gate "G17_preflight_22" "No active doc found referencing 27-check preflight"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# G18 — bundle-manifest.json
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G18: Bundle Manifest ────────────────────────────────────────${NC}"
MANIFEST="$ROOT/release/bundle-manifest.json"
if [[ -f "$MANIFEST" ]]; then
  python3 - "$ROOT" "$MANIFEST" << 'PYEOF' && pass_gate "G18_manifest" "bundle-manifest.json valid" || fail_gate "G18_manifest" "bundle-manifest.json invalid"
import json
import os
import sys

root, path = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as f:
    d = json.load(f)

for k in ['_generator', 'generated_at', 'files']:
    if k not in d:
        print(f'  FAIL: missing required field: {k}')
        sys.exit(1)

files = d.get('files', [])
if not isinstance(files, list):
    print('  FAIL: files must be an array')
    sys.exit(1)

paths = []
for item in files:
    if isinstance(item, dict):
        p = item.get('path')
    else:
        p = str(item)
    if p:
        paths.append(p)

count = d.get('total_files', d.get('file_count'))
if count is None:
    print('  FAIL: missing total_files/file_count')
    sys.exit(1)

if int(count) != len(paths):
    print(f'  FAIL: declared count={count} != len(files)={len(paths)}')
    sys.exit(1)

dup = sorted({p for p in paths if paths.count(p) > 1})
if dup:
    print(f'  FAIL: duplicate manifest paths detected ({len(dup)}): {dup[:5]}')
    sys.exit(1)

ver = d.get('tt_version') or d.get('package_version') or d.get('version')
if not ver:
    print('  FAIL: missing version field (tt_version/package_version/version)')
    sys.exit(1)

missing = [p for p in paths if not os.path.isfile(os.path.join(root, p.replace('/', os.sep)))]
if missing:
    print(f'  FAIL: {len(missing)} listed file(s) missing on disk; sample={missing[:5]}')
    sys.exit(1)

print(f'  OK: count={count}, version={ver}, files={len(paths)}')
PYEOF
fi

# ═══════════════════════════════════════════════════════════════════════════════
# G19 — doc-contract-checker.sh present and passes bash -n
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G19: doc-contract-checker.sh ────────────────────────────────${NC}"
DCC="$ROOT/release/doc-contract-checker.sh"
if [[ -f "$DCC" ]]; then
  if bash -n "$DCC" 2>/dev/null; then
    pass_gate "G19_doc_contract" "doc-contract-checker.sh exists and passes bash -n"
  else
    fail_gate "G19_doc_contract" "doc-contract-checker.sh has syntax errors"
  fi
else
  fail_gate "G19_doc_contract" "release/doc-contract-checker.sh MISSING"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# G20 — LICENSE date aligned with release_date
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G20: LICENSE Date Alignment ─────────────────────────────────${NC}"
LICENSE_FILE="$ROOT/LICENSE.md"
if [[ -f "$LICENSE_FILE" && -n "$RELEASE_DATE" ]]; then
  if grep -q "$RELEASE_DATE" "$LICENSE_FILE"; then
    pass_gate "G20_license_date" "LICENSE.md contains release_date $RELEASE_DATE"
  else
    warn_gate "G20_license_date" "LICENSE.md may not contain release_date $RELEASE_DATE — verify"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Bonus gates — additional quality checks
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── G21+: Additional Quality Gates ──────────────────────────────${NC}"

# Qdrant gRPC variable (DEFECT-06)
if grep -r "TT_QDRANT_GRPC_HOST_PORT" "$ROOT" --include="*.yml" --include="*.env*" 2>/dev/null | grep -v ".git" | head -3; then
  fail_gate "G21_qdrant_grpc" "TT_QDRANT_GRPC_HOST_PORT still present — must be TT_QDRANT_GRPC_PORT"
else
  pass_gate "G21_qdrant_grpc" "TT_QDRANT_GRPC_HOST_PORT absent (uses TT_QDRANT_GRPC_PORT)"
fi

# ttcore.sh present
[[ -f "$ROOT/tt-core/scripts-linux/ttcore.sh" ]] \
  && pass_gate "G22_ttcore_sh" "ttcore.sh present (Linux CLI)" \
  || fail_gate "G22_ttcore_sh" "tt-core/scripts-linux/ttcore.sh MISSING"

# Restore-All.ps1 present
[[ -f "$ROOT/tt-core/scripts/backup/Restore-All.ps1" ]] \
  && pass_gate "G23_restore_all" "Restore-All.ps1 present" \
  || fail_gate "G23_restore_all" "tt-core/scripts/backup/Restore-All.ps1 MISSING"

# SECRET_MANAGEMENT.md present
[[ -f "$ROOT/tt-core/docs/SECRET_MANAGEMENT.md" ]] \
  && pass_gate "G24_secret_mgmt" "SECRET_MANAGEMENT.md present" \
  || fail_gate "G24_secret_mgmt" "tt-core/docs/SECRET_MANAGEMENT.md MISSING"

# start_period on critical services
python3 - "$ROOT/tt-core/compose/tt-core/docker-compose.yml" << 'PYEOF' && pass_gate "G25_start_period" "start_period on critical services" || fail_gate "G25_start_period" "start_period missing on critical services"
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

required = ['postgres', 'redis', 'qdrant', 'n8n', 'n8n-worker']
missing = []

for svc in required:
    block = blocks.get(svc)
    if not block:
        missing.append(f'{svc} (service missing)')
        continue

    has_healthcheck = any(re.match(r'^\s{4}healthcheck:\s*$', ln) for ln in block)
    if not has_healthcheck:
        missing.append(f'{svc} (no healthcheck)')
        continue

    in_health = False
    has_start_period = False
    for ln in block:
        if re.match(r'^\s{4}healthcheck:\s*$', ln):
            in_health = True
            continue
        if in_health:
            if re.match(r'^\s{4}[A-Za-z0-9_.-]+:\s*$', ln):
                break
            if re.match(r'^\s{6}start_period:\s*', ln):
                has_start_period = True
                break

    if not has_start_period:
        missing.append(f'{svc} (no start_period)')

if missing:
    print(f'  Missing start_period/healthcheck: {missing}')
    sys.exit(1)

print('  OK: all critical services have start_period')
PYEOF

# Current release notes may be kept at root, while prior releases live in release/history/.
if [[ -f "$ROOT/RELEASE_NOTES_v14.0.md" ]]; then
  pass_gate "G26_history_v112" "Current release notes present at root (RELEASE_NOTES_v14.0.md)"
elif [[ -f "$ROOT/release/history/RELEASE_NOTES_v14.0.md" ]]; then
  pass_gate "G26_history_v112" "RELEASE_NOTES_v14.0.md present in release/history/"
else
  warn_gate "G26_history_v112" "RELEASE_NOTES_v14.0.md not found at root or in release/history/"
fi

# All 8 canonical JSON artifacts have _generator, package_version, generated_at
echo -e "${CYAN}── G27: Canonical Artifact Schema ──────────────────────────────${NC}"
python3 - "$ROOT" << 'PYEOF' && pass_gate "G27_artifact_schema" "Canonical artifacts contain required schema fields" || fail_gate "G27_artifact_schema" "One or more artifacts missing schema fields"
import json
import os
import sys

root = sys.argv[1]
artifacts = [
  'release/signoff.json', 'release/bundle-manifest.json', 'release/deployment-cert.json',
  'release/restore-cert.json', 'release/handoff-cert.json', 'release/supportability-cert.json',
  'release/smoke-results.json', 'release/exposure-summary.json'
]

all_ok = True
for rel in artifacts:
    path = os.path.join(root, rel)
    if not os.path.exists(path):
        print(f'  SKIP (not found): {rel}')
        continue

    with open(path, encoding='utf-8') as f:
        d = json.load(f)

    missing = []
    for base in ['_generator', 'generated_at']:
        if base not in d:
            missing.append(base)

    name = os.path.basename(rel)
    if name == 'bundle-manifest.json':
        if 'files' not in d:
            missing.append('files')
        if 'total_files' not in d and 'file_count' not in d:
            missing.append('total_files/file_count')
        if not (d.get('tt_version') or d.get('package_version') or d.get('version')):
            missing.append('tt_version/package_version/version')
    elif name == 'signoff.json':
        if not (d.get('verdict') or d.get('pipeline_verdict')):
            missing.append('verdict/pipeline_verdict')
        if not (d.get('tt_version') or d.get('package_version')):
            missing.append('tt_version/package_version')
    else:
        if not (d.get('package_version') or d.get('tt_version') or d.get('generated_version')):
            missing.append('package_version/tt_version/generated_version')

    if missing:
        print(f'  FAIL: {rel} missing {missing}')
        all_ok = False
    else:
        print(f'  OK: {name}')

sys.exit(0 if all_ok else 1)
PYEOF

# ═══════════════════════════════════════════════════════════════════════════════
# Write signoff.json
# ═══════════════════════════════════════════════════════════════════════════════
TOTAL_CHECKS=$((PASSES + FAILURES + WARNINGS))
VERDICT="FAIL"
EXPORT_ALLOWED="false"
HANDOFF_ALLOWED="false"
[[ $FAILURES -eq 0 ]] && VERDICT="PASS" && EXPORT_ALLOWED="true" && HANDOFF_ALLOWED="true"
[[ $FAILURES -eq 0 && $WARNINGS -gt 0 ]] && VERDICT="PASS_WITH_NOTES"

AUTHORITY_MSG="AUTHORIZED: $TOTAL_CHECKS checks at $STAMP. $PASSES pass, $FAILURES fail, $WARNINGS warn. Release may proceed."
[[ $FAILURES -gt 0 ]] && AUTHORITY_MSG="NOT AUTHORIZED: $FAILURES gate(s) failed. Fix before release."

# Build JSON checks array
CHECKS_JSON="["
FIRST=true
for c in "${CHECKS[@]}"; do
  $FIRST || CHECKS_JSON+=","
  CHECKS_JSON+="$c"
  FIRST=false
done
CHECKS_JSON+="]"

python3 - << PYEOF
import json

checks = $CHECKS_JSON
verdict = "$VERDICT"
stamp = "$STAMP"
pkg_version = "$PKG_VERSION"

def to_exit_code(result):
    if result == 'PASS':
        return 0
    if result == 'WARN':
        return 3
    return 1

stages = []
notes = []
blockers = []

for idx, c in enumerate(checks):
    result = c.get('result', 'PASS')
    msg = c.get('message', '')
    gate_id = c.get('id', f'G{idx:02d}')
    stages.append({
        'stage_id': idx,
        'stage_name': gate_id,
        'result': result,
        'exit_code': to_exit_code(result),
        'message': msg,
        'evidence_file': None,
    })
    if result == 'WARN':
        notes.append(f"{gate_id}: {msg}")
    if result == 'FAIL':
        blockers.append(f"{gate_id}: {msg}")

build_suffix = stamp[:10].replace('-', '') if stamp else 'unknown'
doc = {
    '_schema': 'tt-signoff/v2',
    '_comment': 'GENERATED by release/generate-signoff.sh - do not edit manually',
    '_generator': 'release/generate-signoff.sh',
    '_authority': 'This file is the machine readiness verdict. version.json is identity-only.',
    'generated_at': stamp,
    'generated_on_host': "$HOST",
    'product_name': 'TT-Production',
    'bundle_name': 'TT-Production',
    'package_version': pkg_version,
    'tt_version': pkg_version,
    'release_channel': 'stable-commercial',
    'release_stage': 'general-availability',
    'build_id': f"tt-production-{pkg_version.lower()}-{build_suffix}",
    'verdict': verdict,
    'export_allowed': verdict != 'FAIL',
    'handoff_allowed': verdict != 'FAIL',
    'total_checks': $TOTAL_CHECKS,
    'checks_passed': $PASSES,
    'checks_failed': $FAILURES,
    'checks_warned': $WARNINGS,
    'pipeline_verdict': verdict,
    'production_ready': verdict != 'FAIL',
    'release_authorized': verdict != 'FAIL',
    'authority_statement': "$AUTHORITY_MSG",
    'checks': checks,
    'stages': stages,
    'notes': notes,
    'blockers': blockers,
}

with open("$SIGNOFF_FILE", 'w', encoding='utf-8') as f:
    json.dump(doc, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f"  signoff.json written: {len(checks)} checks, {len(blockers)} failed, verdict={doc['verdict']}")
PYEOF

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
if [[ $FAILURES -gt 0 ]]; then
  echo -e "${RED}  SIGNOFF: FAIL — $FAILURES gate(s) failed. RELEASE BLOCKED.${NC}"
  echo -e "${RED}  Fix all FAIL items above, then re-run generate-signoff.sh.${NC}"
  exit 1
else
  echo -e "${GREEN}  SIGNOFF: PASS — $PASSES gates passed, $WARNINGS warned, 0 failed.${NC}"
  echo -e "${GREEN}  pipeline_verdict: PASS | production_ready: true | release_authorized: true${NC}"
fi
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo ""






