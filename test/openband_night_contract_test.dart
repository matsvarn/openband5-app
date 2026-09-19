import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/series_codec.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late LocalOpenBandRepository repository;
  const day = '2026-09-15';
  final start = DateTime.parse('2026-09-14T23:10:00+02:00');
  final end = DateTime.parse('2026-09-15T06:54:00+02:00');
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await LocalDb.close();
    LocalDb.dbName = 'openband_night_contract_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/${LocalDb.dbName}');
    app = AppState.forTesting();
    repository = LocalOpenBandRepository(app);
  });
  tearDown(() async {
    app.dispose();
    await LocalDb.close();
  });
  Map<String, dynamic> payload() => {
    'sleep': {
      'window': {
        'value': {
          'onset_ms': start.millisecondsSinceEpoch,
          'offset_ms': end.millisecondsSinceEpoch,
        },
      },
    },
    'series': {
      'hr_curve': [
        {'t': start.millisecondsSinceEpoch ~/ 1000 - 60, 'v': 99},
        {'t': start.millisecondsSinceEpoch ~/ 1000, 'v': 54},
        {'t': start.millisecondsSinceEpoch ~/ 1000 + 60, 'v': null},
        {'t': start.millisecondsSinceEpoch ~/ 1000 + 120, 'v': 52},
        {'t': end.millisecondsSinceEpoch ~/ 1000, 'v': 88},
      ],
      'resp_day': [
        {'t': start.millisecondsSinceEpoch ~/ 1000 + 300, 'v': 14.2},
      ],
      'hrv_timeline': [
        {'t': start.millisecondsSinceEpoch ~/ 1000, 'v': 999},
      ],
    },
    'hrv_night_shape': {
      'origin_ms': start.millisecondsSinceEpoch,
      'value': {
        'bins': [
          {'t': 0, 'rmssd_ms': 60, 'lo_ms': 55, 'hi_ms': 65},
          {'t': 1800, 'rmssd_ms': null, 'lo_ms': null, 'hi_ms': null},
          {'t': 3600, 'rmssd_ms': 62, 'lo_ms': 58, 'hi_ms': 66},
        ],
      },
    },
  };
  Future<void> save(Map<String, dynamic> data) => LocalDb.putDayResult(
    dayId: day,
    algoVersion: kAlgoVersion,
    payloadJson: SeriesCodec.encodePayloadJson(jsonEncode(data)),
    windowJson: '{}',
    partial: true,
  );

  test(
    'reads the exact stored night, decodes compressed series and retains refusals',
    () async {
      await save(payload());
      final night = await repository.readNightSignals(day);
      expect(night.window, (start: start, end: end));
      final pulse = night.signal(NightSignalKind.pulse);
      expect(pulse.readings.map((p) => p.value), [54, null, 52]);
      expect(pulse.readings.first.at, start);
      expect(pulse.partial, isTrue);
      expect(pulse.maxConnectingGap, const Duration(minutes: 1));
      expect(
        night.signal(NightSignalKind.respiration).readings.single.value,
        14.2,
      );
      final hrv = night.signal(NightSignalKind.hrv);
      expect(hrv.readings.map((p) => p.value), [60, null, 62]);
      expect(hrv.readings.last.at, start.add(const Duration(hours: 1)));
      expect(hrv.readings.first.bounds, (lower: 55.0, upper: 65.0));
      expect(hrv.partial, isTrue);
      final absent = await repository.readNightSignals('2026-09-16');
      expect(absent.window, isNull);
      expect(absent.series, isEmpty);
    },
  );

  test(
    'HRV never substitutes a raw timeline or a value without its stored band',
    () async {
      final data = payload();
      data['hrv_night_shape'] = {'value': '—', 'note': 'too few beats'};
      await save(data);
      expect(
        (await repository.readNightSignals(
          day,
        )).signal(NightSignalKind.hrv).readings,
        isEmpty,
      );
      final withMissingBand = payload();
      final shape = withMissingBand['hrv_night_shape'] as Map;
      ((shape['value'] as Map)['bins'] as List).first.remove('hi_ms');
      await save(withMissingBand);
      final readings = (await repository.readNightSignals(
        day,
      )).signal(NightSignalKind.hrv).readings;
      expect(readings.first.value, isNull);
      expect(readings.first.bounds, isNull);
      shape.remove('origin_ms');
      await save(withMissingBand);
      expect(
        (await repository.readNightSignals(
          day,
        )).signal(NightSignalKind.hrv).readings,
        isEmpty,
      );
    },
  );

  test(
    'a pending correction withholds old curves until its own result is complete',
    () async {
      await save(payload());
      final draft = SleepDraft(
        id: 'synthetic-night',
        day: day,
        onset: start,
        wake: end,
        recordingTimezone: 'Europe/Berlin',
      );
      await repository.saveDraft(draft);
      final saved = await repository.saveCorrection(draft);
      var night = await repository.readNightSignals(day);
      expect(night.processing, isTrue);
      expect(night.series, isEmpty);
      await LocalDb.updateOpenBandCalculationJob(
        dayId: day,
        correctionId: saved.id,
        revision: saved.revision,
        status: 'failed',
      );
      night = await repository.readNightSignals(day);
      expect(night.processing, isFalse);
      expect(night.series, isEmpty);
      await LocalDb.updateOpenBandCalculationJob(
        dayId: day,
        correctionId: saved.id,
        revision: saved.revision,
        status: 'complete',
      );
      night = await repository.readNightSignals(day);
      expect(night.recordingTimezone, 'Europe/Berlin');
      expect(night.signal(NightSignalKind.pulse).readings, hasLength(3));
    },
  );

  test(
    'a missing window stays missing and unreadable storage remains a retryable error',
    () async {
      final data = payload()..remove('sleep');
      await save(data);
      expect((await repository.readNightSignals(day)).window, isNull);
      await LocalDb.putDayResult(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: 'unreadable',
        windowJson: '{}',
      );
      await expectLater(
        repository.readNightSignals(day),
        throwsFormatException,
      );
    },
  );
}
