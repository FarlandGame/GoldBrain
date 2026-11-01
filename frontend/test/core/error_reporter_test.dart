import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/error_reporter.dart';
import 'package:goldbrain/core/notification_service.dart';
import 'package:goldbrain/core/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'technical notifications are localized in all eight languages',
    () async {
      SharedPreferences.setMockInitialValues({
        'settings.crash_reports_enabled': true,
      });
      await SettingsStore.instance.load();
      await NotificationService.instance.load();

      const expected = <String, ({String title, String source})>{
        'english': (title: 'Technical error detected', source: 'Source'),
        'persian': (title: 'یک خطای فنی شناسایی شد', source: 'منبع'),
        'japanese': (title: '技術的なエラーを検出しました', source: '発生元'),
        'russian': (title: 'Обнаружена техническая ошибка', source: 'Источник'),
        'chinese': (title: '检测到技术错误', source: '来源'),
        'arabic': (title: 'تم اكتشاف خطأ تقني', source: 'المصدر'),
        'turkish': (title: 'Teknik bir hata algılandı', source: 'Kaynak'),
        'french': (
          title: 'Une erreur technique a été détectée',
          source: 'Source',
        ),
      };

      for (final entry in expected.entries) {
        await SettingsStore.instance.saveAppearance(
          themeCode: 'gold',
          languageCode: entry.key,
        );
        NotificationService.instance.clearAll();
        ErrorReporter.instance.report(
          StateError('localized-test-${entry.key}'),
          StackTrace.current,
          source: 'test-${entry.key}',
        );

        final notification = NotificationService.instance.notifications.single;
        expect(notification.title, entry.value.title);
        expect(notification.message, startsWith('${entry.value.source}:'));
      }
    },
  );
}
