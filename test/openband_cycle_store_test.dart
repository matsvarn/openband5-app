import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/cycle_store.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/openband/cycle_data.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _now = DateTime(2026, 9, 15, 12);

const _settings = CycleSettings(
  enabled: true,
  estimatesEnabled: true,
  lengthReviewEnabled: false,
);

var _dbSeq = 0;

Future<Database> _open() async {
  final name = 'cycle_store_${_dbSeq++}.db';
  final path = p.join(await databaseFactory.getDatabasesPath(), name);
  await databaseFactory.deleteDatabase(path);
  return databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
            CREATE TABLE cycle_log (
              date TEXT PRIMARY KEY,
              kind TEXT NOT NULL,
              note TEXT
            )
          ''');
        await db.execute('''
            CREATE TABLE cycle_symptom (
              date TEXT PRIMARY KEY,
              symptoms_json TEXT NOT NULL,
              note TEXT,
              updated_at INTEGER
            )
          ''');
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  var invalidations = 0;

  Future<void> bindProductionInvalidate(DatabaseExecutor txn) =>
      LocalDb.invalidateCycleContext(txn);

  setUp(() async {
    invalidations = 0;
    CycleStore.invalidateCycleContext = (_) async {
      invalidations++;
    };
    db = await _open();
  });

  tearDown(() async {
    CycleStore.invalidateCycleContext = bindProductionInvalidate;
    final path = db.path;
    await db.close();
    await databaseFactory.deleteDatabase(path);
  });

  Future<void> seedStart(String date, {String kind = kCycleStartKind, String? note}) =>
      db.insert('cycle_log', {'date': date, 'kind': kind, 'note': note});

  test('fixture four starts: median 28 MAD 4, day 23, range 17–25 Sep', () async {
    for (final date in [
      '2026-06-01',
      '2026-06-29',
      '2026-07-31',
      '2026-08-24',
    ]) {
      await seedStart(date);
    }
    final snap = await CycleStore.read(db, day: '2026-09-15', settings: _settings);
    expect(snap.cycleDay, 23);
    expect(snap.estimate.gapCount, 3);
    expect(snap.estimate.medianDays, 28);
    expect(snap.estimate.madDays, 4);
    expect(snap.estimate.from, '2026-09-17');
    expect(snap.estimate.to, '2026-09-25');
    expect(snap.estimate.point, '2026-09-21');
  });

  test('one and two starts match missing vs point-only', () async {
    await seedStart('2026-08-24');
    var snap = await CycleStore.read(db, day: '2026-09-15', settings: _settings);
    expect(snap.estimate.availability, CycleEstimateAvailability.missing);
    await seedStart('2026-07-27');
    snap = await CycleStore.read(db, day: '2026-09-15', settings: _settings);
    expect(snap.estimate.reason, CycleEstimateReason.availablePoint);
    expect(snap.estimate.madDays, isNull);
    expect(snap.estimate.point, '2026-09-21');
  });

  test('same-day duplicate conflicts; note update keeps the date', () async {
    const original = CycleStart(date: '2026-09-10', kind: kCycleStartKind);
    expect(
      (await CycleStore.saveStart(db, original, now: _now)).start,
      original,
    );
    final dup = await CycleStore.saveStart(
      db,
      const CycleStart(date: '2026-09-10', kind: kCycleStartKind, note: 'x'),
      now: _now,
    );
    expect(dup.conflict, isTrue);
    const edited = CycleStart(
      date: '2026-09-10',
      kind: kCycleStartKind,
      note: 'late',
    );
    final saved = await CycleStore.saveStart(
      db,
      edited,
      expected: original,
      now: _now,
    );
    expect(saved.committed, isTrue);
    expect(saved.start?.note, 'late');
    final rows = await db.query('cycle_log');
    expect(rows, hasLength(1));
  });

  test('move collision is transactional and does not overwrite', () async {
    const from = CycleStart(date: '2026-09-10', kind: kCycleStartKind, note: 'a');
    const dest = CycleStart(date: '2026-09-12', kind: kCycleStartKind, note: 'b');
    await CycleStore.saveStart(db, from, now: _now);
    await CycleStore.saveStart(db, dest, now: _now);
    final move = await CycleStore.saveStart(
      db,
      dest,
      expected: from,
      now: _now,
    );
    expect(move.conflict, isTrue);
    final rows = await db.query('cycle_log', orderBy: 'date ASC');
    expect(rows.map((r) => r['date']), ['2026-09-10', '2026-09-12']);
    expect(rows.map((r) => r['note']), ['a', 'b']);
  });

  test('move succeeds when destination is empty and preserves note', () async {
    const from = CycleStart(date: '2026-09-10', kind: kCycleStartKind, note: 'a');
    const to = CycleStart(date: '2026-09-12', kind: kCycleStartKind, note: 'a');
    await CycleStore.saveStart(db, from, now: _now);
    final moved = await CycleStore.saveStart(db, to, expected: from, now: _now);
    expect(moved.committed, isTrue);
    final rows = await db.query('cycle_log');
    expect(rows, hasLength(1));
    expect(rows.single['date'], '2026-09-12');
    expect(rows.single['note'], 'a');
  });

  test('remove and undo; stale replay cannot recreate', () async {
    const start = CycleStart(date: '2026-09-10', kind: kCycleStartKind, note: null);
    await CycleStore.saveStart(db, start, now: _now);
    expect((await CycleStore.removeStart(db, start)).committed, isTrue);
    expect(await db.query('cycle_log'), isEmpty);
    final replay = await CycleStore.saveStart(db, start, expected: start, now: _now);
    expect(replay.conflict, isTrue);
    expect(await db.query('cycle_log'), isEmpty);
    expect((await CycleStore.restoreStart(db, start, now: _now)).committed, isTrue);
    await CycleStore.removeStart(db, start);
    await CycleStore.saveStart(
      db,
      const CycleStart(date: '2026-09-10', kind: kCycleStartKind, note: 'new'),
      now: _now,
    );
    final occupied = await CycleStore.restoreStart(db, start, now: _now);
    expect(occupied.conflict, isTrue);
    expect(occupied.currentStart?.note, 'new');
  });

  test('observations: note-only, clear, unknown tag, null note retained',
      () async {
    final noteOnly = await CycleStore.saveObservation(
      db,
      const CycleObservation(date: '2026-09-14', tags: [], note: 'sore'),
      now: _now,
    );
    expect(noteOnly.observation?.tags, isEmpty);
    expect(noteOnly.observation?.note, 'sore');
    final tagged = await CycleStore.saveObservation(
      db,
      const CycleObservation(
        date: '2026-09-14',
        tags: ['unknown-tag'],
        note: null,
      ),
      expected: noteOnly.observation,
      now: _now,
    );
    expect(tagged.observation?.tags, ['unknown-tag']);
    expect(tagged.observation?.note, isNull);
    final snap = await CycleStore.read(db, day: '2026-09-15', settings: _settings);
    expect(snap.observations.single.note, isNull);
    expect(snap.observations.single.tags, ['unknown-tag']);
    final cleared = await CycleStore.saveObservation(
      db,
      const CycleObservation(date: '2026-09-14', tags: []),
      expected: tagged.observation,
      now: _now,
    );
    expect(cleared.observation, isNull);
    expect(await db.query('cycle_symptom'), isEmpty);
  });

  test('corrupt rows count partial; empty is not unreadable', () async {
    await seedStart('2026-08-24');
    await db.insert('cycle_log', {'date': 20260901, 'kind': 'start'});
    await db.insert('cycle_symptom', {
      'date': '2026-09-15',
      'symptoms_json': '{',
      'note': null,
    });
    final snap = await CycleStore.read(db, day: '2026-09-15', settings: _settings);
    expect(snap.unreadableCount, 2);
    expect(snap.unreadableStarts, isTrue);
    expect(snap.starts.map((s) => s.date), ['2026-08-24']);
    expect(snap.observations, isEmpty);
    expect(snap.cycleDay, isNull);
    expect(snap.latestStart?.date, '2026-08-24');
    expect(snap.estimate.reason, CycleEstimateReason.unreadableStarts);
    await db.delete('cycle_log');
    await db.delete('cycle_symptom');
    final empty = await CycleStore.read(db, day: '2026-09-15', settings: _settings);
    expect(empty.unreadableCount, 0);
    expect(empty.unreadableStarts, isFalse);
    expect(empty.starts, isEmpty);
    expect(empty.observations, isEmpty);
    expect(empty.cycleDay, isNull);
    expect(empty.estimate.reason, CycleEstimateReason.missingStarts);
  });

  test('corrupt start nulls cycleDay when estimates are off or situation is none',
      () async {
    await seedStart('2026-08-24');
    await db.insert('cycle_log', {'date': 20260901, 'kind': 'start'});
    final off = await CycleStore.read(
      db,
      day: '2026-09-15',
      settings: const CycleSettings(
        enabled: true,
        estimatesEnabled: false,
        lengthReviewEnabled: true,
      ),
    );
    expect(off.unreadableStarts, isTrue);
    expect(off.cycleDay, isNull);
    expect(off.latestStart?.date, '2026-08-24');
    expect(off.estimate.reason, CycleEstimateReason.estimatesDisabled);
    final none = await CycleStore.read(
      db,
      day: '2026-09-15',
      settings: const CycleSettings(
        enabled: true,
        estimatesEnabled: true,
        situation: CycleSituation.none,
        lengthReviewEnabled: true,
      ),
    );
    expect(none.unreadableStarts, isTrue);
    expect(none.cycleDay, isNull);
    expect(none.estimate.reason, CycleEstimateReason.situationNone);
  });

  test('corrupt observation-only keeps a valid cycle day', () async {
    await seedStart('2026-08-24');
    await db.insert('cycle_symptom', {
      'date': '2026-09-15',
      'symptoms_json': '{',
    });
    final snap = await CycleStore.read(db, day: '2026-09-15', settings: _settings);
    expect(snap.unreadableStarts, isFalse);
    expect(snap.unreadableCount, 1);
    expect(snap.cycleDay, 23);
    expect(snap.latestStart?.date, '2026-08-24');
    expect(snap.estimate.reason, CycleEstimateReason.missingStarts);
  });

  test('write abort retains existing rows', () async {
    await seedStart('2026-08-24');
    await db.execute('''
      CREATE TRIGGER fail_write BEFORE INSERT ON cycle_log
      BEGIN SELECT RAISE(ABORT, 'nope'); END
    ''');
    await expectLater(
      CycleStore.saveStart(
        db,
        const CycleStart(date: '2026-09-10', kind: kCycleStartKind),
        now: _now,
      ),
      throwsA(isA<DatabaseException>()),
    );
    final rows = await db.query('cycle_log');
    expect(rows.map((r) => r['date']), ['2026-08-24']);
  });

  test('historical as-of and no future inputs; >60 gap withholds', () async {
    for (final date in [
      '2026-06-01',
      '2026-06-29',
      '2026-07-31',
      '2026-08-24',
    ]) {
      await seedStart(date);
    }
    final july = await CycleStore.read(
      db,
      day: '2026-07-15',
      settings: _settings,
    );
    expect(july.starts.map((s) => s.date), ['2026-06-01', '2026-06-29']);
    expect(july.estimate.point, '2026-07-27');
    expect(july.estimate.reason, CycleEstimateReason.availablePoint);
  });

  test('later known-valid corrupt rows do not contaminate an earlier as-of',
      () async {
    for (final date in ['2026-06-01', '2026-06-29']) {
      await seedStart(date);
    }
    await db.insert('cycle_log', {'date': '2026-09-01', 'kind': ''});
    await db.insert('cycle_log', {
      'date': '2026-09-10',
      'kind': 'start',
      'note': 1,
    });
    await db.insert('cycle_symptom', {
      'date': '2026-09-15',
      'symptoms_json': '{',
    });
    await db.insert('cycle_symptom', {
      'date': '2026-08-01',
      'symptoms_json': jsonEncode(['flow']),
    });
    await db.insert('cycle_symptom', {
      'date': '2026-06-15',
      'symptoms_json': jsonEncode(['cramp']),
    });
    final july = await CycleStore.read(
      db,
      day: '2026-07-15',
      settings: _settings,
    );
    expect(july.starts.map((s) => s.date), ['2026-06-01', '2026-06-29']);
    expect(july.observations.map((o) => o.date), ['2026-06-15']);
    expect(july.unreadableCount, 0);
    expect(july.estimate.reason, CycleEstimateReason.availablePoint);
    expect(july.estimate.point, '2026-07-27');
    await db.insert('cycle_log', {'date': 20260901, 'kind': 'start'});
    final stillJuly = await CycleStore.read(
      db,
      day: '2026-07-15',
      settings: _settings,
    );
    expect(stillJuly.unreadableCount, 1);
    expect(stillJuly.unreadableStarts, isTrue);
    expect(stillJuly.cycleDay, isNull);
    expect(stillJuly.estimate.reason, CycleEstimateReason.unreadableStarts);
    expect(stillJuly.estimate.point, isNull);
  });

  test('gap of 60 days estimates; 61 withholds without a 28-day default',
      () async {
    await seedStart('2026-06-01');
    await seedStart('2026-07-31');
    expect(cycleDiffDays('2026-06-01', '2026-07-31'), 60);
    final exact = await CycleStore.read(
      db,
      day: '2026-09-15',
      settings: _settings,
    );
    expect(exact.estimate.reason, CycleEstimateReason.availablePoint);
    expect(exact.estimate.medianDays, 60);
    expect(exact.estimate.point, '2026-09-29');
    await db.delete('cycle_log');
    await seedStart('2026-06-01');
    await seedStart('2026-08-01');
    expect(cycleDiffDays('2026-06-01', '2026-08-01'), 61);
    final over = await CycleStore.read(
      db,
      day: '2026-09-15',
      settings: _settings,
    );
    expect(over.estimate.reason, CycleEstimateReason.gapExceedsSixtyDays);
    expect(over.estimate.point, isNull);
    expect(over.estimate.medianDays, 61);
  });

  test('DST transitions and west-zone civil labels stay calendar dates', () async {
    await seedStart('2026-03-08');
    await seedStart('2026-03-29');
    final snap = await CycleStore.read(
      db,
      day: '2026-03-30',
      settings: _settings,
    );
    expect(cycleDiffDays('2026-03-08', '2026-03-29'), 21);
    expect(snap.cycleDay, 2);
    expect(snap.latestStart?.date, '2026-03-29');
    expect(isCycleCalendarDay('2026-02-31'), isFalse);
    expect(isCycleCalendarDay('2026-09-15'), isTrue);
    expect(cycleAddDays('2026-11-01', 1), '2026-11-02');
    await expectLater(
      CycleStore.saveStart(
        db,
        const CycleStart(date: '2026-09-16', kind: kCycleStartKind),
        now: _now,
      ),
      throwsArgumentError,
    );
  });

  test('disabled settings still return stored starts', () async {
    await seedStart('2026-08-24');
    final snap = await CycleStore.read(
      db,
      day: '2026-09-15',
      settings: const CycleSettings(
        enabled: false,
        estimatesEnabled: false,
        lengthReviewEnabled: true,
      ),
    );
    expect(snap.starts, hasLength(1));
    expect(snap.settings.lengthReviewEnabled, isTrue);
    expect(snap.estimate.reason, CycleEstimateReason.trackingDisabled);
    expect(snap.cycleDay, 23);
  });

  test('string/number dates are unreadable, not coerced', () async {
    await db.insert('cycle_log', {'date': '20260915', 'kind': 'start'});
    await db.insert('cycle_log', {'date': '2026-9-15', 'kind': 'start'});
    await db.insert('cycle_symptom', {
      'date': '2026-09-15',
      'symptoms_json': jsonEncode([1, 'flow']),
    });
    final snap = await CycleStore.read(db, day: '2026-09-15', settings: _settings);
    expect(snap.starts, isEmpty);
    expect(snap.observations, isEmpty);
    expect(snap.unreadableCount, 3);
  });

  test('unreadable stored rows refuse CAS overwrite and stay on disk', () async {
    await db.insert('cycle_log', {
      'date': '2026-09-10',
      'kind': '',
      'note': 1,
    });
    const start = CycleStart(date: '2026-09-10', kind: kCycleStartKind);
    await expectLater(
      CycleStore.saveStart(db, start, now: _now),
      throwsFormatException,
    );
    await expectLater(CycleStore.removeStart(db, start), throwsFormatException);
    await expectLater(
      CycleStore.restoreStart(db, start, now: _now),
      throwsFormatException,
    );
    final starts = await db.query('cycle_log');
    expect(starts, hasLength(1));
    expect(starts.single['date'], '2026-09-10');
    expect(starts.single['kind'], '');
    expect(starts.single['note'], isNotNull);
    await db.insert('cycle_symptom', {
      'date': '2026-09-10',
      'symptoms_json': '{',
    });
    await expectLater(
      CycleStore.saveObservation(
        db,
        const CycleObservation(date: '2026-09-10', tags: ['flow']),
        now: _now,
      ),
      throwsFormatException,
    );
    expect((await db.query('cycle_symptom')).single['symptoms_json'], '{');
  });

  test('contributing date changes invalidate; notes, symptoms, unknown kinds do not',
      () async {
    const start = CycleStart(date: '2026-09-10', kind: kCycleStartKind);
    await CycleStore.saveStart(db, start, now: _now);
    expect(invalidations, 1);
    await CycleStore.saveStart(
      db,
      const CycleStart(date: '2026-09-10', kind: kCycleStartKind, note: 'late'),
      expected: start,
      now: _now,
    );
    expect(invalidations, 1);
    await CycleStore.saveStart(
      db,
      const CycleStart(date: '2026-09-11', kind: 'spotting'),
      now: _now,
    );
    expect(invalidations, 1);
    await CycleStore.saveObservation(
      db,
      const CycleObservation(date: '2026-09-10', tags: ['flow']),
      now: _now,
    );
    expect(invalidations, 1);
    const moved = CycleStart(
      date: '2026-09-12',
      kind: kCycleStartKind,
      note: 'late',
    );
    await CycleStore.saveStart(
      db,
      moved,
      expected: const CycleStart(
        date: '2026-09-10',
        kind: kCycleStartKind,
        note: 'late',
      ),
      now: _now,
    );
    expect(invalidations, 2);
    await CycleStore.removeStart(db, moved);
    expect(invalidations, 3);
    await CycleStore.saveStart(db, moved, now: _now);
    expect(invalidations, 4);
  });

  test('invalidate failure rolls back the start write', () async {
    CycleStore.invalidateCycleContext = (_) async {
      invalidations++;
      throw StateError('invalidate failed');
    };
    await expectLater(
      CycleStore.saveStart(
        db,
        const CycleStart(date: '2026-09-10', kind: kCycleStartKind),
        now: _now,
      ),
      throwsStateError,
    );
    expect(invalidations, 1);
    expect(await db.query('cycle_log'), isEmpty);
  });

  test('fresh recreate after delete is allowed; stale expected replay is not',
      () async {
    const start = CycleStart(date: '2026-09-10', kind: kCycleStartKind);
    await CycleStore.saveStart(db, start, now: _now);
    await CycleStore.removeStart(db, start);
    expect(
      (await CycleStore.saveStart(db, start, expected: start, now: _now))
          .conflict,
      isTrue,
    );
    expect((await CycleStore.saveStart(db, start, now: _now)).committed, isTrue);
    expect(await db.query('cycle_log'), hasLength(1));
  });

  group('LocalDb.invalidateCycleContext', () {
    late String path;

    setUp(() async {
      CycleStore.invalidateCycleContext = bindProductionInvalidate;
      await LocalDb.close();
      LocalDb.dbName = 'cycle_store_localdb_${_dbSeq++}.db';
      path = p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName);
      await databaseFactory.deleteDatabase(path);
    });

    tearDown(() async {
      await LocalDb.close();
      await databaseFactory.deleteDatabase(path);
      LocalDb.dbName = 'openstrap.db';
    });

    test('start mutations drop crossday and enqueue, keeping day-input cache',
        () async {
      final local = await LocalDb.instance;
      await LocalDb.putBaseline('crossday', jsonEncode({'stale': true}));
      await LocalDb.putBaseline('crossday_input', jsonEncode({'keep': true}));
      const start = CycleStart(date: '2026-09-10', kind: kCycleStartKind);

      Future<void> expectOutputInvalidatedAndInputKept() async {
        expect(await LocalDb.baseline('crossday'), isNull);
        expect(
          jsonDecode(
            (await LocalDb.baseline('crossday_input'))!['payload_json'] as String,
          ),
          {'keep': true},
        );
        expect(
          (await LocalDb.computeJobs())
              .any((j) => j['reason'] == LocalDb.kCycleContextJobReason),
          isTrue,
        );
      }

      expect((await CycleStore.saveStart(local, start, now: _now)).committed, isTrue);
      await expectOutputInvalidatedAndInputKept();
      await local.delete('compute_jobs');
      await LocalDb.putBaseline('crossday', jsonEncode({'stale': true}));
      expect((await CycleStore.removeStart(local, start)).committed, isTrue);
      await expectOutputInvalidatedAndInputKept();
      await local.delete('compute_jobs');
      await LocalDb.putBaseline('crossday', jsonEncode({'stale': true}));
      expect(
        (await CycleStore.restoreStart(local, start, now: _now)).committed,
        isTrue,
      );
      await expectOutputInvalidatedAndInputKept();
      final rows = await local.query('cycle_log');
      expect(rows, hasLength(1));
      expect(rows.single['date'], '2026-09-10');
      expect(rows.single['kind'], 'start');
    });

    test('invalidate rollback keeps the log empty and the prior artifact',
        () async {
      final local = await LocalDb.instance;
      await LocalDb.putBaseline('crossday', jsonEncode({'stale': true}));
      try {
        await local.transaction((txn) async {
          await txn.insert('cycle_log', {
            'date': '2026-06-01',
            'kind': 'start',
          });
          await LocalDb.invalidateCycleContext(txn);
          throw StateError('rollback');
        });
      } on StateError catch (e) {
        expect(e.message, 'rollback');
      }
      expect(await local.query('cycle_log'), isEmpty);
      expect(await LocalDb.baseline('crossday'), isNotNull);
      expect(await LocalDb.computeJobs(), isEmpty);
    });
  });
}
