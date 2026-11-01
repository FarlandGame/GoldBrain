import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/windows_app_data_migrator.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory sandbox;
  late Directory legacy;
  late Directory destination;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'goldbrain_app_data_migration_',
    );
    legacy = Directory(path.join(sandbox.path, 'legacy'));
    destination = Directory(path.join(sandbox.path, 'destination'));
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('copies a source-only preferences file', () async {
    final source = File(path.join(legacy.path, 'shared_preferences.json'));
    await source.parent.create(recursive: true);
    await source.writeAsString(jsonEncode(<String, Object>{'language': 'fa'}));

    await WindowsAppDataMigrator.migrate(
      legacyDirectory: legacy,
      destinationDirectory: destination,
    );

    final migrated = File(
      path.join(destination.path, 'shared_preferences.json'),
    );
    expect(await migrated.exists(), isTrue);
    expect(jsonDecode(await migrated.readAsString()), <String, Object>{
      'language': 'fa',
    });
    expect(await source.exists(), isTrue);
  });

  test('suspended destination prevents every migration write', () async {
    final sourcePreferences = File(
      path.join(legacy.path, 'shared_preferences.json'),
    );
    final sourceProfile = File(
      path.join(legacy.path, 'profile', 'profile_image.jpg'),
    );
    final targetPreferences = File(
      path.join(destination.path, 'shared_preferences.json'),
    );
    await sourceProfile.parent.create(recursive: true);
    await targetPreferences.parent.create(recursive: true);
    await sourcePreferences.writeAsString(
      jsonEncode(<String, Object>{'legacy': true}),
    );
    await sourceProfile.writeAsBytes(<int>[1, 2, 3]);
    final authoritative = jsonEncode(<String, Object>{
      'flutter.settings.local_storage_suspended_v1': true,
      'flutter.settings.theme_code': 'black',
    });
    await targetPreferences.writeAsString(authoritative);

    await WindowsAppDataMigrator.migrate(
      legacyDirectory: legacy,
      destinationDirectory: destination,
    );

    expect(await targetPreferences.readAsString(), authoritative);
    expect(
      await File(
        path.join(destination.path, 'profile', 'profile_image.jpg'),
      ).exists(),
      isFalse,
    );
    expect(
      await File(
        path.join(
          destination.path,
          WindowsAppDataMigrator.migrationMarkerFileName,
        ),
      ).exists(),
      isFalse,
    );
  });

  test(
    'expired confirmed retention prevents files preferences and marker writes',
    () async {
      final sourcePreferences = File(
        path.join(legacy.path, 'shared_preferences.json'),
      );
      final sourceMusic = File(
        path.join(legacy.path, 'managed', 'custom_music', 'legacy.mp3'),
      );
      final targetPreferences = File(
        path.join(destination.path, 'shared_preferences.json'),
      );
      await sourceMusic.parent.create(recursive: true);
      await targetPreferences.parent.create(recursive: true);
      await sourcePreferences.writeAsString(
        jsonEncode(<String, Object>{'legacy': true}),
      );
      await sourceMusic.writeAsBytes(<int>[1, 2, 3]);
      final authoritative = jsonEncode(<String, Object>{
        'flutter.settings.data_retention': '30_days',
        'flutter.settings.data_retention_confirmed_v1': true,
        'flutter.settings.data_retention_deadline_v1':
            '2020-01-01T00:00:00.000Z',
        'flutter.settings.local_storage_suspended_v1': false,
      });
      await targetPreferences.writeAsString(authoritative);

      await WindowsAppDataMigrator.migrate(
        legacyDirectory: legacy,
        destinationDirectory: destination,
      );

      expect(await targetPreferences.readAsString(), authoritative);
      expect(
        await File(
          path.join(destination.path, 'managed', 'custom_music', 'legacy.mp3'),
        ).exists(),
        isFalse,
      );
      expect(
        await File(
          path.join(
            destination.path,
            WindowsAppDataMigrator.migrationMarkerFileName,
          ),
        ).exists(),
        isFalse,
      );
    },
  );

  test('confirmed retention with a malformed deadline fails closed', () async {
    final source = File(path.join(legacy.path, 'profile', 'legacy.jpg'));
    final targetPreferences = File(
      path.join(destination.path, 'shared_preferences.json'),
    );
    await source.parent.create(recursive: true);
    await targetPreferences.parent.create(recursive: true);
    await source.writeAsBytes(<int>[1]);
    await targetPreferences.writeAsString(
      jsonEncode(<String, Object>{
        'flutter.settings.data_retention': '90_days',
        'flutter.settings.data_retention_confirmed_v1': true,
        'flutter.settings.data_retention_deadline_v1': 'not-a-date',
      }),
    );

    await WindowsAppDataMigrator.migrate(
      legacyDirectory: legacy,
      destinationDirectory: destination,
    );

    expect(
      await File(path.join(destination.path, 'profile', 'legacy.jpg')).exists(),
      isFalse,
    );
    expect(
      await File(
        path.join(
          destination.path,
          WindowsAppDataMigrator.migrationMarkerFileName,
        ),
      ).exists(),
      isFalse,
    );
  });

  test(
    'malformed destination preferences fail closed without writes',
    () async {
      final sourcePreferences = File(
        path.join(legacy.path, 'shared_preferences.json'),
      );
      final sourceMusic = File(path.join(legacy.path, 'music', 'copy.mp3'));
      final targetPreferences = File(
        path.join(destination.path, 'shared_preferences.json'),
      );
      await sourceMusic.parent.create(recursive: true);
      await targetPreferences.parent.create(recursive: true);
      await sourcePreferences.writeAsString(jsonEncode({'legacy': true}));
      await sourceMusic.writeAsBytes(<int>[1, 2, 3]);
      await targetPreferences.writeAsString('{invalid-destination');

      await WindowsAppDataMigrator.migrate(
        legacyDirectory: legacy,
        destinationDirectory: destination,
      );

      expect(await targetPreferences.readAsString(), '{invalid-destination');
      expect(
        await File(path.join(destination.path, 'music', 'copy.mp3')).exists(),
        isFalse,
      );
      expect(
        await File(
          path.join(
            destination.path,
            WindowsAppDataMigrator.migrationMarkerFileName,
          ),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'first migration merges preferences with legacy values winning',
    () async {
      final source = File(path.join(legacy.path, 'shared_preferences.json'));
      final target = File(
        path.join(destination.path, 'shared_preferences.json'),
      );
      await source.parent.create(recursive: true);
      await target.parent.create(recursive: true);
      await source.writeAsString(
        jsonEncode(<String, Object>{
          'language': 'fa',
          'theme': 'gold',
          'saved_chats': <String>['legacy'],
        }),
      );
      await target.writeAsString(
        jsonEncode(<String, Object>{'theme': 'blue', 'news_cursor': 12}),
      );

      await WindowsAppDataMigrator.migrate(
        legacyDirectory: legacy,
        destinationDirectory: destination,
      );

      expect(jsonDecode(await target.readAsString()), <String, Object>{
        'theme': 'gold',
        'news_cursor': 12,
        'language': 'fa',
        'saved_chats': <String>['legacy'],
      });
      expect(
        await File(
          path.join(
            destination.path,
            WindowsAppDataMigrator.migrationMarkerFileName,
          ),
        ).exists(),
        isTrue,
      );
    },
  );

  test('keeps an existing non-preferences destination file', () async {
    final source = File(path.join(legacy.path, 'managed', 'playlist.json'));
    final target = File(
      path.join(destination.path, 'managed', 'playlist.json'),
    );
    await source.parent.create(recursive: true);
    await target.parent.create(recursive: true);
    await source.writeAsString('legacy playlist');
    await target.writeAsString('current playlist');

    await WindowsAppDataMigrator.migrate(
      legacyDirectory: legacy,
      destinationDirectory: destination,
    );

    expect(await target.readAsString(), 'current playlist');
    expect(await source.readAsString(), 'legacy playlist');
  });

  test('can be rerun without changing the completed migration', () async {
    final source = File(path.join(legacy.path, 'shared_preferences.json'));
    final target = File(path.join(destination.path, 'shared_preferences.json'));
    await source.parent.create(recursive: true);
    await target.parent.create(recursive: true);
    await source.writeAsString(jsonEncode(<String, Object>{'legacy': true}));
    await target.writeAsString(jsonEncode(<String, Object>{'current': true}));

    await WindowsAppDataMigrator.migrate(
      legacyDirectory: legacy,
      destinationDirectory: destination,
    );
    final afterFirstRun = await target.readAsString();
    await target.writeAsString(
      jsonEncode(<String, Object>{'current': 'user edit', 'legacy': 'edit'}),
    );
    final afterUserEdit = await target.readAsString();
    await source.writeAsString(
      jsonEncode(<String, Object>{'legacy': false, 'later': true}),
    );

    await WindowsAppDataMigrator.migrate(
      legacyDirectory: legacy,
      destinationDirectory: destination,
    );

    expect(await target.readAsString(), afterUserEdit);
    expect(jsonDecode(afterFirstRun), <String, Object>{
      'current': true,
      'legacy': true,
    });
  });

  test('copies nested profile and managed-music binary files', () async {
    final profile = File(
      path.join(legacy.path, 'profile', 'profile_image.jpg'),
    );
    final music = File(
      path.join(legacy.path, 'managed', 'custom_music', 'track.mp3'),
    );
    await profile.parent.create(recursive: true);
    await music.parent.create(recursive: true);
    await profile.writeAsBytes(<int>[0xff, 0xd8, 0x00, 0xff]);
    await music.writeAsBytes(<int>[0x49, 0x44, 0x33, 0x00, 0x7f]);

    await WindowsAppDataMigrator.migrate(
      legacyDirectory: legacy,
      destinationDirectory: destination,
    );

    expect(
      await File(
        path.join(destination.path, 'profile', 'profile_image.jpg'),
      ).readAsBytes(),
      <int>[0xff, 0xd8, 0x00, 0xff],
    );
    expect(
      await File(
        path.join(destination.path, 'managed', 'custom_music', 'track.mp3'),
      ).readAsBytes(),
      <int>[0x49, 0x44, 0x33, 0x00, 0x7f],
    );
  });

  test('remaps only known managed paths after copying their files', () async {
    final profilePath = path.join(legacy.path, 'profile', 'profile_image.jpg');
    final trackPath = path.join(
      legacy.path,
      'managed',
      'custom_music',
      'track.mp3',
    );
    final externalPath = path.join(sandbox.path, 'external.mp3');
    await File(profilePath).parent.create(recursive: true);
    await File(trackPath).parent.create(recursive: true);
    await File(profilePath).writeAsBytes(<int>[1, 2, 3]);
    await File(trackPath).writeAsBytes(<int>[4, 5, 6]);
    final source = File(path.join(legacy.path, 'shared_preferences.json'));
    await source.writeAsString(
      jsonEncode(<String, Object>{
        'flutter.profile_image_path': profilePath,
        'flutter.settings.custom_music_path': trackPath,
        'flutter.settings.custom_music_paths_v2': <String>[
          trackPath,
          externalPath,
        ],
        'flutter.settings.current_custom_music_path_v2': trackPath,
        'flutter.saved_chat_text': 'Do not rewrite $trackPath',
      }),
    );

    await WindowsAppDataMigrator.migrate(
      legacyDirectory: legacy,
      destinationDirectory: destination,
    );

    final migratedPreferences =
        jsonDecode(
              await File(
                path.join(destination.path, 'shared_preferences.json'),
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final migratedProfile = path.join(
      destination.path,
      'profile',
      'profile_image.jpg',
    );
    final migratedTrack = path.join(
      destination.path,
      'managed',
      'custom_music',
      'track.mp3',
    );

    expect(migratedPreferences['flutter.profile_image_path'], migratedProfile);
    expect(
      migratedPreferences['flutter.settings.custom_music_path'],
      migratedTrack,
    );
    expect(
      migratedPreferences['flutter.settings.custom_music_paths_v2'],
      <String>[migratedTrack, externalPath],
    );
    expect(
      migratedPreferences['flutter.settings.current_custom_music_path_v2'],
      migratedTrack,
    );
    expect(
      migratedPreferences['flutter.saved_chat_text'],
      'Do not rewrite $trackPath',
    );
    expect(await File(migratedProfile).exists(), isTrue);
    expect(await File(migratedTrack).exists(), isTrue);
  });

  test('leaves no temporary files after a successful migration', () async {
    final source = File(path.join(legacy.path, 'shared_preferences.json'));
    await source.parent.create(recursive: true);
    await source.writeAsString(jsonEncode(<String, Object>{'legacy': true}));

    await WindowsAppDataMigrator.migrate(
      legacyDirectory: legacy,
      destinationDirectory: destination,
    );

    final names = await destination
        .list()
        .map((entity) => path.basename(entity.path))
        .toList();
    expect(names.where((name) => name.endsWith('.tmp')), isEmpty);
    expect(names.where((name) => name.endsWith('.bak')), isEmpty);
    expect(names, contains(WindowsAppDataMigrator.migrationMarkerFileName));
  });

  test(
    'malformed legacy preferences do not throw or mark completion',
    () async {
      final source = File(path.join(legacy.path, 'shared_preferences.json'));
      await source.parent.create(recursive: true);
      await source.writeAsString('{not-json');

      await WindowsAppDataMigrator.migrate(
        legacyDirectory: legacy,
        destinationDirectory: destination,
      );

      expect(
        await File(
          path.join(
            destination.path,
            WindowsAppDataMigrator.migrationMarkerFileName,
          ),
        ).exists(),
        isFalse,
      );
      expect(await source.readAsString(), '{not-json');
    },
  );
}
