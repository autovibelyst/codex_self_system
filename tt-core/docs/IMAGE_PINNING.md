# Image Digest Pinning Guide — TT-Production v14.0
<!-- Last Updated: v14.0 -->

## Why Pin Images?

Docker image tags (e.g., `postgres:16.6-alpine`) are **mutable**. The same tag can point
to a different image SHA after an upstream push. Digest pinning (`@sha256:<hash>`) makes
images **immutable** — guaranteeing identical bytes on every pull.

Without pinning: `postgres:16.6-alpine` today ≠ `postgres:16.6-alpine` next week.
With pinning:    `postgres:16.6-alpine@sha256:abc123` = exactly that image, always.

---

## Policy

| Scenario | Action |
|----------|--------|
| Before any customer handoff | Generate a complete `release/image-inventory.lock.json` |
| Before commercial packaging | Block export unless every image has a resolved digest |
| After upstream security patches | Refresh the lock, validate, then rebuild the bundle |
| Customer deployment | No post-delivery digest generation required |

---

## Canonical Lock

The commercial bundle is governed by `release/image-inventory.lock.json`.
This file records every image reference discovered from:
- `tt-core/compose/tt-core/docker-compose.yml`
- `tt-core/compose/tt-core/addons/*.addon.yml`
- `tt-core/compose/tt-tunnel/docker-compose.yml`
- `tt-supabase/compose/tt-supabase/docker-compose.yml`

The canonical generator is:

```bash
cd TT-Production-v14.0
bash release/generate-image-pins.sh
```

This script:
1. Discovers all bundle images from compose sources
2. Resolves the registry digest for each image tag
3. Writes `release/image-inventory.lock.json`
4. Exits non-zero if any digest remains unresolved

The bundle export path is strict:
- `release/package-export.sh` fails unless `lock_status == "complete"`
- `unresolved_count` must be `0`
- no image may remain on `:latest`
- `release/image-inventory.lock.json` must ship inside the bundle

Customers do not need to regenerate digests after delivery.

---

## Optional Compose Rewrites

`bash tt-core/scripts-linux/lock-image-digests.sh` still exists for operators who want
to rewrite local compose files with digest-pinned image refs. This is optional and separate
from the bundle-level lock file.

---

## Updating Digests After Security Patches

When upstream security advisories release patched images:

```bash
# 1. Update the image tag in compose/addon files if needed

# 2. Refresh the lock
bash release/generate-image-pins.sh

# 3. Validate the source tree and exported bundle
pwsh -File tt-core/release/validate-release.ps1
pwsh -File release/validate-bundle.ps1 -Root dist/TT-Production-v14.0

# 4. Rebuild the commercial export
bash release/package-export.sh --out dist --version v14.0
```

---

## Rollback with Pinned Images

Pinned digests mean `docker pull` will always retrieve the exact pinned image, even if the
tag was updated upstream. To roll back to a prior deployment:

```bash
bash scripts-linux/rollback.sh --snapshot <snapshot_id>
```

The rollback script uses the digest recorded at backup time, not the current tag.

---

## Verification

Strict validation paths:
- `bash tt-core/scripts-linux/preflight-check.sh`
- `pwsh -File tt-core/scripts/Preflight-Check.ps1`
- `pwsh -File tt-core/release/validate-release.ps1`
- `pwsh -File release/validate-bundle.ps1 -Root <bundle-root>`

---

## Current Pinning Status

Run `bash tt-core/scripts-linux/preflight-check.sh`:
- Check `#24` requires the lock file to exist
- Check `#25` requires the lock to be complete
- Check `#26` blocks `:latest` tags

*TT-Production v14.0 — Image Pinning — docs/IMAGE_PINNING.md*
