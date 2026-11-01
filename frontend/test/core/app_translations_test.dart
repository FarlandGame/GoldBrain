import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/app_translations.dart';

void main() {
  test('critical settings labels have Simplified Chinese translations', () {
    expect(AppTranslations.simplifiedChinese('Application Settings'), '应用设置');
    expect(AppTranslations.simplifiedChinese('Background music'), '背景音乐');
    expect(AppTranslations.simplifiedChinese('Save settings'), '保存设置');
  });

  test('unknown strings remain readable while localization expands', () {
    expect(
      AppTranslations.simplifiedChinese('Unmapped server message'),
      'Unmapped server message',
    );
  });

  test('Arabic, Turkish and French cover every shared application key', () {
    for (final key in AppTranslations.coreEnglishKeys) {
      for (final language in const ['arabic', 'turkish', 'french']) {
        expect(
          AppTranslations.hasTranslation(key, language),
          isTrue,
          reason: '$language is missing: $key',
        );
      }
    }
  });

  test('new languages translate dynamic UI status messages', () {
    for (final language in const ['arabic', 'turkish', 'french']) {
      expect(
        AppTranslations.translate('3 unread', language),
        isNot('3 unread'),
      );
      expect(
        AppTranslations.translate('AI request failed: timeout', language),
        isNot('AI request failed: timeout'),
      );
    }
  });
}
