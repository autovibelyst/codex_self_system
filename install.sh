#!/usr/bin/env bash
# =============================================================================
# install.sh — TT-Production bootstrap installer (Linux/macOS)
#
# Downloads a signed release bundle from GitHub Releases, verifies SHA256, then
# delegates installation to tt-core/installer/Install-TTCore.sh inside the bundle.
#
# Example:
#   bash install.sh --owner acme --repo tt-production --profile local-private --tz UTC
# =============================================================================
set -euo pipefail

OWNER="${TT_GITHUB_OWNER:-}"
REPO="${TT_GITHUB_REPO:-tt-production}"
TAG="${TT_RELEASE_TAG:-v14.0}"
BUNDLE_NAME="${TT_BUNDLE_NAME:-TT-Production-v14.0}"

PROFILE_NAME="local-private"
TIMEZONE=""
ROOT_PATH=""
SUPABASE_ROOT=""
DOMAIN=""
WITH_TUNNEL=false
WITH_SUPABASE=false
NO_START=false

usage() {
  cat <<'EOF'
Usage:
  bash install.sh --owner <github-owner> [options]

Required:
  --owner <name>            GitHub owner/org hosting the release assets

Optional:
  --repo <name>             Repository name (default: tt-production)
  --tag <vX.Y>              Release tag (default: v14.0)
  --bundle <name>           Bundle name without .zip (default: TT-Production-v14.0)
  --profile <name>          local-private|small-business|ai-workstation|public-productivity
  --tz <timezone>           IANA timezone (example: Asia/Riyadh, Europe/Istanbul, UTC)
  --root <path>             tt-core target install path
  --supabase-root <path>    tt-supabase target install path
  --domain <example.com>    Base domain when tunnel is enabled
  --with-tunnel             Enable tunnel install path
  --with-supabase           Install tt-supabase stack
  --no-start                Install only (do not start services)
  -h, --help                Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --tag) TAG="${2:-}"; shift 2 ;;
    --bundle) BUNDLE_NAME="${2:-}"; shift 2 ;;
    --profile) PROFILE_NAME="${2:-}"; shift 2 ;;
    --tz) TIMEZONE="${2:-}"; shift 2 ;;
    --root) ROOT_PATH="${2:-}"; shift 2 ;;
    --supabase-root) SUPABASE_ROOT="${2:-}"; shift 2 ;;
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --with-tunnel) WITH_TUNNEL=true; shift ;;
    --with-supabase) WITH_SUPABASE=true; shift ;;
    --no-start) NO_START=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$OWNER" ]]; then
  echo "ERROR: --owner is required (or set TT_GITHUB_OWNER)"
  echo "Example: bash install.sh --owner your-org --repo tt-production --profile local-private --tz UTC"
  exit 1
fi

case "$PROFILE_NAME" in
  local-private|small-business|ai-workstation|public-productivity) ;;
  *)
    echo "ERROR: unsupported profile '$PROFILE_NAME'"
    echo "Allowed: local-private, small-business, ai-workstation, public-productivity"
    exit 1
    ;;
esac

command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required"; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo "ERROR: unzip is required"; exit 1; }

SHA256_CMD=""
if command -v sha256sum >/dev/null 2>&1; then
  SHA256_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  SHA256_CMD="shasum -a 256"
else
  echo "ERROR: sha256sum or shasum is required"
  exit 1
fi

ASSET_ZIP="${BUNDLE_NAME}.zip"
ASSET_SUM="${ASSET_ZIP}.sha256"
RELEASE_BASE_URL="https://github.com/${OWNER}/${REPO}/releases/download/${TAG}"

WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "Downloading release assets from ${OWNER}/${REPO}@${TAG} ..."
curl -fsSL "${RELEASE_BASE_URL}/${ASSET_ZIP}" -o "${WORK_DIR}/${ASSET_ZIP}"
curl -fsSL "${RELEASE_BASE_URL}/${ASSET_SUM}" -o "${WORK_DIR}/${ASSET_SUM}"

expected_hash="$(awk '{print $1}' "${WORK_DIR}/${ASSET_SUM}" | tr '[:upper:]' '[:lower:]')"
actual_hash="$($SHA256_CMD "${WORK_DIR}/${ASSET_ZIP}" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
if [[ -z "$expected_hash" || "$expected_hash" != "$actual_hash" ]]; then
  echo "ERROR: SHA256 mismatch for ${ASSET_ZIP}"
  echo "Expected: ${expected_hash}"
  echo "Actual:   ${actual_hash}"
  exit 1
fi
echo "Checksum verified."

unzip -q "${WORK_DIR}/${ASSET_ZIP}" -d "$WORK_DIR"
BUNDLE_DIR="${WORK_DIR}/${BUNDLE_NAME}"
INSTALLER="${BUNDLE_DIR}/tt-core/installer/Install-TTCore.sh"

[[ -d "$BUNDLE_DIR" ]] || { echo "ERROR: extracted bundle folder not found: $BUNDLE_DIR"; exit 1; }
[[ -f "$INSTALLER" ]] || { echo "ERROR: installer not found: $INSTALLER"; exit 1; }

INSTALL_CMD=(bash "$INSTALLER" --profile "$PROFILE_NAME")
[[ -n "$TIMEZONE" ]] && INSTALL_CMD+=(--tz "$TIMEZONE")
[[ -n "$ROOT_PATH" ]] && INSTALL_CMD+=(--root "$ROOT_PATH")
[[ -n "$SUPABASE_ROOT" ]] && INSTALL_CMD+=(--supabase-root "$SUPABASE_ROOT")
[[ -n "$DOMAIN" ]] && INSTALL_CMD+=(--domain "$DOMAIN")
[[ "$WITH_TUNNEL" == "true" ]] && INSTALL_CMD+=(--with-tunnel)
[[ "$WITH_SUPABASE" == "true" ]] && INSTALL_CMD+=(--with-supabase)
[[ "$NO_START" == "true" ]] && INSTALL_CMD+=(--no-start)

echo "Running installer with profile: ${PROFILE_NAME}"
"${INSTALL_CMD[@]}"
