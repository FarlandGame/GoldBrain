import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'market_intelligence_service.dart';
import 'market_intelligence_store.dart';
import 'news_service.dart';
import 'news_store.dart';
import 'notification_service.dart';
import 'settings_store.dart';
import 'local_persistence_policy.dart';

/// Bridges real news/analysis store updates into the persisted in-app
/// notification center. It deliberately uses conservative gates and stable
/// identifiers so refreshes cannot spam duplicate alerts.
class NotificationAutomationService {
  NotificationAutomationService._app()
    : newsListenable = NewsStore.instance,
      intelligenceListenable = MarketIntelligenceStore.instance,
      settingsListenable = SettingsStore.instance,
      newsReader = (() => NewsStore.instance.articles),
      reportReader = (() => MarketIntelligenceStore.instance.reportsBySymbol),
      settings = SettingsStore.instance,
      notifications = NotificationService.instance,
      _preferencesLoader = SharedPreferences.getInstance,
      _clock = DateTime.now,
      _persistSeenOverride = null;

  @visibleForTesting
  NotificationAutomationService.forTesting({
    required this.newsListenable,
    required this.intelligenceListenable,
    required this.settingsListenable,
    required this.newsReader,
    required this.reportReader,
    required this.settings,
    required this.notifications,
    Future<SharedPreferences> Function()? preferencesLoader,
    DateTime Function()? clock,
    Future<void> Function()? persistSeenOverride,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
       _clock = clock ?? DateTime.now,
       _persistSeenOverride = persistSeenOverride;

  static final NotificationAutomationService instance =
      NotificationAutomationService._app();

  static const _seenNewsKey = 'notifications.automation.seen_news_v1';
  static const _seenSignalsKey = 'notifications.automation.seen_signals_v1';
  static const _maximumSeenItems = 500;

  final Listenable newsListenable;
  final Listenable intelligenceListenable;
  final Listenable settingsListenable;
  final List<NewsArticle> Function() newsReader;
  final Map<String, MarketIntelligenceReport> Function() reportReader;
  final SettingsStore settings;
  final NotificationService notifications;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final DateTime Function() _clock;
  final Future<void> Function()? _persistSeenOverride;

  SharedPreferences? _preferences;
  final Set<String> _seenNews = <String>{};
  final Set<String> _seenSignals = <String>{};
  bool _started = false;
  bool _disposed = false;
  bool _newsBaselineEstablished = false;
  bool _signalBaselineEstablished = false;
  bool _processRequested = false;
  bool _seenPersistenceDirty = false;
  Future<void>? _processing;

  Future<void> start() async {
    if (_started || _disposed) return;
    _preferences = await _preferencesLoader();
    _seenNews.addAll(
      _preferences!.getStringList(_seenNewsKey) ?? const <String>[],
    );
    _seenSignals.addAll(
      _preferences!.getStringList(_seenSignalsKey) ?? const <String>[],
    );
    _newsBaselineEstablished = _seenNews.isNotEmpty;
    _signalBaselineEstablished = _seenSignals.isNotEmpty;
    newsListenable.addListener(_scheduleProcess);
    intelligenceListenable.addListener(_scheduleProcess);
    settingsListenable.addListener(_scheduleProcess);
    _started = true;
    await processNow();
  }

  void _scheduleProcess() => unawaited(processNow());

  Future<void> processNow() {
    if (_disposed) return Future<void>.value();
    // Coalesce bursts without dropping an update: every request made while a
    // pass is awaiting persistence guarantees at least one later pass, while
    // all callers share a single no-overlap drain future.
    _processRequested = true;
    final active = _processing;
    if (active != null) return active;
    final completer = Completer<void>();
    _processing = completer.future;
    unawaited(_drainProcessing(completer));
    return completer.future;
  }

  Future<void> _drainProcessing(Completer<void> completer) async {
    try {
      while (_processRequested && !_disposed) {
        _processRequested = false;
        await _process();
      }
      // There is intentionally no await between the final dirty check above
      // and clearing _processing. A new request therefore either joined this
      // drain or sees null and starts the next one; it cannot fall between.
      _processing = null;
      completer.complete();
    } catch (error, stackTrace) {
      _processing = null;
      completer.completeError(error, stackTrace);
    }
  }

  Future<void> _process() async {
    if (!_started || _disposed) return;
    var newsChanged = false;
    var emittedNews = false;
    final articles = newsReader();
    final firstNewsSnapshot = !_newsBaselineEstablished;
    for (final article in articles) {
      final key = article.id.trim().isEmpty
          ? '${article.source}|${article.url}|${article.publishedAt.toUtc().toIso8601String()}'
          : article.id.trim();
      if (!_seenNews.add(key)) continue;
      newsChanged = true;
      if (!emittedNews &&
          !firstNewsSnapshot &&
          settings.notificationsEnabled &&
          settings.newsAlertsEnabled &&
          _isRecent(article.publishedAt, const Duration(hours: 3)) &&
          _isImportantFinancialNews(article)) {
        emittedNews = notifications.addSemanticNotificationIfAbsent(
          id: 'breaking-news-${_stableHash(key)}',
          semanticKey: AppNotificationSemanticKey.importantFinancialNews,
          semanticData: <String, String>{
            'headline': _bounded(article.title, 240),
            'source': _bounded(article.source, 80),
          },
          type: AppNotificationType.news,
        );
      }
    }
    if (articles.isNotEmpty) _newsBaselineEstablished = true;

    var signalsChanged = false;
    var emittedSignal = false;
    final reports = reportReader();
    final firstSignalSnapshot = !_signalBaselineEstablished;
    for (final report in reports.values) {
      final fingerprint =
          '${report.symbol}|${report.evidenceFingerprint}|${report.generatedAt.toUtc().toIso8601String()}';
      if (!_seenSignals.add(fingerprint)) continue;
      signalsChanged = true;
      if (!emittedSignal &&
          !firstSignalSnapshot &&
          settings.notificationsEnabled &&
          settings.aiSignalsEnabled &&
          _isRecent(report.generatedAt, const Duration(minutes: 30)) &&
          _isStrongSignal(report)) {
        emittedSignal = notifications.addSemanticNotificationIfAbsent(
          id: 'ai-signal-${_stableHash(fingerprint)}',
          semanticKey: AppNotificationSemanticKey.strongAiSignal,
          semanticData: <String, String>{
            'symbol': report.symbol,
            'direction': report.direction.name,
            'confidence': report.scenarioEstimatePercent.toString(),
            'horizonHours': report.forecastHorizonHours.toString(),
          },
          type: AppNotificationType.ai,
        );
      }
    }
    if (reports.isNotEmpty) _signalBaselineEstablished = true;

    if (newsChanged || signalsChanged || _seenPersistenceDirty) {
      await _persistSeen();
    }
  }

  bool _isRecent(DateTime value, Duration maximumAge) {
    final age = _clock().difference(value.toLocal());
    return !age.isNegative && age <= maximumAge;
  }

  bool _isImportantFinancialNews(NewsArticle article) {
    final text = '${article.title} ${article.summary} ${article.sourceCategory}'
        .toLowerCase();
    const financialTerms = <String>[
      'gold',
      'dollar',
      'currency',
      'inflation',
      'interest rate',
      'central bank',
      'federal reserve',
      'oil',
      'bitcoin',
      'crypto',
      'طلا',
      'دلار',
      'ارز',
      'تورم',
      'نرخ بهره',
      'بانک مرکزی',
      'بورس',
      'نفت',
      'بیت کوین',
      'بیت‌کوین',
      'رمزارز',
    ];
    return financialTerms.any(text.contains);
  }

  bool _isStrongSignal(MarketIntelligenceReport report) {
    final confidence = report.scenarioEstimatePercent;
    return (report.direction == MarketScenarioDirection.upward ||
            report.direction == MarketScenarioDirection.downward) &&
        confidence != null &&
        confidence >= 70 &&
        report.evidenceQualityPercent >= 55 &&
        report.historyPointCount >= 3;
  }

  Future<void> _persistSeen() async {
    if (!LocalPersistencePolicy.instance.canWrite) {
      _seenPersistenceDirty = true;
      return;
    }
    final override = _persistSeenOverride;
    if (override != null) {
      await override();
      _seenPersistenceDirty = false;
      return;
    }
    final prefs = _preferences ?? await _preferencesLoader();
    _preferences = prefs;
    await Future.wait(<Future<bool>>[
      prefs.setStringList(_seenNewsKey, _tail(_seenNews)),
      prefs.setStringList(_seenSignalsKey, _tail(_seenSignals)),
    ]);
    _seenPersistenceDirty = false;
  }

  List<String> _tail(Set<String> source) {
    final values = source.toList(growable: false);
    if (values.length <= _maximumSeenItems) return values;
    return values.sublist(values.length - _maximumSeenItems);
  }

  String _bounded(String value, int maximum) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.length <= maximum
        ? normalized
        : '${normalized.substring(0, maximum - 1)}…';
  }

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }

  @visibleForTesting
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _processRequested = false;
    if (_started) {
      newsListenable.removeListener(_scheduleProcess);
      intelligenceListenable.removeListener(_scheduleProcess);
      settingsListenable.removeListener(_scheduleProcess);
    }
  }
}
