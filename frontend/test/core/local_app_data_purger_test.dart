import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/local_app_data_purger.dart';
import 'package:path/path.dart' as path;

void main() {
  test(
    'purges only known GoldBrain-owned support folders and preserves sources',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'goldbrain-retention-test-',
      );
      addTearDown(() async {
        if (await sandbox.exists()) await sandbox.delete(recursive: true);
      });
      final support = Directory(path.join(sandbox.path, 'support'));
      final source = File(path.join(sandbox.path, 'original-user-song.mp3'));
      final unrelated = File(path.join(support.path, 'unrelated.txt'));
      final managedMusic = File(path.join(support.path, 'music', 'copy.mp3'));
      final managedProfile = File(
        path.join(support.path, 'profile', 'profile_image.png'),
      );
      final legacyManagedMusic = File(
        path.join(support.path, 'managed', 'custom_music', 'legacy.mp3'),
      );
      await managedMusic.parent.create(recursive: true);
      await managedProfile.parent.create(recursive: true);
      await legacyManagedMusic.parent.create(recursive: true);
      await source.writeAsString('user-owned');
      await unrelated.writeAsString('other app support data');
      await managedMusic.writeAsString('managed copy');
      await managedProfile.writeAsString('managed image');
      await legacyManagedMusic.writeAsString('legacy managed copy');

      final purger = LocalAppDataPurger.testing(
        supportDirectoryLoader: () async => support,
      );
      expect(await purger.purge(), isTrue);

      expect(await source.exists(), isTrue);
      expect(await unrelated.exists(), isTrue);
      expect(
        await Directory(path.join(support.path, 'music')).exists(),
        isFalse,
      );
      expect(
        await Directory(path.join(support.path, 'profile')).exists(),
        isFalse,
      );
      expect(
        await Directory(
          path.join(support.path, 'managed', 'custom_music'),
        ).exists(),
        isFalse,
      );
    },
  );
}
