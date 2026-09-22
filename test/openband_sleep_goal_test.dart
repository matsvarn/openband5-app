import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const day = '2026-09-15';
  late AppState app;
  late LocalOpenBandRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await LocalDb.close();
    LocalDb.dbName = 'openband_sleep_goal_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/${LocalDb.dbName}');
    app = AppState.forTesting();
    repository = LocalOpenBandRepository(app);
  });

  tearDown(() async {
    app.dispose();
    await LocalDb.close();
  });

  Map<String, dynamic> crossday({
    Object? algoVersion = kAlgoVersion,
    Object? builtForDay = day,
    Object? builtAtEpoch = 1789459320,
    Object? osdHours = 8.2,
    Object? hasFreeNight = true,
    Object? confidence = 0.6,
    Object? note = 'p75 of weekend nights',
    Object? value,
  }) => {
    'algo_version': algoVersion,
    'built_for_day': builtForDay,
    'built_at_epoch': builtAtEpoch,
    'n_days': 28,
    'sleep_debt': {
      'value':
          value ??
          {
            'osd_hours': osdHours,
            'habitual_hours': 7.1,
            'has_free_night': hasFreeNight,
          },
      'confidence': confidence,
      'note': note,
    },
    'sleep_coach': {
      'need': {
        'value': {'need_sec': 28800},
      },
    },
  };

  Future<void> storeCrossday(Map<String, dynamic> artifact) =>
      LocalDb.putBaseline('crossday', jsonEncode(artifact));

  test('kAlgoVersion is the contract pin', () {
    expect(kAlgoVersion, 92);
  });

  test('field parser accepts 7h45 and rejects blank or 24h+ entries', () {
    expect(sleepGoalMinutesFromFields('7', '45'), 465);
    expect(sleepGoalMinutesFromFields('', ''), isNull);
    expect(sleepGoalMinutesFromFields('7', ''), isNull);
    expect(sleepGoalMinutesFromFields('0', '0'), isNull);
    expect(sleepGoalMinutesFromFields('24', '0'), 1440);
    expect(sleepGoalMinutesFromFields('24', '1'), isNull);
    expect(sleepGoalMinutesFromFields('-1', '0'), isNull);
  });

  test('8.2h stays 8h12 without 7–9.5 clamping', () {
    final estimate = weekendSleepEstimateFromCrossday(
      crossday(),
      selectedDay: day,
      algoVersion: kAlgoVersion,
    );
    expect(estimate, isNotNull);
    expect(estimate!.osdHours, 8.2);
    expect(obDuration(estimate.osdHours * 60), '8h12');
    expect(estimate.builtAtEpoch, 1789459320);
    expect(estimate.confidence, 0.6);
    expect(estimate.note, 'p75 of weekend nights');
  });

  test('absent OSD, habitual-only, and need_sec do not become an estimate', () {
    expect(
      weekendSleepEstimateFromCrossday(
        crossday(value: '—'),
        selectedDay: day,
        algoVersion: kAlgoVersion,
      ),
      isNull,
    );
    expect(
      weekendSleepEstimateFromCrossday(
        crossday(hasFreeNight: false, osdHours: null),
        selectedDay: day,
        algoVersion: kAlgoVersion,
      ),
      isNull,
    );
    expect(
      weekendSleepEstimateFromCrossday(
        {
          'algo_version': kAlgoVersion,
          'built_for_day': day,
          'sleep_coach': {
            'need': {
              'value': {'need_sec': 28800},
            },
          },
        },
        selectedDay: day,
        algoVersion: kAlgoVersion,
      ),
      isNull,
    );
  });

  test(
    'malformed confidence, time, version, or day withholds the estimate',
    () {
      WeekendSleepEstimate? parse(Map<String, dynamic> artifact) =>
          weekendSleepEstimateFromCrossday(
            artifact,
            selectedDay: day,
            algoVersion: kAlgoVersion,
          );
      expect(parse(crossday(confidence: 'high')), isNull);
      expect(parse(crossday(confidence: 1.2)), isNull);
      expect(parse(crossday(confidence: -0.1)), isNull);
      expect(parse(crossday(confidence: double.infinity)), isNull);
      expect(parse(crossday(builtAtEpoch: 'now')), isNull);
      expect(parse(crossday(builtAtEpoch: null)), isNull);
      expect(parse(crossday(builtAtEpoch: 0)), isNull);
      expect(parse(crossday(builtAtEpoch: -1)), isNull);
      expect(parse(crossday(builtAtEpoch: 1.5)), isNull);
      expect(
        parse(Map<String, dynamic>.from(crossday())..remove('built_at_epoch')),
        isNull,
      );
      expect(parse(crossday(algoVersion: 89)), isNull);
      expect(parse(crossday(builtForDay: '2026-09-14')), isNull);
      expect(parse(crossday(osdHours: double.nan)), isNull);
      expect(parse(crossday(note: 12)), isNull);
      expect(parse(crossday(confidence: 0)), isNotNull);
      expect(parse(crossday(confidence: 1)), isNotNull);
      expect(parse(crossday(confidence: null)), isNotNull);
      expect(parse(crossday(builtAtEpoch: 1789459320.0)), isNotNull);
      expect(parse(crossday(osdHours: 8.2))!.osdHours, 8.2);
    },
  );

  test('SQLite round trip unset, set, change, null boundary, reopen', () async {
    var snapshot = await repository.readSleepGoal(day);
    expect(snapshot.period, isNull);
    expect(snapshot.targetMinutes, isNull);
    expect(snapshot.weekendEstimate, isNull);

    await repository.saveSleepGoal(day, 465);
    snapshot = await repository.readSleepGoal(day);
    expect(snapshot.targetMinutes, 465);
    expect(snapshot.period!.validFromDay, day);
    final created = snapshot.period!.createdAt;

    await repository.saveSleepGoal(day, 480);
    snapshot = await repository.readSleepGoal(day);
    expect(snapshot.targetMinutes, 480);
    expect(snapshot.period!.createdAt, created);
    expect((await LocalDb.sleepGoalPeriods()).length, 1);

    await repository.clearSleepGoal(day);
    snapshot = await repository.readSleepGoal(day);
    expect(snapshot.period, isNotNull);
    expect(snapshot.targetMinutes, isNull);

    await LocalDb.close();
    snapshot = await repository.readSleepGoal(day);
    expect(snapshot.period, isNotNull);
    expect(snapshot.targetMinutes, isNull);
    expect((await LocalDb.sleepGoalPeriods()).length, 1);
  });

  test('failed write leaves prior periods unchanged', () async {
    await repository.saveSleepGoal(day, 465);
    final db = await LocalDb.instance;
    await db.execute('''
      CREATE TRIGGER fail_sleep_goal
      BEFORE INSERT ON sleep_goal_period
      BEGIN SELECT RAISE(ABORT, 'synthetic full disk'); END
    ''');
    await expectLater(repository.saveSleepGoal(day, 510), throwsA(anything));
    expect((await repository.readSleepGoal(day)).targetMinutes, 465);
  });

  test(
    'wake-day 15 September covers the 14/15 night and keeps other bounds',
    () async {
      await repository.saveSleepGoal('2026-09-10', 480);
      await repository.saveSleepGoal(day, 465);
      await repository.saveSleepGoal('2026-09-20', 510);

      expect((await repository.readSleepGoal('2026-09-09')).period, isNull);
      expect((await repository.readSleepGoal('2026-09-14')).targetMinutes, 480);
      expect((await repository.readSleepGoal(day)).targetMinutes, 465);
      expect((await repository.readSleepGoal('2026-09-16')).targetMinutes, 465);

      await repository.clearSleepGoal(day);
      expect((await repository.readSleepGoal('2026-09-14')).targetMinutes, 480);
      expect((await repository.readSleepGoal(day)).targetMinutes, isNull);
      expect(
        (await repository.readSleepGoal('2026-09-16')).targetMinutes,
        isNull,
      );
      expect((await repository.readSleepGoal('2026-09-20')).targetMinutes, 510);

      final rows = await LocalDb.sleepGoalPeriods();
      expect(rows.map((r) => r['valid_from_day']), [
        '2026-09-10',
        day,
        '2026-09-20',
      ]);
      expect(rows[1]['minutes'], isNull);
    },
  );

  test(
    'learned estimate is distinct from the user target and selected day',
    () async {
      await storeCrossday(crossday());
      await repository.saveSleepGoal(day, 465);

      final today = await repository.readSleepGoal(day);
      expect(today.targetMinutes, 465);
      expect(today.weekendEstimate?.osdHours, 8.2);
      expect(obDuration(today.weekendEstimate!.osdHours * 60), '8h12');

      final yesterday = await repository.readSleepGoal('2026-09-14');
      expect(yesterday.targetMinutes, isNull);
      expect(yesterday.weekendEstimate, isNull);

      await storeCrossday(crossday(hasFreeNight: false));
      expect((await repository.readSleepGoal(day)).weekendEstimate, isNull);

      await storeCrossday(crossday(osdHours: 10.2));
      expect(
        (await repository.readSleepGoal(day)).weekendEstimate!.osdHours,
        10.2,
      );
      expect(
        obDuration(
          (await repository.readSleepGoal(day)).weekendEstimate!.osdHours * 60,
        ),
        '10h12',
      );
    },
  );

  test('reject non-positive durations at the repository boundary', () async {
    await expectLater(repository.saveSleepGoal(day, 0), throwsArgumentError);
    await expectLater(repository.saveSleepGoal(day, 1441), throwsArgumentError);
    expect(await LocalDb.sleepGoalPeriods(), isEmpty);
  });
}
