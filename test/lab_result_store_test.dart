// lab_result storage.
//
// Two things matter more than the CRUD. A result is keyed on (marker, date
// drawn), so re-entering a value CORRECTS the typo rather than stacking a
// second reading a chart would then average. And each row carries its own
// unit, so a value keeps the unit it was entered under even if the catalogue's
// canonical unit changes later — silently reinterpreting 400 ng/mL as
// 400 nmol/L would be the worst kind of fabrication this app can make.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/lab_catalogue.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_lab_result_test.db';
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  tearDownAll(() async => LocalDb.close());

  setUp(() async {
    final db = await LocalDb.instance;
    await db.delete('lab_result');
    await db.delete('lab_marker_def');
  });

  test('a result round-trips', () async {
    await LocalDb.putLabResult(
      marker: 'ferritin',
      takenOn: '2026-03-04',
      value: 42,
      unit: 'ng/mL',
      note: 'fasted',
    );
    final rows = await LocalDb.labResults();
    expect(rows, hasLength(1));
    expect(rows.single['marker'], 'ferritin');
    expect(rows.single['value'], 42.0);
    expect(rows.single['unit'], 'ng/mL');
    expect(rows.single['note'], 'fasted');
  });

  test('re-entering the same draw corrects it instead of duplicating', () async {
    await LocalDb.putLabResult(
      marker: 'ferritin',
      takenOn: '2026-03-04',
      value: 420,
      unit: 'ng/mL',
    );
    await LocalDb.putLabResult(
      marker: 'ferritin',
      takenOn: '2026-03-04',
      value: 42,
      unit: 'ng/mL',
    );
    final rows = await LocalDb.labResults(marker: 'ferritin');
    expect(rows, hasLength(1), reason: 'a typo must not become a data point');
    expect(rows.single['value'], 42.0);
  });

  test('two draws of the same marker are two rows', () async {
    await LocalDb.putLabResult(
      marker: 'ferritin',
      takenOn: '2026-03-04',
      value: 42,
      unit: 'ng/mL',
    );
    await LocalDb.putLabResult(
      marker: 'ferritin',
      takenOn: '2026-09-04',
      value: 61,
      unit: 'ng/mL',
    );
    final rows = await LocalDb.labResults(marker: 'ferritin');
    expect(rows.map((r) => r['taken_on']), ['2026-09-04', '2026-03-04'],
        reason: 'newest draw first');
  });

  test('markers do not collide with each other', () async {
    await LocalDb.putLabResult(
      marker: 'ferritin',
      takenOn: '2026-03-04',
      value: 42,
      unit: 'ng/mL',
    );
    await LocalDb.putLabResult(
      marker: 'hba1c',
      takenOn: '2026-03-04',
      value: 5.2,
      unit: '%',
    );
    expect(await LocalDb.labResults(), hasLength(2));
    expect(await LocalDb.labResults(marker: 'hba1c'), hasLength(1));
  });

  test('a row keeps the unit it was entered under', () async {
    // Even if the catalogue later changes its canonical unit, the stored
    // reading must not be reinterpreted.
    await LocalDb.putLabResult(
      marker: 'custom_lp_a',
      takenOn: '2026-03-04',
      value: 90,
      unit: 'nmol/L',
    );
    expect(
      (await LocalDb.labResults(marker: 'custom_lp_a')).single['unit'],
      'nmol/L',
    );
  });

  test('deleting removes only that draw', () async {
    for (final d in ['2026-03-04', '2026-09-04']) {
      await LocalDb.putLabResult(
        marker: 'ferritin',
        takenOn: d,
        value: 42,
        unit: 'ng/mL',
      );
    }
    await LocalDb.deleteLabResult('ferritin', '2026-03-04');
    final rows = await LocalDb.labResults(marker: 'ferritin');
    expect(rows.map((r) => r['taken_on']), ['2026-09-04']);
  });

  group('custom marker definitions', () {
    test('round-trip, and no reference range is invented', () async {
      await LocalDb.putLabMarkerDef({
        'key': customLabMarkerKey('Lp(a)'),
        'label': 'Lp(a)',
        'unit': 'nmol/L',
        'category': LabCategory.lipids.name,
        'decimals': 0,
        'ref_low': null,
        'ref_high': null,
      });
      final defs = await LocalDb.labMarkerDefs();
      expect(defs.single['key'], 'custom_lp_a');
      expect(defs.single['unit'], 'nmol/L');
      expect(
        defs.single['ref_low'],
        isNull,
        reason: 'a marker the app knows nothing about gets no verdict',
      );
    });

    test('deleting a definition keeps the readings', () async {
      await LocalDb.putLabMarkerDef({
        'key': 'custom_lp_a',
        'label': 'Lp(a)',
        'unit': 'nmol/L',
        'category': LabCategory.lipids.name,
        'decimals': 0,
      });
      await LocalDb.putLabResult(
        marker: 'custom_lp_a',
        takenOn: '2026-03-04',
        value: 90,
        unit: 'nmol/L',
      );

      await LocalDb.deleteLabMarkerDef('custom_lp_a');

      expect(await LocalDb.labMarkerDefs(), isEmpty);
      final rows = await LocalDb.labResults(marker: 'custom_lp_a');
      expect(rows, hasLength(1));
      expect(
        rows.single['unit'],
        'nmol/L',
        reason: 'the row carries its own unit, so it stays readable',
      );
    });
  });

  test('report bounds round-trip, stay null when omitted, allow one side',
      () async {
    await LocalDb.putLabResult(
      marker: 'ferritin',
      takenOn: '2026-03-04',
      value: 42,
      unit: 'ng/mL',
    );
    expect((await LocalDb.labResults()).single['report_low'], isNull);
    expect((await LocalDb.labResults()).single['report_high'], isNull);

    await LocalDb.putLabResult(
      marker: 'ferritin',
      takenOn: '2026-03-04',
      value: 42,
      unit: 'ng/mL',
      reportLow: 30,
      reportHigh: 400,
    );
    expect((await LocalDb.labResults()).single['report_low'], 30);
    expect((await LocalDb.labResults()).single['report_high'], 400);

    await LocalDb.putLabResult(
      marker: 'ferritin',
      takenOn: '2026-03-04',
      value: 41,
      unit: 'ng/mL',
    );
    expect((await LocalDb.labResults()).single['report_low'], 30,
        reason: 'omitted bounds must not wipe a stored interval');
    expect((await LocalDb.labResults()).single['value'], 41);

    await LocalDb.putLabResult(
      marker: 'vitamin_d',
      takenOn: '2026-09-15',
      value: 37,
      unit: 'ng/mL',
      reportLow: 30,
      reportHigh: null,
    );
    expect((await LocalDb.labResults(marker: 'vitamin_d')).single['report_low'],
        30);
    expect((await LocalDb.labResults(marker: 'vitamin_d')).single['report_high'],
        isNull);
  });

  test('relocate is atomic and refuses a live destination', () async {
    await LocalDb.putLabResult(
      marker: 'ferritin',
      takenOn: '2026-03-04',
      value: 33,
      unit: 'ng/mL',
      reportLow: 30,
      reportHigh: 400,
    );
    await LocalDb.putLabResult(
      marker: 'ferritin',
      takenOn: '2026-09-15',
      value: 52,
      unit: 'ng/mL',
    );
    await expectLater(
      LocalDb.relocateLabResult(
        fromMarker: 'ferritin',
        fromTakenOn: '2026-03-04',
        toMarker: 'ferritin',
        toTakenOn: '2026-09-15',
        value: 33,
        unit: 'ng/mL',
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      (await LocalDb.labResults(marker: 'ferritin'))
          .map((r) => r['taken_on'])
          .toList(),
      ['2026-09-15', '2026-03-04'],
    );

    await LocalDb.relocateLabResult(
      fromMarker: 'ferritin',
      fromTakenOn: '2026-03-04',
      toMarker: 'ferritin',
      toTakenOn: '2026-04-01',
      value: 33,
      unit: 'ng/mL',
      reportLow: 30,
      reportHigh: 400,
    );
    final rows = await LocalDb.labResults(marker: 'ferritin');
    expect(rows.map((r) => r['taken_on']), ['2026-09-15', '2026-04-01']);
    expect(
      rows.firstWhere((r) => r['taken_on'] == '2026-04-01')['report_low'],
      30,
    );
  });

  test('changing a custom definition unit leaves stored units', () async {
    await LocalDb.putLabMarkerDef({
      'key': 'custom_kupfer',
      'label': 'Kupfer',
      'unit': 'µg/dL',
      'category': 'other',
      'decimals': 1,
    });
    await LocalDb.putLabResult(
      marker: 'custom_kupfer',
      takenOn: '2026-09-15',
      value: 90,
      unit: 'µg/dL',
    );
    await LocalDb.putLabMarkerDef({
      'key': 'custom_kupfer',
      'label': 'Kupfer (Serum)',
      'unit': 'µmol/L',
      'category': 'other',
      'decimals': 1,
    });
    expect((await LocalDb.labMarkerDefs()).single['label'], 'Kupfer (Serum)');
    expect(
      (await LocalDb.labResults(marker: 'custom_kupfer')).single['unit'],
      'µg/dL',
    );
  });

  test('fresh schema exposes nullable report bounds', () async {
    final db = await LocalDb.instance;
    final cols = {
      for (final c in await db.rawQuery('PRAGMA table_info(lab_result)'))
        c['name'],
    };
    expect(cols, containsAll(['report_low', 'report_high']));
    final health = await LocalDb.schemaHealth();
    expect(health['ok'], isTrue, reason: '$health');
  });

  test('upgrade from 54 adds report columns without inventing bounds', () async {
    const previous = 'openstrap_lab_result_test.db';
    const name = 'openstrap_lab_result_v54.db';
    await LocalDb.close();
    final path = p.join(await databaseFactory.getDatabasesPath(), name);
    await databaseFactory.deleteDatabase(path);
    final old = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 54,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE lab_result (
              marker TEXT NOT NULL,
              taken_on TEXT NOT NULL,
              value REAL NOT NULL,
              unit TEXT NOT NULL,
              note TEXT NOT NULL DEFAULT '',
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (marker, taken_on)
            )
          ''');
        },
      ),
    );
    await old.insert('lab_result', {
      'marker': 'ferritin',
      'taken_on': '2026-03-04',
      'value': 42.0,
      'unit': 'ng/mL',
      'note': 'fasted',
      'updated_at': 1,
    });
    await old.close();
    LocalDb.dbName = name;
    final row = (await LocalDb.labResults()).single;
    expect(row['value'], 42.0);
    expect(row['note'], 'fasted');
    expect(row['report_low'], isNull);
    expect(row['report_high'], isNull);
    await LocalDb.putLabResult(
      marker: 'ferritin',
      takenOn: '2026-03-04',
      value: 42,
      unit: 'ng/mL',
      reportLow: 15,
      reportHigh: null,
    );
    expect((await LocalDb.labResults()).single['report_low'], 15);
    expect((await LocalDb.labResults()).single['report_high'], isNull);
    await LocalDb.close();
    LocalDb.dbName = previous;
  });

  test('insert without replaceExisting is atomic and refuses a live key',
      () async {
    await LocalDb.putLabResult(
      marker: 'ferritin',
      takenOn: '2026-09-15',
      value: 52,
      unit: 'ng/mL',
    );
    await expectLater(
      LocalDb.putLabResult(
        marker: 'ferritin',
        takenOn: '2026-09-15',
        value: 99,
        unit: 'ng/mL',
        replaceExisting: false,
      ),
      throwsA(isA<StateError>()),
    );
    expect((await LocalDb.labResults()).single['value'], 52);
  });

  test('creating a custom def does not overwrite an existing key', () async {
    await LocalDb.putLabMarkerDef({
      'key': 'custom_kupfer',
      'label': 'Kupfer',
      'unit': 'µg/dL',
      'category': 'other',
      'decimals': 1,
    }, replaceExisting: false);
    await expectLater(
      LocalDb.putLabMarkerDef({
        'key': 'custom_kupfer',
        'label': 'Kupfer (Serum)',
        'unit': 'µmol/L',
        'category': 'other',
        'decimals': 1,
      }, replaceExisting: false),
      throwsA(isA<StateError>()),
    );
    expect((await LocalDb.labMarkerDefs()).single['label'], 'Kupfer');
    expect((await LocalDb.labMarkerDefs()).single['unit'], 'µg/dL');
  });

  group('LocalOpenBandRepository SQLite collisions', () {
    late AppState app;
    late LocalOpenBandRepository repository;

    setUp(() {
      app = AppState.forTesting();
      repository = LocalOpenBandRepository(app);
    });

    tearDown(() => app.dispose());

    test('concurrent new draws collide in one transaction', () async {
      const a = LabDraw(
        marker: 'hba1c',
        takenOn: '2026-02-02',
        value: 5.1,
        unit: '%',
      );
      const b = LabDraw(
        marker: 'hba1c',
        takenOn: '2026-02-02',
        value: 5.9,
        unit: '%',
      );
      Future<Object> attempt(LabDraw draw) async {
        try {
          await repository.saveLabDraw(draw);
          return 'ok';
        } catch (e) {
          return e;
        }
      }

      final out = await Future.wait([attempt(a), attempt(b)]);
      expect(out.where((e) => e == 'ok'), hasLength(1));
      expect(out.whereType<LabDrawCollision>(), hasLength(1));
      final rows = await LocalDb.labResults(marker: 'hba1c');
      expect(rows, hasLength(1));
      expect(rows.single['taken_on'], '2026-02-02');
      expect(rows.single['value'], anyOf(5.1, 5.9));
    });

    test('create does not overwrite a custom definition', () async {
      await repository.saveLabMarkerDef(
        const LabMarkerDef(
          key: 'custom_kupfer',
          label: 'Kupfer',
          unit: 'µg/dL',
          category: 'other',
          decimals: 1,
        ),
        create: true,
      );
      await expectLater(
        repository.saveLabMarkerDef(
          const LabMarkerDef(
            key: 'custom_kupfer',
            label: 'Kupfer (Serum)',
            unit: 'µmol/L',
            category: 'other',
            decimals: 1,
          ),
          create: true,
        ),
        throwsA(isA<LabMarkerCollision>()),
      );
      final snap = await repository.readLabs();
      expect(snap.custom.single.label, 'Kupfer');
      expect(snap.custom.single.unit, 'µg/dL');
    });
  });
}
