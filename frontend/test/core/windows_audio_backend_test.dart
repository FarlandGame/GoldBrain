import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/windows_audio_backend.dart';
import 'package:path/path.dart' as path;

void main() {
  const runNativeSmoke = bool.fromEnvironment('GOLDBRAIN_AUDIO_SMOKE');

  test('resolves bundled audio next to the Windows executable', () {
    final resolved = WindowsAudioBackend.assetPathForExecutable(
      r'C:\Program Files\GoldBrain\goldbrain.exe',
      'assets/sounds/custom track.mp3',
    );

    expect(
      resolved,
      path.normalize(
        r'C:\Program Files\GoldBrain\data\flutter_assets\assets\sounds\custom%20track.mp3',
      ),
    );
  });

  test('WinMM backend availability check is fail-safe', () async {
    final backend = WindowsAudioBackend.tryCreate();

    if (Platform.isWindows) {
      expect(backend, isNotNull);
    } else {
      expect(backend, isNull);
    }

    await backend?.dispose();
  });

  test(
    'WinMM opens bundled WAV without a platform channel',
    () async {
      final backend = WindowsAudioBackend.tryCreate();
      expect(backend, isNotNull);
      try {
        for (final fileName in ['dashboard_ambient.wav']) {
          final releaseExecutable = path.join(
            Directory.current.path,
            'build',
            'windows',
            'x64',
            'runner',
            'Release',
            'goldbrain.exe',
          );
          final audioFile = File(
            WindowsAudioBackend.assetPathForExecutable(
              releaseExecutable,
              'assets/sounds/$fileName',
            ),
          );
          expect(audioFile.existsSync(), isTrue, reason: fileName);

          await backend!.playMusic(audioFile.path, loop: true, volume: 0.02);
          await Future<void>.delayed(const Duration(milliseconds: 250));
          expect(backend.musicMode(), 'playing', reason: fileName);
          await backend.stopMusic();
        }
      } finally {
        await backend?.dispose();
      }
    },
    skip: runNativeSmoke ? false : 'Enable with GOLDBRAIN_AUDIO_SMOKE=true.',
  );

  test(
    'Windows backend plays every bundled background music track',
    () async {
      final backend = WindowsAudioBackend.tryCreate();
      expect(backend, isNotNull);
      const bundledTracks = <String>[
        'Light Piano x Guitar x Flute x Birds Singing.mp3',
        'Beautiful_Relaxing_Music_1231354354.mp3',
        'Relax Music - Nicmusic - 04.mp3',
      ];
      try {
        for (final fileName in bundledTracks) {
          final releaseExecutable = path.join(
            Directory.current.path,
            'build',
            'windows',
            'x64',
            'runner',
            'Release',
            'goldbrain.exe',
          );
          final audioFile = File(
            WindowsAudioBackend.assetPathForExecutable(
              releaseExecutable,
              'assets/sounds/$fileName',
            ),
          );
          expect(audioFile.existsSync(), isTrue, reason: fileName);

          await backend!.playMusic(audioFile.path, loop: true, volume: 0.02);
          await Future<void>.delayed(const Duration(milliseconds: 350));
          expect(backend.musicMode(), 'playing', reason: fileName);
          await backend.stopMusic();
        }
      } finally {
        await backend?.dispose();
      }
    },
    skip: runNativeSmoke ? false : 'Enable with GOLDBRAIN_AUDIO_SMOKE=true.',
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
