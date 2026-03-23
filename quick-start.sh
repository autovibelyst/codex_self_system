#!/usr/bin/env bash
# =============================================================================
# quick-start.sh — TT-Production v14.0 Guided Setup
# Top-level entry point for new operator onboarding.
# Delegates to tt-core/installer/Install-TTCore.sh after profile selection.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/release/lib/version.sh"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

clear
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   TT-Production ${TT_VERSION} — Guided Quick Setup     ║${NC}"
echo -e "${CYAN}║   Self-Hosted AI & Automation Infrastructure         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  This wizard will set up your TT-Production stack."
echo "  Prerequisites: Docker 24+, Docker Compose 2.20+, bash 5+"
echo ""

# Profile selection
echo -e "${CYAN}  Select a deployment profile:${NC}"
echo ""
echo "  1) ai-workstation     — n8n + Ollama + Open WebUI + Qdrant + MinIO"
echo "  2) small-business     — n8n + Kanboard + Metabase + Uptime Kuma"
echo "  3) local-private      — n8n + pgAdmin (local only, no tunnel)"
echo "  4) public-productivity— n8n + WordPress + Kanboard (with tunnel)"
echo "  5) custom             — choose services interactively"
echo ""
read -r -p "  Enter choice [1-5]: " PROFILE_CHOICE

case "$PROFILE_CHOICE" in
  1) PROFILE="ai-workstation" ;;
  2) PROFILE="small-business" ;;
  3) PROFILE="local-private" ;;
  4) PROFILE="public-productivity" ;;
  5) PROFILE="custom" ;;
  *) echo "Invalid choice. Defaulting to local-private."; PROFILE="local-private" ;;
esac

echo ""
echo -e "  ${GREEN}Profile selected: $PROFILE${NC}"
echo ""
echo -e "${YELLOW}  Launching installer...${NC}"
echo ""

exec bash "$SCRIPT_DIR/tt-core/installer/Install-TTCore.sh" --profile "$PROFILE"
