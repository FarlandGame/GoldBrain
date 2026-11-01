import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import 'windows_media_process_backend.dart';

typedef _MciSendStringNative =
    Uint32 Function(
      Pointer<Utf16> command,
      Pointer<Utf16> returnValue,
      Uint32 returnLength,
      IntPtr callbackWindow,
    );
typedef _MciSendStringDart =
    int Function(
      Pointer<Utf16> command,
      Pointer<Utf16> returnValue,
      int returnLength,
      int callbackWindow,
    );
typedef _MciGetErrorStringNative =
    Int32 Function(
      Uint32 errorCode,
      Pointer<Utf16> errorText,
      Uint32 errorTextLength,
    );
typedef _MciGetErrorStringDart =
    int Function(int errorCode, Pointer<Utf16> errorText, int errorTextLength);

class WindowsAudioException implements Exception {
  const WindowsAudioException({
    required this.command,
    required this.code,
    required this.message,
  });

  final String command;
  final int code;
  final String message;

  @override
  String toString() => 'Windows audio error $code: $message';
}

/// Windows audio without Flutter platform channels.
///
/// WinMM/MCI handles bundled PCM audio and short effects. Some Windows
/// editions do not install an MCI driver for compressed formats, so music in
/// MP3/M4A/AAC falls back to an isolated WPF MediaPlayer process.
class WindowsAudioBackend {
  WindowsAudioBackend._(DynamicLibrary library)
    : _sendString = library
          .lookupFunction<_MciSendStringNative, _MciSendStringDart>(
            'mciSendStringW',
          ),
      _getErrorString = library
          .lookupFunction<_MciGetErrorStringNative, _MciGetErrorStringDart>(
            'mciGetErrorStringW',
          ),
      _compressedMusicBackend = WindowsMediaProcessBackend.tryCreate();

  static const _musicAlias = 'goldbrain_music';
  static const _effectAlias = 'goldbrain_effect';
  static const _typingAlias = 'goldbrain_typing';

  final _MciSendStringDart _sendString;
  final _MciGetErrorStringDart _getErrorString;
  final WindowsMediaProcessBackend? _compressedMusicBackend;
  bool _usingCompressedMusicBackend = false;
  bool _disposed = false;

  static WindowsAudioBackend? tryCreate() {
    if (!Platform.isWindows) return null;

    try {
      return WindowsAudioBackend._(DynamicLibrary.open('winmm.dll'));
    } catch (_) {
      return null;
    }
  }

  static String assetPathForExecutable(
    String executablePath,
    String flutterAssetPath,
  ) {
    final normalizedAsset = flutterAssetPath
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    final assetSegments = normalizedAsset
        .split('/')
        .where((segment) => segment.isNotEmpty)
        // Flutter stores Windows asset filenames using URI-encoded segments.
        .map(Uri.encodeComponent)
        .toList(growable: false);

    return path.normalize(
      path.joinAll([
        path.dirname(executablePath),
        'data',
        'flutter_assets',
        ...assetSegments,
      ]),
    );
  }

  String resolveAssetPath(String flutterAssetPath) {
    return assetPathForExecutable(
      Platform.resolvedExecutable,
      flutterAssetPath,
    );
  }

  Future<void> playMusic(
    String filePath, {
    required bool loop,
    required double volume,
  }) async {
    _ensureActive();
    await _stopCompressedMusic();
    _usingCompressedMusicBackend = false;

    try {
      _openAndPlay(
        alias: _musicAlias,
        filePath: filePath,
        loop: loop,
        volume: volume,
      );
      return;
    } on WindowsAudioException catch (mciError) {
      final fallback = _compressedMusicBackend;
      if (fallback == null ||
          !WindowsMediaProcessBackend.supportsPath(filePath)) {
        rethrow;
      }

      _stopAndClose(_musicAlias);
      try {
        await fallback.playMusic(filePath, loop: loop, volume: volume);
        _usingCompressedMusicBackend = true;
      } on WindowsMediaProcessException catch (fallbackError) {
        throw WindowsAudioException(
          command: 'WPF MediaPlayer open',
          code: mciError.code,
          message:
              '${fallbackError.message} '
              '(WinMM fallback error: ${mciError.message})',
        );
      }
    }
  }

  void playEffect(String filePath, {required double volume}) {
    _openAndPlay(
      alias: _effectAlias,
      filePath: filePath,
      loop: false,
      volume: volume,
    );
  }

  void playTyping(String filePath, {required double volume}) {
    _openAndPlay(
      alias: _typingAlias,
      filePath: filePath,
      loop: false,
      volume: volume,
    );
  }

  Future<void> stopMusic() async {
    if (_disposed) return;
    await _stopCompressedMusic();
    _usingCompressedMusicBackend = false;
    _stopAndClose(_musicAlias);
  }

  Future<void> setMusicVolume(double volume) async {
    _ensureActive();
    if (_usingCompressedMusicBackend) {
      final fallback = _compressedMusicBackend;
      if (fallback == null) return;
      try {
        await fallback.setMusicVolume(volume);
      } on WindowsMediaProcessException catch (error) {
        throw WindowsAudioException(
          command: 'WPF MediaPlayer volume',
          code: -3,
          message: error.message,
        );
      }
      return;
    }

    final normalizedVolume = _normalizedVolume(volume);
    _sendSilently('setaudio $_musicAlias volume to $normalizedVolume');
  }

  String musicMode() {
    _ensureActive();
    if (_usingCompressedMusicBackend) {
      switch (_compressedMusicBackend?.currentStatus) {
        case WindowsMediaProcessStatus.starting:
        case WindowsMediaProcessStatus.playing:
          return 'playing';
        case WindowsMediaProcessStatus.idle:
        case WindowsMediaProcessStatus.completed:
        case WindowsMediaProcessStatus.stopped:
        case WindowsMediaProcessStatus.failed:
        case WindowsMediaProcessStatus.disposed:
        case null:
          return 'stopped';
      }
    }
    return _send(
      'status $_musicAlias mode',
      returnLength: 64,
    ).trim().toLowerCase();
  }

  Future<void> _stopCompressedMusic() async {
    final fallback = _compressedMusicBackend;
    if (fallback == null) return;
    try {
      await fallback.stopMusic();
    } on WindowsMediaProcessException catch (error) {
      throw WindowsAudioException(
        command: 'WPF MediaPlayer stop',
        code: -4,
        message: error.message,
      );
    }
  }

  void _openAndPlay({
    required String alias,
    required String filePath,
    required bool loop,
    required double volume,
  }) {
    _ensureActive();
    final file = File(filePath);
    if (!file.existsSync()) {
      throw WindowsAudioException(
        command: 'open',
        code: -1,
        message: 'Audio file not found: $filePath',
      );
    }

    _closeSilently(alias);
    final quotedPath = file.absolute.path.replaceAll('"', '');
    try {
      _send('open "$quotedPath" alias $alias');
    } on WindowsAudioException {
      final deviceType = _deviceTypeFor(quotedPath);
      if (deviceType == null) rethrow;
      _closeSilently(alias);
      _send('open "$quotedPath" type $deviceType alias $alias');
    }

    final normalizedVolume = _normalizedVolume(volume);
    _sendSilently('setaudio $alias volume to $normalizedVolume');

    try {
      if (loop) {
        try {
          _send('play $alias repeat');
        } on WindowsAudioException {
          // waveaudio does not accept `repeat` everywhere. AppSoundService
          // polls completion and restarts the bundled WAV in this case.
          _send('play $alias');
        }
      } else {
        _send('play $alias');
      }
    } catch (_) {
      _closeSilently(alias);
      rethrow;
    }
  }

  String? _deviceTypeFor(String filePath) {
    switch (path.extension(filePath).toLowerCase()) {
      case '.wav':
        return 'waveaudio';
      case '.mp3':
      case '.m4a':
      case '.aac':
      case '.flac':
      case '.ogg':
        return 'mpegvideo';
      default:
        return null;
    }
  }

  int _normalizedVolume(double volume) {
    return (volume.clamp(0.0, 1.0) * 1000).round().clamp(0, 1000);
  }

  void _stopAndClose(String alias) {
    if (_disposed) return;
    _sendSilently('stop $alias');
    _closeSilently(alias);
  }

  void _closeSilently(String alias) {
    _sendSilently('close $alias');
  }

  void _sendSilently(String command) {
    try {
      _send(command);
    } catch (_) {
      // Closing an alias that is not open is expected during source changes.
    }
  }

  String _send(String command, {int returnLength = 0}) {
    _ensureActive();
    final nativeCommand = command.toNativeUtf16();
    final output = returnLength > 0
        ? calloc<Uint16>(returnLength).cast<Utf16>()
        : nullptr.cast<Utf16>();

    try {
      final result = _sendString(nativeCommand, output, returnLength, 0);
      if (result != 0) {
        throw WindowsAudioException(
          command: command,
          code: result,
          message: _errorMessage(result),
        );
      }
      return returnLength > 0 ? output.toDartString() : '';
    } finally {
      calloc.free(nativeCommand);
      if (returnLength > 0) calloc.free(output);
    }
  }

  String _errorMessage(int code) {
    const capacity = 256;
    final output = calloc<Uint16>(capacity).cast<Utf16>();
    try {
      final found = _getErrorString(code, output, capacity) != 0;
      return found ? output.toDartString() : 'Unknown WinMM/MCI error.';
    } finally {
      calloc.free(output);
    }
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('Windows audio backend has been disposed.');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    final fallback = _compressedMusicBackend;
    if (fallback != null) await fallback.dispose();
    _usingCompressedMusicBackend = false;
    _stopAndClose(_musicAlias);
    _stopAndClose(_effectAlias);
    _stopAndClose(_typingAlias);
    _disposed = true;
  }
}
