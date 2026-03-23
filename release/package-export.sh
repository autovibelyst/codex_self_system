#!/usr/bin/env bash
# package-export.sh - TT-Production v14.0
# Builds a clean sanitized customer delivery bundle from the source tree.
# Always packages from an explicit export directory - NEVER zips the working repo directly.
#
# Usage: bash release/package-export.sh [--out /path/to/output-dir] [--version v14.0]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(dirname "$SCRIPT_DIR")}"
VERSION=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1], encoding=\"utf-8-sig\"))[\"package_version\"])" "$ROOT/release/version.json" 2>/dev/null || echo "vNext")
OUTDIR="${OUTDIR:-/tmp/TT-Production-export}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)     OUTDIR="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --root)    ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
BUNDLE_NAME="TT-Production-$VERSION"
EXPORT_PATH="$OUTDIR/$BUNDLE_NAME"
MANIFEST_GEN="$ROOT/release/generate-bundle-manifest.py"

ROOT_FILES=(
  "LICENSE.md" "MASTER_GUIDE.md" "COMMERCIAL_HANDOFF.md" "COMMERCIAL_HANDOFF_AR.md"
  "RELEASE_NOTES_${VERSION}.md" "RELEASE_AUDIT_SUMMARY.md"
  "FULL_PACKAGE_GUIDE.md" "CUSTOMER_ACCEPTANCE_CHECKLIST.md" "SYSTEM_REQUIREMENTS.md"
  "DELIVERY_CHECKLIST.md"
)
CUSTOMER_RELEASE_FILES=(
  "CHANGELOG.md"
  "bundle-manifest.json"
  "export-policy.json"
  "image-inventory.lock.json"
  "validate-bundle.ps1"
  "verify-manifest.sh"
  "version.json"
)

require_complete_image_lock() {
  local lock_file="$1"
  if [[ ! -f "$lock_file" ]]; then
    echo -e "${RED}ERROR: required image lock file not found: $lock_file${NC}"
    exit 1
  fi

  python3 - "$lock_file" << 'PYEOF'
import json, sys

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    lock = json.load(f)

errors = []
if lock.get("lock_status") != "complete":
    errors.append(f"lock_status={lock.get('lock_status')!r} (expected 'complete')")
if int(lock.get("unresolved_count", -1)) != 0:
    errors.append(f"unresolved_count={lock.get('unresolved_count')!r} (expected 0)")

images = lock.get("images", [])
if not images:
    errors.append("images array is empty")

unresolved = [
    img.get("service_name") or img.get("compose_file") or "<unknown>"
    for img in images
    if not img.get("resolved_digest") or str(img.get("digest_status")) != "resolved"
]
latest = [
    img.get("service_name") or img.get("compose_file") or "<unknown>"
    for img in images
    if str(img.get("source_tag", "")).strip().lower() == "latest"
]

if unresolved:
    errors.append("images missing resolved digests: " + ", ".join(unresolved[:10]))
if latest:
    errors.append("images still use :latest tags: " + ", ".join(latest[:10]))

if errors:
    for err in errors:
        print(err)
    sys.exit(1)
PYEOF
}

echo -e "${CYAN}TT-Production Package Export${NC}"
echo "  Source:  $ROOT"
echo "  Output:  $EXPORT_PATH"
echo "  Version: $VERSION"
echo ""

require_complete_image_lock "$ROOT/release/image-inventory.lock.json"

rm -rf "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"

ALLOWED_DIRS=("tt-core" "tt-supabase" "release")
for dir in "${ALLOWED_DIRS[@]}"; do
  if [[ -d "$ROOT/$dir" ]]; then
    mkdir -p "$EXPORT_PATH/$dir"
    cp -a "$ROOT/$dir/." "$EXPORT_PATH/$dir/"
  fi
done

for f in "${ROOT_FILES[@]}"; do
  [[ -f "$ROOT/$f" ]] && cp "$ROOT/$f" "$EXPORT_PATH/"
done

if [[ -d "$EXPORT_PATH/release" ]]; then
  shopt -s nullglob
  for item in "$EXPORT_PATH/release"/*; do
    base="$(basename "$item")"
    keep=false
    for allowed in "${CUSTOMER_RELEASE_FILES[@]}"; do
      if [[ "$base" == "$allowed" ]]; then
        keep=true
        break
      fi
    done
    if [[ "$keep" == false ]]; then
      rm -rf "$item"
    fi
  done
  shopt -u nullglob
fi

RUNTIME_VOLUME_DIRS=(
  "tt-core/compose/tt-core/volumes/postgres/data"
  "tt-core/compose/tt-core/volumes/redis/data"
  "tt-core/compose/tt-core/volumes/n8n/binaryData"
  "tt-core/compose/tt-core/volumes/n8n/git"
  "tt-core/compose/tt-core/volumes/n8n/ssh"
  "tt-core/compose/tt-core/volumes/pgadmin/data"
  "tt-core/compose/tt-core/volumes/redisinsight/data"
  "tt-core/compose/tt-core/volumes/metabase/data"
  "tt-core/compose/tt-core/volumes/qdrant/storage"
  "tt-core/compose/tt-core/volumes/ollama/models"
  "tt-core/compose/tt-core/volumes/openclaw/data"
  "tt-core/compose/tt-core/volumes/openwebui/data"
  "tt-core/compose/tt-core/volumes/portainer/data"
  "tt-core/compose/tt-core/volumes/mariadb/data"
  "tt-core/compose/tt-core/volumes/kanboard/data"
  "tt-core/compose/tt-core/volumes/uptime-kuma/data"
  "tt-core/compose/tt-core/volumes/wordpress/html"
)
for rel in "${RUNTIME_VOLUME_DIRS[@]}"; do
  rm -rf "$EXPORT_PATH/$rel"
done

RUNTIME_VOLUME_FILES=(
  "tt-core/compose/tt-core/volumes/n8n/config"
  "tt-core/compose/tt-core/volumes/n8n/crash.journal"
)
for rel in "${RUNTIME_VOLUME_FILES[@]}"; do
  rm -f "$EXPORT_PATH/$rel"
done
find "$EXPORT_PATH/tt-core/compose/tt-core/volumes/n8n" -maxdepth 1 -type f -name 'n8nEventLog*.log' -delete 2>/dev/null || true

INTERNAL_ARTIFACT_PATHS=(
  "tt-core/.preflight-passed"
  "tt-core/.runtime-test"
  "release/ci-gate-report.txt"
  "release/ci-gate.sh"
  "release/secret-scan-ci.sh"
  "release/history"
  "release/PRODUCTION_ACCEPTANCE_REPORT.json"
  "release/README.md"
  "release/deployment-cert.json"
  "release/doc-contract-checker.sh"
  "release/drift-scan.sh"
  "release/generate-bundle-manifest.py"
  "release/generate-exposure.sh"
  "release/generate-image-pins.sh"
  "release/generate-signoff.sh"
  "release/handoff-cert.json"
  "release/lint-docs.sh"
  "release/make-release.sh"
  "release/package-export.sh"
  "release/release-pipeline.sh"
  "release/restore-cert.json"
  "release/secret-scan.sh"
  "release/signoff.json"
  "release/smoke-results.json"
  "release/supportability-cert.json"
  "release/validation-plan.md"
)
for rel in "${INTERNAL_ARTIFACT_PATHS[@]}"; do
  rm -rf "$EXPORT_PATH/$rel"
done
find "$EXPORT_PATH/release" -maxdepth 1 -type f -name 'TT-Production-*.zip.sha256' -delete 2>/dev/null || true
find "$EXPORT_PATH/tt-core/compose/tt-core/volumes" -depth -type d -empty -delete 2>/dev/null || true
find "$EXPORT_PATH/tt-core" -depth -type d -empty -delete 2>/dev/null || true

find "$EXPORT_PATH" \( \
  -name ".git" -o -name ".github" -o -name ".gitignore" -o -name ".gitattributes" -o -name ".gitmodules" \
  -o -name "*.tmp" -o -name "*.bak" -o -name "*.log" -o -name "*.pyc" \
  -o -name ".DS_Store" -o -name "Thumbs.db" -o -name "*.swp" \
  \) -exec rm -rf {} + 2>/dev/null || true

find "$EXPORT_PATH" \( -name "*.env" -o -name ".env" -o -name ".env.*" \) \
  -not -name "*.example" -not -name "*.template" \
  -not -name "env.addon.template.env" -delete 2>/dev/null || true

require_complete_image_lock "$EXPORT_PATH/release/image-inventory.lock.json"

if [[ ! -f "$MANIFEST_GEN" ]]; then
  echo -e "${RED}ERROR: manifest generator not found: $MANIFEST_GEN${NC}"
  exit 1
fi

python3 "$MANIFEST_GEN" \
  --root "$EXPORT_PATH" \
  --output "$EXPORT_PATH/release/bundle-manifest.json" \
  --version "$VERSION" \
  --bundle-name "$BUNDLE_NAME" \
  --required-root-file "COMMERCIAL_HANDOFF.md" \
  --required-root-file "CUSTOMER_ACCEPTANCE_CHECKLIST.md" \
  --required-root-file "DELIVERY_CHECKLIST.md" \
  --required-root-file "FULL_PACKAGE_GUIDE.md" \
  --required-root-file "LICENSE.md" \
  --required-root-file "MASTER_GUIDE.md" \
  --required-root-file "RELEASE_AUDIT_SUMMARY.md" \
  --required-root-file "RELEASE_NOTES_${VERSION}.md" \
  --required-root-file "SYSTEM_REQUIREMENTS.md"
cp "$EXPORT_PATH/release/bundle-manifest.json" "$ROOT/release/bundle-manifest.json"

RESIDUAL_RUNTIME_PATHS=(
  "tt-core/compose/tt-core/volumes/postgres/data"
  "tt-core/compose/tt-core/volumes/redis/data"
  "tt-core/compose/tt-core/volumes/n8n/config"
  "tt-core/compose/tt-core/volumes/pgadmin/data"
  "tt-core/compose/tt-core/volumes/redisinsight/data"
  "tt-core/.preflight-passed"
  "tt-core/.runtime-test"
  "release/ci-gate-report.txt"
  "release/ci-gate.sh"
  "release/secret-scan-ci.sh"
)
for rel in "${RESIDUAL_RUNTIME_PATHS[@]}"; do
  if [[ -e "$EXPORT_PATH/$rel" ]]; then
    echo -e "${RED}ERROR: artifact survived export cleanup: $rel${NC}"
    exit 1
  fi
done

echo -e "${GREEN}Export complete: $EXPORT_PATH${NC}"
echo "File count: $(find "$EXPORT_PATH" -type f | wc -l)"
echo "Manifest :   $EXPORT_PATH/release/bundle-manifest.json"
echo ""
echo "Run secret scan before packaging:"
echo "  bash release/secret-scan.sh --root $EXPORT_PATH"
echo ""
echo "Then zip for delivery:"
echo "  cd $OUTDIR && zip -r ${BUNDLE_NAME}.zip ${BUNDLE_NAME}/"
