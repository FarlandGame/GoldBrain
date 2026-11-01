import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/ai_chat_store.dart';
import 'package:goldbrain/core/news_service.dart';
import 'package:goldbrain/core/news_store.dart';
import 'package:goldbrain/core/settings_store.dart';
import 'package:goldbrain/core/local_persistence_policy.dart';
import 'package:goldbrain/core/notification_service.dart';
import 'package:goldbrain/core/watchlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalPersistencePolicy.instance.setSuspended(false);
  });

  test('AI creativity defaults to 100 percent', () async {
    final store = SettingsStore.testing();
    await store.load();

    expect(store.aiCreativity, 1.0);
  });

  test(
    'retention safely defaults to forever and price alerts stay off',
    () async {
      final store = SettingsStore.testing();
      await store.load();

      expect(store.dataRetention, 'forever');
      expect(store.dataRetentionDeadline, isNull);
      expect(store.priceAlertsEnabled, isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('settings.data_retention'), 'forever');
      expect(preferences.getBool('settings.price_alerts_enabled'), isFalse);
    },
  );

  test(
    'notification choices persist immediately and master preserves children',
    () async {
      final store = SettingsStore.testing();
      await store.load();
      await store.saveNotificationSettings(
        notificationsEnabled: false,
        newsAlertsEnabled: true,
        aiSignalsEnabled: false,
      );

      expect(store.notificationsEnabled, isFalse);
      expect(store.priceAlertsEnabled, isFalse);
      expect(store.newsAlertsEnabled, isTrue);
      expect(store.aiSignalsEnabled, isFalse);
      final reloaded = SettingsStore.testing();
      await reloaded.load();
      expect(reloaded.notificationsEnabled, isFalse);
      expect(reloaded.newsAlertsEnabled, isTrue);
      expect(reloaded.aiSignalsEnabled, isFalse);
    },
  );

  test(
    'migrates unconfirmed legacy retention to non-destructive forever',
    () async {
      SharedPreferences.setMockInitialValues({
        'settings.data_retention': '90_days',
        'ai_chat.conversations_v1': 'keep-me',
      });
      final store = SettingsStore.testing();
      await store.load();

      expect(store.dataRetention, 'forever');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('ai_chat.conversations_v1'), 'keep-me');
    },
  );

  test(
    'stored suspension is authoritative without a migration marker',
    () async {
      SharedPreferences.setMockInitialValues({
        'settings.data_retention': '90_days',
        'settings.local_storage_suspended_v1': true,
        'settings.data_retention_confirmed_v1': true,
        'settings.data_retention_deadline_v1': '2026-01-01T00:00:00.000Z',
        'ai_chat.conversations_v1': 'must-not-be-restored-or-rewritten',
      });
      final preferences = await SharedPreferences.getInstance();
      final store = SettingsStore.testing(
        preferencesLoader: () async => preferences,
      );

      await store.load();

      expect(store.localStorageSuspended, isTrue);
      expect(store.dataRetention, '90_days');
      expect(LocalPersistencePolicy.instance.isSuspended, isTrue);
      expect(preferences.getString('ai_chat.conversations_v1'), isNull);
      expect(
        preferences.getBool('settings.data_retention_default_migrated_v1'),
        isNull,
      );
    },
  );

  test(
    'confirmed finite retention survives a missing migration marker',
    () async {
      final future = DateTime.now().toUtc().add(const Duration(days: 10));
      SharedPreferences.setMockInitialValues({
        'settings.data_retention': '30_days',
        'settings.data_retention_confirmed_v1': true,
        'settings.data_retention_deadline_v1': future.toIso8601String(),
      });
      final store = SettingsStore.testing();

      await store.load();

      expect(store.dataRetention, '30_days');
      expect(store.dataRetentionDeadline?.toUtc(), future);
      expect(store.localStorageSuspended, isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getBool('settings.data_retention_default_migrated_v1'),
        isTrue,
      );
    },
  );

  test(
    'generic settings save cannot bypass finite-retention consent',
    () async {
      final store = SettingsStore.testing();
      await store.load();

      await _saveSettings(store, dataRetention: '30_days');

      expect(store.dataRetention, 'forever');
      expect(store.dataRetentionDeadline, isNull);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('settings.data_retention'), 'forever');
      expect(
        preferences.getBool('settings.data_retention_confirmed_v1'),
        isFalse,
      );
    },
  );

  test(
    'confirmed finite retention purges only preferences at exact deadline',
    () async {
      var managedPurgeCalls = 0;
      final store = SettingsStore.testing(
        managedDataPurger: () async {
          managedPurgeCalls++;
          return true;
        },
      );
      await store.load();
      final start = DateTime(2026, 8, 13, 10);
      await store.setDataRetentionPolicy('30_days', now: start);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('ai_chat.conversations_v1', 'local-chat');
      await preferences.setString('settings.theme_code', 'purple');
      await preferences.setString('settings.language_code', 'persian');

      expect(
        await store.enforceDataRetentionNow(
          now: start.add(const Duration(days: 29, hours: 23)),
        ),
        isFalse,
      );
      expect(preferences.getString('ai_chat.conversations_v1'), 'local-chat');

      expect(
        await store.enforceDataRetentionNow(
          now: start.add(const Duration(days: 30)),
        ),
        isTrue,
      );
      expect(preferences.getString('ai_chat.conversations_v1'), isNull);
      expect(preferences.getString('settings.theme_code'), 'purple');
      expect(preferences.getString('settings.language_code'), 'persian');
      expect(store.localStorageSuspended, isTrue);
      expect(store.autoSaveEnabled, isFalse);
      expect(LocalPersistencePolicy.instance.isSuspended, isTrue);
      expect(managedPurgeCalls, 1);

      final notificationService = NotificationService.forTesting(
        preferencesLoader: () async => preferences,
      );
      await notificationService.load();
      notificationService.addNotification(title: 'memory', message: 'only');
      await Future<void>.delayed(Duration.zero);
      expect(preferences.getString('app.notifications'), isNull);
      notificationService.dispose();

      await _saveSettings(store, dataRetention: '30_days');
      expect(preferences.getString('settings.theme_code'), 'gold');
      expect(preferences.getString('settings.language_code'), 'english');
      expect(preferences.getBool('settings.sound_enabled'), isNull);
      expect(preferences.getBool('settings.music_enabled'), isNull);
      expect(preferences.getString('settings.startup_page'), isNull);
      expect(preferences.getString('settings.currency_code'), isNull);
      expect(preferences.getBool('settings.motion_enabled'), isNull);

      final chatStore = AiChatStore.testing();
      await chatStore.load(preferences: preferences);
      final conversation = await chatStore.createConversation(
        title: 'memory-only chat',
      );
      await chatStore.appendMessage(
        conversationId: conversation.id,
        text: 'not persisted after expiry',
        fromUser: true,
      );
      expect(preferences.getString('ai_chat.conversations_v1'), isNull);
      expect(preferences.getString('ai_chat.active_id_v1'), isNull);
      chatStore.dispose();

      final newsStore = NewsStore(preferencesFactory: () async => preferences);
      await newsStore.markRead(
        NewsArticle(
          id: 'expiry-news',
          title: 'Gold market update',
          summary: 'A sourced financial update.',
          source: 'Test source',
          sourceCategory: 'Economy',
          url: Uri.parse('https://example.com/expiry-news'),
          publishedAt: start,
        ),
      );
      expect(preferences.getStringList('news.read_ids.v1'), isNull);
      newsStore.dispose();

      final watchlist = WatchlistStore.instance;
      await watchlist.load();
      await watchlist.addFavorite('XAGUSD');
      expect(preferences.getStringList('watchlist.favorite_symbols'), isNull);

      final reloaded = SettingsStore.testing(
        preferencesLoader: () async => preferences,
      );
      await reloaded.load();
      expect(reloaded.localStorageSuspended, isTrue);
      expect(
        preferences.getKeys(),
        equals({
          'settings.data_retention',
          'settings.data_retention_deadline_v1',
          'settings.data_retention_confirmed_v1',
          'settings.local_storage_suspended_v1',
          'settings.managed_data_purge_complete_v1',
          'settings.data_retention_default_migrated_v1',
          'settings.theme_code',
          'settings.language_code',
        }),
      );
    },
  );

  test(
    'forever cancels scheduled deletion and resumes local persistence',
    () async {
      final store = SettingsStore.testing();
      await store.load();
      final start = DateTime(2026, 8, 13);
      await store.setDataRetentionPolicy('90_days', now: start);
      expect(store.dataRetentionDeadline, start.add(const Duration(days: 90)));

      await store.setDataRetentionPolicy('forever', now: start);
      expect(store.dataRetentionDeadline, isNull);
      expect(store.localStorageSuspended, isFalse);
      expect(LocalPersistencePolicy.instance.canWrite, isTrue);
      expect(
        await store.enforceDataRetentionNow(
          now: start.add(const Duration(days: 200)),
        ),
        isFalse,
      );

      final preferences = await SharedPreferences.getInstance();
      final notifications = NotificationService.forTesting(
        preferencesLoader: () async => preferences,
      );
      await notifications.load();
      notifications.addNotification(
        title: 'persistence resumed',
        message: 'saved after choosing forever',
      );
      await Future<void>.delayed(Duration.zero);
      expect(preferences.getString('app.notifications'), isNotNull);
      notifications.dispose();
    },
  );

  test(
    'migrates the old 45 percent default but preserves custom values',
    () async {
      SharedPreferences.setMockInitialValues({'settings.ai_creativity': 0.45});
      final oldDefault = SettingsStore.testing();
      await oldDefault.load();
      expect(oldDefault.aiCreativity, 1.0);

      SharedPreferences.setMockInitialValues({'settings.ai_creativity': 0.72});
      final custom = SettingsStore.testing();
      await custom.load();
      expect(custom.aiCreativity, 0.72);
    },
  );

  test('reset preserves appearance and custom music preference', () async {
    final store = SettingsStore.testing();
    await store.load();
    await store.saveAppearance(themeCode: 'blue', languageCode: 'persian');
    await store.saveCustomMusic(
      path: r'C:\GoldBrain Test\custom track.mp3',
      name: 'custom track.mp3',
    );

    await _saveSettings(
      store,
      notificationsEnabled: false,
      personalizedAiEnabled: false,
      marketContextEnabled: false,
      watchlistContextEnabled: false,
    );
    await store.resetDefaults();

    expect(store.themeCode, 'blue');
    expect(store.languageCode, 'persian');
    expect(store.useCustomMusic, isTrue);
    expect(store.customMusicPath, r'C:\GoldBrain Test\custom track.mp3');
    expect(store.customMusicName, 'custom track.mp3');
    expect(store.notificationsEnabled, isTrue);
    expect(store.personalizedAiEnabled, isTrue);
    expect(store.marketContextEnabled, isTrue);
    expect(store.watchlistContextEnabled, isTrue);
    expect(store.portfolioContextEnabled, isFalse);
    expect(store.aiCreativity, 1.0);
  });

  test('personalization master switch does not erase raw AI choices', () async {
    final store = SettingsStore.testing();
    await store.load();

    await _saveSettings(
      store,
      personalizedAiEnabled: false,
      marketContextEnabled: true,
      portfolioContextEnabled: true,
      watchlistContextEnabled: true,
    );

    expect(store.personalizedAiEnabled, isFalse);
    expect(store.marketContextEnabled, isTrue);
    expect(store.watchlistContextEnabled, isTrue);
    expect(store.portfolioContextEnabled, isFalse);

    final reloaded = SettingsStore.testing();
    await reloaded.load();
    expect(reloaded.personalizedAiEnabled, isFalse);
    expect(reloaded.marketContextEnabled, isTrue);
    expect(reloaded.watchlistContextEnabled, isTrue);
    expect(reloaded.portfolioContextEnabled, isFalse);
  });

  test('custom music can be cleared independently', () async {
    final store = SettingsStore.testing();
    await store.load();
    await store.saveCustomMusic(path: r'C:\music\track.m4a', name: 'track.m4a');

    await store.clearCustomMusic();

    expect(store.useCustomMusic, isFalse);
    expect(store.customMusicPath, isNull);
    expect(store.customMusicName, isNull);
  });

  test('migrates the legacy single custom track into a playlist', () async {
    SharedPreferences.setMockInitialValues({
      'settings.use_custom_music': true,
      'settings.custom_music_path': r'C:\music\legacy.mp3',
      'settings.custom_music_name': 'Legacy track',
    });
    final store = SettingsStore.testing();

    await store.load();

    expect(store.customMusicPlaylist, const [
      CustomMusicTrack(path: r'C:\music\legacy.mp3', name: 'Legacy track'),
    ]);
    expect(store.currentCustomMusicPath, r'C:\music\legacy.mp3');
    expect(store.useCustomMusic, isTrue);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList('settings.custom_music_paths_v2'), [
      r'C:\music\legacy.mp3',
    ]);
  });

  test('persists playlist, current track and playback mode', () async {
    final store = SettingsStore.testing();
    await store.load();
    await store.replaceCustomMusicPlaylist(const [
      CustomMusicTrack(path: r'C:\music\one.mp3', name: 'One'),
      CustomMusicTrack(path: r'C:\music\two.wav', name: 'Two'),
      CustomMusicTrack(path: r'C:\music\three.m4a', name: 'Three'),
    ]);
    await store.selectCustomMusic(r'C:\music\two.wav');
    await store.setMusicPlaybackMode(MusicPlaybackMode.shuffle);

    final reloaded = SettingsStore.testing();
    await reloaded.load();

    expect(reloaded.customMusicPlaylist, hasLength(3));
    expect(reloaded.currentCustomMusicTrack?.name, 'Two');
    expect(reloaded.musicPlaybackMode, MusicPlaybackMode.shuffle);
    expect(reloaded.useCustomMusic, isTrue);

    await reloaded.removeCustomMusic(r'C:\music\two.wav');
    expect(reloaded.customMusicPlaylist, hasLength(2));
    expect(reloaded.currentCustomMusicPath, r'C:\music\three.m4a');
  });

  test('master sound switch does not erase the music preference', () async {
    final store = SettingsStore.testing();
    await store.load();

    await store.saveAll(
      notificationsEnabled: true,
      priceAlertsEnabled: true,
      newsAlertsEnabled: true,
      aiSignalsEnabled: true,
      soundEnabled: false,
      interfaceSoundsEnabled: true,
      musicEnabled: true,
      interfaceVolume: 0.72,
      motionEnabled: true,
      reducedMotion: false,
      animationIntensity: 0.78,
      autoSaveEnabled: false,
      personalizedAiEnabled: true,
      marketContextEnabled: true,
      portfolioContextEnabled: false,
      watchlistContextEnabled: true,
      aiCreativity: 0.45,
      aiTone: 'balanced',
      crashReportsEnabled: true,
      density: 'comfortable',
      startupPage: 'dashboard',
      dataRetention: 'forever',
      currencyCode: 'auto',
    );

    expect(store.soundEnabled, isFalse);
    expect(store.musicEnabled, isTrue);
    expect(store.interfaceSoundsEnabled, isTrue);
  });

  test('accepts and persists the purple application theme', () async {
    final store = SettingsStore.testing();
    await store.load();

    await store.saveAppearance(themeCode: 'purple', languageCode: 'english');

    final reloaded = SettingsStore.testing();
    await reloaded.load();
    expect(reloaded.themeCode, 'purple');
  });

  test('accepts and persists white theme with Chinese language', () async {
    final store = SettingsStore.testing();
    await store.load();

    await store.saveAppearance(themeCode: 'white', languageCode: 'chinese');

    final reloaded = SettingsStore.testing();
    await reloaded.load();
    expect(reloaded.themeCode, 'white');
    expect(reloaded.languageCode, 'chinese');
  });

  test('persists every newly added theme and language code', () async {
    const themes = ['black', 'red', 'orange', 'deepBlue', 'brown'];
    const languages = ['arabic', 'turkish', 'french'];

    for (var index = 0; index < themes.length; index++) {
      final store = SettingsStore.testing();
      await store.load();
      final language = languages[index % languages.length];
      await store.saveAppearance(
        themeCode: themes[index],
        languageCode: language,
      );

      final reloaded = SettingsStore.testing();
      await reloaded.load();
      expect(reloaded.themeCode, themes[index]);
      expect(reloaded.languageCode, language);
    }
  });

  test(
    'display currency is persisted independently and notifies listeners',
    () async {
      final store = SettingsStore.testing();
      await store.load();
      var notifications = 0;
      store.addListener(() => notifications++);

      await store.saveCurrencyCode('JPY');

      expect(store.currencyCode, 'JPY');
      expect(notifications, 1);
      final reloaded = SettingsStore.testing();
      await reloaded.load();
      expect(reloaded.currencyCode, 'JPY');
    },
  );
}

Future<void> _saveSettings(
  SettingsStore store, {
  bool notificationsEnabled = true,
  bool personalizedAiEnabled = true,
  bool marketContextEnabled = true,
  bool portfolioContextEnabled = false,
  bool watchlistContextEnabled = true,
  String dataRetention = 'forever',
}) {
  return store.saveAll(
    notificationsEnabled: notificationsEnabled,
    priceAlertsEnabled: true,
    newsAlertsEnabled: true,
    aiSignalsEnabled: true,
    soundEnabled: true,
    interfaceSoundsEnabled: true,
    musicEnabled: true,
    interfaceVolume: 0.72,
    motionEnabled: true,
    reducedMotion: false,
    animationIntensity: 0.78,
    autoSaveEnabled: false,
    personalizedAiEnabled: personalizedAiEnabled,
    marketContextEnabled: marketContextEnabled,
    portfolioContextEnabled: portfolioContextEnabled,
    watchlistContextEnabled: watchlistContextEnabled,
    aiCreativity: 0.45,
    aiTone: 'balanced',
    crashReportsEnabled: true,
    density: 'comfortable',
    startupPage: 'dashboard',
    dataRetention: dataRetention,
    currencyCode: 'auto',
  );
}
