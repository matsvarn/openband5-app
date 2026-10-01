// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/derive_fixture.dart';
import 'support/derive_idempotence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('clock masking preserves all other JSON bytes and nested stamps', () {
    const input =
        '{ "built_at_epoch":123, "source_rev":7, '
        '"nested":{"built_at_epoch":456}, "value":1.00 }';
    expect(
      maskRootClocks(input, {'built_at_epoch'}),
      '{ "built_at_epoch":0, "source_rev":7, '
      '"nested":{"built_at_epoch":456}, "value":1.00 }',
    );
  });
  test(
    'comparison refuses equal JSON values with different persisted bytes',
    () {
      PersistedSnapshot snapshot(String payload) => PersistedSnapshot({
        'day_result': PersistedTable(1, digest(payload), {
          '["synthetic-day",98]': {'payload_json': payload},
        }),
      });
      final result = compareSnapshots(
        snapshot('{"value":1}'),
        snapshot('{ "value":1 }'),
      ).single;
      expect(result.differing, 1);
      expect(result.paths.single, contains('payload_json (bytes)'));
    },
  );
  test(
    'full and light production derivation preserve persisted results',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'ob5-derive-idempotence-',
      );
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath('file:${dir.path}');
      LocalDb.dbName = 'openstrap.db';
      SharedPreferences.setMockInitialValues({});
      await initializeDateFormatting('de_DE');
      final differences = <String>[];
      try {
        final db = await LocalDb.instance;
        await seedDeriveFixture(db);
        await completeStorageHousekeeping();
        final engine = DerivationEngine(log: (_) {});
        Future<void> run({required bool full}) async {
          final done = await engine.run(
            idempotenceProfile,
            heavy: full,
            force: full,
          );
          expect(
            done,
            greaterThan(0),
            reason: 'Must recompute, not compare two no-ops',
          );
          expect(engine.snapshot()['skipped_days'], 0);
          expect(engine.snapshot()['last_error'], isNull);
          if (full) expect(done, fixtureDays.length);
        }

        Future<void> compare(String mode, PersistedSnapshot before) async {
          final after = await PersistedSnapshot.capture(db);
          for (final result in compareSnapshots(before, after)) {
            print('$mode ${result.report}');
            if (result.differing != 0) {
              differences.add('$mode ${result.report}');
            }
          }
        }

        await run(full: true);
        final nonNull = await db.rawQuery(r'''
        SELECT COUNT(*) AS n FROM day_result WHERE day_id IN (?, ?, ?)
        AND skipped=0 AND partial=0 AND readiness IS NOT NULL AND rmssd IS NOT NULL
        AND json_extract(payload_json, '$.scalars.strain') IS NOT NULL
        AND json_extract(payload_json, '$.sleep.accounting.value.tst_sec') > 0
      ''', fixtureDays);
        expect(
          nonNull.single['n'],
          greaterThan(0),
          reason:
              'One production-derived day must have readiness, HRV, strain and sleep',
        );
        final full = await PersistedSnapshot.capture(db);
        await run(full: true);
        await compare('full', full);
        await run(full: false);
        expect(engine.snapshot()['mode'], 'light');
        final light = await PersistedSnapshot.capture(db);
        await run(full: false);
        expect(engine.snapshot()['mode'], 'light');
        await compare('light', light);
        expect(differences, isEmpty, reason: differences.join('\n'));
      } finally {
        await LocalDb.close();
        dir.deleteSync(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
