import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';

void main() {
  test(
    'a legacy import can create twins after a completed sample-prune pass',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final temp = await Directory.systemTemp.createTemp('ob5-sample-import-');
      await databaseFactory.setDatabasesPath(temp.path);
      LocalDb.dbName = 'test.db';
      try {
        expect(await LocalDb.pruneDuplicateSamples(), 0);
        final source = await databaseFactory.openDatabase(
          '${temp.path}/legacy.db',
        );
        await source.execute(
          'CREATE TABLE samples (device_id TEXT, ts_ms INTEGER, '
          'counter INTEGER, ts INTEGER, hr INTEGER)',
        );
        await source.execute(
          'CREATE TABLE decoded_onehz (device_id TEXT, ts_ms INTEGER, '
          'counter INTEGER, rec_ts INTEGER, hr INTEGER)',
        );
        await source.insert('samples', {
          'device_id': '',
          'ts_ms': 1000,
          'counter': 1,
          'ts': 1,
          'hr': 60,
        });
        await source.insert('decoded_onehz', {
          'device_id': '',
          'ts_ms': 1000,
          'counter': 1,
          'rec_ts': 1,
          'hr': 60,
        });
        await source.close();
        final counts = await LocalDb.importFromDbFile('${temp.path}/legacy.db');
        expect(counts['samples'], 1);
        expect(counts['decoded_onehz'], 1);
        final before = (await LocalDb.latestSample())!.toDbMap();
        expect(await LocalDb.pruneDuplicateSamples(), 1);
        expect(await (await LocalDb.instance).query('samples'), isEmpty);
        expect((await LocalDb.latestSample())!.toDbMap(), before);
      } finally {
        await LocalDb.close();
        await temp.delete(recursive: true);
      }
    },
  );
}
