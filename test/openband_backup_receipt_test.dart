import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/data/backup_import_result.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/import/journal_csv_import.dart';
import 'package:openstrap_edge/l10n/app_localizations.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/openband/vo2_data.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/onboarding/welcome.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart' show dbRebuiltCard;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class _RawReadFails extends AppState {
  _RawReadFails() : super.forTesting();

  @override
  Future<int> importNoopCsv(
    String path, {
    void Function(int days)? onProgress,
  }) {
    throw StateError('raw read failed');
  }
}

const _partial = ImportOutcome(
  source: 'OpenBand-Sicherung',
  vo2TablePresent: true,
  vo2Revisions: 2,
  vo2ConflictIds: 1,
  vo2CorruptIds: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String savedName;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('openband_backup_receipt_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    savedName = LocalDb.dbName;
    for (final font in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
      (
        'packages/lucide_icons_flutter/Lucide',
        'packages/lucide_icons_flutter/assets/lucide.ttf',
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  tearDownAll(() async {
    await LocalDb.close();
    LocalDb.dbName = savedName;
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('count shape', () {
    test('a missing VO2 table is not an explicit zero', () {
      final absent = BackupImportReceipt.fromCounts({
        'journal': 4,
        '_days': 2,
      });
      final zero = BackupImportReceipt.fromCounts({
        '_days': 0,
        'manual_vo2': 0,
        'manual_vo2_conflict': 0,
        'manual_vo2_corrupt': 0,
      });

      expect(absent.vo2TablePresent, isFalse);
      expect(absent.days, 2);
      expect(absent.insertedRevisions, 0);
      expect(zero.vo2TablePresent, isTrue);
      expect(zero.insertedRevisions, 0);
      expect(zero.conflictIds, 0);
      expect(zero.corruptIds, 0);
    });

    test('revision rows are not days and ids are not revisions', () {
      final receipt = BackupImportReceipt.fromCounts({
        '_days': 2,
        'manual_vo2': 5,
        'manual_vo2_conflict': 1,
        'manual_vo2_corrupt': 3,
      });
      expect(receipt.days, 2);
      expect(receipt.insertedRevisions, 5);
      expect(receipt.conflictIds, 1);
      expect(receipt.corruptIds, 3);
    });

    test('an absent table cannot carry VO2 counts', () {
      expect(
        () => BackupImportReceipt(
          days: 0,
          vo2TablePresent: false,
          insertedRevisions: 1,
          conflictIds: 0,
          corruptIds: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('sqlite backup import', () {
    late AppState app;
    var n = 0;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      n += 1;
      await LocalDb.close();
      LocalDb.dbName = 'backup_receipt_$n.db';
      LocalDb.lastRebuild = null;
      await databaseFactory.deleteDatabase(
        p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
      );
      await LocalDb.instance;
      app = AppState.forTesting();
    });

    tearDown(() async {
      LocalDb.debugAfterImportedTable = null;
      LocalDb.debugBeforeNextImportPage = null;
      LocalDb.debugVo2ImportRead = null;
      app.dispose();
      final name = LocalDb.dbName;
      await LocalDb.close();
      final dir = Directory(await databaseFactory.getDatabasesPath());
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          final base = p.basename(entity.path);
          if (entity is File &&
              (base == name || base.startsWith('$name.unopenable'))) {
            try {
              entity.deleteSync();
            } catch (_) {}
          }
        }
      }
      LocalDb.dbName = savedName;
    });

    Future<int> vo2Rows([String? id]) async {
      final db = await LocalDb.instance;
      final rows = await db.rawQuery(
        id == null
            ? 'SELECT COUNT(*) AS n FROM manual_vo2'
            : 'SELECT COUNT(*) AS n FROM manual_vo2 WHERE id = ?',
        id == null ? null : [id],
      );
      return (rows.first['n'] as num).toInt();
    }

    Future<String> source(
      String name,
      Future<void> Function(Database db) fill, {
      bool vo2 = true,
      bool days = false,
    }) async {
      final path = p.join(tmp.path, name);
      final db = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            if (vo2) {
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
            if (days) {
              await db.execute('''
                CREATE TABLE day_result (
                  day_id TEXT NOT NULL,
                  algo_version INTEGER NOT NULL,
                  payload_json TEXT NOT NULL,
                  computed_at INTEGER NOT NULL,
                  PRIMARY KEY (day_id, algo_version)
                )
              ''');
            }
          },
        ),
      );
      await fill(db);
      await db.close();
      return path;
    }

    Map<String, Object?> row({
      required String id,
      required int revision,
      required String measuredOn,
      required double value,
      required int created,
      int? updated,
    }) => {
      'id': id,
      'revision': revision,
      'measured_on': measuredOn,
      'value_ml_kg_min': value,
      'declared_method': null,
      'created_at': created,
      'updated_at': updated ?? created,
      'deleted': 0,
      'origin': kVo2Origin,
      'unit': kVo2Unit,
    };

    test('a VO2-only backup imports revisions and completes onboarding', () async {
      final path = await source('vo2_only.db', (db) async {
        await db.insert(
          'manual_vo2',
          row(
            id: 'a',
            revision: 1,
            measuredOn: '2026-09-01',
            value: 41,
            created: 1,
          ),
        );
        await db.insert(
          'manual_vo2',
          row(
            id: 'a',
            revision: 2,
            measuredOn: '2026-09-02',
            value: 43,
            created: 1,
            updated: 2,
          ),
        );
      });

      final out = await runImport(app, [path]);

      expect(out.days, 0);
      expect(out.vo2TablePresent, isTrue);
      expect(out.vo2Revisions, 2);
      expect(out.vo2ConflictIds, 0);
      expect(out.vo2CorruptIds, 0);
      expect(out.nothingLanded, isFalse);
      expect(out.source, 'OpenStrap backup');
      expect(await vo2Rows('a'), 2);
      await app.completeImportOnboard();
      expect(app.onboardChoice, 'imported');
    });

    test('days and VO2 revisions stay separate, including a second file', () async {
      final first = await source(
        'mixed_a.db',
        (db) async {
          await db.insert('day_result', {
            'day_id': '2026-01-01',
            'algo_version': 1,
            'payload_json': '{}',
            'computed_at': 1,
          });
          await db.insert('day_result', {
            'day_id': '2026-01-02',
            'algo_version': 1,
            'payload_json': '{}',
            'computed_at': 1,
          });
          await db.insert(
            'manual_vo2',
            row(
              id: 'a',
              revision: 1,
              measuredOn: '2026-09-01',
              value: 40,
              created: 1,
            ),
          );
        },
        days: true,
      );
      final second = await source('mixed_b.db', (db) async {
        await db.insert(
          'manual_vo2',
          row(
            id: 'a',
            revision: 1,
            measuredOn: '2026-09-01',
            value: 99,
            created: 9,
          ),
        );
        await db.insert(
          'manual_vo2',
          row(
            id: 'b',
            revision: 1,
            measuredOn: '2026-09-03',
            value: 48,
            created: 3,
          ),
        );
      });

      final out = await runImport(app, [first, second]);

      expect(out.days, 2);
      expect(out.vo2Revisions, 2);
      expect(out.vo2ConflictIds, 1);
      expect(out.vo2CorruptIds, 0);
      expect(out.vo2TablePresent, isTrue);
      expect(await vo2Rows('a'), 1);
      final kept = await (await LocalDb.instance).query(
        'manual_vo2',
        where: 'id = ?',
        whereArgs: ['a'],
      );
      expect(kept.single['value_ml_kg_min'], 40);
      expect(await vo2Rows('b'), 1);
    });

    test('divergent and corrupt ids are entry counts, not revision rows', () async {
      final db = await LocalDb.instance;
      await db.insert(
        'manual_vo2',
        row(
          id: 'keep',
          revision: 1,
          measuredOn: '2026-09-01',
          value: 40,
          created: 1,
        ),
      );
      final path = await source('divergent.db', (src) async {
        await src.insert(
          'manual_vo2',
          row(
            id: 'keep',
            revision: 1,
            measuredOn: '2026-09-01',
            value: 99,
            created: 9,
          ),
        );
        await src.insert(
          'manual_vo2',
          row(
            id: 'ok',
            revision: 1,
            measuredOn: '2026-09-04',
            value: 44,
            created: 4,
          ),
        );
        await src.insert(
          'manual_vo2',
          row(
            id: 'gap',
            revision: 1,
            measuredOn: '2026-09-05',
            value: 33,
            created: 5,
          ),
        );
        await src.insert(
          'manual_vo2',
          row(
            id: 'gap',
            revision: 3,
            measuredOn: '2026-09-06',
            value: 34,
            created: 6,
          ),
        );
        await src.insert(
          'manual_vo2',
          row(
            id: 'bad',
            revision: 1,
            measuredOn: 'yesterday',
            value: 30,
            created: 7,
          ),
        );
      });

      final receipt = await app.importEdgeBackup(path);

      expect(receipt.days, 0);
      expect(receipt.vo2TablePresent, isTrue);
      expect(receipt.insertedRevisions, 1);
      expect(receipt.conflictIds, 1);
      expect(receipt.corruptIds, 2);
      expect(receipt.recalculationError, isNull);
      expect(await vo2Rows('ok'), 1);
      expect(await vo2Rows('gap'), 0);
      expect(await vo2Rows('bad'), 0);
      expect(await vo2Rows('keep'), 1);
    });

    test('a present table with nothing new is a no-op, not a read failure', () async {
      final path = await source('empty_vo2.db', (_) async {});
      final first = await app.importEdgeBackup(path);
      expect(first.vo2TablePresent, isTrue);
      expect(first.insertedRevisions, 0);
      expect(first.conflictIds, 0);
      expect(first.corruptIds, 0);
      expect(first.recalculationError, isNull);

      final again = await runImport(app, [path]);
      expect(again.vo2TablePresent, isTrue);
      expect(again.vo2Revisions, 0);
      expect(again.vo2ConflictIds, 0);
      expect(again.vo2CorruptIds, 0);
      expect(again.nothingLanded, isTrue);
      expect(again.error, isNull);
    });

    test('an old backup without manual_vo2 does not report a VO2 zero', () async {
      final path = await source(
        'old_days.db',
        (db) async {
          await db.insert('day_result', {
            'day_id': '2026-03-01',
            'algo_version': 1,
            'payload_json': '{}',
            'computed_at': 1,
          });
          await db.insert('day_result', {
            'day_id': '2026-03-02',
            'algo_version': 1,
            'payload_json': '{}',
            'computed_at': 1,
          });
        },
        vo2: false,
        days: true,
      );

      final out = await runImport(app, [path]);

      expect(out.days, 2);
      expect(out.vo2TablePresent, isFalse);
      expect(out.vo2Revisions, 0);
      expect(out.vo2ConflictIds, 0);
      expect(out.vo2CorruptIds, 0);
      expect(out.nothingLanded, isFalse);
    });

    Future<String> oneRevision(String name) {
      return source(name, (db) async {
        await db.insert(
          'manual_vo2',
          row(
            id: 'kept',
            revision: 1,
            measuredOn: '2026-09-08',
            value: 46,
            created: 8,
          ),
        );
      });
    }

    Future<void> expectAcceptedDespite(ImportOutcome out) async {
      expect(out.error, isNull);
      expect(out.readError, isNotNull);
      expect(out.vo2TablePresent, isTrue);
      expect(out.vo2Revisions, 1);
      expect(out.nothingLanded, isFalse);
      expect(await vo2Rows('kept'), 1);
      if (!out.nothingLanded) await app.completeImportOnboard();
      expect(app.onboardChoice, 'imported');
    }

    test('a valid VO2 backup then a missing file keeps the accepted rows', () async {
      final good = await oneRevision('then_missing_good.db');
      final missing = p.join(tmp.path, 'then_missing_gone.db');

      final out = await runImport(app, [good, missing]);

      await expectAcceptedDespite(out);
      expect(out.readError, contains('not found'));
    });

    test('a missing file then a valid VO2 backup still stores the rows', () async {
      final good = await oneRevision('missing_first_good.db');
      final missing = p.join(tmp.path, 'missing_first_gone.db');

      final out = await runImport(app, [missing, good]);

      await expectAcceptedDespite(out);
      expect(out.days, 0);
    });

    test('an unreadable database before a valid VO2 backup does not drop it', () async {
      final good = await oneRevision('garbage_first_good.db');
      final garbage = p.join(tmp.path, 'garbage_first.db');
      await File(garbage).writeAsString('not a database');

      final out = await runImport(app, [garbage, good]);

      await expectAcceptedDespite(out);
    });

    test('a committed VO2 backup keeps its receipt when raw import throws', () async {
      final path = await oneRevision('raw_after_backup.db');
      final raw = p.join(tmp.path, 'sensors.csv');
      await File(raw).writeAsString(
        'unix_s,iso_utc,stream,hr_bpm,rr_ms,grav_x,grav_y,grav_z\n'
        '1754000000,2026-08-01T00:00:00Z,hr,61,,,,\n',
      );
      final blowing = _RawReadFails();
      addTearDown(blowing.dispose);

      final out = await runImport(blowing, [path, raw]);

      expect(out.error, isNull);
      expect(out.rollupError, isNull);
      expect(out.readError, contains('raw read failed'));
      expect(out.vo2TablePresent, isTrue);
      expect(out.vo2Revisions, 1);
      expect(out.days, 0);
      expect(out.nothingLanded, isFalse);
      expect(await vo2Rows('kept'), 1);
      if (!out.nothingLanded) await blowing.completeImportOnboard();
      expect(blowing.onboardChoice, 'imported');
    });

    test('a committed VO2 backup keeps its receipt when journal import throws', () async {
      final path = await oneRevision('journal_after_backup.db');
      final bad = p.join(tmp.path, 'bad-journal.csv');
      final later = p.join(tmp.path, 'later-journal.csv');
      await File(bad).writeAsString('date,tags,note\n');
      await File(later).writeAsString('date,tags,note\n');
      final seen = <String>[];

      final out = await runImport(
        app,
        [path, bad, later],
        debugReadJournal: (file) async {
          seen.add(file);
          if (file == bad) throw StateError('journal read failed');
          return const JournalImportResult(0, []);
        },
      );

      expect(seen, [bad, later]);
      expect(out.error, isNull);
      expect(out.rollupError, isNull);
      expect(out.readError, contains('journal read failed'));
      expect(out.vo2Revisions, 1);
      expect(out.journalRows, 0);
      expect(out.nothingLanded, isFalse);
      expect(await vo2Rows('kept'), 1);
    });

    test('a store interruption after one id keeps that id and the table', () async {
      final path = await source('vo2_interrupt_id.db', (db) async {
        await db.insert(
          'manual_vo2',
          row(
            id: 'a',
            revision: 1,
            measuredOn: '2026-09-01',
            value: 41,
            created: 1,
          ),
        );
        await db.insert(
          'manual_vo2',
          row(
            id: 'b',
            revision: 1,
            measuredOn: '2026-09-02',
            value: 42,
            created: 2,
          ),
        );
      });
      final reader = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      var idPages = 0;
      LocalDb.debugVo2ImportRead = (sql, args) async {
        if (sql.contains('GROUP BY id')) {
          idPages++;
          if (idPages > 1) throw StateError('next id failed');
        }
        return reader.rawQuery(sql, args);
      };
      try {
        final out = await runImport(app, [path]);
        expect(out.error, isNull);
        expect(out.rollupError, isNull);
        expect(out.readError, contains('next id failed'));
        expect(out.vo2TablePresent, isTrue);
        expect(out.vo2Revisions, 1);
        expect(out.vo2ConflictIds, 0);
        expect(out.vo2CorruptIds, 0);
        expect(out.nothingLanded, isFalse);
        expect(await vo2Rows('a'), 1);
        expect(await vo2Rows('b'), 0);
        if (!out.nothingLanded) await app.completeImportOnboard();
        expect(app.onboardChoice, 'imported');
      } finally {
        await reader.close();
      }
    });

    test('an interrupted empty VO2 read still reports the table present', () async {
      final path = await source('vo2_interrupt_zero.db', (_) async {});
      LocalDb.debugVo2ImportRead = (sql, args) async {
        throw StateError('count failed');
      };

      final out = await runImport(app, [path]);

      expect(out.error, isNull);
      expect(out.rollupError, isNull);
      expect(out.readError, contains('count failed'));
      expect(out.vo2TablePresent, isTrue);
      expect(out.vo2Revisions, 0);
      expect(out.vo2ConflictIds, 0);
      expect(out.vo2CorruptIds, 0);
      expect(await vo2Rows(), 0);
      expect(app.onboardChoice, isNull);
    });

    test('a committed measurement page is kept when the next read fails', () async {
      final path = p.join(tmp.path, 'meas_page.db');
      final src = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE imported_measurement (
                uuid TEXT PRIMARY KEY,
                ts INTEGER NOT NULL,
                kind TEXT NOT NULL,
                value REAL NOT NULL,
                unit TEXT NOT NULL,
                source TEXT NOT NULL
              )
            ''');
          },
        ),
      );
      final batch = src.batch();
      for (var i = 0; i < 2000; i++) {
        batch.insert('imported_measurement', {
          'uuid': 'm$i',
          'ts': i,
          'kind': 'heart_rate',
          'value': 60,
          'unit': 'bpm',
          'source': 'phone',
        });
      }
      await batch.commit(noResult: true);
      await src.close();
      LocalDb.debugBeforeNextImportPage = (table) async {
        if (table == 'imported_measurement') {
          throw StateError('next page failed');
        }
      };

      Object? caught;
      try {
        await LocalDb.importFromDbFile(path);
      } on PartialImportException catch (e) {
        caught = e;
        expect(e.counts['imported_measurement'], 2000);
        expect('${e.cause}', contains('next page failed'));
      }
      expect(caught, isA<PartialImportException>());
      final rows = await (await LocalDb.instance).rawQuery(
        'SELECT COUNT(*) AS n FROM imported_measurement',
      );
      expect(rows.first['n'], 2000);
    });

    test('a committed VO2 chain survives a later table failure', () async {
      final path = await oneRevision('partial_later.db');
      LocalDb.debugAfterImportedTable = (table) async {
        if (table == 'manual_vo2') throw StateError('later table failed');
      };

      final out = await runImport(app, [path]);

      expect(out.error, isNull);
      expect(out.readError, contains('later table failed'));
      expect(out.rollupError, isNull);
      expect(out.vo2TablePresent, isTrue);
      expect(out.vo2Revisions, 1);
      expect(out.vo2ConflictIds, 0);
      expect(out.vo2CorruptIds, 0);
      expect(out.nothingLanded, isFalse);
      expect(await vo2Rows('kept'), 1);
      if (!out.nothingLanded) await app.completeImportOnboard();
      expect(app.onboardChoice, 'imported');
    });

    test('salvage keeps a committed VO2 count when a later hook throws', () async {
      final db = await LocalDb.instance;
      await db.insert(
        'manual_vo2',
        row(
          id: 'kept',
          revision: 1,
          measuredOn: '2026-09-08',
          value: 46,
          created: 8,
        ),
      );
      await LocalDb.close();
      LocalDb.debugAfterImportedTable = (table) async {
        if (table == 'manual_vo2') throw StateError('salvage hook');
      };
      final raw = await databaseFactory.openDatabase(
        p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
      );
      await raw.execute('CREATE TABLE IF NOT EXISTS _raw_old (hex TEXT)');
      await raw.execute('PRAGMA user_version = 2');
      await raw.close();
      LocalDb.lastRebuild = null;

      final fresh = await LocalDb.instance;
      final rebuild = LocalDb.lastRebuild;
      expect(rebuild, isNotNull);
      expect(rebuild!.salvaged['manual_vo2'], 1);
      expect(rebuild.salvaged['manual_vo2'], isNot(0));
      final kept = await fresh.rawQuery(
        'SELECT COUNT(*) AS n FROM manual_vo2 WHERE id = ?',
        ['kept'],
      );
      expect((kept.first['n'] as num).toInt(), 1);
      final card = dbRebuiltCard(rebuild);
      expect(card!.why.contains('manual_vo2 1'), isTrue);
      expect(card.why.contains('Empty: manual_vo2'), isFalse);
    });

    test('one unreadable backup stays an error and does not finish onboarding', () async {
      final missing = p.join(tmp.path, 'only_missing.db');
      await expectLater(
        runImport(app, [missing]),
        throwsA(isA<FileSystemException>()),
      );
      expect(app.onboardChoice, isNull);
      expect(await vo2Rows(), 0);

      final garbage = p.join(tmp.path, 'only_garbage.db');
      await File(garbage).writeAsString('not a database');
      await expectLater(runImport(app, [garbage]), throwsA(anything));
      expect(app.onboardChoice, isNull);
      expect(await vo2Rows(), 0);
    });

    test('a backup that cannot be read does not become a zero receipt', () async {
      await expectLater(
        app.importEdgeBackup(p.join(tmp.path, 'missing.db')),
        throwsA(isA<FileSystemException>()),
      );
      final garbage = p.join(tmp.path, 'garbage.db');
      await File(garbage).writeAsString('not a database');
      await expectLater(app.importEdgeBackup(garbage), throwsA(anything));
      expect(await vo2Rows(), 0);
    });

    test('a recompute failure keeps the rows that were written', () async {
      app.debugDeriveEngine.debugAfterCrossDayInputRead = () async {
        throw StateError('recompute failed');
      };
      final path = await source('rollup.db', (db) async {
        await db.insert(
          'manual_vo2',
          row(
            id: 'kept',
            revision: 1,
            measuredOn: '2026-09-08',
            value: 46,
            created: 8,
          ),
        );
      });

      final receipt = await app.importEdgeBackup(path);

      expect(receipt.insertedRevisions, 1);
      expect(receipt.vo2TablePresent, isTrue);
      expect(receipt.recalculationError, contains('recompute failed'));
      expect(app.importRollupError, contains('recompute failed'));
      expect(await vo2Rows('kept'), 1);
      final out = await runImport(app, [path]);
      expect(out.vo2Revisions, 0);
      expect(out.rollupError, contains('recompute failed'));
      expect(await vo2Rows('kept'), 1);
    });

    test('a rebuild reports VO2 revisions recovered and unreadable ids withheld', () async {
      final db = await LocalDb.instance;
      await db.insert('journal', {
        'date': '2026-08-01',
        'tags_json': '[]',
        'note': 'kept',
        'updated_at': 1,
      });
      await db.insert(
        'manual_vo2',
        row(id: 'ok', revision: 1, measuredOn: '2026-09-01', value: 41, created: 1),
      );
      await db.insert(
        'manual_vo2',
        row(
          id: 'ok',
          revision: 2,
          measuredOn: '2026-09-02',
          value: 42,
          created: 1,
          updated: 2,
        ),
      );
      await db.insert(
        'manual_vo2',
        row(id: 'gap', revision: 1, measuredOn: '2026-09-03', value: 30, created: 3),
      );
      await db.insert(
        'manual_vo2',
        row(id: 'gap', revision: 3, measuredOn: '2026-09-04', value: 31, created: 4),
      );
      await db.insert(
        'manual_vo2',
        row(id: '', revision: 1, measuredOn: '2026-09-05', value: 32, created: 5),
      );
      await LocalDb.close();
      final raw = await databaseFactory.openDatabase(
        p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
      );
      await raw.execute('CREATE TABLE IF NOT EXISTS _raw_old (hex TEXT)');
      await raw.execute('PRAGMA user_version = 2');
      await raw.close();
      LocalDb.lastRebuild = null;

      final fresh = await LocalDb.instance;
      final rebuild = LocalDb.lastRebuild;
      expect(rebuild, isNotNull);
      expect(rebuild!.salvaged['manual_vo2'], 2);
      expect(rebuild.salvaged['manual_vo2_corrupt'], 2);
      expect(rebuild.salvaged['manual_vo2_conflict'], 0);
      expect(rebuild.salvaged.containsKey('_days'), isFalse);
      expect(rebuild.salvaged['journal'], 1);
      expect(rebuild.cause, isNotEmpty);
      expect(File(rebuild.quarantinePath).existsSync(), isTrue);
      final kept = await fresh.rawQuery(
        'SELECT COUNT(*) AS n FROM manual_vo2',
      );
      expect((kept.first['n'] as num).toInt(), 2);

      final card = dbRebuiltCard(rebuild);
      expect(card, isNotNull);
      expect(card!.why, contains('manual_vo2 2'));
      expect(card.why, contains('journal 1'));
      expect(card.why, contains('Not recovered:'));
      expect(card.why, contains('2 unreadable VO₂max entries'));
      expect(card.why.contains('manual_vo2_conflict'), isFalse);
      expect(card.why.contains('manual_vo2_corrupt'), isFalse);
      expect(card.why, contains(rebuild.quarantinePath));
      expect(card.why, contains(rebuild.cause));
    });
  });

  group('import report', () {
    Future<void> mount(
      WidgetTester tester,
      ImportOutcome outcome, {
      Brightness brightness = Brightness.light,
      Locale locale = const Locale('de'),
      double scale = 1,
      double width = 375,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final canvas = OB(brightness == Brightness.dark).canvas;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: openBandTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            backgroundColor: canvas,
            body: ListView(
              children: [
                RepaintBoundary(
                  key: const ValueKey('capture'),
                  child: ColoredBox(
                    color: canvas,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ImportReport(outcome),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('partial German copy names accepted changes and withheld ids', (
      tester,
    ) async {
      await mount(tester, _partial);
      expect(find.text('Teilweise importiert'), findsOneWidget);
      expect(find.text('OpenBand-Sicherung'), findsOneWidget);
      expect(find.text('2 VO₂max-Änderungen übernommen'), findsOneWidget);
      expect(find.text('Nicht übernommen'), findsOneWidget);
      expect(find.text('1 VO₂max-Konflikt'), findsOneWidget);
      expect(find.text('1 VO₂max-Eintrag nicht lesbar'), findsOneWidget);
      expect(find.textContaining('0 Tag'), findsNothing);
      expect(find.byIcon(LucideIcons.check), findsNothing);
      expect(find.byIcon(LucideIcons.triangleAlert), findsNothing);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/backup_receipt_partial_light.png'),
      );
    });

    testWidgets('partial dark', (tester) async {
      await mount(tester, _partial, brightness: Brightness.dark);
      expect(find.text('Teilweise importiert'), findsOneWidget);
      expect(find.byIcon(LucideIcons.check), findsNothing);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/backup_receipt_partial_dark.png'),
      );
    });

    testWidgets('partial at 375 and text scale 2 has no overflow', (tester) async {
      await mount(tester, _partial, scale: 2);
      expect(find.text('2 VO₂max-Änderungen übernommen'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile(
          'openband_goldens/backup_receipt_partial_light_2x.png',
        ),
      );
      await mount(tester, _partial, brightness: Brightness.dark, scale: 2);
      expect(find.text('1 VO₂max-Eintrag nicht lesbar'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile(
          'openband_goldens/backup_receipt_partial_dark_2x.png',
        ),
      );
    });

    testWidgets('English partial, success, noop, conflict, and corrupt copy', (
      tester,
    ) async {
      await mount(tester, _partial, locale: const Locale('en'));
      expect(find.text('Partially imported'), findsOneWidget);
      expect(find.text('2 VO₂max changes accepted'), findsOneWidget);
      expect(find.text('Not imported'), findsOneWidget);
      expect(find.text('1 VO₂max conflict'), findsOneWidget);
      expect(find.text('1 VO₂max entry unreadable'), findsOneWidget);

      await mount(
        tester,
        const ImportOutcome(
          source: 'OpenBand-Sicherung',
          vo2TablePresent: true,
          vo2Revisions: 2,
        ),
        locale: const Locale('de'),
      );
      expect(find.text('Importiert'), findsOneWidget);
      expect(find.text('2 VO₂max-Änderungen übernommen'), findsOneWidget);
      expect(find.text('Nicht übernommen'), findsNothing);
      expect(find.textContaining('Tag'), findsNothing);
      expect(find.byIcon(LucideIcons.check), findsNothing);

      await mount(
        tester,
        const ImportOutcome(
          source: 'OpenBand-Sicherung',
          vo2TablePresent: true,
        ),
        locale: const Locale('de'),
      );
      expect(find.text('VO₂max unverändert'), findsOneWidget);
      expect(find.text('OpenBand-Sicherung'), findsOneWidget);
      expect(find.text('Keine neuen Änderungen'), findsNothing);
      expect(find.text('Keine neuen VO₂max-Änderungen'), findsNothing);
      expect(find.text('Nichts wurde importiert'), findsNothing);
      expect(find.textContaining('nicht gelesen'), findsNothing);

      await mount(
        tester,
        const ImportOutcome(
          source: 'OpenBand-Sicherung',
          vo2TablePresent: true,
          vo2ConflictIds: 2,
        ),
        locale: const Locale('de'),
      );
      expect(find.text('Nicht übernommen'), findsOneWidget);
      expect(find.text('2 VO₂max-Konflikte'), findsOneWidget);
      expect(find.text('Teilweise importiert'), findsNothing);
      expect(find.text('Nichts wurde importiert'), findsNothing);
      expect(find.byIcon(LucideIcons.check), findsNothing);

      await mount(
        tester,
        const ImportOutcome(
          source: 'OpenBand-Sicherung',
          vo2TablePresent: true,
          vo2CorruptIds: 1,
        ),
        locale: const Locale('de'),
      );
      expect(find.text('Nicht übernommen'), findsOneWidget);
      expect(find.text('1 VO₂max-Eintrag nicht lesbar'), findsOneWidget);
      expect(find.text('Teilweise importiert'), findsNothing);

      await mount(
        tester,
        const ImportOutcome(
          source: 'OpenStrap backup',
          vo2TablePresent: true,
          vo2Revisions: 1,
          readError: 'later table failed',
        ),
        locale: const Locale('de'),
      );
      expect(find.text('Teilweise importiert'), findsOneWidget);
      expect(find.text('1 VO₂max-Änderung übernommen'), findsOneWidget);
      expect(find.text('OpenBand-Sicherung'), findsOneWidget);
      expect(find.text('Import unvollständig'), findsOneWidget);
      expect(find.text('Importiert'), findsNothing);
      expect(find.text('VO₂max unverändert'), findsNothing);
      expect(find.text('Nichts wurde importiert'), findsNothing);
      expect(find.textContaining('Der Rest wurde importiert'), findsNothing);
      expect(find.textContaining('later table failed'), findsOneWidget);
      expect(find.byIcon(LucideIcons.check), findsNothing);

      await mount(
        tester,
        const ImportOutcome(
          source: 'OpenStrap backup',
          vo2TablePresent: true,
          readError: 'count failed',
        ),
        locale: const Locale('de'),
      );
      expect(find.text('Import unvollständig'), findsOneWidget);
      expect(find.textContaining('count failed'), findsOneWidget);
      expect(find.text('VO₂max unverändert'), findsNothing);
      expect(find.text('Nichts wurde importiert'), findsNothing);
      expect(find.textContaining('Der Rest wurde importiert'), findsNothing);
      expect(find.byIcon(LucideIcons.check), findsNothing);
    });

    testWidgets('legacy days, workouts, and failure notes stay', (tester) async {
      await mount(
        tester,
        const ImportOutcome(
          source: 'OpenBand-Sicherung',
          days: 4,
          workouts: 3,
          journalRows: 2,
          vo2TablePresent: true,
          vo2Revisions: 2,
          vo2ConflictIds: 1,
          readError: 'vendor failed',
          rollupError: 'crossday',
          rejectedRows: ['line 12: note is too long'],
        ),
        locale: const Locale('en'),
      );
      expect(find.text('4 days imported'), findsOneWidget);
      expect(find.textContaining('3 workouts'), findsOneWidget);
      expect(find.textContaining('2 journal'), findsOneWidget);
      expect(find.text('Partially imported'), findsOneWidget);
      expect(find.text('1 VO₂max conflict'), findsOneWidget);
      expect(find.textContaining('vendor failed'), findsOneWidget);
      expect(find.textContaining('crossday'), findsOneWidget);
      expect(find.textContaining('line 12'), findsOneWidget);

      await mount(
        tester,
        const ImportOutcome(source: 'Vendor CSV export', workouts: 60),
        locale: const Locale('en'),
      );
      expect(find.text('60 workouts'), findsOneWidget);
      expect(find.textContaining('journal'), findsNothing);
      expect(find.textContaining('0 day'), findsNothing);

      await mount(
        tester,
        const ImportOutcome(source: 'OpenStrap backup', days: 2),
        locale: const Locale('de'),
      );
      expect(find.text('2 Tage importiert'), findsOneWidget);
      expect(find.text('OpenBand-Sicherung'), findsOneWidget);
      expect(find.text('OpenStrap backup'), findsNothing);
      expect(find.textContaining('VO₂'), findsNothing);
      expect(find.textContaining('VO2'), findsNothing);

      await mount(
        tester,
        const ImportOutcome(
          source: 'Encrypted backup + OpenStrap backup',
          vo2TablePresent: true,
          vo2Revisions: 1,
        ),
        locale: const Locale('de'),
      );
      expect(
        find.text('Verschlüsselte Sicherung + OpenBand-Sicherung'),
        findsOneWidget,
      );
      expect(find.textContaining('OpenStrap'), findsNothing);
      expect(find.textContaining('Encrypted backup'), findsNothing);
      expect(find.text('1 VO₂max-Änderung übernommen'), findsOneWidget);

      await mount(
        tester,
        const ImportOutcome(
          source: 'Encrypted backup + OpenStrap backup',
          vo2TablePresent: true,
          vo2Revisions: 1,
        ),
        locale: const Locale('en'),
      );
      expect(
        find.text('Encrypted backup + OpenBand backup'),
        findsOneWidget,
      );
    });
  });

  test('rebuild card keeps conflict ids out of the table lists', () async {
    final l = await AppLocalizations.delegate.load(const Locale('de'));
    final card = dbRebuiltCard((
      cause: 'database disk image is malformed',
      quarantinePath: '/data/openstrap.db.unopenable-1',
      salvaged: const {
        'journal': 3,
        'manual_vo2': 4,
        'manual_vo2_conflict': 2,
        'manual_vo2_corrupt': 1,
        'food_entry': 0,
      },
    ), l)!;
    expect(card.why, contains('journal 3'));
    expect(card.why, contains('manual_vo2 4'));
    expect(card.why, contains('food_entry'));
    expect(card.why, contains('Nicht wiederhergestellt:'));
    expect(card.why, contains('2 VO₂max-Konflikte'));
    expect(card.why, contains('1 VO₂max-Eintrag nicht lesbar'));
    expect(card.why.contains('manual_vo2_conflict'), isFalse);
    expect(card.why.contains('manual_vo2_corrupt'), isFalse);
    expect(card.why, contains('/data/openstrap.db.unopenable-1'));
    expect(card.why, contains('malformed'));
  });

  test('zero accepted VO2 with withheld ids is not an empty table', () async {
    final l = await AppLocalizations.delegate.load(const Locale('de'));
    final card = dbRebuiltCard((
      cause: 'database disk image is malformed',
      quarantinePath: '/data/openstrap.db.unopenable-2',
      salvaged: const {
        'journal': 2,
        'manual_vo2': 0,
        'manual_vo2_conflict': 1,
        'manual_vo2_corrupt': 1,
      },
    ), l)!;
    expect(card.why, contains('journal 2'));
    expect(card.why, contains('Nicht wiederhergestellt:'));
    expect(card.why, contains('1 VO₂max-Konflikt'));
    expect(card.why, contains('1 VO₂max-Eintrag nicht lesbar'));
    expect(card.why.contains('manual_vo2'), isFalse);
    expect(card.why.contains('Empty:'), isFalse);
    expect(card.why.contains('Leer:'), isFalse);
  });
}
