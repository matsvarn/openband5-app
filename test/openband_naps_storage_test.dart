import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const dbName = 'openband_naps_storage_test.db';

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

  test('nap edits enqueue a revision even after the last row is gone', () async {
    const day = '2026-09-15';
    final first = await LocalDb.putNapEdit(
      dayId: day,
      startTs: 1000,
      endTs: 2800,
      source: 'manual',
    );
    expect(first, 1);
    expect((await LocalDb.napEdits(day)).length, 1);
    final second = await LocalDb.deleteNapEdit(day, 1000);
    expect(second, 2);
    expect(await LocalDb.napEdits(day), isEmpty);
    final job = await LocalDb.napRecalcJob(day);
    expect(job?['revision'], 2);
    expect(job?['status'], 'pending');
  });

  test('detected edit with a new start stores reject and manual together', () async {
    const day = '2026-09-15';
    await LocalDb.commitNapLedger(
      dayId: day,
      puts: [
        (
          startTs: 1000,
          endTs: 2800,
          source: 'rejected',
          originStartTs: null,
          originEndTs: null,
        ),
        (
          startTs: 4000,
          endTs: 5800,
          source: 'manual',
          originStartTs: null,
          originEndTs: null,
        ),
      ],
    );
    final rows = await LocalDb.napEdits(day);
    expect(rows.map((r) => r['source']), ['rejected', 'manual']);
    expect(rows.map((r) => r['start_ts']), [1000, 4000]);
  });

  test('same-start detected override keeps a manual row, not a rejection', () async {
    const day = '2026-09-15';
    await LocalDb.commitNapLedger(
      dayId: day,
      puts: [
        (
          startTs: 1000,
          endTs: 2800,
          source: 'rejected',
          originStartTs: null,
          originEndTs: null,
        ),
        (
          startTs: 1000,
          endTs: 4000,
          source: 'manual',
          originStartTs: 1000,
          originEndTs: 2800,
        ),
      ],
    );
    final rows = await LocalDb.napEdits(day);
    expect(rows, hasLength(1));
    expect(rows.single['source'], 'manual');
    expect(rows.single['end_ts'], 4000);
  });

  test('nap job is independent of the night-correction job', () async {
    const day = '2026-09-15';
    await LocalDb.putOpenBandSleepDraft(
      dayId: day,
      draftId: 'night',
      onsetMs: 1000,
      wakeMs: 2000,
    );
    await LocalDb.commitOpenBandSleepCorrection(
      dayId: day,
      draftId: 'night',
      onsetMs: 1000,
      wakeMs: 2000,
    );
    await LocalDb.putNapEdit(
      dayId: day,
      startTs: 5000,
      endTs: 6800,
      source: 'manual',
    );
    expect((await LocalDb.openBandSleepCorrection(day))?['revision'], 1);
    expect((await LocalDb.napRecalcJob(day))?['revision'], 1);
    expect((await LocalDb.openBandSleepCorrection(day))?['status'], 'pending');
    expect((await LocalDb.napRecalcJob(day))?['status'], 'pending');
  });

  test('stale nap revision cannot persist a day result', () async {
    const day = '2026-09-15';
    await LocalDb.putNapEdit(
      dayId: day,
      startTs: 1000,
      endTs: 2800,
      source: 'manual',
    );
    await LocalDb.putDayResult(
      dayId: day,
      algoVersion: kAlgoVersion,
      payloadJson: '{"receipt":"current"}',
      windowJson: '{}',
      expectedNapRevision: 1,
      series: {'nap_min': 30},
    );
    await LocalDb.putNapEdit(
      dayId: day,
      startTs: 4000,
      endTs: 5800,
      source: 'manual',
    );
    await expectLater(
      LocalDb.putDayResult(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: '{"receipt":"stale"}',
        windowJson: '{}',
        expectedNapRevision: 1,
        series: {'nap_min': 99},
      ),
      throwsStateError,
    );
    expect((await LocalDb.dayResult(day))?['payload_json'], contains('current'));
    expect(await LocalDb.metricValueOn(day, 'nap_min'), 30);
  });

  test('relaunch resets an interrupted nap job to pending', () async {
    const day = '2026-09-15';
    await LocalDb.putNapEdit(
      dayId: day,
      startTs: 1000,
      endTs: 2800,
      source: 'manual',
    );
    await LocalDb.updateNapRecalcJob(
      dayId: day,
      revision: 1,
      status: 'calculating',
      fromStatuses: {'pending'},
    );
    await LocalDb.close();
    expect((await LocalDb.napRecalcJob(day))?['status'], 'pending');
    expect((await LocalDb.napEdits(day)).single['source'], 'manual');
  });

  test('night correction revision stays independent of nap persist guard', () async {
    const day = '2026-09-15';
    await LocalDb.putOpenBandSleepDraft(
      dayId: day,
      draftId: 'night',
      onsetMs: 1000,
      wakeMs: 2000,
    );
    await LocalDb.commitOpenBandSleepCorrection(
      dayId: day,
      draftId: 'night',
      onsetMs: 1000,
      wakeMs: 2000,
    );
    await LocalDb.putNapEdit(
      dayId: day,
      startTs: 5000,
      endTs: 6800,
      source: 'manual',
    );
    await LocalDb.putDayResult(
      dayId: day,
      algoVersion: kAlgoVersion,
      payloadJson: '{"ok":true}',
      windowJson: '{}',
      expectedSleepCorrectionRevision: 1,
      expectedNapRevision: 1,
    );
    await expectLater(
      LocalDb.putDayResult(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: '{"stale":true}',
        windowJson: '{}',
        expectedSleepCorrectionRevision: 0,
        expectedNapRevision: 1,
      ),
      throwsStateError,
    );
  });
}
