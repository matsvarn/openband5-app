// Private-copy proof. No SQL arguments, row contents, or exception messages
// are emitted. Run through storage_proof.sh to respect the Flutter quiet gate.
// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/derive_prepare.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const sourcePath = '/tmp/ob5-storage/orig.db';
const compactColumns = {
  'ax',
  'ay',
  'az',
  'temp_ch2_c',
  'temp_ch3_c',
  'dyn_accel_g',
};
const resultColumns = [
  'payload_json',
  'window_json',
  'rhr',
  'rmssd',
  'readiness',
  'finalized',
  'skipped',
  'partial',
];
String hash(String text) => sha256.convert(utf8.encode(text)).toString();
String q(String name) => '"${name.replaceAll('"', '""')}"';
String fixed(num value) => value.toStringAsFixed(3);
int bytes(String path) => File(path).existsSync() ? File(path).lengthSync() : 0;

class Timing {
  int calls = 0, affected = 0;
  double total = 0, maximum = 0;
  Future<int> call(Future<int> Function() fn) async {
    final watch = Stopwatch()..start();
    final n = await fn();
    final ms = watch.elapsedMicroseconds / 1000;
    calls++;
    affected += n;
    total += ms;
    if (ms > maximum) maximum = ms;
    return n;
  }
}

class Proof {
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
  final total = Stopwatch()..start();
  final lines = <String>['# OpenBand 5 storage proof', ''];
  final failures = <String>[];
  final timings = <String, Timing>{};
  late final root = Directory('/tmp/ob5-storage/proof-$stamp');
  late final primary = Directory('${root.path}/P');
  late final originalCopy = '${root.path}/original-readonly.db';
  String _stage = 'setup';
  String get stage => _stage;
  set stage(String value) {
    _stage = value;
    if (root.existsSync()) {
      File(
        '${root.path}/progress.md',
      ).writeAsStringSync('${lines.join('\n')}\n\n- active_stage: $value\n');
    }
  }

  Map<String, dynamic>? profile;
  final baselineInputs = <String, String>{};

  void check(String key, int mismatches) {
    lines.add('- $key: $mismatches');
    if (mismatches != 0) failures.add(key);
  }

  Future<int> count(Database db, String sql) async =>
      ((await db.rawQuery(sql)).first.values.first as num?)?.toInt() ?? 0;

  Future<void> chmod(String path, String mode) async {
    if ((await Process.run('chmod', [mode, path])).exitCode != 0) {
      throw StateError('Copy permissions');
    }
  }

  Future<Directory> copy(String name) async {
    await LocalDb.close();
    final dir = Directory('${root.path}/$name')..createSync(recursive: true);
    await chmod(dir.path, '700');
    File(sourcePath).copySync('${dir.path}/openstrap.db');
    await chmod('${dir.path}/openstrap.db', '600');
    return dir;
  }

  Future<Database> open(Directory dir) async {
    await databaseFactoryFfi.setDatabasesPath('file:${dir.path}');
    await databaseFactory.setDatabasesPath('file:${dir.path}');
    LocalDb.dbName = 'openstrap.db';
    final db = await LocalDb.instance;
    if (db.path != 'file:${dir.path}/openstrap.db' ||
        LocalDb.lastRebuild != null) {
      throw StateError('Copy production open');
    }
    return db;
  }

  Future<void> attach(Database db, String path, String alias) async {
    final uri = Uri.file(path).replace(query: 'mode=ro&immutable=1').toString();
    await db.execute('ATTACH DATABASE ? AS ${q(alias)}', [uri]);
  }

  Future<void> close(Database db) async {
    final row = (await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)')).first;
    check('checkpoint_busy', (row['busy'] as num?)?.toInt() ?? -1);
    await LocalDb.close();
  }

  Future<List<String>> columns(
    Database db,
    String table, {
    String schema = 'o',
  }) async => (await db.rawQuery(
    'PRAGMA ${q(schema)}.table_info(${q(table)})',
  )).map((r) => r['name'] as String).toList();

  Future<Map<String, dynamic>> cursor(String key) async {
    final row = await LocalDb.computeFreshness(key);
    return row == null
        ? <String, dynamic>{}
        : (jsonDecode(row['payload_json'] as String) as Map)
              .cast<String, dynamic>();
  }

  Future<void> compact(String label) async {
    final timing = timings.putIfAbsent(label, Timing.new);
    for (var i = 0; i < 10000; i++) {
      final changed = await timing.call(() => LocalDb.compactLegacyOneHz());
      if (changed == 0 &&
          (await cursor(LocalDb.kOneHzCompactCursorKey))['done'] == true) {
        return;
      }
    }
    throw StateError('Compaction did not complete');
  }

  Future<void> sizes(Database db, Directory dir, String label) async {
    lines.add('');
    lines.add(
      '| Snapshot | DB bytes | WAL bytes | Freelist pages | Page bytes |',
    );
    lines.add('|---|---:|---:|---:|---:|');
    lines.add(
      '| $label | ${bytes('${dir.path}/openstrap.db')} | '
      '${bytes('${dir.path}/openstrap.db-wal')} | '
      '${await count(db, 'PRAGMA freelist_count')} | '
      '${await count(db, 'PRAGMA page_size')} |',
    );
    final stats = await db.rawQuery(
      'SELECT s.name, SUM(s.pgsize) AS bytes '
      'FROM dbstat s JOIN sqlite_master m ON s.name=m.name '
      "WHERE m.type='table' GROUP BY s.name ORDER BY bytes DESC LIMIT 15",
    );
    lines.add('');
    lines.add('| $label dbstat table | Bytes |');
    lines.add('|---|---:|');
    for (final row in stats) {
      lines.add('| ${row['name']} | ${row['bytes']} |');
    }
  }

  String joinKeys(List<String> keys) =>
      keys.map((k) => 'p.${q(k)} IS o.${q(k)}').join(' AND ');

  Future<void> keys(Database db, String table, List<String> keys) async {
    check(
      '$table.missing',
      await count(
        db,
        'SELECT COUNT(*) FROM o.${q(table)} o '
        'WHERE NOT EXISTS (SELECT 1 FROM main.${q(table)} p WHERE ${joinKeys(keys)})',
      ),
    );
    check(
      '$table.extra',
      await count(
        db,
        'SELECT COUNT(*) FROM main.${q(table)} p '
        'WHERE NOT EXISTS (SELECT 1 FROM o.${q(table)} o WHERE ${joinKeys(keys)})',
      ),
    );
  }

  Future<void> values(
    Database db,
    String table,
    List<String> keys, {
    bool decode = false,
    String filter = '',
  }) async {
    final cs = await columns(db, table);
    final selection = cs
        .where((c) => !decode || !compactColumns.contains(c))
        .map(q)
        .join(', ');
    final projection = decode
        ? '$selection, ${LocalDb.decodedOneHzProjection}'
        : selection;
    final sums = cs
        .map(
          (c) =>
              'SUM(CASE WHEN p.${q(c)} IS o.${q(c)} THEN 0 ELSE 1 END) AS ${q(c)}',
        )
        .join(', ');
    final row = (await db.rawQuery(
      'SELECT $sums FROM '
      '(SELECT $projection FROM main.${q(table)}) p '
      'JOIN o.${q(table)} o ON ${joinKeys(keys)} $filter',
    )).first;
    lines.add('');
    lines.add('| $table column | NULL-safe IS mismatches |');
    lines.add('|---|---:|');
    for (final c in cs) {
      final n = (row[c] as num?)?.toInt() ?? 0;
      lines.add('| $c | $n |');
      if (n != 0) failures.add('$table.$c');
    }
  }

  Future<void> retention(Database db, String table) async {
    final rows = await db.rawQuery(
      'SELECT day_id, algo_version${table == 'day_result' ? ',skipped,partial' : ''} FROM o.${q(table)} ORDER BY day_id, algo_version DESC',
    );
    final present = (await db.rawQuery(
      'SELECT day_id,algo_version FROM main.${q(table)}',
    )).map((r) => '${r['day_id']}/${r['algo_version']}').toSet();
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row['day_id'] as String, () => []).add(row);
    }
    var unauthorized = 0, currentMissing = 0, excess = 0;
    final byVersion = <int, int>{};
    lines.add('');
    lines.add('| $table missing key | Version | Policy permits |');
    lines.add('|---|---:|---|');
    for (final entry in grouped.entries) {
      final owned = entry.value
          .where((r) => (r['algo_version'] as int) <= kAlgoVersion)
          .toList();
      final kept = owned.take(2).map((r) => r['algo_version']).toSet();
      if (table == 'day_result') {
        final complete = owned.where(
          (r) => r['skipped'] == 0 && r['partial'] == 0,
        );
        if (complete.isNotEmpty) kept.add(complete.first['algo_version']);
      }
      for (final row in entry.value) {
        final version = row['algo_version'] as int;
        final keep = version > kAlgoVersion || kept.contains(version);
        final found = present.contains('${entry.key}/$version');
        if (!found) {
          if (keep) unauthorized++;
          if (version == kAlgoVersion) currentMissing++;
          byVersion.update(version, (n) => n + 1, ifAbsent: () => 1);
          lines.add('| ${entry.key} | $version | ${!keep} |');
        } else if (!keep) {
          excess++;
        }
      }
    }
    check('$table.unauthorized_missing', unauthorized);
    check('$table.algo98_missing', currentMissing);
    check('$table.excess_versions', excess);
    for (final v in byVersion.keys.toList()..sort()) {
      lines.add('- $table.pruned_version_$v: ${byVersion[v]}');
    }
    check(
      '$table.extra_keys',
      await count(
        db,
        'SELECT COUNT(*) FROM main.${q(table)} p '
        'WHERE NOT EXISTS (SELECT 1 FROM o.${q(table)} o '
        'WHERE p.day_id=o.day_id AND p.algo_version=o.algo_version)',
      ),
    );
  }

  Future<void> candidateRoundtrip(Database db) async {
    var mismatches = 0, checked = 0, legacyBytes = 0, compactBytes = 0;
    for (final row in await db.rawQuery(
      'SELECT payload_json FROM o.sleep_session_candidates WHERE algo_version=98',
    )) {
      final original = (jsonDecode(row['payload_json'] as String) as Map)
          .cast<String, dynamic>();
      final candidate = SleepSessionCandidate.fromJson(original);
      final encoded = candidate.toJson();
      final decoded = SleepSessionCandidate.fromJson(encoded);
      checked++;
      if (jsonEncode(candidate.hypnoStages) !=
              jsonEncode(original['hypno_stages']) ||
          jsonEncode(decoded.toJson()) != jsonEncode(encoded)) {
        mismatches++;
      }
      legacyBytes += utf8.encode(jsonEncode(original['hypno_stages'])).length;
      compactBytes += utf8.encode(jsonEncode(encoded['hypno_stages'])).length;
    }
    check('legacy_candidate_RLE_roundtrip_mismatches', mismatches);
    lines.add('- candidate_roundtrip_rows: $checked');
    lines.add('- candidate_hypno_legacy_bytes: $legacyBytes');
    lines.add('- candidate_hypno_RLE_bytes: $compactBytes');
  }

  Future<Map<String, Map<String, Object?>>> results(Database db) async => {
    for (final row in await db.query(
      'day_result',
      where: 'algo_version=?',
      whereArgs: [kAlgoVersion],
      orderBy: 'day_id',
    ))
      row['day_id'] as String: row,
  };

  Map<String, String> baseline(String path) {
    final text = File(path).readAsStringSync();
    if (!text.contains('schema 68, algorithm 98')) {
      throw StateError('Baseline metadata');
    }
    final runs = <int, Map<String, String>>{};
    var table = false;
    for (final line in const LineSplitter().convert(text)) {
      if (line.startsWith(
        '| Full run | Day | Comparison | Input SHA256 | Re-derived SHA256 |',
      )) {
        table = true;
        continue;
      }
      if (!table || !line.startsWith('|')) continue;
      final cells = line.split('|').map((c) => c.trim()).toList();
      if (cells.length < 7) continue;
      final run = int.tryParse(cells[1]);
      if (run == null) continue;
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(cells[5])) {
        throw StateError('Baseline hash');
      }
      runs.putIfAbsent(run, () => {})[cells[2]] = cells[5];
      if (run == 0) baselineInputs[cells[2]] = cells[4];
    }
    final zero = runs[0];
    if (zero == null || zero.isEmpty || runs.length != 3) {
      throw StateError('Baseline run 0');
    }
    check(
      'old_baseline_nondeterministic_days',
      runs.values.fold<int>(
        0,
        (n, run) =>
            n +
            {...zero.keys, ...run.keys}.where((d) => zero[d] != run[d]).length,
      ),
    );
    lines.add('- old_baseline_sha256: ${hash(text)}');
    return zero;
  }

  Future<void> derive(Database db, String label) async {
    for (final table in [
      'day_result',
      'sleep_session_candidates',
      'wake_day_features',
    ]) {
      await db.delete(
        table,
        where: 'algo_version = ?',
        whereArgs: [kAlgoVersion],
      );
    }
    final engine = DerivationEngine(log: (_) {});
    final sw = Stopwatch()..start();
    final done = await engine.run(
      PersonalProfile.fromMap(profile),
      heavy: true,
      force: true,
    );
    final diag = engine.snapshot();
    lines.add('- $label.derive_ms: ${fixed(sw.elapsedMicroseconds / 1000)}');
    lines.add('- $label.derived_days: $done');
    check('$label.engine_errors', diag['last_error'] == null ? 0 : 1);
    check('$label.skipped_days', (diag['skipped_days'] as num?)?.toInt() ?? -1);
    if (done == 0) failures.add('$label.no_derived_days');
  }

  List<String> differingKeys(String a, String b) {
    final x = jsonDecode(a) as Map, y = jsonDecode(b) as Map;
    final keys = <String>[];
    for (final key in {...x.keys, ...y.keys}) {
      if (jsonEncode(x[key]) == jsonEncode(y[key])) continue;
      keys.add(key.toString());
      if (x[key] is Map && y[key] is Map) {
        final left = x[key] as Map, right = y[key] as Map;
        for (final child in {...left.keys, ...right.keys}) {
          if (jsonEncode(left[child]) != jsonEncode(right[child])) {
            keys.add('$key.$child');
          }
        }
      }
    }
    return keys..sort();
  }

  void diagnoseSchemaMetadata(
    Map<String, Map<String, Object?>> rows,
    Map<String, String> oldHashes,
  ) {
    var otherDifferences = 0;
    lines.add('');
    lines.add(
      '| Old-code difference | Day key | Differing JSON keys | Reconstructed old SHA256 identical |',
    );
    lines.add('|---|---|---|---|');
    for (final d in {...rows.keys, ...oldHashes.keys}.toList()..sort()) {
      final text = rows[d]?['payload_json'] as String?;
      if (text == null) {
        otherDifferences++;
        continue;
      }
      final decoded = jsonDecode(text) as Map;
      const currentField = '"schema_version":69';
      final singleBuildField =
          (decoded['build'] as Map?)?['schema_version'] == 69 &&
          currentField.allMatches(text).length == 1;
      final reconstructed = text.replaceFirst(
        currentField,
        '"schema_version":68',
      );
      final identical = singleBuildField && hash(reconstructed) == oldHashes[d];
      if (!identical) otherDifferences++;
      lines.add(
        '| old run-0 vs P | $d | '
        '${identical ? differingKeys(reconstructed, text).join(', ') : 'unresolved_without_old_JSON'} | $identical |',
      );
    }
    check('old_payload_differences_beyond_schema_metadata', otherDifferences);
    if (otherDifferences == 0) {
      lines.add(
        '- All old hashes are reconstructed by changing only build.schema_version. '
        'The raw byte-identity failure is schema provenance, not a decoded-value, candidate, metric or wall-clock change. '
        'Strict raw-hash assertions remain failed.',
      );
    }
  }

  Future<void> run() async {
    root.createSync(recursive: true);
    await chmod(root.path, '700');
    final baselinePath = Platform.environment['OB5_BASELINE_RESULTS'];
    if (baselinePath == null) throw StateError('OB5_BASELINE_RESULTS required');
    lines.add(
      '- timing_contention: ${Platform.environment['OB5_PROOF_TIMING_CONTENTION'] ?? 'unknown'}; other worktrees may launch later.',
    );
    final oldHashes = baseline(baselinePath);
    final sourceHash = sha256
        .convert(await File(sourcePath).readAsBytes())
        .toString();
    lines.add('- source_sha256: $sourceHash');
    lines.add('- baseline_file: $baselinePath');
    final revision = await Process.run('git', ['rev-parse', 'HEAD']);
    lines.add('- implementation_commit: ${revision.stdout.toString().trim()}');
    File(sourcePath).copySync(originalCopy);
    await chmod(originalCopy, '444');

    stage = 'A migration';
    await copy('P');
    final sw = Stopwatch()..start();
    var db = await open(primary);
    lines.add('- production_open_ms: ${fixed(sw.elapsedMicroseconds / 1000)}');
    lines.add('- user_version: ${await db.getVersion()}');
    lines.add(
      '- FFI URI open enables immutable read-only reference attachments; migration still runs through LocalDb.',
    );
    check('schema69_mismatch', await db.getVersion() == 69 ? 0 : 1);
    await attach(db, originalCopy, 'o');
    check(
      'source_schema68_mismatch',
      await count(db, 'PRAGMA o.user_version') == 68 ? 0 : 1,
    );
    for (final table in ['decoded_onehz', 'decoded_rr', 'raw_blob']) {
      lines.add(
        '- source_$table.rows: ${await count(db, 'SELECT COUNT(*) FROM o.$table')}',
      );
    }
    final signature = await db.query(
      'sync_cursor',
      columns: ['value'],
      where: 'name=?',
      whereArgs: ['derived_profile_signature'],
    );
    if (signature.isEmpty) throw StateError('Profile signature absent');
    profile = (jsonDecode(signature.first['value'] as String) as Map)
        .cast<String, dynamic>();
    lines.add(
      '- profile_signature_sha256: ${hash(signature.first['value'] as String)}',
    );
    await db.execute('DETACH DATABASE o');
    await sizes(db, primary, 'after migration / before B');

    stage = 'B housekeeping';
    await compact('compactLegacyOneHz');
    var zeros = 0;
    final samples = timings.putIfAbsent('pruneDuplicateSamples', Timing.new);
    for (var i = 0; i < 10000; i++) {
      final n = await samples.call(() => LocalDb.pruneDuplicateSamples());
      zeros = n == 0 ? zeros + 1 : 0;
      if (zeros >= 2 ||
          (await cursor(LocalDb.kSamplePruneCursorKey))['cursor'] == 0) {
        break;
      }
      if (i == 9999) throw StateError('Sample prune did not complete');
    }
    await timings
        .putIfAbsent('pruneSupersededIntermediates', Timing.new)
        .call(() => LocalDb.pruneSupersededIntermediates());
    final days = timings.putIfAbsent('pruneSupersededDayResults', Timing.new);
    for (var i = 0; i < 10000; i++) {
      if (await days.call(() => LocalDb.pruneSupersededDayResults()) == 0) {
        break;
      }
      if (i == 9999) throw StateError('Day prune did not complete');
    }
    await sizes(db, primary, 'after deletes / before vacuum');
    final free = await LocalDb.freelistBytes();
    final vacuum = Timing();
    final reclaimed = await vacuum.call(() => LocalDb.vacuumIfBloated());
    timings['vacuumIfBloated (affected unit: free bytes)'] = vacuum;
    check('vacuum_return_vs_freelist_bytes', reclaimed == free ? 0 : 1);
    check(
      'vacuum_request_remaining',
      await LocalDb.computeFreshness(LocalDb.kOneHzVacuumKey) == null ? 0 : 1,
    );
    check(
      'vacuum_freelist_remaining',
      await count(db, 'PRAGMA freelist_count'),
    );
    await sizes(db, primary, 'after B');
    final encoded = await count(
      db,
      'SELECT COUNT(*) FROM decoded_onehz WHERE onehz_enc=1',
    );
    lines.add('- onehz_enc_1: $encoded');
    lines.add(
      '- onehz_enc_NULL: ${await count(db, 'SELECT COUNT(*) FROM decoded_onehz WHERE onehz_enc IS NULL')}',
    );
    check(
      'onehz_enc_unknown',
      await count(
        db,
        'SELECT COUNT(*) FROM decoded_onehz WHERE onehz_enc IS NOT NULL AND onehz_enc != 1',
      ),
    );
    await close(db);

    stage = 'B interruption';
    final interrupted = await copy('interrupted');
    db = await open(interrupted);
    final partial = Timing();
    for (var i = 0; i < 3; i++) {
      await partial.call(() => LocalDb.compactLegacyOneHz());
    }
    timings['interruption initial compact passes'] = partial;
    check(
      'interruption_was_already_done',
      (await cursor(LocalDb.kOneHzCompactCursorKey))['done'] == true ? 1 : 0,
    );
    await LocalDb.close();
    db = await open(interrupted);
    await compact('interruption resumed compact');
    check(
      'interruption_encoded_count_mismatch',
      await count(db, 'SELECT COUNT(*) FROM decoded_onehz WHERE onehz_enc=1') ==
              encoded
          ? 0
          : 1,
    );
    await attach(db, '${primary.path}/openstrap.db', 'o');
    await keys(db, 'decoded_onehz', ['device_id', 'ts_ms']);
    // Both copies are encoded. Decode each through exactly the production SQL.
    final cs = (await columns(
      db,
      'decoded_onehz',
    )).where((c) => c != 'onehz_enc').toList();
    final unchanged = cs
        .where((c) => !compactColumns.contains(c))
        .map(q)
        .join(', ');
    final proj = '$unchanged, ${LocalDb.decodedOneHzProjection}';
    check(
      'interruption_decoded_mismatches',
      await count(
        db,
        'SELECT COUNT(*) FROM (SELECT $proj FROM main.decoded_onehz) p '
        'JOIN (SELECT $proj FROM o.decoded_onehz) o ON p.device_id=o.device_id AND p.ts_ms=o.ts_ms '
        'WHERE NOT (${cs.map((c) => 'p.${q(c)} IS o.${q(c)}').join(' AND ')})',
      ),
    );
    await db.execute('DETACH DATABASE o');
    await close(db);
    lines.add(
      '- interruption_mode: clean close between three default-budget calls; no kill/transaction injection seam used.',
    );

    stage = 'C integrity';
    db = await open(primary);
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    check(
      'integrity_check_errors',
      integrity.length == 1 && integrity.first.values.single == 'ok' ? 0 : 1,
    );
    await attach(db, originalCopy, 'o');

    stage = 'D retention';
    await keys(db, 'decoded_onehz', ['device_id', 'ts_ms']);
    await keys(db, 'decoded_rr', ['device_id', 'ts_ms', 'beat_index']);
    await keys(db, 'raw_blob', [
      'device_id',
      'first_counter',
      'last_counter',
      'first_ts',
      'n',
    ]);
    await values(db, 'raw_blob', [
      'device_id',
      'first_counter',
      'last_counter',
      'first_ts',
      'n',
    ]);
    for (final table in [
      'day_result',
      'sleep_session_candidates',
      'wake_day_features',
    ]) {
      await retention(db, table);
    }
    await values(db, 'day_result', [
      'day_id',
      'algo_version',
    ], filter: 'WHERE o.algo_version=98');
    final deletedSamples =
        'NOT EXISTS (SELECT 1 FROM main.samples p WHERE p.device_id=s.device_id AND p.ts_ms=s.ts_ms)';
    final twin =
        'EXISTS (SELECT 1 FROM main.decoded_onehz d WHERE d.device_id=s.device_id '
        'AND d.ts_ms=s.ts_ms AND d.rec_ts=s.ts AND d.source IS NULL)';
    lines.add(
      '- samples_deleted: ${await count(db, 'SELECT COUNT(*) FROM o.samples s WHERE $deletedSamples')}',
    );
    check(
      'samples_deleted_without_primary_decoded_twin',
      await count(
        db,
        'SELECT COUNT(*) FROM o.samples s WHERE $deletedSamples AND NOT $twin',
      ),
    );
    lines.add(
      '- samples_remaining: ${await count(db, 'SELECT COUNT(*) FROM samples')}',
    );
    check(
      'samples_extra',
      await count(
        db,
        'SELECT COUNT(*) FROM main.samples p '
        'WHERE NOT EXISTS (SELECT 1 FROM o.samples o WHERE p.device_id=o.device_id AND p.ts_ms=o.ts_ms)',
      ),
    );
    await values(db, 'samples', ['device_id', 'ts_ms']);

    stage = 'E value identity';
    await values(db, 'decoded_onehz', ['device_id', 'ts_ms'], decode: true);
    await values(db, 'decoded_rr', ['device_id', 'ts_ms', 'beat_index']);
    await candidateRoundtrip(db);
    final originalResults = await resultsFromOriginal(db);
    check(
      'baseline_input_payload_hash_mismatches',
      {...originalResults.keys, ...baselineInputs.keys}.where((d) {
        final payload = originalResults[d]?['payload_json'] as String?;
        return payload == null || hash(payload) != baselineInputs[d];
      }).length,
    );
    await db.execute('DETACH DATABASE o');

    stage = 'F compacted derivation';
    await derive(db, 'P');
    final after = await results(db);
    lines.add('');
    lines.add('| Day key | Old run-0 vs P | Old SHA256 | P SHA256 |');
    lines.add('|---|---|---|---|');
    for (final d in {...oldHashes.keys, ...after.keys}.toList()..sort()) {
      final next = after[d]?['payload_json'] as String?;
      final h = next == null ? 'absent' : hash(next);
      final equal = oldHashes[d] == h;
      lines.add(
        '| $d | ${equal ? 'identical' : 'different'} | ${oldHashes[d] ?? 'absent'} | $h |',
      );
    }
    diagnoseSchemaMetadata(after, oldHashes);
    await sizes(db, primary, 'after full re-derivation');
    await close(db);

    stage = 'F unoptimized control derivation';
    final control = await copy('unoptimized-control');
    db = await open(control);
    check(
      'control_prederive_encoded_rows',
      await count(db, 'SELECT COUNT(*) FROM decoded_onehz WHERE onehz_enc=1'),
    );
    await derive(db, 'control');
    final controlResults = await results(db);
    final mismatch = {for (final c in resultColumns) c: 0};
    var controlOldMismatches = 0;
    lines.add('');
    lines.add(
      '| Difference comparison | Day key | Top-level and second-level JSON keys only |',
    );
    lines.add('|---|---|---|');
    for (final d in {
      ...after.keys,
      ...controlResults.keys,
      ...oldHashes.keys,
    }.toList()..sort()) {
      final p = after[d], c = controlResults[d];
      final payload = c?['payload_json'] as String?;
      if (payload == null || hash(payload) != oldHashes[d]) {
        controlOldMismatches++;
      }
      for (final key in resultColumns) {
        if (p == null || c == null || p[key] != c[key]) {
          mismatch[key] = mismatch[key]! + 1;
          if (key.endsWith('_json') && p?[key] is String && c?[key] is String) {
            lines.add(
              '| P vs unoptimized control $key | $d | '
              '${differingKeys(p![key] as String, c![key] as String).join(', ')} |',
            );
          }
        }
      }
    }
    // Raw hashes differ from the old code by the recorded schema number alone;
    // `old_payload_differences_beyond_schema_metadata` is the gating check.
    lines.add(
      '- unoptimized_control_vs_old_payload_raw_hash_differences: '
      '$controlOldMismatches (informational)',
    );
    for (final entry in mismatch.entries) {
      check('P_vs_unoptimized_control.${entry.key}', entry.value);
    }
    lines.add(
      '- Direct old-code window_json/scalar comparison is unavailable: the baseline markdown retains payload hashes only. Control comparisons above run the new code on an unoptimized fresh copy.',
    );
    await close(db);

    stage = 'G final export';
    db = await open(primary);
    final finalIntegrity = await db.rawQuery('PRAGMA integrity_check');
    check(
      'final_integrity_check_errors',
      finalIntegrity.length == 1 && finalIntegrity.first.values.single == 'ok'
          ? 0
          : 1,
    );
    await close(db);
    check('P_closed_WAL_bytes', bytes('${primary.path}/openstrap.db-wal'));
    File(
      '${primary.path}/openstrap.db',
    ).copySync('/tmp/ob5-storage/proof-final.db');
    final finalHash = sha256
        .convert(await File('${primary.path}/openstrap.db').readAsBytes())
        .toString();
    check(
      'final_copy_hash_mismatch',
      finalHash ==
              sha256
                  .convert(
                    await File('/tmp/ob5-storage/proof-final.db').readAsBytes(),
                  )
                  .toString()
          ? 0
          : 1,
    );
    check(
      'source_hash_changed',
      sourceHash ==
              sha256.convert(await File(sourcePath).readAsBytes()).toString()
          ? 0
          : 1,
    );
    lines.add('- final_db_sha256: $finalHash');
    lines.add('- P: ${primary.path}/openstrap.db');
    lines.add('- export: /tmp/ob5-storage/proof-final.db');
    lines.add('- final_db_bytes: ${bytes('/tmp/ob5-storage/proof-final.db')}');
  }

  Future<Map<String, Map<String, Object?>>> resultsFromOriginal(
    Database db,
  ) async => {
    for (final row in await db.rawQuery(
      'SELECT * FROM o.day_result WHERE algo_version=98 ORDER BY day_id',
    ))
      row['day_id'] as String: row,
  };

  String report() {
    total.stop();
    lines.add('');
    lines.add(
      '| Production operation | Calls | Total ms | Max single call ms | Rows affected, except vacuum bytes |',
    );
    lines.add('|---|---:|---:|---:|---:|');
    for (final entry in timings.entries) {
      final t = entry.value;
      lines.add(
        '| ${entry.key} | ${t.calls} | ${fixed(t.total)} | ${fixed(t.maximum)} | ${t.affected} |',
      );
    }
    lines.add('');
    lines.add('- total_harness_ms: ${fixed(total.elapsedMicroseconds / 1000)}');
    lines.add('- failed_checks: ${failures.length}');
    if (failures.isNotEmpty) {
      lines.add('- failed_check_keys: ${failures.join(', ')}');
    }
    lines.add(
      '- Host FFI proof only; iPhone runtime, physical Bluetooth and physiological validity were not exercised.',
    );
    return '${lines.join('\n')}\n';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'private real-database storage proof',
    (tester) async {
      final proof = Proof();
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      Object? error;
      try {
        await runZoned(() async {
          await tester.runAsync(() async {
            try {
              SharedPreferences.setMockInitialValues({});
              await initializeDateFormatting('de_DE');
              sqfliteFfiInit();
              databaseFactory = databaseFactoryFfi;
              await proof.run();
            } catch (e) {
              error = e;
            } finally {
              await LocalDb.close();
            }
          });
        }, zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}));
      } finally {
        debugPrint = originalDebugPrint;
      }
      if (error != null) {
        proof.lines.add('- stopped_stage: ${proof.stage}');
        final message = error.toString().toLowerCase();
        for (final category in [
          'unable to open',
          'no such table',
          'readonly',
          'syntax error',
          'not authorized',
          'no such column',
          'locked',
          'out of memory',
        ]) {
          if (message.contains(category)) {
            proof.lines.add('- error_category: $category');
          }
        }
        proof.lines.add(
          '- exception_type: ${error.runtimeType}; private exception text suppressed.',
        );
        proof.failures.add('execution_incomplete');
      }
      final report = proof.report();
      final path = '/tmp/ob5-storage/proof-results-${proof.stamp}.md';
      File(path).writeAsStringSync(report);
      print(report);
      print('RESULTS_FILE=$path');
      expect(proof.failures, isEmpty, reason: 'See aggregate proof report');
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}
