import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../core/app_translations.dart';
import '../core/currency_service.dart';
import '../core/settings_store.dart';
import '../core/error_reporter.dart';
import 'selection_screen.dart';
import '../core/notification_service.dart';
import '../core/app_sound_service.dart';
import '../core/local_persistence_policy.dart';
import '../core/managed_app_file_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.selectedTheme,
    required this.selectedLanguage,
    this.onSettingsChanged,
  });

  final GoldBrainTheme selectedTheme;
  final GoldBrainLanguage selectedLanguage;
  final VoidCallback? onSettingsChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsStore _settingsStore = SettingsStore.instance;
  final NotificationService _notificationService = NotificationService.instance;

  bool _loading = true;
  bool _saving = false;
  bool _selectingMusic = false;
  bool _autoSaveReady = false;
  Timer? _autoSaveTimer;
  Future<void> _audioSettingsQueue = Future<void>.value();
  static const supportEmail = 'bardiya15899000@gmail.com';
  static const developerEmail = 'farland.game@gmail.com';

  bool notifications = true;
  bool priceAlerts = false;
  bool newsAlerts = true;
  bool aiAlerts = true;
  bool sounds = true;
  bool music = true;
  bool motion = true;
  bool reducedMotion = false;
  bool autoSave = false;
  bool cloudSync = false;
  bool appLock = false;
  bool analytics = false;
  bool crashReports = true;
  bool personalizedAi = true;
  bool marketContext = true;
  bool portfolioContext = false;
  bool watchlistContext = true;

  double volume = .72;
  double motionIntensity = .78;
  double aiCreativity = 1.0;

  String density = 'comfortable';
  String startupPage = 'dashboard';
  String aiTone = 'balanced';
  String retention = 'forever';
  String currencyCode = 'auto';
  late GoldBrainTheme themeChoice;
  late GoldBrainLanguage languageChoice;

  ThemePalette get palette => themePalettes[themeChoice]!;

  @override
  void initState() {
    super.initState();
    themeChoice = widget.selectedTheme;
    languageChoice = widget.selectedLanguage;
    _settingsStore.addListener(_onSettingsStoreChanged);
    _loadSettings();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _settingsStore.removeListener(_onSettingsStoreChanged);
    unawaited(AppSoundService.instance.stopPreviewAndResume());
    super.dispose();
  }

  void _onSettingsStoreChanged() {
    if (!mounted || _loading) return;
    super.setState(() {
      if (_settingsStore.localStorageSuspended) autoSave = false;
      retention = _settingsStore.dataRetention;
    });
  }

  @override
  void setState(VoidCallback fn) {
    final savingBeforeChange = _saving;
    super.setState(fn);

    if (!_autoSaveReady || savingBeforeChange != _saving) return;
    if (autoSave && !_saving) _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted && autoSave && !_saving) {
        _save(silent: true);
      }
    });
  }

  Future<void> _loadSettings() async {
    await _settingsStore.load();
    if (!mounted) return;

    setState(() {
      notifications = _settingsStore.notificationsEnabled;
      priceAlerts = _settingsStore.priceAlertsEnabled;
      newsAlerts = _settingsStore.newsAlertsEnabled;
      aiAlerts = _settingsStore.aiSignalsEnabled;
      sounds = _settingsStore.soundEnabled;
      music = _settingsStore.musicEnabled;
      volume = _settingsStore.interfaceVolume;
      motion = _settingsStore.motionEnabled;
      reducedMotion = _settingsStore.reducedMotion;
      motionIntensity = _settingsStore.animationIntensity;
      autoSave = _settingsStore.autoSaveEnabled;
      personalizedAi = _settingsStore.personalizedAiEnabled;
      marketContext = _settingsStore.marketContextEnabled;
      portfolioContext = _settingsStore.portfolioContextEnabled;
      watchlistContext = _settingsStore.watchlistContextEnabled;
      aiCreativity = _settingsStore.aiCreativity;
      aiTone = _settingsStore.aiTone;
      crashReports = _settingsStore.crashReportsEnabled;
      density = _settingsStore.density;
      startupPage = _settingsStore.startupPage;
      retention = _settingsStore.dataRetention;
      currencyCode = _settingsStore.currencyCode;
      themeChoice = _themeFromCode(_settingsStore.themeCode);
      languageChoice = _languageFromCode(_settingsStore.languageCode);

      cloudSync = false;
      appLock = false;
      analytics = false;
      _loading = false;
    });
    _autoSaveReady = true;
  }

  String tr(String en, String fa, String ja, String ru) {
    switch (languageChoice) {
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

  void _click() {
    AppSoundService.instance.playClick(enabled: sounds, volume: volume);
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: palette.primary.withValues(alpha: .35)),
          ),
          content: Text(text, style: TextStyle(color: palette.text)),
        ),
      );
  }

  void _setTransientState(VoidCallback update) {
    if (mounted) super.setState(update);
  }

  Future<void> _pickCustomMusic() async {
    if (_selectingMusic) return;

    if (!LocalPersistencePolicy.instance.canWrite) {
      _message(
        tr(
          'Local storage is paused by the retention policy. Choose Forever before adding music.',
          'ذخیره‌سازی محلی طبق سیاست نگهداری متوقف است؛ پیش از افزودن موسیقی «همیشه» را انتخاب کنید.',
          '保持ポリシーによりローカル保存が停止中です。音楽を追加する前に「無期限」を選んでください。',
          'Локальное хранение приостановлено политикой хранения. Перед добавлением музыки выберите «Всегда».',
        ),
      );
      return;
    }

    _click();
    _setTransientState(() => _selectingMusic = true);

    final copiedFiles = <File>[];
    var playlistSaved = false;
    try {
      final allowedExtensions =
          AppSoundService.supportedCustomMusicExtensions();
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );
      if (result.isEmpty) return;

      // Retention may expire while the native picker is open.
      if (!LocalPersistencePolicy.instance.canWrite) {
        _message(
          tr(
            'Local storage is paused by the retention policy. Choose Forever before adding music.',
            'ذخیره‌سازی محلی طبق سیاست نگهداری متوقف است؛ پیش از افزودن موسیقی «همیشه» را انتخاب کنید.',
            '保持ポリシーによりローカル保存が停止中です。音楽を追加する前に「無期限」を選んでください。',
            'Локальное хранение приостановлено политикой хранения. Перед добавлением музыки выберите «Всегда».',
          ),
        );
        return;
      }

      final selections = <({File source, String name, String extension})>[];
      for (final selected in result) {
        final selectedPath = selected.path?.trim();
        if (selectedPath == null || selectedPath.isEmpty) {
          throw const FileSystemException('A selected file has no local path.');
        }
        if (await selected.length() > 100 * 1024 * 1024) {
          _message(
            tr(
              'Each audio file must be smaller than 100 MB.',
              'حجم هر فایل صوتی باید کمتر از ۱۰۰ مگابایت باشد.',
              '各音声ファイルは100MB未満である必要があります。',
              'Каждый аудиофайл должен быть меньше 100 МБ.',
            ),
          );
          return;
        }
        final extension = path
            .extension(selectedPath)
            .replaceFirst('.', '')
            .toLowerCase();
        if (!allowedExtensions.contains(extension)) {
          throw const FormatException('Unsupported audio format.');
        }
        final sourceFile = File(selectedPath);
        if (!await sourceFile.exists()) {
          throw const FileSystemException(
            'A selected audio file was not found.',
          );
        }
        selections.add((
          source: sourceFile,
          name: selected.name,
          extension: extension,
        ));
      }

      final tracks = <CustomMusicTrack>[];
      for (var index = 0; index < selections.length; index++) {
        if (!LocalPersistencePolicy.instance.canWrite) {
          throw const FileSystemException(
            'Local persistence was suspended before copying music.',
          );
        }
        final selection = selections[index];
        final copied = await ManagedAppFileStore.instance.copy(
          source: selection.source,
          directoryName: 'music',
          fileName:
              'custom_${DateTime.now().microsecondsSinceEpoch}_$index.${selection.extension}',
        );
        copiedFiles.add(copied);
        tracks.add(CustomMusicTrack(path: copied.path, name: selection.name));
      }

      if (!LocalPersistencePolicy.instance.canWrite) {
        throw const FileSystemException(
          'Local persistence was suspended before saving music.',
        );
      }
      await _settingsStore.addCustomMusicTracks(tracks);
      if (!LocalPersistencePolicy.instance.canWrite) {
        throw const LocalPersistenceSuspendedException();
      }
      await _settingsStore.selectCustomMusic(tracks.first.path);
      if (!LocalPersistencePolicy.instance.canWrite) {
        throw const LocalPersistenceSuspendedException();
      }
      playlistSaved = true;
      _setTransientState(() {});

      if (sounds && music) {
        await AppSoundService.instance.previewCustomMusic(
          path: tracks.first.path,
          volume: volume,
        );
      }
      _message(
        tr(
          '${tracks.length} track(s) added to the playlist${sounds && music ? ' and the first one is playing.' : '.'}',
          '${tracks.length} قطعه به فهرست پخش اضافه شد${sounds && music ? ' و قطعه اول در حال پخش است.' : '.'}',
          '${tracks.length}曲をプレイリストに追加しました${sounds && music ? '。最初の曲を再生中です。' : '。'}',
          'Добавлено треков: ${tracks.length}${sounds && music ? '. Первый трек воспроизводится.' : '.'}',
        ),
      );
    } on LocalPersistenceSuspendedException {
      for (final copiedFile in copiedFiles) {
        await _settingsStore.removeCustomMusic(copiedFile.path);
        await _deleteFileQuietly(copiedFile);
      }
      if (mounted) {
        _message(
          tr(
            'Local storage is paused by the retention policy. Choose Forever before adding music.',
            'ذخیره‌سازی محلی طبق سیاست نگهداری متوقف است؛ پیش از افزودن موسیقی «همیشه» را انتخاب کنید.',
            '保持ポリシーによりローカル保存が停止中です。音楽を追加する前に「無期限」を選んでください。',
            'Локальное хранение приостановлено политикой хранения. Перед добавлением музыки выберите «Всегда».',
          ),
        );
      }
    } on AppSoundException {
      if (mounted) {
        _message(
          tr(
            'The playlist was saved, but this file could not be played.',
            'فهرست پخش ذخیره شد، اما این فایل قابل پخش نبود.',
            'プレイリストは保存されましたが、このファイルを再生できません。',
            'Плейлист сохранён, но этот файл не удалось воспроизвести.',
          ),
        );
      }
    } on FileSystemException {
      if (!playlistSaved) {
        for (final copiedFile in copiedFiles) {
          await _deleteFileQuietly(copiedFile);
        }
      }
      if (mounted) {
        _message(
          tr(
            'The selected audio file could not be copied.',
            'فایل صوتی انتخاب‌شده قابل کپی‌کردن نبود.',
            '選択した音声ファイルをコピーできませんでした。',
            'Не удалось скопировать выбранный аудиофайл.',
          ),
        );
      }
    } on FormatException {
      if (mounted) {
        _message(
          tr(
            'This audio format is not supported.',
            'این فرمت صوتی پشتیبانی نمی‌شود.',
            'この音声形式はサポートされていません。',
            'Этот аудиоформат не поддерживается.',
          ),
        );
      }
    } catch (error, stack) {
      if (!playlistSaved) {
        for (final copiedFile in copiedFiles) {
          await _deleteFileQuietly(copiedFile);
        }
      }
      ErrorReporter.instance.report(
        error,
        stack,
        source: 'Selecting custom background music',
      );
      if (mounted) {
        _message(
          tr(
            'Custom music could not be selected. Please try another file.',
            'انتخاب موسیقی دلخواه انجام نشد؛ فایل دیگری را امتحان کنید.',
            'カスタム音楽を選択できませんでした。別のファイルをお試しください。',
            'Не удалось выбрать музыку. Попробуйте другой файл.',
          ),
        );
      }
    } finally {
      _setTransientState(() => _selectingMusic = false);
    }
  }

  Future<void> _toggleCustomMusicPreview() async {
    final soundService = AppSoundService.instance;
    if (soundService.isPreviewing) {
      await soundService.stopPreviewAndResume();
      return;
    }

    final customPath = _settingsStore.customMusicPath;
    if (customPath == null || !File(customPath).existsSync()) {
      _message(
        tr(
          'The custom music file is missing. Choose it again.',
          'فایل موسیقی دلخواه پیدا نشد؛ دوباره آن را انتخاب کنید.',
          'カスタム音楽ファイルが見つかりません。もう一度選択してください。',
          'Файл своей музыки не найден. Выберите его снова.',
        ),
      );
      return;
    }

    try {
      await soundService.previewCustomMusic(path: customPath, volume: volume);
    } on AppSoundException {
      if (!mounted) return;
      _message(
        tr(
          'This audio file could not be played.',
          'این فایل صوتی قابل پخش نیست.',
          'この音声ファイルを再生できませんでした。',
          'Не удалось воспроизвести этот аудиофайл.',
        ),
      );
    }
  }

  Future<void> _restoreBundledMusic() async {
    await _settingsStore.setUseCustomMusic(false);

    if (AppSoundService.instance.isPreviewing) {
      await AppSoundService.instance.stopPreviewAndResume();
    } else {
      await AppSoundService.instance.refreshMusicSource();
    }
    _setTransientState(() {});

    if (!mounted) return;
    _message(
      tr(
        'GoldBrain built-in music restored.',
        'موسیقی اصلی GoldBrain دوباره فعال شد.',
        'GoldBrainの標準音楽に戻しました。',
        'Восстановлена встроенная музыка GoldBrain.',
      ),
    );
  }

  Future<void> _activateCustomPlaylist() async {
    if (_settingsStore.customMusicPlaylist.isEmpty) return;
    await _settingsStore.setUseCustomMusic(true);
    await AppSoundService.instance.refreshMusicSource();
    _setTransientState(() {});
  }

  Future<void> _selectCustomTrack(CustomMusicTrack track) async {
    await _settingsStore.selectCustomMusic(track.path);
    if (AppSoundService.instance.isPreviewing) {
      await AppSoundService.instance.stopPreviewAndResume();
    } else {
      await AppSoundService.instance.refreshMusicSource();
    }
    _setTransientState(() {});
  }

  Future<void> _removeCustomTrack(CustomMusicTrack track) async {
    await _settingsStore.removeCustomMusic(track.path);
    if (AppSoundService.instance.isPreviewing) {
      await AppSoundService.instance.stopPreviewAndResume();
    } else {
      await AppSoundService.instance.refreshMusicSource();
    }
    await _deleteManagedMusicFile(track.path);
    _setTransientState(() {});
  }

  Future<void> _clearCustomPlaylist() async {
    final paths = _settingsStore.customMusicPlaylist
        .map((track) => track.path)
        .toList(growable: false);
    await _settingsStore.clearCustomMusic();
    if (AppSoundService.instance.isPreviewing) {
      await AppSoundService.instance.stopPreviewAndResume();
    } else {
      await AppSoundService.instance.refreshMusicSource();
    }
    for (final filePath in paths) {
      await _deleteManagedMusicFile(filePath);
    }
    _setTransientState(() {});
  }

  Future<void> _changeMusicPlaybackMode(MusicPlaybackMode mode) async {
    await _settingsStore.setMusicPlaybackMode(mode);
    await AppSoundService.instance.refreshMusicSource();
    _setTransientState(() {});
  }

  Future<void> _applyAudioSettings() async {
    final soundValue = sounds;
    final musicValue = music;
    final volumeValue = volume;
    final operation = _audioSettingsQueue.then<void>((_) async {
      await _settingsStore.saveAudioSettings(
        soundEnabled: soundValue,
        interfaceSoundsEnabled: true,
        musicEnabled: musicValue,
        volume: volumeValue,
      );
      await AppSoundService.instance.startMusic(
        track: AppMusicTrack.dashboard,
        enabled: soundValue,
        musicEnabled: musicValue,
        volume: volumeValue,
      );
    });
    _audioSettingsQueue = operation.catchError((Object _) {});
    await operation;
  }

  Future<void> _deleteManagedMusicFile(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return;

    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final managedDirectory = path.normalize(
        path.absolute(path.join(supportDirectory.path, 'music')),
      );
      final candidate = path.normalize(path.absolute(filePath));
      if (!path.isWithin(managedDirectory, candidate)) return;

      await _deleteFileQuietly(File(candidate));
    } catch (_) {
      // A stale optional media file must not break settings.
    }
  }

  Future<void> _deleteFileQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Cleanup can be retried the next time the user changes the track.
    }
  }

  Future<void> _copy(String value, String label) async {
    _click();
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    _message('$label: $value');
  }

  Future<void> _copyReport() async {
    final report = [
      'GoldBrain Diagnostic Report',
      'Platform: Windows',
      'Language: ${languageChoice.name}',
      'Notifications: $notifications',
      'Sound: $sounds',
      'Motion: $motion',
      'Auto save: $autoSave',
      'Cloud sync: unavailable',
      'Personalized AI: $personalizedAi',
      'AI tone: $aiTone',
      'Startup page: $startupPage',
      'Support: $supportEmail',
      'Developer: $developerEmail',
    ].join('\n');

    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    _message(
      tr(
        'Diagnostic report copied.',
        'گزارش فنی کپی شد.',
        '診断レポートをコピーしました。',
        'Диагностический отчёт скопирован.',
      ),
    );
  }

  Future<void> _reset() async {
    _click();

    setState(() {
      _saving = true;
    });

    await _settingsStore.resetDefaults();

    if (!mounted) return;

    setState(() {
      notifications = _settingsStore.notificationsEnabled;
      priceAlerts = _settingsStore.priceAlertsEnabled;
      newsAlerts = _settingsStore.newsAlertsEnabled;
      aiAlerts = _settingsStore.aiSignalsEnabled;
      sounds = _settingsStore.soundEnabled;
      music = _settingsStore.musicEnabled;
      volume = _settingsStore.interfaceVolume;
      motion = _settingsStore.motionEnabled;
      reducedMotion = _settingsStore.reducedMotion;
      motionIntensity = _settingsStore.animationIntensity;
      autoSave = _settingsStore.autoSaveEnabled;
      personalizedAi = _settingsStore.personalizedAiEnabled;
      marketContext = _settingsStore.marketContextEnabled;
      portfolioContext = _settingsStore.portfolioContextEnabled;
      watchlistContext = _settingsStore.watchlistContextEnabled;
      aiCreativity = _settingsStore.aiCreativity;
      aiTone = _settingsStore.aiTone;
      crashReports = _settingsStore.crashReportsEnabled;
      density = _settingsStore.density;
      startupPage = _settingsStore.startupPage;
      retention = _settingsStore.dataRetention;
      currencyCode = _settingsStore.currencyCode;
      themeChoice = _themeFromCode(_settingsStore.themeCode);
      languageChoice = _languageFromCode(_settingsStore.languageCode);
      cloudSync = false;
      appLock = false;
      analytics = false;
      _saving = false;
    });

    await _applyAudioSettings();
    widget.onSettingsChanged?.call();

    _message(
      tr(
        'Settings restored and saved.',
        'تنظیمات به حالت پیش‌فرض برگشت و ذخیره شد.',
        '設定を初期値に戻して保存しました。',
        'Настройки восстановлены и сохранены.',
      ),
    );
  }

  Future<void> _save({bool silent = false}) async {
    if (_saving) return;

    if (!silent) _click();

    setState(() {
      _saving = true;
    });

    await _settingsStore.saveAll(
      notificationsEnabled: notifications,
      priceAlertsEnabled: priceAlerts,
      newsAlertsEnabled: newsAlerts,
      aiSignalsEnabled: aiAlerts,
      soundEnabled: sounds,
      interfaceSoundsEnabled: sounds,
      musicEnabled: music,
      interfaceVolume: volume,
      motionEnabled: motion,
      reducedMotion: reducedMotion,
      animationIntensity: motionIntensity,
      autoSaveEnabled: autoSave,
      personalizedAiEnabled: personalizedAi,
      marketContextEnabled: marketContext,
      portfolioContextEnabled: portfolioContext,
      watchlistContextEnabled: watchlistContext,
      aiCreativity: aiCreativity,
      aiTone: aiTone,
      crashReportsEnabled: crashReports,
      density: density,
      startupPage: startupPage,
      dataRetention: retention,
      currencyCode: currencyCode,
      themeCode: themeChoice.name,
      languageCode: languageChoice.name,
    );

    if (!mounted) return;

    setState(() {
      notifications = _settingsStore.notificationsEnabled;
      priceAlerts = _settingsStore.priceAlertsEnabled;
      newsAlerts = _settingsStore.newsAlertsEnabled;
      aiAlerts = _settingsStore.aiSignalsEnabled;
      sounds = _settingsStore.soundEnabled;
      music = _settingsStore.musicEnabled;
      volume = _settingsStore.interfaceVolume;
      motion = _settingsStore.motionEnabled;
      reducedMotion = _settingsStore.reducedMotion;
      motionIntensity = _settingsStore.animationIntensity;
      autoSave = _settingsStore.autoSaveEnabled;
      personalizedAi = _settingsStore.personalizedAiEnabled;
      marketContext = _settingsStore.marketContextEnabled;
      portfolioContext = _settingsStore.portfolioContextEnabled;
      watchlistContext = _settingsStore.watchlistContextEnabled;
      aiCreativity = _settingsStore.aiCreativity;
      aiTone = _settingsStore.aiTone;
      crashReports = _settingsStore.crashReportsEnabled;
      density = _settingsStore.density;
      startupPage = _settingsStore.startupPage;
      retention = _settingsStore.dataRetention;
      currencyCode = _settingsStore.currencyCode;
      themeChoice = _themeFromCode(_settingsStore.themeCode);
      languageChoice = _languageFromCode(_settingsStore.languageCode);
      _saving = false;
    });

    await AppSoundService.instance.startMusic(
      track: AppMusicTrack.dashboard,
      enabled: sounds,
      musicEnabled: music,
      volume: volume,
    );
    widget.onSettingsChanged?.call();
    if (silent) return;
    _notificationService.addOrReplaceNotification(
      id: 'settings-updated',
      title: tr(
        'Settings Updated',
        'تنظیمات به‌روزرسانی شد',
        '設定を更新しました',
        'Настройки обновлены',
      ),
      message: tr(
        'Your application settings have been saved successfully.',
        'تنظیمات برنامه با موفقیت ذخیره شد.',
        'アプリ設定を保存しました。',
        'Настройки приложения успешно сохранены.',
      ),
      type: AppNotificationType.settings,
    );
    await AppSoundService.instance.playSuccess(enabled: sounds, volume: volume);
    _message(
      tr(
        'Settings saved successfully.',
        'تنظیمات با موفقیت ذخیره شد.',
        '設定を保存しました。',
        'Настройки успешно сохранены.',
      ),
    );
  }

  Future<void> _testErrorReporting() async {
    _click();
    if (!crashReports) {
      _message(
        tr(
          'Enable crash reports first.',
          'ابتدا گزارش خطاهای فنی را فعال کنید.',
          '先にクラッシュレポートを有効にしてください。',
          'Сначала включите отчёты об ошибках.',
        ),
      );
      return;
    }

    await _save(silent: true);
    if (!mounted) return;

    ErrorReporter.instance.report(
      StateError('GoldBrain diagnostic test — no real failure'),
      StackTrace.current,
      source: 'Settings diagnostic test',
    );
  }

  Future<void> _setAutoSave(bool value) async {
    _click();
    setState(() => autoSave = value);
    _autoSaveTimer?.cancel();
    await _save(silent: true);
  }

  Future<void> _applyNotificationSettings() async {
    await _settingsStore.saveNotificationSettings(
      notificationsEnabled: notifications,
      newsAlertsEnabled: newsAlerts,
      aiSignalsEnabled: aiAlerts,
    );
    if (mounted) widget.onSettingsChanged?.call();
  }

  String _retentionDate(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  String _retentionWarningTitle() => switch (languageChoice) {
    GoldBrainLanguage.persian => 'تأیید حذف زمان‌بندی‌شده',
    GoldBrainLanguage.japanese => '予約削除の確認',
    GoldBrainLanguage.russian => 'Подтвердите запланированное удаление',
    GoldBrainLanguage.chinese => '确认定时删除',
    GoldBrainLanguage.arabic => 'تأكيد الحذف المجدول',
    GoldBrainLanguage.turkish => 'Planlı silmeyi onayla',
    GoldBrainLanguage.french => 'Confirmer la suppression planifiée',
    GoldBrainLanguage.english => 'Confirm scheduled deletion',
  };

  String _retentionWarningMessage(
    int days,
    String deadline,
  ) => switch (languageChoice) {
    GoldBrainLanguage.persian =>
      'در تاریخ $deadline (پس از $days روز)، همه داده‌های محلی GoldBrain پاک می‌شوند و ذخیره خودکار محلی متوقف خواهد شد. فایل‌های اصلی موسیقی شما حذف نمی‌شوند. برای لغو این برنامه و ادامه ذخیره‌سازی، «همیشه» را انتخاب کنید.',
    GoldBrainLanguage.japanese =>
      '$deadline（$days日後）にGoldBrainのローカルデータがすべて消去され、自動ローカル保存が停止します。元の音楽ファイルは削除されません。「無期限」を選ぶと、この予定を取り消して保存を再開できます。',
    GoldBrainLanguage.russian =>
      '$deadline (через $days дн.) все локальные данные GoldBrain будут удалены, а локальное автосохранение остановится. Исходные музыкальные файлы не удаляются. Выберите «Всегда», чтобы отменить удаление и возобновить сохранение.',
    GoldBrainLanguage.chinese =>
      '$deadline（$days 天后）将清除 GoldBrain 的全部本地数据，并停止本地自动保存。您的原始音乐文件不会被删除。选择“永久”可取消此计划并恢复保存。',
    GoldBrainLanguage.arabic =>
      'في $deadline (بعد $days يومًا) ستُحذف جميع بيانات GoldBrain المحلية وسيتوقف الحفظ المحلي التلقائي. لن تُحذف ملفات الموسيقى الأصلية. اختر «دائمًا» لإلغاء الجدولة واستئناف الحفظ.',
    GoldBrainLanguage.turkish =>
      '$deadline tarihinde ($days gün sonra) tüm yerel GoldBrain verileri silinecek ve otomatik yerel kayıt duracaktır. Özgün müzik dosyalarınız silinmez. Planı iptal edip kaydı sürdürmek için “Süresiz”i seçin.',
    GoldBrainLanguage.french =>
      'Le $deadline (dans $days jours), toutes les données locales de GoldBrain seront effacées et l’enregistrement local automatique s’arrêtera. Vos fichiers musicaux originaux ne seront pas supprimés. Choisissez « Toujours » pour annuler et reprendre l’enregistrement.',
    GoldBrainLanguage.english =>
      'On $deadline (in $days days), all locally stored GoldBrain data will be erased and automatic local saving will stop. Your original music files will not be deleted. Choose Forever to cancel this schedule and resume saving.',
  };

  String _retentionCancelLabel() => switch (languageChoice) {
    GoldBrainLanguage.persian => 'انصراف',
    GoldBrainLanguage.japanese => 'キャンセル',
    GoldBrainLanguage.russian => 'Отмена',
    GoldBrainLanguage.chinese => '取消',
    GoldBrainLanguage.arabic => 'إلغاء',
    GoldBrainLanguage.turkish => 'İptal',
    GoldBrainLanguage.french => 'Annuler',
    GoldBrainLanguage.english => 'Cancel',
  };

  String _retentionConfirmLabel() => switch (languageChoice) {
    GoldBrainLanguage.persian => 'تأیید و زمان‌بندی',
    GoldBrainLanguage.japanese => '確認して予約',
    GoldBrainLanguage.russian => 'Подтвердить',
    GoldBrainLanguage.chinese => '确认并安排',
    GoldBrainLanguage.arabic => 'تأكيد وجدولة',
    GoldBrainLanguage.turkish => 'Onayla ve planla',
    GoldBrainLanguage.french => 'Confirmer et planifier',
    GoldBrainLanguage.english => 'Confirm & schedule',
  };

  Future<void> _selectRetention(String value) async {
    _click();
    if (value == retention) return;
    if (value == 'forever') {
      await _settingsStore.setDataRetentionPolicy(value);
      if (!mounted) return;
      setState(() => retention = value);
      return;
    }

    final days = value == '30_days' ? 30 : 90;
    final deadline = _settingsStore.retentionDeadlineFor(value);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('retention-confirmation-dialog'),
        title: Text(_retentionWarningTitle()),
        content: Text(_retentionWarningMessage(days, _retentionDate(deadline))),
        actions: [
          TextButton(
            key: const ValueKey('retention-cancel-button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_retentionCancelLabel()),
          ),
          FilledButton(
            key: const ValueKey('retention-confirm-button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_retentionConfirmLabel()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _settingsStore.setDataRetentionPolicy(value);
    if (!mounted) return;
    setState(() => retention = value);
  }

  Future<void> _setCurrencyCode(String value) async {
    _click();
    setState(() => currencyCode = value);
    await _settingsStore.saveCurrencyCode(value);
    if (!mounted) return;
    widget.onSettingsChanged?.call();
  }

  GoldBrainTheme _themeFromCode(String value) {
    return GoldBrainTheme.values.firstWhere(
      (theme) => theme.name == value,
      orElse: () => widget.selectedTheme,
    );
  }

  GoldBrainLanguage _languageFromCode(String value) {
    return GoldBrainLanguage.values.firstWhere(
      (language) => language.name == value,
      orElse: () => widget.selectedLanguage,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        height: 620,
        child: Center(child: CircularProgressIndicator(color: palette.primary)),
      );
    }

    final rtl =
        languageChoice == GoldBrainLanguage.persian ||
        languageChoice == GoldBrainLanguage.arabic;

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: 16),
              if (compact) ...[
                _summary(),
                const SizedBox(height: 16),
                _body(),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 305, child: _summary()),
                    const SizedBox(width: 16),
                    Expanded(child: _body()),
                  ],
                ),
              const SizedBox(height: 16),
              _actions(),
            ],
          );
        },
      ),
    );
  }

  Widget _header() {
    return _Panel(
      palette: palette,
      radius: 26,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          textDirection: TextDirection.ltr,
          children: [
            _IconBox(
              palette: palette,
              icon: Icons.settings_suggest_rounded,
              size: 58,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(
                      'Application Settings',
                      'تنظیمات برنامه',
                      'アプリ設定',
                      'Настройки приложения',
                    ),
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    tr(
                      'Control appearance, alerts, sound, privacy and GoldBrain AI.',
                      'ظاهر، هشدارها، صدا، حریم خصوصی و هوش مصنوعی GoldBrain را مدیریت کنید.',
                      '外観、通知、サウンド、プライバシー、AIを管理します。',
                      'Управляйте внешним видом, уведомлениями, звуком и ИИ.',
                    ),
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF43E394).withValues(alpha: .09),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: const Color(0xFF43E394).withValues(alpha: .25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF43E394),
                    size: 16,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    tr('LOCAL MODE', 'حالت محلی', 'ローカル', 'ЛОКАЛЬНО'),
                    style: const TextStyle(
                      color: Color(0xFF43E394),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary() {
    return _Panel(
      palette: palette,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionTitle(
              palette: palette,
              icon: Icons.tune_rounded,
              title: tr(
                'Quick overview',
                'نمای کلی',
                'クイック概要',
                'Краткий обзор',
              ),
              subtitle: tr(
                'Current configuration',
                'وضعیت تنظیمات فعلی',
                '現在の構成',
                'Текущая конфигурация',
              ),
            ),
            const SizedBox(height: 16),
            _SummaryTile(
              palette: palette,
              icon: Icons.language_rounded,
              title: tr('Language', 'زبان', '言語', 'Язык'),
              value: tr('English', 'فارسی', '日本語', 'Русский'),
            ),
            const SizedBox(height: 10),
            _SummaryTile(
              palette: palette,
              icon: Icons.notifications_active_outlined,
              title: tr('Notifications', 'اعلان‌ها', '通知', 'Уведомления'),
              value: notifications
                  ? tr('Enabled', 'فعال', '有効', 'Включены')
                  : tr('Disabled', 'غیرفعال', '無効', 'Отключены'),
            ),
            const SizedBox(height: 10),
            _SummaryTile(
              palette: palette,
              icon: Icons.graphic_eq_rounded,
              title: tr('Sound', 'صدا', 'サウンド', 'Звук'),
              value: sounds
                  ? '${(volume * 100).round()}%'
                  : tr('Muted', 'بی‌صدا', 'ミュート', 'Без звука'),
            ),
            const SizedBox(height: 10),
            _SummaryTile(
              palette: palette,
              icon: Icons.psychology_alt_rounded,
              title: tr(
                'AI personalization',
                'شخصی‌سازی هوش مصنوعی',
                'AIパーソナライズ',
                'Персонализация ИИ',
              ),
              value: personalizedAi
                  ? tr('Active', 'فعال', '有効', 'Активна')
                  : tr('Off', 'خاموش', 'オフ', 'Отключена'),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: .075),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: palette.primary.withValues(alpha: .16),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.support_agent_rounded,
                    color: palette.primary,
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      'Need help?',
                      'به پشتیبانی نیاز داری؟',
                      'サポートが必要ですか？',
                      'Нужна помощь?',
                    ),
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _EmailButton(
                    palette: palette,
                    label: tr(
                      'Public support',
                      'پشتیبانی عمومی',
                      '一般サポート',
                      'Общая поддержка',
                    ),
                    email: supportEmail,
                    onTap: () => _copy(
                      supportEmail,
                      tr(
                        'Email copied',
                        'ایمیل کپی شد',
                        'コピーしました',
                        'Скопировано',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _EmailButton(
                    palette: palette,
                    label: tr(
                      'Developer contact',
                      'ارتباط با توسعه‌دهنده',
                      '開発者連絡先',
                      'Связь с разработчиком',
                    ),
                    email: developerEmail,
                    onTap: () => _copy(
                      developerEmail,
                      tr(
                        'Email copied',
                        'ایمیل کپی شد',
                        'コピーしました',
                        'Скопировано',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    return Column(
      children: [
        _SettingsSection(
          palette: palette,
          icon: Icons.palette_outlined,
          title: tr('Appearance', 'ظاهر برنامه', '外観', 'Внешний вид'),
          subtitle: tr(
            'Layout and display density',
            'چیدمان و تراکم نمایش',
            'レイアウトと表示密度',
            'Макет и плотность интерфейса',
          ),
          children: [
            _ThemePickerSetting(
              palette: palette,
              value: themeChoice,
              title: tr('Color theme', 'تم رنگی', 'カラーテーマ', 'Цветовая тема'),
              subtitle: tr(
                'Choose one of the eleven GoldBrain color systems.',
                'یکی از شش تم رنگی GoldBrain را انتخاب کنید.',
                '6つのGoldBrainカラーテーマから選択します。',
                'Выберите одну из шести цветовых тем GoldBrain.',
              ),
              onChanged: (value) {
                _click();
                setState(() => themeChoice = value);
              },
            ),
            const SizedBox(height: 10),
            _LanguagePickerSetting(
              palette: palette,
              value: languageChoice,
              title: tr(
                'Application language',
                'زبان برنامه',
                'アプリの言語',
                'Язык приложения',
              ),
              subtitle: tr(
                'Change the language without returning to the welcome screen.',
                'بدون برگشتن به صفحه شروع، زبان را تغییر دهید.',
                '開始画面に戻らず言語を変更できます。',
                'Измените язык без возврата на стартовый экран.',
              ),
              onChanged: (value) {
                _click();
                setState(() => languageChoice = value);
              },
            ),
            const SizedBox(height: 10),
            _ChoiceSetting(
              palette: palette,
              icon: Icons.view_compact_alt_outlined,
              title: tr(
                'Interface density',
                'تراکم رابط',
                '表示密度',
                'Плотность интерфейса',
              ),
              subtitle: tr(
                'Choose spacing between interface elements.',
                'فاصله میان اجزای رابط را انتخاب کنید.',
                '要素間の余白を選択します。',
                'Выберите расстояние между элементами.',
              ),
              value: density,
              options: [
                _Option(
                  'compact',
                  tr('Compact', 'فشرده', 'コンパクト', 'Компактно'),
                ),
                _Option(
                  'comfortable',
                  tr('Comfortable', 'راحت', '標準', 'Комфортно'),
                ),
                _Option('spacious', tr('Spacious', 'باز', '広め', 'Просторно')),
              ],
              onChanged: (value) {
                _click();
                setState(() => density = value);
              },
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: palette.primary.withValues(alpha: 0.16),
                ),
              ),
              child: Row(
                textDirection: TextDirection.ltr,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: palette.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr(
                        'Animation controls will be added in a future update.',
                        'کنترل‌های انیمیشن در به‌روزرسانی بعدی اضافه می‌شوند.',
                        'アニメーション設定は今後のアップデートで追加されます。',
                        'Настройки анимации появятся в следующем обновлении.',
                      ),
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: 11,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          palette: palette,
          icon: Icons.notifications_active_outlined,
          title: tr(
            'Notifications & alerts',
            'اعلان‌ها و هشدارها',
            '通知とアラート',
            'Уведомления',
          ),
          subtitle: tr(
            'Market, news and AI notifications',
            'اعلان‌های بازار، اخبار و هوش مصنوعی',
            '市場・ニュース・AI通知',
            'Рынок, новости и ИИ',
          ),
          children: [
            _SwitchSetting(
              palette: palette,
              icon: Icons.notifications_none_rounded,
              title: tr(
                'Master notifications',
                'اعلان‌های اصلی',
                '通知全体',
                'Все уведомления',
              ),
              subtitle: tr(
                'Turn all notifications on or off.',
                'همه اعلان‌ها را فعال یا غیرفعال کنید.',
                'すべての通知を切り替えます。',
                'Включить или отключить все уведомления.',
              ),
              value: notifications,
              onChanged: (value) {
                _click();
                setState(() => notifications = value);
                unawaited(_applyNotificationSettings());
              },
            ),
            const SizedBox(height: 10),
            _SwitchSetting(
              palette: palette,
              icon: Icons.price_change_outlined,
              title: tr(
                'Price alerts',
                'هشدار قیمت',
                '価格アラート',
                'Ценовые оповещения',
              ),
              subtitle: tr(
                'Coming with the portfolio and target-price feature.',
                'همراه سبد دارایی و قابلیت قیمت هدف اضافه می‌شود.',
                'ポートフォリオと目標価格機能とともに追加されます。',
                'Будет добавлено вместе с портфелем и целевыми ценами.',
              ),
              value: false,
              badge: tr('COMING SOON', 'به‌زودی', '近日公開', 'СКОРО'),
              enabled: false,
              onChanged: (_) {},
            ),
            const SizedBox(height: 10),
            _SwitchSetting(
              palette: palette,
              icon: Icons.newspaper_rounded,
              title: tr(
                'Breaking news',
                'اخبار فوری',
                '速報ニュース',
                'Срочные новости',
              ),
              subtitle: tr(
                'Notify important financial news.',
                'اخبار مالی مهم را اطلاع بده.',
                '重要な金融ニュースを通知します。',
                'Уведомлять о важных финансовых новостях.',
              ),
              value: newsAlerts,
              enabled: notifications,
              onChanged: (value) {
                _click();
                setState(() => newsAlerts = value);
                unawaited(_applyNotificationSettings());
              },
            ),
            const SizedBox(height: 10),
            _SwitchSetting(
              palette: palette,
              icon: Icons.psychology_alt_outlined,
              title: tr(
                'AI signals',
                'سیگنال‌های هوش مصنوعی',
                'AIシグナル',
                'Сигналы ИИ',
              ),
              subtitle: tr(
                'Notify strong AI confidence signals.',
                'سیگنال‌های مهم هوش مصنوعی را اطلاع بده.',
                '強いAIシグナルを通知します。',
                'Уведомлять о сильных сигналах ИИ.',
              ),
              value: aiAlerts,
              enabled: notifications,
              onChanged: (value) {
                _click();
                setState(() => aiAlerts = value);
                unawaited(_applyNotificationSettings());
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          palette: palette,
          icon: Icons.volume_up_outlined,
          title: tr('Sound', 'صدا', 'サウンド', 'Звук'),
          subtitle: tr(
            'Interface feedback and audio behavior',
            'بازخورد صوتی رابط',
            '操作音の設定',
            'Звуки интерфейса',
          ),
          children: [
            _SwitchSetting(
              palette: palette,
              icon: Icons.surround_sound_rounded,
              title: tr(
                'Application sound',
                'صدای برنامه',
                'アプリサウンド',
                'Звук приложения',
              ),
              subtitle: tr(
                'Allow interface sounds.',
                'صدای رابط برنامه فعال باشد.',
                '操作音を許可します。',
                'Разрешить звуки интерфейса.',
              ),
              value: sounds,
              onChanged: (value) {
                _click();
                setState(() => sounds = value);
                unawaited(_applyAudioSettings());
              },
            ),
            const SizedBox(height: 10),
            _SwitchSetting(
              palette: palette,
              icon: Icons.music_note_rounded,
              title: tr(
                'Background music',
                'موسیقی برنامه',
                'バックグラウンド音楽',
                'Фоновая музыка',
              ),
              subtitle: tr(
                'Play ambient GoldBrain music while using the app.',
                'موسیقی فضاساز GoldBrain هنگام کار با برنامه پخش شود.',
                'アプリ利用中にGoldBrainの環境音楽を再生します。',
                'Воспроизводить фоновую музыку GoldBrain.',
              ),
              value: music,
              enabled: sounds,
              onChanged: (value) {
                _click();
                setState(() => music = value);
                unawaited(_applyAudioSettings());
              },
            ),
            const SizedBox(height: 10),
            _CustomMusicSetting(
              palette: palette,
              language: languageChoice,
              tracks: _settingsStore.customMusicPlaylist,
              currentPath: _settingsStore.currentCustomMusicPath,
              customMusicActive: _settingsStore.useCustomMusic,
              playbackMode: _settingsStore.musicPlaybackMode,
              selecting: _selectingMusic,
              canPreview: AppSoundService.instance.isAudioAvailable,
              previewing: AppSoundService.instance.previewing,
              audioAvailable: AppSoundService.instance.isAudioAvailable,
              isWindows: Platform.isWindows,
              onChoose: () => unawaited(_pickCustomMusic()),
              onPreview: () => unawaited(_toggleCustomMusicPreview()),
              onUseBuiltIn: () => unawaited(_restoreBundledMusic()),
              onUseCustom: () => unawaited(_activateCustomPlaylist()),
              onPrevious: () =>
                  unawaited(AppSoundService.instance.previousCustomTrack()),
              onNext: () =>
                  unawaited(AppSoundService.instance.nextCustomTrack()),
              onSelect: (track) => unawaited(_selectCustomTrack(track)),
              onRemove: (track) => unawaited(_removeCustomTrack(track)),
              onClear: () => unawaited(_clearCustomPlaylist()),
              onModeChanged: (mode) =>
                  unawaited(_changeMusicPlaybackMode(mode)),
            ),
            const SizedBox(height: 10),
            _SliderSetting(
              palette: palette,
              icon: Icons.volume_down_rounded,
              title: tr(
                'Interface volume',
                'حجم صدای رابط',
                '操作音量',
                'Громкость интерфейса',
              ),
              subtitle: tr(
                'Adjust interface feedback volume.',
                'حجم صدای رابط را تنظیم کنید.',
                '操作音量を調整します。',
                'Настройте громкость интерфейса.',
              ),
              value: volume,
              enabled: sounds,
              onChanged: (value) => setState(() => volume = value),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          palette: palette,
          icon: Icons.psychology_alt_rounded,
          title: 'GoldBrain AI',
          subtitle: tr(
            'Personalization, context and response style',
            'شخصی‌سازی، زمینه و سبک پاسخ',
            'パーソナライズと回答スタイル',
            'Персонализация и стиль ответа',
          ),
          children: [
            _SwitchSetting(
              palette: palette,
              icon: Icons.auto_awesome_rounded,
              title: tr(
                'Personalized AI',
                'هوش مصنوعی شخصی‌سازی‌شده',
                'パーソナライズAI',
                'Персонализированный ИИ',
              ),
              subtitle: tr(
                'Adapt AI to your preferences.',
                'هوش مصنوعی با ترجیحات شما هماهنگ شود.',
                '利用傾向に合わせます。',
                'Адаптировать ИИ к вашим предпочтениям.',
              ),
              value: personalizedAi,
              onChanged: (value) {
                _click();
                setState(() => personalizedAi = value);
              },
            ),
            const SizedBox(height: 10),
            _ChoiceSetting(
              palette: palette,
              icon: Icons.record_voice_over_outlined,
              title: tr('Response tone', 'لحن پاسخ', '回答トーン', 'Тон ответа'),
              subtitle: tr(
                'Choose how GoldBrain explains information.',
                'نحوه توضیح اطلاعات را انتخاب کنید.',
                '説明スタイルを選びます。',
                'Выберите стиль объяснения.',
              ),
              value: aiTone,
              enabled: personalizedAi,
              options: [
                _Option('concise', tr('Concise', 'خلاصه', '簡潔', 'Кратко')),
                _Option(
                  'balanced',
                  tr('Balanced', 'متعادل', '標準', 'Сбалансированно'),
                ),
                _Option('detailed', tr('Detailed', 'جزئی', '詳細', 'Подробно')),
              ],
              onChanged: (value) {
                _click();
                setState(() => aiTone = value);
              },
            ),
            const SizedBox(height: 10),
            _SliderSetting(
              palette: palette,
              icon: Icons.lightbulb_outline_rounded,
              title: tr(
                'AI creativity',
                'خلاقیت هوش مصنوعی',
                'AI創造性',
                'Креативность ИИ',
              ),
              subtitle: tr(
                'Higher values allow broader suggestions.',
                'مقادیر بالاتر پیشنهادهای گسترده‌تری می‌دهند.',
                '高い値ほど提案が広がります。',
                'Более высокие значения расширяют предложения.',
              ),
              value: aiCreativity,
              enabled: personalizedAi,
              onChanged: (value) => setState(() => aiCreativity = value),
            ),
            const SizedBox(height: 10),
            _SwitchSetting(
              palette: palette,
              icon: Icons.candlestick_chart_rounded,
              title: tr(
                'Use market context',
                'استفاده از زمینه بازار',
                '市場コンテキスト',
                'Контекст рынка',
              ),
              subtitle: tr(
                'Let AI consider market screens.',
                'هوش مصنوعی اطلاعات بازار را در نظر بگیرد.',
                '市場情報を参照します。',
                'Разрешить ИИ учитывать рынок.',
              ),
              value: marketContext,
              enabled: personalizedAi,
              onChanged: (value) {
                _click();
                setState(() => marketContext = value);
              },
            ),
            const SizedBox(height: 10),
            _SwitchSetting(
              palette: palette,
              icon: Icons.account_balance_wallet_outlined,
              title: tr(
                'Use portfolio context',
                'استفاده از سبد دارایی',
                'ポートフォリオ参照',
                'Контекст портфеля',
              ),
              subtitle: tr(
                'Unavailable until a real portfolio data source is connected.',
                'تا زمان اتصال داده واقعی سبد دارایی، این گزینه غیرفعال است.',
                '実際のポートフォリオデータに接続するまで利用できません。',
                'Недоступно до подключения реальных данных портфеля.',
              ),
              value: false,
              enabled: false,
              badge: tr('Unavailable', 'غیرفعال', '利用不可', 'Недоступно'),
              onChanged: (_) {},
            ),
            const SizedBox(height: 10),
            _SwitchSetting(
              palette: palette,
              icon: Icons.star_outline_rounded,
              title: tr(
                'Use watchlist context',
                'استفاده از دیده‌بان',
                'ウォッチリスト参照',
                'Контекст списка наблюдения',
              ),
              subtitle: tr(
                'Prioritize assets in your watchlist.',
                'دارایی‌های دیده‌بان در اولویت باشند.',
                'ウォッチリストを優先します。',
                'Отдавать приоритет списку наблюдения.',
              ),
              value: watchlistContext,
              enabled: personalizedAi,
              onChanged: (value) {
                _click();
                setState(() => watchlistContext = value);
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          palette: palette,
          icon: Icons.currency_exchange_rounded,
          title: tr('Currency', 'واحد پول', '通貨', 'Валюта'),
          subtitle: tr(
            'Choose how prices are displayed.',
            'واحد نمایش قیمت‌ها را انتخاب کنید.',
            '価格表示の通貨を選択します。',
            'Выберите валюту отображения цен.',
          ),
          children: [
            _ChoiceSetting(
              palette: palette,
              icon: Icons.payments_outlined,
              title: tr(
                'Display currency',
                'واحد پول نمایش',
                '表示通貨',
                'Валюта отображения',
              ),
              subtitle: tr(
                'Auto follows the selected language. You can override it manually.',
                'حالت خودکار بر اساس زبان انتخاب می‌شود و می‌توانید آن را دستی تغییر دهید.',
                '自動では言語に合わせて選択され、手動変更もできます。',
                'Авто выбирается по языку, но валюту можно изменить вручную.',
              ),
              value: currencyCode,
              options: [
                _Option('auto', tr('Auto', 'خودکار', '自動', 'Авто')),
                _Option('IRT', tr('Toman', 'تومان', 'トマン', 'Томан')),
                _Option(
                  'USD',
                  tr('US Dollar', 'دلار آمریکا', '米ドル', 'Доллар США'),
                ),
                _Option('EUR', tr('Euro', 'یورو', 'ユーロ', 'Евро')),
              ],
              onChanged: (value) {
                unawaited(_setCurrencyCode(value));
              },
            ),
            const SizedBox(height: 10),
            _ChoiceSetting(
              palette: palette,
              icon: Icons.public_rounded,
              title: tr(
                'More currencies',
                'واحدهای بیشتر',
                'その他の通貨',
                'Другие валюты',
              ),
              subtitle: tr(
                'Choose another supported currency.',
                'یک واحد پول پشتیبانی‌شده دیگر انتخاب کنید.',
                '対応している別の通貨を選択します。',
                'Выберите другую поддерживаемую валюту.',
              ),
              value: currencyCode,
              options:
                  const [
                    'IRR',
                    'USDT',
                    'JPY',
                    'RUB',
                    'GBP',
                    'CNY',
                    'AED',
                    'TRY',
                    'CAD',
                    'AUD',
                    'CHF',
                    'INR',
                    'SAR',
                  ].map((code) {
                    return _Option(
                      code,
                      CurrencyService.localizedName(
                        code: code,
                        language: languageChoice,
                      ),
                    );
                  }).toList(),
              onChanged: (value) {
                unawaited(_setCurrencyCode(value));
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          palette: palette,
          icon: Icons.storage_rounded,
          title: tr(
            'Data & storage',
            'داده و ذخیره‌سازی',
            'データとストレージ',
            'Данные и хранилище',
          ),
          subtitle: tr(
            'Local save, cloud preparation and retention',
            'ذخیره محلی، فضای ابری و نگهداری داده',
            'ローカル保存とクラウド',
            'Локальное хранение и облако',
          ),
          children: [
            _SwitchSetting(
              palette: palette,
              icon: Icons.save_outlined,
              title: tr(
                'Automatic saving of local changes',
                'ذخیره خودکار تغییرات محلی',
                '自動ローカル保存',
                'Автосохранение локально',
              ),
              subtitle: tr(
                'Save profile and settings changes automatically.',
                'تغییرات پروفایل و تنظیمات خودکار ذخیره شوند.',
                '変更を自動保存します。',
                'Автоматически сохранять изменения.',
              ),
              value: autoSave,
              badge: _settingsStore.localStorageSuspended
                  ? tr('PAUSED', 'متوقف', '停止中', 'ПРИОСТАНОВЛЕНО')
                  : tr('IMPORTANT', 'مهم', '重要', 'ВАЖНО'),
              enabled: !_settingsStore.localStorageSuspended,
              tooltip: tr(
                'When enabled, every supported settings and profile change is saved automatically, so you do not need to press Save repeatedly.',
                'اگر فعال باشد، تغییرات پشتیبانی‌شده تنظیمات و پروفایل خودکار ذخیره می‌شوند و لازم نیست هر بار دکمه ذخیره را بزنید.',
                '有効にすると、対応する設定とプロフィールの変更が自動保存され、毎回保存ボタンを押す必要がありません。',
                'Если включено, поддерживаемые изменения настроек и профиля сохраняются автоматически.',
              ),
              onChanged: _setAutoSave,
            ),
            const SizedBox(height: 10),
            _SwitchSetting(
              palette: palette,
              icon: Icons.cloud_sync_outlined,
              title: tr(
                'Cloud synchronization',
                'همگام‌سازی ابری',
                'クラウド同期',
                'Облачная синхронизация',
              ),
              subtitle: tr(
                'Prepared for future account infrastructure.',
                'برای اتصال آینده حساب و فضای ابری آماده شده است.',
                '将来のクラウド接続向けです。',
                'Подготовлено для будущего облака.',
              ),
              value: cloudSync,
              badge: tr('COMING SOON', 'به‌زودی', '近日公開', 'СКОРО'),
              enabled: false,
              onChanged: (value) {
                _click();
                setState(() => cloudSync = value);
              },
            ),
            const SizedBox(height: 10),
            _ChoiceSetting(
              palette: palette,
              icon: Icons.history_rounded,
              title: tr(
                'Local data retention',
                'مدت نگهداری داده محلی',
                'データ保持期間',
                'Хранение локальных данных',
              ),
              subtitle: tr(
                'Choose how long local history is kept.',
                'مدت نگهداری تاریخچه محلی را انتخاب کنید.',
                '履歴の保持期間を選びます。',
                'Выберите срок хранения истории.',
              ),
              value: retention,
              options: [
                _Option('30_days', tr('30 days', '۳۰ روز', '30日', '30 дней')),
                _Option('90_days', tr('90 days', '۹۰ روز', '90日', '90 дней')),
                _Option('forever', tr('Forever', 'همیشه', '無期限', 'Всегда')),
              ],
              onChanged: (value) => unawaited(_selectRetention(value)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          palette: palette,
          icon: Icons.security_rounded,
          title: tr(
            'Security & privacy',
            'امنیت و حریم خصوصی',
            'セキュリティとプライバシー',
            'Безопасность и приватность',
          ),
          subtitle: tr(
            'Lock, analytics and diagnostic data',
            'قفل، آمار استفاده و داده‌های فنی',
            'ロックと診断データ',
            'Блокировка и диагностика',
          ),
          children: [
            _SwitchSetting(
              palette: palette,
              icon: Icons.fingerprint_rounded,
              title: tr(
                'Secure application lock',
                'قفل امن برنامه',
                'アプリロック',
                'Защищённая блокировка',
              ),
              subtitle: tr(
                'Require verification when the app starts.',
                'هنگام شروع برنامه تأیید درخواست شود.',
                '起動時に認証します。',
                'Требовать проверку при запуске.',
              ),
              value: appLock,
              badge: tr('PLANNED', 'برنامه‌ریزی‌شده', '予定', 'В ПЛАНАХ'),
              enabled: false,
              onChanged: (value) {
                _click();
                setState(() => appLock = value);
              },
            ),
            const SizedBox(height: 10),
            _SwitchSetting(
              palette: palette,
              icon: Icons.analytics_outlined,
              title: tr(
                'Anonymous analytics',
                'آمار ناشناس',
                '匿名分析',
                'Анонимная аналитика',
              ),
              subtitle: tr(
                'Share anonymous usage statistics.',
                'آمار استفاده ناشناس ارسال شود.',
                '匿名利用統計を共有します。',
                'Отправлять анонимную статистику.',
              ),
              value: analytics,
              enabled: false,
              onChanged: (value) {
                _click();
                setState(() => analytics = value);
              },
            ),
            const SizedBox(height: 10),
            _SwitchSetting(
              palette: palette,
              icon: Icons.bug_report_outlined,
              title: tr(
                'Crash reports',
                'گزارش خطاهای فنی',
                'クラッシュレポート',
                'Отчёты о сбоях',
              ),
              subtitle: tr(
                'Capture Flutter and Dart errors and show them in notifications.',
                'خطاهای Flutter و Dart ثبت و داخل اعلان‌ها نمایش داده شوند.',
                'FlutterとDartのエラーを記録し、通知に表示します。',
                'Записывать ошибки Flutter и Dart и показывать их в уведомлениях.',
              ),
              value: crashReports,
              onChanged: (value) {
                _click();
                setState(() => crashReports = value);
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          palette: palette,
          icon: Icons.rocket_launch_outlined,
          title: tr('Startup', 'شروع برنامه', '起動設定', 'Запуск'),
          subtitle: tr(
            'Choose the first screen after launch',
            'صفحه نخست بعد از اجرا را انتخاب کنید',
            '起動後の画面を選びます',
            'Выберите первый экран',
          ),
          children: [
            _ChoiceSetting(
              palette: palette,
              icon: Icons.home_outlined,
              title: tr(
                'Startup page',
                'صفحه شروع',
                '起動画面',
                'Стартовая страница',
              ),
              subtitle: tr(
                'Select the default destination after login.',
                'مقصد پیش‌فرض بعد از ورود را انتخاب کنید.',
                'ログイン後の画面を選びます。',
                'Выберите экран после входа.',
              ),
              value: startupPage,
              options: [
                _Option(
                  'dashboard',
                  tr('Dashboard', 'داشبورد', 'ダッシュボード', 'Панель'),
                ),
                _Option('markets', tr('Markets', 'بازارها', '市場', 'Рынки')),
                _Option(
                  'ai',
                  tr(
                    'AI Assistant',
                    'دستیار هوشمند',
                    'AIアシスタント',
                    'ИИ-помощник',
                  ),
                ),
              ],
              onChanged: (value) {
                _click();
                setState(() => startupPage = value);
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        _support(),
      ],
    );
  }

  Widget _support() {
    return _SettingsSection(
      palette: palette,
      icon: Icons.support_agent_rounded,
      title: tr(
        'Support & bug reports',
        'پشتیبانی و گزارش خطا',
        'サポートと不具合報告',
        'Поддержка и ошибки',
      ),
      subtitle: tr(
        'Contact the GoldBrain developer',
        'ارتباط با توسعه‌دهنده GoldBrain',
        '開発者への連絡',
        'Связь с разработчиком',
      ),
      children: [
        _SupportTile(
          palette: palette,
          icon: Icons.public_rounded,
          title: tr(
            'Public support email',
            'ایمیل عمومی پشتیبانی',
            '一般サポートメール',
            'Общая почта поддержки',
          ),
          email: supportEmail,
          description: tr(
            'Recommended for questions and bug reports.',
            'پیشنهادی برای پرسش‌ها و گزارش خطا.',
            '質問や不具合報告に推奨。',
            'Для вопросов и сообщений об ошибках.',
          ),
          onCopy: () => _copy(
            supportEmail,
            tr('Email copied', 'ایمیل کپی شد', 'コピーしました', 'Скопировано'),
          ),
        ),
        const SizedBox(height: 10),
        _SupportTile(
          palette: palette,
          icon: Icons.code_rounded,
          title: tr(
            'Developer email',
            'ایمیل شخصی توسعه‌دهنده',
            '開発者メール',
            'Почта разработчика',
          ),
          email: developerEmail,
          description: tr(
            'For important technical cases.',
            'برای موارد فنی مهم و بررسی مستقیم.',
            '重要な技術問題向け。',
            'Для важных технических случаев.',
          ),
          onCopy: () => _copy(
            developerEmail,
            tr('Email copied', 'ایمیل کپی شد', 'コピーしました', 'Скопировано'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _copyReport,
            icon: Icon(Icons.content_copy_rounded, color: palette.primary),
            label: Text(
              tr(
                'Copy diagnostic report',
                'کپی گزارش فنی',
                '診断レポートをコピー',
                'Копировать диагностику',
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.text,
              padding: const EdgeInsets.symmetric(vertical: 15),
              side: BorderSide(color: palette.primary.withValues(alpha: .30)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _testErrorReporting,
            icon: Icon(Icons.notification_add_outlined, color: palette.primary),
            label: Text(
              tr(
                'Test technical-error notification',
                'آزمایش اعلان خطای فنی',
                '技術エラー通知をテスト',
                'Проверить уведомление об ошибке',
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.text,
              padding: const EdgeInsets.symmetric(vertical: 15),
              side: BorderSide(color: palette.primary.withValues(alpha: .30)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actions() {
    return _Panel(
      palette: palette,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 650;
            final reset = OutlinedButton.icon(
              onPressed: _saving ? null : _reset,
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(
                tr(
                  'Restore defaults',
                  'بازگشت به پیش‌فرض',
                  '初期値に戻す',
                  'Сбросить настройки',
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF7D89),
                side: BorderSide(
                  color: const Color(0xFFFF7D89).withValues(alpha: .32),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            );
            final save = FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.isLight ? Colors.white : Colors.black,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(
                tr(
                  'Save settings',
                  'ذخیره تنظیمات',
                  '設定を保存',
                  'Сохранить настройки',
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: palette.primary,
                foregroundColor: palette.isLight ? Colors.white : Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [reset, const SizedBox(height: 10), save],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: Text(
                    tr(
                      'Supported settings are saved locally on this device.',
                      'تنظیمات پشتیبانی‌شده روی همین دستگاه ذخیره می‌شوند.',
                      '対応する設定はこの端末に保存されます。',
                      'Поддерживаемые настройки сохраняются на этом устройстве.',
                    ),
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 10,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                reset,
                const SizedBox(width: 10),
                save,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.palette, required this.child, this.radius = 24});
  final ThemePalette palette;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: .86),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: palette.primary.withValues(alpha: .17)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 26,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final ThemePalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      palette: palette,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionTitle(
              palette: palette,
              icon: icon,
              title: title,
              subtitle: subtitle,
            ),
            const SizedBox(height: 15),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final ThemePalette palette;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: TextDirection.ltr,
      children: [
        _IconBox(palette: palette, icon: icon),
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
                style: TextStyle(
                  color: palette.mutedText,
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.palette, required this.icon, this.size = 42});
  final ThemePalette palette;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.primary.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(size * .33),
        border: Border.all(color: palette.primary.withValues(alpha: .18)),
      ),
      child: Icon(icon, color: palette.primary, size: size * .5),
    );
  }
}

class _ThemePickerSetting extends StatelessWidget {
  const _ThemePickerSetting({
    required this.palette,
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final ThemePalette palette;
  final GoldBrainTheme value;
  final String title;
  final String subtitle;
  final ValueChanged<GoldBrainTheme> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingShell(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.palette_outlined, color: palette.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: 9.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: GoldBrainTheme.values.map((theme) {
              final optionPalette = themePalettes[theme]!;
              final selected = theme == value;
              return Tooltip(
                message: theme.name,
                child: InkWell(
                  onTap: () => onChanged(theme),
                  borderRadius: BorderRadius.circular(18),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    width: 64,
                    height: 50,
                    decoration: BoxDecoration(
                      color: optionPalette.background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? optionPalette.primary
                            : optionPalette.primary.withValues(alpha: .32),
                        width: selected ? 2.4 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: optionPalette.primary.withValues(
                                  alpha: .28,
                                ),
                                blurRadius: 18,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              optionPalette.primary,
                              optionPalette.secondary,
                            ],
                          ),
                        ),
                        child: selected
                            ? Icon(
                                Icons.check_rounded,
                                color: optionPalette.isLight
                                    ? Colors.white
                                    : Colors.black,
                                size: 17,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _LanguagePickerSetting extends StatelessWidget {
  const _LanguagePickerSetting({
    required this.palette,
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final ThemePalette palette;
  final GoldBrainLanguage value;
  final String title;
  final String subtitle;
  final ValueChanged<GoldBrainLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = <GoldBrainLanguage, String>{
      GoldBrainLanguage.english: 'English',
      GoldBrainLanguage.persian: 'فارسی',
      GoldBrainLanguage.japanese: '日本語',
      GoldBrainLanguage.russian: 'Русский',
      GoldBrainLanguage.chinese: '简体中文',
      GoldBrainLanguage.arabic: 'العربية',
      GoldBrainLanguage.turkish: 'Türkçe',
      GoldBrainLanguage.french: 'Français',
    };

    return _SettingShell(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.language_rounded, color: palette.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: 9.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: GoldBrainLanguage.values.map((language) {
              final selected = language == value;
              return InkWell(
                onTap: () => onChanged(language),
                borderRadius: BorderRadius.circular(13),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 17,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(
                      alpha: selected ? .16 : .045,
                    ),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: palette.primary.withValues(
                        alpha: selected ? .62 : .15,
                      ),
                    ),
                  ),
                  child: Text(
                    labels[language]!,
                    textDirection:
                        language == GoldBrainLanguage.persian ||
                            language == GoldBrainLanguage.arabic
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    style: TextStyle(
                      color: selected ? palette.secondary : palette.text,
                      fontSize: 10.5,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.badge,
    this.tooltip,
  });
  final ThemePalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final String? badge;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final setting = _SettingShell(
      palette: palette,
      child: Row(
        children: [
          Icon(
            icon,
            color: enabled ? palette.primary : palette.mutedText,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: palette.primary.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            color: palette.primary,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: palette.mutedText,
                    fontSize: 9.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: palette.isLight ? Colors.white : Colors.black,
            activeTrackColor: palette.primary,
            inactiveThumbColor: palette.mutedText,
            inactiveTrackColor: palette.background,
          ),
        ],
      ),
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : .48,
      child: tooltip == null
          ? setting
          : Tooltip(
              message: tooltip!,
              waitDuration: const Duration(milliseconds: 350),
              child: setting,
            ),
    );
  }
}

class _CustomMusicSetting extends StatelessWidget {
  const _CustomMusicSetting({
    required this.palette,
    required this.language,
    required this.tracks,
    required this.currentPath,
    required this.customMusicActive,
    required this.playbackMode,
    required this.selecting,
    required this.canPreview,
    required this.previewing,
    required this.audioAvailable,
    required this.isWindows,
    required this.onChoose,
    required this.onPreview,
    required this.onUseBuiltIn,
    required this.onUseCustom,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
    required this.onRemove,
    required this.onClear,
    required this.onModeChanged,
  });

  final ThemePalette palette;
  final GoldBrainLanguage language;
  final List<CustomMusicTrack> tracks;
  final String? currentPath;
  final bool customMusicActive;
  final MusicPlaybackMode playbackMode;
  final bool selecting;
  final bool canPreview;
  final ValueListenable<bool> previewing;
  final bool audioAvailable;
  final bool isWindows;
  final VoidCallback onChoose;
  final VoidCallback onPreview;
  final VoidCallback onUseBuiltIn;
  final VoidCallback onUseCustom;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<CustomMusicTrack> onSelect;
  final ValueChanged<CustomMusicTrack> onRemove;
  final VoidCallback onClear;
  final ValueChanged<MusicPlaybackMode> onModeChanged;

  String tr(String en, String fa, String ja, String ru) {
    switch (language) {
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

  CustomMusicTrack? get currentTrack {
    for (final track in tracks) {
      if (track.path == currentPath) return track;
    }
    return tracks.isEmpty ? null : tracks.first;
  }

  String modeLabel(MusicPlaybackMode mode) {
    switch (mode) {
      case MusicPlaybackMode.sequential:
        return tr('Sequential', 'ترتیبی', '順番', 'По порядку');
      case MusicPlaybackMode.shuffle:
        return tr('Shuffle', 'تصادفی', 'シャッフル', 'Случайно');
      case MusicPlaybackMode.repeatOne:
        return tr('Repeat one', 'تکرار یک قطعه', '1曲リピート', 'Повтор трека');
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedTrack = currentTrack;
    final selectedFileAvailable =
        selectedTrack != null && File(selectedTrack.path).existsSync();
    final status = !audioAvailable
        ? tr(
            'Local audio could not be initialized.',
            'پخش محلی صدا راه‌اندازی نشد.',
            'ローカル音声を初期化できませんでした。',
            'Локальное аудио не удалось запустить.',
          )
        : tracks.isEmpty
        ? tr(
            'Built-in GoldBrain music is active.',
            'موسیقی داخلی GoldBrain فعال است.',
            'GoldBrainの内蔵音楽が有効です。',
            'Активна встроенная музыка GoldBrain.',
          )
        : !selectedFileAvailable
        ? tr(
            'The current track is missing. Select or remove it.',
            'قطعه فعلی پیدا نشد؛ آن را انتخاب یا حذف کنید.',
            '現在の曲が見つかりません。選択または削除してください。',
            'Текущий трек не найден. Выберите или удалите его.',
          )
        : customMusicActive
        ? tr(
            'Custom playlist active · ${tracks.length} track(s) · ${selectedTrack.name}',
            'فهرست دلخواه فعال · ${tracks.length} قطعه · ${selectedTrack.name}',
            'カスタム再生中 · ${tracks.length}曲 · ${selectedTrack.name}',
            'Свой плейлист · ${tracks.length} треков · ${selectedTrack.name}',
          )
        : tr(
            'Built-in music active · ${tracks.length} custom track(s) saved',
            'موسیقی داخلی فعال · ${tracks.length} قطعه دلخواه ذخیره شده',
            '内蔵音楽を再生中 · カスタム${tracks.length}曲を保存済み',
            'Встроенная музыка · сохранено треков: ${tracks.length}',
          );
    final statusColor =
        !audioAvailable || (selectedTrack != null && !selectedFileAvailable)
        ? const Color(0xFFFF8A80)
        : palette.mutedText;

    return _SettingShell(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.library_music_outlined,
                color: palette.primary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        'Custom music playlist',
                        'فهرست موسیقی دلخواه',
                        'カスタムプレイリスト',
                        'Свой плейлист',
                      ),
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(
                        'Choose several local tracks, select the current one and control playback order.',
                        'چند قطعه محلی انتخاب کنید، قطعه فعلی و ترتیب پخش را مدیریت کنید.',
                        '複数のローカル曲を選び、現在の曲と再生順を管理します。',
                        'Выберите несколько локальных треков и настройте порядок.',
                      ),
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: 9.5,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isWindows
                          ? tr(
                              'Windows formats: MP3, WAV, M4A and AAC. Originals are never modified.',
                              'فرمت‌های ویندوز: MP3، WAV، M4A و AAC. فایل اصلی تغییر نمی‌کند.',
                              'Windows対応: MP3、WAV、M4A、AAC。元ファイルは変更されません。',
                              'Windows: MP3, WAV, M4A и AAC. Оригиналы не изменяются.',
                            )
                          : tr(
                              'Supported: MP3, WAV, M4A, AAC, FLAC and OGG. Originals are never modified.',
                              'فرمت‌ها: MP3، WAV، M4A، AAC، FLAC و OGG. فایل اصلی تغییر نمی‌کند.',
                              '対応: MP3、WAV、M4A、AAC、FLAC、OGG。元ファイルは変更されません。',
                              'Форматы: MP3, WAV, M4A, AAC, FLAC и OGG. Оригиналы не изменяются.',
                            ),
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: 9,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<bool>(
            valueListenable: previewing,
            builder: (context, isPreviewing, child) {
              return Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  OutlinedButton.icon(
                    onPressed: selecting ? null : onChoose,
                    icon: selecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.audio_file_outlined, size: 18),
                    label: Text(
                      tr(
                        'Add files',
                        'افزودن فایل‌ها',
                        'ファイル追加',
                        'Добавить файлы',
                      ),
                    ),
                  ),
                  if (selectedTrack != null)
                    FilledButton.tonalIcon(
                      onPressed:
                          audioAvailable && selectedFileAvailable && canPreview
                          ? onPreview
                          : null,
                      icon: Icon(
                        isPreviewing
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline_rounded,
                        size: 18,
                      ),
                      label: Text(
                        isPreviewing
                            ? tr('Stop', 'توقف', '停止', 'Остановить')
                            : tr('Preview', 'پیش‌نمایش', '試聴', 'Прослушать'),
                      ),
                    ),
                  if (tracks.length > 1) ...[
                    PlaylistTransportControls(
                      previousTooltip: tr(
                        'Previous track',
                        'قطعه قبلی',
                        '前の曲',
                        'Предыдущий трек',
                      ),
                      nextTooltip: tr(
                        'Next track',
                        'قطعه بعدی',
                        '次の曲',
                        'Следующий трек',
                      ),
                      onPrevious: onPrevious,
                      onNext: onNext,
                    ),
                  ],
                  if (tracks.isNotEmpty && customMusicActive)
                    TextButton.icon(
                      onPressed: selecting ? null : onUseBuiltIn,
                      icon: const Icon(Icons.album_outlined, size: 18),
                      label: Text(
                        tr(
                          'Use built-in',
                          'استفاده از موسیقی داخلی',
                          '内蔵音楽を使う',
                          'Встроенная музыка',
                        ),
                      ),
                    ),
                  if (tracks.isNotEmpty && !customMusicActive)
                    FilledButton.tonalIcon(
                      onPressed: onUseCustom,
                      icon: const Icon(Icons.queue_music_rounded, size: 18),
                      label: Text(
                        tr(
                          'Use playlist',
                          'فعال‌کردن فهرست',
                          'プレイリストを使う',
                          'Включить плейлист',
                        ),
                      ),
                    ),
                  if (tracks.isNotEmpty)
                    TextButton.icon(
                      onPressed: selecting ? null : onClear,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: Text(
                        tr(
                          'Clear playlist',
                          'پاک‌کردن فهرست',
                          'リストを消去',
                          'Очистить список',
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (tracks.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: MusicPlaybackMode.values.map((mode) {
                return ChoiceChip(
                  selected: playbackMode == mode,
                  onSelected: (_) => onModeChanged(mode),
                  avatar: Icon(switch (mode) {
                    MusicPlaybackMode.sequential => Icons.repeat_rounded,
                    MusicPlaybackMode.shuffle => Icons.shuffle_rounded,
                    MusicPlaybackMode.repeatOne => Icons.repeat_one_rounded,
                  }, size: 16),
                  label: Text(modeLabel(mode)),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: tracks.length > 3 ? 216 : tracks.length * 68,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: tracks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  final selected = track.path == currentPath;
                  final available = File(track.path).existsSync();
                  return Material(
                    color: selected
                        ? palette.primary.withValues(alpha: .12)
                        : palette.background.withValues(alpha: .34),
                    borderRadius: BorderRadius.circular(13),
                    child: ListTile(
                      dense: true,
                      onTap: available ? () => onSelect(track) : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                        side: BorderSide(
                          color: selected
                              ? palette.primary.withValues(alpha: .45)
                              : palette.primary.withValues(alpha: .10),
                        ),
                      ),
                      leading: Icon(
                        selected
                            ? Icons.graphic_eq_rounded
                            : Icons.music_note_rounded,
                        color: available
                            ? palette.primary
                            : const Color(0xFFFF8A80),
                      ),
                      title: Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        available
                            ? (selected
                                  ? tr(
                                      'Current track',
                                      'قطعه فعلی',
                                      '現在の曲',
                                      'Текущий трек',
                                    )
                                  : tr(
                                      'Select track',
                                      'انتخاب قطعه',
                                      '曲を選択',
                                      'Выбрать трек',
                                    ))
                            : tr(
                                'File missing',
                                'فایل پیدا نشد',
                                'ファイルなし',
                                'Файл не найден',
                              ),
                        style: TextStyle(
                          color: available
                              ? palette.mutedText
                              : const Color(0xFFFF8A80),
                          fontSize: 9,
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: tr(
                          'Remove from playlist',
                          'حذف از فهرست',
                          'リストから削除',
                          'Удалить из списка',
                        ),
                        onPressed: () => onRemove(track),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Media transport controls deliberately keep the universal physical order
/// (previous on the left, next on the right). Their meaning therefore never
/// flips merely because the surrounding settings page is RTL.
class PlaylistTransportControls extends StatelessWidget {
  const PlaylistTransportControls({
    super.key,
    required this.previousTooltip,
    required this.nextTooltip,
    required this.onPrevious,
    required this.onNext,
  });

  final String previousTooltip;
  final String nextTooltip;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            key: const ValueKey('playlist-previous-button'),
            tooltip: previousTooltip,
            onPressed: onPrevious,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          const SizedBox(width: 9),
          IconButton.filledTonal(
            key: const ValueKey('playlist-next-button'),
            tooltip: nextTooltip,
            onPressed: onNext,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ],
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final ThemePalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : .48,
      child: _SettingShell(
        palette: palette,
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: enabled ? palette.primary : palette.mutedText,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 9.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(value * 100).round()}%',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: palette.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            Slider(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeColor: palette.primary,
              inactiveColor: palette.primary.withValues(alpha: .13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceSetting extends StatelessWidget {
  const _ChoiceSetting({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });
  final ThemePalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final List<_Option> options;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : .48,
      child: _SettingShell(
        palette: palette,
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: enabled ? palette.primary : palette.mutedText,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 9.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 520) {
                  return Column(
                    children: options
                        .map(
                          (option) => Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: SizedBox(
                              width: double.infinity,
                              child: _ChoiceButton(
                                palette: palette,
                                option: option,
                                selected: value == option.value,
                                enabled: enabled,
                                onTap: () => onChanged(option.value),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                }
                if (options.length > 5) {
                  final columns = constraints.maxWidth >= 900 ? 4 : 3;
                  const spacing = 7.0;
                  final itemWidth =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: options.map((option) {
                      return SizedBox(
                        width: itemWidth,
                        child: _ChoiceButton(
                          palette: palette,
                          option: option,
                          selected: value == option.value,
                          enabled: enabled,
                          onTap: () => onChanged(option.value),
                        ),
                      );
                    }).toList(),
                  );
                }
                return Row(
                  children: List.generate(options.length, (index) {
                    final option = options[index];
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          end: index == options.length - 1 ? 0 : 7,
                        ),
                        child: _ChoiceButton(
                          palette: palette,
                          option: option,
                          selected: value == option.value,
                          enabled: enabled,
                          onTap: () => onChanged(option.value),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingShell extends StatelessWidget {
  const _SettingShell({required this.palette, required this.child});
  final ThemePalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: .018),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: palette.primary.withValues(alpha: .08)),
      ),
      child: child,
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.palette,
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final ThemePalette palette;
  final _Option option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? palette.primary.withValues(alpha: .13)
          : palette.background.withValues(alpha: .36),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? palette.primary.withValues(alpha: .58)
                  : palette.text.withValues(alpha: .045),
            ),
          ),
          child: Text(
            option.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? palette.primary : palette.mutedText,
              fontSize: 10,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _Option {
  const _Option(this.value, this.label);
  final String value;
  final String label;
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.palette,
    required this.icon,
    required this.title,
    required this.value,
  });
  final ThemePalette palette;
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.primary.withValues(alpha: .08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.primary, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: palette.mutedText, fontSize: 8.5),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailButton extends StatelessWidget {
  const _EmailButton({
    required this.palette,
    required this.label,
    required this.email,
    required this.onTap,
  });
  final ThemePalette palette;
  final String label;
  final String email;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.background.withValues(alpha: .42),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: palette.primary.withValues(alpha: .10)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.alternate_email_rounded,
                color: palette.primary,
                size: 18,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(color: palette.mutedText, fontSize: 8.5),
                    ),
                    Text(
                      email,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.copy_rounded, color: palette.mutedText, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportTile extends StatelessWidget {
  const _SupportTile({
    required this.palette,
    required this.icon,
    required this.title,
    required this.email,
    required this.description,
    required this.onCopy,
  });
  final ThemePalette palette;
  final IconData icon;
  final String title;
  final String email;
  final String description;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return _SettingShell(
      palette: palette,
      child: Row(
        children: [
          _IconBox(palette: palette, icon: icon),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: palette.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: palette.mutedText,
                    fontSize: 9,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCopy,
            icon: Icon(Icons.copy_rounded, color: palette.primary, size: 19),
          ),
        ],
      ),
    );
  }
}
