import 'package:flutter/material.dart';

import '../core/app_translations.dart';
import 'selection_screen.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({
    super.key,
    required this.palette,
    required this.selectedLanguage,
  });

  final ThemePalette palette;
  final GoldBrainLanguage selectedLanguage;

  String tr({
    required String en,
    required String fa,
    required String ja,
    required String ru,
  }) {
    switch (selectedLanguage) {
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

  @override
  Widget build(BuildContext context) {
    final isRtl =
        selectedLanguage == GoldBrainLanguage.persian ||
        selectedLanguage == GoldBrainLanguage.arabic;
    final message = tr(
      en: 'Coming in a future update; the internal gateway has not been built yet.',
      fa: 'در به‌روزرسانی اضافه می‌شود؛ درگاه داخلی هنوز ساخته نشده.',
      ja: '今後のアップデートで追加予定です。内部ゲートウェイはまだ構築されていません。',
      ru: 'Будет добавлено в будущем обновлении; внутренний шлюз ещё не создан.',
    );

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Semantics(
        enabled: false,
        label: message,
        child: Container(
          constraints: const BoxConstraints(minHeight: 520),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: .86),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.primary.withValues(alpha: .18)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 610),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          palette.primary.withValues(alpha: .22),
                          palette.primary.withValues(alpha: .035),
                        ],
                      ),
                      border: Border.all(
                        color: palette.primary.withValues(alpha: .34),
                      ),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_outlined,
                      color: palette.primary,
                      size: 43,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: palette.primary.withValues(alpha: .22),
                      ),
                    ),
                    child: Text(
                      tr(
                        en: 'DISABLED · ROADMAP',
                        fa: 'غیرفعال · نقشه راه',
                        ja: '無効 · ロードマップ',
                        ru: 'ОТКЛЮЧЕНО · В ПЛАНАХ',
                      ),
                      style: TextStyle(
                        color: palette.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .7,
                      ),
                    ),
                  ),
                  const SizedBox(height: 17),
                  Text(
                    tr(
                      en: 'Portfolio is not available yet',
                      fa: 'سبد دارایی هنوز در دسترس نیست',
                      ja: 'ポートフォリオはまだ利用できません',
                      ru: 'Портфель пока недоступен',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 13,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    tr(
                      en: 'No sample balances, returns or portfolio signals are displayed.',
                      fa: 'هیچ موجودی، بازده یا سیگنال نمونه‌ای نمایش داده نمی‌شود.',
                      ja: 'サンプル残高、収益、ポートフォリオシグナルは表示しません。',
                      ru: 'Демонстрационные балансы, доходность и сигналы не показываются.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.mutedText.withValues(alpha: .78),
                      fontSize: 10.5,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
