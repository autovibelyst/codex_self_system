#!/usr/bin/env bash
# =============================================================================
# apply-profile.sh — TT-Core Deployment Profile Applicator (v14.0)
#
# Applies a pre-defined deployment profile preset to services.select.json,
# enabling one-command stack configuration for common deployment archetypes.
#
# Usage:
#   bash scripts-linux/apply-profile.sh <profile-name>
#   bash scripts-linux/apply-profile.sh local-private
#   bash scripts-linux/apply-profile.sh small-business
#   bash scripts-linux/apply-profile.sh ai-workstation
#   bash scripts-linux/apply-profile.sh public-productivity
#   bash scripts-linux/apply-profile.sh --list
#   bash scripts-linux/apply-profile.sh --dry-run small-business
#
# Available profiles:
#   local-private       — No public exposure. Local workstation only.
#   small-business      — n8n + Metabase + Kanboard via Cloudflare Tunnel.
#   ai-workstation      — n8n + Qdrant + Ollama + OpenWebUI for AI workflows.
#   public-productivity — Full public stack with tunnel-exposed services.
#
# What this does:
#   1) Reads the profile preset from config/profiles/<profile>.json
#   2) Merges 'profiles' and 'tunnel.routes' blocks into services.select.json
#      (preserving client.name, client.domain, client.timezone, bind_ip)
#   3) Backs up current services.select.json before overwriting
#
# EXIT: 0 = success, 1 = fatal error
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
DRY_RUN=false
LIST_ONLY=false
PROFILE_NAME=""

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
RED='\033[0;31m'; GRAY='\033[0;37m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]${NC}   $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
info() { echo -e "  ${GRAY}[INFO]${NC} $*"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)      ROOT="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=true; shift ;;
    --list)      LIST_ONLY=true; shift ;;
    -*)          echo "Unknown option: $1"; exit 1 ;;
    *)           PROFILE_NAME="$1"; shift ;;
  esac
done

PROFILES_DIR="$ROOT/config/profiles"
SELECT_FILE="$ROOT/config/services.select.json"

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  TT-Core Profile Applicator — v14.0${NC}"
[[ "$DRY_RUN" == "true" ]] && echo -e "${YELLOW}  DRY-RUN — no changes will be written${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""

# ── List available profiles ───────────────────────────────────────────────────
if [[ "$LIST_ONLY" == "true" ]]; then
  echo "  Available deployment profiles:"
  echo ""
  if [[ -d "$PROFILES_DIR" ]]; then
    for pf in "$PROFILES_DIR"/*.json; do
      pname=$(basename "$pf" .json)
      desc=$(python3 -c "import json; d=json.load(open('$pf')); print(d.get('_description',''))" 2>/dev/null || echo "")
      printf "    %-22s %s\n" "$pname" "$desc"
    done
  else
    warn "Profiles directory not found: $PROFILES_DIR"
  fi
  echo ""
  exit 0
fi

# ── Validate inputs ───────────────────────────────────────────────────────────
[[ -z "$PROFILE_NAME" ]] && fail "No profile specified. Run with --list to see available profiles."
[[ ! -f "$SELECT_FILE" ]] && fail "services.select.json not found: $SELECT_FILE"
[[ ! -d "$PROFILES_DIR" ]] && fail "Profiles directory not found: $PROFILES_DIR"
command -v python3 &>/dev/null || fail "python3 required for profile application"

PROFILE_FILE="$PROFILES_DIR/${PROFILE_NAME}.json"
[[ ! -f "$PROFILE_FILE" ]] && fail "Profile not found: $PROFILE_FILE\nRun with --list to see available profiles."

echo "  Profile : $PROFILE_NAME"
echo "  Source  : $PROFILE_FILE"
echo "  Target  : $SELECT_FILE"
echo ""

# ── Show what will change ─────────────────────────────────────────────────────
python3 - <<PYEOF
import json, sys

with open("$PROFILE_FILE") as f:
    profile = json.load(f)

with open("$SELECT_FILE") as f:
    current = json.load(f)

print("  Profile description:")
print(f"    {profile.get('_description', 'No description')}")
print("")
print("  Services to enable:")
for svc, enabled in profile.get("profiles", {}).items():
    status = "ON" if enabled else "off"
    marker = "  ✓" if enabled else "  ·"
    print(f"  {marker} {svc}: {status}")
print("")
if "tunnel" in profile and "routes" in profile["tunnel"]:
    print("  Tunnel routes:")
    for svc, enabled in profile["tunnel"]["routes"].items():
        if not svc.startswith("_"):
            status = "PUBLIC" if enabled else "private"
            marker = "  ✓" if enabled else "  ·"
            print(f"  {marker} {svc}: {status}")
    print("")
PYEOF

if [[ "$DRY_RUN" == "true" ]]; then
  info "DRY-RUN complete — no changes written."
  exit 0
fi

# ── Backup current services.select.json ───────────────────────────────────────
BACKUP_FILE="${SELECT_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
cp "$SELECT_FILE" "$BACKUP_FILE"
ok "Backup saved: $BACKUP_FILE"

# ── Apply profile ─────────────────────────────────────────────────────────────
python3 - <<PYEOF
import json, sys

with open("$PROFILE_FILE") as f:
    profile = json.load(f)

with open("$SELECT_FILE") as f:
    current = json.load(f)

# Merge profiles block
if "profiles" in profile:
    if "profiles" not in current:
        current["profiles"] = {}
    current["profiles"].update(profile["profiles"])

# Merge tunnel routes (preserve existing non-route tunnel settings)
if "tunnel" in profile:
    if "tunnel" not in current:
        current["tunnel"] = {}
    if "routes" in profile["tunnel"]:
        if "routes" not in current["tunnel"]:
            current["tunnel"]["routes"] = {}
        current["tunnel"]["routes"].update(profile["tunnel"]["routes"])
    # tunnel.enabled from profile only if explicitly set
    if "enabled" in profile["tunnel"]:
        current["tunnel"]["enabled"] = profile["tunnel"]["enabled"]

# Merge backup settings if present in profile
if "backup" in profile:
    if "backup" not in current:
        current["backup"] = {}
    current["backup"].update(profile["backup"])

# Update meta timestamp
if "meta" in current:
    from datetime import datetime
    current["meta"]["last_updated_at"] = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    current["meta"]["last_updated_by"] = "apply-profile.sh"

with open("$SELECT_FILE", "w") as f:
    json.dump(current, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("  Applied successfully.")
PYEOF

ok "Profile '$PROFILE_NAME' applied to services.select.json"
echo ""
echo -e "  ${CYAN}Next steps:${NC}"
echo "  1. Review services.select.json and fill client.name / client.domain / client.timezone"
echo "  2. Run: bash scripts-linux/init.sh"
echo "  3. Run: bash scripts-linux/preflight-check.sh"
echo "  4. Run: bash scripts-linux/start-core.sh"
echo ""
