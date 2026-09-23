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

    test('backup scheduling leaves unrelated pending corrections alone', () async {
      const day = '2026-09-25';
      await LocalDb.putOpenBandSleepDraft(
        dayId: day,
        draftId: 'already-pending',
        onsetMs: 1000,
        wakeMs: 2000,
      );
      await LocalDb.commitOpenBandSleepCorrection(
        dayId: day,
        draftId: 'already-pending',
        onsetMs: 1000,
        wakeMs: 2000,
      );
      final path = await source('unrelated_pending.db', (db) async {
        await db.insert(
          'manual_vo2',
          row(
            id: 'pending-test',
            revision: 1,
            measuredOn: '2026-09-25',
            value: 45,
            created: 1,
          ),
        );
      });

      final receipt = await app.importEdgeBackup(path);

      expect(receipt.pendingRecalculations, 0);
      expect(
        (await LocalDb.openBandSleepCorrection(day))?['status'],
        'pending',
      );
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

    test('a committed preserving page is reported when the next read fails', () async {
      final path = p.join(tmp.path, 'raw_page.db');
      final src = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE raw_backing (
                counter INTEGER PRIMARY KEY,
                hex TEXT NOT NULL,
                packet_type INTEGER,
                captured_at INTEGER NOT NULL,
                rec_ts INTEGER NOT NULL DEFAULT 0,
                uploaded INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await db.execute('''
              CREATE VIEW raw_records AS
              SELECT counter AS rowid, counter, hex, packet_type,
                CASE WHEN counter >= 2000
                  THEN abs(-9223372036854775808)
                  ELSE captured_at END AS captured_at,
                rec_ts, uploaded
              FROM raw_backing
            ''');
          },
        ),
      );
      final batch = src.batch();
      for (var i = 0; i < 2001; i++) {
        batch.insert('raw_backing', {
          'counter': i,
          'hex': i.toRadixString(16),
          'packet_type': 47,
          'captured_at': i,
          'rec_ts': i,
          'uploaded': 0,
        });
      }
      await batch.commit(noResult: true);
      await src.close();

      PartialImportException? interrupted;
      try {
        await LocalDb.importFromDbFile(path);
      } on PartialImportException catch (e) {
        interrupted = e;
      }
      expect(interrupted, isNotNull);
      final receipt = BackupImportReceipt.fromCounts(interrupted!.counts);
      expect(receipt.restoredRows, 2000);
      expect(interrupted.cause.toString(), contains('integer overflow'));
      expect(
        (await (await LocalDb.instance).rawQuery(
          'SELECT COUNT(*) AS n FROM raw_records',
        )).single['n'],
        2000,
      );
    });

    test('a real failing later destination page reports only committed rows', () async {
      final path = p.join(tmp.path, 'raw_dest_failure.db');
      final src = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => db.execute('''
            CREATE TABLE raw_records (
              counter INTEGER PRIMARY KEY,
              hex TEXT NOT NULL,
              packet_type INTEGER,
              captured_at INTEGER NOT NULL,
              rec_ts INTEGER NOT NULL DEFAULT 0,
              uploaded INTEGER NOT NULL DEFAULT 0
            )
          '''),
        ),
      );
      final batch = src.batch();
      for (var i = 0; i < 2001; i++) {
        batch.insert('raw_records', {
          'counter': i,
          'hex': i.toRadixString(16),
          'packet_type': 47,
          'captured_at': i,
          'rec_ts': i,
          'uploaded': 0,
        });
      }
      await batch.commit(noResult: true);
      await src.close();
      LocalDb.debugBeforeNextImportPage = (table) async {
        if (table != 'raw_records') return;
        final dest = await LocalDb.instance;
        await dest.execute('''
          CREATE TRIGGER fail_later_raw_restore
          BEFORE INSERT ON raw_records
          WHEN NEW.counter = 2000
          BEGIN SELECT RAISE(ABORT, 'real destination failure'); END
        ''');
      };

      PartialImportException? interrupted;
      try {
        await LocalDb.importFromDbFile(path);
      } on PartialImportException catch (e) {
        interrupted = e;
      }
      expect(interrupted, isNotNull);
      expect(interrupted!.counts['_restore_imported'], 2000);
      expect(interrupted.cause.toString(), contains('real destination failure'));
      final dest = await LocalDb.instance;
      expect(
        (await dest.rawQuery('SELECT COUNT(*) AS n FROM raw_records')).single['n'],
        2000,
      );
    });

    test('a real failing sleep family keeps the prior family receipt', () async {
      final path = p.join(tmp.path, 'sleep_family_failure.db');
      final src = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE sleep_override (
              day_id TEXT PRIMARY KEY, onset_ts INTEGER NOT NULL,
              offset_ts INTEGER NOT NULL, source TEXT NOT NULL,
              created_at INTEGER NOT NULL, correction_id TEXT, revision INTEGER
            )''');
            await db.execute('''CREATE TABLE openband_sleep_correction (
              day_id TEXT PRIMARY KEY, correction_id TEXT NOT NULL UNIQUE,
              draft_id TEXT UNIQUE, action TEXT NOT NULL, onset_ms INTEGER,
              wake_ms INTEGER, recording_timezone TEXT, revision INTEGER NOT NULL,
              saved_at INTEGER NOT NULL
            )''');
            await db.execute('''CREATE TABLE openband_calculation_job (
              day_id TEXT PRIMARY KEY, correction_id TEXT NOT NULL,
              revision INTEGER NOT NULL, status TEXT NOT NULL,
              requested_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
              error TEXT, result_algo_version INTEGER, result_computed_at INTEGER
            )''');
            await db.execute('''CREATE TABLE openband_sleep_draft (
              day_id TEXT PRIMARY KEY, draft_id TEXT NOT NULL UNIQUE,
              onset_ms INTEGER NOT NULL, wake_ms INTEGER NOT NULL,
              recording_timezone TEXT, updated_at INTEGER NOT NULL
            )''');
          },
        ),
      );
      for (final entry in [('2026-09-01', 'first'), ('2026-09-02', 'second')]) {
        await src.insert('sleep_override', {
          'day_id': entry.$1,
          'onset_ts': 100,
          'offset_ts': 200,
          'source': 'manual',
          'created_at': 1,
          'correction_id': entry.$2,
          'revision': 1,
        });
        await src.insert('openband_sleep_correction', {
          'day_id': entry.$1,
          'correction_id': entry.$2,
          'draft_id': entry.$2,
          'action': 'override',
          'onset_ms': 100000,
          'wake_ms': 200000,
          'revision': 1,
          'saved_at': 1,
        });
        await src.insert('openband_calculation_job', {
          'day_id': entry.$1,
          'correction_id': entry.$2,
          'revision': 1,
          'status': 'complete',
          'requested_at': 1,
          'updated_at': 1,
        });
      }
      await src.close();
      final dest = await LocalDb.instance;
      await dest.execute('''
        CREATE TRIGGER fail_second_sleep_family
        BEFORE INSERT ON sleep_override
        WHEN NEW.day_id = '2026-09-02'
        BEGIN SELECT RAISE(ABORT, 'real sleep destination failure'); END
      ''');

      PartialImportException? interrupted;
      try {
        await LocalDb.importFromDbFile(path);
      } on PartialImportException catch (e) {
        interrupted = e;
      }
      expect(interrupted, isNotNull);
      expect(interrupted!.counts['_restore_imported'], 1);
      expect(interrupted.counts['openband_sleep_pending'], 1);
      expect(interrupted.cause.toString(), contains('real sleep destination failure'));
      expect(await LocalDb.openBandSleepCorrection('2026-09-01'), isNotNull);
      expect(await LocalDb.openBandSleepCorrection('2026-09-02'), isNull);
    });

    test('session children require a matching source and retained parent', () async {
      final path = p.join(tmp.path, 'session_family.db');
      final src = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE sessions (
              id TEXT PRIMARY KEY, start_ts INTEGER NOT NULL, end_ts INTEGER,
              type TEXT NOT NULL, status TEXT NOT NULL, source TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )''');
            await db.execute('''CREATE TABLE openband_lap (
              session_id TEXT NOT NULL, lap_index INTEGER NOT NULL,
              at_ts INTEGER NOT NULL, elapsed_sec INTEGER NOT NULL,
              paused_sec INTEGER NOT NULL, distance_m REAL,
              PRIMARY KEY(session_id, lap_index)
            )''');
            await db.execute('''CREATE TABLE openband_session_detail (
              session_id TEXT PRIMARY KEY, algo_version INTEGER NOT NULL,
              computed_at INTEGER NOT NULL, payload_json TEXT NOT NULL
            )''');
            await db.execute('''CREATE TABLE openband_workout_template (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, version INTEGER NOT NULL,
              exercises_json TEXT NOT NULL, archived INTEGER NOT NULL DEFAULT 0,
              updated_at INTEGER NOT NULL
            )''');
            // Deliberately old/malformed shape without singleton CHECK.
            await db.execute('''CREATE TABLE openband_pinned_template (
              singleton INTEGER PRIMARY KEY, template_id TEXT NOT NULL
            )''');
            await db.execute('''CREATE TABLE raw_records (
              counter INTEGER PRIMARY KEY, hex TEXT NOT NULL,
              packet_type INTEGER, captured_at INTEGER NOT NULL,
              rec_ts INTEGER NOT NULL DEFAULT 0, uploaded INTEGER NOT NULL DEFAULT 0
            )''');
          },
        ),
      );
      await src.insert('sessions', {
        'id': 'same-id',
        'start_ts': 10,
        'end_ts': 20,
        'type': 'source-run',
        'status': 'done',
        'source': 'manual',
        'created_at': 1,
      });
      for (final id in ['same-id', 'orphan-id']) {
        await src.insert('openband_lap', {
          'session_id': id,
          'lap_index': 0,
          'at_ts': 15,
          'elapsed_sec': 5,
          'paused_sec': 0,
        });
        await src.insert('openband_session_detail', {
          'session_id': id,
          'algo_version': 1,
          'computed_at': 1,
          'payload_json': '{}',
        });
      }
      await src.insert('openband_workout_template', {
        'id': 'template-malformed-pin',
        'name': 'Plan',
        'version': 1,
        'exercises_json': '[]',
        'archived': 0,
        'updated_at': 1,
      });
      await src.insert('openband_pinned_template', {
        'singleton': 2,
        'template_id': 'template-malformed-pin',
      });
      await src.insert('raw_records', {
        'counter': 5,
        'hex': '05',
        'captured_at': 5,
        'rec_ts': 5,
      });
      await src.close();

      final dest = await LocalDb.instance;
      for (final id in ['same-id', 'orphan-id']) {
        await dest.insert('sessions', {
          'id': id,
          'start_ts': 100,
          'end_ts': 200,
          'type': 'local-ride',
          'status': 'done',
          'source': 'manual',
          'created_at': 2,
        });
      }
      final receipt = BackupImportReceipt.fromCounts(
        await LocalDb.importFromDbFile(path),
      );
      expect(receipt.restoreConflicts, greaterThanOrEqualTo(3));
      expect(receipt.unreadableRows, greaterThanOrEqualTo(3));
      expect((await dest.query('sessions', where: "id = 'same-id'")).single['type'], 'local-ride');
      expect(await dest.query('openband_lap'), isEmpty);
      expect(await dest.query('openband_session_detail'), isEmpty);
      expect(await dest.query('openband_pinned_template'), isEmpty);
      expect(await dest.query('raw_records', where: 'counter = 5'), hasLength(1));
    });

    test('missing source session table withholds children and continues', () async {
      final path = p.join(tmp.path, 'orphan_session_children.db');
      final src = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE openband_lap (
              session_id TEXT NOT NULL, lap_index INTEGER NOT NULL,
              at_ts INTEGER NOT NULL, elapsed_sec INTEGER NOT NULL,
              paused_sec INTEGER NOT NULL, PRIMARY KEY(session_id, lap_index)
            )''');
            await db.execute('''CREATE TABLE openband_session_detail (
              session_id TEXT PRIMARY KEY, algo_version INTEGER NOT NULL,
              computed_at INTEGER NOT NULL, payload_json TEXT NOT NULL
            )''');
            await db.execute('''CREATE TABLE raw_records (
              counter INTEGER PRIMARY KEY, hex TEXT NOT NULL,
              captured_at INTEGER NOT NULL, rec_ts INTEGER NOT NULL DEFAULT 0,
              uploaded INTEGER NOT NULL DEFAULT 0
            )''');
          },
        ),
      );
      await src.insert('openband_lap', {
        'session_id': 'coincidental',
        'lap_index': 0,
        'at_ts': 1,
        'elapsed_sec': 1,
        'paused_sec': 0,
      });
      await src.insert('openband_session_detail', {
        'session_id': 'coincidental',
        'algo_version': 1,
        'computed_at': 1,
        'payload_json': '{}',
      });
      await src.insert('raw_records', {
        'counter': 9,
        'hex': '09',
        'captured_at': 9,
        'rec_ts': 9,
      });
      await src.close();
      final dest = await LocalDb.instance;
      await dest.insert('sessions', {
        'id': 'coincidental',
        'start_ts': 10,
        'type': 'local',
        'status': 'done',
        'source': 'manual',
        'created_at': 1,
      });

      final receipt = BackupImportReceipt.fromCounts(
        await LocalDb.importFromDbFile(path),
      );

      expect(receipt.unreadableRows, 2);
      expect(await dest.query('openband_lap'), isEmpty);
      expect(await dest.query('openband_session_detail'), isEmpty);
      expect(await dest.query('raw_records', where: 'counter = 9'), hasLength(1));
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

    test('full export restores durable rows and sleep families idempotently', () async {
      final destinationName = LocalDb.dbName;
      final sourceName = 'backup_restore_source_$n.db';
      await LocalDb.close();
      LocalDb.dbName = sourceName;
      await databaseFactory.deleteDatabase(
        p.join(await databaseFactory.getDatabasesPath(), sourceName),
      );
      final sourceDb = await LocalDb.instance;
      await sourceDb.insert('openband_workout_template', {
        'id': 'template-1',
        'name': 'Intervals',
        'version': 1,
        'exercises_json': '[]',
        'archived': 0,
        'updated_at': 1,
      });
      await sourceDb.insert('openband_pinned_template', {
        'singleton': 1,
        'template_id': 'template-1',
      });
      await sourceDb.insert('openband_meal_draft', {
        'draft_id': 'meal-1',
        'day_id': '2026-09-18',
        'meal': 'dinner',
        'entries_json': '[]',
        'updated_at': 2,
      });
      await sourceDb.insert('sessions', {
        'id': 'session-1',
        'start_ts': 100,
        'end_ts': 200,
        'type': 'run',
        'status': 'done',
        'source': 'manual',
        'created_at': 1,
      });
      await sourceDb.insert('openband_session_detail', {
        'session_id': 'session-1',
        'algo_version': 1,
        'computed_at': 2,
        'payload_json': '{"frozen":true}',
      });
      await sourceDb.insert('openband_lap', {
        'session_id': 'session-1',
        'lap_index': 0,
        'at_ts': 150,
        'elapsed_sec': 50,
        'paused_sec': 0,
        'distance_m': 400.0,
      });
      await sourceDb.insert('alarm_schedule', {
        'weekday': 2,
        'hour': 7,
        'minute': 15,
        'enabled': 0,
      });
      await sourceDb.insert('workout_suggestions', {
        'id': 'suggestion-1',
        'date': '2026-09-18',
        'start_ts': 100,
        'end_ts': 200,
        'dismissed': 1,
        'created_at': 3,
      });
      await sourceDb.insert('live_coverage', {
        'start_ts': 100,
        'end_ts': 160,
        'steps': 42,
        'day': '2026-09-18',
        'source': 'band_100hz',
        'device_id': '',
      });
      await sourceDb.insert('raw_records', {
        'counter': 0,
        'hex': '00ff',
        'packet_type': 47,
        'captured_at': 1000,
        'rec_ts': 1,
        'uploaded': 0,
      });

      const editedDay = '2026-09-18';
      await LocalDb.putOpenBandSleepDraft(
        dayId: editedDay,
        draftId: 'saved-edit',
        onsetMs: 100000,
        wakeMs: 200000,
      );
      await LocalDb.commitOpenBandSleepCorrection(
        dayId: editedDay,
        draftId: 'saved-edit',
        onsetMs: 100000,
        wakeMs: 200000,
      );
      // A committed correction and a later in-progress edit are both durable.
      await LocalDb.putOpenBandSleepDraft(
        dayId: editedDay,
        draftId: 'next-edit',
        onsetMs: 110000,
        wakeMs: 210000,
      );
      const automaticDay = '2026-09-19';
      await LocalDb.putOpenBandSleepDraft(
        dayId: automaticDay,
        draftId: 'auto-edit',
        onsetMs: 300000,
        wakeMs: 400000,
      );
      await LocalDb.commitOpenBandSleepCorrection(
        dayId: automaticDay,
        draftId: 'auto-edit',
        onsetMs: 300000,
        wakeMs: 400000,
      );
      await LocalDb.restoreOpenBandAutomatic(automaticDay);
      // A newer source may carry columns this destination does not know yet.
      await sourceDb.execute(
        'ALTER TABLE sleep_override ADD COLUMN future_override TEXT',
      );
      await sourceDb.execute(
        'ALTER TABLE openband_sleep_correction ADD COLUMN future_correction TEXT',
      );
      await sourceDb.execute(
        'ALTER TABLE openband_sleep_draft ADD COLUMN future_draft TEXT',
      );
      await sourceDb.update('sleep_override', {'future_override': 'new'});
      await sourceDb.update(
        'openband_sleep_correction',
        {'future_correction': 'new'},
      );
      await sourceDb.update('openband_sleep_draft', {'future_draft': 'new'});
      final backup = await LocalDb.exportCopy();

      await LocalDb.close();
      LocalDb.dbName = destinationName;
      await databaseFactory.deleteDatabase(
        p.join(await databaseFactory.getDatabasesPath(), destinationName),
      );
      final dest = await LocalDb.instance;
      final firstCounts = await LocalDb.importFromDbFile(backup);
      final first = BackupImportReceipt.fromCounts(firstCounts);
      expect(first.restoredRows, 13);
      expect(first.unchangedRows, 0);
      expect(first.restoreConflicts, 0);
      expect(first.unreadableRows, 0);
      expect(first.pendingRecalculations, 2);
      for (final table in [
        'openband_workout_template',
        'openband_pinned_template',
        'openband_meal_draft',
        'openband_session_detail',
        'openband_lap',
        'alarm_schedule',
        'workout_suggestions',
        'live_coverage',
        'raw_records',
      ]) {
        expect(
          (await dest.rawQuery('SELECT COUNT(*) AS n FROM $table')).single['n'],
          1,
          reason: table,
        );
      }
      expect(
        (await dest.query('raw_records')).single['counter'],
        0,
        reason: 'counter zero must survive rowid paging',
      );
      expect(
        (await LocalDb.openBandSleepDraft(editedDay))?['draft_id'],
        'next-edit',
      );
      expect(
        (await LocalDb.openBandSleepCorrection(automaticDay))?['action'],
        'automatic',
      );
      expect(await LocalDb.getSleepOverride(automaticDay), isNull);

      final legacySource = await databaseFactory.openDatabase(
        backup,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await legacySource.insert('sleep_override', {
        'day_id': '2026-09-20',
        'onset_ts': 500,
        'offset_ts': 600,
        'source': 'manual',
        'created_at': 1,
        'correction_id': null,
        'revision': 0,
      });
      await legacySource.insert('openband_sleep_draft', {
        'day_id': '2026-09-20',
        'draft_id': 'legacy-next-edit',
        'onset_ms': 510000,
        'wake_ms': 610000,
        'updated_at': 2,
      });
      await legacySource.insert('openband_sleep_draft', {
        'day_id': '',
        'draft_id': 'invalid-empty-day',
        'onset_ms': 1,
        'wake_ms': 2,
        'updated_at': 1,
      });
      await legacySource.insert('openband_sleep_draft', {
        'day_id': '2026-09-26',
        'draft_id': '',
        'onset_ms': 1,
        'wake_ms': 2,
        'updated_at': 1,
      });
      await legacySource.insert('sleep_override', {
        'day_id': '2026-09-21',
        'onset_ts': 700,
        'offset_ts': 800,
        'source': 'manual',
        'created_at': 1,
        'correction_id': 'missing-correction',
        'revision': 3,
      });
      await legacySource.close();
      final legacyReceipt = BackupImportReceipt.fromCounts(
        await LocalDb.importFromDbFile(backup),
      );
      expect(legacyReceipt.restoredRows, 2);
      expect(legacyReceipt.unchangedRows, 13);
      expect(legacyReceipt.unreadableRows, 3);
      expect(
        (await LocalDb.openBandSleepDraft('2026-09-20'))?['draft_id'],
        'legacy-next-edit',
      );
      expect(await LocalDb.getSleepOverride('2026-09-20'), isNotNull);
      expect(await LocalDb.getSleepOverride('2026-09-21'), isNull);

      await LocalDb.updateOpenBandCalculationJob(
        dayId: editedDay,
        correctionId: 'saved-edit',
        revision: 1,
        status: 'complete',
        fromStatuses: const {'pending'},
      );
      final repeat = BackupImportReceipt.fromCounts(
        await LocalDb.importFromDbFile(backup),
      );
      expect(repeat.restoredRows, 0);
      expect(repeat.unchangedRows, 15);
      expect(repeat.restoreConflicts, 0);
      expect(repeat.unreadableRows, 3);
      expect(repeat.pendingRecalculations, 0);
      expect(
        (await LocalDb.openBandSleepCorrection(editedDay))?['status'],
        'complete',
        reason: 'an identical retry must not reset a completed job',
      );

      // A destination draft is saved work and blocks a source family that
      // would change its context.
      const draftConflictDay = '2026-09-22';
      final familySource = await databaseFactory.openDatabase(
        backup,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await familySource.insert('sleep_override', {
        'day_id': draftConflictDay,
        'onset_ts': 900,
        'offset_ts': 1000,
        'source': 'manual',
        'created_at': 1,
        'correction_id': 'source-family',
        'revision': 1,
      });
      await familySource.insert('openband_sleep_correction', {
        'day_id': draftConflictDay,
        'correction_id': 'source-family',
        'draft_id': 'source-family',
        'action': 'override',
        'onset_ms': 900000,
        'wake_ms': 1000000,
        'revision': 1,
        'saved_at': 1,
      });
      await familySource.insert('openband_calculation_job', {
        'day_id': draftConflictDay,
        'correction_id': 'source-family',
        'revision': 1,
        'status': 'complete',
        'requested_at': 1,
        'updated_at': 1,
      });
      const duplicateDraftDay = '2026-09-23';
      await familySource.insert('sleep_override', {
        'day_id': duplicateDraftDay,
        'onset_ts': 1100,
        'offset_ts': 1200,
        'source': 'manual',
        'created_at': 1,
        'correction_id': 'source-with-draft',
        'revision': 1,
      });
      await familySource.insert('openband_sleep_correction', {
        'day_id': duplicateDraftDay,
        'correction_id': 'source-with-draft',
        'draft_id': 'source-with-draft',
        'action': 'override',
        'onset_ms': 1100000,
        'wake_ms': 1200000,
        'revision': 1,
        'saved_at': 1,
      });
      await familySource.insert('openband_calculation_job', {
        'day_id': duplicateDraftDay,
        'correction_id': 'source-with-draft',
        'revision': 1,
        'status': 'complete',
        'requested_at': 1,
        'updated_at': 1,
      });
      await familySource.insert('openband_sleep_draft', {
        'day_id': duplicateDraftDay,
        'draft_id': 'cross-day-duplicate',
        'onset_ms': 1110000,
        'wake_ms': 1210000,
        'updated_at': 1,
      });
      await familySource.close();
      await LocalDb.putOpenBandSleepDraft(
        dayId: draftConflictDay,
        draftId: 'local-draft',
        onsetMs: 910000,
        wakeMs: 1010000,
      );
      await LocalDb.putOpenBandSleepDraft(
        dayId: '2026-09-24',
        draftId: 'cross-day-duplicate',
        onsetMs: 1300000,
        wakeMs: 1400000,
      );
      final draftConflict = BackupImportReceipt.fromCounts(
        await LocalDb.importFromDbFile(backup),
      );
      expect(draftConflict.restoreConflicts, greaterThanOrEqualTo(3));
      expect(await LocalDb.openBandSleepCorrection(draftConflictDay), isNull);
      expect(await LocalDb.openBandSleepCorrection(duplicateDraftDay), isNull);
      expect(
        (await LocalDb.openBandSleepDraft(draftConflictDay))?['draft_id'],
        'local-draft',
      );

      await dest.delete('openband_meal_draft');
      await dest.insert('openband_meal_draft', {
        'draft_id': 'local-meal',
        'day_id': '2026-09-18',
        'meal': 'dinner',
        'entries_json': '[{"local":true}]',
        'updated_at': 99,
      });
      final mealConflict = BackupImportReceipt.fromCounts(
        await LocalDb.importFromDbFile(backup),
      );
      expect(mealConflict.restoreConflicts, greaterThanOrEqualTo(2));
      expect(
        (await dest.query('openband_meal_draft')).single['draft_id'],
        'local-meal',
      );

      // A numerically newer source still cannot overwrite a different local
      // family: revisions from independent databases do not prove ancestry.
      final writableBackup = await databaseFactory.openDatabase(
        backup,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await writableBackup.update(
        'openband_sleep_correction',
        {'revision': 8, 'onset_ms': 120000, 'wake_ms': 220000},
        where: 'day_id = ?',
        whereArgs: [editedDay],
      );
      await writableBackup.update(
        'sleep_override',
        {'revision': 8, 'onset_ts': 120, 'offset_ts': 220},
        where: 'day_id = ?',
        whereArgs: [editedDay],
      );
      await writableBackup.update(
        'openband_calculation_job',
        {'revision': 8},
        where: 'day_id = ?',
        whereArgs: [editedDay],
      );
      await writableBackup.close();
      final divergent = BackupImportReceipt.fromCounts(
        await LocalDb.importFromDbFile(backup),
      );
      expect(divergent.restoreConflicts, greaterThanOrEqualTo(1));
      expect(
        (await LocalDb.openBandSleepCorrection(editedDay))?['revision'],
        1,
      );
      await dest.update(
        'openband_sleep_correction',
        {'revision': 10},
        where: 'day_id = ?',
        whereArgs: [editedDay],
      );
      await dest.update(
        'sleep_override',
        {'revision': 10},
        where: 'day_id = ?',
        whereArgs: [editedDay],
      );
      await dest.update(
        'openband_calculation_job',
        {'revision': 10},
        where: 'day_id = ?',
        whereArgs: [editedDay],
      );
      final olderSource = BackupImportReceipt.fromCounts(
        await LocalDb.importFromDbFile(backup),
      );
      expect(olderSource.restoreConflicts, greaterThanOrEqualTo(1));
      expect(
        (await LocalDb.openBandSleepCorrection(editedDay))?['revision'],
        10,
      );

      // A pin cannot be attached to a same-id local template whose content
      // differs from the source parent.
      await dest.update(
        'openband_workout_template',
        {'name': 'Local plan'},
        where: 'id = ?',
        whereArgs: ['template-1'],
      );
      await dest.delete('openband_pinned_template');
      final parentConflict = BackupImportReceipt.fromCounts(
        await LocalDb.importFromDbFile(backup),
      );
      expect(parentConflict.restoreConflicts, greaterThanOrEqualTo(2));
      expect(await dest.query('openband_pinned_template'), isEmpty);
      expect(
        (await dest.query('openband_workout_template')).single['name'],
        'Local plan',
      );

      // SQLite can return TEXT from an INTEGER-affinity column. Refuse it at
      // the family boundary instead of throwing a cast over the whole restore.
      final malformed = await databaseFactory.openDatabase(
        backup,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await malformed.rawUpdate(
        'UPDATE openband_sleep_correction SET onset_ms = ? WHERE day_id = ?',
        ['not-a-number', editedDay],
      );
      await malformed.close();
      final malformedReceipt = BackupImportReceipt.fromCounts(
        await LocalDb.importFromDbFile(backup),
      );
      expect(malformedReceipt.unreadableRows, greaterThanOrEqualTo(2));
      expect(
        (await LocalDb.openBandSleepCorrection(editedDay))?['revision'],
        10,
      );

      final fractional = await databaseFactory.openDatabase(
        backup,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await fractional.update(
        'openband_sleep_correction',
        {'revision': 8.5, 'onset_ms': 120000.5, 'wake_ms': 220000},
        where: 'day_id = ?',
        whereArgs: [editedDay],
      );
      await fractional.update(
        'sleep_override',
        {'revision': 8.5, 'onset_ts': 120.5, 'offset_ts': 220},
        where: 'day_id = ?',
        whereArgs: [editedDay],
      );
      await fractional.update(
        'openband_calculation_job',
        {'revision': 8.5},
        where: 'day_id = ?',
        whereArgs: [editedDay],
      );
      await fractional.close();
      final fractionalReceipt = BackupImportReceipt.fromCounts(
        await LocalDb.importFromDbFile(backup),
      );
      expect(fractionalReceipt.unreadableRows, greaterThanOrEqualTo(2));
      expect(
        (await LocalDb.openBandSleepCorrection(editedDay))?['revision'],
        10,
      );
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
    }, tags: const ['golden']);

    testWidgets('durable restore receipt is concise and truthful', (tester) async {
      await mount(
        tester,
        const ImportOutcome(
          source: 'OpenStrap backup',
          restoredRows: 12,
          unchangedRows: 3,
          restoreConflicts: 1,
          unreadableRows: 1,
          pendingRecalculations: 2,
        ),
      );
      expect(find.text('Teilweise importiert'), findsOneWidget);
      expect(find.text('12 Einträge gespeichert'), findsOneWidget);
      expect(find.text('3 unverändert'), findsOneWidget);
      expect(find.text('1 Konflikt · lokal beibehalten'), findsOneWidget);
      expect(find.text('1 Eintrag nicht lesbar'), findsOneWidget);
      expect(find.text('2 Neuberechnungen ausstehend'), findsOneWidget);

      await mount(
        tester,
        const ImportOutcome(
          source: 'OpenStrap backup',
          restoreConflicts: 1,
          unreadableRows: 1,
        ),
        locale: const Locale('en'),
      );
      expect(find.text('Not imported'), findsOneWidget);
      expect(find.text('Partially imported'), findsNothing);
      expect(find.text('1 conflict · local version kept'), findsOneWidget);
    });

    testWidgets('partial dark', (tester) async {
      await mount(tester, _partial, brightness: Brightness.dark);
      expect(find.text('Teilweise importiert'), findsOneWidget);
      expect(find.byIcon(LucideIcons.check), findsNothing);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/backup_receipt_partial_dark.png'),
      );
    }, tags: const ['golden']);

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
    }, tags: const ['golden']);

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
