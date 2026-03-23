#!/usr/bin/env bash
# backup.sh — TT-Core backup (Linux/VPS/macOS)
# Version: v14.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
RUNTIME_ENV_LIB="$SCRIPT_DIR/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2 ;; *) shift ;; esac; done

COMPOSE_DIR="$ROOT/compose/tt-core"
ENV_FILE="$(tt_resolve_core_env_path "$ROOT")"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$ROOT/backups/backup_${STAMP}"
POSTGRES_DIR="$BACKUP_DIR/postgres"
mkdir -p "$POSTGRES_DIR"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]   ${NC}$*"; }
warn() { echo -e "  ${YELLOW}[WARN] ${NC}$*"; }
section() { echo ""; echo -e "${CYAN}$*${NC}"; }
echo -e "${CYAN}TT-Core Backup — $(date)${NC}"
echo "  Output: $BACKUP_DIR"
echo ""

get_env() {
  local key="$1" default="${2:-}"
  if [[ -f "$ENV_FILE" ]]; then
    local line
    line=$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 || true)
    if [[ -n "$line" ]]; then
      echo "${line#*=}" | tr -d '\r'
      return
    fi
  fi
  echo "$default"
}

checksum_tool() {
  if command -v sha256sum &>/dev/null; then
    echo "sha256sum"
  elif command -v shasum &>/dev/null; then
    echo "shasum"
  else
    return 1
  fi
}

write_backup_checksums() {
  local out_file="$1"
  local tool
  tool="$(checksum_tool)" || return 1

  pushd "$BACKUP_DIR" > /dev/null
  : > "$out_file"
  while IFS= read -r -d '' rel; do
    rel="${rel#./}"
    case "$tool" in
      sha256sum) sha256sum "$rel" >> "$out_file" ;;
      shasum)    shasum -a 256 "$rel" >> "$out_file" ;;
    esac
  done < <(find . -type f \( -name "*.dump" -o -name "*.dump.enc" -o -name "*.sql" -o -name "*.tar.gz" \) \
    -not -path "./$(basename "$out_file")" -print0)
  popd > /dev/null
}

# ── Pre-backup health check (introduced v9.4+) ──────────────────────────────────────
# Verify postgres is running before investing time creating backup directory.
echo "  Pre-backup check..."
PG_RUNNING=$(docker ps --filter 'name=tt-core-postgres' --filter 'status=running' --quiet 2>/dev/null || true)
if [[ -z "$PG_RUNNING" ]]; then
  echo -e "${YELLOW}  [WARN] PostgreSQL not running — DB dumps will be skipped.${NC}"
  echo -e "${YELLOW}         For a full backup, start the stack first.${NC}"
  BACKUP_PARTIAL=true
else
  echo "    [OK] PostgreSQL running"
  BACKUP_PARTIAL=false
fi


# ── n8n Workflows Export (v14.0) ─────────────────────────────────────────────
section "n8n Workflow Backup"
N8N_API_KEY=$(get_env "TT_N8N_API_KEY" "" 2>/dev/null || echo "")
N8N_PORT=$(get_env "TT_N8N_HOST_PORT" "15678")
WORKFLOWS_DIR="$BACKUP_DIR/n8n-workflows"
mkdir -p "$WORKFLOWS_DIR"
if [[ -n "$N8N_API_KEY" ]]; then
  if curl -sf -H "X-N8N-API-KEY: $N8N_API_KEY" \
      "http://127.0.0.1:$N8N_PORT/api/v1/workflows" \
      > "$WORKFLOWS_DIR/workflows-${STAMP}.json" 2>/dev/null; then
    WF_COUNT=$(python3 -c "import json; d=json.load(open('$WORKFLOWS_DIR/workflows-${STAMP}.json')); print(len(d.get('data', d if isinstance(d,list) else [])))" 2>/dev/null || echo "?")
    ok "n8n workflows exported: $WF_COUNT workflow(s) → n8n-workflows/workflows-${STAMP}.json"
  else
    warn "n8n workflow export failed — is n8n running? (API key is set)"
    rm -f "$WORKFLOWS_DIR/workflows-${STAMP}.json"
  fi
else
  warn "TT_N8N_API_KEY not set — n8n workflows NOT backed up. Set in runtime env and regenerate from n8n Settings → API."
fi

# ── Notification helper (uses TT_BACKUP_NOTIFY_WEBHOOK_URL if set) ────────────
# Separate failure/success notifications for full observability
_notify_webhook() {
  local msg="$1"
  local WEBHOOK_URL
  WEBHOOK_URL=$(get_env TT_BACKUP_NOTIFY_WEBHOOK_URL "")
  if [[ -n "$WEBHOOK_URL" ]]; then
    curl -s -X POST "$WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"text\":\"${msg}\"}" \
      >/dev/null 2>&1 || true
  fi
}

notify_failure() {
  local msg="$1"
  _notify_webhook "❌ TT-Core Backup FAILED on $(hostname -s 2>/dev/null || echo host): ${msg}"
  echo -e "${YELLOW}  [NOTIFY] Failure notification sent.${NC}"
}

notify_success() {
  local size="$1" stamp="$2"
  _notify_webhook "✅ TT-Core Backup OK on $(hostname -s 2>/dev/null || echo host): ${size} — stamp: ${stamp}"
  echo -e "${GREEN}  [NOTIFY] Success notification sent.${NC}"
}

PG_USER=$(get_env TT_POSTGRES_USER ttcore)
PG_PASS=$(get_env TT_POSTGRES_PASSWORD "")
PG_DB=$(get_env TT_POSTGRES_DB ttcore)
N8N_DB=$(get_env TT_N8N_DB n8n)
MB_DB=$(get_env TT_METABASE_DB metabase_db)
KB_DB=$(get_env TT_KANBOARD_DB kanboard_db)
mapfile -t DBS < <(printf '%s\n' "$PG_DB" "$N8N_DB" "$MB_DB" "$KB_DB" | awk 'NF && !seen[$0]++')

get_postgres_container() {
  local cid
  cid=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" ps -q postgres 2>/dev/null | head -1 || true)
  [[ -n "$cid" ]] && { echo "$cid"; return 0; }
  cid=$(docker ps --filter 'name=tt-core-postgres' --filter 'status=running' --quiet | head -1 || true)
  [[ -n "$cid" ]] && { echo "$cid"; return 0; }
  return 1
}

PG_CID=""
if PG_CID=$(get_postgres_container); then
  echo "  Dumping PostgreSQL databases..."
  ENCRYPT_KEY=$(get_env TT_BACKUP_ENCRYPTION_KEY "")
  for db in "${DBS[@]}"; do
    dump_file="$POSTGRES_DIR/${db}.dump"
    tmp_file="/tmp/${db}.dump"
    if docker exec -e PGPASSWORD="$PG_PASS" "$PG_CID" sh -lc "pg_dump -U '$PG_USER' -Fc '$db' -f '$tmp_file'" >/dev/null 2>&1; then
      docker cp "${PG_CID}:${tmp_file}" "$dump_file" >/dev/null
      docker exec "$PG_CID" rm -f "$tmp_file" >/dev/null 2>&1 || true
      # ── Encryption (v14.0) ─────────────────────────────────────────────────
      # If TT_BACKUP_ENCRYPTION_KEY is set, encrypt the dump with AES-256-CBC.
      # The unencrypted dump is removed after successful encryption.
      # Decryption: openssl enc -d -aes-256-cbc -pbkdf2 -in ${db}.dump.enc -out ${db}.dump -pass pass:"$KEY"
      if [[ -n "$ENCRYPT_KEY" ]]; then
        if openssl enc -aes-256-cbc -salt -pbkdf2 \
            -in "$dump_file" -out "${dump_file}.enc" \
            -pass pass:"$ENCRYPT_KEY" 2>/dev/null; then
          rm -f "$dump_file"
          echo "    [OK] ${db}.dump.enc (encrypted)"
        else
          echo -e "${YELLOW}    [WARN] encryption failed for ${db}.dump — storing unencrypted${NC}"
        fi
      else
        echo "    [OK] ${db}.dump"
      fi
    else
      echo "    [SKIP] ${db} (may not exist or is not initialized yet)"
    fi
  done
else
  echo -e "${YELLOW}  [WARN] Postgres container not running — database dumps skipped${NC}"
fi

# MariaDB/WordPress mysqldump — reliable SQL-level restoration
WP_ROOT_PASS=$(get_env TT_WP_ROOT_PASSWORD "")
MARIA_CID=$(docker ps --filter 'name=tt-core-mariadb' --filter 'status=running' --quiet 2>/dev/null | head -1 || true)
if [[ -n "$MARIA_CID" ]] && [[ -n "$WP_ROOT_PASS" ]]; then
  echo "  Dumping MariaDB (WordPress)..."
  WP_DUMP="$BACKUP_DIR/wordpress.sql"
  if docker exec -e MYSQL_PWD="$WP_ROOT_PASS" "$MARIA_CID" \
       mysqldump -u root wordpress > "$WP_DUMP" 2>/dev/null; then
    echo "    [OK] wordpress.sql (mysqldump)"
  else
    echo -e "    ${YELLOW}[WARN] mysqldump failed — falling back to volume backup${NC}"
    rm -f "$WP_DUMP"
  fi
else
  [[ -n "$MARIA_CID" ]] || echo "    [INFO] MariaDB not running — WordPress SQL dump skipped"
fi

VOLUMES_DIR="$COMPOSE_DIR/volumes"
echo "  Archiving volumes..."
if [[ -d "$VOLUMES_DIR" ]]; then
  tar --exclude='volumes/ollama/models' \
      --exclude='volumes/postgres/data' \
      --exclude='volumes/openclaw/data/workspace' \
      -czf "$BACKUP_DIR/volumes-${STAMP}.tar.gz" \
      -C "$COMPOSE_DIR" "volumes" 2>/dev/null \
    && echo "    [OK] volumes archived (postgres/data, ollama/models, openclaw/workspace excluded)" \
    || echo "    [WARN] volume archive had issues"
fi

if [[ -f "$ENV_FILE" ]]; then
  cp "$ENV_FILE" "$BACKUP_DIR/.env.backup"
  echo "    [OK] .env backed up"
fi

# SHA256 checksums for all dumps — verified on restore
echo "  Computing checksums..."
CHECKSUM_FILE="$BACKUP_DIR/checksums.sha256"
if checksum_tool &>/dev/null; then
  write_backup_checksums "$CHECKSUM_FILE" 2>/dev/null || true
  [[ -s "$CHECKSUM_FILE" ]] && echo "    [OK] checksums.sha256 generated" || echo "    [INFO] no backup artifacts to checksum"
else
  echo "    [WARN] no SHA-256 tool available — checksums.sha256 not generated"
fi

cat > "$BACKUP_DIR/backup-manifest.txt" <<EOF
TT-Core backup manifest
stamp=${STAMP}
created_at=$(date -Is)
compose_dir=${COMPOSE_DIR}
postgres_container=${PG_CID:-not_running}
databases=${DBS[*]}
checksums=checksums.sha256
partial=${BACKUP_PARTIAL:-false}
EOF

echo ""
if [[ "${BACKUP_PARTIAL:-false}" == "true" ]]; then
  echo -e "${YELLOW}Backup complete (PARTIAL — stack was not running): $BACKUP_DIR${NC}"
  notify_failure "Backup completed but PostgreSQL was not running — DB dumps skipped. Backup: $BACKUP_DIR"
else
  BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "unknown")
  echo -e "${GREEN}Backup complete: $BACKUP_DIR  [${BACKUP_SIZE}]${NC}"
  # ── OpenClaw volume backup (v9.4 addition) ──────────────────────────────────
OPENCLAW_VOL="$ROOT/compose/tt-core/volumes/openclaw"
if [[ -d "$OPENCLAW_VOL" ]]; then
  OPENCLAW_OUT="$BACKUP_DIR/volumes"
  mkdir -p "$OPENCLAW_OUT"
  tar -czf "$OPENCLAW_OUT/openclaw.tar.gz" -C "$(dirname "$OPENCLAW_VOL")" "$(basename "$OPENCLAW_VOL")" 2>/dev/null &&     echo "    [OK] openclaw volume archived" ||     echo "    [SKIP] openclaw volume (may be empty)"
fi

notify_success "$BACKUP_SIZE" "$STAMP"
fi
echo ""
