#!/usr/bin/env bash
# installer/lib/summary.sh — Post-Install Summary Generator
# TT-Production v14.0
# Usage: source installer/lib/summary.sh && print_install_summary

print_install_summary() {
  local catalog="${1:-$(dirname "${BASH_SOURCE[0]}")/../../config/service-catalog.json}"
  local select="${2:-$(dirname "${BASH_SOURCE[0]}")/../../config/services.select.json}"
  local version="${TT_VERSION:-unknown}"

  [[ ! -f "$catalog" || ! -f "$select" ]] && return

  echo ""
  printf '%s\n' "══════════════════════════════════════════════════════"
  printf "  TT-Production %s — Installation Summary\n" "$version"
  printf '%s\n' "══════════════════════════════════════════════════════"

  python3 - "$catalog" "$select" << 'PYEOF'
import json, sys

catalog_f, select_f = sys.argv[1], sys.argv[2]
catalog = json.load(open(catalog_f))
select  = json.load(open(select_f))

enabled_set   = set(select.get('enabled_services', []))
tunnel_routes = select.get('tunnel', {}).get('routes', {})
allow_admin   = select.get('security', {}).get('allow_restricted_admin_tunnel_routes', False)
bind_ip       = select.get('client', {}).get('bind_ip', '127.0.0.1')
secret_mode   = select.get('client', {}).get('secret_mode', 'SOPS+age')

core, local_only, tunneled, restricted, disabled = [], [], [], [], []

for s in catalog['services']:
    svc  = s['service']
    kind = s.get('kind','addon')
    tier = s.get('tier','')
    exp  = s.get('exposure_class','')
    name = s.get('display_name', svc)

    is_enabled = (kind == 'core' or svc in enabled_set)
    if not is_enabled:
        disabled.append(name)
        continue

    route_key   = f"TUNNEL_ROUTE_{svc.upper()}"
    tunnel_on   = tunnel_routes.get(route_key, False)
    is_admin    = (exp == 'restricted-admin')
    is_local    = (exp in ('never-exposed','local-only') or tier == 'local_only')

    if is_admin:
        restricted.append((name, tunnel_on, allow_admin))
    elif is_local or not tunnel_on:
        local_only.append(name)
    else:
        tunneled.append(name)

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; NC='\033[0m'

print(f"\n  Bind IP: {bind_ip}")
print(f"  Secret Mode: {secret_mode}")

print(f"\n  LOCAL SERVICES (not publicly exposed):")
for s in local_only:
    print(f"    ✓ {s}")

if tunneled:
    print(f"\n  TUNNEL-EXPOSED SERVICES (configure DNS):")
    for s in tunneled:
        print(f"    ✓ {s} → add DNS A record to your domain")

if restricted:
    print(f"\n  RESTRICTED ADMIN SERVICES:")
    for name, on, allowed in restricted:
        if on and allowed:
            print(f"    ⚠ {name} → tunnel ENABLED (high risk — read RESTRICTED_ADMIN_GUIDE.md)")
        else:
            print(f"    ✓ {name} → tunnel disabled (recommended)")

if disabled:
    print(f"\n  DISABLED ADDONS:")
    for s in disabled:
        print(f"    - {s}")

print(f"\n  NEXT STEPS:")
print(f"    1. bash scripts-linux/start-core.sh")
print(f"    2. bash scripts-linux/smoke-test.sh")
if tunneled:
    print(f"    3. Configure DNS for tunneled services above")
    print(f"    4. bash scripts-linux/start-tunnel.sh")
PYEOF

  echo ""
  printf '%s\n' "══════════════════════════════════════════════════════"
  echo ""
}

