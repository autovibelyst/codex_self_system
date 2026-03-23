#!/usr/bin/env bash
# support-bundle.sh — TT-Core v14.0
# Generates a safe support bundle for debugging and post-sale support.
# NO SECRETS are included. Safe to share with support teams.
#
# Output: backups/support-bundle-YYYYMMDD-HHMMSS.tar.gz
#
# Usage: bash scripts-linux/support-bundle.sh [--root /path/to/tt-core]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
RUNTIME_ENV_LIB="$SCRIPT_DIR/lib/runtime-env.sh"
# shellcheck disable=SC1090
source "$RUNTIME_ENV_LIB"
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2 ;; *) shift ;; esac; done

STAMP="$(date +%Y%m%d-%H%M%S)"
BUNDLE_DIR="$ROOT/backups/support-bundle-${STAMP}"
BUNDLE_TAR="$ROOT/backups/support-bundle-${STAMP}.tar.gz"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
mkdir -p "$BUNDLE_DIR"

echo -e "${CYAN}TT-Core Support Bundle Generator — v14.0${NC}"
echo "  Output: $BUNDLE_TAR"
echo "  NO SECRETS will be included in this bundle."
echo ""

# ── 1. Version info ──────────────────────────────────────────────────────────
echo "  [1/8] Version info..."
cat "$ROOT/../release/version.json" 2>/dev/null > "$BUNDLE_DIR/version.json" || echo "{}" > "$BUNDLE_DIR/version.json"
source "$(dirname "$SCRIPT_DIR")"/release/lib/version.sh 2>/dev/null || TT_VERSION="v14.0"
echo "$TT_VERSION | $(date -Iseconds)" > "$BUNDLE_DIR/bundle-info.txt"
echo "host: $(hostname -f 2>/dev/null || hostname)" >> "$BUNDLE_DIR/bundle-info.txt"

# ── 2. Service selection (no secrets) ────────────────────────────────────────
echo "  [2/8] Service selection..."
cp "$ROOT/config/services.select.json" "$BUNDLE_DIR/services.select.json" 2>/dev/null || true

# ── 3. .env structure (KEYS ONLY — no values) ────────────────────────────────
echo "  [3/8] .env key structure (no values)..."
ENV_FILE="$(tt_resolve_core_env_path "$ROOT")"
if [[ -f "$ENV_FILE" ]]; then
  grep -E "^[A-Z_]+=" "$ENV_FILE" | sed 's/=.*/=<REDACTED>/' > "$BUNDLE_DIR/env-keys-only.txt" 2>/dev/null || true
  echo "  Keys found: $(wc -l < "$BUNDLE_DIR/env-keys-only.txt")"
fi

# ── 4. Container status ───────────────────────────────────────────────────────
echo "  [4/8] Container status..."
if command -v docker &>/dev/null; then
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>/dev/null > "$BUNDLE_DIR/docker-ps.txt" || true
  docker inspect $(docker ps -q --filter "name=tt-core") 2>/dev/null \
    | python3 -c "
import json, sys
containers = json.load(sys.stdin)
safe = []
for c in containers:
    safe.append({
        'Name': c.get('Name',''),
        'Status': c.get('State',{}).get('Status',''),
        'Health': c.get('State',{}).get('Health',{}).get('Status','no-hc'),
        'Image': c.get('Config',{}).get('Image',''),
        'RestartCount': c.get('RestartCount',0)
    })
print(json.dumps(safe, indent=2))
" > "$BUNDLE_DIR/container-health.json" 2>/dev/null || echo "[]" > "$BUNDLE_DIR/container-health.json"
fi

# ── 5. Compose render (no env substitution) ───────────────────────────────────
echo "  [5/8] Compose config structure..."
COMPOSE_FILE="$ROOT/compose/tt-core/docker-compose.yml"
if [[ -f "$COMPOSE_FILE" ]]; then
  cp "$COMPOSE_FILE" "$BUNDLE_DIR/docker-compose.yml"
fi

# ── 6. Recent container logs (last 50 lines each — sanitized) ────────────────
echo "  [6/8] Recent logs (last 50 lines each)..."
mkdir -p "$BUNDLE_DIR/logs"
if command -v docker &>/dev/null; then
  for ctr in tt-core-postgres tt-core-redis tt-core-n8n tt-core-n8n-worker; do
    if docker inspect "$ctr" &>/dev/null 2>&1; then
      docker logs "$ctr" --tail 50 2>&1 \
        | sed 's/password=[^ ]*/password=<REDACTED>/gi' \
        | sed 's/token=[^ ]*/token=<REDACTED>/gi' \
        > "$BUNDLE_DIR/logs/${ctr}.log" 2>/dev/null || true
    fi
  done
fi

# ── 7. Disk and memory summary ────────────────────────────────────────────────
echo "  [7/8] System resources..."
{
  echo "=== Disk ==="
  df -h 2>/dev/null || true
  echo ""
  echo "=== Memory ==="
  free -h 2>/dev/null || true
  echo ""
  echo "=== Docker disk ==="
  docker system df 2>/dev/null || true
} > "$BUNDLE_DIR/system-resources.txt"

# ── 8. Validation summary ─────────────────────────────────────────────────────
echo "  [8/8] Validation state..."
cp "$ROOT/../release/signoff.json" "$BUNDLE_DIR/signoff.json" 2>/dev/null || echo '{"note":"signoff.json not found"}' > "$BUNDLE_DIR/signoff.json"
cp "$ROOT/../release/exposure-summary.json" "$BUNDLE_DIR/exposure-summary.json" 2>/dev/null || true

# ── Package ──────────────────────────────────────────────────────────────────
tar -czf "$BUNDLE_TAR" -C "$(dirname "$BUNDLE_DIR")" "$(basename "$BUNDLE_DIR")" 2>/dev/null
rm -rf "$BUNDLE_DIR"

BUNDLE_SIZE=$(du -sh "$BUNDLE_TAR" 2>/dev/null | cut -f1 || echo "unknown")
echo ""
echo -e "${GREEN}Support bundle created: $BUNDLE_TAR  [${BUNDLE_SIZE}]${NC}"
echo -e "${YELLOW}This bundle contains NO secrets — safe to share with support.${NC}"
