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
  late LocalOpenBandRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    await LocalDb.close();
    LocalDb.dbName = 'openband_g3_sleep_projection_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/${LocalDb.dbName}');
    app = AppState.forTesting();
    repo = LocalOpenBandRepository(app);
  });
  tearDown(() async {
    app.dispose();
    await LocalDb.close();
  });

  int sec(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

  Future<void> save(
    String day,
    Map<String, dynamic> payload, {
    int algoVersion = kAlgoVersion,
  }) => LocalDb.putDayResult(
    dayId: day,
    algoVersion: algoVersion,
    payloadJson: jsonEncode(payload),
    windowJson: '{}',
  );

  Map<String, dynamic> night(
    DateTime onset,
    DateTime wake, {
    List<Map<String, Object?>> pulse = const [],
    List<Map<String, Object?>> gaps = const [],
  }) => {
    'sleep': {
      'window': {
        'value': {
          'onset_ms': onset.millisecondsSinceEpoch,
          'offset_ms': wake.millisecondsSinceEpoch,
        },
      },
    },
    'series': {'hr_curve': pulse, 'hypnogram': gaps},
  };

  test('missing selected output and old algorithm refuse the night', () async {
    const day = '2026-09-29';
    expect((await repo.readNightSignals(day)).window, isNull);
    final onset = DateTime.parse('2026-09-28T23:10:00+02:00');
    final wake = DateTime.parse('2026-09-29T06:54:00+02:00');
    await save(day, night(onset, wake), algoVersion: kAlgoVersion - 1);
    final result = await repo.readNightSignals(day);
    expect(result.window, isNull);
    expect(result.series, isEmpty);
    expect(result.unobservedGaps, isNull);
  });

  test('a night without stored hypnogram has unknown gap spans', () async {
    const day = '2026-09-29';
    final onset = DateTime.parse('2026-09-28T23:10:00+02:00');
    final wake = DateTime.parse('2026-09-29T06:54:00+02:00');
    final data = night(onset, wake);
    (data['series'] as Map).remove('hypnogram');
    await save(day, data);
    final result = await repo.readNightSignals(day);
    expect(result.window, (start: onset, end: wake));
    expect(result.unobservedGaps, isNull);
  });

  test(
    '23:10 night includes both day bundles and only stored gap spans',
    () async {
      const day = '2026-09-29';
      final onset = DateTime.parse('2026-09-28T23:10:00+02:00');
      final wake = DateTime.parse('2026-09-29T06:54:00+02:00');
      final beforeMidnight = DateTime.parse('2026-09-28T23:40:00+02:00');
      final afterMidnight = DateTime.parse('2026-09-29T00:20:00+02:00');
      final gapStart = onset.add(const Duration(hours: 2));
      final gapEnd = gapStart.add(const Duration(minutes: 10));
      await save(
        day,
        night(
          onset,
          wake,
          pulse: [
            {'t': sec(afterMidnight), 'v': 52},
          ],
          gaps: [
            {'start': sec(gapStart), 'end': sec(gapEnd), 'stage': 'unobserved'},
            {'start': sec(gapEnd), 'end': sec(gapEnd) + 60, 'stage': 'light'},
          ],
        ),
      );
      await save(
        '2026-09-28',
        night(
          onset,
          wake,
          pulse: [
            {'t': sec(beforeMidnight), 'v': 59},
          ],
        ),
      );
      final result = await repo.readNightSignals(day);
      expect(result.window, (start: onset, end: wake));
      expect(
        result.signal(NightSignalKind.pulse).readings.map((r) => r.value),
        [59, 52],
      );
      expect(result.unobservedGaps, hasLength(1));
      expect(result.unobservedGaps!.single.start, gapStart);
      expect(result.unobservedGaps!.single.end, gapEnd);
    },
  );

  test(
    'spring-forward night uses absolute window across two local labels',
    () async {
      const day = '2026-03-29';
      final onset = DateTime.parse('2026-03-28T23:10:00+01:00');
      final wake = DateTime.parse('2026-03-29T06:54:00+02:00');
      final before = DateTime.parse('2026-03-28T23:40:00+01:00');
      final after = DateTime.parse('2026-03-29T03:10:00+02:00');
      await save(
        day,
        night(
          onset,
          wake,
          pulse: [
            {'t': sec(after), 'v': 51},
          ],
        ),
      );
      await save(
        '2026-03-28',
        night(
          onset,
          wake,
          pulse: [
            {'t': sec(before), 'v': 58},
          ],
        ),
      );
      final result = await repo.readNightSignals(day);
      expect(result.signal(NightSignalKind.pulse).readings.map((r) => r.at), [
        before,
        after,
      ]);
      expect(
        result.window!.end.difference(result.window!.start),
        const Duration(hours: 6, minutes: 44),
      );
      expect(result.unobservedGaps, isEmpty);
    },
  );

  test(
    'completed correction cannot publish a different stored window',
    () async {
      const day = '2026-09-29';
      final onset = DateTime.parse('2026-09-28T23:10:00+02:00');
      final wake = DateTime.parse('2026-09-29T06:54:00+02:00');
      final draft = SleepDraft(
        id: 'night-window',
        day: day,
        onset: onset,
        wake: wake,
        recordingTimezone: 'Europe/Berlin',
      );
      await save(day, night(onset.add(const Duration(minutes: 20)), wake));
    await repo.saveDraft(draft);
    final correction = await repo.saveCorrection(draft);
    final oldResult = await LocalDb.dayResult(day);
    await LocalDb.updateOpenBandCalculationJob(
      dayId: day,
      correctionId: correction.id,
      revision: correction.revision,
      status: 'complete',
    );
    expect((await repo.readNightSignals(day)).window, isNull);
    await LocalDb.updateOpenBandCalculationJob(
        dayId: day,
        correctionId: correction.id,
        revision: correction.revision,
        status: 'complete',
        resultAlgoVersion: kAlgoVersion,
        resultComputedAt: (oldResult!['computed_at'] as num).toInt(),
      );
      expect((await repo.readNightSignals(day)).window, isNull);
      await save(day, {...night(onset, wake), 'sleep_source': 'manual'});
      expect((await repo.readNightSignals(day)).window, (
        start: onset,
        end: wake,
      ));
    },
  );
}
