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
  String? sleepSource,
  String? deviceFamily,
  StoredNightBaseline? baseline,
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
      sleepSource: sleepSource,
      deviceFamily: deviceFamily,
      baseline: baseline,
      windowStartMs: onsetMs,
      windowEndMs: offsetMs,
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

    final complete = await repo().readDay('2026-09-15');
    expect(complete.hrv.value, 48);
    expect(complete.hrv.baseline, isNull);
    expect(complete.hrv.nightScalar, NightScalarState.current);
    expect(complete.restingHr.value, 54);
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
}
