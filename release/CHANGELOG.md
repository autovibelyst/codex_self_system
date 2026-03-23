# TT-Production — Release Changelog

---

## v14.0 — 2026-03-14 ← CURRENT RELEASE (GA — Fully Hardened)

20 defects from v13.x series resolved. SOPS active, n8n-worker in smoke-test,
n8n workflow backup, all script banners v14.0, pgAdmin banner fixed,
status.sh JSON fixed, KL-01 RESOLVED (SOPS), SECRET_MANAGEMENT rewritten,
RISK_REGISTER R-01/R-02 closed. First fully clean release since v12.0.

See `RELEASE_NOTES_v14.0.md` for complete defect list.

---

v11.2 — 2026-03-13 ← CURRENT STABLE RELEASE (GA)

**Type:** General Availability — Stable Commercial Release
**Channel:** stable-commercial
**Base:** v10.1

### P0 — Critical Fixes (Blocked Commercial Sale)

- **[BUG-R1]** All 5 `.env.example` templates: stale v9.2 version headers removed — now v11.2
- **[BUG-R2]** Supabase Edge Function `index.ts`: hardcoded `version: 'v10.0-RC1'` → dynamic constant `v11.2`
- **[BUG-E1]** `release/package-export.sh`: hardcoded `RELEASE_NOTES_v9.5.md` → dynamic `RELEASE_NOTES_${VERSION}.md`
- **[BUG-E2]** `release/release-pipeline.sh`: hardcoded `RELEASE_NOTES_v9.5.md` → dynamic `RELEASE_NOTES_${VERSION}.md`
- **[BUG-M1]** `release/bundle-manifest.json`: regenerated from actual package (237 files, no v9_5 refs)
- **[BUG-G1]** `RELEASE_AUDIT_SUMMARY.md`: removed false PASS claims — replaced with machine-evidence-backed statements

### P1 — Governance & Reliability

- **[BUG-S1]** `release/signoff.json`: dynamic timestamp (`date -Iseconds`) — never hardcoded midnight again
- **[BUG-V1]** `release/version.json`: ancestry self-reference removed (`→ v11.2 → v11.2` → `→ v10.1 → v11.2`)
- **[BUG-V1]** `release/version.json`: `base_version` corrected from `v10.5/v11.2` to `v10.1`
- **[BUG-V2]** `release/version.json`: `release_channel` → `stable-commercial`
- **[BUG-G2]** `release/consistency-gate.sh`: WARNINGS counter now correctly increments in stale-marker scan
- **[BUG-D1]** `release/CHANGELOG.md`: duplicate contradictory entries removed — single authoritative entry
- **[BUG-D2]** `tt-core/release/CHANGELOG.md`: v11.2 GA entry added
- **[BUG-D3]** `tt-core/release/PRODUCTION_SIGNOFF_TEMPLATE.md`: stale v9.5 header → v11.2
- **[BUG-G3]** `release/generate-signoff.sh`: added gates — `no_reports_dir`, `win_offsite_backup`, `supa_restore/rollback/rotate`, `quickstart_ar`

### Identity & Consistency

- All 237 active files unified to v11.2 identity
- `RELEASE_NOTES_v10.1.md` renamed → `RELEASE_NOTES_v11.2.md`
- All certification artifacts re-issued for v11.2
- `service-catalog.json` version = v11.2
- `public-exposure.policy.json` generated_version = v11.2
- validate-bundle.ps1 Gate 30: design-aware Warn (not hard FAIL)

### Carried from v10.1 Base

- QUICKSTART-AR.md (Arabic, 213 lines)
- Backup-OffsiteSync.ps1 (Windows offsite, rclone)
- tt-supabase: restore.sh, rollback.sh, rotate-secrets.sh
- Preflight-Check.ps1: Check #2.13 (backup encryption advisory)
- TROUBLESHOOTING.md: Full FAQ structure (29+ Q&A)

---

## v10.1 — 2026-03-12

**Type:** General Availability
**Channel:** stable-commercial
**Base:** v10.0-RC1

### Key Changes
- QUICKSTART-AR.md added (Arabic quickstart, 213 lines)
- Backup-OffsiteSync.ps1 added (Windows offsite backup via rclone)
- tt-supabase scripts-linux completed: restore.sh, rollback.sh, rotate-secrets.sh
- Preflight-Check.ps1 Check #2.13: backup encryption advisory
- TROUBLESHOOTING.md restructured as FAQ (29+ Q&A)
- reports/ removed from customer bundle
- manifest.json notes char-array bug fixed

---

## v10.0-RC1 — 2026-03-12

**Type:** Release Candidate

### Key Changes
- CUSTOMER_ACCEPTANCE_CHECKLIST.md
- SYSTEM_REQUIREMENTS.md
- validate-bundle.ps1 (30 sections, 13 acceptance gates)
- make-release.sh (7-stage orchestrator)
- generate-signoff.sh rebuilt (95 real checks)
- All P0 installer + MASTER_GUIDE + preflight issues resolved

---

## v9.5 — 2026-03-12

### Key Changes
- All docs updated to v9.5 identity
- FULL_PACKAGE_GUIDE.md, COMMERCIAL_HANDOFF.md updated
- UPGRADE_GUIDE.md with macOS steps
- version.json introduced


## v14.0 — 2026-03-14 ← CURRENT STABLE RELEASE (GA)

Full corrective hardening release. 20 P0/P1 defects from v13.x closed.
SOPS+age active, n8n-worker smoke-test, n8n workflow backup, all banners v14.0,
generate-signoff ancestry corrected, SECRET_MANAGEMENT/SECURITY-HARDENING/RISK_REGISTER updated.

See `RELEASE_NOTES_v14.0.md` for the full defect list.

---

