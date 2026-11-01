import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Copies data from the application's legacy Windows roaming-data directory
/// into the current production directory without deleting legacy data.
///
/// Migration is intentionally best-effort: an unavailable or malformed file
/// must never prevent the application from starting.
class WindowsAppDataMigrator {
  const WindowsAppDataMigrator._();

  static const String _preferencesFileName = 'shared_preferences.json';
  static const String migrationMarkerFileName = '.legacy_app_data_migrated_v1';
  static const String _suspensionPreferenceKey =
      'flutter.settings.local_storage_suspended_v1';
  static const String _retentionPreferenceKey =
      'flutter.settings.data_retention';
  static const String _retentionDeadlinePreferenceKey =
      'flutter.settings.data_retention_deadline_v1';
  static const String _retentionConfirmedPreferenceKey =
      'flutter.settings.data_retention_confirmed_v1';
  static const Set<String> _authoritativeRetentionPreferenceKeys = <String>{
    _suspensionPreferenceKey,
    _retentionPreferenceKey,
    _retentionDeadlinePreferenceKey,
    _retentionConfirmedPreferenceKey,
  };
  static const Set<String> _managedPathPreferenceKeys = <String>{
    'flutter.profile_image_path',
    'flutter.settings.custom_music_path',
    'flutter.settings.custom_music_paths_v2',
    'flutter.settings.current_custom_music_path_v2',
  };

  /// Runs the production Windows migration when `%APPDATA%` is available.
  static Future<void> migrateForCurrentProcess() async {
    if (!Platform.isWindows) return;

    try {
      final appData = Platform.environment['APPDATA']?.trim();
      if (appData == null || appData.isEmpty) return;

      await migrate(
        legacyDirectory: Directory(
          path.join(appData, 'com.example', 'goldbrain'),
        ),
        destinationDirectory: Directory(
          path.join(appData, 'GoldBrain', 'GoldBrain'),
        ),
      );
    } on Object {
      // App-data migration is best-effort and must not block application boot.
    }
  }

  /// Migrates [legacyDirectory] recursively into [destinationDirectory].
  ///
  /// Existing non-preference destination files always win. On the first
  /// successful migration, `shared_preferences.json` is merged with legacy
  /// values winning conflicts and destination-only keys being retained. An
  /// atomic marker makes every later invocation a no-op.
  static Future<void> migrate({
    required Directory legacyDirectory,
    required Directory destinationDirectory,
  }) async {
    try {
      if (!await legacyDirectory.exists()) return;

      final legacyPath = path.normalize(path.absolute(legacyDirectory.path));
      final destinationPath = path.normalize(
        path.absolute(destinationDirectory.path),
      );
      if (path.equals(legacyPath, destinationPath)) return;

      final marker = File(path.join(destinationPath, migrationMarkerFileName));
      if (await marker.exists()) return;

      // Retention is authoritative before SettingsStore starts. Inspect the
      // destination file read-only and never copy legacy files or write a
      // migration marker while local storage has been suspended.
      if (!await _destinationAllowsMigration(destinationPath)) return;

      final files = <File>[];
      await for (final entity in legacyDirectory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) files.add(entity);
      }

      var migrationComplete = true;
      final createdDestinationFiles = <File>[];
      File? mergedDestinationPreferences;
      String? originalDestinationPreferences;
      var mergedDestinationPreferencesExisted = false;
      var preferencesWereMerged = false;

      Future<void> rollbackMigrationWrites() async {
        if (preferencesWereMerged && mergedDestinationPreferences != null) {
          await _restorePreferences(
            mergedDestinationPreferences,
            originalContents: originalDestinationPreferences,
            originallyExisted: mergedDestinationPreferencesExisted,
          );
        }
        await _deleteCreatedFiles(createdDestinationFiles);
      }

      File? legacyPreferences;
      for (final source in files) {
        try {
          final relativePath = path.relative(source.path, from: legacyPath);
          final destination = File(path.join(destinationPath, relativePath));

          if (path.equals(path.normalize(relativePath), _preferencesFileName)) {
            legacyPreferences = source;
            continue;
          }

          if (!await destination.exists()) {
            if (!await _destinationAllowsMigration(destinationPath)) {
              await rollbackMigrationWrites();
              return;
            }
            final created = await _copyFileIfMissingAtomically(
              source,
              destination,
            );
            if (created) createdDestinationFiles.add(destination);
            // Large media copies can outlive the configured retention
            // deadline. Re-check after the atomic rename and undo only files
            // this invocation created when persistence became disallowed.
            if (!await _destinationAllowsMigration(destinationPath)) {
              await rollbackMigrationWrites();
              return;
            }
          }
        } on Object {
          // A single unreadable file must not stop the remaining migration.
          migrationComplete = false;
        }
      }

      if (legacyPreferences != null) {
        if (!await _destinationAllowsMigration(destinationPath)) {
          await rollbackMigrationWrites();
          return;
        }
        mergedDestinationPreferences = File(
          path.join(destinationPath, _preferencesFileName),
        );
        mergedDestinationPreferencesExisted = await mergedDestinationPreferences
            .exists();
        originalDestinationPreferences = mergedDestinationPreferencesExisted
            ? await mergedDestinationPreferences.readAsString()
            : null;
        final merged = await _mergePreferences(
          legacyPreferences,
          mergedDestinationPreferences,
          legacyRoot: legacyPath,
          destinationRoot: destinationPath,
        );
        migrationComplete = migrationComplete && merged;
        if (!merged) {
          await rollbackMigrationWrites();
          return;
        }
        preferencesWereMerged = true;
        if (!await _destinationAllowsMigration(destinationPath)) {
          await rollbackMigrationWrites();
          return;
        }
      }

      if (migrationComplete) {
        if (!await _destinationAllowsMigration(destinationPath)) {
          await rollbackMigrationWrites();
          return;
        }
        await _writeMarkerAtomically(marker);
        if (!await _destinationAllowsMigration(destinationPath)) {
          try {
            if (await marker.exists()) await marker.delete();
          } on Object {
            // A marker must never authorize another migration write. If it is
            // locked, the authoritative preference policy still blocks work.
          }
          await rollbackMigrationWrites();
        }
      }
    } on Object {
      // Missing permissions, malformed paths, and other I/O failures are safe
      // to ignore because the current application data remains authoritative.
    }
  }

  static Future<bool> _destinationAllowsMigration(
    String destinationRoot,
  ) async {
    final preferences = File(path.join(destinationRoot, _preferencesFileName));
    if (!await preferences.exists()) return true;
    try {
      final decoded = jsonDecode(await preferences.readAsString());
      if (decoded is! Map) return false;
      return _preferencesAllowMigration(decoded, DateTime.now().toUtc());
    } on Object {
      // Fail closed: when retention state cannot be read safely, legacy data
      // must not be restored over the authoritative destination.
      return false;
    }
  }

  static bool _preferencesAllowMigration(
    Map<dynamic, dynamic> preferences,
    DateTime nowUtc,
  ) {
    if (preferences[_suspensionPreferenceKey] == true) return false;

    final explicitlyConfirmed =
        preferences[_retentionConfirmedPreferenceKey] == true;
    final retention = preferences[_retentionPreferenceKey];
    if (!explicitlyConfirmed || retention == null || retention == 'forever') {
      return true;
    }
    // A confirmed finite policy is authoritative. Missing/malformed policy
    // fields fail closed because restoring legacy data would be irreversible.
    if (retention is! String || retention.isEmpty) return false;
    final rawDeadline = preferences[_retentionDeadlinePreferenceKey];
    if (rawDeadline is! String || rawDeadline.isEmpty) return false;
    final deadline = DateTime.tryParse(rawDeadline)?.toUtc();
    if (deadline == null) return false;
    return nowUtc.isBefore(deadline);
  }

  static Future<bool> _mergePreferences(
    File legacyPreferences,
    File destinationPreferences, {
    required String legacyRoot,
    required String destinationRoot,
  }) async {
    try {
      final legacyJson = jsonDecode(await legacyPreferences.readAsString());
      if (legacyJson is! Map<String, dynamic>) {
        return false;
      }

      final Map<String, dynamic> destinationJson;
      if (await destinationPreferences.exists()) {
        final decodedDestination = jsonDecode(
          await destinationPreferences.readAsString(),
        );
        if (decodedDestination is! Map<String, dynamic>) return false;
        destinationJson = decodedDestination;
      } else {
        destinationJson = <String, dynamic>{};
      }

      final merged = <String, dynamic>{...destinationJson};
      for (final entry in legacyJson.entries) {
        merged[entry.key] = entry.value;
      }
      // Destination retention is a newer, explicit user decision. Legacy
      // preference merging may win ordinary conflicts, but never these keys.
      for (final key in _authoritativeRetentionPreferenceKeys) {
        if (destinationJson.containsKey(key)) {
          merged[key] = destinationJson[key];
        }
      }
      await _remapManagedPreferencePaths(
        merged,
        legacyRoot: legacyRoot,
        destinationRoot: destinationRoot,
      );

      if (!_preferencesAllowMigration(merged, DateTime.now().toUtc())) {
        return false;
      }
      if (!await _destinationAllowsMigration(destinationRoot)) return false;
      await _writeTextAtomically(destinationPreferences, jsonEncode(merged));
      return true;
    } on Object {
      // Preserve the destination file unchanged when either JSON document is
      // malformed or an I/O operation fails.
      return false;
    }
  }

  static Future<void> _remapManagedPreferencePaths(
    Map<String, dynamic> preferences, {
    required String legacyRoot,
    required String destinationRoot,
  }) async {
    for (final key in _managedPathPreferenceKeys) {
      final value = preferences[key];
      if (value is String) {
        preferences[key] = await _remapManagedPath(
          value,
          legacyRoot: legacyRoot,
          destinationRoot: destinationRoot,
        );
      } else if (value is List) {
        final remapped = <dynamic>[];
        for (final item in value) {
          if (item is String) {
            remapped.add(
              await _remapManagedPath(
                item,
                legacyRoot: legacyRoot,
                destinationRoot: destinationRoot,
              ),
            );
          } else {
            remapped.add(item);
          }
        }
        preferences[key] = remapped;
      }
    }
  }

  static Future<String> _remapManagedPath(
    String value, {
    required String legacyRoot,
    required String destinationRoot,
  }) async {
    if (!path.isAbsolute(value)) return value;

    final normalizedValue = path.normalize(value);
    if (!path.equals(normalizedValue, legacyRoot) &&
        !path.isWithin(legacyRoot, normalizedValue)) {
      return value;
    }

    final migratedPath = path.normalize(
      path.join(
        destinationRoot,
        path.relative(normalizedValue, from: legacyRoot),
      ),
    );
    return await File(migratedPath).exists() ? migratedPath : value;
  }

  static Future<bool> _copyFileIfMissingAtomically(
    File source,
    File destination,
  ) async {
    final suffix = '$pid.${DateTime.now().microsecondsSinceEpoch}';
    final temporary = File('${destination.path}.$suffix.tmp');
    await destination.parent.create(recursive: true);

    try {
      await source.copy(temporary.path);
      if (await destination.exists()) return false;
      await temporary.rename(destination.path);
      return true;
    } on FileSystemException {
      // Another process may have completed the same migration concurrently.
      // In that case the established destination remains authoritative.
      if (!await destination.exists()) rethrow;
      return false;
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on Object {
        // Cleanup failure is harmless; no source or destination is removed.
      }
    }
  }

  static Future<void> _deleteCreatedFiles(List<File> files) async {
    for (final file in files.reversed) {
      try {
        if (await file.exists()) await file.delete();
      } on Object {
        // Best-effort rollback. Containment is guaranteed because this list
        // only contains destinations derived below destinationRoot.
      }
    }
  }

  static Future<void> _restorePreferences(
    File destination, {
    required String? originalContents,
    required bool originallyExisted,
  }) async {
    try {
      if (originallyExisted && originalContents != null) {
        await _writeTextAtomically(destination, originalContents);
      } else if (await destination.exists()) {
        await destination.delete();
      }
    } on Object {
      // Best-effort rollback; SettingsStore still enforces the destination
      // policy before any application persistence writer starts.
    }
  }

  static Future<void> _writeTextAtomically(
    File destination,
    String contents,
  ) async {
    final suffix = '$pid.${DateTime.now().microsecondsSinceEpoch}';
    final temporary = File('${destination.path}.$suffix.tmp');
    final backup = File('${destination.path}.$suffix.bak');
    var movedExistingFile = false;

    await destination.parent.create(recursive: true);
    try {
      await temporary.writeAsString(contents, flush: true);
      if (await destination.exists()) {
        await destination.rename(backup.path);
        movedExistingFile = true;
      }
      await temporary.rename(destination.path);
    } on Object {
      try {
        if (!await destination.exists() &&
            movedExistingFile &&
            await backup.exists()) {
          await backup.rename(destination.path);
        }
      } on Object {
        // Best-effort rollback; the original backup is kept if restore fails.
      }
      rethrow;
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on Object {
        // Cleanup failure is harmless and will not expose file contents.
      }
    }

    try {
      if (await backup.exists()) await backup.delete();
    } on Object {
      // The destination is already valid; a stale rollback file is harmless.
    }
  }

  static Future<void> _writeMarkerAtomically(File marker) async {
    await _writeTextAtomically(marker, '1');
  }
}
