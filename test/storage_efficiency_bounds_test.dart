import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';

void main() {
  late Directory temp;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('ob5-bounds-');
    await databaseFactory.setDatabasesPath(temp.path);
    LocalDb.dbName = 'test.db';
  });
  tearDown(() async {
    await LocalDb.close();
    await temp.delete(recursive: true);
  });

  test('empty decoded spans stay null', () async {
    expect(await LocalDb.firstAndLastRecordTs(), (null, null));
    final stats = await LocalDb.rawStats();
    expect(stats['min_rec_ts'], isNull);
    expect(stats['max_rec_ts'], isNull);
    expect(await LocalDb.dataHistoryDays(), isEmpty);
  });

  test('ordered bounds match aggregates with absent and excluded edges', () async {
    final db = await LocalDb.instance;
    final start = DateTime(2026, 3, 29).millisecondsSinceEpoch ~/ 1000;
    final stamps = [
      null,
      0,
      start - 1,
      start,
      start + 100,
      start + 82800,
      start + 82801,
    ];
    for (var i = 0; i < stamps.length; i++) {
      await db.insert('decoded_onehz', {
        'device_id': '',
        'ts_ms': i * 1000,
        'rec_ts': stamps[i],
        'counter': i,
        'source': i == 2 || i == 6 ? 'excluded' : null,
      });
    }
    Future<(int?, int?)> aggregate(String predicate) async {
      final row = (await db.rawQuery(
        'SELECT MIN(rec_ts) lo, MAX(rec_ts) hi '
        'FROM decoded_onehz WHERE $predicate',
      )).single;
      return ((row['lo'] as num?)?.toInt(), (row['hi'] as num?)?.toInt());
    }

    expect(
      await LocalDb.firstAndLastRecordTs(),
      await aggregate('rec_ts > 0 AND ${derivableSourceSql()}'),
    );
    final (lo, hi) = await aggregate('rec_ts > 0');
    final stats = await LocalDb.rawStats();
    expect((stats['min_rec_ts'], stats['max_rec_ts']), (lo, hi));
    final oldDays = await db.rawQuery(
      "SELECT strftime('%Y-%m-%d', rec_ts, 'unixepoch', 'localtime') day_id, "
      'COUNT(*) raw_count, MIN(rec_ts) min_rec_ts, MAX(rec_ts) max_rec_ts '
      'FROM decoded_onehz WHERE rec_ts > 0 AND ${derivableSourceSql()} GROUP BY day_id ORDER BY day_id DESC',
    );
    final days = await LocalDb.dataHistoryDays();
    expect([
      for (final r in days) {for (final key in oldDays.first.keys) key: r[key]},
    ], oldDays);
    for (final direction in ['ASC', 'DESC']) {
      final plan = (await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT rec_ts FROM decoded_onehz '
        'WHERE rec_ts > 0 AND ${derivableSourceSql()} ORDER BY rec_ts $direction LIMIT 1',
      )).map((r) => r['detail']).join(' ').toUpperCase();
      expect(plan, contains('IDX_DECODED_ONEHZ_RECTS'));
      expect(plan, contains('SEARCH'));
      expect(plan, isNot(contains('TEMP B-TREE')));
    }
  });

  test(
    'only invalid timestamps or excluded sources have no admitted span',
    () async {
      final db = await LocalDb.instance;
      for (var i = 0; i < 3; i++) {
        await db.insert('decoded_onehz', {
          'ts_ms': i * 1000,
          'rec_ts': i == 0 ? null : i - 1,
          'counter': i,
          'source': i == 2 ? 'excluded' : null,
        });
      }
      expect(await LocalDb.firstAndLastRecordTs(), (null, null));
    },
  );
}
