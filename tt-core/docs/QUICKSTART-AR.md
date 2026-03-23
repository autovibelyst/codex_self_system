# دليل التثبيت السريع — TT-Production v14.0

**المنصات المدعومة:** Linux (Ubuntu/Debian/VPS) · Windows 11 (Docker Desktop + WSL2) · macOS (Docker Desktop)

---

## قبل البدء — المتطلبات الأساسية

| المتطلب | الحد الأدنى | الموصى به |
|---------|------------|-----------|
| ذاكرة الوصول العشوائي | 4 جيجابايت | 8 جيجابايت+ |
| مساحة التخزين | 20 جيجابايت SSD | 50 جيجابايت+ SSD |
| Docker | 24.0+ | 25.0+ |
| Docker Compose | 2.20+ | 2.24+ |

---

## التثبيت على Linux (Ubuntu 22.04 — الموصى به للإنتاج)

### 1. تثبيت Docker

```bash
curl -fsSL https://get.docker.com | bash
sudo usermod -aG docker $USER
newgrp docker
docker --version   # تحقق: Docker Engine 24.0+
```

### 2. فك الضغط

```bash
sudo mkdir -p /opt/stacks
cd /opt/stacks
unzip TT-Production-v14.0.zip
cd TT-Production-v14.0/tt-core
```

### 3. تهيئة البيئة

```bash
# ينشئ .env مع أسرار آمنة تلقائياً (آمن للتكرار — لا يستبدل القيم الموجودة)
bash scripts-linux/init.sh
```

### 4. فحص ما قبل التشغيل (20 فحصاً)

```bash
bash scripts-linux/preflight-check.sh
# يجب أن تنتهي بـ: ✓ Preflight PASSED
```

### 5. تشغيل النظام

```bash
bash scripts-linux/start-core.sh
# انتظر 30–60 ثانية حتى تنبثق كل الخدمات
```

### 6. التحقق من الصحة

```bash
bash scripts-linux/smoke-test.sh
# المتوقع: 7/7 PASS
bash scripts-linux/status.sh
```

### 7. فتح الواجهات

| الواجهة | العنوان الافتراضي |
|---------|-----------------|
| n8n (أتمتة) | http://localhost:5678 |
| pgAdmin (قاعدة بيانات) | http://localhost:5050 |
| RedisInsight (Redis) | http://localhost:8001 |

---

## التثبيت على Windows 11

### 1. تثبيت Docker Desktop

قم بتنزيل Docker Desktop من https://docker.com وتثبيته.
تأكد من تفعيل WSL2 backend.

```powershell
docker --version   # تحقق
docker compose version
```

### 2. فك الضغط

```powershell
# الاستخراج إلى مسار ثابت
Expand-Archive -Path TT-Production-v14.0.zip -DestinationPath $env:USERPROFILE\stacks
Set-Location $env:USERPROFILE\stacks\TT-Production-v14.0	t-core
```

### 3. تهيئة وتشغيل

```powershell
# تهيئة .env والأسرار
.\scripts\Init-TTCore.ps1

# فحص ما قبل التشغيل
.\scripts\Preflight-Check.ps1

# تشغيل
.\scripts\Start-Core.ps1

# التحقق
.\scripts\Smoke-Test.ps1
```

---

## التثبيت على macOS

### 1. تثبيت Docker Desktop

قم بتنزيل Docker Desktop لـ Mac من https://docker.com (Apple Silicon أو Intel).

```bash
docker --version   # تحقق
```

### 2. فك الضغط

```bash
mkdir -p ~/stacks
cd ~/stacks
unzip TT-Production-v14.0.zip
cd TT-Production-v14.0/tt-core
```

### 3. تهيئة وتشغيل

```bash
bash scripts-linux/init.sh
bash scripts-linux/preflight-check.sh
bash scripts-linux/start-core.sh
bash scripts-linux/smoke-test.sh
```

> **ملاحظة Apple Silicon (M1/M2/M3):** جميع الصور متوافقة مع arm64. Ollama/AI models تعمل على CPU.

---

## الخطوات الاختيارية

### تفعيل النفق العام (Cloudflare Tunnel)

```bash
# Linux
bash scripts-linux/start-tunnel.sh

# Windows
.\scripts\Start-Tunnel.ps1
```

### تفعيل النسخ الاحتياطي

```bash
# نسخ محلي
bash scripts-linux/backup.sh

# نسخ خارجي (S3/Wasabi/Cloudflare R2)
# أولاً: عيّن TT_OFFSITE_REMOTE في .env
bash scripts-linux/backup-offsite.sh
```

### إضافة خدمات اختيارية

```bash
# مثال: Metabase
bash scripts-linux/apply-profile.sh metabase

# مثال: Open WebUI + Ollama (AI)
bash scripts-linux/apply-profile.sh openwebui
```

---

## أوامر مفيدة

```bash
# الحالة
bash scripts-linux/status.sh

# السجلات
docker compose -f compose/tt-core/docker-compose.yml logs -f n8n

# إيقاف
bash scripts-linux/stop-core.sh

# تحديث
bash scripts-linux/bump-version.sh   # راجع UPGRADE_GUIDE.md

# دعم فني (حزمة آمنة بدون أسرار)
bash scripts-linux/support-bundle.sh
```

---

## في حالة حدوث مشكلة

راجع: `tt-core/docs/TROUBLESHOOTING.md` — دليل FAQ كامل.

```bash
# تشخيص متكامل (Windows)
.\scripts\Diag.ps1

# Linux
bash scripts-linux/health-dashboard.sh
```
