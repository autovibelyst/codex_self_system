#!/usr/bin/env bash
# =============================================================================
# init.sh — TT-Core first-run initializer (Linux/VPS/macOS)
# Version: v14.0
#
# Usage:
#   bash scripts-linux/init.sh
#   bash scripts-linux/init.sh --root /opt/stacks/tt-core
#
# What this does:
#   1) Creates .env from .env.example (if not present)
#   2) Generates all secrets with openssl (safe to re-run, never overwrites)
#   3) Creates all bind-mount volume directories
#   4) Sets proper file permissions
# =============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

RUNTIME_ENV_LIB="$SCRIPT_DIR/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"
ROTATE_MODE=false
MIGRATE_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)                   ROOT="$2"; shift 2 ;;
    --rotate)                 ROTATE_MODE=true; shift ;;
    --migrate-from-plaintext) MIGRATE_MODE=true; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

CORE_DIR="$ROOT/compose/tt-core"
ENV_EXAMPLE="$ROOT/env/.env.example"
ENV_TARGET="$(tt_runtime_core_env_path "$ROOT")"
LEGACY_ENV_TARGET="$(tt_legacy_core_env_path "$ROOT")"
RUNTIME_DIR="$(dirname "$ENV_TARGET")"
# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; GRAY='\033[0;37m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]${NC}   $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
info() { echo -e "  ${GRAY}[INFO]${NC} $*"; }

echo ""
echo -e "${CYAN}TT-Core Init — v14.0 (Linux)${NC}"
echo -e "${GRAY}  Root: $ROOT${NC}"
echo ""

# ── Validate ──────────────────────────────────────────────────────────────────
if [[ ! -d "$CORE_DIR" ]];    then echo "ERROR: Core dir not found: $CORE_DIR"; exit 1; fi
if [[ ! -f "$ENV_EXAMPLE" ]]; then echo "ERROR: Missing .env.example: $ENV_EXAMPLE"; exit 1; fi

# ── Step 1: Create runtime .env outside repo ──────────────────────────────────
mkdir -p "$RUNTIME_DIR"
if [[ -f "$ENV_TARGET" ]]; then
  info "Runtime env already exists — checking for missing keys..."
elif [[ -f "$LEGACY_ENV_TARGET" ]]; then
  cp "$LEGACY_ENV_TARGET" "$ENV_TARGET"
  chmod 600 "$ENV_TARGET"
  rm -f "$LEGACY_ENV_TARGET"
  ok "Legacy compose/tt-core/.env migrated to external runtime path"
else
  cp "$ENV_EXAMPLE" "$ENV_TARGET"
  chmod 600 "$ENV_TARGET"
  ok "Runtime env created from template at external path"
fi

while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// }" ]] && continue
  key="${line%%=*}"
  [[ -z "$key" ]] && continue
  if ! grep -q "^${key}=" "$ENV_TARGET" 2>/dev/null; then
    warn "MISSING key in runtime env: $key — add from .env.example"
  fi
done < "$ENV_EXAMPLE"

# ── Step 2: Generate secrets (safe — never overwrites) ───────────────────────
echo ""
info "Generating secrets (skips existing)..."

generate_secret_base64() { openssl rand -base64 32 | tr -d '=\n+/'; }
generate_secret_hex()    { openssl rand -hex 24; }

ensure_secret() {
  local key="$1"
  local val
  val=$(grep "^${key}=" "$ENV_TARGET" 2>/dev/null | cut -d= -f2- | xargs 2>/dev/null || true)
  if [[ -z "$val" || "$val" == "__GENERATE__" ]]; then
    local secret
    if [[ "$key" == *"REDIS"* ]] || [[ "$key" == *"TOKEN"* ]]; then
      secret="$(generate_secret_hex)"
    else
      secret="$(generate_secret_base64)"
    fi
    if grep -q "^${key}=" "$ENV_TARGET"; then
      sed -i "s|^${key}=.*|${key}=${secret}|" "$ENV_TARGET"
    else
      echo "${key}=${secret}" >> "$ENV_TARGET"
    fi
    info "  ${key} : [generated]"
  else
    info "  ${key} : [exists, skipped]"
  fi
}

ensure_secret TT_POSTGRES_PASSWORD
ensure_secret TT_REDIS_PASSWORD
# n8n — dedicated DB user
ensure_secret TT_N8N_ENCRYPTION_KEY
ensure_secret TT_N8N_DB_PASSWORD
ensure_secret TT_PGADMIN_PASSWORD
# Per-service DB passwords (DB isolation)
ensure_secret TT_METABASE_DB_PASSWORD
ensure_secret TT_KANBOARD_DB_PASSWORD
ensure_secret TT_WP_DB_PASSWORD
ensure_secret TT_WP_ROOT_PASSWORD
ensure_secret TT_KANBOARD_ADMIN_PASSWORD
ensure_secret TT_OPENCLAW_TOKEN
ensure_secret TT_QDRANT_API_KEY
ensure_secret TT_REDISINSIGHT_PASSWORD
ensure_secret TT_MINIO_PASSWORD
ensure_secret TT_GRAFANA_PASSWORD

ok "Secrets ready."

# ── Rotate mode: re-generate all auto-generated secrets ──────────────────────
if [[ "$ROTATE_MODE" == "true" ]]; then
  echo ""
  warn "ROTATE MODE — this will regenerate ALL auto-generated secrets."
  warn "Services must be restarted after rotation."
  read -r -p "  Confirm rotation? [y/N]: " _confirm
  if [[ "${_confirm,,}" != "y" ]]; then
    echo "  Rotation cancelled."
    exit 0
  fi
  # Force-regenerate all auto-secrets
  for key in TT_POSTGRES_PASSWORD TT_REDIS_PASSWORD TT_N8N_ENCRYPTION_KEY \
             TT_N8N_DB_PASSWORD TT_PGADMIN_PASSWORD TT_METABASE_DB_PASSWORD \
             TT_KANBOARD_DB_PASSWORD TT_WP_DB_PASSWORD TT_WP_ROOT_PASSWORD \
             TT_KANBOARD_ADMIN_PASSWORD TT_OPENCLAW_TOKEN TT_QDRANT_API_KEY \
             TT_REDISINSIGHT_PASSWORD TT_MINIO_PASSWORD TT_GRAFANA_PASSWORD; do
    secret=""
    if [[ "$key" == *"REDIS"* ]] || [[ "$key" == *"TOKEN"* ]]; then
      secret="$(generate_secret_hex)"
    else
      secret="$(generate_secret_base64)"
    fi
    if grep -q "^${key}=" "$ENV_TARGET" 2>/dev/null; then
      sed -i "s|^${key}=.*|${key}=${secret}|" "$ENV_TARGET"
    else
      echo "${key}=${secret}" >> "$ENV_TARGET"
    fi
    info "  ${key} : [rotated]"
  done
  ok "All secrets rotated. Restart all services: bash scripts-linux/start-core.sh"
  echo ""
  exit 0
fi

# ── Migrate from plaintext mode ───────────────────────────────────────────────
if [[ "$MIGRATE_MODE" == "true" ]]; then
  bash "$(dirname "${BASH_SOURCE[0]}")/migrate-to-sops.sh" --root "$ROOT"
  exit $?
fi

# ── Step 3: Create volume directories ────────────────────────────────────────
echo ""
info "Creating bind-mount directories..."

VOLUMES=(
  "volumes/postgres/data"
  "volumes/postgres/init"
  "volumes/redis/data"
  "volumes/n8n"
  "volumes/pgadmin/data"
  "volumes/redisinsight/data"
  "volumes/metabase/data"
  "volumes/metabase/plugins"
  "volumes/uptime-kuma/data"
  "volumes/portainer/data"
  "volumes/mariadb/data"
  "volumes/wordpress/html"
  "volumes/kanboard/data"
  "volumes/kanboard/plugins"
  "volumes/qdrant/storage"
  "volumes/ollama/models"
  "volumes/openwebui/data"
  "volumes/openclaw/data"
  "volumes/openclaw/data/state"
  "volumes/openclaw/data/workspace"
  "volumes/openclaw/config"
)

for vol in "${VOLUMES[@]}"; do
  mkdir -p "$CORE_DIR/$vol"
done

ok "Volume directories created."

# ── Step 4: Permissions ───────────────────────────────────────────────────────
chmod 600 "$ENV_TARGET"
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true

# ── Step 5: Auto-backup schedule (FIX A-12: was dead config, now actually installed) ─
echo ""
SELECT_FILE="$ROOT/config/services.select.json"
if command -v python3 &>/dev/null && [[ -f "$SELECT_FILE" ]]; then
  AUTO_SCHEDULE=$(python3 -c "
import json, sys
with open('$SELECT_FILE') as f:
    d = json.load(f)
print(str(d.get('backup', {}).get('auto_schedule', False)).lower())
" 2>/dev/null || echo "false")
  if [[ "$AUTO_SCHEDULE" == "true" ]]; then
    info "auto_schedule=true detected — installing backup cron job..."
    if bash "$SCRIPT_DIR/setup-backup-schedule.sh" --root "$ROOT"; then
      ok "Backup schedule installed."
    else
      warn "Backup schedule setup failed — run manually: bash scripts-linux/setup-backup-schedule.sh"
    fi
  else
    info "auto_schedule=false — skipping backup cron setup (set backup.auto_schedule=true in config/services.select.json to enable)"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN} TT-Core initialized successfully.${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${GRAY}  .env location : $ENV_TARGET${NC}"
echo -e "${GRAY}  Volumes at    : $CORE_DIR/volumes/${NC}"
echo ""
echo " Next steps:"
echo -e "${GRAY}  1) nano $ENV_TARGET  — set TT_PGADMIN_EMAIL, TT_TZ, TT_BIND_IP${NC}"
echo -e "${GRAY}  2) bash scripts-linux/preflight-check.sh${NC}"
echo -e "${GRAY}  3) bash scripts-linux/start-core.sh${NC}"
echo -e "${GRAY}  4) bash scripts-linux/smoke-test.sh${NC}"
echo ""

# ── Post-init SMTP guidance ───────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo " TT-Core Init Complete — v14.0"
echo "═══════════════════════════════════════════════════"
echo ""
echo " ✅ Auto-generated: all __GENERATE__ secrets"
echo ""
echo " ⚙️  Manual configuration required (optional):"
echo "    TT_SMTP_HOST     — your SMTP server hostname"
echo "    TT_SMTP_USER     — SMTP username"
echo "    TT_SMTP_PASSWORD — SMTP password (not auto-generated)"
echo "    TT_SMTP_FROM     — sender address"
echo ""
echo " Leave SMTP vars empty to disable email notifications."
echo " Config file: $ENV_TARGET"
echo ""

# ── v14.0: SOPS Encryption (appended by v14.0 upgrade) ───────────────────────
# After secrets are generated, encrypt to SOPS format if SOPS is available
_tt_v13_sops_encrypt() {
  local env_file="$ENV_TARGET"
  local enc_file="$ROOT/secrets/core.secrets.enc.env"
  local sops_yaml="$ROOT/secrets/.sops.yaml"

  # Skip if plaintext mode
  local secret_mode
  secret_mode=$(python3 -c "
import json
try:
    sel = json.load(open('$ROOT/config/services.select.json'))
    print(sel.get('client',{}).get('secret_mode','sops'))
except:
    print('sops')
" 2>/dev/null || echo "sops")

  if [[ "$secret_mode" == "plaintext" ]]; then
    echo "  [INFO] TT_SECRET_MODE=plaintext — skipping SOPS encryption (not recommended)"
    return
  fi

  # Align with installer/lib/sops-setup.sh key location unless user overrides.
  if [[ -z "${SOPS_AGE_KEY_FILE:-}" ]]; then
    local tt_age_key_default="$HOME/.config/tt-production/age/key.txt"
    [[ -f "$tt_age_key_default" ]] && export SOPS_AGE_KEY_FILE="$tt_age_key_default"
  fi

  if ! command -v sops &>/dev/null; then
    echo "  [WARN] SOPS not installed — runtime secrets remain in plaintext external env"
    echo "         Run: bash installer/lib/sops-setup.sh to enable SOPS"
    return
  fi

  if grep -q "<OPERATOR_AGE_PUBLIC_KEY>" "$sops_yaml" 2>/dev/null; then
    echo "  [WARN] .sops.yaml not configured — run installer/lib/sops-setup.sh first"
    return
  fi

  if [[ -f "$env_file" ]]; then
    echo "  Encrypting secrets with SOPS + age..."
    mkdir -p "$(dirname "$enc_file")"

    local tmp_plain
    tmp_plain=$(mktemp)
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$env_file" > "$tmp_plain"
    cp "$tmp_plain" "$enc_file"
    rm -f "$tmp_plain"

    if sops --encrypt --config "$sops_yaml" --input-type dotenv --output-type dotenv --in-place "$enc_file" 2>/dev/null; then
      if sops --decrypt "$enc_file" > /dev/null 2>&1; then
        echo "  [OK]  Encrypted: secrets/core.secrets.enc.env"
      else
        echo "  [WARN] SOPS decrypt self-check failed — verify age key and .sops.yaml"
      fi
    else
      echo "  [WARN] SOPS encryption failed — using plaintext external env only"
    fi
  fi
}

# Call the SOPS encrypt function at end of init
_tt_v13_sops_encrypt





