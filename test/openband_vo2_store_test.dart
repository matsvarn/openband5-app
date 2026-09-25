import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/vo2_store.dart';
import 'package:openstrap_edge/openband/vo2_data.dart';
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

Future<String> _path(String name) async =>
    p.join(await databaseFactory.getDatabasesPath(), name);

Future<Database> _use(String name) async {
  await LocalDb.close();
  LocalDb.dbName = name;
  await databaseFactory.deleteDatabase(await _path(name));
  return LocalDb.instance;
}

Vo2Revision _committed(Vo2WriteResult result) {
  expect(result, isA<Vo2Committed>());
  final committed = result as Vo2Committed;
  expect(committed.retry, isFalse);
  return committed.revision;
}

Future<int> _count(Database db, [String? id]) async {
  final rows = await db.rawQuery(
    id == null
        ? 'SELECT COUNT(*) AS n FROM manual_vo2'
        : 'SELECT COUNT(*) AS n FROM manual_vo2 WHERE id = ?',
    id == null ? null : [id],
  );
  return (rows.first['n'] as num).toInt();
}

Future<void> _sourceTable(Database db) async {
  await db.execute('''
    CREATE TABLE manual_vo2 (
      id TEXT NOT NULL,
      revision INTEGER NOT NULL,
      measured_on TEXT NOT NULL,
      value_ml_kg_min REAL NOT NULL,
      declared_method TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted INTEGER NOT NULL,
      origin TEXT NOT NULL,
      unit TEXT NOT NULL,
      PRIMARY KEY (id, revision)
    )
  ''');
}

Map<String, Object?> _raw({
  required String id,
  required int revision,
  required String measuredOn,
  required double value,
  String? method,
  required int createdAt,
  required int updatedAt,
  bool deleted = false,
}) => {
  'id': id,
  'revision': revision,
  'measured_on': measuredOn,
  'value_ml_kg_min': value,
  'declared_method': method,
  'created_at': createdAt,
  'updated_at': updatedAt,
  'deleted': deleted ? 1 : 0,
  'origin': kVo2Origin,
  'unit': kVo2Unit,
};

void main() {
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('openstrap_vo2_store_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    vo2ChainPageSize = 2;
  });

  tearDown(() async => LocalDb.close());

  tearDownAll(() async {
    vo2ChainPageSize = 32;
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('create, edit, reopen keep the date, value, and original time', () async {
    final db = await _use('vo2_reopen.db');
    final createdAt = DateTime(2026, 9, 14, 9, 41);
    final created = _committed(
      await Vo2Store.create(
        db,
        id: 'entry-1',
        measuredOn: '2026-03-29',
        valueMlKgMin: 42.5,
        declaredMethod: '  Spiroergometrie  ',
        now: createdAt,
      ),
    );
    expect(created.revision, 1);
    expect(created.measuredOn, '2026-03-29');
    expect(created.declaredMethod, 'Spiroergometrie');
    expect(created.origin, kVo2Origin);
    expect(created.unit, kVo2Unit);
    expect(created.createdAt, createdAt.millisecondsSinceEpoch);

    final edited = _committed(
      await Vo2Store.edit(
        db,
        id: 'entry-1',
        expectedRevision: 1,
        measuredOn: '2026-09-14',
        valueMlKgMin: 250,
        declaredMethod: '   ',
        now: createdAt,
      ),
    );
    expect(edited.revision, 2);
    expect(edited.createdAt, created.createdAt);
    expect(edited.updatedAt, greaterThan(created.updatedAt));
    expect(edited.declaredMethod, isNull);
    expect(edited.valueMlKgMin, 250);

    await LocalDb.close();
    final reopened = await LocalDb.instance;
    final detail = await Vo2Store.detail(reopened, 'entry-1');
    expect(detail.head?.measuredOn, '2026-09-14');
    expect(detail.head?.valueMlKgMin, 250);
    expect(detail.head?.createdAt, created.createdAt);
    expect(detail.revisions, hasLength(2));
    expect(detail.revisions.map((r) => r.revision), [1, 2]);
  });

  test('invalid input and a missing id write nothing', () async {
    final db = await _use('vo2_reject.db');
    final now = DateTime(2026, 9, 14, 9);
    for (final value in [0.0, -3.0, double.nan, double.infinity]) {
      final result = await Vo2Store.create(
        db,
        id: 'entry-1',
        measuredOn: '2026-09-14',
        valueMlKgMin: value,
        now: now,
      );
      expect(result, isA<Vo2WriteRejected>());
      expect((result as Vo2WriteRejected).reason, Vo2RejectReason.invalid);
    }
    expect(
      await Vo2Store.create(
        db,
        id: 'entry-1',
        measuredOn: '2026-02-31',
        valueMlKgMin: 40,
        now: now,
      ),
      isA<Vo2WriteRejected>(),
    );
    expect(
      await Vo2Store.create(
        db,
        id: '  ',
        measuredOn: '2026-09-14',
        valueMlKgMin: 40,
        now: now,
      ),
      isA<Vo2WriteRejected>(),
    );
    final missing = await Vo2Store.edit(
      db,
      id: 'absent',
      expectedRevision: 1,
      measuredOn: '2026-09-14',
      valueMlKgMin: 40,
      now: now,
    );
    expect(missing, isA<Vo2WriteRejected>());
    expect((missing as Vo2WriteRejected).reason, Vo2RejectReason.missing);
    expect(await _count(db), 0);
    final list = await Vo2Store.list(db);
    expect(list.isEmptyStore, isTrue);
    expect(list.corruptCount, 0);
  });

  test('stale edit conflicts and an exact retry does not duplicate', () async {
    final db = await _use('vo2_cas.db');
    final t1 = DateTime(2026, 9, 14, 9);
    final t2 = DateTime(2026, 9, 14, 10);
    _committed(
      await Vo2Store.create(
        db,
        id: 'entry-1',
        measuredOn: '2026-09-14',
        valueMlKgMin: 40,
        now: t1,
      ),
    );
    final createRetry = await Vo2Store.create(
      db,
      id: 'entry-1',
      measuredOn: '2026-09-14',
      valueMlKgMin: 40,
      now: t2,
    );
    expect(createRetry, isA<Vo2Committed>());
    expect((createRetry as Vo2Committed).retry, isTrue);
    expect(createRetry.revision.revision, 1);
    expect(await _count(db, 'entry-1'), 1);
    final edited = _committed(
      await Vo2Store.edit(
        db,
        id: 'entry-1',
        expectedRevision: 1,
        measuredOn: '2026-09-14',
        valueMlKgMin: 41,
        now: t2,
      ),
    );
    final retry = await Vo2Store.edit(
      db,
      id: 'entry-1',
      expectedRevision: 1,
      measuredOn: '2026-09-14',
      valueMlKgMin: 41,
      now: t2,
    );
    expect(retry, isA<Vo2Committed>());
    expect((retry as Vo2Committed).retry, isTrue);
    expect(retry.revision.revision, edited.revision);
    expect(await _count(db, 'entry-1'), 2);

    final stale = await Vo2Store.edit(
      db,
      id: 'entry-1',
      expectedRevision: 1,
      measuredOn: '2026-09-14',
      valueMlKgMin: 99,
      now: DateTime(2026, 9, 14, 11),
    );
    expect(stale, isA<Vo2WriteConflict>());
    expect((stale as Vo2WriteConflict).head?.valueMlKgMin, 41);
    expect(await _count(db, 'entry-1'), 2);
    expect((await Vo2Store.detail(db, 'entry-1')).head?.valueMlKgMin, 41);
  });

  test('delete and restore append, and the payload stays on the tombstone', () async {
    final db = await _use('vo2_delete.db');
    final t1 = DateTime(2026, 9, 14, 9);
    final created = _committed(
      await Vo2Store.create(
        db,
        id: 'entry-1',
        measuredOn: '2026-09-14',
        valueMlKgMin: 42.5,
        declaredMethod: 'lab',
        now: t1,
      ),
    );
    final deleted = _committed(
      await Vo2Store.delete(
        db,
        id: 'entry-1',
        expectedRevision: 1,
        now: DateTime(2026, 9, 14, 10),
      ),
    );
    expect(deleted.deleted, isTrue);
    expect(deleted.valueMlKgMin, 42.5);
    expect(deleted.declaredMethod, 'lab');
    expect(deleted.createdAt, created.createdAt);
    expect(deleted.updatedAt, greaterThan(created.updatedAt));

    final deleteRetry = await Vo2Store.delete(
      db,
      id: 'entry-1',
      expectedRevision: 1,
      now: DateTime(2026, 9, 15),
    );
    expect((deleteRetry as Vo2Committed).retry, isTrue);
    expect(await _count(db, 'entry-1'), 2);

    final restored = _committed(
      await Vo2Store.restore(
        db,
        id: 'entry-1',
        expectedRevision: 2,
        now: DateTime(2026, 9, 14, 11),
      ),
    );
    expect(restored.deleted, isFalse);
    expect(restored.revision, 3);
    expect(restored.valueMlKgMin, 42.5);
    expect(restored.createdAt, created.createdAt);
    expect(await _count(db, 'entry-1'), 3);

    final editWhileDeleted = await Vo2Store.edit(
      db,
      id: 'entry-1',
      expectedRevision: 2,
      measuredOn: '2026-09-14',
      valueMlKgMin: 10,
      now: DateTime(2026, 9, 14, 12),
    );
    expect(editWhileDeleted, isA<Vo2WriteConflict>());
    expect(await _count(db, 'entry-1'), 3);
  });

  test('a corrupt head is not replaced by the previous value', () async {
    final db = await _use('vo2_corrupt_head.db');
    _committed(
      await Vo2Store.create(
        db,
        id: 'entry-1',
        measuredOn: '2026-09-01',
        valueMlKgMin: 40,
        now: DateTime(2026, 9, 1, 8),
      ),
    );
    await db.insert('manual_vo2', {
      'id': 'entry-1',
      'revision': 2,
      'measured_on': 'not-a-date',
      'value_ml_kg_min': 99,
      'declared_method': null,
      'created_at': 1,
      'updated_at': 2,
      'deleted': 0,
      'origin': kVo2Origin,
      'unit': kVo2Unit,
    });
    final list = await Vo2Store.list(db);
    expect(list.isEmptyStore, isFalse);
    expect(list.corruptCount, 1);
    expect(list.entries.single.corrupt, isTrue);
    expect(list.entries.single.head, isNull);

    final detail = await Vo2Store.detail(db, 'entry-1');
    expect(detail.missing, isFalse);
    expect(detail.headCorrupt, isTrue);
    expect(detail.head, isNull);
    expect(detail.revisions.first.value?.valueMlKgMin, 40);
    expect(detail.corruptRevisionCount, 1);

    final edit = await Vo2Store.edit(
      db,
      id: 'entry-1',
      expectedRevision: 2,
      measuredOn: '2026-09-14',
      valueMlKgMin: 41,
      now: DateTime(2026, 9, 14),
    );
    expect(edit, isA<Vo2WriteConflict>());
    expect((edit as Vo2WriteConflict).headCorrupt, isTrue);
    expect(await _count(db, 'entry-1'), 2);
  });

  test('two creates of one id do not both land', () async {
    final db = await _use('vo2_race.db');
    final now = DateTime(2026, 9, 14, 9);
    final results = await Future.wait([
      Vo2Store.create(
        db,
        id: 'entry-1',
        measuredOn: '2026-09-14',
        valueMlKgMin: 40,
        now: now,
      ),
      Vo2Store.create(
        db,
        id: 'entry-1',
        measuredOn: '2026-09-14',
        valueMlKgMin: 41,
        now: now,
      ),
    ]);
    expect(results.whereType<Vo2Committed>(), hasLength(1));
    expect(results.whereType<Vo2WriteConflict>(), hasLength(1));
    expect(await _count(db, 'entry-1'), 1);
  });

  test('older, newer, repeated, and tombstone chains', () async {
    final db = await _use('vo2_import_chain.db');
    final id = 'entry-1';
    final t1 = DateTime(2026, 9, 1, 8);
    _committed(
      await Vo2Store.create(
        db,
        id: id,
        measuredOn: '2026-09-01',
        valueMlKgMin: 40,
        now: t1,
      ),
    );
    final older = await LocalDb.exportCopy();
    for (var i = 0; i < 4; i++) {
      _committed(
        await Vo2Store.edit(
          db,
          id: id,
          expectedRevision: i + 1,
          measuredOn: '2026-09-14',
          valueMlKgMin: 41 + i.toDouble(),
          now: DateTime(2026, 9, 14, 9 + i),
        ),
      );
    }
    expect(await _count(db, id), 5);
    final newer = await LocalDb.exportCopy();

    final importedOlder = await LocalDb.importFromDbFile(older);
    expect(importedOlder['manual_vo2'], 0);
    expect(importedOlder['manual_vo2_conflict'], 0);
    expect((await Vo2Store.detail(db, id)).head?.valueMlKgMin, 44);
    expect(await _count(db, id), 5);

    await LocalDb.wipeAll();
    expect((await Vo2Store.list(db)).isEmptyStore, isTrue);

    final first = await LocalDb.importFromDbFile(older);
    expect(first['manual_vo2'], 1);
    final second = await LocalDb.importFromDbFile(newer);
    expect(second['manual_vo2'], 4);
    expect((await Vo2Store.detail(db, id)).head?.revision, 5);
    final repeat = await LocalDb.importFromDbFile(newer);
    expect(repeat['manual_vo2'], 0);
    expect(repeat['manual_vo2_conflict'], 0);
    expect(await _count(db, id), 5);

    final live = await LocalDb.exportCopy();
    _committed(
      await Vo2Store.delete(
        db,
        id: id,
        expectedRevision: 5,
        now: DateTime(2026, 9, 20, 8),
      ),
    );
    final afterDelete = await LocalDb.importFromDbFile(live);
    expect(afterDelete['manual_vo2'], 0);
    final stillDeleted = await Vo2Store.detail(db, id);
    expect(stillDeleted.head?.deleted, isTrue);
    expect(stillDeleted.head?.valueMlKgMin, 44);
    expect(await _count(db, id), 6);

    final tombstone = await LocalDb.exportCopy();
    await LocalDb.wipeAll();
    await LocalDb.importFromDbFile(newer);
    final restoredDelete = await LocalDb.importFromDbFile(tombstone);
    expect(restoredDelete['manual_vo2'], 1);
    expect((await Vo2Store.detail(db, id)).head?.deleted, isTrue);
    final again = await LocalDb.importFromDbFile(tombstone);
    expect(again['manual_vo2'], 0);
    expect(await _count(db, id), 6);
  });

  test('a divergent chain is preserved while another record still imports', () async {
    final db = await _use('vo2_partial.db');
    final t1 = DateTime(2026, 9, 1, 8);
    _committed(
      await Vo2Store.create(
        db,
        id: 'keep',
        measuredOn: '2026-09-01',
        valueMlKgMin: 40,
        now: t1,
      ),
    );
    _committed(
      await Vo2Store.edit(
        db,
        id: 'keep',
        expectedRevision: 1,
        measuredOn: '2026-09-01',
        valueMlKgMin: 41,
        now: DateTime(2026, 9, 2, 8),
      ),
    );
    _committed(
      await Vo2Store.create(
        db,
        id: 'fresh',
        measuredOn: '2026-09-03',
        valueMlKgMin: 50,
        now: DateTime(2026, 9, 3, 8),
      ),
    );
    await db.insert('lab_result', {
      'marker': 'ferritin',
      'taken_on': '2026-09-03',
      'value': 52,
      'unit': 'ng/mL',
      'note': '',
      'updated_at': 1,
    });
    final snapshot = await LocalDb.exportCopy();

    await LocalDb.wipeAll();
    _committed(
      await Vo2Store.create(
        db,
        id: 'keep',
        measuredOn: '2026-09-01',
        valueMlKgMin: 40,
        now: t1,
      ),
    );
    _committed(
      await Vo2Store.edit(
        db,
        id: 'keep',
        expectedRevision: 1,
        measuredOn: '2026-09-01',
        valueMlKgMin: 99,
        now: DateTime(2026, 9, 10, 8),
      ),
    );

    final counts = await LocalDb.importFromDbFile(snapshot);
    expect(counts['manual_vo2_conflict'], 1);
    expect(counts['manual_vo2'], 1);
    expect(counts['lab_result'], 1);
    expect((await Vo2Store.detail(db, 'keep')).head?.valueMlKgMin, 99);
    expect(await _count(db, 'keep'), 2);
    expect((await Vo2Store.detail(db, 'fresh')).head?.valueMlKgMin, 50);
    final labs = await db.query('lab_result');
    expect(labs, hasLength(1));
    expect(labs.single['value'], 52);
  });

  test('a hole or invalid source chain does not write a prefix of that id', () async {
    final db = await _use('vo2_hole.db');
    _committed(
      await Vo2Store.create(
        db,
        id: 'local',
        measuredOn: '2026-09-01',
        valueMlKgMin: 40,
        now: DateTime(2026, 9, 1, 8),
      ),
    );
    final path = p.join(tmp.path, 'vo2_hole_src.db');
    final src = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await _sourceTable(db);
          await db.execute('''
            CREATE TABLE lab_result (
              marker TEXT NOT NULL,
              taken_on TEXT NOT NULL,
              value REAL NOT NULL,
              unit TEXT NOT NULL,
              note TEXT NOT NULL DEFAULT '',
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (marker, taken_on)
            )
          ''');
        },
      ),
    );
    await src.insert(
      'manual_vo2',
      _raw(
        id: 'gapped',
        revision: 1,
        measuredOn: '2026-09-04',
        value: 33,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    await src.insert(
      'manual_vo2',
      _raw(
        id: 'gapped',
        revision: 3,
        measuredOn: '2026-09-05',
        value: 34,
        createdAt: 1,
        updatedAt: 2,
      ),
    );
    await src.insert(
      'manual_vo2',
      _raw(
        id: 'bad-date',
        revision: 1,
        measuredOn: 'yesterday',
        value: 30,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    await src.insert(
      'manual_vo2',
      _raw(
        id: 'ok',
        revision: 1,
        measuredOn: '2026-09-06',
        value: 36,
        createdAt: 5,
        updatedAt: 5,
      ),
    );
    await src.insert('lab_result', {
      'marker': 'ferritin',
      'taken_on': '2026-09-06',
      'value': 20,
      'unit': 'ng/mL',
      'note': '',
      'updated_at': 5,
    });
    await src.close();

    final counts = await LocalDb.importFromDbFile(path);
    expect(counts['manual_vo2_corrupt'], 2);
    expect(counts['manual_vo2_conflict'], 0);
    expect(counts['manual_vo2'], 1);
    expect(counts['lab_result'], 1);
    expect(await _count(db, 'gapped'), 0);
    expect(await _count(db, 'bad-date'), 0);
    expect((await Vo2Store.detail(db, 'ok')).head?.valueMlKgMin, 36);
    expect((await Vo2Store.detail(db, 'local')).head?.valueMlKgMin, 40);

    final again = await LocalDb.importFromDbFile(path);
    expect(again['manual_vo2'], 0);
    expect(await _count(db, 'ok'), 1);
    expect(await _count(db, 'gapped'), 0);
  });

  test('a later source page keeps the committed id and its count', () async {
    final db = await _use('vo2_interrupt.db');
    final path = p.join(tmp.path, 'vo2_interrupt_src.db');
    final src = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async => _sourceTable(db),
      ),
    );
    Future<void> put(String id, int revision, int updatedAt) {
      return src.insert(
        'manual_vo2',
        _raw(
          id: id,
          revision: revision,
          measuredOn: '2026-09-14',
          value: 40.0 + revision,
          createdAt: 1,
          updatedAt: updatedAt,
        ),
      );
    }

    await put('a', 1, 1);
    await put('b', 1, 1);
    await put('b', 2, 2);
    await put('b', 3, 3);

    Object? caught;
    try {
      await Vo2Store.mergeImport(
        src: src,
        dest: db,
        readSource: (sql, args) async {
          if (sql.startsWith('SELECT * FROM') &&
              args != null &&
              args[0] == 'b' &&
              args[1] == 2) {
            throw StateError('later page failed');
          }
          return src.rawQuery(sql, args);
        },
      );
    } on Vo2ImportInterrupted catch (e) {
      caught = e;
      expect(e.counts.inserted, 1);
      expect(e.counts.conflictIds, 0);
      expect(e.counts.corruptIds, 0);
      expect(e.counts.tableMissing, isFalse);
      expect(e.cause, isA<StateError>());
      expect(
        e.toString(),
        'Vo2ImportInterrupted(inserted: 1, conflictIds: 0, corruptIds: 0): '
        'Bad state: later page failed',
      );
    }
    expect(caught, isA<Vo2ImportInterrupted>());
    expect(await _count(db, 'a'), 1);
    expect(await _count(db, 'b'), 0);
    expect((await Vo2Store.detail(db, 'a')).head?.valueMlKgMin, 41);

    final done = await Vo2Store.mergeImport(src: src, dest: db);
    expect(done.inserted, 3);
    expect(done.conflictIds, 0);
    expect(done.corruptIds, 0);
    expect(done.tableMissing, isFalse);
    expect(await _count(db, 'a'), 1);
    expect(await _count(db, 'b'), 3);
    expect((await Vo2Store.detail(db, 'b')).head?.valueMlKgMin, 43);

    final bare = p.join(tmp.path, 'vo2_interrupt_bare.db');
    final noTable = await databaseFactory.openDatabase(
      bare,
      options: OpenDatabaseOptions(version: 1),
    );
    final missing = await Vo2Store.mergeImport(src: noTable, dest: db);
    expect(missing.tableMissing, isTrue);
    expect(missing.inserted, 0);
    await noTable.close();

    await src.close();
    await expectLater(
      Vo2Store.mergeImport(src: src, dest: db),
      throwsA(isA<DatabaseException>()),
    );
    expect(await _count(db, 'a'), 1);
    expect(await _count(db, 'b'), 3);
  });

  test('range export keeps full history for in-range heads, including removals', () async {
    final db = await _use('vo2_range.db');
    _committed(
      await Vo2Store.create(
        db,
        id: 'moved',
        measuredOn: '2026-09-01',
        valueMlKgMin: 40,
        now: DateTime(2026, 9, 1, 8),
      ),
    );
    _committed(
      await Vo2Store.edit(
        db,
        id: 'moved',
        expectedRevision: 1,
        measuredOn: '2026-09-14',
        valueMlKgMin: 44,
        now: DateTime(2026, 9, 14, 8),
      ),
    );
    _committed(
      await Vo2Store.create(
        db,
        id: 'outside',
        measuredOn: '2026-08-01',
        valueMlKgMin: 30,
        now: DateTime(2026, 8, 1, 8),
      ),
    );
    _committed(
      await Vo2Store.create(
        db,
        id: 'removed',
        measuredOn: '2026-09-14',
        valueMlKgMin: 51,
        declaredMethod: 'lab',
        now: DateTime(2026, 9, 14, 9),
      ),
    );
    _committed(
      await Vo2Store.delete(
        db,
        id: 'removed',
        expectedRevision: 1,
        now: DateTime(2026, 9, 14, 10),
      ),
    );

    final path = await LocalDb.exportDaysDb({'2026-09-14'});
    final out = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      final rows = await out.query(
        'manual_vo2',
        orderBy: 'id ASC, revision ASC',
      );
      final ids = rows.map((r) => r['id']).toSet();
      expect(ids, {'moved', 'removed'});
      expect(rows.where((r) => r['id'] == 'moved'), hasLength(2));
      expect(
        rows.firstWhere((r) => r['id'] == 'moved' && r['revision'] == 1)['measured_on'],
        '2026-09-01',
      );
      expect(rows.where((r) => r['id'] == 'removed'), hasLength(2));
      expect(
        rows.firstWhere((r) => r['id'] == 'removed' && r['revision'] == 2)['deleted'],
        1,
      );
    } finally {
      await out.close();
    }

    final early = await LocalDb.exportDaysDb({'2026-09-01'});
    final earlyDb = await databaseFactory.openDatabase(
      early,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      final ids = await earlyDb.query('manual_vo2', columns: ['id']);
      expect(ids, isEmpty);
    } finally {
      await earlyDb.close();
    }
  });

  test('a retry has to apply to the revision it names', () async {
    final db = await _use('vo2_retry_base.db');
    final t1 = DateTime(2026, 9, 14, 9);
    _committed(
      await Vo2Store.create(
        db,
        id: 'entry-1',
        measuredOn: '2026-09-14',
        valueMlKgMin: 40,
        declaredMethod: 'lab',
        now: t1,
      ),
    );
    _committed(
      await Vo2Store.edit(
        db,
        id: 'entry-1',
        expectedRevision: 1,
        measuredOn: '2026-09-14',
        valueMlKgMin: 40,
        declaredMethod: 'lab',
        now: DateTime(2026, 9, 14, 10),
      ),
    );

    final restoreOfEdit = await Vo2Store.restore(
      db,
      id: 'entry-1',
      expectedRevision: 1,
      now: DateTime(2026, 9, 14, 11),
    );
    expect(restoreOfEdit, isA<Vo2WriteConflict>());
    expect((restoreOfEdit as Vo2WriteConflict).head?.revision, 2);
    expect(restoreOfEdit.head?.deleted, isFalse);
    expect(await _count(db, 'entry-1'), 2);

    _committed(
      await Vo2Store.delete(
        db,
        id: 'entry-1',
        expectedRevision: 2,
        now: DateTime(2026, 9, 14, 12),
      ),
    );
    _committed(
      await Vo2Store.restore(
        db,
        id: 'entry-1',
        expectedRevision: 3,
        now: DateTime(2026, 9, 14, 13),
      ),
    );
    final editOfTombstone = await Vo2Store.edit(
      db,
      id: 'entry-1',
      expectedRevision: 3,
      measuredOn: '2026-09-14',
      valueMlKgMin: 40,
      declaredMethod: 'lab',
      now: DateTime(2026, 9, 14, 14),
    );
    expect(editOfTombstone, isA<Vo2WriteConflict>());
    expect((editOfTombstone as Vo2WriteConflict).head?.revision, 4);
    expect(await _count(db, 'entry-1'), 4);

    final restoreRetry = await Vo2Store.restore(
      db,
      id: 'entry-1',
      expectedRevision: 3,
      now: DateTime(2026, 9, 14, 15),
    );
    expect(restoreRetry, isA<Vo2Committed>());
    expect((restoreRetry as Vo2Committed).retry, isTrue);
    expect(restoreRetry.revision.revision, 4);
    expect(await _count(db, 'entry-1'), 4);

    _committed(
      await Vo2Store.create(
        db,
        id: 'tomb',
        measuredOn: '2026-09-14',
        valueMlKgMin: 33,
        declaredMethod: 'lab',
        now: t1,
      ),
    );
    _committed(
      await Vo2Store.delete(
        db,
        id: 'tomb',
        expectedRevision: 1,
        now: DateTime(2026, 9, 14, 10),
      ),
    );
    final tomb = (await db.query(
      'manual_vo2',
      where: 'id = ? AND revision = 2',
      whereArgs: ['tomb'],
    )).single;
    await db.rawInsert(
      'INSERT INTO manual_vo2 ('
      'id, revision, measured_on, value_ml_kg_min, declared_method, '
      'created_at, updated_at, deleted, origin, unit'
      ') VALUES (?, 3, ?, ?, ?, ?, ?, 1, ?, ?)',
      [
        tomb['id'],
        tomb['measured_on'],
        tomb['value_ml_kg_min'],
        tomb['declared_method'],
        tomb['created_at'],
        (tomb['updated_at'] as int) + 1,
        tomb['origin'],
        tomb['unit'],
      ],
    );
    final deleteOfTombstone = await Vo2Store.delete(
      db,
      id: 'tomb',
      expectedRevision: 2,
      now: DateTime(2026, 9, 14, 16),
    );
    expect(deleteOfTombstone, isA<Vo2WriteConflict>());
    expect((deleteOfTombstone as Vo2WriteConflict).head?.revision, 3);
    expect(deleteOfTombstone.head?.deleted, isTrue);
    expect(await _count(db, 'tomb'), 3);
  });

  test('a fractional or nonnumeric revision at a page boundary stays in the export', () async {
    final db = await _use('vo2_revision_bound.db');
    await db.execute('''
      INSERT INTO manual_vo2 (
        id, revision, measured_on, value_ml_kg_min, declared_method,
        created_at, updated_at, deleted, origin, unit
      ) VALUES
        ('edge', 1, '2026-01-01', 40, NULL, 1, 1, 0, '$kVo2Origin', '$kVo2Unit'),
        ('edge', 1.5, '2026-01-02', 41, NULL, 2, 2, 0, '$kVo2Origin', '$kVo2Unit'),
        ('edge', 2, '2026-01-03', 42, NULL, 3, 3, 0, '$kVo2Origin', '$kVo2Unit'),
        ('edge', 'not-a-number', '2026-02-02', 43, NULL, 4, 4, 0, '$kVo2Origin', '$kVo2Unit'),
        ('edge', X'0A0B', '2026-09-14', 44, NULL, 5, 5, 0, '$kVo2Origin', '$kVo2Unit')
    ''');

    final detail = await Vo2Store.detail(db, 'edge');
    expect(detail.missing, isFalse);
    expect(detail.head, isNull);
    expect(detail.headCorrupt, isTrue);
    expect(detail.revisions, hasLength(5));
    expect(detail.revisions[0].revision, 1);
    expect(detail.revisions[0].value?.valueMlKgMin, 40);
    expect(detail.revisions[1].corrupt, isTrue);
    expect(detail.revisions[1].revision, isNull);
    expect(detail.revisions[1].value, isNull);
    expect(detail.revisions[2].revision, 2);
    expect(detail.revisions[2].value?.valueMlKgMin, 42);
    expect(detail.revisions[3].revision, isNull);
    expect(detail.revisions[3].value, isNull);
    expect(detail.revisions[4].revision, isNull);
    expect(detail.revisions[4].value, isNull);
    expect(detail.corruptRevisionCount, 3);

    final path = await LocalDb.exportDaysDb({'2026-09-14'});
    final out = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      final typed = await out.rawQuery(
        'SELECT revision, typeof(revision) AS t FROM manual_vo2 '
        'ORDER BY revision ASC, rowid ASC',
      );
      expect(
        typed.map((r) => r['t']).toList(),
        ['integer', 'real', 'integer', 'text', 'blob'],
      );
      expect(typed[0]['revision'], 1);
      expect(typed[1]['revision'], 1.5);
      expect(typed[1]['revision'], isA<double>());
      expect(typed[2]['revision'], 2);
      expect(typed[3]['revision'], 'not-a-number');
      expect(typed[4]['revision'], [0x0A, 0x0B]);
    } finally {
      await out.close();
    }

    final kept = await db.rawQuery(
      'SELECT revision, typeof(revision) AS t FROM manual_vo2 '
      'WHERE id = ? ORDER BY revision ASC, rowid ASC',
      ['edge'],
    );
    expect(kept.map((r) => r['t']).toList(), [
      'integer',
      'real',
      'integer',
      'text',
      'blob',
    ]);
    expect(kept[1]['revision'], 1.5);
    expect(kept[3]['revision'], 'not-a-number');
    expect(kept[4]['revision'], [0x0A, 0x0B]);
  });

  test('a stored 1e100 stays unreadable and is not int64 max', () async {
    final db = await _use('vo2_huge_int.db');
    const saturated = 9223372036854775807;
    await db.execute('''
      INSERT INTO manual_vo2 (
        id, revision, measured_on, value_ml_kg_min, declared_method,
        created_at, updated_at, deleted, origin, unit
      ) VALUES
        ('huge-rev', 1e100, '2026-09-14', 40, NULL, 1, 1, 0, '$kVo2Origin', '$kVo2Unit'),
        ('huge-time', 1, '2026-09-14', 40, NULL, 1e100, 1e100, 0, '$kVo2Origin', '$kVo2Unit'),
        ('one', 1.0, '2026-09-14', 40, NULL, 10.0, 10.0, 0, '$kVo2Origin', '$kVo2Unit')
    ''');

    final hugeRev = (await db.query(
      'manual_vo2',
      where: 'id = ?',
      whereArgs: ['huge-rev'],
    )).single;
    expect(hugeRev['revision'], isNot(saturated));
    expect(hugeRev['revision'], 1e100);
    final hugeTime = (await db.query(
      'manual_vo2',
      where: 'id = ?',
      whereArgs: ['huge-time'],
    )).single;
    expect(hugeTime['created_at'], isNot(saturated));
    expect(hugeTime['updated_at'], isNot(saturated));
    expect(hugeTime['created_at'], 1e100);

    final revDetail = await Vo2Store.detail(db, 'huge-rev');
    expect(revDetail.head, isNull);
    expect(revDetail.headCorrupt, isTrue);
    expect(revDetail.missing, isFalse);
    expect(revDetail.revisions.single.corrupt, isTrue);
    expect(revDetail.revisions.single.value, isNull);
    expect(revDetail.revisions.single.revision, isNull);
    expect(revDetail.revisions.single.revision, isNot(saturated));

    final timeDetail = await Vo2Store.detail(db, 'huge-time');
    expect(timeDetail.head, isNull);
    expect(timeDetail.headCorrupt, isTrue);
    expect(timeDetail.revisions.single.value, isNull);
    expect(timeDetail.revisions.single.revision, 1);

    final list = await Vo2Store.list(db);
    expect(list.isEmptyStore, isFalse);
    expect(list.corruptCount, 2);
    final one = await Vo2Store.detail(db, 'one');
    expect(one.head?.revision, 1);
    expect(one.head?.createdAt, 10);
    expect(one.headCorrupt, isFalse);

    final still = (await db.query(
      'manual_vo2',
      where: 'id = ?',
      whereArgs: ['huge-rev'],
    )).single;
    expect(still['revision'], 1e100);
  });

  test('a stored 2^63 stays unreadable and is not int64 max', () async {
    final db = await _use('vo2_two63.db');
    const saturated = 9223372036854775807;
    final two63 = 9223372036854775808.0;
    expect(two63.toInt(), saturated);
    expect(two63 == saturated.toDouble(), isTrue);
    await db.execute('''
      INSERT INTO manual_vo2 (
        id, revision, measured_on, value_ml_kg_min, declared_method,
        created_at, updated_at, deleted, origin, unit
      ) VALUES
        ('two63-rev', 9223372036854775808, '2026-09-14', 40, NULL, 1, 1, 0, '$kVo2Origin', '$kVo2Unit'),
        ('two63-time', 1, '2026-09-14', 40, NULL, 9223372036854775808, 9223372036854775808, 0, '$kVo2Origin', '$kVo2Unit'),
        ('max-int', $saturated, '2026-09-14', 40, NULL, 1, 1, 0, '$kVo2Origin', '$kVo2Unit')
    ''');

    final revRow = (await db.query(
      'manual_vo2',
      where: 'id = ?',
      whereArgs: ['two63-rev'],
    )).single;
    // Dart treats this double as == int64 max. The stored value is still the
    // 2^63 real, not an INTEGER.
    expect(revRow['revision'], isA<double>());
    expect(revRow['revision'], two63);
    final timeRow = (await db.query(
      'manual_vo2',
      where: 'id = ?',
      whereArgs: ['two63-time'],
    )).single;
    expect(timeRow['created_at'], isA<double>());
    expect(timeRow['updated_at'], isA<double>());
    expect(timeRow['created_at'], two63);

    final revDetail = await Vo2Store.detail(db, 'two63-rev');
    expect(revDetail.head, isNull);
    expect(revDetail.headCorrupt, isTrue);
    expect(revDetail.missing, isFalse);
    expect(revDetail.revisions.single.corrupt, isTrue);
    expect(revDetail.revisions.single.value, isNull);
    expect(revDetail.revisions.single.revision, isNull);

    final timeDetail = await Vo2Store.detail(db, 'two63-time');
    expect(timeDetail.head, isNull);
    expect(timeDetail.headCorrupt, isTrue);
    expect(timeDetail.revisions.single.value, isNull);
    expect(timeDetail.revisions.single.revision, 1);

    final list = await Vo2Store.list(db);
    expect(list.isEmptyStore, isFalse);
    expect(list.corruptCount, 2);
    expect((await Vo2Store.detail(db, 'max-int')).head?.revision, saturated);

    final still = (await db.query(
      'manual_vo2',
      where: 'id = ?',
      whereArgs: ['two63-rev'],
    )).single;
    expect(still['revision'], two63);
  });

  test('an identical gapped source chain counts as corrupt and stays put', () async {
    final db = await _use('vo2_identical_gap.db');
    final gap = [
      _raw(
        id: 'gapped',
        revision: 1,
        measuredOn: '2026-09-04',
        value: 33,
        createdAt: 1,
        updatedAt: 1,
      ),
      _raw(
        id: 'gapped',
        revision: 3,
        measuredOn: '2026-09-05',
        value: 34,
        createdAt: 1,
        updatedAt: 2,
      ),
    ];
    for (final row in gap) {
      await db.insert('manual_vo2', row);
    }
    _committed(
      await Vo2Store.create(
        db,
        id: 'local',
        measuredOn: '2026-09-01',
        valueMlKgMin: 40,
        now: DateTime(2026, 9, 1, 8),
      ),
    );
    final before = await db.query(
      'manual_vo2',
      where: 'id = ?',
      whereArgs: ['gapped'],
      orderBy: 'revision ASC',
    );

    final path = p.join(tmp.path, 'vo2_identical_gap_src.db');
    final src = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await _sourceTable(db);
          await db.execute('''
            CREATE TABLE lab_result (
              marker TEXT NOT NULL,
              taken_on TEXT NOT NULL,
              value REAL NOT NULL,
              unit TEXT NOT NULL,
              note TEXT NOT NULL DEFAULT '',
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (marker, taken_on)
            )
          ''');
        },
      ),
    );
    for (final row in gap) {
      await src.insert('manual_vo2', row);
    }
    await src.insert(
      'manual_vo2',
      _raw(
        id: 'ok',
        revision: 1,
        measuredOn: '2026-09-06',
        value: 36,
        createdAt: 5,
        updatedAt: 5,
      ),
    );
    await src.insert('lab_result', {
      'marker': 'ferritin',
      'taken_on': '2026-09-06',
      'value': 20,
      'unit': 'ng/mL',
      'note': '',
      'updated_at': 5,
    });
    await src.close();

    final counts = await LocalDb.importFromDbFile(path);
    expect(counts['manual_vo2_corrupt'], 1);
    expect(counts['manual_vo2_conflict'], 0);
    expect(counts['manual_vo2'], 1);
    expect(counts['lab_result'], 1);
    final after = await db.query(
      'manual_vo2',
      where: 'id = ?',
      whereArgs: ['gapped'],
      orderBy: 'revision ASC',
    );
    expect(after.length, before.length);
    for (var i = 0; i < before.length; i++) {
      expect(after[i]['revision'], before[i]['revision']);
      expect(after[i]['value_ml_kg_min'], before[i]['value_ml_kg_min']);
      expect(after[i]['measured_on'], before[i]['measured_on']);
      expect(after[i]['created_at'], before[i]['created_at']);
      expect(after[i]['updated_at'], before[i]['updated_at']);
      expect(after[i]['deleted'], before[i]['deleted']);
    }
    expect(after.map((r) => r['revision']), [1, 3]);
    expect(await _count(db, 'gapped'), 2);
    expect((await Vo2Store.detail(db, 'ok')).head?.valueMlKgMin, 36);
    expect((await Vo2Store.detail(db, 'local')).head?.valueMlKgMin, 40);

    final again = await LocalDb.importFromDbFile(path);
    expect(again['manual_vo2_corrupt'], 1);
    expect(again['manual_vo2'], 0);
    expect(await _count(db, 'gapped'), 2);
    expect(await _count(db, 'ok'), 1);
  });

  test('deleteDays keeps manual entries and wipeAll removes them', () async {
    final db = await _use('vo2_retention.db');
    _committed(
      await Vo2Store.create(
        db,
        id: 'entry-1',
        measuredOn: '2026-09-14',
        valueMlKgMin: 42,
        now: DateTime(2026, 9, 14, 9),
      ),
    );
    await db.insert('journal', {
      'date': '2026-09-14',
      'tags_json': '[]',
      'note': 'day',
      'updated_at': 1,
    });
    await LocalDb.deleteDays({'2026-09-14'});
    expect(await _count(db, 'entry-1'), 1);
    expect(await db.query('journal'), isEmpty);

    await LocalDb.wipeAll();
    expect(await _count(db), 0);
    expect((await Vo2Store.list(db)).isEmptyStore, isTrue);
  });

  test('fresh schema reports the vo2 table healthy', () async {
    await _use('vo2_health.db');
    expect(LocalDb.schemaVersion, 68);
    final names = await LocalDb.tableNames();
    expect(names, contains('manual_vo2'));
    final health = await LocalDb.schemaHealth();
    expect(health['ok'], isTrue, reason: '$health');
  });
}
