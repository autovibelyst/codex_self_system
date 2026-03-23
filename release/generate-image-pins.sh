#!/usr/bin/env bash
# =============================================================================
# generate-image-pins.sh — Compose-Derived Image Inventory Lock
# TT-Production v14.0
#
# Scans all docker-compose.yml and *.addon.yml files to discover images.
# Attempts to resolve tags to SHA256 digests via docker manifest inspect.
# Outputs: release/image-inventory.lock.json
#
# EXIT: 0 = complete lock (all digests resolved)
#       1 = tool error
#       3 = partial lock (some digests unresolved) — export will be blocked
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/version.sh"

ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT="$SCRIPT_DIR/image-inventory.lock.json"
DRY_RUN="${1:-}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  TT-Production Image Inventory — ${TT_VERSION}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo ""

# Discover all compose files
COMPOSE_FILES=()
CORE_COMPOSE="$ROOT/tt-core/compose/tt-core/docker-compose.yml"
TUNNEL_COMPOSE="$ROOT/tt-core/compose/tt-tunnel/docker-compose.yml"
[[ -f "$CORE_COMPOSE" ]]   && COMPOSE_FILES+=("$CORE_COMPOSE:core:null")
[[ -f "$TUNNEL_COMPOSE" ]] && COMPOSE_FILES+=("$TUNNEL_COMPOSE:tunnel:null")

# Addon compose files
for f in "$ROOT/tt-core/compose/tt-core/addons/"*.addon.yml; do
  [[ -f "$f" ]] || continue
  [[ "$(basename "$f")" == "00-template.addon.yml" ]] && continue
  addon_name=$(basename "$f" .addon.yml | sed 's/^[0-9]*-//')
  COMPOSE_FILES+=("$f:addon:$addon_name")
done

# Companion (supabase)
SUPA_COMPOSE="$ROOT/tt-supabase/compose/tt-supabase/docker-compose.yml"
[[ -f "$SUPA_COMPOSE" ]] && COMPOSE_FILES+=("$SUPA_COMPOSE:companion:tt-supabase")

# Parse images from each compose file using Python
ALL_IMAGES_JSON=()

for entry in "${COMPOSE_FILES[@]}"; do
  IFS=':' read -r compose_file scope profile_dep <<< "$entry"
  [[ -f "$compose_file" ]] || continue
  rel_compose="${compose_file#$ROOT/}"

  while IFS= read -r line; do
    ALL_IMAGES_JSON+=("$line")
  done < <(python3 - "$compose_file" "$scope" "$profile_dep" "$rel_compose" << 'PYEOF'
import sys, json, re

compose_file, scope, profile_dep, rel_compose = sys.argv[1:]

try:
    with open(compose_file, encoding='utf-8') as f:
        lines = f.readlines()
except Exception as e:
    sys.exit(0)

services_indent = None
service_indent = None
in_services = False
current_service = None

def parse_image(image_value):
    img = image_value.strip().strip('"').strip("'")
    if img.startswith('${') and img.endswith('}'):
        return None
    digest = None
    ref_part = img
    if '@sha256:' in img:
        ref_part, digest = img.split('@', 1)
    if ':' in ref_part and '/' not in ref_part.rsplit(':', 1)[1]:
        img_base, tag = ref_part.rsplit(':', 1)
    else:
        img_base = ref_part
        tag = 'latest'
    return img_base, tag, digest

for raw in lines:
    line = raw.rstrip('\n')
    stripped = line.strip()
    if not stripped or stripped.startswith('#'):
        continue

    indent = len(line) - len(line.lstrip(' '))

    if not in_services:
        if stripped == 'services:':
            in_services = True
            services_indent = indent
            service_indent = services_indent + 2
        continue

    if indent <= services_indent and re.match(r'^[A-Za-z0-9_.-]+:\s*$', stripped):
        in_services = False
        current_service = None
        continue

    service_match = re.match(r'^([A-Za-z0-9_.-]+):\s*$', stripped)
    if indent == service_indent and service_match:
        current_service = service_match.group(1)
        continue

    image_match = re.match(r'^image:\s+(.+)$', stripped)
    if current_service and indent > service_indent and image_match:
        parsed = parse_image(image_match.group(1))
        if not parsed:
            continue
        img_base, tag, digest = parsed
        record = {
            'image_ref': img_base,
            'source_tag': tag,
            'resolved_digest': digest,
            'digest_status': 'resolved' if digest else 'unresolved',
            'scope': scope,
            'profile_dependency': None if profile_dep == 'null' else profile_dep,
            'compose_file': rel_compose,
            'service_name': current_service,
            'locked_at': None
        }
        print(json.dumps(record))
PYEOF
  )
done

echo "  Discovered ${#ALL_IMAGES_JSON[@]} image reference(s)"
echo ""

# Attempt digest resolution
FINAL_IMAGES=()
UNRESOLVED=0

resolve_digest() {
  local full_ref="$1"
  python3 - "$full_ref" << 'PYEOF' 2>/dev/null || true
import json, re, sys, urllib.error, urllib.parse, urllib.request

MANIFEST_ACCEPT = ",".join([
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.v2+json",
])

def parse_ref(ref):
    if "@" in ref:
        ref, _ = ref.split("@", 1)
    parts = ref.split("/")
    if len(parts) > 1 and ("." in parts[0] or ":" in parts[0] or parts[0] == "localhost"):
        registry = parts[0]
        repo = "/".join(parts[1:])
    else:
        registry = "docker.io"
        repo = ref

    last = repo.rsplit("/", 1)[-1]
    if ":" in last:
        repo, tag = repo.rsplit(":", 1)
    else:
        tag = "latest"

    if registry in ("docker.io", "index.docker.io"):
        registry = "registry-1.docker.io"
        if "/" not in repo:
            repo = f"library/{repo}"

    return registry, repo, tag

def open_request(url, headers=None, method="GET"):
    request = urllib.request.Request(url, headers=headers or {}, method=method)
    return urllib.request.urlopen(request, timeout=30)

def parse_bearer_challenge(challenge):
    if not challenge.startswith("Bearer "):
        return None
    params = dict(re.findall(r'(\w+)="([^"]+)"', challenge))
    if "realm" not in params:
        return None
    return params

def with_registry_auth(url, headers=None, method="GET"):
    try:
        return open_request(url, headers=headers, method=method)
    except urllib.error.HTTPError as exc:
        if exc.code != 401:
            raise
        challenge = parse_bearer_challenge(exc.headers.get("WWW-Authenticate", ""))
        if not challenge:
            raise
        token_query = {}
        if challenge.get("service"):
            token_query["service"] = challenge["service"]
        if challenge.get("scope"):
            token_query["scope"] = challenge["scope"]
        token_url = challenge["realm"]
        if token_query:
            token_url = token_url + "?" + urllib.parse.urlencode(token_query)
        token_payload = json.load(open_request(token_url))
        token = token_payload.get("token") or token_payload.get("access_token")
        if not token:
            raise RuntimeError("registry auth challenge did not return a bearer token")
        headers = dict(headers or {})
        headers["Authorization"] = f"Bearer {token}"
        return open_request(url, headers=headers, method=method)

registry, repo, tag = parse_ref(sys.argv[1])
manifest_url = f"https://{registry}/v2/{repo}/manifests/{tag}"
headers = {"Accept": MANIFEST_ACCEPT}

response = with_registry_auth(manifest_url, headers=headers, method="HEAD")
digest = response.headers.get("Docker-Content-Digest", "").strip()
if not digest:
    response = with_registry_auth(manifest_url, headers=headers, method="GET")
    digest = response.headers.get("Docker-Content-Digest", "").strip()

print(digest)
PYEOF
}

for img_json in "${ALL_IMAGES_JSON[@]}"; do
  [[ -z "$img_json" ]] && continue
  digest=$(echo "$img_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['resolved_digest'] or '')" 2>/dev/null || echo "")
  tag=$(echo "$img_json"    | python3 -c "import json,sys; print(json.load(sys.stdin)['source_tag'])" 2>/dev/null || echo "")
  ref=$(echo "$img_json"    | python3 -c "import json,sys; print(json.load(sys.stdin)['image_ref'])" 2>/dev/null || echo "")

  if [[ -z "$digest" && -z "$DRY_RUN" ]]; then
    full_ref="${ref}:${tag}"
    resolved="$(resolve_digest "$full_ref")"
    if [[ -n "$resolved" ]]; then
      img_json=$(echo "$img_json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
d['resolved_digest']='$resolved'
d['digest_status']='resolved'
d['locked_at']='$(date -u +"%Y-%m-%dT%H:%M:%SZ")'
print(json.dumps(d))")
      echo -e "  ${GREEN}[+]${NC} ${full_ref}: resolved"
    else
      UNRESOLVED=$((UNRESOLVED + 1))
      echo -e "  ${YELLOW}[?]${NC} ${full_ref}: unresolved (offline or auth required)"
    fi
  else
    [[ -n "$digest" ]] && echo -e "  ${GREEN}[=]${NC} ${ref}: already pinned" || true
  fi

  FINAL_IMAGES+=("$img_json")
done

# Compute lock status
LOCK_STATUS="complete"
[[ $UNRESOLVED -gt 0 ]] && LOCK_STATUS="partial"
[[ ${#FINAL_IMAGES[@]} -eq 0 ]] && LOCK_STATUS="empty"

# Write lock file
IMAGES_TMP="$(mktemp)"
printf '%s\n' "${FINAL_IMAGES[@]}" > "$IMAGES_TMP"
python3 - "$IMAGES_TMP" "$OUTPUT" "$TIMESTAMP" "$TT_VERSION" "$LOCK_STATUS" "$UNRESOLVED" << 'PYEOF'
import json, sys

images_path, output, timestamp, version, lock_status, unresolved = sys.argv[1:]
images = []
with open(images_path, encoding="utf-8") as handle:
  for line in handle:
    line = line.strip()
    if not line:
      continue
    images.append(json.loads(line))

lock = {
    "_schema": "tt-image-inventory/v1",
    "_generator": "release/generate-image-pins.sh",
    "generated_at": timestamp,
    "tt_version": version,
    "images": images,
    "lock_status": lock_status,
    "unresolved_count": int(unresolved),
}
with open(output, "w", encoding="utf-8") as f:
    json.dump(lock, f, indent=2)
print(f"  Lock written: {len(images)} images, {unresolved} unresolved")
PYEOF
rm -f "$IMAGES_TMP"

echo ""
if [[ $UNRESOLVED -gt 0 ]]; then
  echo -e "  ${YELLOW}[WARN]${NC} Partial lock — $UNRESOLVED digest(s) unresolved"
  echo "         Bundle export will be blocked until all digests are resolved."
  exit 3
else
  echo -e "  ${GREEN}[PASS]${NC} Image inventory lock complete"
fi
