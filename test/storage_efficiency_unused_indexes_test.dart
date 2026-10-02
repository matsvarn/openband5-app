import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';

void main() {
  late Directory temp;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('ob5-index-retire-');
    await databaseFactory.setDatabasesPath(temp.path);
    LocalDb.dbName = 'test.db';
  });
  tearDown(() async {
    await LocalDb.close();
    await temp.delete(recursive: true);
  });
  Future<void> verify(Database db) async {
    final names = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    )).map((r) => r['name']).toSet();
    expect(names, isNot(contains('idx_day_result_day')));
    expect(names, isNot(contains('idx_raw_blob_ts')));
    expect(names, contains('idx_raw_archive_captured'));
    final queries = <String, List<Object?>>{
      'SELECT * FROM day_result WHERE day_id = ? AND algo_version <= ? '
          'ORDER BY algo_version DESC LIMIT 1': [
        '2026-01-01',
        98,
      ],
      'SELECT * FROM raw_blob WHERE device_id = ? AND last_counter > ? '
          'ORDER BY first_counter ASC LIMIT 50': [
        '',
        0,
      ],
    };
    for (final query in queries.entries) {
      final plan = (await db.rawQuery(
        'EXPLAIN QUERY PLAN ${query.key}',
        query.value,
      )).map((r) => r['detail']).join(' ').toUpperCase();
      expect(plan, contains('SEARCH'));
      expect(plan, contains('SQLITE_AUTOINDEX'));
      expect(plan, isNot(contains('TEMP B-TREE')));
    }
    final retainedPlan = (await db.rawQuery(
      'EXPLAIN QUERY PLAN DELETE FROM raw_archive '
      'WHERE reason = ? AND captured_at < ? AND counter % ? != 0',
      ['undecodable_rec_v20', 1000, 60],
    )).map((r) => r['detail']).join(' ').toUpperCase();
    expect(retainedPlan, contains('IDX_RAW_ARCHIVE_CAPTURED'));
  }

  test(
    'fresh creators omit unused indexes and PKs serve the existing reads',
    () async {
      await verify(await LocalDb.instance);
    },
  );
  for (final version in [68, 69]) {
    test(
      'schema $version open retires old indexes without changing stored rows',
      () async {
        final db = await LocalDb.instance;
        await db.execute(
          'CREATE INDEX idx_day_result_day ON day_result(day_id, algo_version)',
        );
        await db.execute(
          'CREATE INDEX idx_raw_blob_ts ON raw_blob(device_id, first_ts)',
        );
        await db.insert('day_result', {
          'day_id': '2026-01-01',
          'algo_version': 98,
          'payload_json': '{}',
          'computed_at': 0,
        });
        await db.insert('raw_blob', {
          'device_id': '',
          'first_counter': 1,
          'last_counter': 2,
          'first_ts': 10,
          'last_ts': 20,
          'n': 2,
          'codec': 1,
          'payload': Uint8List.fromList([1, 2]),
          'captured_at': 0,
        });
        final beforeDay = await db.query('day_result');
        final beforeBlob = await db.query('raw_blob');
        await db.setVersion(version);
        await LocalDb.close();
        final reopened = await LocalDb.instance;
        await verify(reopened);
        expect(await reopened.query('day_result'), beforeDay);
        expect(await reopened.query('raw_blob'), beforeBlob);
        await LocalDb.close();
        await verify(await LocalDb.instance);
      },
    );
  }
}
