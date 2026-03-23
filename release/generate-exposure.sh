#!/usr/bin/env bash
# generate-exposure.sh - TT-Production exposure artifact generator
# Regenerates:
#   tt-core/config/public-exposure.policy.json
#   release/exposure-summary.json
#   release/exposure-summary.md
#
# Usage: bash release/generate-exposure.sh [--root /path/to/bundle]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(dirname "$SCRIPT_DIR")}" 

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

source "$SCRIPT_DIR/lib/version.sh" 2>/dev/null || TT_VERSION="v14.0"
PKG_VER="${TT_VERSION:-v14.0}"

CATALOG="$ROOT/tt-core/config/service-catalog.json"
SELECT="$ROOT/tt-core/config/services.select.json"
POLICY_OUT="$ROOT/tt-core/config/public-exposure.policy.json"
SUMMARY_MD="$ROOT/release/exposure-summary.md"
SUMMARY_JSON="$ROOT/release/exposure-summary.json"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
TIMESTAMP=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

[[ -f "$CATALOG" ]] || { echo "ERROR: service-catalog.json not found at $CATALOG"; exit 1; }
[[ -f "$SELECT" ]]  || { echo "ERROR: services.select.json not found at $SELECT"; exit 1; }

echo -e "${CYAN}Generating exposure policy and summary...${NC}"

python3 - "$CATALOG" "$SELECT" "$POLICY_OUT" "$SUMMARY_JSON" "$SUMMARY_MD" "$TIMESTAMP" "$PKG_VER" << 'PYEOF'
import json
import sys

catalog_path, select_path, policy_out, summary_json_out, summary_md_out, generated_at, pkg_ver = sys.argv[1:8]

with open(catalog_path, encoding='utf-8') as f:
    catalog = json.load(f)
with open(select_path, encoding='utf-8') as f:
    select_data = json.load(f)

services = []
for svc in catalog.get('services', []):
    obj = {
        'service': svc.get('service'),
        'profile': svc.get('profile'),
        'tier': svc.get('tier'),
        'public_capable': bool(svc.get('public_capable', False)),
        'auto_start_tunnel': bool(svc.get('auto_start_tunnel', False)),
        'display_name': svc.get('display_name', svc.get('service', 'unknown')),
    }

    if 'tunnel' in svc and isinstance(svc['tunnel'], dict):
        tun = svc['tunnel']
        obj['toggle'] = tun.get('toggle')
        obj['subdomain_var'] = tun.get('subdomain_var')
        obj['placeholder'] = tun.get('placeholder')
        obj['rule_key'] = tun.get('rule_key')

    if 'route_name' in svc:
        obj['route_name'] = svc.get('route_name')
    if 'requires_explicit_ack' in svc:
        obj['requires_explicit_ack'] = bool(svc.get('requires_explicit_ack'))

    services.append(obj)

policy = {
    '_comment': 'GENERATED FILE - do not edit manually. Regenerate: bash release/generate-exposure.sh',
    '_generator': 'release/generate-exposure.sh',
    '_generated_at': generated_at,
    'generated_from': 'config/service-catalog.json',
    'generated_version': pkg_ver,
    'services': services,
}

with open(policy_out, 'w', encoding='utf-8') as f:
    json.dump(policy, f, indent=2)
    f.write('\n')
print('  Written: tt-core/config/public-exposure.policy.json')

domain = select_data.get('client', {}).get('domain', '__NOT_SET__')
tunnel_enabled = bool(select_data.get('tunnel', {}).get('enabled', False))
allow_restricted = bool(select_data.get('security', {}).get('allow_restricted_admin_tunnel_routes', False))
routes = select_data.get('tunnel', {}).get('routes', {}) or {}
subdomains = select_data.get('tunnel', {}).get('subdomains', {}) or {}

active_routes = []
blocked_admin_routes = []
local_only = []

for svc in catalog.get('services', []):
    service_name = svc.get('service')
    display_name = svc.get('display_name', service_name)
    tier = svc.get('tier', 'local_only')
    public_capable = bool(svc.get('public_capable', False))
    route_name = svc.get('route_name', service_name)

    if (not public_capable) or tier == 'local_only':
        local_only.append({'service': service_name, 'display_name': display_name, 'reason': 'local_only by design'})
        continue

    is_enabled = bool(routes.get(route_name, False))
    is_restricted = tier == 'restricted_admin'
    sub = subdomains.get(route_name, route_name)
    hostname = f"{sub}.{domain}" if domain != '__NOT_SET__' else f"{sub}.<domain>"

    if is_enabled and tunnel_enabled:
        if is_restricted and not allow_restricted:
            blocked_admin_routes.append({
                'service': service_name,
                'display_name': display_name,
                'hostname': hostname,
                'reason': 'restricted_admin requires allow_restricted_admin_tunnel_routes=true',
            })
        else:
            active_routes.append({
                'service': service_name,
                'display_name': display_name,
                'hostname': hostname,
                'tier': tier,
                'requires_ack': bool(svc.get('requires_explicit_ack', False)),
                'ack_given': allow_restricted if is_restricted else None,
            })

summary_json = {
    '_comment': 'GENERATED - do not edit. Regenerate: bash release/generate-exposure.sh',
    '_generator': 'release/generate-exposure.sh',
    '_generated_at': generated_at,
    'generated_at': generated_at,
    'package_version': pkg_ver,
    'tunnel_enabled': tunnel_enabled,
    'domain': domain,
    'allow_restricted_admin': allow_restricted,
    'active_public_routes': active_routes,
    'blocked_admin_routes': blocked_admin_routes,
    'local_only_services': [s['service'] for s in local_only],
    'risk_summary': {
        'public_surfaces': len(active_routes),
        'restricted_admin_blocked': len(blocked_admin_routes),
        'restricted_admin_exposed': sum(1 for r in active_routes if r.get('tier') == 'restricted_admin'),
        'all_clear': (len(active_routes) == 0) or all(
            (r.get('tier') != 'restricted_admin') or bool(r.get('ack_given')) for r in active_routes
        ),
    },
}

with open(summary_json_out, 'w', encoding='utf-8') as f:
    json.dump(summary_json, f, indent=2)
    f.write('\n')
print('  Written: release/exposure-summary.json')

lines = [
    '# TT-Core Exposure Summary',
    '',
    '> **GENERATED FILE** - do not edit. Regenerate: `bash release/generate-exposure.sh`  ',
    f"> Generated: {summary_json['_generated_at']}  ",
    f"> Package: {summary_json['package_version']}",
    '',
    '---',
    '',
    '## Current Configuration',
    '',
    '| Parameter | Value |',
    '|-----------|-------|',
    f"| Tunnel Enabled | {'Yes' if tunnel_enabled else 'No'} |",
    f"| Domain | `{domain}` |",
    f"| Restricted Admin Acknowledged | {'Yes' if allow_restricted else 'No'} |",
    f"| Active Public Routes | {len(active_routes)} |",
    f"| Blocked Admin Routes | {len(blocked_admin_routes)} |",
    '',
]

if active_routes:
    lines += ['## Active Public Routes', '', '| Service | Hostname | Tier | Admin ACK |', '|---------|----------|------|-----------|']
    for route in active_routes:
        if route.get('tier') == 'restricted_admin':
            ack = 'Yes' if route.get('ack_given') else 'No'
        else:
            ack = 'N/A'
        lines.append(f"| {route['display_name']} | `{route['hostname']}` | {route['tier']} | {ack} |")
    lines.append('')
else:
    lines += ['## Active Public Routes', '', 'No public routes currently active.', '']

if blocked_admin_routes:
    lines += [
        '## Blocked Admin Routes (Protected)',
        '',
        'These restricted admin services are blocked until allow_restricted_admin_tunnel_routes=true:',
        '',
        '| Service | Hostname | Status |',
        '|---------|----------|--------|',
    ]
    for route in blocked_admin_routes:
        lines.append(f"| {route['display_name']} | `{route['hostname']}` | Blocked |")
    lines.append('')

lines += ['## Local-Only Services (Never Exposed)', '', '| Service | Reason |', '|---------|--------|']
for svc in local_only:
    lines.append(f"| {svc['display_name']} | {svc['reason']} |")

lines += [
    '',
    '---',
    '',
    '**Security verdict:** ' + ('All clear - no unauthorized admin exposure' if summary_json['risk_summary']['all_clear'] else 'Review required - restricted admin surfaces exposed'),
]

with open(summary_md_out, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')
print('  Written: release/exposure-summary.md')
PYEOF

echo -e "${GREEN}Exposure policy and summary regenerated successfully${NC}"

