import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/managed_app_file_store.dart';
import 'package:path/path.dart' as path;

void main() {
  test('copy race deletes managed result after retention suspends', () async {
    final sandbox = await Directory.systemTemp.createTemp('managed-copy-race-');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });
    final support = Directory(path.join(sandbox.path, 'support'));
    final source = File(path.join(sandbox.path, 'source.mp3'));
    await source.writeAsString('source remains owned by user');
    var canWrite = true;
    final store = ManagedAppFileStore.testing(
      supportDirectoryLoader: () async => support,
      canWrite: () => canWrite,
      copy: (file, destination) async {
        final result = await file.copy(destination);
        canWrite = false;
        return result;
      },
    );

    await expectLater(
      store.copy(
        source: source,
        directoryName: 'music',
        fileName: 'managed.mp3',
      ),
      throwsA(isA<LocalPersistenceSuspendedException>()),
    );
    expect(await source.exists(), isTrue);
    expect(
      await File(path.join(support.path, 'music', 'managed.mp3')).exists(),
      isFalse,
    );
  });

  test('delete cannot remove an external profile path', () async {
    final sandbox = await Directory.systemTemp.createTemp('managed-delete-');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });
    final support = Directory(path.join(sandbox.path, 'support'));
    final external = File(path.join(sandbox.path, 'external-profile.png'));
    final managed = File(path.join(support.path, 'profile', 'profile.png'));
    await external.writeAsString('external');
    await managed.parent.create(recursive: true);
    await managed.writeAsString('managed');
    final store = ManagedAppFileStore.testing(
      supportDirectoryLoader: () async => support,
      canWrite: () => true,
    );

    await store.delete(directoryName: 'profile', filePath: external.path);
    await store.delete(directoryName: 'profile', filePath: managed.path);

    expect(await external.exists(), isTrue);
    expect(await managed.exists(), isFalse);
  });
}
