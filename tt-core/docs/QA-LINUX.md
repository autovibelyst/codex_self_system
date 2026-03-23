# Linux QA Checklist — TT-Production v14.0
<!-- Last Updated: v14.0 -->

This document covers the full Linux validation path for TT-Production.
For Windows validation see `docs/QA.md`.

---

## Phase 0: Prerequisites

- [ ] Docker Engine ≥ 24.0 installed and running (`docker version`)
- [ ] Docker Compose v2 plugin installed (`docker compose version`)
- [ ] Current user in docker group (`docker ps` succeeds without sudo)
- [ ] Minimum 4 GB RAM available (`free -h`)
- [ ] Minimum 10 GB free disk space (`df -h .`)
- [ ] Port availability: 15432, 16379, 15678, 15050, 15540 all free

---

## Phase 1: Init

```bash
cd tt-core
bash scripts-linux/init.sh
```

- [ ] `init.sh` completes without error
- [ ] runtime core env exists (external path resolved by scripts-linux/lib/runtime-env.sh)
- [ ] No `__GENERATE__` placeholders remain in runtime core env
- [ ] `TT_TZ` is set to a valid timezone (e.g. `Asia/Riyadh`)

---

## Phase 2: Preflight

```bash
bash scripts-linux/preflight-check.sh
```

- [ ] All **27 checks** pass
- [ ] Zero `[FAIL]` items
- [ ] SMTP warning acceptable if not configured (optional feature)

---

## Phase 3: Start Core Stack

```bash
bash scripts-linux/start-core.sh
# or using the unified CLI:
bash scripts-linux/ttcore.sh up core
```

- [ ] All containers reach `running` state
- [ ] Required containers running:
  - `tt-core-postgres` — healthy
  - `tt-core-redis` — healthy
  - `tt-core-n8n` — healthy
  - `tt-core-n8n-worker` — healthy
  - `tt-core-pgadmin` — running
  - `tt-core-redisinsight` — running

---

## Phase 4: Smoke Test

```bash
bash scripts-linux/smoke-test.sh
```

- [ ] Exit code 0
- [ ] `release/smoke-results.json` updated with live results
- [ ] `verdict: "PASS"` in smoke-results.json
- [ ] n8n accessible at `http://127.0.0.1:${TT_N8N_HOST_PORT}`

---

## Phase 5: Service Access Validation

- [ ] n8n login: `http://127.0.0.1:15678` — first-run wizard completes
- [ ] pgAdmin login: `http://127.0.0.1:15050` — postgres server visible
- [ ] RedisInsight: `http://127.0.0.1:15540` — Redis connected

---

## Phase 6: Backup Validation

```bash
bash scripts-linux/backup.sh
```

- [ ] Backup completes without error
- [ ] Backup directory created: `backups/backup_<timestamp>/`
- [ ] Postgres dumps present
- [ ] `checksums.sha256` file generated
- [ ] Verify checksums: `sha256sum -c checksums.sha256`

---

## Phase 7: Rollback Test (optional but recommended)

```bash
bash scripts-linux/rollback.sh --list
```

- [ ] Shows at least 1 backup snapshot
- [ ] Dry-run restore completes

---

## Phase 8: Full Validation

```bash
bash scripts-linux/validate-deployment.sh
```

- [ ] All categories pass
- [ ] Zero critical failures

---

## Post-Installation Checklist

- [ ] SMTP configured if email notifications required (see `env/.env.example` SECTION: SMTP)
- [ ] `TT_BIND_IP=127.0.0.1` confirmed (or intentionally changed for LAN access)
- [ ] Cloudflare Tunnel configured if public access required
- [ ] Portainer protected by Cloudflare Access policy if enabled

---

*TT-Production v14.0 — Linux QA — docs/QA-LINUX.md*

