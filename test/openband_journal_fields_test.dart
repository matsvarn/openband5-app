// Custom journal definition persistence: hide is not purge.
//
// Real SQLite. OpenBand list/create/hide/restore plus LocalDb contracts.
// No editor UI.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/csv_export.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => root;
  @override
  Future<String?> getLibraryPath() async => root;
  @override
  Future<String?> getDownloadsPath() async => root;
}

Map _loadFixture(String name) =>
    jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync())
        as Map;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late AppState app;
  late LocalRepositoryImpl repo;
  late LocalOpenBandRepository openband;

  const day = '2026-09-15';
  const mag = JournalFieldSpec(
    key: 'custom_magnesium',
    label: 'Magnesium',
    kind: JournalFieldKind.dose,
    unit: 'mg',
    max: 1000,
    step: 50,
    hasTime: true,
    custom: true,
  );

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('openstrap_journal_fields_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDownAll(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  setUp(() async {
    await LocalDb.close();
    LocalDb.dbName = 'openstrap_journal_fields_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    app = AppState.forTesting();
    repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    app.repo = repo;
    openband = LocalOpenBandRepository(app);
  });

  tearDown(() async {
    app.dispose();
    await LocalDb.close();
  });

  test('hide keeps values, time, label, unit and drops the active list',
      () async {
    await openband.createJournalField(mag);
    final empty = await repo.readJournalDay(day);
    await repo.patchJournalDay(
      JournalDayPatch.fromBase(
        empty,
        metrics: const {
          'custom_magnesium': JournalMetricValue(400, atMinuteOfDay: 855),
        },
      ),
    );

    await openband.hideJournalField(mag.key);

    final active = await openband.listJournalFields();
    expect(active.any((f) => f.key == mag.key), isFalse);
    expect(
      (await repo.getJournalFields()).any((f) => f.key == mag.key),
      isFalse,
    );

    final all = await openband.listJournalFields(includeHidden: true);
    final hidden = all.singleWhere((f) => f.key == mag.key);
    expect(hidden.hidden, isTrue);
    expect(hidden.label, 'Magnesium');
    expect(hidden.unit, 'mg');
    expect(hidden.kind, JournalFieldKind.dose);
    expect(hidden.hasTime, isTrue);
    expect(hidden.max, 1000);
    expect(hidden.step, 50);

    final snap = await repo.readJournalDay(day);
    expect(snap.metrics['custom_magnesium']!.value, 400);
    expect(snap.metrics['custom_magnesium']!.atMinuteOfDay, 855);
    expect(snap.fields.any((f) => f.key == mag.key), isFalse);
  });

  test('timeline after hide still shows the original label, unit and time',
      () async {
    await openband.createJournalField(mag);
    final empty = await repo.readJournalDay(day);
    await repo.patchJournalDay(
      JournalDayPatch.fromBase(
        empty,
        metrics: const {
          'custom_magnesium': JournalMetricValue(400, atMinuteOfDay: 855),
        },
      ),
    );
    await openband.hideJournalField(mag.key);

    expect(
      (await repo.getJournalFields()).any((f) => f.key == mag.key),
      isFalse,
    );
    final historic = await repo.getJournalFields(includeHidden: true);
    final spec = historic.singleWhere((f) => f.key == mag.key);
    expect(spec.hidden, isTrue);
    expect(spec.label, 'Magnesium');
    expect(spec.unit, 'mg');
    expect(spec.hasTime, isTrue);

    final stored = await repo.getJournalMetrics(day);
    expect(stored['custom_magnesium']!.value, 400);
    expect(stored['custom_magnesium']!.atMinuteOfDay, 855);
  });

  test('dirty patch after hide keeps the hidden answer beside mood and note',
      () async {
    await openband.createJournalField(mag);
    final empty = await repo.readJournalDay(day);
    await repo.patchJournalDay(
      JournalDayPatch.fromBase(
        empty,
        metrics: const {
          'custom_magnesium': JournalMetricValue(400, atMinuteOfDay: 855),
          'mood': JournalMetricValue(3, atMinuteOfDay: 480),
        },
        note: 'keep me',
      ),
    );
    await openband.hideJournalField(mag.key);
    expect(
      (await repo.getJournalFields()).any((f) => f.key == mag.key),
      isFalse,
    );

    final snap = await repo.readJournalDay(day);
    await repo.patchJournalDay(
      JournalDayPatch.fromBase(
        snap,
        metrics: const {
          'custom_magnesium': JournalMetricValue(500, atMinuteOfDay: 855),
          'mood': JournalMetricValue(4, atMinuteOfDay: 480),
        },
      ),
    );

    final after = await repo.readJournalDay(day);
    expect(after.metrics['custom_magnesium']!.value, 500);
    expect(after.metrics['custom_magnesium']!.atMinuteOfDay, 855);
    expect(after.metrics['mood']!.value, 4);
    expect(after.metrics['mood']!.atMinuteOfDay, 480);
    expect(after.note, 'keep me');
    expect(after.fields.any((f) => f.key == mag.key), isFalse);

    await expectLater(
      repo.patchJournalDay(
        JournalDayPatch.fromBase(
          after,
          metrics: const {
            'mood': JournalMetricValue(5, atMinuteOfDay: 480),
            'custom_magnesium': JournalMetricValue(5000, atMinuteOfDay: 855),
          },
        ),
      ),
      throwsArgumentError,
    );
    final still = await repo.readJournalDay(day);
    expect(still.metrics['custom_magnesium']!.value, 500);
    expect(still.metrics['custom_magnesium']!.atMinuteOfDay, 855);
    expect(still.metrics['mood']!.value, 4);
    expect(still.note, 'keep me');

    await expectLater(
      repo.patchJournalDay(
        JournalDayPatch.fromBase(
          still,
          metrics: const {'custom_orphan': JournalMetricValue(9)},
        ),
      ),
      throwsArgumentError,
    );
    expect(
      (await repo.readJournalDay(day)).metrics['custom_magnesium']!.value,
      500,
    );
  });

  test('restore reactivates the same identity', () async {
    await openband.createJournalField(mag);
    await openband.hideJournalField(mag.key);
    await openband.restoreJournalField(mag.key);

    final active = await openband.listJournalFields();
    final back = active.singleWhere((f) => f.key == mag.key);
    expect(back.hidden, isFalse);
    expect(back.label, 'Magnesium');
    expect(back.unit, 'mg');
    expect(back.kind, JournalFieldKind.dose);
  });

  test('recreate of a hidden or orphan key is refused', () async {
    await openband.createJournalField(mag);
    await openband.hideJournalField(mag.key);
    await expectLater(openband.createJournalField(mag), throwsStateError);

    await LocalDb.putJournalMetrics(day, {
      'custom_orphan': const JournalMetricValue(9),
    });
    await expectLater(
      openband.createJournalField(
        const JournalFieldSpec(
          key: 'custom_orphan',
          label: 'Orphan',
          kind: JournalFieldKind.dose,
          unit: 'mg',
          max: 10,
          step: 1,
          custom: true,
        ),
      ),
      throwsStateError,
    );
  });

  test('a new key cannot attach old history', () async {
    await openband.createJournalField(mag);
    await LocalDb.putJournalMetrics(day, {
      'custom_magnesium': const JournalMetricValue(400, atMinuteOfDay: 480),
    });
    await openband.hideJournalField(mag.key);

    const other = JournalFieldSpec(
      key: 'custom_magnesium_b',
      label: 'Magnesium citrate',
      kind: JournalFieldKind.dose,
      unit: 'g',
      max: 5,
      step: 0.5,
      custom: true,
    );
    await openband.createJournalField(other);

    final snap = await repo.readJournalDay(day);
    expect(snap.metrics['custom_magnesium']!.value, 400);
    expect(snap.metrics['custom_magnesium']!.atMinuteOfDay, 480);
    expect(snap.metrics.containsKey('custom_magnesium_b'), isFalse);
    expect(snap.fields.any((f) => f.key == 'custom_magnesium_b'), isTrue);
    expect(snap.fields.any((f) => f.key == 'custom_magnesium'), isFalse);
  });

  test('corrupt definitions fail instead of becoming a dose', () async {
    final db = await LocalDb.instance;
    await db.insert('journal_field_def', {
      'key': 'custom_future',
      'label': 'From the future',
      'kind': 'something_new',
      'unit': 'x',
      'max_value': 10.0,
      'step': 1.0,
      'has_time': 0,
      'created_at': 0,
    });
    await expectLater(
      openband.listJournalFields(includeHidden: true),
      throwsA(isA<FormatException>()),
    );
  });

  test('corrupt numeric constraints and malformed flags fail on read', () async {
    final db = await LocalDb.instance;
    await db.insert('journal_field_def', {
      'key': 'custom_zero_max',
      'label': 'Zero',
      'kind': 'dose',
      'unit': 'mg',
      'max_value': 0.0,
      'step': 1.0,
      'has_time': 0,
      'created_at': 0,
      'hidden': 0,
    });
    await expectLater(
      LocalDb.journalFieldDefs(includeHidden: true),
      throwsA(isA<FormatException>()),
    );
    await db.delete('journal_field_def');
    await db.insert('journal_field_def', {
      'key': 'custom_frac_rating',
      'label': 'Frac',
      'kind': 'rating',
      'unit': '',
      'max_value': 5.5,
      'step': 1.0,
      'has_time': 0,
      'created_at': 0,
      'hidden': 0,
    });
    await expectLater(
      LocalDb.journalFieldDefs(includeHidden: true),
      throwsA(isA<FormatException>()),
    );
    await db.delete('journal_field_def');
    await db.insert('journal_field_def', {
      'key': 'custom_bad_flag',
      'label': 'Flag',
      'kind': 'dose',
      'unit': 'mg',
      'max_value': 10.0,
      'step': 1.0,
      'has_time': 2,
      'created_at': 0,
      'hidden': 0,
    });
    await expectLater(
      LocalDb.journalFieldDefs(includeHidden: true),
      throwsA(isA<FormatException>()),
    );
  });

  test('a stored legacy rating max 1 still reads', () async {
    final db = await LocalDb.instance;
    await db.insert('journal_field_def', {
      'key': 'custom_walk_after_lunch',
      'label': 'Walk after lunch',
      'kind': 'rating',
      'unit': '',
      'max_value': 1.0,
      'step': 1.0,
      'has_time': 0,
      'created_at': 0,
      'hidden': 0,
    });
    final stored = await LocalDb.journalFieldDefs();
    expect(stored.single.key, 'custom_walk_after_lunch');
    expect(stored.single.max, 1);
    expect(stored.single.kind, JournalFieldKind.rating);
  });

  test('fractional rating max is refused at create', () async {
    await expectLater(
      LocalDb.putJournalFieldDef(
        const JournalFieldSpec(
          key: 'custom_frac',
          label: 'Frac',
          kind: JournalFieldKind.rating,
          unit: '',
          max: 5.5,
          step: 1,
          custom: true,
        ),
      ),
      throwsArgumentError,
    );
    expect(await LocalDb.journalFieldDefs(includeHidden: true), isEmpty);
  });

  test('unknown saved keys survive an unrelated patch', () async {
    await LocalDb.putJournalMetrics(day, {
      'mood': const JournalMetricValue(3, atMinuteOfDay: 480),
      'custom_orphan': const JournalMetricValue(9, atMinuteOfDay: 900),
    });
    final snap = await repo.readJournalDay(day);
    expect(snap.metrics['custom_orphan']!.value, 9);
    await repo.patchJournalDay(
      JournalDayPatch.fromBase(
        snap,
        metrics: const {'mood': JournalMetricValue(4, atMinuteOfDay: 480)},
      ),
    );
    final after = await repo.readJournalDay(day);
    expect(after.metrics['mood']!.value, 4);
    expect(after.metrics['custom_orphan']!.value, 9);
    expect(after.metrics['custom_orphan']!.atMinuteOfDay, 900);
  });

  test('day export carries hidden definitions', () async {
    await openband.createJournalField(mag);
    await LocalDb.putJournalMetrics(day, {
      'custom_magnesium': const JournalMetricValue(400, atMinuteOfDay: 855),
    });
    await openband.hideJournalField(mag.key);

    final path = await LocalDb.exportDaysDb({day});
    final exported = await databaseFactory.openDatabase(path);
    try {
      final metrics = await exported.query('journal_metric');
      expect(metrics.single['field'], 'custom_magnesium');
      expect(metrics.single['value'], 400);
      expect(metrics.single['at_min'], 855);
      final defs = await exported.query('journal_field_def');
      expect(defs.single['label'], 'Magnesium');
      expect(defs.single['unit'], 'mg');
      expect(defs.single['kind'], 'dose');
      expect(defs.single['hidden'], 1);
    } finally {
      await exported.close();
    }
  });

  test('habits CSV join keeps the hidden label and unit', () async {
    await openband.createJournalField(mag);
    await LocalDb.putJournalMetrics(day, {
      'custom_magnesium': const JournalMetricValue(400),
    });
    await openband.hideJournalField(mag.key);
    final habits = kCsvExportSets.firstWhere((s) => s.name == 'habits');
    final db = await LocalDb.instance;
    final rows = await db.rawQuery(habits.sql);
    final row = rows.singleWhere((r) => r['field'] == 'custom_magnesium');
    expect(row['label'], 'Magnesium');
    expect(row['unit'], 'mg');
    expect(row['value'], 400);
  });

  test('hidden column repair is idempotent on an old-shaped table', () async {
    final db = await LocalDb.instance;
    await db.execute(
      'ALTER TABLE journal_field_def RENAME TO journal_field_def_modern',
    );
    await db.execute('''
      CREATE TABLE journal_field_def (
        key TEXT PRIMARY KEY,
        label TEXT NOT NULL,
        kind TEXT NOT NULL,
        unit TEXT NOT NULL DEFAULT '',
        max_value REAL NOT NULL,
        step REAL NOT NULL,
        has_time INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.insert('journal_field_def', {
      'key': 'custom_magnesium',
      'label': 'Magnesium',
      'kind': 'dose',
      'unit': 'mg',
      'max_value': 1000.0,
      'step': 50.0,
      'has_time': 1,
      'created_at': 0,
    });
    await db.execute('DROP TABLE journal_field_def_modern');
    await LocalDb.close();

    Future<void> expectRepaired() async {
      final opened = await LocalDb.instance;
      final info = await opened.rawQuery(
        'PRAGMA table_info(journal_field_def)',
      );
      expect(info.any((c) => c['name'] == 'hidden'), isTrue);
      final defs = await LocalDb.journalFieldDefs(includeHidden: true);
      expect(defs.single.label, 'Magnesium');
      expect(defs.single.unit, 'mg');
      expect(defs.single.hasTime, isTrue);
      expect(defs.single.hidden, isFalse);
    }

    await expectRepaired();
    await LocalDb.close();
    await expectRepaired();
  });

  test('schemaHealth requires journal_field_def.hidden', () async {
    expect((await LocalDb.schemaHealth())['ok'], isTrue);
    final db = await LocalDb.instance;
    await db.execute(
      'ALTER TABLE journal_field_def RENAME TO journal_field_def_modern',
    );
    await db.execute('''
      CREATE TABLE journal_field_def (
        key TEXT PRIMARY KEY,
        label TEXT NOT NULL,
        kind TEXT NOT NULL,
        unit TEXT NOT NULL DEFAULT '',
        max_value REAL NOT NULL,
        step REAL NOT NULL,
        has_time INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('DROP TABLE journal_field_def_modern');
    final broken = await LocalDb.schemaHealth();
    expect(broken['ok'], isFalse);
    expect(
      (broken['missing_columns'] as Map)['journal_field_def'],
      contains('hidden'),
    );
  });

  test('create accepts unicode labels and UUID keys', () async {
    final key = newCustomJournalFieldKey();
    final stored = await openband.createJournalField(
      JournalFieldSpec(
        key: key,
        label: '  Übung  ',
        kind: JournalFieldKind.dose,
        unit: 'mg',
        max: 400,
        step: 50,
        custom: true,
      ),
    );
    expect(stored.key, key);
    expect(stored.label, 'Übung');
    expect(stored.hidden, isFalse);
    expect(stored.custom, isTrue);
  });

  test('wellness-shaped rating max 1 still creates', () async {
    await repo.postCustomJournalField(
      const JournalFieldSpec(
        key: 'custom_walk_after_lunch',
        label: 'Walk after lunch',
        kind: JournalFieldKind.rating,
        unit: '',
        max: 1,
        step: 1,
        custom: true,
      ),
    );
    final stored = await LocalDb.journalFieldDefs();
    expect(stored.single.max, 1);
    expect(stored.single.kind, JournalFieldKind.rating);
  });

  test('deleteCustomJournalField is a soft-hide', () async {
    await repo.postCustomJournalField(mag);
    await LocalDb.putJournalMetrics(day, {
      'custom_magnesium': const JournalMetricValue(400),
    });
    await repo.deleteCustomJournalField(mag.key);
    expect(
      (await repo.getJournalFields()).any((f) => f.key == mag.key),
      isFalse,
    );
    expect(
      (await LocalDb.journalFieldDefs(includeHidden: true)).single.hidden,
      isTrue,
    );
    expect(
      (await LocalDb.journalMetricsForDay(day))['custom_magnesium']!.value,
      400,
    );
  });

  test('synthetic adapter hide/restore matches the local contract', () async {
    final synthetic = SyntheticOpenBandRepository.fromMaps(
      _loadFixture('day-summary.json'),
      _loadFixture('sleep-detail.json'),
    );
    await synthetic.createJournalField(mag);
    final empty = await synthetic.readJournalDay(day);
    await synthetic.patchJournalDay(
      JournalDayPatch.fromBase(
        empty,
        metrics: const {
          'custom_magnesium': JournalMetricValue(400, atMinuteOfDay: 855),
          'mood': JournalMetricValue(3, atMinuteOfDay: 480),
        },
        note: 'keep me',
      ),
    );
    await synthetic.hideJournalField(mag.key);
    expect(
      (await synthetic.listJournalFields()).any((f) => f.key == mag.key),
      isFalse,
    );
    expect(
      (await synthetic.listJournalFields(includeHidden: true))
          .singleWhere((f) => f.key == mag.key)
          .hidden,
      isTrue,
    );
    expect(
      (await synthetic.readJournal(day)).any((e) => e.key == mag.key),
      isTrue,
    );
    await expectLater(synthetic.createJournalField(mag), throwsStateError);

    final hiddenSnap = await synthetic.readJournalDay(day);
    await synthetic.patchJournalDay(
      JournalDayPatch.fromBase(
        hiddenSnap,
        metrics: const {
          'custom_magnesium': JournalMetricValue(500, atMinuteOfDay: 855),
          'mood': JournalMetricValue(4, atMinuteOfDay: 480),
        },
      ),
    );
    final patched = await synthetic.readJournalDay(day);
    expect(patched.metrics['custom_magnesium']!.value, 500);
    expect(patched.metrics['custom_magnesium']!.atMinuteOfDay, 855);
    expect(patched.metrics['mood']!.value, 4);
    expect(patched.metrics['mood']!.atMinuteOfDay, 480);
    expect(patched.note, 'keep me');
    await expectLater(
      synthetic.patchJournalDay(
        JournalDayPatch.fromBase(
          patched,
          metrics: const {
            'mood': JournalMetricValue(5, atMinuteOfDay: 480),
            'custom_magnesium': JournalMetricValue(5000, atMinuteOfDay: 855),
          },
        ),
      ),
      throwsArgumentError,
    );
    final still = await synthetic.readJournalDay(day);
    expect(still.metrics['custom_magnesium']!.value, 500);
    expect(still.metrics['mood']!.value, 4);

    await synthetic.restoreJournalField(mag.key);
    expect(
      (await synthetic.listJournalFields()).any((f) => f.key == mag.key),
      isTrue,
    );
  });
}
