
# TT-Core Pre-Release Checklist  (TT-Production v14.0)

Use this checklist before every client delivery or release zip.

## Package Integrity
- [ ] `release\validate-release.ps1` passes
- [ ] `env\.env.example` exists
- [ ] `env\tunnel.env.example` exists
- [ ] `compose\tt-tunnel\.env.example` compatibility copy exists
- [ ] `manifest.json` matches compose image versions
- [ ] Release zip excludes live `.env` files and runtime `volumes/`

## Compose / Profiles
- [ ] `Start-Core.ps1` starts **core only** by default
- [ ] WordPress is opt-in only
- [ ] Metabase is opt-in only (`metabase` profile)
- [ ] Optional services are profile-gated
- [ ] Ports bind to `${TT_BIND_IP}` only
- [ ] Internal services remain on `tt_core_internal`

## Backups / Restore
- [ ] Windows backup creates per-database dumps for ttcore / n8n / metabase / kanboard
- [ ] Linux backup creates the same database dumps
- [ ] scripts-linux/restore.sh present and executable
- [ ] Restore script requires explicit --confirm flag (or --force to skip countdown)
- [ ] Backup docs match actual folder structure

## Security
- [ ] Redis auth enabled
- [ ] Qdrant API key enabled
- [ ] Default bind IP is `127.0.0.1`
- [ ] No admin UI is exposed publicly without explicit tunnel routing
- [ ] No hardcoded production secrets in package files

## Documentation
- [ ] `MASTER_GUIDE.md` reflects current behavior
- [ ] `QUICKSTART.md` reflects profile-based start behavior
- [ ] `QA.md` reflects current core/optional services
- [ ] `UPGRADE.md` is current and not tied to obsolete versions
- [ ] No stale version labels (pre-v9.2) remain in active docs/scripts

## Final QA
- [ ] Fresh init works on a clean path
- [ ] Core stack starts successfully
- [ ] Smoke test passes
- [ ] One full backup succeeds
- [ ] One restore test succeeds on a non-production target DB

## Credential Rotation
- [ ] `docs/CREDENTIAL_ROTATION.md` present and up to date
- [ ] All 12 secrets covered with step-by-step rotation procedures
- [ ] `N8N_ENCRYPTION_KEY` data-loss warning clearly documented
- [ ] `scripts-linux/rotate-secrets.sh` present and executable
- [ ] Rotation schedule table present (recommended frequencies)

## Disaster Recovery
- [ ] `docs/DR_PLAYBOOK.md` present and tested
- [ ] RTO ≤ 30 minutes documented and verified against timed restore test
- [ ] RPO ≤ 24 hours (matches backup schedule)
- [ ] All 6 failure scenarios documented (crash, corruption, host failure, .env loss, worker unhealthy, Redis AOF)
- [ ] Backup verification procedure documented (monthly + quarterly timed test)
