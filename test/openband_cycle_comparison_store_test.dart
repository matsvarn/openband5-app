import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

typedef _SetenvNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _SetenvDart = int Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _UnsetenvNative = Int32 Function(Pointer<Utf8>);
typedef _UnsetenvDart = int Function(Pointer<Utf8>);
typedef _TzsetNative = Void Function();
typedef _TzsetDart = void Function();

void _setProcessTz(String? tz) {
  final lib = DynamicLibrary.process();
  final key = 'TZ'.toNativeUtf8();
  try {
    if (tz == null) {
      lib.lookupFunction<_UnsetenvNative, _UnsetenvDart>('unsetenv')(key);
    } else {
      final value = tz.toNativeUtf8();
      lib.lookupFunction<_SetenvNative, _SetenvDart>('setenv')(key, value, 1);
      calloc.free(value);
    }
    lib.lookupFunction<_TzsetNative, _TzsetDart>('tzset')();
  } finally {
    calloc.free(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalOpenBandRepository.readCycleComparison', () {
    late AppState app;
    late LocalOpenBandRepository repository;

    const settings = CycleSettings(
      enabled: true,
      estimatesEnabled: true,
      lengthReviewEnabled: false,
    );
    final now = DateTime(2026, 9, 15, 12);

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      await LocalDb.close();
      LocalDb.dbName = 'openband_cycle_comparison_store_test.db';
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

    Future<void> clearNights() async {
      final db = await LocalDb.instance;
      await db.delete('day_result');
    }

    Future<void> seedPaperNightsFrom(
      String start, {
      num rhrAdd = 0,
      num hrvAdd = 0,
    }) async {
      final last = cycleAddDays(start, kCyclePaperRhr.length - 1);
      final days = cycleCivilDaysInclusive(start, last);
      for (var i = 0; i < days.length; i++) {
        final rhrRaw = kCyclePaperRhr[i];
        final hrvRaw = kCyclePaperHrv[i];
        final rhr = rhrRaw == null ? null : rhrRaw + rhrAdd;
        final hrv = hrvRaw == null ? null : hrvRaw + hrvAdd;
        if (rhr == null && hrv == null) continue;
        await seedNight(days[i], rhr: rhr, hrv: hrv);
      }
    }

    Future<void> seedPaperComparisonFixture() async {
      const starts = ['2026-05-28', '2026-06-29', '2026-07-31', '2026-08-24'];
      for (var i = 0; i < starts.length; i++) {
        await seedStart(starts[i]);
        final last = i == starts.length - 1;
        await seedPaperNightsFrom(
          starts[i],
          rhrAdd: last ? 2 : 0,
          hrvAdd: last ? 3 : 0,
        );
      }
      const rhr = [50.0, 52.0, 54.0];
      const hrv = [45.0, 47.0, 49.0];
      for (var i = 0; i < 3; i++) {
        final start = starts[i];
        await seedNight(
          cycleAddDays(start, 22),
          rhr: rhr[i],
          hrv: kCyclePaperHrv[22],
        );
        await seedNight(
          cycleAddDays(start, 21),
          rhr: kCyclePaperRhr[21],
          hrv: hrv[i],
        );
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

    Future<void> seedLiteral(String day, Map<String, dynamic> payload) {
      return LocalDb.putDayResult(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode(payload),
        windowJson: '{}',
      );
    }

    test('Paper fixture latest RHR/HRV and ana.mean/z references', () async {
      await seedPaperComparisonFixture();
      final snap = await repository.readCycleComparison(
        '2026-09-15',
        now: now,
      );
      expect(snap.window.startDay, '2025-09-16');
      expect(snap.window.endDay, '2026-09-15');
      expect(snap.reason, CycleComparisonReason.available);
      expect(snap.algoVersion, kAlgoVersion);
      expect(snap.rhr.latest?.nightDay, '2026-09-15');
      expect(snap.rhr.latest?.metric.value, 56);
      expect(snap.rhr.latest?.cycleDay, 23);
      expect(snap.hrv.latest?.nightDay, '2026-09-14');
      expect(snap.hrv.latest?.metric.value, 51);
      expect(snap.hrv.latest?.cycleDay, 22);

      final rhrPrior = [
        for (var i = 1; i <= 21; i++)
          if (kCyclePaperRhr[i] != null) kCyclePaperRhr[i]! + 2,
      ];
      expect(snap.rhr.prior21.count, 17);
      expect(snap.rhr.prior21.mean, ana.mean(rhrPrior));
      expect(snap.rhr.prior21.delta, 56 - ana.mean(rhrPrior)!);
      expect(snap.rhr.prior21.z, ana.z(56, rhrPrior));

      final hrvPrior = [
        for (var i = 0; i <= 20; i++)
          if (kCyclePaperHrv[i] != null) kCyclePaperHrv[i]! + 3,
      ];
      expect(snap.hrv.prior21.count, 15);
      expect(snap.hrv.prior21.mean, ana.mean(hrvPrior));
      expect(snap.hrv.prior21.z, ana.z(51, hrvPrior));

      expect(snap.rhr.sameDay.count, 3);
      expect(snap.rhr.sameDay.mean, ana.mean(const [50.0, 52.0, 54.0]));
      expect(snap.rhr.sameDay.delta, 4);
      expect(snap.rhr.sameDay.z, ana.z(56, const [50.0, 52.0, 54.0]));
      expect(snap.hrv.sameDay.mean, ana.mean(const [45.0, 47.0, 49.0]));
      expect(snap.hrv.sameDay.z, ana.z(51, const [45.0, 47.0, 49.0]));
    });

    test('older and newer algo rows are ignored; only exact 90 is read',
        () async {
      await seedStart('2026-08-24');
      await seedNight('2026-09-14', rhr: 40, hrv: 10, algo: kAlgoVersion - 1);
      await seedNight('2026-09-14', rhr: 54, hrv: 48);
      await seedNight('2026-09-15', rhr: 99, hrv: 99, algo: kAlgoVersion + 1);
      final snap = await repository.readCycleComparison('2026-09-15', now: now);
      expect(snap.rhr.latest?.nightDay, '2026-09-14');
      expect(snap.rhr.latest?.metric.value, 54);
      expect(snap.hrv.latest?.metric.value, 48);
    });

    test('prior-21 reads the 21-day pad before window.startDay', () async {
      await seedStart('2025-08-01');
      await seedNight('2025-08-25', rhr: 40);
      await seedNight('2025-08-26', rhr: 50);
      await seedNight('2025-09-10', rhr: 52);
      await seedNight('2025-09-16', rhr: 54);
      final snap = await repository.readCycleComparison('2026-09-15', now: now);
      expect(snap.window.startDay, '2025-09-16');
      expect(cycleComparisonQueryStart(snap.window), '2025-08-26');
      expect(snap.rhr.latest?.nightDay, '2025-09-16');
      expect(snap.rhr.prior21.startDay, '2025-08-26');
      expect(
        snap.rhr.prior21.contributors.map((c) => c.nightDay),
        ['2025-08-26', '2025-09-10'],
      );
      expect(
        snap.rhr.prior21.contributors.any((c) => c.nightDay == '2025-08-25'),
        isFalse,
      );
    });

    test('accepted padding nights never become latest for an empty year',
        () async {
      await seedStart('2026-08-24');
      await seedNight('2025-08-26', rhr: 50, hrv: 20);
      await seedNight('2025-09-10', rhr: 52, hrv: 22);
      await seedNight('2025-09-15', rhr: 54, hrv: 24);
      final snap = await repository.readCycleComparison('2026-09-15', now: now);
      expect(snap.window.startDay, '2025-09-16');
      expect(snap.rhr.latestReason, CycleComparisonLatestReason.missing);
      expect(snap.rhr.latest, isNull);
      expect(snap.hrv.latestReason, CycleComparisonLatestReason.missing);
      expect(snap.hrv.latest, isNull);
      expect(snap.rhr.prior21.reason, CycleComparisonPrior21Reason.noLatest);
      expect(snap.hrv.prior21.reason, CycleComparisonPrior21Reason.noLatest);
    });

    test('leap and DST civil nights under America/Los_Angeles', () async {
      final originalTz = Platform.environment['TZ'];
      _setProcessTz('America/Los_Angeles');
      addTearDown(() => _setProcessTz(originalTz));
      expect(
        DateTime(2026, 3, 8).timeZoneOffset,
        const Duration(hours: -8),
      );
      await seedStart('2026-03-07');
      await seedNight('2026-03-07', rhr: 50);
      await seedNight('2026-03-08', rhr: 51);
      await seedNight('2026-03-09', rhr: 52);
      await seedNight('2026-03-10', rhr: 53);
      final snap = await repository.readCycleComparison(
        '2026-03-10',
        now: DateTime(2026, 3, 10, 12),
      );
      expect(snap.window.endDay, '2026-03-10');
      expect(snap.rhr.latest?.nightDay, '2026-03-10');
      expect(
        snap.rhr.prior21.contributors.map((c) => c.nightDay),
        ['2026-03-07', '2026-03-08', '2026-03-09'],
      );

      await seedStart('2023-09-01');
      await seedNight('2024-02-29', rhr: 60);
      final leap = await repository.readCycleComparison(
        '2024-09-15',
        now: now,
      );
      expect(leap.window.expectedNights, contains('2024-02-29'));
      expect(
        leap.rhr.latest?.nightDay == '2024-02-29' ||
            leap.rhr.prior21.contributors.any((c) => c.nightDay == '2024-02-29'),
        isTrue,
      );
    });

    test('inclusive window end and exclusive latest for prior-21', () async {
      await seedStart('2026-08-24');
      await seedNight('2026-08-25', rhr: 50);
      await seedNight('2026-09-14', rhr: 54);
      await seedNight('2026-09-15', rhr: 56);
      final snap = await repository.readCycleComparison('2026-09-15', now: now);
      expect(snap.rhr.latest?.nightDay, '2026-09-15');
      expect(snap.rhr.prior21.endDay, '2026-09-14');
      expect(
        snap.rhr.prior21.contributors.map((c) => c.nightDay),
        ['2026-08-25', '2026-09-14'],
      );
    });

    test('later starts after as-of do not close the open period', () async {
      await seedStart('2026-05-28');
      await seedStart('2026-06-29');
      await seedStart('2026-07-31');
      await seedStart('2026-08-24');
      await seedStart('2026-10-01');
      await seedPaperNightsFrom('2026-05-28');
      await seedPaperNightsFrom('2026-06-29');
      await seedPaperNightsFrom('2026-07-31');
      await seedPaperNightsFrom('2026-08-24', rhrAdd: 2, hrvAdd: 3);
      await seedNight('2026-06-19', rhr: 50, hrv: kCyclePaperHrv[22]);
      await seedNight('2026-07-21', rhr: 52, hrv: kCyclePaperHrv[22]);
      await seedNight('2026-08-22', rhr: 54, hrv: kCyclePaperHrv[22]);
      final snap = await repository.readCycleComparison('2026-09-15', now: now);
      expect(snap.rhr.latest?.startDay, '2026-08-24');
      expect(snap.rhr.sameDay.count, 3);
    });

    test('pending, failed and stale receipts refuse; complete matching keeps',
        () async {
      await seedStart('2026-08-24');
      await seedNight('2026-09-12', rhr: 50, sleepSource: 'manual');
      await seedNight('2026-09-13', rhr: 51, sleepSource: 'manual');
      await seedNight('2026-09-14', rhr: 52, sleepSource: 'manual');
      await seedNight('2026-09-15', rhr: 53, sleepSource: 'manual');
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
      const receipt = 1800000000000;
      await putCorrection(
        '2026-09-15',
        revision: 1,
        status: 'complete',
        resultAlgo: kAlgoVersion,
        resultAt: receipt,
      );
      await setComputedAt('2026-09-15', receipt - 1);
      final snap = await repository.readCycleComparison('2026-09-15', now: now);
      expect(snap.rhr.latest, isNull);
      expect(snap.rhr.latestReason, CycleComparisonLatestReason.unavailable);
      expect(snap.hrv.latestReason, CycleComparisonLatestReason.unavailable);
      expect(snap.rhr.rejectedCount, 4);
      expect(snap.excludedNightCount, 4);

      await setComputedAt('2026-09-15', receipt);
      final kept = await repository.readCycleComparison('2026-09-15', now: now);
      expect(kept.rhr.latest?.nightDay, '2026-09-15');
      expect(kept.excludedNightCount, 3);
    });

    test('complete override with mismatched bounds withholds; automatic keeps',
        () async {
      await seedStart('2026-08-24');
      await seedNight('2026-09-14', rhr: 54, hrv: 48, sleepSource: 'manual');
      await seedNight('2026-09-15', rhr: 56, hrv: 51);
      const receipt = 1800000000000;
      await putCorrection(
        '2026-09-14',
        revision: 1,
        status: 'complete',
        resultAlgo: kAlgoVersion,
        resultAt: receipt,
        onsetMs: cycleNightOnsetMs('2026-09-14') + 3600000,
        wakeMs: cycleNightOffsetMs('2026-09-14') + 3600000,
      );
      await setComputedAt('2026-09-14', receipt + 1);
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
      final snap = await repository.readCycleComparison('2026-09-15', now: now);
      expect(snap.rhr.latest?.nightDay, '2026-09-15');
      expect(
        snap.rhr.prior21.contributors.any((c) => c.nightDay == '2026-09-14'),
        isFalse,
      );
    });

    test('literal stored payload and independent metric corruption', () async {
      await seedStart('2026-08-24');
      await seedLiteral('2026-09-14', _literalClone());
      final badHrv = _literalClone();
      final c1 = Map<String, dynamic>.from(badHrv['clinical'] as Map);
      c1['rmssd_sleep_session'] = 'bad';
      badHrv['clinical'] = c1;
      await seedLiteral('2026-09-15', badHrv);
      final snap = await repository.readCycleComparison('2026-09-15', now: now);
      expect(snap.rhr.latest?.nightDay, '2026-09-15');
      expect(snap.rhr.latest?.metric.value, 62.996665);
      expect(snap.hrv.latest?.nightDay, '2026-09-14');
      expect(snap.hrv.latest?.metric.value, 19.9);
      expect(snap.unreadableNightCount, 1);
      expect(snap.partial, isTrue);
      expect(snap.hrv.unreadableCount, 1);
      expect(snap.rhr.unreadableCount, 0);
    });

    test('long and unassigned actual nights are retained', () async {
      await seedStart('2025-10-01');
      await seedNight('2026-09-01', rhr: 50);
      await seedNight('2026-09-14', rhr: 54);
      await seedNight('2026-09-15', rhr: 56);
      final snap = await repository.readCycleComparison('2026-09-15', now: now);
      expect(snap.rhr.latest?.nightDay, '2026-09-15');
      expect(snap.rhr.prior21.count, 2);
      expect(
        snap.rhr.sameDay.reason,
        CycleComparisonSameDayReason.longLatestPeriod,
      );

      await clearNights();
      final db = await LocalDb.instance;
      await db.delete('cycle_log');
      await seedStart('2026-09-12');
      await seedNight('2026-08-25', rhr: 50, hrv: 40);
      await seedNight('2026-09-01', rhr: 52, hrv: 42);
      await seedNight('2026-09-10', rhr: 56, hrv: 51);
      final unassigned =
          await repository.readCycleComparison('2026-09-15', now: now);
      expect(unassigned.rhr.latest?.nightDay, '2026-09-10');
      expect(unassigned.rhr.latest?.assignment, isNull);
      expect(unassigned.hrv.latest?.nightDay, '2026-09-10');
      expect(unassigned.hrv.latest?.assignment, isNull);
      expect(
        unassigned.rhr.prior21.reason,
        CycleComparisonPrior21Reason.available,
      );
      expect(unassigned.rhr.prior21.count, 2);
      expect(
        unassigned.hrv.prior21.reason,
        CycleComparisonPrior21Reason.available,
      );
      expect(
        unassigned.rhr.sameDay.reason,
        CycleComparisonSameDayReason.unassignedLatest,
      );
      expect(
        unassigned.hrv.sameDay.reason,
        CycleComparisonSameDayReason.unassignedLatest,
      );
    });

    test('>=2 prior-21 and >=3 same-day thresholds; zero SD withholds z',
        () async {
      await seedStart('2026-05-28');
      await seedStart('2026-06-29');
      await seedStart('2026-07-31');
      await seedStart('2026-08-24');
      await seedNight('2026-06-19', rhr: 54);
      await seedNight('2026-07-21', rhr: 54);
      await seedNight('2026-08-22', rhr: 54);
      await seedNight('2026-09-10', rhr: 54);
      await seedNight('2026-09-11', rhr: 54);
      await seedNight('2026-09-15', rhr: 56);
      final snap = await repository.readCycleComparison('2026-09-15', now: now);
      expect(snap.rhr.prior21.reason, CycleComparisonPrior21Reason.available);
      expect(snap.rhr.prior21.mean, 54);
      expect(snap.rhr.prior21.delta, 2);
      expect(snap.rhr.prior21.z, isNull);
      expect(snap.rhr.sameDay.reason, CycleComparisonSameDayReason.available);
      expect(snap.rhr.sameDay.z, isNull);

      final one = LocalOpenBandRepository(
        app,
        cycleSettingsRead: () async => settings,
      );
      final db = await LocalDb.instance;
      await db.delete('day_result');
      await seedNight('2026-09-15', rhr: 56);
      final thin = await one.readCycleComparison('2026-09-15', now: now);
      expect(
        thin.rhr.prior21.reason,
        CycleComparisonPrior21Reason.insufficientNights,
      );
      expect(
        thin.rhr.sameDay.reason,
        CycleComparisonSameDayReason.insufficientPeriods,
      );
    });

    test('year-1 window pad clamps; future and negative page throw', () async {
      final year1 = await repository.readCycleComparison(
        '0001-12-31',
        now: now,
      );
      expect(year1.window.startDay, '0001-01-01');
      expect(cycleComparisonQueryStart(year1.window), '0001-01-01');
      expect(year1.rhr.latestReason, CycleComparisonLatestReason.missing);

      await expectLater(
        repository.readCycleComparison('2026-09-16', now: now),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        repository.readCycleComparison(
          '2026-09-15',
          pageOffset: -1,
          now: now,
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        repository.readCycleComparison('0001-01-31', now: now),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('tracking off does not read day_result; enabled still throws',
        () async {
      await seedStart('2026-08-24');
      await seedNight('2026-09-15', rhr: 54);
      final db = await LocalDb.instance;
      await db.execute('DROP TABLE day_result');

      final off = LocalOpenBandRepository(
        app,
        cycleSettingsRead: () async => const CycleSettings(
          enabled: false,
          estimatesEnabled: true,
          lengthReviewEnabled: false,
        ),
      );
      expect(
        (await off.readCycleComparison('2026-09-15', now: now)).reason,
        CycleComparisonReason.trackingDisabled,
      );

      await expectLater(
        repository.readCycleComparison('2026-09-15', now: now),
        throwsA(anything),
      );
    });

    test('empty starts still query nights; cycle_log failure throws', () async {
      await seedNight('2026-09-15', rhr: 56);
      final empty = await repository.readCycleComparison(
        '2026-09-15',
        now: now,
      );
      expect(empty.rhr.latest?.nightDay, '2026-09-15');
      expect(empty.rhr.latest?.assignment, isNull);
      expect(
        empty.rhr.sameDay.reason,
        CycleComparisonSameDayReason.emptyStarts,
      );

      final db = await LocalDb.instance;
      await db.execute('DROP TABLE cycle_log');
      await expectLater(
        repository.readCycleComparison('2026-09-15', now: now),
        throwsA(anything),
      );
    });

    test('estimates, length review and situation do not gate comparison',
        () async {
      await seedPaperComparisonFixture();
      final gated = LocalOpenBandRepository(
        app,
        cycleSettingsRead: () async => const CycleSettings(
          enabled: true,
          estimatesEnabled: false,
          lengthReviewEnabled: true,
          situation: CycleSituation.none,
        ),
      );
      final snap = await gated.readCycleComparison('2026-09-15', now: now);
      expect(snap.reason, CycleComparisonReason.available);
      expect(snap.rhr.latest?.metric.value, 56);
      expect(snap.hrv.latest?.metric.value, 51);
    });

    test('readCycleMedians and readCycleMeasurements stay on their contracts',
        () async {
      await seedStart('2026-08-24');
      await seedPaperNightsFrom('2026-08-24');
      final medians = await repository.readCycleMedians('2026-09-15', now: now);
      expect(medians.reason, CycleMediansReason.insufficientDays);
      final measurements = await repository.readCycleMeasurements('2026-09-15');
      expect(measurements.nights, hasLength(23));
      expect(measurements.latestRhr?.value, 54);
    });

    test('window latest reasons and padding coverage stay local to SQLite',
        () async {
      await seedStart('2026-08-24');
      final badRhr = _literalClone();
      final clinical = Map<String, dynamic>.from(badRhr['clinical'] as Map);
      clinical['resting_hr'] = 'bad';
      badRhr['clinical'] = clinical;
      await seedLiteral('2026-09-15', badRhr);
      final corrupt = await repository.readCycleComparison(
        '2026-09-15',
        now: now,
      );
      expect(corrupt.rhr.latestReason, CycleComparisonLatestReason.unreadable);
      expect(corrupt.hrv.latestReason, CycleComparisonLatestReason.available);
      expect(corrupt.hrv.latest?.metric.value, 19.9);
      expect(corrupt.rhr.unreadableCount, 1);
      expect(corrupt.hrv.unreadableCount, 0);

      await clearNights();
      await seedNight('2026-09-15', rhr: 56, imported: true);
      final refused = await repository.readCycleComparison(
        '2026-09-15',
        now: now,
      );
      expect(refused.rhr.latestReason, CycleComparisonLatestReason.unavailable);
      expect(refused.hrv.latestReason, CycleComparisonLatestReason.unavailable);
      expect(refused.rhr.rejectedCount, 1);

      await clearNights();
      await seedNight('2026-09-01', rhr: 50);
      await seedNight('2026-09-10', rhr: 52);
      await seedNight('2026-09-15', rhr: 56);
      final clean = await repository.readCycleComparison(
        '2026-09-15',
        now: now,
      );
      await seedNight('2025-08-26', payloadJson: '{');
      final unused = await repository.readCycleComparison(
        '2026-09-15',
        now: now,
      );
      expect(unused.unreadableNightCount, clean.unreadableNightCount);
      expect(unused.partial, clean.partial);
      expect(unused.rhr.latestReason, CycleComparisonLatestReason.available);

      await clearNights();
      await seedNight('2025-08-26', payloadJson: '{');
      await seedNight('2025-09-16', rhr: 54);
      final relevant = await repository.readCycleComparison(
        '2026-09-15',
        now: now,
      );
      expect(relevant.rhr.latest?.nightDay, '2025-09-16');
      expect(relevant.rhr.prior21.startDay, '2025-08-26');
      expect(relevant.unreadableNightCount, 1);
      expect(relevant.partial, isTrue);
    });
  });

  group('SyntheticOpenBandRepository.readCycleComparison', () {
    SyntheticOpenBandRepository repo() {
      final r = SyntheticOpenBandRepository.fromMaps(
        jsonDecode(
          File('docs/openband5/assets/fixtures/day-summary.json')
              .readAsStringSync(),
        ) as Map,
        jsonDecode(
          File('docs/openband5/assets/fixtures/sleep-detail.json')
              .readAsStringSync(),
        ) as Map,
      );
      return r;
    }

    test('opt-in fixture matches Paper without changing default cycle',
        () async {
      final untouched = repo();
      final defaultSnap = await untouched.readCycleComparison(
        SyntheticOpenBandRepository.cycleComparisonFixtureAnchor,
        now: SyntheticOpenBandRepository.cycleComparisonFixtureNow,
      );
      expect(defaultSnap.rhr.latest?.metric.value, 54);
      expect(
        defaultSnap.rhr.sameDay.reason,
        CycleComparisonSameDayReason.insufficientPeriods,
      );
      expect(
        (await untouched.readCycleMeasurements('2026-09-15')).nights,
        hasLength(23),
      );
      expect(
        (await untouched.readCycleMedians(
          '2026-09-15',
          now: SyntheticOpenBandRepository.cycleComparisonFixtureNow,
        ))
            .periods,
        hasLength(4),
      );

      final r = repo()..seedCycleComparisonFixture();
      final snap = await r.readCycleComparison(
        SyntheticOpenBandRepository.cycleComparisonFixtureAnchor,
        now: SyntheticOpenBandRepository.cycleComparisonFixtureNow,
      );
      expect(snap.rhr.latest?.metric.value, 56);
      expect(snap.rhr.latest?.cycleDay, 23);
      expect(snap.hrv.latest?.metric.value, 51);
      expect(snap.hrv.latest?.cycleDay, 22);
      expect(snap.rhr.prior21.count, 17);
      expect(snap.hrv.prior21.count, 15);
      expect(snap.rhr.sameDay.count, 3);
      expect(snap.hrv.sameDay.count, 3);
      expect(snap.rhr.sameDay.z, ana.z(56, const [50.0, 52.0, 54.0]));
      expect(snap.hrv.sameDay.z, ana.z(51, const [45.0, 47.0, 49.0]));
    });

    test('missing, partial, unreadable, off, long and failure fixtures',
        () async {
      final empty = repo()
        ..clearCycleLogs()
        ..clearCycleNightSources();
      expect(
        (await empty.readCycleComparison(
          '2026-09-15',
          now: SyntheticOpenBandRepository.cycleComparisonFixtureNow,
        ))
            .rhr
            .latestReason,
        CycleComparisonLatestReason.missing,
      );

      final rhrOnly = repo()..seedCycleComparisonFixture(includeHrv: false);
      final rhrSnap = await rhrOnly.readCycleComparison(
        '2026-09-15',
        now: SyntheticOpenBandRepository.cycleComparisonFixtureNow,
      );
      expect(rhrSnap.rhr.latest?.metric.value, 56);
      expect(rhrSnap.hrv.latest, isNull);
      expect(rhrSnap.hrv.latestReason, CycleComparisonLatestReason.missing);

      final unread = repo()
        ..clearCycleLogs()
        ..seedUnreadableCycleStart({'date': '2026-08-24', 'kind': ''})
        ..seedCycleNightSource(
          CycleNightSourceRow(
            day: '2026-09-15',
            algoVersion: kAlgoVersion,
            payload: cycleNightSourcePayload(
              rhr: 56,
              onsetMs: cycleNightOnsetMs('2026-09-15'),
              offsetMs: cycleNightOffsetMs('2026-09-15'),
            ),
          ),
        );
      final unreadSnap = await unread.readCycleComparison(
        '2026-09-15',
        now: SyntheticOpenBandRepository.cycleComparisonFixtureNow,
      );
      expect(unreadSnap.rhr.latest?.metric.value, 56);
      expect(
        unreadSnap.rhr.sameDay.reason,
        CycleComparisonSameDayReason.unreadableStarts,
      );

      final off = repo()
        ..seedCycleComparisonFixture()
        ..cycleSettings = const CycleSettings(
          enabled: false,
          estimatesEnabled: true,
          lengthReviewEnabled: false,
        );
      expect(
        (await off.readCycleComparison(
          '2026-09-15',
          now: SyntheticOpenBandRepository.cycleComparisonFixtureNow,
        ))
            .reason,
        CycleComparisonReason.trackingDisabled,
      );

      final fail = repo()..failCycleComparisonRead = true;
      await expectLater(
        fail.readCycleComparison(
          '2026-09-15',
          now: SyntheticOpenBandRepository.cycleComparisonFixtureNow,
        ),
        throwsStateError,
      );
      fail.failCycleComparisonRead = false;
      fail.seedCycleComparisonFixture();
      expect(
        (await fail.readCycleComparison(
          '2026-09-15',
          now: SyntheticOpenBandRepository.cycleComparisonFixtureNow,
        ))
            .rhr
            .latest
            ?.metric
            .value,
        56,
      );
    });
  });
}

Map<String, dynamic> _literalClone() =>
    jsonDecode(jsonEncode(_kLiteralStoredNightPayload)) as Map<String, dynamic>;

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
};
