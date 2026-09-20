import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _day = '2026-09-15';
const _otherDay = '2026-09-14';

SyntheticOpenBandRepository _synthetic() =>
    SyntheticOpenBandRepository.fromMaps(
      jsonDecode(
            File(
              'docs/openband5/assets/fixtures/day-summary.json',
            ).readAsStringSync(),
          )
          as Map,
      jsonDecode(
            File(
              'docs/openband5/assets/fixtures/sleep-detail.json',
            ).readAsStringSync(),
          )
          as Map,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('water field spec is +/-250 ml bounded at 6000', () {
    final spec = kJournalFieldsByKey['water_ml']!;
    expect(spec.key, 'water_ml');
    expect(spec.kind, JournalFieldKind.dose);
    expect(spec.unit, 'ml');
    expect(spec.step, 250);
    expect(spec.max, 6000);
  });

  group('synthetic', () {
    late SyntheticOpenBandRepository repo;
    setUp(() => repo = _synthetic());
    _contract(() => repo);

    test('failJournalPatch leaves water unchanged so retry can commit', () async {
      repo.failJournalPatch = true;
      await expectLater(
        repo.adjustWater(_day, 250),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'synthetic journal save failure',
          ),
        ),
      );
      expect(
        (await repo.readJournalDay(_day)).metrics.containsKey('water_ml'),
        isFalse,
      );

      repo.failJournalPatch = false;
      expect(await repo.adjustWater(_day, 250), 250);
      final before = await repo.readJournalDay(_day);
      repo.failJournalPatch = true;
      await expectLater(
        repo.adjustWater(_day, 250),
        throwsA(isA<StateError>()),
      );
      final held = await repo.readJournalDay(_day);
      expect(held.metrics['water_ml']!.value, 250);
      expect(
        held.metricUpdatedAt['water_ml'],
        before.metricUpdatedAt['water_ml'],
      );

      repo.failJournalPatch = false;
      expect(await repo.adjustWater(_day, 250), 500);
    });
  });

  group('SQLite', () {
    late AppState app;
    late LocalOpenBandRepository repo;
    late LocalRepositoryImpl store;
    const dbName = 'openband_water_contract_test.db';

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      await LocalDb.close();
      LocalDb.dbName = dbName;
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase('$dir/$dbName');
      app = AppState.forTesting();
      store = LocalRepositoryImpl(getProfileMap: () => app.user);
      app.repo = store;
      repo = LocalOpenBandRepository(app);
    });

    tearDown(() async {
      app.dispose();
      await LocalDb.close();
    });

    _contract(() => repo);

    test('missing is no row; stored zero is a real row', () async {
      expect(await repo.adjustWater(_day, -250), isNull);
      final db = await LocalDb.instance;
      Future<List<Map<String, Object?>>> rows() => db.query(
        'journal_metric',
        where: 'date = ? AND field = ?',
        whereArgs: [_day, 'water_ml'],
      );
      expect(await rows(), isEmpty);

      expect(await repo.adjustWater(_day, 250), 250);
      expect(await rows(), hasLength(1));

      expect(await repo.adjustWater(_day, -250), 0);
      expect((await rows()).single['value'], 0);

      expect(await repo.adjustWater(_day, -250), isNull);
      expect(await rows(), isEmpty);
    });

    test('legacy addJournalMetric returns the committed amount on the same row', () async {
      // LocalRepositoryImpl.addJournalMetric already returns Future<double?>;
      // gesture/UI callers ignore that value. Do not change the method.
      expect(await store.addJournalMetric(_day, 'water_ml', 250), 250);
      expect(await repo.adjustWater(_day, 250), 500);
      expect(await store.addJournalMetric(_day, 'water_ml', -250), 250);
      final written = await LocalDb.journalMetricsForDay(_day);
      expect(written['water_ml']!.value, 250);
    });

    test('reopen returns the committed amount without a follow-up write', () async {
      expect(await repo.adjustWater(_day, 250), 250);
      await LocalDb.close();
      repo = LocalOpenBandRepository(app);
      final snap = await repo.readJournalDay(_day);
      expect(snap.metrics['water_ml']!.value, 250);
      expect(await repo.adjustWater(_day, 250), 500);
    });
  });
}

void _contract(OpenBandRepository Function() repoOf) {
  final spec = kJournalFieldsByKey['water_ml']!;
  final step = spec.step;
  final max = spec.max;

  test('unknown minus stays unknown; unknown plus step is the step', () async {
    final repo = repoOf();
    expect(await repo.adjustWater(_day, -step), isNull);
    expect(
      (await repo.readJournalDay(_day)).metrics.containsKey('water_ml'),
      isFalse,
    );
    expect(await repo.adjustWater(_day, step), step);
    expect((await repo.readJournalDay(_day)).metrics['water_ml']!.value, step);
  });

  test('step down to zero stores zero; zero minus clears', () async {
    final repo = repoOf();
    expect(await repo.adjustWater(_day, step), step);
    expect(await repo.adjustWater(_day, -step), 0);
    final zero = await repo.readJournalDay(_day);
    expect(zero.metrics.containsKey('water_ml'), isTrue);
    expect(zero.metrics['water_ml']!.value, 0);
    expect(await repo.adjustWater(_day, -step), isNull);
    expect(
      (await repo.readJournalDay(_day)).metrics.containsKey('water_ml'),
      isFalse,
    );
  });

  test('fractional values survive a delta and stay unrounded', () async {
    final repo = repoOf();
    await _putMetrics(repo, _day, {
      'water_ml': const JournalMetricValue(100.5),
    });
    expect(await repo.adjustWater(_day, step), 350.5);
    expect((await repo.readJournalDay(_day)).metrics['water_ml']!.value, 350.5);
  });

  test('at_min, siblings, and other days stay put', () async {
    final repo = repoOf();
    await _putMetrics(repo, _day, {
      'water_ml': const JournalMetricValue(250, atMinuteOfDay: 480),
      'mood': const JournalMetricValue(3, atMinuteOfDay: 510),
      'caffeine_mg': const JournalMetricValue(180, atMinuteOfDay: 855),
    });
    await _putMetrics(repo, _otherDay, {
      'water_ml': const JournalMetricValue(1000, atMinuteOfDay: 600),
      'mood': const JournalMetricValue(2, atMinuteOfDay: 420),
    });

    expect(await repo.adjustWater(_day, step), 500);
    final snap = await repo.readJournalDay(_day);
    expect(snap.metrics['water_ml']!.value, 500);
    expect(snap.metrics['water_ml']!.atMinuteOfDay, 480);
    expect(snap.metrics['mood']!.value, 3);
    expect(snap.metrics['mood']!.atMinuteOfDay, 510);
    expect(snap.metrics['caffeine_mg']!.value, 180);
    expect(snap.metrics['caffeine_mg']!.atMinuteOfDay, 855);

    final other = await repo.readJournalDay(_otherDay);
    expect(other.metrics['water_ml']!.value, 1000);
    expect(other.metrics['water_ml']!.atMinuteOfDay, 600);
    expect(other.metrics['mood']!.value, 2);
  });

  test('revision is monotonic and a stale absolute patch conflicts', () async {
    final repo = repoOf();
    expect(await repo.adjustWater(_day, step), step);
    final before = await repo.readJournalDay(_day);
    final rev = before.metricUpdatedAt['water_ml']!;
    expect(await repo.adjustWater(_day, step), step * 2);
    final after = await repo.readJournalDay(_day);
    expect(after.metricUpdatedAt['water_ml']!, greaterThan(rev));
    expect(after.metrics['water_ml']!.value, step * 2);

    await expectLater(
      repo.patchJournalDay(
        JournalDayPatch(
          day: _day,
          metrics: const {'water_ml': JournalMetricValue(1000)},
          expectedMetrics: before.metrics,
          expectedMetricUpdatedAt: before.metricUpdatedAt,
        ),
      ),
      throwsA(isA<JournalConflict>()),
    );
    expect(
      (await repo.readJournalDay(_day)).metrics['water_ml']!.value,
      step * 2,
    );

    await repo.patchJournalDay(
      JournalDayPatch(
        day: _day,
        metrics: const {'water_ml': JournalMetricValue(1000)},
        expectedMetrics: after.metrics,
        expectedMetricUpdatedAt: after.metricUpdatedAt,
      ),
    );
    expect(await repo.adjustWater(_day, step), 1250);
  });

  test('deltas clamp to the field max', () async {
    final repo = repoOf();
    expect(await repo.adjustWater(_day, max + step), max);
    expect(await repo.adjustWater(_day, step), max);
  });

  test('concurrent adds sum', () async {
    final repo = repoOf();
    final results = await Future.wait([
      repo.adjustWater(_day, step),
      repo.adjustWater(_day, step),
      repo.adjustWater(_day, step),
    ]);
    expect(results.toSet(), {step, step * 2, step * 3});
    expect((await repo.readJournalDay(_day)).metrics['water_ml']!.value, step * 3);
  });

  test('invalid day and nonfinite delta are refused', () async {
    final repo = repoOf();
    for (final day in ['', '2026-9-15', '2026-02-30', '2026-09-15T00:00:00Z']) {
      expect(
        () => repo.adjustWater(day, step),
        throwsA(isA<ArgumentError>()),
      );
    }
    for (final delta in [double.nan, double.infinity, double.negativeInfinity]) {
      expect(
        () => repo.adjustWater(_day, delta),
        throwsA(isA<ArgumentError>()),
      );
    }
    expect(
      (await repo.readJournalDay(_day)).metrics.containsKey('water_ml'),
      isFalse,
    );
  });
}

Future<void> _putMetrics(
  OpenBandRepository repo,
  String day,
  Map<String, JournalMetricValue> metrics,
) {
  return repo.patchJournalDay(
    JournalDayPatch(
      day: day,
      metrics: metrics,
      expectedMetrics: {for (final k in metrics.keys) k: null},
      expectedMetricUpdatedAt: {for (final k in metrics.keys) k: 0},
    ),
  );
}
