// Typed caffeine_late × sol_min adapter. SQLite source gates, not mocks.
//
// Independent expected values come from public journalNumericCorrelations
// on the correctly gated calendar series. The adapter must not reimplement
// the statistic, invent yes/no counts, or calculate group means.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late LocalOpenBandRepository repository;

  const endDay = '2026-09-19';
  const nights = 30;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await LocalDb.close();
    LocalDb.dbName = 'openband_journal_pattern_test.db';
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

  test('invalid endDay throws instead of unavailable', () async {
    await expectLater(
      repository.readCaffeineSleepPattern('19-09-2026', nights),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('nights 0 throws instead of unavailable', () async {
    await expectLater(
      repository.readCaffeineSleepPattern(endDay, 0),
      throwsA(isA<ArgumentError>()),
    );
    final synthetic = _gallerySynthetic();
    await expectLater(
      synthetic.readCaffeineSleepPattern(endDay, 0),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('empty window is unavailable, not zeroed groups', () async {
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    expect(actual.kind, CaffeineSleepPatternKind.unavailable);
    expect(actual.pairedN, 0);
    expect(actual.yesNights, isNull);
    expect(actual.noNights, isNull);
    expect(actual.delta, isNull);
    expect(actual.partial, isFalse);
  });

  test('Paper +12 Min fixture matches the public producer', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture();
    await _seedWindow(fixture);

    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, fixture);

    expect(actual.kind, CaffeineSleepPatternKind.meaningful);
    expect(actual.yesNights, 7);
    expect(actual.noNights, 11);
    expect(actual.delta, closeTo(12, 1e-9));
    expect(actual.pairedN, 18);
    expect(actual.yesNights, expected.nWith);
    expect(actual.noNights, expected.nWithout);
    expect(actual.delta, closeTo(expected.delta!, 1e-9));
    expect(actual.pairedN, expected.n);
    expect(actual.partial, isFalse);
    expect(actual.kind, CaffeineSleepPatternKind.meaningful);
    expect(CaffeineSleepPattern.title, 'Einschlafen · Koffein nach 14 Uhr');
    expect(CaffeineSleepPattern.comparisonLabel, 'Ja gegenüber Nein');
    expect(CaffeineSleepPattern.noClearPattern, 'Kein klares Muster');
    expect(CaffeineSleepPattern.tooFewNights, 'Noch zu wenige Nächte');
  });

  test('negative delta retains sign', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture(yesSol: 12, noSol: 24);
    await _seedWindow(fixture);
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, fixture);
    expect(actual.kind, CaffeineSleepPatternKind.meaningful);
    expect(actual.delta, closeTo(-12, 1e-9));
    expect(actual.delta, closeTo(expected.delta!, 1e-9));
    expect(actual.delta! < 0, isTrue);
  });

  test(
    'too few nights is insufficient without invented split counts',
    () async {
      final days = openBandDaysEnding(endDay, nights + 1);
      final fixture = _pairs(
        start: DateTime(2026, 8, 21),
        flags: [1, 0, 1, 0, 1],
        yesSol: 24,
        noSol: 12,
      );
      await _seedWindow(fixture);
      final actual = await repository.readCaffeineSleepPattern(endDay, nights);
      final expected = _producerExpected(days, fixture);
      expect(expected.insufficient, isTrue);
      expect(actual.kind, CaffeineSleepPatternKind.insufficient);
      expect(actual.pairedN, expected.n);
      expect(actual.pairedN, 5);
      expect(actual.yesNights, isNull);
      expect(actual.noNights, isNull);
      expect(actual.delta, isNull);
    },
  );

  test('nonmeaningful keeps producer delta and counts, not means', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _noiseFixture();
    await _seedWindow(fixture);
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, fixture);
    expect(expected.binary, isTrue);
    expect(expected.insufficient, isFalse);
    expect(expected.meaningful, isFalse);
    expect(actual.kind, CaffeineSleepPatternKind.nonmeaningful);
    expect(actual.yesNights, expected.nWith);
    expect(actual.noNights, expected.nWithout);
    expect(actual.delta, closeTo(expected.delta!, 1e-9));
  });

  test('wake day without journal is not Nein', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture();
    await _seedWindow(fixture);
    // SOL on a wake day whose previous day has no caffeine_late.
    await _seedWake('2026-09-09', sol: 99);
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, fixture);
    expect(actual.noNights, expected.nWithout);
    expect(actual.noNights, 11);
    expect(actual.pairedN, 18);
  });

  test('unanswered is not Nein; non-binary answers are dropped', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture();
    await _seedWindow(fixture);
    await LocalDb.putJournalMetrics('2026-09-10', {
      'caffeine_late': const JournalMetricValue(2),
      'mood': const JournalMetricValue(4),
    });
    await _seedWake('2026-09-11', sol: 40);
    await _seedWake('2026-09-12', sol: 41);
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, fixture);
    expect(actual.pairedN, expected.n);
    expect(actual.pairedN, 18);
  });

  test('journal on endDay does not pair a future wake day', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    expect(days.last, endDay);
    expect(days.contains('2026-09-20'), isFalse);
    final fixture = _paperFixture();
    await _seedWindow(fixture);
    await LocalDb.putJournalMetrics(endDay, {
      'caffeine_late': const JournalMetricValue(1),
    });
    await _seedWake('2026-09-20', sol: 8);
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, fixture);
    expect(actual.pairedN, expected.n);
    expect(actual.yesNights, 7);
  });

  test(
    'auto and auto_fallback SOL stay out; stored sol_min is not restaged',
    () async {
      final days = openBandDaysEnding(endDay, nights + 1);
      final fixture = _paperFixture();
      await _seedWindow(fixture);
      await LocalDb.putJournalMetrics('2026-09-10', {
        'caffeine_late': const JournalMetricValue(1),
      });
      await _seedWake('2026-09-11', sol: 5, sleepSource: 'auto');
      await LocalDb.putJournalMetrics('2026-09-11', {
        'caffeine_late': const JournalMetricValue(0),
      });
      await _seedWake('2026-09-12', sol: 6, sleepSource: 'auto_fallback');
      final actual = await repository.readCaffeineSleepPattern(endDay, nights);
      final expected = _producerExpected(days, fixture);
      expect(actual.pairedN, expected.n);
      expect(actual.yesNights, 7);
      expect(actual.partial, isTrue);
    },
  );

  test('partial current day_result leftover sol_min is excluded', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture();
    await _seedWindow(fixture);
    await LocalDb.putJournalMetrics('2026-09-10', {
      'caffeine_late': const JournalMetricValue(1),
    });
    await _seedWake('2026-09-11', sol: 30);
    await LocalDb.putDayResult(
      dayId: '2026-09-11',
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({'sleep_source': 'manual'}),
      windowJson: '{}',
      partial: true,
      source: 'band',
    );
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, fixture);
    expect(actual.pairedN, expected.n);
    expect(actual.yesNights, 7);
    expect(actual.partial, isTrue);
  });

  test('older algo and rolled-back series stamp are excluded', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture();
    await _seedWindow(fixture);
    await LocalDb.putJournalMetrics('2026-09-10', {
      'caffeine_late': const JournalMetricValue(1),
    });
    await _seedWake('2026-09-11', sol: 30, algo: kAlgoVersion - 1);
    await LocalDb.putJournalMetrics('2026-09-11', {
      'caffeine_late': const JournalMetricValue(0),
    });
    await _seedWake('2026-09-12', sol: 31);
    final db = await LocalDb.instance;
    await db.update(
      'metric_series_version',
      {'algo_version': kAlgoVersion - 1},
      where: 'date = ?',
      whereArgs: ['2026-09-12'],
    );
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, fixture);
    expect(actual.pairedN, expected.n);
    expect(actual.partial, isTrue);
  });

  test('skipped current day_result is excluded', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture();
    await _seedWindow(fixture);
    await LocalDb.putJournalMetrics('2026-09-10', {
      'caffeine_late': const JournalMetricValue(1),
    });
    await _seedWake('2026-09-11', sol: 30, skipped: true);
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, fixture);
    expect(actual.pairedN, expected.n);
    expect(actual.yesNights, 7);
    expect(actual.partial, isTrue);
  });

  test('imported series is excluded as measuredOnly', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture();
    await _seedWindow(fixture);
    await LocalDb.putJournalMetrics('2026-09-10', {
      'caffeine_late': const JournalMetricValue(1),
    });
    await _seedWake('2026-09-11', sol: 30, source: 'whoop');
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, fixture);
    expect(actual.pairedN, expected.n);
    expect(actual.partial, isFalse);
  });

  test('pending and failed corrections do not keep the prior SOL', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture();
    await _seedWindow(fixture);
    await _pendingCorrection('2026-08-22');
    await LocalDb.putOpenBandSleepDraft(
      dayId: '2026-08-23',
      draftId: 'fail',
      onsetMs: DateTime(2026, 8, 22, 23).millisecondsSinceEpoch,
      wakeMs: DateTime(2026, 8, 23, 7).millisecondsSinceEpoch,
    );
    await LocalDb.commitOpenBandSleepCorrection(
      dayId: '2026-08-23',
      draftId: 'fail',
      onsetMs: DateTime(2026, 8, 22, 23).millisecondsSinceEpoch,
      wakeMs: DateTime(2026, 8, 23, 7).millisecondsSinceEpoch,
    );
    await LocalDb.updateOpenBandCalculationJob(
      dayId: '2026-08-23',
      correctionId: 'fail',
      revision: 1,
      status: 'failed',
      fromStatuses: {'pending'},
    );
    final gated = fixture.where((row) {
      final wake = row.wake;
      return wake != '2026-08-22' && wake != '2026-08-23';
    }).toList();
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, gated);
    expect(actual.pairedN, expected.n);
    expect(actual.pairedN, 16);
    expect(actual.yesNights, expected.nWith);
    expect(actual.noNights, expected.nWithout);
    expect(actual.yesNights, 5);
    expect(actual.noNights, 11);
    expect(actual.partial, isTrue);
  });

  test(
    'correction without a matching job does not keep the prior SOL',
    () async {
      final days = openBandDaysEnding(endDay, nights + 1);
      final fixture = _paperFixture();
      await _seedWindow(fixture);
      await _orphanCorrection('2026-08-22');
      final gated = fixture.where((row) => row.wake != '2026-08-22').toList();
      final actual = await repository.readCaffeineSleepPattern(endDay, nights);
      final expected = _producerExpected(days, gated);
      expect(actual.pairedN, expected.n);
      expect(actual.pairedN, 17);
      expect(actual.partial, isTrue);
    },
  );

  test('complete status without job receipt is unknown and abstains', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture();
    await _seedWindow(fixture);
    await _pendingCorrection('2026-08-22');
    await LocalDb.updateOpenBandCalculationJob(
      dayId: '2026-08-22',
      correctionId: 'pending-2026-08-22',
      revision: 1,
      status: 'complete',
      fromStatuses: {'pending'},
    );
    final gated = fixture.where((row) => row.wake != '2026-08-22').toList();
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, gated);
    expect(actual.pairedN, expected.n);
    expect(actual.partial, isTrue);
  });

  test('complete current job receipt keeps stored SOL', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture();
    await _seedWindow(fixture);
    await _pendingCorrection('2026-08-22');
    await LocalDb.updateOpenBandCalculationJob(
      dayId: '2026-08-22',
      correctionId: 'pending-2026-08-22',
      revision: 1,
      status: 'complete',
      resultAlgoVersion: kAlgoVersion,
      resultComputedAt: DateTime.now().millisecondsSinceEpoch,
      fromStatuses: {'pending'},
    );
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, fixture);
    expect(actual.pairedN, expected.n);
    expect(actual.yesNights, 7);
    expect(actual.partial, isFalse);
  });

  test('negative sol_min is rejected with partial metadata', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture();
    await _seedWindow(fixture);
    await _seedWake('2026-08-22', sol: -5);
    final gated = fixture.where((row) => row.wake != '2026-08-22').toList();
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, gated);
    expect(actual.partial, isTrue);
    expect(actual.pairedN, expected.n);
    expect(actual.yesNights, expected.nWith);
    expect(actual.yesNights, 6);
  });

  test('unknown sleep_source is rejected with partial metadata', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture();
    await _seedWindow(fixture);
    await _seedWake('2026-08-22', sol: 24, sleepSource: 'not-a-source');
    final gated = fixture.where((row) => row.wake != '2026-08-22').toList();
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, gated);
    expect(actual.partial, isTrue);
    expect(actual.pairedN, expected.n);
  });

  test('confirmed sleep_source pairs like manual', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture();
    await _seedWindow(fixture);
    await LocalDb.putJournalMetrics('2026-09-10', {
      'caffeine_late': const JournalMetricValue(1),
    });
    await _seedWake('2026-09-11', sol: 24, sleepSource: 'confirmed');
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, [
      ...fixture,
      const _Pair('2026-09-10', '2026-09-11', 1, 24),
    ]);
    expect(actual.kind, CaffeineSleepPatternKind.meaningful);
    expect(actual.yesNights, 8);
    expect(actual.noNights, 11);
    expect(actual.pairedN, expected.n);
    expect(actual.partial, isFalse);
  });

  test(
    'mixed 18 eligible pairs plus excluded known outcomes is partial',
    () async {
      final days = openBandDaysEnding(endDay, nights + 1);
      final fixture = _paperFixture();
      await _seedWindow(fixture);
      await LocalDb.putJournalMetrics('2026-09-10', {
        'caffeine_late': const JournalMetricValue(1),
      });
      await _seedWake('2026-09-11', sol: 40, sleepSource: 'rejected');
      await LocalDb.putJournalMetrics('2026-09-12', {
        'caffeine_late': const JournalMetricValue(0),
      });
      await _seedWake('2026-09-13', sol: 30, partial: true);
      await LocalDb.putJournalMetrics('2026-09-14', {
        'caffeine_late': const JournalMetricValue(1),
      });
      await _seedWake('2026-09-15', sol: 28);
      await _pendingCorrection('2026-09-15');
      final actual = await repository.readCaffeineSleepPattern(endDay, nights);
      final expected = _producerExpected(days, fixture);
      expect(actual.kind, CaffeineSleepPatternKind.meaningful);
      expect(actual.partial, isTrue);
      expect(actual.yesNights, 7);
      expect(actual.noNights, 11);
      expect(actual.pairedN, 18);
      expect(actual.delta, closeTo(12, 1e-9));
      expect(actual.pairedN, expected.n);
      expect(actual.yesNights, expected.nWith);
      expect(actual.noNights, expected.nWithout);
      expect(actual.delta, closeTo(expected.delta!, 1e-9));
    },
  );

  test(
    'availableOutcomes counts wake days, not the extra journal day',
    () async {
      final days = openBandDaysEnding(endDay, nights + 1);
      final fixture = _paperFixture();
      await _seedWindow(fixture);
      await _seedWake(days.first, sol: 99);
      final actual = await repository.readCaffeineSleepPattern(endDay, nights);
      final expected = _producerExpected(days, fixture);
      expect(actual.availableOutcomes, expected.availableOutcomes);
      expect(actual.availableOutcomes, 18);
      expect(actual.pairedN, 18);
      expect(actual.partial, isFalse);
    },
  );

  test('absent stored SOL is refused; stored SOL is not restaged', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture();
    await _seedWindow(fixture);
    await LocalDb.putJournalMetrics('2026-09-10', {
      'caffeine_late': const JournalMetricValue(1),
    });
    await _seedWake('2026-09-11');
    await LocalDb.putJournalMetrics('2026-09-11', {
      'caffeine_late': const JournalMetricValue(0),
    });
    await LocalDb.putDayResult(
      dayId: '2026-09-12',
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({
        'sleep_source': 'manual',
        'series': {
          'hypnogram': [
            {'start': 0, 'end': 600, 'stage': 'unobserved'},
            {'start': 600, 'end': 3600, 'stage': 'light'},
          ],
        },
      }),
      windowJson: '{}',
      series: {'sol_min': 18, 'rmssd': 80},
      source: 'band',
    );
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    expect(actual.yesNights, 7);
    expect(actual.noNights, 12);
    expect(actual.pairedN, 19);
    final expected = _producerExpected(days, [
      ...fixture,
      const _Pair('2026-09-11', '2026-09-12', 0, 18),
    ]);
    expect(actual.pairedN, expected.n);
    expect(actual.noNights, expected.nWithout);
  });

  test('corrupt payload abstains with partial metadata', () async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperFixture();
    await _seedWindow(fixture);
    final db = await LocalDb.instance;
    await db.update(
      'day_result',
      {'payload_json': 'not-json'},
      where: 'day_id = ?',
      whereArgs: ['2026-08-22'],
    );
    final gated = fixture.where((row) => row.wake != '2026-08-22').toList();
    final actual = await repository.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, gated);
    expect(actual.partial, isTrue);
    expect(actual.pairedN, expected.n);
    expect(actual.availableOutcomes, expected.availableOutcomes);
  });

  test(
    'calendar axis crosses a DST boundary without skipping the wake day',
    () async {
      const dstEnd = '2026-03-30';
      final days = openBandDaysEnding(dstEnd, 5);
      expect(days, contains('2026-03-29'));
      expect(days.contains('2026-03-30'), isTrue);
      final fixture = [
        _Pair('2026-03-28', '2026-03-29', 1, 20),
        _Pair('2026-03-29', '2026-03-30', 0, 10),
      ];
      await _seedWindow(fixture);
      final actual = await repository.readCaffeineSleepPattern(dstEnd, 4);
      expect(actual.pairedN, 2);
      expect(actual.kind, CaffeineSleepPatternKind.insufficient);
    },
  );

  test('synthetic without stored SOL is unavailable', () async {
    final synthetic = _gallerySynthetic();
    await synthetic.writeJournal('2026-09-18', 'caffeine_late', 1);
    final actual = await synthetic.readCaffeineSleepPattern(endDay, nights);
    expect(actual.kind, CaffeineSleepPatternKind.unavailable);
    expect(actual.yesNights, isNull);
  });

  test('synthetic paperMeaningful seed matches the public producer', () async {
    final synthetic = _gallerySynthetic();
    synthetic.seedCaffeineSleepPattern(endDay);
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _paperLag1(endDay);
    expect(fixture.last.wake, endDay);
    final actual = await synthetic.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, fixture);
    expect(actual.kind, CaffeineSleepPatternKind.meaningful);
    expect(actual.yesNights, 7);
    expect(actual.noNights, 11);
    expect(actual.delta, closeTo(12, 1e-9));
    expect(actual.delta, closeTo(expected.delta!, 1e-9));
    expect(actual.pairedN, expected.n);
    expect(actual.pairedN, 18);
    expect(actual.partial, isFalse);
    expect(actual.endDay, endDay);
  });

  test('synthetic unavailable seed has no supported pairs', () async {
    final synthetic = _gallerySynthetic();
    synthetic.seedCaffeineSleepPattern(
      endDay,
      seed: SyntheticCaffeineSleepSeed.unavailable,
    );
    final actual = await synthetic.readCaffeineSleepPattern(endDay, nights);
    expect(actual.kind, CaffeineSleepPatternKind.unavailable);
    expect(actual.pairedN, 0);
    expect(actual.yesNights, isNull);
    expect(actual.delta, isNull);
  });

  test('synthetic insufficient seed does not invent split counts', () async {
    final synthetic = _gallerySynthetic();
    synthetic.seedCaffeineSleepPattern(
      endDay,
      seed: SyntheticCaffeineSleepSeed.insufficient,
    );
    final days = openBandDaysEnding(endDay, nights + 1);
    final fixture = _lag1Pairs(
      endDay,
      const [1.0, 0.0, 1.0, 0.0, 1.0],
      sols: const [24.0, 12.0, 24.0, 12.0, 24.0],
    );
    final actual = await synthetic.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, fixture);
    expect(expected.insufficient, isTrue);
    expect(actual.kind, CaffeineSleepPatternKind.insufficient);
    expect(actual.pairedN, 5);
    expect(actual.pairedN, expected.n);
    expect(actual.yesNights, isNull);
    expect(actual.delta, isNull);
  });

  test('synthetic nonmeaningful seed keeps producer counts', () async {
    final synthetic = _gallerySynthetic();
    synthetic.seedCaffeineSleepPattern(
      endDay,
      seed: SyntheticCaffeineSleepSeed.nonmeaningful,
    );
    final days = openBandDaysEnding(endDay, nights + 1);
    final rng = math.Random(11);
    final fixture = _lag1Pairs(
      endDay,
      [for (var i = 0; i < 18; i++) i.isEven ? 1.0 : 0.0],
      sols: [for (var i = 0; i < 18; i++) 20 + rng.nextDouble() * 8],
    );
    final actual = await synthetic.readCaffeineSleepPattern(endDay, nights);
    final expected = _producerExpected(days, fixture);
    expect(expected.meaningful, isFalse);
    expect(expected.insufficient, isFalse);
    expect(actual.kind, CaffeineSleepPatternKind.nonmeaningful);
    expect(actual.pairedN, 18);
    expect(actual.pairedN, expected.n);
    expect(actual.yesNights, expected.nWith);
    expect(actual.noNights, expected.nWithout);
    expect(actual.delta, closeTo(expected.delta!, 1e-9));
    expect(actual.partial, isFalse);
    expect(fixture.last.wake, endDay);
  });

  test(
    'synthetic partialMeaningful keeps producer 7/11 and marks ineligible',
    () async {
      final synthetic = _gallerySynthetic();
      synthetic.seedCaffeineSleepPattern(
        endDay,
        seed: SyntheticCaffeineSleepSeed.partialMeaningful,
      );
      final days = openBandDaysEnding(endDay, nights + 1);
      final eligible = _paperLag1(endDay);
      final extra = openBandDaysEnding(endDay, 20);
      expect(eligible.last.wake, endDay);
      expect(eligible.map((p) => p.wake), isNot(contains(extra[1])));
      final actual = await synthetic.readCaffeineSleepPattern(endDay, nights);
      final expected = _producerExpected(days, eligible);
      final leaked = _producerExpected(days, [
        ...eligible,
        _Pair(extra.first, extra[1], 1, 40),
      ]);
      expect(leaked.n, isNot(expected.n));
      expect(expected.meaningful, isTrue);
      expect(actual.kind, CaffeineSleepPatternKind.meaningful);
      expect(actual.partial, isTrue);
      expect(actual.yesNights, 7);
      expect(actual.noNights, 11);
      expect(actual.pairedN, 18);
      expect(actual.pairedN, expected.n);
      expect(actual.delta, closeTo(12, 1e-9));
      expect(actual.delta, closeTo(expected.delta!, 1e-9));
    },
  );

  test('synthetic seed replaces previous caffeine×SOL maps', () async {
    final synthetic = _gallerySynthetic();
    synthetic.seedCaffeineSleepPattern(endDay);
    synthetic.seedCaffeineSleepPattern(
      endDay,
      seed: SyntheticCaffeineSleepSeed.unavailable,
    );
    final actual = await synthetic.readCaffeineSleepPattern(endDay, nights);
    expect(actual.kind, CaffeineSleepPatternKind.unavailable);
    expect(actual.pairedN, 0);
  });
}

SyntheticOpenBandRepository _gallerySynthetic() =>
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

List<_Pair> _paperLag1(String endDay) {
  final flags = [
    for (var i = 0; i < 7; i++) 1.0,
    for (var i = 0; i < 11; i++) 0.0,
  ];
  return _lag1Pairs(
    endDay,
    flags,
    sols: [for (final f in flags) f == 1 ? 24.0 : 12.0],
  );
}

List<_Pair> _lag1Pairs(
  String endDay,
  List<double> flags, {
  required List<double> sols,
}) {
  final days = openBandDaysEnding(endDay, flags.length + 1);
  return [
    for (var i = 0; i < flags.length; i++)
      _Pair(days[i], days[i + 1], flags[i], sols[i]),
  ];
}

class _Pair {
  final String journal;
  final String wake;
  final double flag;
  final double sol;
  const _Pair(this.journal, this.wake, this.flag, this.sol);
}

List<_Pair> _paperFixture({double yesSol = 24, double noSol = 12}) {
  final flags = [
    for (var i = 0; i < 7; i++) 1.0,
    for (var i = 0; i < 11; i++) 0.0,
  ];
  return _pairs(
    start: DateTime(2026, 8, 21),
    flags: flags,
    yesSol: yesSol,
    noSol: noSol,
  );
}

List<_Pair> _noiseFixture() {
  final flags = [for (var i = 0; i < 20; i++) i.isEven ? 1.0 : 0.0];
  final rng = math.Random(11);
  return [
    for (var i = 0; i < flags.length; i++)
      _Pair(
        _label(DateTime(2026, 8, 21).add(Duration(days: i))),
        _label(DateTime(2026, 8, 22).add(Duration(days: i))),
        flags[i],
        20 + rng.nextDouble() * 8,
      ),
  ];
}

List<_Pair> _pairs({
  required DateTime start,
  required List<double> flags,
  required double yesSol,
  required double noSol,
}) {
  return [
    for (var i = 0; i < flags.length; i++)
      _Pair(
        _label(start.add(Duration(days: i))),
        _label(start.add(Duration(days: i + 1))),
        flags[i],
        flags[i] == 1 ? yesSol : noSol,
      ),
  ];
}

String _label(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> _seedWindow(List<_Pair> pairs) async {
  for (final row in pairs) {
    await LocalDb.putJournalMetrics(row.journal, {
      'caffeine_late': JournalMetricValue(row.flag),
    });
    await _seedWake(row.wake, sol: row.sol);
  }
}

Future<void> _seedWake(
  String day, {
  double? sol,
  String sleepSource = 'manual',
  int algo = kAlgoVersion,
  bool partial = false,
  bool skipped = false,
  String? source = 'band',
}) {
  return LocalDb.putDayResult(
    dayId: day,
    algoVersion: algo,
    payloadJson: jsonEncode({'sleep_source': sleepSource}),
    windowJson: '{}',
    partial: partial,
    skipped: skipped,
    series: {'sol_min': ?sol, 'rmssd': 80},
    source: source,
  );
}

Future<void> _pendingCorrection(String day) async {
  final parts = day.split('-').map(int.parse).toList();
  final wake = DateTime(parts[0], parts[1], parts[2], 7);
  final onset = wake.subtract(const Duration(hours: 8));
  await LocalDb.putOpenBandSleepDraft(
    dayId: day,
    draftId: 'pending-$day',
    onsetMs: onset.millisecondsSinceEpoch,
    wakeMs: wake.millisecondsSinceEpoch,
  );
  await LocalDb.commitOpenBandSleepCorrection(
    dayId: day,
    draftId: 'pending-$day',
    onsetMs: onset.millisecondsSinceEpoch,
    wakeMs: wake.millisecondsSinceEpoch,
  );
}

Future<void> _orphanCorrection(String day) async {
  final db = await LocalDb.instance;
  await db.insert('openband_sleep_correction', {
    'day_id': day,
    'correction_id': 'orphan-$day',
    'action': 'override',
    'revision': 1,
    'saved_at': DateTime.now().millisecondsSinceEpoch,
  });
}

({
  int n,
  bool binary,
  bool insufficient,
  bool meaningful,
  int? nWith,
  int? nWithout,
  double? delta,
  int availableOutcomes,
})
_producerExpected(List<String> days, List<_Pair> pairs) {
  final byJournal = {for (final p in pairs) p.journal: p.flag};
  final byWake = {for (final p in pairs) p.wake: p.sol};
  final journal = [
    for (final d in days)
      if (byJournal[d] case final v? when v == 0.0 || v == 1.0)
        ana.JournalNumericDay(d, {'caffeine_late': v}),
  ];
  final outcomes = [for (final d in days) byWake[d]];
  final availableOutcomes = [
    for (var i = 1; i < outcomes.length; i++)
      if (outcomes[i] != null) i,
  ].length;
  final corr = ana.journalNumericCorrelations(
    journal: journal,
    dates: days,
    outcomes: {'sol_min': outcomes},
    fieldLagDays: const {'caffeine_late': 1},
  );
  if (corr.isEmpty || corr.first.effects.isEmpty) {
    return (
      n: 0,
      binary: false,
      insufficient: true,
      meaningful: false,
      nWith: null,
      nWithout: null,
      delta: null,
      availableOutcomes: availableOutcomes,
    );
  }
  final e = corr.first.effects.first;
  return (
    n: e.n,
    binary: e.binary,
    insufficient: e.insufficient,
    meaningful: e.meaningful,
    nWith: e.nWith,
    nWithout: e.nWithout,
    delta: e.delta,
    availableOutcomes: availableOutcomes,
  );
}
