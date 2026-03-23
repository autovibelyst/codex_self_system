# Risk Register — TT-Production v14.0

**Status:** Active | **Last Updated:** 2026-03-13 | **Owner:** Release Engineering

---

## Risk Classification

| Level | Criteria |
|-------|---------|
| CRITICAL | Data loss, security breach, service unrecoverable |
| HIGH | Extended downtime, credential exposure, audit failure |
| MEDIUM | Degraded functionality, operator friction, partial data loss |
| LOW | Cosmetic, minor ops friction, documentation gaps |

---

## Active Risks

| ID | Level | Risk | Likelihood | Impact | Mitigation |
|----|-------|------|-----------|--------|-----------|
| R-01 | HIGH | Secrets in plain env vars visible to root on host | Medium | HIGH | RESOLVED: SOPS+age in v14.0. Restrict host root access. |
| R-02 | HIGH | Image tag mutation — no digest pinning | Low | HIGH | Tags from known registries; RESOLVED: image-inventory.lock.json in v14.0. |
| R-03 | MEDIUM | Single-node SPOF — no HA | Medium | HIGH | DR_PLAYBOOK.md documents recovery. Operator to implement backup policy. |
| R-04 | MEDIUM | ollama GPU passthrough may require privileged ops | Low | MEDIUM | ollama excluded from no-new-privileges. Document in ops runbook. |
| R-05 | MEDIUM | n8n workflows not in volume backup by default | Medium | MEDIUM | Operators must export workflows via n8n UI or API. See BACKUP.md. |
| R-06 | LOW | macOS dev/test — not production supported | Medium | LOW | Documented in PLATFORM_SUPPORT_MATRIX.md. |
| R-07 | LOW | Optional add-ons (Metabase, WordPress) — lower maturity | Low | LOW | Add-ons are opt-in. Core stack unaffected if add-ons fail. |
| R-08 | LOW | Clean-room install artifacts not auto-generated | Low | LOW | Validation plan provided; operator generates on live deployment. |

## Closed Risks (Fixed in v14.0)

| ID | Risk | Resolution |
|----|------|-----------|
| R-C01 | preflight-check.sh syntax error — script crashed on first use | Fixed: orphan fi removed + closing fi added |
| R-C02 | consistency-gate failed — schema mismatch _generator vs generated_by | Fixed: _generator added to all generated artifacts |
| R-C03 | verify-manifest.sh failed — version/package_version field mismatch | Fixed: manifest rebuilt with canonical schema |
| R-C04 | Doc lint failures — stale version markers, dead script refs | Fixed: UPGRADE_GUIDE exempted, dead refs updated |
| R-C05 | Evidence certs had hardcoded midnight timestamp | Fixed: dynamic generated_at on all evidence artifacts |
| R-C06 | No shell validation gate in release pipeline | Fixed: validate-scripts.sh added as mandatory gate |
| R-C07 | No runtime security hardening in any compose service | Fixed: no-new-privileges applied to 23 services |
