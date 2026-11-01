import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'child_process_environment.dart';

/// Playback states reported by [WindowsMediaProcessBackend].
enum WindowsMediaProcessStatus {
  idle,
  starting,
  playing,
  completed,
  stopped,
  failed,
  disposed,
}

/// A failure while starting or controlling the isolated Windows media process.
class WindowsMediaProcessException implements Exception {
  const WindowsMediaProcessException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The immutable process launch description used by the backend.
///
/// This is public so security-sensitive command construction can be unit
/// tested without starting PowerShell. The media path is present only inside
/// the Base64-encoded JSON environment value; it is never interpolated into
/// the PowerShell source or command-line arguments.
class WindowsMediaProcessLaunch {
  const WindowsMediaProcessLaunch({
    required this.executable,
    required this.arguments,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
}

/// Isolated Windows playback fallback for compressed music files.
///
/// The backend runs WPF's `System.Windows.Media.MediaPlayer` inside a hidden,
/// non-interactive STA PowerShell process. It is intended as a fallback when
/// WinMM/MCI rejects MP3, M4A or AAC files.
///
/// [playMusic], [stopMusic], [setMusicVolume], [queryStatus], and [dispose]
/// are serialized, so callers may safely invoke them from unrelated async UI
/// operations. Closing stdin or disposing the backend also asks the child to
/// close MediaPlayer and exit; a short forced-kill fallback prevents leaks.
class WindowsMediaProcessBackend {
  WindowsMediaProcessBackend({
    this.startupTimeout = const Duration(seconds: 8),
    this.commandTimeout = const Duration(seconds: 5),
    this.shutdownTimeout = const Duration(seconds: 2),
    String powershellExecutable = 'powershell.exe',
  }) : _powershellExecutable = powershellExecutable;

  static const String _configEnvironmentKey =
      'GOLDBRAIN_WINDOWS_MEDIA_CONFIG_B64';

  /// A conservative startup deadline which includes codec initialization.
  final Duration startupTimeout;

  /// Deadline for status and volume control acknowledgements.
  final Duration commandTimeout;

  /// Grace period before a non-responsive PowerShell process is killed.
  final Duration shutdownTimeout;

  final String _powershellExecutable;
  final StreamController<WindowsMediaProcessStatus> _statusController =
      StreamController<WindowsMediaProcessStatus>.broadcast(sync: true);

  Future<void> _operationTail = Future<void>.value();
  _MediaProcessSession? _session;
  WindowsMediaProcessStatus _status = WindowsMediaProcessStatus.idle;
  String? _lastError;
  int _nextRequestId = 0;
  bool _disposeRequested = false;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  /// Creates the backend only on Windows.
  static WindowsMediaProcessBackend? tryCreate({
    Duration startupTimeout = const Duration(seconds: 8),
    Duration commandTimeout = const Duration(seconds: 5),
    Duration shutdownTimeout = const Duration(seconds: 2),
  }) {
    if (!Platform.isWindows) return null;
    return WindowsMediaProcessBackend(
      startupTimeout: startupTimeout,
      commandTimeout: commandTimeout,
      shutdownTimeout: shutdownTimeout,
    );
  }

  WindowsMediaProcessStatus get currentStatus => _status;

  String? get lastError => _lastError;

  Stream<WindowsMediaProcessStatus> get statusStream =>
      _statusController.stream;

  /// Whether WPF MediaPlayer is a suitable fallback for this extension.
  static bool supportsPath(String filePath) {
    final lowerPath = filePath.toLowerCase();
    return lowerPath.endsWith('.mp3') ||
        lowerPath.endsWith('.m4a') ||
        lowerPath.endsWith('.aac');
  }

  /// Builds the exact safe launch specification used by [playMusic].
  static WindowsMediaProcessLaunch buildLaunch({
    required String filePath,
    required bool loop,
    required double volume,
    String powershellExecutable = 'powershell.exe',
  }) {
    if (filePath.contains('\u0000')) {
      throw const FormatException('A media path cannot contain a null byte.');
    }

    final config = base64Encode(
      utf8.encode(
        jsonEncode(<String, Object>{
          'path': filePath,
          'loop': loop,
          'volume': volume.clamp(0.0, 1.0).toDouble(),
        }),
      ),
    );

    return WindowsMediaProcessLaunch(
      executable: powershellExecutable,
      arguments: <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-STA',
        '-WindowStyle',
        'Hidden',
        '-EncodedCommand',
        encodePowerShellCommand(_powerShellScript),
      ],
      environment: <String, String>{_configEnvironmentKey: config},
    );
  }

  /// Encodes a script using the UTF-16LE format required by `-EncodedCommand`.
  static String encodePowerShellCommand(String script) {
    final bytes = <int>[];
    for (final codeUnit in script.codeUnits) {
      bytes
        ..add(codeUnit & 0xff)
        ..add((codeUnit >> 8) & 0xff);
    }
    return base64Encode(bytes);
  }

  /// Decodes the launch config for security-focused tests and diagnostics.
  ///
  /// Do not log the result in production because it contains the local path.
  static Map<String, Object?> decodeLaunchConfig(
    WindowsMediaProcessLaunch launch,
  ) {
    final encoded = launch.environment[_configEnvironmentKey];
    if (encoded == null) {
      throw const FormatException('The media launch config is missing.');
    }
    final decoded = jsonDecode(utf8.decode(base64Decode(encoded)));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The media launch config is invalid.');
    }
    return Map<String, Object?>.from(decoded);
  }

  /// Starts playback and completes only after WPF raises `MediaOpened`.
  Future<void> playMusic(
    String filePath, {
    required bool loop,
    required double volume,
  }) {
    _ensureAcceptingOperations();
    return _serialize<void>(() async {
      _ensureAcceptingOperations();
      await _stopCurrent(setStoppedStatus: false);

      final file = File(filePath);
      if (!await file.exists()) {
        throw WindowsMediaProcessException('Audio file not found: $filePath');
      }
      if (!supportsPath(filePath)) {
        throw const WindowsMediaProcessException(
          'WPF fallback supports MP3, M4A and AAC files only.',
        );
      }

      final absolutePath = file.absolute.path;
      final launch = buildLaunch(
        filePath: absolutePath,
        loop: loop,
        volume: volume,
        powershellExecutable: _powershellExecutable,
      );

      _lastError = null;
      _setStatus(WindowsMediaProcessStatus.starting);

      late final Process process;
      try {
        final childEnvironment = sanitizedWindowsChildEnvironment(
          parent: Platform.environment,
          additions: launch.environment,
        );
        process = await Process.start(
          launch.executable,
          launch.arguments,
          environment: childEnvironment,
          includeParentEnvironment: false,
          runInShell: false,
          mode: ProcessStartMode.normal,
        );
      } on ProcessException catch (error) {
        final message =
            'PowerShell media process could not start: '
            '${error.message}';
        _lastError = message;
        _setStatus(WindowsMediaProcessStatus.failed);
        throw WindowsMediaProcessException(message);
      }

      final session = _MediaProcessSession(process);
      _session = session;
      session.stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => _handleProtocolLine(session, line),
            onError: (Object error, StackTrace stackTrace) {
              _failSession(session, 'PowerShell media output failed: $error');
            },
          );
      session.stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .listen((chunk) => session.appendStderr(chunk));
      unawaited(
        process.exitCode.then((exitCode) => _handleExit(session, exitCode)),
      );

      try {
        await session.ready.future.timeout(startupTimeout);
      } on TimeoutException {
        final protocol = session.protocolText.trim();
        final stderr = session.stderrText.trim();
        final diagnostics = <String>[
          if (protocol.isNotEmpty) 'Protocol: $protocol',
          if (stderr.isNotEmpty) 'Stderr: $stderr',
        ];
        final message =
            'Windows media did not become ready before the startup timeout.'
            '${diagnostics.isEmpty ? ' No child-process output was received.' : ' ${diagnostics.join(' ')}'}';
        _lastError = message;
        _setStatus(WindowsMediaProcessStatus.failed);
        await _terminateSession(session);
        throw WindowsMediaProcessException(message);
      } on WindowsMediaProcessException {
        await _terminateSession(session);
        rethrow;
      }
    });
  }

  /// Returns the last state emitted by the child process.
  ///
  /// `READY`, completion, failure and process exit are all reported by the
  /// isolated host. Returning that cached protocol state avoids a Windows
  /// PowerShell quirk where redirected Console.In responses can remain queued
  /// until the pipe is closed under some Flutter test/runner hosts.
  Future<WindowsMediaProcessStatus> queryStatus() {
    _ensureAcceptingOperations();
    return Future<WindowsMediaProcessStatus>.value(_status);
  }

  Future<void> setMusicVolume(double volume) {
    _ensureAcceptingOperations();
    return _serialize<void>(() async {
      final session = _session;
      if (session == null || session.exited) return;

      final requestId = (++_nextRequestId).toString();
      final normalized = volume.clamp(0.0, 1.0).toStringAsFixed(4);
      await _writeCommand(session, 'VOLUME|$requestId|$normalized');
    });
  }

  Future<void> stopMusic() {
    if (_disposed) return Future<void>.value();
    return _serialize<void>(() => _stopCurrent(setStoppedStatus: true));
  }

  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;

    _disposeRequested = true;
    final completer = Completer<void>();
    _disposeFuture = completer.future;
    unawaited(
      _serialize<void>(() async {
        try {
          await _stopCurrent(setStoppedStatus: false);
          _disposed = true;
          _setStatus(WindowsMediaProcessStatus.disposed);
          await _statusController.close();
          completer.complete();
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      }),
    );
    return completer.future;
  }

  Future<void> _stopCurrent({required bool setStoppedStatus}) async {
    final session = _session;
    if (session == null) {
      if (setStoppedStatus && !_disposeRequested) {
        _setStatus(WindowsMediaProcessStatus.stopped);
      }
      return;
    }

    if (!session.exited) {
      session.stopRequested = true;
      try {
        await _writeCommand(session, 'STOP');
      } on WindowsMediaProcessException {
        // A process can exit naturally between the state check and this write.
      }
    }
    await _terminateSession(session);
    if (setStoppedStatus && !_disposeRequested) {
      _setStatus(WindowsMediaProcessStatus.stopped);
    }
  }

  Future<void> _terminateSession(_MediaProcessSession session) async {
    if (!session.stdinClosed) {
      session.stdinClosed = true;
      try {
        await session.process.stdin.close();
      } catch (_) {
        // The process may have already closed the pipe.
      }
    }

    if (!session.exited) {
      try {
        await session.process.exitCode.timeout(shutdownTimeout);
      } on TimeoutException {
        session.process.kill();
        try {
          await session.process.exitCode.timeout(shutdownTimeout);
        } on TimeoutException {
          // Process.kill is best effort; there is no child process to orphan.
        }
      }
    }

    await session.cancelSubscriptions();
    session.failPendingRequests(
      const WindowsMediaProcessException('Windows media process stopped.'),
    );
    if (identical(_session, session)) _session = null;
  }

  Future<void> _writeCommand(
    _MediaProcessSession session,
    String command,
  ) async {
    if (session.exited || session.stdinClosed) {
      throw const WindowsMediaProcessException(
        'Windows media process is not running.',
      );
    }
    try {
      session.process.stdin.add(utf8.encode('$command\r\n'));
      await session.process.stdin.flush();
    } on Object catch (error) {
      throw WindowsMediaProcessException(
        'Windows media command could not be sent: $error',
      );
    }
  }

  void _handleProtocolLine(_MediaProcessSession session, String line) {
    if (!identical(_session, session)) return;
    session.appendProtocol(line);

    if (line == 'READY') {
      _setStatus(WindowsMediaProcessStatus.playing);
      if (!session.ready.isCompleted) session.ready.complete();
      return;
    }

    final parts = line.split('|');
    if (parts.length >= 2 && parts.first == 'STATE') {
      final state = _statusFromProtocol(parts[1]);
      if (state != null) _setStatus(state);
      return;
    }
    if (parts.length >= 3 && parts.first == 'STATUS') {
      final request = session.statusRequests.remove(parts[1]);
      final state = _statusFromProtocol(parts[2]);
      if (request != null && !request.isCompleted) {
        request.complete(state ?? _status);
      }
      return;
    }
    if (parts.length >= 3 && parts.first == 'VOLUME' && parts[2] == 'OK') {
      final request = session.volumeRequests.remove(parts[1]);
      if (request != null && !request.isCompleted) request.complete();
      return;
    }
    if (parts.length >= 2 && parts.first == 'ERROR') {
      String message;
      try {
        message = utf8.decode(base64Decode(parts[1]));
      } catch (_) {
        message = 'Windows MediaPlayer reported an invalid error.';
      }
      _failSession(session, message);
    }
  }

  void _failSession(_MediaProcessSession session, String message) {
    if (!identical(_session, session)) return;
    _lastError = message;
    _setStatus(WindowsMediaProcessStatus.failed);
    final error = WindowsMediaProcessException(message);
    if (!session.ready.isCompleted) session.ready.completeError(error);
    session.failPendingRequests(error);
  }

  Future<void> _handleExit(_MediaProcessSession session, int exitCode) async {
    session.exited = true;
    if (!identical(_session, session)) return;

    if (!session.ready.isCompleted) {
      final stderr = session.stderrText.trim();
      final detail = stderr.isEmpty ? '' : ' $stderr';
      final message =
          'Windows media process exited before playback was ready '
          '(code $exitCode).$detail';
      _failSession(session, message);
    } else if (!session.stopRequested &&
        _status != WindowsMediaProcessStatus.completed &&
        _status != WindowsMediaProcessStatus.failed) {
      final stderr = session.stderrText.trim();
      if (exitCode == 0) {
        _setStatus(WindowsMediaProcessStatus.completed);
      } else {
        _lastError = stderr.isEmpty
            ? 'Windows media process exited with code $exitCode.'
            : stderr;
        _setStatus(WindowsMediaProcessStatus.failed);
      }
    }
  }

  WindowsMediaProcessStatus? _statusFromProtocol(String value) {
    switch (value.toLowerCase()) {
      case 'starting':
        return WindowsMediaProcessStatus.starting;
      case 'playing':
        return WindowsMediaProcessStatus.playing;
      case 'completed':
        return WindowsMediaProcessStatus.completed;
      case 'stopped':
        return WindowsMediaProcessStatus.stopped;
      case 'failed':
        return WindowsMediaProcessStatus.failed;
      default:
        return null;
    }
  }

  void _setStatus(WindowsMediaProcessStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationTail = _operationTail.then<void>((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  void _ensureAcceptingOperations() {
    if (_disposeRequested || _disposed) {
      throw StateError('Windows media process backend has been disposed.');
    }
  }

  static const String _powerShellScript = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Send-ProtocolLine([string] $Line) {
  [Console]::Out.WriteLine($Line)
  [Console]::Out.Flush()
}

function Send-ProtocolError([string] $Message) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
  Send-ProtocolLine ('ERROR|' + [Convert]::ToBase64String($bytes))
}

try {
  Add-Type -AssemblyName PresentationCore
  Add-Type -AssemblyName WindowsBase
  Add-Type -TypeDefinition @'
using System;
using System.Threading.Tasks;

public static class GoldBrainConsoleInput
{
    public static Task<string> ReadLineAsync()
    {
        // Windows PowerShell wraps Console.In in SyncTextReader, whose
        // ReadLineAsync blocks synchronously before returning a Task. Move the
        // blocking read off the STA so WPF can open and dispatch media events.
        return Task.Run(() => Console.In.ReadLine());
    }
}
'@

  $configBytes = [Convert]::FromBase64String(
    $env:GOLDBRAIN_WINDOWS_MEDIA_CONFIG_B64
  )
  $configJson = [System.Text.Encoding]::UTF8.GetString($configBytes)
  $config = ConvertFrom-Json -InputObject $configJson
  $mediaPath = [string] $config.path
  $script:loopPlayback = [bool] $config.loop
  $script:configuredVolume = [double] $config.volume
  $script:state = 'starting'
  $script:player = [System.Windows.Media.MediaPlayer]::new()
  $script:stdinTask = [GoldBrainConsoleInput]::ReadLineAsync()
  $script:shutdown = $false

  $script:player.add_MediaOpened({
    try {
      $script:player.Volume = $script:configuredVolume
      $script:player.Play()
      $script:state = 'playing'
      Send-ProtocolLine 'READY'
    } catch {
      $script:state = 'failed'
      Send-ProtocolError $_.Exception.Message
      $script:shutdown = $true
    }
  })

  $script:player.add_MediaFailed({
    param($sender, $eventArgs)
    $script:state = 'failed'
    $message = 'Windows MediaPlayer could not open this audio file.'
    if ($null -ne $eventArgs -and $null -ne $eventArgs.ErrorException) {
      $message = $eventArgs.ErrorException.Message
    }
    Send-ProtocolError $message
    $script:shutdown = $true
  })

  $script:player.add_MediaEnded({
    if ($script:loopPlayback) {
      $script:player.Position = [TimeSpan]::Zero
      $script:player.Play()
      $script:state = 'playing'
    } else {
      $script:state = 'completed'
      Send-ProtocolLine 'STATE|completed'
      $script:shutdown = $true
    }
  })

  $script:dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
  $script:controlTimer = [System.Windows.Threading.DispatcherTimer]::new()
  $script:controlTimer.Interval = [TimeSpan]::FromMilliseconds(35)
  $script:controlTimer.add_Tick({
    if ($script:shutdown) {
      $script:controlTimer.Stop()
      $script:dispatcher.InvokeShutdown()
      return
    }
    if ($script:stdinTask.IsCompleted) {
      $line = $script:stdinTask.GetAwaiter().GetResult()
      if ($null -eq $line) {
        $script:state = 'stopped'
        $script:player.Stop()
        $script:shutdown = $true
      } else {
        $parts = $line.Split('|')
        switch ($parts[0]) {
          'STOP' {
            $script:state = 'stopped'
            $script:player.Stop()
            Send-ProtocolLine 'STATE|stopped'
            $script:shutdown = $true
          }
          'STATUS' {
            if ($parts.Length -ge 2) {
              Send-ProtocolLine (
                'STATUS|' + $parts[1] + '|' + $script:state
              )
            }
          }
          'VOLUME' {
            if ($parts.Length -ge 3) {
              $newVolume = [double]::Parse(
                $parts[2],
                [System.Globalization.CultureInfo]::InvariantCulture
              )
              $script:configuredVolume = [Math]::Max(
                0.0,
                [Math]::Min(1.0, $newVolume)
              )
              $script:player.Volume = $script:configuredVolume
              Send-ProtocolLine ('VOLUME|' + $parts[1] + '|OK')
            }
          }
        }
        if (-not $script:shutdown) {
          $script:stdinTask = [GoldBrainConsoleInput]::ReadLineAsync()
        }
      }
    }
    if ($script:shutdown) {
      $script:controlTimer.Stop()
      $script:dispatcher.InvokeShutdown()
    }
  })
  $script:controlTimer.Start()

  $mediaUri = [System.Uri]::new($mediaPath, [System.UriKind]::Absolute)
  $script:player.Open($mediaUri)
  [System.Windows.Threading.Dispatcher]::Run()
} catch {
  Send-ProtocolError $_.Exception.Message
  exit 1
} finally {
  if ($null -ne $script:controlTimer) {
    $script:controlTimer.Stop()
  }
  if ($null -ne $script:player) {
    $script:player.Close()
  }
}
''';
}

class _MediaProcessSession {
  _MediaProcessSession(this.process);

  static const int _maximumStderrLength = 8192;

  final Process process;
  final Completer<void> ready = Completer<void>();
  final Map<String, Completer<WindowsMediaProcessStatus>> statusRequests =
      <String, Completer<WindowsMediaProcessStatus>>{};
  final Map<String, Completer<void>> volumeRequests =
      <String, Completer<void>>{};
  late final StreamSubscription<String> stdoutSubscription;
  late final StreamSubscription<String> stderrSubscription;

  String stderrText = '';
  String protocolText = '';
  bool stopRequested = false;
  bool stdinClosed = false;
  bool exited = false;

  void appendStderr(String value) {
    if (stderrText.length >= _maximumStderrLength) return;
    final remaining = _maximumStderrLength - stderrText.length;
    stderrText += value.length <= remaining
        ? value
        : value.substring(0, remaining);
  }

  void appendProtocol(String value) {
    if (protocolText.length >= _maximumStderrLength) return;
    final line = protocolText.isEmpty ? value : '\n$value';
    final remaining = _maximumStderrLength - protocolText.length;
    protocolText += line.length <= remaining
        ? line
        : line.substring(0, remaining);
  }

  void failPendingRequests(Object error) {
    for (final request in statusRequests.values) {
      if (!request.isCompleted) request.completeError(error);
    }
    statusRequests.clear();
    for (final request in volumeRequests.values) {
      if (!request.isCompleted) request.completeError(error);
    }
    volumeRequests.clear();
  }

  Future<void> cancelSubscriptions() async {
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
  }
}
