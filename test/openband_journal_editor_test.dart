// Bounded journal day: exact-day read, dirty-only patch, conflict refusal.
//
// Storage tests go through LocalRepositoryImpl + LocalDb (real SQLite).
// Widget tests pump OpenBandJournalEditor against that same store.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/openband/journal_editor.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late _FlakyJournalRepo repo;
  late LocalOpenBandRepository openband;

  const day = '2026-09-15';
  const otherDay = '2026-09-14';
  const historical = '2020-01-01';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('de_DE');
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
    ]) {
      final loader = FontLoader(family)
        ..addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        );
      await loader.load();
    }
  });

  setUp(() async {
    await LocalDb.close();
    LocalDb.dbName = 'openband_journal_editor_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/${LocalDb.dbName}');
    app = AppState.forTesting();
    repo = _FlakyJournalRepo(getProfileMap: () => app.user);
    app.repo = repo;
    openband = LocalOpenBandRepository(app);
  });

  tearDown(() async {
    app.dispose();
    await LocalDb.close();
  });

  Future<void> seedDay(
    String date, {
    required double mood,
    required int moodAt,
    required double late,
    required int lateAt,
    required double caffeine,
    required int caffeineAt,
  }) {
    return LocalDb.putJournalMetrics(date, {
      'mood': JournalMetricValue(mood, atMinuteOfDay: moodAt),
      'caffeine_late': JournalMetricValue(late, atMinuteOfDay: lateAt),
      'caffeine_mg': JournalMetricValue(caffeine, atMinuteOfDay: caffeineAt),
    });
  }

  Future<void> seedJournal(
    String date, {
    List<String> tags = const [],
    String note = '',
  }) {
    return LocalDb.putJournal(date, encodeTags(tags), note);
  }

  group('readJournalDay', () {
    test('returns that date, including at_min, tags, note, revisions', () async {
      await seedDay(
        day,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      await seedJournal(day, tags: const ['late'], note: 'long day');
      await seedDay(
        otherDay,
        mood: 2,
        moodAt: 510,
        late: 0,
        lateAt: 870,
        caffeine: 120,
        caffeineAt: 720,
      );
      await seedJournal(otherDay, tags: const ['travel'], note: 'yesterday');

      final snap = await repo.readJournalDay(day);
      expect(snap.day, day);
      expect(snap.metrics['mood']!.value, 3);
      expect(snap.metrics['mood']!.atMinuteOfDay, 480);
      expect(snap.metrics['caffeine_late']!.value, 1);
      expect(snap.metrics['caffeine_late']!.atMinuteOfDay, 900);
      expect(snap.metrics['caffeine_mg']!.value, 180);
      expect(snap.metrics['caffeine_mg']!.atMinuteOfDay, 855);
      expect(snap.tags, ['late']);
      expect(snap.note, 'long day');
      expect(snap.journalUpdatedAt, greaterThan(0));
      expect(snap.metricUpdatedAt['mood'], greaterThan(0));
      expect(snap.fields.map((f) => f.key), containsAll(['mood', 'water_ml']));

      final viaOpenBand = await openband.readJournalDay(day);
      expect(viaOpenBand.note, 'long day');
      expect(viaOpenBand.metrics['mood']!.value, 3);
    });

    test('a missing day is empty, not another date', () async {
      await seedDay(
        otherDay,
        mood: 2,
        moodAt: 510,
        late: 0,
        lateAt: 870,
        caffeine: 120,
        caffeineAt: 720,
      );
      await seedJournal(otherDay, tags: const ['travel'], note: 'yesterday');

      final snap = await repo.readJournalDay(day);
      expect(snap.metrics, isEmpty);
      expect(snap.metricUpdatedAt, isEmpty);
      expect(snap.tags, isEmpty);
      expect(snap.note, '');
      expect(snap.journalUpdatedAt, 0);
    });

    test('exact-day historical read is not a 30d hunt', () async {
      await seedDay(
        historical,
        mood: 4,
        moodAt: 400,
        late: 0,
        lateAt: 800,
        caffeine: 90,
        caffeineAt: 600,
      );
      await seedJournal(historical, tags: const ['old'], note: 'years ago');
      await seedDay(
        day,
        mood: 1,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 200,
        caffeineAt: 855,
      );

      final snap = await repo.readJournalDay(historical);
      expect(snap.day, historical);
      expect(snap.metrics['mood']!.value, 4);
      expect(snap.metrics['mood']!.atMinuteOfDay, 400);
      expect(snap.tags, ['old']);
      expect(snap.note, 'years ago');
    });
  });

  group('patchJournalDay', () {
    test('one dirty metric preserves siblings, timing, note and tags', () async {
      await seedDay(
        day,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      await seedJournal(day, tags: const ['late'], note: 'keep me');

      final snap = await repo.readJournalDay(day);
      await repo.patchJournalDay(
        JournalDayPatch.fromBase(
          snap,
          metrics: {
            'mood': JournalMetricValue(5, atMinuteOfDay: 480),
          },
        ),
      );

      final written = await LocalDb.journalMetricsForDay(day);
      expect(written['mood']!.value, 5);
      expect(written['mood']!.atMinuteOfDay, 480);
      expect(written['caffeine_late']!.value, 1);
      expect(written['caffeine_late']!.atMinuteOfDay, 900);
      expect(written['caffeine_mg']!.value, 180);
      expect(written['caffeine_mg']!.atMinuteOfDay, 855);

      final after = await repo.readJournalDay(day);
      expect(after.tags, ['late']);
      expect(after.note, 'keep me');
      expect(after.journalUpdatedAt, snap.journalUpdatedAt);
    });

    test('explicit clear removes only that key', () async {
      await seedDay(
        day,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      final snap = await repo.readJournalDay(day);
      await repo.patchJournalDay(
        JournalDayPatch.fromBase(snap, metrics: const {'caffeine_mg': null}),
      );

      final written = await LocalDb.journalMetricsForDay(day);
      expect(written.containsKey('caffeine_mg'), isFalse);
      expect(written['mood']!.value, 3);
      expect(written['mood']!.atMinuteOfDay, 480);
      expect(written['caffeine_late']!.value, 1);
    });

    test('zero is stored as an answer, distinct from missing', () async {
      await seedDay(
        day,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      final snap = await repo.readJournalDay(day);
      await repo.patchJournalDay(
        JournalDayPatch.fromBase(
          snap,
          metrics: const {'caffeine_late': JournalMetricValue(0)},
        ),
      );
      final written = await LocalDb.journalMetricsForDay(day);
      expect(written.containsKey('caffeine_late'), isTrue);
      expect(written['caffeine_late']!.value, 0);
      expect(written.containsKey('alcohol_evening'), isFalse);
    });

    test('stale revision refuses the whole patch', () async {
      await seedDay(
        day,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      await seedJournal(day, tags: const ['late'], note: 'keep me');
      final snap = await repo.readJournalDay(day);
      await repo.patchJournalDay(
        JournalDayPatch.fromBase(
          snap,
          metrics: {
            'mood': JournalMetricValue(4, atMinuteOfDay: 480),
          },
        ),
      );

      await expectLater(
        repo.patchJournalDay(
          JournalDayPatch.fromBase(
            snap,
            metrics: {
              'mood': JournalMetricValue(5, atMinuteOfDay: 480),
              'caffeine_mg': const JournalMetricValue(250),
            },
          ),
        ),
        throwsA(isA<JournalConflict>()),
      );

      final written = await LocalDb.journalMetricsForDay(day);
      expect(written['mood']!.value, 4);
      expect(written['caffeine_mg']!.value, 180);
      expect(written['caffeine_late']!.value, 1);
      final after = await repo.readJournalDay(day);
      expect(after.note, 'keep me');
      expect(after.tags, ['late']);
    });

    test('same-millisecond write cannot evade conflict via matching updated_at',
        () async {
      await seedDay(
        day,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      final snap = await repo.readJournalDay(day);
      final rev = snap.metricUpdatedAt['mood']!;
      await repo.patchJournalDay(
        JournalDayPatch.fromBase(
          snap,
          metrics: {
            'mood': JournalMetricValue(4, atMinuteOfDay: 480),
          },
        ),
      );
      final db = await LocalDb.instance;
      await db.update(
        'journal_metric',
        {'updated_at': rev},
        where: 'date = ? AND field = ?',
        whereArgs: [day, 'mood'],
      );

      await expectLater(
        repo.patchJournalDay(
          JournalDayPatch(
            day: day,
            metrics: {
              'mood': JournalMetricValue(5, atMinuteOfDay: 480),
            },
            expectedMetrics: {
              'mood': JournalMetricValue(3, atMinuteOfDay: 480),
            },
            expectedMetricUpdatedAt: {'mood': rev},
          ),
        ),
        throwsA(isA<JournalConflict>()),
      );

      final written = await LocalDb.journalMetricsForDay(day);
      expect(written['mood']!.value, 4);
      expect(written['caffeine_mg']!.value, 180);
    });

    test('unrelated field patches both commit', () async {
      await seedDay(
        day,
        mood: 3,
        moodAt: 480,
        late: 0,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      final snap = await repo.readJournalDay(day);
      await Future.wait([
        repo.patchJournalDay(
          JournalDayPatch.fromBase(
            snap,
            metrics: {
              'mood': JournalMetricValue(5, atMinuteOfDay: 480),
            },
          ),
        ),
        repo.patchJournalDay(
          JournalDayPatch.fromBase(
            snap,
            metrics: {
              'caffeine_late': JournalMetricValue(1, atMinuteOfDay: 900),
            },
          ),
        ),
      ]);

      final written = await LocalDb.journalMetricsForDay(day);
      expect(written['mood']!.value, 5);
      expect(written['mood']!.atMinuteOfDay, 480);
      expect(written['caffeine_late']!.value, 1);
      expect(written['caffeine_late']!.atMinuteOfDay, 900);
      expect(written['caffeine_mg']!.value, 180);
    });

    test('conflicting same-field concurrent writes keep one and reject the other',
        () async {
      await seedDay(
        day,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      final snap = await repo.readJournalDay(day);
      final results = await Future.wait([
        repo
            .patchJournalDay(
              JournalDayPatch.fromBase(
                snap,
                metrics: {
                  'mood': JournalMetricValue(4, atMinuteOfDay: 480),
                },
              ),
            )
            .then<bool>((_) => true)
            .catchError((_) => false),
        repo
            .patchJournalDay(
              JournalDayPatch.fromBase(
                snap,
                metrics: {
                  'mood': JournalMetricValue(5, atMinuteOfDay: 480),
                },
              ),
            )
            .then<bool>((_) => true)
            .catchError((_) => false),
      ]);
      expect(results.where((ok) => ok).length, 1);

      final written = await LocalDb.journalMetricsForDay(day);
      expect(written['mood']!.value, anyOf(4, 5));
      expect(written['caffeine_mg']!.value, 180);
      expect(written['caffeine_late']!.value, 1);
    });

    test('malformed patch throws before any write', () async {
      await seedDay(
        day,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      final snap = await repo.readJournalDay(day);

      expect(
        () => repo.patchJournalDay(
          JournalDayPatch.fromBase(
            snap,
            metrics: const {'mood': JournalMetricValue(double.nan)},
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.patchJournalDay(
          JournalDayPatch.fromBase(
            snap,
            metrics: {
              'mood': JournalMetricValue(4, atMinuteOfDay: 2000),
            },
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.patchJournalDay(
          JournalDayPatch.fromBase(
            snap,
            metrics: const {'not_a_field': JournalMetricValue(1)},
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.patchJournalDay(
          JournalDayPatch.fromBase(
            snap,
            metrics: const {'caffeine_late': JournalMetricValue(0.5)},
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.patchJournalDay(
          JournalDayPatch.fromBase(
            snap,
            metrics: const {'mood': JournalMetricValue(3.5, atMinuteOfDay: 480)},
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.patchJournalDay(
          JournalDayPatch.fromBase(
            snap,
            metrics: const {
              'mood': JournalMetricValue(4, atMinuteOfDay: 480),
              'caffeine_mg': JournalMetricValue(5000, atMinuteOfDay: 855),
            },
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.readJournalDay('not-a-day'),
        throwsArgumentError,
      );
      expect(
        () => repo.readJournalDay('2026-02-30'),
        throwsArgumentError,
      );

      final written = await LocalDb.journalMetricsForDay(day);
      expect(written['mood']!.value, 3);
      expect(written['caffeine_late']!.value, 1);
      expect(written['caffeine_mg']!.value, 180);
    });

    test('a SQLite abort in the patch writes nothing', () async {
      await seedDay(
        day,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      final db = await LocalDb.instance;
      await db.execute('''
        CREATE TEMP TRIGGER journal_metric_abort_water_upd
        BEFORE UPDATE ON journal_metric
        WHEN NEW.field = 'water_ml'
        BEGIN
          SELECT RAISE(ABORT, 'test abort');
        END
      ''');
      try {
        await LocalDb.putJournalMetrics(day, {
          ...await LocalDb.journalMetricsForDay(day),
          'water_ml': const JournalMetricValue(250),
        });
        final latest = await repo.readJournalDay(day);
        await expectLater(
          repo.patchJournalDay(
            JournalDayPatch.fromBase(
              latest,
              metrics: {
                'mood': JournalMetricValue(5, atMinuteOfDay: 480),
                'water_ml': const JournalMetricValue(500),
              },
            ),
          ),
          throwsA(isA<DatabaseException>()),
        );
      } finally {
        await db.execute('DROP TRIGGER IF EXISTS journal_metric_abort_water_upd');
      }

      final written = await LocalDb.journalMetricsForDay(day);
      expect(written['mood']!.value, 3);
      expect(written['mood']!.atMinuteOfDay, 480);
      expect(written['caffeine_mg']!.value, 180);
    });

    test('custom definition removal keeps saved history', () async {
      await repo.postCustomJournalField(
        const JournalFieldSpec(
          key: 'custom_magnesium',
          label: 'Magnesium',
          kind: JournalFieldKind.dose,
          unit: 'mg',
          max: 1000,
          step: 50,
          custom: true,
        ),
      );
      final empty = await repo.readJournalDay(day);
      await repo.patchJournalDay(
        JournalDayPatch.fromBase(
          empty,
          metrics: const {'custom_magnesium': JournalMetricValue(400)},
        ),
      );
      await repo.deleteCustomJournalField('custom_magnesium');

      final snap = await repo.readJournalDay(day);
      expect(snap.metrics['custom_magnesium']!.value, 400);
      expect(snap.fields.any((f) => f.key == 'custom_magnesium'), isFalse);

      await repo.patchJournalDay(
        JournalDayPatch.fromBase(
          snap,
          metrics: const {'custom_magnesium': JournalMetricValue(450)},
        ),
      );
      expect(
        (await LocalDb.journalMetricsForDay(day))['custom_magnesium']!.value,
        450,
      );
      expect(
        (await repo.readJournalDay(day))
            .fields
            .any((f) => f.key == 'custom_magnesium'),
        isFalse,
      );
    });

    test('note-only patch leaves metrics and other tags alone', () async {
      await seedDay(
        day,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      await seedJournal(day, tags: const ['late', 'travel'], note: 'old');
      final snap = await repo.readJournalDay(day);
      await repo.patchJournalDay(
        JournalDayPatch.fromBase(snap, note: 'new note'),
      );
      final after = await repo.readJournalDay(day);
      expect(after.note, 'new note');
      expect(after.tags.toSet(), {'late', 'travel'});
      expect(after.metrics['mood']!.value, 3);
      expect(after.metrics['caffeine_mg']!.atMinuteOfDay, 855);
    });

    test('corrupt tags refuse read and note-only patch, source kept', () async {
      await seedDay(
        day,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      const corrupt = '{not-json';
      await LocalDb.putJournal(day, corrupt, 'old note');

      await expectLater(
        repo.readJournalDay(day),
        throwsA(isA<FormatException>()),
      );

      await expectLater(
        repo.patchJournalDay(
          const JournalDayPatch(
            day: day,
            note: 'new note',
            expectedJournalUpdatedAt: 1,
            expectedNote: 'old note',
          ),
        ),
        throwsA(isA<FormatException>()),
      );

      final db = await LocalDb.instance;
      final row = (await db.query(
        'journal',
        where: 'date = ?',
        whereArgs: [day],
      )).single;
      expect(row['tags_json'], corrupt);
      expect(row['note'], 'old note');
      final written = await LocalDb.journalMetricsForDay(day);
      expect(written['mood']!.value, 3);
      expect(written['caffeine_mg']!.atMinuteOfDay, 855);
    });

    test('metric-only patch does not re-read corrupt tags as a false failure',
        () async {
      await seedDay(
        day,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      const corrupt = '{"not":"a-list"}';
      await LocalDb.putJournal(day, corrupt, 'old note');
      final metrics = await LocalDb.journalMetricsForDay(day);
      final db = await LocalDb.instance;
      final moodRev = ((await db.query(
        'journal_metric',
        columns: ['updated_at'],
        where: 'date = ? AND field = ?',
        whereArgs: [day, 'mood'],
      )).first['updated_at'] as num)
          .toInt();

      await repo.patchJournalDay(
        JournalDayPatch(
          day: day,
          metrics: {
            'mood': JournalMetricValue(5, atMinuteOfDay: 480),
          },
          expectedMetrics: {'mood': metrics['mood']},
          expectedMetricUpdatedAt: {'mood': moodRev},
        ),
      );

      final written = await LocalDb.journalMetricsForDay(day);
      expect(written['mood']!.value, 5);
      expect(written['caffeine_mg']!.value, 180);
      expect(written['caffeine_mg']!.atMinuteOfDay, 855);
      final row = (await db.query(
        'journal',
        where: 'date = ?',
        whereArgs: [day],
      )).single;
      expect(row['tags_json'], corrupt);
      expect(row['note'], 'old note');
    });
  });

  group('additive water', () {
    test('concurrent adds sum and keep siblings', () async {
      await seedDay(
        day,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      await Future.wait([
        repo.addJournalMetric(day, 'water_ml', 250),
        repo.addJournalMetric(day, 'water_ml', 250),
        repo.addJournalMetric(day, 'water_ml', 250),
      ]);
      final written = await LocalDb.journalMetricsForDay(day);
      expect(written['water_ml']!.value, 750);
      expect(written['mood']!.value, 3);
      expect(written['mood']!.atMinuteOfDay, 480);
      expect(written['caffeine_mg']!.value, 180);
      expect(written['caffeine_mg']!.atMinuteOfDay, 855);
    });

    test('same-ms water A-B-A still trips a stale patch', () async {
      await seedDay(
        day,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      await repo.addJournalMetric(day, 'water_ml', 500);
      final db = await LocalDb.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.update(
        'journal_metric',
        {'updated_at': now, 'value': 500},
        where: 'date = ? AND field = ?',
        whereArgs: [day, 'water_ml'],
      );
      await repo.addJournalMetric(day, 'water_ml', 250);
      await repo.addJournalMetric(day, 'water_ml', -250);
      final row = (await db.query(
        'journal_metric',
        where: 'date = ? AND field = ?',
        whereArgs: [day, 'water_ml'],
      )).single;
      expect(row['value'], 500);
      expect((row['updated_at'] as num).toInt(), greaterThan(now));

      await expectLater(
        repo.patchJournalDay(
          JournalDayPatch(
            day: day,
            metrics: const {'water_ml': JournalMetricValue(750)},
            expectedMetrics: const {'water_ml': JournalMetricValue(500)},
            expectedMetricUpdatedAt: {'water_ml': now},
          ),
        ),
        throwsA(isA<JournalConflict>()),
      );
      expect((await LocalDb.journalMetricsForDay(day))['water_ml']!.value, 500);
      expect((await LocalDb.journalMetricsForDay(day))['mood']!.value, 3);
    });
  });

  test('full-day replacement still clears omitted fields', () async {
    await seedDay(
      day,
      mood: 3,
      moodAt: 480,
      late: 1,
      lateAt: 900,
      caffeine: 180,
      caffeineAt: 855,
    );
    await repo.postJournalMetrics(day, {
      'mood': const JournalMetricValue(4),
    });
    final written = await LocalDb.journalMetricsForDay(day);
    expect(written.keys, ['mood']);
    expect(written['mood']!.value, 4);
  });

  test('putJournalMetrics same-ms ABA still trips a stale patch', () async {
    await seedDay(
      day,
      mood: 3,
      moodAt: 480,
      late: 1,
      lateAt: 900,
      caffeine: 180,
      caffeineAt: 855,
    );
    final db = await LocalDb.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'journal_metric',
      {'updated_at': now},
      where: 'date = ? AND field = ?',
      whereArgs: [day, 'mood'],
    );
    await repo.postJournalMetrics(day, {
      'mood': const JournalMetricValue(4, atMinuteOfDay: 480),
      'caffeine_late': const JournalMetricValue(1, atMinuteOfDay: 900),
      'caffeine_mg': const JournalMetricValue(180, atMinuteOfDay: 855),
    });
    await repo.postJournalMetrics(day, {
      'mood': const JournalMetricValue(3, atMinuteOfDay: 480),
      'caffeine_late': const JournalMetricValue(1, atMinuteOfDay: 900),
      'caffeine_mg': const JournalMetricValue(180, atMinuteOfDay: 855),
    });
    final row = (await db.query(
      'journal_metric',
      where: 'date = ? AND field = ?',
      whereArgs: [day, 'mood'],
    )).single;
    expect(row['value'], 3);
    expect((row['updated_at'] as num).toInt(), greaterThan(now));

    await expectLater(
      repo.patchJournalDay(
        JournalDayPatch(
          day: day,
          metrics: {
            'mood': const JournalMetricValue(5, atMinuteOfDay: 480),
          },
          expectedMetrics: {
            'mood': const JournalMetricValue(3, atMinuteOfDay: 480),
          },
          expectedMetricUpdatedAt: {'mood': now},
        ),
      ),
      throwsA(isA<JournalConflict>()),
    );
    final written = await LocalDb.journalMetricsForDay(day);
    expect(written['mood']!.value, 3);
    expect(written['caffeine_mg']!.value, 180);
    expect(written['caffeine_mg']!.atMinuteOfDay, 855);
  });

  test('putJournal same-ms ABA still trips a stale note patch', () async {
    await seedDay(
      day,
      mood: 3,
      moodAt: 480,
      late: 1,
      lateAt: 900,
      caffeine: 180,
      caffeineAt: 855,
    );
    await seedJournal(day, tags: const ['late'], note: 'keep me');
    final db = await LocalDb.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'journal',
      {'updated_at': now},
      where: 'date = ?',
      whereArgs: [day],
    );
    await repo.postJournal(day, const ['late'], 'keep me');
    await repo.postJournal(day, const ['late'], 'keep me');
    final row = (await db.query(
      'journal',
      where: 'date = ?',
      whereArgs: [day],
    )).single;
    expect(row['note'], 'keep me');
    expect(row['tags_json'], encodeTags(const ['late']));
    expect((row['updated_at'] as num).toInt(), greaterThan(now));

    await expectLater(
      repo.patchJournalDay(
        JournalDayPatch(
          day: day,
          note: 'stolen',
          expectedJournalUpdatedAt: now,
          expectedNote: 'keep me',
          expectedTags: const ['late'],
        ),
      ),
      throwsA(isA<JournalConflict>()),
    );
    final after = await repo.readJournalDay(day);
    expect(after.note, 'keep me');
    expect(after.tags, ['late']);
    expect(after.metrics['mood']!.value, 3);
  });

  group('moment gesture', () {
    test('appends a tag and keeps note, tags, and metrics', () async {
      final today = todayLabel();
      await seedDay(
        today,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      await seedJournal(today, tags: const ['late'], note: 'keep me');
      await app.markMomentFromGesture();
      final snap = await repo.readJournalDay(today);
      expect(snap.note, 'keep me');
      expect(snap.tags, contains('late'));
      expect(snap.tags.any((t) => t.startsWith('moment ')), isTrue);
      expect(snap.metrics['mood']!.value, 3);
      expect(snap.metrics['caffeine_mg']!.atMinuteOfDay, 855);
    });

    test('read failure refuses the write and keeps the stored row', () async {
      final today = todayLabel();
      await seedDay(
        today,
        mood: 3,
        moodAt: 480,
        late: 1,
        lateAt: 900,
        caffeine: 180,
        caffeineAt: 855,
      );
      const corrupt = '{not-json';
      await LocalDb.putJournal(today, corrupt, 'keep me');
      await app.markMomentFromGesture();
      final row = (await (await LocalDb.instance).query(
        'journal',
        where: 'date = ?',
        whereArgs: [today],
      )).single;
      expect(row['tags_json'], corrupt);
      expect(row['note'], 'keep me');
      expect((await LocalDb.journalMetricsForDay(today))['mood']!.value, 3);
    });
  });


  group('OpenBandJournalEditor sqlite', () {
    Future<void> flushSqlite(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await flushSqlite(tester);
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
            (find.text('Tagesjournal').evaluate().isNotEmpty ||
                find.text('Journal nicht geladen').evaluate().isNotEmpty)) {
          return;
        }
      }
    }

    Future<void> pumpEditor(WidgetTester tester, {required String date}) async {
      tester.view.physicalSize = const Size(400, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            locale: const Locale('de'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('de')],
            theme: openBandTheme(Brightness.light),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(400, 2000),
                disableAnimations: true,
              ),
              child: OpenBandJournalEditor(repository: openband, day: date),
            ),
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('exact-day historical editor loads past 30d', (tester) async {
      await tester.runAsync(() async {
        await seedDay(
          historical,
          mood: 4,
          moodAt: 400,
          late: 0,
          lateAt: 800,
          caffeine: 90,
          caffeineAt: 600,
        );
        await seedJournal(historical, note: 'years ago');
        await seedDay(
          day,
          mood: 1,
          moodAt: 480,
          late: 1,
          lateAt: 900,
          caffeine: 200,
          caffeineAt: 855,
        );
      });
      await pumpEditor(tester, date: historical);
      expect(find.textContaining('years ago'), findsOneWidget);
      expect(find.text('1. Januar'), findsOneWidget);
    });

    testWidgets('saving one answer does not erase siblings', (tester) async {
      await tester.runAsync(() async {
        await seedDay(
          day,
          mood: 3,
          moodAt: 480,
          late: 1,
          lateAt: 900,
          caffeine: 180,
          caffeineAt: 855,
        );
        await seedJournal(day, tags: const ['late'], note: 'keep me');
      });
      await pumpEditor(tester, date: day);
      await tester.tap(find.bySemanticsLabel('Stimmung Sehr gut'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('journal-save')));
      for (var i = 0; i < 40; i++) {
        await flushSqlite(tester);
        if (find.text('Tagesjournal').evaluate().isEmpty) break;
      }
      late Map<String, JournalMetricValue> written;
      late JournalDaySnapshot after;
      await tester.runAsync(() async {
        written = await LocalDb.journalMetricsForDay(day);
        after = await repo.readJournalDay(day);
      });
      expect(written['mood']!.value, 5);
      expect(written['mood']!.atMinuteOfDay, 480);
      expect(written['caffeine_late']!.value, 1);
      expect(written['caffeine_mg']!.value, 180);
      expect(written['caffeine_mg']!.atMinuteOfDay, 855);
      expect(after.note, 'keep me');
      expect(after.tags, ['late']);
    });

    testWidgets('a failed save keeps the draft on screen', (tester) async {
      await tester.runAsync(() async {
        await seedDay(
          day,
          mood: 3,
          moodAt: 480,
          late: 1,
          lateAt: 900,
          caffeine: 180,
          caffeineAt: 855,
        );
      });
      await pumpEditor(tester, date: day);
      await tester.tap(find.bySemanticsLabel('Stimmung Sehr gut'));
      await tester.pump();
      await tester.runAsync(() async {
        final snap = await repo.readJournalDay(day);
        await repo.patchJournalDay(
          JournalDayPatch.fromBase(
            snap,
            metrics: {
              'mood': JournalMetricValue(2, atMinuteOfDay: 480),
            },
          ),
        );
      });
      await tester.tap(find.byKey(const ValueKey('journal-save')));
      for (var i = 0; i < 40; i++) {
        await flushSqlite(tester);
        if (find.text('Eintrag wurde inzwischen geändert.').evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.text('Eintrag wurde inzwischen geändert.'), findsOneWidget);
      expect(find.byType(OpenBandJournalEditor), findsOneWidget);
      late Map<String, JournalMetricValue> written;
      await tester.runAsync(() async {
        written = await LocalDb.journalMetricsForDay(day);
      });
      expect(written['mood']!.value, 2);
      expect(written['caffeine_mg']!.value, 180);
    });
  });
}

class _FlakyJournalRepo extends LocalRepositoryImpl {
  _FlakyJournalRepo({required super.getProfileMap});

  bool failRead = false;
  bool failFields = false;

  @override
  Future<JournalDaySnapshot> readJournalDay(String day) async {
    if (failRead) throw const FormatException('Unreadable journal tags.');
    return super.readJournalDay(day);
  }

  @override
  Future<List<JournalFieldSpec>> getJournalFields({
    bool includeHidden = false,
  }) async {
    if (failFields) throw StateError('fields failed');
    return super.getJournalFields(includeHidden: includeHidden);
  }
}

String encodeTags(List<String> tags) =>
    '[${tags.map((t) => '"$t"').join(',')}]';
