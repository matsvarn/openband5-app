// ALGO-91 POST-AUDIT REPAIR — the small fixes the Sep-22 audit pinned.
//
//   * `raw_blob`: every commitSyncBatch now persists the whole record stream
//     as one gzip blob INSIDE the ACK-gating transaction, so a decoder
//     revision can replay seconds the mapper dropped (the audit found
//     `raw_records` empty — successful v18 bytes were retained nowhere).
//   * `sync_ledger`: a row born already-acked no longer stamps created_at
//     AFTER its acked_at (5,446 rows in the capture read "acked before it
//     existed" by up to ~255 ms of stamp skew).
//   * nap notes count post-attribution-filter naps, not detector candidates.
//   * the movement refusal note reports the real 14-day frozen-floor gate.
//   * `buildProvenance` is what every persisted bundle carries.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/compute/substrate.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_audit91_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  // ── raw_blob ─────────────────────────────────────────────────────────────

  // A gen5-v18-shaped record: type 0x2F, version 0x18, counter u32 LE at
  // inner offset 3 — the layout `rawBlobRecords` slices back out.
  RawRecord v18(int counter) {
    final b = [
      0x2F, 0x18, 0x00,
      counter & 0xFF, (counter >> 8) & 0xFF, (counter >> 16) & 0xFF,
      (counter >> 24) & 0xFF,
      ...List<int>.filled(60, 0xAB),
    ];
    return RawRecord(
      counter: counter,
      packetType: 0x2F,
      hex: b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(),
      capturedAt: 1750000000000 + counter,
      recTs: 1750000000 + counter,
    );
  }

  group('raw_blob — the durable replay source', () {
    test('commitSyncBatch persists the whole record stream, compressed',
        () async {
      final raws = [v18(90001), v18(90002), v18(90003)];
      await LocalDb.commitSyncBatch(
        raws,
        <Sample?>[
          Sample(tsEpoch: 1750090001, counter: 90001, hr: 60),
          Sample(tsEpoch: 1750090002, counter: 90002, hr: 61),
          Sample(tsEpoch: 1750090003, counter: 90003, hr: 62),
        ],
      );
      final db = await LocalDb.instance;
      final rows = await db.query('raw_blob',
          where: 'first_counter = ?', whereArgs: [90001]);
      expect(rows, hasLength(1));
      expect(rows.single['n'], 3);
      expect(rows.single['last_counter'], 90003);
      // DEFLATE: three near-identical 67-byte frames must compress well.
      expect((rows.single['payload'] as List).length, lessThan(3 * 67));
    });

    test('rawBlobRecords round-trips hex, counter and packet type', () async {
      final raws = [v18(90101), v18(90102)];
      await LocalDb.commitSyncBatch(
        raws,
        <Sample?>[
          Sample(tsEpoch: 1750090101, counter: 90101, hr: 60),
          Sample(tsEpoch: 1750090102, counter: 90102, hr: 61),
        ],
      );
      final back = await LocalDb.rawBlobRecords();
      final mine =
          back.where((r) => r.counter >= 90101 && r.counter <= 90102).toList();
      expect(mine.map((r) => r.hex), raws.map((r) => r.hex),
          reason: 'byte-exact frames survive the compress/slice cycle');
      expect(mine.every((r) => r.packetType == 0x2F), isTrue);
    });

    test('re-committing the identical batch dedups the blob row', () async {
      final raws = [v18(90201), v18(90202)];
      final samples = <Sample?>[
        Sample(tsEpoch: 1750090201, counter: 90201, hr: 60),
        Sample(tsEpoch: 1750090202, counter: 90202, hr: 61),
      ];
      await LocalDb.commitSyncBatch(raws, samples);
      await LocalDb.commitSyncBatch(raws, samples);
      final db = await LocalDb.instance;
      final rows = await db.query('raw_blob',
          where: 'first_counter = ?', whereArgs: [90201]);
      expect(rows, hasLength(1),
          reason: 'the content-derived key makes a replayed batch a no-op');
    });
  });

  // ── sync_ledger stamp order ──────────────────────────────────────────────

  group('sync_ledger — a row born acked is not born after its ack', () {
    test('first write with an ackedAt clamps created_at to the ack', () async {
      final ack = 1750000000000; // long before `now`
      await LocalDb.upsertSyncLedgerEntry(
        chunkId: 'audit91-ledger',
        status: 'acked',
        ackedAt: ack,
      );
      final row = await LocalDb.syncLedgerEntry('audit91-ledger');
      expect(row, isNotNull);
      expect(row!['created_at'], ack,
          reason: 'the ack stamp predates this write; the row must not claim '
              'to have been created after it');
      expect(row['acked_at'], ack);
      expect((row['created_at'] as num) <= (row['acked_at'] as num), isTrue);
    });

    test('a later ack on an existing row keeps the original created_at',
        () async {
      await LocalDb.upsertSyncLedgerEntry(
        chunkId: 'audit91-ledger2',
        status: 'pending',
      );
      final first = await LocalDb.syncLedgerEntry('audit91-ledger2');
      await LocalDb.upsertSyncLedgerEntry(
        chunkId: 'audit91-ledger2',
        status: 'acked',
        ackedAt: 1750000000001,
      );
      final row = await LocalDb.syncLedgerEntry('audit91-ledger2');
      expect(row!['created_at'], first!['created_at'],
          reason: 'REPLACE is a merge, not a re-birth');
    });
  });

  // ── provenance stamp ─────────────────────────────────────────────────────

  test('buildProvenance names the exact code that produced a result', () {
    final p = buildProvenance();
    expect(p['algo_version'], kAlgoVersion);
    expect(p['analytics_pin'], kAnalyticsPin);
    expect(p['protocol_pin'], kProtocolPin);
    expect(p['schema_version'], LocalDb.schemaVersion);
  });

  // ── movement refusal note reports the REAL gate ──────────────────────────

  test('movement note says need=14 while the frozen floor is unenrolled', () {
    // |a| oscillates across 1 g so ENMO minutes exist, but the floor is not
    // yet frozen (dynFloorG null) — the refusal must name the edge's 14-day
    // gate, not analytics' 5-day enrollment minimum.
    const n = 7200;
    final ts = <int>[];
    final ax = <double>[];
    for (var i = 0; i < n; i++) {
      ts.add(1750000000 + i);
      ax.add(1.0 + 0.6 * math.sin(i * 2 * math.pi / 30));
    }
    final sub = Substrate(
      tsSec: ts,
      hr: List<int>.filled(n, 78),
      rrTsMs: const [],
      rrMs: const [],
      ax: ax,
      ay: List<double>.filled(n, 0),
      az: List<double>.filled(n, 0),
      spo2Red: List<int>.filled(n, 0),
      spo2Ir: List<int>.filled(n, 0),
      skinTemp: List<int>.filled(n, 0),
      skinContact: List<int>.filled(n, 0),
    );
    final bundle = <String, dynamic>{};
    DerivationEngine.applyDayActivity(
      bundle: bundle,
      scalars: <String, dynamic>{},
      daySub: sub,
      profile: const Profile(
          ageYears: 35, sex: 'm', weightKg: 75, heightCm: 178),
      sleepOnsetSec: 0,
      sleepOffsetSec: 0,
      dayStartSec: ts.first,
      dayCalendarEndSec: ts.last + 1,
      dataNowSec: ts.last + 1,
      dynFloorG: null, // still enrolling — the 14-day gate is not met
      dynHistoryDays: 5,
    );
    final movement = bundle['movement'] as Map<String, dynamic>;
    expect(movement['active_min'], isNull,
        reason: 'absent until the floor freezes — no constant fallback');
    expect(movement['note'], contains('need=14'));
    expect(movement['note'], contains('have=5'));
    expect(movement['note'], isNot(contains('need=5,')),
        reason: 'the analytics enrollment minimum must not leak through');
  });

  // ── nap note counts post-filter naps ─────────────────────────────────────

  test('a nocturnal-band bout is filtered AND the note stops claiming it', () {
    const midnight = 1750000800;
    // A still, low-HR block inside the nocturnal band (start >= midnight+20h).
    // The detector proposes it; the attribution filter reassigns it to the
    // main night; the note must not repeat the detector's "1 nap" claim.
    const len = 22 * 3600;
    final ts = <int>[];
    final hr = <int>[];
    final ax = <double>[];
    final az = <double>[];
    for (var i = 0; i < len; i++) {
      ts.add(midnight + i);
      final inNap = i >= 20 * 3600 && i < 20 * 3600 + 40 * 60;
      hr.add(inNap ? 56 : 78);
      if (inNap) {
        ax.add(0.0);
        az.add(1.0);
      } else {
        final rad = (i % 9) * 10.0 * math.pi / 180.0;
        ax.add(math.cos(rad));
        az.add(math.sin(rad));
      }
    }
    final s = Substrate(
      tsSec: ts,
      hr: hr,
      rrTsMs: const [],
      rrMs: const [],
      ax: ax,
      ay: List<double>.filled(len, 0),
      az: az,
      spo2Red: List<int>.filled(len, 0),
      spo2Ir: List<int>.filled(len, 0),
      skinTemp: List<int>.filled(len, 0),
      skinContact: List<int>.filled(len, 0),
    );
    final bundle = <String, dynamic>{};
    DerivationEngine.debugAttachNaps(
      bundle,
      <String, dynamic>{},
      s,
      0,
      0,
      attributionStartSec: midnight,
      attributionEndSec: midnight + 86400,
    );
    final naps = bundle['naps'] as Map<String, dynamic>;
    final note = naps['note'] as String;
    final count = naps['count'] as int;
    if (count == 0) {
      // The old bug forwarded the detector's "1 nap(s) via van Hees…" verbatim
      // beside an empty list. The rewritten note must say none qualified.
      expect(note, isNot(contains('nap(s) via')),
          reason: 'the detector\'s pre-filter count must not leak through');
      expect(note, contains('no qualifying nap'));
    } else {
      expect(note, contains('$count nap(s)'),
          reason: 'the note counts what survived attribution');
    }
  });
}
