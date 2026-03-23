# TT-Core Versioning Policy

## Version Format
**SemVer**: `MAJOR.MINOR.PATCH`

| Increment | When |
|-----------|------|
| **MAJOR** | Breaking change: compose structure, env key renames, data migration required |
| **MINOR** | New services/addons, new scripts, backwards-compatible improvements |
| **PATCH** | Bug fixes, documentation corrections, script tweaks |

## Build Metadata (optional)
Internal builds may append date: `MAJOR.MINOR.PATCH+YYYYMMDD`
Example: `0.4.0+20260306`

## Release Channels
- **stable** — recommended for all client deliveries
- **edge** — internal testing only, may have breaking changes

## What Gets Versioned
- Compose files (`docker-compose.yml`, addons, tunnel)
- Script bundle (`scripts/`, `installer/`)
- Documentation (`docs/`, `release/`)
- Environment templates (`env/.env.example`)

## Upgrade Guarantees
| From → To | Action Required |
|-----------|-----------------|
| Same MAJOR | Run `Update-TTCore.ps1` — minimal manual steps |
| MAJOR bump | Read `UPGRADE.md` carefully — may require data migration |

## Image Versioning
- Images are pinned in compose files (never `:latest` in production)
- After `Update-TTCore.ps1`, lock file updated in `compose/.locks/`
- Use `Show-ComposeImages.ps1` to audit current image versions
