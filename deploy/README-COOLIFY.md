# نشر ERPNext المخصص على Coolify

> بيئة **تجريبية / Staging** — مبنية من المصدر المحلي `erpnext-develop`.
> **المصدر هو `__version__ = 17.0.0-dev`** أي خط تطوير v17 — لذلك يُبنى مقابل فرع `develop` للإطار، لا `version-16`.

---

## ⚠️ اقرأ هذا أولاً

**لا يمكن لـ Coolify بناء هذه الصورة مباشرة.** السبب معماري:

`images/layered/Containerfile` يقوم بـ `COPY resources/core/main-entrypoint.sh` من سياق البناء (build context)،
أي أن سياق البناء يجب أن يكون مستودع **frappe_docker** — وليس مستودع تطبيقك.
أما كود تطبيقك فلا يُنسخ من السياق أبداً؛ بل يجلبه `bench init` من **Git** عبر `apps.json`.

النتيجة العملية:
1. ارفع `erpnext-develop` إلى مستودع Git (خطوة 1).
2. ابنِ الصورة وادفعها إلى registry من جهازك أو من CI (خطوة 2).
3. في Coolify انشر الـ compose الذي **يسحب** تلك الصورة (خطوة 3).

> Docker غير مثبّت على جهازك حالياً — ستحتاج تثبيته، أو تنفيذ خطوة البناء عبر GitHub Actions.

---

## الخطوة 1 — المصدر على Git ✅ (منجزة)

تم رفع المصدر إلى `github.com/sakAlmahdi/erpnext-neon` على فرع `develop`.

`deploy/apps.json` يشير إليه:

```json
[{ "url": "https://github.com/sakAlmahdi/erpnext-neon", "branch": "develop" }]
```

> المستودع **خاص**، لذا يستخدم workflow البناء token تلقائياً لاستنساخه.

---

## الخطوة 2 — ابنِ الصورة وادفعها

```bash
cd deploy
export IMAGE=ghcr.io/sakalmahdi/erpnext-neon
export TAG=develop
./build-image.sh

docker login ghcr.io           # أو أي registry آخر
docker push $IMAGE:$TAG
```

مدة البناء المتوقعة: **20–40 دقيقة** (تنزيل التبعيات + بناء الأصول).

`build-image.sh` ينفّذ فعلياً:

```bash
docker build --no-cache \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH=develop \
  --secret=id=apps_json,src=apps.json \
  --tag=$IMAGE:$TAG \
  --file=images/layered/Containerfile .
```

> `apps.json` يُمرَّر كـ **secret** لا كـ `--build-arg` — لأن build args تبقى ظاهرة في `docker image history`.

---

## الخطوة 2-بديل — ابنِ عبر GitHub Actions (موصى به هنا)

Docker غير مثبّت على جهازك، لذا الأسهل هو البناء في CI.
الملف `.github/workflows/build-custom-image.yml` جاهز:

1. **Actions** → **Build custom ERPNext image** → **Run workflow**
2. المدخلات (القيم الافتراضية صحيحة):
   - `frappe_branch` = `develop`  ← لأن المصدر v17.0.0-dev
   - `tag` = `develop`
   - `app_branch` = `develop`
3. عند الانتهاء ستجد في **Summary** قيم `CUSTOM_IMAGE` و `CUSTOM_TAG` جاهزة للنسخ.

الصورة تُدفع إلى **GHCR** باسم `ghcr.io/sakalmahdi/erpnext-neon`.

> **المستودع خاص:** الـ workflow يبني `apps.json` بـ token تلقائي
> (`x-access-token`) حتى يستطيع `bench init` استنساخ الكود، ويُمرَّره كـ
> BuildKit secret فلا يُخزَّن في طبقات الصورة.

> **صلاحية الحزمة:** أول دفع يجعل الحزمة خاصة. إن كان سيرفر Coolify
> لا يملك دخولاً إلى GHCR، اجعلها public من
> Package settings → Change visibility، أو أضف `docker login ghcr.io`
> على السيرفر.

---

## الخطوة 3 — انشر على Coolify

1. **Coolify → Project → New Resource → Docker Compose**
2. الصق محتوى `docker-compose.coolify.yaml`
3. في **Environment Variables** الصق `.env.example` بعد تعديل كلمات المرور
4. **لا دومين الآن:** الوصول عبر `http://178.18.249.38:3110`
   - تأكد أن البورت `3110` مفتوح في الجدار الناري
5. **Deploy**

### البورتات والوصول

**البورت الداخلي `8080` غير قابل للتغيير.** قالب nginx داخل صورة frappe
يحتوي `listen 8080;` مكتوباً ثابتاً (لا متغيّر بيئة)، فتغييره يتطلب تعديل
القالب وإعادة بناء الصورة كاملة بلا أي مكسب — البورت داخلي ولا يُرى خارجاً.

الحل: **نشر بورت المضيف** من النطاق `3110-3190`:

| العنصر | القيمة |
|---|---|
| بورت المضيف | `HOST_PORT=3110` (النطاق 3110-3190) |
| بورت الحاوية | `8080` — ثابت في الصورة |
| التعيين | `3110:8080` |
| الوصول | `http://178.18.249.38:3110` |
| backend داخلي | `backend:8000` (gunicorn) |
| websocket داخلي | `websocket:9000` (socket.io) |

### الوصول بدون دومين — نقطة حرجة

nginx يطابق الموقع بترويسة `Host`. عند فتح `http://1.2.3.4:3110` تكون
الترويسة `1.2.3.4:3110`، وهي **لا تطابق** موقعاً اسمه `erp.neon-dev.dev`.
لذلك:

| المتغير | القيمة الآن | عند إضافة الدومين |
|---|---|---|
| `SITE_NAME` | `178.18.249.38` | `erp.neon-dev.dev` |
| `SITE_SCHEME` | `http` | `https` |
| `SITE_HOST` | `178.18.249.38:3110` | `erp.neon-dev.dev` |
| `FRAPPE_SITE_NAME_HEADER` | فارغ → يُثبّت على `SITE_NAME` | نفسه |

> **`SITE_HOST` يجب أن يحوي البورت.** منه يبني Frappe الروابط المطلقة
> (البريد، إعادة تعيين كلمة المرور، OAuth). بدون البورت تشير كل الروابط
> إلى بورت 80 وتفشل.

> **اختر الاسم النهائي مبكراً.** تغيير `SITE_NAME` بعد إنشاء الموقع يتطلب
> `bench rename-site` وليس مجرد تعديل متغيّر.

### الانتقال إلى الدومين لاحقاً

```bash
# 1. سجل A: erp.neon-dev.dev -> IP السيرفر
# 2. في Coolify اربط الدومين بخدمة frontend على بورت 8080
# 3. حدّث المتغيرات: SITE_SCHEME=https و SITE_HOST=erp.neon-dev.dev
# 4. حدّث host_name داخل الموقع:
bench --site 178.18.249.38 set-config host_name https://erp.neon-dev.dev
# 5. إن أردت تغيير اسم الموقع نفسه:
bench --site 178.18.249.38 rename-site erp.neon-dev.dev
```

البورت المنشور يبقى صالحاً بعد إضافة الدومين — proxy الخاص بـ Coolify يتصل
بـ 8080 عبر الشبكة الداخلية، مستقلاً عن تعيين المضيف.

### ترتيب الإقلاع

```
db (healthy) → configurator → create-site → migrate → backend  → frontend
                                                    ├→ websocket
                                                    ├→ queue-short
                                                    ├→ queue-long
                                                    └→ scheduler
```

- **`create-site`** تُنشئ الموقع مرة واحدة، وتخرج `0` إن كان موجوداً
- **`migrate`** تُنفّذ `bench migrate` على كل نشر — ضرورية لأن `MIGRATE_SITES`
  المذكورة في وثائق frappe_docker **غير مُنفَّذة فعلياً** في `start.sh`
- كل الخدمات تنتظر `migrate` حتى لا تدور في crash-loop على موقع غير مهيّأ

---

## إعدادات site_config المطبّقة

تُضبط عبر `configurator` في `common_site_config.json`:

| المفتاح | القيمة | السبب |
|---|---|---|
| `host_name` | `https://erp.neon-dev.dev` | روابط البريد وإعادة تعيين كلمة المرور و OAuth |
| `developer_mode` | `0` | يكتب تعديلات DocType على القرص داخل الحاوية وتضيع عند النشر |
| `server_script_enabled` | `0` | تنفيذ Python من المستخدم = سطح RCE |
| `maintenance_mode` | `0` | الموقع يعمل |
| `pause_scheduler` | `0` | المهام المجدولة تعمل |
| `gunicorn_workers` | `2` | يطابق ضبط الحاوية |

---

## ⚠️ السيرفر مشترك مع SQL Server

`178.18.249.38` يستضيف بالفعل SQL Server (بورت 1433) الذي تستخدمه
`NewMultiFendor_api` و `AppManager_API` وقاعدة `plusCareV2`.

| الأمر | الحالة |
|---|---|
| تعارض بورت 1433 | **لا يوجد** — MariaDB داخل ERPNext لا تنشر أي بورت على المضيف |
| تعارض بورت 3110 | تحقق: `ss -tlnp \| grep 3110` |
| **تنافس على الذاكرة** | **نعم — الحدود مُزالة، والحماية عبر `oom_score_adj`** |

**الذاكرة هي الخطر الحقيقي.** الحدود مُزالة بناءً على طلبك، فالخدمات تأخذ
ما تحتاجه. SQL Server يستهلك عادةً 1-2 جيجا ولا يتنازل عنها. الحماية
المطبّقة هي `oom_score_adj` التي تجعل ERPNext يموت قبل SQL Server عند
نقص الذاكرة — لكنها تقلّل الخطر ولا تلغيه.

**قبل النشر، تحقق من الذاكرة الفعلية المتاحة على السيرفر:**

```bash
free -m                    # المتاح فعلاً
docker stats --no-stream   # ما تستهلكه الحاويات الحالية
```

إن ظهر أن المتاح ضيّق، خفّض `DB_BUFFER_POOL` و `REDIS_CACHE_MAXMEMORY`
و `GUNICORN_WORKERS` — أو خصّص سيرفراً منفصلاً لـ ERPNext.

---

## الموارد — بلا حدود صارمة

أُزيلت حدود الذاكرة عن كل الخدمات: تأخذ ما تحتاجه من المضيف بدل تقييدها.

### المقايضة التي قبلتها

حد Docker **سقف لا حجز**. إزالته لا تعني توزيعاً عادلاً، بل أن لا شيء يمنع
حاوية من استهلاك ذاكرة المضيف. وعندها يتدخل الـ OOM killer، وهو **لا يقتل
المتسبّب بل أكبر عملية** — وقد تكون SQL Server على هذا السيرفر المشترك.

| بلا حدود | مع حدود |
|---|---|
| ERPNext يستفيد من كل ذاكرة متاحة | كل خدمة مقيّدة بسقفها |
| ضغط الذاكرة يهدّد SQL Server | العزل مضمون |
| لا تحتاج معرفة الموارد مقدماً | تحتاج ضبطاً دقيقاً |

### الحمايتان المطبّقتان

**١. أولويات OOM** — تجعل حاويات ERPNext هدفاً أكثر جذباً للـ kernel من
SQL Server، فتموت أولاً:

| الخدمة | `oom_score_adj` | المنطق |
|---|---|---|
| `frontend` | 800 | nginx — يُعاد تشغيله بلا أثر |
| `websocket` / الطوابير / `scheduler` | 700 | تُستأنف تلقائياً |
| `redis-cache` | 600 | الكاش قابل للإسقاط |
| `backend` | 500 | فقده يعني توقف الخدمة |
| `redis-queue` | 300 | يحمل مهاماً غير منفَّذة |
| `db` | 200 | آخر ما يُقتل — فقده = فقد بيانات |
| **SQL Server (خارج Docker)** | **0** | لا يُقتل إلا أخيراً |

**٢. تحديد ما لا يتقلّص** — تخصيصان لا يُعادان للنظام أبداً:

```bash
DB_BUFFER_POOL=1G           # يُخصّص مقدماً ولا يُعاد
REDIS_CACHE_MAXMEMORY=512mb # بدونه ينمو حتى يموت شيء
```

> **`DB_BUFFER_POOL` أول ما تُخفّضه** إن بدأ السيرفر يستخدم swap.

### المراقبة

بلا حدود تصبح المراقبة ضرورية لا رفاهية:

```bash
free -m                                    # الذاكرة المتاحة
docker stats --no-stream                   # استهلاك الحاويات
dmesg -T | grep -i "killed process"        # هل قتل الـ kernel شيئاً؟
systemctl status mssql-server              # هل SQL Server حي؟
```

**إن ظهر `killed process` في `dmesg`** فالسيرفر لا يتحمّل الحمل: خفّض
`DB_BUFFER_POOL` و `GUNICORN_WORKERS`، أو أعد حدود الذاكرة، أو افصل ERPNext
على سيرفر آخر.

**Gunicorn:** 2 workers × 4 threads على نواتين. المعادلة `(2 × cores) + 1`
تعطي 5 وهي تُجيع الـ workers و MariaDB.

---

## نقاط حرجة

| الموضوع | التفصيل |
|---|---|
| **`SITE_NAME` = طريقة الوصول** | بلا دومين: يجب أن يساوي IP السيرفر. أي اختلاف عن ترويسة `Host` ينتج `Site does not exist`. |
| **`SITE_HOST` يحوي البورت** | `<IP>:3110` — بدون البورت تشير روابط البريد إلى 80 وتفشل. |
| **بورت 8080 غير قابل للتغيير** | `listen 8080;` ثابت في قالب nginx داخل الصورة؛ نُشر بورت المضيف 3110 بدلاً منه. |
| **`CUSTOM_IMAGE` إجباري** | لا fallback في الـ compose: لو نسيته يفشل النشر بوضوح بدل نشر ERPNext القياسي بصمت. |
| **`DB_PASSWORD` لا يتغيّر بعد أول نشر** | حجم `db-data` يحفظ كلمة المرور الأصلية؛ تغييرها لاحقاً يمنع الإقلاع. |
| **`ADMIN_PASSWORD` يُقرأ مرة واحدة** | يُستخدم عند إنشاء الموقع فقط؛ غيّره قبل أول نشر. |
| **الحجوم (Volumes)** | `sites` مشترك (لا تحذفه)، `db-data` قاعدة البيانات، `redis-queue-data` المهام. |
| **`MIGRATE_SITES` وهمية** | موثّقة في frappe_docker لكن `start.sh` لا يقرأها — لذلك أضفنا خدمة `migrate`. |
| **v17-dev غير مستقر** | `__version__ = 17.0.0-dev`، غير مُصدَر؛ upstream يتعطل دورياً. staging فقط. |
| **Python 3.14** | `docker-bake.hcl` يضبط 3.14 و Node 24 — متوافق مع `requires-python`. |
| **إعادة البناء يدوية** | Coolify لا يبني الصورة؛ شغّل workflow البناء ثم Redeploy. |
| **لا نسخ احتياطي** | لم نضف backups (staging). للإنتاج: `bench backup` مجدول + تخزين خارجي. |
| **workflows فاشلة** | `crowdin-actions-update-main-pot` تفشل على fork لأن أسرار Crowdin غير موجودة — عطّلها من تبويب Actions. |

---

## أوامر تشخيص

```bash
# داخل حاوية backend
bench --site $SITE_NAME doctor
bench --site $SITE_NAME list-apps
bench --site $SITE_NAME migrate     # بعد تحديث الصورة

# سجلات
docker compose logs -f create-site   # فشل إنشاء الموقع
docker compose logs -f backend
```

### أخطاء شائعة

- **`Site does not exist`** → `SITE_NAME` لا يطابق ما تفتحه في المتصفح (IP أو دومين)، أو `create-site` فشلت. راجع سجلها.
- **البورت 3110 لا يستجيب** → الجدار الناري يحجبه، أو خدمة أخرى تستخدمه (`ss -tlnp | grep 3110`).
- **روابط البريد مكسورة** → `SITE_HOST` بلا بورت؛ يجب `<IP>:3110`.
- **`Access denied for user root`** → `DB_PASSWORD` تغيّر بعد تهيئة `db-data`. الحجم يحتفظ بالقديمة.
- **الأصول (CSS/JS) لا تُحمّل** → الحجم `sites` قديم من صورة سابقة؛ أعد إنشاءه.
- **`create-site` تُعيد المحاولة بلا نهاية** → `restart: "no"` مضبوط؛ إن حدث فراجع السجل لسبب الفشل الحقيقي.
