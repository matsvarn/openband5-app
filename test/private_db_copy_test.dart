import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../tool/private_db_copy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  for (final fail in [false, true]) {
    test(
      'private SQLite copy modes and cleanup on ${fail ? 'failure' : 'success'}',
      () async {
        final scratch = Directory.systemTemp.createTempSync(
          'ob5-private-copy-',
        );
        File('${scratch.path}/before').writeAsStringSync('synthetic');
        final modeBefore =
            File('${scratch.path}/before').statSync().mode & 0x1ff;
        final source = File('${scratch.path}/source.db');
        final root = Directory('${scratch.path}/report');
        Database? opened;
        try {
          final seed = await databaseFactoryFfi.openDatabase(source.path);
          await seed.execute('CREATE TABLE synthetic (id INTEGER PRIMARY KEY)');
          await seed.close();
          await Process.run('chmod', ['644', source.path]);
          Future<void> run() =>
              withPrivateDbCopy(source, root, (directory) async {
                expect(root.statSync().mode & 0x1ff, 0x1c0); // 0700
                expect(directory.statSync().mode & 0x1ff, 0x1c0);
                final main = File('${directory.path}/openstrap.db');
                expect(main.statSync().mode & 0x1ff, 0x180); // 0600
                File('${root.path}/report.txt').writeAsStringSync('rows=1\n');
                final db = opened = await databaseFactoryFfi.openDatabase(
                  main.path,
                );
                await db.rawQuery('PRAGMA journal_mode=DELETE');
                await db.execute('BEGIN IMMEDIATE');
                await db.execute('INSERT INTO synthetic VALUES (1)');
                final journal = File('${main.path}-journal');
                expect(journal.existsSync(), isTrue);
                expect(journal.statSync().mode & 0x1ff, 0x180);
                await db.execute('COMMIT');
                await db.rawQuery('PRAGMA journal_mode=WAL');
                await db.execute('INSERT INTO synthetic VALUES (2)');
                for (final suffix in ['-wal', '-shm']) {
                  final file = File('${main.path}$suffix');
                  expect(file.existsSync(), isTrue);
                  expect(file.statSync().mode & 0x1ff, 0x180);
                }
                if (fail) throw StateError('Synthetic failure');
              }, closeDatabase: () async => opened?.close());
          if (fail) {
            await expectLater(run(), throwsStateError);
          } else {
            await run();
          }
          expect(Directory('${root.path}/copy').existsSync(), isFalse);
          expect(root.listSync().map((entry) => entry.path), [
            '${root.path}/report.txt',
          ]);
          expect(source.existsSync(), isTrue);
          final after = File('${scratch.path}/after')
            ..writeAsStringSync('synthetic');
          expect(after.statSync().mode & 0x1ff, modeBefore);
        } finally {
          await opened?.close();
          scratch.deleteSync(recursive: true);
        }
      },
    );
  }
}
