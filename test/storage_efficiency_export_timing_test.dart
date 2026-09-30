import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common/sqflite_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  final source = Platform.environment['OB5_STORAGE_TIMING_DB'];
  test(
    'measure decoded-export overhead after complete history compaction',
    () async {
      sqfliteFfiInit();
      final events = <SqfliteLoggerEvent>[];
      // Test-only timings; events stay in memory and no SQL arguments are logged.
      // ignore: experimental_member_use
      databaseFactory = SqfliteDatabaseFactoryLogger(
        databaseFactoryFfi,
        options: SqfliteLoggerOptions(log: events.add),
      );
      final temp = await Directory.systemTemp.createTemp('ob5-export-timing-');
      final originalPaths = PathProviderPlatform.instance;
      try {
        final path = '${temp.path}/timing.db';
        await File(source!).copy(path);
        expect((await Process.run('chmod', ['600', path])).exitCode, 0);
        await databaseFactoryFfi.setDatabasesPath(temp.path);
        PathProviderPlatform.instance = _Paths(temp.path);
        LocalDb.dbName = 'timing.db';
        final db = await LocalDb.instance;
        final converted = await LocalDb.compactLegacyOneHz(
          maxBatches: 10000,
          timeBudget: const Duration(minutes: 3),
        );
        expect(
          jsonDecode(
            (await LocalDb.computeFreshness(
                  LocalDb.kOneHzCompactCursorKey,
                ))!['payload_json']
                as String,
          )['done'],
          isTrue,
        );
        final encoded =
            (await db.rawQuery(
                  'SELECT COUNT(*) AS n '
                  'FROM decoded_onehz WHERE onehz_enc = 1',
                )).single['n']
                as int;
        expect(encoded, converted);
        expect(encoded, greaterThan(0));
        // Compact on-disk layout before measuring the production export path.
        await LocalDb.vacuumIfBloated();
        events.clear();
        final timer = Stopwatch()..start();
        final export = await LocalDb.exportCopy();
        timer.stop();
        final sql = events.whereType<SqfliteLoggerSqlEvent>();
        final vacuum = sql
            .singleWhere((e) => e.sql.startsWith('VACUUM INTO'))
            .sw!
            .elapsedMicroseconds;
        final decode = sql
            .singleWhere(
              (e) => e.sql.startsWith(
                'UPDATE decoded_onehz SET ax = ax / 10000.0',
              ),
            )
            .sw!
            .elapsedMicroseconds;
        final out = await databaseFactory.openDatabase(
          export,
          options: OpenDatabaseOptions(readOnly: true),
        );
        try {
          expect(
            (await out.rawQuery(
              'SELECT COUNT(*) AS n FROM decoded_onehz '
              'WHERE onehz_enc = 1',
            )).single['n'],
            0,
          );
          expect(
            (await out.rawQuery(
              'SELECT COUNT(*) AS n FROM decoded_onehz',
            )).single['n'],
            (await db.rawQuery(
              'SELECT COUNT(*) AS n FROM '
              'decoded_onehz',
            )).single['n'],
          );
        } finally {
          await out.close();
        }
        // Counts, sizes, and elapsed times only; never print physiological values.
        // ignore: avoid_print
        print(
          'Decoded export: rows=$encoded; total=${timer.elapsedMicroseconds / 1000} ms; '
          'VACUUM INTO=${vacuum / 1000} ms; decode UPDATE=${decode / 1000} ms; '
          'extra beyond VACUUM INTO=${(timer.elapsedMicroseconds - vacuum) / 1000} ms; '
          'export bytes=${await File(export).length()}',
        );
      } finally {
        await LocalDb.close();
        PathProviderPlatform.instance = originalPaths;
        await temp.delete(recursive: true);
      }
    },
    skip: source == null
        ? 'Set OB5_STORAGE_TIMING_DB to an authorized read-only DB copy'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
