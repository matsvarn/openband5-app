import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/health/glucose_contract.dart';
import 'package:openstrap_edge/health/health_measurement_import.dart';
import 'package:openstrap_edge/openband/glucose.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/profile/phone_import.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

HealthDataPoint _p(
  HealthDataType type,
  num value, {
  String uuid = 'u1',
  String source = 'Dexcom',
  String sourceId = 'com.dexcom.G7',
  HealthDataUnit? unit,
  DateTime? at,
}) {
  final when = at ?? DateTime(2026, 9, 15, 8);
  return HealthDataPoint(
    uuid: uuid,
    value: NumericHealthValue(numericValue: value),
    type: type,
    unit:
        unit ??
        (type == HealthDataType.BLOOD_GLUCOSE
            ? HealthDataUnit.MILLIGRAM_PER_DECILITER
            : HealthDataUnit.MILLIMETER_OF_MERCURY),
    dateFrom: when,
    dateTo: when,
    sourceId: sourceId,
    sourcePlatform: HealthPlatformType.appleHealth,
    sourceDeviceId: 'dev',
    sourceName: source,
  );
}

class _FakeHealth implements Health {
  _FakeHealth({
    this.points = const [],
    this.has,
    this.requestOk = true,
    this.readThrows = false,
    this.delay,
  });

  List<HealthDataPoint> points;
  bool? has;
  bool requestOk;
  bool readThrows;
  Completer<void>? delay;
  final List<List<HealthDataType>> requested = [];
  final List<(DateTime, DateTime)> windows = [];

  @override
  Future<void> configure() async {}

  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async => has;

  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async => requestOk;

  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
    List<RecordingMethod> recordingMethodsToFilter = const [],
  }) async {
    requested.add(List.of(types));
    windows.add((startTime, endTime));
    final snapshot = List<HealthDataPoint>.of(points);
    final wait = delay;
    if (wait != null) await wait.future;
    if (readThrows) throw StateError('read');
    return snapshot;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final created = <String>[];

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await LocalDb.close();
    for (final n in created) {
      await databaseFactory.deleteDatabase(await _dbPath(n));
    }
  });

  Future<void> openDb(String name) async {
    created.add(name);
    await LocalDb.close();
    LocalDb.dbName = name;
    await databaseFactory.deleteDatabase(await _dbPath(name));
  }

  test(
    'sqlite round-trip keeps uuid, clocks, unit and source identity',
    () async {
      await openDb('glucose_roundtrip.db');
      final now = DateTime(2026, 9, 15, 9, 40);
      final n = await LocalDb.putImportedMeasurements([
        {
          'uuid': 'g1',
          'ts': DateTime(2026, 9, 15, 8).millisecondsSinceEpoch ~/ 1000,
          'kind': kKindGlucose,
          'value': 95.0,
          'unit': kGlucoseUnitMilligramPerDeciliter,
          'source': 'Dexcom',
          'source_id': 'com.dexcom.G7',
          'source_key': 'apple:com.dexcom.G7',
        },
      ], now: now);
      expect(n, 1);
      final rows = await LocalDb.importedMeasurements(kKindGlucose);
      expect(rows, hasLength(1));
      expect(rows.single['uuid'], 'g1');
      expect(rows.single['value'], 95.0);
      expect(rows.single['unit'], kGlucoseUnitMilligramPerDeciliter);
      expect(rows.single['source'], 'Dexcom');
      expect(rows.single['source_id'], 'com.dexcom.G7');
      expect(rows.single['source_key'], 'apple:com.dexcom.G7');
      expect(rows.single['imported_at'], now.millisecondsSinceEpoch ~/ 1000);
    },
  );

  test(
    'schema 63 upgrades to 64 twice without fabricating imported_at',
    () async {
      const name = 'glucose_from_63.db';
      created.add(name);
      final path = await _dbPath(name);
      await databaseFactory.deleteDatabase(path);
      final old = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 63,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE imported_measurement (
              uuid TEXT PRIMARY KEY,
              ts INTEGER NOT NULL,
              kind TEXT NOT NULL,
              value REAL NOT NULL,
              unit TEXT NOT NULL,
              source TEXT NOT NULL
            )
          ''');
            await db.insert('imported_measurement', {
              'uuid': 'legacy-g',
              'ts': 1780000000,
              'kind': kKindGlucose,
              'value': 95.0,
              'unit': kGlucoseUnitMilligramPerDeciliter,
              'source': 'Dexcom',
            });
          },
        ),
      );
      await old.close();

      Future<void> reopenAndCheck() async {
        await LocalDb.close();
        LocalDb.dbName = name;
        final db = await LocalDb.instance;
        expect(LocalDb.schemaVersion, 64);
        expect(
          (await db.rawQuery('PRAGMA user_version')).first.values.first,
          64,
        );
        final cols = {
          for (final c in await db.rawQuery(
            'PRAGMA table_info(imported_measurement)',
          ))
            c['name'] as String,
        };
        expect(cols, containsAll(['imported_at', 'source_id', 'source_key']));
        expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='imported_measurement_receipt'",
          ),
          isNotEmpty,
        );
        expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='imported_measurement_source_setting'",
          ),
          isNotEmpty,
        );
        final row = (await db.query('imported_measurement')).single;
        expect(row['uuid'], 'legacy-g');
        expect(row['source'], 'Dexcom');
        expect(row['imported_at'], isNull);
        expect(row['source_id'], isNull);
        expect(row['source_key'], isNull);
      }

      await reopenAndCheck();
      await reopenAndCheck();
    },
  );

  test('legacy name-only rows stay distinct from a known-id source', () async {
    await openDb('glucose_collision.db');
    await LocalDb.putImportedMeasurements([
      {
        'uuid': 'legacy',
        'ts': 1,
        'kind': kKindGlucose,
        'value': 90.0,
        'unit': kGlucoseUnitMilligramPerDeciliter,
        'source': 'Dexcom',
      },
      {
        'uuid': 'known',
        'ts': 2,
        'kind': kKindGlucose,
        'value': 100.0,
        'unit': kGlucoseUnitMilligramPerDeciliter,
        'source': 'Dexcom',
        'source_id': 'com.dexcom.G7',
        'source_key': 'apple:com.dexcom.G7',
      },
    ]);
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final snap = await LocalOpenBandRepository(app).readGlucose();
    expect(snap.sources.map((s) => s.source.key).toSet(), {
      'apple:com.dexcom.G7',
      'legacy:Dexcom',
    });
    await LocalDb.setImportedMeasurementSourceExcluded(
      kind: kKindGlucose,
      sourceKey: 'apple:com.dexcom.G7',
      excluded: true,
    );
    final hidden = await LocalOpenBandRepository(
      app,
    ).readGlucose(sourceKey: 'legacy:Dexcom');
    expect(hidden.history.single.uuid, 'legacy');
    expect(hidden.selectedExcluded, isFalse);
    final known = await LocalOpenBandRepository(
      app,
    ).readGlucose(sourceKey: 'apple:com.dexcom.G7');
    expect(known.selectedExcluded, isTrue);
    expect(known.history.single.uuid, 'known');
    expect(known.series, isEmpty);
  });

  test(
    'unchanged reread keeps imported_at; a change stamps replacement',
    () async {
      await openDb('glucose_dup.db');
      final first = DateTime(2026, 9, 15, 9, 40);
      final later = DateTime(2026, 9, 15, 10, 0);
      final row = {
        'uuid': 'g1',
        'ts': 100,
        'kind': kKindGlucose,
        'value': 95.0,
        'unit': kGlucoseUnitMilligramPerDeciliter,
        'source': 'Dexcom',
        'source_id': 'com.dexcom.G7',
        'source_key': 'apple:com.dexcom.G7',
      };
      await LocalDb.putImportedMeasurements([row], now: first);
      await LocalDb.putImportedMeasurements([row], now: later);
      var stored = (await LocalDb.importedMeasurements(kKindGlucose)).single;
      expect(stored['imported_at'], first.millisecondsSinceEpoch ~/ 1000);
      await LocalDb.putImportedMeasurements([
        {...row, 'value': 110.0},
      ], now: later);
      stored = (await LocalDb.importedMeasurements(kKindGlucose)).single;
      expect(stored['value'], 110.0);
      expect(stored['imported_at'], later.millisecondsSinceEpoch ~/ 1000);
    },
  );

  test(
    'mixed units follow newest known unit; newest unknown withholds plot',
    () async {
      await openDb('glucose_units.db');
      await LocalDb.putImportedMeasurements([
        {
          'uuid': 'mg',
          'ts': 2,
          'kind': kKindGlucose,
          'value': 95.0,
          'unit': kGlucoseUnitMilligramPerDeciliter,
          'source': 'Dexcom',
          'source_key': 'apple:com.dexcom.G7',
        },
        {
          'uuid': 'mmol',
          'ts': 3,
          'kind': kKindGlucose,
          'value': 5.2,
          'unit': kGlucoseUnitMillimolePerLiter,
          'source': 'Dexcom',
          'source_key': 'apple:com.dexcom.G7',
        },
        {
          'uuid': 'older-unknown',
          'ts': 1,
          'kind': kKindGlucose,
          'value': 5.2,
          'unit': 'stones',
          'source': 'Dexcom',
          'source_key': 'apple:com.dexcom.G7',
        },
      ]);
      SharedPreferences.setMockInitialValues({});
      Prefs.debugReset();
      await Prefs.ensureLoaded();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final repo = LocalOpenBandRepository(app);
      final newestMmol = await repo.readGlucose();
      expect(newestMmol.history, hasLength(3));
      expect(newestMmol.series.single.uuid, 'mmol');
      expect(
        newestMmol.series.single.unitKind,
        GlucoseUnitKind.millimolePerLiter,
      );

      await LocalDb.putImportedMeasurements([
        {
          'uuid': 'newest-unknown',
          'ts': 4,
          'kind': kKindGlucose,
          'value': 5.2,
          'unit': 'stones',
          'source': 'Dexcom',
          'source_key': 'apple:com.dexcom.G7',
        },
      ]);
      final newestUnknown = await repo.readGlucose();
      expect(newestUnknown.history, hasLength(4));
      expect(
        newestUnknown.history
            .firstWhere((r) => r.uuid == 'newest-unknown')
            .unitKind,
        GlucoseUnitKind.unknown,
      );
      expect(newestUnknown.series, isEmpty);
    },
  );

  test('empty and thrown reads leave stored rows', () async {
    await openDb('glucose_empty_throw.db');
    await LocalDb.putImportedMeasurements([
      {
        'uuid': 'keep',
        'ts': 1,
        'kind': kKindGlucose,
        'value': 95.0,
        'unit': kGlucoseUnitMilligramPerDeciliter,
        'source': 'Dexcom',
        'source_key': 'apple:com.dexcom.G7',
      },
    ], now: DateTime(2026, 9, 15, 8));
    final emptyHealth = _FakeHealth(points: const [], has: true);
    final empty =
        await ImportedMeasurementImporter(
          health: emptyHealth,
          isApple: true,
        ).sync(
          types: ImportedMeasurementImporter.glucoseOnly,
          now: DateTime(2026, 9, 15, 10),
        );
    expect(empty.status, HealthMeasurementImportStatus.empty);
    expect(await LocalDb.importedMeasurements(kKindGlucose), hasLength(1));

    final thrown =
        await ImportedMeasurementImporter(
          health: _FakeHealth(has: true, readThrows: true),
          isApple: true,
        ).sync(
          types: ImportedMeasurementImporter.glucoseOnly,
          now: DateTime(2026, 9, 15, 10, 1),
        );
    expect(thrown.status, HealthMeasurementImportStatus.readFailed);
    expect(await LocalDb.importedMeasurements(kKindGlucose), hasLength(1));
    expect(
      (await LocalDb.importedMeasurementReceipt(kKindGlucose))!['outcome'],
      HealthMeasurementImportStatus.readFailed.name,
    );

    final retried =
        await ImportedMeasurementImporter(
          health: _FakeHealth(
            has: true,
            points: [_p(HealthDataType.BLOOD_GLUCOSE, 110, uuid: 'keep')],
          ),
          isApple: true,
        ).sync(
          types: ImportedMeasurementImporter.glucoseOnly,
          now: DateTime(2026, 9, 15, 10, 2),
        );
    expect(retried.status, HealthMeasurementImportStatus.stored);
    expect(
      (await LocalDb.importedMeasurements(kKindGlucose)).single['value'],
      110.0,
    );
  });

  test('iOS completed empty is not denied; Android false is denied', () async {
    await openDb('glucose_auth.db');
    final ios =
        await ImportedMeasurementImporter(
          health: _FakeHealth(has: null, requestOk: true, points: const []),
          isApple: true,
        ).sync(
          types: ImportedMeasurementImporter.glucoseOnly,
          now: DateTime(2026, 9, 15, 10),
        );
    expect(ios.status, HealthMeasurementImportStatus.empty);
    expect(
      ios.status,
      isNot(HealthMeasurementImportStatus.authorizationDenied),
    );

    final android =
        await ImportedMeasurementImporter(
          health: _FakeHealth(has: false, requestOk: false),
          isApple: false,
        ).sync(
          types: ImportedMeasurementImporter.glucoseOnly,
          now: DateTime(2026, 9, 15, 10),
        );
    expect(android.status, HealthMeasurementImportStatus.authorizationDenied);
  });

  test(
    'rejected glucose input is partial and does not drop siblings',
    () async {
      await openDb('glucose_partial.db');
      final health = _FakeHealth(
        has: true,
        points: [
          _p(HealthDataType.BLOOD_GLUCOSE, 95, uuid: 'ok'),
          _p(HealthDataType.BLOOD_GLUCOSE, double.nan, uuid: 'nan'),
          _p(HealthDataType.BLOOD_PRESSURE_SYSTOLIC, 120, uuid: 'bp'),
        ],
      );
      final four = await ImportedMeasurementImporter(
        health: health,
        isApple: true,
      ).sync(now: DateTime(2026, 9, 15, 10));
      expect(four.status, HealthMeasurementImportStatus.partial);
      expect(four.invalidCount, 1);
      expect(four.storedCount, 2);
      expect(await LocalDb.importedMeasurements(kKindGlucose), hasLength(1));
      expect(await LocalDb.importedMeasurements(kKindSystolic), hasLength(1));
      final glucose = await LocalDb.importedMeasurementReceipt(kKindGlucose);
      expect(glucose!['outcome'], HealthMeasurementImportStatus.partial.name);
      expect(glucose['stored_count'], 1);
      expect(glucose['invalid_count'], 1);
      final systolic = await LocalDb.importedMeasurementReceipt(kKindSystolic);
      expect(systolic!['outcome'], HealthMeasurementImportStatus.stored.name);
      expect(systolic['stored_count'], 1);
      expect(systolic['invalid_count'], 0);
    },
  );

  test('persistence failure does not claim saved rows', () async {
    await openDb('glucose_persist.db');
    final outcome =
        await ImportedMeasurementImporter(
          health: _FakeHealth(
            has: true,
            points: [_p(HealthDataType.BLOOD_GLUCOSE, 95)],
          ),
          isApple: true,
          commit: (input) async {
            if (input.persistRows) throw StateError('disk');
            return const ImportedMeasurementCommitResult(
              storedCount: 0,
              writtenCount: 0,
            );
          },
        ).sync(
          types: ImportedMeasurementImporter.glucoseOnly,
          now: DateTime(2026, 9, 15, 10),
        );
    expect(outcome.status, HealthMeasurementImportStatus.persistenceFailed);
    expect(outcome.writtenCount, 0);
    expect(await LocalDb.importedMeasurements(kKindGlucose), isEmpty);
  });

  test('two importer instances cannot rewind the same uuid', () async {
    await openDb('glucose_concurrent.db');
    final t0 = DateTime(2026, 9, 15, 10, 0, 0, 400);
    final sameSecond = DateTime(2026, 9, 15, 10, 0, 0, 900);
    final gate = Completer<void>();
    final slow = _FakeHealth(
      has: true,
      points: [_p(HealthDataType.BLOOD_GLUCOSE, 95, uuid: 'x')],
      delay: gate,
    );
    final fast = _FakeHealth(
      has: true,
      points: [_p(HealthDataType.BLOOD_GLUCOSE, 100, uuid: 'x')],
    );
    final first = ImportedMeasurementImporter(
      health: slow,
      isApple: true,
    ).sync(types: ImportedMeasurementImporter.glucoseOnly, now: t0);
    while (slow.requested.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final second = ImportedMeasurementImporter(
      health: fast,
      isApple: true,
    ).sync(types: ImportedMeasurementImporter.glucoseOnly, now: sameSecond);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(fast.requested, isEmpty);
    gate.complete();
    await Future.wait([first, second]);
    final row = (await LocalDb.importedMeasurements(kKindGlucose)).single;
    expect(row['uuid'], 'x');
    expect(row['value'], 100.0);
    final receipt = await LocalDb.importedMeasurementReceipt(kKindGlucose);
    expect(receipt!['last_attempt_at'], t0.millisecondsSinceEpoch ~/ 1000);
    expect(receipt['stored_count'], 1);
  });

  test('glucose-only query does not ask for other kinds', () async {
    await openDb('glucose_only.db');
    final health = _FakeHealth(has: true);
    await ImportedMeasurementImporter(health: health, isApple: true).sync(
      types: ImportedMeasurementImporter.glucoseOnly,
      now: DateTime(2026, 9, 15, 10),
    );
    expect(health.requested.single, [HealthDataType.BLOOD_GLUCOSE]);
  });

  test('legacy four-kind sync still reads the other types', () async {
    await openDb('glucose_four.db');
    final health = _FakeHealth(
      has: true,
      points: [
        _p(HealthDataType.BLOOD_PRESSURE_SYSTOLIC, 118, uuid: 's'),
        _p(HealthDataType.BLOOD_PRESSURE_DIASTOLIC, 76, uuid: 'd'),
        _p(
          HealthDataType.BODY_TEMPERATURE,
          36.8,
          uuid: 't',
          unit: HealthDataUnit.DEGREE_CELSIUS,
        ),
      ],
    );
    final out = await ImportedMeasurementImporter(
      health: health,
      isApple: true,
    ).sync(now: DateTime(2026, 9, 15, 10));
    expect(out.status, HealthMeasurementImportStatus.stored);
    expect(health.requested.single, ImportedMeasurementImporter.types);
    expect(await LocalDb.importedMeasurements(kKindSystolic), hasLength(1));
    expect(await LocalDb.importedMeasurements(kKindDiastolic), hasLength(1));
    expect(await LocalDb.importedMeasurements(kKindBodyTemp), hasLength(1));
    expect(await LocalDb.importedMeasurements(kKindGlucose), isEmpty);
    final glucose = await LocalDb.importedMeasurementReceipt(kKindGlucose);
    expect(glucose!['outcome'], HealthMeasurementImportStatus.empty.name);
    expect(glucose['stored_count'], 0);
    expect(glucose['written_count'], 0);
    expect(glucose['last_success_at'], isNull);
    final systolic = await LocalDb.importedMeasurementReceipt(kKindSystolic);
    expect(systolic!['outcome'], HealthMeasurementImportStatus.stored.name);
    expect(systolic['stored_count'], 1);
  });

  test('Apple asks a year and Android asks 30 days', () async {
    await openDb('glucose_window.db');
    final now = DateTime(2026, 8, 9);
    final apple = _FakeHealth(has: true);
    await ImportedMeasurementImporter(
      health: apple,
      isApple: true,
    ).sync(types: ImportedMeasurementImporter.glucoseOnly, now: now);
    expect(apple.windows.single.$1, DateTime(2025, 8, 9));
    final android = _FakeHealth(has: true);
    await ImportedMeasurementImporter(
      health: android,
      isApple: false,
    ).sync(types: ImportedMeasurementImporter.glucoseOnly, now: now);
    expect(
      android.windows.single.$2.difference(android.windows.single.$1).inDays,
      30,
    );
  });

  test('legacy backup merge keeps imported_at null', () async {
    await openDb('glucose_merge_dest.db');
    final srcPath = p.join(
      await databaseFactory.getDatabasesPath(),
      'glucose_merge_src.db',
    );
    created.add('glucose_merge_src.db');
    await databaseFactory.deleteDatabase(srcPath);
    final src = await databaseFactory.openDatabase(srcPath);
    await src.execute('''
      CREATE TABLE imported_measurement (
        uuid TEXT PRIMARY KEY,
        ts INTEGER NOT NULL,
        kind TEXT NOT NULL,
        value REAL NOT NULL,
        unit TEXT NOT NULL,
        source TEXT NOT NULL
      )
    ''');
    await src.insert('imported_measurement', {
      'uuid': 'from-backup',
      'ts': 1780000000,
      'kind': kKindGlucose,
      'value': 88.0,
      'unit': kGlucoseUnitMilligramPerDeciliter,
      'source': 'Dexcom',
    });
    await src.close();
    await LocalDb.importFromDbFile(srcPath);
    final row = (await LocalDb.importedMeasurements(kKindGlucose)).single;
    expect(row['uuid'], 'from-backup');
    expect(row['value'], 88.0);
    expect(row['imported_at'], isNull);
    expect(row['source'], 'Dexcom');
  });

  test('exclusion persists across reopen and skips new imports', () async {
    await openDb('glucose_exclude.db');
    final first = DateTime(2026, 9, 15, 10);
    await LocalDb.putImportedMeasurements([
      {
        'uuid': 'old',
        'ts': 1,
        'kind': kKindGlucose,
        'value': 95.0,
        'unit': kGlucoseUnitMilligramPerDeciliter,
        'source': 'Dexcom',
        'source_key': 'apple:com.dexcom.G7',
      },
    ], now: first);
    await LocalDb.setImportedMeasurementSourceExcluded(
      kind: kKindGlucose,
      sourceKey: 'apple:com.dexcom.G7',
      excluded: true,
    );
    await LocalDb.close();
    LocalDb.dbName = 'glucose_exclude.db';
    final settings = await LocalDb.importedMeasurementSourceSettings(
      kKindGlucose,
    );
    expect(settings.single['excluded'], 1);

    await ImportedMeasurementImporter(
      health: _FakeHealth(
        has: true,
        points: [_p(HealthDataType.BLOOD_GLUCOSE, 110, uuid: 'new')],
      ),
      isApple: true,
    ).sync(
      types: ImportedMeasurementImporter.glucoseOnly,
      now: DateTime(2026, 9, 15, 11),
    );
    final rows = await LocalDb.importedMeasurements(kKindGlucose);
    expect(rows.map((r) => r['uuid']), ['old']);
    final receipt = await LocalDb.importedMeasurementReceipt(kKindGlucose);
    expect(receipt!['outcome'], HealthMeasurementImportStatus.empty.name);
    expect(receipt['stored_count'], 0);
    expect(receipt['written_count'], 0);
    expect(receipt['ignored_count'], 1);
    expect(receipt['last_success_at'], first.millisecondsSinceEpoch ~/ 1000);
  });

  test('incomplete stored row is partial without dropping siblings', () async {
    await openDb('glucose_corrupt_row.db');
    final db = await LocalDb.instance;
    await db.insert('imported_measurement', {
      'uuid': 'good',
      'ts': 2,
      'kind': kKindGlucose,
      'value': 95.0,
      'unit': kGlucoseUnitMilligramPerDeciliter,
      'source': 'Dexcom',
      'source_key': 'apple:com.dexcom.G7',
    });
    await db.insert('imported_measurement', {
      'uuid': '',
      'ts': 1,
      'kind': kKindGlucose,
      'value': 95.0,
      'unit': kGlucoseUnitMilligramPerDeciliter,
      'source': 'Dexcom',
      'source_key': 'apple:com.dexcom.G7',
    });
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final snap = await LocalOpenBandRepository(app).readGlucose();
    expect(snap.history.single.uuid, 'good');
    expect(snap.unreadableCount, 1);
  });

  test('corrupt stored scalars do not drop healthy rows or throw', () async {
    await openDb('glucose_corrupt_types.db');
    final db = await LocalDb.instance;
    Future<void> insert({
      required String uuid,
      required Object ts,
      required Object value,
    }) async {
      await db.rawInsert(
        'INSERT INTO imported_measurement '
        '(uuid, ts, kind, value, unit, source, source_key) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          uuid,
          ts,
          kKindGlucose,
          value,
          kGlucoseUnitMilligramPerDeciliter,
          'Dexcom',
          'apple:com.dexcom.G7',
        ],
      );
    }

    await insert(uuid: 'good', ts: 1780000000, value: 95.0);
    await insert(uuid: 'bad-ts', ts: 'not-a-time', value: 95.0);
    await insert(uuid: 'huge-ts', ts: 9999999999999999, value: 95.0);
    await insert(uuid: 'bad-value', ts: 1780000001, value: 'nope');
    await db.insert('imported_measurement_receipt', {
      'kind': kKindGlucose,
      'last_attempt_at': 9999999999999999,
      'outcome': 'stored',
      'stored_count': '1',
      'written_count': 1,
      'invalid_count': 0,
      'ignored_count': 0,
    });
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final snap = await LocalOpenBandRepository(app).readGlucose();
    expect(snap.history.single.uuid, 'good');
    expect(snap.history.single.value, 95.0);
    expect(snap.unreadableCount, 4);
    expect(snap.attempt.attemptedAt, isNull);
    expect(snap.attempt.status, HealthMeasurementImportStatus.stored);
    expect(await LocalDb.importedMeasurements(kKindGlucose), hasLength(4));
  });

  test(
    'BP-only four-kind pass leaves glucose empty and keeps last success',
    () async {
      await openDb('glucose_bp_only.db');
      final first = DateTime(2026, 9, 15, 9);
      await ImportedMeasurementImporter(
        health: _FakeHealth(
          has: true,
          points: [_p(HealthDataType.BLOOD_GLUCOSE, 95, uuid: 'g')],
        ),
        isApple: true,
      ).sync(types: ImportedMeasurementImporter.glucoseOnly, now: first);
      final before = await LocalDb.importedMeasurementReceipt(kKindGlucose);
      expect(before!['outcome'], HealthMeasurementImportStatus.stored.name);
      final successAt = before['last_success_at'] as num;
      expect(successAt, greaterThan(first.millisecondsSinceEpoch ~/ 1000));

      final out = await ImportedMeasurementImporter(
        health: _FakeHealth(
          has: true,
          points: [
            _p(HealthDataType.BLOOD_PRESSURE_SYSTOLIC, 118, uuid: 's'),
            _p(HealthDataType.BLOOD_PRESSURE_DIASTOLIC, 76, uuid: 'd'),
            _p(
              HealthDataType.BODY_TEMPERATURE,
              36.8,
              uuid: 't',
              unit: HealthDataUnit.DEGREE_CELSIUS,
            ),
          ],
        ),
        isApple: true,
      ).sync(now: DateTime(2026, 9, 15, 10));
      expect(out.status, HealthMeasurementImportStatus.stored);
      expect(out.storedCount, 3);
      final glucose = await LocalDb.importedMeasurementReceipt(kKindGlucose);
      expect(glucose!['outcome'], HealthMeasurementImportStatus.empty.name);
      expect(glucose['stored_count'], 0);
      expect(glucose['written_count'], 0);
      expect(glucose['last_success_at'], successAt);
      expect(await LocalDb.importedMeasurements(kKindGlucose), hasLength(1));
    },
  );

  test('importGlucose keeps stored outcome when refresh fails', () async {
    await openDb('glucose_refresh_fail.db');
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final repo = LocalOpenBandRepository(
      app,
      measurementImporter: ImportedMeasurementImporter(
        health: _FakeHealth(
          has: true,
          points: [_p(HealthDataType.BLOOD_GLUCOSE, 95, uuid: 'g')],
        ),
        isApple: true,
      ),
      glucoseRefresh: () async => throw StateError('refresh'),
    );
    final result = await repo.importGlucose(now: DateTime(2026, 9, 15, 10));
    expect(result.outcome.status, HealthMeasurementImportStatus.stored);
    expect(result.outcome.storedCount, 1);
    expect(result.refreshFailed, isTrue);
    expect(result.snapshot, isNull);
    final snap = await LocalOpenBandRepository(app).readGlucose();
    expect(snap.history.single.uuid, 'g');
    expect(snap.history.single.value, 95.0);
  });

  test(
    'importGlucose refresh is the hero window, not every stored row',
    () async {
      await openDb('glucose_import_hero.db');
      await LocalDb.putImportedMeasurements([
        for (var i = 0; i < 5; i++)
          {
            'uuid': 'g$i',
            'ts': DateTime(2026, 9, 15, 8, i).millisecondsSinceEpoch ~/ 1000,
            'kind': kKindGlucose,
            'value': 90.0 + i,
            'unit': kGlucoseUnitMilligramPerDeciliter,
            'source': 'Dexcom',
            'source_key': 'apple:com.dexcom.G7',
          },
      ]);
      SharedPreferences.setMockInitialValues({});
      Prefs.debugReset();
      await Prefs.ensureLoaded();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final repo = LocalOpenBandRepository(
        app,
        measurementImporter: ImportedMeasurementImporter(
          health: _FakeHealth(has: true, points: const []),
          isApple: true,
        ),
      );
      final result = await repo.importGlucose(now: DateTime(2026, 9, 15, 10));
      expect(result.outcome.status, HealthMeasurementImportStatus.empty);
      expect(result.refreshFailed, isFalse);
      expect(result.snapshot!.history, hasLength(1));
      expect(result.snapshot!.history.single.uuid, 'g4');
      expect(result.snapshot!.truncated, isTrue);
      expect(result.snapshot!.series, hasLength(5));
      expect(result.snapshot!.sources.single.readingCount, 5);
    },
  );

  test('delayed Health query and persist use different clocks', () async {
    await openDb('glucose_clocks.db');
    final query = DateTime(2026, 9, 15, 9, 41);
    var wall = query;
    final gate = Completer<void>();
    final health = _FakeHealth(
      has: true,
      points: [_p(HealthDataType.BLOOD_GLUCOSE, 95, uuid: 'g')],
      delay: gate,
    );
    final done = ImportedMeasurementImporter(
      health: health,
      isApple: true,
      clock: () => wall,
    ).sync(types: ImportedMeasurementImporter.glucoseOnly, now: query);
    while (health.requested.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    wall = DateTime(2026, 9, 15, 9, 43);
    gate.complete();
    await done;
    final row = (await LocalDb.importedMeasurements(kKindGlucose)).single;
    expect(row['imported_at'], wall.millisecondsSinceEpoch ~/ 1000);
    final receipt = await LocalDb.importedMeasurementReceipt(kKindGlucose);
    expect(receipt!['last_attempt_at'], query.millisecondsSinceEpoch ~/ 1000);
    expect(receipt['last_success_at'], wall.millisecondsSinceEpoch ~/ 1000);
  });

  test(
    'default persist clock is after the Health read, not the query start',
    () async {
      await openDb('glucose_default_clock.db');
      final query = DateTime(2020, 1, 1, 8);
      final started = DateTime.now();
      final gate = Completer<void>();
      final health = _FakeHealth(
        has: true,
        points: [_p(HealthDataType.BLOOD_GLUCOSE, 95, uuid: 'g')],
        delay: gate,
      );
      final done = ImportedMeasurementImporter(
        health: health,
        isApple: true,
      ).sync(types: ImportedMeasurementImporter.glucoseOnly, now: query);
      while (health.requested.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();
      await done;
      final row = (await LocalDb.importedMeasurements(kKindGlucose)).single;
      final importedAt = (row['imported_at'] as num).toInt();
      expect(importedAt, greaterThan(query.millisecondsSinceEpoch ~/ 1000));
      expect(
        importedAt,
        greaterThanOrEqualTo(started.millisecondsSinceEpoch ~/ 1000),
      );
      final receipt = await LocalDb.importedMeasurementReceipt(kKindGlucose);
      expect(receipt!['last_attempt_at'], query.millisecondsSinceEpoch ~/ 1000);
      expect(receipt['last_success_at'], importedAt);
    },
  );

  test('persistence failure keeps per-kind parse counts', () async {
    await openDb('glucose_fail_counts.db');
    final outcome = await ImportedMeasurementImporter(
      health: _FakeHealth(
        has: true,
        points: [
          _p(HealthDataType.BLOOD_GLUCOSE, 95, uuid: 'g'),
          _p(
            HealthDataType.BODY_TEMPERATURE,
            36.8,
            uuid: 't',
            unit: HealthDataUnit.MILLIMETER_OF_MERCURY,
          ),
        ],
      ),
      isApple: true,
      commit: (input) async {
        if (input.persistRows) throw StateError('disk');
        return LocalDb.commitImportedMeasurements(input);
      },
    ).sync(now: DateTime(2026, 9, 15, 10));
    expect(outcome.status, HealthMeasurementImportStatus.persistenceFailed);
    expect(outcome.invalidCount, 1);
    final glucose = await LocalDb.importedMeasurementReceipt(kKindGlucose);
    expect(
      glucose!['outcome'],
      HealthMeasurementImportStatus.persistenceFailed.name,
    );
    expect(glucose['invalid_count'], 0);
    expect(glucose['stored_count'], 0);
    final temp = await LocalDb.importedMeasurementReceipt(kKindBodyTemp);
    expect(
      temp!['outcome'],
      HealthMeasurementImportStatus.persistenceFailed.name,
    );
    expect(temp['invalid_count'], 1);
    expect(temp['stored_count'], 0);
    final systolic = await LocalDb.importedMeasurementReceipt(kKindSystolic);
    expect(systolic!['invalid_count'], 0);
  });

  test('corrupt receipt is partial, not never-attempted', () async {
    await openDb('glucose_corrupt_receipt.db');
    final db = await LocalDb.instance;
    await db.execute('''
      INSERT INTO imported_measurement_receipt
      (kind, last_attempt_at, outcome, stored_count, written_count,
       invalid_count, ignored_count)
      VALUES ('$kKindGlucose', 'nope', 12, 'not-a-count', 0, 0, 0)
    ''');
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final snap = await LocalOpenBandRepository(app).readGlucose();
    expect(snap.history, isEmpty);
    expect(snap.unreadableCount, greaterThan(0));
    expect(snap.attempt.status, HealthMeasurementImportStatus.partial);
    expect(
      snap.attempt.status,
      isNot(HealthMeasurementImportStatus.notAttempted),
    );
    expect(snap.attempt.attemptedAt, isNull);
  });

  test('non-string source identity is quarantined beside a healthy row', () {
    final snap = buildGlucoseSnapshot(
      rows: [
        {
          'uuid': 'good',
          'ts': 2,
          'kind': kKindGlucose,
          'value': 95.0,
          'unit': kGlucoseUnitMilligramPerDeciliter,
          'source': 'Dexcom',
          'source_id': 'com.dexcom.G7',
          'source_key': 'apple:com.dexcom.G7',
        },
        {
          'uuid': 'bad-key',
          'ts': 1,
          'kind': kKindGlucose,
          'value': 90.0,
          'unit': kGlucoseUnitMilligramPerDeciliter,
          'source': 'Dexcom',
          'source_key': 1,
        },
        {
          'uuid': true,
          'ts': 3,
          'kind': kKindGlucose,
          'value': 88.0,
          'unit': kGlucoseUnitMilligramPerDeciliter,
          'source': 7,
        },
      ],
      settings: [
        {'source_key': false, 'excluded': 1},
      ],
      receipt: null,
    );
    expect(snap.history.single.uuid, 'good');
    expect(snap.history.single.source.key, 'apple:com.dexcom.G7');
    expect(snap.unreadableCount, greaterThanOrEqualTo(3));
    expect(snap.sources.map((s) => s.source.key), isNot(contains('1')));
    expect(snap.sources.map((s) => s.source.key), isNot(contains('false')));
  });

  test(
    'source inventory takes the latest measurement name for a known id',
    () async {
      await openDb('glucose_rename.db');
      await LocalDb.putImportedMeasurements([
        {
          'uuid': 'older',
          'ts': DateTime(2026, 9, 14, 8).millisecondsSinceEpoch ~/ 1000,
          'kind': kKindGlucose,
          'value': 90.0,
          'unit': kGlucoseUnitMilligramPerDeciliter,
          'source': 'Dexcom G6',
          'source_id': 'com.dexcom.G7',
          'source_key': 'apple:com.dexcom.G7',
        },
        {
          'uuid': 'newer',
          'ts': DateTime(2026, 9, 15, 8).millisecondsSinceEpoch ~/ 1000,
          'kind': kKindGlucose,
          'value': 95.0,
          'unit': kGlucoseUnitMilligramPerDeciliter,
          'source': 'Dexcom G7',
          'source_id': 'com.dexcom.G7',
          'source_key': 'apple:com.dexcom.G7',
        },
      ]);
      SharedPreferences.setMockInitialValues({});
      Prefs.debugReset();
      await Prefs.ensureLoaded();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final snap = await LocalOpenBandRepository(app).readGlucose();
      expect(snap.sources.single.source.sourceName, 'Dexcom G7');
      expect(snap.sources.single.source.sourceId, 'com.dexcom.G7');
      expect(snap.sources.single.source.key, 'apple:com.dexcom.G7');
      expect(
        snap.history.firstWhere((r) => r.uuid == 'older').source.sourceName,
        'Dexcom G6',
      );
      expect(
        snap.history.firstWhere((r) => r.uuid == 'newer').source.sourceName,
        'Dexcom G7',
      );
    },
  );

  test(
    'SQL history limit 1 still returns the full latest local day series',
    () async {
      await openDb('glucose_limit1_day.db');
      final rows = [
        for (var i = 0; i < 250; i++)
          {
            'uuid': 'n$i',
            'ts':
                DateTime(
                  2026,
                  9,
                  15,
                  12,
                ).subtract(Duration(minutes: i)).millisecondsSinceEpoch ~/
                1000,
            'kind': kKindGlucose,
            'value': 95.0,
            'unit': kGlucoseUnitMilligramPerDeciliter,
            'source': 'Dexcom',
            'source_key': 'apple:com.dexcom.G7',
          },
        for (var i = 0; i < 20; i++)
          {
            'uuid': 'prev$i',
            'ts':
                DateTime(
                  2026,
                  9,
                  14,
                  12,
                ).subtract(Duration(minutes: i)).millisecondsSinceEpoch ~/
                1000,
            'kind': kKindGlucose,
            'value': 90.0,
            'unit': kGlucoseUnitMilligramPerDeciliter,
            'source': 'Dexcom',
            'source_key': 'apple:com.dexcom.G7',
          },
      ];
      await LocalDb.putImportedMeasurements(rows);
      SharedPreferences.setMockInitialValues({});
      Prefs.debugReset();
      await Prefs.ensureLoaded();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final snap = await LocalOpenBandRepository(app).readGlucose(limit: 1);
      expect(snap.history, hasLength(1));
      expect(snap.history.single.uuid, 'n0');
      expect(snap.series, hasLength(250));
      expect(snap.truncated, isTrue);
      expect(snap.sources.single.readingCount, 270);
      expect(snap.lastMeasuredAt, DateTime(2026, 9, 15, 12));
    },
  );

  test('SQL 200 then 400 keeps newest order and stable stored count', () async {
    await openDb('glucose_page.db');
    await LocalDb.putImportedMeasurements([
      for (var i = 0; i < 400; i++)
        {
          'uuid': 'g$i',
          'ts':
              DateTime(
                2026,
                9,
                15,
                16,
              ).subtract(Duration(minutes: i)).millisecondsSinceEpoch ~/
              1000,
          'kind': kKindGlucose,
          'value': 95.0,
          'unit': kGlucoseUnitMilligramPerDeciliter,
          'source': 'Dexcom',
          'source_key': 'apple:com.dexcom.G7',
        },
    ]);
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final repo = LocalOpenBandRepository(app);
    final first = await repo.readGlucose(limit: 200);
    expect(first.history, hasLength(200));
    expect(first.history.first.uuid, 'g0');
    expect(first.history.last.uuid, 'g199');
    expect(first.truncated, isTrue);
    expect(first.sources.single.readingCount, 400);
    expect(first.series, hasLength(400));
    final more = await repo.readGlucose(limit: 400);
    expect(more.history, hasLength(400));
    expect(more.truncated, isFalse);
    expect(more.sources.single.readingCount, 400);
  });

  test(
    'mixed sources and units keep separate keys; latest unknown withholds',
    () async {
      await openDb('glucose_mixed_src.db');
      await LocalDb.putImportedMeasurements([
        {
          'uuid': 'dex-new',
          'ts': DateTime(2026, 9, 15, 8).millisecondsSinceEpoch ~/ 1000,
          'kind': kKindGlucose,
          'value': 5.2,
          'unit': kGlucoseUnitMillimolePerLiter,
          'source': 'Dexcom',
          'source_key': 'apple:com.dexcom.G7',
        },
        {
          'uuid': 'dex-old',
          'ts': DateTime(2026, 9, 15, 7).millisecondsSinceEpoch ~/ 1000,
          'kind': kKindGlucose,
          'value': 95.0,
          'unit': kGlucoseUnitMilligramPerDeciliter,
          'source': 'Dexcom',
          'source_key': 'apple:com.dexcom.G7',
        },
        {
          'uuid': 'legacy',
          'ts': DateTime(2026, 9, 15, 9).millisecondsSinceEpoch ~/ 1000,
          'kind': kKindGlucose,
          'value': 88.0,
          'unit': kGlucoseUnitMilligramPerDeciliter,
          'source': 'Other',
        },
      ]);
      SharedPreferences.setMockInitialValues({});
      Prefs.debugReset();
      await Prefs.ensureLoaded();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final repo = LocalOpenBandRepository(app);
      final dex = await repo.readGlucose(
        sourceKey: 'apple:com.dexcom.G7',
        limit: 1,
      );
      expect(dex.history.single.uuid, 'dex-new');
      expect(dex.series.single.uuid, 'dex-new');
      expect(dex.sources.map((s) => s.source.key).toSet(), {
        'apple:com.dexcom.G7',
        'legacy:Other',
      });
      expect(
        dex.sources
            .firstWhere((s) => s.source.key == 'apple:com.dexcom.G7')
            .readingCount,
        2,
      );
      expect(
        dex.sources
            .firstWhere((s) => s.source.key == 'legacy:Other')
            .readingCount,
        1,
      );

      await LocalDb.putImportedMeasurements([
        {
          'uuid': 'dex-unknown',
          'ts': DateTime(2026, 9, 15, 10).millisecondsSinceEpoch ~/ 1000,
          'kind': kKindGlucose,
          'value': 5.2,
          'unit': 'stones',
          'source': 'Dexcom',
          'source_key': 'apple:com.dexcom.G7',
        },
      ]);
      final unknown = await repo.readGlucose(sourceKey: 'apple:com.dexcom.G7');
      expect(unknown.history.first.uuid, 'dex-unknown');
      expect(unknown.series, isEmpty);
      expect(
        unknown.sources
            .firstWhere((s) => s.source.key == 'apple:com.dexcom.G7')
            .readingCount,
        3,
      );
    },
  );

  test('latest local day bounds use DateTime(y, m, d+1), not 86400', () async {
    await openDb('glucose_local_day.db');
    final latest = DateTime(2026, 3, 8, 12);
    final day = glucoseLocalDayWindow(latest)!;
    await LocalDb.putImportedMeasurements([
      {
        'uuid': 'before',
        'ts':
            day.start
                .subtract(const Duration(seconds: 1))
                .millisecondsSinceEpoch ~/
            1000,
        'kind': kKindGlucose,
        'value': 90.0,
        'unit': kGlucoseUnitMilligramPerDeciliter,
        'source': 'Dexcom',
        'source_key': 'apple:com.dexcom.G7',
      },
      {
        'uuid': 'start',
        'ts': day.start.millisecondsSinceEpoch ~/ 1000,
        'kind': kKindGlucose,
        'value': 91.0,
        'unit': kGlucoseUnitMilligramPerDeciliter,
        'source': 'Dexcom',
        'source_key': 'apple:com.dexcom.G7',
      },
      {
        'uuid': 'mid',
        'ts': latest.millisecondsSinceEpoch ~/ 1000,
        'kind': kKindGlucose,
        'value': 95.0,
        'unit': kGlucoseUnitMilligramPerDeciliter,
        'source': 'Dexcom',
        'source_key': 'apple:com.dexcom.G7',
      },
      {
        'uuid': 'end-1',
        'ts':
            day.end
                .subtract(const Duration(seconds: 1))
                .millisecondsSinceEpoch ~/
            1000,
        'kind': kKindGlucose,
        'value': 96.0,
        'unit': kGlucoseUnitMilligramPerDeciliter,
        'source': 'Dexcom',
        'source_key': 'apple:com.dexcom.G7',
      },
    ]);
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final snap = await LocalOpenBandRepository(app).readGlucose(limit: 1);
    expect(snap.history.single.uuid, 'end-1');
    expect(snap.series.map((r) => r.uuid).toSet(), {'start', 'mid', 'end-1'});
    expect(snap.series.map((r) => r.uuid), isNot(contains('before')));
    expect(snap.sources.single.readingCount, 4);
  });

  test(
    'same-timestamp UUID cursor keeps valid rows after a corrupt page',
    () async {
      await openDb('glucose_uuid_cursor.db');
      final db = await LocalDb.instance;
      final ts = DateTime(2026, 9, 15, 8).millisecondsSinceEpoch ~/ 1000;
      for (var i = 0; i < 40; i++) {
        final uuid = 'z${i.toString().padLeft(2, '0')}';
        if (i >= 8) {
          await db.rawInsert(
            'INSERT INTO imported_measurement '
            '(uuid, ts, kind, value, unit, source, source_key) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
              uuid,
              ts,
              kKindGlucose,
              'nope',
              kGlucoseUnitMilligramPerDeciliter,
              'Dexcom',
              'apple:com.dexcom.G7',
            ],
          );
        } else {
          await db.insert('imported_measurement', {
            'uuid': uuid,
            'ts': ts,
            'kind': kKindGlucose,
            'value': 95.0,
            'unit': kGlucoseUnitMilligramPerDeciliter,
            'source': 'Dexcom',
            'source_key': 'apple:com.dexcom.G7',
          });
        }
      }
      SharedPreferences.setMockInitialValues({});
      Prefs.debugReset();
      await Prefs.ensureLoaded();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final repo = LocalOpenBandRepository(app);
      final snap = await repo.readGlucose(limit: 3);
      expect(snap.history.map((r) => r.uuid), ['z07', 'z06', 'z05']);
      expect(snap.truncated, isTrue);
      expect(snap.lastMeasuredAt, DateTime(2026, 9, 15, 8));
      expect(snap.sources.single.readingCount, 40);
      final all = await repo.readGlucose();
      expect(all.history.map((r) => r.uuid), [
        'z07',
        'z06',
        'z05',
        'z04',
        'z03',
        'z02',
        'z01',
        'z00',
      ]);
      expect(all.truncated, isFalse);
    },
  );

  test('newest-N UUID ties are ts then uuid descending', () async {
    await openDb('glucose_uuid_ties.db');
    final db = await LocalDb.instance;
    final ts = DateTime(2026, 9, 15, 8).millisecondsSinceEpoch ~/ 1000;
    for (final uuid in ['a', 'c', 'e', 'b', 'd']) {
      await db.insert('imported_measurement', {
        'uuid': uuid,
        'ts': ts,
        'kind': kKindGlucose,
        'value': 95.0,
        'unit': kGlucoseUnitMilligramPerDeciliter,
        'source': 'Dexcom',
        'source_key': 'apple:com.dexcom.G7',
      });
    }
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final snap = await LocalOpenBandRepository(app).readGlucose(limit: 3);
    expect(snap.history.map((r) => r.uuid), ['e', 'd', 'c']);
    expect(snap.truncated, isTrue);
  });

  test('pages past hundreds of corrupt rows to a readable one', () async {
    await openDb('glucose_corrupt_page.db');
    final db = await LocalDb.instance;
    for (var i = 0; i < 280; i++) {
      await db.rawInsert(
        'INSERT INTO imported_measurement '
        '(uuid, ts, kind, value, unit, source, source_key) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          'bad$i',
          2000 + i,
          kKindGlucose,
          'nope',
          kGlucoseUnitMilligramPerDeciliter,
          'Dexcom',
          'apple:com.dexcom.G7',
        ],
      );
    }
    await db.insert('imported_measurement', {
      'uuid': 'good',
      'ts': 1000,
      'kind': kKindGlucose,
      'value': 95.0,
      'unit': kGlucoseUnitMilligramPerDeciliter,
      'source': 'Dexcom',
      'source_key': 'apple:com.dexcom.G7',
    });
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final snap = await LocalOpenBandRepository(app).readGlucose(limit: 1);
    expect(snap.history.single.uuid, 'good');
    expect(snap.truncated, isFalse);
    expect(snap.sources.single.readingCount, 281);
    expect(snap.unreadableCount, 280);
  });

  test('2 valid + 3 corrupt at limit 200 is not truncated', () async {
    await openDb('glucose_trunc_corrupt.db');
    final db = await LocalDb.instance;
    await db.insert('imported_measurement', {
      'uuid': 'new',
      'ts': DateTime(2026, 9, 15, 8).millisecondsSinceEpoch ~/ 1000,
      'kind': kKindGlucose,
      'value': 95.0,
      'unit': kGlucoseUnitMilligramPerDeciliter,
      'source': 'Dexcom',
      'source_key': 'apple:com.dexcom.G7',
      'imported_at': 10,
    });
    await db.insert('imported_measurement', {
      'uuid': 'old',
      'ts': DateTime(2026, 9, 14, 8).millisecondsSinceEpoch ~/ 1000,
      'kind': kKindGlucose,
      'value': 90.0,
      'unit': kGlucoseUnitMilligramPerDeciliter,
      'source': 'Dexcom',
      'source_key': 'apple:com.dexcom.G7',
      'imported_at': 50,
    });
    for (var i = 0; i < 3; i++) {
      await db.rawInsert(
        'INSERT INTO imported_measurement '
        '(uuid, ts, kind, value, unit, source, source_key, imported_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'bad$i',
          DateTime(2026, 9, 16, i).millisecondsSinceEpoch ~/ 1000,
          kKindGlucose,
          'nope',
          kGlucoseUnitMilligramPerDeciliter,
          'Dexcom',
          'apple:com.dexcom.G7',
          20,
        ],
      );
    }
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final snap = await LocalOpenBandRepository(app).readGlucose(limit: 200);
    expect(snap.history.map((r) => r.uuid), ['new', 'old']);
    expect(snap.truncated, isFalse);
    expect(snap.sources.single.readingCount, 5);
    expect(snap.unreadableCount, 3);
    expect(snap.lastMeasuredAt, DateTime(2026, 9, 15, 8));
    expect(snap.lastImportedAt, DateTime.fromMillisecondsSinceEpoch(50 * 1000));
  });

  test('lookahead unread after newest-N is counted off the latest day', () async {
    await openDb('glucose_lookahead_unread.db');
    final db = await LocalDb.instance;
    Future<void> put({
      required String uuid,
      required DateTime at,
      Object value = 95.0,
    }) async {
      if (value is String) {
        await db.rawInsert(
          'INSERT INTO imported_measurement '
          '(uuid, ts, kind, value, unit, source, source_key) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            uuid,
            at.millisecondsSinceEpoch ~/ 1000,
            kKindGlucose,
            value,
            kGlucoseUnitMilligramPerDeciliter,
            'Dexcom',
            'apple:com.dexcom.G7',
          ],
        );
      } else {
        await db.insert('imported_measurement', {
          'uuid': uuid,
          'ts': at.millisecondsSinceEpoch ~/ 1000,
          'kind': kKindGlucose,
          'value': value,
          'unit': kGlucoseUnitMilligramPerDeciliter,
          'source': 'Dexcom',
          'source_key': 'apple:com.dexcom.G7',
        });
      }
    }

    for (var i = 0; i < 5; i++) {
      await put(
        uuid: 'new$i',
        at: DateTime(2026, 9, 15, 12 - i),
      );
    }
    for (var i = 0; i < 10; i++) {
      await put(
        uuid: 'bad$i',
        at: DateTime(2026, 9, 14, 12 - i),
        value: 'nope',
      );
    }
    for (var i = 0; i < 5; i++) {
      await put(
        uuid: 'old$i',
        at: DateTime(2026, 9, 13, 12 - i),
      );
    }
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final snap = await LocalOpenBandRepository(app).readGlucose(limit: 5);
    expect(snap.history.map((r) => r.uuid), [
      'new0',
      'new1',
      'new2',
      'new3',
      'new4',
    ]);
    expect(snap.truncated, isTrue);
    expect(snap.unreadableCount, 10);
    expect(snap.series, hasLength(5));
    expect(snap.sources.single.readingCount, 20);
  });

  test('explicit legacy key and null-key name share one identity', () async {
    await openDb('glucose_legacy_key_match.db');
    await LocalDb.putImportedMeasurements([
      {
        'uuid': 'null-key',
        'ts': DateTime(2026, 9, 14, 8).millisecondsSinceEpoch ~/ 1000,
        'kind': kKindGlucose,
        'value': 90.0,
        'unit': kGlucoseUnitMilligramPerDeciliter,
        'source': 'Dexcom',
      },
      {
        'uuid': 'explicit-key',
        'ts': DateTime(2026, 9, 15, 8).millisecondsSinceEpoch ~/ 1000,
        'kind': kKindGlucose,
        'value': 95.0,
        'unit': kGlucoseUnitMilligramPerDeciliter,
        'source': 'Dexcom',
        'source_key': 'legacy:Dexcom',
      },
    ]);
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final repo = LocalOpenBandRepository(app);
    final snap = await repo.readGlucose(sourceKey: 'legacy:Dexcom');
    expect(snap.sources.single.source.key, 'legacy:Dexcom');
    expect(snap.sources.single.readingCount, 2);
    expect(snap.history.map((r) => r.uuid), ['explicit-key', 'null-key']);
    expect(snap.series.map((r) => r.uuid), ['explicit-key']);
    await LocalDb.setImportedMeasurementSourceExcluded(
      kind: kKindGlucose,
      sourceKey: 'legacy:Dexcom',
      excluded: true,
    );
    final hidden = await repo.readGlucose(sourceKey: 'legacy:Dexcom');
    expect(hidden.selectedExcluded, isTrue);
    expect(hidden.series, isEmpty);
    expect(hidden.history.map((r) => r.uuid), ['explicit-key', 'null-key']);
  });

  test('same-ts mixed units page past 32; newest uuid unknown withholds plot',
      () async {
    await openDb('glucose_same_ts_units.db');
    final db = await LocalDb.instance;
    final ts = DateTime(2026, 9, 15, 8).millisecondsSinceEpoch ~/ 1000;
    for (var i = 0; i < 40; i++) {
      final uuid = 'u${i.toString().padLeft(2, '0')}';
      final unknown = i == 39;
      await db.insert('imported_measurement', {
        'uuid': uuid,
        'ts': ts,
        'kind': kKindGlucose,
        'value': unknown ? 5.2 : (i.isEven ? 5.2 : 95.0),
        'unit': unknown
            ? 'stones'
            : (i.isEven
                ? kGlucoseUnitMillimolePerLiter
                : kGlucoseUnitMilligramPerDeciliter),
        'source': 'Dexcom',
        'source_key': 'apple:com.dexcom.G7',
      });
    }
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final snap = await LocalOpenBandRepository(app).readGlucose(limit: 1);
    expect(snap.history.single.uuid, 'u39');
    expect(snap.history.single.unitKind, GlucoseUnitKind.unknown);
    expect(snap.series, isEmpty);
    expect(snap.lastMeasuredAt, DateTime(2026, 9, 15, 8));
    expect(snap.sources.single.readingCount, 40);
  });

  test('invalid imported_at is partial; older valid stamp remains',
      () async {
    await openDb('glucose_imported_at_corrupt.db');
    final db = await LocalDb.instance;
    await db.insert('imported_measurement', {
      'uuid': 'valid-older',
      'ts': DateTime(2026, 9, 14, 8).millisecondsSinceEpoch ~/ 1000,
      'kind': kKindGlucose,
      'value': 90.0,
      'unit': kGlucoseUnitMilligramPerDeciliter,
      'source': 'Dexcom',
      'source_key': 'apple:com.dexcom.G7',
      'imported_at': 50,
    });
    await db.insert('imported_measurement', {
      'uuid': 'inf-import',
      'ts': DateTime(2026, 9, 15, 8).millisecondsSinceEpoch ~/ 1000,
      'kind': kKindGlucose,
      'value': 95.0,
      'unit': kGlucoseUnitMilligramPerDeciliter,
      'source': 'Dexcom',
      'source_key': 'apple:com.dexcom.G7',
      'imported_at': double.infinity,
    });
    await db.insert('imported_measurement', {
      'uuid': 'beyond-range',
      'ts': DateTime(2026, 9, 15, 7).millisecondsSinceEpoch ~/ 1000,
      'kind': kKindGlucose,
      'value': 94.0,
      'unit': kGlucoseUnitMilligramPerDeciliter,
      'source': 'Dexcom',
      'source_key': 'apple:com.dexcom.G7',
      'imported_at': kGlucoseEpochSecMax + 1,
    });
    await db.insert('imported_measurement', {
      'uuid': 'legacy-null',
      'ts': DateTime(2026, 9, 13, 8).millisecondsSinceEpoch ~/ 1000,
      'kind': kKindGlucose,
      'value': 88.0,
      'unit': kGlucoseUnitMilligramPerDeciliter,
      'source': 'Dexcom',
      'source_key': 'apple:com.dexcom.G7',
    });
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final snap = await LocalOpenBandRepository(app).readGlucose();
    expect(snap.history.map((r) => r.uuid), [
      'inf-import',
      'beyond-range',
      'valid-older',
      'legacy-null',
    ]);
    expect(snap.unreadableCount, 2);
    expect(
      snap.lastImportedAt,
      DateTime.fromMillisecondsSinceEpoch(50 * 1000),
    );
    expect(snap.history.where((r) => r.uuid == 'legacy-null').single.importedAt,
        isNull);
  });

  test('numeric ts Infinity does not drop sibling readable rows', () async {
    await openDb('glucose_ts_inf.db');
    final db = await LocalDb.instance;
    await db.insert('imported_measurement', {
      'uuid': 'inf-ts',
      'ts': double.infinity,
      'kind': kKindGlucose,
      'value': 95.0,
      'unit': kGlucoseUnitMilligramPerDeciliter,
      'source': 'Dexcom',
      'source_key': 'apple:com.dexcom.G7',
    });
    await db.insert('imported_measurement', {
      'uuid': 'good',
      'ts': DateTime(2026, 9, 15, 8).millisecondsSinceEpoch ~/ 1000,
      'kind': kKindGlucose,
      'value': 95.0,
      'unit': kGlucoseUnitMilligramPerDeciliter,
      'source': 'Dexcom',
      'source_key': 'apple:com.dexcom.G7',
    });
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final snap = await LocalOpenBandRepository(app).readGlucose();
    expect(snap.history.map((r) => r.uuid), ['good']);
    expect(snap.unreadableCount, 1);
    expect(snap.sources.single.readingCount, 2);
  });

  testWidgets(
    'PhoneImport opens canonical glucose and skips excluded raw rows',
    (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await openDb('glucose_phone_import_nav.db');
        await LocalDb.putImportedMeasurements([
          {
            'uuid': 'legacy-glucose',
            'ts': DateTime(2026, 9, 15, 8).millisecondsSinceEpoch ~/ 1000,
            'kind': kKindGlucose,
            'value': 999.0,
            'unit': kGlucoseUnitMilligramPerDeciliter,
            'source': 'Dexcom',
            'source_key': 'apple:com.dexcom.G7',
          },
          {
            'uuid': 'legacy-sys',
            'ts': DateTime(2026, 9, 15, 8).millisecondsSinceEpoch ~/ 1000,
            'kind': kKindSystolic,
            'value': 118.0,
            'unit': 'mmHg',
            'source': 'Omron',
            'source_key': 'apple:com.omron',
          },
        ]);
        await LocalDb.setImportedMeasurementSourceExcluded(
          kind: kKindGlucose,
          sourceKey: 'apple:com.dexcom.G7',
          excluded: true,
        );
        SharedPreferences.setMockInitialValues({});
        Prefs.debugReset();
        await Prefs.ensureLoaded();
      });
      final repo = SyntheticOpenBandRepository.fromMaps(
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/day-summary.json',
              ).readAsStringSync(),
            )
            as Map,
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/sleep-detail.json',
              ).readAsStringSync(),
            )
            as Map,
      )..clearGlucoseReadings();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: PhoneImport(repository: repo),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        if (find.text('118').evaluate().isNotEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      expect(find.text('999'), findsNothing);
      expect(find.text('MILLIGRAM_PER_DECILITER'), findsNothing);
      expect(find.text('118'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('phone-import-glucose')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('phone-import-glucose')));
      await tester.pump();
      await tester.pump();
      expect(find.byType(OpenBandGlucose), findsOneWidget);
      expect(find.text('Glukose'), findsOneWidget);
    },
  );
}

Future<String> _dbPath(String name) async =>
    p.join(await databaseFactory.getDatabasesPath(), name);
