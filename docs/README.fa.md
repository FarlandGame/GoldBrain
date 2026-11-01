# GoldBrain 🧠✨

**هفت ماه بلندپروازی، یادگیری و یک محیط ناتمام برای تحلیل هوشمند بازارهای مالی.**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain پروژه‌ای آزمایشی از دو برادر دوقلو، بردیا و ارمیا علیزاده (کبیر)، است که توسعه‌اش متوقف شده. این پروژه رابطی مبتنی بر Flutter با تمرکز بر زبان فارسی را با Backend پایتون و FastAPI ترکیب می‌کند. کد منبع حفظ شده تا توسعه‌دهنده‌ای دیگر بتواند کارهای انجام‌شده را بشناسد، وضعیت فعلی را بازتولید کند و دربارهٔ ادامه‌دادنش تصمیم بگیرد.

هم‌سازندگان: **Bardiya Alizadeh (Kabir) · Farland_game** و **Armiya Alizadeh (Kabir) · ArmiyaFbix**؛ در آخرین صفحهٔ دربارهٔ برنامه و یادداشت‌های توسعه، مشارکت هر دو برابر ذکر شده است.

بردیا از حدود هفت ماه کار می‌گوید؛ مسیری که با تجربهٔ کم در برنامه‌نویسی آغاز شد و با آزمون‌وخطا، منابع اینترنتی و کمک هوش مصنوعی ادامه پیدا کرد. هدف اولیه، ساخت محصولی برای ویندوز و اندروید با پیش‌بینی بازار در افق‌های کوتاه و بلند بود و پس از آن، معاملهٔ خودکار در Wallex فقط با بخشی از دارایی که خود کاربر انتخاب می‌کند. او به‌دلیل نیازهای زیرساختی، هزینه‌ها، پیچیدگی و ریسک مالی، دنبال‌کردن این چشم‌انداز کامل را کنار گذاشت. این‌ها هدف‌های پروژه بودند، نه قابلیت‌های تکمیل‌شده یا اعتبارسنجی‌شده.

> مغز، نقشه‌های بزرگی داشت. صورتحساب زیرساخت هم برای خودش نقشه‌هایی داشت! 🧠🧾😅

## کد منبع حفظ‌شده چه چیزهایی دارد؟

- رابط اختصاصی Flutter با ۱۱ تم، ۸ زبان موجود برای رابط کاربری، انیمیشن، نمودار، تنظیمات، فهرست‌های پیگیری، کنترل‌های صدا و صفحهٔ دربارهٔ برنامه.
- Backend مبتنی بر FastAPI با قیمت‌ها و تاریخچهٔ استانداردشدهٔ بازار، اطلاعات منشأ تأمین‌کننده، بررسی تازگی و کیفیت داده، داده‌های ذخیره‌شدهٔ نمای کلی و پردازشگر جمع‌آوری داده.
- موتور پژوهشی پیش‌بینی با ویژگی‌های داده، ارزیابی و بک‌تست به‌ترتیب زمانی و سوابق شواهد؛ این موتور با پیش‌بین نهایی ناتمام پروژه تفاوت دارد.
- APIهای معاملات شبیه‌سازی‌شده یا Paper Trading؛ رابط قابل‌مشاهدهٔ سبد دارایی و معاملات با پول واقعی کامل نشده‌اند.
- فرایندهای تأیید ایمیل و بازیابی رمز عبور، رمزهای عبور هش‌شده با Argon2، توکن‌های دسترسی JWT، چرخش توکن تازه‌سازی و کنترل دستگاه‌ها و نشست‌ها.
- اخبار RSS، ترجمه و خلاصه‌سازی اختیاری مقاله‌ها با هوش مصنوعی، دستیار گفت‌وگوی محدود با دسترسی فقط‌خواندنی و نمای نبض بازار شش کشور.
- کد آزمون‌های Backend و Flutter، ده مهاجرت پایگاه داده، نمونه‌های پیکربندی، مستندات معماری و API و سوابق تاریخی پیشرفت و تصمیم‌ها.

## کار در کجا متوقف شد؟

- سامانهٔ برنامه‌ریزی‌شدهٔ پیش‌بینی زنده و بازخورد خودکار در فاز ۶ ناتمام است. ابزار مربوط به آن در دستیار، به‌جای ساختن پیش‌بینی، صریحاً در دسترس نبودن آن را اعلام می‌کند.
- معاملهٔ خودکار با پول واقعی در Wallex و فرایند پیشنهادی تخصیص بودجهٔ کاربر پیاده‌سازی نشده‌اند. آداپتور صرافی فقط یک قرارداد آزمایشی Mock است.
- قراردادهای دادهٔ مناسب استفادهٔ عملیاتی، اعتبارسنجی مستقل عملکرد مالی، مقاوم‌سازی برای استقرار عمومی و دسترسی مطمئن به تأمین‌کنندگان هنوز به کار نیاز دارند.
- پردازش پرداخت، رابط کامل سبد دارایی و برخی تنظیمات قابل‌مشاهده ناتمام‌اند. داشتن مدل اشتراک و سطح دسترسی به معنای تکمیل سامانهٔ خرید و پرداخت نیست.
- کد یکپارچهٔ فعلی ساختارهای اولیهٔ ویندوز و وب را دارد؛ ساختار قدیمی اندروید جداگانه حفظ شده است. کارکرد نسخهٔ فعلی اندروید یا وب تأیید نشده است.

## پروژه را ادامه بدهید

از راهنمای ادامهٔ توسعه، راه‌اندازی پس از دریافت یک نسخهٔ تازه از مخزن، جدول وضعیت فعلی و گزارش بررسی شروع کنید. مستندات تاریخی همراه تاریخشان حفظ شده‌اند؛ عنوان فازها، قیمت سرویس‌ها و تعداد آزمون‌های قدیمی آن‌ها بر کد فعلی اولویت ندارند. سرویس‌ها را با پیکربندی خودتان و یک پایگاه دادهٔ تازه راه‌اندازی کنید. پایگاه دادهٔ حساب‌های خصوصی، اطلاعات دسترسی API یا هویت امضای اندروید ارائه نمی‌شود.

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## هویت بصری و مطالب تاریخی

پوستر و نشان‌های ارائه‌شدهٔ پروژه در مجموعه قرار دارند. فایل‌های صوتی در بستهٔ دارایی جداگانه و بر پایهٔ گفتهٔ سازنده مبنی بر مجازبودن بازتوزیع ارائه می‌شوند؛ مجوز کد خودبه‌خود شامل آن‌ها نمی‌شود. نسخه‌های قدیمی کد، مرجع تاریخی‌اند و اجزای قابل‌جایگزینی در برنامهٔ فعلی نیستند.

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="پوستر تبلیغاتی تاریخی؛ بیانگر چشم‌انداز اولیهٔ پروژه است، نه یک نسخهٔ فعلیِ تأییدشده."></a></p>

*پوستر تبلیغاتی تاریخی؛ بیانگر چشم‌انداز اولیهٔ پروژه است، نه یک نسخهٔ فعلیِ تأییدشده.*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## راهنمای فنی برای ادامهٔ کار

راهنماهای فنی مفصل به انگلیسی هستند و در کنار مستندات اصلی انگلیسی و فارسی پروژه حفظ شده‌اند. این معرفی‌های رزومه به همان ۱۸ زبان مستندات دیگر بخش‌های رزومه ارائه می‌شوند؛ ۸ زبان موجود رابط کاربری برنامه، ویژگی جداگانه‌ای است.

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

پیش از استفادهٔ دوباره از کد یا رسانه‌ها، سابقهٔ انتشار و مجوز مخزن و اطلاعیه‌های جداگانهٔ دارایی‌های شخص ثالث را بخوانید.

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
