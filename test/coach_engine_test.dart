// CoachEngine log_journal — omitted tags/note must not full-row replace.
//
// Driven through debugRunTool + the existing ActionRequest confirm callback,
// against LocalRepositoryImpl + real SQLite.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/coach/coach_config.dart';
import 'package:openstrap_edge/coach/coach_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _day = '2026-09-15';
const _historical = '2020-01-01';

class _CountingRepo extends LocalRepositoryImpl {
  int patches = 0;
  _CountingRepo() : super(getProfileMap: () => const {});

  @override
  Future<void> patchJournalDay(JournalDayPatch patch) async {
    patches++;
    await super.patchJournalDay(patch);
  }
}

class _ReadFailRepo extends _CountingRepo {
  @override
  Future<JournalDaySnapshot> readJournalDay(String day) async {
    throw StateError('journal read failed');
  }
}

class _ConflictRepo extends _CountingRepo {
  @override
  Future<void> patchJournalDay(JournalDayPatch patch) async {
    throw JournalConflict(patch.day);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingRepo repo;
  late CoachEngine engine;
  ActionRequest? seen;
  var confirmOk = true;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await LocalDb.close();
    LocalDb.dbName = 'coach_engine_journal_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/${LocalDb.dbName}');
    repo = _CountingRepo();
    engine = CoachEngine(config: CoachConfig(), api: repo);
    seen = null;
    confirmOk = true;
  });

  tearDown(() async {
    await LocalDb.close();
  });

  Future<void> seedDay(
    String date, {
    List<String> tags = const ['late', 'travel'],
    String note = 'keep me',
  }) async {
    await LocalDb.putJournalMetrics(date, {
      'mood': const JournalMetricValue(3, atMinuteOfDay: 480),
      'caffeine_late': const JournalMetricValue(1, atMinuteOfDay: 900),
      'caffeine_mg': const JournalMetricValue(180, atMinuteOfDay: 855),
    });
    await LocalDb.putJournal(date, jsonEncode(tags), note);
  }

  Future<String> runLogJournal(Map<String, dynamic> args) {
    return engine.debugRunTool(
      'log_journal',
      args,
      confirm: (req) async {
        seen = req;
        return confirmOk;
      },
    );
  }

  Future<void> expectSiblingsIntact(String date) async {
    final snap = await repo.readJournalDay(date);
    expect(snap.metrics['mood']!.value, 3);
    expect(snap.metrics['mood']!.atMinuteOfDay, 480);
    expect(snap.metrics['caffeine_late']!.value, 1);
    expect(snap.metrics['caffeine_late']!.atMinuteOfDay, 900);
    expect(snap.metrics['caffeine_mg']!.value, 180);
    expect(snap.metrics['caffeine_mg']!.atMinuteOfDay, 855);
    expect(snap.metrics.containsKey('hydration_score'), isFalse);
    expect(snap.metrics.containsKey('custom_foo'), isFalse);
  }

  Future<void> expectSourceIntact(
    String date, {
    required List<String> tags,
    required String note,
    required String tagsJson,
  }) async {
    await expectSiblingsIntact(date);
    final snap = await repo.readJournalDay(date);
    expect(snap.tags, tags);
    expect(snap.note, note);
    final db = await LocalDb.instance;
    final row = (await db.query(
      'journal',
      where: 'date = ?',
      whereArgs: [date],
    )).single;
    expect(row['tags_json'], tagsJson);
    expect(row['note'], note);
  }

  group('log_journal confirmation', () {
    test('asks through ActionRequest and writes only after yes', () async {
      await seedDay(_day);
      final out = await runLogJournal({
        'date': _day,
        'note': 'new note',
      });
      expect(seen, isNotNull);
      expect(seen!.tool, 'log_journal');
      expect(seen!.title, 'Log journal');
      expect(seen!.args['date'], _day);
      expect(seen!.summary, 'Add journal for $_day: note "new note".');
      expect(seen!.summary, isNot(contains('tags')));
      expect(out, 'Journal saved.');
      expect(repo.patches, 1);
    });

    test('summary lists only supplied fields', () async {
      await seedDay(_day);
      await runLogJournal({
        'date': _day,
        'tags': const ['sick'],
      });
      expect(seen!.summary, 'Add journal for $_day: tags [sick].');
      expect(seen!.summary, isNot(contains('note')));

      seen = null;
      await runLogJournal({
        'date': _day,
        'tags': const ['sick'],
        'note': 'updated',
      });
      expect(
        seen!.summary,
        'Add journal for $_day: tags [sick], note "updated".',
      );
    });

    test('explicit empty is confirmed as a clear', () async {
      await seedDay(_day);
      await runLogJournal({
        'date': _day,
        'note': '',
      });
      expect(seen!.summary, 'Add journal for $_day: clear note.');
      expect(seen!.summary, isNot(contains('tags')));

      seen = null;
      await runLogJournal({
        'date': _day,
        'tags': const <String>[],
      });
      expect(seen!.summary, 'Add journal for $_day: clear tags.');
      expect(seen!.summary, isNot(contains('note')));

      seen = null;
      await runLogJournal({
        'date': _day,
        'tags': const <String>[],
        'note': '',
      });
      expect(seen!.summary, 'Add journal for $_day: clear tags, clear note.');
    });

    test('a declined confirmation writes nothing', () async {
      await seedDay(_day);
      confirmOk = false;
      final out = await runLogJournal({
        'date': _day,
        'note': 'should not land',
        'tags': const ['wiped'],
      });
      expect(
        seen!.summary,
        'Add journal for $_day: tags [wiped], note "should not land".',
      );
      expect(out, 'User declined the action. Do not retry it.');
      expect(repo.patches, 0);
      await expectSourceIntact(
        _day,
        tags: const ['late', 'travel'],
        note: 'keep me',
        tagsJson: jsonEncode(const ['late', 'travel']),
      );
    });
  });

  group('log_journal omitted vs explicit empty', () {
    test('omitted note retains the stored note', () async {
      await seedDay(_day);
      await runLogJournal({
        'date': _day,
        'tags': const ['sick'],
      });
      final snap = await repo.readJournalDay(_day);
      expect(snap.tags, ['sick']);
      expect(snap.note, 'keep me');
      await expectSiblingsIntact(_day);
    });

    test('omitted tags retain the stored tags', () async {
      await seedDay(_day);
      await runLogJournal({
        'date': _day,
        'note': 'updated',
      });
      final snap = await repo.readJournalDay(_day);
      expect(snap.note, 'updated');
      expect(snap.tags, ['late', 'travel']);
      await expectSiblingsIntact(_day);
    });

    test('null on one field is omitted, not a clear', () async {
      await seedDay(_day);
      await runLogJournal({
        'date': _day,
        'tags': const ['sick'],
        'note': null,
      });
      expect(seen!.summary, 'Add journal for $_day: tags [sick].');
      expect(seen!.summary, isNot(contains('note')));
      final snap = await repo.readJournalDay(_day);
      expect(snap.tags, ['sick']);
      expect(snap.note, 'keep me');
      await expectSiblingsIntact(_day);
    });

    test('missing both is a reject, not a saved no-op', () async {
      await seedDay(_day);
      final out = await runLogJournal({'date': _day});
      expect(out, isNot('Journal saved.'));
      expect(out, contains('No tags or note given'));
      expect(seen, isNull);
      expect(repo.patches, 0);
      await expectSourceIntact(
        _day,
        tags: const ['late', 'travel'],
        note: 'keep me',
        tagsJson: jsonEncode(const ['late', 'travel']),
      );

      final outNull = await runLogJournal({
        'date': _day,
        'tags': null,
        'note': null,
      });
      expect(outNull, contains('No tags or note given'));
      expect(seen, isNull);
      expect(repo.patches, 0);
      await expectSourceIntact(
        _day,
        tags: const ['late', 'travel'],
        note: 'keep me',
        tagsJson: jsonEncode(const ['late', 'travel']),
      );
    });

    test('missing or malformed date is refused before confirm', () async {
      await seedDay(_day);
      const poison = {'y': 2026, 'm': 9};

      for (final args in [
        {'note': 'new note'},
        {'date': poison, 'note': 'new note'},
        {'date': '2026-02-30', 'note': 'new note'},
        {'date': 'yesterday', 'note': 'new note'},
      ]) {
        seen = null;
        final out = await runLogJournal(args);
        expect(out, isNot('Journal saved.'));
        expect(out, contains('date must be a YYYY-MM-DD day'));
        expect(out, isNot(contains('null')));
        expect(out, isNot(contains('yesterday')));
        expect(out, isNot(contains('2026-02-30')));
        expect(seen, isNull);
        expect(repo.patches, 0);
      }

      await expectSourceIntact(
        _day,
        tags: const ['late', 'travel'],
        note: 'keep me',
        tagsJson: jsonEncode(const ['late', 'travel']),
      );
    });

    test('malformed supplied types are refused without confirm or write',
        () async {
      await seedDay(_day);
      const poison = {'nested': 'object'};

      for (final args in [
        {'date': _day, 'tags': 'late'},
        {'date': _day, 'tags': poison},
        {
          'date': _day,
          'tags': [poison],
        },
        {'date': _day, 'note': poison},
        {
          'date': _day,
          'note': ['not', 'a', 'string'],
        },
      ]) {
        seen = null;
        final out = await runLogJournal(args);
        expect(out, isNot('Journal saved.'));
        expect(out, contains('failed'));
        expect(out, isNot(contains('nested')));
        expect(out, isNot(contains('object')));
        expect(seen, isNull);
        expect(repo.patches, 0);
      }

      await expectSourceIntact(
        _day,
        tags: const ['late', 'travel'],
        note: 'keep me',
        tagsJson: jsonEncode(const ['late', 'travel']),
      );
    });

    test('explicit empty clears only the requested field', () async {
      await seedDay(_day);
      await runLogJournal({
        'date': _day,
        'note': '',
      });
      var snap = await repo.readJournalDay(_day);
      expect(snap.note, '');
      expect(snap.tags, ['late', 'travel']);
      await expectSiblingsIntact(_day);

      await seedDay(_day);
      await runLogJournal({
        'date': _day,
        'tags': const <String>[],
      });
      snap = await repo.readJournalDay(_day);
      expect(snap.tags, isEmpty);
      expect(snap.note, 'keep me');
      await expectSiblingsIntact(_day);
    });

    test('an old day outside the 30d window is an exact-day write', () async {
      await seedDay(_historical);
      final recent = await repo.getJournal(range: '30d');
      expect(recent.any((r) => r['date'] == _historical), isFalse);

      await runLogJournal({
        'date': _historical,
        'note': 'years later',
      });
      final snap = await repo.readJournalDay(_historical);
      expect(snap.day, _historical);
      expect(snap.note, 'years later');
      expect(snap.tags, ['late', 'travel']);
      await expectSiblingsIntact(_historical);
    });
  });

  group('log_journal refusal writes nothing', () {
    test('a failed read preserves the stored row', () async {
      await seedDay(_day);
      engine = CoachEngine(config: CoachConfig(), api: repo = _ReadFailRepo());
      final out = await runLogJournal({
        'date': _day,
        'note': 'new note',
      });
      expect(out, contains('failed'));
      expect(repo.patches, 0);
      engine = CoachEngine(config: CoachConfig(), api: repo = _CountingRepo());
      await expectSourceIntact(
        _day,
        tags: const ['late', 'travel'],
        note: 'keep me',
        tagsJson: jsonEncode(const ['late', 'travel']),
      );
    });

    test('corrupt tags refuse the write and keep the source', () async {
      await LocalDb.putJournalMetrics(_day, {
        'mood': const JournalMetricValue(3, atMinuteOfDay: 480),
        'caffeine_late': const JournalMetricValue(1, atMinuteOfDay: 900),
        'caffeine_mg': const JournalMetricValue(180, atMinuteOfDay: 855),
      });
      const corrupt = '{not-json';
      await LocalDb.putJournal(_day, corrupt, 'old note');

      final out = await runLogJournal({
        'date': _day,
        'note': 'new note',
      });
      expect(out, contains('failed'));
      expect(repo.patches, 0);

      final db = await LocalDb.instance;
      final row = (await db.query(
        'journal',
        where: 'date = ?',
        whereArgs: [_day],
      )).single;
      expect(row['tags_json'], corrupt);
      expect(row['note'], 'old note');
      final metrics = await LocalDb.journalMetricsForDay(_day);
      expect(metrics['mood']!.value, 3);
      expect(metrics['caffeine_mg']!.atMinuteOfDay, 855);
    });

    test('a conflict refuses the write and keeps the source', () async {
      await seedDay(_day);
      engine = CoachEngine(config: CoachConfig(), api: repo = _ConflictRepo());
      final out = await runLogJournal({
        'date': _day,
        'note': 'new note',
      });
      expect(out, contains('failed'));
      expect(out, contains('updated elsewhere'));
      engine = CoachEngine(config: CoachConfig(), api: repo = _CountingRepo());
      await expectSourceIntact(
        _day,
        tags: const ['late', 'travel'],
        note: 'keep me',
        tagsJson: jsonEncode(const ['late', 'travel']),
      );
    });
  });

  group('log_journal_fields through the engine', () {
    test('value-only caffeine keeps dose time and siblings', () async {
      await seedDay(_day);
      ActionRequest? fieldsSeen;
      final out = await engine.debugRunTool(
        'log_journal_fields',
        {
          'date': _day,
          'fields': {'caffeine_mg': 250},
        },
        confirm: (req) async {
          fieldsSeen = req;
          return true;
        },
      );
      expect(fieldsSeen!.tool, 'log_journal_fields');
      expect(jsonDecode(out)['saved'], isTrue);
      final snap = await repo.readJournalDay(_day);
      expect(snap.metrics['caffeine_mg']!.value, 250);
      expect(snap.metrics['caffeine_mg']!.atMinuteOfDay, 855);
      expect(snap.metrics['mood']!.value, 3);
      expect(snap.tags, ['late', 'travel']);
      expect(snap.note, 'keep me');
      expect(snap.metrics.containsKey('hydration_score'), isFalse);
    });
  });
}
