// Run with Flutter 3.41.6: OB5_BENCH_DB=/tmp/ob5-storage/orig.db
// flutter test --no-pub tool/storage_bench_test.dart --reporter expanded
// Copies the input before opening it. Never logs SQL arguments or result rows.
// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/screens/heute.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqflite_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'g3_screens/env.dart';
import 'g3_screens/heute.dart';

String sqlShape(String sql) => sql
    .replaceAll(RegExp(r"X?'(?:''|[^'])*'", caseSensitive: false), '?')
    .replaceAll(RegExp(r'\b\d+(?:\.\d+)?\b'), '?')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
String cell(String value) => value.replaceAll('|', r'\|').replaceAll('\n', ' ');
double ms(Stopwatch sw) => sw.elapsedMicroseconds / 1000;
double percentile(List<double> xs, double p) {
  final sorted = [...xs]..sort();
  return sorted[((sorted.length * p).ceil() - 1).clamp(0, sorted.length - 1)];
}

double median(List<double> xs) {
  final sorted = [...xs]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

String n(double v) => v.toStringAsFixed(3);

class SqlStat {
  SqlStat(this.sql, this.args);
  final String sql;
  final List<Object?>? args;
  int calls = 0, operations = 0, failures = 0;
  double total = 0, max = 0;
  void add(double duration, {int ops = 1, bool failed = false}) {
    calls++;
    operations += ops;
    failures += failed ? 1 : 0;
    total += duration;
    if (duration > max) max = duration;
  }
}

class Bench {
  final timings = <String, List<double>>{};
  final sql = <String, SqlStat>{};
  final batches = <String, SqlStat>{};
  final sizes = <String>[];
  final diagnostics = <String>[];
  final summaries = <String>[];
  final persisted = <String>[];
  final comparisons = <String>[];
  final plans = <String, String>{};
  final phaseSqlMs = <String, double>{};
  final phaseSqlCalls = <String, int>{};
  final cache = <String, String>{};
  String phase = '';
  bool trace = false;
  int observedStatements = 0;
  String day = 'unavailable', latestDay = 'unavailable';
  Map<String, dynamic>? profileMap;
  String profileSource = 'absent';
  late Map<String, String> originalPayloads;
  int sourceOneHz = 0, sourceRr = 0, sourceBlobs = 0;
  final total = Stopwatch()..start();
  int sqlFailures = 0;
  String shape(String raw) => cache.putIfAbsent(raw, () => sqlShape(raw));

  void log(SqfliteLoggerEvent event) {
    if (!trace) return;
    final elapsed = event.sw == null ? 0.0 : ms(event.sw!);
    if (event is SqfliteLoggerSqlEvent) {
      final args = event.arguments;
      final key = shape(event.sql);
      final stat = sql.putIfAbsent(
        key,
        () => SqlStat(
          event.sql,
          args is List ? args.cast<Object?>().toList() : null,
        ),
      );
      stat.add(elapsed, failed: event.error != null);
      observedStatements++;
      if (event.error != null) sqlFailures++;
      phaseSqlMs.update(phase, (v) => v + elapsed, ifAbsent: () => elapsed);
      phaseSqlCalls.update(phase, (v) => v + 1, ifAbsent: () => 1);
    } else if (event is SqfliteLoggerBatchEvent) {
      // sqflite exposes one measured duration for the whole batch. Do not
      // divide it amongst operations or claim an individual statement time.
      final signatures = <String, int>{};
      for (final op in event.operations) {
        final key = shape(op.sql);
        signatures.update(key, (v) => v + 1, ifAbsent: () => 1);
        final args = op.arguments;
        final stat = sql.putIfAbsent(
          key,
          () => SqlStat(
            op.sql,
            args is List ? args.cast<Object?>().toList() : null,
          ),
        );
        stat.operations++;
        observedStatements++;
      }
      final key = (signatures.keys.toList()..sort()).join('; ');
      batches
          .putIfAbsent(key, () => SqlStat(key, null))
          .add(
            elapsed,
            ops: event.operations.length,
            failed: event.error != null,
          );
      phaseSqlMs.update(phase, (v) => v + elapsed, ifAbsent: () => elapsed);
      phaseSqlCalls.update(phase, (v) => v + 1, ifAbsent: () => 1);
      if (event.error != null) sqlFailures++;
    }
  }

  Future<T> measure<T>(String label, Future<T> Function() body) async {
    final sw = Stopwatch()..start();
    final result = await body();
    sw.stop();
    timings.putIfAbsent(label, () => []).add(ms(sw));
    return result;
  }

  Future<Directory> copy() async {
    await LocalDb.close();
    final source = Platform.environment['OB5_BENCH_DB'];
    if (source == null) throw StateError('OB5_BENCH_DB is required');
    if (source.contains('OpenBand5Lab')) throw StateError('Lab paths refused');
    final dir = Directory.systemTemp.createTempSync('ob5-storage-bench-');
    File(source).copySync('${dir.path}/openstrap.db');
    // A chmod-444 source preserves its mode when copied on macOS.
    final chmod = await Process.run('chmod', [
      '600',
      '${dir.path}/openstrap.db',
    ]);
    if (chmod.exitCode != 0) throw StateError('Copy chmod failed');
    await databaseFactoryFfi.setDatabasesPath(dir.path);
    await databaseFactory.setDatabasesPath(dir.path);
    LocalDb.dbName = 'openstrap.db';
    return dir;
  }

  Future<Database> verifiedOpen(Directory dir) async {
    final db = await LocalDb.instance;
    if (db.path != '${dir.path}/openstrap.db' || LocalDb.lastRebuild != null) {
      throw StateError('Production open did not preserve the input copy');
    }
    return db;
  }

  Future<void> verifyCounts(Database db) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM decoded_onehz');
    if (rows.first['n'] != sourceOneHz) {
      throw StateError('Copy row count changed at open');
    }
  }

  int bytes(String path) =>
      File(path).existsSync() ? File(path).lengthSync() : 0;
  void size(Directory dir, String label) {
    sizes.add(
      '| ${cell(label)} | ${bytes('${dir.path}/openstrap.db')} | '
      '${bytes('${dir.path}/openstrap.db-wal')} |',
    );
  }

  Future<void> clean(Directory dir) async {
    trace = false;
    await LocalDb.close();
    dir.deleteSync(recursive: true);
  }

  Future<void> baseline() async {
    final dir = await copy();
    // Read the untouched INPUT COPY, bypassing production repair for hashes.
    final db = await databaseFactoryFfi.openDatabase(
      '${dir.path}/openstrap.db',
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    if (await db.getVersion() != LocalDb.schemaVersion) {
      throw StateError('Input schema differs from production');
    }
    originalPayloads = await payloads(db);
    final signatureRows = await db.query(
      'sync_cursor',
      columns: ['value'],
      where: 'name = ?',
      whereArgs: ['derived_profile_signature'],
    );
    if (signatureRows.isNotEmpty) {
      profileMap = (jsonDecode(signatureRows.first['value'] as String) as Map)
          .cast<String, dynamic>();
      profileSource = 'recovered from derived_profile_signature';
    }
    final days = (await db.rawQuery(
      "SELECT DISTINCT strftime('%Y-%m-%d',rec_ts,'unixepoch','localtime') AS d "
      'FROM decoded_onehz ORDER BY d',
    )).map((r) => r['d'] as String).toList();
    latestDay = days.last;
    final lastTs =
        (await db.rawQuery(
              'SELECT MAX(rec_ts) AS t FROM decoded_onehz',
            )).first['t']
            as int;
    final edge = DateTime.fromMillisecondsSinceEpoch(lastTs * 1000);
    final complete = days
        .where(
          (d) => DateTime.parse(
            d,
          ).isBefore(DateTime(edge.year, edge.month, edge.day)),
        )
        .toList();
    day = complete.last;
    for (final table in ['decoded_onehz', 'decoded_rr', 'raw_blob']) {
      final count =
          (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).first['n']
              as int;
      switch (table) {
        case 'decoded_onehz':
          sourceOneHz = count;
        case 'decoded_rr':
          sourceRr = count;
        case 'raw_blob':
          sourceBlobs = count;
      }
    }
    await db.close();
    await clean(dir);
  }

  Future<Map<String, String>> payloads(Database db) async => {
    for (final row in await db.query(
      'day_result',
      columns: ['day_id', 'payload_json'],
      where: 'algo_version = ?',
      whereArgs: [kAlgoVersion],
      orderBy: 'day_id',
    ))
      row['day_id'] as String: row['payload_json'] as String,
  };

  Future<void> clearDerived(Database db, [String? selected]) async {
    for (final table in [
      'day_result',
      'sleep_session_candidates',
      'wake_day_features',
    ]) {
      await db.delete(
        table,
        where: 'algo_version = ?${selected == null ? '' : ' AND day_id = ?'}',
        whereArgs: [kAlgoVersion, ?selected],
      );
    }
  }

  Future<void> startup(AppState app) async {
    // Public DB calls in _initSteps and _refreshNightlyRhr, in source order.
    await measure('startup.refreshSensors', app.refreshSensors);
    await measure('startup.observedHrCeiling', LocalDb.observedHrCeiling);
    await measure(
      'startup.trailingSeriesValues.rhr28',
      () => LocalDb.trailingSeriesValues('rhr', 28),
    );
    await measure(
      'startup.personalQuietWakingHrr',
      LocalDb.personalQuietWakingHrr,
    );
    await measure(
      'startup.trailingSeriesValues.rhr7',
      () => LocalDb.trailingSeriesValues('rhr', 7),
    );
    await measure('startup.recoverComputeJobs', LocalDb.recoverComputeJobs);
    await measure(
      'startup.computeJobs',
      () => LocalDb.computeJobs(state: 'queued', limit: 50),
    );
    await measure('startup.latestSample', LocalDb.latestSample);
    await measure('startup.rec_ts_hw', () => LocalDb.getCursorInt('rec_ts_hw'));
    await measure(
      'startup.refreshComputeFreshness',
      LocalDb.refreshComputeFreshness,
    );
  }

  Future<void> render(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      final dir = (await tester.runAsync(copy))!;
      phase = 'open';
      trace = true;
      size(dir, 'open $i before');
      await tester.runAsync(
        () => measure('LocalDb.instance', () => verifiedOpen(dir)),
      );
      await tester.runAsync(() async {
        trace = false;
        await verifyCounts(await LocalDb.instance);
        trace = true;
      });
      size(dir, 'open $i after');
      phase = 'startup';
      final app = AppState.forTesting()..user = profileMap;
      app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
      await tester.runAsync(
        () => measure('startup DB sequence', () => startup(app)),
      );
      size(dir, 'startup $i after');
      app.dispose();
      phase = 'Heute';
      final sw = Stopwatch()..start();
      final screenApp = AppState.forTesting()..user = profileMap;
      screenApp.repo = LocalRepositoryImpl(getProfileMap: () => screenApp.user);
      final repo = TimedRepository(screenApp, this);
      // Anchor the UI to the input's latest day at noon. It exercises all
      // today-only futures even when this harness is rerun on a later date.
      final env = G3Env.real(
        repository: repo,
        day: latestDay,
        now: () => DateTime.parse(latestDay).add(const Duration(hours: 12)),
        band: const BandSnapshot(),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: openBandTheme(Brightness.light),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('de'), Locale('en')],
          home: heuteScreens['heute-hell']!(env)!,
        ),
      );
      // Wait for the final readWeekStrip future, then pump its setState.
      // Completion is observed at the repository boundary, not guessed using
      // an arbitrary pumpAndSettle delay. Rendering itself adds no fake time.
      for (var turns = 0; turns < 3000; turns++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
        await tester.pump();
        if (repo.completedWeek >= 3 && repo.dayDone && repo.pending == 0) break;
        if (turns == 2999) throw StateError('Heute futures did not resolve');
      }
      await tester.pump();
      if (tester.takeException() != null ||
          repo.errors != 0 ||
          find.byType(OpenBandHeute).evaluate().length != 1) {
        throw StateError('Heute render failed');
      }
      sw.stop();
      timings
          .putIfAbsent(
            'AppState/repositories to resolved Heute render',
            () => [],
          )
          .add(ms(sw));
      size(dir, 'Heute $i after');
      await tester.runAsync(() async {
        phase = 'startup deferred DB';
        await measure('startup deferred.schemaHealth', LocalDb.schemaHealth);
        await measure(
          'startup deferred.liveSessions query',
          LocalDb.liveSessions,
        );
      });
      size(dir, 'startup deferred $i after');
      await tester.pumpWidget(const SizedBox());
      screenApp.dispose();
      await tester.runAsync(() async {
        await collectPlans(await LocalDb.instance);
        await clean(dir);
      });
    }
  }

  Future<void> derive(String kind, int repeats) async {
    for (var i = 0; i < repeats; i++) {
      final dir = await copy();
      trace = false;
      final db = await verifiedOpen(dir);
      await verifyCounts(db);
      size(dir, '$kind $i before invalidation');
      if (kind != 'post-drain light') {
        await clearDerived(db, kind == 'one day' ? day : null);
      }
      size(dir, '$kind $i before timed engine');
      phase = kind;
      trace = true;
      final engine = DerivationEngine(log: (_) {});
      final done = await measure(
        'derive $kind',
        () => kind == 'one day'
            ? engine.runDays(PersonalProfile.fromMap(profileMap), {
                day,
              }, force: true)
            : engine.run(
                PersonalProfile.fromMap(profileMap),
                heavy: kind == 'full',
                force: kind == 'full',
              ),
      );
      final diag = engine.snapshot();
      if (diag['last_error'] != null ||
          diag['skipped_days'] != 0 ||
          (kind != 'post-drain light' && done == 0)) {
        throw StateError('Derivation did not complete');
      }
      if (kind == 'post-drain light') {
        final app = AppState.forTesting()..user = profileMap;
        app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
        await measure(
          'post-drain rescoreRecentSessions',
          () => app.repo!.rescoreRecentSessions(),
        );
        await measure(
          'post-drain refreshComputeFreshness',
          LocalDb.refreshComputeFreshness,
        );
        app.dispose();
      }
      diagnostics.add(
        '| $kind $i | $done | ${diag['todo_days']} | ${diag['skipped_days']} | '
        '${diag['raw_pages']} | ${diag['raw_rows']} | ${diag['max_day_raw_rows']} | '
        '${diag['concurrency']} | ${diag['last_error'] == null ? 0 : 1} |',
      );
      size(dir, '$kind $i after engine, connection open');
      trace = false;
      final resultCounts = (await db.rawQuery(
        'SELECT COUNT(*) AS n, '
        'SUM(CASE WHEN partial=1 THEN 1 ELSE 0 END) AS p, '
        'SUM(CASE WHEN skipped=1 THEN 1 ELSE 0 END) AS s FROM day_result WHERE algo_version=?',
        [kAlgoVersion],
      )).first;
      persisted.add(
        '| $kind $i | ${resultCounts['n']} | ${resultCounts['p'] ?? 0} | ${resultCounts['s'] ?? 0} |',
      );
      if (kind == 'one day') {
        final result = await db.query(
          'day_result',
          columns: ['partial', 'skipped'],
          where: 'day_id=? AND algo_version=?',
          whereArgs: [day, kAlgoVersion],
        );
        if (result.isEmpty ||
            result.first['partial'] == 1 ||
            result.first['skipped'] == 1) {
          throw StateError(
            'Selected full day has no complete persisted result',
          );
        }
      }
      if (kind == 'full') await compare(await payloads(db), i);
      await collectPlans(db);
      await clean(dir);
    }
  }

  Future<void> compare(Map<String, String> after, int run) async {
    var same = 0, different = 0, missing = 0, added = 0;
    final all = {...originalPayloads.keys, ...after.keys}.toList()..sort();
    for (final d in all) {
      final a = originalPayloads[d], b = after[d];
      final status = a == null
          ? 'added'
          : b == null
          ? 'missing'
          : a == b
          ? 'identical'
          : 'different';
      switch (status) {
        case 'identical':
          same++;
        case 'different':
          different++;
        case 'missing':
          missing++;
        case 'added':
          added++;
      }
      final keys = <String>[];
      if (a != null && b != null && a != b) {
        final x = jsonDecode(a) as Map, y = jsonDecode(b) as Map;
        for (final key in {...x.keys, ...y.keys}) {
          if (jsonEncode(x[key]) != jsonEncode(y[key])) keys.add(key as String);
        }
        keys.sort();
      }
      String hash(String? text) => text == null
          ? 'absent'
          : sha256.convert(utf8.encode(text)).toString();
      comparisons.add(
        '| $run | $d | $status | ${hash(a)} | ${hash(b)} | ${keys.join(', ')} |',
      );
    }
    summaries.add(
      'Full run $run payload comparison counts: identical=$same, different=$different, missing=$missing, added=$added.',
    );
  }

  Future<void> drain() async {
    final dir = await copy();
    final db = await verifiedOpen(dir);
    await verifyCounts(db);
    final blobs = await db.query(
      'raw_blob',
      orderBy: 'last_ts DESC, first_counter DESC',
      limit: 50,
    );
    if (blobs.length != 50) throw StateError('Fewer than 50 replay batches');
    final token = await LocalDb.getCursor('strap_trim');
    var frames = 0;
    size(dir, '50-batch commit before');
    for (final blob in blobs) {
      if (blob['codec'] != 1) throw StateError('Unsupported blob codec');
      final packed = gzip.decode(blob['payload'] as Uint8List);
      final raws = <RawRecord>[];
      final samples = <Sample?>[];
      var p = 0;
      while (p < packed.length) {
        if (p + 2 > packed.length) throw StateError('Truncated frame length');
        final len = packed[p] | (packed[p + 1] << 8);
        if (len == 0 || p + 2 + len > packed.length) {
          throw StateError('Invalid frame length');
        }
        final f = Uint8List.fromList(packed.sublist(p + 2, p + 2 + len));
        final ctr = f.length < 7
            ? 0
            : ByteData.sublistView(f).getUint32(3, Endian.little);
        raws.add(
          RawRecord(
            counter: ctr,
            packetType: f[0],
            hex: f.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
            capturedAt: blob['captured_at'] as int,
          ),
        );
        samples.add(decodeGen5HistoricalSample(f));
        p += len + 2;
      }
      if (raws.length != blob['n']) {
        throw StateError('Blob frame count mismatch');
      }
      frames += raws.length;
      phase = 'commitSyncBatch';
      trace = true;
      await measure(
        'LocalDb.commitSyncBatch (50 recent batches)',
        () => LocalDb.commitSyncBatch(
          raws,
          samples,
          trimToken: token,
          deviceFamily: 'gen5',
          deviceId: blob['device_id'] as String,
        ),
      );
      trace = false;
    }
    size(dir, '50-batch commit after, connection open');
    summaries.add(
      'Replay batches=${blobs.length}, frames=$frames, FULL downgrade count=${LocalDb.syncFullDowngrades}.',
    );
    await collectPlans(db);
    await clean(dir);
  }

  List<MapEntry<String, SqlStat>> top(bool maximum) =>
      (sql.entries.where((e) => e.value.calls > 0).toList()..sort(
            (a, b) => (maximum
                ? b.value.max.compareTo(a.value.max)
                : b.value.total.compareTo(a.value.total)),
          ))
          .take(25)
          .toList();
  Future<void> collectPlans(Database db) async {
    trace = false;
    for (final entry in [
      ...top(false),
      ...top(true),
      ...sql.entries.where((e) => e.value.calls == 0),
    ]) {
      if (plans.containsKey(entry.key)) continue;
      try {
        final rows = await db.rawQuery(
          'EXPLAIN QUERY PLAN ${entry.value.sql}',
          entry.value.args,
        );
        plans[entry.key] = rows.isEmpty
            ? 'No plan rows (DDL/PRAGMA/transaction control).'
            : rows
                  .map((r) => '${r['id']}/${r['parent']}: ${r['detail']}')
                  .join('; ');
      } catch (e) {
        plans[entry.key] =
            'EXPLAIN unavailable: ${e.runtimeType} (no arguments or error text printed).';
      }
    }
  }

  String report() {
    final out = StringBuffer('# OpenBand 5 storage timing benchmark\n\n');
    out.writeln(
      'Flutter 3.41.6; macOS host FFI, widget test, schema ${LocalDb.schemaVersion}, algorithm $kAlgoVersion. '
      'Input copy counts: decoded_onehz=$sourceOneHz, decoded_rr=$sourceRr, raw_blob=$sourceBlobs. '
      'Complete derivation day=$day; Heute day=$latestDay, fixed local noon. Timezone=${DateTime.now().timeZoneName}; profile=$profileSource.',
    );
    out.writeln(
      '\nStopwatch wall-clock milliseconds. Fresh DB copies for each open/UI/derive repeat. '
      'OS page cache is warm after the first run; caches are not flushed. '
      'Copying, invalidation, hash reads and EXPLAIN are outside timed operations. '
      'SQL logging overhead is included. Median averages the middle two samples for even counts; p95 uses nearest rank. Repository counts include nested virtual calls.  Total harness time=${n(ms(total))} ms.',
    );
    out.writeln(
      '\n| Operation | Calls/samples | Min ms | Median ms | p95 ms | All samples ms |\n|---|---:|---:|---:|---:|---|',
    );
    for (final e in timings.entries) {
      out.writeln(
        '| ${cell(e.key)} | ${e.value.length} | ${n(percentile(e.value, 0))} | '
        '${n(median(e.value))} | ${n(percentile(e.value, .95))} | ${e.value.map(n).join(', ')} |',
      );
    }
    out.writeln('\n| Copy step | DB bytes | WAL bytes |\n|---|---:|---:|');
    sizes.forEach(out.writeln);
    out.writeln(
      '\n| Derivation run | Done | Todo | Skipped | Raw pages | Raw rows | Max day raw rows | Concurrency | Error count |\n|---|---:|---:|---:|---:|---:|---:|---:|---:|',
    );
    diagnostics.forEach(out.writeln);
    out.writeln(
      '\n| Persisted algorithm-98 results after run | Rows | Partial | Skipped |\n|---|---:|---:|---:|',
    );
    persisted.forEach(out.writeln);
    out.writeln();
    summaries.forEach(out.writeln);
    out.writeln(
      '\n| Full run | Day | Comparison | Input SHA256 | Re-derived SHA256 | Different top-level keys |\n|---|---|---|---|---|---|',
    );
    comparisons.forEach(out.writeln);
    out.writeln(
      '\n## SQL trace\n\nRecorded SQL operations=$observedStatements; failed SQL events=$sqlFailures. '
      'Single-statement timings include FFI dispatch, queuing and result materialization. '
      'Batch operations have SQL text/counts but only a measured batch duration. '
      'No per-operation batch time is estimated. Rankings below cover independently timed statements; '
      'batch totals follow separately. Literal values are normalized; arguments are never emitted.',
    );
    for (final maximum in [false, true]) {
      out.writeln(
        '\n### Top 25 by ${maximum ? 'single maximum' : 'total'} time\n',
      );
      out.writeln(
        '| SQL | Timed calls | All operations | Total ms | Max ms | EXPLAIN QUERY PLAN |\n|---|---:|---:|---:|---:|---|',
      );
      for (final e in top(maximum)) {
        out.writeln(
          '| `${cell(e.key)}` | ${e.value.calls} | ${e.value.operations} | ${n(e.value.total)} | '
          '${n(e.value.max)} | ${cell(plans[e.key] ?? 'unavailable')} |',
        );
      }
    }
    out.writeln(
      '\n### Batch timings by total time\n\n| SQL operation signatures | Batch calls | Operations | Total ms | Max batch ms |\n|---|---:|---:|---:|---:|',
    );
    final sorted = batches.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    for (final e in sorted.take(25)) {
      out.writeln(
        '| `${cell(e.key)}` | ${e.value.calls} | ${e.value.operations} | ${n(e.value.total)} | ${n(e.value.max)} |',
      );
    }
    out.writeln(
      '\n### Batch SQL operation plans\n\n| SQL | Operations without individual duration | EXPLAIN QUERY PLAN |\n|---|---:|---|',
    );
    for (final e in sql.entries.where((e) => e.value.calls == 0)) {
      out.writeln(
        '| `${cell(e.key)}` | ${e.value.operations} | ${cell(plans[e.key] ?? 'unavailable')} |',
      );
    }
    out.writeln(
      '\n| Trace phase | Timed SQL calls/batches | Summed SQL call ms |\n|---|---:|---:|',
    );
    for (final e in phaseSqlMs.entries) {
      out.writeln('| ${e.key} | ${phaseSqlCalls[e.key]} | ${n(e.value)} |');
    }
    out.writeln('''

## Scope and limits

- These are host timings, not an iPhone launch/Bluetooth measurement. The render endpoint is all Heute repository futures resolved and the production Heute widget pumped; no screenshots or rows are exported. Open, the available startup DB sequence and Heute construction/render are timed separately. Native launch, engine creation and splash animation are excluded. Schema already matches 68, so onUpgrade is not exercised.
- main.dart pre-runApp awaits Firebase, Bluetooth options, native restore/background handlers, headless boot, widgets, notifications, preferences and theme/units/locale. They require device/plugin state and are not represented by this DB copy. AppState pairing/profile/preferences, private alarm initialization, orphan workout resume/finalize, network status, permissions and BLE session are not run. Scheduler DB recovery/snapshot are called without arming its timers. The deferred startup schemaHealth integrity check and live-session query are timed after render; the private workout resume/finalize state machine is not run. Day-result/series reads occur in repository futures; _initSteps does not eagerly load all day results.
- PersonalProfile is recovered from the original derived_profile_signature cursor when available; no personal values are emitted. Actual phone preferences are not supplied, so preferences remain empty and optional features may differ. Re-derivation can differ in time/provenance fields and baseline context. DateTime.now inside production derivation is not injectable without changing lib; fixed dataset/day/ordering/UI clock and Berlin TZ are repeatable, but wall-clock-dependent derivation output is not frozen.
- Full re-derivation invalidates only algorithm-98 day_result/sleep_session_candidates/wake_day_features on a fresh copy, then calls run(heavy:true,force:true), matching the full-history engine path. Metric series/baselines remain as on the phone. The normal post-drain engine pass is run(heavy:false), followed separately by the DB/repository refresh calls where available. No BLE scheduling/debounce/ACK, widget/health export or asynchronous heavy rescan is claimed.
- Replay calls LocalDb.commitSyncBatch, the real ACK-gating DB transaction, with the newest 50 stored batches in deterministic descending data-time order. Inflation and Gen5 mapping are outside commit timing; gzip re-encoding inside commit is included. Existing trim cursor is preserved. Existing raw_blob rows use IGNORE while decoded rows use REPLACE. This measures idempotent replay, not first-insert cost, radio time or ledger/ACK writes outside this function. Null unsupported Gen5 samples use the production DB fallback.
- _PrepareStats is private and contains page/row counts, no phase Stopwatches. Engine snapshots report aggregate counts. Private prepare/compute/persist wall times and individual batch SQL durations cannot be measured through the available API without modifying production code. SQL phase sums may overlap when concurrent derivation queues requests; they are not engine wall time.
- WAL bytes are captured with the connection still open after each step, before cleanup/checkpoint-on-close. Input SHA256s come from an untouched read-only fresh copy of orig.db, never opening orig.db itself. Byte comparisons use payload_json exactly; key comparisons decode JSON but print key names only.
''');
    return out.toString();
  }
}

class TimedRepository extends LocalOpenBandRepository {
  TimedRepository(super.app, this.bench);
  final Bench bench;
  int pending = 0, errors = 0, completedWeek = 0;
  bool dayDone = false;
  Future<T> call<T>(String name, Future<T> Function() action) async {
    pending++;
    try {
      return await bench.measure('Heute.$name', action);
    } catch (_) {
      errors++;
      rethrow;
    } finally {
      pending--;
    }
  }

  @override
  Future<OpenBandDay> readDay(String day) async {
    final result = await call('readDay', () => super.readDay(day));
    dayDone = true;
    return result;
  }

  @override
  Future<G3Baseline> readPersonalRange(G3Metric m, String day) => call(
    'readPersonalRange.${m.name}',
    () => super.readPersonalRange(m, day),
  );
  @override
  Future<SleepGoalSnapshot> readSleepGoal(String day) =>
      call('readSleepGoal', () => super.readSleepGoal(day));
  @override
  Future<G3SleepPlus> readSleepPlus(String day, {DateTime? now}) =>
      call('readSleepPlus', () => super.readSleepPlus(day, now: now));
  @override
  Future<List<G3Activity>> readActivities(String day) =>
      call('readActivities', () => super.readActivities(day));
  @override
  Future<G3CheckIn> readCheckIn(String day) =>
      call('readCheckIn', () => super.readCheckIn(day));
  @override
  Future<DateTime?> readLastBandSampleAt(String day) =>
      call('readLastBandSampleAt', () => super.readLastBandSampleAt(day));
  @override
  Future<G3WeekStrip> readWeekStrip(G3Metric m, String day) async {
    final result = await call(
      'readWeekStrip.${m.name}',
      () => super.readWeekStrip(m, day),
    );
    completedWeek++;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('private-copy storage benchmark', (tester) async {
    final bench = Bench();
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    Object? failure;
    try {
      await runZoned(() async {
        await tester.runAsync(() async {
          SharedPreferences.setMockInitialValues({});
          await initializeDateFormatting('de_DE');
          sqfliteFfiInit();
          // The requested SQL instrumentation API is experimental in sqflite_common.
          // ignore: experimental_member_use
          databaseFactory = SqfliteDatabaseFactoryLogger(
            databaseFactoryFfi,
            options: SqfliteLoggerOptions(
              type: SqfliteDatabaseFactoryLoggerType.all,
              log: bench.log,
            ),
          );
          try {
            await bench.baseline();
          } catch (e) {
            failure = e;
          }
        });
        if (failure != null) throw StateError('Baseline failed');
        await tester.binding.setSurfaceSize(const Size(393, 852));
        await bench.render(tester);
        await tester.runAsync(() async {
          try {
            await bench.derive('one day', 3);
            await bench.derive('full', 3);
            await bench.derive('post-drain light', 3);
            await bench.drain();
          } catch (e) {
            failure = e;
          }
        });
      }, zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}));
    } catch (e) {
      failure = e;
    } finally {
      debugPrint = originalDebugPrint;
      await tester.runAsync(LocalDb.close);
    }
    bench.total.stop();
    final report = bench.report();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final path = '/tmp/ob5-storage/bench-results-$stamp.md';
    File(path).writeAsStringSync(report);
    print(report);
    print('RESULTS_FILE=$path');
    if (failure != null) {
      fail(
        'Benchmark failed: ${failure.runtimeType}; no private error text emitted.',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 45)));
}
