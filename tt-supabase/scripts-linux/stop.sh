#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2 ;; *) shift ;; esac; done
COMPOSE_DIR="$ROOT/compose/tt-supabase"
ENV_FILE="$ROOT/compose/tt-supabase/.env"
echo "Stopping TT-Supabase..."
docker compose -f "$COMPOSE_DIR/docker-compose.yml" --env-file "$ENV_FILE" down
echo "TT-Supabase stopped."
