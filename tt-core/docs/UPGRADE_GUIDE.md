# Upgrade Guide - TT-Production v14.0

This guide covers safe in-place upgrades without data loss.

---

## Pre-Upgrade Checklist

```bash
# 1) Full backup first
bash scripts-linux/backup.sh
ls -lt backups/ | head -3

# 2) Capture current health baseline
bash scripts-linux/smoke-test.sh
bash scripts-linux/status.sh
```

---

## Linux/macOS Upgrade Procedure

### 1) Prepare old/new paths

```bash
OLD=/opt/stacks/TT-Production-CURRENT/tt-core
NEW=/opt/stacks/TT-Production-v14.0/tt-core
```

### 2) Stop current stack

```bash
cd "$OLD"
bash scripts-linux/stop-core.sh
```

### 3) Carry runtime env to the new bundle

Runtime env is external to the repository and derived from stack root (unless `TT_RUNTIME_DIR` is explicitly set).

```bash
# Resolve old/new runtime env paths using official resolver
source "$OLD/scripts-linux/lib/runtime-env.sh"
OLD_CORE_ENV="$(tt_runtime_core_env_path "$OLD")"
OLD_TUNNEL_ENV="$(tt_runtime_tunnel_env_path "$OLD")"

source "$NEW/scripts-linux/lib/runtime-env.sh"
NEW_CORE_ENV="$(tt_runtime_core_env_path "$NEW")"
NEW_TUNNEL_ENV="$(tt_runtime_tunnel_env_path "$NEW")"

mkdir -p "$(dirname "$NEW_CORE_ENV")"
cp "$OLD_CORE_ENV" "$NEW_CORE_ENV"
chmod 600 "$NEW_CORE_ENV"

if [[ -f "$OLD_TUNNEL_ENV" ]]; then
  cp "$OLD_TUNNEL_ENV" "$NEW_TUNNEL_ENV"
  chmod 600 "$NEW_TUNNEL_ENV"
fi
```

### 4) Carry persistent volumes

```bash
cp -a "$OLD/compose/tt-core/volumes" "$NEW/compose/tt-core/"
cp -a "$OLD/backups" "$NEW/" 2>/dev/null || true
```

### 5) Preflight and start

```bash
cd "$NEW"
bash scripts-linux/preflight-check.sh
bash scripts-linux/start-core.sh
```

### 6) Verify

```bash
sleep 60
bash scripts-linux/smoke-test.sh
bash scripts-linux/status.sh
```

### 7) Tunnel (if enabled)

```bash
bash scripts-linux/start-tunnel.sh
```

---

## Windows PowerShell Upgrade Procedure

```powershell
$old = 'C:\stacks\TT-Production-CURRENT\tt-core'
$new = 'C:\stacks\TT-Production-v14.0\tt-core'

# 1) Backup and stop old stack
& "$old\scripts\backup\Backup-Volumes.ps1"
& "$old\scripts\Stop-Core.ps1"

# 2) Resolve runtime env paths and copy
. "$old\scripts\lib\RuntimeEnv.ps1"
$oldCoreEnv = Get-TTRuntimeCoreEnvPath -ProjectRoot $old
$oldTunnelEnv = Get-TTRuntimeTunnelEnvPath -ProjectRoot $old

. "$new\scripts\lib\RuntimeEnv.ps1"
$newCoreEnv = Get-TTRuntimeCoreEnvPath -ProjectRoot $new
$newTunnelEnv = Get-TTRuntimeTunnelEnvPath -ProjectRoot $new

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $newCoreEnv) | Out-Null
Copy-Item $oldCoreEnv $newCoreEnv -Force
if (Test-Path $oldTunnelEnv) { Copy-Item $oldTunnelEnv $newTunnelEnv -Force }

# 3) Copy volumes, then preflight/start
Copy-Item -Recurse "$old\compose\tt-core\volumes" "$new\compose\tt-core\" -Force
Set-Location $new
& ".\scripts\Preflight-Check.ps1"
& ".\scripts\Start-Core.ps1"
& ".\scripts\Smoke-Test.ps1"
```

---

## Rollback Procedure

```bash
# Stop new bundle
cd /opt/stacks/TT-Production-v14.0/tt-core
bash scripts-linux/stop-core.sh

# Start old bundle
cd /opt/stacks/TT-Production-CURRENT/tt-core
bash scripts-linux/start-core.sh
bash scripts-linux/smoke-test.sh
```

Rollback works as long as the previous bundle and its volumes remain intact.

---

## Post-Upgrade Hardening

```bash
bash scripts-linux/lock-image-digests.sh
bash scripts-linux/backup.sh
bash scripts-linux/verify-restore.sh
```

Keep at least the previous 1-2 bundles until the new version is stable in production.
