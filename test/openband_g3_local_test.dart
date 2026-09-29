import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
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

  Future<G3SleepPlus> readCoachParts({
    required double osdHours,
    required double debtHours,
    required double needMinutes,
    required int strainBonus,
    required int napCredit,
  }) async {
    await LocalDb.putBaseline(
      'crossday',
      jsonEncode({
        'built_for_day': day,
        'algo_version': kAlgoVersion,
        'built_at_epoch':
            DateTime(2026, 9, 27, 9, 38).millisecondsSinceEpoch ~/ 1000,
        'sleep_debt': {
          'value': {
            'osd_hours': osdHours,
            'debt_hours': debtHours,
            'has_free_night': true,
          },
        },
        'sleep_coach': {
          'need': {
            'value': {'need_sec': needMinutes * 60},
          },
          'bedtime': {
            'value': {'bedtime_min_of_day': 23 * 60},
          },
          'wake': {
            'value': {'wake_min_of_day': 7 * 60},
          },
          'strain_bonus_min': strainBonus,
          'nap_credit_min': napCredit,
        },
      }),
    );
    return repo.readSleepPlus(day, now: DateTime(2026, 9, 27, 12));
  }

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
        'readiness_absent_diag': {'note': 'need_baseline:have=11,need=14'},
      });
      var result = await repo.readPersonalRange(G3Metric.recovery, day);
      expect(result.status.phase, BaselinePhase.building);
      expect(result.status.nightsHave, 11);
      expect(result.status.nightsNeeded, 14);
      await putDay({
        'readiness_absent_diag': {'note': 'missing_hrv'},
      });
      result = await repo.readPersonalRange(G3Metric.recovery, day);
      expect(result.status.phase, BaselinePhase.none);
      expect(result.status.nightsHave, isNull);
      expect(result.status.nightsNeeded, isNull);
      await putDay({
        'readiness_absent_diag': {'note': 'unstable_baseline:z=4.2'},
      });
      result = await repo.readPersonalRange(G3Metric.recovery, day);
      expect(result.status.phase, BaselinePhase.none);
      expect(result.status.nightsNeeded, isNull);
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
      expect(activity.hrTrace.length, 42);
      expect(activity.hrTrace.every((p) => p.meanBpm == null), isTrue);
      expect(activity.signalGaps.single.duration, const Duration(minutes: 42));
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
    'confirm banks scored trace, HRR and retires overlapping suggestions',
    () async {
      final start = DateTime(2026, 9, 27, 7, 58).millisecondsSinceEpoch ~/ 1000;
      final end = DateTime(2026, 9, 27, 8, 40).millisecondsSinceEpoch ~/ 1000;
      app.user = {'birth_date': '1994-01-01'};
      await LocalDb.putWorkoutSuggestion({
        'id': 'detected-2',
        'date': day,
        'start_ts': start,
        'end_ts': end,
        'sport': 'running',
        'created_at': start * 1000,
      });
      await LocalDb.putWorkoutSuggestion({
        'id': 'detected-fragment',
        'date': day,
        'start_ts': start + 60,
        'end_ts': end - 60,
        'sport': 'running',
        'created_at': start * 1000,
      });
      await putDay({
        'workout_suggestions': [
          {'start': start, 'end': end, 'hrr_bpm': 31},
        ],
      });
      final db = await LocalDb.instance;
      for (var i = 0; i < 60; i++) {
        await db.insert('decoded_onehz', {
          'device_id': '',
          'ts_ms': (start + i) * 1000,
          'rec_ts': start + i,
          'counter': i + 1,
          'hr': 148,
          'signal_quality_logvar': -5.0,
        });
      }
      final sessionId = await repo.confirmSuggestion('detected-2');
      final saved = (await LocalDb.session(sessionId))!;
      expect(saved['source'], 'auto');
      expect(saved['hrr_bpm'], 31);
      expect(saved['zone_min_json'], isNotNull);
      expect(saved['trace_json'], isNotNull);
      final trace = jsonDecode(saved['trace_json'] as String) as Map;
      expect((trace['zone_bands'] as List).last['source'], 'tanaka');
      expect(
        (await repo.readActivities(day)).single.zoneBasis!.kind,
        G3ZoneBasisKind.hfmaxEstimated,
      );
      expect(await repo.confirmSuggestion('detected-2'), sessionId);
      expect((await db.query('sessions')).length, 1);
      expect(await HealthExporter.exportWorkoutId(sessionId), isFalse);
      expect(await LocalDb.activeWorkoutSuggestions(), isEmpty);
      await db.delete('decoded_onehz');
      final frozen = (await repo.readActivities(day)).single;
      expect(frozen.hrTrace.first.meanBpm, 148);
      expect(frozen.hrTrace.skip(1).every((p) => p.meanBpm == null), isTrue);
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
    'prior HRR counts only numeric same-sport starts strictly earlier',
    () async {
      final start = DateTime(2026, 9, 27, 7, 58).millisecondsSinceEpoch ~/ 1000;
      for (final (id, offset, sport, hrr) in [
        ('prior-day', -86400, 'running', 20),
        ('prior-hour', -3600, 'running', 31),
        ('same-start', 0, 'running', 25),
        ('later', 3600, 'running', 28),
        ('other-sport', -7200, 'cycling', 19),
      ]) {
        await LocalDb.putSession({
          'id': id,
          'start_ts': start + offset,
          'end_ts': start + offset + 60,
          'type': sport,
          'status': 'done',
          'source': 'manual',
          'created_at': start * 1000,
          'hrr_bpm': hrr,
        });
      }
      await LocalDb.putWorkoutSuggestion({
        'id': 'target',
        'date': day,
        'start_ts': start,
        'end_ts': start + 120,
        'sport': 'running',
        'created_at': start * 1000,
      });
      final activity = (await repo.readActivities(
        day,
      )).singleWhere((v) => v.id == 'target');
      expect(activity.priorHrrCount, 2);
    },
  );

  test('retained HR uses clock minutes and engine off-wrist gaps', () async {
    final start = DateTime(2026, 9, 27, 7, 58).millisecondsSinceEpoch ~/ 1000;
    await LocalDb.putSession({
      'id': 'run-1',
      'start_ts': start,
      'end_ts': start + 300,
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
    for (var i = 0; i < 300; i++) {
      if (i >= 60 && i < 200 || i >= 260) continue;
      await db.insert('decoded_onehz', {
        'device_id': '',
        'ts_ms': (start + i) * 1000,
        'rec_ts': start + i,
        'counter': i + 1,
        'hr': 148,
        'signal_quality_logvar': i < 60 ? -5.0 : -4.0,
      });
    }
    final result = (await repo.readActivities(day)).single;
    expect(result.hrTrace.map((p) => p.meanBpm), [148, null, null, 148, 148]);
    expect(
      result.signalGaps.map((g) => g.duration),
      contains(const Duration(seconds: 140)),
    );
    expect(result.opticalShare, .5);
    expect(result.hrRecoveryOneMinute, 31);
    expect(result.zoneMinutes, [1, 0, 0, 0, 0]);
    expect(result.zoneBasis!.kind, G3ZoneBasisKind.heartRateReserve);
    expect(result.zoneBasis!.maxHr, 186);
  });

  test(
    'missing crossday inputs, journal answers, and weight stay distinct',
    () async {
      final plus = await repo.readSleepPlus(
        day,
        now: DateTime(2026, 9, 27, 12),
      );
      expect(plus.regularity.value, isNull);
      expect(plus.regularity.gate, isNull);
      expect(plus.socialJetlag.value, isNull);
      expect(plus.socialJetlag.gate, isNull);
      expect(plus.sleepDebt.debtHours, isNull);
      expect(plus.sleepDebt.refusalNote, isNull);
      expect(plus.needMinutes, isNull);
      expect(plus.baselineOsdMinutes, isNull);
      expect(plus.appliedDebtMinutes, isNull);
      expect(plus.needClamp, isNull);
      expect(plus.napsJudged, isNull);
      expect(plus.typicalEfficiency, isNull);
      expect(plus.bedtime, isNull);
      expect(plus.wake, isNull);

      var checkIn = await repo.readCheckIn(day);
      expect(checkIn.total, 4);
      expect(checkIn.answered, 0);
      expect((await repo.readJournalDay(day)).metrics['alcohol_units'], isNull);
      expect(checkIn.questions.map((q) => q.targetDay), [
        '2026-09-26',
        '2026-09-26',
        day,
        '2026-09-26',
      ]);
      expect(checkIn.questions.map((q) => q.kind), [
        G3CheckInKind.yesNo,
        G3CheckInKind.yesNo,
        G3CheckInKind.rating,
        G3CheckInKind.freeNote,
      ]);
      await repo.answerCheckIn(
        day,
        'alcohol_evening',
        const G3YesNoAnswer(false),
      );
      await repo.answerCheckIn(day, 'alcohol_units', const G3QuantityAnswer(0));
      expect(
        (await repo.readJournalDay(
          '2026-09-26',
        )).metrics['alcohol_units']?.value,
        0,
      );
      await repo.answerCheckIn(day, 'mood', const G3RatingAnswer(4));
      await repo.answerCheckIn(
        day,
        'journal_note',
        const G3FreeNoteAnswer('Ruhig'),
      );
      checkIn = await repo.readCheckIn(day);
      expect(checkIn.answered, 3);
      expect((checkIn.questions.first.answer as G3YesNoAnswer).value, isFalse);
      expect((checkIn.questions[2].answer as G3RatingAnswer).value, 4);
      expect(
        (checkIn.questions.last.answer as G3FreeNoteAnswer).value,
        'Ruhig',
      );
      await expectLater(
        repo.answerCheckIn(day, 'mood', const G3YesNoAnswer(true)),
        throwsArgumentError,
      );
      await expectLater(
        repo.answerCheckIn(day, 'mood', const G3RatingAnswer(0)),
        throwsArgumentError,
      );
      await expectLater(
        repo.answerCheckIn(day, 'weight_kg', const G3QuantityAnswer(78)),
        throwsArgumentError,
      );
      final weight = await repo.readG3Weight(day, 7);
      expect(weight.history.entries, isEmpty);
      expect(weight.sources, isEmpty);
    },
  );

  test('imported kg remains separate from journal weight history', () async {
    final db = await LocalDb.instance;
    final inWindow = DateTime(2026, 9, 27, 8).millisecondsSinceEpoch ~/ 1000;
    for (final (id, ts, kind, unit) in [
      ('weight-1', inWindow, 'weight_kg', 'kg'),
      ('old-weight', inWindow - 8 * 86400, 'weight_kg', 'kg'),
      ('wrong-unit', inWindow, 'weight_kg', 'lb'),
      ('temperature', inWindow, 'body_temp', 'kg'),
    ]) {
      await db.insert('imported_measurement', {
        'uuid': id,
        'ts': ts,
        'kind': kind,
        'unit': unit,
        'value': 74.2,
        'source': 'Apple Health',
      });
    }
    final weight = await repo.readG3Weight(day, 7);
    expect(weight.history.entries, isEmpty);
    expect(weight.imported.map((v) => v.id), ['weight-1']);
    expect(weight.imported.single.kg, 74.2);
    expect(weight.imported.single.source, G3WeightSource.imported);
    expect(weight.imported.single.sourceName, 'Apple Health');
  });

  test('last band sample is bounded to the selected local day', () async {
    expect(await repo.readLastBandSampleAt(day), isNull);
    final db = await LocalDb.instance;
    final sample = DateTime(2026, 9, 27, 23, 58).millisecondsSinceEpoch ~/ 1000;
    for (final (id, ts) in [
      (1, sample - 60),
      (2, sample),
      (3, sample + 3 * 60),
    ]) {
      await db.insert('decoded_onehz', {
        'device_id': '',
        'ts_ms': ts * 1000,
        'rec_ts': ts,
        'counter': id,
        'hr': 70,
      });
    }
    expect(await repo.readLastBandSampleAt(day), DateTime(2026, 9, 27, 23, 58));
    expect(await repo.readLastBandSampleAt('2026-09-26'), isNull);
    expect(
      await repo.readLastBandSampleAt('2026-09-28'),
      DateTime(2026, 9, 28, 0, 1),
    );
  });

  test(
    'stored crossday values are read only for their own day and version',
    () async {
      Map<String, dynamic> artifact(String builtFor) => {
        'built_for_day': builtFor,
        'algo_version': kAlgoVersion,
        'regularity': {
          'value': {
            'sri': 82,
            'days': 7,
            'pairs': [
              {
                'prev_date': '2026-09-25',
                'date': '2026-09-26',
                'sri': 76.5,
                'agreement': 706,
                'cases': 800,
              },
            ],
          },
        },
        'social_jetlag': {
          'value': {
            'sjl_hours': 1.5,
            'abs_hours': 1.5,
            'mid_sleep_work_h': 3.25,
            'mid_sleep_free_h': 4.75,
            'n_work': 5,
            'n_free': 2,
          },
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
      expect(plus.regularityDetail!.days, 7);
      expect(plus.regularityDetail!.pairs!.single.previousDay, '2026-09-25');
      expect(plus.regularityDetail!.pairs!.single.day, '2026-09-26');
      expect(plus.regularityDetail!.pairs!.single.sri, 76.5);
      expect(plus.regularityDetail!.pairs!.single.cases, 800);
      expect(plus.socialJetlag.value, 1.5);
      expect(plus.socialJetlagDetail!.signedHours, 1.5);
      expect(plus.socialJetlagDetail!.midSleepWorkHours, 3.25);
      expect(plus.socialJetlagDetail!.midSleepFreeHours, 4.75);
      expect(plus.socialJetlagDetail!.workNights, 5);
      expect(plus.socialJetlagDetail!.freeNights, 2);
      expect(plus.sleepDebt.freeNightP75Hours, 8.2);
      expect(plus.sleepDebt.habitualMedianHours, 7.8);
      expect(plus.sleepDebt.debtHours, .4);
      expect(plus.sleepDebt.hasFreeNight, isTrue);
      var load = await repo.readWeeklyLoad(day);
      expect(load.ctl, 12);
      expect(load.atl, 19);

      final earlierFreeDays = artifact(day);
      earlierFreeDays['social_jetlag'] = {
        'value': {
          'sjl_hours': -1.5,
          'abs_hours': 1.5,
          'mid_sleep_work_h': 3.25,
          'mid_sleep_free_h': 1.75,
          'n_work': 5,
          'n_free': 2,
        },
      };
      await LocalDb.putBaseline('crossday', jsonEncode(earlierFreeDays));
      plus = await repo.readSleepPlus(day, now: DateTime(2026, 9, 27, 12));
      expect(plus.socialJetlag.value, 1.5);
      expect(plus.socialJetlagDetail!.signedHours, -1.5);

      final noSignedValue = artifact(day);
      (noSignedValue['social_jetlag']['value'] as Map).remove('sjl_hours');
      await LocalDb.putBaseline('crossday', jsonEncode(noSignedValue));
      plus = await repo.readSleepPlus(day, now: DateTime(2026, 9, 27, 12));
      expect(plus.socialJetlag.value, 1.5);
      expect(plus.socialJetlagDetail!.signedHours, isNull);

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

      final gated = artifact(day);
      gated['regularity'] = {
        'value': {'sri': 82, 'days': 4},
        'note': 'needs_7_scored_nights:have=4',
      };
      await LocalDb.putBaseline('crossday', jsonEncode(gated));
      plus = await repo.readSleepPlus(day, now: DateTime(2026, 9, 27, 12));
      expect(plus.regularity.value, isNull);
      expect(plus.regularity.gate, 'needs_7_scored_nights:have=4');
      expect(plus.regularityDetail!.days, 4);
      expect(plus.regularityDetail!.pairs, isNull);

      final refused = artifact(day);
      refused['regularity'] = {
        'value': '—',
        'note': 'needs_7_scored_nights:have=0',
      };
      refused['social_jetlag'] = {
        'value': '—',
        'note': 'need_work_and_free_nights',
      };
      await LocalDb.putBaseline('crossday', jsonEncode(refused));
      plus = await repo.readSleepPlus(day, now: DateTime(2026, 9, 27, 12));
      expect(plus.regularityDetail, isNull);
      expect(plus.socialJetlagDetail, isNull);
      expect(plus.regularity.gate, 'needs_7_scored_nights:have=0');
      expect(plus.socialJetlag.gate, 'need_work_and_free_nights');

      await LocalDb.putBaseline('crossday', jsonEncode(artifact('2026-09-26')));
      plus = await repo.readSleepPlus(day, now: DateTime(2026, 9, 27, 12));
      expect(plus.regularity.value, isNull);
      expect(plus.regularity.gate, isNull);
      expect(plus.regularityDetail, isNull);
      expect(plus.socialJetlag.value, isNull);
      expect(plus.socialJetlag.gate, isNull);
      expect(plus.socialJetlagDetail, isNull);
      expect(plus.sleepDebt.debtHours, isNull);
      expect(plus.sleepDebt.refusalNote, isNull);
      load = await repo.readWeeklyLoad(day);
      expect(load.ctl, isNull);

      final oldAlgo = artifact(day)..['algo_version'] = kAlgoVersion - 1;
      await LocalDb.putBaseline('crossday', jsonEncode(oldAlgo));
      plus = await repo.readSleepPlus(day, now: DateTime(2026, 9, 27, 12));
      expect(plus.regularity.value, isNull);
      expect(plus.regularity.gate, isNull);
      expect(plus.socialJetlag.gate, isNull);
      expect(plus.sleepDebt.refusalNote, isNull);
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
          'sleep_debt': {
            'value': {
              'osd_hours': 455 / 60,
              'debt_hours': 10 / 60,
              'has_free_night': true,
            },
          },
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
      expect(plus.baselineOsdMinutes, closeTo(455, 1e-9));
      expect(plus.appliedDebtMinutes, isNull);
      expect(plus.needClamp, isNull);
      expect(plus.strainBonusMinutes, 20);
      expect(plus.napCreditMinutes, isNull);
      expect(plus.napsJudged, isFalse);
      expect(plus.typicalEfficiency, isNull);
      expect(plus.bedtime, DateTime(2026, 9, 27, 22, 18));
      expect(plus.wake, DateTime(2026, 9, 28, 6, 54));
    },
  );

  test('sleep need components come from OSD and debt, not goal', () async {
    await LocalDb.putSleepGoalPeriod(validFromDay: day, minutes: 465);
    await LocalDb.putBaseline(
      'crossday',
      jsonEncode({
        'built_for_day': day,
        'algo_version': kAlgoVersion,
        'built_at_epoch':
            DateTime(2026, 9, 27, 9, 38).millisecondsSinceEpoch ~/ 1000,
        'sleep_debt': {
          'value': {
            'osd_hours': 455 / 60,
            'habitual_hours': 445 / 60,
            'debt_hours': 10 / 60,
            'has_free_night': true,
          },
        },
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
          'nap_credit_min': 0,
        },
      }),
    );
    var plus = await repo.readSleepPlus(day, now: DateTime(2026, 9, 27, 12));
    expect(plus.goalMinutes, 465);
    expect(plus.needMinutes, 485);
    expect(plus.baselineOsdMinutes, closeTo(455, 1e-9));
    expect(plus.appliedDebtMinutes, closeTo(10, 1e-9));
    expect(plus.strainBonusMinutes, 20);
    expect(plus.napCreditMinutes, 0);
    expect(plus.napsJudged, isTrue);

    await LocalDb.putBaseline(
      'crossday',
      jsonEncode({
        'built_for_day': day,
        'algo_version': kAlgoVersion,
        'built_at_epoch':
            DateTime(2026, 9, 27, 9, 38).millisecondsSinceEpoch ~/ 1000,
        'sleep_debt': {
          'value': {
            'osd_hours': 6.5,
            'debt_hours': -0.25,
            'has_free_night': true,
          },
        },
        'sleep_coach': {
          'need': {
            'value': {'need_sec': 420 * 60},
          },
          'bedtime': {
            'value': {'bedtime_min_of_day': 23 * 60},
          },
          'wake': {
            'value': {'wake_min_of_day': 6 * 60 + 27},
          },
          'strain_bonus_min': 0,
          'nap_credit_min': 0,
        },
      }),
    );
    plus = await repo.readSleepPlus(day, now: DateTime(2026, 9, 27, 12));
    expect(plus.baselineOsdMinutes, 420);
    expect(plus.appliedDebtMinutes, 0);

    await LocalDb.putBaseline(
      'crossday',
      jsonEncode({
        'built_for_day': day,
        'algo_version': kAlgoVersion,
        'built_at_epoch':
            DateTime(2026, 9, 27, 9, 38).millisecondsSinceEpoch ~/ 1000,
        'sleep_debt': {
          'value': {
            'osd_hours': 9.5,
            'debt_hours': 165 / 60,
            'has_free_night': true,
          },
        },
        'sleep_coach': {
          'need': {
            'value': {'need_sec': 660 * 60},
          },
          'bedtime': {
            'value': {'bedtime_min_of_day': 20 * 60},
          },
          'wake': {
            'value': {'wake_min_of_day': 7 * 60 + 42},
          },
          'strain_bonus_min': 0,
          'nap_credit_min': 0,
        },
      }),
    );
    plus = await repo.readSleepPlus(day, now: DateTime(2026, 9, 27, 12));
    expect(plus.needMinutes, 660);
    expect(plus.sleepDebt.debtHours, closeTo(165 / 60, 1e-9));
    expect(plus.baselineOsdMinutes, 570);
    expect(plus.appliedDebtMinutes, 165);
    expect(plus.needClamp?.limitMinutes, 660);
    expect(plus.strainBonusMinutes, 0);
    expect(plus.napCreditMinutes, 0);

    // Raw strain 45 and nap 120 yield a 6 h floor. The coach stores their
    // post-clamp applied deltas: strain 0 and nap 115.
    await LocalDb.putBaseline(
      'crossday',
      jsonEncode({
        'built_for_day': day,
        'algo_version': kAlgoVersion,
        'built_at_epoch':
            DateTime(2026, 9, 27, 9, 38).millisecondsSinceEpoch ~/ 1000,
        'sleep_debt': {
          'value': {
            'osd_hours': 7,
            'debt_hours': 10 / 60,
            'has_free_night': true,
          },
        },
        'sleep_coach': {
          'need': {
            'value': {'need_sec': 360 * 60},
          },
          'bedtime': {
            'value': {'bedtime_min_of_day': 23 * 60},
          },
          'wake': {
            'value': {'wake_min_of_day': 5 * 60 + 23},
          },
          'strain_bonus_min': 0,
          'nap_credit_min': 115,
        },
      }),
    );
    plus = await repo.readSleepPlus(day, now: DateTime(2026, 9, 27, 12));
    expect(plus.needMinutes, 360);
    expect(plus.baselineOsdMinutes, 420);
    expect(plus.sleepDebt.debtHours, closeTo(10 / 60, 1e-9));
    expect(plus.appliedDebtMinutes, closeTo(10, 1e-9));
    expect(plus.needClamp?.limitMinutes, 360);
    expect(plus.strainBonusMinutes, 0);
    expect(plus.napCreditMinutes, 115);
  });

  test('inconsistent need away from a clamp refuses inferred debt', () async {
    final plus = await readCoachParts(
      osdHours: 7,
      debtHours: 10 / 60,
      needMinutes: 425,
      strainBonus: 0,
      napCredit: 0,
    );
    expect(plus.appliedDebtMinutes, isNull);
    expect(plus.needClamp, isNull);
  });

  test('a need just off the 6 h limit is not labelled as the limit', () async {
    final plus = await readCoachParts(
      osdHours: 7,
      debtHours: 10 / 60,
      needMinutes: 360.4,
      strainBonus: 0,
      napCredit: 0,
    );
    expect(plus.appliedDebtMinutes, isNull);
    expect(plus.needClamp, isNull);
  });

  test('whole-minute strain bonus does not erase zero debt', () async {
    final plus = await readCoachParts(
      osdHours: 7,
      debtHours: 0,
      needMinutes: 442.5,
      strainBonus: 23,
      napCredit: 0,
    );
    expect(plus.appliedDebtMinutes, 0);
    expect(plus.needClamp, isNull);
  });

  test('sub-minute strain effect does not invent debt', () async {
    final plus = await readCoachParts(
      osdHours: 7,
      debtHours: 0,
      needMinutes: 420 + 1 / 7,
      strainBonus: 0,
      napCredit: 0,
    );
    expect(plus.appliedDebtMinutes, 0);
    expect(plus.needClamp, isNull);
  });

  test(
    'check-in reads and writes yesterday’s caffeine on its journal day',
    () async {
      const selected = '2026-03-30';
      const previous = '2026-03-29';
      await LocalDb.upsertJournalMetric(previous, 'caffeine_late', 1);
      await LocalDb.upsertJournalMetric(selected, 'caffeine_late', 0);

      var checkIn = await repo.readCheckIn(selected);
      expect((checkIn.questions[1].answer as G3YesNoAnswer).value, isTrue);
      expect(checkIn.questions.map((q) => q.targetDay), [
        previous,
        previous,
        selected,
        previous,
      ]);
      expect(g3CheckInTargetDay('2026-03-30', 'custom_meditation'), selected);

      await LocalDb.upsertJournalMetric(selected, 'caffeine_late', 1);
      await repo.answerCheckIn(
        selected,
        'caffeine_late',
        const G3YesNoAnswer(false),
      );
      expect(
        (await repo.readJournalDay(previous)).metrics['caffeine_late']?.value,
        0,
      );
      expect(
        (await repo.readJournalDay(selected)).metrics['caffeine_late']?.value,
        1,
      );
      await repo.answerCheckIn(
        selected,
        'alcohol_evening',
        const G3YesNoAnswer(true),
      );
      expect(
        (await repo.readJournalDay(previous)).metrics['alcohol_evening']?.value,
        1,
      );
      await repo.answerCheckIn(
        selected,
        'alcohol_units',
        const G3QuantityAnswer(0),
      );
      expect(
        (await repo.readJournalDay(previous)).metrics['alcohol_units']?.value,
        0,
      );
      await repo.answerCheckIn(selected, 'mood', const G3RatingAnswer(4));
      expect((await repo.readJournalDay(selected)).metrics['mood']?.value, 4);
      await repo.answerCheckIn(
        selected,
        'journal_note',
        const G3FreeNoteAnswer('Ruhig'),
      );
      expect((await repo.readJournalDay(previous)).note, 'Ruhig');
      expect((await repo.readJournalDay(selected)).note, isEmpty);
      checkIn = await repo.readCheckIn(selected);
      expect(checkIn.answered, 4);
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
