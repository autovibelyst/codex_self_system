#!/usr/bin/env bash
# =============================================================================
# smoke-test.sh - Profile-aware smoke test
# TT-Production v14.0
#
# Fast health check: docker_healthy + http_200/http_ready for enabled services.
# Emits release/smoke-results.json
#
# EXIT: 0 = all enabled core services healthy
#       1 = one or more core services unhealthy
#       3 = addon degraded (core healthy)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
RUNTIME_ENV_LIB="$SCRIPT_DIR/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"
REPO_ROOT="$(dirname "$ROOT")"
source "$REPO_ROOT/release/lib/version.sh" 2>/dev/null || TT_VERSION="unknown"
[ -n "${TT_VERSION:-}" ] || TT_VERSION="unknown"

CATALOG="$ROOT/config/service-catalog.json"
SELECT="$ROOT/config/services.select.json"
ENV_FILE="$(tt_resolve_core_env_path "$ROOT")"
OUTPUT="$REPO_ROOT/release/smoke-results.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
OVERALL="PASS"

docker_available="yes"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo ""
echo -e "${CYAN}-- Smoke Test - TT-Production ${TT_VERSION} ------------------${NC}"
echo ""

if ! command -v python3 >/dev/null 2>&1; then
  echo -e "${RED}[FAIL]${NC} python3 is required for smoke-test.sh"
  exit 1
fi

# Load runtime env so ${TT_*_HOST_PORT} expansions in probes match compose bindings.
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

sanitize_field() {
  local v="${1:-}"
  v="${v//$'\r'/}"
  v="${v//$'\n'/ }"
  v="${v//$'\t'/ }"
  printf '%s' "$v"
}

# Load enabled services.
# Canonical source is profiles from services.select.json.
# Legacy fallback is enabled_services for older profile files.
mapfile -t ENABLED < <(python3 - "$CATALOG" "$SELECT" << 'PYEOF'
import json, sys
catalog = json.load(open(sys.argv[1], encoding='utf-8'))
select = json.load(open(sys.argv[2], encoding='utf-8'))
profiles = select.get('profiles', {}) or {}
legacy_enabled = set(select.get('enabled_services', []) or [])
enabled = set()

for s in catalog.get('services', []):
    svc = s.get('service')
    if not svc:
        continue
    if s.get('kind') == 'core':
        enabled.add(svc)
        continue

    required = []
    p = s.get('profile')
    if isinstance(p, str) and p.strip():
        required.append(p.strip())

    for ap in (s.get('additional_profiles') or []):
        if isinstance(ap, str) and ap.strip() and ap.strip() not in required:
            required.append(ap.strip())

    if required:
        if all(bool(profiles.get(name, False)) for name in required):
            enabled.add(svc)
    elif svc in legacy_enabled:
        enabled.add(svc)

for svc in sorted(enabled):
    print(svc)
PYEOF
)
for i in "${!ENABLED[@]}"; do
  ENABLED[$i]="$(sanitize_field "${ENABLED[$i]}")"
done

if ! docker info >/dev/null 2>&1; then
  docker_available="no"
  echo -e "${RED}[WARN]${NC} Docker daemon is not reachable; docker_healthy checks will fail."
fi

RESULTS_FILE=$(mktemp)
cleanup() {
  rm -f "$RESULTS_FILE"
}
trap cleanup EXIT

append_result() {
  local service kind status message
  service="$(sanitize_field "$1")"
  kind="$(sanitize_field "$2")"
  status="$(sanitize_field "$3")"
  message="$(sanitize_field "$4")"
  # service\tkind\tstatus\tmessage
  printf '%s\t%s\t%s\t%s\n' "$service" "$kind" "$status" "$message" >> "$RESULTS_FILE"
}

for svc in "${ENABLED[@]}"; do
  svc="$(sanitize_field "$svc")"
  probe_info=$(python3 - "$CATALOG" "$svc" << 'PYEOF'
import json, sys
catalog = json.load(open(sys.argv[1], encoding='utf-8'))
svc = sys.argv[2]
for s in catalog.get('services', []):
    if s.get('service') == svc:
        probe = s.get('health_probe', {})
        ptype = probe.get('type', 'NONE')
        if ptype not in ('docker_healthy', 'http_200', 'http_ready'):
            ptype = 'NONE'
        endpoint = probe.get('endpoint', '')
        kind = s.get('kind', 'addon')
        print(f"{ptype}\t{endpoint}\t{kind}")
        break
PYEOF
  )

  IFS=$'\t' read -r ptype endpoint kind <<< "$probe_info"
  ptype="$(sanitize_field "${ptype:-NONE}")"
  endpoint="$(sanitize_field "${endpoint:-}")"
  kind="$(sanitize_field "${kind:-addon}")"

  status="PASS"
  msg="ok"
  case "$ptype" in
    docker_healthy)
      if [[ "$docker_available" != "yes" ]]; then
        hs="docker_unavailable"
      else
        hs=$(docker inspect --format='{{.State.Health.Status}}' "$endpoint" 2>/dev/null || echo "missing")
      fi
      hs="$(sanitize_field "$hs")"
      if [[ "$hs" != "healthy" ]]; then
        status="FAIL"
        msg="health=$hs"
      fi
      ;;
    http_200|http_ready)
      endpoint_expanded=$(eval "echo \"$endpoint\"" 2>/dev/null || echo "$endpoint")
      endpoint_expanded="$(sanitize_field "$endpoint_expanded")"
      if ! curl -sf --max-time 8 "$endpoint_expanded" >/dev/null 2>&1; then
        status="FAIL"
        msg="unreachable"
      fi
      ;;
    NONE)
      status="SKIPPED"
      msg="no probe"
      ;;
  esac

  status="$(sanitize_field "$status")"
  msg="$(sanitize_field "$msg")"

  if [[ "$status" == "FAIL" ]]; then
    if [[ "$kind" == "core" ]]; then
      OVERALL="FAIL"
    elif [[ "$OVERALL" != "FAIL" ]]; then
      OVERALL="DEGRADED"
    fi
    echo -e "  ${RED}[FAIL]${NC} $svc ($kind) - $msg"
  elif [[ "$status" == "PASS" ]]; then
    echo -e "  ${GREEN}[OK]${NC}   $svc"
  else
    echo -e "  ${YELLOW}[-]${NC}   $svc - $status"
  fi

  append_result "$svc" "$kind" "$status" "$msg"
done

# Mandatory core check: n8n-worker
# Queue-mode execution is broken if this worker is down.
echo ""
echo -e "  ${CYAN}[MANDATORY CORE CHECK]${NC} n8n-worker"
if [[ "$docker_available" != "yes" ]]; then
  N8N_WORKER_STATUS="docker_unavailable"
  N8N_WORKER_HEALTH="docker_unavailable"
else
  N8N_WORKER_STATUS=$(docker inspect --format='{{.State.Status}}' "tt-core-n8n-worker" 2>/dev/null || echo "not_found")
  N8N_WORKER_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "tt-core-n8n-worker" 2>/dev/null || echo "no_healthcheck")
fi
N8N_WORKER_STATUS="$(sanitize_field "$N8N_WORKER_STATUS")"
N8N_WORKER_HEALTH="$(sanitize_field "$N8N_WORKER_HEALTH")"

if [[ "$N8N_WORKER_STATUS" != "running" ]]; then
  echo -e "  ${RED}[FAIL]${NC} n8n-worker - status=$N8N_WORKER_STATUS (CRITICAL: queue execution stopped)"
  OVERALL="FAIL"
  append_result "n8n-worker" "core" "FAIL" "status=$N8N_WORKER_STATUS"
elif [[ "$N8N_WORKER_HEALTH" == "unhealthy" ]]; then
  echo -e "  ${RED}[FAIL]${NC} n8n-worker - health=$N8N_WORKER_HEALTH (CRITICAL: worker is not healthy)"
  OVERALL="FAIL"
  append_result "n8n-worker" "core" "FAIL" "health=$N8N_WORKER_HEALTH"
else
  echo -e "  ${GREEN}[OK]${NC}   n8n-worker - running (health=$N8N_WORKER_HEALTH)"
  append_result "n8n-worker" "core" "PASS" "running"
fi

python3 - "$RESULTS_FILE" "$OUTPUT" "$TIMESTAMP" "$TT_VERSION" "$OVERALL" << 'PYEOF'
import json, sys
results_file, output, ts, version, overall = sys.argv[1:6]
results = []
with open(results_file, encoding='utf-8') as fh:
    for line in fh:
        line = line.rstrip('\n')
        if not line:
            continue
        parts = line.split('\t', 3)
        if len(parts) != 4:
            continue
        svc, kind, status, msg = parts
        results.append({
            "service": svc,
            "kind": kind,
            "status": status,
            "message": msg,
        })
out = {
    "_schema": "tt-smoke-results/v1",
    "_generator": "tt-core/scripts-linux/smoke-test.sh",
    "generated_at": ts,
    "tt_version": version,
    "overall": overall,
    "services": results,
}
with open(output, 'w', encoding='utf-8') as f:
    json.dump(out, f, indent=2)
    f.write('\n')
PYEOF

echo ""
case "$OVERALL" in
  PASS)     echo -e "${GREEN}  SMOKE TEST PASSED${NC}" ;;
  DEGRADED) echo -e "${YELLOW}  SMOKE TEST DEGRADED - addon(s) unhealthy${NC}" ;;
  FAIL)     echo -e "${RED}  SMOKE TEST FAILED${NC}" ;;
esac

[[ "$OVERALL" == "FAIL" ]] && exit 1
[[ "$OVERALL" == "DEGRADED" ]] && exit 3
exit 0


