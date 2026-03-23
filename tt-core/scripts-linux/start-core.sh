#!/usr/bin/env bash
# =============================================================================
# start-core.sh — Start TT-Core stack (Linux/VPS/macOS)
# TT-Production v14.0
#
# Usage:
#   bash scripts-linux/start-core.sh
#   bash scripts-linux/start-core.sh --profiles wordpress,metabase,monitoring
#   bash scripts-linux/start-core.sh --root /opt/stacks/tt-core
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
PROFILES_INPUT=""
RUNTIME_ENV_LIB="$SCRIPT_DIR/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT="$2"
      shift 2
      ;;
    --profiles)
      PROFILES_INPUT="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

CORE_DIR="$ROOT/compose/tt-core"
ENV_FILE="$(tt_resolve_core_env_path "$ROOT")"
SELECT_JSON="$ROOT/config/services.select.json"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

sanitize_field() {
  local v="${1:-}"
  v="${v//$'\r'/}"
  v="${v//$'\n'/ }"
  v="${v//$'\t'/ }"
  printf '%s' "$v"
}

# Guard: ensure stack was initialized before starting
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: runtime env not found: $ENV_FILE"
  echo "  Run: bash scripts-linux/init.sh"
  exit 1
fi

# Warn if preflight has not been run (check for sentinel file)
PREFLIGHT_OK="$ROOT/.preflight-passed"
if [[ ! -f "$PREFLIGHT_OK" ]]; then
  echo ""
  echo "WARNING: Preflight check has not been confirmed."
  echo "  It is strongly recommended to run preflight first:"
  echo "    bash scripts-linux/preflight-check.sh"
  echo ""
  echo "  Press Ctrl+C to abort, or wait 5 seconds to continue..."
  sleep 5 || true
fi

profile_flags=()
profile_names=()

if [[ -n "$PROFILES_INPUT" ]]; then
  IFS=',' read -r -a requested_profiles <<< "$PROFILES_INPUT"
  for profile in "${requested_profiles[@]}"; do
    profile="${profile//[[:space:]]/}"
    profile="$(sanitize_field "$profile")"
    [[ -z "$profile" ]] && continue
    profile_flags+=( --profile "$profile" )
    profile_names+=( "$profile" )
  done
elif [[ -f "$SELECT_JSON" ]]; then
  while IFS= read -r profile; do
    profile="$(sanitize_field "$profile")"
    [[ -z "$profile" ]] && continue
    profile_flags+=( --profile "$profile" )
    profile_names+=( "$profile" )
  done < <(python3 - "$SELECT_JSON" <<'PYEOF'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    data = json.load(fh)
for key, value in data.get('profiles', {}).items():
    if value and not str(key).startswith('_'):
        print(key)
PYEOF
)
fi

# Compose files: always core; include only addons that match active profiles.
compose_args=(docker compose -f "$CORE_DIR/docker-compose.yml" --env-file "$ENV_FILE")
if [[ ${#profile_names[@]} -gt 0 ]]; then
  for addon in "$CORE_DIR"/addons/*.addon.yml; do
    [[ -f "$addon" ]] || continue
    addon_profile=$(basename "$addon" .addon.yml | sed 's/^[0-9]*-//')
    addon_profile="$(sanitize_field "$addon_profile")"
    [[ "$addon_profile" == "template" ]] && continue

    include_addon="false"
    for p in "${profile_names[@]}"; do
      if [[ "$p" == "$addon_profile" ]]; then
        include_addon="true"
        break
      fi
    done

    [[ "$include_addon" == "true" ]] && compose_args+=( -f "$addon" )
  done
fi

echo ""
echo -e "${CYAN}Starting TT-Core...${NC}"
echo "  Root: $ROOT"
if [[ ${#profile_names[@]} -gt 0 ]]; then
  echo -e "  ${YELLOW}Profiles:${NC} ${profile_names[*]}"
else
  echo "  Profiles: core only"
fi

"${compose_args[@]}" "${profile_flags[@]}" up -d

echo ""
echo -e "${GREEN}OK: TT-Core started.${NC}"
echo "  Check status: bash scripts-linux/status.sh"
echo ""
