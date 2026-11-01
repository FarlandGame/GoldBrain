import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/local_persistence_policy.dart';
import 'package:goldbrain/core/market_intelligence_service.dart';
import 'package:goldbrain/core/news_service.dart';
import 'package:goldbrain/core/notification_automation_service.dart';
import 'package:goldbrain/core/notification_service.dart';
import 'package:goldbrain/core/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => LocalPersistencePolicy.instance.setSuspended(false));
  tearDown(() => LocalPersistencePolicy.instance.setSuspended(false));

  test(
    'news automation baselines backlog, gates settings and deduplicates',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settings = SettingsStore.testing(
        preferencesLoader: () async => preferences,
      );
      await settings.load();
      final notifications = NotificationService.forTesting(
        preferencesLoader: () async => preferences,
      );
      await notifications.load();
      final newsSource = _TestNotifier();
      final intelligenceSource = _TestNotifier();
      var articles = <NewsArticle>[];
      final reports = <String, MarketIntelligenceReport>{};
      final now = DateTime(2026, 8, 13, 12);
      final automation = NotificationAutomationService.forTesting(
        newsListenable: newsSource,
        intelligenceListenable: intelligenceSource,
        settingsListenable: settings,
        newsReader: () => articles,
        reportReader: () => reports,
        settings: settings,
        notifications: notifications,
        preferencesLoader: () async => preferences,
        clock: () => now,
      );
      addTearDown(automation.dispose);
      addTearDown(newsSource.dispose);
      addTearDown(intelligenceSource.dispose);
      await automation.start();

      articles = [_article('old', 'قیمت طلا امروز', now)];
      newsSource.emit();
      await automation.processNow();
      expect(notifications.notifications, isEmpty);

      articles = [
        _article('new', 'تصمیم مهم بانک مرکزی درباره نرخ بهره', now),
        ...articles,
      ];
      newsSource.emit();
      await automation.processNow();
      expect(notifications.notifications, hasLength(1));
      expect(notifications.notifications.single.type, AppNotificationType.news);
      expect(
        notifications.notifications.single.localizedTitle('persian'),
        'خبر مالی مهم جدید',
      );

      newsSource.emit();
      await automation.processNow();
      expect(notifications.notifications, hasLength(1));

      await _saveNotificationSettings(
        settings,
        master: false,
        news: true,
        ai: true,
      );
      articles = [_article('master-off', 'افزایش قیمت دلار', now), ...articles];
      newsSource.emit();
      await automation.processNow();
      expect(notifications.notifications, hasLength(1));

      await _saveNotificationSettings(
        settings,
        master: true,
        news: false,
        ai: true,
      );
      articles = [_article('news-off', 'کاهش قیمت طلا', now), ...articles];
      newsSource.emit();
      await automation.processNow();
      expect(notifications.notifications, hasLength(1));
    },
  );

  test(
    'AI automation only emits new strong sourced directional signals',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settings = SettingsStore.testing(
        preferencesLoader: () async => preferences,
      );
      await settings.load();
      final notifications = NotificationService.forTesting(
        preferencesLoader: () async => preferences,
      );
      await notifications.load();
      final newsSource = _TestNotifier();
      final intelligenceSource = _TestNotifier();
      final reports = <String, MarketIntelligenceReport>{};
      final now = DateTime(2026, 8, 13, 12);
      final automation = NotificationAutomationService.forTesting(
        newsListenable: newsSource,
        intelligenceListenable: intelligenceSource,
        settingsListenable: settings,
        newsReader: () => const <NewsArticle>[],
        reportReader: () => reports,
        settings: settings,
        notifications: notifications,
        preferencesLoader: () async => preferences,
        clock: () => now,
      );
      addTearDown(automation.dispose);
      addTearDown(newsSource.dispose);
      addTearDown(intelligenceSource.dispose);
      await automation.start();

      reports['GOLD18'] = _report('baseline', now, confidence: 82);
      intelligenceSource.emit();
      await automation.processNow();
      expect(notifications.notifications, isEmpty);

      reports['GOLD18'] = _report('weak', now, confidence: 65);
      intelligenceSource.emit();
      await automation.processNow();
      expect(notifications.notifications, isEmpty);

      reports['GOLD18'] = _report('strong', now, confidence: 78);
      intelligenceSource.emit();
      await automation.processNow();
      expect(notifications.notifications, hasLength(1));
      final signal = notifications.notifications.single;
      expect(signal.type, AppNotificationType.ai);
      expect(signal.localizedTitle('chinese'), '重要 AI 市场信号');
      expect(
        signal.localizedMessage('persian'),
        anyOf(contains('۷۸'), contains('78')),
      );

      intelligenceSource.emit();
      await automation.processNow();
      expect(notifications.notifications, hasLength(1));

      automation.dispose();
      reports['GOLD18'] = _report('after-dispose', now, confidence: 90);
      intelligenceSource.emit();
      await automation.processNow();
      expect(notifications.notifications, hasLength(1));
    },
  );

  test(
    'update arriving during pending persistence is drained without overlap',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settings = SettingsStore.testing(
        preferencesLoader: () async => preferences,
      );
      await settings.load();
      final notifications = NotificationService.forTesting(
        preferencesLoader: () async => preferences,
      );
      await notifications.load();
      final newsSource = _TestNotifier();
      final intelligenceSource = _TestNotifier();
      var articles = <NewsArticle>[];
      final now = DateTime(2026, 8, 13, 12);
      final firstPersistenceEntered = Completer<void>();
      final releaseFirstPersistence = Completer<void>();
      var persistenceCalls = 0;
      var concurrentPersistenceCalls = 0;
      var maximumConcurrentPersistenceCalls = 0;
      final automation = NotificationAutomationService.forTesting(
        newsListenable: newsSource,
        intelligenceListenable: intelligenceSource,
        settingsListenable: settings,
        newsReader: () => articles,
        reportReader: () => const <String, MarketIntelligenceReport>{},
        settings: settings,
        notifications: notifications,
        preferencesLoader: () async => preferences,
        clock: () => now,
        persistSeenOverride: () async {
          persistenceCalls++;
          concurrentPersistenceCalls++;
          if (concurrentPersistenceCalls > maximumConcurrentPersistenceCalls) {
            maximumConcurrentPersistenceCalls = concurrentPersistenceCalls;
          }
          if (persistenceCalls == 1) {
            firstPersistenceEntered.complete();
            await releaseFirstPersistence.future;
          }
          concurrentPersistenceCalls--;
        },
      );
      addTearDown(automation.dispose);
      addTearDown(newsSource.dispose);
      addTearDown(intelligenceSource.dispose);
      await automation.start();

      articles = <NewsArticle>[_article('baseline', 'ordinary update', now)];
      final activeDrain = automation.processNow();
      await firstPersistenceEntered.future;

      articles = <NewsArticle>[
        _article(
          'during-write',
          'Gold price surges after central bank news',
          now,
        ),
        ...articles,
      ];
      newsSource.emit();
      releaseFirstPersistence.complete();
      await activeDrain;

      expect(notifications.notifications, hasLength(1));
      expect(notifications.notifications.single.type, AppNotificationType.news);
      expect(persistenceCalls, 2);
      expect(maximumConcurrentPersistenceCalls, 1);
    },
  );

  test(
    'suspended retention keeps notifications in memory without local writes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settings = SettingsStore.testing(
        preferencesLoader: () async => preferences,
      );
      await settings.load();
      final notifications = NotificationService.forTesting(
        preferencesLoader: () async => preferences,
      );
      await notifications.load();
      final newsSource = _TestNotifier();
      final intelligenceSource = _TestNotifier();
      final now = DateTime(2026, 8, 13, 12);
      var articles = <NewsArticle>[
        _article('baseline', 'ordinary market update', now),
      ];
      final automation = NotificationAutomationService.forTesting(
        newsListenable: newsSource,
        intelligenceListenable: intelligenceSource,
        settingsListenable: settings,
        newsReader: () => articles,
        reportReader: () => const <String, MarketIntelligenceReport>{},
        settings: settings,
        notifications: notifications,
        preferencesLoader: () async => preferences,
        clock: () => now,
      );
      addTearDown(automation.dispose);
      addTearDown(newsSource.dispose);
      addTearDown(intelligenceSource.dispose);
      await automation.start();
      await preferences.remove('notifications.automation.seen_news_v1');
      await preferences.remove('notifications.automation.seen_signals_v1');
      await preferences.remove('app.notifications');
      LocalPersistencePolicy.instance.setSuspended(true);

      articles = <NewsArticle>[
        _article('memory-only', 'Gold price rises after inflation report', now),
        ...articles,
      ];
      newsSource.emit();
      await automation.processNow();

      expect(notifications.notifications, hasLength(1));
      expect(notifications.notifications.single.type, AppNotificationType.news);
      expect(
        preferences.getStringList('notifications.automation.seen_news_v1'),
        isNull,
      );
      expect(
        preferences.getStringList('notifications.automation.seen_signals_v1'),
        isNull,
      );
      expect(preferences.getString('app.notifications'), isNull);
    },
  );
}

class _TestNotifier extends ChangeNotifier {
  void emit() => notifyListeners();
}

NewsArticle _article(String id, String title, DateTime publishedAt) =>
    NewsArticle(
      id: id,
      title: title,
      summary: title,
      source: 'Test source',
      sourceCategory: 'اقتصاد',
      url: Uri.parse('https://example.com/$id'),
      publishedAt: publishedAt,
    );

MarketIntelligenceReport _report(
  String fingerprint,
  DateTime generatedAt, {
  required int confidence,
}) => MarketIntelligenceReport(
  symbol: 'GOLD18',
  direction: MarketScenarioDirection.upward,
  scenarioEstimatePercent: confidence,
  summary: 'Sourced scenario',
  reasons: const ['verified trend'],
  generatedAt: generatedAt,
  evidenceFingerprint: fingerprint,
  languageCode: 'persian',
  forecastTargetPrice: 20000000,
  forecastTargetSymbol: 'GOLD18',
  forecastTargetUnit: 'IRT',
  evidenceQualityPercent: 75,
  historyPointCount: 8,
  relevantNewsCount: 3,
);

Future<void> _saveNotificationSettings(
  SettingsStore store, {
  required bool master,
  required bool news,
  required bool ai,
}) => store.saveAll(
  notificationsEnabled: master,
  priceAlertsEnabled: true,
  newsAlertsEnabled: news,
  aiSignalsEnabled: ai,
  soundEnabled: false,
  interfaceSoundsEnabled: false,
  musicEnabled: false,
  interfaceVolume: 0,
  motionEnabled: true,
  reducedMotion: false,
  animationIntensity: .78,
  autoSaveEnabled: false,
  personalizedAiEnabled: true,
  marketContextEnabled: true,
  portfolioContextEnabled: false,
  watchlistContextEnabled: true,
  aiCreativity: 1,
  aiTone: 'balanced',
  crashReportsEnabled: true,
  density: 'comfortable',
  startupPage: 'dashboard',
  dataRetention: 'forever',
  currencyCode: 'auto',
);
