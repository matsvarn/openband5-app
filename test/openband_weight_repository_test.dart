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
const _other = '2026-09-14';

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

Map<String, Object?> _weightFixture() =>
    jsonDecode(
          File(
            'docs/openband5/assets/fixtures/weight-history.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('synthetic', () {
    late SyntheticOpenBandRepository repo;
    setUp(() => repo = _synthetic());
    _contract(() => repo);

    test('default and profile-only remain no dated entries', () async {
      final empty = await repo.readWeightHistory(_day, 7);
      expect(empty.entries, isEmpty);
      expect(empty.latest, isNull);
      expect(empty.trend, everyElement(isNull));
      expect(empty.unreadableCount, 0);

      repo.seedJournalEditor(filled: false);
      final stillEmpty = await repo.readWeightHistory(_day, 7);
      expect(stillEmpty.entries, isEmpty);
      expect(stillEmpty.latest, isNull);
    });

    test(
      'journal editor seed is dated journal, not a profile fallback',
      () async {
        repo.seedJournalEditor(filled: true);
        final history = await repo.readWeightHistory(_day, 7);
        expect(history.latest?.day, _day);
        expect(history.latest?.value, 78);
        expect(history.entries.single.day, _day);
      },
    );

    test(
      'fixture seeder is journal storage; edits and deletes apply',
      () async {
        final fixture = _weightFixture();
        repo.seedWeightHistory(
          dates: (fixture['dates'] as List).cast<String>(),
          enteredKg: [
            for (final v in fixture['enteredKg'] as List) (v as num).toDouble(),
          ],
        );
        final before = await repo.readWeightHistory(_day, 7);
        expect(before.entries, hasLength(7));
        expect(before.latest?.value, 75);
        for (var i = 0; i < 7; i++) {
          expect(before.trend[i], closeTo(kWeightPaperEwmaKg[i], 1e-12));
        }

        final snap = await repo.readJournalDay(_day);
        await repo.patchJournalDay(
          JournalDayPatch.fromBase(
            snap,
            metrics: const {kWeightJournalField: JournalMetricValue(74.5)},
          ),
        );
        final edited = await repo.readWeightHistory(_day, 7);
        expect(edited.latest?.value, 74.5);
        expect(edited.trend.last, isNot(before.trend.last));

        final afterEdit = await repo.readJournalDay(_day);
        await repo.patchJournalDay(
          JournalDayPatch.fromBase(
            afterEdit,
            metrics: const {kWeightJournalField: null},
          ),
        );
        final removed = await repo.readWeightHistory(_day, 7);
        expect(removed.latest?.day, _other);
        expect(removed.entries.any((e) => e.day == _day), isFalse);
      },
    );

    test('journal read failure is not an empty history', () async {
      repo.failJournalRead = true;
      await expectLater(
        repo.readWeightHistory(_day, 7),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'synthetic journal read failure',
          ),
        ),
      );
    });
  });

  group('SQLite', () {
    late AppState app;
    late LocalOpenBandRepository repo;
    const dbName = 'openband_weight_repository_test.db';

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
      app.user = {'weight_kg': 75};
      app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      repo = LocalOpenBandRepository(app);
    });

    tearDown(() async {
      app.dispose();
      await LocalDb.close();
    });

    _contract(() => repo);

    test('profile weight is not a dated history fallback', () async {
      final history = await repo.readWeightHistory(_day, 7);
      expect(app.user!['weight_kg'], 75);
      expect(history.entries, isEmpty);
      expect(history.latest, isNull);
      expect(history.unreadableCount, 0);
    });

    test('oldest-limit trap is avoided for a trailing 7 of 90', () async {
      final days = weightDaysEnding(_day, 90);
      for (var i = 0; i < days.length; i++) {
        await _putMetrics(repo, days[i], {
          kWeightJournalField: JournalMetricValue(60 + i * 0.1),
        });
      }
      final history = await repo.readWeightHistory(_day, 7);
      expect(history.entries, hasLength(7));
      expect(history.entries.first.day, _day);
      expect(history.entries.last.day, '2026-09-09');
      expect(history.latest?.day, _day);
      expect(history.latest?.value, closeTo(60 + 89 * 0.1, 1e-9));
      expect(history.entries.last.value, closeTo(60 + 83 * 0.1, 1e-9));
    });

    test('corrupt scalar and row dates increment unreadable count', () async {
      await _putMetrics(repo, _day, {
        kWeightJournalField: const JournalMetricValue(75),
      });
      final db = await LocalDb.instance;
      await db.insert('journal_metric', {
        'date': '2026-02-30',
        'field': kWeightJournalField,
        'value': 70,
        'updated_at': 1,
      });
      await db.insert('journal_metric', {
        'date': '2026-00-14',
        'field': kWeightJournalField,
        'value': 70,
        'updated_at': 2,
      });
      await db.insert('journal_metric', {
        'date': '2026-09-14',
        'field': kWeightJournalField,
        'value': 'corrupt',
        'updated_at': 3,
      });
      await db.insert('journal_metric', {
        'date': '2026-09-13',
        'field': kWeightJournalField,
        'value': 0,
        'updated_at': 4,
      });
      await db.insert('journal_metric', {
        'date': '2026-09-12',
        'field': kWeightJournalField,
        'value': 401,
        'updated_at': 5,
      });

      final history = await repo.readWeightHistory(_day, 7);
      expect(history.unreadableCount, 3);
      expect(history.invalidCount, 2);
      expect(history.latest?.day, _day);
      expect(history.latest?.value, 75);
      final byDay = {for (final e in history.entries) e.day: e};
      expect(byDay['2026-09-13']?.value, 0);
      expect(byDay['2026-09-13']?.usableForTrend, isFalse);
      expect(byDay['2026-09-12']?.value, 401);
      expect(byDay['2026-09-12']?.usableForTrend, isFalse);
      expect(byDay.containsKey('2026-09-14'), isFalse);
      expect(history.trend[history.window.indexOf('2026-09-13')], isNull);
      expect(history.trend[history.window.indexOf('2026-09-12')], isNull);
    });

    test(
      'corrupt dates that sort after the selected end stay unreadable',
      () async {
        await _putMetrics(repo, _day, {
          kWeightJournalField: const JournalMetricValue(75),
        });
        final db = await LocalDb.instance;
        await db.insert('journal_metric', {
          'date': '2026-09-32',
          'field': kWeightJournalField,
          'value': 70,
          'updated_at': 1,
        });
        await db.insert('journal_metric', {
          'date': '2026-13-01',
          'field': kWeightJournalField,
          'value': 71,
          'updated_at': 2,
        });
        await db.insert('journal_metric', {
          'date': 'not-a-day',
          'field': kWeightJournalField,
          'value': 72,
          'updated_at': 3,
        });

        final history = await repo.readWeightHistory(_day, 7);
        expect(history.unreadableCount, 3);
        expect(history.invalidCount, 0);
        expect(history.latest?.day, _day);
        expect(history.latest?.value, 75);
        expect(history.entries.map((e) => e.day), [_day]);
      },
    );

    test('valid future weight stays excluded', () async {
      await _putMetrics(repo, '2026-09-09', {
        kWeightJournalField: const JournalMetricValue(80),
      });
      await _putMetrics(repo, _day, {
        kWeightJournalField: const JournalMetricValue(75),
      });
      final before = await repo.readWeightHistory(_day, 7);
      await _putMetrics(repo, '2026-09-16', {
        kWeightJournalField: const JournalMetricValue(40),
      });

      final history = await repo.readWeightHistory(_day, 7);
      expect(history.entries.map((e) => e.day), [_day, '2026-09-09']);
      expect(history.latest?.day, _day);
      expect(history.latest?.value, 75);
      expect(history.trend, before.trend);
      expect(history.unreadableCount, 0);
      expect(history.invalidCount, 0);
    });

    test('database failure throws and is not an empty history', () async {
      await _putMetrics(repo, _day, {
        kWeightJournalField: const JournalMetricValue(75),
      });
      final db = await LocalDb.instance;
      await db.execute(
        'ALTER TABLE journal_metric RENAME TO journal_metric_hidden',
      );
      await expectLater(
        repo.readWeightHistory(_day, 7),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}

void _contract(OpenBandRepository Function() repoOf) {
  test('invalid endDay and window are refused', () async {
    final repo = repoOf();
    for (final day in ['', '2026-9-15', '2026-02-30', '2026-09-15T00:00:00Z']) {
      expect(() => repo.readWeightHistory(day, 7), throwsArgumentError);
    }
    expect(() => repo.readWeightHistory(_day, 14), throwsArgumentError);
    expect(() => repo.readWeightHistory(_day, 0), throwsArgumentError);
  });

  test('empty journal is empty history, not an error', () async {
    final repo = repoOf();
    final history = await repo.readWeightHistory(_day, 7);
    expect(history.endDay, _day);
    expect(history.days, 7);
    expect(history.entries, isEmpty);
    expect(history.latest, isNull);
    expect(history.trend, hasLength(7));
    expect(history.trend, everyElement(isNull));
    expect(history.unreadableCount, 0);
    expect(history.invalidCount, 0);
  });

  test('historical end excludes future; latest date stays actual', () async {
    final repo = repoOf();
    await _putMetrics(repo, '2026-09-01', {
      kWeightJournalField: const JournalMetricValue(80),
    });
    await _putMetrics(repo, '2026-09-10', {
      kWeightJournalField: const JournalMetricValue(79),
    });
    await _putMetrics(repo, _day, {
      kWeightJournalField: const JournalMetricValue(78),
    });

    final historical = await repo.readWeightHistory('2026-09-10', 7);
    expect(historical.latest?.day, '2026-09-10');
    expect(historical.latest?.value, 79);
    expect(historical.entries.map((e) => e.day), ['2026-09-10']);
    expect(historical.entries.any((e) => e.day == _day), isFalse);

    final seven = await repo.readWeightHistory(_day, 7);
    expect(seven.latest?.day, _day);
    expect(seven.latest?.value, 78);
    expect(seven.entries.map((e) => e.day), [_day, '2026-09-10']);
    expect(seven.entries.any((e) => e.day == '2026-09-01'), isFalse);
  });

  test('period-invariant trend and retained gaps', () async {
    final repo = repoOf();
    await _putMetrics(repo, '2026-08-01', {
      kWeightJournalField: const JournalMetricValue(80),
    });
    await _putMetrics(repo, '2026-09-09', {
      kWeightJournalField: const JournalMetricValue(76),
    });
    await _putMetrics(repo, _day, {
      kWeightJournalField: const JournalMetricValue(74),
    });

    final seven = await repo.readWeightHistory(_day, 7);
    final thirty = await repo.readWeightHistory(_day, 30);
    final ninety = await repo.readWeightHistory(_day, 90);
    expect(seven.trend.last, ninety.trend.last);
    expect(thirty.trend.last, ninety.trend.last);
    expect(seven.trend.first, isNotNull);
    for (var i = 1; i < 6; i++) {
      expect(seven.trend[i], isNull);
    }
    expect(seven.entries.map((e) => e.day), [_day, '2026-09-09']);
    expect(ninety.latest?.day, _day);
  });

  test('DST window boundaries stay unique civil days', () async {
    final repo = repoOf();
    const spring = '2026-03-30';
    await _putMetrics(repo, spring, {
      kWeightJournalField: const JournalMetricValue(70),
    });
    final history = await repo.readWeightHistory(spring, 7);
    expect(history.window.toSet(), hasLength(7));
    expect(history.window.first, '2026-03-24');
    expect(history.window.last, spring);
    expect(history.latest?.day, spring);
  });

  test(
    'edit/remove one day via CAS preserves unrelated metrics/tags/note',
    () async {
      final repo = repoOf();
      await repo.patchJournalDay(
        JournalDayPatch(
          day: _day,
          metrics: const {
            kWeightJournalField: JournalMetricValue(75, atMinuteOfDay: 435),
            'mood': JournalMetricValue(3, atMinuteOfDay: 480),
            'caffeine_mg': JournalMetricValue(180, atMinuteOfDay: 855),
          },
          expectedMetrics: const {
            kWeightJournalField: null,
            'mood': null,
            'caffeine_mg': null,
          },
          expectedMetricUpdatedAt: const {
            kWeightJournalField: 0,
            'mood': 0,
            'caffeine_mg': 0,
          },
          tags: const ['Spaziergang'],
          note: 'Abend',
          expectedJournalUpdatedAt: 0,
          expectedTags: const [],
          expectedNote: '',
        ),
      );

      final before = await repo.readJournalDay(_day);
      await repo.patchJournalDay(
        JournalDayPatch.fromBase(
          before,
          metrics: const {kWeightJournalField: JournalMetricValue(74.8)},
        ),
      );
      final edited = await repo.readJournalDay(_day);
      expect(edited.metrics[kWeightJournalField]!.value, 74.8);
      expect(edited.metrics['mood']!.value, 3);
      expect(edited.metrics['mood']!.atMinuteOfDay, 480);
      expect(edited.metrics['caffeine_mg']!.value, 180);
      expect(edited.metrics['caffeine_mg']!.atMinuteOfDay, 855);
      expect(edited.tags, ['Spaziergang']);
      expect(edited.note, 'Abend');
      expect(
        edited.metricUpdatedAt[kWeightJournalField]!,
        greaterThan(before.metricUpdatedAt[kWeightJournalField] ?? 0),
      );

      final history = await repo.readWeightHistory(_day, 7);
      expect(history.latest?.value, 74.8);
      expect(history.latest?.atMinuteOfDay, isNull);

      await repo.patchJournalDay(
        JournalDayPatch.fromBase(
          edited,
          metrics: const {kWeightJournalField: null},
        ),
      );
      final cleared = await repo.readJournalDay(_day);
      expect(cleared.metrics.containsKey(kWeightJournalField), isFalse);
      expect(cleared.metrics['mood']!.value, 3);
      expect(cleared.metrics['caffeine_mg']!.value, 180);
      expect(cleared.tags, ['Spaziergang']);
      expect(cleared.note, 'Abend');
      expect((await repo.readWeightHistory(_day, 7)).latest, isNull);
    },
  );

  test('concurrent journal edits conflict rather than overwrite', () async {
    final repo = repoOf();
    await _putMetrics(repo, _day, {
      kWeightJournalField: const JournalMetricValue(75),
      'mood': const JournalMetricValue(3),
    });
    final base = await repo.readJournalDay(_day);
    await repo.patchJournalDay(
      JournalDayPatch.fromBase(
        base,
        metrics: const {kWeightJournalField: JournalMetricValue(74.9)},
      ),
    );
    await expectLater(
      repo.patchJournalDay(
        JournalDayPatch.fromBase(
          base,
          metrics: const {kWeightJournalField: JournalMetricValue(76)},
        ),
      ),
      throwsA(isA<JournalConflict>()),
    );
    final held = await repo.readJournalDay(_day);
    expect(held.metrics[kWeightJournalField]!.value, 74.9);
    expect(held.metrics['mood']!.value, 3);
    expect((await repo.readWeightHistory(_day, 7)).latest?.value, 74.9);
  });

  test('zero is a stored entry, not missing, and stays out of trend', () async {
    final repo = repoOf();
    await _putMetrics(repo, '2026-09-09', {
      kWeightJournalField: const JournalMetricValue(80),
    });
    await _putMetrics(repo, _day, {
      kWeightJournalField: const JournalMetricValue(0),
    });
    final history = await repo.readWeightHistory(_day, 7);
    expect(history.latest?.value, 0);
    expect(history.latest?.usableForTrend, isFalse);
    expect(history.invalidCount, 1);
    expect(history.entries.first.value, 0);
    expect(history.trend.last, isNull);
    expect(history.trend.first, 80);
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
