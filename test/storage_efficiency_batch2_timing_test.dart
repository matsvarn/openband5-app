import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';

void main() {
  final source = Platform.environment['OB5_STORAGE_TIMING_DB'];
  test(
    'compare timestamp bounds and cached health on an authorized DB copy',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final temp = await Directory.systemTemp.createTemp('ob5-batch2-timing-');
      try {
        final path = '${temp.path}/timing.db';
        await File(source!).copy(path);
        expect((await Process.run('chmod', ['600', path])).exitCode, 0);
        await databaseFactory.setDatabasesPath(temp.path);
        LocalDb.dbName = 'timing.db';
        final db = await LocalDb.instance;
        final clock = Stopwatch()..start();
        final old = (await db.rawQuery(
          'SELECT MIN(rec_ts) lo, MAX(rec_ts) hi '
          'FROM decoded_onehz WHERE rec_ts > 0 AND ${derivableSourceSql()}',
        )).single;
        final aggregateMs = clock.elapsedMicroseconds / 1000;
        clock.reset();
        final bounds = await LocalDb.firstAndLastRecordTs();
        final seeksMs = clock.elapsedMicroseconds / 1000;
        // Assert a boolean so a failure cannot print private timestamps.
        expect(
          bounds ==
              ((old['lo'] as num?)?.toInt(), (old['hi'] as num?)?.toInt()),
          isTrue,
        );
        await db.delete(
          'compute_freshness',
          where: 'key = ?',
          whereArgs: [LocalDb.kIntegrityHealthKey],
        );
        clock.reset();
        final full = await LocalDb.schemaHealth();
        final fullMs = clock.elapsedMicroseconds / 1000;
        expect(full['ok'] == true, isTrue);
        await LocalDb.close();
        await LocalDb.instance;
        clock.reset();
        final cached = await LocalDb.schemaHealth();
        final cachedMs = clock.elapsedMicroseconds / 1000;
        expect(cached['ok'] == full['ok'], isTrue);
        clock.stop();
        // ignore: avoid_print
        print(
          'Bounds aggregate: $aggregateMs ms; ordered seeks: $seeksMs ms; '
          'full health: $fullMs ms; persisted cached health after reopen: $cachedMs ms',
        );
      } finally {
        await LocalDb.close();
        await temp.delete(recursive: true);
      }
    },
    skip: source == null
        ? 'Set OB5_STORAGE_TIMING_DB to an authorized read-only copy'
        : false,
  );
}
