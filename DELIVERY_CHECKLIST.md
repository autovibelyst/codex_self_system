# DELIVERY_CHECKLIST - TT-Production v14.0

هذا الملف هو آخر checklist عملي قبل إرسال الحزمة إلى العميل.

## 1. Technical Go/No-Go

- [ ] `tt-core/release/validate-release.ps1` = PASS
- [ ] `tt-core/scripts/Preflight-Check.ps1` = PASS
- [ ] `tt-core/scripts/Smoke-Test.ps1` = PASS
- [ ] لا يوجد ملف `.env` plaintext داخل الشجرة
- [ ] لا يوجد `.git` داخل الحزمة المرسلة

## 2. Package Artifacts

- [ ] ملف الحزمة النهائي موجود: `TT-Production-v14.0.zip`
- [ ] ملف checksum موجود: `TT-Production-v14.0.zip.sha256`
- [ ] الاسم والإصدار متطابقان مع `v14.0`
- [ ] الوثائق الرئيسية مرفقة ومحدثة

## 3. Handoff Documents

- [ ] `COMMERCIAL_HANDOFF.md` محدث
- [ ] `CUSTOMER_ACCEPTANCE_CHECKLIST.md` محدث
- [ ] `RELEASE_AUDIT_SUMMARY.md` محدث
- [ ] `SYSTEM_REQUIREMENTS.md` موجود
- [ ] `LICENSE.md` موجود

## 4. Customer-Specific Values Before Sending

- [ ] تحديد ما إذا كان العميل سيستخدم Tunnel أم لا
- [ ] تحديد ما إذا كان العميل سيستخدم Supabase أم لا
- [ ] تأكيد domain / SMTP / Cloudflare ownership على جهة العميل
- [ ] تأكيد جهة الدعم بعد التسليم

## 5. Recommended Send Order

1. أرسل ملف الحزمة.
2. أرسل ملف checksum.
3. أرسل `COMMERCIAL_HANDOFF.md` و `CUSTOMER_ACCEPTANCE_CHECKLIST.md`.
4. نفّذ acceptance مع العميل أو فريق التشغيل.

## Final Condition

إذا كانت كل البنود أعلاه مكتملة، فالحزمة تعتبر جاهزة للبيع والتسليم التجاري.
