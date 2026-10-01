import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

// Schema 68's decoded ledger: deliberately created without the encoding marker,
// and never opened through LocalDb (which would migrate it to the new schema).
const _oldDdl = '''CREATE TABLE decoded_onehz (
  device_id TEXT NOT NULL DEFAULT '', ts_ms INTEGER NOT NULL DEFAULT 0,
  rec_ts INTEGER, counter INTEGER NOT NULL, hr INTEGER,
  ax REAL, ay REAL, az REAL, spo2_red_raw INTEGER, spo2_ir_raw INTEGER,
  skin_temp_raw INTEGER, step_count INTEGER, step_cadence INTEGER,
  activity_class INTEGER, skin_temp_c REAL, on_wrist INTEGER, hr_valid INTEGER,
  hr_alt INTEGER, ambient_raw INTEGER, device_family TEXT, source TEXT,
  temp_ch2_c REAL, temp_ch3_c REAL, signal_quality_logvar REAL, dyn_accel_g REAL,
  PRIMARY KEY (device_id, ts_ms)
)''';

void main() {
  late Directory temp;
  late PathProviderPlatform originalPaths;
  const fields = ['ax', 'ay', 'az', 'temp_ch2_c', 'temp_ch3_c', 'dyn_accel_g'];
  final start = DateTime(2026, 1, 5, 12).millisecondsSinceEpoch ~/ 1000;
  final values = <List<double?>>[
    [-0.1234, 0.0001, 1.2345, 32.1234, -2.0011, 0.9876],
    [null, null, null, null, null, null],
    [0.123456789, 0.5, 1, 32, null, 0.2],
  ];
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('ob5-export-units-');
    await databaseFactory.setDatabasesPath(temp.path);
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    LocalDb.dbName = 'test.db';
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      await LocalDb.insertRecord(
        RawRecord(
          counter: i + 1,
          hex: 'synthetic-$i',
          recTs: start + i,
          capturedAt: (start + i) * 1000,
        ),
        Sample(
          counter: i + 1,
          tsEpoch: start + i,
          hr: 60,
          rrIntervalsMs: const [],
          ax: v[0],
          ay: v[1],
          az: v[2],
          tempCh2C: v[3],
          tempCh3C: v[4],
          dynAccelG: v[5],
        ),
      );
    }
  });
  tearDown(() async {
    await LocalDb.close();
    PathProviderPlatform.instance = originalPaths;
    await temp.delete(recursive: true);
  });
  Future<List<Map<String, dynamic>>> liveRead() =>
      LocalDb.decodedOneHzBatchByRecTsRange(
        limit: 100,
        fromRecTs: start,
        toRecTs: start + 100,
      );
  List<List<Object?>> sensorValues(List<Map<String, Object?>> rows) => [
    for (final row in rows) [for (final f in fields) row[f]],
  ];

  for (final selected in [false, true]) {
    test('${selected ? 'selected-day' : 'full backup'} export carries physical '
        'units through old and current imports', () async {
      final db = await LocalDb.instance;
      final before = await liveRead();
      expect(sensorValues(before), values);
      expect(
        (await db.query(
          'decoded_onehz',
          orderBy: 'rec_ts',
        )).map((r) => r['onehz_enc']),
        [1, 1, null],
      );
      final path = selected
          ? await LocalDb.exportDaysDb({
              dayLabelOf(DateTime.fromMillisecondsSinceEpoch(start * 1000)),
            })
          : await LocalDb.exportCopy();
      final exported = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        final rows = await exported.query('decoded_onehz', orderBy: 'rec_ts');
        expect(rows.map((r) => r['onehz_enc']), everyElement(isNull));
        expect(sensorValues(rows), sensorValues(before));
      } finally {
        await exported.close();
      }
      expect(await liveRead(), before);
      expect(
        (await db.query(
          'decoded_onehz',
          orderBy: 'rec_ts',
        )).map((r) => r['onehz_enc']),
        [1, 1, null],
      );

      final old = await databaseFactory.openDatabase('${temp.path}/old.db');
      try {
        await old.execute(_oldDdl);
        await old.setVersion(68);
        final columns = (await old.rawQuery(
          'PRAGMA table_info(decoded_onehz)',
        )).map((r) => r['name'] as String).toList();
        expect(columns, isNot(contains('onehz_enc')));
        // An older importer copies only the columns its destination has.
        await old.execute('ATTACH DATABASE ? AS exported', [path]);
        await old.transaction((txn) async {
          final cols = columns.join(', ');
          await txn.execute(
            'INSERT INTO decoded_onehz ($cols) '
            'SELECT $cols FROM exported.decoded_onehz',
          );
        });
        expect(
          sensorValues(await old.query('decoded_onehz', orderBy: 'rec_ts')),
          sensorValues(before),
        );
      } finally {
        await old.close();
      }
      await db.delete('decoded_onehz');
      await LocalDb.importFromDbFile(path);
      expect(await liveRead(), before);
      expect(
        (await db.query('decoded_onehz')).map((r) => r['onehz_enc']),
        everyElement(isNull),
      );
    });
  }

  test(
    'failed destination decoding deletes the export and preserves live rows',
    () async {
      final db = await LocalDb.instance;
      final before = await liveRead();
      // VACUUM INTO copies this trigger; the second row aborts destination UPDATE.
      await db.execute(
        'CREATE TRIGGER interrupt_export BEFORE UPDATE ON '
        'decoded_onehz WHEN OLD.rec_ts = ${start + 1} '
        "BEGIN SELECT RAISE(ABORT, 'interrupted export'); END",
      );
      await expectLater(
        LocalDb.exportCopy(),
        throwsA(isA<DatabaseException>()),
      );
      expect(await liveRead(), before);
      expect(
        await temp
            .list()
            .where((f) => f.path.contains('openstrap_export_'))
            .toList(),
        isEmpty,
      );
    },
  );
}
