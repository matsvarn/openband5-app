// Dated journal_metric.weight_kg history. Repositories decode storage here.
// Journal entries only — not profile weight, metric_series, day_result, or
// NightScalar. No fabricated samples, goals, or measured/imported source.

import '../data/day_label.dart';
import '../data/journal_fields.dart';

const Set<int> kWeightHistoryWindows = {7, 30, 90};

const String kWeightJournalField = 'weight_kg';

/// Paper fixture nights ending 2026-09-15 from
/// `docs/openband5/assets/fixtures/weight-history.json`.
const String kWeightPaperEndDay = '2026-09-15';

const List<String> kWeightPaperDates = [
  '2026-09-09',
  '2026-09-10',
  '2026-09-11',
  '2026-09-12',
  '2026-09-13',
  '2026-09-14',
  '2026-09-15',
];

const List<double> kWeightPaperEnteredKg = [75.4, 75.2, 75, 74.9, 75.1, 75, 75];

const List<double> kWeightPaperEwmaKg = [
  75.4,
  75.38114473285279,
  75.34521180405432,
  75.30323886654162,
  75.28407825092492,
  75.2572963943654,
  75.23303943310651,
];

/// One stored `journal_metric.weight_kg` row, still uninterpreted.
class WeightStoredRow {
  const WeightStoredRow({
    required this.date,
    required this.value,
    this.updatedAt,
    this.atMinuteOfDay,
  });

  final Object? date;
  final Object? value;
  final Object? updatedAt;
  final Object? atMinuteOfDay;
}

/// One interpretable journal weight entry.
///
/// [value] is the persisted raw number, including 0 and out-of-entry-range
/// finite values. It is never rewritten. [updatedAt] is the stored revision
/// or null when the column is absent — never fabricated as 0.
class WeightEntry {
  const WeightEntry({
    required this.day,
    required this.value,
    this.updatedAt,
    this.atMinuteOfDay,
  });

  final String day;
  final double value;
  final int? updatedAt;
  final int? atMinuteOfDay;

  /// Finite kg in the existing journal entry range `(0, 400]`. Persisted
  /// finite values outside that range remain editable entries, but do not
  /// contribute to [weightTrendEwma].
  bool get usableForTrend =>
      value > 0 && value <= kJournalFieldsByKey[kWeightJournalField]!.max;

  @override
  bool operator ==(Object other) =>
      other is WeightEntry &&
      other.day == day &&
      other.value == value &&
      other.updatedAt == updatedAt &&
      other.atMinuteOfDay == atMinuteOfDay;

  @override
  int get hashCode => Object.hash(day, value, updatedAt, atMinuteOfDay);
}

/// Bounded civil-day journal weight history ending on [endDay].
class WeightHistory {
  const WeightHistory({
    required this.endDay,
    required this.days,
    required this.entries,
    this.latest,
    required this.trend,
    this.unreadableCount = 0,
    this.invalidCount = 0,
  });

  final String endDay;

  /// Requested window length: 7, 30, or 90.
  final int days;

  /// Visible-window journal entries, newest first. Gaps are omitted, not
  /// invented. Includes stored values that are not trend-usable.
  final List<WeightEntry> entries;

  /// Newest interpretable journal entry on or before [endDay], even when that
  /// date precedes the visible window.
  final WeightEntry? latest;

  /// Oldest-first window slots. Null when that civil day has no trend-usable
  /// entry. Length is [days]. Same-date values are invariant across 7/30/90
  /// because EWMA is computed over every usable reading ≤ [endDay].
  final List<double?> trend;

  /// Weight rows that could not be interpreted as a civil-day journal entry,
  /// including nonfinite values.
  final int unreadableCount;

  /// Interpretable finite entries on or before [endDay] that are outside the
  /// journal entry range and therefore excluded from the trend.
  final int invalidCount;

  List<String> get window => weightDaysEnding(endDay, days);

  @override
  bool operator ==(Object other) =>
      other is WeightHistory &&
      other.endDay == endDay &&
      other.days == days &&
      _sameEntries(other.entries, entries) &&
      other.latest == latest &&
      _sameTrend(other.trend, trend) &&
      other.unreadableCount == unreadableCount &&
      other.invalidCount == invalidCount;

  @override
  int get hashCode => Object.hash(
    endDay,
    days,
    Object.hashAll(entries),
    latest,
    Object.hashAll(trend),
    unreadableCount,
    invalidCount,
  );
}

void requireWeightHistoryDay(String day, [String name = 'endDay']) {
  if (!isJournalDayId(day)) {
    throw ArgumentError.value(day, name, 'Expected YYYY-MM-DD.');
  }
}

void requireWeightHistoryDays(int days) {
  if (!kWeightHistoryWindows.contains(days)) {
    throw ArgumentError.value(days, 'days', 'Expected 7, 30, or 90.');
  }
}

/// Civil-calendar window ending on [endDay], oldest first. DST-safe: steps
/// local Y-M-D, never 86400-second arithmetic.
List<String> weightDaysEnding(String endDay, int days) {
  requireWeightHistoryDay(endDay);
  requireWeightHistoryDays(days);
  final p = endDay.split('-').map(int.parse).toList();
  return [
    for (var i = days - 1; i >= 0; i--)
      dayLabelOf(DateTime(p[0], p[1], p[2] - i)),
  ];
}

/// Decode stored rows into a bounded history. Valid future dates relative to
/// [endDay] are omitted. Uninterpretable rows increment [WeightHistory.unreadableCount].
///
/// Trend uses [weightTrendEwma] as-is over every usable reading on or before
/// [endDay]. That helper interprets the parsed local Y/M/D as civil coordinates
/// and normalizes those coordinates to UTC before measuring date gaps. Civil
/// spacing is not reimplemented here. Out-of-range values must not be passed in.
WeightHistory buildWeightHistory({
  required String endDay,
  required int days,
  required Iterable<WeightStoredRow> rows,
}) {
  requireWeightHistoryDay(endDay);
  requireWeightHistoryDays(days);
  final window = weightDaysEnding(endDay, days);
  final inWindow = window.toSet();

  var unreadableCount = 0;
  var invalidCount = 0;
  final byDay = <String, WeightEntry>{};
  for (final row in rows) {
    final day = row.date;
    if (day is String && isJournalDayId(day) && day.compareTo(endDay) > 0) {
      continue;
    }
    final entry = interpretWeightRow(row);
    if (entry == null) {
      unreadableCount++;
      continue;
    }
    if (!entry.usableForTrend) invalidCount++;
    byDay[entry.day] = entry;
  }

  final chronological = byDay.keys.toList()..sort();
  final latest = chronological.isEmpty ? null : byDay[chronological.last];
  final entries = [
    for (var i = chronological.length - 1; i >= 0; i--)
      if (inWindow.contains(chronological[i])) byDay[chronological[i]]!,
  ];

  final ewma = weightTrendEwma({
    for (final day in chronological)
      if (byDay[day]!.usableForTrend) day: byDay[day]!.value,
  });
  final trend = [for (final day in window) ewma[day]];

  return WeightHistory(
    endDay: endDay,
    days: days,
    entries: List.unmodifiable(entries),
    latest: latest,
    trend: List.unmodifiable(trend),
    unreadableCount: unreadableCount,
    invalidCount: invalidCount,
  );
}

/// Null when [row] cannot be read as a civil-day journal weight.
WeightEntry? interpretWeightRow(WeightStoredRow row) {
  final date = row.date;
  if (date is! String || !isJournalDayId(date)) return null;
  final raw = row.value;
  if (raw is! num) return null;
  final value = raw.toDouble();
  if (!value.isFinite) return null;
  return WeightEntry(
    day: date,
    value: value,
    updatedAt: _storedInteger(row.updatedAt, min: 1),
    atMinuteOfDay: _storedInteger(
      row.atMinuteOfDay,
      max: Duration.minutesPerDay - 1,
    ),
  );
}

/// Stored metadata is optional. Corrupt/fractional values stay unknown rather
/// than being rounded or throwing from `num.toInt()`.
int? _storedInteger(Object? raw, {int min = 0, int? max}) {
  if (raw is int) {
    if (raw < min ||
        raw > 9223372036854775807 ||
        (max != null && raw > max)) {
      return null;
    }
    return raw;
  }
  if (raw is! double || !raw.isFinite || raw < min) return null;
  if (raw != raw.truncateToDouble()) return null;
  if (max != null && raw > max) return null;
  // Avoid a conversion outside the signed 64-bit range used by SQLite.
  if (raw >= 9223372036854775808.0) return null;
  return raw.toInt();
}

bool _sameEntries(List<WeightEntry> a, List<WeightEntry> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameTrend(List<double?> a, List<double?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (x == null && y == null) continue;
    if (x == null || y == null || x != y) return false;
  }
  return true;
}
