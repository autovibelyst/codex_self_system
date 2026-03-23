# TT-Production v14.0 — Release Notes

**Release Date:** 2026-03-14
**Version:** v14.0 (General Availability — Fully Hardened Commercial Release)
**Base Version:** v13.0.8
**Build ID:** tt-production-v14.0-20260314
**Verdict:** PASS
**Bundle:** TT-Production-v14.0.zip + TT-Supabase-v14.0.zip (companion)

---

## What's New in v14.0

### Corrective Hardening (over v13.0.8)

This release closes all known defects from the v13.x series. v14.0 is the first
release that passes the complete release governance checklist with no P0 or P1
blockers remaining.

### Defects Resolved

| ID | Priority | Description | Resolution |
|----|----------|-------------|------------|
| FIX-01 | P0 | pgAdmin banner hardcoded v12.0 | Updated to v14.0 |
| FIX-02 | P0 | docker-compose.yml header stale | Updated to v14.0 |
| FIX-03 | P0 | 6 addon file headers stale (v12.0) | All updated to v14.0 |
| FIX-04 | P0 | generate-signoff.sh: wrong ancestry + base_version | Fixed to v13.0.8 → v14.0 |
| FIX-05 | P0 | RELEASE_AUDIT_SUMMARY stale (v12.0 data) | Rebuilt for v14.0 |
| FIX-06 | P0 | KNOWN_LIMITATIONS: KL-01 not resolved | RESOLVED: SOPS+age active |
| FIX-07 | P0 | SECRET_MANAGEMENT.md: says "not implemented" | Rewritten: SOPS is active |
| FIX-08 | P0 | status.sh JSON broken (Python expression) | Fixed: simple printf |
| FIX-09 | P0 | supabase/backup.sh JSON broken | Fixed |
| FIX-10 | P0 | init.sh: --rotate/--migrate modes missing | Restored from v13.0-T |
| FIX-11 | P1 | n8n-worker missing from smoke-test | Added MANDATORY check |
| FIX-12 | P1 | n8n workflow backup missing | Added with TT_N8N_API_KEY |
| FIX-13 | P1 | TT_N8N_API_KEY missing from .env.example | Added Section 11 |
| FIX-14 | P1 | 40–67 scripts had v11.2/v12.0 banners | All bumped to v14.0 |
| FIX-15 | P1 | validate-bundle.ps1 broken warning strings | Fixed |
| FIX-16 | P1 | tt-core/release/manifest.json truncated | Restored full structure |
| FIX-17 | P1 | SECURITY-HARDENING.md: SOPS listed as planned | Updated: applied |
| FIX-18 | P1 | RISK_REGISTER.md: R-01/R-02 open | Marked RESOLVED |
| FIX-19 | P2 | start.sh missing (convenience alias) | Added |
| FIX-20 | P2 | version.json incomplete (no ancestry/build_id) | Completed |

### Confirmed Working Features (carried from v13.x)

- SOPS + age secret encryption (`migrate-to-sops.sh`, `validate-sops.sh`)
- Restricted admin double-gate (`security-ack.json`)
- 8-stage release pipeline
- drift-scan.sh + consistency-gate.sh (12 real checks)
- 27-check preflight (hardened)
- generate-image-pins.sh (registry-derived, bundle-blocking)
- PgBouncer, MinIO, Prometheus+Grafana, Qdrant addons
- tt-supabase companion module with formal integration contract

### Preflight: 27 Checks

| # | Check |
|---|-------|
| 23 | Restricted admin security acknowledgment |
| 24 | Image lock presence in bundle/root |
| 25 | Image lock completeness |
| 26 | No `:latest` tags in any compose file |
| 27 | SOPS availability and decrypt test |

---

## Migration from v13.x

```bash
# 1. Backup
bash tt-core/scripts-linux/backup.sh

# 2. Extract v14.0 bundle
unzip TT-Production-v14.0.zip
cd TT-Production-v14.0

# 3. If coming from plaintext (v12.x or earlier)
bash tt-core/installer/lib/sops-setup.sh
bash tt-core/scripts-linux/migrate-to-sops.sh

# 4. Run preflight (27 checks)
bash tt-core/scripts-linux/preflight-check.sh

# 5. Start
bash tt-core/scripts-linux/start-core.sh
# or: bash tt-core/scripts-linux/start.sh
```

---

## Known Residual Items (v14.0)

- **KL-01 RESOLVED**: Secrets are SOPS-encrypted. Age private key loss = secrets unrecoverable — back up key.
- **KL-03 PARTIAL**: `cap_drop: ALL` applied to new addons; pending for core services (v15.0)
- **KL-04 PARTIAL**: `read_only: true` applied to qdrant; others pending (v15.0)
- **KL-08 OPEN**: No automated integration test suite — manual QA checklists provided
- **Image digests**: Bundle now ships with a complete `image-inventory.lock.json`

---

*TT-Production v14.0 — General Availability — 2026-03-14*
