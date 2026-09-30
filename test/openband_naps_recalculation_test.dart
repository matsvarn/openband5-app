import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late LocalOpenBandRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await LocalDb.close();
    LocalDb.dbName = 'openband_naps_recalculation_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/${LocalDb.dbName}');
    app = AppState.forTesting();
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    repository = LocalOpenBandRepository(app);
  });

  tearDown(() async {
    app.dispose();
    await LocalDb.close();
  });

  const day = '2026-09-15';

  test('missing source fails without dropping committed nap edits', () async {
    final revision = await repository.addNap(
      day: day,
      start: DateTime(2026, 9, 15, 16),
      end: DateTime(2026, 9, 15, 16, 30),
    );
    await expectLater(
      repository.recalculateNaps(day: day, revision: revision),
      throwsStateError,
    );
    final naps = await repository.readNaps(day);
    expect(naps.job?.state, CorrectionState.failed);
    expect(naps.job?.revision, revision);
    final edits = await LocalDb.napEdits(day);
    expect(edits, hasLength(1));
    expect(edits.single['source'], 'manual');
  });

  test(
    'last-edit delete without source fails and keeps the pending job failed',
    () async {
      await repository.addNap(
        day: day,
        start: DateTime(2026, 9, 15, 16),
        end: DateTime(2026, 9, 15, 16, 30),
      );
      final session = NapSession(
        start: DateTime(2026, 9, 15, 16),
        end: DateTime(2026, 9, 15, 16, 30),
        source: NapSource.manual,
        durationMin: 30,
      );
      final revision = await repository.removeNap(day: day, session: session);
      expect(await LocalDb.napEdits(day), isEmpty);
      expect((await LocalDb.napRecalcJob(day))?['revision'], revision);
      expect((await LocalDb.napRecalcJob(day))?['status'], 'pending');
      await expectLater(
        repository.recalculateNaps(day: day, revision: revision),
        throwsStateError,
      );
      expect((await LocalDb.napRecalcJob(day))?['status'], 'failed');
    },
  );

  test('stale nap revision is rejected before a busy derive can succeed', () async {
    final revision = await repository.addNap(
      day: day,
      start: DateTime(2026, 9, 15, 16),
      end: DateTime(2026, 9, 15, 16, 30),
    );
    await expectLater(
      repository.recalculateNaps(day: day, revision: revision + 1),
      throwsStateError,
    );
    expect((await LocalDb.napRecalcJob(day))?['status'], 'pending');
  });

  test('unjudged day stays unjudged after a manual log', () async {
    await repository.addNap(
      day: day,
      start: DateTime(2026, 9, 15, 16),
      end: DateTime(2026, 9, 15, 16, 30),
    );
    final naps = await repository.readNaps(day);
    expect(naps.judged, isFalse);
    expect(naps.totalMin, isNull);
    expect(naps.sessions, hasLength(1));
    expect(naps.sessions.single.source, NapSource.manual);
  });

  Future<void> putJudged({
    List<Map<String, dynamic>> value = const [],
    int? napMin = 0,
    bool partial = false,
    bool skipped = false,
    List<String> inputs = const ['hr'],
  }) {
    return LocalDb.putDayResult(
      dayId: day,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({
        'naps': {
          'value': value,
          'inputs_used': inputs,
        },
        'scalars': {'nap_min': ?napMin},
      }),
      windowJson: '{}',
      partial: partial,
      skipped: skipped,
    );
  }

  test('readNaps overlays ledger after failed recalc', () async {
    final detectedStart =
        DateTime(2026, 9, 15, 14, 10).millisecondsSinceEpoch ~/ 1000;
    final detectedEnd =
        DateTime(2026, 9, 15, 14, 42).millisecondsSinceEpoch ~/ 1000;
    await putJudged(
      value: [
        {
          'start': detectedStart,
          'end': detectedEnd,
          'duration_min': 32,
        },
      ],
      napMin: 32,
    );
    final revision = await repository.addNap(
      day: day,
      start: DateTime(2026, 9, 15, 16),
      end: DateTime(2026, 9, 15, 16, 30),
    );
    await expectLater(
      repository.recalculateNaps(day: day, revision: revision),
      throwsStateError,
    );
    final naps = await repository.readNaps(day);
    expect(naps.job?.state, CorrectionState.failed);
    expect(naps.judged, isTrue);
    expect(naps.totalMin, isNull);
    expect(naps.sessions.map((s) => s.source), [
      NapSource.detected,
      NapSource.manual,
    ]);
  });

  test('stale derived manuals do not survive without a ledger row', () async {
    final detectedStart =
        DateTime(2026, 9, 15, 14, 10).millisecondsSinceEpoch ~/ 1000;
    final detectedEnd =
        DateTime(2026, 9, 15, 14, 42).millisecondsSinceEpoch ~/ 1000;
    final manualStart =
        DateTime(2026, 9, 15, 16).millisecondsSinceEpoch ~/ 1000;
    final manualEnd =
        DateTime(2026, 9, 15, 16, 30).millisecondsSinceEpoch ~/ 1000;
    await putJudged(
      value: [
        {
          'start': detectedStart,
          'end': detectedEnd,
          'duration_min': 32,
        },
        {
          'start': manualStart,
          'end': manualEnd,
          'duration_min': 30,
          'source': 'manual',
        },
      ],
      napMin: 62,
    );
    final naps = await repository.readNaps(day);
    expect(naps.sessions, hasLength(1));
    expect(naps.sessions.single.source, NapSource.detected);
  });

  test('detected missing duration_min stays null', () async {
    final start = DateTime(2026, 9, 15, 14, 10).millisecondsSinceEpoch ~/ 1000;
    final end = DateTime(2026, 9, 15, 14, 42).millisecondsSinceEpoch ~/ 1000;
    await putJudged(
      value: [
        {'start': start, 'end': end},
      ],
      napMin: null,
    );
    final naps = await repository.readNaps(day);
    expect(naps.judged, isTrue);
    expect(naps.sessions.single.durationMin, isNull);
  });

  test('partial and skipped rows are not judged empty', () async {
    await putJudged(value: [], napMin: 0, partial: true);
    var naps = await repository.readNaps(day);
    expect(naps.judged, isFalse);
    expect(naps.totalMin, isNull);
    await putJudged(value: [], napMin: 0, skipped: true);
    naps = await repository.readNaps(day);
    expect(naps.judged, isFalse);
    expect(naps.totalMin, isNull);
  });

  test('corrupt nap entries cannot claim judged empty', () async {
    await putJudged(value: [{}], napMin: 0);
    final naps = await repository.readNaps(day);
    expect(naps.judged, isFalse);
    expect(naps.sessions, isEmpty);
    expect(naps.totalMin, isNull);
  });

  test('unreadable day_result still shows the durable ledger', () async {
    await LocalDb.putDayResult(
      dayId: day,
      algoVersion: kAlgoVersion,
      payloadJson: '{not-json',
      windowJson: '{}',
    );
    await repository.addNap(
      day: day,
      start: DateTime(2026, 9, 15, 16),
      end: DateTime(2026, 9, 15, 16, 30),
    );
    final naps = await repository.readNaps(day);
    expect(naps.judged, isFalse);
    expect(naps.totalMin, isNull);
    expect(naps.note, 'Auswertung unlesbar.');
    expect(naps.sessions, hasLength(1));
    expect(naps.sessions.single.source, NapSource.manual);
  });

  test('duration_min longer than the interval is rejected, not fabricated', () async {
    final start = DateTime(2026, 9, 15, 14, 10).millisecondsSinceEpoch ~/ 1000;
    final end = DateTime(2026, 9, 15, 14, 42).millisecondsSinceEpoch ~/ 1000;
    await putJudged(
      value: [
        {'start': start, 'end': end, 'duration_min': 90},
      ],
      napMin: 90,
    );
    final naps = await repository.readNaps(day);
    expect(naps.judged, isFalse);
    expect(naps.sessions, isEmpty);
    expect(naps.totalMin, isNull);
  });

  test(
    'same-start detected edit then remove writes a rejection, not a delete',
    () async {
      final start = DateTime(2026, 9, 15, 14, 10);
      final end = DateTime(2026, 9, 15, 14, 42);
      await putJudged(
        value: [
          {
            'start': start.millisecondsSinceEpoch ~/ 1000,
            'end': end.millisecondsSinceEpoch ~/ 1000,
            'duration_min': 32,
          },
        ],
        napMin: 32,
      );
      final original = (await repository.readNaps(day)).sessions.single;
      expect(original.source, NapSource.detected);
      await repository.editNap(
        day: day,
        original: original,
        start: start,
        end: DateTime(2026, 9, 15, 15),
      );
      final edited = (await repository.readNaps(day)).sessions.single;
      expect(edited.source, NapSource.manual);
      expect(edited.originStartTs, original.startTs);
      expect(edited.originEndTs, original.endTs);
      await repository.removeNap(day: day, session: edited);
      final after = await repository.readNaps(day);
      expect(after.sessions, isEmpty);
      expect(after.rejected, hasLength(1));
      expect(after.rejected.single.startTs, original.startTs);
      expect(
        (await LocalDb.napEdits(day)).single['source'],
        'rejected',
      );
    },
  );

  test(
    'detected same-start edit then moved edit then remove then restore',
    () async {
      final originStart = DateTime(2026, 9, 15, 14, 10);
      final originEnd = DateTime(2026, 9, 15, 14, 42);
      await putJudged(
        value: [
          {
            'start': originStart.millisecondsSinceEpoch ~/ 1000,
            'end': originEnd.millisecondsSinceEpoch ~/ 1000,
            'duration_min': 32,
          },
        ],
        napMin: 32,
      );
      final detected = (await repository.readNaps(day)).sessions.single;
      await repository.editNap(
        day: day,
        original: detected,
        start: originStart,
        end: DateTime(2026, 9, 15, 15),
      );
      var naps = await repository.readNaps(day);
      expect(naps.sessions, hasLength(1));
      expect(naps.sessions.single.source, NapSource.manual);
      expect(naps.sessions.single.startTs, detected.startTs);
      expect(naps.rejected, isEmpty);
      expect((await LocalDb.napEdits(day)).single['source'], 'manual');
      expect(
        (await LocalDb.napEdits(day)).single['origin_start_ts'],
        detected.startTs,
      );

      final sameStart = naps.sessions.single;
      final movedStart = DateTime(2026, 9, 15, 16);
      final movedEnd = DateTime(2026, 9, 15, 16, 30);
      await repository.editNap(
        day: day,
        original: sameStart,
        start: movedStart,
        end: movedEnd,
      );
      naps = await repository.readNaps(day);
      expect(naps.sessions, hasLength(1));
      expect(naps.sessions.single.startTs, movedStart.millisecondsSinceEpoch ~/ 1000);
      expect(naps.sessions.single.originStartTs, detected.startTs);
      expect(naps.rejected, hasLength(1));
      expect(naps.rejected.single.startTs, detected.startTs);
      final ledger = await LocalDb.napEdits(day);
      expect(ledger.map((r) => r['source']), ['rejected', 'manual']);

      await repository.editNap(
        day: day,
        original: naps.sessions.single,
        start: originStart,
        end: DateTime(2026, 9, 15, 15),
      );
      naps = await repository.readNaps(day);
      expect(naps.sessions, hasLength(1));
      expect(naps.sessions.single.startTs, detected.startTs);
      expect(naps.rejected, isEmpty);
      expect((await LocalDb.napEdits(day)).single['source'], 'manual');

      await repository.editNap(
        day: day,
        original: naps.sessions.single,
        start: movedStart,
        end: movedEnd,
      );
      naps = await repository.readNaps(day);
      await repository.removeNap(day: day, session: naps.sessions.single);
      naps = await repository.readNaps(day);
      expect(naps.sessions, isEmpty);
      expect(naps.rejected, hasLength(1));
      expect(naps.rejected.single.startTs, detected.startTs);
      expect((await LocalDb.napEdits(day)).single['source'], 'rejected');

      await repository.restoreNap(day: day, rejected: naps.rejected.single);
      naps = await repository.readNaps(day);
      expect(await LocalDb.napEdits(day), isEmpty);
      expect(naps.rejected, isEmpty);
      expect(naps.sessions, hasLength(1));
      expect(naps.sessions.single.source, NapSource.detected);
      expect(naps.sessions.single.startTs, detected.startTs);
    },
  );

  test('invalid ledger source is refused', () async {
    await expectLater(
      LocalDb.putNapEdit(
        dayId: day,
        startTs: 1000,
        endTs: 2800,
        source: 'detected',
      ),
      throwsArgumentError,
    );
    expect(await LocalDb.napEdits(day), isEmpty);
  });

  test(
    'last-delete of an old finalized day is restaged by a light run when newer raw exists',
    () async {
      const oldDay = '2026-09-10';
      const newDay = '2026-09-19';
      final db = await LocalDb.instance;
      Future<void> insertDay(String label, int hours, int counter0) async {
        final batch = db.batch();
        final start = DateTime.parse(label).millisecondsSinceEpoch ~/ 1000;
        for (var i = 0; i < hours * 3600; i++) {
          batch.insert('decoded_onehz', {
            'device_id': '',
            'ts_ms': (start + i) * 1000,
            'rec_ts': start + i,
            'counter': counter0 + i,
            'hr': 70,
            'ax': 0.0,
            'ay': 0.0,
            'az': 1.0,
            'device_family': 'gen4',
          });
        }
        await batch.commit(noResult: true);
      }

      await insertDay(oldDay, 12, 0);
      await insertDay(newDay, 2, 100000);
      final addRev = await repository.addNap(
        day: oldDay,
        start: DateTime(2026, 9, 10, 16),
        end: DateTime(2026, 9, 10, 16, 30),
      );
      await repository.recalculateNaps(day: oldDay, revision: addRev);
      expect((await LocalDb.napRecalcJob(oldDay))?['status'], 'complete');
      await db.update(
        'day_result',
        {'finalized': 1},
        where: 'day_id = ?',
        whereArgs: [oldDay],
      );
      expect((await LocalDb.dayResult(oldDay))?['finalized'], 1);
      final rawDays = (await LocalDb.decodedRecTsMaxByDay()).keys.toList()
        ..sort();
      expect(rawDays, containsAll([oldDay, newDay]));
      expect(rawDays.last, isNot(oldDay));
      final before =
          ((await LocalDb.dayResult(oldDay))?['computed_at'] as num).toInt();
      var naps = await repository.readNaps(oldDay);
      final session = naps.sessions.firstWhere(
        (s) => s.source == NapSource.manual,
      );
      await repository.removeNap(day: oldDay, session: session);
      expect(await LocalDb.napEditDays(), isEmpty);
      expect((await LocalDb.napRecalcJob(oldDay))?['status'], 'pending');
      expect(await LocalDb.napRecalcPendingDays(), contains(oldDay));
      final n = await DerivationEngine().run(
        const PersonalProfile(),
      );
      expect(n, greaterThanOrEqualTo(1));
      final after = await LocalDb.dayResult(oldDay);
      expect((after?['computed_at'] as num).toInt(), greaterThan(before));
      expect(after?['skipped'], 0);
      expect(after?['partial'], 0);
      naps = await repository.readNaps(oldDay);
      expect(naps.sessions.any((s) => s.startTs == session.startTs), isFalse);
    },
  );
}
