import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_translations.dart';
import '../core/app_sound_service.dart';
import '../core/settings_store.dart';
import 'auth_screen.dart';

enum GoldBrainTheme {
  gold,
  blue,
  pink,
  purple,
  green,
  white,
  black,
  red,
  orange,
  deepBlue,
  brown,
}

enum GoldBrainLanguage {
  english,
  persian,
  japanese,
  russian,
  chinese,
  arabic,
  turkish,
  french,
}

class ThemePalette {
  const ThemePalette({
    required this.background,
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.text,
    required this.mutedText,
    this.isLight = false,
  });

  final Color background;
  final Color surface;
  final Color primary;
  final Color secondary;
  final Color text;
  final Color mutedText;
  final bool isLight;
}

const Map<GoldBrainTheme, ThemePalette> themePalettes = {
  GoldBrainTheme.gold: ThemePalette(
    background: Color(0xFF030303),
    surface: Color(0xFF111111),
    primary: Color(0xFFD4AF37),
    secondary: Color(0xFFFFE082),
    text: Color(0xFFF8F8F8),
    mutedText: Color(0xFF9E9E9E),
  ),
  GoldBrainTheme.blue: ThemePalette(
    background: Color(0xFF020B16),
    surface: Color(0xFF0B1B2D),
    primary: Color(0xFF38BDF8),
    secondary: Color(0xFFBAE6FD),
    text: Color(0xFFF5FBFF),
    mutedText: Color(0xFF8CA9BE),
  ),
  GoldBrainTheme.pink: ThemePalette(
    background: Color(0xFF160710),
    surface: Color(0xFF29101F),
    primary: Color(0xFFFF4FB8),
    secondary: Color(0xFFFFC5E8),
    text: Color(0xFFFFF7FC),
    mutedText: Color(0xFFC7A0B8),
  ),
  GoldBrainTheme.purple: ThemePalette(
    background: Color(0xFF0C0618),
    surface: Color(0xFF1A1030),
    primary: Color(0xFFA970FF),
    secondary: Color(0xFFE3D2FF),
    text: Color(0xFFFBF8FF),
    mutedText: Color(0xFFB5A5CC),
  ),
  GoldBrainTheme.green: ThemePalette(
    background: Color(0xFF031009),
    surface: Color(0xFF0C2015),
    primary: Color(0xFF22C55E),
    secondary: Color(0xFFBBF7D0),
    text: Color(0xFFF5FFF8),
    mutedText: Color(0xFF8EB49B),
  ),
  GoldBrainTheme.white: ThemePalette(
    background: Color(0xFFF3F6FA),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFF9A6700),
    secondary: Color(0xFF5C3B00),
    text: Color(0xFF111827),
    mutedText: Color(0xFF667085),
    isLight: true,
  ),
  GoldBrainTheme.black: ThemePalette(
    background: Color(0xFF000000),
    surface: Color(0xFF0A0A0B),
    primary: Color(0xFFE5E7EB),
    secondary: Color(0xFFFFFFFF),
    text: Color(0xFFF9FAFB),
    mutedText: Color(0xFF9CA3AF),
  ),
  GoldBrainTheme.red: ThemePalette(
    background: Color(0xFF140405),
    surface: Color(0xFF2A0B0E),
    primary: Color(0xFFEF4444),
    secondary: Color(0xFFFCA5A5),
    text: Color(0xFFFFF7F7),
    mutedText: Color(0xFFC99B9E),
  ),
  GoldBrainTheme.orange: ThemePalette(
    background: Color(0xFF160A02),
    surface: Color(0xFF2A1608),
    primary: Color(0xFFF97316),
    secondary: Color(0xFFFED7AA),
    text: Color(0xFFFFFAF5),
    mutedText: Color(0xFFC9A58B),
  ),
  GoldBrainTheme.deepBlue: ThemePalette(
    background: Color(0xFF010817),
    surface: Color(0xFF071A38),
    primary: Color(0xFF2563EB),
    secondary: Color(0xFF93C5FD),
    text: Color(0xFFF4F8FF),
    mutedText: Color(0xFF91A7C8),
  ),
  GoldBrainTheme.brown: ThemePalette(
    background: Color(0xFF130B07),
    surface: Color(0xFF291A12),
    primary: Color(0xFFA16207),
    secondary: Color(0xFFF5D0A9),
    text: Color(0xFFFFF8F1),
    mutedText: Color(0xFFBEA18D),
  ),
};

class SelectionScreen extends StatefulWidget {
  const SelectionScreen({super.key});

  @override
  State<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends State<SelectionScreen>
    with TickerProviderStateMixin {
  GoldBrainTheme selectedTheme = GoldBrainTheme.gold;
  GoldBrainLanguage selectedLanguage = GoldBrainLanguage.english;

  late final AnimationController _entranceController;
  late final AnimationController _ringController;
  late final AnimationController _pulseController;

  bool _isOpeningDashboard = false;
  Offset? _selectionFlashPosition;

  ThemePalette get palette => themePalettes[selectedTheme]!;

  @override
  void initState() {
    super.initState();

    _startSelectionMusic();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..forward();

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  Future<void> _startSelectionMusic() async {
    final settings = SettingsStore.instance;
    await settings.load();

    if (!mounted) return;

    setState(() {
      selectedTheme = GoldBrainTheme.values.firstWhere(
        (theme) => theme.name == settings.themeCode,
        orElse: () => GoldBrainTheme.gold,
      );
      selectedLanguage = GoldBrainLanguage.values.firstWhere(
        (language) => language.name == settings.languageCode,
        orElse: () => GoldBrainLanguage.english,
      );
    });

    await AppSoundService.instance.startMusic(
      track: AppMusicTrack.selection,
      enabled: settings.soundEnabled,
      musicEnabled: settings.musicEnabled,
      volume: settings.interfaceVolume,
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _ringController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Animation<double> staggeredFade(double start, double end) {
    final safeStart = start.clamp(0.0, .98).toDouble();
    final safeEnd = end.clamp(safeStart + .01, 1.0).toDouble();
    return CurvedAnimation(
      parent: _entranceController,
      curve: Interval(safeStart, safeEnd, curve: Curves.easeOutCubic),
    );
  }

  Animation<Offset> staggeredSlide(
    double start,
    double end, {
    Offset begin = const Offset(0, 0.22),
  }) {
    final safeStart = start.clamp(0.0, .98).toDouble();
    final safeEnd = end.clamp(safeStart + .01, 1.0).toDouble();
    return Tween<Offset>(begin: begin, end: Offset.zero).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Interval(safeStart, safeEnd, curve: Curves.easeOutBack),
      ),
    );
  }

  Future<void> playClickSound() async {
    final settings = SettingsStore.instance;
    await AppSoundService.instance.playClick(
      enabled: settings.soundEnabled && settings.interfaceSoundsEnabled,
      volume: settings.interfaceVolume,
    );
  }

  Future<void> playThemeHoverSound() async {
    final settings = SettingsStore.instance;
    await AppSoundService.instance.playHover(
      enabled: settings.soundEnabled && settings.interfaceSoundsEnabled,
      volume: settings.interfaceVolume,
    );
  }

  Future<void> playThemeSelectedSound() async {
    final settings = SettingsStore.instance;
    await AppSoundService.instance.playThemeSelected(
      enabled: settings.soundEnabled && settings.interfaceSoundsEnabled,
      volume: settings.interfaceVolume,
    );
  }

  String get title {
    switch (selectedLanguage) {
      case GoldBrainLanguage.persian:
        return 'ظاهر و زبان GoldBrain را انتخاب کنید';
      case GoldBrainLanguage.japanese:
        return 'GoldBrainの外観と言語を選択';
      case GoldBrainLanguage.russian:
        return 'Выберите стиль и язык GoldBrain';
      case GoldBrainLanguage.chinese:
        return AppTranslations.simplifiedChinese(
          'Choose your GoldBrain experience',
        );
      case GoldBrainLanguage.arabic:
        return AppTranslations.arabic('Choose your GoldBrain experience');
      case GoldBrainLanguage.turkish:
        return AppTranslations.turkish('Choose your GoldBrain experience');
      case GoldBrainLanguage.french:
        return AppTranslations.french('Choose your GoldBrain experience');
      case GoldBrainLanguage.english:
        return 'Choose your GoldBrain experience';
    }
  }

  String get subtitle {
    switch (selectedLanguage) {
      case GoldBrainLanguage.persian:
        return 'همه چیز را بعداً هم می‌توانید از تنظیمات تغییر دهید';
      case GoldBrainLanguage.japanese:
        return 'これらの設定は後で変更できます';
      case GoldBrainLanguage.russian:
        return 'Эти настройки можно изменить позже';
      case GoldBrainLanguage.chinese:
        return AppTranslations.simplifiedChinese(
          'You can change these settings later',
        );
      case GoldBrainLanguage.arabic:
        return AppTranslations.arabic('You can change these settings later');
      case GoldBrainLanguage.turkish:
        return AppTranslations.turkish('You can change these settings later');
      case GoldBrainLanguage.french:
        return AppTranslations.french('You can change these settings later');
      case GoldBrainLanguage.english:
        return 'You can change these settings later';
    }
  }

  String get themeLabel {
    switch (selectedLanguage) {
      case GoldBrainLanguage.persian:
        return 'تم رنگی';
      case GoldBrainLanguage.japanese:
        return 'カラーテーマ';
      case GoldBrainLanguage.russian:
        return 'Цветовая тема';
      case GoldBrainLanguage.chinese:
        return AppTranslations.simplifiedChinese('COLOR THEME');
      case GoldBrainLanguage.arabic:
        return AppTranslations.arabic('COLOR THEME');
      case GoldBrainLanguage.turkish:
        return AppTranslations.turkish('COLOR THEME');
      case GoldBrainLanguage.french:
        return AppTranslations.french('COLOR THEME');
      case GoldBrainLanguage.english:
        return 'COLOR THEME';
    }
  }

  String get languageLabel {
    switch (selectedLanguage) {
      case GoldBrainLanguage.persian:
        return 'زبان برنامه';
      case GoldBrainLanguage.japanese:
        return 'アプリの言語';
      case GoldBrainLanguage.russian:
        return 'Язык приложения';
      case GoldBrainLanguage.chinese:
        return AppTranslations.simplifiedChinese('APPLICATION LANGUAGE');
      case GoldBrainLanguage.arabic:
        return AppTranslations.arabic('APPLICATION LANGUAGE');
      case GoldBrainLanguage.turkish:
        return AppTranslations.turkish('APPLICATION LANGUAGE');
      case GoldBrainLanguage.french:
        return AppTranslations.french('APPLICATION LANGUAGE');
      case GoldBrainLanguage.english:
        return 'APPLICATION LANGUAGE';
    }
  }

  String get enterText {
    switch (selectedLanguage) {
      case GoldBrainLanguage.persian:
        return 'ورود به GoldBrain';
      case GoldBrainLanguage.japanese:
        return 'GOLDBRAINを開始';
      case GoldBrainLanguage.russian:
        return 'ВОЙТИ В GOLDBRAIN';
      case GoldBrainLanguage.chinese:
        return AppTranslations.simplifiedChinese('ENTER GOLDBRAIN');
      case GoldBrainLanguage.arabic:
        return AppTranslations.arabic('ENTER GOLDBRAIN');
      case GoldBrainLanguage.turkish:
        return AppTranslations.turkish('ENTER GOLDBRAIN');
      case GoldBrainLanguage.french:
        return AppTranslations.french('ENTER GOLDBRAIN');
      case GoldBrainLanguage.english:
        return 'ENTER GOLDBRAIN';
    }
  }

  void selectTheme(GoldBrainTheme theme, Offset globalPosition) {
    if (selectedTheme == theme) {
      return;
    }

    playThemeSelectedSound();

    setState(() {
      selectedTheme = theme;
      _selectionFlashPosition = globalPosition;
    });

    Future.delayed(const Duration(milliseconds: 520), () {
      if (mounted) {
        setState(() {
          _selectionFlashPosition = null;
        });
      }
    });
  }

  void selectLanguage(GoldBrainLanguage language) {
    if (selectedLanguage == language) {
      return;
    }

    playClickSound();

    setState(() {
      selectedLanguage = language;
    });
  }

  Future<void> openDashboard() async {
    if (_isOpeningDashboard) {
      return;
    }

    setState(() {
      _isOpeningDashboard = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 500));

    final settings = SettingsStore.instance;
    await AppSoundService.instance.playMetalImpact(
      enabled: settings.soundEnabled && settings.interfaceSoundsEnabled,
      volume: settings.interfaceVolume,
    );

    await settings.saveAppearance(
      themeCode: selectedTheme.name,
      languageCode: selectedLanguage.name,
    );

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 950),
        pageBuilder: (_, animation, secondaryAnimation) {
          return AuthScreen(
            selectedTheme: selectedTheme,
            selectedLanguage: selectedLanguage,
          );
        },
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );

          return FadeTransition(
            opacity: curvedAnimation,
            child: ScaleTransition(
              scale: Tween<double>(
                begin: 1.06,
                end: 1,
              ).animate(curvedAnimation),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRtl =
        selectedLanguage == GoldBrainLanguage.persian ||
        selectedLanguage == GoldBrainLanguage.arabic;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        color: palette.background,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              _AnimatedBackground(
                palette: palette,
                pulseController: _pulseController,
              ),

              if (_selectionFlashPosition != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _SelectionShockwave(
                      key: ValueKey(_selectionFlashPosition),
                      position: _selectionFlashPosition!,
                      color: palette.primary,
                    ),
                  ),
                ),

              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: AnimatedScale(
                    scale: _isOpeningDashboard ? 1.08 : 1,
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeInCubic,
                    child: AnimatedOpacity(
                      opacity: _isOpeningDashboard ? 0 : 1,
                      duration: const Duration(milliseconds: 650),
                      curve: Curves.easeInCubic,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1060),
                        child: _buildMainPanel(),
                      ),
                    ),
                  ),
                ),
              ),

              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _isOpeningDashboard ? 1 : 0,
                  duration: const Duration(milliseconds: 450),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          palette.secondary.withValues(alpha: 0.8),
                          palette.primary.withValues(alpha: 0.24),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.22, 1],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainPanel() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final glowPower = 0.05 + _pulseController.value * 0.055;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 42),
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: 0.91),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
              color: palette.primary.withValues(alpha: 0.25),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: palette.primary.withValues(alpha: glowPower),
                blurRadius: 70,
                spreadRadius: 8,
              ),
              const BoxShadow(
                color: Colors.black54,
                blurRadius: 45,
                offset: Offset(0, 22),
              ),
            ],
          ),
          child: Column(
            children: [
              FadeTransition(
                opacity: staggeredFade(0.00, 0.28),
                child: SlideTransition(
                  position: staggeredSlide(
                    0.00,
                    0.28,
                    begin: const Offset(0, -0.45),
                  ),
                  child: Text(
                    'GOLDBRAIN',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: palette.primary,
                      fontSize: 23,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(
                          color: palette.primary.withValues(alpha: 0.45),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              FadeTransition(
                opacity: staggeredFade(0.12, 0.42),
                child: SlideTransition(
                  position: staggeredSlide(0.12, 0.42),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.96,
                            end: 1,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      title,
                      key: ValueKey(title),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              FadeTransition(
                opacity: staggeredFade(0.18, 0.48),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Text(
                    subtitle,
                    key: ValueKey(subtitle),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.mutedText, fontSize: 15),
                  ),
                ),
              ),

              const SizedBox(height: 42),

              FadeTransition(
                opacity: staggeredFade(0.28, 0.54),
                child: _SectionTitle(
                  title: themeLabel,
                  color: palette.mutedText,
                ),
              ),

              const SizedBox(height: 22),

              Wrap(
                textDirection: TextDirection.ltr,
                alignment: WrapAlignment.center,
                spacing: 2,
                runSpacing: 14,
                children: GoldBrainTheme.values.indexed.map((entry) {
                  final index = entry.$1;
                  final theme = entry.$2;

                  return FadeTransition(
                    opacity: staggeredFade(
                      0.34 + index * 0.07,
                      0.61 + index * 0.07,
                    ),
                    child: SlideTransition(
                      position: staggeredSlide(
                        0.34 + index * 0.07,
                        0.61 + index * 0.07,
                        begin: const Offset(0, 0.8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        child: ThemeEnergyOrb(
                          palette: themePalettes[theme]!,
                          selected: selectedTheme == theme,
                          ringController: _ringController,
                          pulseController: _pulseController,
                          onTap: (position) {
                            selectTheme(theme, position);
                          },
                          onHover: playThemeHoverSound,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 43),

              FadeTransition(
                opacity: staggeredFade(0.62, 0.78),
                child: _SectionTitle(
                  title: languageLabel,
                  color: palette.mutedText,
                ),
              ),

              const SizedBox(height: 21),

              Wrap(
                textDirection: TextDirection.ltr,
                alignment: WrapAlignment.center,
                spacing: 15,
                runSpacing: 15,
                children: [
                  _languageItem(
                    index: 0,
                    text: 'English',
                    language: GoldBrainLanguage.english,
                  ),
                  _languageItem(
                    index: 1,
                    text: 'فارسی',
                    language: GoldBrainLanguage.persian,
                  ),
                  _languageItem(
                    index: 2,
                    text: '日本語',
                    language: GoldBrainLanguage.japanese,
                  ),
                  _languageItem(
                    index: 3,
                    text: 'Русский',
                    language: GoldBrainLanguage.russian,
                  ),
                  _languageItem(
                    index: 4,
                    text: '简体中文',
                    language: GoldBrainLanguage.chinese,
                  ),
                  _languageItem(
                    index: 5,
                    text: 'العربية',
                    language: GoldBrainLanguage.arabic,
                  ),
                  _languageItem(
                    index: 6,
                    text: 'Türkçe',
                    language: GoldBrainLanguage.turkish,
                  ),
                  _languageItem(
                    index: 7,
                    text: 'Français',
                    language: GoldBrainLanguage.french,
                  ),
                ],
              ),

              const SizedBox(height: 44),

              FadeTransition(
                opacity: staggeredFade(0.82, 1),
                child: SlideTransition(
                  position: staggeredSlide(
                    0.82,
                    1,
                    begin: const Offset(0, 0.65),
                  ),
                  child: EnterEnergyButton(
                    text: enterText,
                    palette: palette,
                    pulseController: _pulseController,
                    onTap: openDashboard,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _languageItem({
    required int index,
    required String text,
    required GoldBrainLanguage language,
  }) {
    final start = 0.66 + index * 0.055;
    final end = 0.84 + index * 0.04;

    return FadeTransition(
      opacity: staggeredFade(start, end),
      child: SlideTransition(
        position: staggeredSlide(
          start,
          end,
          begin: Offset(index.isEven ? -0.45 : 0.45, 0.30),
        ),
        child: LanguageEnergyButton(
          text: text,
          selected: selectedLanguage == language,
          palette: palette,
          pulseController: _pulseController,
          onTap: () {
            selectLanguage(language);
          },
          onHover: playThemeHoverSound,
        ),
      ),
    );
  }
}

class _AnimatedBackground extends StatelessWidget {
  const _AnimatedBackground({
    required this.palette,
    required this.pulseController,
  });

  final ThemePalette palette;
  final AnimationController pulseController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (context, child) {
        final movement = math.sin(pulseController.value * math.pi * 2);

        return Stack(
          children: [
            Positioned(
              top: -180 + movement * 16,
              right: -110,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                width: 480,
                height: 480,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      palette.primary.withValues(alpha: 0.17),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -240 - movement * 12,
              left: -160,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                width: 540,
                height: 540,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      palette.secondary.withValues(alpha: 0.09),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontSize: 11,
        letterSpacing: 2.8,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class ThemeEnergyOrb extends StatefulWidget {
  const ThemeEnergyOrb({
    super.key,
    required this.palette,
    required this.selected,
    required this.ringController,
    required this.pulseController,
    required this.onTap,
    this.onHover,
  });

  final ThemePalette palette;
  final bool selected;
  final AnimationController ringController;
  final AnimationController pulseController;
  final ValueChanged<Offset> onTap;
  final VoidCallback? onHover;

  @override
  State<ThemeEnergyOrb> createState() => _ThemeEnergyOrbState();
}

class _ThemeEnergyOrbState extends State<ThemeEnergyOrb> {
  bool hovered = false;
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        widget.onHover?.call();
        setState(() {
          hovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          hovered = false;
          pressed = false;
        });
      },
      child: GestureDetector(
        onTapDown: (_) {
          setState(() {
            pressed = true;
          });
        },
        onTapCancel: () {
          setState(() {
            pressed = false;
          });
        },
        onTapUp: (details) {
          setState(() {
            pressed = false;
          });

          widget.onTap(details.globalPosition);
        },
        child: AnimatedScale(
          scale: pressed
              ? 0.90
              : hovered
              ? 1.14
              : 1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: AnimatedBuilder(
            animation: Listenable.merge([
              widget.ringController,
              widget.pulseController,
            ]),
            builder: (context, child) {
              final pulse = 0.93 + widget.pulseController.value * 0.07;

              return SizedBox(
                width: 82,
                height: 82,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (widget.selected)
                      Transform.rotate(
                        angle: widget.ringController.value * math.pi * 2,
                        child: Transform.scale(
                          scale: pulse,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SweepGradient(
                                colors: [
                                  Colors.transparent,
                                  widget.palette.primary,
                                  widget.palette.secondary,
                                  Colors.white,
                                  widget.palette.primary,
                                  Colors.transparent,
                                ],
                                stops: const [0, 0.18, 0.40, 0.52, 0.72, 1],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: widget.palette.primary.withValues(
                                    alpha: 0.52,
                                  ),
                                  blurRadius: 25,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      width: widget.selected ? 68 : 65,
                      height: widget.selected ? 68 : 65,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: widget.palette.background,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: hovered
                              ? widget.palette.secondary
                              : widget.palette.text.withValues(alpha: 0.12),
                          width: hovered ? 2.2 : 1.5,
                        ),
                        boxShadow: [
                          if (hovered || widget.selected)
                            BoxShadow(
                              color: widget.palette.primary.withValues(
                                alpha: hovered ? 0.52 : 0.30,
                              ),
                              blurRadius: hovered ? 30 : 18,
                              spreadRadius: hovered ? 3 : 1,
                            ),
                        ],
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              widget.palette.background,
                              widget.palette.primary,
                              widget.palette.secondary,
                            ],
                          ),
                        ),
                      ),
                    ),

                    if (widget.selected)
                      Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: widget.palette.secondary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: widget.palette.background,
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: widget.palette.secondary.withValues(
                                alpha: 0.95,
                              ),
                              blurRadius: 13,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class LanguageEnergyButton extends StatefulWidget {
  const LanguageEnergyButton({
    super.key,
    required this.text,
    required this.selected,
    required this.palette,
    required this.pulseController,
    required this.onTap,
    this.onHover,
  });

  final String text;
  final bool selected;
  final ThemePalette palette;
  final AnimationController pulseController;
  final VoidCallback onTap;
  final VoidCallback? onHover;

  @override
  State<LanguageEnergyButton> createState() => _LanguageEnergyButtonState();
}

class _LanguageEnergyButtonState extends State<LanguageEnergyButton> {
  bool hovered = false;
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        widget.onHover?.call();
        setState(() {
          hovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          hovered = false;
          pressed = false;
        });
      },
      child: GestureDetector(
        onTapDown: (_) {
          setState(() {
            pressed = true;
          });
        },
        onTapCancel: () {
          setState(() {
            pressed = false;
          });
        },
        onTapUp: (_) {
          setState(() {
            pressed = false;
          });

          widget.onTap();
        },
        child: AnimatedScale(
          scale: pressed
              ? 0.97
              : hovered
              ? 1.045
              : 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutBack,
          child: AnimatedBuilder(
            animation: widget.pulseController,
            builder: (context, child) {
              final glow = widget.selected
                  ? 0.16 + widget.pulseController.value * 0.22
                  : 0.0;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 330),
                width: 190,
                height: 61,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.selected
                      ? widget.palette.primary.withValues(alpha: 0.16)
                      : widget.palette.text.withValues(
                          alpha: hovered ? 0.07 : 0.035,
                        ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: widget.selected
                        ? widget.palette.primary
                        : hovered
                        ? widget.palette.primary.withValues(alpha: 0.65)
                        : widget.palette.text.withValues(alpha: 0.11),
                    width: widget.selected ? 2.4 : 1.2,
                  ),
                  boxShadow: [
                    if (widget.selected)
                      BoxShadow(
                        color: widget.palette.primary.withValues(alpha: glow),
                        blurRadius: 20 + widget.pulseController.value * 18,
                        spreadRadius: widget.pulseController.value * 2.5,
                      ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 350),
                      left: widget.selected ? 22 : 60,
                      right: widget.selected ? 22 : 60,
                      bottom: 6,
                      child: AnimatedOpacity(
                        opacity: widget.selected ? 1 : 0,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                widget.palette.primary,
                                widget.palette.secondary,
                                widget.palette.primary,
                                Colors.transparent,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: widget.palette.primary.withValues(
                                  alpha: 0.85,
                                ),
                                blurRadius: 7,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Text(
                      widget.text,
                      textDirection: widget.text == 'فارسی'
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      style: TextStyle(
                        color: widget.selected
                            ? widget.palette.secondary
                            : widget.palette.text,
                        fontSize: 16,
                        fontWeight: widget.selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class EnterEnergyButton extends StatefulWidget {
  const EnterEnergyButton({
    super.key,
    required this.text,
    required this.palette,
    required this.pulseController,
    required this.onTap,
  });

  final String text;
  final ThemePalette palette;
  final AnimationController pulseController;
  final VoidCallback onTap;

  @override
  State<EnterEnergyButton> createState() => _EnterEnergyButtonState();
}

class _EnterEnergyButtonState extends State<EnterEnergyButton> {
  bool hovered = false;
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() {
          hovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          hovered = false;
          pressed = false;
        });
      },
      child: GestureDetector(
        onTapDown: (_) {
          setState(() {
            pressed = true;
          });
        },
        onTapCancel: () {
          setState(() {
            pressed = false;
          });
        },
        onTapUp: (_) {
          setState(() {
            pressed = false;
          });

          widget.onTap();
        },
        child: AnimatedBuilder(
          animation: widget.pulseController,
          builder: (context, child) {
            return AnimatedScale(
              scale: pressed
                  ? 0.96
                  : hovered
                  ? 1.035
                  : 1,
              duration: const Duration(milliseconds: 170),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                width: 335,
                height: 66,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [widget.palette.primary, widget.palette.secondary],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.palette.primary.withValues(
                        alpha: hovered
                            ? 0.48
                            : 0.23 + widget.pulseController.value * 0.08,
                      ),
                      blurRadius: hovered ? 38 : 24,
                      spreadRadius: hovered ? 4 : 1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  textDirection: TextDirection.ltr,
                  children: [
                    Text(
                      widget.text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: widget.palette.isLight
                            ? Colors.white
                            : Colors.black,
                        fontSize: 14,
                        letterSpacing: 1.35,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      width: hovered ? 24 : 0,
                    ),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: hovered ? 1 : 0,
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: widget.palette.isLight
                            ? Colors.white
                            : Colors.black,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SelectionShockwave extends StatefulWidget {
  const _SelectionShockwave({
    super.key,
    required this.position,
    required this.color,
  });

  final Offset position;
  final Color color;

  @override
  State<_SelectionShockwave> createState() => _SelectionShockwaveState();
}

class _SelectionShockwaveState extends State<_SelectionShockwave>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final progress = Curves.easeOutCubic.transform(controller.value);

        final size = 24 + progress * 210;
        final opacity = (1 - controller.value).clamp(0.0, 1.0);

        return Stack(
          children: [
            Positioned(
              left: widget.position.dx - size / 2,
              top: widget.position.dy - size / 2,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withValues(alpha: opacity * 0.75),
                    width: 2.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: opacity * 0.35),
                      blurRadius: 25,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
