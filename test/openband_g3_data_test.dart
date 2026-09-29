import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync())
      as Map,
);

SyntheticOpenBandRepository _repo(SyntheticScenario scenario) =>
    SyntheticOpenBandRepository.fromMaps(
      _fixture('day-summary.json'),
      _fixture('sleep-detail.json'),
      scenario: scenario,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const day = '2026-09-29';

  test('design day and trusted week use literal fixture values', () async {
    final repo = _repo(SyntheticScenario.g3Sample);
    final today = await repo.readDay(day);
    expect(today.recovery.value, 74);
    expect(today.recovery.baseline, 68);
    expect(
      today.recovery.baseline! - 1.253 * today.recovery.baselineSpread!,
      58,
    );
    expect(
      today.recovery.baseline! + 1.253 * today.recovery.baselineSpread!,
      78,
    );
    expect(today.sleep.duration.value, 438);
    expect(today.sleep.bedMinutes, 464);
    expect(today.sleep.onset, DateTime(2026, 9, 28, 23, 10));
    expect(today.sleep.wake, DateTime(2026, 9, 29, 6, 54));
    expect(today.sleep.segments.first.start, today.sleep.onset);
    expect(today.sleep.segments.last.end, today.sleep.wake);
    expect(
      today.sleep.segments.map((s) => s.start).skip(1),
      today.sleep.segments
          .map((s) => s.end)
          .take(today.sleep.segments.length - 1),
    );
    for (final (stage, minutes) in [
      (NightStage.deep, 68),
      (NightStage.light, 247),
      (NightStage.rem, 123),
      (NightStage.awake, 26),
    ]) {
      expect(
        today.sleep.segments
            .where((s) => s.stage == stage)
            .fold<int>(
              0,
              (sum, s) => sum + s.end.difference(s.start).inMinutes,
            ),
        minutes,
      );
    }
    expect(today.strain.value, 9.4);
    expect(today.hrv.value, 48);
    expect(today.restingHr.value, 54);
    expect(today.respiration.value, 15.8);
    expect(today.skinTemperature.value, .4);
    expect(G3Metric.skinTempZ.unit, G3ValueUnit.relativeZ);
    expect(
      (await repo.readTrend(G3Metric.skinTempZ, day, 7)).points.last.value,
      .4,
    );
    expect(today.steps.value, 6480);
    expect(today.stepIntervals.map((s) => s.steps), [820, 4630, 1030]);
    expect(today.stepIntervals.map((s) => s.start.hour), [7, 8, 9]);
    expect(today.stepIntervals.last.end, DateTime(2026, 9, 29, 9, 38));
    expect(today.calculatedAt, DateTime(2026, 9, 29, 9, 38));

    final range = await repo.readPersonalRange(G3Metric.recovery, day);
    expect(range.status.phase, BaselinePhase.trusted);
    expect(
      [range.range!.low, range.range!.median, range.range!.high],
      [58, 68, 78],
    );
    final recovery = await repo.readWeekStrip(G3Metric.recovery, day);
    expect(recovery.days.map((d) => d.value), [66, 55, 62, 71, 49, 63, 74]);
    expect(
      recovery.days.where((d) => d.outOfRange == true).map((d) => d.value),
      [55, 49],
    );
    final sleep = await repo.readWeekStrip(G3Metric.sleepMinutes, day);
    expect(sleep.goal, 465);
    expect((await repo.readSleepGoal(day)).targetMinutes, 465);
    expect(sleep.days.map((d) => d.value), [422, 391, 460, 485, 372, 445, 438]);
    expect(sleep.days.every((d) => d.outOfRange == null), isTrue);
  });

  test('trend keeps calendar gaps and counts usable values', () async {
    final repo = _repo(SyntheticScenario.g3Sample);
    for (final n in [7, 30, 90]) {
      final trend = await repo.readTrend(G3Metric.recovery, day, n);
      expect(trend.points.length, n);
      expect(trend.points.last.day, day);
      expect(trend.valueCount, 7);
      expect(trend.insufficient, isNull);
      if (n > 7) expect(trend.points.first.value, isNull);
    }
    final steps = await repo.readTrend(G3Metric.steps, day, 7);
    expect(steps.valueCount, 1);
    expect(steps.insufficient, 6);
    expect(steps.points.last.value, 6480);
    expect(() => repo.readTrend(G3Metric.hrv, day, 8), throwsArgumentError);
  });

  test('journal refusal exposes pair and side floors separately', () {
    CaffeineSleepPattern pattern(int n, int yes, int no, String note) =>
        CaffeineSleepPattern.fromProducer(
          empty: false,
          binary: true,
          insufficient: true,
          meaningful: false,
          n: n,
          nWith: yes,
          nWithout: no,
          note: note,
          endDay: day,
          startDay: '2026-09-01',
          nights: 30,
          algoVersion: 1,
        );
    final paired = G3JournalPattern(pattern(5, 3, 2, 'min_n'));
    expect(paired.yesNights, 3);
    expect(paired.noNights, 2);
    expect(paired.refusalNote, 'min_n');
    expect(paired.pairedMinimum, 8);
    expect(paired.perSideMinimum, 3);
    expect(paired.refusalGate, G3PatternRefusalGate.paired);
    expect(paired.remaining, 3);
    final side = G3JournalPattern(pattern(8, 6, 2, 'min_per_side'));
    expect(side.refusalNote, 'min_per_side');
    expect(side.yesNights, 6);
    expect(side.noNights, 2);
    expect(side.refusalGate, G3PatternRefusalGate.side);
    expect(side.remaining, isNull);
    expect(
      G3JournalPattern(pattern(8, 3, 5, 'other')).refusalGate,
      isNull,
    );
  });

  test('insufficient pattern split counts only supplied lag-1 pairs', () async {
    final repo = _repo(SyntheticScenario.g3Sample);
    repo.seedCaffeineSleepPattern(
      day,
      seed: SyntheticCaffeineSleepSeed.insufficient,
    );
    // This answer has no following wake day in the requested window.
    await repo.writeJournal(day, CaffeineSleepPattern.field, 1);
    final result = await repo.readJournalPattern(day, 30);
    expect(result.pattern.pairedN, 5);
    expect(result.yesNights, 3);
    expect(result.noNights, 2);
    expect(result.refusalGate, G3PatternRefusalGate.paired);
    expect(result.remaining, 3);
  });

  test('building fixture withholds score and normal bands', () async {
    final repo = _repo(SyntheticScenario.g3Building);
    final today = await repo.readDay(day);
    expect(today.recovery.value, isNull);
    expect(today.hrv.value, 48);
    expect(today.hrv.baseline, isNull);
    expect(today.restingHr.baseline, isNull);
    expect(today.skinTemperature.value, isNull);
    final range = await repo.readPersonalRange(G3Metric.recovery, day);
    expect(range.range, isNull);
    expect(range.status.nightsHave, 11);
    expect(range.status.nightsNeeded, 14);
    expect(range.status.remaining, 3);
    expect(
      (await repo.readWeekStrip(
        G3Metric.recovery,
        day,
      )).days.every((d) => d.value == null && d.outOfRange == null),
      isTrue,
    );
    expect((await repo.readTrend(G3Metric.recovery, day, 7)).insufficient, 7);
    expect((await repo.readPersonalRange(G3Metric.hrv, day)).range, isNull);
    expect((await repo.readPersonalRange(G3Metric.rhr, day)).range, isNull);
  });

  test(
    'activity suggestion has explicit trace gap and can be reviewed',
    () async {
      final repo = _repo(SyntheticScenario.g3Sample);
      var activity = (await repo.readActivities(day)).single;
      expect(activity.confirmed, isFalse);
      expect(activity.source, G3ActivitySource.auto);
      expect(activity.start, DateTime(2026, 9, 29, 7, 58));
      expect(activity.end, DateTime(2026, 9, 29, 8, 40));
      expect(activity.duration, const Duration(minutes: 42));
      expect(activity.zoneMinutes, isNull);
      expect(activity.zoneBasis, isNull);
      expect(activity.avgHr, 148);
      expect(activity.maxHr, 176);
      expect(activity.strain, 6.1);
      expect(activity.opticalShare, .96);
      expect(activity.hrRecoveryOneMinute, 31);
      expect(activity.hrTrace.length, 84);
      expect(activity.hrTrace.where((p) => p.meanBpm == null).length, 1);
      expect(activity.signalGaps.single.duration, const Duration(seconds: 40));
      expect(activity.priorHrrCount, 0);
      await repo.changeSuggestionSport(activity.id, 'cycling');
      expect((await repo.readActivities(day)).single.sport, 'cycling');
      expect(await repo.confirmSuggestion(activity.id), activity.id);
      activity = (await repo.readActivities(day)).single;
      expect(activity.confirmed, isTrue);
      expect(activity.zoneMinutes, [0, 4, 19, 16, 3]);
      expect(activity.zoneBasis!.kind, G3ZoneBasisKind.hfmaxEstimated);
      expect(activity.zoneBasis!.maxHr, 186);
      expect(activity.sport, 'cycling');
      await expectLater(repo.dismissSuggestion(activity.id), throwsStateError);
    },
  );

  test('dismissal and absent activity do not create a session', () async {
    final repo = _repo(SyntheticScenario.g3Sample);
    expect(await repo.readActivities('2026-09-28'), isEmpty);
    await repo.dismissSuggestion('g3-run-0758');
    expect(await repo.readActivities(day), isEmpty);
    await expectLater(repo.confirmSuggestion('g3-run-0758'), throwsStateError);
  });

  test(
    'sleep and journal expose missing gates and existing patch path',
    () async {
      final repo = _repo(SyntheticScenario.g3Sample);
      final plus = await repo.readSleepPlus(day);
      expect(plus.regularity.value, isNull);
      expect(plus.regularity.gate, isNull);
      expect(plus.socialJetlag.value, isNull);
      expect(plus.sleepDebt.freeNightP75Hours, closeTo(455 / 60, 1e-9));
      expect(plus.sleepDebt.habitualMedianHours, closeTo(445 / 60, 1e-9));
      expect(plus.sleepDebt.debtHours, closeTo(10 / 60, 1e-9));
      expect(plus.sleepDebt.hasFreeNight, isTrue);
      expect(plus.sleepDebt.refusalNote, isNull);
      expect(plus.needMinutes, 485);
      expect(plus.goalMinutes, 465);
      expect(plus.baselineOsdMinutes, 455);
      expect(plus.appliedDebtMinutes, 10);
      expect(plus.strainBonusMinutes, 20);
      expect(plus.napCreditMinutes, 0);
      expect(plus.napsJudged, isTrue);
      expect(
        plus.baselineOsdMinutes! +
            plus.appliedDebtMinutes! +
            plus.strainBonusMinutes! -
            plus.napCreditMinutes!,
        plus.needMinutes,
      );
      expect(plus.typicalEfficiency, .94);
      expect(plus.bedtime, DateTime(2026, 9, 29, 22, 18));
      expect(plus.wake, DateTime(2026, 9, 30, 6, 54));
      expect(
        plus.needMinutes! / plus.wake!.difference(plus.bedtime!).inMinutes,
        closeTo(plus.typicalEfficiency!, .001),
      );
      expect(
        (await repo.readSleepPlan(day)).plan?.bedtimeMinuteOfDay,
        22 * 60 + 18,
      );
      var checkIn = await repo.readCheckIn(day);
      expect([checkIn.answered, checkIn.total], [1, 4]);
      expect(checkIn.questions.map((q) => q.key), [
        'alcohol_evening',
        'caffeine_late',
        'mood',
        'journal_note',
      ]);
      expect(checkIn.questions.map((q) => q.kind), [
        G3CheckInKind.yesNo,
        G3CheckInKind.yesNo,
        G3CheckInKind.rating,
        G3CheckInKind.freeNote,
      ]);
      expect(checkIn.questions.map((q) => q.targetDay), [
        '2026-09-28',
        '2026-09-28',
        day,
        '2026-09-28',
      ]);
      expect((checkIn.questions[2].answer as G3RatingAnswer).value, 4);
      await repo.answerCheckIn(
        day,
        'alcohol_evening',
        const G3YesNoAnswer(false),
      );
      checkIn = await repo.readCheckIn(day);
      expect(checkIn.answered, 2);
      expect((checkIn.questions.first.answer as G3YesNoAnswer).value, isFalse);
      await repo.answerCheckIn(
        day,
        'journal_note',
        const G3FreeNoteAnswer('Gut geschlafen'),
      );
      expect((await repo.readJournalDay('2026-09-28')).note, 'Gut geschlafen');
      expect((await repo.readJournalDay(day)).note, isEmpty);
      await expectLater(
        repo.answerCheckIn(day, 'mood', const G3YesNoAnswer(true)),
        throwsArgumentError,
      );
      final weight = await repo.readG3Weight(day, 7);
      expect(weight.history.entries, isEmpty);
      expect(weight.sources, isEmpty);
      final pattern = await repo.readJournalPattern(day, 7);
      expect(pattern.remaining, isNull);
      expect(
        await repo.readLastBandSampleAt(day),
        DateTime(2026, 9, 29, 9, 38),
      );
      expect(await repo.readLastBandSampleAt('2026-09-28'), isNull);
    },
  );

  test(
    'missing generic fixture never gains a range or invented steps',
    () async {
      final repo = _repo(SyntheticScenario.missing);
      final sleepPlus = await repo.readSleepPlus(
        '2026-09-15',
        now: DateTime(2026, 9, 15, 12),
      );
      expect(sleepPlus.sleepDebt.refusalNote, isNull);
      final trend = await repo.readTrend(G3Metric.steps, '2026-09-15', 7);
      expect(trend.valueCount, 0);
      expect(trend.insufficient, 7);
      expect(
        (await repo.readPersonalRange(G3Metric.skinTempZ, day)).range,
        isNull,
      );
      expect((await repo.readWeeklyLoad(day)).days.length, 7);
    },
  );
}
