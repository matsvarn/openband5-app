import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Execution-clock columns are ignored. Measurement timestamps, dates,
// analytics revisions, versions, ordering, nulls and numerical outputs stay exact.
const ignoredClockColumns = <String, Set<String>>{
  'day_result': {'computed_at'},
  'sleep_session_candidates': {'computed_at'},
  'wake_day_features': {'computed_at'},
  'baselines': {'updated_at'},
  'compute_freshness': {'updated_at'},
  'sync_cursor': {'updated_at'},
  'workout_suggestions': {'created_at'},
  'notifications': {'created_at'},
  'notif_fired': {'fired_at'},
};

// LocalDb.bumpCrossDaySourceRevision increments on every putDayResult. Its
// documentation calls this a local publication fence for orchestration
// eligibility, not analytics output. Exclude only these three fence values.
const ignoredPayloadFields = <String, Map<String, Set<String>>>{
  'baselines': {
    'crossday': {'built_at_epoch', 'input_read_started_at_ms', 'source_rev'},
    'crossday_input': {'input_read_started_at_ms', 'source_rev'},
  },
  'compute_freshness': {
    'crossday_source_rev': {'v'},
  },
};

String normalizePayload(String table, String key, String text) =>
    maskRootFields(text, ignoredPayloadFields[table]?[key] ?? <String>{});

// Preserve JSON bytes, including key order, spacing and number formatting.
// Mask ONLY the numeric literal of an explicitly allowed ROOT clock or fence field.
String maskRootFields(String text, Set<String> fields) {
  final matches = RegExp(r'"([^"\\]*)"\s*:\s*(-?\d+)').allMatches(text);
  final replacements = <(int, int)>[];
  for (final m in matches) {
    if (!fields.contains(m.group(1))) continue;
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (var i = 0; i < m.start; i++) {
      final c = text[i];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          quoted = false;
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == '{' || c == '[') {
        depth++;
      } else if (c == '}' || c == ']') {
        depth--;
      }
    }
    if (depth == 1 && !quoted) {
      replacements.add((m.end - m.group(2)!.length, m.end));
    }
  }
  for (final (start, end) in replacements.reversed) {
    text = text.replaceRange(start, end, '0');
  }
  return text;
}

String digest(String text) => sha256.convert(utf8.encode(text)).toString();
String _quote(String text) => '"${text.replaceAll('"', '""')}"';

class PersistedTable {
  const PersistedTable(this.rows, this.fingerprint, this.records);
  final int rows;
  final String fingerprint;
  final Map<String, Map<String, Object?>> records;
}

class PersistedSnapshot {
  const PersistedSnapshot(this.tables);
  final Map<String, PersistedTable> tables;

  static Future<PersistedSnapshot> capture(Database db) async {
    // Capture EVERY application table, so housekeeping and deferred writes
    // cannot escape the comparison. Large source ledgers keep hashes only.
    const ledgers = {
      'decoded_onehz',
      'decoded_rr',
      'samples',
      'raw_records',
      'archive_records',
      'raw_archive',
      'raw_blob',
      'observation',
      'external_hr',
    };
    final tables = <String, PersistedTable>{};
    final names = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    await db.transaction((txn) async {
      for (final entry in names) {
        final name = entry['name'] as String;
        final schema = await txn.rawQuery('PRAGMA table_info(${_quote(name)})');
        final pk = schema.where((c) => (c['pk'] as int) > 0).toList()
          ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
        final records = <String, Map<String, Object?>>{};
        var cursor = 0;
        var count = 0;
        var sum = BigInt.zero;
        final modulus = BigInt.one << 256;
        while (true) {
          final page = await txn.rawQuery(
            'SELECT rowid AS __snapshot_rowid, * FROM ${_quote(name)} '
            'WHERE rowid > ? ORDER BY rowid LIMIT 2000',
            [cursor],
          );
          if (page.isEmpty) break;
          for (final raw in page) {
            cursor = raw['__snapshot_rowid'] as int;
            final key = pk.isEmpty
                ? cursor.toString()
                : jsonEncode([for (final column in pk) raw[column['name']]]);
            final row = Map<String, Object?>.from(raw)
              ..remove('__snapshot_rowid');
            for (final column in ignoredClockColumns[name] ?? <String>{}) {
              row.remove(column);
            }
            if (row['payload_json'] is String) {
              row['payload_json'] = normalizePayload(
                name,
                row['key']?.toString() ?? '',
                row['payload_json'] as String,
              );
            }
            final hash = digest(jsonEncode(row));
            sum = (sum + BigInt.parse(hash, radix: 16)) % modulus;
            if (!ledgers.contains(name)) records[key] = row;
            count++;
          }
        }
        tables[name] = PersistedTable(count, digest('$count:$sum'), records);
      }
    });
    return PersistedSnapshot(tables);
  }
}

class TableDifference {
  TableDifference(this.table, this.compared, this.differing, this.paths);
  final String table;
  final int compared;
  final int differing;
  final List<String> paths;
  String get report =>
      '$table: rows_compared=$compared rows_differing=${differing < 0 ? 'unknown (ledger hash mismatch)' : differing}'
      '${paths.isEmpty ? '' : '\n${paths.join('\n')}'}';
}

List<String> _paths(Object? before, Object? after, String path) {
  if (before == after) return [];
  if (before is Map && after is Map) {
    return [
      for (final key in {...before.keys, ...after.keys})
        if (!before.containsKey(key) || !after.containsKey(key))
          '$path.$key (presence)'
        else
          ..._paths(before[key], after[key], '$path.$key'),
    ];
  }
  if (before is List && after is List) {
    return [
      if (before.length != after.length) '$path.length',
      for (var i = 0; i < before.length && i < after.length; i++)
        ..._paths(before[i], after[i], '$path[$i]'),
    ];
  }
  return [path];
}

List<TableDifference> compareSnapshots(
  PersistedSnapshot before,
  PersistedSnapshot after,
) {
  return [
    for (final table in {...before.tables.keys, ...after.tables.keys})
      _compareTable(table, before.tables[table], after.tables[table]),
  ];
}

TableDifference _compareTable(
  String table,
  PersistedTable? a,
  PersistedTable? b,
) {
  final keys = {...?a?.records.keys, ...?b?.records.keys};
  final paths = <String>[];
  var differing = 0;
  for (final key in keys) {
    final left = a?.records[key];
    final right = b?.records[key];
    if (jsonEncode(left) == jsonEncode(right)) continue;
    differing++;
    if (left == null || right == null) {
      paths.add('$key: row presence');
      continue;
    }
    for (final column in {...left.keys, ...right.keys}) {
      if (left[column] == right[column]) continue;
      if (column.endsWith('_json') &&
          left[column] is String &&
          right[column] is String) {
        final nested = _paths(
          jsonDecode(left[column] as String),
          jsonDecode(right[column] as String),
          column,
        );
        paths.addAll([
          for (final path in nested.isEmpty ? ['$column (bytes)'] : nested)
            '$key: $path',
        ]);
      } else {
        paths.add('$key: $column');
      }
    }
  }
  if (keys.isEmpty && a?.fingerprint != b?.fingerprint) {
    // Source ledgers are compared losslessly by commutative row hashes; no
    // physiological fields are printed, even if retention changes a ledger.
    differing = -1;
    paths.add('row hashes/count (source ledger)');
  }
  return TableDifference(
    table,
    keys.isEmpty ? (a?.rows ?? b?.rows ?? 0) : keys.length,
    differing,
    paths,
  );
}

Future<Map<String, dynamic>> _freshness(String key) async {
  final row = await LocalDb.computeFreshness(key);
  return row == null
      ? {}
      : (jsonDecode(row['payload_json'] as String) as Map)
            .cast<String, dynamic>();
}

// Same bounded production jobs as storage_proof_test.dart, plus the series
// re-encoding walk. Complete them BEFORE deriving so migration progress is
// not confused with recalculation drift. No output rows are reset between runs.
Future<void> completeStorageHousekeeping() async {
  Future<void> until(Future<bool> Function() step) async {
    for (var i = 0; i < 10000; i++) {
      if (await step()) return;
    }
    throw StateError('Housekeeping did not converge');
  }

  await until(() async {
    final n = await LocalDb.compactLegacyOneHz();
    return n == 0 &&
        (await _freshness(LocalDb.kOneHzCompactCursorKey))['done'] == true;
  });
  await until(() async {
    await LocalDb.pruneDuplicateSamples();
    return (await _freshness(LocalDb.kSamplePruneCursorKey))['cursor'] == 0;
  });
  await until(() async => await LocalDb.pruneSupersededIntermediates() == 0);
  await until(() async => await LocalDb.pruneSupersededDayResults() == 0);
  await until(() async {
    await LocalDb.reencodeLegacyDayResults();
    return (await _freshness(LocalDb.kReencodeCursorKey))['done'] == true;
  });
  await LocalDb.vacuumIfBloated();
}
