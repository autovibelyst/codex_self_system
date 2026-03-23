# Customer Acceptance Checklist - TT-Production v14.0

**Date:** _______________
**Customer/Operator:** _______________
**Environment:** _______________
**Engineer:** _______________

---

## Phase 1: Package Verification

- [ ] **1.1** Package received: `TT-Production-v14.0.zip` (or equivalent)
- [ ] **1.2** Checksum verified against the supplied `.sha256` file
- [ ] **1.3** Package extracted without errors
- [ ] **1.4** Run: `powershell -ExecutionPolicy Bypass -File tt-core/release/validate-release.ps1`
- [ ] **1.5** Expected result: `PASSED - 100 checks OK, 0 failures, 0 warnings`
- [ ] **1.6** `LICENSE.md` reviewed and accepted
- [ ] **1.7** `SYSTEM_REQUIREMENTS.md` reviewed and prerequisites confirmed

---

## Phase 2: Configuration

- [ ] **2.1** `MASTER_GUIDE.md` reviewed and installation path confirmed
- [ ] **2.2** Init executed once to create the external runtime env
- [ ] **2.3** Runtime env path confirmed and editable by the operator
- [ ] **2.4** Client identity, domain, timezone, and SMTP values reviewed and adjusted if needed
- [ ] **2.5** `TT_BIND_IP` set correctly (`127.0.0.1` for private use, `0.0.0.0` only with firewall controls)
- [ ] **2.6** Cloudflare Tunnel token configured if public exposure is required
- [ ] **2.7** `TT_BACKUP_ENCRYPTION_KEY` present and accepted
- [ ] **2.8** Backup notification webhook configured if desired

---

## Phase 3: Preflight

- [ ] **3.1** Run: `bash tt-core/scripts-linux/preflight-check.sh` or `.\\tt-core\scripts\Preflight-Check.ps1`
- [ ] **3.2** Result shows `Preflight checks PASSED`
- [ ] **3.3** No `FAIL` results appear in output
- [ ] **3.4** Docker version confirmed compatible

---

## Phase 4: First Start

- [ ] **4.1** Run: `bash tt-core/scripts-linux/init.sh` or `.\\tt-core\scripts\Init-TTCore.ps1`
- [ ] **4.2** DB provisioner completes without error
- [ ] **4.3** Core services start: postgres, redis, n8n, n8n-worker, pgAdmin, RedisInsight
- [ ] **4.4** If tunnel is enabled, run the tunnel start command for the chosen platform
- [ ] **4.5** Run: `bash tt-core/scripts-linux/smoke-test.sh` or `.\\tt-core\scripts\Smoke-Test.ps1`
- [ ] **4.6** Smoke test result shows `RESULT: ALL CHECKS PASSED`

---

## Phase 5: Health Verification

- [ ] **5.1** Run: `bash tt-core/scripts-linux/status.sh` or `.\\tt-core\scripts\Status-Core.ps1`
- [ ] **5.2** Verify core containers are `Up` and `healthy`
- [ ] **5.3** n8n accessible at the configured local or routed URL
- [ ] **5.4** pgAdmin container healthy
- [ ] **5.5** RedisInsight container healthy
- [ ] **5.6** If tunnel is enabled, public endpoints are reachable through Cloudflare

---

## Phase 6: Backup and Restore

- [ ] **6.1** Run: `bash tt-core/scripts-linux/backup.sh`
- [ ] **6.2** Backup completes with integrity artifacts generated
- [ ] **6.3** Run: `bash tt-core/scripts-linux/verify-restore.sh` (dry-run)
- [ ] **6.4** Restore integrity confirmed
- [ ] **6.5** Optional full restore rehearsal completed on staging or approved environment

---

## Phase 7: Support Bundle

- [ ] **7.1** Run: `bash tt-core/scripts-linux/support-bundle.sh`
- [ ] **7.2** Bundle generated successfully
- [ ] **7.3** Bundle reviewed and sensitive values confirmed redacted
- [ ] **7.4** Bundle metadata shows version `v14.0`

---

## Phase 8: Acceptance Sign-Off

**All Phase 1-7 checks completed:** YES / NO

**Issues found (if any):**
_____________________________________________

**Notes:**
_____________________________________________

**Customer/Operator signature:** _______________
**Date:** _______________
**Handoff engineer signature:** _______________
**Date:** _______________

---

## Reference Commands

```bash
# Full health check
bash tt-core/scripts-linux/preflight-check.sh
bash tt-core/scripts-linux/smoke-test.sh
bash tt-core/scripts-linux/status.sh

# Backup and restore validation
bash tt-core/scripts-linux/backup.sh
bash tt-core/scripts-linux/verify-restore.sh

# Support bundle
bash tt-core/scripts-linux/support-bundle.sh

# Tunnel (optional)
bash tt-core/scripts-linux/start-tunnel.sh
```

```powershell
# Release verification
powershell -ExecutionPolicy Bypass -File .\tt-core\release\validate-release.ps1
```
