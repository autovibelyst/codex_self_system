## [v6.7.3] — 2026-03-10

## v11.2 — 2026-03-12 ← CURRENT RELEASE (GA)

**Type:** General Availability — Full Commercial Release
**Base:** v10.0-RC1 (Release Candidate)
**Channel:** stable-commercial

### P0 — RC1 Blockers Resolved
- Removed reports/ directory from customer bundle (internal audit artifacts)
- Promoted release_channel: release-candidate → stable-commercial
- Fixed tt-core/release/manifest.json: notes field was char-array instead of string
- Re-issued all 5 certification artifacts for v11.2 identity
- RELEASE_NOTES_v10.0-RC1.md archived to release/history/

### P1 — Important Improvements
- Added Backup-OffsiteSync.ps1 (Windows offsite backup parity with Linux)
- Added Preflight-Check.ps1 check #2.13: backup encryption advisory (Windows parity)
- Added tt-supabase restore.sh, rollback.sh, rotate-secrets.sh (Linux)
- Added QUICKSTART-AR.md (Arabic quickstart — Linux, Windows, macOS)
- Restructured TROUBLESHOOTING.md as FAQ with categories
- Updated CHANGELOG.md (this file) with v11.2 entry

---

- Active TT-Supabase release docs aligned to current bundle version
- Current preflight validation aligned with `compose/tt-supabase/.env`
- URL validation updated for `SUPABASE_PUBLIC_URL`, `API_EXTERNAL_URL`, and `SITE_URL`
- Historical multi-version changelog moved to bundle-level `release/history/`
