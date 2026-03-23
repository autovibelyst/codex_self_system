#!/usr/bin/env bash
# =============================================================================
# sops-setup.sh — SOPS + age Bootstrap for TT-Production v14.0
# Idempotent: safe to run multiple times — will not overwrite existing key.
#
# What this does:
#   1. Installs SOPS binary (Linux amd64/arm64) if not present
#   2. Installs age binary if not present  
#   3. Generates age keypair (stored OUTSIDE repo at ~/.config/tt-production/age/)
#   4. Updates .sops.yaml with the age public key
# =============================================================================
set -euo pipefail

SOPS_VERSION="3.8.1"
AGE_VERSION="1.1.1"
SOPS_SHA256_AMD64="d6bf07fb61972127c9e0d622523124c2d81caf9f7971fb123228961021811697"
SOPS_SHA256_ARM64="15b8e90ca80dc23125cd2925731035fdef20c749ba259df477d1dd103a06d621"
AGE_SHA256_AMD64="cf16cbb108fc56e2064b00ba2b65d9fb1b8d7002ca5e38260ee1cc34f6aaa8f9"
AGE_SHA256_ARM64="f0dbf4364f5ba44e37ad85af9fdd3716bd410018ce344d317b174d206b03e6fc"
KEY_DIR="${HOME}/.config/tt-production/age"
KEY_FILE="$KEY_DIR/key.txt"
FORBIDDEN_DEV_AGE_KEY="age1qprwg5fxspev023zhv2thdrl7k6gx5rkv9rfenc2k0w0txj5c9vs5hk7yc"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SOPS_YAML="$ROOT/tt-core/secrets/.sops.yaml"
TMP_DIR="$(mktemp -d)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

echo -e "${CYAN}── SOPS + age Bootstrap ────────────────────────────────${NC}"

cleanup() {
  [[ -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT

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

verify_download_checksum() {
  local file="$1" expected="$2" label="$3"
  local actual

  actual="$(calc_sha256 "$file" 2>/dev/null || true)"
  if [[ -z "$actual" ]]; then
    echo -e "  ${RED}[FAIL]${NC} Could not calculate SHA256 for $label"
    exit 1
  fi
  if [[ "${actual,,}" != "${expected,,}" ]]; then
    rm -f "$file"
    echo -e "  ${RED}[FAIL]${NC} Checksum mismatch for $label"
    echo -e "  ${RED}[FAIL]${NC} Expected: ${expected}"
    echo -e "  ${RED}[FAIL]${NC} Actual:   ${actual}"
    exit 1
  fi
}

manual_install_hint() {
  local tool_name="$1" version="$2" arch="$3" url="$4"
  echo -e "  ${RED}[FAIL]${NC} Unsupported arch ${arch} for ${tool_name} auto-install."
  echo -e "  ${YELLOW}[WARN]${NC} Please install manually from: ${url}"
  exit 1
}

# ── Install SOPS ──────────────────────────────────────────────────────────────
if ! command -v sops &>/dev/null; then
  echo -e "  Installing SOPS v${SOPS_VERSION}..."
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  SOPS_ARCH="amd64"; SOPS_SHA256="$SOPS_SHA256_AMD64" ;;
    aarch64) SOPS_ARCH="arm64"; SOPS_SHA256="$SOPS_SHA256_ARM64" ;;
    *)       manual_install_hint "SOPS" "$SOPS_VERSION" "$ARCH" "https://github.com/getsops/sops/releases" ;;
  esac
  [[ -n "${SOPS_SHA256:-}" ]] || manual_install_hint "SOPS" "$SOPS_VERSION" "$ARCH" "https://github.com/getsops/sops/releases"
  SOPS_URL="https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${SOPS_ARCH}"
  SOPS_DOWNLOAD="$TMP_DIR/sops"
  if curl -fsSL "$SOPS_URL" -o "$SOPS_DOWNLOAD" 2>/dev/null; then
    verify_download_checksum "$SOPS_DOWNLOAD" "$SOPS_SHA256" "SOPS binary"
    chmod +x "$SOPS_DOWNLOAD"
    sudo mv "$SOPS_DOWNLOAD" /usr/local/bin/sops
    echo -e "  ${GREEN}[OK]${NC}  SOPS installed"
  else
    echo -e "  ${RED}[FAIL]${NC} Could not download SOPS from $SOPS_URL"
    exit 1
  fi
else
  echo -e "  ${GREEN}[OK]${NC}  SOPS already installed: $(sops --version 2>&1 | head -1)"
fi

# ── Install age ───────────────────────────────────────────────────────────────
if ! command -v age-keygen &>/dev/null; then
  echo -e "  Installing age v${AGE_VERSION}..."
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  AGE_ARCH="amd64"; AGE_SHA256="$AGE_SHA256_AMD64" ;;
    aarch64) AGE_ARCH="arm64"; AGE_SHA256="$AGE_SHA256_ARM64" ;;
    *)       manual_install_hint "age" "$AGE_VERSION" "$ARCH" "https://github.com/FiloSottile/age/releases" ;;
  esac
  [[ -n "${AGE_SHA256:-}" ]] || manual_install_hint "age" "$AGE_VERSION" "$ARCH" "https://github.com/FiloSottile/age/releases"
  AGE_URL="https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-${AGE_ARCH}.tar.gz"
  AGE_DOWNLOAD="$TMP_DIR/age.tar.gz"
  AGE_EXTRACT="$TMP_DIR/age-extract"
  mkdir -p "$AGE_EXTRACT"
  if curl -fsSL "$AGE_URL" -o "$AGE_DOWNLOAD" 2>/dev/null; then
    verify_download_checksum "$AGE_DOWNLOAD" "$AGE_SHA256" "age tarball"
    tar -xzf "$AGE_DOWNLOAD" -C "$AGE_EXTRACT"
    sudo mv "$AGE_EXTRACT/age/age" /usr/local/bin/age
    sudo mv "$AGE_EXTRACT/age/age-keygen" /usr/local/bin/age-keygen
    echo -e "  ${GREEN}[OK]${NC}  age installed"
  else
    echo -e "  ${RED}[FAIL]${NC} Could not download age from $AGE_URL"
    exit 1
  fi
else
  echo -e "  ${GREEN}[OK]${NC}  age already installed"
fi

# ── Generate age keypair (idempotent) ─────────────────────────────────────────
if [[ -f "$KEY_FILE" ]]; then
  echo -e "  ${GREEN}[OK]${NC}  age key already exists at $KEY_FILE — not regenerating"
else
  echo -e "  Generating age keypair..."
  mkdir -p "$KEY_DIR"
  chmod 700 "$KEY_DIR"
  age-keygen -o "$KEY_FILE" 2>/dev/null
  chmod 600 "$KEY_FILE"
  echo -e "  ${GREEN}[OK]${NC}  age key generated at $KEY_FILE"
fi

# ── Read public key and update .sops.yaml ─────────────────────────────────────
if command -v age-keygen &>/dev/null && [[ -f "$KEY_FILE" ]]; then
  PUBLIC_KEY=$(grep "^# public key:" "$KEY_FILE" | awk '{print $NF}')
  if [[ ! -f "$SOPS_YAML" ]]; then
    echo -e "  ${RED}[FAIL]${NC} Missing $SOPS_YAML"
    exit 1
  fi
  if grep -q "$FORBIDDEN_DEV_AGE_KEY" "$SOPS_YAML"; then
    echo -e "  ${RED}[FAIL]${NC} .sops.yaml contains forbidden developer key."
    echo -e "  ${RED}[FAIL]${NC} Reset to <OPERATOR_AGE_PUBLIC_KEY> before running setup."
    exit 1
  fi
  if [[ -n "$PUBLIC_KEY" ]]; then
    if grep -q "<OPERATOR_AGE_PUBLIC_KEY>" "$SOPS_YAML"; then
      sed -i "s|<OPERATOR_AGE_PUBLIC_KEY>|$PUBLIC_KEY|g" "$SOPS_YAML"
      echo -e "  ${GREEN}[OK]${NC}  .sops.yaml updated with public key: ${PUBLIC_KEY:0:20}..."
    else
      CURRENT_KEY=$(grep -Eo 'age1[a-z0-9]+' "$SOPS_YAML" | head -1 || true)
      if [[ -z "$CURRENT_KEY" ]]; then
        echo -e "  ${RED}[FAIL]${NC} .sops.yaml has no placeholder and no valid age key."
        exit 1
      fi
      echo -e "  ${YELLOW}[WARN]${NC} .sops.yaml already configured with an operator key."
    fi
  fi
  if grep -q "$FORBIDDEN_DEV_AGE_KEY" "$SOPS_YAML"; then
    echo -e "  ${RED}[FAIL]${NC} Forbidden developer key remains in .sops.yaml."
    exit 1
  fi
fi

echo ""
echo -e "  ${YELLOW}IMPORTANT: Back up your age private key!${NC}"
echo -e "  Location: ${KEY_FILE}"
echo -e "  If you lose this key, encrypted secrets cannot be recovered."
echo ""
