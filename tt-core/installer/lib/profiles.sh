#!/usr/bin/env bash
# installer/lib/profiles.sh — Profile Loader and Validator
# TT-Production v14.0

PROFILES_DIR="$(dirname "${BASH_SOURCE[0]}")/../../config/profiles"
CATALOG_FILE="$(dirname "${BASH_SOURCE[0]}")/../../config/service-catalog.json"

list_profiles() {
  for f in "$PROFILES_DIR"/*.json; do
    name=$(basename "$f" .json)
    desc=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('description',''))" 2>/dev/null || echo "")
    echo "  $name — $desc"
  done
}

apply_profile() {
  local profile_name="$1"
  local select_file="$2"
  local profile_file="$PROFILES_DIR/${profile_name}.json"

  if [[ ! -f "$profile_file" ]]; then
    echo "ERROR: Profile '$profile_name' not found in $PROFILES_DIR" >&2
    return 1
  fi

  # Validate: profile cannot enable local_only services via tunnel
  # Validate: profile cannot disable core services
  python3 - "$profile_file" "$CATALOG_FILE" "$select_file" << 'PYEOF'
import json, sys

profile_f, catalog_f, select_f = sys.argv[1:]
profile = json.load(open(profile_f))
catalog = json.load(open(catalog_f))

cat_map = {s['service']: s for s in catalog['services']}
errors = []

for svc in profile.get('enabled_services', []):
    info = cat_map.get(svc, {})
    tier = info.get('tier','')
    if tier == 'local_only' and svc in profile.get('tunnel_routes', {}):
        errors.append(f"Profile violation: {svc} is local_only but profile tries to tunnel it")

for svc in cat_map:
    if cat_map[svc].get('kind') == 'core' and svc in profile.get('disabled_services', []):
        errors.append(f"Profile violation: cannot disable core service {svc}")

if errors:
    for e in errors:
        print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)

# Merge profile into services.select.json
try:
    sel = json.load(open(select_f))
except:
    sel = {}

sel['enabled_services'] = list(set(sel.get('enabled_services', []) + profile.get('enabled_services', [])))
if 'tunnel' not in sel:
    sel['tunnel'] = {'routes': {}}
sel['tunnel']['routes'].update(profile.get('tunnel_routes', {}))

with open(select_f, 'w') as f:
    json.dump(sel, f, indent=2)
print(f"Profile '{profile.get('name', 'unknown')}' applied successfully")
PYEOF
}

