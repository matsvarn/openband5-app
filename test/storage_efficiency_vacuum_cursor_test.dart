import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temp;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('ob5-vacuum-cursor-');
    await databaseFactory.setDatabasesPath(temp.path);
    LocalDb.dbName = 'test.db';
    final db = await LocalDb.instance;
    for (var i = 1; i <= 5; i++) {
      await db.insert('decoded_onehz', {
        'rowid': i * 100,
        'ts_ms': i * 1000,
        'rec_ts': i,
        'counter': i,
        'ax': -0.1234,
        'ay': null,
        'az': 1.0001,
        'temp_ch2_c': 32.1234,
        'temp_ch3_c': null,
        'dyn_accel_g': 0.1234,
      });
      await db.insert('samples', {
        'rowid': i * 100,
        'ts_ms': (i + 10) * 1000,
        'ts': i + 10,
        'hr': 60,
      });
    }
  });
  tearDown(() async {
    await LocalDb.close();
    await temp.delete(recursive: true);
  });
  Future<Map<String, dynamic>> state(String key) async =>
      jsonDecode(
            (await LocalDb.computeFreshness(key))!['payload_json'] as String,
          )
          as Map<String, dynamic>;

  for (final requested in [false, true]) {
    test('vacuum via ${requested ? 'request' : 'freelist threshold'} resets '
        'unfinished rowid walks and conversion finishes', () async {
      expect(await LocalDb.compactLegacyOneHz(batchSize: 2, maxBatches: 1), 2);
      await LocalDb.pruneDuplicateSamples(batchSize: 2);
      expect((await state(LocalDb.kOneHzCompactCursorKey))['cursor'], 200);
      expect((await state(LocalDb.kSamplePruneCursorKey))['cursor'], 200);
      if (requested) {
        await LocalDb.putComputeFreshness(
          LocalDb.kOneHzVacuumKey,
          '{"requested":true}',
        );
      }
      await LocalDb.vacuumIfBloated(minFreeBytes: requested ? 1 << 50 : 0);
      expect((await state(LocalDb.kOneHzCompactCursorKey))['cursor'], 0);
      expect((await state(LocalDb.kOneHzCompactCursorKey))['done'], isFalse);
      expect((await state(LocalDb.kSamplePruneCursorKey))['cursor'], 0);
      await LocalDb.close(); // Reset progress must survive another launch.
      expect(await LocalDb.compactLegacyOneHz(batchSize: 2), 3);
      final db = await LocalDb.instance;
      expect((await db.query('samples')).length, 5);
      expect(
        (await db.rawQuery(
          'SELECT COUNT(*) AS n FROM decoded_onehz '
          'WHERE onehz_enc IS NULL',
        )).single['n'],
        0,
      );
      expect((await state(LocalDb.kOneHzCompactCursorKey))['done'], isTrue);
    });
  }

  test(
    'vacuum preserves completed compaction and does not request another walk',
    () async {
      expect(await LocalDb.compactLegacyOneHz(), 5);
      final completed = await state(LocalDb.kOneHzCompactCursorKey);
      await LocalDb.vacuumIfBloated();
      expect(await state(LocalDb.kOneHzCompactCursorKey), completed);
      expect(await LocalDb.compactLegacyOneHz(), 0);
      expect(await LocalDb.computeFreshness(LocalDb.kOneHzVacuumKey), isNull);
    },
  );
}
