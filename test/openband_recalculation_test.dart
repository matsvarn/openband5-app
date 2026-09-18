import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late LocalOpenBandRepository repository;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await LocalDb.close();
    LocalDb.dbName = 'openband_recalculation_test.db';
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

  const day = '2026-09-15';
  SleepDraft draft(String id) => SleepDraft(
    id: id,
    day: day,
    onset: DateTime(2026, 9, 14, 23, 15),
    wake: DateTime(2026, 9, 15, 6, 45),
  );

  test(
    'selected day never borrows a previous night and keeps its own baselines',
    () async {
      final today = todayLabel();
      final yesterday = dayLabelOf(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      await LocalDb.putDayResult(
        dayId: yesterday,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({
          'scalars': {'rmssd': 48, 'rhr': 54, 'readiness': 74},
          'baselines': {
            'hrv': {'baseline': 40},
            'resting_hr': {'baseline': 56},
          },
        }),
        windowJson: '{}',
        finalized: true,
        series: {'rmssd': 48, 'rhr': 54},
      );
      final missing = await repository.readDay(today);
      expect(missing.hrv.value, isNull);
      expect(missing.restingHr.value, isNull);
      expect(missing.recovery.value, isNull);
      final historical = await repository.readDay(yesterday);
      expect(historical.hrv.value, 48);
      expect(historical.hrv.baseline, 40);
      expect(historical.restingHr.value, 54);
      expect(historical.restingHr.baseline, 56);
    },
  );

  test(
    'intake chips distinguish unknown from a known lower bound for that day',
    () async {
      final db = await LocalDb.instance;
      await NutritionDb.put(
        db,
        const FoodEntry(
          id: 'known',
          date: day,
          meal: 'breakfast',
          label: 'Synthetic breakfast',
          kcal: 620,
        ),
      );
      await NutritionDb.put(
        db,
        const FoodEntry(
          id: 'unknown',
          date: day,
          meal: 'snack',
          label: 'Synthetic unmeasured snack',
        ),
      );
      final result = await repository.readDay(day);
      expect(result.intake.kcal, 620);
      expect(result.intake.kcalIsFloor, isTrue);
      expect(result.intake.waterMl, isNull);
      expect((await repository.readDay('2026-09-14')).intake.kcal, isNull);
    },
  );

  test(
    'band snapshot separates primary battery observation and committed frontier',
    () async {
      await LocalDb.setCursor('rec_ts_hw', '1000');
      await LocalDb.insertBandBatterySample(
        ts: 900,
        deviceId: LocalDb.kPrimaryDeviceId,
        batteryPct: 64,
        source: 'synthetic',
      );
      await LocalDb.insertBandBatterySample(
        ts: 1100,
        deviceId: 'other-synthetic-device',
        batteryPct: 12,
        source: 'synthetic',
      );
      await LocalDb.upsertSyncLedgerEntry(status: 'ack_failed');
      final band = await repository.readBand();
      expect(band.connection, BandConnection.disconnected);
      expect(band.transfer, TransferState.interrupted);
      expect(band.batteryPercent, 64);
      expect(band.batteryObservedAt?.millisecondsSinceEpoch, 900000);
      expect(band.latestStoredAt?.millisecondsSinceEpoch, 1000000);
      expect(band.receivedAt, isNull);
    },
  );

  test(
    'retained synthetic sensor rows produce a confirmed corrected day',
    () async {
      final db = await LocalDb.instance;
      final batch = db.batch();
      final start = DateTime(2026, 9, 14, 23).millisecondsSinceEpoch ~/ 1000;
      for (var i = 0; i < 8 * 3600; i++) {
        batch.insert('decoded_onehz', {
          'device_id': '',
          'ts_ms': (start + i) * 1000,
          'rec_ts': start + i,
          'counter': i,
          'hr': 55 + i % 3,
          'ax': 0.0,
          'ay': 0.0,
          'az': 1.0,
          'device_family': 'gen4',
        });
      }
      await batch.commit(noResult: true);
      final edit = draft('synthetic-correction');
      await repository.saveDraft(edit);
      final receipt = await repository.saveCorrection(edit);
      expect(receipt.state, CorrectionState.pending);
      await repository.recalculate(receipt);
      final result = await repository.readDay(day);
      expect(result.correction?.state, CorrectionState.complete);
      expect(result.sleep.onset, edit.onset);
      expect(result.sleep.wake, edit.wake);
      expect(result.sleep.duration.value, isNotNull);
      expect(result.sleep.bedMinutes, 450);
      expect(result.sleep.segments, isNotEmpty);
      expect((await LocalDb.dayResult(day))?['algo_version'], kAlgoVersion);
      final count = (await db.rawQuery(
        'SELECT COUNT(*) AS n FROM decoded_onehz',
      )).single['n'];
      expect(count, 28800, reason: 'recalculation must retain source');
      await LocalDb.close();
      expect(
        (await repository.readDay(day)).correction?.state,
        CorrectionState.complete,
      );
    },
  );

  test(
    'missing source fails durably without deleting the saved correction',
    () async {
      final edit = draft('missing-source');
      await repository.saveDraft(edit);
      final receipt = await repository.saveCorrection(edit);
      await expectLater(repository.recalculate(receipt), throwsStateError);
      await LocalDb.close();
      final result = await repository.readDay(day);
      expect(result.correction?.id, receipt.id);
      expect(result.correction?.state, CorrectionState.failed);
      expect(result.sleep.duration.value, isNull);
      expect(await LocalDb.getSleepOverride(day), isNotNull);
    },
  );
}
