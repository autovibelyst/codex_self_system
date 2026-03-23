#!/usr/bin/env bash
# =============================================================================
# TT-Core Preflight Check — v14.0 (27 checks)
# Validates configuration before first start or after changes.
#
# Usage:
#   bash scripts-linux/preflight-check.sh
#   bash scripts-linux/preflight-check.sh --include-supabase
#   bash scripts-linux/preflight-check.sh --root /path/to/tt-core
#
# Exit codes:
#   0 = all checks passed (warnings may still be printed)
#   1 = one or more blocking issues found
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISSUES=()
WARNINGS=()
INCLUDE_SUPABASE=false
RUNTIME_ENV_LIB="$ROOT/scripts-linux/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)             ROOT="$2"; shift 2 ;;
    --include-supabase) INCLUDE_SUPABASE=true; shift ;;
    *)                  echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# Source canonical version
if [[ -f "$(dirname "$ROOT")/release/lib/version.sh" ]]; then
  source "$(dirname "$ROOT")/release/lib/version.sh"
else
  TT_VERSION="unknown"
fi

fail()  { ISSUES+=("$1"); }
warn()  { WARNINGS+=("$1"); }
pass()  { echo -e "  \033[32m[OK]\033[0m  $1"; }

get_env_value() { grep -E "^${2}=" "$1" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r'; }
env_contains_placeholder() { grep -qF "$2" "$1" 2>/dev/null; }

# Cross-platform file mtime (GNU stat first, BSD stat fallback)
get_mtime_epoch() {
  local file="$1"
  if stat -c %Y "$file" >/dev/null 2>&1; then
    stat -c %Y "$file"
    return 0
  fi
  if stat -f %m "$file" >/dev/null 2>&1; then
    stat -f %m "$file"
    return 0
  fi
  echo 0
  return 1
}

is_profile_enabled() {
  local profile="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "false"
    return 0
  fi
  python3 - "$SELECT_FILE" "$profile" << 'PYEOF'
import json, sys
path, profile = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
print('true' if bool(data.get('profiles', {}).get(profile, False)) else 'false')
PYEOF
}

is_tunnel_enabled() {
  if ! command -v python3 >/dev/null 2>&1 || [[ ! -f "$SELECT_FILE" ]]; then
    echo "false"
    return 0
  fi
  python3 - "$SELECT_FILE" << 'PYEOF'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    data = json.load(f)
print('true' if bool(data.get('tunnel', {}).get('enabled', False)) else 'false')
PYEOF
}

get_secret_mode() {
  local mode=""

  # Canonical source is services.select.json (installer + init use this).
  if command -v python3 >/dev/null 2>&1 && [[ -f "$SELECT_FILE" ]]; then
    mode=$(python3 - "$SELECT_FILE" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], encoding='utf-8') as f:
        data = json.load(f)
    print(str(data.get('client', {}).get('secret_mode', '')).strip().lower())
except Exception:
    print('')
PYEOF
)
  fi

  # Backward compatibility fallback: TT_SECRET_MODE in .env
  if [[ -z "$mode" && -f "$ENV_FILE" ]]; then
    mode=$(get_env_value "$ENV_FILE" "TT_SECRET_MODE" 2>/dev/null || echo "")
    mode=$(echo "$mode" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  fi

  case "$mode" in
    plaintext|sops) echo "$mode" ;;
    "")             echo "sops" ;;
    *)
      warn "Unknown secret mode '$mode' — defaulting to sops checks"
      echo "sops"
      ;;
  esac
}

is_placeholder_value() {
  local val="$1"
  [[ -z "$val" ]] && return 0
  [[ "$val" == "__GENERATE__" ]] && return 0
  [[ "$val" == "__CLIENT_NAME__" ]] && return 0
  [[ "$val" == "__CLIENT_DOMAIN__" ]] && return 0
  [[ "$val" == "__CLIENT_TIMEZONE__" ]] && return 0
  [[ "$val" == "__CF_TUNNEL_TOKEN__" ]] && return 0
  return 1
}

ENV_FILE="$(tt_resolve_core_env_path "$ROOT")"
SELECT_FILE="$ROOT/config/services.select.json"
CATALOG_FILE="$ROOT/config/service-catalog.json"
TUNNEL_ENV_FILE="$(tt_resolve_tunnel_env_path "$ROOT")"
ACK_FILE="$ROOT/config/security-ack.json"
SOPS_YAML="$ROOT/secrets/.sops.yaml"
ADDONS_DIR="$ROOT/compose/tt-core/addons"
PREFLIGHT_SENTINEL="$ROOT/.preflight-passed"
FORBIDDEN_DEV_AGE_KEY="age1qprwg5fxspev023zhv2thdrl7k6gx5rkv9rfenc2k0w0txj5c9vs5hk7yc"

# Use the project-managed age key location when available.
TT_AGE_KEY_DEFAULT="$HOME/.config/tt-production/age/key.txt"
if [[ -z "${SOPS_AGE_KEY_FILE:-}" && -f "$TT_AGE_KEY_DEFAULT" ]]; then
  export SOPS_AGE_KEY_FILE="$TT_AGE_KEY_DEFAULT"
fi

echo ""
echo -e "\033[36m══════════════════════════════════════════════════════\033[0m"
echo -e "\033[36m  TT-Core Preflight Check — ${TT_VERSION} (27 checks)  \033[0m"
echo -e "\033[36m══════════════════════════════════════════════════════\033[0m"
echo ""

# ── 1. Required Files ────────────────────────────────────────────────────────
echo "── 1. Required Files ──────────────────────────────────────────"
for req in "$SELECT_FILE" "$CATALOG_FILE"; do
  [[ -f "$req" ]] && pass "$req" || fail "Missing required file: $req"
done

# ── 2. Placeholder Detection ────────────────────────────────────────────────
echo "── 2. Placeholder Detection ────────────────────────────────────"
if [[ -f "$ENV_FILE" ]]; then
  # Check only keys required for currently enabled core services.
  REQUIRED_KEYS=(
    TT_TZ
    TT_POSTGRES_PASSWORD
    TT_REDIS_PASSWORD
    TT_N8N_ENCRYPTION_KEY
    TT_N8N_DB_PASSWORD
    TT_PGADMIN_PASSWORD
    TT_REDISINSIGHT_PASSWORD
  )
  for key in "${REQUIRED_KEYS[@]}"; do
    val=$(get_env_value "$ENV_FILE" "$key" 2>/dev/null || echo "")
    if is_placeholder_value "$val"; then
      warn ".env key '$key' still has placeholder/empty value"
    fi
  done
  pass "runtime env exists: $ENV_FILE"
else
  fail "runtime env not found — run init.sh first"
fi

# ── 2b. Template Secret Safety ───────────────────────────────────────────────
CORE_TEMPLATE="$ROOT/compose/tt-core/.env.example"
if [[ -f "$CORE_TEMPLATE" ]]; then
  if grep -Eq '^[[:space:]]*TT_MINIO_PASSWORD[[:space:]]*=[[:space:]]*$' "$CORE_TEMPLATE"; then
    fail "compose/tt-core/.env.example: TT_MINIO_PASSWORD is empty — use __GENERATE__"
  fi
  if grep -Eq '^[[:space:]]*TT_GRAFANA_PASSWORD[[:space:]]*=[[:space:]]*$' "$CORE_TEMPLATE"; then
    fail "compose/tt-core/.env.example: TT_GRAFANA_PASSWORD is empty — use __GENERATE__"
  fi
fi

# ── 3. Network Binding ──────────────────────────────────────────────────────
echo "── 3. Network Binding ──────────────────────────────────────────"
BIND_IP=$(get_env_value "$ENV_FILE" "TT_BIND_IP" 2>/dev/null || echo "")
if [[ "$BIND_IP" == "0.0.0.0" ]]; then
  warn "TT_BIND_IP=0.0.0.0 — all ports exposed on LAN. Use 127.0.0.1 unless intentional."
elif [[ -n "$BIND_IP" ]]; then
  pass "TT_BIND_IP=$BIND_IP"
else
  warn "TT_BIND_IP not set in .env — defaulting to 127.0.0.1"
fi

# ── 4. Tunnel Configuration ─────────────────────────────────────────────────
echo "── 4. Tunnel Configuration ─────────────────────────────────────"
tunnel_enabled=$(is_tunnel_enabled 2>/dev/null || echo "false")
if [[ "$tunnel_enabled" == "true" ]]; then
  if [[ -f "$TUNNEL_ENV_FILE" ]]; then
    TOKEN=$(get_env_value "$TUNNEL_ENV_FILE" "CF_TUNNEL_TOKEN")
    if [[ -z "$TOKEN" || "$TOKEN" == *"__"* ]]; then
      warn "Tunnel is enabled but CF_TUNNEL_TOKEN is missing/placeholder"
    else
      pass "CF_TUNNEL_TOKEN is set"
    fi
  else
    warn "Tunnel is enabled but runtime tunnel env is missing"
  fi
else
  pass "Tunnel disabled in services.select.json (local-only mode)"
fi

# ── 5. Docker & Compose Versions ────────────────────────────────────────────
echo "── 5. Docker & Compose Versions ────────────────────────────────"
if command -v docker &>/dev/null; then
  DOCKER_VER=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0")
  pass "Docker: $DOCKER_VER"
else
  fail "Docker not found"
fi
if docker compose version &>/dev/null 2>&1; then
  COMPOSE_VER=$(docker compose version --short 2>/dev/null || echo "0")
  pass "Docker Compose: $COMPOSE_VER"
else
  fail "Docker Compose v2 not found"
fi

# ── 6. PostgreSQL Secret Strength ───────────────────────────────────────────
echo "── 6. Secret Strength ──────────────────────────────────────────"
if [[ -f "$ENV_FILE" ]]; then
  for key in TT_POSTGRES_PASSWORD TT_REDIS_PASSWORD TT_N8N_ENCRYPTION_KEY; do
    val=$(get_env_value "$ENV_FILE" "$key")
    len=${#val}
    if [[ $len -lt 16 ]]; then
      fail "$key too short ($len chars, min 16)"
    elif [[ $len -lt 32 ]]; then
      warn "$key: $len chars (recommend >=32)"
      pass "$key length: $len chars (adequate)"
    else
      pass "$key length: $len chars"
    fi
  done
fi

# ── 7–15. Port availability, disk, memory (condensed) ───────────────────────
echo "── 7. Resource Checks ──────────────────────────────────────────"
if command -v df >/dev/null 2>&1; then
  DISK_FREE=$(df -BG / 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G\r')
  if [[ "${DISK_FREE:-}" =~ ^[0-9]+$ ]]; then
    [[ "$DISK_FREE" -lt 10 ]] && warn "Low disk space: ${DISK_FREE}GB free (recommend >=10GB)" || pass "Disk: ${DISK_FREE}GB free"
  else
    warn "Could not parse free disk space from df output"
  fi
else
  warn "df command not available — skipping disk space check"
fi

if command -v free >/dev/null 2>&1; then
  MEM_FREE=$(free -m 2>/dev/null | awk '/^Mem/{print $7}' | tr -d '\r')
  if [[ "${MEM_FREE:-}" =~ ^[0-9]+$ ]]; then
    [[ "$MEM_FREE" -lt 1024 ]] && warn "Low available memory: ${MEM_FREE}MB (recommend >=2GB free)" || pass "Memory: ${MEM_FREE}MB available"
  else
    warn "Could not parse available memory from free output"
  fi
elif [[ -r /proc/meminfo ]]; then
  MEM_KB=$(awk '/^MemAvailable:/ {print $2; found=1; exit} /^MemFree:/ {if(!fallback) fallback=$2} END {if(!found && fallback) print fallback}' /proc/meminfo | tr -d '\r')
  if [[ "${MEM_KB:-}" =~ ^[0-9]+$ ]]; then
    MEM_FREE=$((MEM_KB / 1024))
    [[ "$MEM_FREE" -lt 1024 ]] && warn "Low available memory: ${MEM_FREE}MB (recommend >=2GB free)" || pass "Memory: ${MEM_FREE}MB available"
  else
    warn "Could not parse available memory from /proc/meminfo"
  fi
else
  warn "free command not available — skipping memory check"
fi

# ── 16. Redis password ───────────────────────────────────────────────────────
echo "── 16. Redis Password ──────────────────────────────────────────"
if [[ -f "$ENV_FILE" ]]; then
  REDIS_PASS=$(get_env_value "$ENV_FILE" "TT_REDIS_PASSWORD")
  [[ -z "$REDIS_PASS" ]] && fail "TT_REDIS_PASSWORD is empty" || pass "TT_REDIS_PASSWORD is set"
fi

# ── 17–22. Image checks ──────────────────────────────────────────────────────
echo "── 17. Service Config JSON ─────────────────────────────────────"
if command -v python3 &>/dev/null && [[ -f "$CATALOG_FILE" ]]; then
  if python3 - "$CATALOG_FILE" << 'PYEOF' >/dev/null 2>&1
import json, sys
json.load(open(sys.argv[1], encoding='utf-8'))
PYEOF
  then
    pass "service-catalog.json is valid JSON"
  else
    fail "service-catalog.json is invalid JSON"
  fi
fi
if command -v python3 &>/dev/null && [[ -f "$SELECT_FILE" ]]; then
  if python3 - "$SELECT_FILE" << 'PYEOF' >/dev/null 2>&1
import json, sys
json.load(open(sys.argv[1], encoding='utf-8'))
PYEOF
  then
    pass "services.select.json is valid JSON"
  else
    fail "services.select.json is invalid JSON"
  fi
fi

# ── 23. Security Acknowledgment (NEW v14.0) ──────────────────────────────────
echo "── 23. Restricted Admin Security Acknowledgment (NEW v14.0) ────"
if [[ -f "$SELECT_FILE" ]] && command -v python3 &>/dev/null; then
  ALLOW_RESTRICTED=$(python3 -c "
import json
sel = json.load(open('$SELECT_FILE'))
print('true' if sel.get('security',{}).get('allow_restricted_admin_tunnel_routes', False) else 'false')
" 2>/dev/null || echo "false")
  if [[ "$ALLOW_RESTRICTED" == "true" ]]; then
    if [[ ! -f "$ACK_FILE" ]]; then
      fail "Restricted admin routes enabled but config/security-ack.json is missing"
      fail "→ Complete security-ack.json and run scripts-linux/verify-security-ack.sh"
    else
      IS_TEMPLATE=$(python3 -c "import json; d=json.load(open('$ACK_FILE')); print(d.get('_is_template','false'))" 2>/dev/null || echo "true")
      if [[ "$IS_TEMPLATE" == "true" ]]; then
        fail "config/security-ack.json is still a template — fill all fields"
      else
        bash "$ROOT/scripts-linux/verify-security-ack.sh" 2>/dev/null \
          && pass "security-ack.json: both gates verified" \
          || fail "security-ack.json: gate verification failed — run verify-security-ack.sh"
      fi
    fi
  else
    pass "No restricted admin tunnel routes — security-ack.json not required"
  fi
fi

# ── 24. Image Lock Presence (STRICT v14.0) ───────────────────────────────────
echo "── 24. Image Lock Presence (STRICT v14.0) ──────────────────────"
LOCK_FILE="$(dirname "$ROOT")/release/image-inventory.lock.json"
if [[ ! -f "$LOCK_FILE" ]]; then
  fail "release/image-inventory.lock.json not found — bundle must ship with a complete image lock"
else
  pass "Image lock file present"
fi

# ── 25. Image Lock Completeness ──────────────────────────────────────────────
echo "── 25. Image Lock Completeness ─────────────────────────────────"
if [[ -f "$LOCK_FILE" ]] && command -v python3 &>/dev/null; then
  readarray -t LOCK_STATE < <(python3 -c "
import json
lock = json.load(open('$LOCK_FILE'))
images = lock.get('images', [])
latest = sum(1 for img in images if str(img.get('source_tag', '')).strip().lower() == 'latest')
null_digests = sum(1 for img in images if not img.get('resolved_digest'))
bad_status = sum(1 for img in images if str(img.get('digest_status')) != 'resolved')
print(lock.get('lock_status', 'missing'))
print(lock.get('unresolved_count', 0))
print(latest)
print(null_digests)
print(bad_status)
" 2>/dev/null || echo "0")
  LOCK_STATUS="${LOCK_STATE[0]:-missing}"
  UNRESOLVED="${LOCK_STATE[1]:-0}"
  LATEST_IN_LOCK="${LOCK_STATE[2]:-0}"
  NULL_DIGESTS="${LOCK_STATE[3]:-0}"
  BAD_STATUS="${LOCK_STATE[4]:-0}"
  if [[ "$LOCK_STATUS" != "complete" ]]; then
    fail "Image lock status is '$LOCK_STATUS' — expected 'complete'"
  elif [[ "$UNRESOLVED" -gt 0 || "$LATEST_IN_LOCK" -gt 0 || "$NULL_DIGESTS" -gt 0 || "$BAD_STATUS" -gt 0 ]]; then
    fail "Image lock incomplete — unresolved=$UNRESOLVED latest=$LATEST_IN_LOCK null_digests=$NULL_DIGESTS bad_status=$BAD_STATUS"
  else
    pass "Image lock: all digests resolved"
  fi
elif [[ -f "$LOCK_FILE" ]]; then
  fail "python3 is required to validate image lock completeness"
fi

# ── 26. No :latest Tags ──────────────────────────────────────────────────────
echo "── 26. No :latest Image Tags (NEW v14.0) ───────────────────────"
LATEST_FOUND=0
for f in "$ROOT/compose/tt-core/docker-compose.yml" "$ROOT/compose/tt-core/addons/"*.addon.yml; do
  [[ -f "$f" ]] || continue

  if grep -E "^\s+image:.*:latest" "$f" 2>/dev/null; then
    fail "$(basename "$f"): contains :latest image tag — pin to explicit version"
    LATEST_FOUND=1
  fi
done
[[ $LATEST_FOUND -eq 0 ]] && pass "No :latest image tags found in compose/addon files"

# ── 27. SOPS Availability (NEW v14.0) ────────────────────────────────────────
echo "── 27. SOPS Secret Mode (NEW v14.0) ────────────────────────────"
SECRET_MODE=$(get_secret_mode)

if [[ -f "$SOPS_YAML" ]]; then
  if grep -q "$FORBIDDEN_DEV_AGE_KEY" "$SOPS_YAML"; then
    fail "secrets/.sops.yaml contains forbidden developer age key"
  fi
else
  warn "secrets/.sops.yaml not found — SOPS mode cannot be fully validated"
fi

if [[ "$SECRET_MODE" == "plaintext" ]]; then
  warn "secret_mode=plaintext — SOPS hardening not active (not recommended for production)"
elif command -v sops &>/dev/null; then
  ENC_FILE="$ROOT/secrets/core.secrets.enc.env"
  if [[ -f "$ENC_FILE" ]]; then
    sops --decrypt "$ENC_FILE" > /dev/null 2>&1 \
      && pass "SOPS: binary present, core.secrets.enc.env decrypts" \
      || fail "SOPS: decrypt failed — check age key at ~/.config/tt-production/age/key.txt"
  else
    warn "SOPS binary present but secrets/core.secrets.enc.env not found — run init.sh"
  fi
else
  warn "secret_mode=sops but SOPS binary not installed — run installer/lib/sops-setup.sh"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "\033[36m══════════════════════════════════════════════════════\033[0m"
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo -e "\033[33m  Warnings (${#WARNINGS[@]}):\033[0m"
  for w in "${WARNINGS[@]}"; do echo -e "  \033[33m[WARN]\033[0m $w"; done
fi
if [[ ${#ISSUES[@]} -gt 0 ]]; then
  echo -e "\033[31m  Blocking Issues (${#ISSUES[@]}):\033[0m"
  for i in "${ISSUES[@]}"; do echo -e "  \033[31m[FAIL]\033[0m $i"; done
  echo ""
  echo -e "\033[31m  PREFLIGHT FAILED — resolve issues before starting.\033[0m"
  echo -e "\033[36m══════════════════════════════════════════════════════\033[0m"
  exit 1
else
  printf '%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$PREFLIGHT_SENTINEL" 2>/dev/null || true
  [[ -f "$PREFLIGHT_SENTINEL" ]] && pass "Preflight sentinel updated: $PREFLIGHT_SENTINEL"
  echo -e "\033[32m  PREFLIGHT PASSED — all 27 checks complete.\033[0m"
  echo -e "\033[36m══════════════════════════════════════════════════════\033[0m"
fi





