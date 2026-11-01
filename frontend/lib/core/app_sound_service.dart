import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'settings_store.dart';
import 'windows_audio_backend.dart';

enum AppMusicTrack { selection, auth, dashboard }

class AppSoundException implements Exception {
  const AppSoundException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppSoundService {
  AppSoundService._() {
    _windowsBackend = Platform.isWindows
        ? WindowsAudioBackend.tryCreate()
        : null;
    _audioAvailable = !Platform.isWindows || _windowsBackend != null;

    if (_windowsBackend == null && _audioAvailable) {
      _effectsPlayer = AudioPlayer();
      _musicPlayer = AudioPlayer();
      _typingPlayer = AudioPlayer();
      _musicStateSubscription = _musicPlayer.processingStateStream.listen(
        _handleMusicProcessingState,
      );
    }
  }

  @visibleForTesting
  AppSoundService.testing({
    Future<void> Function()? stopMusicPlayback,
    Future<void> Function(bool forceReload)? playCurrentBackground,
  }) : _testStopMusicPlayback = stopMusicPlayback,
       _testPlayCurrentBackground = playCurrentBackground {
    _windowsBackend = null;
    _audioAvailable = true;
    _effectsPlayer = AudioPlayer();
    _musicPlayer = AudioPlayer();
    _typingPlayer = AudioPlayer();
    _musicStateSubscription = _musicPlayer.processingStateStream.listen(
      _handleMusicProcessingState,
    );
  }

  static final AppSoundService instance = AppSoundService._();

  late final AudioPlayer _effectsPlayer;
  late final AudioPlayer _musicPlayer;
  late final AudioPlayer _typingPlayer;
  final ValueNotifier<bool> previewing = ValueNotifier<bool>(false);
  final ValueNotifier<String?> activeCustomTrackPath = ValueNotifier<String?>(
    null,
  );

  late final StreamSubscription<ProcessingState> _musicStateSubscription;
  late final bool _audioAvailable;
  late final WindowsAudioBackend? _windowsBackend;
  Timer? _windowsPollTimer;

  Future<void> _musicQueue = Future<void>.value();
  AppMusicTrack? _currentMusicTrack;
  String? _loadedMusicSourceId;
  double _currentMusicVolume = 0.8;
  bool _backgroundMusicAllowed = false;
  bool _isPreviewing = false;
  bool _windowsResumeScheduled = false;
  bool _lifecycleSuspended = false;
  bool _disposed = false;
  Future<void> Function()? _testStopMusicPlayback;
  Future<void> Function(bool forceReload)? _testPlayCurrentBackground;
  final math.Random _random = math.Random();

  bool get isPreviewing => _isPreviewing;
  bool get isAudioAvailable => _audioAvailable;

  static List<String> supportedCustomMusicExtensions({bool? isWindows}) {
    final windows = isWindows ?? Platform.isWindows;
    return windows
        ? const ['mp3', 'wav', 'm4a', 'aac']
        : const ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'];
  }

  @visibleForTesting
  static String? resolveAdjacentCustomTrack({
    required List<String> playlist,
    required String? currentPath,
    required MusicPlaybackMode mode,
    required int direction,
    required bool automatic,
    int? shuffleIndex,
  }) {
    if (playlist.isEmpty) return null;
    final currentIndex = currentPath == null
        ? -1
        : playlist.indexOf(currentPath);
    if (automatic && mode == MusicPlaybackMode.repeatOne && currentIndex >= 0) {
      return playlist[currentIndex];
    }
    if (mode == MusicPlaybackMode.shuffle && playlist.length > 1) {
      final excludedIndex = currentIndex >= 0 ? currentIndex : 0;
      final rawChoice = (shuffleIndex ?? 0) % (playlist.length - 1);
      final selectedIndex = rawChoice >= excludedIndex
          ? rawChoice + 1
          : rawChoice;
      return playlist[selectedIndex];
    }

    if (currentIndex < 0) {
      return direction < 0 ? playlist.last : playlist.first;
    }
    final offset = direction < 0 ? -1 : 1;
    final nextIndex = (currentIndex + offset) % playlist.length;
    return playlist[nextIndex];
  }

  Future<void> playClick({required bool enabled, required double volume}) {
    return _playEffect(
      asset: 'sounds/interface_click.wav',
      enabled: enabled,
      volume: volume,
    );
  }

  Future<void> playTab({required bool enabled, required double volume}) {
    return _playEffect(
      asset: 'sounds/tab_shift.wav',
      enabled: enabled,
      volume: volume,
    );
  }

  Future<void> playNotification({
    required bool enabled,
    required double volume,
  }) {
    return _playEffect(
      asset: 'sounds/notification_open.wav',
      enabled: enabled,
      volume: volume,
    );
  }

  Future<void> playSuccess({required bool enabled, required double volume}) {
    return _playEffect(
      asset: 'sounds/settings_saved.wav',
      enabled: enabled,
      volume: volume,
    );
  }

  Future<void> playStartup({required bool enabled, required double volume}) {
    return _playEffect(
      asset: 'sounds/startup_sequence.wav',
      enabled: enabled,
      volume: volume,
    );
  }

  Future<void> playHover({required bool enabled, required double volume}) {
    return _playEffect(
      asset: 'sounds/theme_hover.wav',
      enabled: enabled,
      volume: volume,
    );
  }

  Future<void> playThemeSelected({
    required bool enabled,
    required double volume,
  }) {
    return _playEffect(
      asset: 'sounds/theme_selected.wav',
      enabled: enabled,
      volume: volume,
    );
  }

  Future<void> playMetalImpact({
    required bool enabled,
    required double volume,
  }) {
    return _playEffect(
      asset: 'sounds/alexis_gaming_cam-ks-motion-metal-hit-351564.mp3',
      enabled: enabled,
      volume: volume,
    );
  }

  Future<void> playTyping({
    required bool enabled,
    required double volume,
  }) async {
    if (!enabled || _disposed || !_audioAvailable) return;

    final windowsBackend = _windowsBackend;
    if (windowsBackend != null) {
      try {
        windowsBackend.playTyping(
          windowsBackend.resolveAssetPath('assets/sounds/typing_key.wav'),
          volume: _effectVolume(volume),
        );
      } on WindowsAudioException {
        // Typing feedback is optional and must never block user input.
      }
      return;
    }

    try {
      await _typingPlayer.stop();
      await _typingPlayer.setAsset('assets/sounds/typing_key.wav');
      await _typingPlayer.setVolume(_effectVolume(volume));
      unawaited(_ignorePlaybackCompletion(_typingPlayer.play()));
    } on PlayerInterruptedException {
      // A newer keystroke superseded this sound.
    } on PlayerException {
      // Interface audio must never block typing.
    }
  }

  Future<void> playLogin({required bool enabled, required double volume}) {
    return _playEffect(
      asset: 'sounds/login_confirm.wav',
      enabled: enabled,
      volume: volume,
    );
  }

  Future<void> playDashboardReady({
    required bool enabled,
    required double volume,
  }) {
    return _playEffect(
      asset: 'sounds/dashboard_ready.wav',
      enabled: enabled,
      volume: volume,
    );
  }

  Future<void> playSignupTransition({
    required bool enabled,
    required double volume,
  }) async {
    if (!enabled) return;

    await _playEffect(
      asset: 'sounds/glass-breaking-93803.mp3',
      enabled: true,
      volume: volume,
    );
    await Future<void>.delayed(const Duration(milliseconds: 650));
    await _playEffect(
      asset: 'sounds/gun-cocking-01.mp3',
      enabled: true,
      volume: volume,
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _playEffect(
      asset: 'sounds/gun-gunshot-01.mp3',
      enabled: true,
      volume: volume,
    );
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _playEffect(
      asset: 'sounds/empty-bullet-shell-fall-01.mp3',
      enabled: true,
      volume: volume,
    );
  }

  Future<void> playLoginTransition({
    required bool enabled,
    required double volume,
  }) async {
    if (!enabled) return;

    await _playEffect(
      asset: 'sounds/glass-breaking-93803.mp3',
      enabled: true,
      volume: volume,
    );
    await Future<void>.delayed(const Duration(milliseconds: 850));
    await _playEffect(
      asset: 'sounds/writing-signature-3.mp3',
      enabled: true,
      volume: volume,
    );
  }

  Future<void> startMusic({
    required AppMusicTrack track,
    required bool enabled,
    required bool musicEnabled,
    required double volume,
  }) {
    if (!_audioAvailable) return Future<void>.value();
    return _enqueueMusicOperation(() async {
      _currentMusicTrack = track;
      _currentMusicVolume = _musicVolume(volume);
      _backgroundMusicAllowed = enabled && musicEnabled;
      _setPreviewing(false);

      if (!_backgroundMusicAllowed) {
        _cancelWindowsPollTimer();
        _loadedMusicSourceId = null;
        _setActiveCustomTrack(null);
        await _stopMusicPlayback();
        return;
      }

      if (_lifecycleSuspended) return;
      await _playCurrentBackground();
    });
  }

  Future<void> nextCustomTrack() => _changeCustomTrack(direction: 1);

  Future<void> previousCustomTrack() => _changeCustomTrack(direction: -1);

  Future<void> _changeCustomTrack({required int direction}) {
    if (!_audioAvailable) {
      final selectedPath = _adjacentCustomTrackPath(
        direction: direction,
        automatic: false,
      );
      return selectedPath == null
          ? Future<void>.value()
          : SettingsStore.instance.selectCustomMusic(selectedPath);
    }
    return _enqueueMusicOperation(() async {
      final selectedPath = _adjacentCustomTrackPath(
        direction: direction,
        automatic: false,
      );
      if (selectedPath == null) return;
      await SettingsStore.instance.selectCustomMusic(selectedPath);
      _setPreviewing(false);
      _loadedMusicSourceId = null;
      if (_backgroundMusicAllowed && !_lifecycleSuspended) {
        await _playCurrentBackground(forceReload: true);
      }
    });
  }

  String? _adjacentCustomTrackPath({
    required int direction,
    required bool automatic,
  }) {
    final settings = SettingsStore.instance;
    final availablePaths = settings.customMusicPlaylist
        .where((track) => File(track.path).existsSync())
        .map((track) => track.path)
        .toList(growable: false);
    final shuffleIndex =
        settings.musicPlaybackMode == MusicPlaybackMode.shuffle &&
            availablePaths.length > 1
        ? _random.nextInt(availablePaths.length - 1)
        : null;
    return resolveAdjacentCustomTrack(
      playlist: availablePaths,
      currentPath: settings.currentCustomMusicPath,
      mode: settings.musicPlaybackMode,
      direction: direction,
      automatic: automatic,
      shuffleIndex: shuffleIndex,
    );
  }

  Future<void> suspendForLifecycle() {
    _cancelWindowsPollTimer();
    if (!_audioAvailable || _disposed) return Future<void>.value();
    return _enqueueMusicOperation(() async {
      _lifecycleSuspended = true;
      _setPreviewing(false);
      _loadedMusicSourceId = null;
      _setActiveCustomTrack(null);
      await _stopMusicPlayback();
    });
  }

  Future<void> resumeFromLifecycle() {
    if (!_audioAvailable || _disposed) return Future<void>.value();
    return _enqueueMusicOperation(() async {
      _lifecycleSuspended = false;
      if (_backgroundMusicAllowed && _currentMusicTrack != null) {
        await _playCurrentBackground(forceReload: true);
      }
    });
  }

  Future<void> previewCustomMusic({
    required String path,
    required double volume,
  }) {
    if (!_audioAvailable) {
      return Future<void>.error(
        const AppSoundException(
          'Audio playback is temporarily unavailable on Windows.',
        ),
      );
    }
    return _enqueueMusicOperation(() async {
      final normalizedPath = path.trim();
      if (normalizedPath.isEmpty || !File(normalizedPath).existsSync()) {
        throw const AppSoundException(
          'The selected audio file is unavailable.',
        );
      }
      final supported = supportedCustomMusicExtensions().any(
        (extension) => normalizedPath.toLowerCase().endsWith('.$extension'),
      );
      if (!supported) {
        throw const AppSoundException(
          'This audio format is not supported on the current platform.',
        );
      }

      final windowsBackend = _windowsBackend;
      if (windowsBackend != null) {
        try {
          _setPreviewing(false);
          await windowsBackend.playMusic(
            normalizedPath,
            loop: false,
            volume: _musicVolume(volume),
          );
          _loadedMusicSourceId = 'preview:$normalizedPath';
          _setPreviewing(true);
          _ensureWindowsPollTimer();
        } on WindowsAudioException catch (error) {
          _setPreviewing(false);
          _loadedMusicSourceId = null;
          if (_backgroundMusicAllowed && _currentMusicTrack != null) {
            await _playCurrentBackground(forceReload: true);
          } else {
            _cancelWindowsPollTimer();
          }
          throw AppSoundException(error.message);
        }
        return;
      }

      try {
        _setPreviewing(false);
        await _musicPlayer.stop();
        await _musicPlayer.setLoopMode(LoopMode.off);
        await _musicPlayer.setFilePath(normalizedPath);
        await _musicPlayer.setVolume(_musicVolume(volume));
        _loadedMusicSourceId = 'preview:$normalizedPath';
        _setPreviewing(true);
        unawaited(_ignorePlaybackCompletion(_musicPlayer.play()));
      } on PlayerException catch (error) {
        _setPreviewing(false);
        throw AppSoundException(
          error.message ?? 'The audio file cannot be played.',
        );
      } on PlayerInterruptedException {
        _setPreviewing(false);
        throw const AppSoundException('Audio preview was interrupted.');
      }
    });
  }

  Future<void> stopPreviewAndResume() {
    if (!_audioAvailable || _disposed) return Future<void>.value();
    return _enqueueMusicOperation(() async {
      // This check must happen inside the serialized music queue. A preview
      // completion or another navigation request may have run while this
      // operation was waiting. Most importantly, leaving Settings without an
      // active preview must not cancel the Windows completion poller that
      // advances a custom playlist.
      if (!_isPreviewing) return;

      _cancelWindowsPollTimer();
      _setPreviewing(false);
      await _stopMusicPlayback();
      _loadedMusicSourceId = null;

      if (_backgroundMusicAllowed && _currentMusicTrack != null) {
        await _playCurrentBackground(forceReload: true);
      }
    });
  }

  Future<void> refreshMusicSource() {
    if (!_audioAvailable) return Future<void>.value();
    return _enqueueMusicOperation(() async {
      _setPreviewing(false);
      if (!_backgroundMusicAllowed || _currentMusicTrack == null) {
        _cancelWindowsPollTimer();
        return;
      }

      await _playCurrentBackground(forceReload: true);
    });
  }

  Future<void> stopMusic() {
    _cancelWindowsPollTimer();
    if (!_audioAvailable) return Future<void>.value();
    return _enqueueMusicOperation(() async {
      _cancelWindowsPollTimer();
      _currentMusicTrack = null;
      _backgroundMusicAllowed = false;
      _loadedMusicSourceId = null;
      _setActiveCustomTrack(null);
      _setPreviewing(false);
      await _stopMusicPlayback();
    });
  }

  Future<void> _playEffect({
    required String asset,
    required bool enabled,
    required double volume,
  }) async {
    if (!enabled || _disposed || !_audioAvailable) return;

    final windowsBackend = _windowsBackend;
    if (windowsBackend != null) {
      try {
        windowsBackend.playEffect(
          windowsBackend.resolveAssetPath('assets/$asset'),
          volume: _effectVolume(volume),
        );
      } on WindowsAudioException {
        // Optional interface feedback must never break navigation.
      }
      return;
    }

    try {
      await _effectsPlayer.stop();
      await _effectsPlayer.setAsset('assets/$asset');
      await _effectsPlayer.setVolume(_effectVolume(volume));
      unawaited(_ignorePlaybackCompletion(_effectsPlayer.play()));
    } on PlayerInterruptedException {
      // Rapid UI feedback intentionally replaces the previous effect.
    } on PlayerException {
      // A missing optional effect must never make the interface unresponsive.
    }
  }

  Future<void> _playCurrentBackground({bool forceReload = false}) async {
    final testPlayer = _testPlayCurrentBackground;
    if (testPlayer != null) {
      await testPlayer(forceReload);
      return;
    }

    final track = _currentMusicTrack;
    if (track == null ||
        !_backgroundMusicAllowed ||
        _lifecycleSuspended ||
        _disposed) {
      return;
    }

    final source = _preferredMusicSource(track);
    if (source.filePath != null &&
        SettingsStore.instance.currentCustomMusicPath != source.filePath) {
      await SettingsStore.instance.selectCustomMusic(source.filePath!);
    }
    final shouldLoop =
        source.filePath == null ||
        SettingsStore.instance.musicPlaybackMode == MusicPlaybackMode.repeatOne;
    final windowsBackend = _windowsBackend;
    if (windowsBackend != null) {
      if (!forceReload && _loadedMusicSourceId == source.id) {
        await windowsBackend.setMusicVolume(_currentMusicVolume);
        _ensureWindowsPollTimer();
        return;
      }

      try {
        await windowsBackend.playMusic(
          source.filePath ?? windowsBackend.resolveAssetPath(source.assetPath!),
          loop: shouldLoop,
          volume: _currentMusicVolume,
        );
        _loadedMusicSourceId = source.id;
        _setActiveCustomTrack(source.filePath);
        _ensureWindowsPollTimer();
      } on WindowsAudioException {
        final fallbacks = <_MusicSource>[
          if (source.filePath != null) _bundledMusicSource(track),
          _codecSafeBundledMusicSource(track),
        ];
        for (final fallback in fallbacks) {
          if (fallback.id == source.id) continue;
          try {
            await windowsBackend.playMusic(
              windowsBackend.resolveAssetPath(fallback.assetPath!),
              loop: true,
              volume: _currentMusicVolume,
            );
            _loadedMusicSourceId = fallback.id;
            _setActiveCustomTrack(null);
            _ensureWindowsPollTimer();
            return;
          } on WindowsAudioException {
            // Try the codec-independent PCM fallback next.
          }
        }
        _loadedMusicSourceId = null;
        _setActiveCustomTrack(null);
        _cancelWindowsPollTimer();
      }
      return;
    }

    if (!forceReload && _loadedMusicSourceId == source.id) {
      await _musicPlayer.setVolume(_currentMusicVolume);
      if (!_musicPlayer.playing) {
        unawaited(_ignorePlaybackCompletion(_musicPlayer.play()));
      }
      return;
    }

    try {
      await _musicPlayer.stop();
      await _musicPlayer.setLoopMode(shouldLoop ? LoopMode.one : LoopMode.off);
      if (source.filePath != null) {
        await _musicPlayer.setFilePath(source.filePath!);
      } else {
        await _musicPlayer.setAsset(source.assetPath!);
      }
      await _musicPlayer.setVolume(_currentMusicVolume);
      _loadedMusicSourceId = source.id;
      _setActiveCustomTrack(source.filePath);
      unawaited(_ignorePlaybackCompletion(_musicPlayer.play()));
    } on PlayerInterruptedException {
      // A newer navigation or preview request superseded this load.
    } on PlayerException {
      final fallbacks = <_MusicSource>[
        if (source.filePath != null) _bundledMusicSource(track),
        _codecSafeBundledMusicSource(track),
      ];
      for (final fallback in fallbacks) {
        if (fallback.id == source.id) continue;
        try {
          await _musicPlayer.stop();
          await _musicPlayer.setLoopMode(LoopMode.one);
          await _musicPlayer.setAsset(fallback.assetPath!);
          await _musicPlayer.setVolume(_currentMusicVolume);
          _loadedMusicSourceId = fallback.id;
          _setActiveCustomTrack(null);
          unawaited(_ignorePlaybackCompletion(_musicPlayer.play()));
          return;
        } on PlayerException {
          // Continue to the codec-independent bundled fallback.
        }
      }
      _loadedMusicSourceId = null;
      _setActiveCustomTrack(null);
    }
  }

  _MusicSource _preferredMusicSource(AppMusicTrack track) {
    final settings = SettingsStore.instance;
    if (settings.useCustomMusic) {
      final selected = settings.currentCustomMusicTrack;
      if (selected != null && File(selected.path).existsSync()) {
        return _MusicSource.file(selected.path);
      }
      for (final customTrack in settings.customMusicPlaylist) {
        if (File(customTrack.path).existsSync()) {
          return _MusicSource.file(customTrack.path);
        }
      }
    }

    return _bundledMusicSource(track);
  }

  _MusicSource _bundledMusicSource(AppMusicTrack track) {
    return _MusicSource.asset('assets/${bundledMusicAsset(track)}');
  }

  /// Returns the original full-length music selected for each app section.
  ///
  /// WindowsAudioBackend supports these files through MCI and its WPF media
  /// fallback. The generated PCM tracks are kept only as a last-resort codec
  /// fallback and must not silently replace the user's bundled music.
  static String bundledMusicAsset(AppMusicTrack track) {
    switch (track) {
      case AppMusicTrack.selection:
        return 'sounds/Light Piano x Guitar x Flute x Birds Singing.mp3';
      case AppMusicTrack.auth:
        return 'sounds/Beautiful_Relaxing_Music_1231354354.mp3';
      case AppMusicTrack.dashboard:
        return 'sounds/Relax Music - Nicmusic - 04.mp3';
    }
  }

  _MusicSource _codecSafeBundledMusicSource(AppMusicTrack track) {
    final asset = switch (track) {
      AppMusicTrack.selection => 'sounds/selection_ambient.wav',
      AppMusicTrack.auth => 'sounds/auth_ambient.wav',
      AppMusicTrack.dashboard => 'sounds/dashboard_ambient.wav',
    };
    return _MusicSource.asset('assets/$asset');
  }

  Future<void> _enqueueMusicOperation(Future<void> Function() operation) {
    final result = _musicQueue.then<void>((_) async {
      if (_disposed) return;
      await operation();
    });
    _musicQueue = result.catchError((Object _) {});
    return result;
  }

  Future<void> _stopMusicPlayback() async {
    final testStopper = _testStopMusicPlayback;
    if (testStopper != null) {
      await testStopper();
      return;
    }

    final windowsBackend = _windowsBackend;
    if (windowsBackend != null) {
      await windowsBackend.stopMusic();
      return;
    }
    await _musicPlayer.stop();
  }

  void _pollWindowsMusicState() {
    final windowsBackend = _windowsBackend;
    if (windowsBackend == null || _disposed || _windowsResumeScheduled) return;

    try {
      if (windowsBackend.musicMode() != 'stopped') return;
    } on WindowsAudioException {
      _cancelWindowsPollTimer();
      return;
    }

    if (!_isPreviewing &&
        (!_backgroundMusicAllowed || _currentMusicTrack == null)) {
      _cancelWindowsPollTimer();
      return;
    }

    _windowsResumeScheduled = true;
    unawaited(
      _enqueueMusicOperation(
        _handleMusicCompletion,
      ).whenComplete(() => _windowsResumeScheduled = false),
    );
  }

  void _ensureWindowsPollTimer() {
    if (_windowsBackend == null ||
        _disposed ||
        (_windowsPollTimer?.isActive ?? false)) {
      return;
    }
    _windowsPollTimer = Timer.periodic(
      const Duration(milliseconds: 650),
      (_) => _pollWindowsMusicState(),
    );
  }

  void _cancelWindowsPollTimer() {
    _windowsPollTimer?.cancel();
    _windowsPollTimer = null;
  }

  @visibleForTesting
  bool get hasActiveWindowsPollTimer => _windowsPollTimer?.isActive ?? false;

  @visibleForTesting
  void setPreviewStateForTesting({
    required bool previewActive,
    required bool backgroundMusicAllowed,
    AppMusicTrack? currentTrack,
    bool startWindowsPollTimer = false,
  }) {
    _setPreviewing(previewActive);
    _backgroundMusicAllowed = backgroundMusicAllowed;
    _currentMusicTrack = currentTrack;
    if (startWindowsPollTimer && !hasActiveWindowsPollTimer) {
      _windowsPollTimer = Timer.periodic(const Duration(days: 1), (_) {});
    }
  }

  void _handleMusicProcessingState(ProcessingState state) {
    if (state != ProcessingState.completed || _disposed) return;
    unawaited(_enqueueMusicOperation(_handleMusicCompletion));
  }

  Future<void> _handleMusicCompletion() async {
    final completedPreview = _isPreviewing;
    final completedCustomBackground =
        !completedPreview && activeCustomTrackPath.value != null;
    _setPreviewing(false);
    _loadedMusicSourceId = null;

    if (completedCustomBackground) {
      final nextPath = _adjacentCustomTrackPath(direction: 1, automatic: true);
      if (nextPath != null &&
          nextPath != SettingsStore.instance.currentCustomMusicPath) {
        await SettingsStore.instance.selectCustomMusic(nextPath);
      }
    }

    if (_backgroundMusicAllowed &&
        _currentMusicTrack != null &&
        !_lifecycleSuspended) {
      await _playCurrentBackground(forceReload: true);
    } else {
      _setActiveCustomTrack(null);
      _cancelWindowsPollTimer();
    }
  }

  void _setPreviewing(bool value) {
    _isPreviewing = value;
    if (!_disposed && previewing.value != value) {
      previewing.value = value;
    }
  }

  void _setActiveCustomTrack(String? path) {
    if (!_disposed && activeCustomTrackPath.value != path) {
      activeCustomTrackPath.value = path;
    }
  }

  double _effectVolume(double value) {
    return (value * 1.7).clamp(0.0, 1.0).toDouble();
  }

  double _musicVolume(double value) {
    return value.clamp(0.0, 1.0).toDouble();
  }

  Future<void> _ignorePlaybackCompletion(Future<void> playback) async {
    try {
      await playback;
    } on PlayerInterruptedException {
      // Expected whenever another sound replaces the current one.
    } on PlayerException {
      // Playback errors are surfaced while loading or ignored for optional SFX.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;
    _isPreviewing = false;
    if (previewing.value) previewing.value = false;
    if (activeCustomTrackPath.value != null) {
      activeCustomTrackPath.value = null;
    }
    _cancelWindowsPollTimer();
    await _musicQueue.catchError((Object _) {});
    final windowsBackend = _windowsBackend;
    if (windowsBackend != null) {
      await windowsBackend.dispose();
      previewing.dispose();
      activeCustomTrackPath.dispose();
      return;
    }
    if (!_audioAvailable) {
      previewing.dispose();
      activeCustomTrackPath.dispose();
      return;
    }
    await _musicStateSubscription.cancel();
    await Future.wait([
      _effectsPlayer.dispose(),
      _musicPlayer.dispose(),
      _typingPlayer.dispose(),
    ]);
    previewing.dispose();
    activeCustomTrackPath.dispose();
  }
}

class _MusicSource {
  const _MusicSource._({required this.id, this.assetPath, this.filePath});

  factory _MusicSource.asset(String assetPath) {
    return _MusicSource._(id: 'asset:$assetPath', assetPath: assetPath);
  }

  factory _MusicSource.file(String filePath) {
    return _MusicSource._(id: 'file:$filePath', filePath: filePath);
  }

  final String id;
  final String? assetPath;
  final String? filePath;
}
