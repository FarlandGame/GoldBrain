import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_app_data_purger.dart';
import 'local_persistence_policy.dart';

enum MusicPlaybackMode { sequential, shuffle, repeatOne }

@immutable
class CustomMusicTrack {
  const CustomMusicTrack({required this.path, required this.name});

  final String path;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is CustomMusicTrack && other.path == path && other.name == name;

  @override
  int get hashCode => Object.hash(path, name);
}

class SettingsStore extends ChangeNotifier {
  SettingsStore._()
    : _enableRetentionTimer = true,
      _preferencesLoader = SharedPreferences.getInstance,
      _managedDataPurger = LocalAppDataPurger.instance.purge;

  @visibleForTesting
  SettingsStore.testing({
    Future<SharedPreferences> Function()? preferencesLoader,
    Future<bool> Function()? managedDataPurger,
  }) : _enableRetentionTimer = false,
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
       _managedDataPurger = managedDataPurger ?? (() async => true);

  static final SettingsStore instance = SettingsStore._();

  static const _notificationsEnabledKey = 'settings.notifications_enabled';
  static const _priceAlertsEnabledKey = 'settings.price_alerts_enabled';
  static const _newsAlertsEnabledKey = 'settings.news_alerts_enabled';
  static const _aiSignalsEnabledKey = 'settings.ai_signals_enabled';

  static const _soundEnabledKey = 'settings.sound_enabled';
  static const _interfaceSoundsEnabledKey = 'settings.interface_sounds_enabled';
  static const _interfaceVolumeKey = 'settings.interface_volume';
  static const _musicEnabledKey = 'settings.music_enabled';
  static const _useCustomMusicKey = 'settings.use_custom_music';
  static const _customMusicPathKey = 'settings.custom_music_path';
  static const _customMusicNameKey = 'settings.custom_music_name';
  static const _customMusicPathsKey = 'settings.custom_music_paths_v2';
  static const _customMusicNamesKey = 'settings.custom_music_names_v2';
  static const _currentCustomMusicPathKey =
      'settings.current_custom_music_path_v2';
  static const _musicPlaybackModeKey = 'settings.music_playback_mode_v2';

  static const _motionEnabledKey = 'settings.motion_enabled';
  static const _reducedMotionKey = 'settings.reduced_motion';
  static const _animationIntensityKey = 'settings.animation_intensity';

  static const _autoSaveEnabledKey = 'settings.auto_save_enabled';
  static const _autoSaveDefaultMigrationKey =
      'settings.auto_save_default_migrated_v2';
  static const _personalizedAiEnabledKey = 'settings.personalized_ai_enabled';
  static const _marketContextEnabledKey = 'settings.market_context_enabled';
  static const _portfolioContextEnabledKey =
      'settings.portfolio_context_enabled';
  static const _watchlistContextEnabledKey =
      'settings.watchlist_context_enabled';

  static const _crashReportsEnabledKey = 'settings.crash_reports_enabled';

  static const _densityKey = 'settings.density';
  static const _startupPageKey = 'settings.startup_page';
  static const _aiToneKey = 'settings.ai_tone';
  static const _dataRetentionKey = 'settings.data_retention';
  static const _dataRetentionDeadlineKey =
      'settings.data_retention_deadline_v1';
  static const _dataRetentionConfirmedKey =
      'settings.data_retention_confirmed_v1';
  static const _localStorageSuspendedKey =
      'settings.local_storage_suspended_v1';
  static const _retentionDefaultMigrationKey =
      'settings.data_retention_default_migrated_v1';
  static const _managedDataPurgeCompleteKey =
      'settings.managed_data_purge_complete_v1';
  static const _currencyCodeKey = 'settings.currency_code';
  static const _aiCreativityKey = 'settings.ai_creativity';
  static const _aiCreativityDefaultMigrationKey =
      'settings.ai_creativity_default_migrated_v3';
  static const _themeCodeKey = 'settings.theme_code';
  static const _languageCodeKey = 'settings.language_code';

  SharedPreferences? _preferences;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final Future<bool> Function() _managedDataPurger;
  bool _loaded = false;
  final bool _enableRetentionTimer;
  Timer? _retentionTimer;

  bool notificationsEnabled = true;
  bool priceAlertsEnabled = false;
  bool newsAlertsEnabled = true;
  bool aiSignalsEnabled = true;

  bool soundEnabled = true;
  bool interfaceSoundsEnabled = true;
  bool musicEnabled = true;
  double interfaceVolume = 0.72;
  bool useCustomMusic = false;
  List<CustomMusicTrack> _customMusicPlaylist = const [];
  String? currentCustomMusicPath;
  MusicPlaybackMode musicPlaybackMode = MusicPlaybackMode.sequential;

  List<CustomMusicTrack> get customMusicPlaylist =>
      List<CustomMusicTrack>.unmodifiable(_customMusicPlaylist);

  CustomMusicTrack? get currentCustomMusicTrack {
    if (_customMusicPlaylist.isEmpty) return null;
    final selectedPath = currentCustomMusicPath;
    if (selectedPath != null) {
      for (final track in _customMusicPlaylist) {
        if (track.path == selectedPath) return track;
      }
    }
    return _customMusicPlaylist.first;
  }

  // Compatibility getters for call sites and preferences created before the
  // playlist migration.
  String? get customMusicPath => currentCustomMusicTrack?.path;
  String? get customMusicName => currentCustomMusicTrack?.name;

  bool motionEnabled = true;
  bool reducedMotion = false;
  double animationIntensity = 0.78;

  bool autoSaveEnabled = false;

  bool personalizedAiEnabled = true;
  bool marketContextEnabled = true;
  bool portfolioContextEnabled = false;
  bool watchlistContextEnabled = true;
  double aiCreativity = 1.0;
  String aiTone = 'balanced';

  bool crashReportsEnabled = true;

  String density = 'comfortable';
  String startupPage = 'dashboard';
  String dataRetention = 'forever';
  DateTime? dataRetentionDeadline;
  bool localStorageSuspended = false;
  String currencyCode = 'auto';
  String themeCode = 'gold';
  String languageCode = 'english';

  bool get loaded => _loaded;

  // These features do not have a real subsystem yet.
  // Keep them disabled in the UI until their services are implemented.
  bool get cloudSyncAvailable => false;
  bool get secureLockAvailable => false;
  bool get anonymousAnalyticsAvailable => false;

  Future<void> load() async {
    _preferences ??= await _preferencesLoader();
    final prefs = _preferences!;

    final now = DateTime.now();
    _primePersistencePolicyFromStoredRetention(prefs, now);
    await _enforceRetentionDeadline(prefs, now);
    await _migrateRetentionDefault(prefs);

    notificationsEnabled = prefs.getBool(_notificationsEnabledKey) ?? true;
    // Price targets belong to the portfolio feature, which is not available
    // yet. Never leave a legacy enabled value behind because it suggests an
    // alert engine exists when it does not.
    priceAlertsEnabled = false;
    if (LocalPersistencePolicy.instance.canWrite &&
        prefs.getBool(_priceAlertsEnabledKey) != false) {
      await prefs.setBool(_priceAlertsEnabledKey, false);
    }
    newsAlertsEnabled = prefs.getBool(_newsAlertsEnabledKey) ?? true;
    aiSignalsEnabled = prefs.getBool(_aiSignalsEnabledKey) ?? true;

    soundEnabled = prefs.getBool(_soundEnabledKey) ?? true;
    interfaceSoundsEnabled = prefs.getBool(_interfaceSoundsEnabledKey) ?? true;
    musicEnabled = prefs.getBool(_musicEnabledKey) ?? true;
    interfaceVolume = (prefs.getDouble(_interfaceVolumeKey) ?? 0.72).clamp(
      0.0,
      1.0,
    );
    await _loadCustomMusic(prefs);

    motionEnabled = prefs.getBool(_motionEnabledKey) ?? true;
    reducedMotion = prefs.getBool(_reducedMotionKey) ?? false;
    animationIntensity = (prefs.getDouble(_animationIntensityKey) ?? 0.78)
        .clamp(0.0, 1.0);

    final autoSaveDefaultMigrated =
        prefs.getBool(_autoSaveDefaultMigrationKey) ?? false;
    if (autoSaveDefaultMigrated) {
      autoSaveEnabled = prefs.getBool(_autoSaveEnabledKey) ?? false;
    } else {
      autoSaveEnabled = false;
      if (LocalPersistencePolicy.instance.canWrite) {
        await Future.wait([
          prefs.setBool(_autoSaveEnabledKey, false),
          prefs.setBool(_autoSaveDefaultMigrationKey, true),
        ]);
      }
    }

    personalizedAiEnabled = prefs.getBool(_personalizedAiEnabledKey) ?? true;
    marketContextEnabled = prefs.getBool(_marketContextEnabledKey) ?? true;
    // Portfolio data is still demonstrative, so it must not be sent to AI.
    portfolioContextEnabled = false;
    if (LocalPersistencePolicy.instance.canWrite &&
        prefs.getBool(_portfolioContextEnabledKey) != false) {
      await prefs.setBool(_portfolioContextEnabledKey, false);
    }
    watchlistContextEnabled =
        prefs.getBool(_watchlistContextEnabledKey) ?? true;
    final storedAiCreativity = prefs.getDouble(_aiCreativityKey);
    final creativityDefaultMigrated =
        prefs.getBool(_aiCreativityDefaultMigrationKey) ?? false;
    final usesOldCreativityDefault =
        storedAiCreativity == null ||
        (storedAiCreativity - 0.45).abs() < 0.0001;
    aiCreativity = (!creativityDefaultMigrated && usesOldCreativityDefault)
        ? 1.0
        : (storedAiCreativity ?? 1.0).clamp(0.0, 1.0);
    if (!creativityDefaultMigrated &&
        LocalPersistencePolicy.instance.canWrite) {
      await Future.wait([
        prefs.setDouble(_aiCreativityKey, aiCreativity),
        prefs.setBool(_aiCreativityDefaultMigrationKey, true),
      ]);
    }
    aiTone = _validatedAiTone(prefs.getString(_aiToneKey) ?? 'balanced');

    crashReportsEnabled = prefs.getBool(_crashReportsEnabledKey) ?? true;

    density = _validatedDensity(prefs.getString(_densityKey) ?? 'comfortable');
    startupPage = _validatedStartupPage(
      prefs.getString(_startupPageKey) ?? 'dashboard',
    );
    dataRetention = _validatedRetention(
      prefs.getString(_dataRetentionKey) ?? 'forever',
    );
    dataRetentionDeadline = _parseUtcDate(
      prefs.getString(_dataRetentionDeadlineKey),
    )?.toLocal();
    localStorageSuspended = prefs.getBool(_localStorageSuspendedKey) ?? false;
    LocalPersistencePolicy.instance.setSuspended(localStorageSuspended);
    if (localStorageSuspended) autoSaveEnabled = false;
    currencyCode = _validatedCurrencyCode(
      prefs.getString(_currencyCodeKey) ?? 'auto',
    );
    themeCode = _validatedThemeCode(prefs.getString(_themeCodeKey) ?? 'gold');
    languageCode = _validatedLanguageCode(
      prefs.getString(_languageCodeKey) ?? 'english',
    );

    _loaded = true;
    _scheduleRetentionEnforcement();
    notifyListeners();
  }

  Future<void> saveAll({
    required bool notificationsEnabled,
    required bool priceAlertsEnabled,
    required bool newsAlertsEnabled,
    required bool aiSignalsEnabled,
    required bool soundEnabled,
    required bool interfaceSoundsEnabled,
    required bool musicEnabled,
    required double interfaceVolume,
    required bool motionEnabled,
    required bool reducedMotion,
    required double animationIntensity,
    required bool autoSaveEnabled,
    required bool personalizedAiEnabled,
    required bool marketContextEnabled,
    required bool portfolioContextEnabled,
    required bool watchlistContextEnabled,
    required double aiCreativity,
    required String aiTone,
    required bool crashReportsEnabled,
    required String density,
    required String startupPage,
    required String dataRetention,
    required String currencyCode,
    String? themeCode,
    String? languageCode,
  }) async {
    _preferences ??= await _preferencesLoader();
    final prefs = _preferences!;

    this.notificationsEnabled = notificationsEnabled;
    this.priceAlertsEnabled = false;
    // Keep child choices intact when the master notification switch is off.
    // The delivery layer applies both switches at runtime.
    this.newsAlertsEnabled = newsAlertsEnabled;
    this.aiSignalsEnabled = aiSignalsEnabled;

    this.soundEnabled = soundEnabled;
    // Preserve subordinate preferences while the master sound switch is off.
    // Runtime playback applies both switches, so re-enabling sound restores
    // the user's previous music/interface choices.
    this.interfaceSoundsEnabled = interfaceSoundsEnabled;
    this.musicEnabled = musicEnabled;
    this.interfaceVolume = interfaceVolume.clamp(0.0, 1.0);

    this.motionEnabled = motionEnabled;
    this.reducedMotion = !motionEnabled || reducedMotion;
    this.animationIntensity = animationIntensity.clamp(0.0, 1.0);

    this.autoSaveEnabled = localStorageSuspended ? false : autoSaveEnabled;

    this.personalizedAiEnabled = personalizedAiEnabled;
    // Store the user's raw preferences. The master switch is applied by the AI
    // runtime so turning personalization off does not erase these choices.
    this.marketContextEnabled = marketContextEnabled;
    this.portfolioContextEnabled = false;
    this.watchlistContextEnabled = watchlistContextEnabled;
    this.aiCreativity = aiCreativity.clamp(0.0, 1.0);
    this.aiTone = _validatedAiTone(aiTone);

    this.crashReportsEnabled = crashReportsEnabled;

    this.density = _validatedDensity(density);
    this.startupPage = _validatedStartupPage(startupPage);
    var normalizedRetention = _validatedRetention(dataRetention);
    if (normalizedRetention != this.dataRetention) {
      if (normalizedRetention == 'forever') {
        // Cancelling deletion is always safe. Finite retention, however, is
        // accepted only through setDataRetentionPolicy after the explicit
        // confirmation dialog has shown its exact deletion date.
        await _persistRetentionPolicy(normalizedRetention, DateTime.now());
      } else {
        normalizedRetention = this.dataRetention;
      }
    }
    this.dataRetention = normalizedRetention;
    this.currencyCode = _validatedCurrencyCode(currencyCode);
    this.themeCode = _validatedThemeCode(themeCode ?? this.themeCode);
    this.languageCode = _validatedLanguageCode(
      languageCode ?? this.languageCode,
    );

    if (LocalPersistencePolicy.instance.isSuspended) {
      // Keep the two recovery-critical presentation settings usable while
      // all other local persistence remains blocked.
      await Future.wait(<Future<bool>>[
        prefs.setString(_themeCodeKey, this.themeCode),
        prefs.setString(_languageCodeKey, this.languageCode),
      ]);
      notifyListeners();
      return;
    }

    await Future.wait([
      prefs.setBool(_notificationsEnabledKey, this.notificationsEnabled),
      prefs.setBool(_priceAlertsEnabledKey, this.priceAlertsEnabled),
      prefs.setBool(_newsAlertsEnabledKey, this.newsAlertsEnabled),
      prefs.setBool(_aiSignalsEnabledKey, this.aiSignalsEnabled),
      prefs.setBool(_soundEnabledKey, this.soundEnabled),
      prefs.setBool(_interfaceSoundsEnabledKey, this.interfaceSoundsEnabled),
      prefs.setBool(_musicEnabledKey, this.musicEnabled),
      prefs.setDouble(_interfaceVolumeKey, this.interfaceVolume),
      prefs.setBool(_motionEnabledKey, this.motionEnabled),
      prefs.setBool(_reducedMotionKey, this.reducedMotion),
      prefs.setDouble(_animationIntensityKey, this.animationIntensity),
      prefs.setBool(_autoSaveEnabledKey, this.autoSaveEnabled),
      prefs.setBool(_personalizedAiEnabledKey, this.personalizedAiEnabled),
      prefs.setBool(_marketContextEnabledKey, this.marketContextEnabled),
      prefs.setBool(_portfolioContextEnabledKey, this.portfolioContextEnabled),
      prefs.setBool(_watchlistContextEnabledKey, this.watchlistContextEnabled),
      prefs.setDouble(_aiCreativityKey, this.aiCreativity),
      prefs.setString(_aiToneKey, this.aiTone),
      prefs.setBool(_crashReportsEnabledKey, this.crashReportsEnabled),
      prefs.setString(_densityKey, this.density),
      prefs.setString(_startupPageKey, this.startupPage),
      prefs.setString(_dataRetentionKey, this.dataRetention),
      prefs.setString(_currencyCodeKey, this.currencyCode),
      prefs.setString(_themeCodeKey, this.themeCode),
      prefs.setString(_languageCodeKey, this.languageCode),
    ]);

    notifyListeners();
  }

  Future<void> resetDefaults() async {
    await saveAll(
      notificationsEnabled: true,
      priceAlertsEnabled: false,
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
      personalizedAiEnabled: true,
      marketContextEnabled: true,
      portfolioContextEnabled: false,
      watchlistContextEnabled: true,
      aiCreativity: 1.0,
      aiTone: 'balanced',
      crashReportsEnabled: true,
      density: 'comfortable',
      startupPage: 'dashboard',
      dataRetention: 'forever',
      currencyCode: 'auto',
    );
  }

  Future<void> saveAudioSettings({
    required bool soundEnabled,
    required bool interfaceSoundsEnabled,
    required bool musicEnabled,
    required double volume,
  }) async {
    _preferences ??= await _preferencesLoader();
    this.soundEnabled = soundEnabled;
    this.interfaceSoundsEnabled = interfaceSoundsEnabled;
    this.musicEnabled = musicEnabled;
    interfaceVolume = volume.clamp(0.0, 1.0);
    if (LocalPersistencePolicy.instance.isSuspended) {
      notifyListeners();
      return;
    }
    await Future.wait([
      _preferences!.setBool(_soundEnabledKey, this.soundEnabled),
      _preferences!.setBool(
        _interfaceSoundsEnabledKey,
        this.interfaceSoundsEnabled,
      ),
      _preferences!.setBool(_musicEnabledKey, this.musicEnabled),
      _preferences!.setDouble(_interfaceVolumeKey, interfaceVolume),
    ]);
    notifyListeners();
  }

  Future<void> saveNotificationSettings({
    required bool notificationsEnabled,
    required bool newsAlertsEnabled,
    required bool aiSignalsEnabled,
  }) async {
    _preferences ??= await _preferencesLoader();
    this.notificationsEnabled = notificationsEnabled;
    priceAlertsEnabled = false;
    this.newsAlertsEnabled = newsAlertsEnabled;
    this.aiSignalsEnabled = aiSignalsEnabled;
    if (LocalPersistencePolicy.instance.canWrite) {
      await Future.wait(<Future<bool>>[
        _preferences!.setBool(
          _notificationsEnabledKey,
          this.notificationsEnabled,
        ),
        _preferences!.setBool(_priceAlertsEnabledKey, false),
        _preferences!.setBool(_newsAlertsEnabledKey, this.newsAlertsEnabled),
        _preferences!.setBool(_aiSignalsEnabledKey, this.aiSignalsEnabled),
      ]);
    }
    notifyListeners();
  }

  Future<void> saveCustomMusic({
    required String path,
    required String name,
  }) async {
    await replaceCustomMusicPlaylist([
      CustomMusicTrack(path: path, name: name),
    ]);
  }

  Future<void> addCustomMusicTracks(
    Iterable<CustomMusicTrack> tracks, {
    bool activate = true,
  }) async {
    _preferences ??= await _preferencesLoader();
    final additions = _normalizeTracks(tracks);
    if (additions.isEmpty) {
      throw ArgumentError('At least one valid custom music track is required.');
    }

    final merged = <CustomMusicTrack>[..._customMusicPlaylist];
    for (final track in additions) {
      final existingIndex = merged.indexWhere(
        (item) => item.path == track.path,
      );
      if (existingIndex >= 0) {
        merged[existingIndex] = track;
      } else {
        merged.add(track);
      }
    }
    _customMusicPlaylist = List.unmodifiable(merged);
    currentCustomMusicPath ??= additions.first.path;
    if (activate) useCustomMusic = true;
    await _persistCustomMusic();
    notifyListeners();
  }

  Future<void> replaceCustomMusicPlaylist(
    Iterable<CustomMusicTrack> tracks, {
    String? currentPath,
    bool activate = true,
  }) async {
    _preferences ??= await _preferencesLoader();
    final normalized = _normalizeTracks(tracks);
    _customMusicPlaylist = List.unmodifiable(normalized);
    final requestedPath = _nullableText(currentPath);
    currentCustomMusicPath =
        normalized.any((track) => track.path == requestedPath)
        ? requestedPath
        : (normalized.isEmpty ? null : normalized.first.path);
    useCustomMusic = activate && normalized.isNotEmpty;
    await _persistCustomMusic();
    notifyListeners();
  }

  Future<void> selectCustomMusic(String path) async {
    _preferences ??= await _preferencesLoader();
    final normalizedPath = path.trim();
    if (!_customMusicPlaylist.any((track) => track.path == normalizedPath)) {
      throw ArgumentError('The selected track is not in the custom playlist.');
    }
    currentCustomMusicPath = normalizedPath;
    useCustomMusic = true;
    await _persistCustomMusic();
    notifyListeners();
  }

  Future<void> removeCustomMusic(String path) async {
    _preferences ??= await _preferencesLoader();
    final normalizedPath = path.trim();
    final currentIndex = _customMusicPlaylist.indexWhere(
      (track) => track.path == normalizedPath,
    );
    if (currentIndex < 0) return;

    final updated = <CustomMusicTrack>[..._customMusicPlaylist]
      ..removeAt(currentIndex);
    _customMusicPlaylist = List.unmodifiable(updated);
    if (currentCustomMusicPath == normalizedPath) {
      if (updated.isEmpty) {
        currentCustomMusicPath = null;
      } else {
        final replacementIndex = currentIndex < updated.length
            ? currentIndex
            : updated.length - 1;
        currentCustomMusicPath = updated[replacementIndex].path;
      }
    }
    if (updated.isEmpty) useCustomMusic = false;
    await _persistCustomMusic();
    notifyListeners();
  }

  Future<void> setUseCustomMusic(bool value) async {
    _preferences ??= await _preferencesLoader();
    useCustomMusic = value && _customMusicPlaylist.isNotEmpty;
    await _persistCustomMusic();
    notifyListeners();
  }

  Future<void> setMusicPlaybackMode(MusicPlaybackMode mode) async {
    _preferences ??= await _preferencesLoader();
    musicPlaybackMode = mode;
    if (LocalPersistencePolicy.instance.canWrite) {
      await _preferences!.setString(_musicPlaybackModeKey, mode.name);
    }
    notifyListeners();
  }

  Future<void> clearCustomMusic() async {
    _preferences ??= await _preferencesLoader();
    useCustomMusic = false;
    _customMusicPlaylist = const [];
    currentCustomMusicPath = null;

    if (LocalPersistencePolicy.instance.canWrite) {
      await Future.wait([
        _preferences!.setBool(_useCustomMusicKey, false),
        _preferences!.remove(_customMusicPathKey),
        _preferences!.remove(_customMusicNameKey),
        _preferences!.remove(_customMusicPathsKey),
        _preferences!.remove(_customMusicNamesKey),
        _preferences!.remove(_currentCustomMusicPathKey),
      ]);
    }
    notifyListeners();
  }

  Future<void> saveAppearance({
    required String themeCode,
    required String languageCode,
  }) async {
    _preferences ??= await _preferencesLoader();

    this.themeCode = _validatedThemeCode(themeCode);
    this.languageCode = _validatedLanguageCode(languageCode);

    // Theme/language are the only user preferences deliberately writable
    // while storage is suspended, so the retention warning stays usable.
    await Future.wait([
      _preferences!.setString(_themeCodeKey, this.themeCode),
      _preferences!.setString(_languageCodeKey, this.languageCode),
    ]);

    notifyListeners();
  }

  /// Persists the display currency independently so selecting it in Settings
  /// takes effect immediately and is not conditional on the global Save/auto
  /// save controls.
  Future<void> saveCurrencyCode(String value) async {
    _preferences ??= await _preferencesLoader();
    currencyCode = _validatedCurrencyCode(value);
    if (LocalPersistencePolicy.instance.canWrite) {
      await _preferences!.setString(_currencyCodeKey, currencyCode);
    }
    notifyListeners();
  }

  Future<void> _loadCustomMusic(SharedPreferences prefs) async {
    final storedPaths = prefs.getStringList(_customMusicPathsKey) ?? const [];
    final storedNames = prefs.getStringList(_customMusicNamesKey) ?? const [];
    final storedTracks = <CustomMusicTrack>[];
    for (var index = 0; index < storedPaths.length; index++) {
      final path = storedPaths[index].trim();
      if (path.isEmpty) continue;
      final name = index < storedNames.length ? storedNames[index].trim() : '';
      storedTracks.add(
        CustomMusicTrack(
          path: path,
          name: name.isEmpty ? _fileNameForPath(path) : name,
        ),
      );
    }

    var migratedLegacyTrack = false;
    if (storedTracks.isEmpty) {
      final legacyPath = _nullableText(prefs.getString(_customMusicPathKey));
      if (legacyPath != null) {
        final legacyName =
            _nullableText(prefs.getString(_customMusicNameKey)) ??
            _fileNameForPath(legacyPath);
        storedTracks.add(CustomMusicTrack(path: legacyPath, name: legacyName));
        migratedLegacyTrack = true;
      }
    }

    _customMusicPlaylist = List.unmodifiable(_normalizeTracks(storedTracks));
    final storedCurrentPath = _nullableText(
      prefs.getString(_currentCustomMusicPathKey),
    );
    currentCustomMusicPath =
        _customMusicPlaylist.any((track) => track.path == storedCurrentPath)
        ? storedCurrentPath
        : (_customMusicPlaylist.isEmpty
              ? null
              : _customMusicPlaylist.first.path);
    useCustomMusic =
        (prefs.getBool(_useCustomMusicKey) ??
            _customMusicPlaylist.isNotEmpty) &&
        _customMusicPlaylist.isNotEmpty;
    musicPlaybackMode = _validatedMusicPlaybackMode(
      prefs.getString(_musicPlaybackModeKey),
    );

    if (migratedLegacyTrack ||
        (prefs.getBool(_useCustomMusicKey) == true &&
            _customMusicPlaylist.isEmpty)) {
      await _persistCustomMusic();
    }
  }

  Future<void> _persistCustomMusic() async {
    if (!LocalPersistencePolicy.instance.canWrite) return;
    final prefs = _preferences!;
    final current = currentCustomMusicTrack;
    final writes = <Future<bool>>[
      prefs.setBool(_useCustomMusicKey, useCustomMusic),
      prefs.setStringList(
        _customMusicPathsKey,
        _customMusicPlaylist.map((track) => track.path).toList(),
      ),
      prefs.setStringList(
        _customMusicNamesKey,
        _customMusicPlaylist.map((track) => track.name).toList(),
      ),
      prefs.setString(_musicPlaybackModeKey, musicPlaybackMode.name),
    ];
    if (current == null) {
      writes.addAll([
        prefs.remove(_currentCustomMusicPathKey),
        prefs.remove(_customMusicPathKey),
        prefs.remove(_customMusicNameKey),
      ]);
    } else {
      writes.addAll([
        prefs.setString(_currentCustomMusicPathKey, current.path),
        prefs.setString(_customMusicPathKey, current.path),
        prefs.setString(_customMusicNameKey, current.name),
      ]);
    }
    await Future.wait(writes);
  }

  List<CustomMusicTrack> _normalizeTracks(Iterable<CustomMusicTrack> tracks) {
    final normalized = <CustomMusicTrack>[];
    final seenPaths = <String>{};
    for (final track in tracks) {
      final path = track.path.trim();
      if (path.isEmpty || !seenPaths.add(path)) continue;
      final name = track.name.trim();
      normalized.add(
        CustomMusicTrack(
          path: path,
          name: name.isEmpty ? _fileNameForPath(path) : name,
        ),
      );
    }
    return normalized;
  }

  String _fileNameForPath(String value) {
    final parts = value.split(RegExp(r'[/\\]'));
    final candidate = parts.isEmpty ? value : parts.last;
    return candidate.trim().isEmpty ? 'Custom music' : candidate.trim();
  }

  MusicPlaybackMode _validatedMusicPlaybackMode(String? value) {
    return MusicPlaybackMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => MusicPlaybackMode.sequential,
    );
  }

  int startupNavigationIndex() {
    switch (startupPage) {
      case 'markets':
        return 1;
      case 'ai':
        return 3;
      case 'dashboard':
      default:
        return 0;
    }
  }

  String _validatedDensity(String value) {
    const allowed = {'compact', 'comfortable', 'spacious'};
    return allowed.contains(value) ? value : 'comfortable';
  }

  String _validatedStartupPage(String value) {
    const allowed = {'dashboard', 'markets', 'ai'};
    return allowed.contains(value) ? value : 'dashboard';
  }

  String _validatedAiTone(String value) {
    const allowed = {'concise', 'balanced', 'detailed'};
    return allowed.contains(value) ? value : 'balanced';
  }

  String _validatedRetention(String value) {
    const allowed = {'30_days', '90_days', 'forever'};

    return allowed.contains(value) ? value : 'forever';
  }

  /// The exact local time at which a finite retention choice will expire.
  DateTime retentionDeadlineFor(String value, {DateTime? from}) {
    final base = from ?? DateTime.now();
    final days = value == '30_days' ? 30 : 90;
    return base.add(Duration(days: days));
  }

  /// Applies a retention choice immediately. Finite policies schedule one
  /// explicit, user-confirmed erase; choosing forever cancels that schedule
  /// and resumes local persistence.
  Future<void> setDataRetentionPolicy(String value, {DateTime? now}) async {
    _preferences ??= await _preferencesLoader();
    final normalized = _validatedRetention(value);
    await _persistRetentionPolicy(normalized, now ?? DateTime.now());
    dataRetention = normalized;
    if (normalized == 'forever') {
      localStorageSuspended = false;
      dataRetentionDeadline = null;
      LocalPersistencePolicy.instance.setSuspended(false);
    }
    _scheduleRetentionEnforcement();
    notifyListeners();
  }

  /// Runs the due-date check now. This is also called at startup and by a
  /// lightweight timer while the application is open.
  Future<bool> enforceDataRetentionNow({DateTime? now}) async {
    _preferences ??= await _preferencesLoader();
    final purged = await _enforceRetentionDeadline(
      _preferences!,
      now ?? DateTime.now(),
    );
    if (purged) {
      localStorageSuspended = true;
      autoSaveEnabled = false;
      LocalPersistencePolicy.instance.setSuspended(true);
      notifyListeners();
    }
    _scheduleRetentionEnforcement();
    return purged;
  }

  Future<void> _migrateRetentionDefault(SharedPreferences prefs) async {
    if (prefs.getBool(_retentionDefaultMigrationKey) == true) return;
    // A suspension decision is authoritative even if an older build never
    // wrote the migration marker. Never fail open by rewriting it to Forever.
    if (prefs.getBool(_localStorageSuspendedKey) == true) {
      LocalPersistencePolicy.instance.setSuspended(true);
      return;
    }
    final storedRetention = _validatedRetention(
      prefs.getString(_dataRetentionKey) ?? 'forever',
    );
    final storedDeadline = _parseUtcDate(
      prefs.getString(_dataRetentionDeadlineKey),
    );
    final explicitlyConfirmed =
        prefs.getBool(_dataRetentionConfirmedKey) ?? false;
    if (storedRetention != 'forever' &&
        explicitlyConfirmed &&
        storedDeadline != null) {
      // This policy came from the explicit confirmation flow and remains
      // authoritative regardless of whether its migration marker is absent.
      await prefs.setBool(_retentionDefaultMigrationKey, true);
      return;
    }
    // Previous builds silently defaulted to 90 days. Since no confirmation
    // was shown, migrate everybody to the safe, non-destructive default.
    await Future.wait(<Future<bool>>[
      prefs.setString(_dataRetentionKey, 'forever'),
      prefs.remove(_dataRetentionDeadlineKey),
      prefs.setBool(_dataRetentionConfirmedKey, false),
      prefs.setBool(_localStorageSuspendedKey, false),
      prefs.setBool(_managedDataPurgeCompleteKey, true),
      prefs.setBool(_retentionDefaultMigrationKey, true),
    ]);
  }

  Future<void> _persistRetentionPolicy(String value, DateTime now) async {
    final prefs = _preferences!;
    dataRetention = value;
    if (value == 'forever') {
      dataRetentionDeadline = null;
      localStorageSuspended = false;
      LocalPersistencePolicy.instance.setSuspended(false);
      await Future.wait(<Future<bool>>[
        prefs.setString(_dataRetentionKey, value),
        prefs.remove(_dataRetentionDeadlineKey),
        prefs.setBool(_dataRetentionConfirmedKey, false),
        prefs.setBool(_localStorageSuspendedKey, false),
        prefs.setBool(_managedDataPurgeCompleteKey, true),
      ]);
      return;
    }
    final deadline = retentionDeadlineFor(value, from: now);
    dataRetentionDeadline = deadline;
    localStorageSuspended = false;
    LocalPersistencePolicy.instance.setSuspended(false);
    await Future.wait(<Future<bool>>[
      prefs.setString(_dataRetentionKey, value),
      prefs.setString(
        _dataRetentionDeadlineKey,
        deadline.toUtc().toIso8601String(),
      ),
      prefs.setBool(_dataRetentionConfirmedKey, true),
      prefs.setBool(_localStorageSuspendedKey, false),
      prefs.setBool(_managedDataPurgeCompleteKey, true),
    ]);
  }

  Future<bool> _enforceRetentionDeadline(
    SharedPreferences prefs,
    DateTime now,
  ) async {
    final retention = _validatedRetention(
      prefs.getString(_dataRetentionKey) ?? 'forever',
    );
    final deadline = _parseUtcDate(
      prefs.getString(_dataRetentionDeadlineKey),
    )?.toLocal();
    final alreadySuspended = prefs.getBool(_localStorageSuspendedKey) ?? false;
    final explicitlyConfirmed =
        prefs.getBool(_dataRetentionConfirmedKey) ?? false;
    if (alreadySuspended) {
      LocalPersistencePolicy.instance.setSuspended(true);
      if (prefs.getBool(_managedDataPurgeCompleteKey) != true) {
        final complete = await _purgeManagedDataSafely();
        await prefs.setBool(_managedDataPurgeCompleteKey, complete);
      }
      // Re-run the preference purge on startup. This closes the recovery
      // window where an older build (or an interrupted purge) persisted the
      // suspension bit but left application data behind. The policy and the
      // two recovery preferences remain available so the user can switch
      // back to Forever deliberately.
      await _purgeOwnedPreferenceData(prefs);
      return false;
    }
    if (retention == 'forever' || deadline == null) return false;
    if (!explicitlyConfirmed) return false;
    if (now.isBefore(deadline)) return false;

    // Purge only GoldBrain-owned preferences. Keep the policy itself plus
    // language/theme so the user can understand the suspended state and
    // safely opt back into "Forever" later.
    // Gate every persistence writer before deleting data so an asynchronous
    // store cannot recreate a key while the purge is in progress.
    LocalPersistencePolicy.instance.setSuspended(true);
    await prefs.setBool(_managedDataPurgeCompleteKey, false);
    final managedDataPurged = await _purgeManagedDataSafely();
    await _purgeOwnedPreferenceData(prefs);
    await prefs.setBool(_localStorageSuspendedKey, true);
    await prefs.setBool(_managedDataPurgeCompleteKey, managedDataPurged);
    LocalPersistencePolicy.instance.setSuspended(true);
    return true;
  }

  Future<void> _purgeOwnedPreferenceData(SharedPreferences prefs) async {
    const preserved = <String>{
      _dataRetentionKey,
      _dataRetentionDeadlineKey,
      _dataRetentionConfirmedKey,
      _localStorageSuspendedKey,
      _managedDataPurgeCompleteKey,
      _retentionDefaultMigrationKey,
      _themeCodeKey,
      _languageCodeKey,
    };
    final keys = prefs.getKeys().where((key) => !preserved.contains(key));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  void _primePersistencePolicyFromStoredRetention(
    SharedPreferences prefs,
    DateTime now,
  ) {
    final alreadySuspended = prefs.getBool(_localStorageSuspendedKey) ?? false;
    final retention = _validatedRetention(
      prefs.getString(_dataRetentionKey) ?? 'forever',
    );
    final confirmed = prefs.getBool(_dataRetentionConfirmedKey) ?? false;
    final deadline = _parseUtcDate(
      prefs.getString(_dataRetentionDeadlineKey),
    )?.toLocal();
    final confirmedPolicyIsDue =
        retention != 'forever' &&
        confirmed &&
        deadline != null &&
        !now.isBefore(deadline);
    LocalPersistencePolicy.instance.setSuspended(
      alreadySuspended || confirmedPolicyIsDue,
    );
  }

  Future<bool> _purgeManagedDataSafely() async {
    try {
      return await _managedDataPurger();
    } catch (_) {
      // A locked media file can be retried at the next application startup.
      return false;
    }
  }

  DateTime? _parseUtcDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  void _scheduleRetentionEnforcement() {
    _retentionTimer?.cancel();
    if (!_enableRetentionTimer || !_loaded) return;
    if (localStorageSuspended) return;
    final deadline = dataRetentionDeadline;
    if (deadline == null) return;
    final delay = deadline.difference(DateTime.now());
    _retentionTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(enforceDataRetentionNow()),
    );
  }

  @override
  void dispose() {
    _retentionTimer?.cancel();
    super.dispose();
  }

  String _validatedCurrencyCode(String value) {
    const allowed = {
      'auto',
      'IRT',
      'IRR',
      'USD',
      'EUR',
      'GBP',
      'JPY',
      'RUB',
      'CNY',
      'AED',
      'TRY',
      'CAD',
      'AUD',
      'CHF',
      'INR',
      'SAR',
    };

    return allowed.contains(value) ? value : 'auto';
  }

  String _validatedThemeCode(String value) {
    const allowed = {
      'gold',
      'blue',
      'pink',
      'purple',
      'green',
      'white',
      'black',
      'red',
      'orange',
      'deepBlue',
      'brown',
    };
    return allowed.contains(value) ? value : 'gold';
  }

  String _validatedLanguageCode(String value) {
    const allowed = {
      'english',
      'persian',
      'japanese',
      'russian',
      'chinese',
      'arabic',
      'turkish',
      'french',
    };
    return allowed.contains(value) ? value : 'english';
  }

  String? _nullableText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
