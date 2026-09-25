import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

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

NightScalarRow row(
  String day, {
  double? value = 48,
  int algo = kAlgoVersion,
  bool skipped = false,
  bool partial = false,
  bool unreadable = false,
  bool imported = false,
  String? source,
  String? rowSource,
  String? sleepSource,
  String? deviceFamily,
  StoredNightBaseline? baseline,
  NightScalarEnvelope? envelope,
  int? onsetMs,
  int? offsetMs,
  int? computedAtMs = 1000,
}) =>
    NightScalarRow(
      day: day,
      algoVersion: algo,
      skipped: skipped,
      partial: partial,
      payloadUnreadable: unreadable,
      value: value,
      computedAtMs: computedAtMs,
      imported: imported,
      source: source,
      rowSource: rowSource,
      sleepSource: sleepSource,
      deviceFamily: deviceFamily,
      baseline: baseline,
      windowStartMs: onsetMs,
      windowEndMs: offsetMs,
      envelope: envelope,
    );

NightScalarDetail snap({
  String day = '2026-09-15',
  NightScalarMetric key = NightScalarMetric.hrv,
  int nights = 7,
  int currentAlgo = kAlgoVersion,
  NightScalarRow? selected,
  Map<String, NightScalarRow> matching = const {},
  Set<String> otherVersionDays = const {},
  Set<String> seriesOnlyDays = const {},
  Map<String, NightScalarJob> sleepJobs = const {},
  Map<String, NightScalarJob> napJobs = const {},
  String? recordingTimezone,
}) {
  final days = nightScalarDaysEnding(day, nights);
  return buildNightScalarDetail(
    day: day,
    key: key,
    nights: nights,
    currentAlgo: currentAlgo,
    days: days,
    selected: selected,
    matching: matching,
    otherVersionDays: otherVersionDays,
    seriesOnlyDays: seriesOnlyDays,
    sleepJobs: sleepJobs,
    napJobs: napJobs,
    recordingTimezone: recordingTimezone,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nights and metric keys are restricted', () {
    expect(() => requireNightScalarNights(14), throwsArgumentError);
    expect(
      () => nightScalarMetricOf(MetricKey.strain),
      throwsArgumentError,
    );
    expect(nightScalarMetricOf(MetricKey.hrv), NightScalarMetric.hrv);
    expect(
      nightScalarMetricOf(MetricKey.restingHr),
      NightScalarMetric.rhr,
    );
    expect(
      nightScalarMetricOf(MetricKey.respiration),
      NightScalarMetric.respiration,
    );
    expect(
      nightScalarMetricOf(MetricKey.skinTemperature),
      NightScalarMetric.skinTemperature,
    );
    expect(NightScalarMetric.hrv.series, 'rmssd');
    expect(NightScalarMetric.hrv.baselinePath, 'hrv');
    expect(NightScalarMetric.hrv.sqlColumn, 'rmssd');
    expect(NightScalarMetric.hrv.payloadScalar, isNull);
    expect(NightScalarMetric.rhr.series, 'rhr');
    expect(NightScalarMetric.rhr.baselinePath, 'resting_hr');
    expect(NightScalarMetric.rhr.sqlColumn, 'rhr');
    expect(NightScalarMetric.rhr.payloadScalar, isNull);
    expect(NightScalarMetric.respiration.series, 'resp_rate');
    expect(NightScalarMetric.respiration.baselinePath, 'resp');
    expect(NightScalarMetric.respiration.sqlColumn, isNull);
    expect(NightScalarMetric.respiration.payloadScalar, 'resp_rate');
    expect(MetricKey.respiration.series, 'resp_rate');
    expect(NightScalarMetric.skinTemperature.series, 'skin_temp_z');
    expect(NightScalarMetric.skinTemperature.baselinePath, 'skin_temp');
    expect(NightScalarMetric.skinTemperature.sqlColumn, isNull);
    expect(NightScalarMetric.skinTemperature.payloadScalar, 'skin_temp_z');
    expect(MetricKey.skinTemperature.series, 'skin_temp_z');
  });

  test('trailing 30 and 90 are local calendar days, including DST', () {
    const spring = '2026-03-30';
    final thirty = nightScalarDaysEnding(spring, 30);
    expect(thirty, hasLength(30));
    expect(thirty.last, spring);
    expect(thirty.first, '2026-03-01');
    expect(thirty, openBandDaysEnding(spring, 30));
    expect(thirty.toSet(), hasLength(30));
    final ninety = nightScalarDaysEnding('2026-09-15', 90);
    expect(ninety, hasLength(90));
    expect(ninety.first, '2026-06-18');
    expect(ninety.last, '2026-09-15');
  });

  test('synthetic Paper HRV 48 / RHR 54 with baselines 40 / 56 and 15 nights',
      () async {
    final hrv = await repo().readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      30,
    );
    expect(hrv.state, NightScalarState.current);
    expect(hrv.value, 48);
    expect(hrv.baseline?.value, 40);
    expect(hrv.sleepSource, isNull);
    expect(hrv.vendorSource, isNull);
    expect(hrv.recordingTimezone, isNull);
    expect(hrv.history, hasLength(30));
    expect(
      [
        for (final n in hrv.history)
          if (n.value != null) n.value,
      ],
      kNightScalarPaperHrv,
    );
    expect(hrv.counts.compared, 15);
    final rhr = await repo().readNightScalarDetail(
      MetricKey.restingHr,
      '2026-09-15',
      7,
    );
    expect(rhr.value, 54);
    expect(rhr.baseline?.value, 56);
    expect(
      [for (final n in rhr.history) n.value],
      [57, 55, 56, 55, 57, 56, 54],
    );
  });

  test('synthetic Paper respiration 16/min, 15 nights, no trusted baseline',
      () async {
    final resp = await repo().readNightScalarDetail(
      MetricKey.respiration,
      '2026-09-15',
      30,
    );
    expect(resp.key, NightScalarMetric.respiration);
    expect(resp.state, NightScalarState.current);
    expect(resp.value, kNightScalarPaperRespRate);
    expect(resp.baseline, isNull);
    expect(resp.envelope, isNull);
    expect(resp.history, hasLength(30));
    expect(
      [
        for (final n in resp.history)
          if (n.value != null) n.value,
      ],
      kNightScalarPaperResp,
    );
    expect(resp.counts.compared, 15);
    final seven = await repo().readNightScalarDetail(
      MetricKey.respiration,
      '2026-09-15',
      7,
    );
    expect(
      [for (final n in seven.history) n.value],
      [14, 18, 15, 17, 15.5, 16.5, 16],
    );
    final ninety = await repo().readNightScalarDetail(
      MetricKey.respiration,
      '2026-09-15',
      90,
    );
    expect(ninety.history, hasLength(90));
    expect(ninety.history.last.value, 16);
    expect(
      () => repo().readNightScalarDetail(MetricKey.respiration, '2026-09-15', 14),
      throwsArgumentError,
    );
    final day = await repo().readDay('2026-09-15');
    expect(day.respiration.value, 16);
    expect(day.respiration.baseline, isNull);
    expect(day.respiration.nightScalar, NightScalarState.current);
    final history = await repo().readMetricHistory(
      MetricKey.respiration,
      '2026-09-15',
      30,
    );
    expect(history, hasLength(30));
    expect(
      [for (final p in history) if (p.value != null) p.value],
      kNightScalarPaperResp,
    );
  });

  test('synthetic processing withholds hero and keeps storedForInfo', () async {
    final hrv = await repo(scenario: SyntheticScenario.processing)
        .readNightScalarDetail(MetricKey.hrv, '2026-09-15', 7);
    expect(hrv.state, NightScalarState.pending);
    expect(hrv.value, isNull);
    expect(hrv.storedForInfo, 48);
    expect(hrv.evaluationLabel, kNightScalarPendingLabel);
    expect(hrv.history.last.gap, NightScalarGap.withheld);
    expect(hrv.history.last.value, isNull);
  });

  test('unknown provenance stays null, never WHOOP 5.0', () {
    final detail = snap(selected: row('2026-09-15'));
    expect(detail.sleepSource, isNull);
    expect(detail.vendorSource, isNull);
    expect(detail.deviceFamily, isNull);
    expect(detail.recordingTimezone, isNull);
    expect(detail.sleepSource, isNot('WHOOP 5.0'));
  });

  test('finite older selected stays readable and anchors history', () {
    const old = kAlgoVersion - 3;
    final selected = row('2026-09-15', algo: old, value: 41);
    final detail = snap(
      currentAlgo: kAlgoVersion,
      selected: selected,
      matching: {
        '2026-09-14': row('2026-09-14', algo: old, value: 39),
        '2026-09-15': selected,
      },
    );
    expect(detail.state, NightScalarState.older);
    expect(detail.olderCalculation, isTrue);
    expect(detail.partial, isFalse);
    expect(detail.value, 41);
    expect(detail.historyAnchor, old);
    expect(detail.history[5].value, 39);
    expect(detail.counts.compared, 2);
  });

  test('old and partial flags coexist; partial is the published state', () {
    const old = kAlgoVersion - 1;
    final selected = row(
      '2026-09-15',
      algo: old,
      value: 44,
      partial: true,
    );
    final detail = snap(selected: selected, matching: {
      '2026-09-15': selected,
    });
    expect(detail.olderCalculation, isTrue);
    expect(detail.partial, isTrue);
    expect(detail.state, NightScalarState.partial);
    expect(detail.value, 44);
  });

  test('history points keep partial flags; gaps stay null', () {
    final selected = row('2026-09-15', value: 48, partial: true);
    final points = nightScalarHistoryPoints(
      snap(
        selected: selected,
        matching: {
          '2026-09-14': row('2026-09-14', value: 40),
          '2026-09-15': selected,
        },
      ),
    );
    expect(points, hasLength(7));
    expect(MetricPoint('2026-09-14', 40).partial, isFalse);
    expect(points.last.value, 48);
    expect(points.last.partial, isTrue);
    expect(points[5].value, 40);
    expect(points[5].partial, isFalse);
    expect(points[4].value, isNull);
    expect(points[4].partial, isFalse);
  });

  test('skipped and corrupt are refused independently of neighbors', () {
    final selected = row('2026-09-15', skipped: true, value: 48);
    final skipped = snap(
      selected: selected,
      matching: {
        '2026-09-14': row('2026-09-14', value: 40),
        '2026-09-15': selected,
      },
    );
    expect(skipped.state, NightScalarState.missing);
    expect(skipped.value, isNull);
    expect(skipped.history.last.gap, NightScalarGap.skipped);
    expect(skipped.history[5].value, 40);

    final corruptSelected = row('2026-09-15', unreadable: true, value: 48);
    final corrupt = snap(
      selected: corruptSelected,
      matching: {
        '2026-09-13': row('2026-09-13', unreadable: true, value: 11),
        '2026-09-14': row('2026-09-14', value: 40),
        '2026-09-15': corruptSelected,
      },
    );
    expect(corrupt.state, NightScalarState.unreadable);
    expect(corrupt.value, isNull);
    expect(corrupt.storedForInfo, isNull);
    expect(corrupt.historyAnchor, kAlgoVersion);
    expect(corrupt.history[4].gap, NightScalarGap.unreadable);
    expect(corrupt.history[5].value, 40);
    expect(corrupt.counts.unreadable, 2);
    expect(corrupt.counts.compared, 1);
  });

  test('corrupt selected keeps stored algo history, not the current series', () {
    const old = 84;
    const current = 90;
    final oldNeighbor = row('2026-09-14', algo: old, value: 41);
    final selected = row('2026-09-15', algo: old, unreadable: true, value: 48);
    final detail = snap(
      currentAlgo: current,
      selected: selected,
      matching: {
        '2026-09-14': oldNeighbor,
        '2026-09-15': selected,
      },
      otherVersionDays: {'2026-09-13'},
    );
    expect(detail.state, NightScalarState.unreadable);
    expect(detail.value, isNull);
    expect(detail.olderCalculation, isFalse);
    expect(detail.algoVersion, old);
    expect(detail.historyAnchor, old);
    expect(detail.history.last.gap, NightScalarGap.unreadable);
    expect(detail.history[5].value, 41);
    expect(detail.history[4].gap, NightScalarGap.version);
    expect(detail.history[4].value, isNull);
    expect(detail.counts.compared, 1);
    expect(detail.counts.unreadable, 1);
    expect(detail.counts.excludedVersion, 1);
  });

  test('version-mixed, series-only, and imports stay labelled', () {
    final selected = row(
      '2026-09-15',
      value: 48,
      imported: true,
      source: 'whoop_export',
    );
    final detail = snap(
      selected: selected,
      matching: {
        '2026-09-13': row(
          '2026-09-13',
          value: 33,
          imported: true,
          source: 'cloud_v2',
        ),
        '2026-09-15': selected,
      },
      otherVersionDays: {'2026-09-12'},
      seriesOnlyDays: {'2026-09-11'},
    );
    expect(detail.value, 48);
    expect(detail.vendorSource, 'whoop_export');
    expect(detail.history[2].gap, NightScalarGap.unversioned);
    expect(detail.history[3].gap, NightScalarGap.version);
    expect(detail.history[4].source, 'cloud_v2');
    expect(detail.history[4].value, 33);
    expect(detail.history.last.value, 48);
    expect(detail.counts.excludedVersion, 1);
    expect(detail.counts.excludedUnversioned, 1);
    expect(detail.counts.imported, 2);
    expect(detail.counts.sources, {'cloud_v2': 1, 'whoop_export': 1});
  });

  test('baseline stores scalar and metadata without a range', () {
    final unknown = snap(
      selected: row(
        '2026-09-15',
        baseline: const StoredNightBaseline(status: 'unknown'),
      ),
    );
    expect(unknown.baseline?.value, isNull);
    expect(unknown.baseline?.status, 'unknown');
    final provisional = snap(
      selected: row(
        '2026-09-15',
        baseline: const StoredNightBaseline(
          value: 40,
          status: 'provisional',
          nValid: 4,
          nightsSinceUpdate: 2,
          note: 'warming_up',
        ),
      ),
    );
    expect(provisional.baseline?.value, 40);
    expect(provisional.baseline?.status, 'provisional');
    expect(provisional.baseline?.nValid, 4);
    final stale = snap(
      selected: row(
        '2026-09-15',
        baseline: const StoredNightBaseline(
          value: 39,
          status: 'stale',
          nightsSinceUpdate: 12,
        ),
      ),
    );
    expect(stale.baseline?.status, 'stale');
    expect(stale.baseline?.nightsSinceUpdate, 12);
  });

  test('nonfinite selected is missing, not a number', () {
    final detail = snap(
      selected: row('2026-09-15', value: double.nan),
      matching: {
        '2026-09-15': row('2026-09-15', value: double.infinity),
      },
    );
    expect(detail.state, NightScalarState.missing);
    expect(detail.value, isNull);
    expect(detail.history.last.value, isNull);
  });

  test('complete receipt covers later same-algorithm persist and older stored algo', () {
    final selected = row('2026-09-15', algo: 80, value: 42, computedAtMs: 50);
    NightScalarDetail of(NightScalarJob? sleep, NightScalarJob? nap) => snap(
          currentAlgo: 90,
          selected: selected,
          matching: {'2026-09-15': selected},
          sleepJobs: {'2026-09-15': ?sleep},
          napJobs: {'2026-09-15': ?nap},
        );

    final equal = of(
      const NightScalarJob(
        day: '2026-09-15',
        status: 'complete',
        resultAlgo: 80,
        resultComputedAt: 50,
        action: 'automatic',
      ),
      null,
    );
    expect(equal.state, NightScalarState.older);
    expect(equal.value, 42);

    final laterPersist = of(
      const NightScalarJob(
        day: '2026-09-15',
        status: 'complete',
        resultAlgo: 80,
        resultComputedAt: 49,
        action: 'automatic',
      ),
      null,
    );
    expect(laterPersist.state, NightScalarState.older);
    expect(laterPersist.value, 42);

    final stale = of(
      const NightScalarJob(
        day: '2026-09-15',
        status: 'complete',
        resultAlgo: 80,
        resultComputedAt: 51,
      ),
      null,
    );
    expect(stale.state, NightScalarState.outdated);
    expect(stale.value, isNull);
    expect(stale.storedForInfo, 42);
    expect(stale.evaluationLabel, kNightScalarOpenLabel);

    final statusOnly = of(
      const NightScalarJob(day: '2026-09-15', status: 'complete'),
      null,
    );
    expect(statusOnly.state, NightScalarState.unknown);
    expect(statusOnly.value, isNull);
    expect(statusOnly.storedForInfo, 42);
    expect(statusOnly.evaluationLabel, kNightScalarOpenLabel);

    final latestAlgo = of(
      const NightScalarJob(
        day: '2026-09-15',
        status: 'complete',
        resultAlgo: 90,
        resultComputedAt: 50,
      ),
      null,
    );
    expect(latestAlgo.state, NightScalarState.unknown);
    expect(latestAlgo.storedForInfo, 42);
    expect(latestAlgo.evaluationLabel, kNightScalarOpenLabel);

    final identity = of(
      const NightScalarJob(
        day: '2026-09-15',
        status: 'complete',
        identityMatched: false,
        resultAlgo: 80,
        resultComputedAt: 50,
      ),
      null,
    );
    expect(identity.state, NightScalarState.unknown);
    expect(identity.evaluationLabel, kNightScalarOpenLabel);

    final calculating = of(
      const NightScalarJob(day: '2026-09-15', status: 'calculating'),
      null,
    );
    expect(calculating.state, NightScalarState.pending);
    expect(calculating.evaluationLabel, kNightScalarPendingLabel);
    expect(calculating.storedForInfo, 42);

    final napFail = of(
      null,
      const NightScalarJob(day: '2026-09-15', status: 'failed'),
    );
    expect(napFail.state, NightScalarState.failed);
    expect(napFail.storedForInfo, 42);
    expect(napFail.evaluationLabel, kNightScalarFailedLabel);
    expect(napFail.history.last.gap, NightScalarGap.withheld);
  });

  test('window uses onset/offset only when chronological', () {
    final start = DateTime.utc(2026, 3, 29, 22);
    final end = DateTime.utc(2026, 3, 30, 6);
    final ok = snap(
      selected: row(
        '2026-09-15',
        onsetMs: start.millisecondsSinceEpoch,
        offsetMs: end.millisecondsSinceEpoch,
      ),
    );
    expect(ok.window!.start.isAtSameMomentAs(start), isTrue);
    expect(ok.window!.end.isAtSameMomentAs(end), isTrue);
    expect(
      snap(
        selected: row(
          '2026-09-15',
          onsetMs: end.millisecondsSinceEpoch,
          offsetMs: start.millisecondsSinceEpoch,
        ),
      ).window,
      isNull,
    );
    expect(
      snap(
        recordingTimezone: 'Europe/Berlin',
        selected: row('2026-09-15'),
      ).recordingTimezone,
      'Europe/Berlin',
    );
  });

  test('seeded synthetic API is used instead of Paper defaults', () async {
    final r = repo();
    r.seedNightScalarDetail(
      selected: row('2026-09-15', value: 12, sleepSource: 'manual'),
      matching: {
        '2026-09-15': row('2026-09-15', value: 12, sleepSource: 'manual'),
      },
    );
    final detail = await r.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(detail.value, 12);
    expect(detail.sleepSource, 'manual');
    expect(detail.counts.compared, 1);
  });

  test('override proof requires known action and stored window/source', () {
    final onset = DateTime.utc(2026, 9, 14, 21).millisecondsSinceEpoch;
    final wake = DateTime.utc(2026, 9, 15, 5).millisecondsSinceEpoch;
    NightScalarDetail of({
      String? action,
      String? sleepSource,
      int? onsetMs,
      int? offsetMs,
    }) {
      final night = row(
        '2026-09-15',
        value: 48,
        computedAtMs: 900,
        sleepSource: sleepSource,
        onsetMs: onsetMs,
        offsetMs: offsetMs,
      );
      return snap(
        selected: night,
        matching: {'2026-09-15': night},
        sleepJobs: {
          '2026-09-15': NightScalarJob(
            day: '2026-09-15',
            status: 'complete',
            resultAlgo: kAlgoVersion,
            resultComputedAt: 900,
            action: action,
            onsetMs: onset,
            wakeMs: wake,
          ),
        },
      );
    }

    expect(of(action: 'automatic').state, NightScalarState.current);
    expect(of(action: 'automatic').value, 48);
    expect(
      of(
        action: 'override',
        sleepSource: 'manual',
        onsetMs: onset,
        offsetMs: wake,
      ).state,
      NightScalarState.current,
    );
    expect(
      of(
        action: 'override',
        sleepSource: 'confirmed',
        onsetMs: onset,
        offsetMs: wake,
      ).value,
      48,
    );
    final missingProof = of(action: 'override');
    expect(missingProof.state, NightScalarState.unknown);
    expect(missingProof.evaluationLabel, kNightScalarOpenLabel);
    expect(missingProof.storedForInfo, 48);
    expect(
      of(
        action: 'rewrite',
        sleepSource: 'manual',
        onsetMs: onset,
        offsetMs: wake,
      ).state,
      NightScalarState.unknown,
    );
    expect(
      of(
        action: 'override',
        sleepSource: 'automatic',
        onsetMs: onset,
        offsetMs: wake,
      ).state,
      NightScalarState.unknown,
    );
    expect(
      of(
        action: 'override',
        sleepSource: 'manual',
        onsetMs: onset + 60000,
        offsetMs: wake,
      ).state,
      NightScalarState.unknown,
    );
    expect(of().state, NightScalarState.unknown);
    expect(of().storedForInfo, 48);
    expect(of().evaluationLabel, kNightScalarOpenLabel);
  });

  test('imported rows stay labelled without a job; a job cannot prove them', () {
    final imported = row(
      '2026-09-15',
      value: 48,
      computedAtMs: 901,
      imported: true,
      source: 'whoop_export',
    );
    final labelled = snap(
      selected: imported,
      matching: {'2026-09-15': imported},
    );
    expect(labelled.state, NightScalarState.current);
    expect(labelled.value, 48);
    expect(labelled.vendorSource, 'whoop_export');
    expect(labelled.history.last.imported, isTrue);

    final sleepAutomatic = snap(
      selected: imported,
      matching: {'2026-09-15': imported},
      sleepJobs: {
        '2026-09-15': const NightScalarJob(
          day: '2026-09-15',
          status: 'complete',
          resultAlgo: kAlgoVersion,
          resultComputedAt: 900,
          action: 'automatic',
        ),
      },
    );
    expect(sleepAutomatic.state, NightScalarState.unknown);
    expect(sleepAutomatic.value, isNull);
    expect(sleepAutomatic.storedForInfo, 48);
    expect(sleepAutomatic.evaluationLabel, kNightScalarOpenLabel);
    expect(sleepAutomatic.vendorSource, 'whoop_export');

    final napCovered = snap(
      selected: imported,
      matching: {'2026-09-15': imported},
      napJobs: {
        '2026-09-15': const NightScalarJob(
          day: '2026-09-15',
          status: 'complete',
          resultAlgo: kAlgoVersion,
          resultComputedAt: 900,
        ),
      },
    );
    expect(napCovered.state, NightScalarState.unknown);
    expect(napCovered.storedForInfo, 48);

    final measured = row('2026-09-15', value: 48, computedAtMs: 901);
    final measuredLater = snap(
      selected: measured,
      matching: {'2026-09-15': measured},
      sleepJobs: {
        '2026-09-15': const NightScalarJob(
          day: '2026-09-15',
          status: 'complete',
          resultAlgo: kAlgoVersion,
          resultComputedAt: 900,
          action: 'automatic',
        ),
      },
    );
    expect(measuredLater.state, NightScalarState.current);
    expect(measuredLater.value, 48);

    final prior = row(
      '2026-09-14',
      value: 33,
      computedAtMs: 901,
      imported: true,
      source: 'cloud_v2',
    );
    final historyJob = snap(
      selected: measured,
      matching: {'2026-09-14': prior, '2026-09-15': measured},
      sleepJobs: {
        '2026-09-14': const NightScalarJob(
          day: '2026-09-14',
          status: 'complete',
          resultAlgo: kAlgoVersion,
          resultComputedAt: 900,
          action: 'automatic',
        ),
      },
    );
    expect(historyJob.state, NightScalarState.current);
    expect(historyJob.history[5].gap, NightScalarGap.withheld);
    expect(historyJob.history[5].value, isNull);
    final historyOpen = snap(
      selected: measured,
      matching: {'2026-09-14': prior, '2026-09-15': measured},
    );
    expect(historyOpen.history[5].value, 33);
    expect(historyOpen.history[5].imported, isTrue);
    expect(historyOpen.counts.imported, 1);
  });

  test('projection last-wins duplicate keys; malformed flags stay unknown', () {
    final last = projectNightScalarPayload(
      '{"imported":false,"imported":true,'
      '"source":"first","source":"whoop_export",'
      '"sleep_source":"auto","sleep_source":"manual",'
      '"baselines":{"hrv":{"n_valid":-1,"n_valid":3,"baseline":40}}}',
      'hrv',
    );
    expect(nightScalarJsonTrue(last!['imported']), isTrue);
    expect(nightScalarLabel(last['source']), 'whoop_export');
    expect(nightScalarLabel(last['sleep_source']), 'manual');
    expect(nightScalarNonnegInt(last['baseline_n_valid']), 3);

    final resp = projectNightScalarPayload(
      '{"scalars":{"resp_rate":9,"resp_rate":16},'
      '"baselines":{"resp":{"baseline":12,"baseline":14.5,'
      '"status":"open","status":"trusted"}},'
      '"respiration":{"rsa":{"confidence":0.2,"confidence":0.72,'
      '"tier":"high","tier":"estimate",'
      '"inputs_used":["rr_cleaned","beat_times"],'
      '"note":"stable HF peak",'
      '"value":{"brpm":12,"brpm":12.2,"source":"riiv","source":"rsa",'
      '"peak_hz":0.1,"peak_hz":0.27,"power":1,"power":2.5}}}}',
      'resp',
      'resp_rate',
    );
    expect(nightScalarFinite(resp!['scalar']), 16);
    expect(nightScalarFinite(resp['baseline_value']), 14.5);
    expect(nightScalarStatus(resp['baseline_status']), 'trusted');
    final env = nightScalarEnvelope(resp['envelope']);
    expect(env!.confidence, 0.72);
    expect(env.tier, 'estimate');
    expect(env.inputsUsed, ['rr_cleaned', 'beat_times']);
    expect(env.note, 'stable HF peak');
    expect(env.brpm, 12.2);
    expect(env.peakHz, 0.27);
    expect(env.power, 2.5);
    expect(env.source, 'rsa');
    expect(nightScalarEnvelope(null), isNull);
    expect(nightScalarEnvelope({}), isNull);
    expect(nightScalarEnvelope({'confidence': 0.5})!.confidence, 0.5);
    expect(nightScalarEnvelope({'tier': 'estimate'})!.confidence, isNull);
    expect(nightScalarEnvelope({'confidence': double.nan}), isNull);
    expect(nightScalarEnvelope({'confidence': 1.2, 'tier': 'HIGH'})!.confidence, isNull);
    expect(nightScalarEnvelope({'confidence': 0})!.confidence, 0);
    expect(
      nightScalarEnvelope({
        'inputs_used': ['rr_cleaned', 1, true, '  ', {'k': 1}, null],
      })!.inputsUsed,
      ['rr_cleaned'],
    );
    expect(nightScalarEnvelope({'inputs_used': [1, true, {'k': 1}]}), isNull);
    expect(
      nightScalarEnvelope({
        'value': '—',
        'confidence': 0,
        'tier': 'ESTIMATE',
        'note': 'need nn_beats',
      })!.peakHz,
      isNull,
    );

    expect(nightScalarJsonTrue('true'), isFalse);
    expect(nightScalarJsonTrue('1'), isFalse);
    expect(nightScalarNonnegInt(-1), isNull);
    expect(nightScalarEpochMs(0), isNull);
    expect(nightScalarEpochMs(8640000000000001), isNull);

    final stringTrue = snap(
      selected: row('2026-09-15', imported: true, source: 'whoop_export'),
    );
    expect(stringTrue.vendorSource, 'whoop_export');
    expect(
      nightScalarBaseline(value: 40, nValid: -2)?.nValid,
      isNull,
    );
    expect(
      nightScalarBaseline(value: 40, nValid: -2)?.value,
      40,
    );

    const a = NightScalarCounts(
      compared: 2,
      imported: 2,
      sources: {'b': 1, 'a': 1},
    );
    const b = NightScalarCounts(
      compared: 2,
      imported: 2,
      sources: {'a': 1, 'b': 1},
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);

    final outOfRange = snap(
      selected: row('2026-09-15', computedAtMs: 8640000000000001),
    );
    expect(outOfRange.computedAt, isNull);
    expect(outOfRange.value, 48);
  });

  test('card metrics withhold comparison unless current and trusted', () {
    const trusted = StoredNightBaseline(
      value: 40,
      status: kNightScalarTrustedBaseline,
    );
    const provisional = StoredNightBaseline(value: 40, status: 'provisional');
    final current = dayMetricFromNightScalar(
      state: NightScalarState.current,
      value: 48,
      baseline: trusted,
    );
    expect(current.value, 48);
    expect(current.baseline, 40);
    expect(current.nightScalar, NightScalarState.current);
    expect(
      dayMetricFromNightScalar(
        state: NightScalarState.current,
        value: 48,
        baseline: provisional,
      ).baseline,
      isNull,
    );
    expect(
      dayMetricFromNightScalar(
        state: NightScalarState.older,
        value: 41,
        baseline: trusted,
      ).baseline,
      isNull,
    );
    expect(
      dayMetricFromNightScalar(
        state: NightScalarState.partial,
        value: 44,
        baseline: trusted,
      ).baseline,
      isNull,
    );
    final pending = dayMetricFromNightScalar(
      state: NightScalarState.pending,
      value: 48,
      baseline: trusted,
    );
    expect(pending.value, isNull);
    expect(pending.baseline, isNull);
    expect(pending.readiness, MetricReadiness.processing);
    expect(pending.reason, kNightScalarPendingLabel);
    final failed = dayMetricFromNightScalar(
      state: NightScalarState.failed,
      value: 48,
      baseline: trusted,
    );
    expect(failed.value, isNull);
    expect(failed.baseline, isNull);
    expect(failed.readiness, MetricReadiness.missing);
    expect(failed.nightScalar, NightScalarState.failed);
    expect(failed.readiness, isNot(MetricReadiness.unreliable));
    final spaced = nightScalarBaseline(value: 40, status: ' Trusted ');
    expect(spaced?.status, kNightScalarTrustedBaseline);
    expect(
      nightScalarCardBaseline(
        state: NightScalarState.current,
        baseline: spaced,
      ),
      40,
    );
    expect(
      nightScalarCardBaseline(
        state: NightScalarState.current,
        baseline: const StoredNightBaseline(value: 40, status: 'TRUSTED'),
      ),
      40,
    );
    expect(
      nightScalarCardBaseline(
        state: NightScalarState.current,
        baseline: nightScalarBaseline(value: 40, status: ' STALE '),
      ),
      isNull,
    );
  });

  test('synthetic cards follow night-scalar gating and keep other metrics',
      () async {
    final processing = await repo(scenario: SyntheticScenario.processing)
        .readDay('2026-09-15');
    expect(processing.hrv.value, isNull);
    expect(processing.hrv.baseline, isNull);
    expect(processing.hrv.readiness, MetricReadiness.processing);
    expect(processing.hrv.nightScalar, NightScalarState.pending);
    expect(processing.respiration.value, isNull);
    expect(processing.respiration.nightScalar, NightScalarState.pending);
    expect(processing.recovery.value, isNotNull);
    expect(processing.recovery.readiness, MetricReadiness.processing);
    expect(processing.strain.value, isNotNull);
    final yesterday = await repo(scenario: SyntheticScenario.processing)
        .readDay('2026-09-14');
    expect(yesterday.hrv.value, 40);

    final failed = await repo(scenario: SyntheticScenario.calculationFailure)
        .readDay('2026-09-15');
    expect(failed.hrv.value, isNull);
    expect(failed.hrv.baseline, isNull);
    expect(failed.hrv.nightScalar, NightScalarState.failed);
    expect(failed.restingHr.value, isNull);
    expect(failed.respiration.value, isNull);
    expect(failed.respiration.nightScalar, NightScalarState.failed);

    final complete = await repo().readDay('2026-09-15');
    expect(complete.hrv.value, 48);
    expect(complete.hrv.baseline, 40);
    expect(complete.hrv.nightScalar, NightScalarState.current);
    expect(complete.restingHr.value, 54);
    expect(complete.respiration.value, 16);
    expect(complete.respiration.baseline, isNull);
    expect(complete.respiration.nightScalar, NightScalarState.current);
    expect(complete.sleep.duration.value, isNotNull);

    final partial = await repo(scenario: SyntheticScenario.partial)
        .readDay('2026-09-15');
    expect(partial.hrv.value, 48);
    expect(partial.hrv.readiness, MetricReadiness.partial);
    expect(partial.hrv.baseline, isNull);

    final r = repo();
    r.seedNightScalarDetail(
      selected: row(
        '2026-09-15',
        value: 41,
        algo: 84,
        computedAtMs: 900,
        baseline: const StoredNightBaseline(
          value: 40,
          status: kNightScalarTrustedBaseline,
        ),
      ),
      matching: {
        '2026-09-15': row('2026-09-15', value: 41, algo: 84, computedAtMs: 900),
      },
      currentAlgo: 90,
    );
    final older = await r.readDay('2026-09-15');
    expect(older.hrv.value, 41);
    expect(older.hrv.nightScalar, NightScalarState.older);
    expect(older.hrv.baseline, isNull);
    final detail = await r.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(older.hrv.value, detail.value);
    expect(older.hrv.nightScalar, detail.state);

    final history = await repo(scenario: SyntheticScenario.processing)
        .readMetricHistory(MetricKey.hrv, '2026-09-15', 7);
    expect(history.last.value, isNull);
    expect(history[5].value, 40);
    final strain = await repo().readMetricHistory(
      MetricKey.strain,
      '2026-09-15',
      7,
    );
    expect(strain, hasLength(7));
  });

  test('seeded HRV 48ms and RHR 54/min stay independent on the same repo',
      () async {
    final r = repo();
    const hrvBaseline = StoredNightBaseline(
      value: 40,
      status: kNightScalarTrustedBaseline,
      nValid: 14,
    );
    const rhrBaseline = StoredNightBaseline(
      value: 56,
      status: kNightScalarTrustedBaseline,
      nValid: 14,
    );
    final hrvSelected = row(
      '2026-09-15',
      value: 48,
      computedAtMs: 900,
      baseline: hrvBaseline,
    );
    final rhrSelected = row(
      '2026-09-15',
      value: 54,
      computedAtMs: 900,
      baseline: rhrBaseline,
    );
    final sharedJob = NightScalarJob(
      day: '2026-09-15',
      status: 'complete',
      resultAlgo: kAlgoVersion,
      resultComputedAt: 900,
      action: 'automatic',
    );
    r.seedNightScalarDetail(
      selected: hrvSelected,
      matching: {
        '2026-09-14': row('2026-09-14', value: 40, computedAtMs: 800),
        '2026-09-15': hrvSelected,
      },
      otherVersionDays: {'2026-09-13'},
      sleepJobs: {'2026-09-15': sharedJob},
    );
    r.seedNightScalarDetail(
      key: MetricKey.restingHr,
      selected: rhrSelected,
      matching: {
        '2026-09-14': row('2026-09-14', value: 56, computedAtMs: 800),
        '2026-09-15': rhrSelected,
      },
      seriesOnlyDays: {'2026-09-13'},
      sleepJobs: {'2026-09-15': sharedJob},
    );

    final day = await r.readDay('2026-09-15');
    expect(day.hrv.value, 48);
    expect(day.restingHr.value, 54);
    expect(day.hrv.baseline, 40);
    expect(day.restingHr.baseline, 56);
    expect(day.hrv.nightScalar, NightScalarState.current);
    expect(day.restingHr.nightScalar, NightScalarState.current);

    final hrv = await r.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    final rhr = await r.readNightScalarDetail(
      MetricKey.restingHr,
      '2026-09-15',
      7,
    );
    expect(hrv.key, NightScalarMetric.hrv);
    expect(rhr.key, NightScalarMetric.rhr);
    expect(day.hrv.value, hrv.value);
    expect(day.restingHr.value, rhr.value);
    expect(day.hrv.nightScalar, hrv.state);
    expect(day.restingHr.nightScalar, rhr.state);
    expect(hrv.baseline?.value, 40);
    expect(rhr.baseline?.value, 56);
    expect(hrv.history[5].value, 40);
    expect(rhr.history[5].value, 56);
    expect(hrv.history.last.value, 48);
    expect(rhr.history.last.value, 54);
    expect(hrv.counts.excludedVersion, 1);
    expect(rhr.counts.excludedVersion, 0);
    expect(hrv.counts.excludedUnversioned, 0);
    expect(rhr.counts.excludedUnversioned, 1);

    final hrvHistory = await r.readMetricHistory(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    final rhrHistory = await r.readMetricHistory(
      MetricKey.restingHr,
      '2026-09-15',
      7,
    );
    expect(hrvHistory.last.value, hrv.value);
    expect(rhrHistory.last.value, rhr.value);
    expect(hrvHistory[5].value, 40);
    expect(rhrHistory[5].value, 56);
  });

  test('HRV-only seed does not invent RHR value or baseline', () async {
    final r = repo();
    r.seedNightScalarDetail(
      selected: row(
        '2026-09-15',
        value: 48,
        baseline: const StoredNightBaseline(
          value: 40,
          status: kNightScalarTrustedBaseline,
        ),
      ),
      matching: {
        '2026-09-15': row('2026-09-15', value: 48),
      },
    );
    final day = await r.readDay('2026-09-15');
    expect(day.hrv.value, 48);
    expect(day.hrv.baseline, 40);
    expect(day.restingHr.value, isNull);
    expect(day.restingHr.baseline, isNull);
    expect(day.restingHr.nightScalar, NightScalarState.missing);
    expect(day.respiration.value, isNull);
    expect(day.respiration.baseline, isNull);
    expect(day.respiration.nightScalar, NightScalarState.missing);
    final rhr = await r.readNightScalarDetail(
      MetricKey.restingHr,
      '2026-09-15',
      7,
    );
    expect(rhr.key, NightScalarMetric.rhr);
    expect(rhr.value, isNull);
    expect(rhr.state, NightScalarState.missing);
    expect(rhr.baseline, isNull);
    final rhrHistory = await r.readMetricHistory(
      MetricKey.restingHr,
      '2026-09-15',
      7,
    );
    expect(rhrHistory.last.value, isNull);
  });

  test('nightScalarOverride does not leak to the other key or day', () async {
    final r = repo();
    final hrvSeed = row('2026-09-15', value: 48);
    final rhrSeed = row('2026-09-15', value: 54);
    r.seedNightScalarDetail(
      selected: hrvSeed,
      matching: {'2026-09-15': hrvSeed},
    );
    r.seedNightScalarDetail(
      key: MetricKey.restingHr,
      selected: rhrSeed,
      matching: {'2026-09-15': rhrSeed},
    );
    r.nightScalarOverride = snap(
      selected: row('2026-09-15', value: 12),
      matching: {'2026-09-15': row('2026-09-15', value: 12)},
    );
    final hrv = await r.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(hrv.value, 12);
    expect(hrv.key, NightScalarMetric.hrv);
    final day = await r.readDay('2026-09-15');
    expect(day.hrv.value, 12);
    expect(day.hrv.nightScalar, hrv.state);
    expect(day.restingHr.value, 54);
    final rhr = await r.readNightScalarDetail(
      MetricKey.restingHr,
      '2026-09-15',
      7,
    );
    expect(rhr.key, NightScalarMetric.rhr);
    expect(rhr.value, 54);
    expect(day.restingHr.value, rhr.value);
    expect(day.restingHr.nightScalar, rhr.state);
    final otherDay = await r.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-14',
      7,
    );
    expect(otherDay.value, isNot(12));
    final prior = await r.readDay('2026-09-14');
    expect(prior.hrv.value, isNot(12));
  });

  test('seeded detail uses the requested day, not the fixture selected',
      () async {
    final r = repo();
    final selected = row('2026-09-15', value: 48);
    r.seedNightScalarDetail(
      selected: selected,
      matching: {
        '2026-09-14': row('2026-09-14', value: 40),
        '2026-09-15': selected,
      },
    );
    final prior = await r.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-14',
      7,
    );
    expect(prior.day, '2026-09-14');
    expect(prior.value, 40);
    expect(prior.value, isNot(48));
    final day = await r.readDay('2026-09-14');
    expect(day.hrv.value, 40);
    expect(day.hrv.nightScalar, prior.state);
    final history = await r.readMetricHistory(
      MetricKey.hrv,
      '2026-09-14',
      7,
    );
    expect(history.last.day, '2026-09-14');
    expect(history.last.value, 40);
  });

  test('respiration envelope is disclosed and never invents confidence 0.5', () {
    const envelope = NightScalarEnvelope(
      tier: 'estimate',
      confidence: 0.72,
      inputsUsed: ['rr_cleaned', 'beat_times'],
      note: 'stable HF peak',
      brpm: 12.2,
      peakHz: 0.27,
      power: 2.5,
      source: 'rsa',
    );
    final selected = row(
      '2026-09-15',
      value: 16,
      envelope: envelope,
    );
    final detail = snap(
      key: NightScalarMetric.respiration,
      selected: selected,
      matching: {'2026-09-15': selected},
    );
    expect(detail.key, NightScalarMetric.respiration);
    expect(detail.series, 'resp_rate');
    expect(detail.baselinePath, 'resp');
    expect(detail.value, 16);
    expect(detail.value, isNot(envelope.brpm));
    expect(detail.envelope, envelope);
    expect(detail.envelope!.confidence, isNot(0.5));
    expect(detail.envelope!.peakHz, 0.27);
    expect(detail.envelope!.power, 2.5);
    expect(detail.envelope!.source, 'rsa');
    expect(detail.envelope!.brpm, 12.2);

    final noConfidence = snap(
      key: NightScalarMetric.respiration,
      selected: row(
        '2026-09-15',
        value: 16,
        envelope: const NightScalarEnvelope(tier: 'estimate'),
      ),
    );
    expect(noConfidence.envelope!.confidence, isNull);
    expect(noConfidence.envelope!.tier, 'estimate');

    final unreadable = snap(
      key: NightScalarMetric.respiration,
      selected: row(
        '2026-09-15',
        value: 16,
        unreadable: true,
        envelope: envelope,
      ),
    );
    expect(unreadable.state, NightScalarState.unreadable);
    expect(unreadable.envelope, isNull);

    const trusted = StoredNightBaseline(
      value: 15,
      status: kNightScalarTrustedBaseline,
      nValid: 14,
      nightsSinceUpdate: 0,
    );
    expect(
      dayMetricFromNightScalar(
        state: NightScalarState.current,
        value: 16,
        baseline: trusted,
      ).baseline,
      15,
    );
    expect(
      dayMetricFromNightScalar(
        state: NightScalarState.current,
        value: 16,
        baseline: const StoredNightBaseline(value: 15, status: 'open'),
      ).baseline,
      isNull,
    );
    expect(
      dayMetricFromNightScalar(
        state: NightScalarState.current,
        value: 16,
        baseline: const StoredNightBaseline(value: 15, status: 'stale'),
      ).baseline,
      isNull,
    );
  });

  test('respiration missing selected does not borrow a prior night', () {
    final detail = snap(
      key: NightScalarMetric.respiration,
      selected: null,
      matching: {
        '2026-09-14': row('2026-09-14', value: 15),
      },
    );
    expect(detail.state, NightScalarState.missing);
    expect(detail.value, isNull);
    expect(detail.history.last.gap, NightScalarGap.missing);
    expect(detail.history[5].value, 15);
  });

  test('respiration unversioned metric_series is a gap, not a fallback', () {
    final detail = snap(
      key: NightScalarMetric.respiration,
      selected: null,
      seriesOnlyDays: {'2026-09-15', '2026-09-14'},
    );
    expect(detail.state, NightScalarState.missing);
    expect(detail.value, isNull);
    expect(detail.history.last.gap, NightScalarGap.unversioned);
    expect(detail.history.last.value, isNull);
    expect(detail.counts.excludedUnversioned, 2);
  });

  test('respiration seed stays coherent with cards and history', () async {
    final r = repo();
    const envelope = NightScalarEnvelope(
      tier: 'estimate',
      inputsUsed: ['rr_cleaned'],
      note: 'too few beats for an RSA spectral estimate (need ≥20)',
    );
    final selected = row(
      '2026-09-15',
      value: 16,
      envelope: envelope,
      baseline: const StoredNightBaseline(
        value: 15,
        status: kNightScalarTrustedBaseline,
      ),
    );
    r.seedNightScalarDetail(
      key: MetricKey.respiration,
      selected: selected,
      matching: {
        '2026-09-14': row('2026-09-14', value: 15.5),
        '2026-09-15': selected,
      },
    );
    final detail = await r.readNightScalarDetail(
      MetricKey.respiration,
      '2026-09-15',
      7,
    );
    expect(detail.value, 16);
    expect(detail.envelope, envelope);
    expect(detail.envelope!.confidence, isNull);
    expect(detail.baseline?.value, 15);
    final day = await r.readDay('2026-09-15');
    expect(day.respiration.value, 16);
    expect(day.respiration.baseline, 15);
    expect(day.respiration.nightScalar, detail.state);
    expect(day.hrv.value, isNull);
    expect(day.restingHr.value, isNull);
    final history = await r.readMetricHistory(
      MetricKey.respiration,
      '2026-09-15',
      7,
    );
    expect(history.last.value, 16);
    expect(history[5].value, 15.5);
  });

  test('skin-temperature unit classification is source-only and typed', () {
    NightScalarUnit of({
      Object? result,
      Object? payload,
      Object? imported,
    }) =>
        nightScalarSkinTemperatureUnit(
          resultSource: result,
          payloadSource: payload,
          imported: imported,
        );

    expect(of(result: 'band'), NightScalarUnit.sd);
    expect(of(result: 'band', payload: 'band'), NightScalarUnit.sd);
    expect(of(result: 'whoop_export'), NightScalarUnit.celsius);
    expect(
      of(result: 'whoop_export', payload: 'whoop_export'),
      NightScalarUnit.celsius,
    );
    expect(of(result: 'cloud_v2'), NightScalarUnit.unknown);
    expect(
      of(result: 'cloud_v2', payload: 'cloud_v2'),
      NightScalarUnit.unknown,
    );
    expect(of(result: 'other'), NightScalarUnit.unknown);
    expect(of(result: 'band', payload: 'whoop_export'), NightScalarUnit.unknown);
    expect(of(result: 'whoop_export', payload: 'band'), NightScalarUnit.unknown);
    expect(of(result: 'band', payload: 'cloud_v2'), NightScalarUnit.unknown);

    expect(
      of(payload: 'whoop_export', imported: true),
      NightScalarUnit.celsius,
    );
    expect(of(payload: 'whoop_export'), NightScalarUnit.unknown);
    expect(of(payload: 'band'), NightScalarUnit.unknown);
    expect(of(imported: true), NightScalarUnit.unknown);
    expect(of(payload: 'band', imported: true), NightScalarUnit.unknown);
    expect(of(), NightScalarUnit.unknown);

    expect(of(result: 'BAND'), NightScalarUnit.unknown);
    expect(of(result: ' whoop_export '), NightScalarUnit.celsius);
    expect(of(result: ''), NightScalarUnit.unknown);
    expect(of(result: 1), NightScalarUnit.unknown);
    expect(of(result: true), NightScalarUnit.unknown);
    expect(of(result: double.nan), NightScalarUnit.unknown);
    expect(of(payload: double.infinity, imported: true), NightScalarUnit.unknown);
    expect(nightScalarKnownUnit(NightScalarUnit.sd), isTrue);
    expect(nightScalarKnownUnit(NightScalarUnit.celsius), isTrue);
    expect(nightScalarKnownUnit(NightScalarUnit.unknown), isFalse);
    expect(nightScalarKnownUnit(null), isFalse);
  });

  test('skin temperature publishes payload z, never ADC or baseline', () {
    final selected = row(
      '2026-09-15',
      value: 0.4,
      rowSource: 'band',
      source: 'band',
      baseline: const StoredNightBaseline(
        value: 12,
        status: kNightScalarTrustedBaseline,
      ),
    );
    final detail = snap(
      key: NightScalarMetric.skinTemperature,
      selected: selected,
      matching: {'2026-09-15': selected},
    );
    expect(detail.key, NightScalarMetric.skinTemperature);
    expect(detail.series, 'skin_temp_z');
    expect(detail.value, 0.4);
    expect(detail.unit, NightScalarUnit.sd);
    expect(detail.baseline, isNull);
    expect(detail.envelope, isNull);
    expect(detail.resultSource, 'band');
    expect(detail.payloadSource, 'band');
    expect(detail.hasComparableQuantity, isTrue);
    final card = dayMetricFromNightScalar(
      state: detail.state,
      value: detail.value,
      baseline: const StoredNightBaseline(
        value: 12,
        status: kNightScalarTrustedBaseline,
      ),
      unit: detail.unit,
    );
    expect(card.value, 0.4);
    expect(card.baseline, isNull);
    expect(card.unit, NightScalarUnit.sd);
    expect(card.nightScalar, NightScalarState.current);
    expect(card.reason, isNull);
  });

  test('unknown skin-temperature unit keeps storedForInfo and is not missing', () {
    final selected = row(
      '2026-09-15',
      value: 0.4,
      rowSource: 'cloud_v2',
      source: 'cloud_v2',
    );
    final neighbor = row(
      '2026-09-14',
      value: -0.1,
      rowSource: 'band',
      source: 'band',
    );
    final detail = snap(
      key: NightScalarMetric.skinTemperature,
      selected: selected,
      matching: {'2026-09-14': neighbor, '2026-09-15': selected},
    );
    expect(detail.state, NightScalarState.current);
    expect(detail.state, isNot(NightScalarState.missing));
    expect(detail.value, isNull);
    expect(detail.storedForInfo, 0.4);
    expect(detail.unit, NightScalarUnit.unknown);
    expect(detail.hasComparableQuantity, isFalse);
    expect(detail.resultSource, 'cloud_v2');
    expect(detail.payloadSource, 'cloud_v2');
    expect(detail.history.last.gap, NightScalarGap.unit);
    expect(detail.history.last.value, isNull);
    expect(detail.history[5].gap, NightScalarGap.unit);
    expect(detail.history[5].value, isNull);
    expect(detail.counts.compared, 0);
    expect(detail.counts.excludedUnit, 2);
    final card = dayMetricFromNightScalar(
      state: detail.state,
      value: 0.4,
      unit: detail.unit,
    );
    expect(card.value, isNull);
    expect(card.reason, kNightScalarUnknownUnitLabel);
    expect(card.readiness, isNot(MetricReadiness.missing));
    expect(card.nightScalar, NightScalarState.current);
    expect(card.unit, NightScalarUnit.unknown);
  });

  test('celsius skin temperature is usable on card and history', () {
    final selected = row(
      '2026-09-15',
      value: 33.2,
      imported: true,
      source: 'whoop_export',
      rowSource: 'whoop_export',
    );
    final prior = row(
      '2026-09-14',
      value: 33.0,
      imported: true,
      source: 'whoop_export',
      rowSource: 'whoop_export',
    );
    final detail = snap(
      key: NightScalarMetric.skinTemperature,
      selected: selected,
      matching: {'2026-09-14': prior, '2026-09-15': selected},
    );
    expect(detail.state, NightScalarState.current);
    expect(detail.value, 33.2);
    expect(detail.unit, NightScalarUnit.celsius);
    expect(detail.baseline, isNull);
    expect(detail.history[5].value, 33.0);
    expect(detail.history[5].unit, NightScalarUnit.celsius);
    expect(detail.counts.compared, 2);
    final card = dayMetricFromNightScalar(
      state: detail.state,
      value: detail.value,
      unit: detail.unit,
    );
    expect(card.value, 33.2);
    expect(card.unit, NightScalarUnit.celsius);
    expect(card.readiness, MetricReadiness.available);
    expect(card.reason, isNull);
    expect(card.baseline, isNull);
  });

  test('mixed skin-temperature units become gaps with exclusion count', () {
    final selected = row(
      '2026-09-15',
      value: 0.4,
      rowSource: 'band',
      source: 'band',
    );
    final detail = snap(
      key: NightScalarMetric.skinTemperature,
      selected: selected,
      matching: {
        '2026-09-12': row(
          '2026-09-12',
          value: 33.2,
          imported: true,
          source: 'whoop_export',
          rowSource: 'whoop_export',
        ),
        '2026-09-13': row(
          '2026-09-13',
          value: 0.2,
          rowSource: 'cloud_v2',
          source: 'cloud_v2',
        ),
        '2026-09-14': row(
          '2026-09-14',
          value: -0.1,
          rowSource: 'band',
          source: 'band',
        ),
        '2026-09-15': selected,
      },
    );
    expect(detail.unit, NightScalarUnit.sd);
    expect(detail.value, 0.4);
    expect(detail.history[3].gap, NightScalarGap.unit);
    expect(detail.history[3].value, isNull);
    expect(detail.history[3].resultSource, 'whoop_export');
    expect(detail.history[3].payloadSource, 'whoop_export');
    expect(detail.history[4].gap, NightScalarGap.unit);
    expect(detail.history[4].resultSource, 'cloud_v2');
    expect(detail.history[4].payloadSource, 'cloud_v2');
    expect(detail.history[5].value, -0.1);
    expect(detail.history[5].unit, NightScalarUnit.sd);
    expect(detail.history[5].resultSource, 'band');
    expect(detail.history[5].payloadSource, 'band');
    expect(detail.history.last.value, 0.4);
    expect(detail.counts.compared, 2);
    expect(detail.counts.excludedUnit, 2);
    expect(detail.counts.sources, {'band': 2});
  });

  test('history keeps both source channels without conflating counts', () {
    final selected = row(
      '2026-09-15',
      value: 0.4,
      rowSource: 'band',
    );
    final detail = snap(
      key: NightScalarMetric.skinTemperature,
      selected: selected,
      matching: {
        '2026-09-11': row(
          '2026-09-11',
          value: 33.2,
          imported: true,
          source: 'whoop_export',
          rowSource: 'whoop_export',
        ),
        '2026-09-12': row(
          '2026-09-12',
          value: 0.2,
          rowSource: 'cloud_v2',
          source: 'cloud_v2',
        ),
        '2026-09-13': row(
          '2026-09-13',
          value: 0.1,
          rowSource: 'band',
          source: 'whoop_export',
          imported: true,
        ),
        '2026-09-14': row(
          '2026-09-14',
          value: -0.1,
          rowSource: 'band',
        ),
        '2026-09-15': selected,
      },
    );
    expect(detail.unit, NightScalarUnit.sd);
    expect(detail.value, 0.4);
    expect(detail.history.last.resultSource, 'band');
    expect(detail.history.last.payloadSource, isNull);
    expect(detail.history.last.source, isNull);
    expect(detail.history[5].resultSource, 'band');
    expect(detail.history[5].payloadSource, isNull);
    expect(detail.history[5].value, -0.1);

    expect(detail.history[2].gap, NightScalarGap.unit);
    expect(detail.history[2].value, isNull);
    expect(detail.history[2].resultSource, 'whoop_export');
    expect(detail.history[2].payloadSource, 'whoop_export');
    expect(detail.history[2].unit, NightScalarUnit.celsius);

    expect(detail.history[3].gap, NightScalarGap.unit);
    expect(detail.history[3].resultSource, 'cloud_v2');
    expect(detail.history[3].payloadSource, 'cloud_v2');
    expect(detail.history[3].unit, NightScalarUnit.unknown);

    expect(detail.history[4].gap, NightScalarGap.unit);
    expect(detail.history[4].resultSource, 'band');
    expect(detail.history[4].payloadSource, 'whoop_export');
    expect(detail.history[4].source, 'whoop_export');
    expect(detail.history[4].unit, NightScalarUnit.unknown);
    expect(detail.counts.compared, 2);
    expect(detail.counts.excludedUnit, 3);
    expect(detail.counts.sources, {'band': 2});
    expect(detail.counts.sources.containsKey('whoop_export'), isFalse);
    expect(detail.counts.sources.containsKey('cloud_v2'), isFalse);
  });

  test('null-column whoop import is legacy C; band or imported alone is unknown', () {
    final legacy = row(
      '2026-09-15',
      value: 33.2,
      imported: true,
      source: 'whoop_export',
    );
    final legacyDetail = snap(
      key: NightScalarMetric.skinTemperature,
      selected: legacy,
      matching: {'2026-09-15': legacy},
    );
    expect(legacyDetail.unit, NightScalarUnit.celsius);
    expect(legacyDetail.value, 33.2);
    expect(legacyDetail.resultSource, isNull);
    expect(legacyDetail.payloadSource, 'whoop_export');

    final bandOnly = row('2026-09-15', value: 0.4, source: 'band');
    expect(
      snap(
        key: NightScalarMetric.skinTemperature,
        selected: bandOnly,
        matching: {'2026-09-15': bandOnly},
      ).unit,
      NightScalarUnit.unknown,
    );
    final importedAlone = row('2026-09-15', value: 0.4, imported: true);
    final unknownImported = snap(
      key: NightScalarMetric.skinTemperature,
      selected: importedAlone,
      matching: {'2026-09-15': importedAlone},
    );
    expect(unknownImported.unit, NightScalarUnit.unknown);
    expect(unknownImported.value, isNull);
    expect(unknownImported.storedForInfo, 0.4);
  });

  test('conflicting sources stay unknown and retain both channels', () {
    final selected = row(
      '2026-09-15',
      value: 0.4,
      rowSource: 'band',
      source: 'whoop_export',
      imported: true,
    );
    final detail = snap(
      key: NightScalarMetric.skinTemperature,
      selected: selected,
      matching: {'2026-09-15': selected},
    );
    expect(detail.unit, NightScalarUnit.unknown);
    expect(detail.resultSource, 'band');
    expect(detail.payloadSource, 'whoop_export');
    expect(detail.vendorSource, 'whoop_export');
    expect(detail.value, isNull);
    expect(detail.storedForInfo, 0.4);
  });

  test('skin-temperature missing selected does not borrow a prior unit', () {
    final detail = snap(
      key: NightScalarMetric.skinTemperature,
      selected: null,
      matching: {
        '2026-09-14': row(
          '2026-09-14',
          value: 0.2,
          rowSource: 'band',
          source: 'band',
        ),
      },
    );
    expect(detail.state, NightScalarState.missing);
    expect(detail.value, isNull);
    expect(detail.storedForInfo, isNull);
    expect(detail.unit, isNull);
    expect(detail.history.last.gap, NightScalarGap.missing);
    expect(detail.history[5].gap, NightScalarGap.unit);
    expect(detail.history[5].value, isNull);
    expect(detail.counts.excludedUnit, 1);
  });

  test('withheld skin-temperature receipt keeps raw and beats unknown unit', () {
    final selected = row(
      '2026-09-15',
      value: 0.4,
      rowSource: 'cloud_v2',
      source: 'cloud_v2',
      computedAtMs: 900,
    );
    final pending = snap(
      key: NightScalarMetric.skinTemperature,
      selected: selected,
      matching: {'2026-09-15': selected},
      sleepJobs: {
        '2026-09-15': const NightScalarJob(
          day: '2026-09-15',
          status: 'pending',
        ),
      },
    );
    expect(pending.state, NightScalarState.pending);
    expect(pending.value, isNull);
    expect(pending.storedForInfo, 0.4);
    expect(pending.unit, NightScalarUnit.unknown);
    expect(pending.evaluationLabel, kNightScalarPendingLabel);
    expect(pending.history.last.gap, NightScalarGap.withheld);
    final card = dayMetricFromNightScalar(
      state: pending.state,
      value: 0.4,
      unit: pending.unit,
    );
    expect(card.reason, kNightScalarPendingLabel);
    expect(card.reason, isNot(kNightScalarUnknownUnitLabel));
    expect(card.unit, NightScalarUnit.unknown);
  });

  test('paper SD and C synthetic seeds stay explicit and unmixed', () async {
    final sdRepo = repo();
    sdRepo.seedPaperSkinTemperature();
    final sd = await sdRepo.readNightScalarDetail(
      MetricKey.skinTemperature,
      '2026-09-15',
      30,
    );
    expect(sd.state, NightScalarState.current);
    expect(sd.value, kNightScalarPaperSkinTempSdSelected);
    expect(sd.unit, NightScalarUnit.sd);
    expect(sd.baseline, isNull);
    expect(sd.history, hasLength(30));
    expect(
      [for (final n in sd.history) ?n.value],
      [for (final v in kNightScalarPaperSkinTempSd) ?v],
    );
    expect(sd.counts.compared, 14);
    expect(sd.history[19].gap, NightScalarGap.missing);
    final sdDay = await sdRepo.readDay('2026-09-15');
    expect(sdDay.skinTemperature.value, 0.4);
    expect(sdDay.skinTemperature.unit, NightScalarUnit.sd);
    expect(sdDay.skinTemperature.baseline, isNull);
    expect(sdDay.hrv.value, isNull);
    final sdHistory = await sdRepo.readMetricHistory(
      MetricKey.skinTemperature,
      '2026-09-15',
      30,
    );
    expect(
      [for (final p in sdHistory) ?p.value],
      [for (final v in kNightScalarPaperSkinTempSd) ?v],
    );

    final seven = await sdRepo.readNightScalarDetail(
      MetricKey.skinTemperature,
      '2026-09-15',
      7,
    );
    final trailingSeven = kNightScalarPaperSkinTempSd.sublist(
      kNightScalarPaperSkinTempSd.length - 7,
    );
    expect(seven.history, hasLength(7));
    expect(
      [for (final n in seven.history) n.value],
      trailingSeven,
    );
    expect(seven.value, 0.4);
    expect(seven.counts.compared, 7);
    expect(seven.history.first.resultSource, 'band');

    final ninety = await sdRepo.readNightScalarDetail(
      MetricKey.skinTemperature,
      '2026-09-15',
      90,
    );
    expect(ninety.history, hasLength(90));
    expect(ninety.history[75].value, -0.2);
    expect(ninety.history[79].gap, NightScalarGap.missing);
    expect(ninety.history.last.value, 0.4);
    expect(ninety.counts.compared, 14);

    final cRepo = repo();
    cRepo.seedPaperSkinTemperature(unit: NightScalarUnit.celsius);
    final c = await cRepo.readNightScalarDetail(
      MetricKey.skinTemperature,
      '2026-09-15',
      30,
    );
    expect(c.value, kNightScalarPaperSkinTempCSelected);
    expect(c.unit, NightScalarUnit.celsius);
    expect(c.counts.compared, 14);
    expect(c.history.last.value, 33.2);
    final cDay = await cRepo.readDay('2026-09-15');
    expect(cDay.skinTemperature.value, 33.2);
    expect(cDay.skinTemperature.unit, NightScalarUnit.celsius);
    expect(cDay.skinTemperature.reason, isNull);

    final unknownRepo = repo();
    unknownRepo.seedPaperSkinTemperature(unit: NightScalarUnit.unknown);
    final unknown = await unknownRepo.readNightScalarDetail(
      MetricKey.skinTemperature,
      '2026-09-15',
      30,
    );
    expect(unknown.unit, NightScalarUnit.unknown);
    expect(unknown.value, isNull);
    expect(unknown.storedForInfo, 0.4);
    expect(unknown.hasComparableQuantity, isFalse);
    expect(unknown.counts.compared, 0);
    expect(
      unknown.history.where((n) => n.value != null),
      isEmpty,
    );
    final unknownDay = await unknownRepo.readDay('2026-09-15');
    expect(unknownDay.skinTemperature.value, isNull);
    expect(unknownDay.skinTemperature.reason, kNightScalarUnknownUnitLabel);
    expect(unknownDay.skinTemperature.nightScalar, NightScalarState.current);
    expect(unknownDay.skinTemperature.unit, NightScalarUnit.unknown);
  });

  test('unseeded synthetic skin temperature is not fabricated', () async {
    final day = await repo().readDay('2026-09-15');
    expect(day.skinTemperature.value, isNull);
    expect(day.skinTemperature.nightScalar, NightScalarState.missing);
    expect(day.skinTemperature.unit, isNull);
    expect(day.hrv.value, 48);
    expect(day.respiration.value, 16);
    final detail = await repo().readNightScalarDetail(
      MetricKey.skinTemperature,
      '2026-09-15',
      7,
    );
    expect(detail.state, NightScalarState.missing);
    expect(detail.value, isNull);
    expect(detail.unit, isNull);
  });
}
