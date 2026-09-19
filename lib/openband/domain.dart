/// Typed boundary for the OpenBand daily flow. Only repositories decode maps.
library;

import '../data/journal_fields.dart';
import 'package:uuid/uuid.dart';

enum MetricReadiness {
  available,
  processing,
  missing,
  partial,
  unreliable,
  unsupported,
}

enum BandConnection { connected, disconnected, connecting }

enum TransferState { idle, receiving, interrupted }

enum NightStage { awake, rem, light, deep }

enum CorrectionState { pending, calculating, complete, failed }

class DayMetric {
  final double? value;
  final MetricReadiness readiness;
  final String? reason;
  final double? baseline;
  const DayMetric(
    this.value, {
    this.readiness = MetricReadiness.available,
    this.reason,
    this.baseline,
  });
  const DayMetric.missing([this.reason])
    : value = null,
      baseline = null,
      readiness = MetricReadiness.missing;
}

class BandSnapshot {
  final BandConnection connection;
  final TransferState transfer;
  final int? batteryPercent;
  final DateTime? batteryObservedAt;
  final DateTime? latestStoredAt;
  final DateTime? receivedAt;
  const BandSnapshot({
    this.connection = BandConnection.disconnected,
    this.transfer = TransferState.idle,
    this.batteryPercent,
    this.batteryObservedAt,
    this.latestStoredAt,
    this.receivedAt,
  });
}

/// Current-local-day evaluation for first setup. Never a BLE cursor.
enum SetupEvalState {
  missing,
  stale,
  unavailable,
  partial,
  pending,
  failed,
  complete,
}

class SetupEvaluation {
  final String day;
  final int currentAlgo;
  final int? storedAlgo;
  final DateTime? computedAt;
  final SetupEvalState state;
  const SetupEvaluation({
    required this.day,
    required this.currentAlgo,
    this.storedAlgo,
    this.computedAt,
    required this.state,
  });

  @override
  bool operator ==(Object other) =>
      other is SetupEvaluation &&
      other.day == day &&
      other.currentAlgo == currentAlgo &&
      other.storedAlgo == storedAlgo &&
      other.computedAt == computedAt &&
      other.state == state;

  @override
  int get hashCode =>
      Object.hash(day, currentAlgo, storedAlgo, computedAt, state);
}

class NightSegment {
  final DateTime start;
  final DateTime end;

  /// null is an unobserved interval, never light sleep.
  final NightStage? stage;
  const NightSegment(this.start, this.end, this.stage);
}

class SleepNight {
  final DateTime? onset;
  final DateTime? wake;
  final String? recordingTimezone;
  final DayMetric duration;
  final double? bedMinutes,
      awakeMinutes,
      remMinutes,
      lightMinutes,
      deepMinutes,
      unobservedMinutes;
  final List<NightSegment> segments;
  final String source;
  final List<({String day, double? minutes})> history;
  const SleepNight({
    this.onset,
    this.wake,
    this.recordingTimezone,
    this.duration = const DayMetric.missing(),
    this.bedMinutes,
    this.awakeMinutes,
    this.remMinutes,
    this.lightMinutes,
    this.deepMinutes,
    this.unobservedMinutes,
    this.segments = const [],
    this.source = 'WHOOP 5.0',
    this.history = const [],
  });
}

enum NightSignalKind { pulse, hrv, respiration }

class NightSignalReading {
  final DateTime at;

  /// A stored refusal stays in the timeline as a gap.
  final double? value;
  final ({double lower, double upper})? bounds;
  const NightSignalReading(this.at, this.value, {this.bounds});
}

class NightSignalSeries {
  final List<NightSignalReading> readings;
  final String? reason;
  final bool partial;

  /// Known source cadence, including its timestamp tolerance. Null means
  /// isolated observations; the chart must not connect them.
  final Duration? maxConnectingGap;
  const NightSignalSeries({
    this.readings = const [],
    this.reason,
    this.partial = false,
    this.maxConnectingGap,
  });
}

class NightSignals {
  final String day;
  final ({DateTime start, DateTime end})? window;
  final String? recordingTimezone;
  final Map<NightSignalKind, NightSignalSeries> series;
  final bool processing, synthetic;
  const NightSignals({
    required this.day,
    this.window,
    this.recordingTimezone,
    this.series = const {},
    this.processing = false,
    this.synthetic = false,
  });

  NightSignalSeries signal(NightSignalKind kind) =>
      series[kind] ?? const NightSignalSeries();
}

class SleepDraft {
  final String id, day;
  final DateTime onset, wake;
  final String? recordingTimezone;
  const SleepDraft({
    required this.id,
    required this.day,
    required this.onset,
    required this.wake,
    this.recordingTimezone,
  });
  Duration get timeInBed => wake.difference(onset);
  SleepDraft withTimes(DateTime start, DateTime end) => SleepDraft(
    id: id,
    day: day,
    onset: start,
    wake: end,
    recordingTimezone: recordingTimezone,
  );
}

class SleepCorrection {
  final String id, day;
  final DateTime onset, wake, savedAt;
  final int revision;
  final CorrectionState state;
  final bool automatic;
  final String? error;
  const SleepCorrection({
    required this.id,
    required this.day,
    required this.onset,
    required this.wake,
    required this.savedAt,
    required this.revision,
    required this.state,
    this.automatic = false,
    this.error,
  });
}

enum NapSource { detected, manual }

class NapSession {
  final DateTime start, end;
  final NapSource source;
  final int? durationMin;
  final int? originStartTs, originEndTs;
  const NapSession({
    required this.start,
    required this.end,
    required this.source,
    this.durationMin,
    this.originStartTs,
    this.originEndTs,
  });
  int get startTs => start.millisecondsSinceEpoch ~/ 1000;
  int get endTs => end.millisecondsSinceEpoch ~/ 1000;
  bool get fromDetected =>
      source == NapSource.detected || originStartTs != null;
}

class NapJob {
  final String day;
  final int revision;
  final CorrectionState state;
  final DateTime requestedAt;
  final String? error;
  const NapJob({
    required this.day,
    required this.revision,
    required this.state,
    required this.requestedAt,
    this.error,
  });
}

/// Selected-day nap list. [judged] is detector coverage, not whether the user
/// logged anything: manuals on an unjudged day must not claim a measured zero.
class NapDay {
  final String day;
  final bool judged;
  final List<NapSession> sessions;
  final int? totalMin;
  final List<NapSession> rejected;
  final NapJob? job;
  final String? recordingTimezone;
  final String? note;
  const NapDay({
    required this.day,
    this.judged = false,
    this.sessions = const [],
    this.totalMin,
    this.rejected = const [],
    this.job,
    this.recordingTimezone,
    this.note,
  });
}

class StepInterval {
  final DateTime start, end;
  final double steps;
  const StepInterval(this.start, this.end, this.steps);
}

class DayIntake {
  final double? kcal, waterMl;
  final bool kcalIsFloor;
  const DayIntake({this.kcal, this.waterMl, this.kcalIsFloor = false});
}

class OpenBandDay {
  final String day;
  final SleepNight sleep;
  final DayMetric recovery, strain, hrv, restingHr, steps;
  final SleepCorrection? correction;
  final List<StepInterval> stepIntervals;
  final DateTime? calculatedAt;
  final DayIntake intake;
  final bool synthetic;
  const OpenBandDay({
    required this.day,
    this.sleep = const SleepNight(),
    this.recovery = const DayMetric.missing(),
    this.strain = const DayMetric.missing(),
    this.hrv = const DayMetric.missing(),
    this.restingHr = const DayMetric.missing(),
    this.steps = const DayMetric.missing(),
    this.correction,
    this.stepIntervals = const [],
    this.calculatedAt,
    this.intake = const DayIntake(),
    this.synthetic = false,
  });
}

/// Save returns only after the correction and its pending job are durable.
/// Calculation is a separate operation. A failure must retain that correction.
class MetricPoint {
  final String day;
  final double? value;
  const MetricPoint(this.day, this.value);
}

enum MetricKey {
  hrv('rmssd'),
  restingHr('rhr'),
  recovery('readiness'),
  sleepDuration('tst_min'),
  strain('strain');

  final String series;
  const MetricKey(this.series);
}

class TrainingSession {
  final String id, day, type;
  final DateTime start;
  final int? durationMin;
  final double? strain, kcal;
  final bool live;
  const TrainingSession({
    required this.id,
    required this.day,
    required this.type,
    required this.start,
    this.durationMin,
    this.strain,
    this.kcal,
    this.live = false,
  });
}

class JournalEntry {
  final String key;
  final double value;
  const JournalEntry(this.key, this.value);
}

class PatternGroup {
  final int nights;
  final double? mean;
  const PatternGroup(this.nights, this.mean);
}

/// Outcome of the night that FOLLOWS a yes/no journal answer, split by the
/// answer. A journal day D is paired with the metric dated D+1 (the wake
/// day of that night). Nights without an answer or without the metric are
/// not counted anywhere.
class PatternSummary {
  final PatternGroup yes, no;
  const PatternSummary({required this.yes, required this.no});
}

PatternSummary summarizePattern(
  Map<String, double?> answers,
  Map<String, double?> outcomes,
  List<String> days,
) {
  final yes = <double>[], no = <double>[];
  for (var i = 0; i + 1 < days.length; i++) {
    final answer = answers[days[i]], outcome = outcomes[days[i + 1]];
    if (answer == null || outcome == null) continue;
    (answer >= .5 ? yes : no).add(outcome);
  }
  PatternGroup group(List<double> v) => PatternGroup(
    v.length,
    v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length,
  );
  return PatternSummary(yes: group(yes), no: group(no));
}

class PlannedSet {
  final String id;
  final String type;
  final int? reps, seconds, restSec;
  final double? loadKg;
  const PlannedSet({
    required this.id,
    this.type = 'work',
    this.reps,
    this.seconds,
    this.restSec,
    this.loadKg,
  });
  factory PlannedSet.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String? ?? '';
    if (id.isEmpty) {
      throw const FormatException('Planned set is missing a stable id.');
    }
    return PlannedSet(
      id: id,
      type: j['type'] as String? ?? 'work',
      reps: (j['reps'] as num?)?.toInt(),
      seconds: (j['seconds'] as num?)?.toInt(),
      restSec: (j['restSec'] as num?)?.toInt(),
      loadKg: (j['loadKg'] as num?)?.toDouble(),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'reps': reps,
    'seconds': seconds,
    'restSec': restSec,
    'loadKg': loadKg,
  };
}

class PlannedExercise {
  final String id, exerciseKey, name;
  final List<PlannedSet> sets;
  final String note;
  const PlannedExercise({
    required this.id,
    required this.exerciseKey,
    required this.name,
    required this.sets,
    this.note = '',
  });
  factory PlannedExercise.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String? ?? '';
    final exerciseKey = j['exerciseKey'] as String? ?? '';
    final name = j['name'] as String? ?? '';
    if (id.isEmpty || exerciseKey.isEmpty || name.isEmpty) {
      throw const FormatException('Planned exercise is missing identity.');
    }
    final rawSets = j['sets'];
    if (rawSets is! List || rawSets.isEmpty) {
      throw const FormatException('Planned exercise has no sets.');
    }
    return PlannedExercise(
      id: id,
      exerciseKey: exerciseKey,
      name: name,
      sets: [
        for (final s in rawSets) PlannedSet.fromJson(s as Map<String, dynamic>),
      ],
      note: j['note'] as String? ?? '',
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'exerciseKey': exerciseKey,
    'name': name,
    'sets': [for (final s in sets) s.toJson()],
    'note': note,
  };
}

/// A plan. Confirming a set records a strength_set row. Editing the template
/// never changes a recorded session (B23).
class WorkoutTemplate {
  final String id, name;
  final int version;
  final List<PlannedExercise> exercises;
  final DateTime updatedAt;
  const WorkoutTemplate({
    required this.id,
    required this.name,
    required this.version,
    required this.exercises,
    required this.updatedAt,
  });
  int get workSets => exercises.fold(
    0,
    (n, e) => n + e.sets.where((s) => s.type == 'work').length,
  );

  factory WorkoutTemplate.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String? ?? '';
    final name = j['name'] as String? ?? '';
    final version = (j['version'] as num?)?.toInt();
    final updatedAtMs = (j['updatedAtMs'] as num?)?.toInt();
    final rawExercises = j['exercises'];
    if (id.isEmpty ||
        name.isEmpty ||
        version == null ||
        updatedAtMs == null ||
        rawExercises is! List ||
        rawExercises.isEmpty) {
      throw const FormatException('Strength plan snapshot is unreadable.');
    }
    final exercises = [
      for (final e in rawExercises)
        PlannedExercise.fromJson(e as Map<String, dynamic>),
    ];
    final ids = <String>{};
    for (final e in exercises) {
      if (!ids.add(e.id)) {
        throw const FormatException('Strength plan has duplicate exercise ids.');
      }
      for (final s in e.sets) {
        if (!ids.add(s.id)) {
          throw const FormatException('Strength plan has duplicate set ids.');
        }
      }
    }
    return WorkoutTemplate(
      id: id,
      name: name,
      version: version,
      exercises: exercises,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'exercises': [for (final e in exercises) e.toJson()],
    'updatedAtMs': updatedAt.millisecondsSinceEpoch,
  };
}

/// Current plan + added sets as 1-based indexes within each exercise block.
typedef StrengthPlanSlot = ({
  String plannedSetId,
  String exerciseKey,
  String exerciseId,
  int setIndex,
  bool timed,
});

List<StrengthPlanSlot> strengthPlanSlots(
  WorkoutTemplate plan,
  List<PlannedExercise> added,
) {
  final counts = <String, int>{};
  final out = <StrengthPlanSlot>[];
  void walk(List<PlannedExercise> exercises) {
    for (final e in exercises) {
      var n = counts[e.id] ?? 0;
      for (final s in e.sets) {
        n++;
        out.add((
          plannedSetId: s.id,
          exerciseKey: e.exerciseKey,
          exerciseId: e.id,
          setIndex: n,
          timed: s.seconds != null,
        ));
      }
      counts[e.id] = n;
    }
  }

  walk(plan.exercises);
  walk(added);
  return out;
}

String? _strengthExerciseId(String? id) =>
    (id == null || id.isEmpty) ? null : id;

bool _onePriorStrengthBlock(List<RecordedSet> priors) {
  final ids = <String>{};
  final anonIndex = <int>{};
  var anonymous = 0;
  for (final s in priors) {
    final id = _strengthExerciseId(s.exerciseId);
    if (id == null) {
      anonymous++;
      if (!anonIndex.add(s.setIndex)) return false;
    } else {
      ids.add(id);
    }
  }
  if (ids.length > 1) return false;
  if (ids.length == 1) return anonymous == 0;
  return anonymous > 0;
}

/// Prefer [RecordedSet.exerciseId] + index inside the latest prior session.
/// Copied/new plan ids fall back to [exerciseKey] + index only when that key
/// has one current block and one prior block. Duplicate legacy rows omit.
Map<String, RecordedSet> previousStrengthSetsFromLatest({
  required List<StrengthPlanSlot> slots,
  required Map<String, List<RecordedSet>> latestByExercise,
}) {
  final currentIds = <String, Set<String>>{};
  for (final slot in slots) {
    (currentIds[slot.exerciseKey] ??= {}).add(slot.exerciseId);
  }
  final out = <String, RecordedSet>{};
  for (final slot in slots) {
    final priors = latestByExercise[slot.exerciseKey] ?? const <RecordedSet>[];
    RecordedSet? picked;
    final slotId = _strengthExerciseId(slot.exerciseId);
    if (slotId != null) {
      final matches = [
        for (final s in priors)
          if (_strengthExerciseId(s.exerciseId) == slotId &&
              s.setIndex == slot.setIndex)
            s,
      ];
      if (matches.length == 1) picked = matches.single;
    }
    if (picked == null &&
        (currentIds[slot.exerciseKey]?.length ?? 0) == 1 &&
        _onePriorStrengthBlock(priors)) {
      final matches = [
        for (final s in priors)
          if (s.setIndex == slot.setIndex) s,
      ];
      if (matches.length == 1) picked = matches.single;
    }
    if (picked == null) continue;
    final compatible = slot.timed ? picked.seconds != null : picked.reps != null;
    if (!compatible) continue;
    out[slot.plannedSetId] = picked;
  }
  return out;
}

/// Another workout is already live. Start is refused; read the active
/// strength state instead of opening a second session.
class WorkoutBusy implements Exception {
  const WorkoutBusy();
  @override
  String toString() => 'Eine Einheit läuft bereits.';
}

/// Durable Alpin strength runtime: none, a readable live plan, or a live
/// row whose snapshot cannot be shown without fabricating a plan.
sealed class ActiveStrengthRuntime {
  const ActiveStrengthRuntime();
}

final class NoActiveStrength extends ActiveStrengthRuntime {
  const NoActiveStrength();
}

final class CorruptActiveStrength extends ActiveStrengthRuntime {
  final String sessionId;
  const CorruptActiveStrength(this.sessionId);
}

/// Live `weight_training` without an Alpin snapshot. Resume through the
/// existing live engine; do not invent a plan or start another session.
final class LegacyActiveStrength extends ActiveStrengthRuntime {
  final String sessionId;
  const LegacyActiveStrength(this.sessionId);
}

final class ActiveStrengthSession extends ActiveStrengthRuntime {
  final String sessionId;
  final WorkoutTemplate plan;
  final List<RecordedSet> recorded;
  final Set<String> skippedPlannedSetIds;
  final List<PlannedExercise> added;
  final DateTime startedAt;
  final DateTime? restEndsAt;
  const ActiveStrengthSession({
    required this.sessionId,
    required this.plan,
    required this.recorded,
    required this.skippedPlannedSetIds,
    required this.added,
    required this.startedAt,
    this.restEndsAt,
  });

  /// Stored rest end. Null after an explicit skip. Never derived from now.
  DateTime? restUntil() => restEndsAt;
}

String obExerciseCount(int n) => n == 1 ? '1 Übung' : '$n Übungen';

/// Hub card: a still-active pin, otherwise the most recently updated plan.
WorkoutTemplate? featuredTemplate(
  Iterable<WorkoutTemplate> templates, [
  String? pinnedId,
]) {
  if (pinnedId != null) {
    for (final t in templates) {
      if (t.id == pinnedId) return t;
    }
  }
  final i = templates.iterator;
  return i.moveNext() ? i.current : null;
}

enum TemplateMenuChoice { edit, duplicate, pin, unpin, archive }

/// Independent plan + exercise/set identities. Content is copied; the source
/// plan is not rewritten. Name is marked ` · Kopie`.
WorkoutTemplate copyWorkoutTemplate(WorkoutTemplate source, {DateTime? at}) {
  String next() => const Uuid().v4();
  return WorkoutTemplate(
    id: next(),
    name: '${source.name} · Kopie',
    version: 0,
    exercises: [
      for (final e in source.exercises)
        PlannedExercise(
          id: next(),
          exerciseKey: e.exerciseKey,
          name: e.name,
          note: e.note,
          sets: [
            for (final s in e.sets)
              PlannedSet(
                id: next(),
                type: s.type,
                reps: s.reps,
                seconds: s.seconds,
                restSec: s.restSec,
                loadKg: s.loadKg,
              ),
          ],
        ),
    ],
    updatedAt: at ?? DateTime.now(),
  );
}

/// Entries of one meal staged before an atomic save (B05). Nothing in a
/// draft counts toward the day until [OpenBandRepository.commitMealDraft].
class MealDraft {
  final String id, day, meal;
  final List<MealDraftEntry> entries;
  final DateTime updatedAt;
  const MealDraft({
    required this.id,
    required this.day,
    required this.meal,
    required this.entries,
    required this.updatedAt,
  });
}

class MealDraftEntry {
  final String id, label;
  final double? quantity;
  final String unit;
  final double? kcal, proteinG, carbsG, fatG;
  final String? foodKey;
  const MealDraftEntry({
    required this.id,
    required this.label,
    this.quantity,
    this.unit = 'g',
    this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.foodKey,
  });
  factory MealDraftEntry.fromJson(Map<String, dynamic> j) => MealDraftEntry(
    id: j['id'] as String,
    label: j['label'] as String,
    quantity: (j['quantity'] as num?)?.toDouble(),
    unit: j['unit'] as String? ?? 'g',
    kcal: (j['kcal'] as num?)?.toDouble(),
    proteinG: (j['proteinG'] as num?)?.toDouble(),
    carbsG: (j['carbsG'] as num?)?.toDouble(),
    fatG: (j['fatG'] as num?)?.toDouble(),
    foodKey: j['foodKey'] as String?,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'quantity': quantity,
    'unit': unit,
    'kcal': kcal,
    'proteinG': proteinG,
    'carbsG': carbsG,
    'fatG': fatG,
    'foodKey': foodKey,
  };
}

/// Saved food entries of one day, grouped by meal, with per-nutrient totals
/// that stay a lower bound when any entry lacks the nutrient.
class MealEntry {
  final String id, meal, label;
  final double? kcal, proteinG, carbsG, fatG;
  const MealEntry({
    required this.id,
    required this.meal,
    required this.label,
    this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
  });
}

class NutrientSum {
  final double? value;
  final int known, unknown;
  const NutrientSum(this.value, this.known, this.unknown);
  bool get complete => known > 0 && unknown == 0;
}

class DayMeals {
  final String day;
  final List<MealEntry> entries;
  final NutrientSum kcal, proteinG, carbsG, fatG;
  const DayMeals({
    required this.day,
    required this.entries,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });
}

/// Frozen detail of one recorded session (B19): stored once with the
/// algorithm version that produced it, so history never shrinks after raw
/// points are pruned. Absent inputs stay null.
class SessionDetail {
  final String sessionId, type, day;
  final DateTime start;
  final int algoVersion;
  final int? durationSec, pauseSec;
  final double? distanceM, avgHr, strain, kcal;
  final int? maxHr, hrCoveredSec, hrr60, hrr120;
  final List<int>? zoneSec;
  final List<SessionSplit> splits;
  final List<Lap> laps;
  const SessionDetail({
    required this.sessionId,
    required this.type,
    required this.day,
    required this.start,
    required this.algoVersion,
    this.durationSec,
    this.pauseSec,
    this.distanceM,
    this.avgHr,
    this.maxHr,
    this.hrCoveredSec,
    this.strain,
    this.kcal,
    this.hrr60,
    this.hrr120,
    this.zoneSec,
    this.splits = const [],
    this.laps = const [],
  });
  factory SessionDetail.fromJson(Map<String, dynamic> j) => SessionDetail(
    sessionId: j['sessionId'] as String,
    type: j['type'] as String,
    day: j['day'] as String,
    start: DateTime.fromMillisecondsSinceEpoch(j['startMs'] as int),
    algoVersion: j['algoVersion'] as int,
    durationSec: (j['durationSec'] as num?)?.toInt(),
    pauseSec: (j['pauseSec'] as num?)?.toInt(),
    distanceM: (j['distanceM'] as num?)?.toDouble(),
    avgHr: (j['avgHr'] as num?)?.toDouble(),
    maxHr: (j['maxHr'] as num?)?.toInt(),
    hrCoveredSec: (j['hrCoveredSec'] as num?)?.toInt(),
    strain: (j['strain'] as num?)?.toDouble(),
    kcal: (j['kcal'] as num?)?.toDouble(),
    hrr60: (j['hrr60'] as num?)?.toInt(),
    hrr120: (j['hrr120'] as num?)?.toInt(),
    zoneSec: (j['zoneSec'] as List?)?.map((e) => (e as num).toInt()).toList(),
    splits: [
      for (final s in j['splits'] as List? ?? const [])
        SessionSplit(
          km: (s['km'] as num).toInt(),
          seconds: (s['seconds'] as num).toInt(),
          avgHr: (s['avgHr'] as num?)?.toDouble(),
        ),
    ],
    laps: [
      for (final l in j['laps'] as List? ?? const [])
        Lap.fromJson((l as Map).cast<String, dynamic>()),
    ],
  );
  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'type': type,
    'day': day,
    'startMs': start.millisecondsSinceEpoch,
    'algoVersion': algoVersion,
    'durationSec': durationSec,
    'pauseSec': pauseSec,
    'distanceM': distanceM,
    'avgHr': avgHr,
    'maxHr': maxHr,
    'hrCoveredSec': hrCoveredSec,
    'strain': strain,
    'kcal': kcal,
    'hrr60': hrr60,
    'hrr120': hrr120,
    'zoneSec': zoneSec,
    'splits': [
      for (final s in splits)
        {'km': s.km, 'seconds': s.seconds, 'avgHr': s.avgHr},
    ],
    'laps': [for (final l in laps) l.toJson()],
  };
}

/// A user-tapped lap mark inside a distance session. [distanceM] stays null
/// when GPS was off.
class Lap {
  final int index, elapsedSec, pausedSec;
  final double? distanceM;
  final DateTime at;
  const Lap({
    required this.index,
    required this.elapsedSec,
    required this.pausedSec,
    this.distanceM,
    required this.at,
  });
  factory Lap.fromJson(Map<String, dynamic> j) => Lap(
    index: (j['index'] as num).toInt(),
    elapsedSec: (j['elapsedSec'] as num).toInt(),
    pausedSec: (j['pausedSec'] as num).toInt(),
    distanceM: (j['distanceM'] as num?)?.toDouble(),
    at: DateTime.fromMillisecondsSinceEpoch(j['atMs'] as int),
  );
  Map<String, dynamic> toJson() => {
    'index': index,
    'elapsedSec': elapsedSec,
    'pausedSec': pausedSec,
    'distanceM': distanceM,
    'atMs': at.millisecondsSinceEpoch,
  };
}

class SessionSplit {
  final int km, seconds;
  final double? avgHr;
  const SessionSplit({required this.km, required this.seconds, this.avgHr});
}

/// A confirmed set. Bodyweight is not a load of 0 kg: [loadKg] stays null.
/// [plannedSetId] / [exerciseId] are the stable plan identities; without
/// them repeated blocks of the same [exerciseKey] cannot be mapped.
class RecordedSet {
  final String exerciseKey;
  final int setIndex;
  final int? reps, seconds, restSec;
  final double? loadKg;
  final DateTime at;
  final String? plannedSetId, exerciseId;
  const RecordedSet({
    required this.exerciseKey,
    required this.setIndex,
    this.reps,
    this.seconds,
    this.loadKg,
    required this.at,
    this.plannedSetId,
    this.exerciseId,
    this.restSec,
  });
}

/// Work sets per muscle over a window, from recorded sets joined to the
/// exercise catalogue. Sets whose exercise has no muscle mapping are counted
/// under [unmapped] instead of being guessed.
class MuscleLoad {
  final Map<String, int> setsByMuscle;
  final int unmapped;
  const MuscleLoad(this.setsByMuscle, this.unmapped);
}

class FoodHit {
  final String key, label, brand;
  final double? servingG, kcal100, proteinG100, carbsG100, fatG100;
  const FoodHit({
    required this.key,
    required this.label,
    this.brand = '',
    this.servingG,
    this.kcal100,
    this.proteinG100,
    this.carbsG100,
    this.fatG100,
  });
  MealDraftEntry portion(String id, double grams) {
    double? per(double? v100) => v100 == null ? null : v100 * grams / 100;
    return MealDraftEntry(
      id: id,
      label: label,
      quantity: grams,
      unit: 'g',
      kcal: per(kcal100),
      proteinG: per(proteinG100),
      carbsG: per(carbsG100),
      fatG: per(fatG100),
      foodKey: key,
    );
  }
}

const int kSleepGoalMinMinutes = 1;
const int kSleepGoalMaxMinutes = 24 * 60;

/// Latest user-chosen sleep duration for a wake day. [minutes] null is an
/// explicit "no target" boundary, not a missing row.
class SleepGoalPeriod {
  final String validFromDay;
  final int? minutes;
  final DateTime createdAt, updatedAt;
  const SleepGoalPeriod({
    required this.validFromDay,
    required this.minutes,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// Stored weekend p75 duration from the current `crossday` baseline only.
class WeekendSleepEstimate {
  final String asOfDay;
  final int algoVersion;
  final int builtAtEpoch;
  final double osdHours;
  final double? confidence;
  final String? note;
  const WeekendSleepEstimate({
    required this.asOfDay,
    required this.algoVersion,
    required this.builtAtEpoch,
    required this.osdHours,
    this.confidence,
    this.note,
  });
}

class SleepGoalSnapshot {
  final SleepGoalPeriod? period;
  final WeekendSleepEstimate? weekendEstimate;
  const SleepGoalSnapshot({this.period, this.weekendEstimate});
  int? get targetMinutes => period?.minutes;
}

int? sleepGoalMinutesFromFields(String hoursText, String minutesText) {
  final hours = int.tryParse(hoursText.trim());
  final minutes = int.tryParse(minutesText.trim());
  if (hours == null ||
      minutes == null ||
      hours < 0 ||
      minutes < 0 ||
      minutes > 59) {
    return null;
  }
  final total = hours * 60 + minutes;
  if (total < kSleepGoalMinMinutes || total > kSleepGoalMaxMinutes) return null;
  return total;
}

int? _positiveWhole(Object? value) {
  if (value is! num || !value.isFinite || value <= 0) return null;
  if (value != value.roundToDouble()) return null;
  return value.toInt();
}

/// Decode the stored `crossday` envelope. Wrong day, version, or malformed
/// fields yield null — never a borrowed rollup or `sleep_coach.need`.
WeekendSleepEstimate? weekendSleepEstimateFromCrossday(
  Map<String, dynamic>? artifact, {
  required String selectedDay,
  required int algoVersion,
}) {
  if (artifact == null) return null;
  final version = _positiveWhole(artifact['algo_version']);
  if (version == null || version != algoVersion) return null;
  final builtFor = artifact['built_for_day'];
  if (builtFor is! String || builtFor != selectedDay || builtFor.isEmpty) {
    return null;
  }
  final builtAtEpoch = _positiveWhole(artifact['built_at_epoch']);
  if (builtAtEpoch == null) return null;
  final debt = artifact['sleep_debt'];
  if (debt is! Map) return null;
  final value = debt['value'];
  if (value is! Map) return null;
  if (value['has_free_night'] != true) return null;
  final osd = value['osd_hours'];
  if (osd is! num || !osd.isFinite || osd <= 0) return null;
  final confRaw = debt['confidence'];
  double? confidence;
  if (confRaw != null) {
    if (confRaw is! num || !confRaw.isFinite || confRaw < 0 || confRaw > 1) {
      return null;
    }
    confidence = confRaw.toDouble();
  }
  final noteRaw = debt['note'];
  if (noteRaw != null && noteRaw is! String) return null;
  final note = noteRaw is String && noteRaw.isNotEmpty ? noteRaw : null;
  return WeekendSleepEstimate(
    asOfDay: builtFor,
    algoVersion: version,
    builtAtEpoch: builtAtEpoch,
    osdHours: osd.toDouble(),
    confidence: confidence,
    note: note,
  );
}

/// One hand-entered draw. [unit] is the row's own unit, never converted.
class LabDraw {
  final String marker, takenOn, unit, note;
  final double value;
  final double? reportLow, reportHigh;
  final int updatedAt;
  final Map<String, Object?> extras;
  const LabDraw({
    required this.marker,
    required this.takenOn,
    required this.value,
    required this.unit,
    this.note = '',
    this.reportLow,
    this.reportHigh,
    this.updatedAt = 0,
    this.extras = const {},
  });

  bool get readable =>
      value.isFinite && unit.isNotEmpty && isLabCalendarDay(takenOn);

  LabDraw copyWith({
    String? marker,
    String? takenOn,
    double? value,
    String? unit,
    String? note,
    double? reportLow,
    double? reportHigh,
    bool clearReportLow = false,
    bool clearReportHigh = false,
  }) => LabDraw(
    marker: marker ?? this.marker,
    takenOn: takenOn ?? this.takenOn,
    value: value ?? this.value,
    unit: unit ?? this.unit,
    note: note ?? this.note,
    reportLow: clearReportLow ? null : (reportLow ?? this.reportLow),
    reportHigh: clearReportHigh ? null : (reportHigh ?? this.reportHigh),
    updatedAt: updatedAt,
    extras: extras,
  );
}

/// User-defined marker. [key] is stable across label changes.
class LabMarkerDef {
  final String key, label, unit, category;
  final int decimals;
  final double? refLow, refHigh;
  final int createdAt;
  const LabMarkerDef({
    required this.key,
    required this.label,
    required this.unit,
    required this.category,
    this.decimals = 1,
    this.refLow,
    this.refHigh,
    this.createdAt = 0,
  });
}

class LabSnapshot {
  final List<LabDraw> results;
  final List<LabMarkerDef> custom;
  final String? sex;
  const LabSnapshot({
    this.results = const [],
    this.custom = const [],
    this.sex,
  });
}

/// Destination already has a draw. UI must confirm before replacing it.
class LabDrawCollision implements Exception {
  final String marker, takenOn;
  const LabDrawCollision(this.marker, this.takenOn);
  @override
  String toString() => 'LabDrawCollision($marker, $takenOn)';
}

/// Create would overwrite another custom definition. Rename keeps its key.
class LabMarkerCollision implements Exception {
  final String key;
  const LabMarkerCollision(this.key);
  @override
  String toString() => 'LabMarkerCollision($key)';
}

/// Locale comma or dot as the decimal mark. Both present is ambiguous.
class LabParse {
  final double? value;
  final bool bad;
  const LabParse._(this.value, this.bad);
  bool get blank => value == null && !bad;

  static LabParse of(String text) {
    final s = text.trim().replaceAll(RegExp(r'[\s\u00a0]'), '');
    if (s.isEmpty) return const LabParse._(null, false);
    if (s.contains(',') && s.contains('.')) return const LabParse._(null, true);
    final v = double.tryParse(s.replaceAll(',', '.'));
    if (v == null || !v.isFinite) return const LabParse._(null, true);
    return LabParse._(v, false);
  }
}

bool isLabCalendarDay(String day) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) return false;
  final p = day.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  return d.year == p[0] && d.month == p[1] && d.day == p[2];
}

/// One-sided bounds are allowed. Both present must be ordered.
String? labBoundsError(LabParse low, LabParse high) {
  if (low.bad || high.bad) return 'Bereich ist keine Zahl.';
  if (low.value != null && high.value != null && low.value! > high.value!) {
    return 'Untere Grenze liegt über der oberen.';
  }
  return null;
}

abstract interface class OpenBandRepository {
  Future<OpenBandDay> readDay(String day);
  Future<SetupEvaluation> readSetupEvaluation(String day);
  Future<NightSignals> readNightSignals(String day);
  Future<String> startStrengthSession(WorkoutTemplate template);
  Future<void> recordSet(String sessionId, RecordedSet set);
  Future<void> skipPlannedSet(String sessionId, String plannedSetId);
  Future<void> addPlannedSet(
    String sessionId,
    PlannedExercise exercise,
    PlannedSet set,
  );
  Future<void> skipRest(String sessionId);
  Future<void> extendRest(String sessionId, {int seconds = 30});
  Future<ActiveStrengthRuntime> readActiveStrengthSession();
  Future<Map<String, RecordedSet>> readPreviousStrengthSets(String sessionId);
  Future<void> finishStrengthSession(String sessionId);
  Future<MuscleLoad> readMuscleLoad(String endDay, int days);
  Future<List<FoodHit>> searchFoods(String query);
  Future<List<WorkoutTemplate>> readTemplates();
  Future<WorkoutTemplate> saveTemplate(WorkoutTemplate template);
  Future<void> archiveTemplate(String id);
  Future<String?> readPinnedTemplateId();
  Future<void> pinTemplate(String? id);
  Future<DayMeals> readMeals(String day);
  Future<MealDraft?> readMealDraft(String day, String meal);
  Future<void> saveMealDraft(MealDraft draft);
  Future<void> discardMealDraft(String draftId);
  Future<void> commitMealDraft(MealDraft draft);
  Future<SessionDetail?> readSessionDetail(String sessionId);
  Future<void> recordLap(String sessionId, Lap lap);
  Future<List<Lap>> readLaps(String sessionId);
  Future<PatternSummary> readPattern(
    String habitKey,
    MetricKey outcome,
    String endDay,
    int nights,
  );
  Future<List<JournalEntry>> readJournal(String day);
  Future<void> writeJournal(String day, String key, double value);
  Future<JournalDaySnapshot> readJournalDay(String day);
  Future<void> patchJournalDay(JournalDayPatch patch);
  Future<List<JournalFieldSpec>> listJournalFields({bool includeHidden = false});
  Future<JournalFieldSpec> createJournalField(JournalFieldSpec spec);
  Future<void> hideJournalField(String key);
  Future<void> restoreJournalField(String key);
  Future<List<TrainingSession>> readSessions(String endDay, int days);
  Future<List<MetricPoint>> readMetricHistory(
    MetricKey key,
    String endDay,
    int nights,
  );
  Future<Set<String>> sleepDays();
  Future<SleepDraft?> readDraft(String day);
  Future<void> saveDraft(SleepDraft draft);
  Future<void> discardDraft(String day);
  Future<SleepCorrection> saveCorrection(SleepDraft draft);
  Future<void> recalculate(SleepCorrection correction);
  Future<void> restoreAutomatic(String day);
  Future<NapDay> readNaps(String day);
  Future<int> addNap({
    required String day,
    required DateTime start,
    required DateTime end,
  });
  Future<int> editNap({
    required String day,
    required NapSession original,
    required DateTime start,
    required DateTime end,
  });
  Future<int> removeNap({required String day, required NapSession session});
  Future<int> restoreNap({required String day, required NapSession rejected});
  Future<void> recalculateNaps({required String day, required int revision});
  Future<SleepGoalSnapshot> readSleepGoal(String day);
  Future<void> saveSleepGoal(String day, int minutes);
  Future<void> clearSleepGoal(String day);
  Future<LabSnapshot> readLabs();
  Future<void> saveLabDraw(
    LabDraw draw, {
    LabDraw? replacing,
    bool replaceExisting = false,
  });
  Future<void> deleteLabDraw(String marker, String takenOn);
  Future<void> saveLabMarkerDef(LabMarkerDef def, {bool create = false});
  Future<void> deleteLabMarkerDef(String key);
}
