import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalOpenBandRepository.readCycleMedians', () {
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
      LocalDb.dbName = 'openband_cycle_medians_store_test.db';
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

    Future<void> seedPaperNightsFrom(String start) async {
      final last = cycleAddDays(start, kCyclePaperRhr.length - 1);
      final days = cycleCivilDaysInclusive(start, last);
      for (var i = 0; i < days.length; i++) {
        final rhr = kCyclePaperRhr[i];
        final hrv = kCyclePaperHrv[i];
        if (rhr == null && hrv == null) continue;
        await seedNight(days[i], rhr: rhr, hrv: hrv);
      }
    }

    Future<void> seedPaperMedianFixture() async {
      for (final date in ['2026-06-29', '2026-07-31', '2026-08-24']) {
        await seedStart(date);
        await seedPaperNightsFrom(date);
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

    test('Paper arrays yield RHR day 23 = 54 and HRV day 22 = 48 from 3 cycles',
        () async {
      await seedPaperMedianFixture();
      final snap = await repository.readCycleMedians(
        '2026-09-15',
        now: now,
      );
      expect(snap.window.startDay, '2025-09-16');
      expect(snap.window.endDay, '2026-09-15');
      expect(snap.window.page, 0);
      expect(snap.window.expectedNightCount, 365);
      expect(snap.reason, CycleMediansReason.available);
      expect(snap.algoVersion, 91);
      expect(snap.periods.map((p) => p.startDay), [
        '2026-06-29',
        '2026-07-31',
        '2026-08-24',
      ]);
      expect(snap.rhr.available, isTrue);
      expect(snap.hrv.available, isTrue);
      expect(snap.rhr.latest?.cycleDay, 23);
      expect(snap.rhr.latest?.median, 54);
      expect(snap.rhr.latest?.contributingPeriodCount, 3);
      expect(snap.hrv.latest?.cycleDay, 22);
      expect(snap.hrv.latest?.median, 48);
      expect(snap.hrv.latest?.contributingPeriodCount, 3);
      expect(snap.rhr.qualifyingDayCount, 19);
      expect(snap.hrv.qualifyingDayCount, 16);
      expect(snap.rhr.eligibleNightCount, 57);
      expect(snap.hrv.eligibleNightCount, 48);
      final rhrGaps = [
        for (final p in snap.rhr.points)
          if (p.median == null) p.cycleDay,
      ];
      expect(rhrGaps, [6, 7, 15, 20]);
      expect(snap.rhr.latest!.contributors.first.metric.confidence, isNull);
      expect(
        snap.rhr.latest!.contributors.first.metric.confidenceUnreadable,
        isFalse,
      );
    });

    test('older and newer algo rows are ignored; only exact 90 is read',
        () async {
      await seedStart('2026-08-01');
      await seedStart('2026-08-24');
      await seedNight('2026-09-14', rhr: 40, hrv: 10, algo: kAlgoVersion - 1);
      await seedNight('2026-09-14', rhr: 54, hrv: 48);
      await seedNight('2026-09-15', rhr: 99, hrv: 99, algo: kAlgoVersion + 1);
      await seedNight('2026-08-14', rhr: 54, hrv: 48);
      await seedNight('2026-08-15', rhr: 54);
      final snap = await repository.readCycleMedians('2026-09-15', now: now);
      final rhrDays = {for (final c in snap.rhr.eligibleNights) c.nightDay};
      expect(rhrDays, containsAll(['2026-08-14', '2026-08-15', '2026-09-14']));
      expect(rhrDays, isNot(contains('2026-09-15')));
      expect(
        snap.rhr.eligibleNights.where((c) => c.nightDay == '2026-09-14').single
            .metric.value,
        54,
      );
    });

    test('365 and 366 civil windows page adjacently from an independent end',
        () async {
      final page0 = cycleMedianWindow(anchorEnd: '2026-09-15', pageOffset: 0);
      final page1 = cycleMedianWindow(anchorEnd: '2026-09-15', pageOffset: 1);
      expect(page0.expectedNightCount, 365);
      expect(page1.expectedNightCount, 365);
      expect(cycleAddDays(page1.endDay, 1), page0.startDay);
      final leap = cycleMedianWindow(anchorEnd: '2024-09-15', pageOffset: 0);
      expect(leap.expectedNightCount, 366);
      expect(leap.expectedNights, contains('2024-02-29'));
      expect(page0.expectedNights, isNot(contains('2026-02-29')));

      await seedStart('2026-07-20');
      await seedStart('2026-08-24');
      await seedNight('2026-08-01', rhr: 50);
      final historical = await repository.readCycleMedians(
        '2026-08-01',
        now: now,
      );
      expect(historical.window.endDay, '2026-08-01');
      expect(historical.window.startDay, '2025-08-02');
      expect(historical.periods, isNot(isEmpty));
      expect(
        historical.periods.every((p) => p.endDay.compareTo('2026-08-01') <= 0),
        isTrue,
      );
      expect(
        historical.rhr.eligibleNights.any((c) => c.nightDay == '2026-08-01'),
        isTrue,
      );
    });

    test('pageOffset 1 keeps prior-year bounds and drops current-page rows',
        () async {
      const anchor = '2026-09-15';
      final page0 = cycleMedianWindow(anchorEnd: anchor, pageOffset: 0);
      final page1 = cycleMedianWindow(anchorEnd: anchor, pageOffset: 1);
      expect(page1.startDay, '2024-09-16');
      expect(page1.endDay, '2025-09-15');
      expect(page1.page, 1);
      expect(page1.expectedNightCount, 365);
      expect(cycleAddDays(page1.endDay, 1), page0.startDay);

      await seedStart('2024-09-01');
      await seedStart('2024-10-20');
      await seedStart('2025-09-15');
      await seedStart('2026-08-24');
      final db = await LocalDb.instance;
      await db.insert('cycle_log', {'date': '2025-09-16', 'kind': ''});

      await seedNight('2024-09-15', rhr: 40);
      await seedNight('2024-09-16', rhr: 51);
      await seedNight('2025-09-15', rhr: 54);
      await seedNight('2025-09-16', rhr: 99);
      await seedNight('2026-09-15', rhr: 88);

      final snap = await repository.readCycleMedians(
        anchor,
        pageOffset: 1,
        now: now,
      );
      expect(snap.window.startDay, '2024-09-16');
      expect(snap.window.endDay, '2025-09-15');
      expect(snap.window.page, 1);
      expect(snap.window.expectedNightCount, 365);
      expect(snap.reason, isNot(CycleMediansReason.unreadableStarts));
      expect(snap.periods.map((p) => p.startDay), [
        '2024-09-01',
        '2025-09-15',
      ]);
      expect(snap.periods.first.endDay, '2024-10-19');
      expect(snap.periods.last.endDay, '2025-09-15');
      expect(snap.periods.last.open, isTrue);
      expect(
        snap.rhr.eligibleNights.map((c) => c.nightDay),
        ['2024-09-16', '2025-09-15'],
      );
      expect(
        snap.rhr.eligibleNights
            .firstWhere((c) => c.nightDay == '2024-09-16')
            .cycleDay,
        16,
      );
      expect(
        snap.rhr.eligibleNights
            .firstWhere((c) => c.nightDay == '2025-09-15')
            .startDay,
        '2025-09-15',
      );
    });

    test('nights older than 120 civil days still contribute', () async {
      await seedStart('2025-09-01');
      await seedStart('2025-10-20');
      await seedNight('2025-09-16', rhr: 51, hrv: 49);
      final snap = await repository.readCycleMedians('2026-09-15', now: now);
      expect(
        snap.rhr.eligibleNights.single.nightDay,
        '2025-09-16',
      );
      expect(snap.rhr.eligibleNights.single.cycleDay, 16);
      expect(snap.rhr.eligibleNights.single.startDay, '2025-09-01');
    });

    test('DST civil nights stay consecutive labels', () async {
      final window = cycleMedianWindow(anchorEnd: '2026-03-10', pageOffset: 0);
      final nights = window.expectedNights;
      final i = nights.indexOf('2026-03-07');
      expect(i, greaterThan(0));
      expect(nights.sublist(i, i + 4), [
        '2026-03-07',
        '2026-03-08',
        '2026-03-09',
        '2026-03-10',
      ]);
      await seedStart('2026-03-07');
      final snap = await repository.readCycleMedians(
        '2026-03-10',
        now: DateTime(2026, 3, 10, 12),
      );
      expect(snap.window.endDay, '2026-03-10');
      expect(snap.periods.single.startDay, '2026-03-07');
      expect(snap.periods.single.endDay, '2026-03-10');
    });

    test('one pre-window start clips into the window; later starts are as-of',
        () async {
      await seedStart('2025-09-01');
      await seedStart('2025-10-20');
      await seedStart('2026-09-20');
      await seedNight('2025-09-16', rhr: 50);
      await seedNight('2026-09-20', rhr: 99);
      final snap = await repository.readCycleMedians('2026-09-15', now: now);
      expect(
        snap.periods.map((p) => p.startDay),
        ['2025-09-01'],
      );
      expect(snap.periods.single.endDay, '2025-10-19');
      expect(snap.rhr.eligibleNights.single.nightDay, '2025-09-16');
      expect(
        snap.rhr.eligibleNights.any((c) => c.nightDay == '2026-09-20'),
        isFalse,
      );
    });

    test('pending, failed and stale receipts refuse; complete matching keeps',
        () async {
      await seedStart('2026-07-20');
      await seedStart('2026-08-24');
      await seedNight('2026-09-12', rhr: 50, sleepSource: 'manual');
      await seedNight('2026-09-13', rhr: 51, sleepSource: 'manual');
      await seedNight('2026-09-14', rhr: 52, sleepSource: 'manual');
      await seedNight('2026-09-15', rhr: 53, sleepSource: 'manual');
      await seedNight('2026-08-12', rhr: 50, sleepSource: 'manual');
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
      final snap = await repository.readCycleMedians('2026-09-15', now: now);
      expect(snap.excludedNightCount, 4);
      expect(
        snap.rhr.eligibleNights.any((c) => c.nightDay.startsWith('2026-09-')),
        isFalse,
      );
      expect(
        snap.rhr.eligibleNights.any((c) => c.nightDay == '2026-08-12'),
        isTrue,
      );

      await setComputedAt('2026-09-15', receipt);
      final kept = await repository.readCycleMedians('2026-09-15', now: now);
      expect(
        kept.rhr.eligibleNights.any((c) => c.nightDay == '2026-09-15'),
        isTrue,
      );
      expect(kept.excludedNightCount, 3);
    });

    test('complete override with mismatched bounds withholds; automatic keeps',
        () async {
      await seedStart('2026-07-20');
      await seedStart('2026-08-24');
      await seedNight('2026-09-14', rhr: 54, hrv: 48, sleepSource: 'manual');
      await seedNight('2026-09-15', rhr: 54, hrv: 48);
      await seedNight('2026-08-14', rhr: 54, hrv: 48, sleepSource: 'manual');
      const receipt = 1800000000000;
      await putCorrection(
        '2026-08-14',
        revision: 1,
        status: 'complete',
        resultAlgo: kAlgoVersion,
        resultAt: receipt,
        onsetMs: cycleNightOnsetMs('2026-08-14') + 3600000,
        wakeMs: cycleNightOffsetMs('2026-08-14') + 3600000,
      );
      await setComputedAt('2026-08-14', receipt + 1);
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
      final snap = await repository.readCycleMedians('2026-09-15', now: now);
      expect(
        snap.rhr.eligibleNights.any((c) => c.nightDay == '2026-08-14'),
        isFalse,
      );
      expect(snap.excludedNightCount, 1);
      expect(
        snap.rhr.eligibleNights.any((c) => c.nightDay == '2026-09-15'),
        isTrue,
      );
    });

    test('malformed, non-object and duplicate-key JSON follow Dart last-wins',
        () async {
      await seedStart('2026-07-20');
      await seedStart('2026-08-24');
      await seedNight('2026-09-12', payloadJson: '{');
      await seedNight('2026-09-13', payloadJson: '[]');
      await seedNight('2026-09-14', payloadJson: '"nope"');
      final last = jsonEncode({
        'imported': false,
        ..._kLiteralStoredNightPayload,
      });
      const first = '{"imported":true,"sleep_source":"none","sleep":{"window":'
          '{"value":{"onset_ms":1,"offset_ms":2}}},"clinical":[]}';
      final duplicated =
          '${first.substring(0, first.length - 1)},${last.substring(1)}';
      await seedNight('2026-08-14', payloadJson: duplicated);
      await seedNight('2026-08-15', payloadJson: duplicated);
      await seedNight('2026-09-15', payloadJson: duplicated);
      final snap = await repository.readCycleMedians('2026-09-15', now: now);
      expect(snap.unreadableNightCount, 3);
      expect(
        snap.rhr.eligibleNights.map((c) => c.nightDay),
        containsAll(['2026-08-14', '2026-08-15', '2026-09-15']),
      );
      expect(
        snap.rhr.eligibleNights
            .where((c) => c.nightDay == '2026-09-15')
            .single
            .metric
            .value,
        62.996665,
      );
    });

    test('independent metric missing and malformed clinical stay per-metric',
        () async {
      await seedStart('2026-07-20');
      await seedStart('2026-08-24');
      await seedNight('2026-08-14', rhr: 54);
      await seedNight('2026-09-14', hrv: 48);
      final badHrv = _literalClone();
      final c1 = Map<String, dynamic>.from(badHrv['clinical'] as Map);
      c1['rmssd_sleep_session'] = 'bad';
      badHrv['clinical'] = c1;
      await seedLiteral('2026-08-15', badHrv);
      await seedLiteral('2026-09-15', badHrv);
      final snap = await repository.readCycleMedians('2026-09-15', now: now);
      expect(
        snap.rhr.eligibleNights.map((c) => c.nightDay),
        containsAll(['2026-08-14', '2026-08-15', '2026-09-15']),
      );
      expect(
        snap.hrv.eligibleNights.map((c) => c.nightDay),
        ['2026-09-14'],
      );
      expect(snap.unreadableNightCount, 2);
      expect(snap.partial, isTrue);
    });

    test('imported true is refused; 1 and string true stay eligible', () async {
      await seedStart('2026-07-20');
      await seedStart('2026-08-24');
      final importedTrue = _literalClone()..['imported'] = true;
      await seedLiteral('2026-08-13', importedTrue);
      await seedLiteral('2026-09-13', importedTrue);
      final importedOne = _literalClone()..['imported'] = 1;
      await seedLiteral('2026-08-14', importedOne);
      await seedLiteral('2026-09-14', importedOne);
      final importedString = _literalClone()..['imported'] = 'true';
      await seedLiteral('2026-08-15', importedString);
      await seedLiteral('2026-09-15', importedString);
      final snap = await repository.readCycleMedians('2026-09-15', now: now);
      expect(snap.excludedNightCount, 2);
      expect(
        snap.rhr.eligibleNights.map((c) => c.nightDay),
        containsAll(['2026-08-14', '2026-09-14', '2026-08-15', '2026-09-15']),
      );
      expect(
        snap.rhr.eligibleNights.any((c) => c.nightDay.endsWith('-13')),
        isFalse,
      );
    });

    test('tracking off, empty and unreadable starts do not read day_result',
        () async {
      await seedStart('2026-08-24');
      await seedNight('2026-09-15', rhr: 54, hrv: 48);
      final db = await LocalDb.instance;
      await db.execute('DROP TABLE day_result');

      final emptyRepo = LocalOpenBandRepository(
        app,
        cycleSettingsRead: () async => settings,
      );
      await db.delete('cycle_log');
      expect(
        (await emptyRepo.readCycleMedians('2026-09-15', now: now)).reason,
        CycleMediansReason.emptyStarts,
      );

      await db.insert('cycle_log', {'date': '2026-08-24', 'kind': ''});
      expect(
        (await emptyRepo.readCycleMedians('2026-09-15', now: now)).reason,
        CycleMediansReason.unreadableStarts,
      );

      final off = LocalOpenBandRepository(
        app,
        cycleSettingsRead: () async => const CycleSettings(
          enabled: false,
          estimatesEnabled: true,
          lengthReviewEnabled: false,
        ),
      );
      expect(
        (await off.readCycleMedians('2026-09-15', now: now)).reason,
        CycleMediansReason.trackingDisabled,
      );
    });

    test('valid starts still throw when day_result is missing', () async {
      await seedStart('2026-08-24');
      final db = await LocalDb.instance;
      await db.execute('DROP TABLE day_result');
      await expectLater(
        repository.readCycleMedians('2026-09-15', now: now),
        throwsA(anything),
      );
    });

    test('long intersecting periods are excluded without dropping valid ones',
        () async {
      await seedStart('2025-10-01');
      await seedStart('2026-06-29');
      await seedStart('2026-07-31');
      await seedPaperNightsFrom('2026-06-29');
      await seedPaperNightsFrom('2026-07-31');
      final snap = await repository.readCycleMedians('2026-09-15', now: now);
      expect(snap.reason, CycleMediansReason.available);
      expect(snap.partial, isTrue);
      expect(snap.excludedPeriodCount, 1);
      expect(
        snap.excludedPeriods.single.reason,
        CycleMedianPeriodExcludeReason.longClosed,
      );
      expect(snap.periods.map((p) => p.startDay), ['2026-06-29', '2026-07-31']);
      expect(snap.rhr.latest?.contributingPeriodCount, 2);
    });

    test('all-long intersecting periods withhold without fabricating medians',
        () async {
      await seedStart('2025-10-01');
      final snap = await repository.readCycleMedians('2026-09-15', now: now);
      expect(snap.reason, CycleMediansReason.longPeriods);
      expect(snap.rhr.available, isFalse);
      expect(snap.hrv.available, isFalse);
      expect(snap.rhr.points, isEmpty);
      expect(snap.excludedPeriodCount, 1);
    });

    test('estimates, length review and situation do not gate medians', () async {
      await seedPaperMedianFixture();
      final gated = LocalOpenBandRepository(
        app,
        cycleSettingsRead: () async => const CycleSettings(
          enabled: true,
          estimatesEnabled: false,
          lengthReviewEnabled: true,
          situation: CycleSituation.none,
        ),
      );
      final snap = await gated.readCycleMedians('2026-09-15', now: now);
      expect(snap.reason, CycleMediansReason.available);
      expect(snap.rhr.latest?.median, 54);
      expect(snap.hrv.latest?.median, 48);
    });

    test('>32 rows are read through the final batch; fat equals slim', () async {
      expect(kCycleNightPayloadBatchSize, 32);
      await seedStart('2026-07-01');
      await seedStart('2026-08-10');
      final period1 = [
        for (var i = 0; i < kCycleNightPayloadBatchSize + 8; i++)
          cycleAddDays('2026-07-01', i),
      ];
      final period2 = cycleCivilDaysInclusive('2026-08-10', '2026-09-15');
      final days = [...period1, ...period2];
      final fat = _literalClone();
      fat['series'] = {
        'hr_curve': {
          't0': 0,
          'dt': 60,
          'v': List<int>.filled(8000, 60),
        },
      };
      fat['activity_curve'] = {
        't0': 0,
        'dt': 60,
        'v': List<int>.filled(8000, 1),
      };
      for (final day in days) {
        await seedLiteral(day, fat);
      }
      final fatSnap = await repository.readCycleMedians('2026-09-15', now: now);
      expect(fatSnap.rhr.eligibleNightCount, days.length);
      expect(fatSnap.rhr.eligibleNightCount, greaterThan(32));
      expect(
        fatSnap.rhr.eligibleNights.map((c) => c.nightDay),
        containsAll([period1.first, period1[32], period2.last]),
      );
      for (final day in days) {
        await seedLiteral(day, _literalClone());
      }
      final slimSnap = await repository.readCycleMedians('2026-09-15', now: now);
      expect(slimSnap.rhr.eligibleNightCount, fatSnap.rhr.eligibleNightCount);
      expect(slimSnap.hrv.eligibleNightCount, fatSnap.hrv.eligibleNightCount);
      expect(slimSnap.rhr.latest?.median, fatSnap.rhr.latest?.median);
      expect(slimSnap.hrv.latest?.median, fatSnap.hrv.latest?.median);
      expect(
        [for (final c in slimSnap.rhr.eligibleNights) c.metric.value],
        [for (final c in fatSnap.rhr.eligibleNights) c.metric.value],
      );
    });

    test('database failure is not rewritten as an empty snapshot', () async {
      await seedStart('2026-08-24');
      final db = await LocalDb.instance;
      await db.execute('DROP TABLE cycle_log');
      await expectLater(
        repository.readCycleMedians('2026-09-15', now: now),
        throwsA(anything),
      );
    });

    test('invalid, future and negative page throw at the boundary', () async {
      await expectLater(
        repository.readCycleMedians('15-09-2026', now: now),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        repository.readCycleMedians('2026-09-31', now: now),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        repository.readCycleMedians(
          '2026-09-16',
          now: now,
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        repository.readCycleMedians(
          '2026-09-15',
          pageOffset: -1,
          now: now,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('selected-cycle 120-night contract still truncates', () async {
      const start = '2026-04-19';
      const asOf = '2026-09-15';
      final visible = cycleAddDays(asOf, -(kCycleMeasurementMaxNights - 1));
      await seedStart(start);
      await seedNight(start, rhr: 40);
      await seedNight(visible, rhr: 41);
      final snap = await repository.readCycleMeasurements(asOf);
      expect(snap.truncated, isTrue);
      expect(snap.nights, hasLength(120));
      expect(snap.nights.any((n) => n.day == start), isFalse);
      expect(snap.nights.first.rhr?.value, 41);
    });
  });

  group('SyntheticOpenBandRepository.readCycleMedians', () {
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

    test('opt-in fixture matches Paper medians without changing default cycle',
        () async {
      final untouched = repo();
      final defaultSnap = await untouched.readCycleMedians(
        SyntheticOpenBandRepository.cycleMedianFixtureAnchor,
        now: SyntheticOpenBandRepository.cycleMedianFixtureNow,
      );
      expect(defaultSnap.reason, CycleMediansReason.insufficientDays);
      expect(defaultSnap.periods, hasLength(4));
      expect(
        (await untouched.readCycleMeasurements('2026-09-15')).nights,
        hasLength(23),
      );

      final r = repo()..seedCycleMedianFixture();
      final snap = await r.readCycleMedians(
        SyntheticOpenBandRepository.cycleMedianFixtureAnchor,
        now: SyntheticOpenBandRepository.cycleMedianFixtureNow,
      );
      expect(snap.window.startDay, '2025-09-16');
      expect(snap.window.endDay, '2026-09-15');
      expect(snap.reason, CycleMediansReason.available);
      expect(snap.periods.map((p) => p.startDay), [
        '2026-06-29',
        '2026-07-31',
        '2026-08-24',
      ]);
      expect(snap.rhr.latest?.cycleDay, 23);
      expect(snap.rhr.latest?.median, 54);
      expect(snap.rhr.latest?.contributingPeriodCount, 3);
      expect(snap.hrv.latest?.cycleDay, 22);
      expect(snap.hrv.latest?.median, 48);
      expect(snap.hrv.latest?.contributingPeriodCount, 3);
      expect(
        snap.rhr.points.firstWhere((p) => p.cycleDay == 6).median,
        isNull,
      );
      expect(snap.rhr.latest!.contributors.first.nightDay, '2026-07-21');
      expect(
        snap.rhr.latest!.contributors.first.sleepStart,
        DateTime.fromMillisecondsSinceEpoch(
          cycleNightOnsetMs('2026-07-21'),
          isUtc: true,
        ),
      );
    });

    test('empty, missing metric, unreadable, off, long and failure fixtures',
        () async {
      final empty = repo()
        ..clearCycleLogs()
        ..clearCycleNightSources();
      expect(
        (await empty.readCycleMedians(
          '2026-09-15',
          now: SyntheticOpenBandRepository.cycleMedianFixtureNow,
        ))
            .reason,
        CycleMediansReason.emptyStarts,
      );

      final rhrOnly = repo()..seedCycleMedianFixture(includeHrv: false);
      final rhrSnap = await rhrOnly.readCycleMedians(
        '2026-09-15',
        now: SyntheticOpenBandRepository.cycleMedianFixtureNow,
      );
      expect(rhrSnap.rhr.available, isTrue);
      expect(rhrSnap.hrv.available, isFalse);
      expect(rhrSnap.hrv.eligibleNightCount, 0);

      final unread = repo()
        ..clearCycleLogs()
        ..seedUnreadableCycleStart({'date': '2026-08-24', 'kind': ''});
      expect(
        (await unread.readCycleMedians(
          '2026-09-15',
          now: SyntheticOpenBandRepository.cycleMedianFixtureNow,
        ))
            .reason,
        CycleMediansReason.unreadableStarts,
      );

      final off = repo()
        ..seedCycleMedianFixture()
        ..cycleSettings = const CycleSettings(
          enabled: false,
          estimatesEnabled: true,
          lengthReviewEnabled: false,
        );
      expect(
        (await off.readCycleMedians(
          '2026-09-15',
          now: SyntheticOpenBandRepository.cycleMedianFixtureNow,
        ))
            .reason,
        CycleMediansReason.trackingDisabled,
      );

      final partial = repo()
        ..clearCycleLogs()
        ..seedCycleStart(const CycleStart(date: '2025-10-01', kind: kCycleStartKind))
        ..seedCycleStart(const CycleStart(date: '2026-06-29', kind: kCycleStartKind))
        ..seedCycleStart(const CycleStart(date: '2026-07-31', kind: kCycleStartKind))
        ..clearCycleNightSources()
        ..seedCyclePaperNightsFrom('2026-06-29')
        ..seedCyclePaperNightsFrom('2026-07-31');
      final partialSnap = await partial.readCycleMedians(
        '2026-09-15',
        now: SyntheticOpenBandRepository.cycleMedianFixtureNow,
      );
      expect(partialSnap.reason, CycleMediansReason.available);
      expect(partialSnap.partial, isTrue);
      expect(partialSnap.excludedPeriodCount, 1);

      final allLong = repo()
        ..clearCycleLogs()
        ..seedCycleStart(const CycleStart(date: '2025-10-01', kind: kCycleStartKind))
        ..clearCycleNightSources();
      expect(
        (await allLong.readCycleMedians(
          '2026-09-15',
          now: SyntheticOpenBandRepository.cycleMedianFixtureNow,
        ))
            .reason,
        CycleMediansReason.longPeriods,
      );

      final fail = repo()..failCycleMediansRead = true;
      await expectLater(
        fail.readCycleMedians(
          '2026-09-15',
          now: SyntheticOpenBandRepository.cycleMedianFixtureNow,
        ),
        throwsStateError,
      );
      fail.failCycleMediansRead = false;
      fail.seedCycleMedianFixture();
      expect(
        (await fail.readCycleMedians(
          '2026-09-15',
          now: SyntheticOpenBandRepository.cycleMedianFixtureNow,
        ))
            .reason,
        CycleMediansReason.available,
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
  'scalars': {'rmssd': 48.0},
};
