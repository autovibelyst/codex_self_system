## [v9.4] — 2026-03-11

## v12.0 — 2026-03-13 ← CURRENT STABLE RELEASE (GA)

**Channel:** stable-commercial | **Base:** v10.1

### P0 Fixes
- BUG-R1: All .env.example templates version headers v9.2 → v12.0
- BUG-R2: Edge Function runtime version constant v10.0-RC1 → v12.0
- BUG-E1/E2: Dynamic RELEASE_NOTES filenames in pipeline scripts
- BUG-M1: bundle-manifest.json regenerated from actual package (237 files)
- BUG-G1: RELEASE_AUDIT_SUMMARY.md false claims removed

### P1 Fixes
- BUG-S1: signoff.json dynamic timestamp (no more hardcoded midnight)
- BUG-V1: ancestry self-reference removed; base_version corrected to v10.1
- BUG-V2: release_channel = stable-commercial
- BUG-G2: consistency-gate.sh WARNINGS counter fixed
- BUG-D1: CHANGELOG duplicate entries removed
- BUG-D3: PRODUCTION_SIGNOFF_TEMPLATE.md v9.5 header → v12.0
- BUG-G3: signoff gates added for no_reports_dir, win_offsite_backup, supa scripts

## v10.1 — 2026-03-12

**Channel:** stable-commercial | **Base:** v10.0-RC1

- QUICKSTART-AR.md (Arabic quickstart, 213 lines)
- Backup-OffsiteSync.ps1 (Windows offsite backup via rclone)
- tt-supabase scripts-linux: restore.sh, rollback.sh, rotate-secrets.sh
- Preflight-Check.ps1 Check #2.13: backup encryption advisory
- TROUBLESHOOTING.md restructured as FAQ
- reports/ removed from customer bundle
- manifest.json notes char-array bug fixed

## v7.1 — 2026-03-10 ← CURRENT RELEASE

### Regressions Closed
- `secrets-strength.sh` restored from v6.8.6 and hardened for v7.1
- `release-pipeline.sh` REQ[] now includes all three v7.1 scripts

### New Scripts
- `scripts-linux/cleanup-backups.sh` — retention-based cleanup with `--dry-run`
- `scripts-linux/verify-restore.sh` — schema-only restore test without touching live data
- `scripts-linux/status.sh` — enhanced with `--json` output for monitoring integration

### Preflight (14 checks)
- Check #13: OpenClaw production mode requires `TT_OPENCLAW_TELEGRAM_TOKEN`
- Check #14: `TT_N8N_ENCRYPTION_KEY` must be ≥ 32 characters

### Documentation
- `SECURITY.md`: rate limiting guidance, fixed PORT_POLICY reference
- `PROFILES_AND_ADDONS.md`: comprehensive profile documentation
- `TUNNEL-SUBDOMAINS-POLICY.md`: clear subdomain rules
- `scripts-linux/README.md`: full v7.1 script inventory

### Inherited from v6.8.8 (all preserved)
- 7-stage release-pipeline.sh
- AUTHORITY_MODEL.md three-class file model
- Machine-generated signoff.json
- JSON schemas for service-catalog and services.select
- 4 customer deployment profiles
- support-bundle.sh, update-tunnel-urls.sh, lint-docs.sh
- CI/CD pipeline with Dockerfile/.sh/.ps1 scanning

---

## v6.8.8 — 2026-03-10
See `RELEASE_NOTES_v12.0.md` for details.

## v14.0 — 2026-03-14

### Corrective Hardening (20 fixes)
- All 25+ script banners bumped from v11.2/v12.0/v13.x to v14.0
- pgAdmin banner: v14.0
- docker-compose.yml + tunnel + all 11 addons: v14.0
- generate-signoff.sh: ancestry corrected → v13.0.8 → v14.0
- n8n-worker added to smoke-test (MANDATORY)
- n8n workflow backup added to backup.sh
- TT_N8N_API_KEY added to .env.example
- SOPS: migrate-to-sops.sh, validate-sops.sh, sops-setup.sh all present
- init.sh: --rotate and --migrate-from-plaintext modes restored
- status.sh JSON: clean printf (no broken Python expression)
- KNOWN_LIMITATIONS: KL-01 RESOLVED (SOPS active)
- SECRET_MANAGEMENT.md: rewritten — SOPS is active
- SECURITY-HARDENING.md: SOPS moved from planned to applied
- RISK_REGISTER.md: R-01/R-02 RESOLVED
- tt-core/release/manifest.json: full structure restored (16 images)
- start.sh convenience alias added
- version.json: completed with ancestry, build_id, release_stage
- validate-bundle.ps1: broken warning strings fixed

