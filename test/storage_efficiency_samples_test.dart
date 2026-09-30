import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';

void main() {
  late Directory temp;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('ob5-samples-');
    await databaseFactory.setDatabasesPath(temp.path);
    LocalDb.dbName = 'test.db';
  });
  tearDown(() async {
    await LocalDb.close();
    await temp.delete(recursive: true);
  });
  test('bounded duplicate cleanup resumes, preserves orphans and served reads', () async {
    final db = await LocalDb.instance;
    for (var i = 1; i <= 5; i++) {
      await db.insert('samples', {'device_id': '', 'ts_ms': i * 1000,
        'ts': i, 'counter': i, 'hr': 50 + i});
      if (i != 3) {
        await db.insert('decoded_onehz', {'ts_ms': i * 1000, 'rec_ts': i,
          'counter': i, 'hr': 50 + i});
      }
    }
    final before = (await LocalDb.samplesInRange(1, 5)).map((s) => s.toDbMap()).toList();
    final orphan = (await LocalDb.samplesInRange(3, 3)).single.toDbMap();
    final latest = (await LocalDb.latestSample())!.toDbMap();
    expect(await LocalDb.pruneDuplicateSamples(batchSize: 2), 2);
    await LocalDb.close();
    expect(await LocalDb.pruneDuplicateSamples(batchSize: 2), 1);
    expect(await LocalDb.pruneDuplicateSamples(batchSize: 2), 1);
    expect(await LocalDb.pruneDuplicateSamples(batchSize: 2), 0);
    expect((await (await LocalDb.instance).query('samples')).single['ts'], 3);
    expect((await LocalDb.samplesInRange(1, 5)).map((s) => s.toDbMap()).toList(), before);
    expect((await LocalDb.samplesInRange(3, 3)).single.toDbMap(), orphan);
    expect((await LocalDb.latestSample())!.toDbMap(), latest);
  });
  test('excluded decoded sources and mismatched seconds cannot erase fallback', () async {
    final db = await LocalDb.instance;
    for (var i = 1; i <= 2; i++) {
      await db.insert('samples', {'device_id': 'other', 'ts_ms': i * 1000,
        'ts': i, 'counter': i, 'hr': 60});
      await db.insert('decoded_onehz', {'device_id': 'other', 'ts_ms': i * 1000,
        'rec_ts': i == 1 ? i : 20, 'counter': i, 'hr': 60,
        'source': i == 1 ? 'external' : null});
    }
    final before = (await LocalDb.samplesInRange(1, 2)).map((s) => s.toDbMap()).toList();
    expect(await LocalDb.pruneDuplicateSamples(), 0);
    expect((await db.query('samples')).length, 2);
    expect((await LocalDb.samplesInRange(1, 2)).map((s) => s.toDbMap()).toList(), before);
  });
}
