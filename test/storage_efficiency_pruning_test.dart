import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';

void main() {
  late Directory temp;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('ob5-prune-');
    await databaseFactory.setDatabasesPath(temp.path);
    LocalDb.dbName = 'test.db';
  });
  tearDown(() async {
    await LocalDb.close();
    await temp.delete(recursive: true);
  });

  test(
    'runDays prunes intermediates even with retained original inputs',
    () async {
      expect(LocalDb.retainOriginalSourceByDefault, isTrue);
      final db = await LocalDb.instance;
      for (final table in ['sleep_session_candidates', 'wake_day_features']) {
        for (final day in ['2026-01-01', '2026-01-02']) {
          for (final version in [95, 96, 97, kAlgoVersion, 99, 100]) {
            await db.insert(table, {
              'day_id': day,
              'algo_version': version,
              'payload_json': '{}',
              'computed_at': 0,
            });
          }
        }
      }
      await DerivationEngine().runDays(const PersonalProfile(), {'2026-01-01'});
      for (final table in ['sleep_session_candidates', 'wake_day_features']) {
        for (final day in ['2026-01-01', '2026-01-02']) {
          expect(
            (await db.query(
              table,
              columns: ['algo_version'],
              where: 'day_id = ?',
              whereArgs: [day],
              orderBy: 'algo_version',
            )).map((r) => r['algo_version']),
            [97, kAlgoVersion, 99, 100],
          );
        }
      }
    },
  );

  test(
    'day result policy is bounded, idempotent and preserves served rows',
    () async {
      final db = await LocalDb.instance;
      for (final day in ['2026-01-01', '2026-01-02']) {
        for (final version in [90, 91, 92, 96, 97, 98, 99]) {
          await db.insert('day_result', {
            'day_id': day,
            'algo_version': version,
            'payload_json': '{}',
            'computed_at': 0,
            'skipped': version == 98 ? 1 : 0,
            'partial': version == 97 || version == 96 ? 1 : 0,
          });
        }
      }
      final before = await LocalDb.dayResult('2026-01-01');
      expect(await LocalDb.pruneSupersededDayResults(limit: 1), 1);
      expect(await LocalDb.pruneSupersededDayResults(), 5);
      for (final day in ['2026-01-01', '2026-01-02']) {
        expect(
          (await db.query(
            'day_result',
            columns: ['algo_version'],
            where: 'day_id = ?',
            whereArgs: [day],
            orderBy: 'algo_version',
          )).map((r) => r['algo_version']),
          [92, 97, 98, 99],
        );
      }
      expect(await LocalDb.dayResult('2026-01-01'), before);
      expect(await LocalDb.pruneSupersededDayResults(), 0);
    },
  );
}
