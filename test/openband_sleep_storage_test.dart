import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const dbName = 'openband_sleep_storage_test.db';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await LocalDb.close();
    LocalDb.dbName = dbName;
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/$dbName');
  });

  tearDown(() async => LocalDb.close());

  test('an older calculation cannot overwrite a newer correction', () async {
    const day = '2026-09-15';
    for (final id in ['first', 'second']) {
      await LocalDb.putOpenBandSleepDraft(
        dayId: day,
        draftId: id,
        onsetMs: 1000,
        wakeMs: 2000,
      );
      await LocalDb.commitOpenBandSleepCorrection(
        dayId: day,
        draftId: id,
        onsetMs: 1000,
        wakeMs: 2000,
      );
    }
    await LocalDb.putDayResult(
      dayId: day,
      algoVersion: kAlgoVersion,
      payloadJson: '{"receipt":"current"}',
      windowJson: '{}',
      expectedSleepCorrectionRevision: 2,
      series: {'tst_min': 123},
    );
    await expectLater(
      LocalDb.putDayResult(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: '{"receipt":"stale"}',
        windowJson: '{}',
        expectedSleepCorrectionRevision: 1,
        series: {'tst_min': 456},
      ),
      throwsStateError,
    );
    expect(
      (await LocalDb.dayResult(day))?['payload_json'],
      contains('current'),
    );
    expect(await LocalDb.metricValueOn(day, 'tst_min'), 123);
  });

  test('relaunch makes an interrupted calculation retryable', () async {
    const day = '2026-09-15';
    await LocalDb.putOpenBandSleepDraft(
      dayId: day,
      draftId: 'interrupted',
      onsetMs: 1000,
      wakeMs: 2000,
    );
    await LocalDb.commitOpenBandSleepCorrection(
      dayId: day,
      draftId: 'interrupted',
      onsetMs: 1000,
      wakeMs: 2000,
    );
    await LocalDb.updateOpenBandCalculationJob(
      dayId: day,
      correctionId: 'interrupted',
      revision: 1,
      status: 'calculating',
      fromStatuses: {'pending'},
    );
    await LocalDb.close();
    expect((await LocalDb.openBandSleepCorrection(day))?['status'], 'pending');
    expect(
      (await LocalDb.getSleepOverride(day))?['correction_id'],
      'interrupted',
    );
  });

  test(
    'draft survives relaunch and correction commit is atomic/idempotent',
    () async {
      const day = '2026-09-15';
      final onset = DateTime(2026, 9, 14, 23, 25).millisecondsSinceEpoch;
      final wake = DateTime(2026, 9, 15, 6, 54).millisecondsSinceEpoch;
      await LocalDb.putOpenBandSleepDraft(
        dayId: day,
        draftId: 'draft-stable',
        onsetMs: onset,
        wakeMs: wake,
        recordingTimezone: 'Europe/Berlin',
      );

      await LocalDb.close();
      final restored = await LocalDb.openBandSleepDraft(day);
      expect(restored?['draft_id'], 'draft-stable');
      expect(restored?['recording_timezone'], 'Europe/Berlin');

      final first = await LocalDb.commitOpenBandSleepCorrection(
        dayId: day,
        draftId: 'draft-stable',
        onsetMs: onset,
        wakeMs: wake,
        recordingTimezone: 'Europe/Berlin',
      );
      final retry = await LocalDb.commitOpenBandSleepCorrection(
        dayId: day,
        draftId: 'draft-stable',
        onsetMs: onset,
        wakeMs: wake,
        recordingTimezone: 'Europe/Berlin',
      );
      expect(first['revision'], 1);
      expect(retry['revision'], 1);
      expect(await LocalDb.openBandSleepDraft(day), isNull);

      final db = await LocalDb.instance;
      expect(
        (await db.rawQuery(
          'SELECT COUNT(*) AS n FROM openband_sleep_correction',
        )).single['n'],
        1,
      );
      expect(
        (await db.rawQuery(
          'SELECT COUNT(*) AS n FROM openband_calculation_job',
        )).single['n'],
        1,
      );
      final receipt = await LocalDb.openBandSleepCorrection(day);
      expect(receipt?['status'], 'pending');
      expect(receipt?['correction_id'], 'draft-stable');
    },
  );

  test('failed atomic save retains durable draft', () async {
    const day = '2026-09-15';
    final onset = DateTime(2026, 9, 14, 23).millisecondsSinceEpoch;
    final wake = DateTime(2026, 9, 15, 7).millisecondsSinceEpoch;
    await LocalDb.putOpenBandSleepDraft(
      dayId: day,
      draftId: 'draft-failure',
      onsetMs: onset,
      wakeMs: wake,
    );
    final db = await LocalDb.instance;
    await db.execute('''
      CREATE TRIGGER fail_openband_override
      BEFORE INSERT ON sleep_override
      BEGIN SELECT RAISE(ABORT, 'synthetic full disk'); END
    ''');

    await expectLater(
      LocalDb.commitOpenBandSleepCorrection(
        dayId: day,
        draftId: 'draft-failure',
        onsetMs: onset,
        wakeMs: wake,
      ),
      throwsA(anything),
    );
    expect(
      (await LocalDb.openBandSleepDraft(day))?['draft_id'],
      'draft-failure',
    );
    expect(await LocalDb.openBandSleepCorrection(day), isNull);
  });

  test(
    'failed calculation is durable and restore invalidates auto candidate',
    () async {
      const day = '2026-09-15';
      final onset = DateTime(2026, 9, 14, 23).millisecondsSinceEpoch;
      final wake = DateTime(2026, 9, 15, 7).millisecondsSinceEpoch;
      await LocalDb.putOpenBandSleepDraft(
        dayId: day,
        draftId: 'draft-job',
        onsetMs: onset,
        wakeMs: wake,
      );
      await LocalDb.commitOpenBandSleepCorrection(
        dayId: day,
        draftId: 'draft-job',
        onsetMs: onset,
        wakeMs: wake,
      );
      expect(
        await LocalDb.updateOpenBandCalculationJob(
          dayId: day,
          correctionId: 'draft-job',
          revision: 1,
          status: 'failed',
          error: 'source unavailable',
          fromStatuses: const {'pending'},
        ),
        isTrue,
      );
      await LocalDb.putSleepSessionCandidate(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: '{}',
      );

      await LocalDb.close();
      expect((await LocalDb.openBandSleepCorrection(day))?['status'], 'failed');
      expect(
        (await LocalDb.openBandSleepCorrection(day))?['error'],
        'source unavailable',
      );

      await LocalDb.restoreOpenBandAutomatic(day);
      expect(await LocalDb.getSleepOverride(day), isNull);
      expect(await LocalDb.sleepSessionCandidate(day, kAlgoVersion), isNull);
      final restored = await LocalDb.openBandSleepCorrection(day);
      expect(restored?['action'], 'automatic');
      expect(restored?['revision'], 2);
      expect(restored?['status'], 'pending');
    },
  );

  test(
    'non-destructive retention keeps decoded rows and full-rate v20 archive',
    () async {
      final db = await LocalDb.instance;
      await db.insert('decoded_onehz', {
        'device_id': '',
        'ts_ms': 1000000,
        'rec_ts': 1000,
        'counter': 1,
        'hr': 60,
      });
      for (var i = 1; i <= 3; i++) {
        await db.insert('raw_archive', {
          'device_id': '',
          'hex': i.toRadixString(16).padLeft(4, '0'),
          'counter': i,
          'packet_type': 47,
          'rec_ts': 1000,
          'captured_at': 1000000,
          'reason': 'undecodable_rec_v20',
        });
      }

      expect(await LocalDb.pruneDecodedBeforeRecTs(2000), 0);
      expect(await LocalDb.thinRawArchiveBefore(2000000), 0);
      expect((await LocalDb.counts())['decoded_onehz'], 1);
      expect((await LocalDb.rawArchiveStats())['count'], 3);
    },
  );
}
