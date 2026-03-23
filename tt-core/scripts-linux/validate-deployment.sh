#!/usr/bin/env bash
# =============================================================================
# validate-deployment.sh - Profile-aware validation matrix
# TT-Production v14.0
#
# Derives expected service probes from service-catalog.json + services.select.json.
# Emits release/validation-matrix.json on completion.
#
# EXIT: 0 = PASS
#       1 = FAIL (core service probe failed or policy violation)
#       3 = DEGRADED (addon probe failed)
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
OUTPUT="$REPO_ROOT/release/validation-matrix.json"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
OVERALL="PASS"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START_MS=$(($(date +%s%3N)))
docker_available="yes"

echo ""
echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}  TT-Core Validation Matrix - ${TT_VERSION}${NC}"
echo -e "${CYAN}======================================================${NC}"
echo ""

if ! command -v python3 >/dev/null 2>&1; then
  echo -e "${RED}[FAIL]${NC} python3 is required for validate-deployment.sh"
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

if ! docker info >/dev/null 2>&1; then
  docker_available="no"
  echo -e "${RED}[WARN]${NC} Docker daemon is not reachable; docker_healthy checks will fail."
fi

# Enabled set is canonical from profiles + core, with legacy enabled_services fallback.
mapfile -t ENABLED_SERVICES < <(python3 - "$CATALOG" "$SELECT" << 'PYEOF'
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
for i in "${!ENABLED_SERVICES[@]}"; do
  ENABLED_SERVICES[$i]="$(sanitize_field "${ENABLED_SERVICES[$i]}")"
done

mapfile -t ALL_SERVICES < <(python3 - "$CATALOG" << 'PYEOF'
import json, sys
catalog = json.load(open(sys.argv[1], encoding='utf-8'))
for s in catalog.get('services', []):
    svc = s.get('service')
    if svc:
        print(svc)
PYEOF
)
for i in "${!ALL_SERVICES[@]}"; do
  ALL_SERVICES[$i]="$(sanitize_field "${ALL_SERVICES[$i]}")"
done

run_probe() {
  local probe_type="$1" endpoint="$2" timeout_s="${3:-10}"
  local start
  start=$(($(date +%s%3N)))

  case "$probe_type" in
    http_200|http_ready)
      endpoint=$(eval "echo \"$endpoint\"" 2>/dev/null || echo "$endpoint")
      endpoint="$(sanitize_field "$endpoint")"
      if curl -sf --max-time "$timeout_s" "$endpoint" >/dev/null 2>&1; then
        echo "PASS:$(($(date +%s%3N)-start)):connected"
      else
        echo "FAIL:$(($(date +%s%3N)-start)):endpoint unreachable"
      fi
      ;;
    docker_healthy)
      local status
      if [[ "$docker_available" != "yes" ]]; then
        status="docker_unavailable"
      else
        status=$(docker inspect --format='{{.State.Health.Status}}' "$endpoint" 2>/dev/null || echo "missing")
      fi
      status="$(sanitize_field "$status")"
      if [[ "$status" == "healthy" ]]; then
        echo "PASS:$(($(date +%s%3N)-start)):healthy"
      else
        echo "FAIL:$(($(date +%s%3N)-start)):health=$status"
      fi
      ;;
    tcp_connect)
      local host port
      host=$(echo "$endpoint" | cut -d: -f1)
      port=$(echo "$endpoint" | cut -d: -f2)
      if timeout "$timeout_s" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        echo "PASS:$(($(date +%s%3N)-start)):port open"
      else
        echo "FAIL:$(($(date +%s%3N)-start)):port closed"
      fi
      ;;
    env_set)
      local val
      if [[ ! -f "$ENV_FILE" ]]; then
        echo "FAIL:0:env file missing"
      else
        val=$(grep -E "^${endpoint}=." "$ENV_FILE" 2>/dev/null | head -1 || true)
        if [[ -n "$val" ]]; then
          echo "PASS:0:var set"
        else
          echo "FAIL:0:var not set"
        fi
      fi
      ;;
    NONE)
      echo "SKIPPED:0:no probe defined"
      ;;
    *)
      echo "WARN:0:unknown probe type: $probe_type"
      ;;
  esac
}

get_service_probe() {
  local svc="$1"
  python3 - "$CATALOG" "$svc" << 'PYEOF'
import json, sys
catalog = json.load(open(sys.argv[1], encoding='utf-8'))
svc = sys.argv[2]
for s in catalog.get('services', []):
    if s.get('service') == svc:
        probe = s.get('health_probe', {})
        ptype = probe.get('type', 'NONE')
        endpoint = probe.get('endpoint', '')
        timeout = str(probe.get('timeout_secs', '10'))
        kind = s.get('kind', 'addon')
        exposure = s.get('exposure_class', 'unknown')
        route_name = s.get('route_name') or s.get('service') or ''
        print(f"{ptype}\t{endpoint}\t{timeout}\t{kind}\t{exposure}\t{route_name}")
        break
PYEOF
}

get_service_meta() {
  local svc="$1"
  python3 - "$CATALOG" "$svc" << 'PYEOF'
import json, sys
catalog = json.load(open(sys.argv[1], encoding='utf-8'))
svc = sys.argv[2]
for s in catalog.get('services', []):
    if s.get('service') == svc:
        print(f"{s.get('kind','addon')}\t{s.get('exposure_class','')}")
        break
PYEOF
}

route_is_enabled() {
  local route_name="$1"
  python3 - "$SELECT" "$route_name" << 'PYEOF'
import json, sys
select = json.load(open(sys.argv[1], encoding='utf-8'))
route = sys.argv[2]
routes = select.get('tunnel', {}).get('routes', {})
print('yes' if bool(routes.get(route, False)) else 'no')
PYEOF
}

RESULTS_FILE=$(mktemp)
VIOLATIONS_FILE=$(mktemp)
cleanup() {
  rm -f "$RESULTS_FILE" "$VIOLATIONS_FILE"
}
trap cleanup EXIT

append_result() {
  local service kind enabled probe_type probe_endpoint status duration_ms message exposure_class
  service="$(sanitize_field "$1")"
  kind="$(sanitize_field "$2")"
  enabled="$(sanitize_field "$3")"
  probe_type="$(sanitize_field "$4")"
  probe_endpoint="$(sanitize_field "$5")"
  status="$(sanitize_field "$6")"
  duration_ms="$(sanitize_field "$7")"
  message="$(sanitize_field "$8")"
  exposure_class="$(sanitize_field "$9")"
  # service\tkind\tenabled\tprobe_type\tprobe_endpoint\tstatus\tduration_ms\tmessage\texposure_class
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$service" "$kind" "$enabled" "$probe_type" "$probe_endpoint" "$status" "$duration_ms" "$message" "$exposure_class" >> "$RESULTS_FILE"
}

for svc in "${ENABLED_SERVICES[@]}"; do
  svc="$(sanitize_field "$svc")"
  probe_info=$(get_service_probe "$svc")
  IFS=$'\t' read -r probe_type endpoint timeout kind exposure_class route_name <<< "$probe_info"

  probe_type="$(sanitize_field "${probe_type:-NONE}")"
  endpoint="$(sanitize_field "${endpoint:-}")"
  timeout="$(sanitize_field "${timeout:-10}")"
  kind="$(sanitize_field "${kind:-addon}")"
  exposure_class="$(sanitize_field "${exposure_class:-unknown}")"
  route_name="$(sanitize_field "${route_name:-$svc}")"

  # Policy check: local-only service must never have an enabled tunnel route.
  if [[ "$exposure_class" == "never-exposed" || "$exposure_class" == "local-only" ]]; then
    tunnel_active=$(route_is_enabled "$route_name" 2>/dev/null || echo "no")
    tunnel_active="$(sanitize_field "$tunnel_active")"
    if [[ "$tunnel_active" == "yes" ]]; then
      printf '%s\n' "$(sanitize_field "$svc: exposure_class=$exposure_class but route '$route_name' is enabled")" >> "$VIOLATIONS_FILE"
      OVERALL="FAIL"
    fi
  fi

  result=$(run_probe "$probe_type" "$endpoint" "$timeout")
  status=$(echo "$result" | cut -d: -f1)
  duration=$(echo "$result" | cut -d: -f2)
  message=$(echo "$result" | cut -d: -f3-)

  status="$(sanitize_field "$status")"
  duration="$(sanitize_field "$duration")"
  message="$(sanitize_field "$message")"

  if [[ "$status" == "FAIL" ]]; then
    if [[ "$kind" == "core" ]]; then
      OVERALL="FAIL"
      echo -e "  ${RED}[FAIL]${NC} $svc ($kind) - $message"
    else
      if [[ "$OVERALL" != "FAIL" ]]; then
        OVERALL="DEGRADED"
      fi
      echo -e "  ${YELLOW}[WARN]${NC} $svc ($kind addon) - $message"
    fi
  elif [[ "$status" == "PASS" ]]; then
    echo -e "  ${GREEN}[OK]${NC}   $svc - $message (${duration}ms)"
  else
    echo -e "  ${YELLOW}[-]${NC}   $svc - $status"
  fi

  append_result "$svc" "$kind" "true" "$probe_type" "$endpoint" "$status" "$duration" "$message" "$exposure_class"
done

for svc in "${ALL_SERVICES[@]}"; do
  svc="$(sanitize_field "$svc")"
  is_enabled="false"
  for e in "${ENABLED_SERVICES[@]}"; do
    e="$(sanitize_field "$e")"
    if [[ "$e" == "$svc" ]]; then
      is_enabled="true"
      break
    fi
  done

  if [[ "$is_enabled" == "false" ]]; then
    meta=$(get_service_meta "$svc")
    IFS=$'\t' read -r kind exposure <<< "$meta"
    kind="$(sanitize_field "${kind:-addon}")"
    exposure="$(sanitize_field "${exposure:-}")"
    append_result "$svc" "$kind" "false" "NONE" "" "SKIPPED" "0" "service not enabled" "$exposure"
  fi
done

if [[ -s "$VIOLATIONS_FILE" ]]; then
  echo ""
  echo -e "${RED}  Policy Violations:${NC}"
  while IFS= read -r v; do
    echo -e "  ${RED}[POLICY]${NC} $v"
  done < "$VIOLATIONS_FILE"
fi

TOTAL_MS=$(( $(date +%s%3N) - START_MS ))
python3 - "$RESULTS_FILE" "$VIOLATIONS_FILE" "$OUTPUT" "$TIMESTAMP" "$TT_VERSION" "$OVERALL" "$TOTAL_MS" << 'PYEOF'
import json, sys
results_file, violations_file, output, ts, version, overall, total_ms = sys.argv[1:8]

results = []
with open(results_file, encoding='utf-8') as fh:
    for line in fh:
        line = line.rstrip('\n')
        if not line:
            continue
        parts = line.split('\t', 8)
        if len(parts) != 9:
            continue
        svc, kind, enabled, probe_type, probe_endpoint, status, duration, message, exposure = parts
        results.append({
            "service": svc,
            "kind": kind,
            "enabled": enabled.lower() == 'true',
            "probe_type": probe_type,
            "probe_endpoint": (probe_endpoint if probe_endpoint else None),
            "status": status,
            "duration_ms": int(duration),
            "message": message,
            "exposure_class": exposure,
        })

violations = []
with open(violations_file, encoding='utf-8') as fh:
    for line in fh:
        line = line.strip()
        if line:
            violations.append(line)

matrix = {
    "_schema": "tt-validation-matrix/v1",
    "_generator": "tt-core/scripts-linux/validate-deployment.sh",
    "generated_at": ts,
    "tt_version": version,
    "overall_result": overall,
    "total_duration_ms": int(total_ms),
    "services": results,
    "policy_violations": violations,
}

with open(output, 'w', encoding='utf-8') as f:
    json.dump(matrix, f, indent=2)
    f.write('\n')

print(f"  Matrix written: {len(results)} services evaluated")
PYEOF

echo ""
echo -e "${CYAN}======================================================${NC}"
case "$OVERALL" in
  PASS)     echo -e "${GREEN}  VALIDATION PASSED${NC}" ;;
  DEGRADED) echo -e "${YELLOW}  VALIDATION DEGRADED - addon(s) unhealthy${NC}" ;;
  FAIL)     echo -e "${RED}  VALIDATION FAILED - see details above${NC}" ;;
esac
echo -e "${CYAN}======================================================${NC}"

[[ "$OVERALL" == "FAIL" ]] && exit 1
[[ "$OVERALL" == "DEGRADED" ]] && exit 3
exit 0

