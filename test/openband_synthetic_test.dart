import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';

Map _load(String name) =>
    jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync())
        as Map;

SyntheticOpenBandRepository repo({
  SyntheticScenario scenario = SyntheticScenario.complete,
}) => SyntheticOpenBandRepository.fromMaps(
  _load('day-summary.json'),
  _load('sleep-detail.json'),
  scenario: scenario,
);

SleepDraft _draft(String id, {DateTime? onset, DateTime? wake}) => SleepDraft(
  id: id,
  day: '2026-09-15',
  onset: onset ?? DateTime(2026, 9, 14, 23, 25),
  wake: wake ?? DateTime(2026, 9, 15, 6, 54),
  recordingTimezone: 'Europe/Berlin',
);

void main() {
  test('baseline Sept 15 matches fixture intervals and headlines', () async {
    final r = repo();
    final day = await r.readDay('2026-09-15');
    expect(day.synthetic, isTrue);
    expect(day.sleep.onset, DateTime(2026, 9, 14, 23, 10));
    expect(day.sleep.wake, DateTime(2026, 9, 15, 6, 54));
    expect(day.sleep.recordingTimezone, 'Europe/Berlin');
    expect(day.sleep.duration.value, 438);
    expect(day.sleep.bedMinutes, 464);
    expect(day.sleep.awakeMinutes, 26);
    expect(day.sleep.remMinutes, 123);
    expect(day.sleep.lightMinutes, 247);
    expect(day.sleep.deepMinutes, 68);
    expect(day.sleep.unobservedMinutes, isNull);
    expect(day.sleep.segments, hasLength(14));
    expect(day.sleep.segments.every((s) => s.stage != null), isTrue);
    expect(day.recovery.value, closeTo(74.062276, 1e-6));
    expect(day.hrv.value, 48);
    expect(day.hrv.baseline, isNull);
    expect(day.restingHr.value, 54);
    expect(day.restingHr.baseline, isNull);
    expect(day.strain.value, 1.6);
    final hrv = await r.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(hrv.baseline?.value, 40);
    expect(hrv.baseline?.status, isNot(kNightScalarTrustedBaseline));
    final rhr = await r.readNightScalarDetail(
      MetricKey.restingHr,
      '2026-09-15',
      7,
    );
    expect(rhr.baseline?.value, 56);
    expect(rhr.baseline?.status, isNot(kNightScalarTrustedBaseline));
    expect(day.steps.value, 1240);
    expect(r.band.connection, BandConnection.connected);
    expect(r.band.transfer, TransferState.idle);
    expect(r.band.batteryPercent, 64);
    expect(r.band.latestStoredAt, DateTime(2026, 9, 15, 7, 42));
  });

  test(
    'changed window trims fixture intervals to 428 sleep and 21 awake',
    () async {
      final r = repo();
      final draft = _draft('sleep-2026-09-15');
      await r.saveDraft(draft);
      final saved = await r.saveCorrection(draft);
      expect(saved.id, 'sleep-2026-09-15');
      expect(saved.state, CorrectionState.pending);
      expect((await r.readDay('2026-09-15')).sleep.duration.value, 438);

      await r.recalculate(saved);
      final day = await r.readDay('2026-09-15');
      expect(day.correction?.state, CorrectionState.complete);
      expect(day.correction?.id, saved.id);
      expect(day.sleep.onset, DateTime(2026, 9, 14, 23, 25));
      expect(day.sleep.wake, DateTime(2026, 9, 15, 6, 54));
      expect(day.sleep.bedMinutes, 449);
      expect(day.sleep.duration.value, 428);
      expect(day.sleep.awakeMinutes, 21);
      expect(day.sleep.lightMinutes, 237);
      expect(day.sleep.remMinutes, 123);
      expect(day.sleep.deepMinutes, 68);
      expect(day.sleep.segments.first.start, DateTime(2026, 9, 14, 23, 25));
      expect(day.sleep.segments.first.stage, NightStage.light);
      expect(day.synthetic, isTrue);

      await r.restoreAutomatic('2026-09-15');
      final restored = await r.readDay('2026-09-15');
      expect(restored.correction, isNull);
      expect(restored.sleep.duration.value, 438);
      expect(restored.sleep.onset, DateTime(2026, 9, 14, 23, 10));
      expect(await r.readDraft('2026-09-15'), isNull);
    },
  );

  test('partial scenario keeps a null gap from 02:10 to 02:34', () async {
    final r = repo(scenario: SyntheticScenario.partial);
    final day = await r.readDay('2026-09-15');
    expect(day.sleep.duration.readiness, MetricReadiness.partial);
    expect(day.sleep.duration.value, 414);
    expect(day.sleep.unobservedMinutes, 24);
    expect(day.sleep.awakeMinutes, 26);
    expect(day.sleep.lightMinutes, 223);
    expect(day.recovery.readiness, MetricReadiness.available);
    final gap = day.sleep.segments.where((s) => s.stage == null).single;
    expect(gap.start, DateTime(2026, 9, 15, 2, 10));
    expect(gap.end, DateTime(2026, 9, 15, 2, 34));
    expect(r.band.connection, BandConnection.connected);
  });

  test('historic Sept 14 is independent of today and of band state', () async {
    final r = repo();
    final historic = await r.readDay('2026-09-14');
    expect(historic.synthetic, isTrue);
    expect(historic.sleep.duration.value, 422);
    expect(historic.hrv.value, 40);
    expect(historic.restingHr.value, 56);
    expect(historic.recovery.value, isNull);
    expect(historic.recovery.readiness, MetricReadiness.missing);
    expect(historic.strain.readiness, MetricReadiness.missing);

    await r.saveCorrection(_draft('sleep-2026-09-15'));
    await r.recalculate((await r.readDay('2026-09-15')).correction!);
    r.scenario = SyntheticScenario.disconnected;
    expect(r.band.connection, BandConnection.disconnected);
    expect((await r.readDay('2026-09-15')).sleep.duration.value, 428);
    expect((await r.readDay('2026-09-14')).sleep.duration.value, 422);
    expect(
      (await r.readDay('2026-09-14')).recovery.readiness,
      MetricReadiness.missing,
    );

    r.scenario = SyntheticScenario.interrupted;
    expect(r.band.transfer, TransferState.interrupted);
    expect(r.band.connection, BandConnection.connected);
    expect((await r.readDay('2026-09-15')).sleep.duration.value, 428);

    r.scenario = SyntheticScenario.missing;
    expect(r.band.connection, BandConnection.connected);
    expect((await r.readDay('2026-09-15')).sleep.duration.value, isNull);
    expect((await r.readDay('2026-09-14')).sleep.duration.value, 422);

    r.scenario = SyntheticScenario.processing;
    expect(
      (await r.readDay('2026-09-15')).recovery.readiness,
      MetricReadiness.processing,
    );
    expect((await r.readDay('2026-09-14')).hrv.value, 40);
  });

  test(
    'save failure retains draft; retry is idempotent after scenario change',
    () async {
      final r = repo(scenario: SyntheticScenario.saveFailure);
      final draft = _draft('sleep-2026-09-15');
      await r.saveDraft(draft);
      await expectLater(r.saveCorrection(draft), throwsA(isA<StateError>()));
      expect(await r.readDraft('2026-09-15'), isNotNull);
      expect((await r.readDay('2026-09-15')).correction, isNull);

      r.scenario = SyntheticScenario.complete;
      final first = await r.saveCorrection(draft);
      final retry = await r.saveCorrection(draft);
      expect(retry.id, first.id);
      expect(retry.revision, first.revision);
      expect(first.state, CorrectionState.pending);
    },
  );

  test(
    'calculation failure keeps the correction until retry can succeed',
    () async {
      final r = repo(scenario: SyntheticScenario.calculationFailure);
      final draft = _draft('sleep-2026-09-15');
      final saved = await r.saveCorrection(draft);
      await expectLater(r.recalculate(saved), throwsA(isA<StateError>()));
      final failed = await r.readDay('2026-09-15');
      expect(failed.correction?.id, saved.id);
      expect(failed.correction?.state, CorrectionState.failed);
      expect(failed.sleep.duration.value, 438);
      expect(await r.readDraft('2026-09-15'), isNotNull);

      r.scenario = SyntheticScenario.complete;
      await r.recalculate(failed.correction!);
      final done = await r.readDay('2026-09-15');
      expect(done.correction?.id, saved.id);
      expect(done.correction?.state, CorrectionState.complete);
      expect(done.sleep.duration.value, 428);
      expect(done.sleep.awakeMinutes, 21);
    },
  );

  test(
    'readPreviousStrengthSets matches the seeded Ganzkörper A history',
    () async {
      final r = repo();
      final template = (await r.readTemplates()).singleWhere((t) => t.id == 'tpl-ganzkoerper-a');
      final id = await r.startStrengthSession(template);
      final prev = await r.readPreviousStrengthSets(id);
      expect(prev['bp-1']!.loadKg, 37.5);
      expect(prev['bp-1']!.reps, 8);
      expect(prev['bp-1']!.at, DateTime(2026, 9, 13, 18, 10));
      expect(prev['row-2']!.loadKg, 32.5);
      expect(prev['sq-3']!.loadKg, 62.5);
      expect(prev['plank-1']!.seconds, 40);
      expect(prev['plank-1']!.loadKg, isNull);
      expect(prev.containsKey('missing'), isFalse);
      await r.addPlannedSet(
        id,
        PlannedExercise(
          id: 'ex-bench_press',
          exerciseKey: 'bench_press',
          name: 'Bankdrücken',
          sets: const [PlannedSet(id: 'bp-4', reps: 8, loadKg: 40)],
        ),
        const PlannedSet(id: 'bp-4', reps: 8, loadKg: 40),
      );
      expect(
        (await r.readPreviousStrengthSets(id)).containsKey('bp-4'),
        isFalse,
      );
      await expectLater(
        r.readPreviousStrengthSets('foreign-id'),
        throwsA(isA<ArgumentError>()),
      );
    },
  );
}
