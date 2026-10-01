// Private-copy harness. Emit counts, keys and hashes only, including failures.
// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test/support/derive_idempotence.dart';
import 'private_db_copy.dart';

Future<String> _fileHash(File file) async =>
    (await sha256.bind(file.openRead()).single).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = Platform.environment['OB5_IDEMPOTENCE_DB'];
  testWidgets(
    'copied private database full and light derivation idempotence',
    (tester) async {
      final watch = Stopwatch()..start();
      final root = Directory(
        '/tmp/ob5-storage/derive-idempotence-'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
      final reportFile = File('${root.path}/report.txt');
      final lines = <String>[];
      final failures = <String>[];
      String? errorType;
      void report(String line) {
        lines.add(line);
        reportFile.writeAsStringSync('${lines.join('\n')}\n');
      }

      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      try {
        await runZoned(() async {
          await tester.runAsync(() async {
            try {
              await createPrivateDirectory(root);
              final input = File(source!);
              if (File('$source-wal').existsSync() ||
                  File('$source-shm').existsSync()) {
                throw StateError('Expected closed, standalone source snapshot');
              }
              final sourceHash = await _fileHash(input);
              report('source_sha256=$sourceHash');
              await withPrivateDbCopy(input, root, (dir) async {
                SharedPreferences.setMockInitialValues({});
                await initializeDateFormatting('de_DE');
                sqfliteFfiInit();
                databaseFactory = databaseFactoryFfi;
                await databaseFactory.setDatabasesPath('file:${dir.path}');
                LocalDb.dbName = 'openstrap.db';
                final db = await LocalDb.instance;
                if (db.path != 'file:${dir.path}/openstrap.db' ||
                    LocalDb.lastRebuild != null) {
                  throw StateError('Copy production migration failed');
                }
                final signature = await LocalDb.getCursor(
                  'derived_profile_signature',
                );
                if (signature == null) {
                  throw StateError('Profile signature absent');
                }
                final profile = PersonalProfile.fromMap(
                  (jsonDecode(signature) as Map).cast<String, dynamic>(),
                );
                report('profile_signature_sha256=${digest(signature)}');
                report('stage=housekeeping');
                await completeStorageHousekeeping();
                report('housekeeping_complete_ms=${watch.elapsedMilliseconds}');
                final engine = DerivationEngine(log: (_) {});
                final rawDays = (await LocalDb.decodedRecTsMaxByDay()).keys
                    .toSet();
                report('source_day_count=${rawDays.length}');
                Future<void> run(String stage, {required bool full}) async {
                  report('stage=$stage');
                  final timer = Stopwatch()..start();
                  // run(heavy:true, force:true) still skips finalized rows. The
                  // selected-day production entry with EVERY source day and
                  // force:true restages the complete retained history.
                  final done = full
                      ? await engine.runDays(profile, rawDays, force: true)
                      : await engine.run(profile);
                  final diag = engine.snapshot();
                  report(
                    '$stage rows_derived=$done skipped=${diag['skipped_days']} '
                    'elapsed_ms=${timer.elapsedMilliseconds}',
                  );
                  if (done == 0 ||
                      diag['skipped_days'] != 0 ||
                      diag['last_error'] != null) {
                    failures.add('$stage incomplete production derivation');
                  }
                  if (!full && diag['mode'] != 'light') {
                    failures.add('$stage mode');
                  }
                  if (full && done != rawDays.length) {
                    failures.add('$stage incomplete scope');
                  }
                }

                Future<void> compare(
                  String stage,
                  PersistedSnapshot before,
                ) async {
                  report('stage=$stage-snapshot');
                  final after = await PersistedSnapshot.capture(db);
                  for (final result in compareSnapshots(before, after)) {
                    report('$stage ${result.report}');
                    if (result.differing != 0) {
                      failures.add('$stage ${result.table}');
                    }
                  }
                }

                await run('full-1', full: true);
                report('stage=full-1-snapshot');
                final full = await PersistedSnapshot.capture(db);
                await run('full-2', full: true);
                await compare('full', full);
                await run('light-1', full: false);
                report('stage=light-1-snapshot');
                final light = await PersistedSnapshot.capture(db);
                await run('light-2', full: false);
                await compare('light', light);
                report(
                  'source_unchanged=${await _fileHash(input) == sourceHash}',
                );
                if (await _fileHash(input) != sourceHash) {
                  failures.add('source file hash');
                }
              }, closeDatabase: LocalDb.close);
            } catch (e) {
              // Never expose an exception's SQL arguments, message or stack.
              errorType = e.runtimeType.toString();
            }
          });
        }, zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}));
      } finally {
        debugPrint = originalDebugPrint;
      }
      report('elapsed_total_ms=${watch.elapsedMilliseconds}');
      report('failed_check_count=${failures.length}');
      if (errorType != null) report('harness_error_type=$errorType');
      print(lines.join('\n'));
      print('report=${reportFile.path}');
      expect(errorType, isNull, reason: 'Harness must finish both comparisons');
      expect(failures, isEmpty, reason: failures.join('\n'));
    },
    skip: source == null || source.isEmpty,
    timeout: const Timeout(Duration(minutes: 45)),
  );
}
