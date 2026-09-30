// day_result.source — per-row provenance, independent of metric_series_version.
//
// metric_series_version is date-only and can describe another payload. A
// partial write, an empty series, or a rolled-back algo version must still
// keep the source supplied with THAT day_result row. Never infer or backfill
// from the series stamp. Run against REAL sqflite_ffi.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';

/// Schema 65 `day_result` — no `source` column.
const _v65DayResultDdl = '''
  CREATE TABLE day_result (
    day_id TEXT NOT NULL,
    algo_version INTEGER NOT NULL,
    payload_json TEXT NOT NULL,
    window_json TEXT NOT NULL DEFAULT '{}',
    computed_at INTEGER NOT NULL,
    finalized INTEGER NOT NULL DEFAULT 0,
    rhr REAL,
    rmssd REAL,
    readiness REAL,
    skipped INTEGER NOT NULL DEFAULT 0,
    partial INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (day_id, algo_version)
  )
''';

const _metricSeriesDdl = '''
  CREATE TABLE metric_series (
    date TEXT NOT NULL,
    key TEXT NOT NULL,
    value REAL,
    PRIMARY KEY (date, key)
  )
''';

const _metricSeriesVersionDdl = '''
  CREATE TABLE metric_series_version (
    date TEXT PRIMARY KEY,
    algo_version INTEGER NOT NULL,
    source TEXT
  )
''';

Future<String> _dbPath(String name) async =>
    p.join(await databaseFactory.getDatabasesPath(), name);

Future<void> _seedOldDb(
  String name,
  int version, {
  Future<void> Function(Database db)? seedRows,
}) async {
  final path = await _dbPath(name);
  await databaseFactory.deleteDatabase(path);
  final db = await databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onCreate: (db, _) async {
        await db.execute(_v65DayResultDdl);
        await db.execute(_metricSeriesDdl);
        await db.execute(_metricSeriesVersionDdl);
      },
    ),
  );
  if (seedRows != null) await seedRows(db);
  await db.close();
}

/// A pre-source day_result plus a series stamp that would be the WRONG answer
/// to copy. Migration/repair must leave the day_result row NULL.
Future<void> _seedUnattributedDay(Database db) async {
  await db.insert('day_result', {
    'day_id': '2026-03-01',
    'algo_version': 70,
    'payload_json': '{}',
    'window_json': '{}',
    'computed_at': 1,
    'finalized': 0,
    'skipped': 0,
    'partial': 0,
    'rhr': 54.0,
  });
  await db.insert('metric_series', {
    'date': '2026-03-01',
    'key': 'rhr',
    'value': 54.0,
  });
  await db.insert('metric_series_version', {
    'date': '2026-03-01',
    'algo_version': 70,
    'source': 'whoop_export',
  });
}

Future<int> _openThroughLocalDb(String name) async {
  await LocalDb.close();
  LocalDb.lastRebuild = null;
  LocalDb.dbName = name;
  final db = await LocalDb.instance;
  expect(
    LocalDb.lastRebuild,
    isNull,
    reason: 'the upgrade bricked and fell back to quarantine-and-rebuild: '
        '${LocalDb.lastRebuild?.cause}',
  );
  final rows = await db.rawQuery('PRAGMA user_version');
  return (rows.first.values.first as num?)?.toInt() ?? -1;
}

Future<void> _useFreshDb(String name) async {
  await LocalDb.close();
  LocalDb.lastRebuild = null;
  LocalDb.dbName = name;
  await databaseFactory.deleteDatabase(await _dbPath(name));
}

Future<Map<String, Object?>> _sourceCol(Database db) async {
  final cols = await db.rawQuery('PRAGMA table_info(day_result)');
  return cols.firstWhere((c) => c['name'] == 'source');
}

Future<Map<String, Object?>> _dayRow(Database db, String day, int v) async {
  final rows = await db.query(
    'day_result',
    where: 'day_id = ? AND algo_version = ?',
    whereArgs: [day, v],
  );
  return rows.single;
}

Future<Map<String, Object?>> _stamp(Database db, String day) async {
  final rows = await db.query(
    'metric_series_version',
    where: 'date = ?',
    whereArgs: [day],
  );
  return rows.single;
}

void main() {
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

  test('fresh schema has nullable day_result.source with no default', () async {
    const name = 'day_result_source_fresh.db';
    created.add(name);
    await _useFreshDb(name);
    final db = await LocalDb.instance;
    expect(LocalDb.schemaVersion, greaterThanOrEqualTo(66));
    expect(
      (await db.rawQuery('PRAGMA user_version')).first.values.first,
      LocalDb.schemaVersion,
    );
    final col = await _sourceCol(db);
    expect(col['type'], 'TEXT');
    expect(col['notnull'], 0);
    expect(col['dflt_value'], isNull);
  });

  test(
    'v65 upgrade adds source, does not backfill from metric_series_version, '
    'and is idempotent',
    () async {
      const name = 'day_result_source_from_65.db';
      created.add(name);
      await _seedOldDb(name, 65, seedRows: _seedUnattributedDay);

      Future<void> reopenAndCheck() async {
        final version = await _openThroughLocalDb(name);
        expect(version, LocalDb.schemaVersion);
        final db = await LocalDb.instance;
        final col = await _sourceCol(db);
        expect(col['type'], 'TEXT');
        expect(col['notnull'], 0);
        expect(col['dflt_value'], isNull);
        final row = await _dayRow(db, '2026-03-01', 70);
        expect(row['payload_json'], '{}');
        expect(row['rhr'], 54.0);
        expect(
          row['source'],
          isNull,
          reason: 'must not copy metric_series_version.source',
        );
        expect((await _stamp(db, '2026-03-01'))['source'], 'whoop_export');
      }

      await reopenAndCheck();
      await reopenAndCheck();
    },
  );

  test(
    'same-version repair adds missing source, does not backfill, idempotent',
    () async {
      const name = 'day_result_source_repair_66.db';
      created.add(name);
      expect(LocalDb.schemaVersion, greaterThanOrEqualTo(66));
      await _seedOldDb(
        name,
        LocalDb.schemaVersion,
        seedRows: _seedUnattributedDay,
      );

      Future<void> reopenAndCheck() async {
        final version = await _openThroughLocalDb(name);
        expect(version, LocalDb.schemaVersion);
        final db = await LocalDb.instance;
        final col = await _sourceCol(db);
        expect(col['notnull'], 0);
        expect(col['dflt_value'], isNull);
        expect((await _dayRow(db, '2026-03-01', 70))['source'], isNull);
        expect((await _stamp(db, '2026-03-01'))['source'], 'whoop_export');
      }

      await reopenAndCheck();
      await reopenAndCheck();
    },
  );

  test(
    'partial and empty-series writes keep their own source; series stamp '
    'unchanged',
    () async {
      const name = 'day_result_source_partial_empty.db';
      created.add(name);
      await _useFreshDb(name);
      const day = '2026-04-01';

      await LocalDb.putDayResult(
        dayId: day,
        algoVersion: 80,
        payloadJson: '{}',
        windowJson: '{}',
        source: 'band',
        series: const {'rhr': 51},
      );
      final db = await LocalDb.instance;
      expect((await _dayRow(db, day, 80))['source'], 'band');
      expect((await _stamp(db, day))['source'], 'band');
      expect((await _stamp(db, day))['algo_version'], 80);

      await LocalDb.putDayResult(
        dayId: day,
        algoVersion: 80,
        payloadJson: '{"partial":true}',
        windowJson: '{}',
        partial: true,
        source: 'cloud_v2',
        series: const {'rhr': 99},
      );
      expect((await _dayRow(db, day, 80))['source'], 'cloud_v2');
      expect(
        (await _stamp(db, day))['source'],
        'band',
        reason: 'partial must not move the series stamp',
      );
      expect((await _stamp(db, day))['algo_version'], 80);

      await LocalDb.putDayResult(
        dayId: day,
        algoVersion: 80,
        payloadJson: '{}',
        windowJson: '{}',
        source: 'whoop_export',
      );
      expect((await _dayRow(db, day, 80))['source'], 'whoop_export');
      expect(
        (await _stamp(db, day))['source'],
        'band',
        reason: 'empty series must not move the series stamp',
      );
      expect((await _stamp(db, day))['algo_version'], 80);
    },
  );

  test('same-version replacement with null removes the prior claim', () async {
    const name = 'day_result_source_null_replace.db';
    created.add(name);
    await _useFreshDb(name);
    const day = '2026-05-01';

    await LocalDb.putDayResult(
      dayId: day,
      algoVersion: 81,
      payloadJson: '{}',
      windowJson: '{}',
      source: 'band',
      series: const {'rhr': 50},
    );
    final db = await LocalDb.instance;
    expect((await _dayRow(db, day, 81))['source'], 'band');

    await LocalDb.putDayResult(
      dayId: day,
      algoVersion: 81,
      payloadJson: '{}',
      windowJson: '{}',
      source: null,
      series: const {'rhr': 51},
    );
    expect((await _dayRow(db, day, 81))['source'], isNull);
  });

  test(
    'lower-version rollback leaves the higher row provenance intact',
    () async {
      const name = 'day_result_source_rollback.db';
      created.add(name);
      await _useFreshDb(name);
      const day = '2026-06-01';

      await LocalDb.putDayResult(
        dayId: day,
        algoVersion: 90,
        payloadJson: '{"v":90}',
        windowJson: '{}',
        source: 'whoop_export',
        series: const {'rhr': 54},
      );
      await LocalDb.putDayResult(
        dayId: day,
        algoVersion: 89,
        payloadJson: '{"v":89}',
        windowJson: '{}',
        source: 'band',
        series: const {'rhr': 55},
      );

      final db = await LocalDb.instance;
      expect((await _dayRow(db, day, 90))['source'], 'whoop_export');
      expect((await _dayRow(db, day, 89))['source'], 'band');
      // Series stamp is date-only and follows the last non-partial series
      // write — that existing behaviour is unchanged, and is why day_result
      // must keep its own source.
      expect((await _stamp(db, day))['algo_version'], 89);
      expect((await _stamp(db, day))['source'], 'band');
    },
  );
}
