# TT-Production v14.0 — Full Package Guide

هذه هي الحزمة الموحّدة الكاملة النهائية لـ **TT-Production v14.0**.

## البنية
```text
TT-Production-v14.0/
├── tt-core/     ← البيئة الأساسية (PostgreSQL، Redis، n8n، pgAdmin، RedisInsight + Addons)
└── tt-supabase/ ← Supabase BaaS stack (اختياري)
```

## مسارات مقترحة
- **Windows:** `%USERPROFILE%\stacks\TT-Production-v14.0`
- **Linux:** `/opt/stacks/TT-Production-v14.0`

## التسلسل الكامل

### 1) Validate قبل أي شيء
```powershell
cd TT-Production-v14.0
.\tt-core\release\validate-release.ps1
```

### 2) Init + Preflight
```powershell
cd tt-core
.\scripts\Init-TTCore.ps1
.\scripts\Preflight-Check.ps1
```

### 3) Start Core
```powershell
.\scripts\Start-Core.ps1
```

### 4) Addons (اختياري)
```powershell
# فعّل الـ profile في config/services.select.json أولاً
.\scripts\ttcore.ps1 up profile metabase
.\scripts\ttcore.ps1 up profile openclaw
```

### 5) Tunnel (اختياري)
```powershell
# تأكد أن tunnel.enabled=true في config/services.select.json
.\scripts\Start-Tunnel.ps1
```

### 6) Supabase (اختياري)
```powershell
cd ..\tt-supabase
# ضع ملف compose/tt-supabase/.env
.\scripts\start.ps1
```

## ما يميّز هذه النسخة
- هوية إصدار نشطة نظيفة ومختومة على `v14.0`
- فصل واضح بين وثائق التشغيل الحالية والتاريخ الهندسي داخل `release/history/`
- تشغيل tunnel ما زال fail-closed لكن أصبح يزامن عناوين n8n وWordPress تلقائيًا
- `start-core.sh` بقي في المسار الآمن بدون `eval`
- Preflight لـ Supabase أصبح متوافقًا مع متغيرات URL الحديثة
- تمت إضافة وثائق GPU والموارد لتسهيل التخطيط التشغيلي

## قبل أول تشغيل فعلي
```powershell
tt-core\scripts\Preflight-Check.ps1 -IncludeSupabase
```

> **Note:** `config/public-exposure.policy.json` is a generated compatibility artifact.
> Refresh it from `config/service-catalog.json` with `scripts/Sync-PublicExposurePolicy.ps1` whenever service metadata changes.

## Final Validation Before Delivery
```powershell
tt-core\release\validate-release.ps1
tt-core\scripts\Preflight-Check.ps1
tt-core\scripts\Smoke-Test.ps1
```
