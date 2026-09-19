// The numeric half of a journal entry — the vocabulary, not the storage.
//
// `journal` holds a tag set and a note, which can only ever answer "did this
// happen today". These fields carry a NUMBER, and the number is usually the
// question: one coffee and five coffees are not the same day, and a tag cannot
// tell them apart.
//
// Built-in fields live in [kJournalFields] as a plain constant table, the same
// shape as the workout-type table — extend it HERE, never with a local map in
// a screen. User-invented fields carry their own [JournalFieldSpec] loaded
// from the database, so a custom field behaves exactly like a built-in one
// everywhere downstream.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// What a field measures, which decides how it is entered and read back.
enum JournalFieldKind {
  /// A subjective 1–5 self-report (mood, sleep quality). Ordinal: the gap
  /// between 3 and 4 is not claimed to equal the gap between 4 and 5, which is
  /// exactly why the correlation over these is rank-based.
  rating,

  /// A physical quantity with a unit (ml, mg, units).
  dose,

  /// Minutes.
  duration,

  /// Stored 1 (yes) or 0 (no). An ABSENT row is "open", never "no" — the
  /// distinction B29 requires; a missing answer must not read as a denial.
  yesNo,
}

/// One day's value for one field.
@immutable
class JournalMetricValue {
  const JournalMetricValue(this.value, {this.atMinuteOfDay});

  /// The day's total for a dose, or the day's single reading for a rating.
  final double value;

  /// Local minutes past midnight for the LATEST occurrence, or null when the
  /// field has no meaningful time. Held because when a dose landed often
  /// matters more than how big it was — the sleep-relevant fact about caffeine
  /// is the last cup, not the total.
  final int? atMinuteOfDay;

  @override
  bool operator ==(Object other) =>
      other is JournalMetricValue &&
      other.value == value &&
      other.atMinuteOfDay == atMinuteOfDay;

  @override
  int get hashCode => Object.hash(value, atMinuteOfDay);

  @override
  String toString() => 'JournalMetricValue($value, at: $atMinuteOfDay)';
}

@immutable
class JournalFieldSpec {
  const JournalFieldSpec({
    required this.key,
    required this.label,
    required this.kind,
    required this.unit,
    required this.max,
    required this.step,
    this.hasTime = false,
    this.custom = false,
    this.hidden = false,
  });

  /// Stored `field` value. Lowercase and stable — renaming one orphans its
  /// history, so labels change freely and keys never do.
  final String key;
  final String label;
  final JournalFieldKind kind;

  /// Shown after the number; empty for ratings.
  final String unit;

  /// Entry ceiling. Not a physiological claim — it exists so a slip on a
  /// stepper cannot enter 40 coffees and quietly dominate every correlation
  /// that field appears in.
  final double max;

  /// Increment for one tap of the stepper.
  final double step;

  /// Whether the field offers a "last one at" time.
  final bool hasTime;

  /// User-invented rather than built in.
  final bool custom;

  /// Archived from active entry. History and this definition stay;
  /// archive is not purge. Built-ins are never hidden.
  final bool hidden;

  bool get isRating => kind == JournalFieldKind.rating;
  bool get isYesNo => kind == JournalFieldKind.yesNo;

  /// Human-readable value, without the unit.
  String format(double v) {
    if (isRating) return v.round().toString();
    // Doses are entered on whole steps, so a trailing .0 is noise.
    return v == v.roundToDouble()
        ? v.round().toString()
        : v.toStringAsFixed(1);
  }

  String formatWithUnit(double v) =>
      unit.isEmpty ? format(v) : '${format(v)} $unit';
}

/// The built-in fields, in the order the editor shows them.
///
/// Ratings run 1–5 rather than 1–10: a ten-point self-report is not ten
/// distinguishable states, and the extra resolution is noise that a rank
/// correlation then has to see through.
const kJournalFields = <JournalFieldSpec>[
  JournalFieldSpec(
    key: 'mood',
    label: 'Mood',
    kind: JournalFieldKind.rating,
    unit: '',
    max: 5,
    step: 1,
  ),
  JournalFieldSpec(
    key: 'sleep_quality',
    label: 'Sleep quality',
    kind: JournalFieldKind.rating,
    unit: '',
    max: 5,
    step: 1,
  ),
  JournalFieldSpec(
    key: 'energy',
    label: 'Energy',
    kind: JournalFieldKind.rating,
    unit: '',
    max: 5,
    step: 1,
  ),
  JournalFieldSpec(
    key: 'stress',
    label: 'Stress',
    kind: JournalFieldKind.rating,
    unit: '',
    max: 5,
    step: 1,
  ),
  JournalFieldSpec(
    key: 'soreness',
    label: 'Soreness',
    kind: JournalFieldKind.rating,
    unit: '',
    max: 5,
    step: 1,
  ),
  JournalFieldSpec(
    key: 'water_ml',
    label: 'Water',
    kind: JournalFieldKind.dose,
    unit: 'ml',
    max: 6000,
    step: 250,
  ),
  // Caffeine is the field the timing support exists for. A 200 mg morning
  // coffee and a 200 mg evening one are the same dose and a completely
  // different night, and collapsing them loses the only part that predicts
  // anything.
  JournalFieldSpec(
    key: 'caffeine_mg',
    label: 'Caffeine',
    kind: JournalFieldKind.dose,
    unit: 'mg',
    max: 1000,
    step: 25,
    hasTime: true,
  ),
  JournalFieldSpec(
    key: 'alcohol_units',
    label: 'Alcohol',
    kind: JournalFieldKind.dose,
    unit: 'units',
    max: 20,
    step: 1,
    hasTime: true,
  ),
  JournalFieldSpec(
    key: 'caffeine_late',
    label: 'Caffeine after 14:00',
    kind: JournalFieldKind.yesNo,
    unit: '',
    max: 1,
    step: 1,
  ),
  JournalFieldSpec(
    key: 'alcohol_evening',
    label: 'Alcohol in the evening',
    kind: JournalFieldKind.yesNo,
    unit: '',
    max: 1,
    step: 1,
  ),
  JournalFieldSpec(
    key: 'read_before_bed',
    label: 'Read before bed',
    kind: JournalFieldKind.yesNo,
    unit: '',
    max: 1,
    step: 1,
  ),
  JournalFieldSpec(
    key: 'screens_min',
    label: 'Screens before bed',
    kind: JournalFieldKind.duration,
    unit: 'min',
    max: 480,
    step: 15,
  ),
  // MT-03 — WEIGHT AS A SERIES, not a profile field.
  //
  // HealthKit/Health Connect WEIGHT is read once at profile import and
  // collapsed to a single scalar, so Mifflin BMR is pinned to whatever you
  // weighed on install day forever. `journal_metric` is already (date, field,
  // value) with a field-first index and CSV export, so this one row gets
  // storage, editor, chart and correlation without a table.
  //
  // ENTERED, NEVER MEASURED, and labelled that way wherever it appears. Read
  // the ceiling before building anything on it: this is the most
  // eating-disorder-adjacent surface in the app and it must never EMIT.
  //   * Render [weightTrendEwma], NOT the raw readings — day-to-day scale
  //     noise is water and glycogen at ±1-2 kg and a raw line makes that read
  //     as change.
  //   * Show gaps. Never interpolate one.
  //   * No goal weight, no daily prompt, no red/green, no "you gained"
  //     notification, no body fat, no lean mass, no metabolic age.
  //   * BMR keeps reading the onboarding scalar for now — see the note on
  //     [weightTrendEwma].
  JournalFieldSpec(
    key: 'weight_kg',
    label: 'Weight',
    kind: JournalFieldKind.dose,
    unit: 'kg',
    max: 400,
    step: 0.1,
  ),
];

/// Half-life of the weight trend, in days.
///
/// A week is long enough that a salty dinner does not move the line and short
/// enough that a real four-week change is visible by the end of it.
const double kWeightTrendHalfLifeDays = 7;

/// The EWMA trend through a set of dated weight readings — THE thing to draw.
///
/// [byDay] is keyed by 'YYYY-MM-DD'. The output has one entry per day that
/// actually had a reading, in date order: gaps stay gaps, because a smoothed
/// line drawn across a fortnight nobody weighed is a fortnight of invented
/// data. The decay is by ELAPSED DAYS, not by position in the list, so two
/// readings a month apart do not smooth into each other the way two
/// consecutive ones do.
///
/// NOT WIRED TO BMR, deliberately. Changing the BMR input recomputes every
/// historical calorie number in the app, so that lands on its own commit where
/// a regression is attributable. And the calorie-model calibration from a
/// weight-drift residual is DROPPED, not deferred: the noise band on a weekly
/// delta (~±1 kg) is several times the signal a 2 400 kcal weekly imbalance
/// produces (~0.3 kg), so "your balance says −2 400 and you didn't move, so
/// the model is off for you" would be false more often than true.
Map<String, double> weightTrendEwma(
  Map<String, double> byDay, {
  double halfLifeDays = kWeightTrendHalfLifeDays,
}) {
  final days = byDay.keys.toList()..sort();
  final out = <String, double>{};
  double? ewma;
  DateTime? prev;
  for (final day in days) {
    final d = DateTime.tryParse(day);
    final v = byDay[day];
    if (d == null || v == null || !v.isFinite) continue;
    if (ewma == null || prev == null) {
      ewma = v;
    } else {
      final gap = d.difference(prev).inDays.abs().clamp(0, 3650).toDouble();
      // Weight of the new reading after `gap` days of decay. One day at a
      // 7-day half-life is ~0.094; a month is ~0.95, i.e. after a long gap the
      // trend restarts from the reading rather than dragging the old one in.
      final w = 1 - math.pow(0.5, gap / halfLifeDays).toDouble();
      ewma = ewma + w * (v - ewma);
    }
    prev = d;
    out[day] = ewma;
  }
  return out;
}

/// Built-ins by key, for a lookup that does not walk the list.
final Map<String, JournalFieldSpec> kJournalFieldsByKey = {
  for (final f in kJournalFields) f.key: f,
};

/// Resolve a stored field key to its spec, preferring built-ins.
///
/// Returns null for a key with no definition at all — an orphan metric
/// whose custom row was never stored. Hidden definitions are still
/// definitions; pass them in [custom] so history keeps its label and unit.
JournalFieldSpec? journalFieldSpec(
  String key, {
  List<JournalFieldSpec> custom = const [],
}) {
  final builtIn = kJournalFieldsByKey[key];
  if (builtIn != null) return builtIn;
  for (final c in custom) {
    if (c.key == key) return c;
  }
  return null;
}

/// A stable storage key for a user-invented field name.
///
/// Prefixed so a custom field can never collide with a built-in one, present
/// or future: adding `magnesium` to [kJournalFields] later must not silently
/// adopt somebody's existing custom column and reinterpret its units.
String customJournalFieldKey(String label) {
  final slug = label
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return 'custom_$slug';
}

final _customJournalFieldKeyPattern = RegExp(r'^custom_[A-Za-z0-9_]+$');

/// True for a user-invented storage key that cannot collide with a built-in.
bool isCustomJournalFieldKey(String key) =>
    _customJournalFieldKeyPattern.hasMatch(key) &&
    !kJournalFieldsByKey.containsKey(key);

/// A storage key independent of the display label.
///
/// [customJournalFieldKey] slugs the label, so punctuation collides and
/// non-ASCII names can collapse toward `custom_`. New UI mints a UUID v4
/// identity (32 hex chars, hyphens stripped) and keeps a Unicode label as
/// display-only. The `custom_` prefix still reserves the namespace against
/// future built-ins.
String newCustomJournalFieldKey() =>
    'custom_${const Uuid().v4().replaceAll('-', '')}';

/// Named kind from storage. Unknown names are corrupt — never a silent dose.
JournalFieldKind journalFieldKindNamed(String name) {
  for (final k in JournalFieldKind.values) {
    if (k.name == name) return k;
  }
  throw FormatException('Unknown journal field kind: $name');
}

/// Throws [ArgumentError] if [spec] cannot be stored as a new custom field.
void validateCustomJournalField(JournalFieldSpec spec) {
  final key = spec.key.trim();
  if (!isCustomJournalFieldKey(key)) {
    throw ArgumentError.value(
      spec.key,
      'key',
      'Custom journal key must be a nonempty custom_ identity, not a built-in.',
    );
  }
  if (spec.label.trim().isEmpty) {
    throw ArgumentError.value(
      spec.label,
      'label',
      'Custom journal label is required.',
    );
  }
  if (!spec.max.isFinite ||
      spec.max <= 0 ||
      !spec.step.isFinite ||
      spec.step <= 0) {
    throw ArgumentError(
      'Custom journal max and step must be finite and positive.',
    );
  }
  if (spec.max < spec.step) {
    throw ArgumentError('Custom journal max must be at least the step.');
  }
  switch (spec.kind) {
    case JournalFieldKind.yesNo:
      if (spec.max != 1 ||
          spec.step != 1 ||
          spec.unit.trim().isNotEmpty ||
          spec.hasTime) {
        throw ArgumentError(
          'Yes/no fields must be 0/1 with no unit or time.',
        );
      }
    case JournalFieldKind.rating:
      if (spec.step != 1 ||
          !_isWholeNumber(spec.max) ||
          spec.unit.trim().isNotEmpty ||
          spec.hasTime) {
        throw ArgumentError(
          'Rating fields use a whole-number scale with no unit or time.',
        );
      }
    case JournalFieldKind.dose:
      if (spec.unit.trim().isEmpty) {
        throw ArgumentError('Dose fields need a unit.');
      }
    case JournalFieldKind.duration:
      break;
  }
}

bool _isWholeNumber(double v) => v == v.roundToDouble();

/// Patch-boundary check for one dirty metric. Unknown keys are the
/// caller's problem. Out-of-range numbers and fractional ratings are
/// refused rather than rewritten into a different answer.
void validateJournalPatchMetric(
  JournalFieldSpec spec,
  JournalMetricValue next,
) {
  if (!next.value.isFinite) {
    throw ArgumentError.value(
      next.value,
      'value',
      'Journal value must be finite.',
    );
  }
  final at = next.atMinuteOfDay;
  if (at != null && (at < 0 || at > 1439)) {
    throw ArgumentError.value(at, 'atMinuteOfDay', 'Expected 0..1439.');
  }
  if (next.value < 0 || next.value > spec.max) {
    throw ArgumentError.value(
      next.value,
      'value',
      'Journal value must be within 0 and ${spec.max}.',
    );
  }
  if (spec.isYesNo && next.value != 0 && next.value != 1) {
    throw ArgumentError.value(
      next.value,
      'value',
      'Yes/no must be 0 or 1.',
    );
  }
  if (spec.isRating && !_isWholeNumber(next.value)) {
    throw ArgumentError.value(
      next.value,
      'value',
      'Rating values must be whole numbers.',
    );
  }
}

int _storedFlag(Object? value, String key, String column) {
  if (value is num && value == value.roundToDouble()) {
    final n = value.round();
    if (n == 0 || n == 1) return n;
  }
  throw FormatException(
    'Corrupt journal field definition: $key ($column)',
  );
}

/// Read-boundary parse of a `journal_field_def` row.
///
/// Rejects unknown kinds, non-finite/non-positive/inverted max and step,
/// fractional rating scales, and boolean columns that are not 0/1. Does
/// **not** apply create-only key/label rules: wellness and the compose sheet
/// slug labels (`custom_walk_after_lunch`), older writers stored untrimmed
/// labels, and a missing name is still the stored definition.
JournalFieldSpec parseStoredCustomJournalField(Map<String, Object?> row) {
  final key = row['key'];
  final label = row['label'];
  final kindRaw = row['kind'];
  final unit = row['unit'];
  if (key is! String ||
      label is! String ||
      kindRaw is! String ||
      unit is! String) {
    throw FormatException('Corrupt journal field definition: $key');
  }
  final kind = journalFieldKindNamed(kindRaw);
  final max = (row['max_value'] as num?)?.toDouble();
  final step = (row['step'] as num?)?.toDouble();
  if (max == null ||
      step == null ||
      !max.isFinite ||
      !step.isFinite ||
      max <= 0 ||
      step <= 0 ||
      max < step) {
    throw FormatException('Corrupt journal field definition: $key');
  }
  if (kind == JournalFieldKind.rating &&
      (!_isWholeNumber(max) || !_isWholeNumber(step))) {
    throw FormatException('Corrupt journal field definition: $key');
  }
  return JournalFieldSpec(
    key: key,
    label: label,
    kind: kind,
    unit: unit,
    max: max,
    step: step,
    hasTime: _storedFlag(row['has_time'], key, 'has_time') == 1,
    custom: true,
    hidden: _storedFlag(row['hidden'], key, 'hidden') == 1,
  );
}

/// Create-boundary spec: trimmed, custom, active. Validates first.
JournalFieldSpec preparedCustomJournalField(JournalFieldSpec spec) {
  validateCustomJournalField(spec);
  final ratingLike =
      spec.kind == JournalFieldKind.rating || spec.kind == JournalFieldKind.yesNo;
  return JournalFieldSpec(
    key: spec.key.trim(),
    label: spec.label.trim(),
    kind: spec.kind,
    unit: ratingLike ? '' : spec.unit.trim(),
    max: spec.max,
    step: spec.step,
    hasTime: ratingLike ? false : spec.hasTime,
    custom: true,
    hidden: false,
  );
}

/// Local minutes past midnight → "7:05 AM".
String formatMinuteOfDay(int minuteOfDay) {
  final m = minuteOfDay % (24 * 60);
  final h24 = m ~/ 60;
  final mm = (m % 60).toString().padLeft(2, '0');
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h:$mm ${h24 < 12 ? 'AM' : 'PM'}';
}

/// True for a real calendar day in `YYYY-MM-DD`. `2026-02-30` is rejected.
bool isJournalDayId(String day) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) return false;
  final p = day.split('-');
  final y = int.parse(p[0]), m = int.parse(p[1]), d = int.parse(p[2]);
  final dt = DateTime(y, m, d);
  return dt.year == y && dt.month == m && dt.day == d;
}

/// Decode stored `tags_json`. Missing/empty is no tags. Unreadable JSON is
/// refused rather than treated as empty — a note-only patch must not wipe
/// a corrupt saved list.
List<String> decodeJournalTags(Object? json) {
  if (json == null) return const [];
  if (json is! String) {
    throw const FormatException('Unreadable journal tags.');
  }
  if (json.isEmpty) return const [];
  final decoded = jsonDecode(json);
  if (decoded is! List) {
    throw const FormatException('Unreadable journal tags.');
  }
  return [for (final e in decoded) e.toString()];
}

/// A patch could not be applied because a dirty field's stored value or
/// revision no longer matches what the caller read. Nothing was written.
class JournalConflict implements Exception {
  const JournalConflict(this.day, {this.fields = const []});
  final String day;
  final List<String> fields;
  @override
  String toString() => 'JournalConflict($day)';
}

/// One local day's journal as stored: metrics, note/tags, and revisions.
@immutable
class JournalDaySnapshot {
  const JournalDaySnapshot({
    required this.day,
    required this.metrics,
    required this.metricUpdatedAt,
    required this.tags,
    required this.note,
    required this.journalUpdatedAt,
    required this.fields,
  });

  final String day;
  final Map<String, JournalMetricValue> metrics;
  final Map<String, int> metricUpdatedAt;
  final List<String> tags;
  final String note;

  /// `0` when no `journal` row exists yet.
  final int journalUpdatedAt;
  final List<JournalFieldSpec> fields;
}

/// Dirty-only write. Omitted metrics/tags/note stay. `metrics[key] == null`
/// clears that key. Compare expected value+revision for dirty keys only.
@immutable
class JournalDayPatch {
  const JournalDayPatch({
    required this.day,
    this.metrics = const {},
    this.expectedMetrics = const {},
    this.expectedMetricUpdatedAt = const {},
    this.tags,
    this.note,
    this.expectedJournalUpdatedAt,
    this.expectedTags,
    this.expectedNote,
  });

  /// Build a patch against [base], filling expected value/revision for every
  /// dirty key (and the journal row when tags or note are sent).
  factory JournalDayPatch.fromBase(
    JournalDaySnapshot base, {
    Map<String, JournalMetricValue?> metrics = const {},
    List<String>? tags,
    String? note,
  }) {
    final journalDirty = tags != null || note != null;
    return JournalDayPatch(
      day: base.day,
      metrics: metrics,
      expectedMetrics: {for (final k in metrics.keys) k: base.metrics[k]},
      expectedMetricUpdatedAt: {
        for (final k in metrics.keys) k: base.metricUpdatedAt[k] ?? 0,
      },
      tags: tags,
      note: note,
      expectedJournalUpdatedAt: journalDirty ? base.journalUpdatedAt : null,
      expectedTags: tags != null ? base.tags : null,
      expectedNote: note != null ? base.note : null,
    );
  }

  final String day;
  final Map<String, JournalMetricValue?> metrics;
  final Map<String, JournalMetricValue?> expectedMetrics;
  final Map<String, int> expectedMetricUpdatedAt;
  final List<String>? tags;
  final String? note;
  final int? expectedJournalUpdatedAt;
  final List<String>? expectedTags;
  final String? expectedNote;
}
