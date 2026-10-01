import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:openstrap_edge/data/db.dart';

void main() {
  final source = Platform.environment['OB5_STORAGE_TIMING_DB'];
  test(
    'time schema 68 to 69 LocalDb open on a disposable copy',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final temp = await Directory.systemTemp.createTemp('ob5-migration-');
      try {
        final path = '${temp.path}/timing.db';
        await File(source!).copy(path);
        final chmod = await Process.run('chmod', ['600', path]);
        expect(chmod.exitCode, 0);
        await databaseFactory.setDatabasesPath(temp.path);
        LocalDb.dbName = 'timing.db';
        final before = await databaseFactory.openDatabase(
          path,
          options: OpenDatabaseOptions(readOnly: true),
        );
        expect(await before.getVersion(), 68);
        final count = Sqflite.firstIntValue(
          await before.rawQuery('SELECT COUNT(*) FROM decoded_onehz'),
        );
        await before.close();
        final timer = Stopwatch()..start();
        final db = await LocalDb.instance;
        timer.stop();
        expect(await db.getVersion(), 69);
        expect(
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM decoded_onehz'),
          ),
          count,
        );
        expect(
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM decoded_onehz WHERE onehz_enc IS NOT NULL',
            ),
          ),
          0,
        );
        expect(
          (await db.rawQuery('PRAGMA quick_check')).single.values.single,
          'ok',
        );
        // Counts and timings only; never log source rows or physiological values.
        // ignore: avoid_print
        print(
          'LocalDb 68->69 open: ${timer.elapsedMicroseconds / 1000} ms; retained rows: $count',
        );
      } finally {
        await LocalDb.close();
        await temp.delete(recursive: true);
      }
    },
    skip: source == null
        ? 'Set OB5_STORAGE_TIMING_DB to an authorized read-only DB copy'
        : false,
  );
}
