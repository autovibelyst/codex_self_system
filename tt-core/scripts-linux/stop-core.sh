#!/usr/bin/env bash
# stop-core.sh — Stop TT-Core stack (Linux/VPS/macOS)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2 ;; *) shift ;; esac; done

CORE_DIR="$ROOT/compose/tt-core"
COMPOSE_CMD="docker compose -f $CORE_DIR/docker-compose.yml"
for addon in "$CORE_DIR"/addons/*.addon.yml; do [[ -f "$addon" ]] && COMPOSE_CMD="$COMPOSE_CMD -f $addon"; done

echo "Stopping TT-Core..."
$COMPOSE_CMD down
echo -e "\033[0;32mOK: TT-Core stopped.\033[0m"
