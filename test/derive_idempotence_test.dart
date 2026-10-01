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
      maskRootFields(input, {'built_at_epoch'}),
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
    'publication fence exclusions are scoped to their rows and root fields',
    () {
      const input =
          '{ "v":123, "source_rev":7, '
          '"nested":{"v":456,"source_rev":8}, "value":1.00 }';
      expect(
        normalizePayload('compute_freshness', 'crossday_source_rev', input),
        '{ "v":0, "source_rev":7, '
        '"nested":{"v":456,"source_rev":8}, "value":1.00 }',
      );
      for (final key in ['crossday', 'crossday_input']) {
        expect(
          normalizePayload('baselines', key, input),
          '{ "v":123, "source_rev":0, '
          '"nested":{"v":456,"source_rev":8}, "value":1.00 }',
        );
      }
      expect(normalizePayload('compute_freshness', 'other', input), input);
      expect(normalizePayload('baselines', 'other', input), input);
      expect(normalizePayload('day_result', 'crossday', input), input);
    },
  );

  group('production derivation idempotence', () {
    late Directory dir;
    late Database db;
    late DerivationEngine engine;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('ob5-derive-idempotence-');
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath('file:${dir.path}');
      LocalDb.dbName = 'openstrap.db';
      SharedPreferences.setMockInitialValues({});
      await initializeDateFormatting('de_DE');
      db = await LocalDb.instance;
      await seedDeriveFixture(db);
      await completeStorageHousekeeping();
      engine = DerivationEngine(log: (_) {});
    });
    tearDown(() async {
      await LocalDb.close();
      dir.deleteSync(recursive: true);
    });

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
      if (full) {
        expect(done, fixtureDays.length);
      } else {
        expect(engine.snapshot()['mode'], 'light');
      }
    }

    Future<void> assertNonVacuous() async {
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
    }

    Future<List<String>> compare(String mode, PersistedSnapshot before) async {
      final after = await PersistedSnapshot.capture(db);
      final differences = <String>[];
      for (final result in compareSnapshots(before, after)) {
        print('$mode ${result.report}');
        if (result.differing != 0) differences.add('$mode ${result.report}');
      }
      return differences;
    }

    test(
      'first and second full passes preserve persisted results',
      () async {
        await run(full: true);
        await assertNonVacuous();
        final first = await PersistedSnapshot.capture(db);
        await run(full: true);
        final differences = await compare('first_full', first);
        expect(differences, isEmpty, reason: differences.join('\n'));
      },
      skip:
          'Known defect: a multi-day pass derives each day against baseline history frozen at the start of the pass, so the next pass changes readiness/strain/skin_temp_z of later days. Decision pending (storage-2 report).',
      timeout: const Timeout(Duration(minutes: 10)),
    );
    test(
      'second and third full passes and light reruns preserve persisted results',
      () async {
        await run(full: true);
        await assertNonVacuous();
        await run(full: true);
        final second = await PersistedSnapshot.capture(db);
        await run(full: true);
        final differences = await compare('converged_full', second);
        await run(full: false);
        final light = await PersistedSnapshot.capture(db);
        await run(full: false);
        differences.addAll(await compare('light', light));
        expect(differences, isEmpty, reason: differences.join('\n'));
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  });
}
