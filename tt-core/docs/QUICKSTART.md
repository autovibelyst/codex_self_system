# TechnoTag Core — Quick Start (Customer One‑Pager)

> هذا الملف مخصص للتسليم السريع للعميل لتثبيت وتشغيل **TT‑Core**، مع إمكانية تشغيل الإضافات وCloudflare Tunnel عند الحاجة.

---

## 0) المتطلبات السريعة
- Windows 11 أو Linux أو macOS
- Docker Desktop (Windows: WSL2 backend)
- PowerShell 5.1 أو أحدث
- Domain اختياري إذا كنت ستستخدم Cloudflare Tunnel

---

## 1) المسارات الافتراضية
- **TT‑Core:** `%USERPROFILE%\stacks\tt-core`
- **TT‑Supabase (اختياري / مستقل):** `%USERPROFILE%\stacks\tt-supabase`

---

## 2) التثبيت (الموصى به)
من داخل الحزمة:

### Windows
1) افتح PowerShell كمسؤول
2) شغّل:
- `installer\Install-TTCore.ps1`

أمثلة:
- `installer\Install-TTCore.ps1`
- `installer\Install-TTCore.ps1 -WithMetabase -WithKanboard`
- `installer\Install-TTCore.ps1 -WithTunnel -Domain "example.com"`
- `installer\Install-TTCore.ps1 -WithOpenClaw -WithMonitoring -WithPortainer`


### macOS (Docker Desktop for Mac)
1) ثبّت Docker Desktop for Mac: https://docker.com/products/docker-desktop  
   يعمل على Apple Silicon (M1/M2/M3) وعلى Intel.
2) افتح Terminal وانتقل إلى مجلد الحزمة:
   ```bash
   cd ~/stacks/TT-Production-v14.0/tt-core
   ```
3) شغّل المثبّت (نفس Linux):
   ```bash
   bash installer/Install-TTCore.sh
   ```
4) Preflight check (20 فحصاً):
   ```bash
   bash scripts-linux/preflight-check.sh
   ```

> **ملاحظة macOS:** تسريع GPU غير متاح على macOS Docker.  
> Ollama يعمل على CPU — استخدم نموذجاً صغيراً (مثلاً `llama3.2:3b`).  
> إذا احتجت bash 4+: `brew install bash`

### Manual fallback
يمكنك أيضًا استخدام:
- `scripts\Init-TTCore.ps1`
- `scripts\Start-Core.ps1`

---

## 3) التشغيل والإيقاف
### تشغيل Core فقط
- `scripts\Start-Core.ps1`

### إيقاف Core
- `scripts\Stop-Core.ps1`

### إعادة تشغيل Core
- `scripts\Restart-Core.ps1`

### تشغيل خدمة اختيارية
- `scripts\Start-Service.ps1 wordpress`
- `scripts\Start-Service.ps1 metabase`
- `scripts\Start-Service.ps1 portainer`

### تشغيل / إيقاف Tunnel
- `scripts\Start-Tunnel.ps1`
- `scripts\Stop-Tunnel.ps1`

---

## 4) الوصول للخدمات
### محليًا
- n8n
- pgAdmin
- RedisInsight
- Metabase (عند التفعيل)
- WordPress (عند التفعيل)
- Portainer (عند التفعيل)

راجع `docs\PORTS.md` للقيم النهائية.

### عبر Tunnel
- لكل خدمة تم تفعيل route لها subdomain مستقل
- يوصى بحماية الخدمات الإدارية عبر Cloudflare Access

---

## 5) سياسة البرودكشن
- baseline الافتراضي = Core only
- WordPress **غير مفعّل افتراضيًا**
- لا تنشر خدمات الإدارة مباشرة على الإنترنت
- التونيل اختياري ومستقل

---

## 6) النسخ الاحتياطي والتحديث
- النسخ الاحتياطي: `docs/BACKUP.md`
- التحديث والترقية: `docs/UPGRADE.md`
- الفحص: `bash scripts-linux/smoke-test.sh`

### جدولة النسخ الاحتياطي التلقائي (Linux/VPS)
إذا كانت قيمة `backup.auto_schedule=true` في `config/services.select.json`، فإن `init.sh` يثبّت جدول cron تلقائياً.
يمكنك أيضاً تشغيله يدوياً:
```bash
# تثبيت الجدول
bash scripts-linux/setup-backup-schedule.sh

# معاينة بدون تثبيت
bash scripts-linux/setup-backup-schedule.sh --dry-run

# إزالة الجدول
bash scripts-linux/setup-backup-schedule.sh --remove
```

### الاستعادة من نسخة احتياطية
```bash
# عرض النسخ المتاحة
ls backups/

# استعادة (مع تأكيد)
bash scripts-linux/restore.sh --backup-dir backups/backup_<stamp> --confirm

# استعادة كاملة بما فيها الـ volumes
bash scripts-linux/restore.sh --backup-dir backups/backup_<stamp> --confirm --force
```

---

## 7) أين أجد التفاصيل؟
- `docs\README.md`
- `docs\SERVICES.md`
- `docs\PORTS.md`
- `docs\SECURITY.md`
- `docs\BACKUP.md`
- `docs\UPGRADE.md`
- `docs\TROUBLESHOOTING.md`
- `docs\QA.md`


