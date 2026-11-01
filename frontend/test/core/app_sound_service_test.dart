import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/app_sound_service.dart';
import 'package:goldbrain/core/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const playlist = <String>['one.mp3', 'two.mp3', 'three.mp3'];

  test('sequential playlist wraps in both directions', () {
    expect(
      AppSoundService.resolveAdjacentCustomTrack(
        playlist: playlist,
        currentPath: 'three.mp3',
        mode: MusicPlaybackMode.sequential,
        direction: 1,
        automatic: true,
      ),
      'one.mp3',
    );
    expect(
      AppSoundService.resolveAdjacentCustomTrack(
        playlist: playlist,
        currentPath: 'one.mp3',
        mode: MusicPlaybackMode.sequential,
        direction: -1,
        automatic: false,
      ),
      'three.mp3',
    );
  });

  test('repeat-one affects automatic completion but not manual next', () {
    expect(
      AppSoundService.resolveAdjacentCustomTrack(
        playlist: playlist,
        currentPath: 'two.mp3',
        mode: MusicPlaybackMode.repeatOne,
        direction: 1,
        automatic: true,
      ),
      'two.mp3',
    );
    expect(
      AppSoundService.resolveAdjacentCustomTrack(
        playlist: playlist,
        currentPath: 'two.mp3',
        mode: MusicPlaybackMode.repeatOne,
        direction: 1,
        automatic: false,
      ),
      'three.mp3',
    );
  });

  test('shuffle excludes the current track', () {
    final next = AppSoundService.resolveAdjacentCustomTrack(
      playlist: playlist,
      currentPath: 'two.mp3',
      mode: MusicPlaybackMode.shuffle,
      direction: 1,
      automatic: true,
      shuffleIndex: 1,
    );

    expect(next, 'three.mp3');
    expect(next, isNot('two.mp3'));
  });

  test('Windows picker exposes only formats supported by its backends', () {
    expect(AppSoundService.supportedCustomMusicExtensions(isWindows: true), [
      'mp3',
      'wav',
      'm4a',
      'aac',
    ]);
  });

  test('bundled sections use the original full-length music files', () {
    expect(
      AppSoundService.bundledMusicAsset(AppMusicTrack.selection),
      'sounds/Light Piano x Guitar x Flute x Birds Singing.mp3',
    );
    expect(
      AppSoundService.bundledMusicAsset(AppMusicTrack.auth),
      'sounds/Beautiful_Relaxing_Music_1231354354.mp3',
    );
    expect(
      AppSoundService.bundledMusicAsset(AppMusicTrack.dashboard),
      'sounds/Relax Music - Nicmusic - 04.mp3',
    );
  });

  test(
    'stopping without a preview preserves the Windows playlist poller',
    () async {
      var stopCalls = 0;
      var resumeCalls = 0;
      final service = AppSoundService.testing(
        stopMusicPlayback: () async => stopCalls++,
        playCurrentBackground: (_) async => resumeCalls++,
      );
      addTearDown(service.dispose);
      service.setPreviewStateForTesting(
        previewActive: false,
        backgroundMusicAllowed: true,
        currentTrack: AppMusicTrack.dashboard,
        startWindowsPollTimer: true,
      );

      await service.stopPreviewAndResume();

      expect(service.hasActiveWindowsPollTimer, isTrue);
      expect(stopCalls, 0);
      expect(resumeCalls, 0);
    },
  );

  test(
    'stopping a real preview stops it and resumes background once',
    () async {
      var stopCalls = 0;
      var resumeCalls = 0;
      final service = AppSoundService.testing(
        stopMusicPlayback: () async => stopCalls++,
        playCurrentBackground: (forceReload) async {
          expect(forceReload, isTrue);
          resumeCalls++;
        },
      );
      addTearDown(service.dispose);
      service.setPreviewStateForTesting(
        previewActive: true,
        backgroundMusicAllowed: true,
        currentTrack: AppMusicTrack.dashboard,
        startWindowsPollTimer: true,
      );

      await service.stopPreviewAndResume();
      await service.stopPreviewAndResume();

      expect(service.isPreviewing, isFalse);
      expect(stopCalls, 1);
      expect(resumeCalls, 1);
    },
  );
}
