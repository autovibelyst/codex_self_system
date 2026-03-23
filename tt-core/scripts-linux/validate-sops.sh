#!/usr/bin/env bash
# =============================================================================
# validate-sops.sh — SOPS + age Secret Integrity Validator
# TT-Production v14.0
#
# EXIT: 0 = SOPS setup valid
#       1 = SOPS issue found (non-fatal in legacy mode, fatal in strict mode)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
STRICT="${1:-}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ISSUES=()
WARNINGS=()

# Align decrypt operations with installer-managed age key location.
TT_AGE_KEY_DEFAULT="$HOME/.config/tt-production/age/key.txt"
if [[ -z "${SOPS_AGE_KEY_FILE:-}" && -f "$TT_AGE_KEY_DEFAULT" ]]; then
  export SOPS_AGE_KEY_FILE="$TT_AGE_KEY_DEFAULT"
fi

echo ""
echo -e "${CYAN}── SOPS + age Secret Validation ────────────────────────${NC}"

# Check SOPS binary
if ! command -v sops &>/dev/null; then
  if [[ "$STRICT" == "--strict" ]]; then
    ISSUES+=("sops binary not found — run installer/lib/sops-setup.sh")
  else
    WARNINGS+=("sops binary not found — SOPS mode not active (plaintext fallback)")
  fi
else
  echo -e "  ${GREEN}[OK]${NC}  sops binary: $(sops --version 2>&1 | head -1)"
fi

# Check age binary
if ! command -v age &>/dev/null && ! command -v age-keygen &>/dev/null; then
  WARNINGS+=("age binary not found — needed for SOPS secret management")
else
  echo -e "  ${GREEN}[OK]${NC}  age binary present"
fi

# Check .sops.yaml exists
SOPS_YAML="$ROOT/secrets/.sops.yaml"
if [[ ! -f "$SOPS_YAML" ]]; then
  ISSUES+=("secrets/.sops.yaml not found — run installer/lib/sops-setup.sh")
else
  # Verify it has a real key (not placeholder)
  if grep -q "<OPERATOR_AGE_PUBLIC_KEY>" "$SOPS_YAML"; then
    ISSUES+=("secrets/.sops.yaml contains placeholder — run installer/lib/sops-setup.sh")
  else
    echo -e "  ${GREEN}[OK]${NC}  .sops.yaml configured"
  fi
fi

# Check encrypted files exist
ENC_FILE="$ROOT/secrets/core.secrets.enc.env"
if [[ ! -f "$ENC_FILE" ]]; then
  WARNINGS+=("secrets/core.secrets.enc.env not found — run init.sh to generate secrets")
else
  # Try decrypt
  if command -v sops &>/dev/null; then
    if sops --decrypt "$ENC_FILE" > /dev/null 2>&1; then
      echo -e "  ${GREEN}[OK]${NC}  core.secrets.enc.env decrypts successfully"
    else
      ISSUES+=("core.secrets.enc.env decrypt failed — age key may be missing from ~/.config/tt-production/age/key.txt")
    fi
  fi
fi

# Ensure no plaintext secrets in secrets/ dir
for f in "$ROOT/secrets/"*.env; do
  [[ -f "$f" ]] || continue
  [[ "$f" == *.enc.env ]] && continue
  ISSUES+=("Plaintext secret file found: $f — this file must not exist outside compose/*/")
done

# Ensure age private key is NOT in repo
if find "$ROOT" -name "*.age.key" -o -name "age.key" -o -name "key.txt" 2>/dev/null | grep -v ".config" | grep -q .; then
  ISSUES+=("Possible age private key found in repository tree — CRITICAL: remove immediately")
fi

# Report
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  for w in "${WARNINGS[@]}"; do
    echo -e "  ${YELLOW}[WARN]${NC} $w"
  done
fi

if [[ ${#ISSUES[@]} -gt 0 ]]; then
  for i in "${ISSUES[@]}"; do
    echo -e "  ${RED}[FAIL]${NC} $i"
  done
  echo ""
  exit 1
fi

echo -e "  ${GREEN}[PASS]${NC} SOPS secret validation passed"
exit 0

