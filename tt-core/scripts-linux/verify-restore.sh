#!/usr/bin/env bash
# =============================================================================
# verify-restore.sh — TT-Core backup verification (Linux/VPS/macOS)
# Version: v14.0
#
# Verifies a backup created by backup.sh without touching live data.
# Validates checksums, decrypts encrypted PostgreSQL dumps into a temp directory,
# and restores them into disposable PostgreSQL/MariaDB containers.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
RUNTIME_ENV_LIB="$SCRIPT_DIR/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"

BACKUP_DIR=""
WEBHOOK_URL=""
ENV_FILE=""
DECRYPT_TMP_DIR=""
PG_TEST_CONTAINER=""
MYSQL_TEST_CONTAINER=""
POSTGRES_IMAGE="postgres:16.6-alpine"
MARIADB_IMAGE="mariadb:11.8.6"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BOLD='\033[1m'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)        ROOT="$2";        shift 2 ;;
    --backup-dir)  BACKUP_DIR="$2";  shift 2 ;;
    --webhook)     WEBHOOK_URL="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

ENV_FILE="$(tt_resolve_core_env_path "$ROOT")"

ok()   { echo -e "  ${GREEN}[OK]${NC}  $*"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; }

notify() {
  local status="$1" msg="$2"
  if [[ -n "$WEBHOOK_URL" ]]; then
    curl -sf -X POST "$WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"text\":\"TT-Core restore verify: ${status} — ${msg}\"}" \
      > /dev/null 2>&1 || true
  fi
}

cleanup() {
  [[ -n "$PG_TEST_CONTAINER" ]] && docker rm -f "$PG_TEST_CONTAINER" > /dev/null 2>&1 || true
  [[ -n "$MYSQL_TEST_CONTAINER" ]] && docker rm -f "$MYSQL_TEST_CONTAINER" > /dev/null 2>&1 || true
  [[ -n "$DECRYPT_TMP_DIR" && -d "$DECRYPT_TMP_DIR" ]] && rm -rf "$DECRYPT_TMP_DIR"
}
trap cleanup EXIT

die() {
  local msg="$1"
  fail "$msg"
  notify "FAIL" "$msg"
  exit 1
}

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

calc_sha256() {
  local file="$1"
  case "$(checksum_tool)" in
    sha256sum) sha256sum "$file" | awk '{print $1}' ;;
    shasum)    shasum -a 256 "$file" | awk '{print $1}' ;;
  esac
}

verify_checksum_manifest() {
  local manifest="$1"
  local failed=0
  local line expected rel actual

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    if [[ ! "$line" =~ ^([A-Fa-f0-9]{64})[[:space:]]+(.+)$ ]]; then
      echo "Malformed checksum entry: $line"
      failed=1
      continue
    fi
    expected="${BASH_REMATCH[1],,}"
    rel="${BASH_REMATCH[2]}"
    if [[ ! -f "$rel" ]]; then
      echo "$rel: MISSING"
      failed=1
      continue
    fi
    actual="$(calc_sha256 "$rel" 2>/dev/null || true)"
    if [[ -z "$actual" || "${actual,,}" != "$expected" ]]; then
      echo "$rel: FAILED"
      failed=1
    fi
  done < "$manifest"

  return "$failed"
}

require_docker() {
  command -v docker &>/dev/null || die "Docker is required for dry-restore verification."
  docker info > /dev/null 2>&1 || die "Docker daemon is not reachable."
}

wait_for_postgres() {
  local tries=0
  until docker exec "$PG_TEST_CONTAINER" pg_isready -U postgres > /dev/null 2>&1; do
    tries=$((tries + 1))
    [[ "$tries" -ge 30 ]] && die "Temporary PostgreSQL validator did not become ready."
    sleep 1
  done
}

wait_for_mariadb() {
  local tries=0
  until docker exec "$MYSQL_TEST_CONTAINER" mariadb-admin ping -uroot -pverifytest123 --silent > /dev/null 2>&1; do
    tries=$((tries + 1))
    [[ "$tries" -ge 40 ]] && die "Temporary MariaDB validator did not become ready."
    sleep 1
  done
}

start_postgres_validator() {
  PG_TEST_CONTAINER="tt-verify-restore-pg-$$"
  docker run -d --rm --name "$PG_TEST_CONTAINER" \
    -e POSTGRES_PASSWORD=verifytest123 \
    "$POSTGRES_IMAGE" > /dev/null 2>&1 \
    || die "Could not start temporary PostgreSQL validator container."
  info "Started temporary PostgreSQL validator ($POSTGRES_IMAGE)"
  wait_for_postgres
}

start_mariadb_validator() {
  MYSQL_TEST_CONTAINER="tt-verify-restore-mariadb-$$"
  docker run -d --rm --name "$MYSQL_TEST_CONTAINER" \
    -e MARIADB_ROOT_PASSWORD=verifytest123 \
    -e MARIADB_DATABASE=wordpress \
    "$MARIADB_IMAGE" > /dev/null 2>&1 \
    || die "Could not start temporary MariaDB validator container."
  info "Started temporary MariaDB validator ($MARIADB_IMAGE)"
  wait_for_mariadb
}

decrypt_dump_if_needed() {
  local dump_file="$1"
  local encrypt_key="$2"

  if [[ "$dump_file" != *.dump.enc ]]; then
    printf '%s\n' "$dump_file"
    return 0
  fi

  [[ -n "$encrypt_key" ]] || die "Encrypted dump found but TT_BACKUP_ENCRYPTION_KEY is not set in runtime env."
  command -v openssl &>/dev/null || die "Encrypted dump found but openssl is not available."

  if [[ -z "$DECRYPT_TMP_DIR" ]]; then
    DECRYPT_TMP_DIR="$(mktemp -d)"
    info "Created temp directory for decrypted dump validation: $DECRYPT_TMP_DIR"
  fi

  local plain_name
  plain_name="$(basename "${dump_file%.enc}")"
  local out_file="$DECRYPT_TMP_DIR/$plain_name"
  if openssl enc -d -aes-256-cbc -pbkdf2 \
      -in "$dump_file" -out "$out_file" \
      -pass pass:"$encrypt_key" 2>/dev/null; then
    ok "Decrypted $(basename "$dump_file")"
    printf '%s\n' "$out_file"
  else
    die "Decryption failed for $(basename "$dump_file") — wrong key or corrupted backup."
  fi
}

validate_postgres_dump() {
  local work_file="$1"
  local db_name
  db_name="$(basename "$work_file" .dump)"
  local container_path="/tmp/${db_name}.dump"

  docker exec "$PG_TEST_CONTAINER" createdb -U postgres "$db_name" > /dev/null 2>&1 || true
  docker cp "$work_file" "$PG_TEST_CONTAINER:$container_path" > /dev/null 2>&1 \
    || die "Could not copy $(basename "$work_file") into validator container."

  if docker exec "$PG_TEST_CONTAINER" sh -lc \
      "pg_restore -U postgres -d '$db_name' --schema-only --clean --if-exists -Fc '$container_path'" \
      > /dev/null 2>&1; then
    ok "Schema restore verified: ${db_name}.dump"
  else
    docker exec "$PG_TEST_CONTAINER" rm -f "$container_path" > /dev/null 2>&1 || true
    die "Schema restore failed for ${db_name}.dump"
  fi

  docker exec "$PG_TEST_CONTAINER" rm -f "$container_path" > /dev/null 2>&1 || true
}

validate_wordpress_dump() {
  local wp_sql="$1"
  if docker exec -i -e MYSQL_PWD=verifytest123 "$MYSQL_TEST_CONTAINER" \
      mariadb -uroot wordpress < "$wp_sql" > /dev/null 2>&1; then
    ok "WordPress SQL import verified: $(basename "$wp_sql")"
  else
    die "WordPress SQL import failed for $(basename "$wp_sql")"
  fi
}

if [[ -z "$BACKUP_DIR" ]]; then
  BACKUP_DIR=$(find "$ROOT/backups" -maxdepth 1 -name "backup_*" -type d 2>/dev/null | sort | tail -1 || true)
  [[ -n "$BACKUP_DIR" ]] || die "No backups found in $ROOT/backups"
fi
[[ "${BACKUP_DIR:0:1}" != "/" ]] && BACKUP_DIR="$ROOT/$BACKUP_DIR"

POSTGRES_DIR="$BACKUP_DIR/postgres"
CHECKSUM_FILE="$BACKUP_DIR/checksums.sha256"
WORDPRESS_SQL="$BACKUP_DIR/wordpress.sql"

echo ""
echo -e "${BOLD}TT-Core Backup Verification${NC}"
echo -e "${CYAN}Backup: $BACKUP_DIR${NC}"
echo -e "${CYAN}Mode: disposable dry-restore (no live data affected)${NC}"
echo ""

echo "── 1. Backup directory check ───────────────────────────"
[[ -d "$BACKUP_DIR" ]] || die "Backup directory not found: $BACKUP_DIR"
ok "Directory exists"

echo "── 2. SHA256 checksum verification ────────────────────"
[[ -f "$CHECKSUM_FILE" ]] || die "checksums.sha256 not found in backup."
checksum_tool > /dev/null 2>&1 || die "No SHA-256 verification tool found (sha256sum or shasum)."
pushd "$BACKUP_DIR" > /dev/null
if verify_checksum_manifest "$(basename "$CHECKSUM_FILE")"; then
  ok "All backup artifact checksums verified"
else
  verify_checksum_manifest "$(basename "$CHECKSUM_FILE")" || true
  popd > /dev/null
  die "Checksum verification failed."
fi
popd > /dev/null

echo "── 3. PostgreSQL dump presence check ───────────────────"
[[ -d "$POSTGRES_DIR" ]] || die "No postgres/ directory in backup."
mapfile -t DUMP_FILES < <(find "$POSTGRES_DIR" -maxdepth 1 -type f \( -name "*.dump" -o -name "*.dump.enc" \) | sort)
[[ "${#DUMP_FILES[@]}" -gt 0 ]] || die "No PostgreSQL dump artifacts (.dump / .dump.enc) found in postgres/."
ok "Found ${#DUMP_FILES[@]} PostgreSQL dump artifact(s)"

echo "── 4. Disposable restore test ─────────────────────────"
require_docker
start_postgres_validator

ENCRYPT_KEY=""
if printf '%s\n' "${DUMP_FILES[@]}" | grep -qE '\.dump\.enc$'; then
  ENCRYPT_KEY="$(get_env TT_BACKUP_ENCRYPTION_KEY "")"
  [[ -n "$ENCRYPT_KEY" ]] || die "Encrypted dumps detected but TT_BACKUP_ENCRYPTION_KEY is not set in runtime env."
fi

for dump_file in "${DUMP_FILES[@]}"; do
  work_file="$(decrypt_dump_if_needed "$dump_file" "$ENCRYPT_KEY")"
  validate_postgres_dump "$work_file"
done

if [[ -f "$WORDPRESS_SQL" ]]; then
  start_mariadb_validator
  validate_wordpress_dump "$WORDPRESS_SQL"
else
  info "No wordpress.sql found — MariaDB validation skipped"
fi

echo ""
echo "────────────────────────────────────────────────────"
echo -e "${GREEN}${BOLD}Backup verification PASSED${NC}"
echo -e "  Backup: $(basename "$BACKUP_DIR")"
echo -e "  PostgreSQL dumps verified: ${#DUMP_FILES[@]}"
if [[ -f "$WORDPRESS_SQL" ]]; then
  echo -e "  WordPress SQL verified: yes"
else
  echo -e "  WordPress SQL verified: not present"
fi
echo ""
notify "PASS" "Backup $(basename "$BACKUP_DIR") verified successfully"
exit 0
