import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

List<Map<String, dynamic>>? _recentEnding(String end, Object? nDays) {
  if (nDays is! int || nDays <= 0) return null;
  final p = end.split('-').map(int.parse).toList();
  return [
    for (var i = nDays - 1; i >= 0; i--)
      {'date': dayLabelOf(DateTime(p[0], p[1], p[2] - i))},
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const day = '2026-09-15';
  final now = DateTime(2026, 9, 15, 7, 42);
  final builtAt = now.millisecondsSinceEpoch ~/ 1000;
  final stampMs = builtAt * 1000 - 250;
  final fixture =
      jsonDecode(
            File(
              'docs/openband5/assets/fixtures/sleep-plan.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final outputs = fixture['outputs'] as Map<String, dynamic>;
  final fixtureNeedSec = (outputs['need_seconds'] as num).toDouble();
  final fixtureBedtimeMin = (outputs['bedtime_minute'] as num).toDouble();
  final fixtureWakeMin = (outputs['wake_minute'] as num).toDouble();

  List<SleepPlanDayObservation> stableObservations(
    Iterable<String> days, {
    int? computedAtMs,
    bool skipped = false,
    bool inFetchWindow = true,
  }) => [
    for (final d in days)
      SleepPlanDayObservation(
        day: d,
        computedAtMs: computedAtMs ?? stampMs - 1,
        skipped: skipped,
        inFetchWindow: inFetchWindow,
      ),
  ];

  Map<String, dynamic> artifact({
    Object? algoVersion = kAlgoVersion,
    Object? builtForDay = day,
    Object? builtAtEpoch,
    Object? inputReadStartedAtMs,
    bool includeInputStamp = true,
    Object? needSec,
    Object? bedtimeMin,
    Object? wakeMin,
    Object? napCredit = 0,
    Object? strainBonus = 3,
    Object? needValue,
    Object? bedtimeValue,
    Object? wakeValue,
    Object? needNote = 'need_baseline:have=14,need=1',
    Object? bedtimeNote,
    Object? wakeNote,
    Object? needConfidence = 0.7,
    Object? bedtimeConfidence = 0.6,
    Object? wakeConfidence = 0.6,
    Object? nDays = 2,
    List<Map<String, dynamic>>? recent,
    Object? sleepDebt,
    Object? coach,
  }) {
    Object? envelope(
      Object? value,
      Object? innerKey,
      Object? innerValue, {
      Object? note,
      Object? confidence,
      List<String>? inputs,
    }) {
      if (value != null) return value;
      return {
        'value': innerValue == null ? '—' : {innerKey: innerValue},
        'confidence': confidence,
        'tier': 'ESTIMATE',
        'inputs_used': inputs ?? const ['osd_hours'],
        'note': note,
      };
    }

    final end = builtForDay is String ? builtForDay : day;
    final recentRows = recent ?? _recentEnding(end, nDays);
    final resolvedBuiltAt = builtAtEpoch ?? builtAt;
    final resolvedStamp = includeInputStamp
        ? inputReadStartedAtMs ??
            (resolvedBuiltAt is num &&
                    resolvedBuiltAt.isFinite &&
                    resolvedBuiltAt == resolvedBuiltAt.roundToDouble()
                ? resolvedBuiltAt.toInt() * 1000 - 250
                : null)
        : null;

    return {
      'algo_version': algoVersion,
      'built_for_day': builtForDay,
      'built_at_epoch': resolvedBuiltAt,
      if (includeInputStamp) 'input_read_started_at_ms': resolvedStamp,
      'n_days': nDays,
      'recent': ?recentRows,
      'sleep_debt':
          sleepDebt ??
          {
            'value': {'osd_hours': 8.0, 'has_free_night': true},
            'note': 'p75 of undisturbed nights',
          },
      'sleep_coach':
          coach ??
          {
            'need': envelope(
              needValue,
              'need_sec',
              needSec ?? fixtureNeedSec,
              note: needNote,
              confidence: needConfidence,
            ),
            'bedtime': envelope(
              bedtimeValue,
              'bedtime_min_of_day',
              bedtimeMin ?? fixtureBedtimeMin,
              note: bedtimeNote,
              confidence: bedtimeConfidence,
              inputs: const ['sleep_need', 'wake_time', 'efficiency'],
            ),
            'wake': envelope(
              wakeValue,
              'wake_min_of_day',
              wakeMin ?? fixtureWakeMin,
              note: wakeNote,
              confidence: wakeConfidence,
              inputs: const ['sleep_need', 'bedtime', 'efficiency'],
            ),
            'nap_credit_min': napCredit,
            'strain_bonus_min': strainBonus,
          },
    };
  }

  SleepPlanSnapshot parse(
    Map<String, dynamic>? raw, {
    String requested = day,
    DateTime? clock,
    bool unreadable = false,
    List<SleepPlanInputJob> jobs = const [],
    List<SleepPlanDayObservation>? observations,
    int? version,
  }) {
    final when = clock ?? now;
    final days = sleepPlanContributingDays(raw, planDay: requested);
    final stamp = sleepPlanMillis(raw?['input_read_started_at_ms']);
    return sleepPlanFromStoredCrossday(
      requestedDay: requested,
      now: when,
      algoVersion: version ?? kAlgoVersion,
      artifact: raw,
      unreadable: unreadable,
      jobs: jobs,
      observations:
          observations ??
          (days == null || stamp == null
              ? const []
              : stableObservations(days, computedAtMs: stamp - 1)),
    );
  }

  test('exact fixture need, bedtime and wake survive the mapper', () {
    final snapshot = parse(artifact());
    expect(snapshot.status, SleepPlanStatus.available);
    final plan = snapshot.plan!;
    expect(plan.needSeconds, fixtureNeedSec);
    expect(plan.bedtimeMinuteOfDay, fixtureBedtimeMin);
    expect(plan.wakeMinuteOfDay, fixtureWakeMin);
    expect(plan.napCreditMin, 0);
    expect(plan.strainBonusMin, 3);
    expect(plan.nightStartDay, day);
    expect(plan.wakeDay, '2026-09-16');
    expect(plan.builtAtEpoch, builtAt);
    expect(plan.inputReadStartedAtMs, stampMs);
    expect(plan.algoVersion, kAlgoVersion);
    expect(obDuration(plan.needSeconds / 60), '8h33');
    expect(plan.need.note, 'need_baseline:have=14,need=1');
    expect(plan.need.confidence, 0.7);
    expect(plan.need.tier, 'ESTIMATE');
    expect(plan.sleepDebt?.osdHours, 8.0);
    expect(plan.limitations.sourceTimezoneUnknown, isTrue);
    expect(plan.limitations.confidenceNotCalibrated, isTrue);
    expect(plan.limitations.notCycleAligned, isTrue);
    expect(plan.freshness, SleepPlanFreshness.fresh);
  });

  test('missing artifact or need stays missing and keeps the stored note', () {
    expect(parse(null).status, SleepPlanStatus.missing);
    expect(parse(null).issue, SleepPlanIssue.missingArtifact);
    final noCoach = artifact()..remove('sleep_coach');
    expect(parse(noCoach).status, SleepPlanStatus.missing);
    final absent = parse(
      artifact(
        needValue: {
          'value': '—',
          'note': 'need_baseline:have=0,need=1',
          'inputs_used': ['osd_hours'],
        },
      ),
    );
    expect(absent.status, SleepPlanStatus.missing);
    expect(absent.issue, SleepPlanIssue.missingNeed);
    expect(absent.need?.note, 'need_baseline:have=0,need=1');
    expect(absent.plan, isNull);
  });

  test('zero nap credit is not null, and null is not zero', () {
    final zero = parse(artifact(napCredit: 0, strainBonus: 0));
    expect(zero.plan!.napCreditMin, 0);
    expect(zero.plan!.strainBonusMin, 0);
    final unknown = parse(artifact(napCredit: null, strainBonus: null));
    expect(unknown.plan!.napCreditMin, isNull);
    expect(unknown.plan!.strainBonusMin, isNull);
    expect(unknown.status, SleepPlanStatus.partial);
    expect(unknown.plan!.freshness, SleepPlanFreshness.fresh);
    final dash = parse(artifact(napCredit: '—', strainBonus: '—'));
    expect(dash.plan!.napCreditMin, isNull);
    expect(dash.plan!.strainBonusMin, isNull);
    expect(dash.status, SleepPlanStatus.partial);
    expect(parse(artifact(napCredit: null, strainBonus: 3)).status, SleepPlanStatus.partial);
    expect(parse(artifact(napCredit: 0, strainBonus: null)).status, SleepPlanStatus.partial);
  });

  test('wrong version or built day is stale, not today\'s plan', () {
    expect(parse(artifact(algoVersion: 89)).status, SleepPlanStatus.stale);
    expect(parse(artifact(algoVersion: 89)).issue, SleepPlanIssue.wrongVersion);
    expect(
      parse(artifact(builtForDay: '2026-09-14')).status,
      SleepPlanStatus.stale,
    );
    expect(parse(artifact(builtForDay: '2026-09-14')).plan, isNull);
  });

  test('a historical or tomorrow request never returns today\'s forecast', () {
    final yesterday = parse(artifact(), requested: '2026-09-14');
    expect(yesterday.status, SleepPlanStatus.unavailable);
    expect(yesterday.plan, isNull);
    final tomorrow = parse(artifact(), requested: '2026-09-16');
    expect(tomorrow.status, SleepPlanStatus.unavailable);
    final atMidnight = parse(
      artifact(),
      clock: DateTime(2026, 9, 16),
      requested: day,
    );
    expect(atMidnight.status, SleepPlanStatus.unavailable);
    final todayAfterMidnight = parse(
      artifact(builtForDay: '2026-09-16', builtAtEpoch: DateTime(2026, 9, 16, 0, 1).millisecondsSinceEpoch ~/ 1000),
      requested: '2026-09-16',
      clock: DateTime(2026, 9, 16, 0, 1),
    );
    expect(todayAfterMidnight.status, SleepPlanStatus.available);
  });

  test('nonfinite or out-of-range fields are corrupt, not sanitized', () {
    expect(
      parse(artifact(needSec: double.nan)).status,
      SleepPlanStatus.corrupt,
    );
    expect(
      parse(artifact(needSec: 5 * 3600)).issue,
      SleepPlanIssue.invalidNeed,
    );
    expect(
      parse(artifact(needSec: 12 * 3600)).issue,
      SleepPlanIssue.invalidNeed,
    );
    expect(
      parse(artifact(bedtimeMin: 1440)).issue,
      SleepPlanIssue.invalidClock,
    );
    expect(
      parse(artifact(wakeMin: -1)).issue,
      SleepPlanIssue.invalidClock,
    );
    expect(
      parse(artifact(bedtimeMin: double.infinity)).status,
      SleepPlanStatus.corrupt,
    );
    expect(
      parse(artifact(strainBonus: double.nan)).issue,
      SleepPlanIssue.invalidContribution,
    );
    expect(
      parse(artifact(napCredit: 'twenty')).issue,
      SleepPlanIssue.invalidContribution,
    );
    expect(
      parse(artifact(needConfidence: 1.2)).issue,
      SleepPlanIssue.invalidConfidence,
    );
    expect(parse(artifact(needSec: 5 * 3600)).plan, isNull);
    expect(parse(artifact(needSec: 6 * 3600)).status, SleepPlanStatus.available);
    expect(parse(artifact(needSec: 11 * 3600)).status, SleepPlanStatus.available);
    expect(parse(artifact(bedtimeMin: 0)).status, SleepPlanStatus.available);
    expect(parse(artifact(wakeMin: 1439.999)).status, SleepPlanStatus.available);
    expect(parse(artifact(needConfidence: 0)).status, SleepPlanStatus.available);
    expect(parse(artifact(needConfidence: 1)).status, SleepPlanStatus.available);
  });

  test('unreadable JSON is corrupt and does not throw', () {
    final snapshot = parse(null, unreadable: true);
    expect(snapshot.status, SleepPlanStatus.corrupt);
    expect(snapshot.issue, SleepPlanIssue.unreadableJson);
    expect(snapshot.plan, isNull);
  });

  test('builtAt must be a past whole second on the built local day', () {
    expect(
      parse(Map<String, dynamic>.from(artifact())..['built_at_epoch'] = null)
          .status,
      SleepPlanStatus.inconsistent,
    );
    expect(parse(artifact(builtAtEpoch: 0)).issue, SleepPlanIssue.inconsistentBuiltAt);
    expect(parse(artifact(builtAtEpoch: 1.5)).status, SleepPlanStatus.inconsistent);
    expect(
      parse(artifact(builtAtEpoch: builtAt + 60)).issue,
      SleepPlanIssue.futureBuiltAt,
    );
    final otherDay = DateTime(2026, 9, 14, 23, 0).millisecondsSinceEpoch ~/ 1000;
    expect(
      parse(artifact(builtAtEpoch: otherDay)).issue,
      SleepPlanIssue.inconsistentBuiltAt,
    );
    expect(parse(artifact(builtAtEpoch: builtAt.toDouble())).status, SleepPlanStatus.available);
  });

  test('valid need survives honestly absent bedtime or wake', () {
    final noBed = parse(
      artifact(
        bedtimeValue: {
          'value': '—',
          'note': 'need_input:efficiency',
          'inputs_used': ['sleep_need', 'wake_time', 'efficiency'],
        },
      ),
    );
    expect(noBed.status, SleepPlanStatus.partial);
    expect(noBed.plan!.freshness, SleepPlanFreshness.fresh);
    expect(noBed.plan!.needSeconds, fixtureNeedSec);
    expect(noBed.plan!.bedtimeMinuteOfDay, isNull);
    expect(noBed.plan!.wakeMinuteOfDay, fixtureWakeMin);
    expect(noBed.plan!.bedtime.note, 'need_input:efficiency');
    final noWake = parse(
      artifact(
        wakeValue: {
          'value': '—',
          'note': 'need_input:wake_time',
        },
      ),
    );
    expect(noWake.status, SleepPlanStatus.partial);
    expect(noWake.plan!.wakeMinuteOfDay, isNull);
    expect(noWake.plan!.wake.note, 'need_input:wake_time');
  });

  test('contributing window requires a complete recent-date list', () {
    expect(sleepPlanWakeDay('2026-03-29'), '2026-03-30');
    expect(
      sleepPlanContributingDays({
        'n_days': 3,
        'recent': [
          {'date': '2026-03-28'},
          {'date': '2026-03-29'},
          {'date': '2026-03-30'},
        ],
      }, planDay: '2026-03-30'),
      ['2026-03-28', '2026-03-29', '2026-03-30'],
    );
    expect(
      sleepPlanContributingDays({'n_days': 3}, planDay: '2026-03-30'),
      isNull,
    );
    expect(
      sleepPlanContributingDays(
        {
          'n_days': 2,
          'recent': [
            {'date': '2026-01-02'},
            {'date': '2026-09-15'},
          ],
        },
        planDay: day,
      ),
      ['2026-01-02', '2026-09-15'],
    );
    expect(
      sleepPlanContributingDays(
        {
          'n_days': 3,
          'recent': [
            {'date': '2026-09-14'},
            {'date': 'nope'},
            {'date': '2026-09-15'},
          ],
        },
        planDay: day,
      ),
      isNull,
    );
    expect(
      sleepPlanContributingDays(
        {
          'n_days': 2,
          'recent': [
            {'date': day},
            {'date': '2026-09-16'},
          ],
        },
        planDay: day,
      ),
      isNull,
    );
    expect(
      sleepPlanContributingDays(
        {
          'n_days': 2,
          'recent': [
            {'date': day},
            {'date': day},
          ],
        },
        planDay: day,
      ),
      isNull,
    );
    expect(
      sleepPlanContributingDays(
        {
          'n_days': 3,
          'recent': [
            {'date': '2026-09-14'},
            {'date': day},
          ],
        },
        planDay: day,
      ),
      isNull,
    );
  });

  test('pending, failed, or newer jobs are not fresh; older complete jobs are', () {
    final pending = parse(
      artifact(),
      jobs: const [
        SleepPlanInputJob(
          day: day,
          kind: SleepPlanJobKind.napRecalc,
          status: 'pending',
        ),
      ],
    );
    expect(pending.plan!.freshness, SleepPlanFreshness.staleInputs);
    expect(pending.status, SleepPlanStatus.stale);
    expect(pending.status, isNot(SleepPlanStatus.available));
    expect(pending.plan!.needSeconds, fixtureNeedSec);
    final failed = parse(
      artifact(),
      jobs: const [
        SleepPlanInputJob(
          day: '2026-09-14',
          kind: SleepPlanJobKind.sleepCorrection,
          status: 'failed',
        ),
      ],
    );
    expect(failed.plan!.freshness, SleepPlanFreshness.staleInputs);
    expect(failed.status, SleepPlanStatus.stale);
    final newer = parse(
      artifact(),
      jobs: [
        SleepPlanInputJob(
          day: day,
          kind: SleepPlanJobKind.sleepCorrection,
          status: 'complete',
          resultComputedAtMs: stampMs,
        ),
      ],
    );
    expect(newer.plan!.freshness, SleepPlanFreshness.staleInputs);
    expect(newer.status, SleepPlanStatus.stale);
    final older = parse(
      artifact(),
      jobs: [
        SleepPlanInputJob(
          day: '2026-09-14',
          kind: SleepPlanJobKind.sleepCorrection,
          status: 'complete',
          resultComputedAtMs: stampMs - 60,
        ),
        SleepPlanInputJob(
          day: day,
          kind: SleepPlanJobKind.napRecalc,
          status: 'complete',
          resultComputedAtMs: stampMs - 1,
        ),
      ],
    );
    expect(older.plan!.freshness, SleepPlanFreshness.fresh);
    expect(older.status, SleepPlanStatus.available);
    final oldOutside = parse(
      artifact(nDays: 2, recent: [
        {'date': '2026-09-14'},
        {'date': day},
      ]),
      jobs: const [
        SleepPlanInputJob(
          day: '2026-01-01',
          kind: SleepPlanJobKind.sleepCorrection,
          status: 'pending',
        ),
      ],
    );
    expect(oldOutside.plan!.freshness, SleepPlanFreshness.fresh);
    expect(oldOutside.status, SleepPlanStatus.available);
    final noWindow = parse(artifact(nDays: null, recent: null)..remove('n_days'));
    expect(noWindow.plan!.freshness, SleepPlanFreshness.unknown);
    expect(noWindow.status, SleepPlanStatus.partial);
    expect(noWindow.status, isNot(SleepPlanStatus.available));
    final undated = parse(
      artifact(),
      jobs: const [
        SleepPlanInputJob(
          day: day,
          kind: SleepPlanJobKind.napRecalc,
          status: 'complete',
        ),
      ],
    );
    expect(undated.plan!.freshness, SleepPlanFreshness.unknown);
    expect(undated.status, SleepPlanStatus.partial);
    expect(undated.status, isNot(SleepPlanStatus.available));
  });

  test('sparse recent dates gate jobs; a malformed list does not use a subset', () {
    final sparse = {
      'n_days': 2,
      'recent': [
        {'date': '2026-01-02'},
        {'date': day},
      ],
    };
    expect(
      sleepPlanContributingDays(sparse, planDay: day),
      ['2026-01-02', day],
    );
    final oldPending = parse(
      artifact(
        nDays: 2,
        recent: [
          {'date': '2026-01-02'},
          {'date': day},
        ],
      ),
      jobs: const [
        SleepPlanInputJob(
          day: '2026-01-02',
          kind: SleepPlanJobKind.sleepCorrection,
          status: 'pending',
        ),
      ],
    );
    expect(oldPending.plan!.freshness, SleepPlanFreshness.staleInputs);
    expect(oldPending.status, SleepPlanStatus.stale);
    final gapPending = parse(
      artifact(
        nDays: 2,
        recent: [
          {'date': '2026-01-02'},
          {'date': day},
        ],
      ),
      jobs: const [
        SleepPlanInputJob(
          day: '2026-06-01',
          kind: SleepPlanJobKind.sleepCorrection,
          status: 'pending',
        ),
      ],
    );
    expect(gapPending.plan!.freshness, SleepPlanFreshness.fresh);
    expect(gapPending.status, SleepPlanStatus.available);
    final malformed = parse(
      artifact(
        nDays: 3,
        recent: [
          {'date': '2026-09-14'},
          {'date': 'nope'},
          {'date': day},
        ],
      ),
      jobs: const [
        SleepPlanInputJob(
          day: '2026-09-14',
          kind: SleepPlanJobKind.sleepCorrection,
          status: 'pending',
        ),
      ],
    );
    expect(malformed.plan!.freshness, SleepPlanFreshness.unknown);
    expect(malformed.status, SleepPlanStatus.partial);
    expect(malformed.status, isNot(SleepPlanStatus.stale));
  });

  test('input stamp and served observations decide freshness at ms precision', () {
    final days = ['2026-09-14', day];
    expect(parse(artifact(), observations: const []).plan!.freshness,
        SleepPlanFreshness.unknown);
    expect(parse(artifact(includeInputStamp: false)).plan!.freshness,
        SleepPlanFreshness.unknown);
    expect(parse(artifact(includeInputStamp: false)).plan!.inputReadStartedAtMs,
        isNull);
    expect(
      parse(artifact(inputReadStartedAtMs: 1.5)).issue,
      SleepPlanIssue.invalidInputStamp,
    );
    expect(
      parse(artifact(inputReadStartedAtMs: 'later')).issue,
      SleepPlanIssue.invalidInputStamp,
    );
    expect(
      parse(artifact(inputReadStartedAtMs: builtAt)).issue,
      SleepPlanIssue.inconsistentInputStamp,
    );
    expect(
      parse(artifact(inputReadStartedAtMs: now.millisecondsSinceEpoch + 1)).issue,
      SleepPlanIssue.inconsistentInputStamp,
    );
    expect(
      parse(artifact(inputReadStartedAtMs: builtAt * 1000 + 1000)).issue,
      SleepPlanIssue.inconsistentInputStamp,
    );
    expect(sleepPlanMillis(builtAt), isNull);
    expect(sleepPlanMillis(stampMs), stampMs);
    expect(sleepPlanMillis(stampMs + 0.5), isNull);

    final sameSecond = parse(
      artifact(
        inputReadStartedAtMs: builtAt * 1000 + 100,
      ),
      clock: DateTime.fromMillisecondsSinceEpoch(builtAt * 1000 + 800),
      observations: stableObservations(days, computedAtMs: builtAt * 1000 + 400),
    );
    expect(sameSecond.plan!.freshness, SleepPlanFreshness.staleInputs);
    expect(sameSecond.status, SleepPlanStatus.stale);
    expect(sameSecond.plan!.inputReadStartedAtMs, builtAt * 1000 + 100);

    final atStamp = parse(
      artifact(),
      observations: stableObservations(days, computedAtMs: stampMs),
    );
    expect(atStamp.plan!.freshness, SleepPlanFreshness.staleInputs);

    final olderStable = parse(
      artifact(),
      observations: stableObservations(days, computedAtMs: stampMs - 1),
    );
    expect(olderStable.plan!.freshness, SleepPlanFreshness.fresh);
    expect(olderStable.status, SleepPlanStatus.available);

    final wouldEnter = parse(
      artifact(),
      observations: [
        ...stableObservations(days),
        SleepPlanDayObservation(
          day: '2026-09-13',
          computedAtMs: stampMs - 1,
          inFetchWindow: true,
        ),
      ],
    );
    expect(wouldEnter.plan!.freshness, SleepPlanFreshness.staleInputs);

    final stillSkipped = parse(
      artifact(),
      observations: [
        ...stableObservations(days),
        SleepPlanDayObservation(
          day: '2026-09-13',
          computedAtMs: stampMs - 1,
          skipped: true,
          inFetchWindow: true,
        ),
      ],
    );
    expect(stillSkipped.plan!.freshness, SleepPlanFreshness.fresh);

    final wouldDrop = parse(
      artifact(),
      observations: [
        SleepPlanDayObservation(
          day: '2026-09-14',
          computedAtMs: stampMs - 1,
          inFetchWindow: true,
        ),
        SleepPlanDayObservation(
          day: day,
          computedAtMs: stampMs - 1,
        ),
      ],
    );
    expect(wouldDrop.plan!.freshness, SleepPlanFreshness.staleInputs);
  });

  test('a present prior-day input stamp is inconsistent even with fresh observations', () {
    final days = ['2026-09-14', day];
    final priorStamp = DateTime(2026, 9, 14, 23).millisecondsSinceEpoch;
    expect(dayLabelOf(DateTime.fromMillisecondsSinceEpoch(priorStamp)), isNot(day));
    final prior = parse(
      artifact(inputReadStartedAtMs: priorStamp),
      observations: stableObservations(days, computedAtMs: priorStamp - 1),
    );
    expect(prior.status, SleepPlanStatus.inconsistent);
    expect(prior.issue, SleepPlanIssue.inconsistentInputStamp);
    expect(prior.plan, isNull);
    expect(prior.status, isNot(SleepPlanStatus.available));

    final missing = parse(
      artifact(includeInputStamp: false),
      observations: stableObservations(days),
    );
    expect(missing.plan!.freshness, SleepPlanFreshness.unknown);
    expect(missing.plan!.inputReadStartedAtMs, isNull);
    expect(missing.status, SleepPlanStatus.partial);

    const dstDay = '2026-03-30';
    final dstNow = DateTime(2026, 3, 30, 7, 42);
    final dstBuiltAt = dstNow.millisecondsSinceEpoch ~/ 1000;
    final dstRecent = [
      {'date': '2026-03-29'},
      {'date': dstDay},
    ];
    expect(sleepPlanWakeDay('2026-03-29'), dstDay);
    final priorCivil = DateTime(2026, 3, 29, 23).millisecondsSinceEpoch;
    expect(
      dayLabelOf(DateTime.fromMillisecondsSinceEpoch(priorCivil)),
      '2026-03-29',
    );
    final dstPrior = parse(
      artifact(
        builtForDay: dstDay,
        builtAtEpoch: dstBuiltAt,
        inputReadStartedAtMs: priorCivil,
        nDays: 2,
        recent: dstRecent,
      ),
      requested: dstDay,
      clock: dstNow,
      observations: stableObservations(
        ['2026-03-29', dstDay],
        computedAtMs: priorCivil - 1,
      ),
    );
    expect(dstPrior.status, SleepPlanStatus.inconsistent);
    expect(dstPrior.issue, SleepPlanIssue.inconsistentInputStamp);
    expect(dstPrior.plan, isNull);

    final sameCivil = DateTime(2026, 3, 30, 0, 15).millisecondsSinceEpoch;
    expect(dayLabelOf(DateTime.fromMillisecondsSinceEpoch(sameCivil)), dstDay);
    final dstSame = parse(
      artifact(
        builtForDay: dstDay,
        builtAtEpoch: dstBuiltAt,
        inputReadStartedAtMs: sameCivil,
        nDays: 2,
        recent: dstRecent,
      ),
      requested: dstDay,
      clock: dstNow,
      observations: stableObservations(
        ['2026-03-29', dstDay],
        computedAtMs: sameCivil - 1,
      ),
    );
    expect(dstSame.status, SleepPlanStatus.available);
    expect(dstSame.plan!.inputReadStartedAtMs, sameCivil);
    expect(dstSame.plan!.limitations.sourceTimezoneUnknown, isTrue);
  });

  test('job relevance is today-nap and contributing-or-fetch sleep only', () {
    final pendingOldNap = parse(
      artifact(),
      jobs: const [
        SleepPlanInputJob(
          day: '2026-09-14',
          kind: SleepPlanJobKind.napRecalc,
          status: 'pending',
        ),
      ],
    );
    expect(pendingOldNap.plan!.freshness, SleepPlanFreshness.fresh);
    expect(pendingOldNap.status, SleepPlanStatus.available);

    final pendingTodayNap = parse(
      artifact(),
      jobs: const [
        SleepPlanInputJob(
          day: day,
          kind: SleepPlanJobKind.napRecalc,
          status: 'pending',
        ),
      ],
    );
    expect(pendingTodayNap.plan!.freshness, SleepPlanFreshness.staleInputs);

    final completeAfterUpdatedAt = parse(
      artifact(),
      jobs: [
        SleepPlanInputJob(
          day: day,
          kind: SleepPlanJobKind.napRecalc,
          status: 'complete',
          resultComputedAtMs: stampMs - 1,
        ),
      ],
    );
    expect(completeAfterUpdatedAt.plan!.freshness, SleepPlanFreshness.fresh);
    expect(completeAfterUpdatedAt.plan!.inputReadStartedAtMs, stampMs);

    final fetchSleep = parse(
      artifact(),
      observations: [
        ...stableObservations(['2026-09-14', day]),
        SleepPlanDayObservation(
          day: '2026-09-13',
          computedAtMs: stampMs - 1,
          skipped: true,
          inFetchWindow: true,
        ),
      ],
      jobs: const [
        SleepPlanInputJob(
          day: '2026-09-13',
          kind: SleepPlanJobKind.sleepCorrection,
          status: 'failed',
        ),
      ],
    );
    expect(fetchSleep.plan!.freshness, SleepPlanFreshness.staleInputs);

    final secondsResult = parse(
      artifact(),
      jobs: [
        SleepPlanInputJob(
          day: day,
          kind: SleepPlanJobKind.napRecalc,
          status: 'complete',
          resultComputedAtMs: builtAt,
        ),
      ],
    );
    expect(secondsResult.plan!.freshness, SleepPlanFreshness.unknown);
  });

  test('sleep debt is provenance only and is not a goal or need substitute', () {
    final snapshot = parse(
      artifact(
        needValue: {
          'value': '—',
          'note': 'need_baseline:have=0,need=1',
        },
        sleepDebt: {
          'value': {'osd_hours': 8.2, 'has_free_night': true},
        },
      ),
    );
    expect(snapshot.status, SleepPlanStatus.missing);
    expect(snapshot.plan, isNull);
  });

  group('SQLite repository', () {
    late AppState app;
    late LocalOpenBandRepository repository;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      await LocalDb.close();
      LocalDb.dbName = 'openband_sleep_plan_data_test.db';
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase('$dir/${LocalDb.dbName}');
      app = AppState.forTesting();
      repository = LocalOpenBandRepository(app);
    });

    tearDown(() async {
      app.dispose();
      await LocalDb.close();
    });

    Future<void> store(Map<String, dynamic> raw) =>
        LocalDb.putBaseline('crossday', jsonEncode(raw));

    Future<void> seedServedDay(
      String dayId, {
      required int computedAtMs,
      bool skipped = false,
      int version = kAlgoVersion,
    }) async {
      await LocalDb.putDayResult(
        dayId: dayId,
        algoVersion: version,
        payloadJson: skipped ? '{"skipped":true}' : '{}',
        windowJson: '{}',
        skipped: skipped,
      );
      final db = await LocalDb.instance;
      await db.update(
        'day_result',
        {'computed_at': computedAtMs},
        where: 'day_id = ? AND algo_version = ?',
        whereArgs: [dayId, version],
      );
    }

    Future<void> seedWindow({int? computedAtMs}) async {
      final at = computedAtMs ?? stampMs - 1;
      await seedServedDay('2026-09-14', computedAtMs: at);
      await seedServedDay(day, computedAtMs: at);
    }

    test('reads the stored fixture and rejects corrupt JSON', () async {
      await seedWindow();
      await store(artifact());
      final snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.status, SleepPlanStatus.available);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.fresh);
      expect(snapshot.plan!.needSeconds, fixtureNeedSec);
      expect(snapshot.plan!.bedtimeMinuteOfDay, fixtureBedtimeMin);
      expect(snapshot.plan!.wakeMinuteOfDay, fixtureWakeMin);
      expect(snapshot.plan!.inputReadStartedAtMs, stampMs);

      await LocalDb.putBaseline('crossday', '{not json');
      final corrupt = await repository.readSleepPlan(day, now: now);
      expect(corrupt.status, SleepPlanStatus.corrupt);
      expect(corrupt.issue, SleepPlanIssue.unreadableJson);
    });

    test('empty payload is corrupt; a missing row is missing', () async {
      expect(
        (await repository.readSleepPlan(day, now: now)).status,
        SleepPlanStatus.missing,
      );
      await LocalDb.putBaseline('crossday', '');
      final empty = await repository.readSleepPlan(day, now: now);
      expect(empty.status, SleepPlanStatus.corrupt);
      expect(empty.issue, SleepPlanIssue.unreadableJson);
    });

    test('historical SQLite reads stay unavailable without reading the store', () async {
      await store(artifact());
      final db = await LocalDb.instance;
      await db.execute('DROP TABLE baselines');
      await db.execute('DROP TABLE nap_recalc_job');
      final past = await repository.readSleepPlan('2026-09-14', now: now);
      expect(past.status, SleepPlanStatus.unavailable);
      expect(past.plan, isNull);
      await expectLater(
        repository.readSleepPlan(day, now: now),
        throwsA(anything),
      );
    });

    test('pending or newer correction and nap jobs mark freshness', () async {
      await seedWindow();
      await store(artifact());
      await LocalDb.putOpenBandSleepDraft(
        dayId: '2026-09-14',
        draftId: 'corr-old',
        onsetMs: DateTime(2026, 9, 13, 23).millisecondsSinceEpoch,
        wakeMs: DateTime(2026, 9, 14, 7).millisecondsSinceEpoch,
      );
      final older = await LocalDb.commitOpenBandSleepCorrection(
        dayId: '2026-09-14',
        draftId: 'corr-old',
        onsetMs: DateTime(2026, 9, 13, 23).millisecondsSinceEpoch,
        wakeMs: DateTime(2026, 9, 14, 7).millisecondsSinceEpoch,
      );
      await LocalDb.updateOpenBandCalculationJob(
        dayId: '2026-09-14',
        correctionId: older['correction_id'] as String,
        revision: (older['revision'] as num).toInt(),
        status: 'complete',
        resultAlgoVersion: kAlgoVersion,
        resultComputedAt: (builtAt - 120) * 1000,
      );
      var snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.fresh);
      expect(snapshot.status, SleepPlanStatus.available);

      await LocalDb.putNapEdit(
        dayId: day,
        startTs: 1000,
        endTs: 2800,
        source: 'manual',
      );
      snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.staleInputs);
      expect(snapshot.status, SleepPlanStatus.stale);
      expect(snapshot.status, isNot(SleepPlanStatus.available));
      expect(snapshot.plan!.needSeconds, fixtureNeedSec);

      final db = await LocalDb.instance;
      await db.update(
        'nap_recalc_job',
        {
          'status': 'complete',
          'result_computed_at': (builtAt - 30) * 1000,
          'updated_at': (builtAt - 30) * 1000,
        },
        where: 'day_id = ?',
        whereArgs: [day],
      );
      snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.fresh);
      expect(snapshot.status, SleepPlanStatus.available);

      await db.update(
        'nap_recalc_job',
        {
          'status': 'failed',
          'updated_at': (builtAt - 30) * 1000,
        },
        where: 'day_id = ?',
        whereArgs: [day],
      );
      snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.staleInputs);
      expect(snapshot.status, SleepPlanStatus.stale);

      await db.update(
        'nap_recalc_job',
        {
          'status': 'complete',
          'result_computed_at': (builtAt + 5) * 1000,
          'updated_at': (builtAt + 5) * 1000,
        },
        where: 'day_id = ?',
        whereArgs: [day],
      );
      snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.staleInputs);
      expect(snapshot.status, SleepPlanStatus.stale);

      await db.update(
        'nap_recalc_job',
        {
          'status': 'complete',
          'result_computed_at': stampMs - 1,
          'updated_at': (builtAt + 30) * 1000,
        },
        where: 'day_id = ?',
        whereArgs: [day],
      );
      snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.fresh);
      expect(snapshot.status, SleepPlanStatus.available);

      await db.rawUpdate(
        'UPDATE nap_recalc_job SET status = ?, result_computed_at = NULL, '
        'updated_at = ? WHERE day_id = ?',
        ['complete', (builtAt + 30) * 1000, day],
      );
      snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.unknown);
      expect(snapshot.status, SleepPlanStatus.partial);
    });

    test('non-today naps and unrelated failed jobs do not blank the forecast',
        () async {
      await seedWindow();
      await store(artifact());
      await LocalDb.putNapEdit(
        dayId: '2026-09-14',
        startTs: 1000,
        endTs: 2800,
        source: 'manual',
      );
      var snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.fresh);
      expect(snapshot.status, SleepPlanStatus.available);

      await LocalDb.putOpenBandSleepDraft(
        dayId: '2026-01-01',
        draftId: 'corr-unrelated',
        onsetMs: DateTime(2025, 12, 31, 23).millisecondsSinceEpoch,
        wakeMs: DateTime(2026, 1, 1, 7).millisecondsSinceEpoch,
      );
      final unrelated = await LocalDb.commitOpenBandSleepCorrection(
        dayId: '2026-01-01',
        draftId: 'corr-unrelated',
        onsetMs: DateTime(2025, 12, 31, 23).millisecondsSinceEpoch,
        wakeMs: DateTime(2026, 1, 1, 7).millisecondsSinceEpoch,
      );
      await LocalDb.updateOpenBandCalculationJob(
        dayId: '2026-01-01',
        correctionId: unrelated['correction_id'] as String,
        revision: (unrelated['revision'] as num).toInt(),
        status: 'failed',
      );
      snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.fresh);
      expect(snapshot.status, SleepPlanStatus.available);
    });

    test('generic day_result recalc after the input read is stale', () async {
      await seedWindow();
      await store(artifact());
      var snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.status, SleepPlanStatus.available);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.fresh);

      await seedServedDay(day, computedAtMs: stampMs);
      snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.staleInputs);
      expect(snapshot.status, SleepPlanStatus.stale);
      expect(snapshot.plan!.needSeconds, fixtureNeedSec);
      expect(snapshot.plan!.inputReadStartedAtMs, stampMs);

      await seedWindow();
      final raceStamp = builtAt * 1000 + 100;
      final raceNow = DateTime.fromMillisecondsSinceEpoch(builtAt * 1000 + 800);
      await store(artifact(inputReadStartedAtMs: raceStamp));
      snapshot = await repository.readSleepPlan(day, now: raceNow);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.fresh);
      expect(snapshot.plan!.inputReadStartedAtMs, raceStamp);

      await seedServedDay(day, computedAtMs: builtAt * 1000 + 400);
      snapshot = await repository.readSleepPlan(day, now: raceNow);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.staleInputs);
      expect(snapshot.status, SleepPlanStatus.stale);
    });

    test('newest-90 served rows that would enter or stay skipped', () async {
      await seedWindow();
      await store(artifact());
      await seedServedDay('2026-09-13', computedAtMs: stampMs - 1);
      var snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.staleInputs);

      await seedServedDay(
        '2026-09-13',
        computedAtMs: stampMs - 1,
        skipped: true,
      );
      snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.fresh);
      expect(snapshot.status, SleepPlanStatus.available);
    });

    test('served join ignores newer-than-current algo rows', () async {
      await seedWindow();
      await seedServedDay(day, computedAtMs: stampMs + 5000, version: 91);
      await store(artifact());
      final snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.fresh);
      expect(snapshot.status, SleepPlanStatus.available);
    });

    test('legacy missing stamp and empty served metadata stay unknown', () async {
      await store(artifact(includeInputStamp: false));
      var snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.unknown);
      expect(snapshot.plan!.inputReadStartedAtMs, isNull);
      expect(snapshot.status, SleepPlanStatus.partial);

      await store(artifact());
      snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.unknown);
      expect(snapshot.status, isNot(SleepPlanStatus.available));

      await seedWindow();
      snapshot = await repository.readSleepPlan(day, now: now);
      expect(snapshot.plan!.freshness, SleepPlanFreshness.fresh);
      expect(snapshot.status, SleepPlanStatus.available);
    });
  });

  group('synthetic repository', () {
    late SyntheticOpenBandRepository repo;

    setUp(() {
      repo = SyntheticOpenBandRepository.fromMaps(
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/day-summary.json',
              ).readAsStringSync(),
            )
            as Map,
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/sleep-detail.json',
              ).readAsStringSync(),
            )
            as Map,
      );
      repo.sleepPlanNow = () => now;
    });

    test('defaults to missing and does not invent a plan from the night', () async {
      final snapshot = await repo.readSleepPlan(day, now: now);
      expect(snapshot.status, SleepPlanStatus.missing);
      expect(snapshot.plan, isNull);
      final night = (await repo.readDay(day)).sleep;
      expect(night.duration.value, isNotNull);
    });

    test('serves an explicit fixture and throws a retryable read error', () async {
      repo.sleepPlanArtifact = artifact();
      repo.sleepPlanObservations = stableObservations(['2026-09-14', day]);
      final snapshot = await repo.readSleepPlan(day, now: now);
      expect(snapshot.status, SleepPlanStatus.available);
      expect(snapshot.plan!.needSeconds, fixtureNeedSec);
      expect(snapshot.plan!.inputReadStartedAtMs, stampMs);
      repo.sleepPlanObservations = const [];
      final unknown = await repo.readSleepPlan(day, now: now);
      expect(unknown.plan!.freshness, SleepPlanFreshness.unknown);
      expect(unknown.status, isNot(SleepPlanStatus.available));
      repo.failSleepPlanRead = true;
      await expectLater(
        repo.readSleepPlan(day, now: now),
        throwsA(isA<StateError>()),
      );
    });
  });
}
