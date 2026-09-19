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
  const previous = '2026-09-14';
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
  Map<String, dynamic> payload({
    DateTime? windowStart,
    DateTime? windowEnd,
    List<Object?>? pulse,
    List<Object?>? respiration,
    Map<String, dynamic>? hrv,
  }) {
    final from = windowStart ?? start;
    final to = windowEnd ?? end;
    return {
      'sleep': {
        'window': {
          'value': {
            'onset_ms': from.millisecondsSinceEpoch,
            'offset_ms': to.millisecondsSinceEpoch,
          },
        },
      },
      'series': {
        'hr_curve':
            pulse ??
            [
              {'t': from.millisecondsSinceEpoch ~/ 1000 - 60, 'v': 99},
              {'t': from.millisecondsSinceEpoch ~/ 1000, 'v': 54},
              {'t': from.millisecondsSinceEpoch ~/ 1000 + 60, 'v': null},
              {'t': from.millisecondsSinceEpoch ~/ 1000 + 120, 'v': 52},
              {'t': to.millisecondsSinceEpoch ~/ 1000, 'v': 88},
            ],
        'resp_day':
            respiration ??
            [
              {'t': from.millisecondsSinceEpoch ~/ 1000 + 300, 'v': 14.2},
            ],
        'hrv_timeline': [
          {'t': from.millisecondsSinceEpoch ~/ 1000, 'v': 999},
        ],
      },
      'hrv_night_shape':
          hrv ??
          {
            'origin_ms': from.millisecondsSinceEpoch,
            'value': {
              'bins': [
                {'t': 0, 'rmssd_ms': 60, 'lo_ms': 55, 'hi_ms': 65},
                {'t': 1800, 'rmssd_ms': null, 'lo_ms': null, 'hi_ms': null},
                {'t': 3600, 'rmssd_ms': 62, 'lo_ms': 58, 'hi_ms': 66},
              ],
            },
          },
    };
  }

  Future<void> save(
    Map<String, dynamic> data, {
    String dayId = day,
    int? algoVersion,
    bool partial = true,
    bool skipped = false,
    String? payloadJson,
  }) => LocalDb.putDayResult(
    dayId: dayId,
    algoVersion: algoVersion ?? kAlgoVersion,
    payloadJson: payloadJson ?? SeriesCodec.encodePayloadJson(jsonEncode(data)),
    windowJson: '{}',
    partial: partial,
    skipped: skipped,
  );

  int sec(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

  Future<void> completeZone(String dayId, DateTime onset, DateTime wake) async {
    final draft = SleepDraft(
      id: 'zone-$dayId',
      day: dayId,
      onset: onset,
      wake: wake,
      recordingTimezone: 'Europe/Berlin',
    );
    await repository.saveDraft(draft);
    final saved = await repository.saveCorrection(draft);
    await LocalDb.updateOpenBandCalculationJob(
      dayId: dayId,
      correctionId: saved.id,
      revision: saved.revision,
      status: 'complete',
    );
  }

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

  test(
    'pulse and respiration union compressed bundles that intersect the night',
    () async {
      final beforeMidnight = DateTime.parse('2026-09-14T23:40:00+02:00');
      final eveningOut = DateTime.parse('2026-09-14T21:00:00+02:00');
      await save(payload());
      await save(
        payload(
          pulse: [
            {'t': sec(eveningOut), 'v': 120},
            {'t': sec(beforeMidnight), 'v': 61},
            {'t': sec(beforeMidnight) + 60, 'v': 60},
            {'t': sec(beforeMidnight) + 120, 'v': 59},
            {'t': sec(end), 'v': 70},
          ],
          respiration: [
            {'t': sec(beforeMidnight), 'v': 13.1},
            {'t': sec(beforeMidnight) + 300, 'v': 13.0},
            {'t': sec(beforeMidnight) + 600, 'v': 12.9},
          ],
          hrv: {
            'origin_ms': beforeMidnight.millisecondsSinceEpoch,
            'value': {
              'bins': [
                {'t': 0, 'rmssd_ms': 999, 'lo_ms': 900, 'hi_ms': 1000},
              ],
            },
          },
        ),
        dayId: previous,
      );
      await save(
        {
          'series': {
            'hr_curve': [
              {'t': sec(start) + 180, 'v': 40},
              {'t': sec(start) + 240, 'v': 41},
              {'t': sec(start) + 300, 'v': 42},
            ],
          },
        },
        dayId: '2026-08-01',
      );
      final night = await repository.readNightSignals(day);
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.value),
        [54, null, 52, 61, 60, 59],
      );
      expect(night.signal(NightSignalKind.pulse).readings.first.at, start);
      expect(
        night.signal(NightSignalKind.respiration).readings.map((p) => p.value),
        [14.2, 13.1, 13.0, 12.9],
      );
      expect(
        night.signal(NightSignalKind.hrv).readings.map((p) => p.value),
        [60, null, 62],
      );
      expect(night.signal(NightSignalKind.pulse).partial, isTrue);
    },
  );

  test(
    'timezone and DST candidate days still find stored pre-midnight samples',
    () async {
      final utc12Start = DateTime.parse('2026-09-15T10:00:00Z');
      final utc12End = DateTime.parse('2026-09-15T18:00:00Z');
      await save(
        payload(
          windowStart: utc12Start,
          windowEnd: utc12End,
          pulse: [
            {'t': sec(utc12Start), 'v': 54},
            {'t': sec(utc12Start) + 60, 'v': 53},
            {'t': sec(utc12Start) + 120, 'v': 52},
          ],
        ),
      );
      await save(
        payload(
          pulse: [
            {'t': sec(utc12Start) - 3600, 'v': 80},
            {'t': sec(utc12Start) + 1800, 'v': 61},
            {'t': sec(utc12Start) + 1860, 'v': 60},
            {'t': sec(utc12Start) + 1920, 'v': 59},
          ],
        ),
        dayId: previous,
      );
      var night = await repository.readNightSignals(day);
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.value),
        [54, 53, 52, 61, 60, 59],
      );

      const dstDay = '2026-03-29';
      final springStart = DateTime.parse('2026-03-28T22:00:00+01:00');
      final springEnd = DateTime.parse('2026-03-29T07:00:00+02:00');
      final springEvening = DateTime.parse('2026-03-28T23:20:00+01:00');
      final springMorning = DateTime.parse('2026-03-29T03:30:00+02:00');
      await save(
        payload(
          windowStart: springStart,
          windowEnd: springEnd,
          pulse: [
            {'t': sec(springMorning), 'v': 50},
            {'t': sec(springMorning) + 60, 'v': 49},
            {'t': sec(springMorning) + 120, 'v': 48},
          ],
        ),
        dayId: dstDay,
      );
      await save(
        payload(
          pulse: [
            {'t': sec(springEvening), 'v': 58},
            {'t': sec(springEvening) + 60, 'v': 57},
            {'t': sec(springEvening) + 120, 'v': 56},
          ],
        ),
        dayId: '2026-03-28',
      );
      await completeZone(dstDay, springStart, springEnd);
      night = await repository.readNightSignals(dstDay);
      expect(night.recordingTimezone, 'Europe/Berlin');
      expect(night.window, (start: springStart, end: springEnd));
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.value),
        [58, 57, 56, 50, 49, 48],
      );
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.at),
        [
          springEvening,
          springEvening.add(const Duration(seconds: 60)),
          springEvening.add(const Duration(seconds: 120)),
          springMorning,
          springMorning.add(const Duration(seconds: 60)),
          springMorning.add(const Duration(seconds: 120)),
        ],
      );

      const autumnDay = '2026-10-25';
      final autumnStart = DateTime.parse('2026-10-24T22:00:00+02:00');
      final autumnEnd = DateTime.parse('2026-10-25T07:00:00+01:00');
      final autumnEvening = DateTime.parse('2026-10-24T23:20:00+02:00');
      final autumnMorning = DateTime.parse('2026-10-25T04:30:00+01:00');
      await save(
        payload(
          windowStart: autumnStart,
          windowEnd: autumnEnd,
          pulse: [
            {'t': sec(autumnMorning), 'v': 50},
            {'t': sec(autumnMorning) + 60, 'v': 49},
            {'t': sec(autumnMorning) + 120, 'v': 48},
          ],
        ),
        dayId: autumnDay,
      );
      await save(
        payload(
          pulse: [
            {'t': sec(autumnEvening), 'v': 58},
            {'t': sec(autumnEvening) + 60, 'v': 57},
            {'t': sec(autumnEvening) + 120, 'v': 56},
          ],
        ),
        dayId: '2026-10-24',
      );
      await completeZone(autumnDay, autumnStart, autumnEnd);
      night = await repository.readNightSignals(autumnDay);
      expect(night.recordingTimezone, 'Europe/Berlin');
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.at),
        [
          autumnEvening,
          autumnEvening.add(const Duration(seconds: 60)),
          autumnEvening.add(const Duration(seconds: 120)),
          autumnMorning,
          autumnMorning.add(const Duration(seconds: 60)),
          autumnMorning.add(const Duration(seconds: 120)),
        ],
      );

      final travelStart = DateTime.parse('2026-09-13T20:00:00Z');
      final travelEnd = DateTime.parse('2026-09-14T06:00:00Z');
      await save(
        payload(
          windowStart: travelStart,
          windowEnd: travelEnd,
          pulse: [
            {'t': sec(travelEnd) - 180, 'v': 51},
            {'t': sec(travelEnd) - 120, 'v': 50},
            {'t': sec(travelEnd) - 60, 'v': 49},
          ],
        ),
      );
      await save(
        payload(
          pulse: [
            {'t': sec(travelStart) + 60, 'v': 70},
            {'t': sec(travelStart) + 120, 'v': 69},
            {'t': sec(travelStart) + 180, 'v': 68},
          ],
        ),
        dayId: '2026-09-13',
      );
      night = await repository.readNightSignals(day);
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.value),
        [70, 69, 68, 51, 50, 49],
      );
    },
  );

  test(
    'neighbor generations above the ceiling or below the selected version are refused',
    () async {
      final at = start.add(const Duration(minutes: 30));
      await save(payload());
      await save(
        payload(
          pulse: [
            {'t': sec(at), 'v': 41},
            {'t': sec(at) + 60, 'v': 40},
            {'t': sec(at) + 120, 'v': 39},
          ],
        ),
        dayId: previous,
        algoVersion: kAlgoVersion - 1,
      );
      var night = await repository.readNightSignals(day);
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.value),
        [54, null, 52],
      );
      expect(night.signal(NightSignalKind.pulse).partial, isTrue);

      await save(
        payload(
          pulse: [
            {'t': sec(at), 'v': 42},
            {'t': sec(at) + 60, 'v': 43},
            {'t': sec(at) + 120, 'v': 44},
          ],
        ),
        dayId: '2026-09-16',
        algoVersion: kAlgoVersion + 1,
      );
      night = await repository.readNightSignals(day);
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.value),
        [54, null, 52],
      );
      expect(night.signal(NightSignalKind.pulse).partial, isTrue);

      await save(
        payload(
          pulse: [
            {'t': sec(at), 'v': 61},
            {'t': sec(at) + 60, 'v': 60},
            {'t': sec(at) + 120, 'v': 59},
          ],
        ),
        dayId: previous,
      );
      night = await repository.readNightSignals(day);
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.value),
        [54, null, 52, 61, 60, 59],
      );
    },
  );

  test(
    'duplicate timestamps keep one agreed value and retain a null at conflicts',
    () async {
      await save(
        payload(
          respiration: [
            {'t': sec(start) + 300, 'v': 14.2},
            {'t': sec(start) + 420, 'v': 15.0},
            {'t': sec(start) + 540, 'v': 16.0},
          ],
        ),
      );
      await save(
        payload(
          pulse: [
            {'t': sec(start), 'v': 54},
            {'t': sec(start) + 60, 'v': null},
            {'t': sec(start) + 120, 'v': 99},
            {'t': sec(start) + 180, 'v': 47},
          ],
          respiration: [
            {'t': sec(start) + 300, 'v': 14.2},
            {'t': sec(start) + 420, 'v': 99.0},
            {'t': sec(start) + 540, 'v': 16.0},
            {'t': sec(start) + 900, 'v': 11.0},
          ],
        ),
        dayId: previous,
      );
      final night = await repository.readNightSignals(day);
      final pulse = night.signal(NightSignalKind.pulse);
      expect(pulse.readings.map((p) => p.value), [54, null, null, 47]);
      expect(pulse.readings[2].at, start.add(const Duration(seconds: 120)));
      final respiration = night.signal(NightSignalKind.respiration);
      expect(respiration.readings.map((p) => p.value), [14.2, null, 16.0, 11.0]);
      expect(
        respiration.readings[1].at,
        start.add(const Duration(seconds: 420)),
      );
      expect(
        respiration.readings[2].at.difference(respiration.readings[0].at) <
            respiration.maxConnectingGap!,
        isTrue,
      );
      expect(pulse.partial, isTrue);
    },
  );

  test(
    'a corrupt neighbor stays partial and a corrupt selected night stays retryable',
    () async {
      await save(payload());
      await save(payload(), dayId: previous, payloadJson: 'not-json');
      final night = await repository.readNightSignals(day);
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.value),
        [54, null, 52],
      );
      expect(night.signal(NightSignalKind.pulse).partial, isTrue);
      await save(
        payload(
          pulse: [
            {'t': sec(start) + 180, 'v': 47},
            {'t': sec(start) + 240, 'v': 46},
            {'t': sec(start) + 300, 'v': 45},
          ],
        ),
        dayId: previous,
      );
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

  test(
    'a pending neighbor correction withholds only that bundle',
    () async {
      await save(payload());
      await save(
        payload(
          pulse: [
            {'t': sec(start) + 180, 'v': 47},
            {'t': sec(start) + 240, 'v': 46},
            {'t': sec(start) + 300, 'v': 45},
          ],
        ),
        dayId: previous,
      );
      final draft = SleepDraft(
        id: 'previous-night',
        day: previous,
        onset: DateTime.parse('2026-09-13T23:10:00+02:00'),
        wake: DateTime.parse('2026-09-14T06:54:00+02:00'),
        recordingTimezone: 'Europe/Berlin',
      );
      await repository.saveDraft(draft);
      final saved = await repository.saveCorrection(draft);
      var night = await repository.readNightSignals(day);
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.value),
        [54, null, 52],
      );
      expect(night.signal(NightSignalKind.pulse).partial, isTrue);
      expect(night.processing, isFalse);
      await LocalDb.updateOpenBandCalculationJob(
        dayId: previous,
        correctionId: saved.id,
        revision: saved.revision,
        status: 'failed',
      );
      night = await repository.readNightSignals(day);
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.value),
        [54, null, 52],
      );
      await LocalDb.updateOpenBandCalculationJob(
        dayId: previous,
        correctionId: saved.id,
        revision: saved.revision,
        status: 'complete',
      );
      night = await repository.readNightSignals(day);
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.value),
        [54, null, 52, 47, 46, 45],
      );
    },
  );

  test(
    'an unplaceable corrupt array item refuses that source curve',
    () async {
      await save(
        payload(
          pulse: [
            {'t': sec(start), 'v': 54},
            'junk',
            {'t': sec(start) + 60, 'v': 52},
          ],
        ),
      );
      await save(
        payload(
          pulse: [
            {'t': sec(start) + 180, 'v': 47},
            {'t': sec(start) + 240, 'v': 46},
            {'t': sec(start) + 300, 'v': 45},
          ],
        ),
        dayId: previous,
      );
      var night = await repository.readNightSignals(day);
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.value),
        [47, 46, 45],
      );
      await save(
        payload(
          pulse: [
            {'t': sec(start), 'v': 54},
            {'t': 'nope', 'v': 50},
            {'t': sec(start) + 60, 'v': 52},
          ],
        ),
      );
      night = await repository.readNightSignals(day);
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.value),
        [47, 46, 45],
      );
    },
  );

  test(
    'a usable timestamp with a bad value stays a null point',
    () async {
      await save(
        payload(
          pulse: [
            {'t': sec(start), 'v': 54},
            {'t': sec(start) + 30, 'v': 'bad'},
            {'t': sec(start) + 60, 'v': 52},
          ],
        ),
        partial: false,
      );
      final night = await repository.readNightSignals(day);
      final pulse = night.signal(NightSignalKind.pulse);
      expect(pulse.readings.map((p) => p.value), [54, null, 52]);
      expect(
        pulse.readings[1].at,
        start.add(const Duration(seconds: 30)),
      );
      expect(pulse.partial, isTrue);
    },
  );

  test(
    'calendar curves stay partial when the stored row is not',
    () async {
      await save(
        payload(
          hrv: {
            'origin_ms': start.millisecondsSinceEpoch,
            'value': {
              'bins': [
                {'t': 0, 'rmssd_ms': 60, 'lo_ms': 55, 'hi_ms': 65},
                {'t': 3600, 'rmssd_ms': 62, 'lo_ms': 58, 'hi_ms': 66},
              ],
            },
          },
        ),
        partial: false,
      );
      final night = await repository.readNightSignals(day);
      expect(night.signal(NightSignalKind.pulse).partial, isTrue);
      expect(night.signal(NightSignalKind.hrv).partial, isFalse);
    },
  );

  test(
    'skipped rows omit that bundle without substituting its samples',
    () async {
      await save(payload());
      await save(
        payload(
          pulse: [
            {'t': sec(start) + 360, 'v': 41},
            {'t': sec(start) + 420, 'v': 40},
            {'t': sec(start) + 480, 'v': 39},
          ],
        ),
        dayId: previous,
        skipped: true,
      );
      var night = await repository.readNightSignals(day);
      expect(
        night.signal(NightSignalKind.pulse).readings.map((p) => p.value),
        [54, null, 52],
      );
      await save(payload(), skipped: true);
      night = await repository.readNightSignals(day);
      expect(night.window, isNull);
      expect(night.series, isEmpty);
    },
  );

  test('an oversized stored night window is a retryable error', () async {
    await save(
      payload(
        windowStart: DateTime.utc(2026, 1, 1),
        windowEnd: DateTime.utc(2026, 9, 15),
      ),
    );
    await expectLater(repository.readNightSignals(day), throwsFormatException);
  });
}
