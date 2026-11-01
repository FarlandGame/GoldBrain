import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'local_app_data_purger.dart';
import 'local_persistence_policy.dart';

class LocalPersistenceSuspendedException implements Exception {
  const LocalPersistenceSuspendedException();
}

/// Owns copies created below GoldBrain's support directory. It checks the
/// retention policy both before and after potentially long file copies.
class ManagedAppFileStore {
  ManagedAppFileStore._()
    : _supportDirectoryLoader = getApplicationSupportDirectory,
      _canWrite = (() => LocalPersistencePolicy.instance.canWrite),
      _copy = ((source, destination) => source.copy(destination));

  @visibleForTesting
  ManagedAppFileStore.testing({
    required Future<Directory> Function() supportDirectoryLoader,
    required bool Function() canWrite,
    Future<File> Function(File, String)? copy,
  }) : _supportDirectoryLoader = supportDirectoryLoader,
       _canWrite = canWrite,
       _copy = copy ?? ((source, destination) => source.copy(destination));

  static final ManagedAppFileStore instance = ManagedAppFileStore._();

  final Future<Directory> Function() _supportDirectoryLoader;
  final bool Function() _canWrite;
  final Future<File> Function(File, String) _copy;

  Future<File> copy({
    required File source,
    required String directoryName,
    required String fileName,
  }) async {
    if (!_canWrite()) throw const LocalPersistenceSuspendedException();
    if (!LocalAppDataPurger.managedDirectoryNames.contains(directoryName)) {
      throw ArgumentError.value(directoryName, 'directoryName');
    }
    final support = await _supportDirectoryLoader();
    final supportRoot = path.normalize(path.absolute(support.path));
    final managedRoot = path.normalize(
      path.absolute(path.join(supportRoot, directoryName)),
    );
    final destination = path.normalize(
      path.absolute(path.join(managedRoot, path.basename(fileName))),
    );
    if (!path.isWithin(supportRoot, managedRoot) ||
        !path.isWithin(managedRoot, destination)) {
      throw const FileSystemException('Invalid managed file destination.');
    }
    if (!_canWrite()) throw const LocalPersistenceSuspendedException();
    await Directory(managedRoot).create(recursive: true);
    if (!_canWrite()) throw const LocalPersistenceSuspendedException();
    final normalizedSource = path.normalize(path.absolute(source.path));
    if (path.equals(normalizedSource, destination)) return source;
    final existing = File(destination);
    if (await existing.exists()) await existing.delete();
    if (!_canWrite()) throw const LocalPersistenceSuspendedException();
    final copied = await _copy(source, destination);
    if (!_canWrite()) {
      try {
        if (await copied.exists()) await copied.delete();
      } on FileSystemException {
        // The retention purger retries this managed directory at startup.
      }
      throw const LocalPersistenceSuspendedException();
    }
    return copied;
  }

  Future<void> delete({
    required String directoryName,
    required String filePath,
  }) async {
    if (!LocalAppDataPurger.managedDirectoryNames.contains(directoryName)) {
      return;
    }
    final support = await _supportDirectoryLoader();
    final supportRoot = path.normalize(path.absolute(support.path));
    final managedRoot = path.normalize(
      path.absolute(path.join(supportRoot, directoryName)),
    );
    final candidate = path.normalize(path.absolute(filePath));
    if (!path.isWithin(supportRoot, managedRoot) ||
        !path.isWithin(managedRoot, candidate)) {
      return;
    }
    try {
      final type = await FileSystemEntity.type(candidate, followLinks: false);
      if (type == FileSystemEntityType.file) {
        await File(candidate).delete();
      } else if (type == FileSystemEntityType.link) {
        await Link(candidate).delete();
      }
    } on FileSystemException {
      // Optional stale files can be retried by the retention purger.
    }
  }
}
