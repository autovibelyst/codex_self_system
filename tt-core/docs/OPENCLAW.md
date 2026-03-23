# OpenClaw AI Agent — دليل الإعداد الكامل

> **Profile:** `openclaw` | **المنفذ:** `TT_OPENCLAW_HOST_PORT` (افتراضي: `18789`)
> **يعتمد على:** n8n (service_healthy)

---

## ما هو OpenClaw؟

OpenClaw هو وكيل ذكاء اصطناعي مستقل يعمل بمبدأ **"العقل يفكر، n8n ينفّذ"**:

```
المستخدم (Telegram)
       ↓
 OpenClaw — يستقبل الرسالة، يحلل النية، يقرر أي "مهارة" يستدعي
       ↓ HTTP Webhook
 n8n — يستقبل الطلب، ينفذ المنطق (DB/API/تقرير...)، يُرجع JSON
       ↓
 OpenClaw — يصيغ الرد بلغة طبيعية
       ↓
المستخدم (Telegram) — يستقبل الرد
```

**المميز في هذه التكاملة مع TT-Production:**
- النموذج افتراضياً **Ollama محلي** (مجاني، خصوصية كاملة، لا إنترنت)
- الذاكرة طويلة الأمد عبر **Qdrant** (إذا مفعّل)
- كل workflow تبنيه في n8n يصبح "مهارة" للـ AI تلقائياً
- لوحة Canvas تعرض تفكير الـ AI خطوة بخطوة

---

## المتطلبات

| المتطلب | الحالة |
|---------|--------|
| TT-Core Core Stack | ✅ يجب أن يعمل أولاً |
| n8n (healthy) | ✅ OpenClaw يعتمد عليه |
| git | ✅ لاستنساخ كود OpenClaw |
| Telegram Bot Token | اختياري (من @BotFather) |
| Ollama + نموذج | اختياري — أو استخدم Gemini Cloud |

---

## الإعداد الكامل

### الخطوة 0: اختر النموذج

**الخيار A — Ollama محلي (مُوصى به):**
```powershell
# تأكد أن Ollama شغّال
.\scripts\Start-Service.ps1 -Service ollama

# حمّل النموذج المطلوب
docker exec -it tt-core-ollama ollama pull llama3.2

# في .env: TT_OPENCLAW_MODEL=ollama/llama3.2
```

**الخيار B — Google Gemini (cloud):**
```ini
# في runtime core.env:
TT_OPENCLAW_MODEL=google/gemini-2.5-flash
TT_OPENCLAW_GEMINI_KEY=<مفتاحك من https://aistudio.google.com/>
```

---

### الخطوة 1: تشغيل سكربت الإعداد الكامل

```powershell
# يتولى كل شيء: clone المصدر → بناء الصورة → تشغيل الـ wizard
.\scripts\Init-OpenClaw.ps1
```

الـ wizard سيطلب منك:
1. **Gateway** → اختر: `Local`
2. **Model** → حسب اختيارك في الخطوة 0
3. **Channel** → اختر: `Telegram` → الصق Bot Token
4. **Permissions** → أدخل @username الخاص بك

---

### الخطوة 2: إصلاح `openclaw.json` (ضروري)

بعد انتهاء الـ wizard، يجب تعديل الملف يدوياً:

```
compose\tt-core\volumes\openclaw\data\openclaw.json
```

**التعديلات المطلوبة:**

```json
{
  "gateway": {
    "bind": "lan",           ← غيّر من "loopback" إلى "lan"
    "auth": {
      "token": "<قيمة TT_OPENCLAW_TOKEN من .env>"
    },
    "controlUi": {
      "allowInsecureAuth": true
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "ollama/llama3.2"   ← تأكد من البادئة ollama/ أو google/
      }
    }
  },
  "channels": {
    "telegram": {
      "botToken": "<Bot Token من @BotFather>"
    }
  }
}
```

> القالب المرجعي: `compose\tt-core\volumes\openclaw\config\openclaw_template.json`

---

### الخطوة 3: الانتقال لوضع الإنتاج

```ini
# في runtime core.env:
TT_OPENCLAW_MODE=production
```

ثم أعد تشغيل الخدمة:
```powershell
.\scripts\Stop-Service.ps1 -Service openclaw
.\scripts\Start-Service.ps1 -Service openclaw
```

---

### الخطوة 4: ربط Telegram

1. افتح Telegram وأرسل `/start` لبوتك
2. البوت سيردّ برقم (Auth ID)
3. أضف الصلاحية:

```powershell
.\scripts\Approve-Telegram.ps1 -AuthId 123456789
```

الآن يمكنك التحدث مع الـ AI عبر Telegram!

---

## الوصول للـ Dashboard (Canvas)

```
1. اقرأ TT_OPENCLAW_TOKEN من .env
2. افتح: http://127.0.0.1:18789/#token=<قيمة_التوكن>
```

Dashboard يعرض:
- **Canvas:** تفكير الـ AI خطوة بخطوة (أداة لا تقدّر بثمن للـ debug)
- **Chat:** محادثة مباشرة مع الـ AI من المتصفح
- **Memory:** ما يتذكره الـ AI من المحادثات السابقة

---

## تعليم الـ AI مهارات n8n

هنا القيمة الحقيقية: كل webhook في n8n = مهارة جديدة للـ AI.

### مثال: حفظ جهات الاتصال

**في n8n:**
1. أنشئ workflow جديد
2. Trigger: Webhook → الـ URL: `http://n8n:5678/webhook/save-contact`
3. أضف منطق الحفظ (في Postgres أو Google Sheets أو غيره)
4. فعّل الـ workflow

**في OpenClaw Dashboard → Chat:**
```
أخبر الـ AI بالمهارة:
"Whenever asked to save a contact, call the webhook
 http://tt-core-n8n:5678/webhook/save-contact
 and extract: name, phone, email from the message."
```

**الآن في Telegram:**
```
أنت: "احفظ جهة الاتصال: أحمد 0501234567 ahmed@example.com"
الـ AI: يستدعي webhook تلقائياً → "تم حفظ جهة الاتصال لـ أحمد ✓"
```

### أمثلة مهارات شائعة

```
# تقرير المبيعات
"When asked for a sales report, call: http://tt-core-n8n:5678/webhook/sales-report"

# استعلام عن طلب
"When asked about an order, call: http://tt-core-n8n:5678/webhook/order-status
 Extract the order ID from the message."

# إرسال إيميل
"When asked to send an email, call: http://tt-core-n8n:5678/webhook/send-email
 Extract: to, subject, body from the message."

# جدولة موعد
"When asked to schedule a meeting, call: http://tt-core-n8n:5678/webhook/schedule
 Extract: date, time, title from the message."
```

---

## تكامل Qdrant (ذاكرة طويلة الأمد)

إذا كان Qdrant مفعّلاً (`-WithQdrant`), يمكن تكوين OpenClaw لحفظ المحادثات فيه:

```
# في n8n: أنشئ workflow لحفظ المحادثات في Qdrant
# Webhook → Extract embedding → Save to Qdrant collection "openclaw-memory"

# ثم علّم الـ AI:
"Before answering questions about past conversations, 
 search memory by calling: http://tt-core-n8n:5678/webhook/search-memory
 with the user's question."
```

هذا يعطي الـ AI ذاكرة **دائمة وقابلة للبحث بالمعنى** — أقوى بكثير من الـ filesystem memory الافتراضية.

---

## إدارة المستخدمين

```powershell
# قبول مستخدم جديد
.\scripts\Approve-Telegram.ps1 -AuthId 123456789

# إلغاء صلاحية مستخدم
.\scripts\Approve-Telegram.ps1 -AuthId 123456789 -Action revoke

# عرض كل المستخدمين المقبولين
.\scripts\Approve-Telegram.ps1 -ListPaired
```

---

## Cloudflare Tunnel

لنشر Dashboard عبر الإنترنت:

```ini
# في runtime tunnel.env:
TUNNEL_ROUTE_OPENCLAW=true
SUB_OPENCLAW=ai                    # سيكون: ai.yourdomain.com
```

> **تحذير أمني:** يُوصى بحماية الـ subdomain بـ Cloudflare Access قبل نشره.

---

## استكشاف الأخطاء

| المشكلة | السبب | الحل |
|---------|-------|------|
| `Control UI assets not found` | الـ UI لم يُبنَ | أعد البناء: `docker compose build --no-cache openclaw` |
| Dashboard لا يفتح | `bind` غلط | غيّر لـ `"bind": "lan"` في `openclaw.json` |
| LLM 404 Error | بادئة النموذج ناقصة | تأكد: `google/gemini-2.5-flash` أو `ollama/llama3.2` |
| Telegram bot لا يستجيب | في وضع Setup | تأكد من `TT_OPENCLAW_MODE=production` في `.env` |
| الـ AI لا يستدعي webhook | لم يُعلَّم المهارة | أخبره في Dashboard Chat بالـ webhook URL |
| Token mismatch | التوكن غير متطابق | تأكد `gateway.auth.token` = `TT_OPENCLAW_TOKEN` |

**عرض سجلات OpenClaw:**
```powershell
.\scripts\Logs-Core.ps1 -Service openclaw
# أو مباشرة:
docker logs tt-core-openclaw -f --tail 100
```

---

## ملاحظات هامة

- **لا تغيّر N8N_ENCRYPTION_KEY** بعد أول تشغيل — ستفقد كل credentials
- **openclaw.json** يحتوي Telegram Bot Token — لا تشاركه
- **openclaw_source/** مستثنى من الـ zip والـ git (حجمه كبير)
- عند تحديث OpenClaw: `git pull` في `openclaw_source/` ثم `docker compose build --no-cache openclaw`
