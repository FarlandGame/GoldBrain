import 'package:flutter/foundation.dart';

import 'notification_service.dart';
import 'settings_store.dart';

class ErrorReporter {
  ErrorReporter._();

  static final ErrorReporter instance = ErrorReporter._();

  bool _installed = false;
  bool _reporting = false;
  String? _lastSignature;
  DateTime? _lastReportedAt;

  void install() {
    if (_installed) return;
    _installed = true;

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      report(
        details.exception,
        details.stack ?? StackTrace.current,
        source: details.library ?? 'Flutter framework',
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, source: 'Platform dispatcher');
      return true;
    };
  }

  void report(Object error, StackTrace stack, {required String source}) {
    final settings = SettingsStore.instance;
    if (!settings.crashReportsEnabled || _reporting) return;

    final rawMessage = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    final shortMessage = rawMessage.length > 230
        ? '${rawMessage.substring(0, 230)}…'
        : rawMessage;
    final signature = '$source::$shortMessage';
    final now = DateTime.now();

    if (_lastSignature == signature &&
        _lastReportedAt != null &&
        now.difference(_lastReportedAt!).inSeconds < 4) {
      return;
    }

    _lastSignature = signature;
    _lastReportedAt = now;
    _reporting = true;

    final language = settings.languageCode;
    try {
      NotificationService.instance.addNotification(
        title: _text(
          language,
          en: 'Technical error detected',
          fa: 'یک خطای فنی شناسایی شد',
          ja: '技術的なエラーを検出しました',
          ru: 'Обнаружена техническая ошибка',
          zh: '检测到技术错误',
          ar: 'تم اكتشاف خطأ تقني',
          tr: 'Teknik bir hata algılandı',
          fr: 'Une erreur technique a été détectée',
        ),
        message:
            '${_text(language, en: 'Source', fa: 'منبع', ja: '発生元', ru: 'Источник', zh: '来源', ar: 'المصدر', tr: 'Kaynak', fr: 'Source')}: $source\n$shortMessage',
        type: AppNotificationType.system,
      );
    } finally {
      _reporting = false;
    }
  }

  String _text(
    String language, {
    required String en,
    required String fa,
    required String ja,
    required String ru,
    required String zh,
    required String ar,
    required String tr,
    required String fr,
  }) {
    switch (language) {
      case 'persian':
        return fa;
      case 'japanese':
        return ja;
      case 'russian':
        return ru;
      case 'chinese':
        return zh;
      case 'arabic':
        return ar;
      case 'turkish':
        return tr;
      case 'french':
        return fr;
      default:
        return en;
    }
  }
}
