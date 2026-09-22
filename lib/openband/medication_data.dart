// Typed medication boundary for OpenBand. Repositories decode storage here;
// callers never see SQLite maps. No diagnosis, interaction check, or default
// dosage lives in this file.

import 'package:uuid/uuid.dart';

import '../data/day_label.dart';
import 'time.dart';

enum MedicationKind { medication, supplement }

enum MedicationSlotStatus { unknown, taken, skipped, upcoming, unavailable }

enum MedicationEntryAnswer { taken, skipped, clear }

enum MedicationPlanOrigin { user, migrated }

/// Civil `YYYY-MM-DD` that exists on the Gregorian calendar.
bool isMedicationCalendarDay(String day) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) return false;
  final p = day.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  return d.year == p[0] && d.month == p[1] && d.day == p[2];
}

String newMedicationPlanId() => const Uuid().v4();

String medicationTimeLabel(int minuteOfDay) {
  final h = (minuteOfDay ~/ 60).toString().padLeft(2, '0');
  final m = (minuteOfDay % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// Wall-clock instant for a civil slot, or null when the local/zoned time is
/// nonexistent or ambiguous. Never midnight-plus-elapsed-seconds.
DateTime? medicationSlotInstant(
  String date,
  int slotMin, {
  String? zone,
  DateTime? previous,
}) {
  if (!isMedicationCalendarDay(date)) return null;
  if (slotMin < 0 || slotMin > 1439) return null;
  final p = date.split('-').map(int.parse).toList();
  return parseRecordedTime(
    DateTime(p[0], p[1], p[2]),
    medicationTimeLabel(slotMin),
    zone: zone,
    previous: previous,
  );
}

class MedicationScheduleSlot {
  const MedicationScheduleSlot({
    required this.minuteOfDay,
    this.weekdays = const [],
  });

  /// 0–1439. Empty [weekdays] means every civil weekday.
  final int minuteOfDay;
  final List<int> weekdays;

  bool onDay(DateTime d) => weekdays.isEmpty || weekdays.contains(d.weekday);

  Map<String, Object?> toJson() => {
        'minute_of_day': minuteOfDay,
        'days': weekdays,
      };
}

/// One schedule entry decoded from storage. [unreadable] rows are counted, not
/// repaired into midnight or default days.
class MedicationScheduleParse {
  const MedicationScheduleParse._(this.slot, this.unreadable);
  const MedicationScheduleParse.ok(MedicationScheduleSlot slot)
      : this._(slot, false);
  const MedicationScheduleParse.unreadable() : this._(null, true);

  final MedicationScheduleSlot? slot;
  final bool unreadable;
}

/// Whole finite integer, or null when missing/non-finite/non-integral.
/// Check [num.isFinite] before [num.roundToDouble] / [num.toInt] — Infinity
/// equals its own `roundToDouble` and `toInt` throws.
int? parseMedicationInt(Object? raw) {
  if (raw is! num || !raw.isFinite) return null;
  if (raw != raw.roundToDouble()) return null;
  return raw.toInt();
}

/// Stored optional dose. Null is unknown. Non-finite is unreadable, not a value.
({double? value, bool unreadable}) parseMedicationStoredDose(Object? raw) {
  if (raw == null) return (value: null, unreadable: false);
  if (raw is! num || !raw.isFinite) return (value: null, unreadable: true);
  return (value: raw.toDouble(), unreadable: false);
}

/// `0` / `1` only. Null or any other number is unreadable, not a default.
bool? parseMedicationActiveFlag(Object? raw) {
  final n = parseMedicationInt(raw);
  if (n == 0) return false;
  if (n == 1) return true;
  return null;
}

/// UTC-minute floor of a recorded epoch. Used for same-civil-minute covering
/// so 08:00:30 cannot rewrite 08:00 without resolving the slot in a later zone.
int medicationRecordedMinuteStartMs(int epochMs) => epochMs - (epochMs % 60000);

MedicationScheduleParse parseMedicationScheduleEntry(Object? raw) {
  if (raw is! Map) return const MedicationScheduleParse.unreadable();
  final j = raw.cast<Object?, Object?>();
  final minute = parseMedicationInt(j['minute_of_day']);
  if (minute == null || minute < 0 || minute > 1439) {
    return const MedicationScheduleParse.unreadable();
  }
  if (!j.containsKey('days') || j['days'] is! List) {
    return const MedicationScheduleParse.unreadable();
  }
  final days = <int>[];
  for (final d in j['days'] as List) {
    final n = parseMedicationInt(d);
    if (n == null || n < 1 || n > 7) {
      return const MedicationScheduleParse.unreadable();
    }
    days.add(n);
  }
  return MedicationScheduleParse.ok(
    MedicationScheduleSlot(minuteOfDay: minute, weekdays: days),
  );
}

class MedicationScheduleJsonParse {
  const MedicationScheduleJsonParse({
    required this.slots,
    required this.unreadableCount,
  });
  final List<MedicationScheduleSlot> slots;
  final int unreadableCount;
}

MedicationScheduleJsonParse parseMedicationScheduleList(Object? raw) {
  if (raw is! List) {
    return const MedicationScheduleJsonParse(slots: [], unreadableCount: 1);
  }
  final slots = <MedicationScheduleSlot>[];
  var unreadable = 0;
  for (final e in raw) {
    final p = parseMedicationScheduleEntry(e);
    if (p.unreadable || p.slot == null) {
      unreadable++;
      continue;
    }
    slots.add(p.slot!);
  }
  return MedicationScheduleJsonParse(slots: slots, unreadableCount: unreadable);
}

MedicationKind? parseMedicationKind(String? raw) {
  switch (raw) {
    case 'medication':
      return MedicationKind.medication;
    case 'supplement':
      return MedicationKind.supplement;
    default:
      return null;
  }
}

String medicationKindWire(MedicationKind kind) => kind.name;

class MedicationPlanDraft {
  const MedicationPlanDraft({
    required this.create,
    this.key,
    required this.name,
    this.doseValue,
    this.doseUnit,
    this.kind = MedicationKind.medication,
    this.note = '',
    this.schedule = const [],
    this.active = true,
  });

  /// True inserts a new identity. False updates [key] and refuses if missing.
  final bool create;
  final String? key;
  final String name;
  final double? doseValue;
  final String? doseUnit;
  final MedicationKind kind;
  final String note;
  final List<MedicationScheduleSlot> schedule;
  final bool active;
}

class MedicationPlan {
  const MedicationPlan({
    required this.key,
    required this.name,
    this.doseValue,
    this.doseUnit,
    required this.kind,
    this.note = '',
    this.schedule = const [],
    required this.active,
    this.createdAtMs,
    required this.revisionId,
    required this.effectiveTs,
    required this.effectiveDate,
    required this.effectiveMin,
    required this.origin,
    this.scheduleUnreadableCount = 0,
  });

  final String key;
  final String name;
  final double? doseValue;
  final String? doseUnit;
  final MedicationKind kind;
  final String note;
  final List<MedicationScheduleSlot> schedule;
  final bool active;
  final int? createdAtMs;
  final int revisionId;
  final int effectiveTs;
  final String effectiveDate;
  final int effectiveMin;
  final MedicationPlanOrigin origin;
  final int scheduleUnreadableCount;
}

class MedicationEntryDraft {
  const MedicationEntryDraft({
    required this.key,
    required this.date,
    required this.slotMin,
    required this.answer,
    this.takenAt,
    this.note,
  });

  final String key;
  final String date;
  final int slotMin;
  final MedicationEntryAnswer answer;
  final DateTime? takenAt;
  final String? note;
}

class MedicationDayEntry {
  const MedicationDayEntry({
    required this.key,
    required this.date,
    required this.slotMin,
    required this.status,
    this.scheduledAt,
    this.takenAt,
    this.takenUtcOffsetMinutes,
    this.snapshotLabel,
    this.snapshotDoseValue,
    this.snapshotDoseUnit,
    this.snapshotKind,
    this.currentName,
    this.note = '',
    this.orphan = false,
  });

  final String key;
  final String date;
  final int slotMin;
  final MedicationSlotStatus status;
  final DateTime? scheduledAt;
  final DateTime? takenAt;
  final int? takenUtcOffsetMinutes;

  /// Frozen at first write of this dose row. Null is unknown, never current.
  final String? snapshotLabel;
  final double? snapshotDoseValue;
  final String? snapshotDoseUnit;
  final MedicationKind? snapshotKind;

  /// Live head name, tagged separately. Not a historical claim.
  final String? currentName;
  final String note;
  final bool orphan;

  String get timeLabel => medicationTimeLabel(slotMin);
}

class MedicationDay {
  const MedicationDay({
    required this.day,
    this.entries = const [],
    this.unreadableCount = 0,
  });

  final String day;
  final List<MedicationDayEntry> entries;
  final int unreadableCount;
}

class MedicationHistory {
  const MedicationHistory({
    required this.fromDay,
    required this.toDay,
    this.entries = const [],
    this.unreadableCount = 0,
  });

  final String fromDay;
  final String toDay;
  final List<MedicationDayEntry> entries;
  final int unreadableCount;
}

/// Write committed. [remindersFailed] means the durable row is already stored
/// and the caller must not retry the write — only reminder refresh.
class MedicationMutationResult {
  const MedicationMutationResult.saved({this.plan, this.entry})
      : committed = true,
        remindersFailed = false;

  const MedicationMutationResult.savedRemindersFailed({this.plan, this.entry})
      : committed = true,
        remindersFailed = true;

  final bool committed;
  final bool remindersFailed;
  final MedicationPlan? plan;
  final MedicationDayEntry? entry;
}

class MedicationPlanRevision {
  const MedicationPlanRevision({
    required this.id,
    required this.medKey,
    required this.effectiveTs,
    required this.effectiveDate,
    required this.effectiveMin,
    required this.label,
    this.doseValue,
    this.doseUnit,
    required this.kind,
    this.note = '',
    required this.schedule,
    required this.active,
    required this.origin,
    this.scheduleUnreadableCount = 0,
  });

  final int id;
  final String medKey;
  final int effectiveTs;
  final String effectiveDate;
  final int effectiveMin;
  final String label;
  final double? doseValue;
  final String? doseUnit;
  final MedicationKind kind;
  final String note;
  final List<MedicationScheduleSlot> schedule;
  final bool active;
  final MedicationPlanOrigin origin;
  final int scheduleUnreadableCount;
}

class MedicationStoredDose {
  const MedicationStoredDose({
    required this.medKey,
    required this.date,
    required this.slotMin,
    this.takenTsSeconds,
    this.skipped = false,
    this.doseValue,
    this.doseUnit,
    this.label,
    this.kind,
    this.note = '',
    this.takenUtcOffsetMinutes,
  });

  final String medKey;
  final String date;
  final int slotMin;
  final int? takenTsSeconds;
  final bool skipped;
  final double? doseValue;
  final String? doseUnit;
  final String? label;
  final MedicationKind? kind;
  final String note;
  final int? takenUtcOffsetMinutes;
}

class MedicationDayResolve {
  const MedicationDayResolve({
    required this.entries,
    required this.unreadableCount,
  });
  final List<MedicationDayEntry> entries;
  final int unreadableCount;
}

void requireMedicationPlanDraft(MedicationPlanDraft draft) {
  if (draft.create) {
    if (draft.key != null && draft.key!.trim().isEmpty) {
      throw ArgumentError.value(draft.key, 'key', 'Create key must be non-empty when set.');
    }
  } else {
    final key = draft.key?.trim() ?? '';
    if (key.isEmpty) {
      throw ArgumentError.value(draft.key, 'key', 'Update requires a plan key.');
    }
  }
  final name = draft.name.trim();
  if (name.isEmpty) {
    throw ArgumentError.value(draft.name, 'name', 'A medication needs a name.');
  }
  final dose = draft.doseValue;
  if (dose != null && (!dose.isFinite || dose <= 0)) {
    throw ArgumentError.value(
      dose,
      'doseValue',
      'Dose must be finite and positive when set.',
    );
  }
  final unit = draft.doseUnit;
  if (unit != null && unit.trim().isEmpty) {
    // Empty string is unknown, same as null. Reject only whitespace-as-unit.
    if (unit.isNotEmpty) {
      throw ArgumentError.value(unit, 'doseUnit', 'Unit is unknown when empty.');
    }
  }
  for (final s in draft.schedule) {
    if (s.minuteOfDay < 0 || s.minuteOfDay > 1439) {
      throw ArgumentError.value(s.minuteOfDay, 'minuteOfDay');
    }
    for (final d in s.weekdays) {
      if (d < 1 || d > 7) {
        throw ArgumentError.value(d, 'weekdays');
      }
    }
  }
}

void requireMedicationEntryDraft(MedicationEntryDraft draft, {required DateTime now}) {
  if (draft.key.trim().isEmpty) {
    throw ArgumentError.value(draft.key, 'key');
  }
  if (!isMedicationCalendarDay(draft.date)) {
    throw ArgumentError.value(draft.date, 'date', 'Expected a Gregorian YYYY-MM-DD.');
  }
  if (draft.slotMin < 0 || draft.slotMin > 1439) {
    throw ArgumentError.value(draft.slotMin, 'slotMin');
  }
  if (draft.answer == MedicationEntryAnswer.taken) {
    final at = draft.takenAt ?? now;
    if (at.isAfter(now)) {
      throw ArgumentError.value(at, 'takenAt', 'Taken time cannot be in the future.');
    }
  }
}

MedicationPlanOrigin parseMedicationPlanOrigin(String? raw) {
  return raw == 'migrated'
      ? MedicationPlanOrigin.migrated
      : MedicationPlanOrigin.user;
}

String medicationPlanOriginWire(MedicationPlanOrigin origin) => origin.name;

int compareRevisionCover(MedicationPlanRevision a, MedicationPlanRevision b) {
  final ts = a.effectiveTs.compareTo(b.effectiveTs);
  if (ts != 0) return ts;
  return a.id.compareTo(b.id);
}

/// Historical floating wall slots use the revision's recorded civil date and
/// minute, not a slot epoch resolved in the caller's current zone (travel
/// would rewrite covering). Same recorded minute uses the saved epoch against
/// that minute's start so 08:00:30 does not cover 08:00. [zone] is accepted
/// for existing callers and does not change covering.
bool revisionCoversSlot(
  MedicationPlanRevision rev,
  String date,
  int slotMin, {
  String? zone,
}) {
  final cmp = rev.effectiveDate.compareTo(date);
  if (cmp < 0) return true;
  if (cmp > 0) return false;
  if (rev.effectiveMin < slotMin) return true;
  if (rev.effectiveMin > slotMin) return false;
  return rev.effectiveTs <= medicationRecordedMinuteStartMs(rev.effectiveTs);
}

MedicationPlanRevision? coveringMedicationRevision({
  required List<MedicationPlanRevision> revisions,
  required String date,
  required int slotMin,
  String? zone,
}) {
  MedicationPlanRevision? best;
  for (final r in revisions) {
    if (!revisionCoversSlot(r, date, slotMin, zone: zone)) continue;
    if (best == null || compareRevisionCover(r, best) > 0) best = r;
  }
  return best;
}

MedicationSlotStatus medicationStatusFor({
  required MedicationStoredDose? dose,
  required DateTime? scheduledAt,
  required String date,
  required int slotMin,
  required DateTime now,
}) {
  if (dose != null) {
    if (dose.takenTsSeconds != null) return MedicationSlotStatus.taken;
    if (dose.skipped) return MedicationSlotStatus.skipped;
    return MedicationSlotStatus.unknown;
  }
  if (scheduledAt == null) return MedicationSlotStatus.unavailable;
  final nowDay = dayLabelOf(now);
  if (date.compareTo(nowDay) > 0) return MedicationSlotStatus.upcoming;
  if (date.compareTo(nowDay) < 0) return MedicationSlotStatus.unknown;
  final nowMin = now.hour * 60 + now.minute;
  if (slotMin <= nowMin) return MedicationSlotStatus.unknown;
  return MedicationSlotStatus.upcoming;
}

MedicationDayResolve resolveMedicationDay({
  required String date,
  required DateTime now,
  required Map<String, List<MedicationPlanRevision>> revisionsByKey,
  required List<MedicationStoredDose> doses,
  Map<String, String> currentNames = const {},
  String? zone,
}) {
  if (!isMedicationCalendarDay(date)) {
    throw ArgumentError.value(date, 'date', 'Expected a Gregorian YYYY-MM-DD.');
  }
  final p = date.split('-').map(int.parse).toList();
  final civil = DateTime(p[0], p[1], p[2]);
  var unreadable = 0;
  final keys = <String>{
    ...revisionsByKey.keys,
    for (final d in doses) d.medKey,
  };
  final doseByKeySlot = <String, MedicationStoredDose>{};
  for (final d in doses) {
    if (d.date != date) continue;
    if (d.slotMin < 0 || d.slotMin > 1439) {
      unreadable++;
      continue;
    }
    doseByKeySlot['${d.medKey}|${d.slotMin}'] = d;
  }

  final entries = <MedicationDayEntry>[];
  for (final key in keys) {
    final revs = revisionsByKey[key] ?? const <MedicationPlanRevision>[];
    for (final r in revs) {
      unreadable += r.scheduleUnreadableCount;
    }
    final candidateMins = <int>{
      for (final r in revs)
        for (final s in r.schedule) s.minuteOfDay,
      for (final d in doses)
        if (d.medKey == key && d.date == date && d.slotMin >= 0 && d.slotMin <= 1439)
          d.slotMin,
    };
    for (final slotMin in candidateMins) {
      final covering = coveringMedicationRevision(
        revisions: revs,
        date: date,
        slotMin: slotMin,
        zone: zone,
      );
      var generated = false;
      if (covering != null && covering.active) {
        for (final s in covering.schedule) {
          if (s.minuteOfDay == slotMin && s.onDay(civil)) {
            generated = true;
            break;
          }
        }
      }
      final dose = doseByKeySlot['$key|$slotMin'];
      if (!generated && dose == null) continue;
      final scheduledAt = medicationSlotInstant(date, slotMin, zone: zone);
      final takenSeconds = dose?.takenTsSeconds;
      final takenAt = takenSeconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(takenSeconds * 1000);
      entries.add(
        MedicationDayEntry(
          key: key,
          date: date,
          slotMin: slotMin,
          status: medicationStatusFor(
            dose: dose,
            scheduledAt: generated ? scheduledAt : (dose == null ? null : scheduledAt),
            date: date,
            slotMin: slotMin,
            now: now,
          ),
          scheduledAt: scheduledAt,
          takenAt: takenAt,
          takenUtcOffsetMinutes: dose?.takenUtcOffsetMinutes,
          snapshotLabel: dose != null ? dose.label : covering?.label,
          snapshotDoseValue: dose != null ? dose.doseValue : covering?.doseValue,
          snapshotDoseUnit: dose != null ? dose.doseUnit : covering?.doseUnit,
          snapshotKind: dose != null ? dose.kind : covering?.kind,
          currentName: currentNames[key],
          note: dose?.note ?? '',
          orphan: !generated,
        ),
      );
    }
  }
  entries.sort((a, b) {
    final t = a.slotMin.compareTo(b.slotMin);
    if (t != 0) return t;
    return a.key.compareTo(b.key);
  });
  return MedicationDayResolve(entries: entries, unreadableCount: unreadable);
}

/// Inclusive civil-day walk. Does not assume 86400-second days.
Iterable<String> medicationCivilDays(String fromDay, String toDay) sync* {
  if (!isMedicationCalendarDay(fromDay)) {
    throw ArgumentError.value(fromDay, 'fromDay');
  }
  if (!isMedicationCalendarDay(toDay)) {
    throw ArgumentError.value(toDay, 'toDay');
  }
  if (fromDay.compareTo(toDay) > 0) {
    throw ArgumentError.value(toDay, 'toDay', 'Range end precedes start.');
  }
  var p = fromDay.split('-').map(int.parse).toList();
  var cursor = DateTime(p[0], p[1], p[2]);
  final endParts = toDay.split('-').map(int.parse).toList();
  final end = DateTime(endParts[0], endParts[1], endParts[2]);
  while (!cursor.isAfter(end)) {
    yield dayLabelOf(cursor);
    cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
  }
}
