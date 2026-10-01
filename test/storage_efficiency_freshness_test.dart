import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqflite_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';

void main() {
  late Directory temp;
  final sql = <String>[];
  setUp(() async {
    sqfliteFfiInit();
    // Test-only SQL tracing uses sqflite's experimental logger API.
    // ignore: experimental_member_use
    databaseFactory = SqfliteDatabaseFactoryLogger(
      databaseFactoryFfi,
      options: SqfliteLoggerOptions(
        log: (event) {
          if (event is SqfliteLoggerSqlEvent) sql.add(event.sql);
        },
      ),
    );
    temp = await Directory.systemTemp.createTemp('ob5-freshness-');
    await databaseFactoryFfi.setDatabasesPath(temp.path);
    LocalDb.dbName = 'test.db';
    await LocalDb.instance;
    sql.clear();
  });
  tearDown(() async {
    await LocalDb.close();
    await temp.delete(recursive: true);
  });
  Future<Map<String, dynamic>> payload(String key) async =>
      jsonDecode(
            (await LocalDb.computeFreshness(key))!['payload_json'] as String,
          )
          as Map<String, dynamic>;

  test(
    'freshness states and capture edge need no count or source filter',
    () async {
      await LocalDb.refreshComputeFreshness();
      expect((await payload('today'))['activity_state'], 'missing');
      expect((await payload('today'))['overnight_state'], 'missing');
      expect((await payload('capture'))['latest_raw_rec_ts'], isNull);
      final db = await LocalDb.instance;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.insert('decoded_onehz', {
        'device_id': 'external',
        'ts_ms': now * 1000,
        'rec_ts': now,
        'counter': 1,
        'source': 'external',
      });
      await db.insert('decoded_onehz', {'ts_ms': 0, 'rec_ts': 0, 'counter': 2});
      sql.clear();
      await LocalDb.refreshComputeFreshness();
      final capture = await payload('capture');
      expect(capture, {
        'latest_raw_rec_ts': now,
        'latest_raw_day': dayLabelOf(
          DateTime.fromMillisecondsSinceEpoch(now * 1000),
        ),
      });
      expect((await payload('today'))['activity_state'], 'building');
      expect((await payload('today'))['overnight_state'], 'building');
      await LocalDb.putDayResult(
        dayId: dayLabelOf(DateTime.now()),
        algoVersion: 98,
        payloadJson: '{"flags":["NO_SLEEP_DETECTED"],"scalars":{}}',
        windowJson: '{}',
        finalized: false,
      );
      await LocalDb.refreshComputeFreshness();
      expect((await payload('today'))['activity_state'], 'ready');
      expect((await payload('today'))['overnight_state'], 'ready');
      expect(
        sql.where(
          (s) => RegExp(r'COUNT\s*\(', caseSensitive: false).hasMatch(s),
        ),
        isEmpty,
      );
      expect(
        sql.where((s) => s.contains('MAX(rec_ts) FROM decoded_onehz')),
        isNotEmpty,
      );
    },
  );
}
