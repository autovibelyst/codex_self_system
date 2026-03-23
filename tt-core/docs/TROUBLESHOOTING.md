# Troubleshooting — TT-Production v14.0

> **Format:** Question & Answer. Jump to the section matching your issue.

---

## Quick Diagnostic

Before diving in, run:
```bash
bash tt-core/scripts-linux/health-dashboard.sh    # Linux/macOS
.\tt-core\scripts\Diag.ps1                      # Windows
```

---

## FAQ — Docker & Installation

**Q: `docker compose` command not found on Linux**
A: You have the legacy `docker-compose` (v1) instead of Compose V2.
```bash
sudo apt-get update && sudo apt-get install docker-compose-plugin
docker compose version  # should show v2.x
```

**Q: Docker Desktop won't start on Windows**
A: Check that WSL2 is enabled:
```powershell
wsl --status
wsl --update
```
Restart Docker Desktop after WSL2 update.

**Q: Preflight fails with "Docker daemon is not running"**
A: Start Docker Desktop (Windows/Mac) or: `sudo systemctl start docker` (Linux).

**Q: "Permission denied" error on Linux when running scripts**
A: Add your user to the docker group:
```bash
sudo usermod -aG docker $USER && newgrp docker
```

---

## FAQ — n8n

**Q: n8n is unreachable after starting**
A: Wait 60 seconds — n8n takes longer than other services on first start.
Check: `docker compose -f tt-core/compose/tt-core/docker-compose.yml logs n8n`

**Q: Workflows not executing / stuck in queue**
A: The n8n-worker must be running alongside n8n main.
```bash
docker ps | grep n8n  # should show both n8n and n8n-worker
```
If worker is missing: `docker compose -f tt-core/compose/tt-core/docker-compose.yml up -d n8n-worker`

**Q: "EXECUTIONS_MODE not set" warning in n8n logs**
A: This is informational only when using queue mode. The worker handles execution.

---

## FAQ — PostgreSQL

**Q: pgAdmin can't connect to PostgreSQL**
A: pgAdmin is pre-configured via servers.json. If the connection fails:
1. Verify PostgreSQL is running: `docker ps | grep postgres`
2. Check credentials in runtime `core.env`: `TT_PGADMIN_DEFAULT_EMAIL` and `TT_PGADMIN_DEFAULT_PASSWORD`
3. In pgAdmin UI, the server may need the `tt-core` password from `TT_PG_PASSWORD`

**Q: "FATAL: role does not exist" errors in logs**
A: The db-provisioner creates per-service users on first start. It runs once then exits.
If it failed: `docker compose -f tt-core/compose/tt-core/docker-compose.yml restart db-provisioner`

**Q: PostgreSQL memory warning at startup**
A: Adjust in runtime `core.env`:
```
TT_PG_SHARED_BUFFERS=128MB   # reduce if < 4GB RAM
TT_PG_MAX_CONNECTIONS=100
```

---

## FAQ — Redis

**Q: Redis authentication error: WRONGPASS**
A: The `TT_REDIS_PASSWORD` in runtime `core.env` does not match the running Redis container.
Solution: `docker compose -f tt-core/compose/tt-core/docker-compose.yml restart redis`
If persists, check that runtime `core.env` is being read correctly.

**Q: Redis is using too much memory**
A: Adjust `maxmemory` in `tt-core/compose/tt-core/volumes/redis/config/redis.conf`:
```
maxmemory 256mb  # reduce if limited RAM
```

---

## FAQ — Cloudflare Tunnel

**Q: Tunnel not connecting: "failed to connect tunnel"**
A: Verify your `CF_TUNNEL_TOKEN` in runtime tunnel env is correct.
Check cloudflared logs: `docker compose -f tt-core/compose/tt-tunnel/docker-compose.yml logs`

**Q: Routes not appearing in Cloudflare dashboard**
A: Run `Update-TunnelURLs.ps1` (Windows) or `bash scripts-linux/update-tunnel-urls.sh` (Linux)
after editing `services.select.json` tunnel routes.

**Q: Only some services accessible via tunnel**
A: Admin services (pgAdmin, Portainer, OpenClaw) are `restricted_admin` tier — disabled by default.
To enable: set `security.allow_restricted_admin_tunnel_routes: true` in `services.select.json`.
⚠️ Only do this behind Cloudflare Access authentication.

---

## FAQ — Backup & Restore

**Q: Backup fails with "openssl: command not found"**
A: Install openssl: `sudo apt-get install openssl` (Linux)
On macOS: `brew install openssl`

**Q: "TT_BACKUP_ENCRYPTION_KEY is not set" warning**
A: This is an advisory — backups still work but will be unencrypted.
To enable encryption: add a 32+ character key to runtime `core.env`:
```
TT_BACKUP_ENCRYPTION_KEY=your-32-char-passphrase-here
```

**Q: Offsite backup failing: "rclone: command not found"**
A: Install rclone: `curl https://rclone.org/install.sh | sudo bash`
Then configure: `rclone config` and set `TT_OFFSITE_REMOTE=remotename:bucket/path` in runtime `core.env`

**Q: restore.sh fails with "pg_restore: error"**
A: Some pg_restore warnings about existing objects are normal (non-fatal).
A true failure will show `ERROR` lines. Check: was the backup from the same PostgreSQL version?

---

## FAQ — macOS Specific

**Q: "no matching manifest for linux/amd64" on Apple Silicon**
A: Add `platform: linux/arm64` to affected services in docker-compose.yml overrides,
or use `DOCKER_DEFAULT_PLATFORM=linux/arm64` in your shell.

**Q: Very slow performance on macOS**
A: Enable VirtioFS in Docker Desktop → Settings → General → "Use VirtioFS".
Also increase Docker Desktop RAM allocation to 8GB+.

**Q: Scripts fail with "permission denied"**
A: macOS may quarantine scripts downloaded as zip:
```bash
xattr -rd com.apple.quarantine TT-Production-v14.0/
chmod +x tt-core/scripts-linux/*.sh
```

---


---

## Full Troubleshooting Reference

# Troubleshooting — TT-Core v14.0

Quick reference for the most common issues. For each issue: cause, diagnosis command, and fix.

---

## 1. n8n يظهر "unhealthy" أو لا يبدأ

**السبب الأكثر شيوعاً:** PostgreSQL أو Redis لم يكتمل startup قبل n8n.

```powershell
# Windows — شوف حالة كل container:
docker ps -a --filter "name=tt-core"

# شوف logs n8n:
docker logs tt-core-n8n --tail 50

# شوف logs postgres:
docker logs tt-core-postgres --tail 30
```

**الحل:**
```powershell
# أعد التشغيل — n8n يحاول مرة أخرى بعد start_period=60s:
scripts\Restart-Core.ps1

# أو انتظر 90 ثانية بعد أول start ثم:
scripts\Smoke-Test.ps1
```

---

## 2. Redis: "NOAUTH Authentication required"

**السبب:** `TT_REDIS_PASSWORD` فارغ أو `__GENERATE__` في `runtime core.env`.

```bash
docker logs tt-core-redis --tail 20
docker logs tt-core-n8n --tail 20 | grep -i redis
```

**الحل:**
```powershell
# أعد توليد الـ secrets (آمن — لا يُعيد كتابة الموجود):
scripts\Init-TTCore.ps1

# ثم أعد تشغيل Redis وn8n:
scripts\Restart-Core.ps1
```

---

## 3. PostgreSQL: "password authentication failed"

**السبب:** `TT_POSTGRES_PASSWORD` تغيّر بعد أن Docker أنشأ الـ volume.

```bash
docker logs tt-core-postgres --tail 20
```

**الحل:**
```powershell
# Option A — استرجع كلمة المرور القديمة من backup:
# `core.env` backup في مجلد الـ backup الأخير

# Option B — إذا لا يوجد backup، امسح قاعدة البيانات وأعد البدء (حذر!):
# docker compose down
# rm -rf compose\tt-core\volumes\postgres\data
# scripts\Init-TTCore.ps1
# scripts\Start-Core.ps1
```

---

## 4. Cloudflare Tunnel لا يتصل

```bash
docker logs tt-core-cloudflared --tail 30
```

**أسباب شائعة:**
- `CF_TUNNEL_TOKEN` غلط أو منتهي الصلاحية
- لا يوجد اتصال إنترنت
- خطأ في `tt_shared_net` (الـ tunnel لا يرى الخدمات)

**الحل:**
```powershell
# تحقق من الـ token:
type %TT_RUNTIME_DIR%\tunnel.env | findstr CF_TUNNEL_TOKEN

# تحقق من أن tt_shared_net موجود:
docker network ls | findstr tt_shared_net

# أعد تشغيل الـ tunnel:
scripts\Stop-Tunnel.ps1
scripts\Start-Tunnel.ps1
```

---

## 5. OpenClaw: LLM يُرجع 404

**السبب:** بادئة النموذج ناقصة أو Ollama لم يُشغَّل.

```bash
docker logs tt-core-openclaw --tail 30
```

**الحل:**
```ini
# في runtime core env، تأكد من البادئة:
TT_OPENCLAW_MODEL=ollama/llama3.2    ← صحيح
TT_OPENCLAW_MODEL=llama3.2           ← خطأ (بادئة ناقصة)

TT_OPENCLAW_MODEL=google/gemini-2.5-flash  ← صحيح للـ cloud
TT_OPENCLAW_MODEL=gemini-2.5-flash         ← خطأ
```

```powershell
# إذا تستخدم Ollama، تأكد أنه يعمل:
docker ps --filter "name=tt-core-ollama"

# وأن النموذج محمّل:
docker exec tt-core-ollama ollama list
docker exec tt-core-ollama ollama pull llama3.2
```

---

## 6. OpenClaw Dashboard: "Invalid token" أو لا يفتح

```powershell
# اقرأ الـ token من `runtime core.env`:
type %TT_RUNTIME_DIR%\core.env | findstr TT_OPENCLAW_TOKEN

# الرابط الصحيح:
# http://127.0.0.1:18789/#token=<القيمة هنا>
```

**تحقق من openclaw.json:**
```json
{
  "gateway": {
    "bind": "lan",           ← يجب "lan" وليس "loopback"
    "auth": {
      "token": "<نفس قيمة TT_OPENCLAW_TOKEN>"
    }
  }
}
```

---

## 7. OpenClaw في SETUP MODE — Telegram لا يستجيب

```ini
# في runtime core env:
TT_OPENCLAW_MODE=production   ← غيّرها من "setup"
```

```powershell
scripts\Stop-Service.ps1 -Service openclaw
scripts\Start-Service.ps1 -Service openclaw
```

---

## 8. WordPress: "Error establishing a database connection"

```bash
docker logs tt-core-wordpress --tail 20
docker logs tt-core-mariadb --tail 20
```

**السبب الأكثر شيوعاً:** MariaDB لم تكتمل startup.

```powershell
# انتظر 30 ثانية ثم:
docker restart tt-core-wordpress

# إذا استمر المشكلة، تحقق من passwords في `runtime core.env`:
# TT_WP_DB_PASSWORD يجب أن يتطابق في MariaDB وWordPress
```

---

## 9. pgAdmin: لا يتذكر الـ server connection بعد restart

**السبب طبيعي:** pgAdmin يحفظ الـ server definitions في `/var/lib/pgadmin` — هذا مرتبط بالـ volume.

**الحل الدائم:** استخدم الـ "Save Password" عند إضافة الـ server، ثم:

```powershell
# تأكد أن volume موجود:
dir compose\tt-core\volumes\pgadmin\data
```

إذا فارغ — أعد إضافة الـ server يدوياً مرة واحدة فقط.

---

## 10. Disk Full — السيرفر امتلأ

```bash
# تحقق من المساحة:
df -h

# أكبر المجلدات:
du -sh /var/lib/docker/containers/* 2>/dev/null | sort -rh | head -10
```

**TT-Core v14.0** يملك log rotation مدمج (50MB × 3 = 150MB max per service).

إذا المشكلة في الـ volumes:
```bash
# أكبر volumes:
du -sh compose/tt-core/volumes/* | sort -rh

# Ollama models (تأخذ GBs):
du -sh compose/tt-core/volumes/ollama/models/
```

---

## 11. Port Conflict: "address already in use"

```powershell
# Windows — شوف مين يستخدم الـ port:
Get-NetTCPConnection -LocalPort 15678 | Select LocalAddress,LocalPort,OwningProcess
Get-Process -Id <OwningProcess>

# Linux:
ss -tlnp | grep 15678
```

**الحل:** غيّر الـ `TT_N8N_HOST_PORT` في `runtime core.env` لـ port مختلف، ثم `Restart-Core.ps1`.

---

## 12. Windows: D: Drive غير موجود (خطأ في الـ path)

**المشكلة:** المسار الافتراضي القديم كان `%USERPROFILE%\stacks\tt-core`.

**TT-Core v14.0** يستخدم `%USERPROFILE%\stacks\tt-core` تلقائياً.

```powershell
# إذا ثبّتت نسخة قديمة، حدد المسار يدوياً:
scripts\Init-TTCore.ps1 -Root "C:\stacks\tt-core"
scripts\Start-Core.ps1  -Root "C:\stacks\tt-core"
```

---

## 13. VPS/Linux: Permission denied على volumes

```bash
docker logs tt-core-n8n --tail 20 | grep -i permission

# الحل الأكثر شيوعاً:
sudo chown -R 1000:1000 compose/tt-core/volumes/n8n
sudo chown -R 999:999   compose/tt-core/volumes/postgres
sudo chown -R 999:999   compose/tt-core/volumes/redis
```

---

## 14. Backup: pg_dump connection refused

```bash
# تأكد postgres يعمل:
docker ps --filter "name=tt-core-postgres"

# الـ backup يعمل فقط إذا postgres running:
docker inspect tt-core-postgres --format "{{.State.Status}}"
```

---

## 15. بعد Update: n8n credentials مفقودة

**السبب الحرج:** `TT_N8N_ENCRYPTION_KEY` تغيّر — n8n لا يستطيع فك تشفير الـ credentials.

```powershell
# تحقق من وجود backup للـ `core.env`:
dir _backups\*\.env.backup

# استرجع الـ encryption key القديم من `core.env.backup` وضعه في `core.env` الحالي
```

**درس:** لا تُغيّر `TT_N8N_ENCRYPTION_KEY` أبداً بعد أول تشغيل.

---

## 16. Docker network: "Resource is still in use"

```powershell
# شوف من يستخدم الـ network:
docker network inspect tt_shared_net

# أوقف كل containers TT-Core:
scripts\Stop-Core.ps1
scripts\Stop-Tunnel.ps1

# ثم:
docker network rm tt_shared_net tt_core_internal
scripts\Start-Core.ps1
```

---

## أدوات التشخيص السريعة

```powershell
# Windows — تقرير شامل:
scripts\Diag.ps1

# فحص كامل لكل الخدمات:
scripts\Smoke-Test.ps1

# حالة containers:
scripts\Status-Core.ps1

# Logs خدمة محددة:
scripts\Logs-Core.ps1 -Service n8n
scripts\Logs-Core.ps1 -Service postgres
scripts\Logs-Core.ps1 -Service openclaw
```

```bash
# Linux/VPS:
bash scripts-linux/smoke-test.sh
bash scripts-linux/status.sh
docker logs tt-core-n8n -f --tail 100
```
