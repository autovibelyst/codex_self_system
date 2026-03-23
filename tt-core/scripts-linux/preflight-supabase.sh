
#!/usr/bin/env bash
# TT-Supabase Preflight Check — TT-Production v14.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPABASE_ROOT="$ROOT/tt-supabase"
ISSUES=()
WARNINGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --supabase-root) SUPABASE_ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

get_env() { grep -E "^${1}=" "$2" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '
'; }

ENV_FILE="$SUPABASE_ROOT/compose/tt-supabase/.env"
echo -e "
[36m── TT-Supabase Preflight Check — TT-Production v14.0 ─────[0m"

[[ -f "$ENV_FILE" ]] || { echo -e "[31m[FAIL][0m compose/tt-supabase/.env not found. Run Init-Supabase.ps1"; exit 1; }

JWT_SECRET=$(get_env "JWT_SECRET" "$ENV_FILE")
ANON_KEY=$(get_env "ANON_KEY" "$ENV_FILE")
SVC_KEY=$(get_env "SERVICE_ROLE_KEY" "$ENV_FILE")
PG_PASS=$(get_env "POSTGRES_PASSWORD" "$ENV_FILE")
DASHBOARD_PASSWORD=$(get_env "DASHBOARD_PASSWORD" "$ENV_FILE")
SUPABASE_PUBLIC_URL=$(get_env "SUPABASE_PUBLIC_URL" "$ENV_FILE")
API_EXTERNAL_URL=$(get_env "API_EXTERNAL_URL" "$ENV_FILE")
SITE_URL=$(get_env "SITE_URL" "$ENV_FILE")

[[ -z "$JWT_SECRET" ]] && ISSUES+=("JWT_SECRET not set")
[[ ${#JWT_SECRET} -lt 32 ]] && ISSUES+=("JWT_SECRET too short")
[[ $(echo "$ANON_KEY" | tr -cd '.' | wc -c) -ne 2 ]] && ISSUES+=("ANON_KEY is not a valid JWT (run Init-Supabase.ps1)")
[[ $(echo "$SVC_KEY" | tr -cd '.' | wc -c) -ne 2 ]] && ISSUES+=("SERVICE_ROLE_KEY is not a valid JWT (run Init-Supabase.ps1)")
[[ -z "$PG_PASS" ]] && ISSUES+=("POSTGRES_PASSWORD not set")
[[ -z "$DASHBOARD_PASSWORD" ]] && ISSUES+=("DASHBOARD_PASSWORD not set")
[[ -z "$SUPABASE_PUBLIC_URL" || "$SUPABASE_PUBLIC_URL" == *"__SET_YOUR_SUPABASE_DOMAIN__"* ]] && WARNINGS+=("SUPABASE_PUBLIC_URL is not set to a real public URL")
[[ -z "$API_EXTERNAL_URL" || "$API_EXTERNAL_URL" == *"__SET_YOUR_SUPABASE_DOMAIN__"* ]] && WARNINGS+=("API_EXTERNAL_URL is not set to a real public URL")
[[ -z "$SITE_URL" || "$SITE_URL" == *"__SET_YOUR_APP_DOMAIN__"* ]] && WARNINGS+=("SITE_URL is not set to a real frontend URL")

for issue in "${ISSUES[@]}"; do echo -e "[31m[FAIL][0m $issue"; done
for w in "${WARNINGS[@]}"; do echo -e "[33m[WARN][0m $w"; done

[[ ${#ISSUES[@]} -gt 0 ]] && { echo -e "[31mSupabase preflight FAILED.[0m"; exit 1; }
echo -e "[32m✓  Supabase preflight passed.[0m"
