# TechnoTag Core (TT-Core) - Production Skeleton

هذا المجلد هو **المرجع التنفيذي الأساسي** لتجهيز نسخة Production من TT-Core على Windows 11 أو Linux،
مع تنظيم ثابت، وملفات Compose واضحة، وسكربتات تشغيل/إيقاف/تشخيص.

## المسار الافتراضي
- `%USERPROFILE%\stacks\tt-core`

## الستاكات
- **tt-core**: الخدمات الأساسية + الخدمات الاختيارية عبر Profiles.
- **tt-tunnel**: Cloudflare Tunnel ستاك مستقل تشغيلًا وإيقافًا.

## تشغيل سريع (على جهاز جديد)
1) انسخ هذا المجلد إلى: `%USERPROFILE%\stacks\tt-core`
2) شغّل:
   - `installer\Install-TTCore.ps1`
3) للتشغيل اليدوي:
   - `scripts\Init-TTCore.ps1`
   - `scripts\Start-Core.ps1`

## ملاحظات مهمة
- baseline البرودكشن = **Core only**
- **WordPress** و **Metabase** و **Portainer** و **OpenClaw** خدمات اختيارية
- **TT-Supabase** منتج مستقل وليس جزءًا من baseline TT-Core
- انشر الخدمات خارجيًا عبر Cloudflare Tunnel فقط عند الحاجة

