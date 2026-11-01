import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/child_process_environment.dart';
import 'package:goldbrain/core/windows_media_process_backend.dart';
import 'package:path/path.dart' as path;

void main() {
  const runNativeSmoke = bool.fromEnvironment('GOLDBRAIN_MEDIA_PROCESS_SMOKE');

  test('child environment keeps Windows runtime values but strips secrets', () {
    final environment = sanitizedWindowsChildEnvironment(
      parent: const <String, String>{
        'SystemRoot': r'C:\Windows',
        'PATH': r'C:\Windows\System32',
        'TEMP': r'C:\Temp',
        'GAPGPT_API_KEY': 'top-secret-ai-key',
        'NAVASAN_API_KEY': 'top-secret-market-key',
        'HTTPS_PROXY': 'http://user:password@proxy.invalid',
      },
      additions: const <String, String>{
        'GOLDBRAIN_WINDOWS_MEDIA_CONFIG_B64': 'safe-config',
      },
    );

    expect(environment['SystemRoot'], r'C:\Windows');
    expect(environment['PATH'], r'C:\Windows\System32');
    expect(environment['TEMP'], r'C:\Temp');
    expect(environment['GOLDBRAIN_WINDOWS_MEDIA_CONFIG_B64'], 'safe-config');
    expect(environment, isNot(contains('GAPGPT_API_KEY')));
    expect(environment, isNot(contains('NAVASAN_API_KEY')));
    expect(environment, isNot(contains('HTTPS_PROXY')));
    expect(environment.values.join(' '), isNot(contains('top-secret')));
    expect(environment.values.join(' '), isNot(contains('password')));
  });

  test(
    'launch keeps an adversarial Unicode path out of script and arguments',
    () {
      const mediaPath =
          r"C:\موسیقی من\track'; Write-Output PWNED; $(Get-ChildItem).mp3";
      final launch = WindowsMediaProcessBackend.buildLaunch(
        filePath: mediaPath,
        loop: true,
        volume: 2.5,
      );

      expect(launch.executable, 'powershell.exe');
      expect(
        launch.arguments,
        containsAllInOrder(<String>[
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-STA',
          '-WindowStyle',
          'Hidden',
          '-EncodedCommand',
        ]),
      );
      expect(launch.arguments.join(' '), isNot(contains(mediaPath)));
      expect(launch.environment.values.join(' '), isNot(contains(mediaPath)));

      final encodedScript = launch.arguments.last;
      final scriptBytes = base64Decode(encodedScript);
      final codeUnits = <int>[
        for (var index = 0; index < scriptBytes.length; index += 2)
          scriptBytes[index] | (scriptBytes[index + 1] << 8),
      ];
      final script = String.fromCharCodes(codeUnits);
      expect(script, isNot(contains(mediaPath)));
      expect(script, contains(r'$env:GOLDBRAIN_WINDOWS_MEDIA_CONFIG_B64'));
      expect(script, contains('MediaOpened'));
      expect(script, contains("Send-ProtocolLine 'READY'"));

      final config = WindowsMediaProcessBackend.decodeLaunchConfig(launch);
      expect(config['path'], mediaPath);
      expect(config['loop'], isTrue);
      expect(config['volume'], 1.0);
    },
  );

  test('compressed fallback accepts only its documented formats', () {
    expect(
      WindowsMediaProcessBackend.supportsPath(r'C:\music\track.MP3'),
      isTrue,
    );
    expect(
      WindowsMediaProcessBackend.supportsPath(r'C:\music\track.m4a'),
      isTrue,
    );
    expect(
      WindowsMediaProcessBackend.supportsPath(r'C:\music\track.aac'),
      isTrue,
    );
    expect(
      WindowsMediaProcessBackend.supportsPath(r'C:\music\track.wav'),
      isFalse,
    );
    expect(
      WindowsMediaProcessBackend.supportsPath(r'C:\music\track.exe'),
      isFalse,
    );
  });

  test('PowerShell command encoding is UTF-16LE and round-trips', () {
    const source = r"Write-Output 'GoldBrain فارسی'";
    final bytes = base64Decode(
      WindowsMediaProcessBackend.encodePowerShellCommand(source),
    );
    expect(bytes.length, source.codeUnits.length * 2);
    final decoded = String.fromCharCodes(<int>[
      for (var index = 0; index < bytes.length; index += 2)
        bytes[index] | (bytes[index + 1] << 8),
    ]);
    expect(decoded, source);
  });

  test(
    'WPF process opens a real Release MP3, reports status, and exits on stop',
    () async {
      expect(Platform.isWindows, isTrue);
      final mp3 = File(
        path.join(
          Directory.current.path,
          'build',
          'windows',
          'x64',
          'runner',
          'Release',
          'data',
          'flutter_assets',
          'assets',
          'sounds',
          'alexis_gaming_cam-ks-motion-metal-hit-351564.mp3',
        ),
      );
      expect(
        mp3.existsSync(),
        isTrue,
        reason: 'Run `flutter build windows --release` before the smoke test.',
      );

      final backend = WindowsMediaProcessBackend(
        startupTimeout: const Duration(seconds: 12),
      );
      try {
        await backend.playMusic(mp3.path, loop: true, volume: 0.01);
        expect(backend.currentStatus, WindowsMediaProcessStatus.playing);
        expect(await backend.queryStatus(), WindowsMediaProcessStatus.playing);
        await backend.setMusicVolume(0.02);
        await backend.stopMusic();
        expect(backend.currentStatus, WindowsMediaProcessStatus.stopped);
      } finally {
        await backend.dispose();
      }
      expect(backend.currentStatus, WindowsMediaProcessStatus.disposed);
    },
    skip: runNativeSmoke
        ? false
        : 'Enable with GOLDBRAIN_MEDIA_PROCESS_SMOKE=true.',
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
