#!/usr/bin/env bash
# =============================================================================
# release/lib/version.sh — Canonical Version Reader (TT-Production v14.0)
# THE ONLY AUTHORITATIVE WAY to read package version in bash.
#
# Usage: source release/lib/version.sh
# Exports: TT_VERSION, TT_BUNDLE, TT_RELEASE_DATE, TT_BUILD_ID, TT_RELEASE_STAGE
#
# RULE: No script may hardcode a version literal. All must source this file.
# =============================================================================
set -euo pipefail 2>/dev/null || true

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_VERSION_FILE="$_LIB_DIR/../version.json"

_die() {
  echo "$1" >&2
  return 1 2>/dev/null || exit 1
}

[[ -f "$_VERSION_FILE" ]] || _die "FATAL: release/version.json not found at $_VERSION_FILE"
command -v python3 >/dev/null 2>&1 || _die "FATAL: python3 required to parse release/version.json"

mapfile -t __tt_fields < <(python3 - "$_VERSION_FILE" << 'PYEOF'
import json, sys

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    data = json.load(f)

keys = ["package_version", "bundle_name", "release_date", "build_id", "release_stage"]
for k in keys:
    v = data.get(k)
    print("" if v is None else str(v))
PYEOF
)

TT_VERSION="${__tt_fields[0]:-}"
TT_BUNDLE="${__tt_fields[1]:-}"
TT_RELEASE_DATE="${__tt_fields[2]:-}"
TT_BUILD_ID="${__tt_fields[3]:-}"
TT_RELEASE_STAGE="${__tt_fields[4]:-}"

[[ -n "$TT_VERSION" ]] || _die "FATAL: package_version missing in release/version.json"
[[ -n "$TT_BUNDLE" ]] || _die "FATAL: bundle_name missing in release/version.json"
[[ -n "$TT_RELEASE_DATE" ]] || _die "FATAL: release_date missing in release/version.json"
[[ -n "$TT_BUILD_ID" ]] || _die "FATAL: build_id missing in release/version.json"
[[ -n "$TT_RELEASE_STAGE" ]] || _die "FATAL: release_stage missing in release/version.json"

for i in "${!__tt_fields[@]}"; do
  __tt_fields[$i]="${__tt_fields[$i]%$'\r'}"
done

TT_VERSION="${TT_VERSION%$'\r'}"
TT_BUNDLE="${TT_BUNDLE%$'\r'}"
TT_RELEASE_DATE="${TT_RELEASE_DATE%$'\r'}"
TT_BUILD_ID="${TT_BUILD_ID%$'\r'}"
TT_RELEASE_STAGE="${TT_RELEASE_STAGE%$'\r'}"

export TT_VERSION TT_BUNDLE TT_RELEASE_DATE TT_BUILD_ID TT_RELEASE_STAGE
