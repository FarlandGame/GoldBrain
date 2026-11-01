/// Small built-in translations used by screens that still own their strings.
///
/// The app currently does not use generated ARB localization files. Keeping
/// the Simplified Chinese fallback here avoids silently presenting the entire
/// settings experience in English while the localization migration is done.
abstract final class AppTranslations {
  static Iterable<String> get coreEnglishKeys => _simplifiedChinese.keys;

  static bool hasTranslation(String english, String languageCode) =>
      switch (languageCode) {
        'chinese' => _simplifiedChinese.containsKey(english),
        'arabic' => _arabic.containsKey(english),
        'turkish' => _turkish.containsKey(english),
        'french' => _french.containsKey(english),
        _ => false,
      };

  static String simplifiedChinese(String english) {
    return _simplifiedChinese[english] ?? english;
  }

  static String arabic(String english) =>
      _arabic[english] ?? _dynamicTranslation(english, 'arabic');

  static String turkish(String english) =>
      _turkish[english] ?? _dynamicTranslation(english, 'turkish');

  static String french(String english) =>
      _french[english] ?? _dynamicTranslation(english, 'french');

  static String translate(String english, String languageCode) =>
      forLanguageCode(languageCode, english);

  static String forLanguageCode(String languageCode, String english) {
    return switch (languageCode) {
      'chinese' => simplifiedChinese(english),
      'arabic' => arabic(english),
      'turkish' => turkish(english),
      'french' => french(english),
      _ => english,
    };
  }

  static String _dynamicTranslation(String value, String languageCode) {
    final replacements = switch (languageCode) {
      'arabic' => const <String, String>{
        ' unread': ' غير مقروء',
        ' days ago': ' يوم مضى',
        ' hours ago': ' ساعة مضت',
        ' min ago': ' دقيقة مضت',
        ' attributed Iranian RSS feeds': ' خلاصات RSS إيرانية موثقة',
        'AI request failed: ': 'فشل طلب الذكاء الاصطناعي: ',
        'Authentication failed: ': 'فشلت المصادقة: ',
        ' prices were updated.': ' من الأسعار تم تحديثها.',
        'Retry price refresh. ': 'أعد محاولة تحديث السعر. ',
        'Source: ': 'المصدر: ',
        'Updated: ': 'آخر تحديث: ',
        'Hover for exact values': 'مرر المؤشر للقيم الدقيقة',
        'Click to enlarge': 'انقر للتكبير',
        'verified device samples': 'عينات جهاز موثقة',
        'no interpolation': 'دون استيفاء',
        'a real futures proxy, not the XAU/XAG spot quote.':
            'بديل حقيقي للعقود الآجلة وليس سعر XAU/XAG الفوري.',
        'the latest network refresh failed.': 'فشل آخر تحديث للشبكة.',
        'was added to your watchlist.': 'تمت إضافته إلى قائمة المتابعة.',
        'was removed from your watchlist.': 'تمت إزالته من قائمة المتابعة.',
        'This is a sourced reference quote, not an AI prediction or investment signal.':
            'هذا سعر مرجعي موثق وليس توقع ذكاء اصطناعي أو إشارة استثمار.',
      },
      'turkish' => const <String, String>{
        ' unread': ' okunmamış',
        ' days ago': ' gün önce',
        ' hours ago': ' saat önce',
        ' min ago': ' dk önce',
        ' attributed Iranian RSS feeds': ' kaynaklı İran RSS akışı',
        'AI request failed: ': 'AI isteği başarısız: ',
        'Authentication failed: ': 'Kimlik doğrulama başarısız: ',
        ' prices were updated.': ' fiyat güncellendi.',
        'Retry price refresh. ': 'Fiyat yenilemeyi tekrar dene. ',
        'Source: ': 'Kaynak: ',
        'Updated: ': 'Güncellendi: ',
        'Hover for exact values': 'Kesin değerler için üzerine gelin',
        'Click to enlarge': 'Büyütmek için tıklayın',
        'verified device samples': 'doğrulanmış cihaz örneği',
        'no interpolation': 'enterpolasyon yok',
        'a real futures proxy, not the XAU/XAG spot quote.':
            'gerçek vadeli işlem göstergesi; XAU/XAG spot fiyatı değildir.',
        'the latest network refresh failed.': 'son ağ yenilemesi başarısız.',
        'was added to your watchlist.': 'izleme listenize eklendi.',
        'was removed from your watchlist.': 'izleme listenizden kaldırıldı.',
        'This is a sourced reference quote, not an AI prediction or investment signal.':
            'Bu kaynaklı referans fiyattır; AI tahmini veya yatırım sinyali değildir.',
      },
      _ => const <String, String>{
        ' unread': ' non lu(s)',
        ' days ago': ' jours auparavant',
        ' hours ago': ' heures auparavant',
        ' min ago': ' min auparavant',
        ' attributed Iranian RSS feeds': ' flux RSS iraniens attribués',
        'AI request failed: ': 'Échec de la requête IA : ',
        'Authentication failed: ': 'Échec de l’authentification : ',
        ' prices were updated.': ' prix ont été actualisés.',
        'Retry price refresh. ': 'Réessayer l’actualisation. ',
        'Source: ': 'Source : ',
        'Updated: ': 'Mise à jour : ',
        'Hover for exact values': 'Survolez pour les valeurs exactes',
        'Click to enlarge': 'Cliquez pour agrandir',
        'verified device samples': 'échantillons vérifiés sur l’appareil',
        'no interpolation': 'sans interpolation',
        'a real futures proxy, not the XAU/XAG spot quote.':
            'un proxy réel des contrats à terme, pas le cours spot XAU/XAG.',
        'the latest network refresh failed.':
            'la dernière actualisation réseau a échoué.',
        'was added to your watchlist.': 'a été ajouté à votre liste de suivi.',
        'was removed from your watchlist.':
            'a été retiré de votre liste de suivi.',
        'This is a sourced reference quote, not an AI prediction or investment signal.':
            'Il s’agit d’un cours de référence sourcé, pas d’une prévision IA ni d’un signal financier.',
      },
    };
    var translated = value;
    for (final entry in replacements.entries) {
      translated = translated.replaceAll(entry.key, entry.value);
    }
    return translated;
  }

  static const Map<String, String> _arabic = {
    'Choose your GoldBrain experience': 'اختر تجربة GoldBrain الخاصة بك',
    'You can change these settings later': 'يمكنك تغيير هذه الإعدادات لاحقًا',
    'COLOR THEME': 'سمة الألوان',
    'APPLICATION LANGUAGE': 'لغة التطبيق',
    'ENTER GOLDBRAIN': 'الدخول إلى GOLDBRAIN',
    'Portfolio': 'المحفظة',
    'About Us': 'من نحن',
    'GoldBrain User': 'مستخدم GoldBrain',
    'Neural account': 'الحساب الذكي',
    'Neural Account': 'الحساب الذكي',
    'Neural market intelligence system': 'نظام ذكاء السوق العصبي',
    'SYSTEM ONLINE': 'النظام متصل',
    'Gold 18K': 'ذهب عيار 18',
    'Global Gold Ounce': 'أونصة الذهب العالمية',
    'Global Ounce': 'الأونصة العالمية',
    'Bitcoin': 'بيتكوين',
    'Ethereum': 'إيثريوم',
    'Silver': 'الفضة',
    'Neural Market Pulse': 'نبض السوق العصبي',
    'Markets Command Center': 'مركز قيادة الأسواق',
    'Search, compare and inspect tracked assets.':
        'ابحث وقارن وافحص الأصول المتابعة.',
    'PRICE COVERAGE': 'تغطية الأسعار',
    'Search symbol or asset...': 'ابحث عن رمز أو أصل...',
    'Gainers': 'الرابحة',
    'Losers': 'الخاسرة',
    'Saved': 'المحفوظة',
    'No matching assets': 'لا توجد أصول مطابقة',
    'REAL PRICE HISTORY': 'سجل الأسعار الحقيقي',
    'Open large chart': 'فتح الرسم الكبير',
    'Historical data is temporarily unavailable':
        'البيانات التاريخية غير متاحة مؤقتًا',
    'Waiting for verified local price samples':
        'بانتظار عينات أسعار محلية موثقة',
    'UNAVAILABLE': 'غير متاح',
    'PROVIDER': 'المزوّد',
    'UPDATED': 'آخر تحديث',
    '24H CHANGE': 'تغير 24 ساعة',
    'Not provided': 'غير متوفر',
    'No internet connection. GoldBrain needs internet for live prices, news and AI.':
        'لا يوجد اتصال بالإنترنت. يحتاج GoldBrain إلى الإنترنت للأسعار المباشرة والأخبار والذكاء الاصطناعي.',
    'Smart Watchlist': 'قائمة متابعة ذكية',
    'Added to Watchlist': 'أُضيف إلى قائمة المتابعة',
    'Removed from Watchlist': 'أُزيل من قائمة المتابعة',
    'FAVORITES': 'المفضلة',
    'LIVE QUOTES': 'أسعار مباشرة',
    'NO DATA': 'لا توجد بيانات',
    'Positive movement': 'حركة إيجابية',
    'Sourced live quotes': 'أسعار مباشرة موثقة المصدر',
    'Not connected': 'غير متصل',
    'GoldBrain Analysis Pipeline': 'مسار تحليل GoldBrain',
    'Application Settings': 'إعدادات التطبيق',
    'Control appearance, alerts, sound, privacy and GoldBrain AI.':
        'تحكّم في المظهر والتنبيهات والصوت والخصوصية وذكاء GoldBrain.',
    'Appearance': 'المظهر',
    'Layout and display density': 'التخطيط وكثافة العرض',
    'Color theme': 'سمة الألوان',
    'Choose one of the four GoldBrain color systems.':
        'اختر نظام ألوان GoldBrain.',
    'Choose one of the six GoldBrain color systems.':
        'اختر نظام ألوان GoldBrain.',
    'Choose one of the eleven GoldBrain color systems.':
        'اختر واحدًا من أحد عشر نظام ألوان لـ GoldBrain.',
    'Application language': 'لغة التطبيق',
    'Change the language without returning to the welcome screen.':
        'غيّر اللغة دون الرجوع إلى شاشة الترحيب.',
    'Interface density': 'كثافة الواجهة',
    'Choose spacing between interface elements.':
        'اختر التباعد بين عناصر الواجهة.',
    'Compact': 'مضغوط',
    'Comfortable': 'مريح',
    'Spacious': 'واسع',
    'Notifications & alerts': 'الإشعارات والتنبيهات',
    'Market, news and AI notifications':
        'إشعارات السوق والأخبار والذكاء الاصطناعي',
    'Master notifications': 'الإشعارات الرئيسية',
    'Price alerts': 'تنبيهات الأسعار',
    'Coming with the portfolio and target-price feature.':
        'ستتم إضافتها مع المحفظة وميزة السعر المستهدف.',
    'Planned with portfolio · Off': 'مخطط مع المحفظة · متوقف',
    'News alerts': 'تنبيهات الأخبار',
    'Sound': 'الصوت',
    'Background music': 'موسيقى الخلفية',
    'Preview': 'معاينة',
    'Stop': 'إيقاف',
    'Sequential': 'متتالٍ',
    'Shuffle': 'عشوائي',
    'Repeat one': 'تكرار واحد',
    'GoldBrain AI': 'ذكاء GoldBrain',
    'Response tone': 'أسلوب الإجابة',
    'Concise': 'مختصر',
    'Balanced': 'متوازن',
    'Detailed': 'مفصل',
    'AI creativity': 'إبداع الذكاء الاصطناعي',
    'Use market context': 'استخدام سياق السوق',
    'Use portfolio context': 'استخدام سياق المحفظة',
    'Use watchlist context': 'استخدام سياق قائمة المتابعة',
    'Currency': 'العملة',
    'Display currency': 'عملة العرض',
    'Auto': 'تلقائي',
    'Toman': 'تومان',
    'US Dollar': 'الدولار الأمريكي',
    'Euro': 'اليورو',
    'British Pound': 'الجنيه الإسترليني',
    'Chinese Yuan': 'اليوان الصيني',
    'Data & storage': 'البيانات والتخزين',
    'Automatic local save': 'الحفظ المحلي التلقائي',
    'Automatic saving of local changes': 'الحفظ التلقائي للتغييرات المحلية',
    'PAUSED': 'متوقف',
    'Local storage is paused by the retention policy. Choose Forever before adding music.':
        'التخزين المحلي متوقف وفق سياسة الاحتفاظ. اختر «دائمًا» قبل إضافة الموسيقى.',
    'Local storage is paused. Choose Forever in data retention before adding an image.':
        'التخزين المحلي متوقف. اختر «دائمًا» في مدة الاحتفاظ قبل إضافة صورة.',
    'Startup page': 'صفحة البدء',
    'Dashboard': 'لوحة المعلومات',
    'Markets': 'الأسواق',
    'AI Assistant': 'المساعد الذكي',
    '30 days': '30 يومًا',
    '90 days': '90 يومًا',
    'Forever': 'دائمًا',
    'Security & privacy': 'الأمان والخصوصية',
    'Crash reports': 'تقارير الأعطال',
    'Language': 'اللغة',
    'Notifications': 'الإشعارات',
    'Enabled': 'مفعّل',
    'Disabled': 'معطّل',
    'Unavailable': 'غير متاح',
    'Muted': 'صامت',
    'Save settings': 'حفظ الإعدادات',
    'Restore defaults': 'استعادة الإعدادات الافتراضية',
    'Settings saved successfully.': 'تم حفظ الإعدادات بنجاح.',
    'Close': 'إغلاق',
    'All': 'الكل',
    'Metals': 'المعادن',
    'Crypto': 'العملات الرقمية',
    'News': 'الأخبار',
    'Profile': 'الملف الشخصي',
    'Settings': 'الإعدادات',
    'About us': 'من نحن',
    'Watchlist': 'قائمة المتابعة',
    'Search an asset...': 'ابحث عن أصل...',
    'No asset found': 'لم يتم العثور على أصل',
    'Loading...': 'جارٍ التحميل...',
    'Retry': 'إعادة المحاولة',
    'Refresh': 'تحديث',
    'Online': 'متصل',
    'Offline': 'غير متصل',
    'Animation controls will be added in a future update.':
        'ستُضاف عناصر التحكم بالحركة في تحديث لاحق.',
    'Turn all notifications on or off.': 'تشغيل جميع الإشعارات أو إيقافها.',
    'Alert when an asset crosses its target.': 'تنبيه عند وصول الأصل إلى هدفه.',
    'Breaking news': 'أخبار عاجلة',
    'Notify important financial news.':
        'إرسال إشعارات بالأخبار المالية المهمة.',
    'AI signals': 'إشارات الذكاء الاصطناعي',
    'Notify strong AI confidence signals.':
        'تنبيه عند وجود إشارات ذكاء اصطناعي قوية.',
    'Interface feedback and audio behavior': 'استجابة الواجهة وسلوك الصوت',
    'Application sound': 'صوت التطبيق',
    'Allow interface sounds.': 'السماح بأصوات الواجهة.',
    'Play ambient GoldBrain music while using the app.':
        'تشغيل موسيقى GoldBrain أثناء استخدام التطبيق.',
    'Custom music playlist': 'قائمة موسيقى مخصصة',
    'Choose several local tracks, select the current one and control playback order.':
        'اختر عدة مقاطع محلية وحدد المقطع الحالي وترتيب التشغيل.',
    'Add files': 'إضافة ملفات',
    'Use built-in': 'استخدام المدمج',
    'Use playlist': 'استخدام القائمة',
    'Previous track': 'المقطع السابق',
    'Next track': 'المقطع التالي',
    'Select track': 'اختيار المقطع',
    'Current track': 'المقطع الحالي',
    'Remove from playlist': 'إزالة من القائمة',
    'Clear playlist': 'مسح القائمة',
    'GoldBrain built-in music restored.':
        'تمت استعادة موسيقى GoldBrain المدمجة.',
    'Built-in GoldBrain music is active.': 'موسيقى GoldBrain المدمجة مفعّلة.',
    'Local audio could not be initialized.': 'تعذرت تهيئة الصوت المحلي.',
    'The custom music file is missing. Choose it again.':
        'ملف الموسيقى المخصص مفقود. اختره مجددًا.',
    'This audio file could not be played.': 'تعذر تشغيل هذا الملف الصوتي.',
    'The playlist was saved, but this file could not be played.':
        'حُفظت القائمة، لكن تعذر تشغيل هذا الملف.',
    'The selected audio file could not be copied.':
        'تعذر نسخ الملف الصوتي المحدد.',
    'This audio format is not supported.': 'تنسيق الصوت هذا غير مدعوم.',
    'Each audio file must be smaller than 100 MB.':
        'يجب أن يقل حجم كل ملف صوتي عن 100 ميغابايت.',
    'Interface volume': 'مستوى صوت الواجهة',
    'Adjust interface feedback volume.': 'ضبط مستوى أصوات الواجهة.',
    'Personalized AI': 'ذكاء اصطناعي مخصص',
    'Adapt AI to your preferences.': 'تكييف الذكاء الاصطناعي مع تفضيلاتك.',
    'Choose how GoldBrain explains information.':
        'اختر طريقة شرح GoldBrain للمعلومات.',
    'Higher values allow broader suggestions.':
        'القيم الأعلى تسمح باقتراحات أوسع.',
    'Let AI consider market screens.':
        'السماح للذكاء الاصطناعي باستخدام بيانات السوق.',
    'Unavailable until a real portfolio data source is connected.':
        'غير متاح حتى توصيل مصدر حقيقي لبيانات المحفظة.',
    'Prioritize assets in your watchlist.':
        'إعطاء الأولوية لأصول قائمة المتابعة.',
    'Choose how prices are displayed.': 'اختر طريقة عرض الأسعار.',
    'Auto follows the selected language. You can override it manually.':
        'يتبع الوضع التلقائي اللغة المختارة ويمكن تغييره يدويًا.',
    'More currencies': 'عملات إضافية',
    'Choose another supported currency.': 'اختر عملة أخرى مدعومة.',
    'Japanese Yen': 'الين الياباني',
    'Russian Ruble': 'الروبل الروسي',
    'Local save, cloud preparation and retention':
        'الحفظ المحلي والاستعداد للسحابة والاحتفاظ',
    'Save profile and settings changes automatically.':
        'حفظ تغييرات الملف والإعدادات تلقائيًا.',
    'Select the default destination after login.':
        'اختر الصفحة الافتراضية بعد الدخول.',
    'Local data retention': 'مدة حفظ البيانات المحلية',
    'Choose how long local history is kept.':
        'اختر مدة الاحتفاظ بالسجل المحلي.',
    'Lock, analytics and diagnostic data': 'القفل والتحليلات وبيانات التشخيص',
    'Capture Flutter and Dart errors and show them in notifications.':
        'التقاط أخطاء Flutter وDart وعرضها في الإشعارات.',
    'Quick overview': 'نظرة سريعة',
    'Current configuration': 'الإعداد الحالي',
    'English': 'العربية',
    'Settings restored and saved.': 'تمت استعادة الإعدادات وحفظها.',
    'Need help?': 'هل تحتاج مساعدة؟',
    'Public support': 'الدعم العام',
    'Developer contact': 'التواصل مع المطور',
    'Email copied': 'تم نسخ البريد',
    'COMING SOON': 'قريبًا',
    'PLANNED': 'مخطط له',
    'Off': 'متوقف',
    'Active': 'نشط',
    'Markets, news and artificial intelligence in one neural command center.':
        'الأسواق والأخبار والذكاء الاصطناعي في مركز واحد.',
    'Already registered? Sign in': 'لديك حساب؟ سجّل الدخول',
    'Continue as guest (local only)': 'المتابعة كضيف (محلي فقط)',
    'CREATE ACCOUNT': 'إنشاء حساب',
    'Create your account': 'أنشئ حسابك',
    'Email address': 'البريد الإلكتروني',
    'Enter a valid email address.': 'أدخل بريدًا إلكترونيًا صالحًا.',
    'Enter the GoldBrain intelligence network.': 'ادخل شبكة GoldBrain الذكية.',
    'Enter your full name.': 'أدخل اسمك الكامل.',
    'Full name': 'الاسم الكامل',
    'No account? Create one': 'ليس لديك حساب؟ أنشئ حسابًا',
    'Password': 'كلمة المرور',
    'Confirm password': 'تأكيد كلمة المرور',
    'Please re-enter your password.': 'أعد إدخال كلمة المرور.',
    'Passwords do not match.': 'كلمتا المرور غير متطابقتين.',
    'Password must contain at least 8 characters.':
        'يجب أن تتكون كلمة المرور من 8 أحرف على الأقل.',
    'Account created. Confirm the email we sent, then sign in.':
        'تم إنشاء الحساب. أكد الرسالة المرسلة ثم سجّل الدخول.',
    'Could not reach the login service. Check the network and try again.':
        'تعذر الوصول إلى خدمة الدخول. تحقق من الشبكة وحاول مجددًا.',
    'Email or password is incorrect, or the email is not confirmed.':
        'البريد أو كلمة المرور غير صحيحة، أو لم يتم تأكيد البريد.',
    'Real login is not configured. Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY before launch.':
        'لم يتم إعداد الدخول الحقيقي. عيّن SUPABASE_URL وSUPABASE_PUBLISHABLE_KEY قبل التشغيل.',
    'Too many attempts. Please wait and try again.':
        'محاولات كثيرة جدًا. انتظر ثم حاول مجددًا.',
    'Unexpected authentication error. Please try again.':
        'حدث خطأ مصادقة غير متوقع. حاول مجددًا.',
    'Welcome back': 'مرحبًا بعودتك',
    'YOUR INTELLIGENCE. AMPLIFIED.': 'ذكاؤك، بصورة أقوى.',
    'Portfolio is not available yet': 'المحفظة غير متاحة بعد',
    'Coming in a future update; the internal gateway has not been built yet.':
        'ستتوفر في تحديث لاحق؛ لم تُبنَ البوابة الداخلية بعد.',
    'DISABLED · ROADMAP': 'معطّل · خارطة الطريق',
    'No sample balances, returns or portfolio signals are displayed.':
        'لا يتم عرض أرصدة أو عوائد أو إشارات تجريبية.',
    'Profile & Identity': 'الملف والهوية',
    'Manage personal information and account preferences.':
        'إدارة المعلومات الشخصية وتفضيلات الحساب.',
    'Display name': 'اسم العرض',
    'Phone number': 'رقم الهاتف',
    'Choose Image': 'اختيار صورة',
    'Remove Image': 'إزالة الصورة',
    'Save Changes': 'حفظ التغييرات',
    'Saving...': 'جارٍ الحفظ...',
    'Account status': 'حالة الحساب',
    'Verified': 'موثّق',
    'Local profile': 'ملف محلي',
    'Active theme': 'السمة النشطة',
    'Theme': 'السمة',
    'AI profile': 'ملف الذكاء الاصطناعي',
    'Learning mode': 'وضع التعلم',
    'Cloud sync': 'المزامنة السحابية',
    'The selected image could not be opened.': 'تعذر فتح الصورة المحددة.',
    'The selected image file was not found.': 'لم يتم العثور على ملف الصورة.',
    'An error occurred while saving the image.': 'حدث خطأ أثناء حفظ الصورة.',
    'Profile image saved successfully.': 'تم حفظ صورة الملف بنجاح.',
    'Profile image removed.': 'تمت إزالة صورة الملف.',
    'Please enter your display name.': 'أدخل اسم العرض.',
    'Please enter a valid email address.': 'أدخل بريدًا صالحًا.',
    'Profile changes saved locally.': 'تم حفظ تغييرات الملف محليًا.',
    'Profile changes could not be saved.': 'تعذر حفظ تغييرات الملف.',
    'Your profile information has been saved successfully.':
        'تم حفظ معلومات ملفك بنجاح.',
    'Profile Updated': 'تم تحديث الملف',
    'Later, GoldBrain will use your preferences, watchlist and portfolio to personalize analysis.':
        'سيستخدم GoldBrain لاحقًا تفضيلاتك وقائمة المتابعة والمحفظة لتخصيص التحليل.',
    'Track selected assets and prepare them for GoldBrain AI analysis.':
        'تابع الأصول المختارة وجهزها لتحليل GoldBrain.',
    'WATCHLIST OVERVIEW': 'نظرة على قائمة المتابعة',
    'Live prices, charts, news and prediction models will later analyze every favorite asset here.':
        'ستحلل الأسعار والرسوم والأخبار والنماذج كل أصل مفضل هنا لاحقًا.',
    'No sourced quote is currently available. GoldBrain will not manufacture an AI score or price.':
        'لا يتوفر سعر موثق حاليًا، ولن ينشئ GoldBrain سعرًا أو تقييمًا وهميًا.',
    'What GoldBrain does': 'ما الذي يقدمه GoldBrain',
    'A transparent information workspace': 'مساحة معلومات شفافة',
    'The people behind GoldBrain': 'فريق GoldBrain',
    'Creators': 'المؤسسون',
    'Product creator & developer': 'منشئ المنتج والمطور',
    'Co-creator': 'شريك الإنشاء',
    'Risk notice & roadmap': 'تنبيه المخاطر وخارطة الطريق',
    'No guaranteed return or accuracy claim': 'لا ضمان للعائد أو الدقة',
    'Support and official contact channels': 'الدعم وقنوات الاتصال الرسمية',
    'Official network': 'الشبكة الرسمية',
    'Direct contact': 'اتصال مباشر',
    'Ownership & copyright': 'الملكية وحقوق النشر',
    'Official GoldBrain ownership notice': 'إشعار ملكية GoldBrain الرسمي',
    'Designed and developed in Iran': 'صُمم وطُوّر في إيران',
    'Intelligence for a clearer financial future': 'ذكاء لمستقبل مالي أوضح',
    'Tap any card to open it in your browser.':
        'اضغط أي بطاقة لفتحها في المتصفح.',
    'Could not open this link.': 'تعذر فتح هذا الرابط.',
    'GoldBrain brings sourced market prices and sourced news together, then provides AI-assisted analysis of that information. Every available source and timestamp should remain visible to the user.':
        'يجمع GoldBrain أسعار السوق والأخبار الموثقة ثم يحللها بمساعدة الذكاء الاصطناعي مع عرض المصدر والوقت.',
    'Market data can be delayed or incorrect, and AI output can contain errors. GoldBrain does not provide investment advice or guarantee profit. Financial decisions may result in loss.':
        'قد تتأخر بيانات السوق أو تخطئ، وقد يخطئ الذكاء الاصطناعي. لا يقدم GoldBrain نصيحة استثمارية أو ضمان ربح، وقد تسبب القرارات خسارة.',
    'In-app purchases are only a future roadmap item. No internal payment gateway has been implemented.':
        'المشتريات داخل التطبيق ضمن خطة مستقبلية فقط، ولم تُنفذ بوابة دفع داخلية.',
    'GoldBrain belongs to Bardia and Armiya Alizadeh (Kabir). Unauthorized copying, redistribution, modification for resale, or illegal sale is prohibited. This application is made in Iran.':
        'GoldBrain ملك لبرديا وأرميا عليزاده (كبير). يُحظر النسخ أو إعادة التوزيع أو التعديل لإعادة البيع دون إذن. صُنع التطبيق في إيران.',
    'Bardiya Alizadeh, known as Kabir': 'برديا عليزاده، المعروف بكبير',
    'Armiya Alizadeh, known as Kabir': 'أرميا عليزاده، المعروف بكبير',
    '12-hour gold outlook': 'توقع الذهب خلال 12 ساعة',
    '12-hour scenario target': 'هدف السيناريو خلال 12 ساعة',
    '1H': 'ساعة',
    '24H': '24 ساعة',
    '7D': '7 أيام',
    'A target is hidden because there is not enough exact, verified history for this instrument.':
        'الهدف مخفي لعدم توفر سجل دقيق وموثق كافٍ لهذه الأداة.',
    'AI forecasts can be wrong and capital can be lost. The final decision and responsibility are yours.':
        'قد تخطئ توقعات الذكاء الاصطناعي وقد تخسر المال. القرار والمسؤولية لك.',
    'AI key not configured': 'مفتاح الذكاء الاصطناعي غير معدّ',
    'AI Market Conversation': 'محادثة السوق الذكية',
    'AI scenario': 'سيناريو الذكاء الاصطناعي',
    'AI signals are disabled in Settings.':
        'إشارات الذكاء الاصطناعي معطلة في الإعدادات.',
    'AI translated': 'ترجمة بالذكاء الاصطناعي',
    'AI translations and summaries may contain mistakes. The publisher original is authoritative. This content is informational and not investment advice.':
        'قد تحتوي الترجمة والملخص على أخطاء. نص الناشر الأصلي هو المرجع، والمحتوى معلوماتي وليس نصيحة استثمارية.',
    'An unexpected error occurred. Please try again.':
        'حدث خطأ غير متوقع. حاول مجددًا.',
    'Analyzing verified data…': 'جارٍ تحليل البيانات الموثقة…',
    'Ask about gold, currency, economy and market news.':
        'اسأل عن الذهب والعملات والاقتصاد وأخبار السوق.',
    'Ask GoldBrain something...': 'اسأل GoldBrain...',
    'ASSISTANT CORE': 'نواة المساعد',
    'Cancel': 'إلغاء',
    'Change the search text or category.': 'غيّر نص البحث أو الفئة.',
    'Check the internet connection. The app never inserts fabricated content.':
        'تحقق من الإنترنت. لا يضيف التطبيق محتوى مختلقًا.',
    'Clear all conversations': 'مسح جميع المحادثات',
    'Clear all conversations?': 'مسح جميع المحادثات؟',
    'Close notifications': 'إغلاق الإشعارات',
    'Configure GAPGPT_API_KEY, then run the analysis.':
        'اضبط GAPGPT_API_KEY ثم شغّل التحليل.',
    'Connected': 'متصل',
    'Connection failed': 'فشل الاتصال',
    'Conversation name': 'اسم المحادثة',
    'Delete': 'حذف',
    'Delete conversation': 'حذف المحادثة',
    'Delete conversation?': 'حذف المحادثة؟',
    'Upward scenario': 'سيناريو صاعد',
    'Downward scenario': 'سيناريو هابط',
    'Mixed scenario': 'سيناريو مختلط',
    'Evidence-based 12-hour gold scenario':
        'سيناريو الذهب لـ12 ساعة المبني على الأدلة',
    'Evidence-based AI scenario': 'سيناريو ذكاء اصطناعي مبني على الأدلة',
    'Generate summary': 'إنشاء ملخص',
    'Generated only when requested. The summary is based on the publisher text above.':
        'يُنشأ عند الطلب فقط ويعتمد على نص الناشر أعلاه.',
    'GoldBrain combines sourced prices, charts and news for a 12-hour scenario.':
        'يجمع GoldBrain الأسعار والرسوم والأخبار الموثقة لسيناريو 12 ساعة.',
    'GOLDBRAIN DEEP ANALYST': 'محلل GOLDBRAIN العميق',
    'GoldBrain system messages': 'رسائل نظام GoldBrain',
    'Hello, I am GoldBrain. Ask me about this application, sourced market prices, gold, currencies, or financial news.':
        'مرحبًا، أنا GoldBrain. اسألني عن التطبيق والأسعار الموثقة والذهب والعملات والأخبار المالية.',
    'IMPORTANT': 'مهم',
    'Iranian Financial News': 'الأخبار المالية الإيرانية',
    'just now': 'الآن',
    'LATEST RELEASES': 'أحدث الأخبار',
    'Loading the official feed...': 'جارٍ تحميل الخلاصة الرسمية...',
    'LOCAL MODE': 'الوضع المحلي',
    'Mark all read': 'تعليم الكل كمقروء',
    'MIXED SCENARIO': 'سيناريو مختلط',
    'Needs setup': 'يحتاج إلى إعداد',
    'Neural analysis engine': 'محرك التحليل العصبي',
    'New conversation': 'محادثة جديدة',
    'New notification': 'إشعار جديد',
    'Newest first • automatic refresh every 5 minutes':
        'الأحدث أولًا • تحديث تلقائي كل 5 دقائق',
    'No matching official release': 'لا يوجد خبر رسمي مطابق',
    'No sample article is shown while real data is loading.':
        'لا تُعرض أخبار تجريبية أثناء تحميل البيانات الحقيقية.',
    'No valid release was returned': 'لم يصل خبر صالح',
    'NO VERIFIED SCENARIO': 'لا يوجد سيناريو موثق',
    'Not a buy/sell order. The estimate is uncalibrated, may be wrong, and loss is possible.':
        'ليس أمر شراء أو بيع. التقدير غير معاير وقد يخطئ وقد تحدث خسارة.',
    'Notification Settings': 'إعدادات الإشعارات',
    'Notifications are disabled in Settings.': 'الإشعارات معطلة في الإعدادات.',
    'Official news is currently unavailable':
        'الأخبار الرسمية غير متاحة حاليًا',
    'Only fields returned by the named provider are shown. High, low, volume and market cap are intentionally omitted when unavailable.':
        'تُعرض فقط الحقول التي يوفرها المصدر، وتُحذف القيم غير المتاحة.',
    'Open original article': 'فتح الخبر الأصلي',
    'Press the button to analyze current prices, charts and news.':
        'اضغط الزر لتحليل الأسعار والرسوم والأخبار الحالية.',
    'Ready to send': 'جاهز للإرسال',
    'Receiving response': 'جارٍ استقبال الرد',
    'Refresh analysis': 'تحديث التحليل',
    'Refresh later. No placeholder news was inserted.':
        'حدّث لاحقًا. لم تُدرج أخبار وهمية.',
    'Refresh now': 'تحديث الآن',
    'Refresh prices': 'تحديث الأسعار',
    'Regenerate': 'إعادة الإنشاء',
    'Rename conversation': 'إعادة تسمية المحادثة',
    'Retry real AI translation': 'إعادة محاولة ترجمة الذكاء الاصطناعي',
    'Save': 'حفظ',
    'Saved conversations': 'المحادثات المحفوظة',
    'Search real news...': 'ابحث في الأخبار الحقيقية...',
    'Set GAPGPT_API_KEY to enable the 12-hour analysis.':
        'عيّن GAPGPT_API_KEY لتفعيل تحليل 12 ساعة.',
    'Source feed information': 'معلومات مصدر الخلاصة',
    'Sourced prices and recent news are both required.':
        'يلزم توفر الأسعار الموثقة والأخبار الحديثة.',
    'START DEEP ANALYSIS': 'بدء التحليل العميق',
    'Startup': 'بدء التشغيل',
    'The AI connection timed out. Check the network and try again.':
        'انتهت مهلة اتصال الذكاء الاصطناعي. تحقق من الشبكة وحاول مجددًا.',
    'The AI key is not configured. Set GAPGPT_API_KEY before starting GoldBrain.':
        'مفتاح الذكاء الاصطناعي غير معدّ. عيّن GAPGPT_API_KEY قبل تشغيل GoldBrain.',
    'The AI key was rejected. Rotate it and check the configuration.':
        'رُفض مفتاح الذكاء الاصطناعي. استبدله وتحقق من الإعداد.',
    'The AI provider returned an incomplete answer. Please send the message again.':
        'أعاد مزود الذكاء الاصطناعي ردًا ناقصًا. أرسل الرسالة مجددًا.',
    'The AI request limit has been reached. Please try again later.':
        'تم بلوغ حد طلبات الذكاء الاصطناعي. حاول لاحقًا.',
    'The AI service is temporarily unreachable. Check your internet connection and the provider status, then try again. GoldBrain also detects an enabled Windows system proxy automatically.':
        'خدمة الذكاء الاصطناعي غير متاحة مؤقتًا. تحقق من الإنترنت وحالة المزود ثم حاول مجددًا.',
    'The analysis could not be completed. Check the network and retry.':
        'تعذر إكمال التحليل. تحقق من الشبكة وأعد المحاولة.',
    'The displayed percentage is an uncalibrated AI scenario estimate, not a statistical guarantee. Forecasts can be wrong, capital can be lost, and the final decision is yours.':
        'النسبة تقدير سيناريو غير معاير وليست ضمانًا إحصائيًا. قد يخطئ التوقع وقد تخسر المال والقرار لك.',
    'The latest refresh failed. Previously verified news is still shown.':
        'فشل آخر تحديث، وما زالت الأخبار الموثقة السابقة معروضة.',
    'The official source information page could not be opened.':
        'تعذر فتح صفحة معلومات المصدر الرسمي.',
    'The original article could not be opened.': 'تعذر فتح الخبر الأصلي.',
    'The providers returned no usable points. Try again.':
        'لم تُعد المصادر نقاطًا صالحة. حاول مجددًا.',
    'The selected AI model is unavailable. Choose another model or configure GAPGPT_FALLBACK_MODELS and try again.':
        'نموذج الذكاء الاصطناعي المختار غير متاح. اختر نموذجًا آخر أو اضبط GAPGPT_FALLBACK_MODELS.',
    'This removes the local chat history from this device.':
        'سيؤدي هذا إلى حذف سجل المحادثة المحلي من الجهاز.',
    'Translating...': 'جارٍ الترجمة...',
    'Translation is unavailable; original publisher text is shown.':
        'الترجمة غير متاحة؛ يُعرض نص الناشر الأصلي.',
    'Try again': 'حاول مجددًا',
    'UPWARD SCENARIO': 'سيناريو صاعد',
    'Validated 12-hour scenario target': 'هدف سيناريو 12 ساعة موثّق',
    'Verified global gold history · XAU': 'سجل الذهب العالمي الموثق · XAU',
    'Verified gold history is unavailable': 'سجل الذهب الموثق غير متاح',
    'View publisher original': 'عرض نص الناشر الأصلي',
    'Waiting for sufficient evidence': 'بانتظار أدلة كافية',
  };

  static const Map<String, String> _turkish = {
    'Choose your GoldBrain experience': 'GoldBrain deneyiminizi seçin',
    'You can change these settings later':
        'Bu ayarları daha sonra değiştirebilirsiniz',
    'COLOR THEME': 'RENK TEMASI',
    'APPLICATION LANGUAGE': 'UYGULAMA DİLİ',
    'ENTER GOLDBRAIN': "GOLDBRAIN'E GİR",
    'Portfolio': 'Portföy',
    'About Us': 'Hakkımızda',
    'GoldBrain User': 'GoldBrain Kullanıcısı',
    'Neural account': 'Akıllı hesap',
    'Neural Account': 'Akıllı Hesap',
    'Neural market intelligence system': 'Sinirsel piyasa zekâ sistemi',
    'SYSTEM ONLINE': 'SİSTEM ÇEVRİMİÇİ',
    'Gold 18K': '18 Ayar Altın',
    'Global Gold Ounce': 'Küresel Altın Ons',
    'Global Ounce': 'Küresel Ons',
    'Bitcoin': 'Bitcoin',
    'Ethereum': 'Ethereum',
    'Silver': 'Gümüş',
    'Neural Market Pulse': 'Sinirsel Piyasa Nabzı',
    'Markets Command Center': 'Piyasalar Komuta Merkezi',
    'Search, compare and inspect tracked assets.':
        'İzlenen varlıkları arayın, karşılaştırın ve inceleyin.',
    'PRICE COVERAGE': 'FİYAT KAPSAMI',
    'Search symbol or asset...': 'Sembol veya varlık ara...',
    'Gainers': 'Yükselenler',
    'Losers': 'Düşenler',
    'Saved': 'Kaydedilenler',
    'No matching assets': 'Eşleşen varlık yok',
    'REAL PRICE HISTORY': 'GERÇEK FİYAT GEÇMİŞİ',
    'Open large chart': 'Büyük grafiği aç',
    'Historical data is temporarily unavailable':
        'Geçmiş veriler geçici olarak kullanılamıyor',
    'Waiting for verified local price samples':
        'Doğrulanmış yerel fiyat örnekleri bekleniyor',
    'UNAVAILABLE': 'KULLANILAMIYOR',
    'PROVIDER': 'SAĞLAYICI',
    'UPDATED': 'GÜNCELLENDİ',
    '24H CHANGE': '24S DEĞİŞİM',
    'Not provided': 'Sağlanmadı',
    'No internet connection. GoldBrain needs internet for live prices, news and AI.':
        'İnternet bağlantısı yok. GoldBrain canlı fiyatlar, haberler ve AI için internete ihtiyaç duyar.',
    'Smart Watchlist': 'Akıllı İzleme Listesi',
    'Added to Watchlist': 'İzleme listesine eklendi',
    'Removed from Watchlist': 'İzleme listesinden kaldırıldı',
    'FAVORITES': 'FAVORİLER',
    'LIVE QUOTES': 'CANLI FİYATLAR',
    'NO DATA': 'VERİ YOK',
    'Positive movement': 'Pozitif hareket',
    'Sourced live quotes': 'Kaynaklı canlı fiyatlar',
    'Not connected': 'Bağlı değil',
    'GoldBrain Analysis Pipeline': 'GoldBrain Analiz Süreci',
    'Application Settings': 'Uygulama Ayarları',
    'Control appearance, alerts, sound, privacy and GoldBrain AI.':
        'Görünümü, uyarıları, sesi, gizliliği ve GoldBrain AI’ı yönetin.',
    'Appearance': 'Görünüm',
    'Layout and display density': 'Düzen ve görüntü yoğunluğu',
    'Color theme': 'Renk teması',
    'Choose one of the four GoldBrain color systems.':
        'Bir GoldBrain renk sistemi seçin.',
    'Choose one of the six GoldBrain color systems.':
        'Bir GoldBrain renk sistemi seçin.',
    'Choose one of the eleven GoldBrain color systems.':
        'On bir GoldBrain renk sisteminden birini seçin.',
    'Application language': 'Uygulama dili',
    'Change the language without returning to the welcome screen.':
        'Karşılama ekranına dönmeden dili değiştirin.',
    'Interface density': 'Arayüz yoğunluğu',
    'Compact': 'Kompakt',
    'Comfortable': 'Rahat',
    'Spacious': 'Geniş',
    'Notifications & alerts': 'Bildirimler ve uyarılar',
    'Master notifications': 'Ana bildirimler',
    'Price alerts': 'Fiyat uyarıları',
    'Coming with the portfolio and target-price feature.':
        'Portföy ve hedef fiyat özelliğiyle birlikte eklenecek.',
    'Planned with portfolio · Off': 'Portföyle planlandı · Kapalı',
    'News alerts': 'Haber uyarıları',
    'Sound': 'Ses',
    'Background music': 'Arka plan müziği',
    'Preview': 'Önizleme',
    'Stop': 'Durdur',
    'Sequential': 'Sıralı',
    'Shuffle': 'Karışık',
    'Repeat one': 'Birini tekrarla',
    'GoldBrain AI': 'GoldBrain AI',
    'Response tone': 'Yanıt tonu',
    'Concise': 'Kısa',
    'Balanced': 'Dengeli',
    'Detailed': 'Ayrıntılı',
    'AI creativity': 'AI yaratıcılığı',
    'Use market context': 'Piyasa bağlamını kullan',
    'Use portfolio context': 'Portföy bağlamını kullan',
    'Use watchlist context': 'İzleme listesi bağlamını kullan',
    'Currency': 'Para birimi',
    'Display currency': 'Görüntüleme para birimi',
    'Auto': 'Otomatik',
    'Toman': 'Tümen',
    'US Dollar': 'ABD Doları',
    'Euro': 'Euro',
    'British Pound': 'İngiliz Sterlini',
    'Chinese Yuan': 'Çin Yuanı',
    'Data & storage': 'Veri ve depolama',
    'Automatic local save': 'Otomatik yerel kayıt',
    'Automatic saving of local changes': 'Yerel değişiklikleri otomatik kaydet',
    'PAUSED': 'DURAKLATILDI',
    'Local storage is paused by the retention policy. Choose Forever before adding music.':
        'Yerel depolama saklama ilkesi nedeniyle duraklatıldı. Müzik eklemeden önce “Süresiz”i seçin.',
    'Local storage is paused. Choose Forever in data retention before adding an image.':
        'Yerel depolama duraklatıldı. Görsel eklemeden önce veri saklamada “Süresiz”i seçin.',
    'Startup page': 'Başlangıç sayfası',
    'Dashboard': 'Kontrol paneli',
    'Markets': 'Piyasalar',
    'AI Assistant': 'AI Asistanı',
    '30 days': '30 gün',
    '90 days': '90 gün',
    'Forever': 'Süresiz',
    'Security & privacy': 'Güvenlik ve gizlilik',
    'Crash reports': 'Çökme raporları',
    'Language': 'Dil',
    'Notifications': 'Bildirimler',
    'Enabled': 'Etkin',
    'Disabled': 'Devre dışı',
    'Unavailable': 'Kullanılamıyor',
    'Muted': 'Sessiz',
    'Save settings': 'Ayarları kaydet',
    'Restore defaults': 'Varsayılanları geri yükle',
    'Settings saved successfully.': 'Ayarlar başarıyla kaydedildi.',
    'Close': 'Kapat',
    'All': 'Tümü',
    'Metals': 'Metaller',
    'Crypto': 'Kripto',
    'News': 'Haberler',
    'Profile': 'Profil',
    'Settings': 'Ayarlar',
    'About us': 'Hakkımızda',
    'Watchlist': 'İzleme listesi',
    'Search an asset...': 'Varlık ara...',
    'No asset found': 'Varlık bulunamadı',
    'Loading...': 'Yükleniyor...',
    'Retry': 'Yeniden dene',
    'Refresh': 'Yenile',
    'Online': 'Çevrimiçi',
    'Offline': 'Çevrimdışı',
    'Choose spacing between interface elements.':
        'Arayüz öğeleri arasındaki boşluğu seçin.',
    'Animation controls will be added in a future update.':
        'Animasyon kontrolleri sonraki bir güncellemede eklenecek.',
    'Market, news and AI notifications': 'Piyasa, haber ve AI bildirimleri',
    'Turn all notifications on or off.': 'Tüm bildirimleri açın veya kapatın.',
    'Alert when an asset crosses its target.':
        'Bir varlık hedefine ulaştığında uyar.',
    'Breaking news': 'Son dakika haberleri',
    'Notify important financial news.': 'Önemli finans haberlerini bildir.',
    'AI signals': 'AI sinyalleri',
    'Notify strong AI confidence signals.':
        'Güçlü AI güven sinyallerini bildir.',
    'Interface feedback and audio behavior':
        'Arayüz geri bildirimi ve ses davranışı',
    'Application sound': 'Uygulama sesi',
    'Allow interface sounds.': 'Arayüz seslerine izin ver.',
    'Play ambient GoldBrain music while using the app.':
        'Uygulamayı kullanırken GoldBrain müziğini çal.',
    'Custom music playlist': 'Özel müzik listesi',
    'Choose several local tracks, select the current one and control playback order.':
        'Birden çok yerel parça seçin ve çalma sırasını yönetin.',
    'Add files': 'Dosya ekle',
    'Use built-in': 'Yerleşik müziği kullan',
    'Use playlist': 'Listeyi kullan',
    'Previous track': 'Önceki parça',
    'Next track': 'Sonraki parça',
    'Select track': 'Parça seç',
    'Current track': 'Geçerli parça',
    'Remove from playlist': 'Listeden kaldır',
    'Clear playlist': 'Listeyi temizle',
    'GoldBrain built-in music restored.':
        'GoldBrain yerleşik müziği geri yüklendi.',
    'Built-in GoldBrain music is active.': 'GoldBrain yerleşik müziği etkin.',
    'Local audio could not be initialized.': 'Yerel ses başlatılamadı.',
    'The custom music file is missing. Choose it again.':
        'Özel müzik dosyası eksik. Yeniden seçin.',
    'This audio file could not be played.': 'Bu ses dosyası oynatılamadı.',
    'The playlist was saved, but this file could not be played.':
        'Liste kaydedildi ancak bu dosya oynatılamadı.',
    'The selected audio file could not be copied.':
        'Seçilen ses dosyası kopyalanamadı.',
    'This audio format is not supported.': 'Bu ses biçimi desteklenmiyor.',
    'Each audio file must be smaller than 100 MB.':
        'Her ses dosyası 100 MB’tan küçük olmalıdır.',
    'Interface volume': 'Arayüz ses düzeyi',
    'Adjust interface feedback volume.':
        'Arayüz geri bildirim sesini ayarlayın.',
    'Personalized AI': 'Kişiselleştirilmiş AI',
    'Adapt AI to your preferences.': 'AI’ı tercihlerinize uyarlayın.',
    'Choose how GoldBrain explains information.':
        'GoldBrain’in bilgileri nasıl açıklayacağını seçin.',
    'Higher values allow broader suggestions.':
        'Yüksek değerler daha geniş önerilere izin verir.',
    'Let AI consider market screens.':
        'AI’ın piyasa verilerini dikkate almasını sağlayın.',
    'Unavailable until a real portfolio data source is connected.':
        'Gerçek portföy veri kaynağı bağlanana kadar kullanılamaz.',
    'Prioritize assets in your watchlist.':
        'İzleme listenizdeki varlıklara öncelik verin.',
    'Choose how prices are displayed.':
        'Fiyatların nasıl gösterileceğini seçin.',
    'Auto follows the selected language. You can override it manually.':
        'Otomatik mod seçilen dili izler; elle değiştirebilirsiniz.',
    'More currencies': 'Diğer para birimleri',
    'Choose another supported currency.':
        'Desteklenen başka bir para birimi seçin.',
    'Japanese Yen': 'Japon Yeni',
    'Russian Ruble': 'Rus Rublesi',
    'Local save, cloud preparation and retention':
        'Yerel kayıt, bulut hazırlığı ve saklama',
    'Save profile and settings changes automatically.':
        'Profil ve ayar değişikliklerini otomatik kaydet.',
    'Select the default destination after login.':
        'Girişten sonraki varsayılan sayfayı seçin.',
    'Local data retention': 'Yerel veri saklama',
    'Choose how long local history is kept.':
        'Yerel geçmişin ne kadar tutulacağını seçin.',
    'Lock, analytics and diagnostic data': 'Kilit, analiz ve tanılama verileri',
    'Capture Flutter and Dart errors and show them in notifications.':
        'Flutter ve Dart hatalarını yakalayıp bildirimlerde göster.',
    'Quick overview': 'Hızlı genel bakış',
    'Current configuration': 'Geçerli yapılandırma',
    'English': 'Türkçe',
    'Settings restored and saved.': 'Ayarlar geri yüklendi ve kaydedildi.',
    'Need help?': 'Yardıma mı ihtiyacınız var?',
    'Public support': 'Genel destek',
    'Developer contact': 'Geliştirici iletişimi',
    'Email copied': 'E-posta kopyalandı',
    'COMING SOON': 'YAKINDA',
    'PLANNED': 'PLANLANDI',
    'Off': 'Kapalı',
    'Active': 'Etkin',
    'Markets, news and artificial intelligence in one neural command center.':
        'Piyasalar, haberler ve yapay zekâ tek bir merkezde.',
    'Already registered? Sign in': 'Kayıtlı mısınız? Giriş yapın',
    'Continue as guest (local only)':
        'Misafir olarak devam et (yalnızca yerel)',
    'CREATE ACCOUNT': 'HESAP OLUŞTUR',
    'Create your account': 'Hesabınızı oluşturun',
    'Email address': 'E-posta adresi',
    'Enter a valid email address.': 'Geçerli bir e-posta adresi girin.',
    'Enter the GoldBrain intelligence network.': 'GoldBrain zekâ ağına girin.',
    'Enter your full name.': 'Adınızı ve soyadınızı girin.',
    'Full name': 'Ad soyad',
    'No account? Create one': 'Hesabınız yok mu? Oluşturun',
    'Password': 'Şifre',
    'Confirm password': 'Şifreyi tekrar girin',
    'Please re-enter your password.': 'Lütfen şifrenizi tekrar girin.',
    'Passwords do not match.': 'Şifreler eşleşmiyor.',
    'Password must contain at least 8 characters.':
        'Şifre en az 8 karakter içermelidir.',
    'Account created. Confirm the email we sent, then sign in.':
        'Hesap oluşturuldu. Gönderdiğimiz e-postayı onaylayıp giriş yapın.',
    'Could not reach the login service. Check the network and try again.':
        'Giriş hizmetine ulaşılamadı. Ağı kontrol edip yeniden deneyin.',
    'Email or password is incorrect, or the email is not confirmed.':
        'E-posta ya da şifre yanlış veya e-posta doğrulanmamış.',
    'Real login is not configured. Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY before launch.':
        'Gerçek giriş yapılandırılmadı. Başlatmadan önce SUPABASE_URL ve SUPABASE_PUBLISHABLE_KEY değerlerini ayarlayın.',
    'Too many attempts. Please wait and try again.':
        'Çok fazla deneme. Bekleyip yeniden deneyin.',
    'Unexpected authentication error. Please try again.':
        'Beklenmeyen kimlik doğrulama hatası. Yeniden deneyin.',
    'Welcome back': 'Tekrar hoş geldiniz',
    'YOUR INTELLIGENCE. AMPLIFIED.': 'ZEKÂNIZI GÜÇLENDİRİN.',
    'Portfolio is not available yet': 'Portföy henüz kullanılamıyor',
    'Coming in a future update; the internal gateway has not been built yet.':
        'Gelecek bir güncellemede eklenecek; dahili ağ geçidi henüz oluşturulmadı.',
    'DISABLED · ROADMAP': 'DEVRE DIŞI · YOL HARİTASI',
    'No sample balances, returns or portfolio signals are displayed.':
        'Örnek bakiye, getiri veya portföy sinyali gösterilmez.',
    'Profile & Identity': 'Profil ve Kimlik',
    'Manage personal information and account preferences.':
        'Kişisel bilgileri ve hesap tercihlerini yönetin.',
    'Display name': 'Görünen ad',
    'Phone number': 'Telefon numarası',
    'Choose Image': 'Görsel Seç',
    'Remove Image': 'Görseli Kaldır',
    'Save Changes': 'Değişiklikleri Kaydet',
    'Saving...': 'Kaydediliyor...',
    'Account status': 'Hesap durumu',
    'Verified': 'Doğrulandı',
    'Local profile': 'Yerel profil',
    'Active theme': 'Etkin tema',
    'Theme': 'Tema',
    'AI profile': 'AI profili',
    'Learning mode': 'Öğrenme modu',
    'Cloud sync': 'Bulut eşitleme',
    'The selected image could not be opened.': 'Seçilen görsel açılamadı.',
    'The selected image file was not found.':
        'Seçilen görsel dosyası bulunamadı.',
    'An error occurred while saving the image.':
        'Görsel kaydedilirken hata oluştu.',
    'Profile image saved successfully.': 'Profil görseli kaydedildi.',
    'Profile image removed.': 'Profil görseli kaldırıldı.',
    'Please enter your display name.': 'Görünen adınızı girin.',
    'Please enter a valid email address.': 'Geçerli bir e-posta adresi girin.',
    'Profile changes saved locally.':
        'Profil değişiklikleri yerel olarak kaydedildi.',
    'Profile changes could not be saved.':
        'Profil değişiklikleri kaydedilemedi.',
    'Your profile information has been saved successfully.':
        'Profil bilgileriniz kaydedildi.',
    'Profile Updated': 'Profil Güncellendi',
    'Later, GoldBrain will use your preferences, watchlist and portfolio to personalize analysis.':
        'GoldBrain daha sonra analizi kişiselleştirmek için tercihlerinizi, izleme listenizi ve portföyünüzü kullanacak.',
    'Track selected assets and prepare them for GoldBrain AI analysis.':
        'Seçili varlıkları izleyip GoldBrain AI analizine hazırlayın.',
    'WATCHLIST OVERVIEW': 'İZLEME LİSTESİ ÖZETİ',
    'Live prices, charts, news and prediction models will later analyze every favorite asset here.':
        'Canlı fiyatlar, grafikler, haberler ve modeller ileride favori varlıkları burada analiz edecek.',
    'No sourced quote is currently available. GoldBrain will not manufacture an AI score or price.':
        'Şu anda kaynaklı fiyat yok. GoldBrain yapay bir AI puanı veya fiyat üretmez.',
    'What GoldBrain does': 'GoldBrain ne yapar?',
    'A transparent information workspace': 'Şeffaf bir bilgi çalışma alanı',
    'The people behind GoldBrain': 'GoldBrain ekibi',
    'Creators': 'Kurucular',
    'Product creator & developer': 'Ürün kurucusu ve geliştirici',
    'Co-creator': 'Ortak kurucu',
    'Risk notice & roadmap': 'Risk bildirimi ve yol haritası',
    'No guaranteed return or accuracy claim':
        'Getiri veya doğruluk garantisi yoktur',
    'Support and official contact channels':
        'Destek ve resmî iletişim kanalları',
    'Official network': 'Resmî ağ',
    'Direct contact': 'Doğrudan iletişim',
    'Ownership & copyright': 'Mülkiyet ve telif hakkı',
    'Official GoldBrain ownership notice': 'Resmî GoldBrain mülkiyet bildirimi',
    'Designed and developed in Iran': 'İran’da tasarlanıp geliştirildi',
    'Intelligence for a clearer financial future':
        'Daha açık bir finansal gelecek için zekâ',
    'Tap any card to open it in your browser.':
        'Tarayıcıda açmak için bir karta dokunun.',
    'Could not open this link.': 'Bu bağlantı açılamadı.',
    'GoldBrain brings sourced market prices and sourced news together, then provides AI-assisted analysis of that information. Every available source and timestamp should remain visible to the user.':
        'GoldBrain kaynaklı piyasa fiyatlarıyla haberleri birleştirir ve AI destekli analiz sunar; kaynak ve zaman bilgisi görünür kalır.',
    'Market data can be delayed or incorrect, and AI output can contain errors. GoldBrain does not provide investment advice or guarantee profit. Financial decisions may result in loss.':
        'Piyasa verileri gecikebilir veya yanlış olabilir; AI da hata yapabilir. GoldBrain yatırım tavsiyesi ya da kazanç garantisi vermez.',
    'In-app purchases are only a future roadmap item. No internal payment gateway has been implemented.':
        'Uygulama içi satın alma yalnızca gelecek planıdır; dahili ödeme altyapısı yoktur.',
    'GoldBrain belongs to Bardia and Armiya Alizadeh (Kabir). Unauthorized copying, redistribution, modification for resale, or illegal sale is prohibited. This application is made in Iran.':
        'GoldBrain, Bardia ve Armiya Alizadeh’e (Kabir) aittir. İzinsiz kopyalama, dağıtma veya satış yasaktır. Uygulama İran’da yapılmıştır.',
    'Bardiya Alizadeh, known as Kabir': 'Kabir olarak bilinen Bardiya Alizadeh',
    'Armiya Alizadeh, known as Kabir': 'Kabir olarak bilinen Armiya Alizadeh',
    '12-hour gold outlook': '12 saatlik altın görünümü',
    '12-hour scenario target': '12 saatlik senaryo hedefi',
    '1H': '1S',
    '24H': '24S',
    '7D': '7G',
    'A target is hidden because there is not enough exact, verified history for this instrument.':
        'Bu araç için yeterli doğrulanmış geçmiş olmadığından hedef gizlendi.',
    'AI forecasts can be wrong and capital can be lost. The final decision and responsibility are yours.':
        'AI tahminleri yanlış olabilir ve para kaybedilebilir. Son karar ve sorumluluk sizindir.',
    'AI key not configured': 'AI anahtarı yapılandırılmadı',
    'AI Market Conversation': 'AI Piyasa Sohbeti',
    'AI scenario': 'AI senaryosu',
    'AI signals are disabled in Settings.': 'AI sinyalleri Ayarlar’da kapalı.',
    'AI translated': 'AI tarafından çevrildi',
    'AI translations and summaries may contain mistakes. The publisher original is authoritative. This content is informational and not investment advice.':
        'AI çevirileri ve özetleri hata içerebilir. Yayıncının özgün metni esastır; bu içerik yatırım tavsiyesi değildir.',
    'An unexpected error occurred. Please try again.':
        'Beklenmeyen bir hata oluştu. Yeniden deneyin.',
    'Analyzing verified data…': 'Doğrulanmış veriler analiz ediliyor…',
    'Ask about gold, currency, economy and market news.':
        'Altın, döviz, ekonomi ve piyasa haberlerini sorun.',
    'Ask GoldBrain something...': 'GoldBrain’e bir şey sorun...',
    'ASSISTANT CORE': 'ASİSTAN ÇEKİRDEĞİ',
    'Cancel': 'İptal',
    'Change the search text or category.':
        'Arama metnini veya kategoriyi değiştirin.',
    'Check the internet connection. The app never inserts fabricated content.':
        'İnternet bağlantısını kontrol edin. Uygulama uydurma içerik eklemez.',
    'Clear all conversations': 'Tüm sohbetleri temizle',
    'Clear all conversations?': 'Tüm sohbetler temizlensin mi?',
    'Close notifications': 'Bildirimleri kapat',
    'Configure GAPGPT_API_KEY, then run the analysis.':
        'GAPGPT_API_KEY değerini ayarlayıp analizi çalıştırın.',
    'Connected': 'Bağlandı',
    'Connection failed': 'Bağlantı başarısız',
    'Conversation name': 'Sohbet adı',
    'Delete': 'Sil',
    'Delete conversation': 'Sohbeti sil',
    'Delete conversation?': 'Sohbet silinsin mi?',
    'Upward scenario': 'Yükseliş senaryosu',
    'Downward scenario': 'Düşüş senaryosu',
    'Mixed scenario': 'Karma senaryo',
    'Evidence-based 12-hour gold scenario':
        'Kanıta dayalı 12 saatlik altın senaryosu',
    'Evidence-based AI scenario': 'Kanıta dayalı AI senaryosu',
    'Generate summary': 'Özet oluştur',
    'Generated only when requested. The summary is based on the publisher text above.':
        'Yalnızca istendiğinde oluşturulur ve yayıncı metnine dayanır.',
    'GoldBrain combines sourced prices, charts and news for a 12-hour scenario.':
        'GoldBrain, 12 saatlik senaryo için kaynaklı fiyatları, grafikleri ve haberleri birleştirir.',
    'GOLDBRAIN DEEP ANALYST': 'GOLDBRAIN DERİN ANALİST',
    'GoldBrain system messages': 'GoldBrain sistem mesajları',
    'Hello, I am GoldBrain. Ask me about this application, sourced market prices, gold, currencies, or financial news.':
        'Merhaba, ben GoldBrain. Uygulama, kaynaklı fiyatlar, altın, döviz veya finans haberlerini sorabilirsiniz.',
    'IMPORTANT': 'ÖNEMLİ',
    'Iranian Financial News': 'İran Finans Haberleri',
    'just now': 'şimdi',
    'LATEST RELEASES': 'SON HABERLER',
    'Loading the official feed...': 'Resmî akış yükleniyor...',
    'LOCAL MODE': 'YEREL MOD',
    'Mark all read': 'Tümünü okundu işaretle',
    'MIXED SCENARIO': 'KARMA SENARYO',
    'Needs setup': 'Kurulum gerekli',
    'Neural analysis engine': 'Sinirsel analiz motoru',
    'New conversation': 'Yeni sohbet',
    'New notification': 'Yeni bildirim',
    'Newest first • automatic refresh every 5 minutes':
        'En yeni önce • her 5 dakikada otomatik yenileme',
    'No matching official release': 'Eşleşen resmî haber yok',
    'No sample article is shown while real data is loading.':
        'Gerçek veri yüklenirken örnek haber gösterilmez.',
    'No valid release was returned': 'Geçerli haber alınamadı',
    'NO VERIFIED SCENARIO': 'DOĞRULANMIŞ SENARYO YOK',
    'Not a buy/sell order. The estimate is uncalibrated, may be wrong, and loss is possible.':
        'Bu bir al/sat emri değildir. Tahmin kalibre edilmemiştir, yanlış olabilir ve kayıp yaşanabilir.',
    'Notification Settings': 'Bildirim Ayarları',
    'Notifications are disabled in Settings.': 'Bildirimler Ayarlar’da kapalı.',
    'Official news is currently unavailable':
        'Resmî haberler şu anda kullanılamıyor',
    'Only fields returned by the named provider are shown. High, low, volume and market cap are intentionally omitted when unavailable.':
        'Yalnızca sağlayıcının döndürdüğü alanlar gösterilir; olmayan değerler özellikle atlanır.',
    'Open original article': 'Özgün haberi aç',
    'Press the button to analyze current prices, charts and news.':
        'Geçerli fiyatları, grafikleri ve haberleri analiz etmek için düğmeye basın.',
    'Ready to send': 'Göndermeye hazır',
    'Receiving response': 'Yanıt alınıyor',
    'Refresh analysis': 'Analizi yenile',
    'Refresh later. No placeholder news was inserted.':
        'Daha sonra yenileyin. Yer tutucu haber eklenmedi.',
    'Refresh now': 'Şimdi yenile',
    'Refresh prices': 'Fiyatları yenile',
    'Regenerate': 'Yeniden oluştur',
    'Rename conversation': 'Sohbeti yeniden adlandır',
    'Retry real AI translation': 'Gerçek AI çevirisini yeniden dene',
    'Save': 'Kaydet',
    'Saved conversations': 'Kaydedilen sohbetler',
    'Search real news...': 'Gerçek haberlerde ara...',
    'Set GAPGPT_API_KEY to enable the 12-hour analysis.':
        '12 saatlik analiz için GAPGPT_API_KEY ayarlayın.',
    'Source feed information': 'Kaynak akış bilgileri',
    'Sourced prices and recent news are both required.':
        'Kaynaklı fiyatlar ve güncel haberler birlikte gereklidir.',
    'START DEEP ANALYSIS': 'DERİN ANALİZİ BAŞLAT',
    'Startup': 'Başlangıç',
    'The AI connection timed out. Check the network and try again.':
        'AI bağlantısı zaman aşımına uğradı. Ağı kontrol edip yeniden deneyin.',
    'The AI key is not configured. Set GAPGPT_API_KEY before starting GoldBrain.':
        'AI anahtarı yapılandırılmadı. GoldBrain’i başlatmadan GAPGPT_API_KEY ayarlayın.',
    'The AI key was rejected. Rotate it and check the configuration.':
        'AI anahtarı reddedildi. Anahtarı yenileyip yapılandırmayı kontrol edin.',
    'The AI provider returned an incomplete answer. Please send the message again.':
        'AI sağlayıcısı eksik yanıt döndürdü. Mesajı yeniden gönderin.',
    'The AI request limit has been reached. Please try again later.':
        'AI istek sınırına ulaşıldı. Daha sonra deneyin.',
    'The AI service is temporarily unreachable. Check your internet connection and the provider status, then try again. GoldBrain also detects an enabled Windows system proxy automatically.':
        'AI hizmetine geçici olarak ulaşılamıyor. İnterneti ve sağlayıcı durumunu kontrol edip yeniden deneyin.',
    'The analysis could not be completed. Check the network and retry.':
        'Analiz tamamlanamadı. Ağı kontrol edip yeniden deneyin.',
    'The displayed percentage is an uncalibrated AI scenario estimate, not a statistical guarantee. Forecasts can be wrong, capital can be lost, and the final decision is yours.':
        'Gösterilen yüzde kalibre edilmemiş bir AI senaryo tahminidir; garanti değildir. Tahmin yanlış olabilir ve karar sizindir.',
    'The latest refresh failed. Previously verified news is still shown.':
        'Son yenileme başarısız oldu; önceki doğrulanmış haberler gösteriliyor.',
    'The official source information page could not be opened.':
        'Resmî kaynak bilgi sayfası açılamadı.',
    'The original article could not be opened.': 'Özgün haber açılamadı.',
    'The providers returned no usable points. Try again.':
        'Sağlayıcılar kullanılabilir veri döndürmedi. Yeniden deneyin.',
    'The selected AI model is unavailable. Choose another model or configure GAPGPT_FALLBACK_MODELS and try again.':
        'Seçilen AI modeli kullanılamıyor. Başka model seçin veya GAPGPT_FALLBACK_MODELS ayarlayın.',
    'This removes the local chat history from this device.':
        'Bu işlem yerel sohbet geçmişini cihazdan siler.',
    'Translating...': 'Çevriliyor...',
    'Translation is unavailable; original publisher text is shown.':
        'Çeviri kullanılamıyor; yayıncının özgün metni gösteriliyor.',
    'Try again': 'Yeniden dene',
    'UPWARD SCENARIO': 'YÜKSELİŞ SENARYOSU',
    'Validated 12-hour scenario target':
        'Doğrulanmış 12 saatlik senaryo hedefi',
    'Verified global gold history · XAU':
        'Doğrulanmış küresel altın geçmişi · XAU',
    'Verified gold history is unavailable':
        'Doğrulanmış altın geçmişi kullanılamıyor',
    'View publisher original': 'Yayıncının özgün metnini göster',
    'Waiting for sufficient evidence': 'Yeterli kanıt bekleniyor',
  };

  static const Map<String, String> _french = {
    'Choose your GoldBrain experience': 'Choisissez votre expérience GoldBrain',
    'You can change these settings later':
        'Vous pourrez modifier ces réglages plus tard',
    'COLOR THEME': 'THÈME DE COULEUR',
    'APPLICATION LANGUAGE': "LANGUE DE L’APPLICATION",
    'ENTER GOLDBRAIN': 'ENTRER DANS GOLDBRAIN',
    'Portfolio': 'Portefeuille',
    'About Us': 'À propos',
    'GoldBrain User': 'Utilisateur GoldBrain',
    'Neural account': 'Compte intelligent',
    'Neural Account': 'Compte intelligent',
    'Neural market intelligence system': 'Système neuronal d’analyse du marché',
    'SYSTEM ONLINE': 'SYSTÈME EN LIGNE',
    'Gold 18K': 'Or 18 carats',
    'Global Gold Ounce': 'Once d’or mondiale',
    'Global Ounce': 'Once mondiale',
    'Bitcoin': 'Bitcoin',
    'Ethereum': 'Ethereum',
    'Silver': 'Argent',
    'Neural Market Pulse': 'Pouls neuronal du marché',
    'Markets Command Center': 'Centre de commande des marchés',
    'Search, compare and inspect tracked assets.':
        'Recherchez, comparez et examinez les actifs suivis.',
    'PRICE COVERAGE': 'COUVERTURE DES PRIX',
    'Search symbol or asset...': 'Rechercher un symbole ou un actif...',
    'Gainers': 'Hausses',
    'Losers': 'Baisses',
    'Saved': 'Enregistrés',
    'No matching assets': 'Aucun actif correspondant',
    'REAL PRICE HISTORY': 'HISTORIQUE RÉEL DES PRIX',
    'Open large chart': 'Ouvrir le grand graphique',
    'Historical data is temporarily unavailable':
        'Les données historiques sont temporairement indisponibles',
    'Waiting for verified local price samples':
        'En attente d’échantillons de prix locaux vérifiés',
    'UNAVAILABLE': 'INDISPONIBLE',
    'PROVIDER': 'FOURNISSEUR',
    'UPDATED': 'MIS À JOUR',
    '24H CHANGE': 'VARIATION 24 H',
    'Not provided': 'Non fourni',
    'No internet connection. GoldBrain needs internet for live prices, news and AI.':
        'Aucune connexion Internet. GoldBrain a besoin d’Internet pour les prix en direct, les actualités et l’IA.',
    'Smart Watchlist': 'Liste de suivi intelligente',
    'Added to Watchlist': 'Ajouté à la liste de suivi',
    'Removed from Watchlist': 'Retiré de la liste de suivi',
    'FAVORITES': 'FAVORIS',
    'LIVE QUOTES': 'COURS EN DIRECT',
    'NO DATA': 'AUCUNE DONNÉE',
    'Positive movement': 'Mouvement positif',
    'Sourced live quotes': 'Cours en direct avec sources',
    'Not connected': 'Non connecté',
    'GoldBrain Analysis Pipeline': 'Pipeline d’analyse GoldBrain',
    'Application Settings': "Paramètres de l’application",
    'Control appearance, alerts, sound, privacy and GoldBrain AI.':
        'Gérez l’apparence, les alertes, le son, la confidentialité et GoldBrain AI.',
    'Appearance': 'Apparence',
    'Layout and display density': "Disposition et densité d’affichage",
    'Color theme': 'Thème de couleur',
    'Choose one of the four GoldBrain color systems.':
        'Choisissez un thème GoldBrain.',
    'Choose one of the six GoldBrain color systems.':
        'Choisissez un thème GoldBrain.',
    'Choose one of the eleven GoldBrain color systems.':
        'Choisissez l’un des onze thèmes GoldBrain.',
    'Application language': "Langue de l’application",
    'Change the language without returning to the welcome screen.':
        'Changez de langue sans revenir à l’écran d’accueil.',
    'Interface density': "Densité de l’interface",
    'Compact': 'Compacte',
    'Comfortable': 'Confortable',
    'Spacious': 'Spacieuse',
    'Notifications & alerts': 'Notifications et alertes',
    'Master notifications': 'Notifications principales',
    'Price alerts': 'Alertes de prix',
    'Coming with the portfolio and target-price feature.':
        'Sera ajouté avec le portefeuille et les prix cibles.',
    'Planned with portfolio · Off': 'Prévu avec le portefeuille · Désactivé',
    'News alerts': "Alertes d’actualité",
    'Sound': 'Son',
    'Background music': 'Musique de fond',
    'Preview': 'Aperçu',
    'Stop': 'Arrêter',
    'Sequential': 'Séquentiel',
    'Shuffle': 'Aléatoire',
    'Repeat one': 'Répéter un titre',
    'GoldBrain AI': 'GoldBrain AI',
    'Response tone': 'Style de réponse',
    'Concise': 'Concis',
    'Balanced': 'Équilibré',
    'Detailed': 'Détaillé',
    'AI creativity': "Créativité de l’IA",
    'Use market context': 'Utiliser le contexte du marché',
    'Use portfolio context': 'Utiliser le contexte du portefeuille',
    'Use watchlist context': 'Utiliser le contexte de la liste de suivi',
    'Currency': 'Devise',
    'Display currency': "Devise d’affichage",
    'Auto': 'Auto',
    'Toman': 'Toman',
    'US Dollar': 'Dollar américain',
    'Euro': 'Euro',
    'British Pound': 'Livre sterling',
    'Chinese Yuan': 'Yuan chinois',
    'Data & storage': 'Données et stockage',
    'Automatic local save': 'Sauvegarde locale automatique',
    'Automatic saving of local changes':
        'Enregistrement automatique des modifications locales',
    'PAUSED': 'EN PAUSE',
    'Local storage is paused by the retention policy. Choose Forever before adding music.':
        'Le stockage local est suspendu par la politique de conservation. Choisissez « Toujours » avant d’ajouter de la musique.',
    'Local storage is paused. Choose Forever in data retention before adding an image.':
        'Le stockage local est suspendu. Choisissez « Toujours » dans la conservation avant d’ajouter une image.',
    'Startup page': 'Page de démarrage',
    'Dashboard': 'Tableau de bord',
    'Markets': 'Marchés',
    'AI Assistant': 'Assistant IA',
    '30 days': '30 jours',
    '90 days': '90 jours',
    'Forever': 'Toujours',
    'Security & privacy': 'Sécurité et confidentialité',
    'Crash reports': "Rapports d’incident",
    'Language': 'Langue',
    'Notifications': 'Notifications',
    'Enabled': 'Activé',
    'Disabled': 'Désactivé',
    'Unavailable': 'Indisponible',
    'Muted': 'Muet',
    'Save settings': 'Enregistrer les paramètres',
    'Restore defaults': 'Rétablir les valeurs par défaut',
    'Settings saved successfully.': 'Paramètres enregistrés.',
    'Close': 'Fermer',
    'All': 'Tout',
    'Metals': 'Métaux',
    'Crypto': 'Crypto',
    'News': 'Actualités',
    'Profile': 'Profil',
    'Settings': 'Paramètres',
    'About us': 'À propos',
    'Watchlist': 'Liste de suivi',
    'Search an asset...': 'Rechercher un actif...',
    'No asset found': 'Aucun actif trouvé',
    'Loading...': 'Chargement...',
    'Retry': 'Réessayer',
    'Refresh': 'Actualiser',
    'Online': 'En ligne',
    'Offline': 'Hors ligne',
    'Choose spacing between interface elements.':
        'Choisissez l’espacement entre les éléments.',
    'Animation controls will be added in a future update.':
        'Les réglages d’animation seront ajoutés ultérieurement.',
    'Market, news and AI notifications':
        'Notifications des marchés, actualités et IA',
    'Turn all notifications on or off.':
        'Activez ou désactivez toutes les notifications.',
    'Alert when an asset crosses its target.':
        'Alerter lorsqu’un actif atteint son objectif.',
    'Breaking news': 'Actualités urgentes',
    'Notify important financial news.':
        'Notifier les actualités financières importantes.',
    'AI signals': 'Signaux IA',
    'Notify strong AI confidence signals.':
        'Notifier les signaux IA à forte confiance.',
    'Interface feedback and audio behavior':
        'Retour de l’interface et comportement audio',
    'Application sound': 'Son de l’application',
    'Allow interface sounds.': 'Autoriser les sons de l’interface.',
    'Play ambient GoldBrain music while using the app.':
        'Lire la musique GoldBrain pendant l’utilisation.',
    'Custom music playlist': 'Liste musicale personnalisée',
    'Choose several local tracks, select the current one and control playback order.':
        'Choisissez plusieurs pistes locales et leur ordre de lecture.',
    'Add files': 'Ajouter des fichiers',
    'Use built-in': 'Utiliser la musique intégrée',
    'Use playlist': 'Utiliser la liste',
    'Previous track': 'Piste précédente',
    'Next track': 'Piste suivante',
    'Select track': 'Choisir la piste',
    'Current track': 'Piste actuelle',
    'Remove from playlist': 'Retirer de la liste',
    'Clear playlist': 'Vider la liste',
    'GoldBrain built-in music restored.':
        'La musique intégrée de GoldBrain a été restaurée.',
    'Built-in GoldBrain music is active.':
        'La musique intégrée de GoldBrain est active.',
    'Local audio could not be initialized.':
        'L’audio local n’a pas pu être initialisé.',
    'The custom music file is missing. Choose it again.':
        'Le fichier musical est introuvable. Sélectionnez-le à nouveau.',
    'This audio file could not be played.':
        'Ce fichier audio ne peut pas être lu.',
    'The playlist was saved, but this file could not be played.':
        'La liste a été enregistrée, mais ce fichier ne peut pas être lu.',
    'The selected audio file could not be copied.':
        'Le fichier audio sélectionné n’a pas pu être copié.',
    'This audio format is not supported.':
        'Ce format audio n’est pas pris en charge.',
    'Each audio file must be smaller than 100 MB.':
        'Chaque fichier audio doit faire moins de 100 Mo.',
    'Interface volume': 'Volume de l’interface',
    'Adjust interface feedback volume.':
        'Réglez le volume des sons de l’interface.',
    'Personalized AI': 'IA personnalisée',
    'Adapt AI to your preferences.': 'Adaptez l’IA à vos préférences.',
    'Choose how GoldBrain explains information.':
        'Choisissez comment GoldBrain explique les informations.',
    'Higher values allow broader suggestions.':
        'Une valeur élevée autorise des suggestions plus larges.',
    'Let AI consider market screens.':
        'Autoriser l’IA à tenir compte des données du marché.',
    'Unavailable until a real portfolio data source is connected.':
        'Indisponible tant qu’une source réelle de portefeuille n’est pas connectée.',
    'Prioritize assets in your watchlist.':
        'Donner la priorité aux actifs de votre liste de suivi.',
    'Choose how prices are displayed.':
        'Choisissez le mode d’affichage des prix.',
    'Auto follows the selected language. You can override it manually.':
        'Le mode automatique suit la langue choisie, mais vous pouvez le modifier.',
    'More currencies': 'Autres devises',
    'Choose another supported currency.':
        'Choisissez une autre devise prise en charge.',
    'Japanese Yen': 'Yen japonais',
    'Russian Ruble': 'Rouble russe',
    'Local save, cloud preparation and retention':
        'Sauvegarde locale, préparation cloud et conservation',
    'Save profile and settings changes automatically.':
        'Enregistrer automatiquement les modifications.',
    'Select the default destination after login.':
        'Choisissez la page par défaut après connexion.',
    'Local data retention': 'Conservation des données locales',
    'Choose how long local history is kept.':
        'Choisissez la durée de conservation de l’historique.',
    'Lock, analytics and diagnostic data':
        'Verrouillage, analyses et diagnostics',
    'Capture Flutter and Dart errors and show them in notifications.':
        'Capturer les erreurs Flutter et Dart et les afficher.',
    'Quick overview': 'Aperçu rapide',
    'Current configuration': 'Configuration actuelle',
    'English': 'Français',
    'Settings restored and saved.':
        'Les paramètres ont été restaurés et enregistrés.',
    'Need help?': 'Besoin d’aide ?',
    'Public support': 'Assistance publique',
    'Developer contact': 'Contacter le développeur',
    'Email copied': 'Adresse e-mail copiée',
    'COMING SOON': 'BIENTÔT',
    'PLANNED': 'PRÉVU',
    'Off': 'Désactivé',
    'Active': 'Actif',
    'Markets, news and artificial intelligence in one neural command center.':
        'Marchés, actualités et intelligence artificielle dans un centre unique.',
    'Already registered? Sign in': 'Déjà inscrit ? Se connecter',
    'Continue as guest (local only)':
        'Continuer comme invité (local uniquement)',
    'CREATE ACCOUNT': 'CRÉER UN COMPTE',
    'Create your account': 'Créez votre compte',
    'Email address': 'Adresse e-mail',
    'Enter a valid email address.': 'Saisissez une adresse e-mail valide.',
    'Enter the GoldBrain intelligence network.':
        'Entrez dans le réseau intelligent GoldBrain.',
    'Enter your full name.': 'Saisissez votre nom complet.',
    'Full name': 'Nom complet',
    'No account? Create one': 'Pas de compte ? Créez-en un',
    'Password': 'Mot de passe',
    'Confirm password': 'Confirmer le mot de passe',
    'Please re-enter your password.':
        'Veuillez saisir à nouveau votre mot de passe.',
    'Passwords do not match.': 'Les mots de passe ne correspondent pas.',
    'Password must contain at least 8 characters.':
        'Le mot de passe doit comporter au moins 8 caractères.',
    'Account created. Confirm the email we sent, then sign in.':
        'Compte créé. Confirmez l’e-mail envoyé, puis connectez-vous.',
    'Could not reach the login service. Check the network and try again.':
        'Service de connexion inaccessible. Vérifiez le réseau et réessayez.',
    'Email or password is incorrect, or the email is not confirmed.':
        'L’e-mail ou le mot de passe est incorrect, ou l’e-mail n’est pas confirmé.',
    'Real login is not configured. Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY before launch.':
        'La connexion réelle n’est pas configurée. Définissez SUPABASE_URL et SUPABASE_PUBLISHABLE_KEY avant le lancement.',
    'Too many attempts. Please wait and try again.':
        'Trop de tentatives. Patientez puis réessayez.',
    'Unexpected authentication error. Please try again.':
        'Erreur d’authentification inattendue. Réessayez.',
    'Welcome back': 'Bon retour',
    'YOUR INTELLIGENCE. AMPLIFIED.': 'VOTRE INTELLIGENCE, AMPLIFIÉE.',
    'Portfolio is not available yet':
        'Le portefeuille n’est pas encore disponible',
    'Coming in a future update; the internal gateway has not been built yet.':
        'Prévu dans une future mise à jour ; la passerelle interne n’existe pas encore.',
    'DISABLED · ROADMAP': 'DÉSACTIVÉ · FEUILLE DE ROUTE',
    'No sample balances, returns or portfolio signals are displayed.':
        'Aucun solde, rendement ou signal de démonstration n’est affiché.',
    'Profile & Identity': 'Profil et identité',
    'Manage personal information and account preferences.':
        'Gérez vos informations personnelles et préférences.',
    'Display name': 'Nom affiché',
    'Phone number': 'Numéro de téléphone',
    'Choose Image': 'Choisir une image',
    'Remove Image': 'Supprimer l’image',
    'Save Changes': 'Enregistrer',
    'Saving...': 'Enregistrement...',
    'Account status': 'État du compte',
    'Verified': 'Vérifié',
    'Local profile': 'Profil local',
    'Active theme': 'Thème actif',
    'Theme': 'Thème',
    'AI profile': 'Profil IA',
    'Learning mode': 'Mode apprentissage',
    'Cloud sync': 'Synchronisation cloud',
    'The selected image could not be opened.':
        'L’image sélectionnée n’a pas pu être ouverte.',
    'The selected image file was not found.':
        'Le fichier image sélectionné est introuvable.',
    'An error occurred while saving the image.':
        'Une erreur est survenue pendant l’enregistrement.',
    'Profile image saved successfully.': 'Image de profil enregistrée.',
    'Profile image removed.': 'Image de profil supprimée.',
    'Please enter your display name.': 'Saisissez votre nom affiché.',
    'Please enter a valid email address.':
        'Saisissez une adresse e-mail valide.',
    'Profile changes saved locally.':
        'Modifications du profil enregistrées localement.',
    'Profile changes could not be saved.':
        'Impossible d’enregistrer les modifications du profil.',
    'Your profile information has been saved successfully.':
        'Vos informations de profil ont été enregistrées.',
    'Profile Updated': 'Profil mis à jour',
    'Later, GoldBrain will use your preferences, watchlist and portfolio to personalize analysis.':
        'GoldBrain utilisera ensuite vos préférences, votre liste de suivi et votre portefeuille pour personnaliser l’analyse.',
    'Track selected assets and prepare them for GoldBrain AI analysis.':
        'Suivez les actifs sélectionnés et préparez-les pour l’analyse GoldBrain.',
    'WATCHLIST OVERVIEW': 'APERÇU DE LA LISTE DE SUIVI',
    'Live prices, charts, news and prediction models will later analyze every favorite asset here.':
        'Les prix, graphiques, actualités et modèles analyseront ici chaque actif favori.',
    'No sourced quote is currently available. GoldBrain will not manufacture an AI score or price.':
        'Aucun cours sourcé n’est disponible. GoldBrain n’inventera ni score IA ni prix.',
    'What GoldBrain does': 'Ce que fait GoldBrain',
    'A transparent information workspace':
        'Un espace d’information transparent',
    'The people behind GoldBrain': 'L’équipe derrière GoldBrain',
    'Creators': 'Créateurs',
    'Product creator & developer': 'Créateur du produit et développeur',
    'Co-creator': 'Co-créateur',
    'Risk notice & roadmap':
        'Avertissement sur les risques et feuille de route',
    'No guaranteed return or accuracy claim':
        'Aucune garantie de rendement ou de précision',
    'Support and official contact channels':
        'Assistance et canaux de contact officiels',
    'Official network': 'Réseau officiel',
    'Direct contact': 'Contact direct',
    'Ownership & copyright': 'Propriété et droits d’auteur',
    'Official GoldBrain ownership notice':
        'Avis officiel de propriété GoldBrain',
    'Designed and developed in Iran': 'Conçu et développé en Iran',
    'Intelligence for a clearer financial future':
        'L’intelligence pour un avenir financier plus clair',
    'Tap any card to open it in your browser.':
        'Touchez une carte pour l’ouvrir dans le navigateur.',
    'Could not open this link.': 'Impossible d’ouvrir ce lien.',
    'GoldBrain brings sourced market prices and sourced news together, then provides AI-assisted analysis of that information. Every available source and timestamp should remain visible to the user.':
        'GoldBrain réunit des prix et des actualités sourcés, puis fournit une analyse assistée par IA en conservant les sources et horodatages visibles.',
    'Market data can be delayed or incorrect, and AI output can contain errors. GoldBrain does not provide investment advice or guarantee profit. Financial decisions may result in loss.':
        'Les données peuvent être retardées ou erronées et l’IA peut se tromper. GoldBrain ne fournit aucun conseil financier ni garantie de gain.',
    'In-app purchases are only a future roadmap item. No internal payment gateway has been implemented.':
        'Les achats intégrés sont uniquement prévus ; aucune passerelle de paiement interne n’est en place.',
    'GoldBrain belongs to Bardia and Armiya Alizadeh (Kabir). Unauthorized copying, redistribution, modification for resale, or illegal sale is prohibited. This application is made in Iran.':
        'GoldBrain appartient à Bardia et Armiya Alizadeh (Kabir). Toute copie, redistribution ou revente non autorisée est interdite. Cette application est créée en Iran.',
    'Bardiya Alizadeh, known as Kabir':
        'Bardiya Alizadeh, connu sous le nom de Kabir',
    'Armiya Alizadeh, known as Kabir':
        'Armiya Alizadeh, connu sous le nom de Kabir',
    '12-hour gold outlook': 'Prévision de l’or sur 12 heures',
    '12-hour scenario target': 'Objectif du scénario à 12 heures',
    '1H': '1 H',
    '24H': '24 H',
    '7D': '7 J',
    'A target is hidden because there is not enough exact, verified history for this instrument.':
        'L’objectif est masqué faute d’un historique précis et vérifié suffisant.',
    'AI forecasts can be wrong and capital can be lost. The final decision and responsibility are yours.':
        'Les prévisions IA peuvent être erronées et entraîner des pertes. La décision finale vous appartient.',
    'AI key not configured': 'Clé IA non configurée',
    'AI Market Conversation': 'Conversation IA sur le marché',
    'AI scenario': 'Scénario IA',
    'AI signals are disabled in Settings.':
        'Les signaux IA sont désactivés dans les paramètres.',
    'AI translated': 'Traduit par IA',
    'AI translations and summaries may contain mistakes. The publisher original is authoritative. This content is informational and not investment advice.':
        'Les traductions et résumés IA peuvent contenir des erreurs. Le texte original fait autorité ; ce contenu n’est pas un conseil financier.',
    'An unexpected error occurred. Please try again.':
        'Une erreur inattendue est survenue. Réessayez.',
    'Analyzing verified data…': 'Analyse des données vérifiées…',
    'Ask about gold, currency, economy and market news.':
        'Posez vos questions sur l’or, les devises, l’économie et les marchés.',
    'Ask GoldBrain something...': 'Posez une question à GoldBrain...',
    'ASSISTANT CORE': 'CŒUR DE L’ASSISTANT',
    'Cancel': 'Annuler',
    'Change the search text or category.':
        'Modifiez la recherche ou la catégorie.',
    'Check the internet connection. The app never inserts fabricated content.':
        'Vérifiez la connexion Internet. L’application n’insère jamais de contenu inventé.',
    'Clear all conversations': 'Effacer toutes les conversations',
    'Clear all conversations?': 'Effacer toutes les conversations ?',
    'Close notifications': 'Fermer les notifications',
    'Configure GAPGPT_API_KEY, then run the analysis.':
        'Configurez GAPGPT_API_KEY, puis lancez l’analyse.',
    'Connected': 'Connecté',
    'Connection failed': 'Échec de la connexion',
    'Conversation name': 'Nom de la conversation',
    'Delete': 'Supprimer',
    'Delete conversation': 'Supprimer la conversation',
    'Delete conversation?': 'Supprimer la conversation ?',
    'Upward scenario': 'Scénario haussier',
    'Downward scenario': 'Scénario baissier',
    'Mixed scenario': 'Scénario mitigé',
    'Evidence-based 12-hour gold scenario':
        'Scénario de l’or à 12 heures fondé sur les données',
    'Evidence-based AI scenario': 'Scénario IA fondé sur les données',
    'Generate summary': 'Générer le résumé',
    'Generated only when requested. The summary is based on the publisher text above.':
        'Généré uniquement sur demande à partir du texte de l’éditeur.',
    'GoldBrain combines sourced prices, charts and news for a 12-hour scenario.':
        'GoldBrain combine prix, graphiques et actualités sourcés pour un scénario sur 12 heures.',
    'GOLDBRAIN DEEP ANALYST': 'ANALYSTE APPROFONDI GOLDBRAIN',
    'GoldBrain system messages': 'Messages système GoldBrain',
    'Hello, I am GoldBrain. Ask me about this application, sourced market prices, gold, currencies, or financial news.':
        'Bonjour, je suis GoldBrain. Interrogez-moi sur l’application, les prix sourcés, l’or, les devises ou l’actualité financière.',
    'IMPORTANT': 'IMPORTANT',
    'Iranian Financial News': 'Actualités financières iraniennes',
    'just now': 'à l’instant',
    'LATEST RELEASES': 'DERNIÈRES ACTUALITÉS',
    'Loading the official feed...': 'Chargement du flux officiel...',
    'LOCAL MODE': 'MODE LOCAL',
    'Mark all read': 'Tout marquer comme lu',
    'MIXED SCENARIO': 'SCÉNARIO MIXTE',
    'Needs setup': 'Configuration requise',
    'Neural analysis engine': 'Moteur d’analyse neuronale',
    'New conversation': 'Nouvelle conversation',
    'New notification': 'Nouvelle notification',
    'Newest first • automatic refresh every 5 minutes':
        'Plus récentes d’abord • actualisation toutes les 5 minutes',
    'No matching official release':
        'Aucune actualité officielle correspondante',
    'No sample article is shown while real data is loading.':
        'Aucun article fictif n’est affiché pendant le chargement.',
    'No valid release was returned': 'Aucune actualité valide reçue',
    'NO VERIFIED SCENARIO': 'AUCUN SCÉNARIO VÉRIFIÉ',
    'Not a buy/sell order. The estimate is uncalibrated, may be wrong, and loss is possible.':
        'Ce n’est pas un ordre d’achat ou de vente. L’estimation n’est pas calibrée et une perte est possible.',
    'Notification Settings': 'Paramètres des notifications',
    'Notifications are disabled in Settings.':
        'Les notifications sont désactivées.',
    'Official news is currently unavailable':
        'Les actualités officielles sont indisponibles',
    'Only fields returned by the named provider are shown. High, low, volume and market cap are intentionally omitted when unavailable.':
        'Seuls les champs fournis par la source sont affichés ; les valeurs indisponibles sont omises.',
    'Open original article': 'Ouvrir l’article original',
    'Press the button to analyze current prices, charts and news.':
        'Appuyez sur le bouton pour analyser les prix, graphiques et actualités.',
    'Ready to send': 'Prêt à envoyer',
    'Receiving response': 'Réception de la réponse',
    'Refresh analysis': 'Actualiser l’analyse',
    'Refresh later. No placeholder news was inserted.':
        'Actualisez plus tard. Aucune actualité fictive n’a été insérée.',
    'Refresh now': 'Actualiser',
    'Refresh prices': 'Actualiser les prix',
    'Regenerate': 'Régénérer',
    'Rename conversation': 'Renommer la conversation',
    'Retry real AI translation': 'Réessayer la traduction IA',
    'Save': 'Enregistrer',
    'Saved conversations': 'Conversations enregistrées',
    'Search real news...': 'Rechercher dans les actualités...',
    'Set GAPGPT_API_KEY to enable the 12-hour analysis.':
        'Définissez GAPGPT_API_KEY pour activer l’analyse sur 12 heures.',
    'Source feed information': 'Informations sur la source',
    'Sourced prices and recent news are both required.':
        'Des prix sourcés et des actualités récentes sont nécessaires.',
    'START DEEP ANALYSIS': 'LANCER L’ANALYSE APPROFONDIE',
    'Startup': 'Démarrage',
    'The AI connection timed out. Check the network and try again.':
        'La connexion IA a expiré. Vérifiez le réseau et réessayez.',
    'The AI key is not configured. Set GAPGPT_API_KEY before starting GoldBrain.':
        'La clé IA n’est pas configurée. Définissez GAPGPT_API_KEY avant GoldBrain.',
    'The AI key was rejected. Rotate it and check the configuration.':
        'La clé IA a été refusée. Renouvelez-la et vérifiez la configuration.',
    'The AI provider returned an incomplete answer. Please send the message again.':
        'Le fournisseur IA a renvoyé une réponse incomplète. Renvoyez le message.',
    'The AI request limit has been reached. Please try again later.':
        'La limite de requêtes IA est atteinte. Réessayez plus tard.',
    'The AI service is temporarily unreachable. Check your internet connection and the provider status, then try again. GoldBrain also detects an enabled Windows system proxy automatically.':
        'Le service IA est temporairement inaccessible. Vérifiez Internet et l’état du fournisseur puis réessayez.',
    'The analysis could not be completed. Check the network and retry.':
        'L’analyse n’a pas pu être terminée. Vérifiez le réseau et réessayez.',
    'The displayed percentage is an uncalibrated AI scenario estimate, not a statistical guarantee. Forecasts can be wrong, capital can be lost, and the final decision is yours.':
        'Le pourcentage affiché est une estimation IA non calibrée, sans garantie statistique. La prévision peut être fausse et la décision vous appartient.',
    'The latest refresh failed. Previously verified news is still shown.':
        'La dernière actualisation a échoué ; les actualités vérifiées précédentes restent affichées.',
    'The official source information page could not be opened.':
        'Impossible d’ouvrir la page d’information de la source.',
    'The original article could not be opened.':
        'Impossible d’ouvrir l’article original.',
    'The providers returned no usable points. Try again.':
        'Les fournisseurs n’ont renvoyé aucune donnée exploitable. Réessayez.',
    'The selected AI model is unavailable. Choose another model or configure GAPGPT_FALLBACK_MODELS and try again.':
        'Le modèle IA choisi est indisponible. Choisissez-en un autre ou configurez GAPGPT_FALLBACK_MODELS.',
    'This removes the local chat history from this device.':
        'Cela supprime l’historique local des conversations.',
    'Translating...': 'Traduction...',
    'Translation is unavailable; original publisher text is shown.':
        'Traduction indisponible ; le texte original est affiché.',
    'Try again': 'Réessayer',
    'UPWARD SCENARIO': 'SCÉNARIO HAUSSIER',
    'Validated 12-hour scenario target':
        'Objectif de scénario à 12 heures validé',
    'Verified global gold history · XAU':
        'Historique mondial vérifié de l’or · XAU',
    'Verified gold history is unavailable':
        'L’historique vérifié de l’or est indisponible',
    'View publisher original': 'Voir le texte original',
    'Waiting for sufficient evidence': 'En attente de données suffisantes',
  };

  static const Map<String, String> _simplifiedChinese = {
    'Choose your GoldBrain experience': '选择您的 GoldBrain 体验',
    'You can change these settings later': '您以后可以在设置中更改这些选项',
    'COLOR THEME': '颜色主题',
    'APPLICATION LANGUAGE': '应用语言',
    'ENTER GOLDBRAIN': '进入 GOLDBRAIN',
    'Application Settings': '应用设置',
    'Control appearance, alerts, sound, privacy and GoldBrain AI.':
        '管理外观、提醒、声音、隐私和 GoldBrain AI。',
    'Appearance': '外观',
    'Layout and display density': '布局和显示密度',
    'Color theme': '颜色主题',
    'Choose one of the four GoldBrain color systems.': '选择一种 GoldBrain 配色方案。',
    'Choose one of the six GoldBrain color systems.':
        '从六种 GoldBrain 配色方案中选择一种。',
    'Choose one of the eleven GoldBrain color systems.':
        '从十一种 GoldBrain 配色方案中选择一种。',
    'Application language': '应用语言',
    'Change the language without returning to the welcome screen.':
        '无需返回欢迎页面即可更改语言。',
    'Interface density': '界面密度',
    'Choose spacing between interface elements.': '选择界面元素之间的间距。',
    'Compact': '紧凑',
    'Comfortable': '舒适',
    'Spacious': '宽松',
    'Animation controls will be added in a future update.': '动画控制将在后续更新中加入。',
    'Notifications & alerts': '通知和提醒',
    'Market, news and AI notifications': '市场、新闻和 AI 通知',
    'Master notifications': '总通知开关',
    'Turn all notifications on or off.': '开启或关闭全部通知。',
    'Price alerts': '价格提醒',
    'Coming with the portfolio and target-price feature.': '将随资产组合和目标价格功能一起提供。',
    'Planned with portfolio · Off': '随资产组合规划 · 已关闭',
    'Alert when an asset crosses its target.': '资产价格达到目标时提醒。',
    'Breaking news': '突发新闻',
    'Notify important financial news.': '推送重要财经新闻。',
    'AI signals': 'AI 信号',
    'Notify strong AI confidence signals.': '推送高置信度 AI 信号。',
    'Sound': '声音',
    'Interface feedback and audio behavior': '界面反馈和音频行为',
    'Application sound': '应用声音',
    'Allow interface sounds.': '允许播放界面音效。',
    'Background music': '背景音乐',
    'Play ambient GoldBrain music while using the app.':
        '使用应用时播放 GoldBrain 背景音乐。',
    'Custom music playlist': '自定义音乐播放列表',
    'Choose several local tracks, select the current one and control playback order.':
        '选择多首本地音乐、当前曲目和播放顺序。',
    'Add files': '添加文件',
    'Use built-in': '使用内置音乐',
    'Use playlist': '使用播放列表',
    'Previous track': '上一首',
    'Next track': '下一首',
    'Select track': '选择曲目',
    'Current track': '当前曲目',
    'Remove from playlist': '从播放列表移除',
    'Clear playlist': '清空播放列表',
    'GoldBrain built-in music restored.': '已恢复 GoldBrain 内置音乐。',
    'Built-in GoldBrain music is active.': '正在使用 GoldBrain 内置音乐。',
    'Local audio could not be initialized.': '无法初始化本地音频。',
    'The custom music file is missing. Choose it again.': '自定义音乐文件不存在，请重新选择。',
    'This audio file could not be played.': '无法播放此音频文件。',
    'The playlist was saved, but this file could not be played.':
        '播放列表已保存，但无法播放此文件。',
    'The selected audio file could not be copied.': '无法复制所选音频文件。',
    'This audio format is not supported.': '不支持此音频格式。',
    'Each audio file must be smaller than 100 MB.': '每个音频文件必须小于 100 MB。',
    'Preview': '试听',
    'Stop': '停止',
    'Sequential': '顺序播放',
    'Shuffle': '随机播放',
    'Repeat one': '单曲循环',
    'Interface volume': '界面音量',
    'Adjust interface feedback volume.': '调整界面反馈音量。',
    'Personalized AI': '个性化 AI',
    'Adapt AI to your preferences.': '让 AI 适应您的偏好。',
    'Response tone': '回答风格',
    'Choose how GoldBrain explains information.': '选择 GoldBrain 的解释方式。',
    'Concise': '简洁',
    'Balanced': '均衡',
    'Detailed': '详细',
    'AI creativity': 'AI 创造力',
    'Higher values allow broader suggestions.': '数值越高，建议范围越广。',
    'Use market context': '使用市场上下文',
    'Let AI consider market screens.': '允许 AI 参考市场页面数据。',
    'Use portfolio context': '使用资产组合上下文',
    'Unavailable until a real portfolio data source is connected.':
        '连接真实资产组合数据源后才可使用。',
    'Use watchlist context': '使用自选列表上下文',
    'Prioritize assets in your watchlist.': '优先考虑自选列表中的资产。',
    'Currency': '货币',
    'Choose how prices are displayed.': '选择价格显示货币。',
    'Display currency': '显示货币',
    'Auto follows the selected language. You can override it manually.':
        '自动模式会跟随所选语言，也可以手动更改。',
    'More currencies': '更多货币',
    'Choose another supported currency.': '选择其他受支持的货币。',
    'Auto': '自动',
    'Toman': '伊朗土曼',
    'US Dollar': '美元',
    'Euro': '欧元',
    'Japanese Yen': '日元',
    'Russian Ruble': '俄罗斯卢布',
    'British Pound': '英镑',
    'Chinese Yuan': '人民币',
    'Data & storage': '数据和存储',
    'Local save, cloud preparation and retention': '本地保存、云端准备和保留期限',
    'Automatic local save': '自动本地保存',
    'Automatic saving of local changes': '自动保存本地更改',
    'PAUSED': '已暂停',
    'Local storage is paused by the retention policy. Choose Forever before adding music.':
        '本地存储已按保留策略暂停。添加音乐前请选择“永久”。',
    'Local storage is paused. Choose Forever in data retention before adding an image.':
        '本地存储已暂停。添加图片前请在数据保留中选择“永久”。',
    'Save profile and settings changes automatically.': '自动保存个人资料和设置更改。',
    'Startup page': '启动页面',
    'Select the default destination after login.': '选择登录后的默认页面。',
    'Dashboard': '仪表板',
    'Markets': '市场',
    'AI Assistant': 'AI 助手',
    'Local data retention': '本地数据保留',
    'Choose how long local history is kept.': '选择本地历史记录的保留时间。',
    '30 days': '30 天',
    '90 days': '90 天',
    'Forever': '永久',
    'Security & privacy': '安全与隐私',
    'Lock, analytics and diagnostic data': '应用锁、分析和诊断数据',
    'Crash reports': '崩溃报告',
    'Capture Flutter and Dart errors and show them in notifications.':
        '捕获 Flutter 和 Dart 错误并在通知中显示。',
    'Quick overview': '快速概览',
    'Current configuration': '当前配置',
    'Language': '语言',
    'English': '简体中文',
    'Notifications': '通知',
    'Enabled': '已启用',
    'Disabled': '已禁用',
    'Muted': '静音',
    'Save settings': '保存设置',
    'Restore defaults': '恢复默认设置',
    'Settings saved successfully.': '设置已成功保存。',
    'Settings restored and saved.': '默认设置已恢复并保存。',
    'Need help?': '需要帮助？',
    'Public support': '公共支持',
    'Developer contact': '联系开发者',
    'Email copied': '邮箱已复制',
    'Unavailable': '不可用',
    'COMING SOON': '即将推出',
    'PLANNED': '计划中',
    'Off': '关闭',
    'Active': '已启用',
    'Markets, news and artificial intelligence in one neural command center.':
        '在一个智能中枢中查看市场、新闻和人工智能。',
    'Already registered? Sign in': '已有账户？登录',
    'Continue as guest (local only)': '以访客身份继续（仅本地）',
    'CREATE ACCOUNT': '创建账户',
    'Create your account': '创建您的账户',
    'Email address': '电子邮箱',
    'Enter a valid email address.': '请输入有效的电子邮箱。',
    'Enter the GoldBrain intelligence network.': '进入 GoldBrain 智能网络。',
    'Enter your full name.': '请输入您的姓名。',
    'Full name': '姓名',
    'No account? Create one': '没有账户？立即创建',
    'Password': '密码',
    'Confirm password': '确认密码',
    'Please re-enter your password.': '请再次输入密码。',
    'Passwords do not match.': '两次输入的密码不一致。',
    'Password must contain at least 8 characters.': '密码至少需要 8 个字符。',
    'Account created. Confirm the email we sent, then sign in.':
        '账户已创建。请确认我们发送的邮件，然后登录。',
    'Could not reach the login service. Check the network and try again.':
        '无法连接登录服务，请检查网络后重试。',
    'Email or password is incorrect, or the email is not confirmed.':
        '邮箱或密码错误，或邮箱尚未确认。',
    'Real login is not configured. Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY before launch.':
        '尚未配置真实登录。启动前请设置 SUPABASE_URL 和 SUPABASE_PUBLISHABLE_KEY。',
    'Too many attempts. Please wait and try again.': '尝试次数过多，请稍后重试。',
    'Unexpected authentication error. Please try again.': '发生意外的身份验证错误，请重试。',
    'Welcome back': '欢迎回来',
    'YOUR INTELLIGENCE. AMPLIFIED.': '让您的智慧更强大。',
    'Portfolio is not available yet': '资产组合功能尚未开放',
    'Coming in a future update; the internal gateway has not been built yet.':
        '该功能将在后续更新中推出；内部网关尚未构建。',
    'DISABLED · ROADMAP': '已禁用 · 开发计划',
    'No sample balances, returns or portfolio signals are displayed.':
        '不会显示虚拟余额、收益或资产组合信号。',
    'Profile & Identity': '个人资料与身份',
    'Manage personal information and account preferences.': '管理个人信息和账户偏好。',
    'Neural Account': '智能账户',
    'Display name': '显示名称',
    'Phone number': '电话号码',
    'Choose Image': '选择图片',
    'Remove Image': '移除图片',
    'Save Changes': '保存更改',
    'Saving...': '正在保存…',
    'Account status': '账户状态',
    'Verified': '已验证',
    'Local profile': '本地个人资料',
    'Active theme': '当前主题',
    'Theme': '主题',
    'AI profile': 'AI 配置',
    'Learning mode': '学习模式',
    'Cloud sync': '云同步',
    'Not connected': '未连接',
    'GoldBrain User': 'GoldBrain 用户',
    'The selected image could not be opened.': '无法打开所选图片。',
    'The selected image file was not found.': '找不到所选图片文件。',
    'An error occurred while saving the image.': '保存图片时发生错误。',
    'Profile image saved successfully.': '个人资料图片已成功保存。',
    'Profile image removed.': '个人资料图片已移除。',
    'Please enter your display name.': '请输入显示名称。',
    'Please enter a valid email address.': '请输入有效的电子邮箱。',
    'Profile changes saved locally.': '个人资料更改已保存到本地。',
    'Profile changes could not be saved.': '无法保存个人资料更改。',
    'Your profile information has been saved successfully.': '您的个人资料已成功保存。',
    'Profile Updated': '个人资料已更新',
    'Later, GoldBrain will use your preferences, watchlist and portfolio to personalize analysis.':
        '未来，GoldBrain 将根据您的偏好、自选列表和资产组合提供个性化分析。',
    'Smart Watchlist': '智能自选列表',
    'Track selected assets and prepare them for GoldBrain AI analysis.':
        '跟踪选定资产，并为 GoldBrain AI 分析准备数据。',
    'Search an asset...': '搜索资产…',
    'All': '全部',
    'Metals': '贵金属',
    'Crypto': '加密货币',
    'No asset found': '未找到资产',
    'Sourced live quotes': '有来源的实时行情',
    'LIVE QUOTES': '实时行情',
    'NO DATA': '暂无数据',
    'Positive movement': '上涨走势',
    'Close': '关闭',
    'FAVORITES': '自选资产',
    'WATCHLIST OVERVIEW': '自选列表概览',
    'GoldBrain Analysis Pipeline': 'GoldBrain 分析流程',
    'Live prices, charts, news and prediction models will later analyze every favorite asset here.':
        '未来将结合实时价格、图表、新闻和预测模型分析每项自选资产。',
    'No sourced quote is currently available. GoldBrain will not manufacture an AI score or price.':
        '当前没有可验证来源的行情。GoldBrain 不会虚构 AI 分数或价格。',
    'What GoldBrain does': 'GoldBrain 的功能',
    'A transparent information workspace': '透明的信息工作空间',
    'The people behind GoldBrain': 'GoldBrain 创作者',
    'Creators': '创作者',
    'Product creator & developer': '产品创作者与开发者',
    'Co-creator': '联合创作者',
    'Risk notice & roadmap': '风险提示与开发计划',
    'No guaranteed return or accuracy claim': '不保证收益或预测准确性',
    'Support and official contact channels': '支持与官方联系方式',
    'Official network': '官方网络',
    'Direct contact': '直接联系',
    'Ownership & copyright': '所有权与版权',
    'Official GoldBrain ownership notice': 'GoldBrain 官方所有权声明',
    'Designed and developed in Iran': '在伊朗设计与开发',
    'Intelligence for a clearer financial future': '以智能洞察更清晰的金融未来',
    'Tap any card to open it in your browser.': '点击任意卡片即可在浏览器中打开。',
    'Could not open this link.': '无法打开此链接。',
    'GoldBrain brings sourced market prices and sourced news together, then provides AI-assisted analysis of that information. Every available source and timestamp should remain visible to the user.':
        'GoldBrain 汇集有来源的市场价格和新闻，并对这些信息进行 AI 辅助分析。所有可用来源和时间戳都应向用户展示。',
    'Market data can be delayed or incorrect, and AI output can contain errors. GoldBrain does not provide investment advice or guarantee profit. Financial decisions may result in loss.':
        '市场数据可能延迟或不准确，AI 输出也可能出错。GoldBrain 不提供投资建议，也不保证收益；金融决策可能造成损失。',
    'In-app purchases are only a future roadmap item. No internal payment gateway has been implemented.':
        '应用内购买仅属于未来开发计划，目前尚未实现内部支付网关。',
    'GoldBrain belongs to Bardia and Armiya Alizadeh (Kabir). Unauthorized copying, redistribution, modification for resale, or illegal sale is prohibited. This application is made in Iran.':
        'GoldBrain 归 Bardia Alizadeh 与 Armiya Alizadeh（Kabir）所有。禁止未经授权的复制、再分发、修改转售或非法销售。本应用在伊朗制作。',
    'Bardiya Alizadeh, known as Kabir': 'Bardiya Alizadeh（Kabir）',
    'Armiya Alizadeh, known as Kabir': 'Armiya Alizadeh（Kabir）',
  };
}
