import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/health/health_export.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late LocalOpenBandRepository repo;
  const day = '2026-09-27';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({kHealthSyncPref: false});
    await LocalDb.close();
    LocalDb.dbName = 'openband_g3_local_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/${LocalDb.dbName}');
    app = AppState.forTesting();
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    repo = LocalOpenBandRepository(app);
  });
  tearDown(() async {
    app.dispose();
    await LocalDb.close();
  });

  Future<void> putDay(Map<String, dynamic> payload, {bool partial = false}) =>
      LocalDb.putDayResult(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode(payload),
        windowJson: '{}',
        partial: partial,
      );

  test(
    'stored trusted baseline is the only source of the personal band',
    () async {
      await putDay({
        'baselines': {
          'recovery': {
            'baseline': 68,
            'spread': 8 / 1.253,
            'status': 'trusted',
            'n_valid': 20,
          },
        },
      });
      final result = await repo.readPersonalRange(G3Metric.recovery, day);
      expect(result.status.phase, BaselinePhase.trusted);
      expect(result.range!.low, closeTo(60, .0001));
      expect(result.range!.median, 68);
      expect(result.range!.high, closeTo(76, .0001));
      expect(
        (await repo.readPersonalRange(G3Metric.skinTempZ, day)).range,
        isNull,
      );
    },
  );

  test(
    'stored readiness gate supplies count; absent basis stays unknown',
    () async {
      await putDay({
        'clinical': {
          'readiness_composite': {'note': 'need_baseline:have=11,need=14'},
        },
      });
      var result = await repo.readPersonalRange(G3Metric.recovery, day);
      expect(result.status.phase, BaselinePhase.building);
      expect(result.status.nightsHave, 11);
      expect(result.status.nightsNeeded, 14);
      await putDay({
        'clinical': {
          'readiness_composite': {'note': 'missing_hrv'},
        },
      });
      result = await repo.readPersonalRange(G3Metric.recovery, day);
      expect(result.status.nightsHave, isNull);
      expect(result.status.nightsNeeded, 14);
    },
  );

  test('missing or partial selected day has no personal range', () async {
    expect((await repo.readPersonalRange(G3Metric.hrv, day)).range, isNull);
    await putDay({
      'baselines': {
        'hrv': {'baseline': 45, 'spread': 5, 'status': 'trusted'},
      },
    }, partial: true);
    expect((await repo.readPersonalRange(G3Metric.hrv, day)).range, isNull);
  });

  test(
    'trend and week preserve missing days and stored goal absence',
    () async {
      final db = await LocalDb.instance;
      for (final (date, value) in [
        ('2026-09-21', 66),
        ('2026-09-25', 49),
        ('2026-09-27', 74),
      ]) {
        await db.insert('metric_series', {
          'date': date,
          'key': 'readiness',
          'value': value,
        });
      }
      final trend = await repo.readTrend(G3Metric.recovery, day, 7);
      expect(trend.points.map((p) => p.value), [
        66,
        null,
        null,
        null,
        49,
        null,
        74,
      ]);
      expect(trend.valueCount, 3);
      expect(trend.insufficient, 4);
      final week = await repo.readWeekStrip(G3Metric.recovery, day);
      expect(week.range, isNull);
      expect(week.days.every((v) => v.outOfRange == null), isTrue);
      expect(
        (await repo.readWeekStrip(G3Metric.sleepMinutes, day)).goal,
        isNull,
      );
    },
  );

  test(
    'suggestion is unconfirmed, changes sport, and dismisses without session',
    () async {
      final start = DateTime(2026, 9, 27, 7, 58).millisecondsSinceEpoch ~/ 1000;
      final end = DateTime(2026, 9, 27, 8, 40).millisecondsSinceEpoch ~/ 1000;
      await LocalDb.putWorkoutSuggestion({
        'id': 'detected-1',
        'date': day,
        'start_ts': start,
        'end_ts': end,
        'sport': 'running',
        'avg_bpm': 148,
        'peak_bpm': 176,
        'created_at': start * 1000,
      });
      var activity = (await repo.readActivities(day)).single;
      expect(activity.confirmed, isFalse);
      expect(activity.strain, isNull);
      expect(activity.zoneMinutes, isNull);
      expect(activity.opticalShare, isNull);
      expect(activity.hrRecoveryOneMinute, isNull);
      await putDay({
        'workout_suggestions': [
          {'start': start, 'end': end, 'hrr_bpm': 31},
        ],
      });
      expect((await repo.readActivities(day)).single.hrRecoveryOneMinute, 31);
      await repo.changeSuggestionSport('detected-1', 'cycling');
      activity = (await repo.readActivities(day)).single;
      expect(activity.sport, 'cycling');
      await repo.dismissSuggestion('detected-1');
      expect(await repo.readActivities(day), isEmpty);
      expect(await LocalDb.session('detected-1'), isNull);
    },
  );

  test(
    'confirm uses the manual session write and retires suggestion',
    () async {
      final start = DateTime(2026, 9, 27, 7, 58).millisecondsSinceEpoch ~/ 1000;
      final end = DateTime(2026, 9, 27, 8, 40).millisecondsSinceEpoch ~/ 1000;
      await LocalDb.putWorkoutSuggestion({
        'id': 'detected-2',
        'date': day,
        'start_ts': start,
        'end_ts': end,
        'sport': 'running',
        'created_at': start * 1000,
      });
      final sessionId = await repo.confirmSuggestion('detected-2');
      expect((await LocalDb.session(sessionId))?['source'], 'auto');
      expect(await repo.confirmSuggestion('detected-2'), sessionId);
      final db = await LocalDb.instance;
      expect((await db.query('sessions')).length, 1);
      expect(await HealthExporter.exportWorkoutId(sessionId), isFalse);
      expect(
        (await LocalDb.activeWorkoutSuggestions()).any(
          (row) => row['id'] == 'detected-2',
        ),
        isFalse,
      );
      expect((await repo.readActivities(day)).single.confirmed, isTrue);
    },
  );

  test('failed suggestion dismissal rolls back the session insert', () async {
    final start = DateTime(2026, 9, 27, 7, 58).millisecondsSinceEpoch ~/ 1000;
    await LocalDb.putWorkoutSuggestion({
      'id': 'detected-rollback',
      'date': day,
      'start_ts': start,
      'end_ts': start + 42 * 60,
      'sport': 'running',
      'created_at': start * 1000,
    });
    final db = await LocalDb.instance;
    await db.execute('''
      CREATE TRIGGER fail_suggestion_dismissal
      BEFORE UPDATE OF dismissed ON workout_suggestions
      BEGIN SELECT RAISE(ABORT, 'simulated dismissal failure'); END
    ''');
    await expectLater(
      repo.confirmSuggestion('detected-rollback'),
      throwsA(isA<Exception>()),
    );
    expect(await db.query('sessions'), isEmpty);
    expect(
      (await LocalDb.activeWorkoutSuggestions()).single['id'],
      'detected-rollback',
    );
    await db.execute('DROP TRIGGER fail_suggestion_dismissal');
    final id = await repo.confirmSuggestion('detected-rollback');
    expect((await LocalDb.session(id))?['source'], 'auto');
  });

  test(
    'retained HR creates 30-second slots with a gap and quality share',
    () async {
      final start = DateTime(2026, 9, 27, 7, 58).millisecondsSinceEpoch ~/ 1000;
      await LocalDb.putSession({
        'id': 'run-1',
        'start_ts': start,
        'end_ts': start + 90,
        'type': 'running',
        'status': 'done',
        'source': 'manual',
        'created_at': start * 1000,
        'hrr_bpm': 31,
        'zone_min_json': jsonEncode([1, 0, 0, 0, 0]),
        'trace_json': jsonEncode({
          'zone_bands': [
            for (var i = 0; i < 5; i++)
              {'source': 'karvonen', 'hi': i == 4 ? 186 : 100 + i * 20},
          ],
        }),
      });
      final db = await LocalDb.instance;
      for (var i = 0; i < 90; i++) {
        if (i >= 30 && i < 60) continue;
        await db.insert('decoded_onehz', {
          'device_id': '',
          'ts_ms': (start + i) * 1000,
          'rec_ts': start + i,
          'counter': i + 1,
          'hr': 148,
          'signal_quality_logvar': i < 30 ? -5.0 : -4.0,
        });
      }
      final result = (await repo.readActivities(day)).single;
      expect(result.hrTrace.map((p) => p.meanBpm), [148, null, 148]);
      expect(result.signalGaps.single.duration, const Duration(seconds: 30));
      expect(result.opticalShare, .5);
      expect(result.hrRecoveryOneMinute, 31);
      expect(result.zoneMinutes, [1, 0, 0, 0, 0]);
      expect(result.zoneBasis!.method, 'karvonen');
      expect(result.zoneBasis!.maxHr, 186);
      expect(result.zoneBasis!.maxHrSource, G3MaxHrSource.measured);
    },
  );

  test(
    'missing crossday inputs, journal answers, and weight stay distinct',
    () async {
      final plus = await repo.readSleepPlus(
        day,
        now: DateTime(2026, 9, 27, 12),
      );
      expect(plus.regularity.value, isNull);
      expect(plus.regularity.gate, isNotNull);
      expect(plus.socialJetlag.value, isNull);
      expect(plus.sleepDebt.debtHours, isNull);
      expect(plus.sleepDebt.refusalNote, isNotNull);
      expect(plus.needMinutes, isNull);
      expect(plus.napsIncomplete, isNull);
      expect(plus.typicalEfficiency, isNull);
      expect(plus.bedtime, isNull);
      expect(plus.wake, isNull);

      var checkIn = await repo.readCheckIn(day);
      expect(checkIn.total, 4);
      expect(checkIn.answered, 0);
      await repo.answerCheckIn(day, 'mood', const JournalMetricValue(4));
      checkIn = await repo.readCheckIn(day);
      expect(checkIn.answered, 1);
      expect(checkIn.questions.first.value?.value, 4);
      await expectLater(
        repo.answerCheckIn(day, 'weight_kg', const JournalMetricValue(78)),
        throwsArgumentError,
      );
      final weight = await repo.readG3Weight(day, 7);
      expect(weight.history.entries, isEmpty);
      expect(weight.sources, isEmpty);
    },
  );

  test(
    'stored crossday values are read only for their own day and version',
    () async {
      Map<String, dynamic> artifact(String builtFor) => {
        'built_for_day': builtFor,
        'algo_version': kAlgoVersion,
        'regularity': {
          'value': {'sri': 82, 'days': 7},
        },
        'social_jetlag': {
          'value': {'abs_hours': 1.5},
        },
        'sleep_debt': {
          'value': {
            'osd_hours': 8.2,
            'habitual_hours': 7.8,
            'debt_hours': .4,
            'has_free_night': true,
          },
        },
        'load': {
          'value': {'ctl': 12, 'atl': 19},
        },
      };
      await LocalDb.putBaseline('crossday', jsonEncode(artifact(day)));
      var plus = await repo.readSleepPlus(day, now: DateTime(2026, 9, 27, 12));
      expect(plus.regularity.value, 82);
      expect(plus.socialJetlag.value, 1.5);
      expect(plus.sleepDebt.freeNightP75Hours, 8.2);
      expect(plus.sleepDebt.habitualMedianHours, 7.8);
      expect(plus.sleepDebt.debtHours, .4);
      expect(plus.sleepDebt.hasFreeNight, isTrue);
      var load = await repo.readWeeklyLoad(day);
      expect(load.ctl, 12);
      expect(load.atl, 19);

      final withoutFreeNight = artifact(day);
      withoutFreeNight['sleep_debt'] = {
        'value': {'habitual_hours': 7.8, 'has_free_night': false},
        'note': 'need_free_night:have=0,need=1',
      };
      await LocalDb.putBaseline('crossday', jsonEncode(withoutFreeNight));
      plus = await repo.readSleepPlus(day, now: DateTime(2026, 9, 27, 12));
      expect(plus.sleepDebt.hasFreeNight, isFalse);
      expect(plus.sleepDebt.habitualMedianHours, 7.8);
      expect(plus.sleepDebt.freeNightP75Hours, isNull);
      expect(plus.sleepDebt.debtHours, isNull);
      expect(plus.sleepDebt.refusalNote, 'need_free_night:have=0,need=1');

      await LocalDb.putBaseline('crossday', jsonEncode(artifact('2026-09-26')));
      plus = await repo.readSleepPlus(day, now: DateTime(2026, 9, 27, 12));
      expect(plus.regularity.value, isNull);
      load = await repo.readWeeklyLoad(day);
      expect(load.ctl, isNull);
    },
  );

  test(
    'sleep plan exposes stored need and incomplete nap contribution',
    () async {
      final built = DateTime(2026, 9, 27, 9, 38);
      await LocalDb.putSleepGoalPeriod(validFromDay: day, minutes: 465);
      await LocalDb.putBaseline(
        'crossday',
        jsonEncode({
          'built_for_day': day,
          'algo_version': kAlgoVersion,
          'built_at_epoch': built.millisecondsSinceEpoch ~/ 1000,
          'sleep_coach': {
            'need': {
              'value': {'need_sec': 485 * 60},
            },
            'bedtime': {
              'value': {'bedtime_min_of_day': 22 * 60 + 18},
            },
            'wake': {
              'value': {'wake_min_of_day': 6 * 60 + 54},
            },
            'strain_bonus_min': 20,
            'nap_credit_min': '—',
          },
        }),
      );
      final plus = await repo.readSleepPlus(
        day,
        now: DateTime(2026, 9, 27, 12),
      );
      expect(plus.goalMinutes, 465);
      expect(plus.needMinutes, 485);
      expect(plus.strainBonusMinutes, 20);
      expect(plus.napCreditMinutes, isNull);
      expect(plus.napsIncomplete, isTrue);
      expect(plus.typicalEfficiency, isNull);
      expect(plus.bedtime, DateTime(2026, 9, 27, 22, 18));
      expect(plus.wake, DateTime(2026, 9, 28, 6, 54));
    },
  );

  test('open live session keeps unknown end and duration absent', () async {
    final start = DateTime(2026, 9, 27, 7, 58).millisecondsSinceEpoch ~/ 1000;
    await LocalDb.putSession({
      'id': 'live-1',
      'start_ts': start,
      'type': 'running',
      'status': 'live',
      'source': 'manual',
      'created_at': start * 1000,
    });
    final activity = (await repo.readActivities(day)).single;
    expect(activity.source, G3ActivitySource.live);
    expect(activity.confirmed, isTrue);
    expect(activity.end, isNull);
    expect(activity.duration, isNull);
    expect(activity.hrRecoveryOneMinute, isNull);
  });
}
