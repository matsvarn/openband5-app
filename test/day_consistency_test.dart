import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show DerivationEngine, kAlgoVersion;
import 'package:openstrap_edge/compute/strain_backfill.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _day = '2026-09-15';
final _onsetA = DateTime.utc(2026, 9, 14, 22).millisecondsSinceEpoch;
final _onsetB = DateTime.utc(2026, 9, 14, 23).millisecondsSinceEpoch;

Future<void> _putCalculation({
  required bool second,
  int algo = kAlgoVersion,
  bool partial = false,
  bool skipped = false,
}) async {
  final onset = second ? _onsetB : _onsetA;
  final minutes = second ? 420 : 360;
  final wake = onset + minutes * 60000;
  await LocalDb.putDayResult(
    dayId: _day,
    algoVersion: algo,
    payloadJson: jsonEncode({
      'source': second ? 'whoop_export' : 'band',
      'sleep_source': 'auto',
      'scalars': {
        'readiness': second ? 80 : 60,
        'strain': second ? 9 : 4,
        'rmssd': second ? 70 : 40,
        'rhr': second ? 55 : 50,
        'resp_rate': second ? 16 : 14,
        'skin_temp_z': second ? 1.5 : .5,
        'sol_min': second ? 20 : 10,
      },
      'steps': {'value': second ? 9000 : 3000},
      'baselines': {
        'hrv': {'baseline': second ? 65 : 35, 'spread': 5, 'status': 'trusted'},
      },
      'sleep': {
        'window': {
          'value': {
            'onset_ms': onset,
            'offset_ms': wake,
            'spt_sec': minutes * 60,
          },
        },
        'accounting': {
          'value': {
            'tst_sec': minutes * 60,
            'waso_sec': 0,
            'light_sec': minutes * 60,
            'rem_sec': 0,
            'deep_sec': 0,
          },
        },
      },
      'series': {
        'hr_curve': [
          {'t': onset ~/ 1000, 'v': second ? 75 : 60},
        ],
        'hypnogram': [
          {'start': onset ~/ 1000, 'end': wake ~/ 1000, 'stage': 'light'},
        ],
      },
    }),
    windowJson: '{}',
    partial: partial,
    skipped: skipped,
    rmssd: second ? 70 : 40,
    rhr: second ? 55 : 50,
    readiness: second ? 80 : 60,
    source: second ? 'whoop_export' : 'band',
    series: {
      'tst_min': minutes.toDouble(),
      'readiness': second ? 80 : 60,
      'strain': second ? 9 : 4,
      'steps': second ? 9000 : 3000,
      'rmssd': second ? 70 : 40,
      'rhr': second ? 55 : 50,
    },
  );
  final db = await LocalDb.instance;
  await db.update(
    'day_result',
    {'computed_at': second ? 2000 : 1000},
    where: 'day_id = ? AND algo_version = ?',
    whereArgs: [_day, algo],
  );
}

// readDay starts all four reads with Future.wait. Hold each at the same
// boundary until the replacement is committed, so the interleaving is exact.
// A reader that stops reselecting the row will simply not invoke this seam.
class _ReplacingRepository extends LocalRepositoryImpl {
  _ReplacingRepository() : super(getProfileMap: () => null);

  Future<void>? _replacement;
  Future<void> _commitReplacement() =>
      _replacement ??= _putCalculation(second: true);

  @override
  Future<Map<String, dynamic>> getDaySleep(String date) async {
    await _commitReplacement();
    return super.getDaySleep(date);
  }

  @override
  Future<Map<String, dynamic>> getDayHeart(String date) async {
    await _commitReplacement();
    return super.getDayHeart(date);
  }

  @override
  Future<Map<String, dynamic>> getDayStrain(String date) async {
    await _commitReplacement();
    return super.getDayStrain(date);
  }

  @override
  Future<Map<String, dynamic>> getDaySteps(String date) async {
    await _commitReplacement();
    return super.getDaySteps(date);
  }
}

Map<String, Object?> _fingerprint(OpenBandDay day) => {
  'duration': day.sleep.duration.value,
  'onset': day.sleep.onset?.millisecondsSinceEpoch,
  'wake': day.sleep.wake?.millisecondsSinceEpoch,
  'bed': day.sleep.bedMinutes,
  'awake': day.sleep.awakeMinutes,
  'light': day.sleep.lightMinutes,
  'rem': day.sleep.remMinutes,
  'deep': day.sleep.deepMinutes,
  'segments': [
    for (final s in day.sleep.segments)
      [s.start.millisecondsSinceEpoch, s.end.millisecondsSinceEpoch, s.stage],
  ],
  'history': day.sleep.history.singleWhere((p) => p.day == _day).minutes,
  'source': day.sleep.source,
  'recovery': day.recovery.value,
  'strain': day.strain.value,
  'steps': day.steps.value,
  'hrv': day.hrv.value,
  'rhr': day.restingHr.value,
  'resp': day.respiration.value,
  'temperature': day.skinTemperature.value,
  'calculatedAt': day.calculatedAt?.millisecondsSinceEpoch,
};

Map<String, Object?> _expectedCalculation(bool second) {
  final onset = second ? _onsetB : _onsetA;
  final minutes = second ? 420 : 360;
  final wake = onset + minutes * 60000;
  return {
    'duration': minutes.toDouble(),
    'onset': onset,
    'wake': wake,
    'bed': minutes.toDouble(),
    'awake': 0.0,
    'light': minutes.toDouble(),
    'rem': 0.0,
    'deep': 0.0,
    'segments': [
      [onset, wake, NightStage.light],
    ],
    'history': minutes.toDouble(),
    'source': second ? 'whoop_export' : 'band',
    'recovery': second ? 80.0 : 60.0,
    'strain': second ? 9.0 : 4.0,
    'steps': second ? 9000.0 : 3000.0,
    'hrv': second ? 70.0 : 40.0,
    'rhr': second ? 55.0 : 50.0,
    'resp': second ? 16.0 : 14.0,
    'temperature': second ? 1.5 : .5,
    'calculatedAt': second ? 2000 : 1000,
  };
}

Future<Map<String, List<double?>>> _screenValues(
  LocalOpenBandRepository repo,
) async {
  final day = await repo.readDay(_day);
  final sleepHistory = await repo.readMetricHistory(
    MetricKey.sleepDuration,
    _day,
    7,
  );
  final recoveryHistory = await repo.readMetricHistory(
    MetricKey.recovery,
    _day,
    7,
  );
  final strainHistory = await repo.readMetricHistory(MetricKey.strain, _day, 7);
  final stepsTrend = await repo.readTrend(G3Metric.steps, _day, 7);
  return {
    'sleep headline/history': [
      day.sleep.duration.value,
      sleepHistory.last.value,
    ],
    'recovery headline/history': [
      day.recovery.value,
      recoveryHistory.last.value,
    ],
    'strain headline/history': [day.strain.value, strainHistory.last.value],
    'steps headline/readTrend': [day.steps.value, stepsTrend.points.last.value],
  };
}

const _completeA = {
  'sleep headline/history': [360.0, 360.0],
  'recovery headline/history': [60.0, 60.0],
  'strain headline/history': [4.0, 4.0],
  'steps headline/readTrend': [3000.0, 3000.0],
};
const _completeB = {
  'sleep headline/history': [420.0, 420.0],
  'recovery headline/history': [80.0, 80.0],
  'strain headline/history': [9.0, 9.0],
  'steps headline/readTrend': [9000.0, 9000.0],
};

// Complete calculations with alternating measured and absent optional fields.
// Explicit NULL series entries exercise metricSeries's historical SQL filter.
Future<void> _putOptionalHistoryFixture() async {
  for (var offset = 0; offset < 21; offset++) {
    final day = g3DaysEnding(_day, offset + 1).first;
    final measured = offset.isEven;
    final values = <String, double?>{
      'readiness': measured ? 60 + offset.toDouble() : null,
      'strain': measured ? 4 + offset / 10 : null,
      'steps': measured ? 1000 + offset.toDouble() : null,
      'tst_min': measured ? 400 + offset.toDouble() : null,
      'rmssd': measured ? 40 + offset.toDouble() : null,
      'rhr': measured ? 50 + offset.toDouble() : null,
      'resp_rate': measured ? 14 + offset / 10 : null,
      'skin_temp_z': measured ? offset / 10 : null,
      'sol_min': null,
    };
    await LocalDb.putDayResult(
      dayId: day,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({
        'source': 'band',
        'sleep_source': 'auto',
        'scalars': values,
        'steps': {'value': values['steps']},
        'sleep': {
          'accounting': {
            'value': {
              'tst_sec': values['tst_min'] == null
                  ? null
                  : values['tst_min']! * 60,
            },
          },
        },
        'baselines': {
          'recovery': {'baseline': 65, 'spread': 4, 'status': 'trusted'},
        },
      }),
      windowJson: '{}',
      source: 'band',
      readiness: values['readiness'],
      rmssd: values['rmssd'],
      rhr: values['rhr'],
      series: values,
    );
  }
}

Future<List<MetricPoint>> _legacyCalendarPoints(String key, int nights) async {
  final rows = await LocalDb.metricSeries(key);
  expect(rows.every((row) => row['value'] != null), isTrue);
  final byDay = {
    for (final row in rows)
      row['date'] as String: (row['value'] as num).toDouble(),
  };
  return [
    for (final day in g3DaysEnding(_day, nights))
      MetricPoint(day, byDay[day]),
  ];
}

List<Object?> _points(List<MetricPoint> points) => [
  for (final point in points) [point.day, point.value, point.partial],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory scratch;
  late AppState app;
  late LocalOpenBandRepository repo;
  late String originalDbName;
  late String originalDbPath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    originalDbName = LocalDb.dbName;
    originalDbPath = await databaseFactory.getDatabasesPath();
    scratch = Directory.systemTemp.createTempSync('ob5-day-consistency-');
    await databaseFactory.setDatabasesPath(scratch.path);
  });
  setUp(() async {
    await LocalDb.close();
    LocalDb.dbName = 'synthetic.db';
    await databaseFactory.deleteDatabase('${scratch.path}/synthetic.db');
    app = AppState.forTesting();
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    repo = LocalOpenBandRepository(app);
  });
  tearDown(() async {
    app.dispose();
    await LocalDb.close();
  });
  tearDownAll(() async {
    LocalDb.dbName = originalDbName;
    await databaseFactory.setDatabasesPath(originalDbPath);
    scratch.deleteSync(recursive: true);
  });

  group('complete optional fields retain filtered-series behavior', () {
    setUp(_putOptionalHistoryFixture);

    test('readDay keeps the latest eight measured sleep nights', () async {
      final oldRows = (await LocalDb.metricSeries(
        'tst_min',
      )).where((row) => (row['date'] as String).compareTo(_day) <= 0).toList();
      expect(oldRows.length, 11);
      final expected = [
        for (final row in oldRows.skip(oldRows.length - 8))
          (
            day: row['date'] as String,
            minutes: (row['value'] as num).toDouble(),
          ),
      ];
      final actual = await repo.readDay(_day);
      expect(actual.sleep.history, expected);
      expect(actual.sleep.history.length, 8);
      expect(
        actual.sleep.history.every((point) => point.minutes != null),
        isTrue,
      );
    });

    test(
      'readDay still includes missing partial and skipped sleep gaps',
      () async {
        final skippedDay = g3DaysEnding(_day, 2).first;
        for (final day in [_day, skippedDay]) {
          await LocalDb.putDayResult(
            dayId: day,
            algoVersion: kAlgoVersion,
            payloadJson: '{"scalars":{},"sleep_source":"auto"}',
            windowJson: '{}',
            partial: day == _day,
            skipped: day == skippedDay,
          );
        }
        final history = (await repo.readDay(_day)).sleep.history;
        expect(history.length, 8);
        expect(
          history
              .where((point) => point.minutes == null)
              .map((point) => point.day),
          [skippedDay, _day],
        );
      },
    );

    test('readMetricHistory keeps calendar gaps and night counts', () async {
      for (final key in MetricKey.values) {
        final expected = await _legacyCalendarPoints(key.series, 7);
        expect(
          _points(await repo.readMetricHistory(key, _day, 7)),
          _points(expected),
          reason: key.name,
        );
        if ([
          MetricKey.hrv,
          MetricKey.restingHr,
          MetricKey.respiration,
          MetricKey.skinTemperature,
        ].contains(key)) {
          final detail = await repo.readNightScalarDetail(key, _day, 7);
          expect(detail.counts.compared, 4, reason: key.name);
        }
      }
    });

    test(
      'readTrend including steps keeps dated gaps and minimum-count gate',
      () async {
        for (final metric in G3Metric.values) {
          final key = switch (metric) {
            G3Metric.steps => 'steps',
            G3Metric.sleepMinutes => 'tst_min',
            G3Metric.recovery => 'readiness',
            G3Metric.hrv => 'rmssd',
            G3Metric.rhr => 'rhr',
            G3Metric.respRate => 'resp_rate',
            G3Metric.skinTempZ => 'skin_temp_z',
            G3Metric.strain => 'strain',
          };
          final expected = await _legacyCalendarPoints(key, 7);
          final trend = await repo.readTrend(metric, _day, 7);
          expect(_points(trend.points), _points(expected), reason: metric.name);
          expect(trend.valueCount, 4, reason: metric.name);
          expect(trend.insufficient, 3, reason: metric.name);
        }
      },
    );

    test(
      'readWeekStrip keeps seven positions and absent comparison flags',
      () async {
        for (final entry in {
          G3Metric.recovery: 'readiness',
          G3Metric.sleepMinutes: 'tst_min',
          G3Metric.strain: 'strain',
        }.entries) {
          final expected = await _legacyCalendarPoints(entry.value, 7);
          final strip = await repo.readWeekStrip(entry.key, _day);
          expect(
            [
              for (final point in strip.days) [point.day, point.value],
            ],
            [
              for (final point in expected) [point.day, point.value],
            ],
            reason: entry.key.name,
          );
          expect(strip.days.length, 7);
          expect(
            strip.days
                .where((point) => point.value == null)
                .every((point) => point.outOfRange == null),
            isTrue,
          );
        }
      },
    );

    test('readWeeklyLoad keeps daily gaps and stored load counts', () async {
      await LocalDb.putBaseline(
        'crossday',
        jsonEncode({
          'built_for_day': _day,
          'algo_version': kAlgoVersion,
          'load': {
            'value': {'ctl': 8, 'atl': 9},
            'note': 'have=4,need=7',
          },
        }),
      );
      final expected = await _legacyCalendarPoints('strain', 7);
      final load = await repo.readWeeklyLoad(_day);
      expect(_points(load.days), _points(expected));
      expect(load.daysHave, 4);
      expect(load.daysNeed, 7);
      expect(load.ctl, 8);
      expect(load.atl, 9);
    });
  });

  test(
    'control: each complete calculation reads consistently in isolation',
    () async {
      await _putCalculation(second: false);
      expect(
        _fingerprint(await repo.readDay(_day)),
        _expectedCalculation(false),
      );
      await _putCalculation(second: true);
      expect(
        _fingerprint(await repo.readDay(_day)),
        _expectedCalculation(true),
      );
    },
  );

  test(
    'DUP-1 readDay retains one calculation across a committed replacement',
    () async {
      await _putCalculation(second: false);
      app.repo = _ReplacingRepository();
      expect(
        _fingerprint(await repo.readDay(_day)),
        anyOf(_expectedCalculation(false), _expectedCalculation(true)),
        reason: 'A day may expose calculation A or B, never fields from both.',
      );
    },
  );

  test(
    'DUP-2 partial row supplies its valid scalars to readDay and history/trend',
    () async {
      await _putCalculation(second: false, algo: kAlgoVersion - 1);
      await _putCalculation(second: true, partial: true);
      expect(
        await _screenValues(repo),
        _completeB,
        reason: 'A finished partial row publishes its own scalars throughout.',
      );
    },
  );

  test(
    'DUP-2 series-only strain rewrite cannot change readMetricHistory independently of readDay',
    () async {
      await _putCalculation(second: false);
      await LocalDb.putMetricSeriesValue(_day, 'strain', 12);
      final day = await repo.readDay(_day);
      final history = await repo.readMetricHistory(MetricKey.strain, _day, 7);
      expect(
        [day.strain.value, history.last.value],
        [4.0, 4.0],
        reason:
            'The strain detail history must use the same published calculation as its headline.',
      );
    },
  );

  test(
    'DUP-2 newer-build series cannot leak into public history or steps trend',
    () async {
      await _putCalculation(second: false);
      await _putCalculation(second: true, algo: kAlgoVersion + 1);
      expect(
        await _screenValues(repo),
        _completeA,
        reason:
            'Every day point must obey the same algorithm ceiling as readDay.',
      );
    },
  );

  test(
    'DUP-2 readWeekStrip uses the served sleep calculation after a series-only import',
    () async {
      await _putCalculation(second: false);
      await LocalDb.putMetricSeriesValue(_day, 'tst_min', 500);
      final day = await repo.readDay(_day);
      final strip = await repo.readWeekStrip(G3Metric.sleepMinutes, _day);
      expect(
        [
          day.sleep.duration.value,
          day.sleep.history.last.minutes,
          strip.days.last.value,
        ],
        [360.0, 360.0, 360.0],
        reason:
            'The embedded sleep history and Heute week strip must agree with the night headline.',
      );
    },
  );

  test(
    'protected: actual complete-row strain backfill updates headline and history together',
    () async {
      await _putCalculation(second: false, algo: kAlgoVersion - 1);
      final db = await LocalDb.instance;
      final row = (await LocalDb.dayResult(_day))!;
      final payload =
          jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
      (payload['series'] as Map)['strain_curve'] = [
        for (var i = 0; i < 600; i++) {'t': i * 60, 'v': 4},
      ];
      await LocalDb.putDayResult(
        dayId: _day,
        algoVersion: kAlgoVersion - 1,
        payloadJson: jsonEncode(payload),
        windowJson: '{}',
        series: const {'strain': 4, 'trimp': 100, 'quiet_waking_hrr': .1},
        source: 'band',
      );
      // Move the data edge beyond retention so this old day is eligible.
      await LocalDb.putMetricSeriesValue('2026-09-25', 'strain', 5);
      final result = await backfillStrainScale(female: false, force: true);
      expect(result.bundleDays, 1);
      expect(result.seriesDays, 1);
      expect((await LocalDb.dayResult(_day))!['algo_version'], kAlgoVersion);
      final day = await repo.readDay(_day);
      final history = await repo.readMetricHistory(MetricKey.strain, _day, 7);
      expect(day.strain.value, isNot(4));
      expect(history.last.value, day.strain.value);
      expect(
        await db.query('day_result', where: 'day_id = ?', whereArgs: [_day]),
        hasLength(2),
      );
    },
  );

  test(
    'protected: nightly HRV history ignores newer-build metric_series',
    () async {
      await _putCalculation(second: false);
      await _putCalculation(second: true, algo: kAlgoVersion + 1);
      final day = await repo.readDay(_day);
      final history = await repo.readMetricHistory(MetricKey.hrv, _day, 7);
      expect([day.hrv.value, history.last.value], [40.0, 40.0]);
    },
  );

  test('controller refresh listener reads await the new day pin', () async {
    await _putCalculation(second: false);
    final controller = OpenBandController(repository: repo, initialDay: _day);
    addTearDown(controller.dispose);
    await controller.refresh();
    await _putCalculation(second: true);
    var loadedRequest = controller.refreshRequest;
    late Future<G3WeekStrip> strip;
    late Future<G3Baseline> range;
    late Future<G3Trend> hrvTrend;
    controller.addListener(() {
      if (loadedRequest == controller.refreshRequest) return;
      loadedRequest = controller.refreshRequest;
      strip = repo.readWeekStrip(G3Metric.sleepMinutes, controller.selectedDay);
      range = repo.readPersonalRange(G3Metric.hrv, controller.selectedDay);
      hrvTrend = repo.readTrend(G3Metric.hrv, controller.selectedDay, 7);
    });
    await controller.refresh();
    expect(controller.loadError, isNull);
    expect(controller.day!.sleep.duration.value, 420);
    expect((await strip).days.last.value, controller.day!.sleep.duration.value);
    expect((await range).range?.median, controller.day!.hrv.baseline);
    expect((await range).range?.median, 65);
    expect((await hrvTrend).points.last.value, controller.day!.hrv.value);
  });

  test(
    'night reads started before readDay in the same turn await its pin',
    () async {
      await _putCalculation(second: false);
      await repo.readDay(_day);
      await _putCalculation(second: true);
      final signals = repo.readNightSignals(_day);
      final day = repo.readDay(_day);
      final range = repo.readPersonalRange(G3Metric.hrv, _day);
      expect((await day).hrv.value, 70);
      expect((await signals).processing, isFalse);
      expect(
        (await signals).signal(NightSignalKind.pulse).readings.single.value,
        75,
      );
      expect((await range).range?.median, 65);
    },
  );

  test(
    'failed controller day refresh releases dependent readers and can retry',
    () async {
      await _putCalculation(second: false);
      final controller = OpenBandController(repository: repo, initialDay: _day);
      addTearDown(controller.dispose);
      await controller.refresh();
      await _putCalculation(second: true);
      await (await LocalDb.instance).update(
        'day_result',
        {'payload_json': '{'},
        where: 'day_id = ? AND algo_version = ?',
        whereArgs: [_day, kAlgoVersion],
      );
      var loadedRequest = controller.refreshRequest;
      late Future<G3WeekStrip> strip;
      late Future<G3Baseline> range;
      controller.addListener(() {
        if (loadedRequest == controller.refreshRequest) return;
        loadedRequest = controller.refreshRequest;
        strip = repo.readWeekStrip(
          G3Metric.sleepMinutes,
          controller.selectedDay,
        );
        range = repo.readPersonalRange(G3Metric.hrv, controller.selectedDay);
      });
      await controller.refresh();
      expect(controller.loadError, isA<FormatException>());
      expect((await strip).days.last.value, isNull);
      expect((await range).range, isNull);
      await _putCalculation(second: true);
      await controller.refresh();
      expect(controller.loadError, isNull);
      expect((await strip).days.last.value, 420);
      expect((await range).range?.median, 65);
    },
  );

  for (final retained in [true, false]) {
    test(
      'cross-call ${retained ? "retained" : "replaced"} pin protects week/trend/history/signals/range until readDay',
      () async {
        await _putCalculation(
          second: false,
          algo: retained ? kAlgoVersion - 1 : kAlgoVersion,
        );
        await repo.readDay(_day);
        await _putCalculation(second: true);
        final oldOrGap = retained ? 360.0 : null;
        expect(
          (await repo.readWeekStrip(
            G3Metric.sleepMinutes,
            _day,
          )).days.last.value,
          oldOrGap,
        );
        expect(
          (await repo.readTrend(G3Metric.steps, _day, 7)).points.last.value,
          retained ? 3000 : null,
        );
        expect(
          (await repo.readMetricHistory(MetricKey.strain, _day, 7)).last.value,
          retained ? 4 : null,
        );
        expect(
          (await repo.readMetricHistory(MetricKey.hrv, _day, 7)).last.value,
          retained ? 40 : null,
        );
        final signals = await repo.readNightSignals(_day);
        expect(signals.signal(NightSignalKind.pulse).readings, isEmpty);
        if (!retained) expect(signals.processing, isTrue);
        expect(
          (await repo.readPersonalRange(G3Metric.hrv, _day)).range,
          isNull,
        );
        expect(
          _fingerprint(await repo.readDay(_day)),
          _expectedCalculation(true),
        );
        expect(
          (await repo.readWeekStrip(
            G3Metric.sleepMinutes,
            _day,
          )).days.last.value,
          420,
        );
        expect(
          (await repo.readTrend(G3Metric.steps, _day, 7)).points.last.value,
          9000,
        );
        expect(
          (await repo.readMetricHistory(MetricKey.strain, _day, 7)).last.value,
          9,
        );
        expect(
          (await repo.readMetricHistory(MetricKey.hrv, _day, 7)).last.value,
          70,
        );
        expect(
          (await repo.readNightSignals(
            _day,
          )).signal(NightSignalKind.pulse).readings.single.value,
          75,
        );
        expect(
          (await repo.readPersonalRange(G3Metric.hrv, _day)).range!.median,
          65,
        );
      },
    );
  }

  test('a missing pinned day remains a gap until the next readDay', () async {
    await repo.readDay(_day);
    await _putCalculation(second: true);
    expect(
      (await repo.readMetricHistory(MetricKey.recovery, _day, 7)).last.value,
      isNull,
    );
    expect(
      (await repo.readMetricHistory(MetricKey.hrv, _day, 7)).last.value,
      isNull,
    );
    expect((await repo.readNightSignals(_day)).window, isNull);
    await repo.readDay(_day);
    expect(
      (await repo.readMetricHistory(MetricKey.recovery, _day, 7)).last.value,
      80,
    );
  });

  test(
    'failed readDay does not re-pin a still-visible older calculation',
    () async {
      await _putCalculation(second: false);
      await repo.readDay(_day);
      await _putCalculation(second: true);
      final db = await LocalDb.instance;
      final row = (await LocalDb.dayResult(_day))!;
      final payload =
          jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
      payload['steps'] = {'value': 'unreadable'};
      await db.update(
        'day_result',
        {'payload_json': jsonEncode(payload)},
        where: 'day_id = ?',
        whereArgs: [_day],
      );
      await expectLater(repo.readDay(_day), throwsA(isA<TypeError>()));
      expect(
        (await repo.readMetricHistory(MetricKey.strain, _day, 7)).last.value,
        isNull,
      );
    },
  );

  test(
    'other trend days use current served rows, independent of older pins',
    () async {
      await _putCalculation(second: false);
      await repo.readDay(_day);
      await _putCalculation(second: true);
      final points = await repo.readMetricHistory(
        MetricKey.strain,
        '2026-09-16',
        7,
      );
      expect(points.singleWhere((p) => p.day == _day).value, 9);
    },
  );

  test(
    'skipped served rows suppress all calculated headlines and series',
    () async {
      await _putCalculation(second: false, algo: kAlgoVersion - 1);
      await _putCalculation(second: true, skipped: true);
      final values = await _screenValues(repo);
      expect(values.values.expand((v) => v), everyElement(isNull));
      for (final key in LocalDb.servedDaySeriesSources.keys) {
        expect(
          (await LocalDb.servedDaySeries(key)).single['value'],
          isNull,
          reason: key,
        );
      }
      expect(
        (await repo.readMetricHistory(MetricKey.hrv, _day, 7)).last.value,
        isNull,
      );
      expect((await repo.sleepDays()), isNot(contains(_day)));
      expect((await repo.readNightSignals(_day)).window, isNull);
    },
  );

  test(
    'partial missing fields are gaps, never the previous series values',
    () async {
      await _putCalculation(second: false, algo: kAlgoVersion - 1);
      await LocalDb.putDayResult(
        dayId: _day,
        algoVersion: kAlgoVersion,
        payloadJson: '{"scalars":{"readiness":81}}',
        windowJson: '{}',
        partial: true,
      );
      final values = await _screenValues(repo);
      expect(values['recovery headline/history'], [81.0, 81.0]);
      for (final key in [
        'sleep headline/history',
        'strain headline/history',
        'steps headline/readTrend',
      ]) {
        expect(values[key], [null, null], reason: key);
      }
    },
  );

  test(
    'served projection preserves every explicit source, rounding and identity',
    () async {
      await _putCalculation(second: false);
      final db = await LocalDb.instance;
      final row = (await LocalDb.dayResult(_day))!;
      final payload =
          jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
      ((payload['sleep'] as Map)['accounting']['value'] as Map)['tst_sec'] =
          21630;
      await db.update(
        'day_result',
        {'payload_json': jsonEncode(payload)},
        where: 'day_id = ?',
        whereArgs: [_day],
      );
      const values = {
        'readiness': 60,
        'strain': 4,
        'steps': 3000,
        'tst_min': 361,
        'rmssd': 40,
        'rhr': 50,
        'resp_rate': 14,
        'skin_temp_z': .5,
        'sol_min': 10,
      };
      for (final e in values.entries) {
        final point = (await LocalDb.servedDaySeries(e.key)).single;
        expect(point['value'], e.value, reason: e.key);
        expect(point['date'], _day);
        expect(point['algo_version'], kAlgoVersion);
        expect(point['computed_at'], 1000);
      }
      expect((await repo.readDay(_day)).sleep.duration.value, 361);
    },
  );

  test(
    'new crossday artifacts cannot be attached to an older pinned day',
    () async {
      await _putCalculation(second: false);
      await repo.saveSleepGoal(_day, 450);
      await repo.readDay(_day);
      await _putCalculation(second: true);
      await LocalDb.putBaseline(
        'crossday',
        jsonEncode({
          'built_for_day': _day,
          'algo_version': kAlgoVersion,
          'load': {
            'value': {'ctl': 8, 'atl': 10},
          },
          'regularity': {
            'value': {'sri': 75, 'days': 14},
          },
          'sleep_debt': {
            'value': {'osd_hours': 8, 'has_free_night': true},
          },
        }),
      );
      expect((await repo.readWeeklyLoad(_day)).ctl, isNull);
      expect((await repo.readSleepPlus(_day)).regularity.value, isNull);
      expect((await repo.readSleepGoal(_day)).weekendEstimate, isNull);
      expect((await repo.readSleepGoal(_day)).targetMinutes, 450);
      expect(
        (await repo.readSleepPlan(_day, now: DateTime(2026, 9, 15, 12))).status,
        SleepPlanStatus.stale,
      );
      await repo.readDay(_day);
      expect((await repo.readWeeklyLoad(_day)).ctl, 8);
      expect((await repo.readSleepPlus(_day)).regularity.value, 75);
    },
  );

  test(
    'sleep source falls back to a series stamp only at the served version',
    () async {
      await _putCalculation(second: false);
      final db = await LocalDb.instance;
      final row = (await LocalDb.dayResult(_day))!;
      final payload =
          jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
      payload.remove('source');
      await db.update(
        'day_result',
        {'source': null, 'payload_json': jsonEncode(payload)},
        where: 'day_id = ?',
        whereArgs: [_day],
      );
      await db.update(
        'metric_series_version',
        {'algo_version': kAlgoVersion + 1, 'source': 'foreign'},
        where: 'date = ?',
        whereArgs: [_day],
      );
      expect((await repo.readDay(_day)).sleep.source, 'unknown');
      await db.update(
        'metric_series_version',
        {'algo_version': kAlgoVersion, 'source': 'band'},
        where: 'date = ?',
        whereArgs: [_day],
      );
      expect((await repo.readDay(_day)).sleep.source, 'band');
    },
  );

  test(
    'normally derived complete day has servedDaySeries == metric_series for every UI key',
    () async {
      final db = await LocalDb.instance;
      final start = DateTime(2026, 9, 15).millisecondsSinceEpoch ~/ 1000;
      final batch = db.batch();
      for (var i = 0; i < 12 * 3600; i++) {
        batch.insert('decoded_onehz', {
          'device_id': '',
          'ts_ms': (start + i) * 1000,
          'rec_ts': start + i,
          'counter': i,
          'hr': 60 + i % 3,
          'ax': 0.0,
          'ay': 0.0,
          'az': 1.0,
          'device_family': 'gen4',
        });
      }
      await batch.commit(noResult: true);
      expect(
        await DerivationEngine().run(const PersonalProfile()),
        greaterThanOrEqualTo(1),
      );
      final row = (await LocalDb.dayResult(_day))!;
      expect(row['partial'], 0);
      expect(row['skipped'], 0);
      for (final key in LocalDb.servedDaySeriesSources.keys) {
        final served = (await LocalDb.servedDaySeries(
          key,
          fromDay: _day,
          throughDay: _day,
        )).single;
        final series = (await db.query(
          'metric_series',
          where: 'date = ? AND key = ?',
          whereArgs: [_day, key],
        )).single;
        expect(served['value'], series['value'], reason: key);
      }
    },
  );

  test('servedDaySeries 365-day benchmark and primary-key lookup plan', () async {
    await _putCalculation(second: false);
    final db = await LocalDb.instance;
    final row = (await LocalDb.dayResult(_day))!..remove('date');
    final payload =
        jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
    payload['benchmark_padding'] = List.filled(80000, 'x').join();
    row['payload_json'] = jsonEncode(payload);
    await db.update(
      'day_result',
      {'payload_json': row['payload_json']},
      where: 'day_id = ?',
      whereArgs: [_day],
    );
    final batch = db.batch();
    for (var i = 1; i < 365; i++) {
      final date = DateTime.utc(
        2026,
        9,
        15,
      ).subtract(Duration(days: i)).toIso8601String().substring(0, 10);
      batch.insert('day_result', {...row, 'day_id': date});
    }
    await batch.commit(noResult: true);
    final watch = Stopwatch()..start();
    final points = await LocalDb.servedDaySeries(
      'strain',
      throughDay: _day,
      limitDays: 365,
    );
    watch.stop();
    expect(points, hasLength(365));
    // Informational only: no machine-dependent timing threshold.
    // ignore: avoid_print
    print(
      'servedDaySeries: ${points.length} rows (~80 KB payload each) x ${watch.elapsedMicroseconds / 1000} ms',
    );
    final plan = await db.rawQuery(
      'EXPLAIN QUERY PLAN SELECT r.day_id FROM day_result r WHERE r.day_id <= ? AND r.algo_version = (SELECT MAX(v.algo_version) FROM day_result v WHERE v.day_id = r.day_id AND v.algo_version <= ?)',
      [_day, kAlgoVersion],
    );
    expect(
      plan.map((r) => r['detail']).join(' '),
      contains('sqlite_autoindex_day_result_1'),
    );
  });
}
