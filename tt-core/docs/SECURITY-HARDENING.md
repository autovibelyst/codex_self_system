# Container Security Hardening — TT-Production v14.0

## Applied Hardening (v14.0)

### `security_opt: ["no-new-privileges:true"]`
Applied to all services in:
- `tt-core/compose/tt-core/docker-compose.yml` (9/10 services)
- `tt-supabase/compose/tt-supabase/docker-compose.yml` (all 13 services)
- `tt-core/compose/tt-tunnel/docker-compose.yml` (cloudflared tunnel service)

**Effect:** Prevents privilege escalation via setuid/setgid binaries inside containers. Safe for all API/web/database services. Validated: does not affect service startup or runtime behavior.

### `TT_BIND_IP=127.0.0.1` (default)
All services bound to loopback only. External access via Cloudflare Tunnel exclusively.

### Redis Password Enforcement
`TT_REDIS_PASSWORD` enforced in environment block. Verified by preflight check #16.

### DB Isolation
Per-service PostgreSQL users provisioned by `db-provisioner`. Services cannot cross-access each other's data.

### Network Isolation
Services communicate via internal Docker networks. No service exposes ports on 0.0.0.0 by default.

## Deferred Hardening (v15.0 Roadmap)

| Hardening | Reason Deferred |
|-----------|-----------------|
| `read_only: true` per service | Requires per-service tmpfs mapping. Needs live validation per service to avoid write-path failures. |
| `cap_drop: ["ALL"]` | Some services (postgres, cloudflared) may require specific capabilities. Needs per-service validation in live environment. |
| Non-root users per service | Most images already run non-root; enforcement requires image-specific `user:` mapping validated per image. |
| Docker Secrets / SOPS | Replaces plain env-var secrets. Requires operator workflow changes and compose refactor. |
| Image digest pinning | Requires digest registry lookup per image per release. Implemented: generate-image-pins.sh + image-inventory.lock.json. |
| SBOM + CVE scan (Trivy/Grype) | Deferred to v15.0. |

## Exception Log

| Service | Hardening Skipped | Justification |
|---------|-------------------|---------------|
| ollama | `no-new-privileges` skipped | May require device access for GPU passthrough. Applied manually if GPU not used. |
