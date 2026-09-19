// Production OpenBand journal writes must not replace the day.
//
// writeJournal used to call postJournalMetrics with a one-key map. That
// delete-and-insert path cleared every other field (and their at_min) for
// the date. These tests go through LocalOpenBandRepository + LocalDb.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late LocalOpenBandRepository repository;
  late LocalRepositoryImpl repo;

  const day = '2026-09-15';
  const otherDay = '2026-09-14';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await LocalDb.close();
    LocalDb.dbName = 'openband_journal_storage_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/${LocalDb.dbName}');
    app = AppState.forTesting();
    repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    app.repo = repo;
    repository = LocalOpenBandRepository(app);
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

  test(
    'inline mood write keeps sibling answers, doses, times, and other days',
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
      await seedDay(
        otherDay,
        mood: 2,
        moodAt: 510,
        late: 0,
        lateAt: 870,
        caffeine: 120,
        caffeineAt: 720,
      );

      await repository.writeJournal(day, 'mood', 4);

      final written = await LocalDb.journalMetricsForDay(day);
      expect(written['mood']!.value, 4);
      expect(written['mood']!.atMinuteOfDay, 480);
      expect(written['caffeine_late']!.value, 1);
      expect(written['caffeine_late']!.atMinuteOfDay, 900);
      expect(written['caffeine_mg']!.value, 180);
      expect(written['caffeine_mg']!.atMinuteOfDay, 855);

      final other = await LocalDb.journalMetricsForDay(otherDay);
      expect(other['mood']!.value, 2);
      expect(other['mood']!.atMinuteOfDay, 510);
      expect(other['caffeine_late']!.value, 0);
      expect(other['caffeine_late']!.atMinuteOfDay, 870);
      expect(other['caffeine_mg']!.value, 120);
      expect(other['caffeine_mg']!.atMinuteOfDay, 720);

      final viaAdapter = {
        for (final e in await repository.readJournal(day)) e.key: e.value,
      };
      expect(viaAdapter, {'mood': 4, 'caffeine_late': 1, 'caffeine_mg': 180});
    },
  );

  test('inline boolean write keeps the rest of the day', () async {
    await seedDay(
      day,
      mood: 4,
      moodAt: 480,
      late: 0,
      lateAt: 900,
      caffeine: 200,
      caffeineAt: 855,
    );

    await repository.writeJournal(day, 'caffeine_late', 1);

    final written = await LocalDb.journalMetricsForDay(day);
    expect(written['caffeine_late']!.value, 1);
    expect(written['caffeine_late']!.atMinuteOfDay, 900);
    expect(written['mood']!.value, 4);
    expect(written['mood']!.atMinuteOfDay, 480);
    expect(written['caffeine_mg']!.value, 200);
    expect(written['caffeine_mg']!.atMinuteOfDay, 855);
  });

  test('concurrent independent fields do not clobber each other', () async {
    await seedDay(
      day,
      mood: 3,
      moodAt: 480,
      late: 0,
      lateAt: 900,
      caffeine: 180,
      caffeineAt: 855,
    );

    await Future.wait([
      repository.writeJournal(day, 'mood', 5),
      repository.writeJournal(day, 'caffeine_late', 1),
    ]);

    final written = await LocalDb.journalMetricsForDay(day);
    expect(written['mood']!.value, 5);
    expect(written['mood']!.atMinuteOfDay, 480);
    expect(written['caffeine_late']!.value, 1);
    expect(written['caffeine_late']!.atMinuteOfDay, 900);
    expect(written['caffeine_mg']!.value, 180);
    expect(written['caffeine_mg']!.atMinuteOfDay, 855);
  });

  test('inserting a new boolean keeps siblings and the timed dose', () async {
    await LocalDb.putJournalMetrics(day, {
      'mood': const JournalMetricValue(3, atMinuteOfDay: 480),
      'caffeine_mg': const JournalMetricValue(180, atMinuteOfDay: 855),
    });

    await repository.writeJournal(day, 'alcohol_evening', 1);

    final written = await LocalDb.journalMetricsForDay(day);
    expect(written['alcohol_evening']!.value, 1);
    expect(written['alcohol_evening']!.atMinuteOfDay, isNull);
    expect(written['mood']!.value, 3);
    expect(written['mood']!.atMinuteOfDay, 480);
    expect(written['caffeine_mg']!.value, 180);
    expect(written['caffeine_mg']!.atMinuteOfDay, 855);
    expect(written.containsKey('caffeine_late'), isFalse);
  });

  test('a timed-dose value update keeps at_min', () async {
    await seedDay(
      day,
      mood: 3,
      moodAt: 480,
      late: 1,
      lateAt: 900,
      caffeine: 180,
      caffeineAt: 855,
    );

    await repository.writeJournal(day, 'caffeine_mg', 250);

    final written = await LocalDb.journalMetricsForDay(day);
    expect(written['caffeine_mg']!.value, 250);
    expect(written['caffeine_mg']!.atMinuteOfDay, 855);
    expect(written['mood']!.value, 3);
    expect(written['mood']!.atMinuteOfDay, 480);
    expect(written['caffeine_late']!.value, 1);
    expect(written['caffeine_late']!.atMinuteOfDay, 900);
  });

  test('a failed write leaves previous values in place', () async {
    await seedDay(
      day,
      mood: 3,
      moodAt: 480,
      late: 1,
      lateAt: 900,
      caffeine: 180,
      caffeineAt: 855,
    );

    expect(
      () => repository.writeJournal('not-a-day', 'mood', 5),
      throwsArgumentError,
    );
    expect(
      () => repository.writeJournal(day, 'mood', double.nan),
      throwsArgumentError,
    );
    expect(
      () => repository.writeJournal(day, 'mood', double.infinity),
      throwsArgumentError,
    );
    expect(
      () => repository.writeJournal(day, '', 1),
      throwsArgumentError,
    );

    final written = await LocalDb.journalMetricsForDay(day);
    expect(written['mood']!.value, 3);
    expect(written['mood']!.atMinuteOfDay, 480);
    expect(written['caffeine_late']!.value, 1);
    expect(written['caffeine_late']!.atMinuteOfDay, 900);
    expect(written['caffeine_mg']!.value, 180);
    expect(written['caffeine_mg']!.atMinuteOfDay, 855);
  });

  test('a SQLite UPDATE abort on the target field leaves previous rows in place',
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
    final db = await LocalDb.instance;
    await db.execute('''
      CREATE TEMP TRIGGER journal_metric_abort_mood_upd
      BEFORE UPDATE ON journal_metric
      WHEN NEW.field = 'mood'
      BEGIN
        SELECT RAISE(ABORT, 'test abort');
      END
    ''');
    try {
      await expectLater(
        repository.writeJournal(day, 'mood', 5),
        throwsA(isA<DatabaseException>()),
      );
    } finally {
      await db.execute('DROP TRIGGER IF EXISTS journal_metric_abort_mood_upd');
    }

    final written = await LocalDb.journalMetricsForDay(day);
    expect(written['mood']!.value, 3);
    expect(written['mood']!.atMinuteOfDay, 480);
    expect(written['caffeine_late']!.value, 1);
    expect(written['caffeine_late']!.atMinuteOfDay, 900);
    expect(written['caffeine_mg']!.value, 180);
    expect(written['caffeine_mg']!.atMinuteOfDay, 855);
  });

  test('a SQLite INSERT abort of a new mood leaves existing siblings in place',
      () async {
    await LocalDb.putJournalMetrics(day, {
      'caffeine_late': const JournalMetricValue(1, atMinuteOfDay: 900),
      'caffeine_mg': const JournalMetricValue(180, atMinuteOfDay: 855),
    });
    final db = await LocalDb.instance;
    await db.execute('''
      CREATE TEMP TRIGGER journal_metric_abort_mood_ins
      BEFORE INSERT ON journal_metric
      WHEN NEW.field = 'mood'
      BEGIN
        SELECT RAISE(ABORT, 'test abort');
      END
    ''');
    try {
      await expectLater(
        repository.writeJournal(day, 'mood', 5),
        throwsA(isA<DatabaseException>()),
      );
    } finally {
      await db.execute('DROP TRIGGER IF EXISTS journal_metric_abort_mood_ins');
    }

    final written = await LocalDb.journalMetricsForDay(day);
    expect(written.containsKey('mood'), isFalse);
    expect(written['caffeine_late']!.value, 1);
    expect(written['caffeine_late']!.atMinuteOfDay, 900);
    expect(written['caffeine_mg']!.value, 180);
    expect(written['caffeine_mg']!.atMinuteOfDay, 855);
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
    expect(written.containsKey('caffeine_late'), isFalse);
    expect(written.containsKey('caffeine_mg'), isFalse);
  });

  test('writeJournal clamps to the field ceiling, matching postJournalMetrics',
      () async {
    await repository.writeJournal(day, 'mood', 40);
    final written = await LocalDb.journalMetricsForDay(day);
    expect(written['mood']!.value, 5);
    expect(written['mood']!.atMinuteOfDay, isNull);
  });
}
