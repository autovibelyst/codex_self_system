# Known Limitations — TT-Production v14.0
<!-- Last Updated: v14.0 -->

This document lists all known limitations, their severity, current mitigations,
and planned resolution path. Items are classified by operational impact.

---

## KL-01: ~~Secrets in Plaintext Environment Variables~~ — RESOLVED in v14.0

**Status:** ✅ RESOLVED in v14.0
**Area:** Security

Secrets are now encrypted at rest using SOPS + age. The age private key lives
on the operator machine at `~/.config/tt-production/age/key.txt` and is never
in the repository or any package file.

**Resolution applied:**
- `tt-core/secrets/core.secrets.enc.env` — SOPS-encrypted core secrets
- `tt-core/secrets/tunnel.secrets.enc.env` — SOPS-encrypted tunnel token
- `installer/lib/sops-setup.sh` — bootstraps SOPS + age
- `scripts-linux/migrate-to-sops.sh` — migrates from plaintext (v12.0 → v14.0)
- `scripts-linux/validate-sops.sh` — verifies SOPS setup before start

**Plaintext fallback:** Set `secret_mode: "plaintext"` in `config/services.select.json`
(not recommended for production; generates Preflight warning).

**Remaining consideration:** age private key loss = encrypted secrets unrecoverable.
Back up the key to a secure offline location. See `docs/SOPS_GUIDE.md`.

---

## KL-02: No Rate Limiting on n8n Webhooks at Application Layer

**Severity:** Medium
**Area:** Security / Availability
**Affected versions:** All

n8n webhook endpoints (`/webhook/*`) have no built-in rate limiting.
Under DDoS conditions, the webhook endpoint can be overwhelmed.

**Current mitigation:**
- `TT_BIND_IP=127.0.0.1` — webhooks not directly internet-reachable
- Cloudflare Tunnel + WAF — rate limiting configurable at Cloudflare layer
- n8n queue mode — worker separation prevents main process starvation

**Deferred resolution:** Optional nginx rate-limiting proxy addon — planned for v15.0.

---

## KL-03: `cap_drop: ALL` — Partially Applied (status carried into v14.0)

**Severity:** Low
**Area:** Container Hardening
**Status:** PARTIAL — new addons done; core services pending v15.0

`cap_drop: ALL` is applied to hardened addon set (introduced in v13.0, retained in v14.0):
pgbouncer, minio, qdrant (addon), prometheus, grafana.

**Pending for core services:** postgres, redis, n8n, n8n-worker, pgadmin,
redisinsight — requires per-image capability audit to determine which caps are
genuinely required (e.g., postgres needs `CHOWN`, `SETUID` for initialization).

**Current mitigation:** `no-new-privileges:true` applied to all 23+ containers
prevents escalation even without explicit cap_drop.

**Planned resolution:** Per-service capability audit and `cap_drop: ALL` + selective
`cap_add` for core services — planned for v15.0.

---

## KL-04: `read_only: true` Filesystem — Partially Applied (status carried into v14.0)

**Severity:** Low
**Area:** Container Hardening
**Status:** PARTIAL — qdrant done; others pending v15.0

`read_only: true` is applied to the qdrant addon (introduced in v13.0, retained in v14.0).

**Pending:** Core services (postgres, redis, n8n, pgadmin) — each requires
individual analysis of runtime write paths and tmpfs mapping for temp directories.

**Current mitigation:** Volume mounts explicitly mapped; no sensitive host paths mounted.

**Planned resolution:** Per-service `read_only: true` + tmpfs for temp paths — v15.0.

---

## KL-05: Non-Root User Execution Not Enforced

**Severity:** Low
**Area:** Container Hardening

Not all container images run as non-root by default (notably postgres, n8n).

**Current mitigation:** `no-new-privileges:true` applied; DB isolation via per-service users.

**Deferred resolution:** Per-image UID/GID analysis and `user:` overrides where safe.
Planned for v15.0.

---

## KL-06: ~~Image Digest Pinning Advisory Only~~ — RESOLVED in v14.0

**Status:** ✅ RESOLVED in v14.0
**Area:** Supply Chain Security

Image governance is now mandatory:
- `release/image-inventory.lock.json` — catalogues all images with digest slots
- Preflight Check **#24** — verifies lock file exists
- Preflight Check **#25** — verifies all digests are resolved (no `null` entries)
- Preflight Check **#26** — verifies no `:latest` tags in any compose file
- `release/package-export.sh` — blocks commercial export if the lock is partial
- `release/validate-bundle.ps1` — fails the bundle if the shipped lock is incomplete

**Current state:** the delivered bundle ships with a complete image lock.
Customers do not need to regenerate digests after delivery.

---

## KL-07: Evidence Cert Files Are Pre-Packaged Templates

**Severity:** Low
**Area:** Release Integrity

`deployment-cert.json`, `restore-cert.json`, `handoff-cert.json`, and
`supportability-cert.json` ship as templates (`_is_template: true`). They contain
no live deployment evidence.

**Current mitigation:** All template certs are explicitly marked `_is_template: true`
with instructional `_template_note`. `smoke-results.json` is the primary live evidence
artifact (replaced by `smoke-test.sh` on real deployments).

**Deferred resolution:** Automated cert generation during deployment — planned for v15.0.

---

## KL-08: No Automated Integration Test Suite

**Severity:** Low
**Area:** Quality Assurance

`smoke-test.sh` validates container health but does not perform end-to-end functional
testing (e.g., n8n workflow execution, actual database queries).

**Current mitigation:** Manual QA checklists for Linux (`docs/QA-LINUX.md`) and
Windows (`docs/QA.md`) cover functional validation steps.

**Deferred resolution:** Docker-in-Docker CI integration test suite — planned for v15.0.

---

## KL-09: SBOM Not Generated

**Severity:** Low
**Area:** Supply Chain Transparency

Software Bill of Materials (SBOM) is not generated as part of the release pipeline.
CVE scanning relies on Docker Hub vulnerability reports for each image.

**Current mitigation:** All images use explicit version tags. CVE awareness via
Docker Hub image scanning UI.

**Deferred resolution:** Trivy/Grype SBOM generation and CVE blocking gate — planned for v15.0.

---

## KL-10: Backup Encryption Key Stored in `.env`

**Severity:** Medium
**Area:** Backup Security

The AES-256-CBC backup encryption key is stored in the same `.env` file as
other operational secrets. A leaked `.env` exposes both the backup and its key.

**Current mitigation:** `chmod 600` on `.env`; key is randomly generated by `init.sh`.
Offsite backup transport is separate from local key storage.

**Deferred resolution:** Key derivation from operator-provided passphrase (PBKDF2/argon2)
or HSM/KMS integration — planned for v15.0.

---

## KL-11: macOS Support is Development/Test Only

**Severity:** Low — Documentation Clarity
**Area:** Platform Support

macOS (Docker Desktop) is supported for development and testing workflows.
It is **not validated for production deployments**.

**Current mitigation:** Clearly documented in `docs/PLATFORM_SUPPORT.md`.
Linux VPS/server is the recommended production platform.

**Deferred resolution:** Formal macOS production validation requires additional testing
and Apple Silicon (ARM64) specific verification — planned for v15.0.

---

## KL-12: ARM64 Support is Best-Effort

**Severity:** Low
**Area:** Platform Support

ARM64 platforms (Apple Silicon M1/M2/M3, AWS Graviton) run all core images
but have not been formally validated. Some third-party images may not provide ARM64 variants.

**Current mitigation:** All official core images (`postgres`, `redis`, `n8n`) support ARM64.
Optional services (`metabase`, `qdrant`) should be verified per-deployment.

**Deferred resolution:** Formal ARM64 validation matrix per-image — planned for v15.0.

---

*TT-Production v14.0 — Known Limitations — docs/KNOWN_LIMITATIONS.md*
