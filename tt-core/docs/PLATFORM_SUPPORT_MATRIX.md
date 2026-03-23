# Platform Support Matrix — TT-Production v14.0

## Support Tiers

| Tier | Definition |
|------|-----------|
| ✅ Production | Fully tested, scripts provided, supported by vendor |
| ⚠ Dev/Test | Works but not validated for production workloads |
| ❌ Unsupported | Not tested, no scripts, no support |

## OS and Runtime

| Platform | Tier | Docker | Scripts | Notes |
|----------|------|--------|---------|-------|
| Ubuntu 22.04 LTS | ✅ Production | Docker CE | scripts-linux/ | Primary target |
| Ubuntu 24.04 LTS | ✅ Production | Docker CE | scripts-linux/ | Tested |
| Debian 12 | ✅ Production | Docker CE | scripts-linux/ | Tested |
| Windows 11 + Docker Desktop | ✅ Production | Docker Desktop | scripts/ (PS1) | WSL2 required |
| Windows Server 2022 | ⚠ Dev/Test | Docker Desktop | scripts/ (PS1) | Not validated |
| macOS 13+ + Docker Desktop | ⚠ Dev/Test | Docker Desktop | Manual | CPU-only, no GPU |
| ARM64 Linux (Graviton, Pi) | ⚠ Dev/Test | Docker CE | scripts-linux/ | Image compat varies |
| Rootless Docker | ⚠ Dev/Test | Docker CE rootless | scripts-linux/ | Untested |

## Feature Parity by Platform

| Feature | Linux | Windows | macOS |
|---------|-------|---------|-------|
| Core stack (start/stop/status) | ✅ | ✅ | ✅ |
| Preflight checks | ✅ (20 checks) | ✅ (13 checks) | ⚠ Manual |
| Backup / Restore | ✅ | ✅ | ⚠ Manual |
| Offsite backup (rclone) | ✅ | ✅ | ⚠ Manual |
| Secret rotation | ✅ | ⚠ Partial | ⚠ Manual |
| Support bundle | ✅ | ⚠ Manual | ⚠ Manual |
| Health dashboard | ✅ | ⚠ Via PowerShell | ⚠ Manual |
| Smoke test | ✅ | ⚠ Manual | ⚠ Manual |
| Tunnel management | ✅ | ✅ | ⚠ Manual |
| Arabic quickstart | ✅ | ✅ | ✅ |
