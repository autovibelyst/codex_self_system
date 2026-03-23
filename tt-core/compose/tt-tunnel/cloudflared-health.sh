#!/bin/sh
# cloudflared-health.sh — Cloudflare tunnel health probe
#
# Probes the cloudflared metrics endpoint at /ready.
# Returns 0 (healthy) when the tunnel is connected and reports {"healthy":true}.
#
# Strategy:
#   1) Primary:  wget (lightweight, present in cloudflare/cloudflared image)
#   2) Fallback: python3 urllib.request (no external dependency)
#
# Called by docker-compose.yml healthcheck — must exit 0 or 1 only.
# ---------------------------------------------------------------------------

ENDPOINT="http://127.0.0.1:2000/ready"

# Primary: wget
if wget -qO- "http://127.0.0.1:2000/ready" 2>/dev/null | grep -q '"healthy"'; then
    exit 0
fi

# Fallback: python3 urllib
if python3 - <<'PYEOF' 2>/dev/null
import urllib.request, sys
try:
    r = urllib.request.urlopen('http://127.0.0.1:2000/ready', timeout=5)
    sys.exit(0 if 'healthy' in r.read().decode() else 1)
except Exception:
    sys.exit(1)
PYEOF
then
    exit 0
fi

exit 1

