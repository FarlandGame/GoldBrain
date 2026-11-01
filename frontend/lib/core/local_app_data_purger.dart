import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Deletes only files copied and owned by GoldBrain below its application
/// support directory. User-selected source files outside that directory are
/// never inspected or removed.
class LocalAppDataPurger {
  LocalAppDataPurger._()
    : _supportDirectoryLoader = getApplicationSupportDirectory;

  @visibleForTesting
  LocalAppDataPurger.testing({
    required Future<Directory> Function() supportDirectoryLoader,
  }) : _supportDirectoryLoader = supportDirectoryLoader;

  static final LocalAppDataPurger instance = LocalAppDataPurger._();

  static const managedDirectoryNames = <String>[
    'music',
    'profile',
    // Legacy builds copied custom music here.
    'managed/custom_music',
  ];

  final Future<Directory> Function() _supportDirectoryLoader;

  /// Returns false when a managed file is temporarily locked. A later app
  /// startup can retry without broadening the deletion scope.
  Future<bool> purge() async {
    final supportDirectory = await _supportDirectoryLoader();
    final supportRoot = path.normalize(path.absolute(supportDirectory.path));
    var complete = true;

    for (final name in managedDirectoryNames) {
      final candidate = path.normalize(
        path.absolute(path.join(supportRoot, name)),
      );
      if (!path.isWithin(supportRoot, candidate)) {
        complete = false;
        continue;
      }
      try {
        final type = await FileSystemEntity.type(candidate, followLinks: false);
        switch (type) {
          case FileSystemEntityType.directory:
            await Directory(candidate).delete(recursive: true);
            break;
          case FileSystemEntityType.file:
            await File(candidate).delete();
            break;
          case FileSystemEntityType.link:
            // Delete the link itself, never the target it may point to.
            await Link(candidate).delete();
            break;
          case FileSystemEntityType.notFound:
            break;
          default:
            complete = false;
            break;
        }
      } on FileSystemException {
        complete = false;
      }
    }
    return complete;
  }
}
