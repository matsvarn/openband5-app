import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late LocalOpenBandRepository repository;

  const settings = CycleSettings(
    enabled: true,
    estimatesEnabled: true,
    lengthReviewEnabled: false,
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await LocalDb.close();
    LocalDb.dbName = 'openband_cycle_measurements_store_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/${LocalDb.dbName}');
    app = AppState.forTesting();
    repository = LocalOpenBandRepository(
      app,
      cycleSettingsRead: () async => settings,
    );
  });

  tearDown(() async {
    app.dispose();
    await LocalDb.close();
  });

  Future<void> seedStart(String date, {String kind = kCycleStartKind}) async {
    final db = await LocalDb.instance;
    await db.insert('cycle_log', {'date': date, 'kind': kind});
  }

  Future<void> seedPaperStarts() async {
    for (final date in [
      '2026-06-01',
      '2026-06-29',
      '2026-07-31',
      '2026-08-24',
    ]) {
      await seedStart(date);
    }
  }

  Future<void> seedNight(
    String day, {
    double? rhr,
    double? hrv,
    int algo = kAlgoVersion,
    bool skipped = false,
    bool partial = false,
    bool imported = false,
    String sleepSource = 'auto',
    int? onsetMs,
    int? offsetMs,
    double? rmssdScalar,
    String? payloadJson,
  }) {
    return LocalDb.putDayResult(
      dayId: day,
      algoVersion: algo,
      payloadJson: payloadJson ??
          jsonEncode(
            cycleNightSourcePayload(
              rhr: rhr,
              hrv: hrv,
              rmssdScalar: rmssdScalar,
              imported: imported,
              sleepSource: sleepSource,
              onsetMs: onsetMs ?? cycleNightOnsetMs(day),
              offsetMs: offsetMs ?? cycleNightOffsetMs(day),
            ),
          ),
      windowJson: '{}',
      skipped: skipped,
      partial: partial,
    );
  }

  Future<void> seedPaperNights() async {
    final days =
        cycleCivilDaysInclusive(kCyclePaperStartDay, kCyclePaperAsOfDay);
    for (var i = 0; i < days.length; i++) {
      final rhr = kCyclePaperRhr[i];
      final hrv = kCyclePaperHrv[i];
      if (rhr == null && hrv == null) continue;
      await seedNight(days[i], rhr: rhr, hrv: hrv);
    }
  }

  Future<void> putCorrection(
    String day, {
    required int revision,
    required String status,
    int? resultAlgo,
    int? resultAt,
    int? jobRevision,
    int? onsetMs,
    int? wakeMs,
  }) async {
    final onset = onsetMs ?? cycleNightOnsetMs(day);
    final wake = wakeMs ?? cycleNightOffsetMs(day);
    await LocalDb.putOpenBandSleepDraft(
      dayId: day,
      draftId: 'corr-$day',
      onsetMs: onset,
      wakeMs: wake,
    );
    final saved = await LocalDb.commitOpenBandSleepCorrection(
      dayId: day,
      draftId: 'corr-$day',
      onsetMs: onset,
      wakeMs: wake,
    );
    if (revision != 1) {
      final db = await LocalDb.instance;
      await db.update(
        'openband_sleep_correction',
        {'revision': revision},
        where: 'day_id = ?',
        whereArgs: [day],
      );
    }
    await LocalDb.updateOpenBandCalculationJob(
      dayId: day,
      correctionId: saved['correction_id'] as String,
      revision: jobRevision ?? revision,
      status: status,
      resultAlgoVersion: resultAlgo,
      resultComputedAt: resultAt,
      fromStatuses: {'pending'},
    );
  }

  Future<void> setComputedAt(String day, int ms) async {
    final db = await LocalDb.instance;
    await db.update(
      'day_result',
      {'computed_at': ms},
      where: 'day_id = ? AND algo_version = ?',
      whereArgs: [day, kAlgoVersion],
    );
  }

  test('Paper arrays survive exact v90 SQLite rows', () async {
    await seedPaperStarts();
    await seedPaperNights();
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.reason, CycleMeasurementsReason.available);
    expect(snap.nights, hasLength(23));
    expect(snap.rhrAvailableCount, 19);
    expect(snap.hrvAvailableCount, 16);
    expect(snap.latestRhr, const CycleMetricLatest(day: '2026-09-15', value: 54));
    expect(snap.latestHrv, const CycleMetricLatest(day: '2026-09-14', value: 48));
    expect([for (final n in snap.nights) n.rhr?.value], kCyclePaperRhr);
    expect([for (final n in snap.nights) n.hrv?.value], kCyclePaperHrv);
  });

  test('older and newer algo rows are ignored; only exact 90 is read', () async {
    await seedStart('2026-08-24');
    await seedNight('2026-09-14', rhr: 40, hrv: 10, algo: kAlgoVersion - 1);
    await seedNight('2026-09-14', rhr: 54, hrv: 48);
    await seedNight('2026-09-15', rhr: 99, hrv: 99, algo: kAlgoVersion + 1);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.latestRhr, const CycleMetricLatest(day: '2026-09-14', value: 54));
    expect(snap.latestHrv, const CycleMetricLatest(day: '2026-09-14', value: 48));
    expect(snap.nights.last.rhr, isNull);
    expect(snap.nights.last.hrv, isNull);
  });

  test('skipped, partial, imported and corrupt rows are excluded independently',
      () async {
    await seedStart('2026-08-24');
    await seedNight('2026-09-12', rhr: 51, skipped: true);
    await seedNight('2026-09-13', rhr: 52, partial: true);
    await seedNight('2026-09-14', rhr: 53, imported: true);
    await seedNight('2026-09-15', payloadJson: '{');
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.nights[19].day, '2026-09-12');
    expect(snap.nights[19].rhr, isNull);
    expect(snap.nights[20].rhr, isNull);
    expect(snap.nights[21].rhr, isNull);
    expect(snap.nights[22].rhr, isNull);
    expect(snap.excludedCount, 3);
    expect(snap.unreadableCount, 1);
    expect(snap.partial, isTrue);
    expect(snap.reason, CycleMeasurementsReason.metricUnavailable);
  });

  test('none, rejected and unknown sleep_source stay unavailable', () async {
    await seedStart('2026-08-24');
    await seedNight('2026-09-13', rhr: 50, sleepSource: 'none');
    await seedNight('2026-09-14', rhr: 51, sleepSource: 'rejected');
    await seedNight('2026-09-15', rhr: 52, sleepSource: 'guess');
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.rhrAvailableCount, 0);
    expect(snap.excludedCount, 3);
  });

  test('auto, auto_fallback, manual and confirmed nights are eligible', () async {
    await seedStart('2026-08-24');
    await seedNight('2026-09-12', rhr: 50, sleepSource: 'auto');
    await seedNight('2026-09-13', rhr: 51, sleepSource: 'auto_fallback');
    await seedNight('2026-09-14', rhr: 52, sleepSource: 'manual');
    await seedNight('2026-09-15', rhr: 53, sleepSource: 'confirmed');
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.rhrAvailableCount, 4);
    expect(snap.excludedCount, 0);
  });

  test('pending, failed and mismatched correction jobs refuse the night',
      () async {
    await seedStart('2026-08-24');
    await seedNight('2026-09-12', rhr: 50);
    await seedNight('2026-09-13', rhr: 51);
    await seedNight('2026-09-14', rhr: 52);
    await seedNight('2026-09-15', rhr: 53);
    await putCorrection('2026-09-12', revision: 1, status: 'pending');
    await putCorrection('2026-09-13', revision: 1, status: 'failed');
    await putCorrection(
      '2026-09-14',
      revision: 2,
      status: 'complete',
      resultAlgo: kAlgoVersion,
      resultAt: 1,
      jobRevision: 1,
    );
    await putCorrection(
      '2026-09-15',
      revision: 1,
      status: 'complete',
      resultAlgo: kAlgoVersion - 1,
      resultAt: 1,
    );
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.rhrAvailableCount, 0);
    expect(snap.excludedCount, 4);
  });

  test('complete job matching revision and version keeps the night', () async {
    await seedStart('2026-08-24');
    await seedNight('2026-09-15', rhr: 54, hrv: 48, sleepSource: 'manual');
    const receipt = 1800000000000;
    await putCorrection(
      '2026-09-15',
      revision: 1,
      status: 'complete',
      resultAlgo: kAlgoVersion,
      resultAt: receipt,
    );
    await setComputedAt('2026-09-15', receipt);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.latestRhr?.value, 54);
    expect(snap.latestHrv?.value, 48);
    expect(snap.excludedCount, 0);
  });

  test('stale day_result older than a completed receipt is withheld', () async {
    await seedStart('2026-08-24');
    await seedNight('2026-09-15', rhr: 54, hrv: 48, sleepSource: 'manual');
    const receipt = 1800000000000;
    await putCorrection(
      '2026-09-15',
      revision: 1,
      status: 'complete',
      resultAlgo: kAlgoVersion,
      resultAt: receipt,
    );
    await setComputedAt('2026-09-15', receipt - 1);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.nights.last.rhr, isNull);
    expect(snap.nights.last.hrv, isNull);
    expect(snap.excludedCount, 1);
    expect(snap.reason, CycleMeasurementsReason.metricUnavailable);
  });

  test('newer valid day_result after a completed receipt is kept', () async {
    await seedStart('2026-08-24');
    await seedNight('2026-09-15', rhr: 54, hrv: 48, sleepSource: 'manual');
    const receipt = 1800000000000;
    await putCorrection(
      '2026-09-15',
      revision: 1,
      status: 'complete',
      resultAlgo: kAlgoVersion,
      resultAt: receipt,
    );
    await setComputedAt('2026-09-15', receipt + 1);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.latestRhr?.value, 54);
    expect(snap.latestHrv?.value, 48);
    expect(snap.excludedCount, 0);
  });

  test('complete automatic job still serves a newer valid result', () async {
    await seedStart('2026-08-24');
    await seedNight('2026-09-15', rhr: 54, hrv: 48);
    const receipt = 1800000000000;
    final restored = await LocalDb.restoreOpenBandAutomatic('2026-09-15');
    await LocalDb.updateOpenBandCalculationJob(
      dayId: '2026-09-15',
      correctionId: restored['correction_id'] as String,
      revision: (restored['revision'] as num).toInt(),
      status: 'complete',
      resultAlgoVersion: kAlgoVersion,
      resultComputedAt: receipt,
      fromStatuses: {'pending'},
    );
    await setComputedAt('2026-09-15', receipt + 1);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.latestRhr?.value, 54);
    expect(snap.latestHrv?.value, 48);
    expect(snap.excludedCount, 0);
    expect(snap.unreadableCount, 0);
  });

  test('unknown complete correction action cannot serve', () async {
    await seedStart('2026-08-24');
    await seedNight('2026-09-15', rhr: 54, hrv: 48);
    const receipt = 1800000000000;
    await putCorrection(
      '2026-09-15',
      revision: 1,
      status: 'complete',
      resultAlgo: kAlgoVersion,
      resultAt: receipt,
    );
    final db = await LocalDb.instance;
    await db.update(
      'openband_sleep_correction',
      {'action': 'repair'},
      where: 'day_id = ?',
      whereArgs: ['2026-09-15'],
    );
    await setComputedAt('2026-09-15', receipt);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.nights.last.rhr, isNull);
    expect(snap.nights.last.hrv, isNull);
    expect(snap.unreadableCount, 1);
    expect(snap.reason, CycleMeasurementsReason.metricUnavailable);
  });

  test('complete override with mismatched bounds withholds the night', () async {
    await seedStart('2026-08-24');
    await seedNight('2026-09-15', rhr: 54, hrv: 48, sleepSource: 'manual');
    const receipt = 1800000000000;
    await putCorrection(
      '2026-09-15',
      revision: 1,
      status: 'complete',
      resultAlgo: kAlgoVersion,
      resultAt: receipt,
      onsetMs: cycleNightOnsetMs('2026-09-15') + 3600000,
      wakeMs: cycleNightOffsetMs('2026-09-15') + 3600000,
    );
    await setComputedAt('2026-09-15', receipt + 1);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.nights.last.rhr, isNull);
    expect(snap.excludedCount, 1);
  });

  test('literal stored payload keeps session HRV, fractional RHR and bounds',
      () async {
    await seedStart('2026-08-24');
    await LocalDb.putDayResult(
      dayId: '2026-09-15',
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode(_kLiteralStoredNightPayload),
      windowJson: '{}',
    );
    final snap = await repository.readCycleMeasurements('2026-09-15');
    final night = snap.nights.last;
    expect(night.rhr?.value, 62.996665);
    expect(night.rhr?.confidence, 0.95);
    expect(
      night.rhr?.note,
      'lowest-30-min mean + 1st-percentile; HR=0 excluded as off-skin',
    );
    expect(night.rhr?.tier, 'HIGH');
    expect(night.rhr?.inputsUsed, ['hr_1hz']);
    expect(night.hrv?.value, 19.9);
    expect(night.hrv?.confidence, 0.3);
    expect(
      night.hrv?.note,
      'sleep-session HRV: mean RMSSD over cleaned 5-min windows.',
    );
    expect(night.hrv?.tier, 'HIGH');
    expect(night.hrv?.inputsUsed, ['rr_sleep_window']);
    expect(
      night.windowStart,
      DateTime.fromMillisecondsSinceEpoch(1577923200000, isUtc: true),
    );
    expect(
      night.windowEnd,
      DateTime.fromMillisecondsSinceEpoch(1577951999000, isUtc: true),
    );
  });

  test('malformed session HRV keeps valid RHR, window and source', () async {
    await seedStart('2026-08-24');
    final payload = _literalClone();
    _putHrv(payload, 'bad');
    await seedLiteral('2026-09-15', payload);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    final night = snap.nights.last;
    expect(night.rhr?.value, 62.996665);
    expect(night.hrv, isNull);
    expect(night.hrvUnreadable, isTrue);
    expect(night.rhrUnreadable, isFalse);
    expect(night.sleepSource, 'auto');
    expect(
      night.windowStart,
      DateTime.fromMillisecondsSinceEpoch(1577923200000, isUtc: true),
    );
    expect(snap.unreadableCount, 1);
    expect(snap.partial, isTrue);
    expect(snap.rhrAvailableCount, 1);
    expect(snap.hrvAvailableCount, 0);
    expect(snap.reason, CycleMeasurementsReason.available);
  });

  test('malformed RHR map keeps valid session HRV', () async {
    await seedStart('2026-08-24');
    final payload = _literalClone();
    _putRhr(payload, {'p1_bpm': 54.0, 'valid_samples': 100});
    await seedLiteral('2026-09-15', payload);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    final night = snap.nights.last;
    expect(night.rhr, isNull);
    expect(night.rhrUnreadable, isTrue);
    expect(night.hrv?.value, 19.9);
    expect(night.hrvUnreadable, isFalse);
    expect(night.sleepSource, 'auto');
    expect(snap.unreadableCount, 1);
    expect(snap.partial, isTrue);
    expect(snap.rhrAvailableCount, 0);
    expect(snap.hrvAvailableCount, 1);
  });

  test('known absence is not nested unreadable', () async {
    await seedStart('2026-08-24');
    final dash = _literalClone();
    _putRhr(dash, '—');
    _putHrv(dash, '—');
    await seedLiteral('2026-09-13', dash);
    final envelopeNull = _literalClone();
    final nullClinical =
        Map<String, dynamic>.from(envelopeNull['clinical'] as Map);
    nullClinical['resting_hr'] = null;
    envelopeNull['clinical'] = nullClinical;
    await seedLiteral('2026-09-14', envelopeNull);
    final missing = _literalClone();
    final clinical = Map<String, dynamic>.from(missing['clinical'] as Map);
    clinical.remove('resting_hr');
    clinical['rmssd_sleep_session'] = {
      'value': null,
      'confidence': 0.0,
      'tier': 'HIGH',
      'inputs_used': ['rr_sleep_window'],
    };
    missing['clinical'] = clinical;
    await seedLiteral('2026-09-15', missing);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.nights[20].rhr, isNull);
    expect(snap.nights[20].hrv, isNull);
    expect(snap.nights[20].rhrUnreadable, isFalse);
    expect(snap.nights[21].rhr, isNull);
    expect(snap.nights[21].rhrUnreadable, isFalse);
    expect(snap.nights[21].hrv?.value, 19.9);
    expect(snap.nights.last.rhr, isNull);
    expect(snap.nights.last.hrv, isNull);
    expect(snap.nights.last.rhrUnreadable, isFalse);
    expect(snap.nights.last.hrvUnreadable, isFalse);
    expect(snap.nights.last.windowStart, isNotNull);
    expect(snap.unreadableCount, 0);
    expect(snap.partial, isFalse);
    expect(snap.reason, CycleMeasurementsReason.available);
  });

  test('present non-map clinical envelopes are unreadable, not absent',
      () async {
    await seedStart('2026-08-24');
    final badHrv = _literalClone();
    final c1 = Map<String, dynamic>.from(badHrv['clinical'] as Map);
    c1['rmssd_sleep_session'] = 'bad';
    badHrv['clinical'] = c1;
    await seedLiteral('2026-09-12', badHrv);

    final listRhr = _literalClone();
    final c2 = Map<String, dynamic>.from(listRhr['clinical'] as Map);
    c2['resting_hr'] = [];
    listRhr['clinical'] = c2;
    await seedLiteral('2026-09-13', listRhr);

    final missingValue = _literalClone();
    final c3 = Map<String, dynamic>.from(missingValue['clinical'] as Map);
    c3['resting_hr'] = {
      'confidence': 0.95,
      'tier': 'HIGH',
      'inputs_used': ['hr_1hz'],
    };
    missingValue['clinical'] = c3;
    await seedLiteral('2026-09-14', missingValue);

    final badClinical = _literalClone();
    badClinical['clinical'] = [];
    await seedLiteral('2026-09-15', badClinical);

    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.nights[19].rhr?.value, 62.996665);
    expect(snap.nights[19].hrv, isNull);
    expect(snap.nights[19].hrvUnreadable, isTrue);
    expect(snap.nights[20].rhr, isNull);
    expect(snap.nights[20].rhrUnreadable, isTrue);
    expect(snap.nights[20].hrv?.value, 19.9);
    expect(snap.nights[21].rhr, isNull);
    expect(snap.nights[21].rhrUnreadable, isTrue);
    expect(snap.nights[21].hrv?.value, 19.9);
    expect(snap.nights.last.rhr, isNull);
    expect(snap.nights.last.hrv, isNull);
    expect(snap.nights.last.rhrUnreadable, isTrue);
    expect(snap.nights.last.hrvUnreadable, isTrue);
    expect(snap.nights.last.windowStart, isNotNull);
    expect(snap.unreadableCount, 4);
    expect(snap.partial, isTrue);
  });

  test('nonfinite nested values are unreadable without dropping the sibling',
      () async {
    await seedStart('2026-08-24');
    await LocalDb.putDayResult(
      dayId: '2026-09-14',
      algoVersion: kAlgoVersion,
      payloadJson:
          '{"sleep_source":"auto","sleep":{"window":{"value":{"onset_ms":1577923200000.0,"offset_ms":1577951999000.0}}},"clinical":{"resting_hr":{"value":{"low30_mean_bpm":1e309},"confidence":0.95,"tier":"HIGH","inputs_used":["hr_1hz"]},"rmssd_sleep_session":{"value":19.9,"confidence":0.3,"tier":"HIGH","inputs_used":["rr_sleep_window"]}}}',
      windowJson: '{}',
    );
    final infHrv = _literalClone();
    _putHrv(infHrv, 'Infinity');
    await seedLiteral('2026-09-15', infHrv);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.nights[21].rhr, isNull);
    expect(snap.nights[21].rhrUnreadable, isTrue);
    expect(snap.nights[21].hrv?.value, 19.9);
    expect(snap.nights.last.hrv, isNull);
    expect(snap.nights.last.hrvUnreadable, isTrue);
    expect(snap.nights.last.rhr?.value, 62.996665);
    expect(snap.unreadableCount, 2);
    expect(snap.partial, isTrue);
  });

  test('malformed confidence stays unknown without discarding the value',
      () async {
    await seedStart('2026-08-24');
    final high = _literalClone();
    _putRhr(high, {'low30_mean_bpm': 54.0}, confidence: 2);
    _putHrv(high, 19.9, confidence: -0.1);
    await seedLiteral('2026-09-15', high);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    final night = snap.nights.last;
    expect(night.rhr?.value, 54);
    expect(night.rhr?.confidence, isNull);
    expect(night.rhr?.confidenceUnreadable, isTrue);
    expect(night.hrv?.value, 19.9);
    expect(night.hrv?.confidence, isNull);
    expect(night.hrv?.confidenceUnreadable, isTrue);
    expect(night.rhrUnreadable, isFalse);
    expect(night.hrvUnreadable, isFalse);
    expect(snap.unreadableCount, 1);
    expect(snap.partial, isTrue);
    expect(snap.reason, CycleMeasurementsReason.available);
  });

  test('invalid window and missing session envelope keep HRV unavailable',
      () async {
    await seedStart('2026-08-24');
    await seedNight(
      '2026-09-14',
      rhr: 54,
      hrv: 48,
      onsetMs: cycleNightOffsetMs('2026-09-14'),
      offsetMs: cycleNightOnsetMs('2026-09-14'),
    );
    await seedNight('2026-09-15', rhr: 54, rmssdScalar: 48);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.nights[21].rhr, isNull);
    expect(snap.nights[21].hrv, isNull);
    expect(snap.nights.last.rhr?.value, 54);
    expect(snap.nights.last.hrv, isNull);
  });

  test('latest dates stay independent across dense missing slots', () async {
    await seedStart('2026-08-24');
    await seedNight('2026-09-13', rhr: 51);
    await seedNight('2026-09-14', hrv: 48);
    await seedNight('2026-09-15', rhr: 54);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.latestRhr, const CycleMetricLatest(day: '2026-09-15', value: 54));
    expect(snap.latestHrv, const CycleMetricLatest(day: '2026-09-14', value: 48));
    expect(snap.nights[21].rhr, isNull);
    expect(snap.nights.last.hrv, isNull);
  });

  test('RHR <= 0 is corrupt in SQLite while HRV 0 stays valid', () async {
    await seedStart('2026-08-24');
    final zeroNight = _literalClone();
    _putRhr(zeroNight, {'low30_mean_bpm': 0});
    _putHrv(zeroNight, 0);
    await seedLiteral('2026-09-14', zeroNight);
    final negHrv = _literalClone();
    _putHrv(negHrv, -1);
    await seedLiteral('2026-09-15', negHrv);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    final fourteen = snap.nights[21];
    expect(fourteen.rhr, isNull);
    expect(fourteen.rhrUnreadable, isTrue);
    expect(fourteen.hrv?.value, 0);
    expect(fourteen.hrvUnreadable, isFalse);
    expect(snap.nights.last.rhr?.value, 62.996665);
    expect(snap.nights.last.hrv, isNull);
    expect(snap.nights.last.hrvUnreadable, isTrue);
    expect(snap.unreadableCount, 2);
    expect(snap.partial, isTrue);
  });

  test('as-of ignores later rows and later corruption', () async {
    await seedStart('2026-08-24');
    await seedNight('2026-09-15', rhr: 54);
    await seedStart('2026-09-20');
    await seedNight('2026-09-20', payloadJson: '{');
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(snap.selected?.endDay, '2026-09-15');
    expect(snap.unreadableCount, 0);
    expect(snap.latestRhr?.value, 54);
  });

  test('previous selection uses the day before the next stored start', () async {
    await seedPaperStarts();
    final snap = await repository.readCycleMeasurements(
      '2026-09-15',
      cycleStartDay: '2026-06-29',
    );
    expect(snap.selected?.startDay, '2026-06-29');
    expect(snap.selected?.endDay, '2026-07-30');
    expect(snap.nights.first.day, '2026-06-29');
    expect(snap.nights.last.day, '2026-07-30');
  });

  test('removed selected start does not silently choose another', () async {
    await seedPaperStarts();
    final db = await LocalDb.instance;
    await db.delete('cycle_log', where: 'date = ?', whereArgs: ['2026-08-24']);
    final snap = await repository.readCycleMeasurements(
      '2026-09-15',
      cycleStartDay: '2026-08-24',
    );
    expect(snap.reason, CycleMeasurementsReason.selectedStartMissing);
    expect(snap.selected, isNull);
    expect(snap.selectedStartDay, '2026-08-24');
    expect(snap.nights, isEmpty);
    expect(snap.latestRhr, isNull);
    expect(snap.periods.map((p) => p.startDay), [
      '2026-06-01',
      '2026-06-29',
      '2026-07-31',
    ]);
    expect(snap.periods.last.endDay, '2026-09-15');
    expect(snap.periods.last.open, isTrue);
  });

  test('DST civil windows stay consecutive labels', () async {
    await seedStart('2026-03-07');
    final snap = await repository.readCycleMeasurements('2026-03-10');
    expect(
      [for (final n in snap.nights) n.day],
      ['2026-03-07', '2026-03-08', '2026-03-09', '2026-03-10'],
    );
    expect(snap.nights.map((n) => n.cycleDay), [1, 2, 3, 4]);
  });

  test('120-day SQL window preserves cycle-day offset', () async {
    const start = '2026-04-19';
    const asOf = '2026-09-15';
    final visible = cycleAddDays(asOf, -(kCycleMeasurementMaxNights - 1));
    await seedStart(start);
    await seedNight(start, rhr: 40);
    await seedNight(visible, rhr: 41);
    final snap = await repository.readCycleMeasurements(asOf);
    expect(snap.truncated, isTrue);
    expect(snap.nights, hasLength(120));
    expect(snap.firstCycleDay, 31);
    expect(snap.nights.first.cycleDay, 31);
    expect(snap.nights.first.rhr?.value, 41);
    expect(snap.nights.any((n) => n.day == start), isFalse);
  });

  test('database failure is not rewritten as an empty snapshot', () async {
    await seedStart('2026-08-24');
    final db = await LocalDb.instance;
    await db.execute('DROP TABLE cycle_log');
    await expectLater(
      repository.readCycleMeasurements('2026-09-15'),
      throwsA(anything),
    );
  });

  CycleMeasurementsSnapshot expectedAsOf({
    required List<CycleNightMeasurement> nights,
    CycleMetricLatest? latestRhr,
    CycleMetricLatest? latestHrv,
    int excludedCount = 0,
    int unreadableCount = 0,
  }) {
    final hasMetric = latestRhr != null || latestHrv != null;
    return CycleMeasurementsSnapshot(
      asOfDay: '2026-09-15',
      settings: settings,
      reason: hasMetric
          ? CycleMeasurementsReason.available
          : CycleMeasurementsReason.metricUnavailable,
      selectedStartDay: '2026-08-24',
      selected: _kOpenPeriod,
      periods: const [_kOpenPeriod],
      nights: nights,
      latestRhr: latestRhr,
      latestHrv: latestHrv,
      excludedCount: excludedCount,
      unreadableCount: unreadableCount,
      partial: excludedCount > 0 || unreadableCount > 0,
    );
  }

  List<CycleNightMeasurement> openNights({
    CycleNightMeasurement Function(String day, int cycleDay)? at,
  }) {
    final days =
        cycleCivilDaysInclusive('2026-08-24', '2026-09-15');
    return [
      for (var i = 0; i < days.length; i++)
        at?.call(days[i], i + 1) ??
            CycleNightMeasurement(day: days[i], cycleDay: i + 1),
    ];
  }

  test('large unused series matches the slim payload snapshot', () async {
    await seedStart('2026-08-24');
    const samples = 20000;
    final fat = _literalClone();
    fat['series'] = {
      'hr_curve': {
        't0': 0,
        'dt': 60,
        'v': List<int>.filled(samples, 60),
      },
    };
    fat['activity_curve'] = {
      't0': 0,
      'dt': 60,
      'v': List<int>.filled(samples, 1),
    };
    await seedLiteral('2026-09-15', fat);
    final fatSnap = await repository.readCycleMeasurements('2026-09-15');
    await seedLiteral('2026-09-15', _literalClone());
    final slimSnap = await repository.readCycleMeasurements('2026-09-15');
    expect(fatSnap, slimSnap);
    expect(
      fatSnap,
      expectedAsOf(
        nights: openNights(
          at: (day, cycleDay) => day == '2026-09-15'
              ? _literalEligibleNight(day, cycleDay)
              : CycleNightMeasurement(day: day, cycleDay: cycleDay),
        ),
        latestRhr: const CycleMetricLatest(day: '2026-09-15', value: 62.996665),
        latestHrv: const CycleMetricLatest(day: '2026-09-15', value: 19.9),
      ),
    );
  });

  test('malformed and non-object payloads stay unreadable', () async {
    await seedStart('2026-08-24');
    await seedNight('2026-09-12', payloadJson: '{');
    await seedNight('2026-09-13', payloadJson: '[]');
    await seedNight('2026-09-14', payloadJson: '"nope"');
    await seedNight('2026-09-15', payloadJson: 'null');
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(
      snap,
      expectedAsOf(
        nights: openNights(),
        unreadableCount: 4,
      ),
    );
  });

  test('imported true is refused; 1 and string true stay eligible', () async {
    await seedStart('2026-08-24');
    final importedTrue = _literalClone();
    importedTrue['imported'] = true;
    await seedLiteral('2026-09-12', importedTrue);
    final importedOne = _literalClone();
    importedOne['imported'] = 1;
    await seedLiteral('2026-09-13', importedOne);
    final importedString = _literalClone();
    importedString['imported'] = 'true';
    await seedLiteral('2026-09-14', importedString);
    await seedLiteral('2026-09-15', _literalClone());
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(
      snap,
      expectedAsOf(
        nights: openNights(
          at: (day, cycleDay) {
            if (day == '2026-09-12') {
              return CycleNightMeasurement(day: day, cycleDay: cycleDay);
            }
            if (day == '2026-09-13' ||
                day == '2026-09-14' ||
                day == '2026-09-15') {
              return _literalEligibleNight(day, cycleDay);
            }
            return CycleNightMeasurement(day: day, cycleDay: cycleDay);
          },
        ),
        latestRhr: const CycleMetricLatest(day: '2026-09-15', value: 62.996665),
        latestHrv: const CycleMetricLatest(day: '2026-09-15', value: 19.9),
        excludedCount: 1,
      ),
    );
  });

  test('duplicate relevant keys keep the last Dart object', () async {
    await seedStart('2026-08-24');
    final last = jsonEncode({
      'imported': false,
      ..._kLiteralStoredNightPayload,
    });
    const first = '{"imported":true,"sleep_source":"none","sleep":{"window":'
        '{"value":{"onset_ms":1,"offset_ms":2}}},"clinical":[]}';
    final duplicated =
        '${first.substring(0, first.length - 1)},${last.substring(1)}';
    await seedNight('2026-09-15', payloadJson: duplicated);
    final snap = await repository.readCycleMeasurements('2026-09-15');
    expect(
      snap,
      expectedAsOf(
        nights: openNights(
          at: (day, cycleDay) => day == '2026-09-15'
              ? _literalEligibleNight(day, cycleDay)
              : CycleNightMeasurement(day: day, cycleDay: cycleDay),
        ),
        latestRhr: const CycleMetricLatest(day: '2026-09-15', value: 62.996665),
        latestHrv: const CycleMetricLatest(day: '2026-09-15', value: 19.9),
      ),
    );
  });
}

const _kOpenPeriod = CycleMeasurementPeriod(
  startDay: '2026-08-24',
  endDay: '2026-09-15',
  open: true,
);

CycleNightMeasurement _literalEligibleNight(String day, int cycleDay) {
  return CycleNightMeasurement(
    day: day,
    cycleDay: cycleDay,
    windowStart: DateTime.fromMillisecondsSinceEpoch(1577923200000, isUtc: true),
    windowEnd: DateTime.fromMillisecondsSinceEpoch(1577951999000, isUtc: true),
    rhr: const CycleNightMetric(
      value: 62.996665,
      confidence: 0.95,
      note: 'lowest-30-min mean + 1st-percentile; HR=0 excluded as off-skin',
      tier: 'HIGH',
      inputsUsed: ['hr_1hz'],
    ),
    hrv: const CycleNightMetric(
      value: 19.9,
      confidence: 0.3,
      note: 'sleep-session HRV: mean RMSSD over cleaned 5-min windows.',
      tier: 'HIGH',
      inputsUsed: ['rr_sleep_window'],
    ),
    algoVersion: kAlgoVersion,
    sleepSource: 'auto',
  );
}

/// Independent of [cycleNightSourcePayload]. Canonical v90 clinical envelopes,
/// float epoch bounds, and a scalar RMSSD fallback that must stay unused.
const _kLiteralStoredNightPayload = {
  'sleep_source': 'auto',
  'sleep': {
    'window': {
      'value': {
        'onset_ms': 1577923200000.0,
        'offset_ms': 1577951999000.0,
        'spt_sec': 28799,
      },
    },
  },
  'clinical': {
    'resting_hr': {
      'value': {
        'low30_mean_bpm': 62.996665,
        'p1_bpm': 60.0,
        'valid_samples': 21597,
      },
      'confidence': 0.95,
      'tier': 'HIGH',
      'inputs_used': ['hr_1hz'],
      'note': 'lowest-30-min mean + 1st-percentile; HR=0 excluded as off-skin',
    },
    'rmssd_sleep_session': {
      'value': 19.9,
      'confidence': 0.3,
      'tier': 'HIGH',
      'inputs_used': ['rr_sleep_window'],
      'note': 'sleep-session HRV: mean RMSSD over cleaned 5-min windows.',
    },
  },
  'scalars': {'rmssd': 48.0},
};

Map<String, dynamic> _literalClone() =>
    jsonDecode(jsonEncode(_kLiteralStoredNightPayload)) as Map<String, dynamic>;

void _putRhr(
  Map<String, dynamic> payload,
  Object? value, {
  Object? confidence = 0.95,
}) {
  final clinical = Map<String, dynamic>.from(payload['clinical'] as Map);
  clinical['resting_hr'] = {
    'value': value,
    'confidence': confidence,
    'tier': 'HIGH',
    'inputs_used': ['hr_1hz'],
  };
  payload['clinical'] = clinical;
}

void _putHrv(
  Map<String, dynamic> payload,
  Object? value, {
  Object? confidence = 0.3,
}) {
  final clinical = Map<String, dynamic>.from(payload['clinical'] as Map);
  clinical['rmssd_sleep_session'] = {
    'value': value,
    'confidence': confidence,
    'tier': 'HIGH',
    'inputs_used': ['rr_sleep_window'],
  };
  payload['clinical'] = clinical;
}

Future<void> seedLiteral(String day, Map<String, dynamic> payload) {
  return LocalDb.putDayResult(
    dayId: day,
    algoVersion: kAlgoVersion,
    payloadJson: jsonEncode(payload),
    windowJson: '{}',
  );
}
