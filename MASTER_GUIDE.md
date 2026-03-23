# TT-Production v14.0 — Master Guide

هذه هي النسخة الإنتاجية الموحّدة من **TT-Production v14.0** — الإصدار التجاري المُحكَم والمُقوَّى أمنياً.

---

## ما هو TT-Production؟

بنية تحتية كاملة تعمل على أي جهاز محلي أو سيرفر بأمر تثبيت واحد، مع دعم Cloudflare Tunnel للنشر العام اختيارياً.

**Core Stack (دائم التشغيل):**
PostgreSQL 16.6 · Redis 7.4 · n8n 1.88.0 · pgAdmin 4.8.14 · RedisInsight 2.66

**Optional Addons:**
PgBouncer · Metabase · WordPress+MariaDB · Kanboard · Qdrant · Ollama · Open WebUI · Uptime Kuma · Portainer · OpenClaw · MinIO · Prometheus+Grafana

**Supported Platforms (v14.0):**
Windows 11 (Docker Desktop + WSL2) · Linux (Ubuntu/Debian/VPS) · macOS (Docker Desktop — dev/test only)

**Companion Module (مستقل):**
tt-supabase — يُشحن كحزمة منفصلة `TT-Supabase-v14.0tar.gz`

---

## ترتيب التثبيت والتشغيل

```
الطريقة السريعة (مُوصى بها للمستخدمين الجدد):
  bash quick-start.sh

الطريقة التفصيلية:

1. فك الحزمة في مسار ثابت
   Linux:   /opt/stacks/TT-Production-v14.0
   macOS:   ~/stacks/TT-Production-v14.0
   Windows: %USERPROFILE%\stacks\TT-Production-v14.0

2. اذهب إلى tt-core/
   cd tt-core

3. تثبيت SOPS + age (جديد في v14.0 — نظام الأسرار المشفرة)
   bash installer/lib/sops-setup.sh  (Linux/macOS)

4. تهيئة runtime env والأسرار (آمن للتكرار — لا يكتب فوق secrets موجودة)
   bash scripts-linux/init.sh  (Linux/macOS)
   scripts\Init-TTCore.ps1     (Windows)

5. فحص pre-flight قبل أول تشغيل
   bash scripts-linux/preflight-check.sh  (Linux/macOS)
   scripts\Preflight-Check.ps1            (Windows)

6. تشغيل tt-core
   bash scripts-linux/start-core.sh  (Linux/macOS)
   scripts\Start-Core.ps1            (Windows)

7. أضف addons تدريجياً (اختياري)
   bash scripts-linux/ttcore.sh up profile ai-workstation
   bash scripts-linux/ttcore.sh up addon minio

8. فعّل Tunnel بعد نجاح التشغيل المحلي
   bash scripts-linux/start-tunnel.sh
   scripts\Start-Tunnel.ps1

9. لتشغيل tt-supabase (Companion Module — اختياري)
   cd ../tt-supabase
   bash scripts-linux/init.sh
   bash scripts-linux/start.sh
```

---

## ما الجديد في v14.0

### أمان (Breaking Changes)
- **SOPS + age**: أسرار مشفرة — يتطلب تشغيل `installer/lib/sops-setup.sh`
- **Double-Gate للـ Restricted Admin**: فعّل `security-ack.json` قبل كشف pgAdmin/Portainer
- **Image Digest Pinning إلزامي**: لا `latest` tags في أي compose file

### حوكمة
- **Canonical Version**: `release/version.json` المصدر الوحيد — لا version literals في أي سكريبت
- **Version Drift Gate**: Stage 0 من release pipeline يمنع الإصدار عند وجود drift
- **27 Preflight Check**: بدلاً من 22 (5 فحوصات جديدة)
- **Profile-Aware Validation Matrix**: validate-deployment.sh يشتق التوقعات من الـ catalog

### خدمات جديدة
- **PgBouncer** (addon) — Connection pooling لـ PostgreSQL
- **MinIO** (addon) — S3-compatible object storage
- **Prometheus + Grafana** (addon) — Monitoring (Prometheus على admin-net فقط)
- **Qdrant** (addon) — Vector DB للـ RAG (local-only بالافتراضي)

### Scope
- **tt-supabase** الآن Companion Module رسمي بعقد تكامل مستقل

---

## CLI الموحّد (ttcore.sh)

```bash
bash scripts-linux/ttcore.sh up core              # تشغيل core كامل
bash scripts-linux/ttcore.sh up profile ai-workstation  # تشغيل profile
bash scripts-linux/ttcore.sh up addon minio       # تشغيل addon واحد
bash scripts-linux/ttcore.sh down core            # إيقاف core
bash scripts-linux/ttcore.sh status               # حالة الخدمات
bash scripts-linux/ttcore.sh logs n8n             # logs خدمة
bash scripts-linux/ttcore.sh diag                 # تشخيص كامل
bash scripts-linux/ttcore.sh validate             # تشغيل validation matrix
```

---

## الأسرار والأمان (v14.0)

```bash
# الوضع الافتراضي: SOPS + age (مُوصى)
bash installer/lib/sops-setup.sh  # مرة واحدة لإنشاء age key
bash scripts-linux/init.sh        # يشفر الأسرار تلقائياً

# التحقق من صحة SOPS
bash scripts-linux/validate-sops.sh

# تدوير سر منخفض الخطورة
bash scripts-linux/rotate-secrets.sh --secret TT_PGADMIN_PASSWORD

# كشف الخدمات الإدارية المقيدة (يتطلب بوابة مزدوجة)
# انظر: docs/RESTRICTED_ADMIN_GUIDE.md
bash scripts-linux/verify-security-ack.sh
```

---

## النسخ الاحتياطية

```bash
# نسخ احتياطي محلي
bash scripts-linux/backup.sh

# نسخ احتياطي خارجي — S3/Wasabi/Cloudflare R2
# عيّن TT_OFFSITE_REMOTE في .env
bash scripts-linux/backup-offsite.sh

# اختبار (dry-run)
bash scripts-linux/backup-offsite.sh --dry-run

# التراجع الفوري
bash scripts-linux/rollback.sh --latest
```

---

## نقاط التحقق قبل التسليم

```bash
# Release validator (authoritative commercial gate)
powershell -ExecutionPolicy Bypass -File tt-core/release/validate-release.ps1

# Preflight
bash scripts-linux/preflight-check.sh

# Smoke test
bash scripts-linux/smoke-test.sh
```

---

## ملاحظات أمنية هامة

- `TT_BIND_IP=127.0.0.1` بالافتراضي — لا كشف للشبكة المحلية
- Prometheus على `tt_admin_net` فقط — **لا يُعرَّض عبر tunnel أبداً**
- Grafana على `restricted_admin` tier — يتطلب double-gate
- pgAdmin وPortainer: `tunnel routes` معطّل بالافتراضي ويتطلب `security-ack.json`
- كل خدمة لها قاعدة بيانات PostgreSQL ومستخدم منفصل (db-provisioner)
- أسرار SOPS لا تُحفظ في الـ repository — private key على جهاز المشغّل فقط

---

## tt-supabase (Companion Module)

tt-supabase منتج مستقل يتكامل مع TT-Core ولكنه **ليس جزءاً منه**.

- حزمة منفصلة: `TT-Supabase-v14.0tar.gz`
- يتطلب: TT-Core ≥ v14.0
- قاعدة بيانات PostgreSQL مستقلة (لا تشارك tt-core postgres)
- حد دعم مستقل: مشاكل Supabase لا تغطيها SLA الخاصة بـ TT-Core
- عقد التكامل: `tt-supabase/contract/integration.json`

---

> **Note:** `config/public-exposure.policy.json` ملف مُولَّد.
> أعد توليده بـ `bash release/generate-exposure.sh` عند تغيير service-catalog.json.
