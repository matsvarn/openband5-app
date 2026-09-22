// SQLite CAS for cycle_log / cycle_symptom. Settings persistence is runtime.

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../openband/cycle_data.dart';
import 'db.dart';

class CycleStore {
  /// Production binds [LocalDb.invalidateCycleContext]. Tests replace this.
  static Future<void> Function(DatabaseExecutor txn) invalidateCycleContext =
      (txn) => LocalDb.invalidateCycleContext(txn);

  static Future<CycleSnapshot> read(
    DatabaseExecutor db, {
    required String day,
    required CycleSettings settings,
  }) async {
    requireCycleCalendarDay(day);
    final parsed = await load(db, asOf: day);
    return buildCycleSnapshot(
      day: day,
      settings: settings,
      starts: parsed.starts,
      observations: parsed.observations,
      unreadableCount: parsed.unreadableCount,
      unreadableStarts: parsed.unreadableStarts,
    );
  }

  static Future<CycleLogParse> load(
    DatabaseExecutor db, {
    String? asOf,
  }) async {
    final startRows = await db.query('cycle_log', orderBy: 'date ASC');
    final observationRows =
        await db.query('cycle_symptom', orderBy: 'date ASC');
    return parseCycleLog(
      startRows: [for (final r in startRows) r.cast<Object?, Object?>()],
      observationRows: [
        for (final r in observationRows) r.cast<Object?, Object?>(),
      ],
      asOf: asOf,
    );
  }

  static Future<CycleWriteResult> saveStart(
    DatabaseExecutor db,
    CycleStart desired, {
    CycleStart? expected,
    required DateTime now,
  }) async {
    if (desired.kind.isEmpty) {
      throw ArgumentError.value(desired.kind, 'kind', 'Cycle kind is required.');
    }
    requireCycleWriteDay(desired.date, now);
    if (expected != null) requireCycleCalendarDay(expected.date, 'expected.date');
    return _txn(db, (txn) async {
      final before = await _contributingDates(txn);
      final atDesired = await _startOn(txn, desired.date);
      late final CycleWriteResult result;
      if (expected == null) {
        if (atDesired == desired) {
          result = CycleWriteResult.saved(start: atDesired);
        } else if (atDesired != null) {
          result = CycleWriteResult.conflict(currentStart: atDesired);
        } else {
          await _insertStart(txn, desired);
          result = CycleWriteResult.saved(start: desired);
        }
      } else if (expected.date == desired.date) {
        if (atDesired == desired) {
          result = CycleWriteResult.saved(start: atDesired);
        } else if (atDesired != expected) {
          result = CycleWriteResult.conflict(currentStart: atDesired);
        } else {
          await _updateStart(txn, desired);
          result = CycleWriteResult.saved(start: desired);
        }
      } else {
        final atSource = await _startOn(txn, expected.date);
        if (atDesired == desired && atSource == null) {
          result = CycleWriteResult.saved(start: atDesired);
        } else if (atSource != expected) {
          result = CycleWriteResult.conflict(currentStart: atSource);
        } else if (atDesired != null) {
          result = CycleWriteResult.conflict(currentStart: atDesired);
        } else {
          await txn.delete(
            'cycle_log',
            where: 'date = ?',
            whereArgs: [expected.date],
          );
          await _insertStart(txn, desired);
          result = CycleWriteResult.saved(start: desired);
        }
      }
      await _invalidateIfContributingChanged(txn, before, result);
      return result;
    });
  }

  static Future<CycleWriteResult> removeStart(
    DatabaseExecutor db,
    CycleStart expected,
  ) async {
    requireCycleCalendarDay(expected.date, 'expected.date');
    return _txn(db, (txn) async {
      final before = await _contributingDates(txn);
      final current = await _startOn(txn, expected.date);
      late final CycleWriteResult result;
      if (current == null) {
        result = CycleWriteResult.saved(start: expected);
      } else if (current != expected) {
        result = CycleWriteResult.conflict(currentStart: current);
      } else {
        await txn.delete(
          'cycle_log',
          where: 'date = ?',
          whereArgs: [expected.date],
        );
        result = CycleWriteResult.saved(start: expected);
      }
      await _invalidateIfContributingChanged(txn, before, result);
      return result;
    });
  }

  static Future<CycleWriteResult> restoreStart(
    DatabaseExecutor db,
    CycleStart removed, {
    required DateTime now,
  }) async {
    if (removed.kind.isEmpty) {
      throw ArgumentError.value(removed.kind, 'kind', 'Cycle kind is required.');
    }
    requireCycleWriteDay(removed.date, now);
    return _txn(db, (txn) async {
      final before = await _contributingDates(txn);
      final current = await _startOn(txn, removed.date);
      late final CycleWriteResult result;
      if (current == removed) {
        result = CycleWriteResult.saved(start: current);
      } else if (current != null) {
        result = CycleWriteResult.conflict(currentStart: current);
      } else {
        await _insertStart(txn, removed);
        result = CycleWriteResult.saved(start: removed);
      }
      await _invalidateIfContributingChanged(txn, before, result);
      return result;
    });
  }

  static Future<CycleWriteResult> saveObservation(
    DatabaseExecutor db,
    CycleObservation desired, {
    CycleObservation? expected,
    required DateTime now,
  }) async {
    requireCycleWriteDay(desired.date, now);
    if (expected != null) {
      requireCycleCalendarDay(expected.date, 'expected.date');
      if (expected.date != desired.date) {
        throw ArgumentError.value(
          desired.date,
          'date',
          'Observation date cannot move.',
        );
      }
    }
    return _txn(db, (txn) async {
      final current = await _observationOn(txn, desired.date);
      if (desired.isClear) {
        if (current == null) {
          return const CycleWriteResult.saved();
        }
        if (cycleObservationsContentEqual(current, desired)) {
          await txn.delete(
            'cycle_symptom',
            where: 'date = ?',
            whereArgs: [desired.date],
          );
          return const CycleWriteResult.saved();
        }
        if (expected != null && current != expected) {
          return CycleWriteResult.conflict(currentObservation: current);
        }
        if (expected == null) {
          return CycleWriteResult.conflict(currentObservation: current);
        }
        await txn.delete(
          'cycle_symptom',
          where: 'date = ?',
          whereArgs: [desired.date],
        );
        return const CycleWriteResult.saved();
      }
      if (cycleObservationsContentEqual(current, desired)) {
        return CycleWriteResult.saved(observation: current);
      }
      if (expected == null) {
        if (current != null) {
          return CycleWriteResult.conflict(currentObservation: current);
        }
      } else if (current != expected) {
        return CycleWriteResult.conflict(currentObservation: current);
      }
      final saved = CycleObservation(
        date: desired.date,
        tags: List.unmodifiable(desired.tags),
        note: desired.note,
        updatedAt: now.millisecondsSinceEpoch,
      );
      await txn.insert(
        'cycle_symptom',
        {
          'date': saved.date,
          'symptoms_json': jsonEncode(saved.tags),
          'note': saved.note,
          'updated_at': saved.updatedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return CycleWriteResult.saved(observation: saved);
    });
  }

  static Future<CycleStart?> _startOn(DatabaseExecutor db, String date) async {
    final rows = await db.query(
      'cycle_log',
      where: 'date = ?',
      whereArgs: [date],
    );
    if (rows.isEmpty) return null;
    final parsed = parseCycleStartRow(rows.single.cast<Object?, Object?>());
    if (parsed.unreadable || parsed.start == null) {
      throw const FormatException('Stored cycle start is unreadable.');
    }
    return parsed.start;
  }

  static Future<CycleObservation?> _observationOn(
    DatabaseExecutor db,
    String date,
  ) async {
    final rows = await db.query(
      'cycle_symptom',
      where: 'date = ?',
      whereArgs: [date],
    );
    if (rows.isEmpty) return null;
    final parsed =
        parseCycleObservationRow(rows.single.cast<Object?, Object?>());
    if (parsed.unreadable || parsed.observation == null) {
      throw const FormatException('Stored cycle observation is unreadable.');
    }
    return parsed.observation;
  }

  static Future<void> _insertStart(DatabaseExecutor db, CycleStart start) =>
      db.insert('cycle_log', {
        'date': start.date,
        'kind': start.kind,
        'note': start.note,
      });

  static Future<void> _updateStart(DatabaseExecutor db, CycleStart start) =>
      db.update(
        'cycle_log',
        {'kind': start.kind, 'note': start.note},
        where: 'date = ?',
        whereArgs: [start.date],
      );

  static Future<List<String>> _contributingDates(DatabaseExecutor db) async {
    final rows = await db.query(
      'cycle_log',
      columns: ['date', 'kind'],
      orderBy: 'date ASC',
    );
    return [
      for (final r in rows)
        if (r['kind'] == kCycleStartKind && r['date'] is String)
          r['date'] as String,
    ];
  }

  static Future<void> _invalidateIfContributingChanged(
    DatabaseExecutor txn,
    List<String> before,
    CycleWriteResult result,
  ) async {
    if (!result.committed) return;
    final after = await _contributingDates(txn);
    if (_sameDates(before, after)) return;
    await invalidateCycleContext(txn);
  }

  static bool _sameDates(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Future<T> _txn<T>(
    DatabaseExecutor db,
    Future<T> Function(DatabaseExecutor txn) fn,
  ) {
    if (db is Database) return db.transaction(fn);
    return fn(db);
  }
}
