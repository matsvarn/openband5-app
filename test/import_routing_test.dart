// Issues #160 / #199: the onboarding router picked an importer by FILE
// EXTENSION, and got it wrong in both directions at once.
//
//   • NOOP's Android "raw sensor CSV" export is a plain `.csv`, so it went to
//     the vendor importer, which told the user to re-download it with WHOOP
//     set to English. (That is the exact file attached to #160.)
//   • A WHOOP "My Data" export is a `.zip` of CSVs — the shape WHOOP actually
//     gives you — so it went to the NOOP importer, which refused it for
//     holding too many CSVs.
//
// Both files were fine. Both were refused, each with advice meant for the
// other one. These tests drive the real `runImport` and assert WHICH importer
// each shape reaches, so neither direction can come back.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/backup_import_result.dart';
import 'package:openstrap_edge/import/journal_csv_import.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/onboarding/welcome.dart';

/// Records where `runImport` sent each path instead of importing it. Every
/// override replaces work that needs a database and a derivation engine; the
/// routing decision above them is what is under test.
class _RoutingSpy extends AppState {
  _RoutingSpy() : super.forTesting();

  final noop = <String>[];
  final vendor = <String>[];
  final backups = <String>[];
  final receipts = <String, BackupImportReceipt>{};
  final rawFailures = <String>{};

  @override
  Future<BackupImportReceipt> importEdgeBackup(String path) async {
    backups.add(path);
    return receipts[path] ??
        const BackupImportReceipt(
          days: 0,
          vo2TablePresent: false,
          insertedRevisions: 0,
          conflictIds: 0,
          corruptIds: 0,
        );
  }

  @override
  Future<int> importNoopCsv(String path,
      {void Function(int days)? onProgress}) async {
    noop.add(path);
    if (rawFailures.contains(path)) throw StateError('raw read failed');
    return 1;
  }

  @override
  Future<int> importWhoopCsvs(List<String> paths,
      {void Function(int days)? onProgress}) async {
    vendor.addAll(paths);
    return 1;
  }
}

List<int> _zipOf(Map<String, String> members) {
  final a = Archive();
  members.forEach((name, body) {
    final bytes = utf8.encode(body);
    a.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encode(a);
}

/// The header row a real NOOP raw-sensor export starts with (NOOP 9.1/9.2, as
/// observed on the #160 attachment).
const _noopCsv = 'unix_s,iso_utc,stream,hr_bpm,rr_ms,grav_x,grav_y,grav_z\n'
    '1754000000,2026-08-01T00:00:00Z,hr,61,,,,\n';

/// A WHOOP "My Data" export, which is several named CSVs in one archive.
const _whoopZipMembers = {
  'physiological_cycles.csv': 'Cycle start time,Recovery score %\n',
  'sleeps.csv': 'Cycle start time,Sleep performance %\n',
  'workouts.csv': 'Workout start time,Activity name\n',
  'journal_entries.csv': 'Cycle start time,Question text\n',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('import_routing_test_');
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<String> write(String name, List<int> bytes) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  test('a NOOP raw-sensor CSV goes to the NOOP importer, not the vendor one',
      () async {
    final app = _RoutingSpy();
    final path = await write('noop-export.csv', utf8.encode(_noopCsv));

    final out = await runImport(app, [path]);

    expect(app.noop, [path]);
    expect(app.vendor, isEmpty,
        reason: 'this is the #160 file — the vendor importer answers it with '
            '"re-download it with WHOOP set to English"');
    expect(out.source, contains('Raw sensor export'));
  });

  test('a WHOOP My Data ZIP goes to the vendor importer, not the NOOP one',
      () async {
    final app = _RoutingSpy();
    final path = await write('my_whoop_data.zip', _zipOf(_whoopZipMembers));

    final out = await runImport(app, [path]);

    expect(app.vendor, [path]);
    expect(app.noop, isEmpty,
        reason: 'the NOOP importer refuses this for holding too many CSVs');
    expect(out.source, contains('Vendor CSV export'));
  });

  test('a .noopbak still routes to NOOP once the name stops deciding',
      () async {
    final app = _RoutingSpy();
    // The real shape: a ZIP whose member is NOOP's own SQLite database. The
    // magic is what identifies it, so the bytes have to be real.
    final path = await write(
      'backup.noopbak',
      _zipOf({'noop-backup.sqlite': 'SQLite format 3\x00 and then some rows'}),
    );

    await runImport(app, [path]);

    expect(app.noop, [path]);
    expect(app.vendor, isEmpty);
  });

  test('a NOOP CSV keeps routing to NOOP when someone zips it first', () async {
    final app = _RoutingSpy();
    final path =
        await write('noop.zip', _zipOf({'raw_sensor.csv': _noopCsv}));

    await runImport(app, [path]);

    expect(app.noop, [path]);
    expect(app.vendor, isEmpty);
  });

  test('a mixed selection reaches both importers', () async {
    final app = _RoutingSpy();
    final noopPath = await write('noop-export.csv', utf8.encode(_noopCsv));
    final whoopPath = await write('whoop.zip', _zipOf(_whoopZipMembers));

    final out = await runImport(app, [noopPath, whoopPath]);

    expect(app.noop, [noopPath]);
    expect(app.vendor, [whoopPath]);
    expect(out.source, contains('Raw sensor export'));
    expect(out.source, contains('Vendor CSV export'));
  });

  test('two database backups aggregate days and VO2 counts separately', () async {
    final app = _RoutingSpy();
    final older = await write('older.db', [0, 1, 2, 3]);
    final newer = await write('newer.db', [4, 5, 6, 7]);
    app.receipts[older] = const BackupImportReceipt(
      days: 3,
      vo2TablePresent: false,
      insertedRevisions: 0,
      conflictIds: 0,
      corruptIds: 0,
    );
    app.receipts[newer] = const BackupImportReceipt(
      days: 1,
      vo2TablePresent: true,
      insertedRevisions: 2,
      conflictIds: 1,
      corruptIds: 1,
      recalculationError: 'rollup',
    );

    final out = await runImport(app, [older, newer]);

    expect(app.backups, [older, newer]);
    expect(out.days, 4);
    expect(out.vo2TablePresent, isTrue);
    expect(out.vo2Revisions, 2);
    expect(out.vo2ConflictIds, 1);
    expect(out.vo2CorruptIds, 1);
    expect(out.rollupError, 'rollup');
    expect(out.nothingLanded, isFalse);
  });

  test('an old backup without a VO2 table stays absent in the aggregate', () async {
    final app = _RoutingSpy();
    final a = await write('a.db', [0]);
    final b = await write('b.db', [1]);
    const absent = BackupImportReceipt(
      days: 1,
      vo2TablePresent: false,
      insertedRevisions: 0,
      conflictIds: 0,
      corruptIds: 0,
    );
    app.receipts[a] = absent;
    app.receipts[b] = const BackupImportReceipt(
      days: 0,
      vo2TablePresent: false,
      insertedRevisions: 0,
      conflictIds: 0,
      corruptIds: 0,
    );

    final out = await runImport(app, [a, b]);

    expect(out.days, 1);
    expect(out.vo2TablePresent, isFalse);
    expect(out.vo2Revisions, 0);
  });

  test('a committed backup survives a later raw read failure', () async {
    final app = _RoutingSpy();
    final backup = await write('band.db', [1, 2, 3, 4]);
    final raw = await write('sensors.csv', utf8.encode(_noopCsv));
    final later = await write('sensors-2.csv', utf8.encode(_noopCsv));
    app.receipts[backup] = const BackupImportReceipt(
      days: 0,
      vo2TablePresent: true,
      insertedRevisions: 2,
      conflictIds: 0,
      corruptIds: 0,
    );
    app.rawFailures.add(raw);

    final out = await runImport(app, [backup, raw, later]);

    expect(app.backups, [backup]);
    expect(app.noop, [raw, later]);
    expect(out.error, isNull);
    expect(out.vo2TablePresent, isTrue);
    expect(out.vo2Revisions, 2);
    expect(out.days, 1);
    expect(out.readError, contains('raw read failed'));
    expect(out.nothingLanded, isFalse);
  });

  test('a raw file that is the only selection still fails', () async {
    final app = _RoutingSpy();
    final raw = await write('only.csv', utf8.encode(_noopCsv));
    app.rawFailures.add(raw);

    await expectLater(
      runImport(app, [raw]),
      throwsA(isA<StateError>()),
    );
  });

  test('a journal format error still reaches the vendor importer', () async {
    final app = _RoutingSpy();
    final path = await write('notes.csv', utf8.encode('not,a,journal\n'));

    final out = await runImport(app, [path]);

    expect(app.vendor, [path]);
    expect(app.noop, isEmpty);
    expect(out.journalRows, 0);
  });

  test('a committed backup survives an unexpected journal failure', () async {
    final app = _RoutingSpy();
    final backup = await write('kept.db', [9]);
    final bad = await write('bad-journal.csv', utf8.encode('date,tags,note\n'));
    final later = await write('later-journal.csv', utf8.encode('date,tags,note\n'));
    app.receipts[backup] = const BackupImportReceipt(
      days: 3,
      vo2TablePresent: true,
      insertedRevisions: 1,
      conflictIds: 0,
      corruptIds: 0,
    );
    final seen = <String>[];

    final out = await runImport(
      app,
      [backup, bad, later],
      debugReadJournal: (path) async {
        seen.add(path);
        if (path == bad) throw StateError('journal read failed');
        return const JournalImportResult(4, []);
      },
    );

    expect(seen, [bad, later]);
    expect(out.error, isNull);
    expect(out.days, 3);
    expect(out.vo2Revisions, 1);
    expect(out.journalRows, 4);
    expect(out.readError, contains('journal read failed'));
    expect(out.nothingLanded, isFalse);
  });
}
