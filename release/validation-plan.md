# Clean-Room Validation Plan — TT-Production v14.0

**Purpose:** Define the exact steps to validate the package on a fresh server before commercial delivery.

---

## Prerequisites

- Clean Ubuntu 22.04 LTS VPS (2+ CPU, 4+ GB RAM, 20+ GB SSD)
- Docker 25.0+ and Docker Compose 2.24+
- No existing TT-Production installation
- Network access (outbound HTTPS)

---

## Step 1: Unpack and Verify

```bash
# Transfer package
scp TT-Production-v14.0zip user@server:~

# Verify checksum
sha256sum -c TT-Production-v14.0zip.sha256

# Extract
unzip TT-Production-v14.0zip
cd TT-Production-v14.0

# Verify release identity
python3 -c "import json; d=json.load(open('release/version.json')); print(d['package_version'])"
# Expected: 13.0.0

# Run signoff verification
bash release/generate-signoff.sh
# Expected: PASS — 95+ checks
```

---

## Step 2: Preflight

```bash
cd tt-core
cp compose/tt-core/.env.example compose/tt-core/.env

# Edit .env - set all required values
# Then run preflight
bash scripts-linux/preflight-check.sh
# Expected: 20/20 PASS
```

---

## Step 3: First Start

```bash
bash scripts-linux/init.sh
# Expected: all services start, DB provisioned
```

---

## Step 4: Smoke Test

```bash
bash scripts-linux/smoke-test.sh
# Expected: 7/7 PASS
# smoke-results.json updated
```

---

## Step 5: Status Check

```bash
bash scripts-linux/status.sh
# Verify: "package_version": "v14.0" in output
# Verify: all services show healthy
```

---

## Step 6: Backup Flow

```bash
bash scripts-linux/backup.sh
# Expected: backup created with checksums.sha256

bash scripts-linux/verify-restore.sh
# Expected: checksums match
```

---

## Step 7: Stop and Full Restore Test

```bash
bash scripts-linux/stop.sh
bash scripts-linux/restore.sh --backup [backup-file]
bash scripts-linux/start-core.sh
bash scripts-linux/smoke-test.sh
# Expected: 7/7 PASS after restore
```

---

## Step 8: Support Bundle

```bash
bash scripts-linux/support-bundle.sh
# Verify: bundle generated
# Verify: env values REDACTED in bundle
# Verify: package_version=v14.0 in version.json
```

---

## Step 9: Release Signoff

```bash
# Run final signoff
bash release/generate-signoff.sh
python3 -c "
import json
d = json.load(open('release/signoff.json'))
print(f'Verdict: {d[\"pipeline_verdict\"]}')
print(f'Checks: {d[\"total_checks\"]} total, {d[\"checks_passed\"]} pass')
print(f'Host: {d[\"generated_on_host\"]}')
"
# Expected: PASS, 95+ checks, actual server hostname
```

---

## Step 10: Release Pipeline

```bash
# Final release pipeline (from package root)
bash release/release-pipeline.sh
# Expected: all 10 stages pass
```

---

## Pass Criteria

All of the following must be true:

- [ ] sha256 checksum verified
- [ ] signoff.json: PASS (95+ checks)
- [ ] preflight: 20/20 checks pass
- [ ] smoke-test: 7/7 probes pass
- [ ] status.sh: version = 13.0.0
- [ ] backup: success with checksums
- [ ] restore: checksums match
- [ ] support-bundle: env values REDACTED, version correct
- [ ] release-pipeline: all stages pass
- [ ] generated_on_host: real server (not CI/build host)

---

## Failure Procedure

If any step fails:
1. Capture the error output
2. Run `bash scripts-linux/support-bundle.sh`
3. Review `release/signoff.json` for specific check failures
4. Resolve the issue and re-run from the failed step
5. Do not mark the release ready until all checks pass on actual hardware

---

## Completion

When all pass criteria are met, the release is validated for commercial delivery.

Record the validation results in:
- `release/signoff.json` (auto-generated)
- `CUSTOMER_ACCEPTANCE_CHECKLIST.md` (manual sign-off)
