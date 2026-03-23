#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2 ;; *) shift ;; esac; done
ENV_FILE="$ROOT/compose/tt-supabase/.env"
ISSUES=()
PASS=0

get_val() { grep "^${1}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | xargs 2>/dev/null || true; }
is_jwt() { [[ "$(echo "$1" | awk -F'.' '{print NF}')" -eq 3 ]]; }

echo ""
echo -e "\033[36m── TT-Supabase Preflight Check ─────────────────────────────\033[0m"
echo ""

[[ ! -f "$ENV_FILE" ]] && ISSUES+=("compose/tt-supabase/.env not found — run init.sh first")

if [[ ${#ISSUES[@]} -eq 0 ]]; then
  JWT_SECRET=$(get_val JWT_SECRET)
  ANON_KEY=$(get_val ANON_KEY)
  SVC_KEY=$(get_val SERVICE_ROLE_KEY)
  PG_PASS=$(get_val POSTGRES_PASSWORD)
  DOMAIN=$(get_val PUBLIC_DOMAIN)

  [[ -z "$JWT_SECRET" || "$JWT_SECRET" == "__GENERATE__" ]] && ISSUES+=("JWT_SECRET not set — run init.sh")
  [[ -z "$PG_PASS"    || "$PG_PASS"    == "__GENERATE__" ]] && ISSUES+=("POSTGRES_PASSWORD not set")
  is_jwt "$ANON_KEY"   || ISSUES+=("ANON_KEY is not a valid JWT — run init.sh to regenerate")
  is_jwt "$SVC_KEY"    || ISSUES+=("SERVICE_ROLE_KEY is not a valid JWT — run init.sh to regenerate")
  [[ -z "$DOMAIN" || "$DOMAIN" == "example.com" ]] && echo -e "\033[33m[WARN]\033[0m  PUBLIC_DOMAIN is not set to your real domain"
fi

if [[ ${#ISSUES[@]} -gt 0 ]]; then
  for issue in "${ISSUES[@]}"; do echo -e "\033[31m[FAIL]\033[0m $issue"; done
  echo ""
  echo -e "\033[31mPreflight FAILED. Fix issues before starting TT-Supabase.\033[0m"
  exit 1
fi
echo -e "\033[32m✓  Supabase preflight checks passed.\033[0m"
