#!/usr/bin/env bash
# =============================================================================
# lock-image-digests.sh — TT-Production Image Digest Locking
# Version: reads from release/lib/version.sh
#
# AUTHORITATIVE IMAGE GOVERNANCE PATH for TT-Production.
# Resolves SHA-256 digests for all images defined in docker-compose files
# and writes results to release/image-inventory.lock.json.
#
# This script is the SINGLE canonical image governance mechanism.
# Do NOT maintain parallel static image-lock arrays elsewhere.
#
# Usage:
#   bash scripts-linux/lock-image-digests.sh [--verify] [--root /path]
#
# Modes:
#   (default)  Pull and resolve digests, update image-inventory.lock.json
#   --verify   Verify running containers match locked digests (no writes)
#   --dry-run  Show what would be resolved without writing
#
# Exit codes:
#   0 = success / all verified
#   1 = failure / digest mismatch
#   2 = Docker not available
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$ROOT")"
MODE="lock"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)     REPO_ROOT="$2"; ROOT="$REPO_ROOT/tt-core"; shift 2 ;;
    --verify)   MODE="verify"; shift ;;
    --dry-run)  MODE="dryrun"; shift ;;
    *)          shift ;;
  esac
done

# Load canonical version
VERSION_LIB="$REPO_ROOT/release/lib/version.sh"
if [[ -f "$VERSION_LIB" ]]; then
  source "$VERSION_LIB"
else
  TT_VERSION="v14.0"
fi

INVENTORY_FILE="$REPO_ROOT/release/image-inventory.lock.json"
COMPOSE_FILES=(
  "$ROOT/compose/tt-core/docker-compose.yml"
  "$ROOT/compose/tt-tunnel/docker-compose.yml"
)
ADDON_DIR="$ROOT/compose/tt-core/addons"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; GRAY='\033[0;37m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC}   $*"; }
err()  { echo -e "  ${RED}[ERR]${NC}  $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
info() { echo -e "  ${GRAY}[INFO]${NC} $*"; }

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  TT-Production ${TT_VERSION} — Image Digest Lock${NC}"
echo -e "${CYAN}  Mode: ${MODE}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""

# Check Docker availability
if ! docker info &>/dev/null 2>&1; then
  echo -e "  ${RED}[ERR]${NC}  Docker daemon not available"
  echo "         Cannot resolve digests without Docker. Exiting."
  exit 2
fi

# ── Extract images from compose files ────────────────────────────────────────
declare -A IMAGE_MAP  # image_ref:tag -> service:scope

extract_images() {
  local file="$1"
  local scope="$2"
  command -v python3 &>/dev/null || { warn "python3 required for image extraction"; return; }
  python3 << PYEOF
import yaml, sys, os
try:
    dc = yaml.safe_load(open('$file'))
    for svc_name, svc in dc.get('services', {}).items():
        img = svc.get('image', '')
        if img:
            # Format: scope|service_name|image_with_tag
            print(f'$scope|{svc_name}|{img}')
except Exception as e:
    print(f'# ERROR: {e}', file=sys.stderr)
PYEOF
}

ALL_IMAGES=()
for cf in "${COMPOSE_FILES[@]}"; do
  scope="core"
  [[ "$cf" == *"tunnel"* ]] && scope="tunnel"
  [[ -f "$cf" ]] && while IFS= read -r line; do
    [[ "$line" == \#* ]] && continue
    ALL_IMAGES+=("$cf|$line")
  done < <(extract_images "$cf" "$scope")
done

# Addons
for af in "$ADDON_DIR"/*.addon.yml; do
  [[ -f "$af" ]] || continue
  addon_name=$(basename "$af" .addon.yml)
  while IFS= read -r line; do
    [[ "$line" == \#* ]] && continue
    ALL_IMAGES+=("$af|$line")
  done < <(extract_images "$af" "addon:$addon_name")
done

if [[ ${#ALL_IMAGES[@]} -eq 0 ]]; then
  warn "No images found in compose files"
  exit 0
fi

info "Found ${#ALL_IMAGES[@]} image entries across compose files"
echo ""

# ── Mode: verify ─────────────────────────────────────────────────────────────
if [[ "$MODE" == "verify" ]]; then
  if [[ ! -f "$INVENTORY_FILE" ]]; then
    err "image-inventory.lock.json not found — run without --verify to generate"
    exit 1
  fi
  echo "── Verifying against locked inventory ──"
  MISMATCHES=0
  while IFS= read -r entry; do
    compose_file=$(echo "$entry" | cut -d'|' -f1)
    scope=$(echo "$entry" | cut -d'|' -f2)
    svc_name=$(echo "$entry" | cut -d'|' -f3)
    image_ref=$(echo "$entry" | cut -d'|' -f4)
    tag=$(echo "$image_ref" | cut -d: -f2)
    base=$(echo "$image_ref" | cut -d: -f1)

    # Get locked digest
    locked_digest=$(python3 -c "
import json
inv = json.load(open('$INVENTORY_FILE'))
for img in inv.get('images',[]):
    if img.get('service_name') == '$svc_name':
        print(img.get('resolved_digest','') or '')
        break
" 2>/dev/null || echo "")

    if [[ -z "$locked_digest" ]]; then
      warn "$svc_name ($image_ref): no locked digest — not verified"
      continue
    fi

    # Get running digest
    running_digest=$(docker inspect --format='{{index .RepoDigests 0}}' \
      "$(docker ps -qf "name=tt-core-$svc_name" 2>/dev/null | head -1)" 2>/dev/null || echo "")
    running_digest_hash=$(echo "$running_digest" | grep -oP '@sha256:\K[0-9a-f]+' || echo "")
    locked_hash=$(echo "$locked_digest" | grep -oP 'sha256:\K[0-9a-f]+' || echo "$locked_digest")

    if [[ -n "$running_digest_hash" && "$running_digest_hash" == "$locked_hash" ]]; then
      ok "$svc_name: digest matches locked inventory"
    elif [[ -z "$running_digest_hash" ]]; then
      warn "$svc_name: container not running — cannot verify"
    else
      err "$svc_name: DIGEST MISMATCH"
      err "  Locked:  sha256:${locked_hash:0:16}..."
      err "  Running: sha256:${running_digest_hash:0:16}..."
      MISMATCHES=$((MISMATCHES+1))
    fi
  done < <(printf '%s\n' "${ALL_IMAGES[@]}")

  [[ $MISMATCHES -eq 0 ]] && { echo ""; ok "All verified digests match"; exit 0; } || exit 1
fi

# ── Mode: lock / dryrun ───────────────────────────────────────────────────────
echo "── Resolving image digests ──"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RESOLVED=()
UNRESOLVED=()
IMAGES_JSON=()

while IFS= read -r entry; do
  compose_file=$(echo "$entry" | cut -d'|' -f1)
  scope=$(echo "$entry" | cut -d'|' -f2)
  svc_name=$(echo "$entry" | cut -d'|' -f3)
  image_ref=$(echo "$entry" | cut -d'|' -f4)

  # Split image:tag
  if [[ "$image_ref" == *":"* ]]; then
    img_base=$(echo "$image_ref" | cut -d: -f1)
    img_tag=$(echo "$image_ref" | cut -d: -f2-)
  else
    img_base="$image_ref"
    img_tag="latest"
  fi

  info "Resolving: $svc_name ($image_ref)"

  digest=""
  lock_status="unresolved"
  locked_at=""

  if [[ "$MODE" != "dryrun" ]]; then
    # Pull to get latest digest
    if docker pull "$image_ref" &>/dev/null 2>&1; then
      digest=$(docker inspect --format='{{index .RepoDigests 0}}' "$image_ref" 2>/dev/null || echo "")
      digest_hash=$(echo "$digest" | grep -oP 'sha256:[0-9a-f]+' || echo "")
      if [[ -n "$digest_hash" ]]; then
        lock_status="resolved"
        locked_at="$TIMESTAMP"
        RESOLVED+=("$svc_name")
        ok "$svc_name: ${digest_hash:0:20}..."
      else
        warn "$svc_name: pulled but no digest available"
        UNRESOLVED+=("$svc_name")
      fi
    else
      warn "$svc_name: pull failed (network/auth issue)"
      UNRESOLVED+=("$svc_name")
    fi
  else
    info "$svc_name: [dry-run] would resolve"
    UNRESOLVED+=("$svc_name")
  fi

  compose_rel="${compose_file#$REPO_ROOT/}"
  IMAGES_JSON+=("{
    \"image_ref\": \"$img_base\",
    \"source_tag\": \"$img_tag\",
    \"resolved_digest\": $([ -n "$digest_hash" ] && echo "\"$digest_hash\"" || echo "null"),
    \"digest_status\": \"$lock_status\",
    \"scope\": \"$scope\",
    \"compose_file\": \"$compose_rel\",
    \"service_name\": \"$svc_name\",
    \"locked_at\": $([ -n "$locked_at" ] && echo "\"$locked_at\"" || echo "null")
  }")
done < <(printf '%s\n' "${ALL_IMAGES[@]}")

# Write inventory
UNRESOLVED_COUNT=${#UNRESOLVED[@]}
RESOLVED_COUNT=${#RESOLVED[@]}
LOCK_STATUS="partial"
[[ $UNRESOLVED_COUNT -eq 0 ]] && LOCK_STATUS="locked"

IMAGES_ARRAY=$(printf ',%s' "${IMAGES_JSON[@]}"); IMAGES_ARRAY="[${IMAGES_ARRAY:1}]"

if [[ "$MODE" != "dryrun" ]]; then
  cat > "$INVENTORY_FILE" << JSONEOF
{
  "_schema": "tt-image-inventory/v1",
  "_generator": "tt-core/scripts-linux/lock-image-digests.sh",
  "_authority": "Single authoritative image governance path. Do not maintain parallel lock arrays.",
  "generated_at": "$TIMESTAMP",
  "tt_version": "$TT_VERSION",
  "lock_status": "$LOCK_STATUS",
  "resolved_count": $RESOLVED_COUNT,
  "unresolved_count": $UNRESOLVED_COUNT,
  "images": $IMAGES_ARRAY
}
JSONEOF
  ok "Written: release/image-inventory.lock.json"
fi

echo ""
echo -e "${CYAN}── Summary ──────────────────────────────────────────${NC}"
echo "  Resolved:   ${#RESOLVED[@]}"
echo "  Unresolved: ${#UNRESOLVED[@]}"
[[ $UNRESOLVED_COUNT -gt 0 ]] && {
  echo "  Unresolved services: ${UNRESOLVED[*]}"
  warn "Partial lock — run again with Docker daemon and network access to resolve all"
}
echo ""
[[ $LOCK_STATUS == "locked" ]] && ok "All images locked" || warn "Partial lock — image governance advisory only"
exit 0
