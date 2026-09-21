import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
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

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await LocalDb.close();
    LocalDb.dbName = 'openband_night_scalar_repository_test.db';
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

  Future<void> putNight(
    String day, {
    double? rmssd,
    double? rhr,
    int algo = kAlgoVersion,
    bool skipped = false,
    bool partial = false,
    bool imported = false,
    String? source,
    String? sleepSource,
    String? deviceFamily,
    String? payloadJson,
    Map<String, Object?>? baselineHrv,
    Map<String, Object?>? baselineRhr,
    int? onsetMs,
    int? offsetMs,
    int? computedAt,
  }) async {
    await LocalDb.putDayResult(
      dayId: day,
      algoVersion: algo,
      payloadJson: payloadJson ??
            jsonEncode({
            if (imported) 'imported': true,
            'source': ?source,
            'sleep_source': ?sleepSource,
            'device_family': ?deviceFamily,
            'scalars': {'rmssd': rmssd, 'rhr': rhr},
            if (onsetMs != null || offsetMs != null)
              'sleep': {
                'window': {
                  'value': {
                    'onset_ms': ?onsetMs,
                    'offset_ms': ?offsetMs,
                  },
                },
              },
            'baselines': {
              'hrv': ?baselineHrv,
              'resting_hr': ?baselineRhr,
            },
          }),
      windowJson: '{}',
      skipped: skipped,
      partial: partial,
      rmssd: rmssd,
      rhr: rhr,
      source: source,
    );
    if (computedAt != null) {
      final db = await LocalDb.instance;
      await db.update(
        'day_result',
        {'computed_at': computedAt},
        where: 'day_id = ? AND algo_version = ?',
        whereArgs: [day, algo],
      );
    }
  }

  final overrideOnset = DateTime.utc(2026, 9, 14, 21).millisecondsSinceEpoch;
  final overrideWake = DateTime.utc(2026, 9, 15, 5).millisecondsSinceEpoch;

  Future<void> putCoveredNight(
    String day, {
    double? rmssd,
    double? rhr,
    int algo = kAlgoVersion,
    bool partial = false,
    bool imported = false,
    String? source,
    int computedAt = 900,
    String sleepSource = 'manual',
  }) =>
      putNight(
        day,
        rmssd: rmssd,
        rhr: rhr,
        algo: algo,
        partial: partial,
        imported: imported,
        source: source,
        computedAt: computedAt,
        sleepSource: sleepSource,
        onsetMs: overrideOnset,
        offsetMs: overrideWake,
      );

  Future<void> putSleepJob(
    String day, {
    required String status,
    int? resultAlgo,
    int? resultAt,
    bool mismatchRevision = false,
    String? action,
  }) async {
    final onset = DateTime.utc(2026, 9, 14, 21).millisecondsSinceEpoch;
    final wake = DateTime.utc(2026, 9, 15, 5).millisecondsSinceEpoch;
    await LocalDb.putOpenBandSleepDraft(
      dayId: day,
      draftId: 'draft-$day',
      onsetMs: onset,
      wakeMs: wake,
      recordingTimezone: 'Europe/Berlin',
    );
    final saved = await LocalDb.commitOpenBandSleepCorrection(
      dayId: day,
      draftId: 'draft-$day',
      onsetMs: onset,
      wakeMs: wake,
      recordingTimezone: 'Europe/Berlin',
    );
    if (mismatchRevision) {
      final db = await LocalDb.instance;
      await db.update(
        'openband_sleep_correction',
        {'revision': 9},
        where: 'day_id = ?',
        whereArgs: [day],
      );
    }
    await LocalDb.updateOpenBandCalculationJob(
      dayId: day,
      correctionId: saved['correction_id'] as String,
      revision: mismatchRevision ? 9 : 1,
      status: status,
      resultAlgoVersion: resultAlgo,
      resultComputedAt: resultAt,
      fromStatuses: {'pending'},
    );
    if (action != null) {
      final db = await LocalDb.instance;
      await db.update(
        'openband_sleep_correction',
        {'action': action},
        where: 'day_id = ?',
        whereArgs: [day],
      );
    }
  }

  Future<void> putNapJob(
    String day, {
    required String status,
    int? resultAlgo,
    int? resultAt,
  }) async {
    final db = await LocalDb.instance;
    await db.insert('nap_recalc_job', {
      'day_id': day,
      'revision': 1,
      'status': status,
      'requested_at': 1,
      'updated_at': 1,
      'result_algo_version': resultAlgo,
      'result_computed_at': resultAt,
    });
  }

  test('missing selected is a typed gap, neighbors stay', () async {
    await putNight('2026-09-14', rmssd: 40);
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.state, NightScalarState.missing);
    expect(snap.value, isNull);
    expect(snap.history.last.gap, NightScalarGap.missing);
    expect(snap.history[5].value, 40);
    expect(snap.historyAnchor, kAlgoVersion);
  });

  test('partial finite selected is published with the partial flag', () async {
    await putNight('2026-09-15', rmssd: 48, partial: true);
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.state, NightScalarState.partial);
    expect(snap.partial, isTrue);
    expect(snap.value, 48);
    expect(snap.history.last.value, 48);
    expect(snap.history.last.partial, isTrue);
  });

  test('skipped selected is refused even with a stored column', () async {
    await putNight('2026-09-14', rmssd: 40);
    await putNight('2026-09-15', rmssd: 48, skipped: true);
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.state, NightScalarState.missing);
    expect(snap.value, isNull);
    expect(snap.history.last.gap, NightScalarGap.skipped);
    expect(snap.counts.excludedSkipped, 1);
    expect(snap.history[5].value, 40);
  });

  test('corrupt selected and neighbor do not drop the rest of the window',
      () async {
    await putNight('2026-09-13', rmssd: 36);
    await putNight(
      '2026-09-14',
      rmssd: 40,
      payloadJson: '{not-json',
    );
    await putNight(
      '2026-09-15',
      rmssd: 48,
      payloadJson: '[]',
    );
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.state, NightScalarState.unreadable);
    expect(snap.value, isNull);
    expect(snap.history[4].value, 36);
    expect(snap.history[5].gap, NightScalarGap.unreadable);
    expect(snap.history.last.gap, NightScalarGap.unreadable);
    expect(snap.counts.unreadable, 2);
    expect(snap.counts.compared, 1);
    expect(snap.historyAnchor, kAlgoVersion);
  });

  test('corrupt selected on an old algo keeps that generation in history',
      () async {
    const old = 84;
    await putNight('2026-09-13', rmssd: 41, algo: old);
    await putNight('2026-09-14', rmssd: 99);
    await putNight(
      '2026-09-15',
      rmssd: 48,
      algo: old,
      payloadJson: '{not-json',
    );
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.state, NightScalarState.unreadable);
    expect(snap.value, isNull);
    expect(snap.olderCalculation, isFalse);
    expect(snap.historyAnchor, old);
    expect(snap.algoVersion, old);
    expect(snap.history[4].value, 41);
    expect(snap.history[5].gap, NightScalarGap.version);
    expect(snap.history[5].value, isNull);
    expect(snap.history.last.gap, NightScalarGap.unreadable);
    expect(snap.counts.compared, 1);
    expect(snap.counts.unreadable, 1);
    expect(snap.counts.excludedVersion, 1);
  });

  test('older selected stays readable; mixed versions are excluded counts',
      () async {
    const old = kAlgoVersion - 2;
    await putNight('2026-09-13', rmssd: 30, algo: old);
    await putNight('2026-09-14', rmssd: 99);
    await putNight('2026-09-15', rmssd: 41, algo: old, partial: true);
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.olderCalculation, isTrue);
    expect(snap.partial, isTrue);
    expect(snap.state, NightScalarState.partial);
    expect(snap.value, 41);
    expect(snap.historyAnchor, old);
    expect(snap.history[4].value, 30);
    expect(snap.history[5].gap, NightScalarGap.version);
    expect(snap.history.last.value, 41);
    expect(snap.counts.excludedVersion, 1);
    expect(snap.counts.compared, 2);
  });

  test('WHOOP and cloud imports remain visible with source labels', () async {
    await putNight(
      '2026-09-13',
      rmssd: 33,
      imported: true,
      source: 'cloud_v2',
    );
    await putNight(
      '2026-09-15',
      rmssd: 48,
      imported: true,
      source: 'whoop_export',
      sleepSource: 'manual',
    );
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.value, 48);
    expect(snap.vendorSource, 'whoop_export');
    expect(snap.sleepSource, 'manual');
    expect(snap.history[4].source, 'cloud_v2');
    expect(snap.history[4].imported, isTrue);
    expect(snap.counts.imported, 2);
    expect(snap.counts.sources['whoop_export'], 1);
    expect(snap.counts.sources['cloud_v2'], 1);
  });

  test('series-only nights are unversioned exclusions, not bars', () async {
    await putNight('2026-09-15', rmssd: 48);
    await LocalDb.putMetricSeriesValue('2026-09-12', 'rmssd', 77);
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.history[3].gap, NightScalarGap.unversioned);
    expect(snap.history[3].value, isNull);
    expect(snap.counts.excludedUnversioned, 1);
    expect(snap.value, 48);
  });

  test('30 and 90 trailing windows are exact local calendar lengths', () async {
    await putNight('2026-03-30', rmssd: 21);
    final thirty = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-03-30',
      30,
    );
    expect(thirty.history, hasLength(30));
    expect(thirty.history.first.day, '2026-03-01');
    expect(thirty.history.last.day, '2026-03-30');
    expect(thirty.history.last.value, 21);
    final ninety = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-03-30',
      90,
    );
    expect(ninety.history, hasLength(90));
    expect(ninety.history.first.day, '2025-12-31');
  });

  test('stored baseline unknown / provisional / stale is not refolded',
      () async {
    await putNight(
      '2026-09-15',
      rmssd: 48,
      baselineHrv: {
        'baseline': null,
        'status': 'unknown',
        'n_valid': 0,
        'nights_since_update': 0,
      },
    );
    expect(
      (await repository.readNightScalarDetail(
        MetricKey.hrv,
        '2026-09-15',
        7,
      ))
          .baseline,
      const StoredNightBaseline(
        status: 'unknown',
        nValid: 0,
        nightsSinceUpdate: 0,
      ),
    );
    await putNight(
      '2026-09-15',
      rhr: 54,
      baselineRhr: {
        'baseline': 56,
        'status': 'provisional',
        'n_valid': 5,
        'nights_since_update': 1,
        'note': 'warming_up',
      },
    );
    final provisional = await repository.readNightScalarDetail(
      MetricKey.restingHr,
      '2026-09-15',
      7,
    );
    expect(provisional.baseline?.value, 56);
    expect(provisional.baseline?.status, 'provisional');
    expect(provisional.baseline?.nValid, 5);
    await putNight(
      '2026-09-15',
      rmssd: 48,
      baselineHrv: {
        'baseline': 40,
        'status': 'stale',
        'nights_since_update': 11,
      },
    );
    final stale = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(stale.baseline?.status, 'stale');
    expect(stale.baseline?.nightsSinceUpdate, 11);
    expect(stale.baseline?.value, 40);
  });

  test('sleep pending withholds hero and keeps the stored scalar', () async {
    await putNight('2026-09-15', rmssd: 48, computedAt: 5000);
    await putSleepJob('2026-09-15', status: 'pending');
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.state, NightScalarState.pending);
    expect(snap.value, isNull);
    expect(snap.storedForInfo, 48);
    expect(snap.evaluationLabel, kNightScalarPendingLabel);
    expect(snap.recordingTimezone, 'Europe/Berlin');
    expect(snap.history.last.gap, NightScalarGap.withheld);
  });

  test('complete sleep receipt covering an older stored row stays readable',
      () async {
    const old = kAlgoVersion - 4;
    await putCoveredNight('2026-09-15', rmssd: 41, algo: old, computedAt: 900);
    await putSleepJob(
      '2026-09-15',
      status: 'complete',
      resultAlgo: old,
      resultAt: 900,
    );
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.state, NightScalarState.older);
    expect(snap.value, 41);
    expect(snap.storedForInfo, isNull);
  });

  test('complete sleep receipt at latest algo does not cover an older row',
      () async {
    const old = kAlgoVersion - 4;
    await putNight('2026-09-15', rmssd: 41, algo: old, computedAt: 900);
    await putSleepJob(
      '2026-09-15',
      status: 'complete',
      resultAlgo: kAlgoVersion,
      resultAt: 900,
    );
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.state, NightScalarState.unknown);
    expect(snap.value, isNull);
    expect(snap.storedForInfo, 41);
    expect(snap.evaluationLabel, kNightScalarOpenLabel);
  });

  test('later same-algorithm persist still satisfies the sleep receipt',
      () async {
    await putCoveredNight('2026-09-15', rmssd: 48, computedAt: 901);
    await putSleepJob(
      '2026-09-15',
      status: 'complete',
      resultAlgo: kAlgoVersion,
      resultAt: 900,
    );
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.state, NightScalarState.current);
    expect(snap.value, 48);
  });

  test('imported overwrite after an automatic sleep job is unproven', () async {
    await putCoveredNight(
      '2026-09-15',
      rmssd: 48,
      imported: true,
      source: 'whoop_export',
      computedAt: 901,
    );
    await putSleepJob(
      '2026-09-15',
      status: 'complete',
      resultAlgo: kAlgoVersion,
      resultAt: 900,
      action: 'automatic',
    );
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.state, NightScalarState.unknown);
    expect(snap.value, isNull);
    expect(snap.storedForInfo, 48);
    expect(snap.evaluationLabel, kNightScalarOpenLabel);
    expect(snap.vendorSource, 'whoop_export');
    expect(snap.history.last.gap, NightScalarGap.withheld);
  });

  test('imported overwrite after a complete nap job is unproven', () async {
    await putNight(
      '2026-09-15',
      rhr: 54,
      imported: true,
      source: 'cloud_v2',
      computedAt: 901,
    );
    await putNapJob(
      '2026-09-15',
      status: 'complete',
      resultAlgo: kAlgoVersion,
      resultAt: 900,
    );
    final snap = await repository.readNightScalarDetail(
      MetricKey.restingHr,
      '2026-09-15',
      7,
    );
    expect(snap.state, NightScalarState.unknown);
    expect(snap.storedForInfo, 54);
    expect(snap.evaluationLabel, kNightScalarOpenLabel);
  });

  test('complete without result fields is unknown, not a queued job', () async {
    await putCoveredNight('2026-09-15', rmssd: 48, computedAt: 700);
    await putSleepJob('2026-09-15', status: 'complete');
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.state, NightScalarState.unknown);
    expect(snap.storedForInfo, 48);
    expect(snap.evaluationLabel, kNightScalarOpenLabel);
  });

  test('sleep identity mismatch is unknown, not pending', () async {
    await putCoveredNight('2026-09-15', rmssd: 48, computedAt: 700);
    await putSleepJob(
      '2026-09-15',
      status: 'complete',
      resultAlgo: kAlgoVersion,
      resultAt: 700,
      mismatchRevision: true,
    );
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.state, NightScalarState.unknown);
    expect(snap.storedForInfo, 48);
    expect(snap.evaluationLabel, kNightScalarOpenLabel);
  });

  test('override without stored window/source is unknown, not pending',
      () async {
    await putNight('2026-09-15', rmssd: 48, computedAt: 900);
    await putSleepJob(
      '2026-09-15',
      status: 'complete',
      resultAlgo: kAlgoVersion,
      resultAt: 900,
    );
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.state, NightScalarState.unknown);
    expect(snap.storedForInfo, 48);
    expect(snap.evaluationLabel, kNightScalarOpenLabel);
  });

  test('failed nap withholds and preserves storedForInfo', () async {
    await putNight('2026-09-15', rhr: 54, computedAt: 800);
    await putNapJob('2026-09-15', status: 'failed');
    final snap = await repository.readNightScalarDetail(
      MetricKey.restingHr,
      '2026-09-15',
      7,
    );
    expect(snap.state, NightScalarState.failed);
    expect(snap.value, isNull);
    expect(snap.storedForInfo, 54);
  });

  test('complete nap receipt must cover the stored result', () async {
    await putNight('2026-09-15', rhr: 54, computedAt: 800);
    await putNapJob(
      '2026-09-15',
      status: 'complete',
      resultAlgo: kAlgoVersion,
      resultAt: 801,
    );
    final mismatch = await repository.readNightScalarDetail(
      MetricKey.restingHr,
      '2026-09-15',
      7,
    );
    expect(mismatch.state, NightScalarState.outdated);
    expect(mismatch.storedForInfo, 54);
    expect(mismatch.evaluationLabel, kNightScalarOpenLabel);
    final db = await LocalDb.instance;
    await db.update(
      'nap_recalc_job',
      {'result_computed_at': 800, 'result_algo_version': kAlgoVersion},
      where: 'day_id = ?',
      whereArgs: ['2026-09-15'],
    );
    final ok = await repository.readNightScalarDetail(
      MetricKey.restingHr,
      '2026-09-15',
      7,
    );
    expect(ok.state, NightScalarState.current);
    expect(ok.value, 54);
  });

  test('validated window is chronological; inverted times stay empty', () async {
    final start = DateTime.utc(2026, 3, 28, 22, 10);
    final end = DateTime.utc(2026, 3, 29, 6, 54);
    await putNight(
      '2026-03-29',
      rmssd: 48,
      onsetMs: start.millisecondsSinceEpoch,
      offsetMs: end.millisecondsSinceEpoch,
    );
    final ok = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-03-29',
      7,
    );
    expect(ok.window!.start.isAtSameMomentAs(start), isTrue);
    expect(ok.window!.end.isAtSameMomentAs(end), isTrue);
    await putNight(
      '2026-03-29',
      rmssd: 48,
      onsetMs: end.millisecondsSinceEpoch,
      offsetMs: start.millisecondsSinceEpoch,
    );
    final inverted = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-03-29',
      7,
    );
    expect(inverted.window, isNull);
    expect(inverted.value, 48);
  });

  test('unknown source is left null, not defaulted', () async {
    await putNight('2026-09-15', rmssd: 48, imported: true);
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.sleepSource, isNull);
    expect(snap.vendorSource, isNull);
    expect(snap.deviceFamily, isNull);
    expect(snap.recordingTimezone, isNull);
    expect(snap.history.last.imported, isTrue);
    expect(snap.history.last.source, isNull);
  });

  test('duplicate JSON keys follow dart last-wins, not sqlite first-wins',
      () async {
    await putNight(
      '2026-09-15',
      rmssd: 48,
      payloadJson:
          '{"imported":false,"imported":true,'
          '"source":"first","source":"whoop_export",'
          '"sleep_source":"auto","sleep_source":"manual",'
          '"scalars":{"rmssd":48},'
          '"baselines":{"hrv":{"baseline":40,"n_valid":-1,"n_valid":3}}}',
    );
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.vendorSource, 'whoop_export');
    expect(snap.sleepSource, 'manual');
    expect(snap.baseline?.value, 40);
    expect(snap.baseline?.nValid, 3);
  });

  test('string true and negative baseline counts stay unknown', () async {
    await putNight(
      '2026-09-15',
      rmssd: 48,
      payloadJson: jsonEncode({
        'imported': 'true',
        'source': 'whoop_export',
        'scalars': {'rmssd': 48},
        'baselines': {
          'hrv': {'baseline': 40, 'n_valid': -2, 'nights_since_update': -1},
        },
      }),
    );
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.vendorSource, isNull);
    expect(snap.history.last.imported, isFalse);
    expect(snap.baseline?.value, 40);
    expect(snap.baseline?.nValid, isNull);
    expect(snap.baseline?.nightsSinceUpdate, isNull);
  });

  test('out-of-range computed_at is not a DateTime', () async {
    await putNight(
      '2026-09-15',
      rmssd: 48,
      computedAt: 8640000000000001,
    );
    final snap = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(snap.computedAt, isNull);
    expect(snap.value, 48);
  });

  test('readDay and history follow the typed overlay for HRV/RHR only',
      () async {
    await putCoveredNight('2026-09-14', rmssd: 40, rhr: 56, computedAt: 800);
    await putCoveredNight('2026-09-15', rmssd: 48, rhr: 54, computedAt: 900);
    await LocalDb.putMetricSeriesValue('2026-09-14', 'strain', 11);
    await LocalDb.putMetricSeriesValue('2026-09-15', 'strain', 12);

    Future<void> expectSameAsDetail(OpenBandDay day) async {
      final hrv = await repository.readNightScalarDetail(
        MetricKey.hrv,
        day.day,
        7,
      );
      expect(day.hrv.value, hrv.value);
      expect(day.hrv.nightScalar, hrv.state);
      if (hrv.withheld) {
        expect(day.hrv.baseline, isNull);
        expect(hrv.storedForInfo, isNotNull);
      }
    }

    final complete = await repository.readDay('2026-09-15');
    expect(complete.hrv.value, 48);
    expect(complete.hrv.nightScalar, NightScalarState.current);
    expect(complete.hrv.baseline, isNull);
    await expectSameAsDetail(complete);

    await putSleepJob('2026-09-15', status: 'pending');
    final pending = await repository.readDay('2026-09-15');
    expect(pending.hrv.value, isNull);
    expect(pending.hrv.baseline, isNull);
    expect(pending.hrv.readiness, MetricReadiness.processing);
    expect(pending.hrv.nightScalar, NightScalarState.pending);
    expect(pending.restingHr.value, isNull);
    expect(pending.hrv.readiness, MetricReadiness.processing);
    expect(pending.recovery.readiness, isNot(MetricReadiness.processing));
    await expectSameAsDetail(pending);
    final pendingHistory = await repository.readMetricHistory(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(pendingHistory.last.value, isNull);
    expect(pendingHistory[5].value, 40);
    final strain = await repository.readMetricHistory(
      MetricKey.strain,
      '2026-09-15',
      7,
    );
    expect(strain.last.value, 12);
    expect(strain[5].value, 11);
  });

  test('failed nap leaves no stale HRV number or baseline', () async {
    await putCoveredNight('2026-09-15', rmssd: 48, rhr: 54, computedAt: 900);
    await putNapJob('2026-09-15', status: 'failed');
    final failed = await repository.readDay('2026-09-15');
    expect(failed.hrv.value, isNull);
    expect(failed.hrv.baseline, isNull);
    expect(failed.hrv.nightScalar, NightScalarState.failed);
    expect(failed.hrv.readiness, isNot(MetricReadiness.unreliable));
    expect(failed.restingHr.value, isNull);
  });

  test('complete sleep without receipt is unknown on cards', () async {
    await putCoveredNight('2026-09-15', rmssd: 48, computedAt: 900);
    await putSleepJob('2026-09-15', status: 'complete');
    final unknown = await repository.readDay('2026-09-15');
    expect(unknown.hrv.value, isNull);
    expect(unknown.hrv.nightScalar, NightScalarState.unknown);
    expect(unknown.hrv.reason, kNightScalarOpenLabel);
  });

  test('outdated nap receipt withholds the selected night', () async {
    await putCoveredNight('2026-09-15', rmssd: 48, computedAt: 800);
    await putNapJob(
      '2026-09-15',
      status: 'complete',
      resultAlgo: kAlgoVersion,
      resultAt: 900,
    );
    final outdated = await repository.readDay('2026-09-15');
    expect(outdated.hrv.value, isNull);
    expect(outdated.hrv.nightScalar, NightScalarState.outdated);
  });

  test('older complete proof stays published without a card delta', () async {
    const old = kAlgoVersion - 4;
    await putCoveredNight(
      '2026-09-15',
      rmssd: 41,
      algo: old,
      computedAt: 900,
    );
    await putSleepJob(
      '2026-09-15',
      status: 'complete',
      resultAlgo: old,
      resultAt: 900,
    );
    final older = await repository.readDay('2026-09-15');
    expect(older.hrv.value, 41);
    expect(older.hrv.nightScalar, NightScalarState.older);
    expect(older.hrv.baseline, isNull);
    final detail = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(older.hrv.value, detail.value);
  });

  test('partial selected keeps the scalar and abstains card baseline', () async {
    await putNight('2026-09-15', rmssd: 48, partial: true);
    final partial = await repository.readDay('2026-09-15');
    expect(partial.hrv.value, 48);
    expect(partial.hrv.readiness, MetricReadiness.partial);
    expect(partial.hrv.baseline, isNull);
  });

  test('trusted baseline is the only card comparison; provisional stays in detail',
      () async {
    await putNight(
      '2026-09-15',
      rmssd: 48,
      computedAt: 900,
      baselineHrv: {
        'baseline': 40,
        'status': kNightScalarTrustedBaseline,
        'n_valid': 14,
      },
    );
    final trusted = await repository.readDay('2026-09-15');
    expect(trusted.hrv.value, 48);
    expect(trusted.hrv.baseline, 40);
    await putNight(
      '2026-09-15',
      rmssd: 48,
      computedAt: 900,
      baselineHrv: {
        'baseline': 40,
        'status': 'provisional',
        'n_valid': 4,
      },
    );
    final provisional = await repository.readDay('2026-09-15');
    expect(provisional.hrv.value, 48);
    expect(provisional.hrv.baseline, isNull);
    final stored = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(stored.baseline?.status, 'provisional');
    expect(stored.baseline?.value, 40);
    await putNight(
      '2026-09-15',
      rmssd: 48,
      computedAt: 900,
      baselineHrv: {
        'baseline': 40,
        'status': ' Trusted ',
        'n_valid': 14,
      },
    );
    final spaced = await repository.readDay('2026-09-15');
    expect(spaced.hrv.value, 48);
    expect(spaced.hrv.baseline, 40);
    final spacedDetail = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(spacedDetail.baseline?.status, kNightScalarTrustedBaseline);
  });

  test('unreadable history keeps the stored algo; other keys unchanged',
      () async {
    const old = 84;
    await putNight('2026-09-13', rmssd: 41, algo: old);
    await putNight('2026-09-14', rmssd: 99);
    await putNight(
      '2026-09-15',
      rmssd: 48,
      algo: old,
      payloadJson: '{not-json',
    );
    final history = await repository.readMetricHistory(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(history[4].value, 41);
    expect(history[5].value, isNull);
    expect(history.last.value, isNull);
  });

  test('card and detail use SQL rmssd/rhr when payload scalars disagree',
      () async {
    await putNight('2026-09-15', rmssd: 48, rhr: 54, computedAt: 900);
    final db = await LocalDb.instance;
    await db.update(
      'day_result',
      {
        'payload_json': jsonEncode({
          'scalars': {'rmssd': 99, 'rhr': 11},
        }),
      },
      where: 'day_id = ? AND algo_version = ?',
      whereArgs: ['2026-09-15', kAlgoVersion],
    );
    final envelope = await app.repo!.getDayHrv('2026-09-15');
    expect(envelope['rmssd'], 99);
    final heart = await app.repo!.getDayHeart('2026-09-15');
    expect(heart['resting_hr'], 11);
    final day = await repository.readDay('2026-09-15');
    expect(day.hrv.value, 48);
    expect(day.restingHr.value, 54);
    final hrv = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    final rhr = await repository.readNightScalarDetail(
      MetricKey.restingHr,
      '2026-09-15',
      7,
    );
    expect(day.hrv.value, hrv.value);
    expect(day.hrv.nightScalar, hrv.state);
    expect(day.restingHr.value, rhr.value);
    expect(day.restingHr.nightScalar, rhr.state);
    expect(hrv.value, 48);
    expect(rhr.value, 54);
  });

  test('null SQL rmssd/rhr does not borrow payload or legacy envelopes',
      () async {
    await putNight('2026-09-15', rmssd: 48, rhr: 54, computedAt: 900);
    final db = await LocalDb.instance;
    await db.update(
      'day_result',
      {'rmssd': null, 'rhr': null},
      where: 'day_id = ? AND algo_version = ?',
      whereArgs: ['2026-09-15', kAlgoVersion],
    );
    final envelope = await app.repo!.getDayHrv('2026-09-15');
    expect(envelope['rmssd'], 48);
    final heart = await app.repo!.getDayHeart('2026-09-15');
    expect(heart['resting_hr'], 54);
    final day = await repository.readDay('2026-09-15');
    expect(day.hrv.value, isNull);
    expect(day.restingHr.value, isNull);
    expect(day.hrv.nightScalar, NightScalarState.missing);
    expect(day.restingHr.nightScalar, NightScalarState.missing);
    final hrv = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(day.hrv.value, hrv.value);
    expect(day.hrv.nightScalar, hrv.state);
    expect(hrv.value, isNull);
  });

  test('corrupt payload throws from readDay; cards never see unreadable',
      () async {
    await putNight(
      '2026-09-15',
      rmssd: 48,
      rhr: 54,
      computedAt: 900,
      payloadJson: '{not-json',
    );
    await expectLater(
      repository.readDay('2026-09-15'),
      throwsA(isA<FormatException>()),
    );
    final detail = await repository.readNightScalarDetail(
      MetricKey.hrv,
      '2026-09-15',
      7,
    );
    expect(detail.state, NightScalarState.unreadable);
    expect(detail.value, isNull);
  });

  test('readDay banner and cards share the sleep-correction snapshot', () async {
    await putCoveredNight('2026-09-15', rmssd: 48, rhr: 54, computedAt: 900);
    await putSleepJob('2026-09-15', status: 'pending');
    final pending = await repository.readDay('2026-09-15');
    expect(pending.hrv.value, isNull);
    expect(pending.restingHr.value, isNull);
    expect(pending.hrv.nightScalar, NightScalarState.pending);
    expect(pending.restingHr.nightScalar, NightScalarState.pending);
    expect(pending.correction, isNotNull);
    expect(pending.correction!.id, 'draft-2026-09-15');
    expect(pending.correction!.day, '2026-09-15');
    expect(pending.correction!.revision, 1);
    expect(pending.correction!.state, CorrectionState.pending);
    expect(pending.correction!.automatic, isFalse);
    expect(pending.correction!.error, isNull);
    expect(pending.correction!.savedAt.millisecondsSinceEpoch, greaterThan(0));

    final db = await LocalDb.instance;
    await db.update(
      'openband_calculation_job',
      {'status': 'failed', 'error': 'staging timeout'},
      where: 'day_id = ?',
      whereArgs: ['2026-09-15'],
    );
    final failed = await repository.readDay('2026-09-15');
    expect(failed.hrv.nightScalar, NightScalarState.failed);
    expect(failed.restingHr.nightScalar, NightScalarState.failed);
    expect(failed.correction!.id, pending.correction!.id);
    expect(failed.correction!.state, CorrectionState.failed);
    expect(failed.correction!.error, 'staging timeout');

    await putCoveredNight('2026-09-14', rmssd: 40, rhr: 56, computedAt: 800);
    await LocalDb.restoreOpenBandAutomatic('2026-09-14');
    final restored = await repository.readDay('2026-09-14');
    expect(restored.correction, isNull);
    expect(restored.hrv.value, isNull);
    expect(restored.hrv.nightScalar, NightScalarState.pending);
  });

  test('recovery and strain keys are refused', () async {
    expect(
      () => repository.readNightScalarDetail(
        MetricKey.recovery,
        '2026-09-15',
        7,
      ),
      throwsArgumentError,
    );
  });
}
