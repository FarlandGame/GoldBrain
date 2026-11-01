# GoldBrain

اپلیکیشن دسکتاپ Flutter برای نمایش بازارهای مالی، خبرهای اقتصادی و دستیار هوشمند چندزبانه.

## اجرای پروژه روی Windows

بعد از نصب Flutter و Visual Studio با ابزار Desktop development with C++:

```powershell
cd G:\GoldBrainFlutter
flutter pub get
flutter run -d windows
```

## تنظیم دائمی OpenRouter

نام متغیرهای قدیمی `GAPGPT_*` برای سازگاری کد حفظ شده است، اما می‌توان آن‌ها را برای endpoint سازگار OpenRouter تنظیم کرد. کلید را داخل فایل Dart، فایل قابل commit یا `--dart-define` قرار ندهید.

```powershell
[Environment]::SetEnvironmentVariable('GAPGPT_API_KEY', 'YOUR_OPENROUTER_KEY', 'User')
[Environment]::SetEnvironmentVariable('GAPGPT_BASE_URL', 'https://openrouter.ai/api/v1', 'User')
[Environment]::SetEnvironmentVariable('GAPGPT_MODEL', 'openrouter/free', 'User')
```

پس از ثبت یا تعویض کلید، تمام پنجره‌های VS Code و Terminal را یک‌بار ببندید و دوباره باز کنید. از آن پس فقط این فرمان لازم است:

```powershell
flutter run -d windows
```

برای بررسی ثبت‌شدن کلید بدون نمایش مقدار آن:

```powershell
if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('GAPGPT_API_KEY', 'User'))) { 'AI key is missing' } else { 'AI key is configured' }
```

پاسخ گفت‌وگو با SSE به‌صورت Streaming نمایش داده می‌شود. خطاهای رسمی OpenRouter، قطع ارتباط، rate limit و مدل ناموجود به خطای کنترل‌شده تبدیل می‌شوند. مدل رایگان سهمیهٔ محدودی دارد؛ بنابراین تحلیل خودکار بازار حداقل هر ۶۰ دقیقه اجرا می‌شود و اگر شواهد بازار تغییر نکرده باشند درخواست تکراری نمی‌فرستد. دکمهٔ تحلیل دستی همچنان درخواست فوری می‌فرستد.

اگر شبکه یک HTTP proxy محلی در اختیار برنامه‌ها می‌گذارد، می‌توان آدرس آن را قبل از اجرای برنامه در `GAPGPT_PROXY_URL` تنظیم کرد. تنظیم proxy تضمینی برای عبور از محدودیت منطقه‌ای یا حساب سرویس نیست.

در نسخهٔ Production نباید کلید مالک برنامه همراه فایل اجرایی Flutter توزیع شود؛ کلید باید در backend دارای احراز هویت، cache و rate limit نگهداری شود.

## نمودار دلار و طلای ۱۸ عیار

کلید Navasan را برای کاربر Windows ذخیره کنید:

```powershell
[Environment]::SetEnvironmentVariable('NAVASAN_API_KEY', 'YOUR_NAVASAN_KEY', 'User')
```

پس از آن VS Code و Terminal را یک‌بار کامل باز و بسته کنید.

- `USD` از نماد `usd_sell` و `GOLD18` از نماد `18ayar` استفاده می‌کند.
- تاریخچهٔ ۷روزه با یک درخواست OHLC واقعی Navasan دریافت می‌شود.
- اگر Navasan برای طلای ۱۸ عیار ردیف تاریخی ندهد، بازهٔ ۷روزه از تاریخچهٔ عمومی و واقعی TGJU با نام منبع واضح استفاده می‌کند.
- بازه‌های ۱ و ۲۴ ساعت فقط دادهٔ واقعی Navasan یا نمونه‌های واقعی هم‌منبع ذخیره‌شده روی دستگاه را نمایش می‌دهند؛ نقطهٔ گمشده ساخته نمی‌شود.
- cache داخلی بازار ایران دو ساعت است و حتی Refresh اجباری سهمیهٔ پلن رایگان را بی‌دلیل مصرف نمی‌کند.
- برای Production، کلید Navasan نیز باید پشت backend امن قرار بگیرد.

## قیمت‌ها و تبدیل واحد پول

قیمت‌های جاری USD/تومان، طلای ۱۸ عیار، XAU، XAG، BTC و ETH از سرویس‌های واقعی دریافت می‌شوند. شکست یک نماد باعث حذف پاسخ سالم بقیهٔ نمادها نمی‌شود. واحد پول انتخابی بلافاصله ذخیره و در Dashboard، Markets و Watchlist اعمال می‌شود؛ حالت «خودکار» واحد متناسب با زبان انتخابی را برمی‌گزیند.

## خبرها

خبرها از RSS ناشران ایرانی تسنیم و مهر دریافت می‌شوند و هر پنج دقیقه، تا زمانی که صفحه‌ای به خبرها نیاز دارد، تازه‌سازی می‌شوند. عنوان، زمان، لینک و متن ناشر حفظ می‌شود. ترجمه و خلاصهٔ هوش مصنوعی تنها در زبان انتخابی نمایش داده می‌شود؛ هنگام شکست ترجمه، محتوای زبان دیگری به‌عنوان ترجمه جا زده نمی‌شود.

## ورود واقعی و حالت مهمان

ورود و ثبت‌نام ایمیل/رمز برای استفاده از Supabase Auth آماده شده، اما تا زمان تنظیم این دو متغیر فعال نیست:

```powershell
[Environment]::SetEnvironmentVariable('SUPABASE_URL', 'https://YOUR_PROJECT.supabase.co', 'User')
[Environment]::SetEnvironmentVariable('SUPABASE_PUBLISHABLE_KEY', 'YOUR_PUBLIC_PUBLISHABLE_KEY', 'User')
```

فقط Publishable Key عمومی مجاز است؛ Secret یا Service Role را داخل کلاینت قرار ندهید. بدون این تنظیمات، برنامه فقط با دکمهٔ حالت مهمان و داده‌های محلی آزمایش می‌شود و حساب مهمان «تأییدشده» نمایش داده نمی‌شود.

## موسیقی در Windows

پخش Windows بدون `audioplayers_windows` انجام می‌شود تا خطای Platform Channel آن افزونه رخ ندهد. WAV و افکت‌ها با WinMM/MCI و موسیقی فشرده با MediaPlayer یک process مخفی و قابل cleanup پخش می‌شوند. Playlist داخلی و فایل‌های انتخابی کاربر از حالت ترتیبی، تصادفی، تکرار، قبلی و بعدی پشتیبانی می‌کنند.

## کنترل کیفیت

```powershell
flutter analyze
flutter test
flutter build windows --release
```

تست‌های Live و Native عمداً در اجرای عادی Skip می‌شوند و فقط با فلگ‌های صریح خودشان شبکه یا backend صوتی واقعی را مصرف می‌کنند.
