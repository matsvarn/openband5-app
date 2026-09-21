import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map _load(String name) =>
    jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync())
        as Map;

SyntheticOpenBandRepository repo() => SyntheticOpenBandRepository.fromMaps(
      _load('day-summary.json'),
      _load('sleep-detail.json'),
    );

final _paperNow = SyntheticOpenBandRepository.cycleFixtureNow;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('fromProfile version 1 uses track_cycle and defaults estimates off', () {
    expect(
      CycleSettings.fromProfile(
        const {
          'cycle_preferences_version': 1,
          'track_cycle': true,
          'repro_state': 'cycling',
          'cycle_length_review': true,
        },
        false,
      ),
      const CycleSettings(
        enabled: true,
        estimatesEnabled: false,
        situation: CycleSituation.cycling,
        lengthReviewEnabled: true,
      ),
    );
    expect(
      CycleSettings.fromProfile(
        const {
          'cycle_preferences_version': 1,
          'track_cycle': false,
        },
        true,
      ).enabled,
      isFalse,
    );
  });

  test('fromProfile without version requires both legacy and track_cycle', () {
    const profile = {'track_cycle': true};
    expect(
      CycleSettings.fromProfile(profile, false).enabled,
      isFalse,
    );
    expect(
      CycleSettings.fromProfile(profile, true).enabled,
      isTrue,
    );
    expect(
      CycleSettings.fromProfile(
        const {'track_cycle': false},
        true,
      ).enabled,
      isFalse,
    );
  });

  test('fromProfile treats a valid empty profile as unchosen/off', () {
    const empty = CycleSettings(
      enabled: false,
      estimatesEnabled: false,
      lengthReviewEnabled: false,
    );
    expect(CycleSettings.fromProfile(const {}, false), empty);
    expect(CycleSettings.fromProfile(const {}, true), empty);
    expect(
      CycleSettings.fromProfile(
        const {'cycle_preferences_version': 1},
        true,
      ),
      empty,
    );
  });

  test('fromProfile absent keys are off, present null errors, false is off', () {
    const off = CycleSettings(
      enabled: false,
      estimatesEnabled: false,
      lengthReviewEnabled: false,
    );
    expect(CycleSettings.fromProfile(const {}, true), off);
    expect(
      CycleSettings.fromProfile(const {'track_cycle': false}, true),
      off,
    );
    expect(
      CycleSettings.fromProfile(
        const {
          'track_cycle': false,
          'cycle_estimates': false,
          'cycle_length_review': false,
        },
        true,
      ),
      off,
    );
    expect(
      () => CycleSettings.fromProfile(
        <String, Object?>{'track_cycle': null},
        true,
      ),
      throwsFormatException,
    );
    expect(
      () => CycleSettings.fromProfile(
        <String, Object?>{'cycle_estimates': null},
        true,
      ),
      throwsFormatException,
    );
    expect(
      () => CycleSettings.fromProfile(
        <String, Object?>{'cycle_length_review': null},
        true,
      ),
      throwsFormatException,
    );
    expect(
      CycleSettings.fromProfile(
        <String, Object?>{'repro_state': null},
        false,
      ).situation,
      isNull,
    );
    expect(CycleSettings.fromProfile(const {}, false).situation, isNull);
  });

  test('fromProfile throws on unavailable or malformed present values', () {
    expect(
      () => CycleSettings.fromProfile(null, false),
      throwsFormatException,
    );
    expect(
      () => CycleSettings.fromProfile(
        const {'cycle_preferences_version': 2, 'track_cycle': true},
        true,
      ),
      throwsFormatException,
    );
    expect(
      () => CycleSettings.fromProfile(
        const {'track_cycle': 'true'},
        true,
      ),
      throwsFormatException,
    );
    expect(
      () => CycleSettings.fromProfile(
        const {'track_cycle': true, 'cycle_estimates': 1},
        true,
      ),
      throwsFormatException,
    );
    expect(
      () => CycleSettings.fromProfile(
        const {'track_cycle': true, 'repro_state': 'pregnant'},
        true,
      ),
      throwsFormatException,
    );
  });

  test('Paper fixture is day 23 with median 28 MAD 4 and 17–25 September',
      () async {
    final snap = await repo().readCycle(
      SyntheticOpenBandRepository.cycleFixtureDay,
      now: _paperNow,
    );
    expect(snap.day, '2026-09-15');
    expect(snap.unreadableCount, 0);
    expect(snap.unreadableStarts, isFalse);
    expect(snap.starts.map((s) => s.date), [
      '2026-06-01',
      '2026-06-29',
      '2026-07-31',
      '2026-08-24',
    ]);
    expect(snap.latestStart?.date, '2026-08-24');
    expect(snap.cycleDay, 23);
    expect(snap.estimate.availability, CycleEstimateAvailability.available);
    expect(snap.estimate.reason, CycleEstimateReason.availableRange);
    expect(snap.estimate.gapCount, 3);
    expect(snap.estimate.medianDays, 28);
    expect(snap.estimate.madDays, 4);
    expect(snap.estimate.point, '2026-09-21');
    expect(snap.estimate.from, '2026-09-17');
    expect(snap.estimate.to, '2026-09-25');
    expect(
      ana.median(const [28.0, 32.0, 24.0]),
      snap.estimate.medianDays,
    );
    expect(
      ana.mad(const [28.0, 32.0, 24.0], scaled: false),
      snap.estimate.madDays,
    );
  });

  test('one start is missing; two starts are a point without a range', () async {
    final r = repo()..clearCycleLogs();
    r.seedCycleStart(
      const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
    );
    final one = await r.readCycle('2026-09-15', now: _paperNow);
    expect(one.cycleDay, 23);
    expect(one.estimate.availability, CycleEstimateAvailability.missing);
    expect(one.estimate.reason, CycleEstimateReason.missingStarts);
    expect(one.estimate.point, isNull);
    r.seedCycleStart(
      const CycleStart(date: '2026-07-27', kind: kCycleStartKind),
    );
    final two = await r.readCycle('2026-09-15', now: _paperNow);
    expect(two.estimate.availability, CycleEstimateAvailability.available);
    expect(two.estimate.reason, CycleEstimateReason.availablePoint);
    expect(two.estimate.gapCount, 1);
    expect(two.estimate.medianDays, 28);
    expect(two.estimate.madDays, isNull);
    expect(two.estimate.point, '2026-09-21');
    expect(two.estimate.from, isNull);
    expect(two.estimate.to, isNull);
  });

  test('a gap over 60 days withholds prediction and does not default 28d',
      () async {
    final r = repo()..clearCycleLogs();
    r
      ..seedCycleStart(
        const CycleStart(date: '2026-06-01', kind: kCycleStartKind),
      )
      ..seedCycleStart(
        const CycleStart(date: '2026-08-24', kind: kCycleStartKind),
      );
    final snap = await r.readCycle('2026-09-15', now: _paperNow);
    expect(cycleDiffDays('2026-06-01', '2026-08-24'), 84);
    expect(snap.estimate.availability, CycleEstimateAvailability.withheld);
    expect(snap.estimate.reason, CycleEstimateReason.gapExceedsSixtyDays);
    expect(snap.estimate.point, isNull);
    expect(snap.estimate.medianDays, 84);
  });

  test('historical as-of ignores later starts and does not invent a phase',
      () async {
    final snap = await repo().readCycle('2026-07-15', now: _paperNow);
    expect(snap.starts.map((s) => s.date), ['2026-06-01', '2026-06-29']);
    expect(snap.latestStart?.date, '2026-06-29');
    expect(snap.cycleDay, 17);
    expect(snap.estimate.reason, CycleEstimateReason.availablePoint);
    expect(snap.estimate.point, '2026-07-27');
    expect(snap.estimate.from, isNull);
  });

  test('later unreadable known-valid rows do not withhold an earlier as-of',
      () async {
    final r = repo();
    r.seedUnreadableCycleStart({'date': '2026-09-01', 'kind': ''});
    r.seedUnreadableCycleObservation({
      'date': '2026-09-15',
      'symptoms_json': '{',
    });
    r.seedCycleObservation(
      const CycleObservation(date: '2026-08-01', tags: ['flow']),
    );
    final snap = await r.readCycle('2026-07-15', now: _paperNow);
    expect(snap.starts.map((s) => s.date), ['2026-06-01', '2026-06-29']);
    expect(snap.observations, isEmpty);
    expect(snap.unreadableCount, 0);
    expect(snap.unreadableStarts, isFalse);
    expect(snap.cycleDay, 17);
    expect(snap.estimate.reason, CycleEstimateReason.availablePoint);
    expect(snap.estimate.point, '2026-07-27');
    r.seedUnreadableCycleStart({'date': 20260901, 'kind': 'start'});
    final undated = await r.readCycle('2026-07-15', now: _paperNow);
    expect(undated.unreadableCount, 1);
    expect(undated.unreadableStarts, isTrue);
    expect(undated.cycleDay, isNull);
    expect(undated.estimate.reason, CycleEstimateReason.unreadableStarts);
  });

  test('a 60-day gap estimates; 61 days withholds', () async {
    final r = repo()..clearCycleLogs();
    r
      ..seedCycleStart(
        const CycleStart(date: '2026-06-01', kind: kCycleStartKind),
      )
      ..seedCycleStart(
        const CycleStart(date: '2026-07-31', kind: kCycleStartKind),
      );
    final exact = await r.readCycle('2026-09-15', now: _paperNow);
    expect(cycleDiffDays('2026-06-01', '2026-07-31'), 60);
    expect(exact.estimate.reason, CycleEstimateReason.availablePoint);
    expect(exact.estimate.medianDays, 60);
    r.clearCycleLogs();
    r
      ..seedCycleStart(
        const CycleStart(date: '2026-06-01', kind: kCycleStartKind),
      )
      ..seedCycleStart(
        const CycleStart(date: '2026-08-01', kind: kCycleStartKind),
      );
    final over = await r.readCycle('2026-09-15', now: _paperNow);
    expect(cycleDiffDays('2026-06-01', '2026-08-01'), 61);
    expect(over.estimate.reason, CycleEstimateReason.gapExceedsSixtyDays);
    expect(over.estimate.point, isNull);
  });

  test('unknown kind stays in history and does not contribute', () async {
    final r = repo();
    r.seedCycleStart(
      const CycleStart(date: '2026-09-01', kind: 'spotting', note: null),
    );
    final snap = await r.readCycle('2026-09-15', now: _paperNow);
    expect(
      snap.starts.singleWhere((s) => s.date == '2026-09-01').kind,
      'spotting',
    );
    expect(snap.starts.singleWhere((s) => s.date == '2026-09-01').note, isNull);
    expect(snap.latestStart?.date, '2026-08-24');
    expect(snap.cycleDay, 23);
  });

  test('corrupt start rows count partial and withhold prediction', () async {
    final r = repo();
    r.seedUnreadableCycleStart({'date': 20260901, 'kind': 'start'});
    final snap = await r.readCycle('2026-09-15', now: _paperNow);
    expect(snap.unreadableCount, 1);
    expect(snap.unreadableStarts, isTrue);
    expect(snap.starts, hasLength(4));
    expect(snap.latestStart?.date, '2026-08-24');
    expect(snap.cycleDay, isNull);
    expect(snap.estimate.availability, CycleEstimateAvailability.withheld);
    expect(snap.estimate.reason, CycleEstimateReason.unreadableStarts);
    expect(snap.estimate.point, isNull);
  });

  test('corrupt start nulls cycleDay when estimates are off or situation is none',
      () async {
    final r = repo();
    r.seedUnreadableCycleStart({'date': 20260901, 'kind': 'start'});
    r.cycleSettings = const CycleSettings(
      enabled: true,
      estimatesEnabled: false,
      lengthReviewEnabled: true,
    );
    var snap = await r.readCycle('2026-09-15', now: _paperNow);
    expect(snap.unreadableStarts, isTrue);
    expect(snap.cycleDay, isNull);
    expect(snap.latestStart?.date, '2026-08-24');
    expect(snap.starts, hasLength(4));
    expect(snap.estimate.reason, CycleEstimateReason.estimatesDisabled);
    r.cycleSettings = const CycleSettings(
      enabled: true,
      estimatesEnabled: true,
      situation: CycleSituation.none,
      lengthReviewEnabled: true,
    );
    snap = await r.readCycle('2026-09-15', now: _paperNow);
    expect(snap.unreadableStarts, isTrue);
    expect(snap.cycleDay, isNull);
    expect(snap.latestStart?.date, '2026-08-24');
    expect(snap.estimate.reason, CycleEstimateReason.situationNone);
  });

  test('corrupt observation-only keeps a valid cycle day', () async {
    final r = repo();
    r.seedUnreadableCycleObservation({
      'date': '2026-09-15',
      'symptoms_json': '{',
      'note': null,
    });
    final snap = await r.readCycle('2026-09-15', now: _paperNow);
    expect(snap.unreadableStarts, isFalse);
    expect(snap.unreadableCount, 1);
    expect(snap.cycleDay, 23);
    expect(snap.latestStart?.date, '2026-08-24');
    expect(snap.estimate.reason, CycleEstimateReason.availableRange);
  });

  test('empty observations are not a No; corrupt observation is partial',
      () async {
    final empty = await repo().readCycle('2026-09-15', now: _paperNow);
    expect(empty.observations, isEmpty);
    expect(empty.unreadableCount, 0);
    final r = repo();
    r.seedUnreadableCycleObservation({
      'date': '2026-09-15',
      'symptoms_json': '{',
      'note': null,
    });
    final bad = await r.readCycle('2026-09-15', now: _paperNow);
    expect(bad.observations, isEmpty);
    expect(bad.unreadableCount, 1);
    expect(bad.estimate.availability, CycleEstimateAvailability.available);
  });

  test('situation none and disabled estimates withhold without dropping logs',
      () async {
    final r = repo();
    r.cycleSettings = const CycleSettings(
      enabled: true,
      estimatesEnabled: true,
      situation: CycleSituation.none,
      lengthReviewEnabled: true,
    );
    var snap = await r.readCycle('2026-09-15', now: _paperNow);
    expect(snap.starts, hasLength(4));
    expect(snap.estimate.reason, CycleEstimateReason.situationNone);
    r.cycleSettings = const CycleSettings(
      enabled: true,
      estimatesEnabled: false,
      situation: CycleSituation.cycling,
      lengthReviewEnabled: true,
    );
    snap = await r.readCycle('2026-09-15', now: _paperNow);
    expect(snap.starts, hasLength(4));
    expect(snap.estimate.reason, CycleEstimateReason.estimatesDisabled);
    r.cycleSettings = const CycleSettings(
      enabled: false,
      estimatesEnabled: true,
      lengthReviewEnabled: true,
    );
    snap = await r.readCycle('2026-09-15', now: _paperNow);
    expect(snap.starts, hasLength(4));
    expect(snap.settings.lengthReviewEnabled, isTrue);
    expect(snap.estimate.reason, CycleEstimateReason.trackingDisabled);
  });

  test('predicted window behind the selected day is stale/open', () async {
    final snap = await repo().readCycle('2026-09-26', now: _paperNow);
    expect(snap.estimate.availability, CycleEstimateAvailability.stale);
    expect(snap.estimate.reason, CycleEstimateReason.staleOpen);
    expect(snap.estimate.from, '2026-09-17');
    expect(snap.estimate.to, '2026-09-25');
    expect(snap.estimate.point, '2026-09-21');
    expect(snap.estimate.gapCount, 3);
  });

  test('same-day create conflicts; matching retry commits before expected',
      () async {
    final r = repo();
    const start = CycleStart(date: '2026-09-10', kind: kCycleStartKind);
    final first = await r.saveCycleStart(start, now: _paperNow);
    expect(first.committed, isTrue);
    final dup = await r.saveCycleStart(
      const CycleStart(date: '2026-09-10', kind: kCycleStartKind, note: 'x'),
      now: _paperNow,
    );
    expect(dup.conflict, isTrue);
    expect(dup.currentStart, start);
    final retry = await r.saveCycleStart(
      start,
      expected: const CycleStart(
        date: '2026-09-10',
        kind: kCycleStartKind,
        note: 'stale',
      ),
      now: _paperNow,
    );
    expect(retry.committed, isTrue);
    expect(retry.start, start);
  });

  test('moving onto an occupied date conflicts and keeps both rows', () async {
    final r = repo();
    const from = CycleStart(date: '2026-09-10', kind: kCycleStartKind);
    const occupied = CycleStart(date: '2026-09-12', kind: kCycleStartKind);
    await r.saveCycleStart(from, now: _paperNow);
    await r.saveCycleStart(occupied, now: _paperNow);
    final move = await r.saveCycleStart(
      occupied,
      expected: from,
      now: _paperNow,
    );
    expect(move.conflict, isTrue);
    expect(move.currentStart, occupied);
    final snap = await r.readCycle('2026-09-15', now: _paperNow);
    expect(snap.starts.where((s) => s.date == '2026-09-10'), isNotEmpty);
    expect(snap.starts.where((s) => s.date == '2026-09-12'), isNotEmpty);
  });

  test('remove then undo restores; occupied undo conflicts', () async {
    final r = repo();
    const start = CycleStart(
      date: '2026-09-10',
      kind: kCycleStartKind,
      note: 'kept',
    );
    await r.saveCycleStart(start, now: _paperNow);
    final removed = await r.removeCycleStart(start);
    expect(removed.committed, isTrue);
    expect(removed.start?.note, 'kept');
    var snap = await r.readCycle('2026-09-15', now: _paperNow);
    expect(snap.starts.where((s) => s.date == '2026-09-10'), isEmpty);
    final staleReplay = await r.saveCycleStart(start, expected: start, now: _paperNow);
    expect(staleReplay.conflict, isTrue);
    final restored = await r.restoreCycleStart(start, now: _paperNow);
    expect(restored.committed, isTrue);
    expect(restored.start?.note, 'kept');
    await r.removeCycleStart(start);
    await r.saveCycleStart(
      const CycleStart(date: '2026-09-10', kind: kCycleStartKind, note: 'other'),
      now: _paperNow,
    );
    final occupied = await r.restoreCycleStart(start, now: _paperNow);
    expect(occupied.conflict, isTrue);
    expect(occupied.currentStart?.note, 'other');
  });

  test('fresh create after delete is allowed; stale expected replay is not',
      () async {
    final r = repo();
    const start = CycleStart(date: '2026-09-10', kind: kCycleStartKind);
    await r.saveCycleStart(start, now: _paperNow);
    await r.removeCycleStart(start);
    final replay = await r.saveCycleStart(start, expected: start, now: _paperNow);
    expect(replay.conflict, isTrue);
    final fresh = await r.saveCycleStart(start, now: _paperNow);
    expect(fresh.committed, isTrue);
    expect(fresh.start, start);
  });

  test('note-only observation, clear, and null note stay distinct', () async {
    final r = repo();
    final saved = await r.saveCycleObservation(
      const CycleObservation(date: '2026-09-15', tags: [], note: 'cramps'),
      now: _paperNow,
    );
    expect(saved.observation?.tags, isEmpty);
    expect(saved.observation?.note, 'cramps');
    expect(saved.observation?.updatedAt, isNotNull);
    final tagged = await r.saveCycleObservation(
      const CycleObservation(
        date: '2026-09-15',
        tags: ['flow'],
        note: 'cramps',
      ),
      expected: saved.observation,
      now: _paperNow,
    );
    expect(tagged.observation?.tags, ['flow']);
    expect(tagged.observation?.note, 'cramps');
    final cleared = await r.saveCycleObservation(
      const CycleObservation(date: '2026-09-15', tags: []),
      expected: tagged.observation,
      now: _paperNow,
    );
    expect(cleared.committed, isTrue);
    expect(cleared.observation, isNull);
    final snap = await r.readCycle('2026-09-15', now: _paperNow);
    expect(snap.observations, isEmpty);
  });

  test('write failure keeps existing rows; refresh failure does not replay',
      () async {
    final r = repo();
    final before = await r.readCycle('2026-09-15', now: _paperNow);
    r.failCycleWrite = true;
    await expectLater(
      r.saveCycleStart(
        const CycleStart(date: '2026-09-10', kind: kCycleStartKind),
        now: _paperNow,
      ),
      throwsStateError,
    );
    r.failCycleWrite = false;
    final afterFail = await r.readCycle('2026-09-15', now: _paperNow);
    expect(afterFail.starts.map((s) => s.date), before.starts.map((s) => s.date));
    r.failCycleContextRefresh = true;
    final written = await r.saveCycleStart(
      const CycleStart(date: '2026-09-10', kind: kCycleStartKind),
      now: _paperNow,
    );
    expect(written.committed, isTrue);
    expect(written.contextRefreshFailed, isTrue);
    expect(written.start?.date, '2026-09-10');
    expect(r.cycleContextRefreshCalls, 1);
    r.failCycleContextRefresh = false;
    await r.refreshCycleContext();
    expect(r.cycleContextRefreshCalls, 2);
    final snap = await r.readCycle('2026-09-15', now: _paperNow);
    expect(snap.starts.where((s) => s.date == '2026-09-10'), hasLength(1));
  });

  test('new writes refuse dates after local today', () async {
    final r = repo();
    await expectLater(
      r.saveCycleStart(
        const CycleStart(date: '2026-09-16', kind: kCycleStartKind),
        now: _paperNow,
      ),
      throwsArgumentError,
    );
    await expectLater(
      r.readCycle('2026-02-31'),
      throwsArgumentError,
    );
  });

  test('civil arithmetic is UTC day integers across both DST transitions', () {
    expect(cycleDiffDays('2026-03-08', '2026-03-09'), 1);
    expect(cycleDiffDays('2026-11-01', '2026-11-02'), 1);
    expect(cycleDiffDays('2026-03-29', '2026-03-30'), 1);
    expect(cycleDiffDays('2026-10-25', '2026-10-26'), 1);
    expect(cycleDiffDays('2026-03-28', '2026-03-30'), 2);
    expect(cycleAddDays('2026-03-08', 1), '2026-03-09');
    expect(cycleAddDays('2026-11-01', 1), '2026-11-02');
  });

  test('local civil now refuses tomorrow without UTC conversion', () {
    final evening = DateTime(2026, 9, 15, 23);
    expect(cycleTodayLabel(evening), '2026-09-15');
    expect(() => requireCycleWriteDay('2026-09-15', evening), returnsNormally);
    expect(
      () => requireCycleWriteDay('2026-09-16', evening),
      throwsArgumentError,
    );
    expect(
      const CycleStart(date: '2026-09-15', kind: kCycleStartKind).date,
      '2026-09-15',
    );
  });

  group('LocalOpenBandRepository production AppState fallback', () {
    late String path;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      Prefs.debugReset();
      await Prefs.ensureLoaded();
      await LocalDb.close();
      LocalDb.dbName = 'openband_cycle_production_fallback.db';
      path = p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName);
      await databaseFactory.deleteDatabase(path);
    });

    tearDown(() async {
      await LocalDb.close();
      await databaseFactory.deleteDatabase(path);
      LocalDb.dbName = 'openstrap.db';
    });

    test('unavailable user vs empty profile, then persist via AppState',
        () async {
      final missing = AppState.forTesting();
      addTearDown(missing.dispose);
      await expectLater(
        LocalOpenBandRepository(missing).readCycleSettings(),
        throwsFormatException,
      );

      final app = AppState.forTesting()..user = {};
      addTearDown(app.dispose);
      final repo = LocalOpenBandRepository(app);
      const empty = CycleSettings(
        enabled: false,
        estimatesEnabled: false,
        lengthReviewEnabled: false,
      );
      expect(await repo.readCycleSettings(), empty);
      const chosen = CycleSettings(
        enabled: true,
        estimatesEnabled: false,
        situation: CycleSituation.cycling,
        lengthReviewEnabled: true,
      );
      final saved = await repo.saveCycleSettings(chosen);
      expect(saved.committed, isTrue);
      expect(saved.contextRefreshFailed, isFalse);
      expect(await repo.readCycleSettings(), chosen);
      expect(app.user!['track_cycle'], isTrue);
      expect(app.user!['cycle_preferences_version'], 1);
    });

    test('AppState.refreshCycleContext propagates a durable-queue failure',
        () async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await (await LocalDb.instance).execute('DROP TABLE compute_jobs');
      await expectLater(
        app.refreshCycleContext(),
        throwsA(isA<Object>()),
      );
    });

    test('saved start, wake failure, retry refresh only; notes and observations do not enqueue',
        () async {
      final app = _WakeApp()
        ..user = {
          'cycle_preferences_version': 1,
          'track_cycle': true,
        };
      addTearDown(app.dispose);
      final repo = LocalOpenBandRepository(app);
      final now = DateTime(2026, 9, 15, 12);

      await (await LocalDb.instance).delete('compute_jobs');
      expect(
        (await repo.saveCycleObservation(
          const CycleObservation(date: '2026-09-10', tags: ['flow']),
          now: now,
        ))
            .committed,
        isTrue,
      );
      expect(await LocalDb.computeJobs(), isEmpty);
      expect(app.refreshes, 1);

      app.failWake = true;
      const start = CycleStart(date: '2026-09-10', kind: kCycleStartKind);
      final written = await repo.saveCycleStart(start, now: now);
      expect(written.committed, isTrue);
      expect(written.contextRefreshFailed, isTrue);
      expect(written.start, start);
      expect(app.refreshes, 2);
      expect(
        (await LocalDb.computeJobs())
            .any((j) => j['reason'] == LocalDb.kCycleContextJobReason),
        isTrue,
      );

      app.failWake = false;
      await repo.refreshCycleContext();
      expect(app.refreshes, 3);
      expect(
        (await repo.readCycle('2026-09-15', now: now))
            .starts
            .where((s) => s.date == '2026-09-10'),
        hasLength(1),
      );

      await (await LocalDb.instance).delete('compute_jobs');
      expect(
        (await repo.saveCycleStart(
          const CycleStart(
            date: '2026-09-10',
            kind: kCycleStartKind,
            note: 'late',
          ),
          expected: start,
          now: now,
        ))
            .committed,
        isTrue,
      );
      expect(await LocalDb.computeJobs(), isEmpty);
    });
  });
}

class _WakeApp extends AppState {
  _WakeApp() : super.forTesting();

  var failWake = false;
  var refreshes = 0;

  @override
  Future<void> refreshCycleContext() async {
    refreshes++;
    if (failWake) throw StateError('cycle context wake failed');
    await super.refreshCycleContext();
  }
}
