import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';

void main() {
  late Directory temp;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('ob5-event-index-');
    await databaseFactory.setDatabasesPath(temp.path);
    LocalDb.dbName = 'test.db';
  });
  tearDown(() async {
    await LocalDb.close();
    await temp.delete(recursive: true);
  });

  Future<void> verifyPlans(Database db) async {
    for (final query in [
      'SELECT ts, event_id FROM band_events WHERE device_id = ? AND ts < ? '
          'AND event_id IN (?, ?) ORDER BY ts DESC LIMIT 1',
      'SELECT ts, event_id FROM band_events WHERE device_id = ? AND ts >= ? '
          'AND ts < ? AND event_id IN (?, ?) ORDER BY ts ASC',
    ]) {
      final args = query.contains('ts >=')
          ? <Object?>['', 5, 20, 1, 2]
          : <Object?>['', 20, 1, 2];
      final plan = (await db.rawQuery(
        'EXPLAIN QUERY PLAN $query',
        args,
      )).map((r) => r['detail']).join(' ').toUpperCase();
      expect(plan, contains('IDX_BAND_EVENTS_DEVICE_TS'));
      expect(plan, contains('SEARCH'));
      expect(plan, isNot(contains('TEMP B-TREE')));
    }
  }

  test(
    'fresh band-event lookups seek by device and time without a sort',
    () async {
      final db = await LocalDb.instance;
      for (final device in ['', 'other']) {
        for (var i = 1; i <= 30; i++) {
          await db.insert('band_events', {
            'device_id': device,
            'hex': '$i',
            'ts': i,
            'event_id': i.isEven ? 1 : 2,
            'name': 'test',
            'captured_at': i,
          });
        }
      }
      await verifyPlans(db);
      expect(
        (await db.rawQuery(
          'SELECT ts FROM band_events WHERE device_id = ? AND ts < ? '
          'AND event_id IN (?, ?) ORDER BY ts DESC LIMIT 1',
          ['', 20, 1, 2],
        )).single['ts'],
        19,
      );
    },
  );

  for (final version in [68, 69]) {
    test(
      'schema $version open repairs the band-event index idempotently',
      () async {
        final db = await LocalDb.instance;
        await db.execute('DROP INDEX idx_band_events_device_ts');
        await db.setVersion(version);
        await LocalDb.close();
        await verifyPlans(await LocalDb.instance);
        await LocalDb.close();
        await verifyPlans(await LocalDb.instance);
      },
    );
  }
}
