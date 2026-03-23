#!/usr/bin/env bash
# =============================================================================
# verify-security-ack.sh — Restricted Admin Double-Gate Verifier
# TT-Production v14.0
#
# Validates that BOTH conditions are met before any restricted-admin tunnel
# route is permitted:
#   Gate 1: services.select.json → security.allow_restricted_admin_tunnel_routes=true
#   Gate 2: config/security-ack.json → present, complete, valid signature
#
# EXIT: 0 = gates satisfied or no restricted admin routes configured
#       1 = gate violation (preflight blocker)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
source "$(dirname "$ROOT")/release/lib/version.sh" 2>/dev/null || true

SELECT_FILE="$ROOT/config/services.select.json"
ACK_FILE="$ROOT/config/security-ack.json"
CATALOG_FILE="$ROOT/config/service-catalog.json"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo ""
echo -e "${CYAN}── Restricted Admin Double-Gate Check ──────────────────${NC}"

# Check if any restricted-admin routes are configured
restricted_routes_enabled=$(python3 - << PYEOF
import json, sys
try:
    sel = json.load(open('$SELECT_FILE'))
    allow = sel.get('security', {}).get('allow_restricted_admin_tunnel_routes', False)
    routes = sel.get('tunnel', {}).get('routes', {})
    # Find any restricted-admin route that is enabled
    try:
        cat = json.load(open('$CATALOG_FILE'))
        restricted_svcs = [s['service'] for s in cat['services'] if s.get('exposure_class') == 'restricted-admin']
    except:
        restricted_svcs = ['pgadmin','portainer','openclaw']
    
    active_restricted = [s for s in restricted_svcs if routes.get(f'TUNNEL_ROUTE_{s.upper()}', False)]
    print('true' if (allow or active_restricted) else 'false')
except Exception as e:
    print('false')
PYEOF
)

if [[ "$restricted_routes_enabled" != "true" ]]; then
  echo -e "  ${GREEN}[OK]${NC}  No restricted-admin tunnel routes configured — gate not required"
  exit 0
fi

echo -e "  ${YELLOW}[!]${NC}   Restricted admin tunnel routes detected — validating both gates..."

# Gate 1: services.select.json flag
gate1=$(python3 -c "
import json
sel = json.load(open('$SELECT_FILE'))
print('pass' if sel.get('security',{}).get('allow_restricted_admin_tunnel_routes', False) else 'fail')
")

if [[ "$gate1" != "pass" ]]; then
  echo -e "  ${RED}[FAIL]${NC} Gate 1: services.select.json → security.allow_restricted_admin_tunnel_routes is not true"
  exit 1
fi
echo -e "  ${GREEN}[OK]${NC}  Gate 1: services.select.json flag set"

# Gate 2: security-ack.json exists and is complete
if [[ ! -f "$ACK_FILE" ]]; then
  echo -e "  ${RED}[FAIL]${NC} Gate 2: config/security-ack.json is missing"
  echo "  → Run: cp tt-core/config/security-ack.json.template tt-core/config/security-ack.json"
  echo "  → Fill all fields, then re-run this script to generate the signature"
  exit 1
fi

# Verify fields are filled
is_template=$(python3 -c "
import json
d = json.load(open('$ACK_FILE'))
print('true' if d.get('_is_template') else 'false')
")
if [[ "$is_template" == "true" ]]; then
  echo -e "  ${RED}[FAIL]${NC} Gate 2: security-ack.json is still a template — fill all fields"
  exit 1
fi

# Verify signature
sig_valid=$(python3 - << PYEOF
import json, hashlib
d = json.load(open('$ACK_FILE'))
parts = [
    d.get('operator_name',''),
    d.get('hostname',''),
    d.get('acknowledged_at',''),
    ','.join(sorted(d.get('services_acknowledged',[])))
]
expected = hashlib.sha256('|'.join(parts).encode()).hexdigest()
actual   = d.get('signature','')
print('pass' if expected == actual else f'fail:{expected}')
PYEOF
)

if [[ "$sig_valid" != "pass" ]]; then
  expected_sig=$(echo "$sig_valid" | cut -d: -f2)
  echo -e "  ${RED}[FAIL]${NC} Gate 2: security-ack.json signature mismatch"
  echo "  → Expected signature: $expected_sig"
  echo "  → Update the 'signature' field in config/security-ack.json with the above value"
  exit 1
fi

echo -e "  ${GREEN}[OK]${NC}  Gate 2: security-ack.json present and signature valid"
echo -e "  ${GREEN}[PASS]${NC} Restricted admin double-gate satisfied"
exit 0
