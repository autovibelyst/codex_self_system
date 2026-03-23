#!/usr/bin/env bash
# =============================================================================
# start.sh — TT-Production v14.0 — Quick Start Alias
# Convenience wrapper → delegates to start-core.sh
#
# Usage:  bash scripts-linux/start.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/start-core.sh" "$@"
