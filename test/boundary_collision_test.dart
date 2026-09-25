// Boundary collisions: two consecutive 1 Hz records whose band timestamps
// straddle a second boundary — … (x-2).990, x.000, x.990 … — truncate onto the
// same second x and leave x-1 empty. `decoded_onehz` keys on the second, so
// the first record (row AND beats) used to be REPLACEd away. Measured on the
// owner's WHOOP 5: 9 of 277,036 records, every one this exact shape.
//
// The write path now moves that predecessor into the empty second, keeping
// its band time; the raw replay applies the same rule; and the schema 68 rung
// restores records lost before the fix from `raw_blob`.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart'
    show decodeGen5HistoricalSample;
import 'package:openstrap_edge/compute/substrate.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const x = 1790145777;

/// A v18 inner `Gen5V18Decoder` accepts, with the header fields under test.
Uint8List v18({
  required int index,
  required int unix,
  required int subsec,
  int hr = 70,
  List<int> rr = const [],
}) {
  final inner = Uint8List(kGen5V18InnerLen);
  final v = inner.buffer.asByteData();
  inner[0] = PacketType.historicalData;
  inner[1] = 18;
  inner[2] = 0x80;
  v.setUint32(3, index, Endian.little);
  v.setUint32(7, unix, Endian.little);
  v.setUint16(11, subsec, Endian.little);
  inner[14] = hr;
  inner[15] = rr.length;
  for (var i = 0; i < rr.length; i++) {
    v.setInt16(16 + 2 * i, rr[i], Endian.little);
  }
  v.setFloat32(33, 0.5, Endian.little);
  v.setFloat32(45, 1.0, Endian.little);
  v.setInt16(65, 3057, Endian.little);
  return inner;
}

String hexOf(Uint8List b) =>
    [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();

/// The owner's measured shape: A at (x-2).990, B at x.000 (a +10 ms step
/// across the boundary), C at x.990, D at (x+1).990.
final a = v18(index: 100, unix: x - 2, subsec: 32440, hr: 71, rr: [800]);
final b = v18(index: 101, unix: x, subsec: 0, hr: 72, rr: [700, 726]);
final c = v18(index: 102, unix: x, subsec: 32440, hr: 73, rr: [810]);
final d = v18(index: 103, unix: x + 1, subsec: 32440, hr: 74, rr: [790]);

Future<void> commit(List<Uint8List> inners) {
  final samples = [for (final i in inners) decodeGen5HistoricalSample(i)!];
  return LocalDb.commitSyncBatch(
    [
      for (var k = 0; k < inners.length; k++)
        RawRecord(
          counter: samples[k].counter,
          packetType: PacketType.historicalData,
          hex: hexOf(inners[k]),
          capturedAt: 0,
          recTs: samples[k].tsEpoch,
        ),
    ],
    samples,
    deviceFamily: 'gen5',
  );
}

Future<List<Map<String, Object?>>> rows() async =>
    (await LocalDb.instance).query(
      'decoded_onehz',
      columns: ['rec_ts', 'ts_ms', 'counter', 'hr', 'ts_subsec'],
      orderBy: 'ts_ms',
    );

Future<List<Map<String, Object?>>> beats() async =>
    (await LocalDb.instance).query(
      'decoded_rr',
      columns: [
        'rec_ts',
        'ts_ms',
        'beat_index',
        'rr_ms',
        'rr_ts_ms',
        'beat_ts_ms',
      ],
      orderBy: 'ts_ms, beat_index',
    );

Future<void> fresh(String name) async {
  LocalDb.dbName = name;
  await LocalDb.close();
  final db = await LocalDb.instance;
  for (final t in ['decoded_rr', 'decoded_onehz', 'raw_blob']) {
    await db.delete(t);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  tearDown(() async => LocalDb.close());

  group('isBoundaryCollision', () {
    test('a ~1 s pair inside one second is a split pair', () {
      expect(isBoundaryCollision(prevSubsec: 0, subsec: 32440), isTrue);
      expect(isBoundaryCollision(prevSubsec: 327, subsec: 32440), isTrue);
    });
    test('two readings well inside one second are not', () {
      expect(isBoundaryCollision(prevSubsec: 16384, subsec: 32440), isFalse);
      expect(isBoundaryCollision(prevSubsec: null, subsec: 32440), isFalse);
      expect(isBoundaryCollision(prevSubsec: 0, subsec: null), isFalse);
      // Already moved (sub-second past a whole second): never again.
      expect(isBoundaryCollision(prevSubsec: 32768, subsec: 32440), isFalse);
    });
  });

  group('the write keeps both records of a split pair', () {
    const expected = [
      {'rec_ts': x - 2, 'counter': 100, 'hr': 71, 'ts_subsec': 32440},
      // B moved into the empty second; band time = rec_ts + 32768/32768 = x.
      {'rec_ts': x - 1, 'counter': 101, 'hr': 72, 'ts_subsec': 32768},
      {'rec_ts': x, 'counter': 102, 'hr': 73, 'ts_subsec': 32440},
      {'rec_ts': x + 1, 'counter': 103, 'hr': 74, 'ts_subsec': 32440},
    ];

    void expectFixed(List<Map<String, Object?>> r) {
      expect([
        for (final m in r)
          {
            'rec_ts': m['rec_ts'],
            'counter': m['counter'],
            'hr': m['hr'],
            'ts_subsec': m['ts_subsec'],
          },
      ], expected);
      for (final m in r) {
        expect(m['ts_ms'], (m['rec_ts'] as int) * 1000);
      }
    }

    Future<void> expectBeatsOfB() async {
      final bBeats = [
        for (final m in await beats())
          if (m['rec_ts'] == x - 1) m,
      ];
      expect(bBeats.map((m) => m['rr_ms']), [700, 726]);
      // The whole-second column follows the row…
      expect(bBeats.map((m) => m['rr_ts_ms']), [
        (x - 1) * 1000,
        (x - 1) * 1000,
      ]);
      expect(bBeats.map((m) => m['ts_ms']), [(x - 1) * 1000, (x - 1) * 1000]);
      // …the measured instant does not: still the band's x.000.
      expect(bBeats.map((m) => m['beat_ts_ms']), beatTimesMs(x, 0, [700, 726]));
    }

    test('in one commit', () async {
      await fresh('boundary_one.db');
      await commit([a, b, c, d]);
      expectFixed(await rows());
      await expectBeatsOfB();
      // C's own beats stay on x.
      expect(
        [
          for (final m in await beats())
            if (m['rec_ts'] == x) m['rr_ms'],
        ],
        [810],
      );
    });

    test('across commits — the predecessor already committed', () async {
      await fresh('boundary_two.db');
      await commit([a, b]);
      await commit([c, d]);
      expectFixed(await rows());
      await expectBeatsOfB();
    });

    test('a re-flood of the same records changes nothing', () async {
      await fresh('boundary_reflood.db');
      await commit([a, b, c, d]);
      final before = await beats();
      await commit([a, b, c, d]);
      expectFixed(await rows());
      expect(await beats(), before);
      // Split re-delivery: the batch ends on B, then the rest. Every commit
      // is its own durable state (a crash can land between them), so each is
      // checked, not just the last.
      await commit([a, b]);
      expectFixed(await rows());
      expect(await beats(), before);
      await commit([c, d]);
      expectFixed(await rows());
      expect(await beats(), before);
    });

    test('the moved record re-delivered alone keeps its successor', () async {
      await fresh('boundary_alone.db');
      await commit([a, b, c, d]);
      final before = await beats();
      for (final writeB in [
        () => commit([b]),
        () {
          final s = decodeGen5HistoricalSample(b)!;
          return LocalDb.insertRecord(
            RawRecord(
              counter: s.counter,
              packetType: PacketType.historicalData,
              hex: hexOf(b),
              capturedAt: 0,
              recTs: s.tsEpoch,
            ),
            s,
          );
        },
      ]) {
        await writeB();
        expectFixed(await rows());
        expect(await beats(), before);
      }
    });

    test('a normal 1 Hz run is untouched', () async {
      await fresh('boundary_normal.db');
      await commit([
        v18(index: 1, unix: x, subsec: 32440),
        v18(index: 2, unix: x + 1, subsec: 32440),
        v18(index: 3, unix: x + 2, subsec: 32440),
      ]);
      final r = await rows();
      expect(r.map((m) => m['rec_ts']), [x, x + 1, x + 2]);
      expect(r.map((m) => m['ts_subsec']), [32440, 32440, 32440]);
    });
  });

  group('anything else still resolves newest-wins, as before', () {
    test('the second before is taken', () async {
      await fresh('boundary_taken.db');
      await commit([
        v18(index: 100, unix: x - 1, subsec: 16384, hr: 71),
        v18(index: 101, unix: x, subsec: 0, hr: 72),
        v18(index: 102, unix: x, subsec: 32440, hr: 73),
      ]);
      final r = await rows();
      expect(r.map((m) => m['counter']), [100, 102]);
      expect(r.map((m) => m['rec_ts']), [x - 1, x]);
    });

    test('the pair is not ~1 s apart on the band clock', () async {
      await fresh('boundary_half.db');
      await commit([
        v18(index: 100, unix: x - 2, subsec: 32440),
        v18(index: 101, unix: x, subsec: 16384),
        v18(index: 102, unix: x, subsec: 32440),
      ]);
      expect((await rows()).map((m) => m['counter']), [100, 102]);
    });

    test('the records are not consecutive', () async {
      await fresh('boundary_gap.db');
      await commit([
        v18(index: 100, unix: x - 2, subsec: 32440),
        v18(index: 101, unix: x, subsec: 0),
        v18(index: 103, unix: x, subsec: 32440),
      ]);
      expect((await rows()).map((m) => m['counter']), [100, 103]);
    });
  });

  group('the raw replay lands on the stored rows', () {
    test('keys, values and re-flooded duplicates', () async {
      await fresh('boundary_replay.db');
      await commit([a, b, c, d]);
      final stored = await rows();
      final sub = decodeSubstrate([
        for (final i in [a, b, c, d, b, c]) hexOf(i),
      ]);
      expect(sub.tsSec, [for (final m in stored) m['rec_ts']]);
      expect(sub.hr, [for (final m in stored) m['hr']]);
    });

    test('B\'s replayed beats sit where the store put them', () {
      final sub = decodeSubstrate([
        for (final i in [a, b, c, d]) hexOf(i),
      ]);
      final placed = beatTimesMs(x, 0, [700, 726]);
      for (final t in placed) {
        expect(sub.rrTsMs, contains(t!.toDouble()));
      }
    });
  });

  group('schema 68 repair', () {
    Future<void> losePredecessor() async {
      // The pre-fix state: B REPLACEd away, x-1 empty, bytes still in the blob.
      final db = await LocalDb.instance;
      await db.delete(
        'decoded_rr',
        where: 'ts_ms = ?',
        whereArgs: [(x - 1) * 1000],
      );
      await db.delete(
        'decoded_onehz',
        where: 'ts_ms = ?',
        whereArgs: [(x - 1) * 1000],
      );
    }

    // The only caller is the rung, so the repair is exercised the way the
    // phone runs it: a v67 file reopened by this build, inside onUpgrade.
    Future<void> upgradeFrom67() async {
      await (await LocalDb.instance).execute('PRAGMA user_version = 67');
      await LocalDb.close();
      final db = await LocalDb.instance;
      expect(
        (await db.rawQuery('PRAGMA user_version')).first.values.first,
        LocalDb.schemaVersion,
      );
    }

    test('restores a lost record from raw_blob, idempotently', () async {
      await fresh('boundary_repair.db');
      await commit([a, b, c, d]);
      final fixedRows = await rows();
      final fixedBeats = await beats();
      await losePredecessor();
      expect((await rows()).length, 3);

      await upgradeFrom67();
      expect(await rows(), fixedRows);
      expect(await beats(), fixedBeats);

      await upgradeFrom67();
      expect(await rows(), fixedRows);
      expect(await beats(), fixedBeats);
    });

    test('finds the right frame when a reboot reused the counters', () async {
      await fresh('boundary_repair_epochs.db');
      // An earlier band epoch with the same record indices, a day before —
      // committed first, so its blob is the one a naive lookup meets first.
      await commit([
        for (var i = 0; i < 4; i++)
          v18(index: 100 + i, unix: x - 86400 + i, subsec: 32440),
      ]);
      await commit([a, b, c, d]);
      final fixedRows = await rows();
      await losePredecessor();
      await upgradeFrom67();
      expect(await rows(), fixedRows);
    });

    test('an unreadable blob is skipped, not fatal to the upgrade', () async {
      await fresh('boundary_repair_corrupt.db');
      await commit([a, b, c, d]);
      final fixedRows = await rows();
      await losePredecessor();
      await (await LocalDb.instance).insert('raw_blob', {
        'device_id': '',
        'first_counter': 90,
        'last_counter': 110,
        'first_ts': 0,
        'n': 1,
        'codec': 1,
        'payload': Uint8List.fromList([1, 2, 3, 4]),
        'captured_at': 0,
      });
      await upgradeFrom67();
      expect(await rows(), fixedRows);
    });

    test(
      'a write that fails mid-repair rolls back, keeping record n',
      () async {
        await fresh('boundary_repair_rollback.db');
        await commit([a, b, c, d]);
        await losePredecessor();
        final before = await rows();
        final beatsBefore = await beats();
        // Fail the SECOND write (record n = 102), after the first has already
        // evicted it from x.
        await (await LocalDb.instance).execute(
          'CREATE TRIGGER fail_repair BEFORE INSERT ON decoded_onehz '
          'WHEN NEW.counter = 102 BEGIN SELECT RAISE(ABORT, \'boom\'); END',
        );
        await upgradeFrom67();
        await (await LocalDb.instance).execute('DROP TRIGGER fail_repair');
        expect(await rows(), before);
        expect(await beats(), beatsBefore);
      },
    );

    test('leaves an honest hole when the bytes are gone', () async {
      await fresh('boundary_repair_nobytes.db');
      await commit([a, b, c, d]);
      await losePredecessor();
      await (await LocalDb.instance).delete('raw_blob');
      final before = await rows();
      await upgradeFrom67();
      expect(await rows(), before);
    });

    test('never matches a real drift hole (one record apart)', () async {
      await fresh('boundary_repair_drift.db');
      // (x-2).990 → x.010: consecutive records, a genuine uncovered second.
      await commit([
        v18(index: 100, unix: x - 2, subsec: 32440),
        v18(index: 101, unix: x, subsec: 327),
        v18(index: 102, unix: x + 1, subsec: 327),
      ]);
      final before = await rows();
      expect(before.map((m) => m['rec_ts']), [x - 2, x, x + 1]);
      await upgradeFrom67();
      expect(await rows(), before);
    });
  });
}
