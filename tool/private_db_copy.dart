import 'dart:ffi';
import 'dart:io';

Future<void> createPrivateDirectory(Directory directory) async {
  final made = await Process.run('mkdir', ['-p', '-m', '700', directory.path]);
  final restricted = await Process.run('chmod', ['700', directory.path]);
  if (made.exitCode != 0 || restricted.exitCode != 0) {
    throw StateError('Private directory permissions');
  }
}

/// SQLite's sidecars inherit the process umask when created, including files
/// created by the FFI database worker. The report directory survives cleanup.
Future<T> withPrivateDbCopy<T>(
  File source,
  Directory root,
  Future<T> Function(Directory directory) use, {
  required Future<void> Function() closeDatabase,
}) async {
  final umask = DynamicLibrary.process()
      .lookupFunction<Uint32 Function(Uint32), int Function(int)>('umask');
  final previous = umask(0x3f); // 0077: main and sidecars are owner-only.
  final directory = Directory('${root.path}/copy');
  try {
    await createPrivateDirectory(root);
    await createPrivateDirectory(directory);
    final target = await source.copy('${directory.path}/openstrap.db');
    // copy() preserves the source mode, which may be read-only or broader.
    if ((await Process.run('chmod', ['600', target.path])).exitCode != 0) {
      throw StateError('Private copy permissions');
    }
    return await use(directory);
  } finally {
    try {
      await closeDatabase();
    } finally {
      try {
        if (directory.existsSync()) await directory.delete(recursive: true);
      } finally {
        umask(previous);
      }
    }
  }
}
