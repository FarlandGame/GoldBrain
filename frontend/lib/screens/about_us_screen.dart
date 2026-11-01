import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_translations.dart';
import '../core/motion_preferences.dart';
import '../core/settings_store.dart';
import 'selection_screen.dart';

class AboutUsScreen extends StatefulWidget {
  const AboutUsScreen({
    super.key,
    required this.palette,
    required this.selectedLanguage,
  });

  final ThemePalette palette;
  final GoldBrainLanguage selectedLanguage;

  @override
  State<AboutUsScreen> createState() => _AboutUsScreenState();
}

class _AboutUsScreenState extends State<AboutUsScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _ambientController;
  bool _reducedMotion = false;

  ThemePalette get palette => widget.palette;

  static const _linkGroups = <String>[
    "بردیا (farland_game) — ویدیو و پخش زنده",
    "بردیا (farland_game) — شبکه‌های اجتماعی",
    "بردیا (farland_game) — THE APEX و Minehunt",
    "بردیا (farland_game) — موسیقی، حمایت و کد",
    "ارمیا — کانال رسمی",
  ];

  static const _links = <_SocialLink>[
    _SocialLink(
      "یوتیوب · Farland Game",
      "https://www.youtube.com/@Farland_game",
      Icons.smart_display_rounded,
      0,
    ),
    _SocialLink(
      "یوتیوب دوم · Farland Animation",
      "https://www.youtube.com/@Farland_animation",
      Icons.movie_creation_outlined,
      0,
    ),
    _SocialLink(
      "توییچ · Farland Game",
      "https://twitch.tv/farlandgame",
      Icons.live_tv_rounded,
      0,
    ),
    _SocialLink(
      "کیک · Farland Game",
      "https://kick.com/farlandgame",
      Icons.play_circle_outline_rounded,
      0,
    ),
    _SocialLink(
      "آپارات · Farland Game",
      "https://aparat.com/Farland_Game",
      Icons.ondemand_video_rounded,
      0,
    ),
    _SocialLink(
      "کانال روبیکا · Farland Game",
      "https://rubika.ir/farland_gam",
      Icons.forum_outlined,
      1,
    ),
    _SocialLink(
      "کانال دوم روبیکا · Farland Animation",
      "https://rubika.ir/Farland_animatio",
      Icons.animation_rounded,
      1,
    ),
    _SocialLink(
      "صفحه روبیکا · Farland Game",
      "https://rubika.ir/farland_game",
      Icons.person_outline_rounded,
      1,
    ),
    _SocialLink(
      "صفحه دوم روبیکا · Farland Animations",
      "https://rubika.ir/Farland_animations",
      Icons.auto_awesome_rounded,
      1,
    ),
    _SocialLink(
      "اینستاگرام · Farland Game",
      "https://www.instagram.com/farland_game",
      Icons.camera_alt_outlined,
      1,
    ),
    _SocialLink(
      "کانال تلگرام · Farland Game",
      "https://t.me/Farland_gam",
      Icons.send_rounded,
      1,
    ),
    _SocialLink(
      "کانال دوم تلگرام · Farland Animation",
      "https://t.me/Farland_animatio",
      Icons.send_outlined,
      1,
    ),
    _SocialLink(
      "یوتیوب · THE APEX",
      "https://www.youtube.com/@THE_APEX_MC",
      Icons.smart_display_rounded,
      2,
    ),
    _SocialLink(
      "کانال تلگرام · THE APEX",
      "https://t.me/+-3uY7eIZArVjZDE0",
      Icons.send_rounded,
      2,
    ),
    _SocialLink(
      "گروه تلگرام · Minehunt",
      "https://t.me/+DAq20XrkPyZhNjVk",
      Icons.groups_2_outlined,
      2,
    ),
    _SocialLink(
      "ربات موسیقی تلگرام",
      "https://t.me/Farland_Music_bot",
      Icons.music_note_rounded,
      3,
      caption:
          "اگه می‌خوای هر موسیقی رو پیدا کنی، بیا تو ربات تلگرامی ما و لینک ویدیوش رو بفرست.",
    ),
    _SocialLink(
      "ساندکلاد · بردیا",
      "https://soundcloud.com/bardiya-kabir-798008614",
      Icons.headphones_rounded,
      3,
    ),
    _SocialLink(
      "حمایت مالی · ریمیت",
      "https://reymit.ir/farland_game",
      Icons.volunteer_activism_rounded,
      3,
    ),
    _SocialLink(
      "گیت‌هاب · FarlandGame",
      "https://github.com/FarlandGame",
      Icons.code_rounded,
      3,
    ),
    _SocialLink(
      "یوتیوب · ارمیا (Armiya Fabix)",
      "https://www.youtube.com/@ArmiyaFabix",
      Icons.video_library_outlined,
      4,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: MotionPreferences.controllerDuration(760),
    );
    _ambientController = AnimationController(
      vsync: this,
      duration: MotionPreferences.controllerDuration(7600),
    );
    SettingsStore.instance.addListener(_handleMotionPreferenceChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configureMotion();
  }

  @override
  void dispose() {
    SettingsStore.instance.removeListener(_handleMotionPreferenceChange);
    _entranceController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  void _handleMotionPreferenceChange() {
    if (mounted) _configureMotion();
  }

  void _configureMotion() {
    final platformReducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final reduce = platformReducedMotion || !MotionPreferences.enabled;
    if (_reducedMotion != reduce) {
      _reducedMotion = reduce;
    }
    if (reduce) {
      _entranceController.value = 1;
      _ambientController
        ..stop()
        ..value = 0;
      return;
    }
    if (!_entranceController.isCompleted && !_entranceController.isAnimating) {
      _entranceController.forward();
    }
    if (!_ambientController.isAnimating) _ambientController.repeat();
  }

  String tr(String en, String fa, String ja, String ru) {
    switch (widget.selectedLanguage) {
      case GoldBrainLanguage.persian:
        return fa;
      case GoldBrainLanguage.japanese:
        return ja;
      case GoldBrainLanguage.russian:
        return ru;
      case GoldBrainLanguage.chinese:
        return AppTranslations.simplifiedChinese(en);
      case GoldBrainLanguage.arabic:
        return AppTranslations.arabic(en);
      case GoldBrainLanguage.turkish:
        return AppTranslations.turkish(en);
      case GoldBrainLanguage.french:
        return AppTranslations.french(en);
      case GoldBrainLanguage.english:
        return en;
    }
  }

  Future<void> _open(String value) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(value),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Could not open this link.',
              'این لینک باز نشد.',
              'リンクを開けませんでした。',
              'Не удалось открыть ссылку.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _email(String address) {
    return _open(Uri(scheme: 'mailto', path: address).toString());
  }

  @override
  Widget build(BuildContext context) {
    final isRtl =
        widget.selectedLanguage == GoldBrainLanguage.persian ||
        widget.selectedLanguage == GoldBrainLanguage.arabic;
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _ambientController,
                  builder: (context, _) => CustomPaint(
                    painter: _AboutBackgroundPainter(
                      color: palette.primary,
                      progress: _ambientController.value,
                    ),
                  ),
                ),
              ),
            ),
          ),
          FadeTransition(
            opacity: CurvedAnimation(
              parent: _entranceController,
              curve: Curves.easeOutCubic,
            ),
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, .035),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: _entranceController,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _hero(),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 900) {
                        return Column(
                          children: [
                            _identityCard(),
                            const SizedBox(height: 14),
                            _contactCard(),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _identityCard()),
                          const SizedBox(width: 14),
                          Expanded(child: _contactCard()),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 900) {
                        return Column(
                          children: [
                            _missionCard(),
                            const SizedBox(height: 14),
                            _riskAndRoadmapCard(),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _missionCard()),
                          const SizedBox(width: 14),
                          Expanded(child: _riskAndRoadmapCard()),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _linksCard(),
                  const SizedBox(height: 16),
                  _legalCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero() {
    return _panel(
      padding: const EdgeInsets.all(28),
      child: Row(
        children: [
          RepaintBoundary(
            child: RotationTransition(
              turns: _ambientController,
              child: Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [
                      palette.primary,
                      palette.secondary,
                      palette.primary,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: palette.primary.withValues(alpha: .30),
                      blurRadius: 36,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(3),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.background,
                  ),
                  child: Icon(
                    Icons.psychology_alt_rounded,
                    color: palette.primary,
                    size: 42,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GOLDBRAIN',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: palette.primary,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 5,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  tr(
                    'Intelligence for a clearer financial future',
                    'هوشمندی برای آینده مالی شفاف‌تر',
                    'より明確な金融の未来へ',
                    'Интеллект для ясного финансового будущего',
                  ),
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    'Designed and developed in Iran',
                    'طراحی و توسعه‌ی ایران',
                    'イランで設計・開発',
                    'Разработано в Иране',
                  ),
                  style: TextStyle(color: palette.mutedText, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.primary.withValues(alpha: .25)),
            ),
            child: Text(
              'VERSION 1',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: palette.primary,
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _identityCard() {
    return _panel(
      child: _section(
        icon: Icons.groups_2_outlined,
        title: tr('Creators', 'سازندگان', 'クリエイター', 'Создатели'),
        subtitle: tr(
          'The people behind GoldBrain',
          'افراد سازنده GoldBrain',
          'GoldBrainの制作者',
          'Авторы GoldBrain',
        ),
        children: [
          _person(
            tr(
              'Bardia Alizadeh, known as Kabir',
              'بردیا علیزاده، ملقب به کبیر',
              'バルディヤ・アリザデ（通称カビール）',
              'Бардия Ализаде, известный как Кабир',
            ),
            tr(
              'Co-creator · 50% contribution · farland_game',
              'هم‌سازنده · مشارکت ۵۰٪ · farland_game',
              '共同制作者・貢献50%・farland_game',
              'Соавтор · вклад 50% · farland_game',
            ),
          ),
          const SizedBox(height: 10),
          _person(
            tr(
              'Armia Alizadeh, known as Kabir',
              'ارمیا علیزاده، ملقب به کبیر',
              'アルミヤ・アリザデ（通称カビール）',
              'Армия Ализаде, известный как Кабир',
            ),
            tr(
              'Co-creator · 50% contribution',
              'هم‌سازنده · مشارکت ۵۰٪',
              '共同制作者・貢献50%',
              'Соавтор · вклад 50%',
            ),
          ),
        ],
      ),
    );
  }

  Widget _missionCard() {
    return _panel(
      child: _section(
        icon: Icons.hub_rounded,
        title: tr(
          'What GoldBrain does',
          'GoldBrain چه کاری انجام می‌دهد؟',
          'GoldBrainの目的',
          'Что делает GoldBrain',
        ),
        subtitle: tr(
          'A transparent information workspace',
          'فضای کاری شفاف برای اطلاعات مالی',
          '透明性のある金融情報ワークスペース',
          'Прозрачное пространство финансовой информации',
        ),
        children: [
          Text(
            tr(
              'GoldBrain brings sourced market prices and sourced news together, then provides AI-assisted analysis of that information. Every available source and timestamp should remain visible to the user.',
              'هدف GoldBrain تجمیع قیمت‌های منبع‌دار بازار و خبرهای منبع‌دار و سپس ارائه تحلیل با کمک هوش مصنوعی است. هر منبع و زمان به‌روزرسانیِ موجود باید برای کاربر قابل مشاهده بماند.',
              'GoldBrainは、出典付きの市場価格とニュースを集約し、その情報をAIで補助分析します。利用可能な出典と更新時刻は常に表示します。',
              'GoldBrain объединяет рыночные цены и новости с указанием источников, а затем предлагает анализ с помощью ИИ. Доступные источники и время обновления должны оставаться видимыми.',
            ),
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 11,
              height: 1.75,
            ),
          ),
        ],
      ),
    );
  }

  Widget _riskAndRoadmapCard() {
    return _panel(
      child: _section(
        icon: Icons.shield_outlined,
        title: tr(
          'Risk notice & roadmap',
          'هشدار ریسک و نقشه راه',
          'リスク通知とロードマップ',
          'Риски и планы',
        ),
        subtitle: tr(
          'No guaranteed return or accuracy claim',
          'بدون ادعای سود یا دقت قطعی',
          '利益や精度を保証しません',
          'Без гарантий прибыли или точности',
        ),
        children: [
          Text(
            tr(
              'Market data can be delayed or incorrect, and AI output can contain errors. GoldBrain does not provide investment advice or guarantee profit. Financial decisions may result in loss.',
              'داده‌های بازار ممکن است با تأخیر یا خطا همراه باشند و پاسخ هوش مصنوعی نیز می‌تواند اشتباه باشد. GoldBrain توصیه سرمایه‌گذاری یا تضمین سود ارائه نمی‌کند و تصمیم‌های مالی ممکن است به زیان منجر شوند.',
              '市場データには遅延や誤りがあり、AIの出力も間違う可能性があります。GoldBrainは投資助言や利益保証を提供せず、金融判断には損失の可能性があります。',
              'Рыночные данные могут запаздывать или содержать ошибки, как и ответы ИИ. GoldBrain не является инвестиционной рекомендацией и не гарантирует прибыль; финансовые решения могут привести к убыткам.',
            ),
            style: TextStyle(color: palette.text, fontSize: 11, height: 1.7),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.primary.withValues(alpha: .16)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.route_outlined, color: palette.primary, size: 19),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    tr(
                      'In-app purchases are only a future roadmap item. No internal payment gateway has been implemented.',
                      'خرید درون‌برنامه‌ای فقط بخشی از نقشه راه آینده است و هنوز هیچ درگاه پرداخت داخلی پیاده‌سازی نشده است.',
                      'アプリ内購入は将来のロードマップ項目にすぎず、内部決済ゲートウェイはまだ実装されていません。',
                      'Внутренние покупки — только пункт будущего плана; встроенный платёжный шлюз ещё не реализован.',
                    ),
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 10,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactCard() {
    return _panel(
      child: _section(
        icon: Icons.alternate_email_rounded,
        title: tr('Direct contact', 'ارتباط مستقیم', 'お問い合わせ', 'Контакты'),
        subtitle: tr(
          'Support and official contact channels',
          'پشتیبانی و راه‌های ارتباط رسمی',
          'サポートと公式連絡先',
          'Поддержка и официальные контакты',
        ),
        children: [
          _contact(
            'bardiya15899000@gmail.com',
            Icons.support_agent_rounded,
            () => _email('bardiya15899000@gmail.com'),
          ),
          const SizedBox(height: 9),
          _contact(
            'farland.game@gmail.com',
            Icons.mail_outline_rounded,
            () => _email('farland.game@gmail.com'),
          ),
        ],
      ),
    );
  }

  Widget _linksCard() {
    return _panel(
      child: _section(
        icon: Icons.public_rounded,
        title: tr(
          'Official network',
          'شبکه رسمی ما',
          '公式ネットワーク',
          'Официальная сеть',
        ),
        subtitle: tr(
          'Tap any card to open it in your browser.',
          'برای بازکردن هر لینک روی کارت آن بزنید.',
          'カードをタップしてブラウザで開きます。',
          'Нажмите на карточку, чтобы открыть ссылку.',
        ),
        children: [
          for (var group = 0; group < _linkGroups.length; group++) ...[
            if (group > 0) const SizedBox(height: 17),
            Text(
              _linkGroups[group],
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: palette.text,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 1100
                    ? 4
                    : constraints.maxWidth > 700
                    ? 3
                    : constraints.maxWidth > 460
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 10) / columns;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _links
                      .where((link) => link.group == group)
                      .map(
                        (link) =>
                            SizedBox(width: width, child: _socialButton(link)),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _legalCard() {
    return _panel(
      child: _section(
        icon: Icons.verified_user_outlined,
        title: tr(
          'Ownership & copyright',
          'مالکیت و حقوق برنامه',
          '所有権と著作権',
          'Право собственности',
        ),
        subtitle: tr(
          'Official GoldBrain ownership notice',
          'اطلاعیه رسمی مالکیت GoldBrain',
          'GoldBrainの公式所有権表示',
          'Официальное уведомление GoldBrain',
        ),
        children: [
          Text(
            tr(
              'GoldBrain belongs to Bardia and Armiya Alizadeh (Kabir). Unauthorized copying, redistribution, modification for resale, or illegal sale is prohibited. This application is made in Iran.',
              'برنامه GoldBrain متعلق به بردیا و ارمیا علیزاده (کبیر) است. کپی، بازنشر، تغییر با هدف فروش یا فروش غیرقانونی آن بدون اجازه ممنوع است. این برنامه ساخت ایران است.',
              'GoldBrainはBardiyaとArmiya Alizadeh（Kabir）に帰属します。無断複製、再配布、転売目的の改変、不正販売は禁止されています。本アプリはイラン製です。',
              'GoldBrain принадлежит Бардии и Армии Ализаде (Кабир). Несанкционированное копирование, распространение, изменение для перепродажи и незаконная продажа запрещены. Приложение создано в Иране.',
            ),
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 11,
              height: 1.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: palette.primary, size: 24),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(color: palette.mutedText, fontSize: 9.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          ...children,
        ],
      ),
    );
  }

  Widget _person(String name, String role) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: palette.primary.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: palette.primary.withValues(alpha: .13)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: palette.primary.withValues(alpha: .16),
            child: Icon(Icons.person_rounded, color: palette.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  role,
                  style: TextStyle(color: palette.mutedText, fontSize: 9.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contact(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: palette.background.withValues(alpha: .38),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.primary.withValues(alpha: .13)),
        ),
        child: Row(
          textDirection: TextDirection.ltr,
          children: [
            Icon(icon, color: palette.primary, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.open_in_new_rounded, color: palette.mutedText, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _socialButton(_SocialLink link) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HoverLink(palette: palette, link: link, onTap: () => _open(link.url)),
        if (link.caption != null) ...[
          const SizedBox(height: 6),
          Text(
            link.caption!,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 9.5,
              height: 1.6,
            ),
          ),
        ],
      ],
    );
  }

  Widget _panel({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: .87),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: palette.primary.withValues(alpha: .17)),
        boxShadow: [
          BoxShadow(
            color: palette.primary.withValues(alpha: .045),
            blurRadius: 30,
          ),
          const BoxShadow(
            color: Colors.black38,
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SocialLink {
  const _SocialLink(
    this.label,
    this.url,
    this.icon,
    this.group, {
    this.caption,
  });
  final String label;
  final String url;
  final IconData icon;
  final int group;
  final String? caption;
}

class _HoverLink extends StatefulWidget {
  const _HoverLink({
    required this.palette,
    required this.link,
    required this.onTap,
  });
  final ThemePalette palette;
  final _SocialLink link;
  final VoidCallback onTap;

  @override
  State<_HoverLink> createState() => _HoverLinkState();
}

class _HoverLinkState extends State<_HoverLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: widget.palette.primary.withValues(
              alpha: _hovered ? .13 : .055,
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: widget.palette.primary.withValues(
                alpha: _hovered ? .42 : .14,
              ),
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: widget.palette.primary.withValues(alpha: .13),
                      blurRadius: 18,
                    ),
                  ]
                : null,
          ),
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              Icon(widget.link.icon, color: widget.palette.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.link.label,
                  textDirection: TextDirection.rtl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.palette.text,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.north_east_rounded,
                color: widget.palette.mutedText,
                size: 15,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutBackgroundPainter extends CustomPainter {
  const _AboutBackgroundPainter({required this.color, required this.progress});
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(1589);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 38; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final radius = 1.0 + random.nextDouble() * 2.0;
      final phase = progress * math.pi * 2 + i * .71;
      paint.color = color.withValues(
        alpha: .035 + (math.sin(phase) + 1) * .035,
      );
      canvas.drawCircle(
        Offset(baseX + math.sin(phase) * 10, baseY + math.cos(phase * .8) * 8),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AboutBackgroundPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
