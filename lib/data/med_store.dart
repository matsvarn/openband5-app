// Medication and supplements — definitions, a schedule, and per-dose state.
//
// This needs its own table where habits do not (see db.dart's journal_metric
// note and UI_WIRING §5.6): a habit is one number per day, a medication is a
// SCHEDULE plus one taken/skipped record per slot. Multiple rows per (day,
// thing) is the whole reason for a table.
//
// Schema 65 adds `med_plan_revision` as historical truth. `med_def` remains
// the latest head cache. A missing answer is unknown, never skipped, and is
// never a percentage. THERE IS NO INTERACTION CHECKING.

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../openband/medication_data.dart';
import 'day_label.dart';

// ══════════════════ SCHEMA ══════════════════

/// schemaVersion 36 tables, plus schema 65 revision history and dose snapshots.
Future<void> createMedTables(Database db, {DateTime? now}) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS med_def (
      key           TEXT PRIMARY KEY,
      label         TEXT NOT NULL,
      dose_value    REAL,
      dose_unit     TEXT NOT NULL DEFAULT '',
      kind          TEXT NOT NULL DEFAULT 'medication',
      schedule_json TEXT NOT NULL DEFAULT '[]',
      active        INTEGER NOT NULL DEFAULT 1,
      note          TEXT NOT NULL DEFAULT '',
      created_at    INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS med_dose (
      med_key     TEXT NOT NULL,
      date        TEXT NOT NULL,
      slot_min    INTEGER NOT NULL,
      taken_ts    INTEGER,
      skipped     INTEGER NOT NULL DEFAULT 0,
      dose_value  REAL,
      note        TEXT NOT NULL DEFAULT '',
      updated_at  INTEGER NOT NULL,
      PRIMARY KEY (med_key, date, slot_min)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_med_dose_date ON med_dose(date)',
  );
  await _ensureMedDoseColumn(db, 'label', 'TEXT');
  await _ensureMedDoseColumn(db, 'dose_unit', 'TEXT');
  await _ensureMedDoseColumn(db, 'kind', 'TEXT');
  await _ensureMedDoseColumn(db, 'taken_utc_offset_min', 'INTEGER');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS med_plan_revision (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      med_key         TEXT NOT NULL,
      effective_ts    INTEGER NOT NULL,
      effective_date  TEXT NOT NULL,
      effective_min   INTEGER NOT NULL,
      label           TEXT NOT NULL,
      dose_value      REAL,
      dose_unit       TEXT,
      kind            TEXT NOT NULL,
      note            TEXT NOT NULL DEFAULT '',
      schedule_json   TEXT NOT NULL,
      active          INTEGER NOT NULL,
      origin          TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_med_plan_revision_key_ts '
    'ON med_plan_revision(med_key, effective_ts, id)',
  );
  await migrateMedPlanRevisions(db, now: now);
}

Future<void> upgradeMedTables(Database db, {DateTime? now}) =>
    createMedTables(db, now: now);

Future<void> _ensureMedDoseColumn(
  Database db,
  String name,
  String typeSql,
) async {
  final info = await db.rawQuery('PRAGMA table_info(med_dose)');
  final cols = {
    for (final c in info)
      if (c['name'] is String) c['name'] as String,
  };
  if (cols.contains(name)) return;
  await db.execute('ALTER TABLE med_dose ADD COLUMN $name $typeSql');
}

/// Snapshot current `med_def` heads at [now], never `created_at`. Idempotent:
/// a key that already has a revision is left alone. Copies stored columns as
/// they are — corrupt kind/active/dose stay unreadable rather than becoming a
/// known schedule or unknown amount.
Future<void> migrateMedPlanRevisions(Database db, {DateTime? now}) async {
  final at = now ?? DateTime.now();
  final existing = await db.rawQuery(
    'SELECT DISTINCT med_key FROM med_plan_revision',
  );
  final have = {
    for (final r in existing)
      if (r['med_key'] is String) r['med_key'] as String,
  };
  final defs = await db.query('med_def');
  for (final row in defs) {
    final key = row['key'] as String?;
    if (key == null || key.isEmpty || have.contains(key)) continue;
    try {
      await _snapshotHeadRevision(db, row, now: at);
    } catch (_) {
      // Opening must not fail because one head cannot be snapshotted.
      // A missing revision is counted unreadable at read, not backdated here.
    }
  }
}

String? _storedUnit(String? unit) {
  final s = unit?.trim() ?? '';
  return s.isEmpty ? null : s;
}

Object? _decodeScheduleJson(Object? raw) {
  if (raw is List) return raw;
  if (raw is! String || raw.isEmpty) return const [];
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

// ══════════════════ STORE ══════════════════

/// Runtime read surface (schema 65).
///
/// ```text
/// MedDb.readPlans(db, {activeOnly}) -> Future<List<MedicationPlan>>
/// MedDb.readPlan(db, key) -> Future<MedicationPlan>
/// MedDb.readDay(db, date, {now, zone}) -> Future<MedicationDay>
/// MedDb.readHistory(db, from, to, {now, zone}) -> Future<MedicationHistory>
/// MedDb.coveringRevision(db, {key, date, slotMin}) -> Future<MedicationPlanRevision?>
/// MedDb.revisionsForKey(db, key) -> Future<List<MedicationPlanRevision>>
/// MedDb.upcomingReminderInstants(db, {now, horizonDays, zone})
///   -> Future<List<({key, date, slotMin, at})>>
/// ```
///
/// Writes: [MedDb.commitPlan], [MedDb.setActive], [MedDb.markDose].
class MedDb {
  MedDb._();

  static Future<bool> _hasPlan(DatabaseExecutor db, String key) async {
    final rows = await db.query(
      'med_def',
      columns: ['key'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<MedicationPlan> commitPlan(
    Database db,
    MedicationPlanDraft draft, {
    required DateTime now,
  }) async {
    requireMedicationPlanDraft(draft);
    final name = draft.name.trim();
    final unit = _storedUnit(draft.doseUnit);
    if (!draft.create) {
      if (!await _hasPlan(db, draft.key!.trim())) {
        throw StateError('No medication plan "${draft.key}" to update.');
      }
    }
    final key = draft.create
        ? (draft.key?.trim().isNotEmpty == true
            ? draft.key!.trim()
            : newMedicationPlanId())
        : draft.key!.trim();
    if (draft.create) {
      if (await _hasPlan(db, key)) {
        throw StateError('Medication plan "$key" already exists.');
      }
    }
    final scheduleJson = jsonEncode([
      for (final s in draft.schedule) s.toJson(),
    ]);
    final kind = medicationKindWire(draft.kind);
    final ts = now.millisecondsSinceEpoch;
    final committed = await db.transaction((txn) async {
      final created = await _createdAtMs(txn, key) ?? ts;
      await txn.insert(
        'med_def',
        {
          'key': key,
          'label': name,
          'dose_value': draft.doseValue,
          'dose_unit': unit ?? '',
          'kind': kind,
          'schedule_json': scheduleJson,
          'active': draft.active ? 1 : 0,
          'note': draft.note,
          'created_at': created,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final revisionId = await _insertRevision(
        txn,
        key: key,
        label: name,
        doseValue: draft.doseValue,
        doseUnit: unit,
        kind: kind,
        note: draft.note,
        scheduleJson: scheduleJson,
        active: draft.active,
        origin: MedicationPlanOrigin.user,
        now: now,
      );
      return (revisionId: revisionId, createdAt: created);
    });
    return MedicationPlan(
      key: key,
      name: name,
      doseValue: draft.doseValue,
      doseUnit: unit,
      kind: draft.kind,
      note: draft.note,
      schedule: draft.schedule,
      active: draft.active,
      createdAtMs: committed.createdAt,
      revisionId: committed.revisionId,
      effectiveTs: ts,
      effectiveDate: dayLabelOf(now),
      effectiveMin: now.hour * 60 + now.minute,
      origin: MedicationPlanOrigin.user,
    );
  }

  /// Typed current head for one key. Refuses an unreadable row rather than
  /// inventing a kind or dropping invalid slots.
  static Future<MedicationPlan> readPlan(Database db, String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(key, 'key');
    }
    final rows = await db.query(
      'med_def',
      where: 'key = ?',
      whereArgs: [trimmed],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('No medication plan "$trimmed" to update.');
    }
    return _planFromHeadRow(db, rows.first);
  }

  static Future<MedicationPlan> setActive(
    Database db,
    String key, {
    required bool active,
    required DateTime now,
  }) async {
    final current = await readPlan(db, key);
    if (current.scheduleUnreadableCount > 0) {
      throw FormatException(
        'Stored medication plan "${current.key}" has an unreadable schedule.',
      );
    }
    return commitPlan(
      db,
      MedicationPlanDraft(
        create: false,
        key: current.key,
        name: current.name,
        doseValue: current.doseValue,
        doseUnit: current.doseUnit,
        kind: current.kind,
        note: current.note,
        schedule: current.schedule,
        active: active,
      ),
      now: now,
    );
  }

  static Future<int?> _createdAtMs(DatabaseExecutor db, String key) async {
    final prior = await db.query(
      'med_def',
      columns: ['created_at'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (prior.isEmpty) return null;
    return (prior.first['created_at'] is num)
        ? parseMedicationInt(prior.first['created_at'])
        : null;
  }

  static Future<MedicationDayEntry?> markDose(
    Database db,
    MedicationEntryDraft draft, {
    required DateTime now,
    String? zone,
  }) async {
    requireMedicationEntryDraft(draft, now: now);
    final key = draft.key.trim();
    return db.transaction((txn) async {
      final revs = await revisionsForKey(txn, key);
      final currentName = await _headLabel(txn, key);
      if (draft.answer == MedicationEntryAnswer.clear) {
        await txn.delete(
          'med_dose',
          where: 'med_key = ? AND date = ? AND slot_min = ?',
          whereArgs: [key, draft.date, draft.slotMin],
        );
        return _entryFromMemory(
          key: key,
          date: draft.date,
          slotMin: draft.slotMin,
          now: now,
          revisions: revs,
          doses: const [],
          currentName: currentName,
          zone: zone,
        );
      }
      final written = await _upsertDose(
        txn,
        key: key,
        date: draft.date,
        slotMin: draft.slotMin,
        takenAt: draft.answer == MedicationEntryAnswer.taken
            ? (draft.takenAt ?? now)
            : null,
        skipped: draft.answer == MedicationEntryAnswer.skipped,
        note: draft.note,
        now: now,
        revisions: revs,
      );
      return _entryFromMemory(
        key: key,
        date: draft.date,
        slotMin: draft.slotMin,
        now: now,
        revisions: revs,
        doses: [written],
        currentName: currentName,
        zone: zone,
      );
    });
  }

  static Future<String?> _headLabel(DatabaseExecutor db, String key) async {
    final rows = await db.query(
      'med_def',
      columns: ['label'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final label = rows.first['label'];
    return label is String && label.isNotEmpty ? label : null;
  }

  static MedicationDayEntry? _entryFromMemory({
    required String key,
    required String date,
    required int slotMin,
    required DateTime now,
    required List<MedicationPlanRevision> revisions,
    required List<MedicationStoredDose> doses,
    required String? currentName,
    String? zone,
  }) {
    final resolved = resolveMedicationDay(
      date: date,
      now: now,
      revisionsByKey: {key: revisions},
      doses: doses,
      currentNames: currentName == null ? const {} : {key: currentName},
      zone: zone,
    );
    for (final e in resolved.entries) {
      if (e.key == key && e.slotMin == slotMin) return e;
    }
    return null;
  }

  static Future<MedicationStoredDose> _upsertDose(
    DatabaseExecutor db, {
    required String key,
    required String date,
    required int slotMin,
    required DateTime? takenAt,
    required bool skipped,
    String? note,
    required DateTime now,
    required List<MedicationPlanRevision> revisions,
  }) async {
    final existingRows = await db.query(
      'med_dose',
      where: 'med_key = ? AND date = ? AND slot_min = ?',
      whereArgs: [key, date, slotMin],
      limit: 1,
    );
    final existing =
        existingRows.isEmpty ? null : _doseFromRow(existingRows.first);
    final covering = coveringMedicationRevision(
      revisions: revisions,
      date: date,
      slotMin: slotMin,
    );
    final takenTs =
        takenAt == null ? null : takenAt.millisecondsSinceEpoch ~/ 1000;
    final Object? offsetToStore;
    if (existing != null && existing.takenTsSeconds == takenTs) {
      offsetToStore = existing.takenUtcOffsetMinutes;
    } else if (takenAt != null) {
      offsetToStore = takenAt.timeZoneOffset.inMinutes;
    } else {
      offsetToStore = null;
    }
    final written = MedicationStoredDose(
      medKey: key,
      date: date,
      slotMin: slotMin,
      takenTsSeconds: takenTs,
      skipped: skipped,
      doseValue: existing != null ? existing.doseValue : covering?.doseValue,
      doseUnit: existing != null ? existing.doseUnit : covering?.doseUnit,
      label: existing != null ? existing.label : covering?.label,
      kind: existing != null ? existing.kind : covering?.kind,
      note: note ?? existing?.note ?? '',
      takenUtcOffsetMinutes: offsetToStore is int ? offsetToStore : null,
    );
    await db.insert(
      'med_dose',
      {
        'med_key': written.medKey,
        'date': written.date,
        'slot_min': written.slotMin,
        'taken_ts': written.takenTsSeconds,
        'skipped': written.skipped ? 1 : 0,
        'dose_value': written.doseValue,
        'dose_unit': written.doseUnit,
        'label': written.label,
        'kind': written.kind == null ? null : medicationKindWire(written.kind!),
        'note': written.note,
        'updated_at': now.millisecondsSinceEpoch,
        'taken_utc_offset_min': offsetToStore,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return written;
  }

  static Future<List<MedicationPlan>> readPlans(
    Database db, {
    bool activeOnly = true,
  }) async {
    final rows = await db.query('med_def', orderBy: 'label ASC');
    if (rows.isEmpty) return const [];
    final out = <MedicationPlan>[];
    for (final r in rows) {
      final plan = await _planFromHeadRow(db, r);
      if (!activeOnly || plan.active) out.add(plan);
    }
    return out;
  }

  static Future<MedicationPlan> _planFromHeadRow(
    Database db,
    Map<String, Object?> r,
  ) async {
    final key = r['key'];
    final label = r['label'];
    if (key is! String || key.isEmpty || label is! String || label.isEmpty) {
      throw const FormatException('Stored medication plan is unreadable.');
    }
    final kindRaw = r['kind'];
    final kind = kindRaw is String ? parseMedicationKind(kindRaw) : null;
    if (kind == null) {
      throw FormatException(
        'Stored medication plan "$key" has an unreadable kind.',
      );
    }
    final dose = parseMedicationStoredDose(r['dose_value']);
    if (dose.unreadable) {
      throw FormatException(
        'Stored medication plan "$key" has an unreadable dose.',
      );
    }
    final active = parseMedicationActiveFlag(r['active']);
    if (active == null) {
      throw FormatException(
        'Stored medication plan "$key" has an unreadable active flag.',
      );
    }
    final decoded = _decodeScheduleJson(r['schedule_json']);
    if (decoded == null) {
      throw FormatException(
        'Stored medication plan "$key" has an unreadable schedule.',
      );
    }
    final parsed = parseMedicationScheduleList(decoded);
    if (parsed.unreadableCount > 0) {
      throw FormatException(
        'Stored medication plan "$key" has an unreadable schedule.',
      );
    }
    final revs = await revisionsForKey(db, key);
    MedicationPlanRevision? head;
    for (final rev in revs) {
      if (head == null || compareRevisionCover(rev, head) > 0) head = rev;
    }
    if ((head?.scheduleUnreadableCount ?? 0) > 0) {
      throw FormatException(
        'Stored medication plan "$key" has an unreadable schedule.',
      );
    }
    return MedicationPlan(
      key: key,
      name: label,
      doseValue: dose.value,
      doseUnit: _storedUnit(r['dose_unit'] as String?),
      kind: kind,
      note: (r['note'] as String?) ?? '',
      schedule: head?.schedule ?? parsed.slots,
      active: active,
      createdAtMs: parseMedicationInt(r['created_at']),
      revisionId: head?.id ?? 0,
      effectiveTs: head?.effectiveTs ?? (parseMedicationInt(r['created_at']) ?? 0),
      effectiveDate: head?.effectiveDate ?? '',
      effectiveMin: head?.effectiveMin ?? 0,
      origin: head?.origin ?? MedicationPlanOrigin.user,
      scheduleUnreadableCount:
          head?.scheduleUnreadableCount ?? parsed.unreadableCount,
    );
  }

  static Future<MedicationDay> readDay(
    Database db,
    String date, {
    required DateTime now,
    String? zone,
  }) async {
    if (!isMedicationCalendarDay(date)) {
      throw ArgumentError.value(date, 'date', 'Expected a Gregorian YYYY-MM-DD.');
    }
    final loaded = await _allRevisions(db);
    final stored = await _dosesOn(db, date);
    final names = await _headLabels(db);
    final resolved = resolveMedicationDay(
      date: date,
      now: now,
      revisionsByKey: loaded.byKey,
      doses: stored.doses,
      currentNames: names,
      zone: zone,
    );
    return MedicationDay(
      day: date,
      entries: resolved.entries,
      unreadableCount:
          resolved.unreadableCount + loaded.unreadable + stored.unreadable,
    );
  }

  static Future<MedicationHistory> readHistory(
    Database db,
    String fromDay,
    String toDay, {
    required DateTime now,
    String? zone,
  }) async {
    final days = medicationCivilDays(fromDay, toDay).toList();
    final loaded = await _allRevisions(db);
    final stored = await _dosesBetween(db, fromDay, toDay);
    final names = await _headLabels(db);
    final entries = <MedicationDayEntry>[];
    var unreadable = loaded.unreadable + stored.unreadable;
    for (final day in days) {
      final resolved = resolveMedicationDay(
        date: day,
        now: now,
        revisionsByKey: loaded.byKey,
        doses: stored.doses,
        currentNames: names,
        zone: zone,
      );
      entries.addAll(resolved.entries);
      unreadable += resolved.unreadableCount;
    }
    return MedicationHistory(
      fromDay: fromDay,
      toDay: toDay,
      entries: entries,
      unreadableCount: unreadable,
    );
  }

  static Future<MedicationPlanRevision?> coveringRevision(
    DatabaseExecutor db, {
    required String key,
    required String date,
    required int slotMin,
    String? zone,
  }) async {
    final revs = await revisionsForKey(db, key);
    return coveringMedicationRevision(
      revisions: revs,
      date: date,
      slotMin: slotMin,
      zone: zone,
    );
  }

  static Future<List<MedicationPlanRevision>> revisionsForKey(
    DatabaseExecutor db,
    String key,
  ) async {
    final rows = await db.query(
      'med_plan_revision',
      where: 'med_key = ?',
      whereArgs: [key],
      orderBy: 'effective_ts ASC, id ASC',
    );
    return [for (final r in rows) _revisionFromRow(r)];
  }

  /// Upcoming valid wall instants for reminder arming. DST gaps/folds are
  /// omitted rather than shifted. A successful empty list is known-empty
  /// (cancel armed reminders). Unreadable/partial store throws rather than
  /// looking like known-empty.
  static Future<List<({String key, String date, int slotMin, DateTime at})>>
      upcomingReminderInstants(
    Database db, {
    required DateTime now,
    int horizonDays = 3,
    String? zone,
  }) async {
    final out = <({String key, String date, int slotMin, DateTime at})>[];
    for (var i = 0; i < horizonDays; i++) {
      final day = dayLabelOf(DateTime(now.year, now.month, now.day + i));
      if (!isMedicationCalendarDay(day)) {
        throw FormatException('Medication reminder day "$day" is unreadable.');
      }
      final resolved = await readDay(db, day, now: now, zone: zone);
      if (resolved.unreadableCount > 0) {
        throw const FormatException(
          'Medication reminder slots are unreadable.',
        );
      }
      for (final e in resolved.entries) {
        if (e.status != MedicationSlotStatus.upcoming) continue;
        final at = e.scheduledAt;
        if (at == null) continue;
        out.add((key: e.key, date: e.date, slotMin: e.slotMin, at: at));
      }
    }
    return out;
  }

  static Future<Map<String, String>> _headLabels(DatabaseExecutor db) async {
    final rows = await db.query('med_def', columns: ['key', 'label']);
    final out = <String, String>{};
    for (final r in rows) {
      final key = r['key'];
      final label = r['label'];
      if (key is String && key.isNotEmpty && label is String && label.isNotEmpty) {
        out[key] = label;
      }
    }
    return out;
  }

  static Future<({Map<String, List<MedicationPlanRevision>> byKey, int unreadable})>
      _allRevisions(DatabaseExecutor db) async {
    final rows = await db.query(
      'med_plan_revision',
      orderBy: 'med_key ASC, effective_ts ASC, id ASC',
    );
    final out = <String, List<MedicationPlanRevision>>{};
    final failedKeys = <String>{};
    final revisionKeys = <String>{};
    var unreadable = 0;
    for (final r in rows) {
      final key = r['med_key'];
      if (key is String && key.isNotEmpty) revisionKeys.add(key);
      try {
        final rev = _revisionFromRow(r);
        (out[rev.medKey] ??= []).add(rev);
      } on FormatException {
        unreadable++;
        if (key is String && key.isNotEmpty) failedKeys.add(key);
      }
    }
    for (final key in failedKeys) {
      out.remove(key);
    }
    unreadable += await _headRevisionHoles(db, revisionKeys);
    return (byKey: out, unreadable: unreadable);
  }

  /// Heads with no revision row are unreadable covering, not known-empty.
  /// Keys that already have a revision row (even an unreadable one) are not
  /// holes — those are counted when the row fails to parse.
  static Future<int> _headRevisionHoles(
    DatabaseExecutor db,
    Set<String> revisionKeys,
  ) async {
    final heads = await db.query('med_def', columns: ['key']);
    var holes = 0;
    for (final r in heads) {
      final key = r['key'];
      if (key is! String || key.isEmpty || !revisionKeys.contains(key)) {
        holes++;
      }
    }
    return holes;
  }

  static Future<({List<MedicationStoredDose> doses, int unreadable})> _dosesOn(
    DatabaseExecutor db,
    String date,
  ) async {
    final rows = await db.query(
      'med_dose',
      where: 'date = ?',
      whereArgs: [date],
    );
    return _parseDoseRows(rows);
  }

  static Future<({List<MedicationStoredDose> doses, int unreadable})>
      _dosesBetween(DatabaseExecutor db, String fromDay, String toDay) async {
    final rows = await db.query(
      'med_dose',
      where: 'date >= ? AND date <= ?',
      whereArgs: [fromDay, toDay],
    );
    return _parseDoseRows(rows);
  }

  static ({List<MedicationStoredDose> doses, int unreadable}) _parseDoseRows(
    List<Map<String, Object?>> rows,
  ) {
    final out = <MedicationStoredDose>[];
    var unreadable = 0;
    for (final r in rows) {
      try {
        out.add(_doseFromRow(r));
      } on FormatException {
        unreadable++;
      }
    }
    return (doses: out, unreadable: unreadable);
  }
}

Future<void> _snapshotHeadRevision(
  DatabaseExecutor db,
  Map<String, Object?> row, {
  required DateTime now,
}) async {
  final key = row['key'] as String;
  final kindRaw = row['kind'];
  final kindWire = kindRaw is String
      ? kindRaw
      : (kindRaw == null ? '' : kindRaw.toString());
  final activeParsed = parseMedicationInt(row['active']);
  final Object activeWire;
  if (activeParsed != null) {
    activeWire = activeParsed;
  } else if (row['active'] is num) {
    activeWire = row['active'] as num;
  } else {
    activeWire = 2;
  }
  final ts = now.millisecondsSinceEpoch;
  await db.insert('med_plan_revision', {
    'med_key': key,
    'effective_ts': ts,
    'effective_date': dayLabelOf(now),
    'effective_min': now.hour * 60 + now.minute,
    'label': (row['label'] as String?) ?? key,
    'dose_value': row['dose_value'],
    'dose_unit': _storedUnit((row['dose_unit'] as String?) ?? ''),
    'kind': kindWire,
    'note': (row['note'] as String?) ?? '',
    'schedule_json': (row['schedule_json'] as String?) ?? '[]',
    'active': activeWire,
    'origin': medicationPlanOriginWire(MedicationPlanOrigin.migrated),
  });
}

Future<int> _insertRevision(
  DatabaseExecutor db, {
  required String key,
  required String label,
  required double? doseValue,
  required String? doseUnit,
  required String kind,
  required String note,
  required String scheduleJson,
  required bool active,
  required MedicationPlanOrigin origin,
  required DateTime now,
}) async {
  final ts = now.millisecondsSinceEpoch;
  return db.insert('med_plan_revision', {
    'med_key': key,
    'effective_ts': ts,
    'effective_date': dayLabelOf(now),
    'effective_min': now.hour * 60 + now.minute,
    'label': label,
    'dose_value': doseValue,
    'dose_unit': doseUnit,
    'kind': kind,
    'note': note,
    'schedule_json': scheduleJson,
    'active': active ? 1 : 0,
    'origin': medicationPlanOriginWire(origin),
  });
}

MedicationPlanRevision _revisionFromRow(Map<String, Object?> r) {
  final id = parseMedicationInt(r['id']);
  final ts = parseMedicationInt(r['effective_ts']);
  final min = parseMedicationInt(r['effective_min']);
  final date = r['effective_date'];
  final key = r['med_key'];
  final label = r['label'];
  if (id == null ||
      ts == null ||
      min == null ||
      date is! String ||
      !isMedicationCalendarDay(date) ||
      key is! String ||
      key.isEmpty ||
      label is! String ||
      label.isEmpty) {
    throw const FormatException('Stored medication revision is unreadable.');
  }
  final kindRaw = r['kind'];
  final kind = kindRaw is String ? parseMedicationKind(kindRaw) : null;
  if (kind == null) {
    throw const FormatException(
      'Stored medication revision kind is unreadable.',
    );
  }
  final active = parseMedicationActiveFlag(r['active']);
  if (active == null) {
    throw const FormatException(
      'Stored medication revision active flag is unreadable.',
    );
  }
  final dose = parseMedicationStoredDose(r['dose_value']);
  if (dose.unreadable) {
    throw const FormatException(
      'Stored medication revision dose is unreadable.',
    );
  }
  final parsed = parseMedicationScheduleList(
    _decodeScheduleJson(r['schedule_json']),
  );
  return MedicationPlanRevision(
    id: id,
    medKey: key,
    effectiveTs: ts,
    effectiveDate: date,
    effectiveMin: min,
    label: label,
    doseValue: dose.value,
    doseUnit: _storedUnit(r['dose_unit'] as String?),
    kind: kind,
    note: (r['note'] as String?) ?? '',
    schedule: parsed.slots,
    active: active,
    origin: parseMedicationPlanOrigin(r['origin'] as String?),
    scheduleUnreadableCount: parsed.unreadableCount,
  );
}

MedicationStoredDose _doseFromRow(Map<String, Object?> r) {
  final key = r['med_key'];
  final date = r['date'];
  final slot = parseMedicationInt(r['slot_min']);
  if (key is! String ||
      key.isEmpty ||
      date is! String ||
      !isMedicationCalendarDay(date) ||
      slot == null ||
      slot < 0 ||
      slot > 1439) {
    throw const FormatException('Stored medication dose is unreadable.');
  }
  final takenRaw = r['taken_ts'];
  int? takenTs;
  if (takenRaw != null) {
    takenTs = parseMedicationInt(takenRaw);
    if (takenTs == null) {
      throw const FormatException(
        'Stored medication taken time is unreadable.',
      );
    }
  }
  final skippedRaw = r['skipped'];
  final bool skipped;
  if (skippedRaw == null) {
    skipped = false;
  } else {
    final flag = parseMedicationInt(skippedRaw);
    if (flag == 0) {
      skipped = false;
    } else if (flag == 1) {
      skipped = true;
    } else {
      throw const FormatException(
        'Stored medication skipped flag is unreadable.',
      );
    }
  }
  final dose = parseMedicationStoredDose(r['dose_value']);
  if (dose.unreadable) {
    throw const FormatException('Stored medication dose value is unreadable.');
  }
  final offsetRaw = r['taken_utc_offset_min'];
  int? offset;
  if (offsetRaw != null) {
    offset = parseMedicationInt(offsetRaw);
    if (offset == null) {
      throw const FormatException(
        'Stored medication UTC offset is unreadable.',
      );
    }
  }
  final kindRaw = r['kind'];
  MedicationKind? kind;
  if (kindRaw != null && kindRaw != '') {
    kind = kindRaw is String ? parseMedicationKind(kindRaw) : null;
    if (kind == null) {
      throw const FormatException('Stored medication dose kind is unreadable.');
    }
  }
  return MedicationStoredDose(
    medKey: key,
    date: date,
    slotMin: slot,
    takenTsSeconds: takenTs,
    skipped: skipped,
    doseValue: dose.value,
    doseUnit: r.containsKey('dose_unit')
        ? _storedUnit(r['dose_unit'] as String?)
        : null,
    label: r['label'] as String?,
    kind: kind,
    note: (r['note'] as String?) ?? '',
    takenUtcOffsetMinutes: offset,
  );
}
