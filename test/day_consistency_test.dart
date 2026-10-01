import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/compute/strain_backfill.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/openband/domain.dart';
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
      },
      'steps': {'value': second ? 9000 : 3000},
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
        'hypnogram': [
          {'start': onset ~/ 1000, 'end': wake ~/ 1000, 'stage': 'light'},
        ],
      },
    }),
    windowJson: '{}',
    partial: partial,
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
const _processing = {
  'sleep headline/history': [null, null],
  'recovery headline/history': [null, null],
  'strain headline/history': [null, null],
  'steps headline/readTrend': [null, null],
};

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
    'DUP-2 partial row keeps readDay and public history/trend on one complete result',
    () async {
      await _putCalculation(second: false, algo: kAlgoVersion - 1);
      await _putCalculation(second: true, partial: true);
      expect(
        await _screenValues(repo),
        anyOf(_completeA, _processing),
        reason:
            'Partial recalculation must show the previous complete result or explicit gaps throughout.',
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
}
