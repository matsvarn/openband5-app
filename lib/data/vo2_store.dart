// User-entered VO2max. Append-only revisions keyed by a stable entry id.
//
// The head is the highest revision. A delete keeps that revision's payload and
// sets the deleted flag; restore appends another revision. Nothing here is a
// metric, and nothing is removed except by the existing whole-database wipe.

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite/sqflite.dart';

import '../openband/vo2_data.dart';

const String kManualVo2Table = 'manual_vo2';

/// Rows read per chain page. One entry id is in memory at a time.
@visibleForTesting
int vo2ChainPageSize = 32;

Future<void> createVo2Tables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS $kManualVo2Table (
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
      PRIMARY KEY (id, revision),
      CHECK (revision >= 1),
      CHECK (value_ml_kg_min > 0),
      CHECK (deleted IN (0, 1)),
      CHECK (origin = '$kVo2Origin'),
      CHECK (unit = '$kVo2Unit')
    )
  ''');
}

class Vo2Store {
  Vo2Store._();

  static final _Gate _gate = _Gate();

  static Future<Vo2WriteResult> create(
    Database db, {
    required String id,
    required String measuredOn,
    required double valueMlKgMin,
    String? declaredMethod,
    required DateTime now,
  }) {
    return _write(
      db,
      id: id,
      expectedRevision: 0,
      now: now,
      op: _Op.create,
      measuredOn: measuredOn,
      valueMlKgMin: valueMlKgMin,
      declaredMethod: declaredMethod,
    );
  }

  static Future<Vo2WriteResult> edit(
    Database db, {
    required String id,
    required int expectedRevision,
    required String measuredOn,
    required double valueMlKgMin,
    String? declaredMethod,
    required DateTime now,
  }) {
    return _write(
      db,
      id: id,
      expectedRevision: expectedRevision,
      now: now,
      op: _Op.edit,
      measuredOn: measuredOn,
      valueMlKgMin: valueMlKgMin,
      declaredMethod: declaredMethod,
    );
  }

  static Future<Vo2WriteResult> delete(
    Database db, {
    required String id,
    required int expectedRevision,
    required DateTime now,
  }) {
    return _write(
      db,
      id: id,
      expectedRevision: expectedRevision,
      now: now,
      op: _Op.delete,
    );
  }

  static Future<Vo2WriteResult> restore(
    Database db, {
    required String id,
    required int expectedRevision,
    required DateTime now,
  }) {
    return _write(
      db,
      id: id,
      expectedRevision: expectedRevision,
      now: now,
      op: _Op.restore,
    );
  }

  static Future<Vo2List> list(Database db) {
    return db.transaction((txn) async {
      final rowCount =
          Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM $kManualVo2Table'),
          ) ??
          0;
      final badIds =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM $kManualVo2Table '
              "WHERE typeof(id) != 'text' OR id = ''",
            ),
          ) ??
          0;
      final entries = <Vo2ListEntry>[];
      var corrupt = badIds;
      String? after;
      while (true) {
        final ids = await txn.rawQuery(
          'SELECT id FROM $kManualVo2Table '
          "WHERE typeof(id) = 'text' AND id != '' "
          'AND (? IS NULL OR id > ?) '
          'GROUP BY id ORDER BY id LIMIT 1',
          [after, after],
        );
        if (ids.isEmpty) break;
        final id = ids.first['id'];
        if (id is! String) {
          corrupt += 1;
          break;
        }
        after = id;
        final headRows = await txn.rawQuery(
          'SELECT * FROM $kManualVo2Table WHERE id = ? '
          'ORDER BY revision DESC LIMIT 1',
          [id],
        );
        final head = headRows.isEmpty
            ? null
            : tryParseVo2Row(headRows.first);
        if (head == null) {
          corrupt += 1;
          entries.add(Vo2ListEntry(id: id, head: null, corrupt: true));
        } else {
          entries.add(Vo2ListEntry(id: id, head: head, corrupt: false));
        }
      }
      return Vo2List(
        entries: entries,
        corruptCount: corrupt,
        rowCount: rowCount,
      );
    });
  }

  static Future<Vo2Detail> detail(Database db, String id) {
    return db.transaction((txn) async {
      if (!isVo2EntryId(id)) {
        return Vo2Detail(
          id: id,
          head: null,
          missing: true,
          headCorrupt: false,
          revisions: const [],
          corruptRevisionCount: 0,
        );
      }
      final slots = <Vo2RevisionSlot>[];
      final cursor = _ChainCursor(txn, id);
      while (true) {
        final raw = await cursor.next();
        if (raw == null) break;
        final parsed = tryParseVo2Row(raw);
        slots.add(
          Vo2RevisionSlot(
            revision: parsed?.revision ?? _whole(raw['revision']),
            value: parsed,
            corrupt: parsed == null,
          ),
        );
      }
      if (slots.isEmpty) {
        return Vo2Detail(
          id: id,
          head: null,
          missing: true,
          headCorrupt: false,
          revisions: const [],
          corruptRevisionCount: 0,
        );
      }
      final last = slots.last;
      final corruptRevisions = slots.where((s) => s.corrupt).length;
      return Vo2Detail(
        id: id,
        head: last.corrupt ? null : last.value,
        missing: false,
        headCorrupt: last.corrupt,
        revisions: slots,
        corruptRevisionCount: corruptRevisions,
      );
    });
  }

  /// Merge one entry's revision chain at a time.
  ///
  /// [inserted] is revision rows appended. [conflictIds] and [corruptIds] are
  /// entry ids left untouched. A divergent or invalid chain does not write a
  /// prefix of that id. Other ids still merge.
  ///
  /// Each id commits before the next is read. After the source table is
  /// confirmed, a later read or write throws [Vo2ImportInterrupted] carrying
  /// only ids whose transactions committed. A missing table still returns
  /// [Vo2ImportCounts.missing]. [readSource] is the test seam for a later
  /// source page; production leaves it null.
  static Future<Vo2ImportCounts> mergeImport({
    required Database src,
    required Database dest,
    @visibleForTesting
    Future<List<Map<String, Object?>>> Function(
      String sql,
      List<Object?>? arguments,
    )?
    readSource,
  }) async {
    try {
      await src.rawQuery('SELECT 1 FROM $kManualVo2Table LIMIT 1');
    } on DatabaseException catch (e) {
      if (e.isNoSuchTableError()) return const Vo2ImportCounts.missing();
      rethrow;
    }
    Future<List<Map<String, Object?>>> sourceQuery(
      String sql,
      List<Object?>? arguments,
    ) {
      final read = readSource;
      if (read != null) return read(sql, arguments);
      return src.rawQuery(sql, arguments);
    }

    var inserted = 0;
    var conflictIds = 0;
    var corruptIds = 0;
    try {
      corruptIds =
          Sqflite.firstIntValue(
            await sourceQuery(
              'SELECT COUNT(*) FROM $kManualVo2Table '
              "WHERE typeof(id) != 'text' OR id = ''",
              null,
            ),
          ) ??
          0;
      String? after;
      while (true) {
        final ids = await sourceQuery(
          'SELECT id FROM $kManualVo2Table '
          "WHERE typeof(id) = 'text' AND id != '' "
          'AND (? IS NULL OR id > ?) '
          'GROUP BY id ORDER BY id LIMIT 1',
          [after, after],
        );
        if (ids.isEmpty) break;
        final id = ids.first['id'];
        if (id is! String) {
          corruptIds += 1;
          break;
        }
        after = id;
        final outcome = await _gate.run(
          () => dest.transaction((txn) async {
            final pair = await _lockstep(src, txn, id);
            // An invalid source is corrupt even when it matches the local chain.
            // Checking the prefix first reported a gapped 1,3 copy as a no-op.
            if (!pair.sourceValid) return (kind: _IdOutcome.corrupt, n: 0);
            if (pair.sourceRows <= pair.localRows && pair.prefixEqual) {
              return (kind: _IdOutcome.noop, n: 0);
            }
            if (pair.prefixEqual &&
                pair.localContiguous &&
                pair.sourceRows > pair.localRows) {
              final n = await _appendTail(
                src,
                txn,
                id,
                pair.localRows,
                readSource: readSource,
              );
              return (kind: _IdOutcome.appended, n: n);
            }
            return (kind: _IdOutcome.conflict, n: 0);
          }),
        );
        switch (outcome.kind) {
          case _IdOutcome.noop:
            break;
          case _IdOutcome.appended:
            inserted += outcome.n;
            break;
          case _IdOutcome.conflict:
            conflictIds += 1;
            break;
          case _IdOutcome.corrupt:
            corruptIds += 1;
            break;
        }
      }
      return Vo2ImportCounts(
        inserted: inserted,
        conflictIds: conflictIds,
        corruptIds: corruptIds,
      );
    } catch (e, st) {
      if (e is Vo2ImportInterrupted) {
        Error.throwWithStackTrace(e, st);
      }
      Error.throwWithStackTrace(
        Vo2ImportInterrupted(
          Vo2ImportCounts(
            inserted: inserted,
            conflictIds: conflictIds,
            corruptIds: corruptIds,
          ),
          e,
        ),
        st,
      );
    }
  }

  /// Every revision of each id whose current head [measured_on] is in [dayIds],
  /// including a deleted head. Older revisions stay even when their own date
  /// is outside the range.
  static Future<void> copyChainsForHeadDays({
    required Database src,
    required Database out,
    required List<String> dayIds,
  }) async {
    if (dayIds.isEmpty) return;
    const chunk = 400;
    for (var i = 0; i < dayIds.length; i += chunk) {
      final days = dayIds.sublist(
        i,
        i + chunk > dayIds.length ? dayIds.length : i + chunk,
      );
      final ph = List.filled(days.length, '?').join(',');
      final heads = await src.rawQuery(
        'SELECT h.id FROM $kManualVo2Table h '
        'WHERE h.measured_on IN ($ph) '
        'AND h.revision = ('
        '  SELECT MAX(r.revision) FROM $kManualVo2Table r WHERE r.id = h.id'
        ')',
        days,
      );
      for (final head in heads) {
        final id = head['id'];
        if (id is! String || id.isEmpty) continue;
        await _copyId(src, out, id);
      }
    }
  }
}

class Vo2ImportCounts {
  const Vo2ImportCounts({
    required this.inserted,
    required this.conflictIds,
    required this.corruptIds,
  }) : tableMissing = false;

  const Vo2ImportCounts.missing()
    : inserted = 0,
      conflictIds = 0,
      corruptIds = 0,
      tableMissing = true;

  final int inserted;
  final int conflictIds;
  final int corruptIds;
  final bool tableMissing;
}

/// A source read or dest write failed after [counts] had already committed.
///
/// [counts] omits the id whose transaction failed. [cause] is that failure.
class Vo2ImportInterrupted implements Exception {
  Vo2ImportInterrupted(this.counts, this.cause);

  final Vo2ImportCounts counts;
  final Object cause;

  @override
  String toString() =>
      'Vo2ImportInterrupted(inserted: ${counts.inserted}, '
      'conflictIds: ${counts.conflictIds}, '
      'corruptIds: ${counts.corruptIds}): $cause';
}

enum _Op { create, edit, delete, restore }

enum _IdOutcome { noop, appended, conflict, corrupt }

class _Gate {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() job) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return previous.catchError((_) {}).then((_) => job()).whenComplete(() {
      if (!done.isCompleted) done.complete();
    });
  }
}

Future<Vo2WriteResult> _write(
  Database db, {
  required String id,
  required int expectedRevision,
  required DateTime now,
  required _Op op,
  String? measuredOn,
  double? valueMlKgMin,
  String? declaredMethod,
}) async {
  final method = normalizeVo2Method(declaredMethod);
  if (!_inputOk(
    op: op,
    id: id,
    expectedRevision: expectedRevision,
    measuredOn: measuredOn,
    valueMlKgMin: valueMlKgMin,
  )) {
    return const Vo2WriteRejected(Vo2RejectReason.invalid);
  }
  final nowMs = now.millisecondsSinceEpoch;
  return Vo2Store._gate.run(() => db.transaction((txn) async {
    final headRow = await _headRaw(txn, id);
    if (headRow == null) {
      if (op != _Op.create) {
        return const Vo2WriteRejected(Vo2RejectReason.missing);
      }
      final created = Vo2Revision(
        id: id,
        revision: 1,
        measuredOn: measuredOn!,
        valueMlKgMin: valueMlKgMin!,
        declaredMethod: method,
        createdAt: nowMs,
        updatedAt: nowMs,
        deleted: false,
      );
      await txn.insert(kManualVo2Table, _toRow(created));
      return Vo2Committed(created);
    }
    final head = tryParseVo2Row(headRow);
    if (head == null) {
      return const Vo2WriteConflict(headCorrupt: true);
    }
    if (head.revision == expectedRevision) {
      if (!_applies(op, head)) return Vo2WriteConflict(head: head);
      final next = _next(
        op: op,
        head: head,
        nowMs: nowMs,
        measuredOn: measuredOn,
        valueMlKgMin: valueMlKgMin,
        method: method,
      );
      await txn.insert(kManualVo2Table, _toRow(next));
      return Vo2Committed(next);
    }
    if (head.revision == expectedRevision + 1 &&
        await _isRetry(
          txn,
          op: op,
          head: head,
          expectedRevision: expectedRevision,
          measuredOn: measuredOn,
          valueMlKgMin: valueMlKgMin,
          method: method,
        )) {
      return Vo2Committed(head, retry: true);
    }
    return Vo2WriteConflict(head: head);
  }));
}

bool _inputOk({
  required _Op op,
  required String id,
  required int expectedRevision,
  String? measuredOn,
  double? valueMlKgMin,
}) {
  if (!isVo2EntryId(id)) return false;
  if (op == _Op.create) {
    if (expectedRevision != 0) return false;
  } else if (expectedRevision < 1) {
    return false;
  }
  if (op == _Op.create || op == _Op.edit) {
    if (measuredOn == null || !isVo2CivilDay(measuredOn)) return false;
    if (valueMlKgMin == null || !isVo2Value(valueMlKgMin)) return false;
  }
  return true;
}

bool _applies(_Op op, Vo2Revision head) {
  switch (op) {
    case _Op.create:
      return false;
    case _Op.edit:
    case _Op.delete:
      return !head.deleted;
    case _Op.restore:
      return head.deleted;
  }
}

Vo2Revision _next({
  required _Op op,
  required Vo2Revision head,
  required int nowMs,
  String? measuredOn,
  double? valueMlKgMin,
  String? method,
}) {
  final deleted = op == _Op.delete;
  return Vo2Revision(
    id: head.id,
    revision: head.revision + 1,
    measuredOn: op == _Op.edit ? measuredOn! : head.measuredOn,
    valueMlKgMin: op == _Op.edit ? valueMlKgMin! : head.valueMlKgMin,
    declaredMethod: op == _Op.edit ? method : head.declaredMethod,
    createdAt: head.createdAt,
    updatedAt: nowMs > head.updatedAt ? nowMs : head.updatedAt + 1,
    deleted: deleted,
  );
}

Future<bool> _isRetry(
  DatabaseExecutor txn, {
  required _Op op,
  required Vo2Revision head,
  required int expectedRevision,
  String? measuredOn,
  double? valueMlKgMin,
  String? method,
}) async {
  if (op == _Op.create) {
    return !head.deleted &&
        head.revision == 1 &&
        head.measuredOn == measuredOn &&
        head.valueMlKgMin == valueMlKgMin &&
        head.declaredMethod == method &&
        head.origin == kVo2Origin &&
        head.unit == kVo2Unit;
  }
  final baseRaw = await txn.query(
    kManualVo2Table,
    where: 'id = ? AND revision = ?',
    whereArgs: [head.id, expectedRevision],
    limit: 1,
  );
  if (baseRaw.isEmpty) return false;
  final base = tryParseVo2Row(baseRaw.first);
  if (base == null || base.createdAt != head.createdAt) return false;
  // The named revision has to be one this operation could have changed.
  // An identical active edit is not a restore, and a restore is not an edit.
  if (!_applies(op, base)) return false;
  final deleted = op == _Op.delete;
  if (op == _Op.edit) {
    return !head.deleted &&
        head.measuredOn == measuredOn &&
        head.valueMlKgMin == valueMlKgMin &&
        head.declaredMethod == method;
  }
  return head.deleted == deleted &&
      head.measuredOn == base.measuredOn &&
      head.valueMlKgMin == base.valueMlKgMin &&
      head.declaredMethod == base.declaredMethod &&
      head.origin == base.origin &&
      head.unit == base.unit;
}

Future<Map<String, Object?>?> _headRaw(DatabaseExecutor db, String id) async {
  final rows = await db.rawQuery(
    'SELECT * FROM $kManualVo2Table WHERE id = ? '
    'ORDER BY revision DESC LIMIT 1',
    [id],
  );
  if (rows.isEmpty) return null;
  return rows.first;
}

Map<String, Object?> _toRow(Vo2Revision revision) => {
  'id': revision.id,
  'revision': revision.revision,
  'measured_on': revision.measuredOn,
  'value_ml_kg_min': revision.valueMlKgMin,
  'declared_method': revision.declaredMethod,
  'created_at': revision.createdAt,
  'updated_at': revision.updatedAt,
  'deleted': revision.deleted ? 1 : 0,
  'origin': revision.origin,
  'unit': revision.unit,
};

class _Pair {
  const _Pair({
    required this.sourceRows,
    required this.localRows,
    required this.sourceValid,
    required this.localContiguous,
    required this.prefixEqual,
  });

  final int sourceRows;
  final int localRows;
  final bool sourceValid;
  final bool localContiguous;
  final bool prefixEqual;
}

Future<_Pair> _lockstep(
  DatabaseExecutor src,
  DatabaseExecutor local,
  String id,
) async {
  final source = _ChainCursor(src, id);
  final stored = _ChainCursor(local, id);
  var sourceRows = 0;
  var localRows = 0;
  var sourceValid = true;
  var localContiguous = true;
  var prefixEqual = true;
  int? createdAt;
  int? previousUpdated;
  var sourceRaw = await source.next();
  var localRaw = await stored.next();
  while (sourceRaw != null || localRaw != null) {
    Vo2Revision? sourceRev;
    Vo2Revision? localRev;
    if (sourceRaw != null) {
      sourceRows += 1;
      sourceRev = tryParseVo2Row(sourceRaw);
      if (sourceRev == null ||
          sourceRev.id != id ||
          sourceRev.revision != sourceRows) {
        sourceValid = false;
      } else if (createdAt == null) {
        createdAt = sourceRev.createdAt;
        if (sourceRev.updatedAt < sourceRev.createdAt) sourceValid = false;
        previousUpdated = sourceRev.updatedAt;
      } else if (sourceRev.createdAt != createdAt ||
          sourceRev.updatedAt <= previousUpdated!) {
        sourceValid = false;
      } else {
        previousUpdated = sourceRev.updatedAt;
      }
    }
    if (localRaw != null) {
      localRows += 1;
      localRev = tryParseVo2Row(localRaw);
      if (localRev == null ||
          localRev.id != id ||
          localRev.revision != localRows) {
        localContiguous = false;
      }
    }
    if (sourceRaw != null &&
        localRaw != null &&
        (sourceRev == null ||
            localRev == null ||
            !sourceRev.sameStored(localRev))) {
      prefixEqual = false;
    }
    if (sourceRaw != null) sourceRaw = await source.next();
    if (localRaw != null) localRaw = await stored.next();
  }
  return _Pair(
    sourceRows: sourceRows,
    localRows: localRows,
    sourceValid: sourceValid,
    localContiguous: localContiguous,
    prefixEqual: prefixEqual,
  );
}

Future<int> _appendTail(
  DatabaseExecutor src,
  DatabaseExecutor txn,
  String id,
  int localRows, {
  Future<List<Map<String, Object?>>> Function(
    String sql,
    List<Object?>? arguments,
  )?
  readSource,
}) async {
  var after = localRows;
  var inserted = 0;
  while (true) {
    const tailSql =
        'SELECT * FROM $kManualVo2Table '
        'WHERE id = ? AND revision > ? '
        'ORDER BY revision ASC LIMIT ?';
    final tailArgs = [id, after, vo2ChainPageSize];
    final page = readSource == null
        ? await src.rawQuery(tailSql, tailArgs)
        : await readSource(tailSql, tailArgs);
    if (page.isEmpty) return inserted;
    for (final raw in page) {
      final parsed = tryParseVo2Row(Map<String, Object?>.from(raw));
      if (parsed == null || parsed.revision <= after) {
        throw StateError('VO2 chain changed during import');
      }
      await txn.insert(
        kManualVo2Table,
        _toRow(parsed),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      after = parsed.revision;
      inserted += 1;
    }
    if (page.length < vo2ChainPageSize) return inserted;
  }
}

class _ChainCursor {
  _ChainCursor(this.db, this.id);

  final DatabaseExecutor db;
  final String id;
  var _started = false;
  var _exhausted = false;
  var _blocked = false;
  Object? _revision;
  var _rowid = 0;
  List<Map<String, Object?>> _page = const [];
  var _index = 0;

  Future<Map<String, Object?>?> next() async {
    if (_index >= _page.length) {
      if (_exhausted) return null;
      if (_blocked) {
        throw StateError('VO2 revision page has no continuation bound');
      }
      final List<Map<String, Object?>> page;
      if (!_started) {
        page = await db.rawQuery(
          'SELECT rowid AS _rowid, * FROM $kManualVo2Table '
          'WHERE id = ? ORDER BY revision ASC, rowid ASC LIMIT ?',
          [id, vo2ChainPageSize],
        );
        _started = true;
      } else {
        page = await db.rawQuery(
          'SELECT rowid AS _rowid, * FROM $kManualVo2Table '
          'WHERE id = ? AND (revision > ? OR (revision = ? AND rowid > ?)) '
          'ORDER BY revision ASC, rowid ASC LIMIT ?',
          [id, _revision, _revision, _rowid, vo2ChainPageSize],
        );
      }
      if (page.isEmpty) {
        _exhausted = true;
        return null;
      }
      _page = page;
      _index = 0;
      final last = page.last;
      final revision = last['revision'];
      final rowid = last['_rowid'];
      final full = page.length == vo2ChainPageSize;
      // Exact stored value. toInt() makes 1.5 select itself again, and a
      // text or blob revision is still a real bound — stopping there drops
      // the rest of the chain.
      if (revision == null || rowid is! int) {
        if (full) {
          _blocked = true;
        } else {
          _exhausted = true;
        }
      } else {
        _revision = revision;
        _rowid = rowid;
        _exhausted = !full;
      }
    }
    return _page[_index++];
  }
}

/// Same bound as the row parser. 2^63 must not become the revision shown for
/// an unreadable slot: `toInt` clamps it to int64 max, and that max converts
/// back to the same double.
int? _whole(Object? raw) {
  if (raw is int) {
    if (raw < -9223372036854775808 || raw > 9223372036854775807) return null;
    return raw;
  }
  if (raw is! double || !raw.isFinite) return null;
  if (raw >= 9223372036854775808.0) return null;
  if (raw != raw.roundToDouble()) return null;
  final n = raw.toInt();
  if (n.toDouble() != raw) return null;
  return n;
}

Future<void> _copyId(Database src, Database out, String id) async {
  await out.transaction((txn) async {
    final cursor = _ChainCursor(src, id);
    while (true) {
      final raw = await cursor.next();
      if (raw == null) return;
      final row = <String, Object?>{
        for (final e in raw.entries)
          if (e.key != '_rowid') e.key: e.value,
      };
      await txn.insert(
        kManualVo2Table,
        row,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  });
}
