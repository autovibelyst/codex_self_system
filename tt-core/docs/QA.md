
# TT-Core Production QA Checklist  (TT-Production v14.0)

Validate a **fresh install** before handover. All required checks must pass.

---

## 0) Preconditions
- [ ] Docker running
- [ ] PowerShell 5.1+ available
- [ ] Clean test path prepared
- [ ] `scripts\Init-TTCore.ps1` completed successfully
- [ ] runtime core env exists (external path resolved by scripts\lib\RuntimeEnv.ps1)

---

## 1) Core Start

```powershell
scripts\Start-Core.ps1
```

Expected:
- [ ] No compose errors
- [ ] Core containers start: postgres, redis, n8n, pgAdmin, RedisInsight
- [ ] No optional service starts unless explicitly requested

---

## 2) Automated Validation

```powershell
scripts\Smoke-Test.ps1
```

Expected:
- [ ] Exit code 0
- [ ] Required HTTP checks pass
- [ ] No required container missing

---

## 3) Web UI Verification

Open local endpoints from the runtime core env:

- [ ] n8n login/setup page opens
- [ ] pgAdmin opens
- [ ] RedisInsight opens
- [ ] Metabase opens only if the `metabase` profile was enabled

---

## 4) Database Verification

Using pgAdmin or `psql`:
- [ ] Main DB exists
- [ ] n8n DB exists
- [ ] Metabase DB exists if enabled
- [ ] Kanboard DB exists if enabled

---

## 5) Optional Services (only when enabled)

### WordPress
- [ ] WordPress page opens
- [ ] MariaDB is healthy before WordPress starts

### Kanboard
- [ ] Kanboard opens
- [ ] Admin login works

### Qdrant / Ollama / OpenWebUI
- [ ] Containers are up only when their profiles are enabled
- [ ] No unintended public exposure

### Uptime Kuma / Portainer / OpenClaw
- [ ] Open normally when enabled
- [ ] Tunnel exposure is intentional and protected

---

## 6) Backup / Restore

- [ ] `scripts\backup\Backup-All.ps1` succeeds
- [ ] Per-database dumps are created
- [ ] `scripts\backup\Restore-PostgresDump.ps1` works on a test target DB

---

## 7) Restart / Persistence

- [ ] Stop/start cycle succeeds
- [ ] Restart-Core starts only baseline core services unless profiles are explicitly requested
- [ ] Existing workflows/data remain present after restart

---

## 8) Sign-Off

A build is production-approved only if:
- [ ] package validator passed
- [ ] fresh init passed
- [ ] core start passed
- [ ] smoke test passed
- [ ] backup passed
- [ ] restore test passed
- [ ] no critical logs/errors remain
