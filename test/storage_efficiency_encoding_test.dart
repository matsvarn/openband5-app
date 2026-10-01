import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/derive_prepare.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/models.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  late Directory temp;
  const fields = ['ax', 'ay', 'az', 'temp_ch2_c', 'temp_ch3_c', 'dyn_accel_g'];
  final start = DateTime(2026, 1, 5, 12).millisecondsSinceEpoch ~/ 1000;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('ob5-encoding-');
    await databaseFactory.setDatabasesPath(temp.path);
    PathProviderPlatform.instance = _Paths(temp.path);
    LocalDb.dbName = 'test.db';
  });
  tearDown(() async {
    await LocalDb.close();
    await temp.delete(recursive: true);
  });
  Future<List<Map<String, dynamic>>> read({int? after}) =>
      LocalDb.decodedOneHzBatchByRecTsRange(
        limit: 100,
        fromRecTs: start,
        toRecTs: start + 100,
        afterRecTs: after,
        afterCounter: after == null ? null : 1,
      );
  Future<void> ingest(int i, List<double?> values) => LocalDb.insertRecord(
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
      ax: values[0],
      ay: values[1],
      az: values[2],
      tempCh2C: values[3],
      tempCh3C: values[4],
      dynAccelG: values[5],
    ),
  ).then((_) {});

  test(
    'canonical ingest and decoded substrate preserve exact doubles and nulls',
    () async {
      final inputs = <List<double?>>[
        [-0.1234, 0.0001, 1.2345, 32.1234, -2.0011, 0.9876],
        [null, null, null, null, null, null],
        [0.123456789, 0.5, 1, 32, null, 0.2],
      ];
      for (var i = 0; i < inputs.length; i++) {
        await ingest(i, inputs[i]);
      }
      final db = await LocalDb.instance;
      final stored = await db.query('decoded_onehz', orderBy: 'rec_ts');
      expect(stored.map((r) => r['onehz_enc']), [1, 1, null]);
      expect(stored.first['ax'], -1234.0);
      final rows = await read();
      for (var i = 0; i < inputs.length; i++) {
        expect(fields.map((f) => rows[i][f]).toList(), inputs[i]);
      }
      final sub = substrateFromDecodedPage(rows, const []);
      expect(sub.ax.first, inputs.first[0]);
      expect(sub.ay.first, inputs.first[1]);
      expect(sub.az.first, inputs.first[2]);
      expect(sub.accelPresentAt(1), isFalse);
      expect(sub.ax.last, inputs.last[0]);
      expect((await read(after: start)).map((r) => r['ax']), [
        null,
        inputs.last[0],
      ]);
      // A replacement must replace both the marker and the whole sensor row.
      await ingest(0, inputs.last);
      expect(
        (await db.query(
          'decoded_onehz',
          where: 'rec_ts = ?',
          whereArgs: [start],
        )).single['onehz_enc'],
        isNull,
      );
      expect((await read()).first['ax'], inputs.last[0]);
    },
  );

  test(
    'mixed history conversion resumes across reopen and skips inexact rows',
    () async {
      final db = await LocalDb.instance;
      for (var i = 0; i < 5; i++) {
        await db.insert('decoded_onehz', {
          'ts_ms': (start + i) * 1000,
          'rec_ts': start + i,
          'counter': i + 1,
          'ax': i == 2 ? 0.123456789 : -0.1234,
          'ay': null,
          'az': 1.0001,
          'temp_ch2_c': 32.1234,
          'temp_ch3_c': null,
          'dyn_accel_g': 0.1234,
        });
      }
      final before = await read();
      expect(await LocalDb.compactLegacyOneHz(batchSize: 2, maxBatches: 1), 2);
      await LocalDb.close(); // Simulated termination between atomic batches.
      expect(await LocalDb.compactLegacyOneHz(batchSize: 2, maxBatches: 1), 1);
      expect(await LocalDb.compactLegacyOneHz(batchSize: 2, maxBatches: 1), 1);
      expect(await LocalDb.compactLegacyOneHz(), 0);
      expect(await read(), before);
      final rows = await (await LocalDb.instance).query(
        'decoded_onehz',
        orderBy: 'rec_ts',
      );
      expect(rows.map((r) => r['onehz_enc']), [1, 1, null, 1, 1]);
      expect(
        jsonDecode(
          (await LocalDb.computeFreshness(
                LocalDb.kOneHzCompactCursorKey,
              ))!['payload_json']
              as String,
        )['done'],
        isTrue,
      );
      expect(
        await LocalDb.computeFreshness(LocalDb.kOneHzVacuumKey),
        isNotNull,
      );
    },
  );

  test(
    'failed history batch rolls back sensor values and its durable cursor',
    () async {
      final db = await LocalDb.instance;
      for (var i = 0; i < 2; i++) {
        await db.insert('decoded_onehz', {
          'ts_ms': (start + i) * 1000,
          'rec_ts': start + i,
          'counter': i + 1,
          'ax': 0.1234,
        });
      }
      final before = await read();
      await db.execute(
        "CREATE TRIGGER interrupt_compaction BEFORE UPDATE ON decoded_onehz "
        "WHEN OLD.rec_ts = ${start + 1} BEGIN SELECT RAISE(ABORT, 'interrupted'); END",
      );
      await expectLater(
        LocalDb.compactLegacyOneHz(batchSize: 2, maxBatches: 1),
        throwsA(isA<DatabaseException>()),
      );
      expect(await read(), before);
      expect((await db.query('decoded_onehz')).map((r) => r['onehz_enc']), [
        null,
        null,
      ]);
      expect(
        await LocalDb.computeFreshness(LocalDb.kOneHzCompactCursorKey),
        isNull,
      );
      await db.execute('DROP TRIGGER interrupt_compaction');
      expect(await LocalDb.compactLegacyOneHz(batchSize: 2, maxBatches: 1), 2);
      expect(await read(), before);
    },
  );

  for (final version in [68, 69]) {
    test(
      'schema $version open adds missing encoding column without conversion',
      () async {
        final db = await LocalDb.instance;
        await db.insert('decoded_onehz', {
          'ts_ms': start * 1000,
          'rec_ts': start,
          'counter': 1,
          'ax': 0.1234,
        });
        await LocalDb.close();
        final old = await databaseFactory.openDatabase('${temp.path}/test.db');
        await old.execute('ALTER TABLE decoded_onehz DROP COLUMN onehz_enc');
        await old.setVersion(version);
        await old.close();
        final reopened = await LocalDb.instance;
        expect(await reopened.getVersion(), 69);
        final row = (await reopened.query('decoded_onehz')).single;
        expect(row['onehz_enc'], isNull);
        expect(row['ax'], 0.1234);
        expect(await read(), hasLength(1));
        await LocalDb.close();
        expect(
          (await (await LocalDb.instance).query('decoded_onehz')).single['ax'],
          0.1234,
        );
      },
    );
  }

  test('encoded selected-day export/import and old backups round-trip', () async {
    final values = [-0.1234, 0.0001, 1.2345, 32.1234, -2.0011, 0.9876];
    await ingest(0, values);
    final before = await read();
    final path = await LocalDb.exportDaysDb({
      dayLabelOf(DateTime.fromMillisecondsSinceEpoch(start * 1000)),
    });
    final db = await LocalDb.instance;
    await db.delete('decoded_onehz');
    await LocalDb.importFromDbFile(path);
    expect(await read(), before);
    expect((await db.query('decoded_onehz')).single['onehz_enc'], isNull);
    // A backup without the marker carries the original doubles.
    final backup = await databaseFactory.openDatabase('${temp.path}/legacy.db');
    await backup.execute(
      'CREATE TABLE decoded_onehz (device_id TEXT, ts_ms INTEGER, rec_ts INTEGER, counter INTEGER, ax REAL)',
    );
    await backup.insert('decoded_onehz', {
      'device_id': '',
      'ts_ms': (start + 1) * 1000,
      'rec_ts': start + 1,
      'counter': 2,
      'ax': 0.123456789,
    });
    await backup.close();
    await LocalDb.importFromDbFile('${temp.path}/legacy.db');
    expect((await read()).last['ax'], 0.123456789);
    expect(
      (await db.query('decoded_onehz', orderBy: 'rec_ts')).last['onehz_enc'],
      isNull,
    );
  });

  test(
    'vacuum request overrides threshold once and checkpoints through rawQuery',
    () async {
      final db = await LocalDb.instance;
      await LocalDb.putComputeFreshness(
        LocalDb.kOneHzVacuumKey,
        '{"requested":true}',
      );
      final pages = await db.rawQuery('PRAGMA journal_size_limit');
      expect(pages.single.values.single, 16 << 20);
      await LocalDb.vacuumIfBloated(minFreeBytes: 1 << 50);
      expect(await LocalDb.computeFreshness(LocalDb.kOneHzVacuumKey), isNull);
      final wal = File('${temp.path}/test.db-wal');
      if (await wal.exists()) expect(await wal.length(), lessThan(16 << 10));
      expect(await LocalDb.vacuumIfBloated(minFreeBytes: 1 << 50), 0);
      expect(
        (await db.rawQuery('PRAGMA quick_check')).single.values.single,
        'ok',
      );
    },
  );
}
