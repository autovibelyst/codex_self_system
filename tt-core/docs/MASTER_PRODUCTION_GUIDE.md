# دليل TT-Production النهائي (TT-Core + الحزمة الاختيارية TT-Supabase)

هذا الدليل هو المرجع التشغيلي النهائي لحزمة `TT-Production-v14.0`.
اسم المنتج التجاري هو **TT-Production**، بينما يبقى مسار التشغيل الفعلي بعد التثبيت:
- `%USERPROFILE%\stacks\tt-core`

هذا الفصل بين **اسم الباندل** و**مسار التشغيل** مقصود لتسهيل التحديث والدعم.

## 0) ما الذي لدينا؟

### A) TT-Core (المنتج الأساسي)
- المسار التشغيلي الافتراضي على ويندوز: `%USERPROFILE%\stacks\tt-core`
- Core baseline:
  - Postgres
  - Redis
  - n8n
  - pgAdmin
  - RedisInsight
- Add-ons عبر Profiles (اختيارية بالكامل):
  - `wordpress`
  - `metabase`
  - `kanboard`
  - `qdrant`
  - `ollama`
  - `openwebui`
  - `monitoring`
  - `portainer`
  - `openclaw`
- الشبكات:
  - `tt_shared_net`
  - `tt_core_internal` (`internal: true`)
- سياسة الأمان:
  - كل البورتات على الهوست مربوطة بـ `127.0.0.1` افتراضيًا
  - النشر الخارجي يتم فقط عبر **Cloudflare Tunnel** عند الحاجة
- WordPress غير مفعّل افتراضيًا. يتم تفعيله فقط بطلب صريح.
- القيم الأولية للتثبيت تُقرأ من `config/services.select.json`
- سياسة النشر العام المركزية تُقرأ من `config/public-exposure.policy.json`

### B) TT-Supabase (اختياري / مستقل)
- المسار التشغيلي الافتراضي: `%USERPROFILE%\stacks\tt-supabase`
- ستاك مستقل عن TT-Core تشغيلًا ونسخًا احتياطيًا وتحديثًا
- يمكن توزيعه مع نفس الباندل التجاري كمنتج إضافي مستقل

## 1) كيف نفهم الحزمة؟
- اسم الحزمة التجارية: `TT-Production-v14.0`
- مقترح حفظ الحزمة قبل التثبيت على ويندوز: `%USERPROFILE%\stacks\TT-Production-v14.0`
- أين تعمل البيئة بعد التثبيت:
  - TT-Core → `%USERPROFILE%\stacks\tt-core`
  - TT-Supabase → `%USERPROFILE%\stacks\tt-supabase`

  لا تخلط بين **مجلد الباندل** وبين **مجلد التشغيل الفعلي**.

## 2) تجهيز جهاز عميل جديد (Windows 11)
1. ثبّت Docker Desktop
2. فعّل WSL2 backend
3. استخدم PowerShell 5.1 أو أحدث
4. استخدم دومين فقط إذا كنت ستفعل Cloudflare Tunnel

### التثبيت
1. افتح مجلد الباندل `TT-Production-v14.0`
2. شغّل `tt-core\installer\Install-TTCore.ps1`
3. يقوم الإنستالر بقراءة `tt-core\config\services.select.json` افتراضيًا

## 3) baseline البرودكشن المعتمد
عند التشغيل الافتراضي يجب أن يعمل فقط:
- postgres
- redis
- n8n
- pgadmin
- redisinsight

ولا يجب أن يبدأ أي profile اختياري تلقائيًا.

## 4) التشغيل والإيقاف
- تشغيل Core فقط: `scripts\Start-Core.ps1`
- إعادة تشغيل Core فقط: `scripts\Restart-Core.ps1`
- تشغيل خدمة اختيارية: `scripts\Start-Service.ps1 wordpress`
- تشغيل التونيل: `scripts\Start-Tunnel.ps1`

  التونيل مستقل عن core ويعمل فقط بعد تجهيز `runtime tunnel.env` الخارجي.

## 5) الوصول المحلي الافتراضي
المرجع النهائي للبورتات هو `docs/PORTS.md`.

أمثلة شائعة:
- n8n: `http://127.0.0.1:15678`
- pgAdmin: `http://127.0.0.1:15050`
- RedisInsight: `http://127.0.0.1:15540`
- WordPress: `http://127.0.0.1:18081` عند التفعيل
- Portainer: `http://127.0.0.1:19000` عند التفعيل
