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

## الخطوة 1 — ارفع المصدر إلى Git

```bash
cd /Users/engsakher/cliProjects/neon_platfrom_v2/erpnext-develop
git init
git add -A
git commit -m "chore: import ERPNext develop source"
git branch -M develop
git remote add origin https://github.com/sakAlmahdi/erpnext-neon.git
git push -u origin develop
```

> أوامر Git معروضة للتنفيذ **بواسطتك** — لم يتم تنفيذ أي منها.
> المستودع يمكن أن يكون **خاصاً**؛ في هذه الحالة استخدم رابطاً يحتوي token في `apps.json`
> (يبقى آمناً لأنه يُمرَّر كـ BuildKit secret ولا يُخزَّن في طبقات الصورة).

`deploy/apps.json` مضبوط مسبقاً على مستودعك:

```json
[{ "url": "https://github.com/sakAlmahdi/erpnext-neon", "branch": "develop" }]
```

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
3. في **Environment Variables** أضف متغيرات `.env.example` بعد تعديلها:
   - `CUSTOM_IMAGE` / `CUSTOM_TAG` → الصورة التي دفعتها
   - `SITE_NAME` → **يجب أن يطابق الدومين** الذي ستربطه
   - `ADMIN_PASSWORD` و `DB_PASSWORD` → كلمات مرور قوية
4. **Domains:** اربط الدومين بخدمة `frontend` على البورت **8080**
5. **Deploy**

### ترتيب الإقلاع

```
db (healthy) → configurator → create-site → backend → frontend
                                              ├→ websocket
                                              ├→ queue-short / queue-long
                                              └→ scheduler
```

`create-site` مهمة تُنفَّذ مرة واحدة: تتحقق من وجود الموقع، تنشئه إن لم يوجد، ثم تخرج.
عند إعادة النشر تخرج بـ `exit 0` فوراً دون لمس بياناتك.

---

## نقاط حرجة

| الموضوع | التفصيل |
|---|---|
| **`SITE_NAME` = الدومين** | nginx يستدل على الموقع من ترويسة `Host`. إن اختلفا ستحصل على `Site does not exist`. |
| **الحجوم (Volumes)** | `sites` مشترك بين backend/frontend/workers — لا تحذفه. `db-data` يحمل قاعدة البيانات. |
| **`develop` غير مستقر** | المصدر v17.0.0-dev (غير مُصدَر إطلاقاً)؛ upstream يتعطل دورياً والـ migrations غير مضمونة. staging فقط. |
| **Python 3.14** | تم التحقق: `docker-bake.hcl` يضبط Python 3.14 و Node 24 — متوافق مع `requires-python = ">=3.14"`. |
| **وسم الصورة `develop`** | `frappe/base:develop` و `frappe/build:develop` موجودان على Docker Hub (آخر تحديث 2026-08-31). |
| **`CUSTOM_IMAGE` إجباري** | لا يوجد fallback في الـ compose — لو نسيته يفشل النشر بوضوح بدل نشر ERPNext القياسي بصمت. |
| **إعادة البناء** | Coolify لن يعيد البناء عند `git push`؛ أعد تنفيذ خطوة 2 ثم Redeploy. |
| **لا نسخ احتياطي** | لم أضف backups (بيئة تجريبية). للإنتاج أضف `bench backup` مجدولاً + تخزين خارجي. |

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

- **`Site does not exist`** → `SITE_NAME` لا يطابق الدومين، أو `create-site` فشلت. راجع سجلها.
- **`Access denied for user root`** → `DB_PASSWORD` تغيّر بعد تهيئة `db-data`. الحجم يحتفظ بالقديمة.
- **الأصول (CSS/JS) لا تُحمّل** → الحجم `sites` قديم من صورة سابقة؛ أعد إنشاءه.
- **`create-site` تُعيد المحاولة بلا نهاية** → `restart: "no"` مضبوط؛ إن حدث فراجع السجل لسبب الفشل الحقيقي.
