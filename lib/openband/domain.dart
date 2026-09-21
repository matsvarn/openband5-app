/// Typed boundary for the OpenBand daily flow. Only repositories decode maps.
library;

import '../data/journal_fields.dart';
import '../data/nutrition_store.dart';
import '../health/glucose_contract.dart';
import 'package:uuid/uuid.dart';
import 'cycle_comparison_data.dart';
import 'cycle_data.dart';
import 'cycle_measurements_data.dart';
import 'cycle_medians_data.dart';
import 'exercise_catalogue.dart';
import 'exercise_load.dart';
import 'medication_data.dart';
import 'night_scalar_data.dart';
import 'sleep_plan_data.dart';

export '../data/nutrition_store.dart'
    show FoodEntry, FoodSource, NutritionWindow, NutritionDay, NutrientTotal;
export '../health/glucose_contract.dart';
export 'cycle_comparison_data.dart';
export 'cycle_data.dart';
export 'cycle_measurements_data.dart';
export 'cycle_medians_data.dart';
export 'exercise_catalogue.dart';
export 'exercise_load.dart';
export 'medication_data.dart';
export 'night_scalar_data.dart';
export 'sleep_plan_data.dart';

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
  /// Typed night-scalar overlay for nightly scalar cards. Null on other metrics.
  final NightScalarState? nightScalar;
  const DayMetric(
    this.value, {
    this.readiness = MetricReadiness.available,
    this.reason,
    this.baseline,
    this.nightScalar,
  });
  const DayMetric.missing([this.reason])
    : value = null,
      baseline = null,
      readiness = MetricReadiness.missing,
      nightScalar = null;
}

/// Compact nightly-scalar card. Comparison [DayMetric.baseline] is only a current
/// complete scalar with stored status `trusted`. Typed detail keeps the rest.
DayMetric dayMetricFromNightScalar({
  required NightScalarState state,
  double? value,
  StoredNightBaseline? baseline,
}) {
  final cardBaseline = nightScalarCardBaseline(
    state: state,
    baseline: baseline,
  );
  switch (state) {
    case NightScalarState.pending:
      return DayMetric(
        null,
        readiness: MetricReadiness.processing,
        reason: kNightScalarPendingLabel,
        nightScalar: state,
      );
    case NightScalarState.failed:
      return DayMetric(
        null,
        readiness: MetricReadiness.missing,
        reason: kNightScalarFailedLabel,
        nightScalar: state,
      );
    case NightScalarState.unknown:
    case NightScalarState.outdated:
      return DayMetric(
        null,
        readiness: MetricReadiness.missing,
        reason: kNightScalarOpenLabel,
        nightScalar: state,
      );
    case NightScalarState.unreadable:
    case NightScalarState.missing:
      return DayMetric(
        null,
        readiness: MetricReadiness.missing,
        nightScalar: state,
      );
    case NightScalarState.partial:
      return DayMetric(
        nightScalarFinite(value),
        readiness: MetricReadiness.partial,
        reason: 'Ein Teil der Nacht wurde nicht erfasst.',
        nightScalar: state,
      );
    case NightScalarState.older:
      return DayMetric(
        nightScalarFinite(value),
        readiness: MetricReadiness.available,
        nightScalar: state,
      );
    case NightScalarState.current:
      return DayMetric(
        nightScalarFinite(value),
        readiness: MetricReadiness.available,
        baseline: cardBaseline,
        nightScalar: state,
      );
  }
}

List<MetricPoint> nightScalarHistoryPoints(NightScalarDetail detail) => [
  for (final n in detail.history)
    MetricPoint(n.day, n.value, partial: n.partial),
];

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
  final DayMetric recovery, strain, hrv, restingHr, respiration, steps;
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
    this.respiration = const DayMetric.missing(),
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
  final bool partial;
  const MetricPoint(this.day, this.value, {this.partial = false});
}

enum MetricKey {
  hrv('rmssd'),
  restingHr('rhr'),
  respiration('resp_rate'),
  recovery('readiness'),
  sleepDuration('tst_min'),
  strain('strain');

  final String series;
  const MetricKey(this.series);
}

NightScalarMetric nightScalarMetricOf(MetricKey key) => switch (key) {
  MetricKey.hrv => NightScalarMetric.hrv,
  MetricKey.restingHr => NightScalarMetric.rhr,
  MetricKey.respiration => NightScalarMetric.respiration,
  _ => throw ArgumentError.value(
    key,
    'key',
    'Night scalar detail is HRV, resting pulse, or respiration only.',
  ),
};

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

/// Fixed hypothesis: `caffeine_late` on journal day D versus stored `sol_min`
/// on wake day D+1. Group means are not on the producer and are never filled.
enum CaffeineSleepPatternKind {
  /// No supported pairs (empty/misaligned series, or a non-binary field).
  unavailable,

  /// Pairs exist but floors (minN / minPerSide / permutation history) refuse.
  insufficient,

  /// Binary comparison ran; size + FDR did not clear.
  nonmeaningful,

  /// Binary comparison ran and survived size + FDR.
  meaningful,
}

class CaffeineSleepPattern {
  static const field = 'caffeine_late';
  static const outcome = 'sol_min';
  static const lagDays = 1;
  static const title = 'Einschlafen · Koffein nach 14 Uhr';
  static const comparisonLabel = 'Ja gegenüber Nein';
  static const noClearPattern = 'Kein klares Muster';
  static const tooFewNights = 'Noch zu wenige Nächte';
  static const unavailableTitle = 'Noch kein Vergleich';
  static const unavailableDetail = 'Keine auswertbaren Nächte mit Eintrag';
  static const nightsWithEntry = 'Nächte mit Eintrag';
  static const partialLabel = 'Teilweise auswertbar';
  static const loadError = 'Vergleich konnte nicht geladen werden.';
  static const retryLabel = 'Erneut';
  static const infoTitle = 'Vergleich verstehen';
  static const infoComparison =
      'Verglichen wird die Einschlafdauer nach „Ja“ und „Nein“ zu Koffein nach 14 Uhr am Vortag.';
  static const infoEligibility =
      'Nur bestätigte oder korrigierte Nächte mit verfügbarer Einschlafdauer zählen. Fehlende Antworten bleiben offen.';
  static const infoCausation = 'Ein Zusammenhang belegt keine Ursache.';

  final CaffeineSleepPatternKind kind;
  final int pairedN;
  final int? yesNights;
  final int? noNights;
  final double? delta;
  final String? note;
  final String endDay;
  final String startDay;
  final int nights;
  final int algoVersion;

  /// True when some window inputs were rejected or ineligible.
  final bool partial;
  final int availableOutcomes;

  const CaffeineSleepPattern({
    required this.kind,
    required this.pairedN,
    this.yesNights,
    this.noNights,
    this.delta,
    this.note,
    required this.endDay,
    required this.startDay,
    required this.nights,
    required this.algoVersion,
    this.partial = false,
    this.availableOutcomes = 0,
  });

  /// Map one producer effect. Never invents yes/no counts or group means.
  factory CaffeineSleepPattern.fromProducer({
    required bool empty,
    required bool binary,
    required bool insufficient,
    required bool meaningful,
    required int n,
    int? nWith,
    int? nWithout,
    double? delta,
    String? note,
    required String endDay,
    required String startDay,
    required int nights,
    required int algoVersion,
    bool partial = false,
    int availableOutcomes = 0,
  }) {
    final countsOk = binary && nWith != null && nWithout != null;
    final kind = empty || n == 0 || (!binary && !insufficient)
        ? CaffeineSleepPatternKind.unavailable
        : insufficient
        ? CaffeineSleepPatternKind.insufficient
        : meaningful
        ? CaffeineSleepPatternKind.meaningful
        : CaffeineSleepPatternKind.nonmeaningful;
    final showSplit =
        countsOk &&
        (kind == CaffeineSleepPatternKind.meaningful ||
            kind == CaffeineSleepPatternKind.nonmeaningful);
    return CaffeineSleepPattern(
      kind: kind,
      pairedN: n,
      yesNights: showSplit ? nWith : null,
      noNights: showSplit ? nWithout : null,
      delta: showSplit ? delta : null,
      note: kind == CaffeineSleepPatternKind.insufficient ? note : null,
      endDay: endDay,
      startDay: startDay,
      nights: nights,
      algoVersion: algoVersion,
      partial: partial,
      availableOutcomes: availableOutcomes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CaffeineSleepPattern &&
      other.kind == kind &&
      other.pairedN == pairedN &&
      other.yesNights == yesNights &&
      other.noNights == noNights &&
      other.delta == delta &&
      other.note == note &&
      other.endDay == endDay &&
      other.startDay == startDay &&
      other.nights == nights &&
      other.algoVersion == algoVersion &&
      other.partial == partial &&
      other.availableOutcomes == availableOutcomes;

  @override
  int get hashCode => Object.hash(
    kind,
    pairedN,
    yesNights,
    noNights,
    delta,
    note,
    endDay,
    startDay,
    nights,
    algoVersion,
    partial,
    availableOutcomes,
  );
}

enum PlannedSetMode { repetitions, time }

class PlannedSet {
  final String id;
  final String type;
  final int? reps, seconds, restSec;
  final double? loadKg;
  final PlannedSetMode? mode;
  final OriginalLoadInput? load;
  const PlannedSet({
    required this.id,
    this.type = 'work',
    this.reps,
    this.seconds,
    this.restSec,
    this.loadKg,
    this.mode,
    this.load,
  });

  /// Explicit mode wins. Legacy JSON without [mode] is timed only when
  /// [seconds] is actually present; otherwise prior reps behavior stands.
  PlannedSetMode? get effectiveMode {
    if (mode != null) return mode;
    if (seconds != null) return PlannedSetMode.time;
    return null;
  }

  bool get isTimed => effectiveMode == PlannedSetMode.time;

  factory PlannedSet.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String? ?? '';
    if (id.isEmpty) {
      throw const FormatException('Planned set is missing a stable id.');
    }
    final reps = (j['reps'] as num?)?.toInt();
    final seconds = (j['seconds'] as num?)?.toInt();
    final mode = _parsePlannedSetMode(j['mode']);
    // Historical JSON without mode keeps both values. Reinterpreting
    // reps+seconds as one mode would invent a typed choice the row never had.
    if (mode != null) {
      if (reps != null && seconds != null) {
        throw const FormatException('Planned set has contradictory reps+time.');
      }
      if (mode == PlannedSetMode.repetitions && seconds != null) {
        throw const FormatException('Planned set has contradictory reps+time.');
      }
      if (mode == PlannedSetMode.time && reps != null) {
        throw const FormatException('Planned set has contradictory reps+time.');
      }
    }
    final load = _parseOriginalLoad(j['load']);
    final statedKg = _optionalFiniteLoad(j['loadKg']);
    final loadKg = load == null
        ? statedKg
        : load.basis == null
        ? statedKg
        : resolveStoredLoadKg(input: load, loadKg: statedKg);
    return PlannedSet(
      id: id,
      type: j['type'] as String? ?? 'work',
      reps: reps,
      seconds: seconds,
      restSec: (j['restSec'] as num?)?.toInt(),
      loadKg: loadKg,
      mode: mode,
      load: load,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'reps': reps,
    'seconds': seconds,
    'restSec': restSec,
    'loadKg': loadKg,
    if (mode != null) 'mode': mode!.name,
    if (load != null) 'load': load!.toJson(),
  };
}

OriginalLoadInput? _parseOriginalLoad(Object? raw) {
  if (raw == null) return null;
  if (raw is! Map) {
    throw const FormatException('Original load is unreadable.');
  }
  return OriginalLoadInput.fromJson(Map<String, dynamic>.from(raw));
}

double? _optionalFiniteLoad(Object? raw) {
  if (raw == null) return null;
  if (raw is! num || !raw.isFinite) {
    throw const FormatException('Planned set load is unreadable.');
  }
  return raw.toDouble();
}

PlannedSetMode? _parsePlannedSetMode(Object? raw) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException('Planned set mode is unreadable.');
  }
  return switch (raw) {
    'repetitions' => PlannedSetMode.repetitions,
    'time' => PlannedSetMode.time,
    _ => throw const FormatException('Planned set mode is unreadable.'),
  };
}

class PlannedExercise {
  final String id, exerciseKey, name;
  final List<PlannedSet> sets;
  final String note;
  final ExerciseDefinitionSnapshot? definition;
  const PlannedExercise({
    required this.id,
    required this.exerciseKey,
    required this.name,
    required this.sets,
    this.note = '',
    this.definition,
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
    final rawDefinition = j['definition'];
    ExerciseDefinitionSnapshot? definition;
    if (rawDefinition != null) {
      if (rawDefinition is! Map) {
        throw const FormatException('Exercise definition snapshot is unreadable.');
      }
      definition = ExerciseDefinitionSnapshot.fromJson(
        Map<String, dynamic>.from(rawDefinition),
      );
      if (definition.id != exerciseKey) {
        throw const FormatException(
          'Exercise definition snapshot is unreadable.',
        );
      }
    }
    return PlannedExercise(
      id: id,
      exerciseKey: exerciseKey,
      name: name,
      sets: [
        for (final s in rawSets) PlannedSet.fromJson(s as Map<String, dynamic>),
      ],
      note: j['note'] as String? ?? '',
      definition: definition,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'exerciseKey': exerciseKey,
    'name': name,
    'sets': [for (final s in sets) s.toJson()],
    'note': note,
    if (definition != null) 'definition': definition!.toJson(),
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
          timed: s.isTimed,
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
          definition: e.definition,
          sets: [
            for (final s in e.sets)
              PlannedSet(
                id: next(),
                type: s.type,
                reps: s.reps,
                seconds: s.seconds,
                restSec: s.restSec,
                loadKg: s.loadKg,
                mode: s.mode,
                load: s.load,
              ),
          ],
        ),
    ],
    updatedAt: at ?? DateTime.now(),
  );
}

/// Known enum wins over a conflicting [sourceCode]. [FoodSource.unknown]
/// uses the exact code, which may itself be a known name (`photo`).
({FoodSource source, String code}) canonicalFoodSource(
  FoodSource source, {
  String? sourceCode,
}) {
  final entry = FoodEntry(
    id: '_',
    date: '2000-01-01',
    meal: 'snack',
    label: '_',
    source: source,
    sourceCode: sourceCode,
  );
  return (source: entry.source, code: entry.sourceCode);
}

/// Decode stored `source` TEXT through [FoodEntry]. Null is the schema
/// default (`manual`); empty and any other unknown string stay unknown with
/// that exact code.
({FoodSource source, String code}) decodeFoodSource(String? raw) =>
    canonicalFoodSource(
      raw == null ? FoodSource.manual : FoodSource.unknown,
      sourceCode: raw,
    );

/// Exact persisted comparison. [ledger] includes created/updated stamps.
/// Source equality is the wire code, including future unknown values.
bool foodEntriesEqual(FoodEntry a, FoodEntry b, {bool ledger = true}) =>
    a.id == b.id &&
    a.date == b.date &&
    a.meal == b.meal &&
    a.label == b.label &&
    a.atTs == b.atTs &&
    a.foodKey == b.foodKey &&
    a.quantity == b.quantity &&
    a.unit == b.unit &&
    a.kcal == b.kcal &&
    a.proteinG == b.proteinG &&
    a.carbsG == b.carbsG &&
    a.fatG == b.fatG &&
    a.fibreG == b.fibreG &&
    a.sugarG == b.sugarG &&
    a.satFatG == b.satFatG &&
    a.sodiumMg == b.sodiumMg &&
    a.ironMg == b.ironMg &&
    a.calciumMg == b.calciumMg &&
    a.sourceCode == b.sourceCode &&
    a.confirmed == b.confirmed &&
    a.note == b.note &&
    (!ledger || (a.createdAt == b.createdAt && a.updatedAt == b.updatedAt));

void requireFoodEntryWrite(FoodEntry e) {
  if (e.id.trim().isEmpty) {
    throw ArgumentError.value(e.id, 'id', 'Food id is required.');
  }
  if (e.label.trim().isEmpty) {
    throw ArgumentError.value(e.label, 'label', 'Food label is required.');
  }
  if (e.meal.trim().isEmpty) {
    throw ArgumentError.value(e.meal, 'meal', 'Meal is required.');
  }
  if (!isLabCalendarDay(e.date)) {
    throw ArgumentError.value(e.date, 'date', 'Expected a real YYYY-MM-DD day.');
  }
  if (e.unit.trim().isEmpty) {
    throw ArgumentError.value(e.unit, 'unit', 'Unit is required.');
  }
  if (e.atTs != null && e.atTs! < 0) {
    throw ArgumentError.value(e.atTs, 'atTs', 'Consumed-at must be nonnegative.');
  }
  void amount(double? value, String name) {
    if (value == null) return;
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(
        value,
        name,
        'Quantity and nutrients must be finite and nonnegative when set.',
      );
    }
  }

  amount(e.quantity, 'quantity');
  amount(e.kcal, 'kcal');
  amount(e.proteinG, 'proteinG');
  amount(e.carbsG, 'carbsG');
  amount(e.fatG, 'fatG');
  amount(e.fibreG, 'fibreG');
  amount(e.sugarG, 'sugarG');
  amount(e.satFatG, 'satFatG');
  amount(e.sodiumMg, 'sodiumMg');
  amount(e.ironMg, 'ironMg');
  amount(e.calciumMg, 'calciumMg');
}

enum FoodSnapshotStatus { saved, conflict }

/// Optimistic food-row outcome. Missing is [conflict] with no [current].
/// A thrown read/write error is distinct.
class FoodSnapshotResult {
  final FoodSnapshotStatus status;
  final FoodEntry? current;
  const FoodSnapshotResult._(this.status, this.current);
  const FoodSnapshotResult.saved([FoodEntry? current])
    : this._(FoodSnapshotStatus.saved, current);
  const FoodSnapshotResult.conflict([FoodEntry? current])
    : this._(FoodSnapshotStatus.conflict, current);
  bool get saved => status == FoodSnapshotStatus.saved;
  bool get conflict => status == FoodSnapshotStatus.conflict;
  bool get missing => conflict && current == null;
}

/// Outcome of [OpenBandRepository.commitMealDraft]. Distinct from
/// [FoodSnapshotResult]: draft drift is [conflict], never a missing food row.
enum MealDraftCommitResult { saved, conflict }

/// Outcome of [OpenBandRepository.compareAndSaveMealDraft]. Conflict writes
/// nothing; [saved] means the durable retained row is committed.
enum MealDraftSaveResult { saved, conflict }

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
  final double? fibreG, sugarG, satFatG, sodiumMg, ironMg, calciumMg;
  final String? foodKey;
  final FoodSource? source;
  final String? sourceCode;
  final bool? confirmed;
  final String? note;
  final int? atTs, createdAt, updatedAt;
  const MealDraftEntry({
    required this.id,
    required this.label,
    this.quantity,
    this.unit = 'g',
    this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fibreG,
    this.sugarG,
    this.satFatG,
    this.sodiumMg,
    this.ironMg,
    this.calciumMg,
    this.foodKey,
    this.source,
    this.sourceCode,
    this.confirmed,
    this.note,
    this.atTs,
    this.createdAt,
    this.updatedAt,
  });
  factory MealDraftEntry.fromJson(Map<String, dynamic> j) {
    double? d(String k) => (j[k] as num?)?.toDouble();
    int? i(String k) => (j[k] as num?)?.toInt();
    FoodSource? source;
    String? sourceCode;
    if (j.containsKey('source')) {
      final decoded = decodeFoodSource(j['source'] as String?);
      source = decoded.source;
      sourceCode = decoded.code;
    }
    bool? confirmed;
    final rawConfirmed = j['confirmed'];
    if (rawConfirmed is bool) {
      confirmed = rawConfirmed;
    } else if (rawConfirmed is num) {
      confirmed = rawConfirmed != 0;
    }
    return MealDraftEntry(
      id: j['id'] as String,
      label: j['label'] as String,
      quantity: d('quantity'),
      unit: j['unit'] as String? ?? 'g',
      kcal: d('kcal'),
      proteinG: d('proteinG'),
      carbsG: d('carbsG'),
      fatG: d('fatG'),
      fibreG: d('fibreG'),
      sugarG: d('sugarG'),
      satFatG: d('satFatG'),
      sodiumMg: d('sodiumMg'),
      ironMg: d('ironMg'),
      calciumMg: d('calciumMg'),
      foodKey: j['foodKey'] as String?,
      source: source,
      sourceCode: sourceCode,
      confirmed: confirmed,
      note: j['note'] as String?,
      atTs: i('atTs'),
      createdAt: i('createdAt'),
      updatedAt: i('updatedAt'),
    );
  }
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
    if (fibreG != null) 'fibreG': fibreG,
    if (sugarG != null) 'sugarG': sugarG,
    if (satFatG != null) 'satFatG': satFatG,
    if (sodiumMg != null) 'sodiumMg': sodiumMg,
    if (ironMg != null) 'ironMg': ironMg,
    if (calciumMg != null) 'calciumMg': calciumMg,
    if (source != null || sourceCode != null)
      'source': canonicalFoodSource(
        source ?? FoodSource.unknown,
        sourceCode: sourceCode,
      ).code,
    if (confirmed != null) 'confirmed': confirmed,
    if (note != null) 'note': note,
    if (atTs != null) 'atTs': atTs,
    if (createdAt != null) 'createdAt': createdAt,
    if (updatedAt != null) 'updatedAt': updatedAt,
  };

  @override
  bool operator ==(Object other) =>
      other is MealDraftEntry &&
      other.id == id &&
      other.label == label &&
      other.quantity == quantity &&
      other.unit == unit &&
      other.kcal == kcal &&
      other.proteinG == proteinG &&
      other.carbsG == carbsG &&
      other.fatG == fatG &&
      other.fibreG == fibreG &&
      other.sugarG == sugarG &&
      other.satFatG == satFatG &&
      other.sodiumMg == sodiumMg &&
      other.ironMg == ironMg &&
      other.calciumMg == calciumMg &&
      other.foodKey == foodKey &&
      other.source == source &&
      other.sourceCode == sourceCode &&
      other.confirmed == confirmed &&
      other.note == note &&
      other.atTs == atTs &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll([
    id,
    label,
    quantity,
    unit,
    kcal,
    proteinG,
    carbsG,
    fatG,
    fibreG,
    sugarG,
    satFatG,
    sodiumMg,
    ironMg,
    calciumMg,
    foodKey,
    source,
    sourceCode,
    confirmed,
    note,
    atTs,
    createdAt,
    updatedAt,
  ]);
}

FoodEntry foodEntryFromDraft(MealDraft draft, MealDraftEntry e) {
  final uiManual = e.source == null && e.sourceCode == null;
  final decoded = uiManual
      ? (source: FoodSource.manual, code: 'manual')
      : canonicalFoodSource(
          e.source ?? FoodSource.unknown,
          sourceCode: e.sourceCode,
        );
  return FoodEntry(
    id: e.id,
    date: draft.day,
    meal: draft.meal,
    label: e.label,
    atTs: e.atTs,
    foodKey: e.foodKey,
    quantity: e.quantity,
    unit: e.unit,
    kcal: e.kcal,
    proteinG: e.proteinG,
    carbsG: e.carbsG,
    fatG: e.fatG,
    fibreG: e.fibreG,
    sugarG: e.sugarG,
    satFatG: e.satFatG,
    sodiumMg: e.sodiumMg,
    ironMg: e.ironMg,
    calciumMg: e.calciumMg,
    source: decoded.source,
    sourceCode: decoded.code,
    confirmed: e.confirmed ?? uiManual,
    note: e.note ?? '',
    createdAt: e.createdAt,
    updatedAt: e.updatedAt,
  );
}

void requireMealDraftWrite(MealDraft draft) {
  if (!isLabCalendarDay(draft.day)) {
    throw ArgumentError.value(
      draft.day,
      'day',
      'Expected a real YYYY-MM-DD day.',
    );
  }
  if (draft.id.trim().isEmpty) {
    throw ArgumentError.value(draft.id, 'id', 'Draft id is required.');
  }
  if (draft.meal.trim().isEmpty) {
    throw ArgumentError.value(draft.meal, 'meal', 'Meal is required.');
  }
  final seen = <String>{};
  for (final entry in draft.entries) {
    requireFoodEntryWrite(foodEntryFromDraft(draft, entry));
    if (!seen.add(entry.id)) {
      throw ArgumentError.value(
        entry.id,
        'id',
        'Draft entry ids must be unique.',
      );
    }
  }
}

void requireMealDraftCompare({
  required MealDraft? expected,
  required MealDraft draft,
}) {
  requireMealDraftWrite(draft);
  if (expected != null &&
      (expected.day != draft.day || expected.meal != draft.meal)) {
    throw ArgumentError(
      'Draft day and meal must match the expected slot.',
    );
  }
}

/// Persisted draft revision: never equal or behind the row we just observed.
int nextMealDraftRevision(int? storedRevision, int clockNow) {
  if (storedRevision == null) return clockNow;
  return clockNow > storedRevision ? clockNow : storedRevision + 1;
}

/// Canonical retained-draft comparison: slot identity, revision timestamp,
/// and full entry snapshots after [MealDraftEntry.toJson] round-trip.
/// Legacy omitted optional keys match a reread; extra unknown JSON keys are
/// not part of the typed snapshot. Invalid JSON must throw, not save.
bool mealDraftRevisionMatches(MealDraft expected, MealDraft observed) {
  if (expected.id != observed.id ||
      expected.day != observed.day ||
      expected.meal != observed.meal ||
      expected.updatedAt.millisecondsSinceEpoch !=
          observed.updatedAt.millisecondsSinceEpoch ||
      expected.entries.length != observed.entries.length) {
    return false;
  }
  for (var i = 0; i < expected.entries.length; i++) {
    if (MealDraftEntry.fromJson(expected.entries[i].toJson()) !=
        MealDraftEntry.fromJson(observed.entries[i].toJson())) {
      return false;
    }
  }
  return true;
}

/// Saved food entries of one day, grouped by meal, with per-nutrient totals
/// that stay a lower bound when any entry lacks the nutrient.
class MealEntry {
  final String id, meal, label;
  final double? kcal, proteinG, carbsG, fatG;
  final double? fibreG, sugarG, satFatG, sodiumMg, ironMg, calciumMg;
  final String? foodKey;
  final double? quantity;
  final String unit;
  final FoodSource source;
  final String sourceCode;
  final bool confirmed;
  final String note;
  final int? atTs, createdAt, updatedAt;
  const MealEntry({
    required this.id,
    required this.meal,
    required this.label,
    this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fibreG,
    this.sugarG,
    this.satFatG,
    this.sodiumMg,
    this.ironMg,
    this.calciumMg,
    this.foodKey,
    this.quantity,
    this.unit = 'g',
    this.source = FoodSource.manual,
    this.sourceCode = 'manual',
    this.confirmed = false,
    this.note = '',
    this.atTs,
    this.createdAt,
    this.updatedAt,
  });

  factory MealEntry.fromFood(FoodEntry e) => MealEntry(
    id: e.id,
    meal: e.meal,
    label: e.label,
    kcal: e.kcal,
    proteinG: e.proteinG,
    carbsG: e.carbsG,
    fatG: e.fatG,
    fibreG: e.fibreG,
    sugarG: e.sugarG,
    satFatG: e.satFatG,
    sodiumMg: e.sodiumMg,
    ironMg: e.ironMg,
    calciumMg: e.calciumMg,
    foodKey: e.foodKey,
    quantity: e.quantity,
    unit: e.unit,
    source: e.source,
    sourceCode: e.sourceCode,
    confirmed: e.confirmed,
    note: e.note,
    atTs: e.atTs,
    createdAt: e.createdAt,
    updatedAt: e.updatedAt,
  );
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
  final OriginalLoadInput? load;
  final ExerciseDefinitionSnapshot? definition;
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
    this.load,
    this.definition,
  });
}

/// Copy the plan snapshot onto a live set and resolve [loadKg] from original
/// input. Identified sets must match the plan exercise; later definition
/// edits cannot rewrite this snapshot.
RecordedSet bindRecordedStrengthSet({
  required RecordedSet set,
  String? planExerciseId,
  String? planExerciseKey,
  ExerciseDefinitionSnapshot? planDefinition,
}) {
  final identity = set.plannedSetId != null && set.plannedSetId!.isNotEmpty;
  if (identity &&
      set.exerciseId != null &&
      planExerciseId != null &&
      set.exerciseId != planExerciseId) {
    throw ArgumentError.value(set.exerciseId, 'exerciseId');
  }
  if (identity &&
      planExerciseKey != null &&
      set.exerciseKey != planExerciseKey) {
    throw ArgumentError.value(set.exerciseKey, 'exerciseKey');
  }
  if (set.definition != null &&
      set.definition!.id != set.exerciseKey) {
    throw const FormatException('Exercise definition snapshot is unreadable.');
  }
  if (planDefinition != null && planDefinition.id != set.exerciseKey) {
    throw const FormatException('Exercise definition snapshot is unreadable.');
  }
  ExerciseDefinitionSnapshot? definition;
  if (identity && planDefinition != null) {
    if (set.definition != null &&
        !customExerciseSnapshotsEqual(set.definition!, planDefinition)) {
      throw const FormatException(
        'Recorded definition contradicts the plan snapshot.',
      );
    }
    definition = planDefinition;
  } else {
    definition = set.definition ?? planDefinition;
  }
  final loadKg = set.load == null
      ? set.loadKg
      : set.load!.basis == null
      ? set.loadKg
      : resolveStoredLoadKg(input: set.load, loadKg: set.loadKg);
  return RecordedSet(
    exerciseKey: set.exerciseKey,
    setIndex: set.setIndex,
    reps: set.reps,
    seconds: set.seconds,
    loadKg: loadKg,
    at: set.at,
    plannedSetId: set.plannedSetId,
    exerciseId: set.exerciseId,
    restSec: set.restSec,
    load: set.load,
    definition: definition,
  );
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
  final String key, label, brand, servingLabel;
  final double? servingG,
      kcal100,
      proteinG100,
      carbsG100,
      fatG100,
      fibreG100,
      sugarG100,
      satFatG100,
      sodiumMg100,
      ironMg100,
      calciumMg100;
  final FoodSource source;
  final String sourceCode;
  const FoodHit({
    required this.key,
    required this.label,
    this.brand = '',
    this.servingG,
    this.servingLabel = '',
    this.kcal100,
    this.proteinG100,
    this.carbsG100,
    this.fatG100,
    this.fibreG100,
    this.sugarG100,
    this.satFatG100,
    this.sodiumMg100,
    this.ironMg100,
    this.calciumMg100,
    this.source = FoodSource.manual,
    this.sourceCode = 'manual',
  });

  factory FoodHit.fromDef(Map<String, Object?> r) {
    double? d(String k) => (r[k] as num?)?.toDouble();
    final decoded = decodeFoodSource(r['source'] as String?);
    return FoodHit(
      key: r['key'] as String,
      label: r['label'] as String,
      brand: r['brand'] as String? ?? '',
      servingG: d('serving_g'),
      servingLabel: r['serving_label'] as String? ?? '',
      kcal100: d('kcal_100'),
      proteinG100: d('protein_g_100'),
      carbsG100: d('carbs_g_100'),
      fatG100: d('fat_g_100'),
      fibreG100: d('fibre_g_100'),
      sugarG100: d('sugar_g_100'),
      satFatG100: d('sat_fat_g_100'),
      sodiumMg100: d('sodium_mg_100'),
      ironMg100: d('iron_mg_100'),
      calciumMg100: d('calcium_mg_100'),
      source: decoded.source,
      sourceCode: decoded.code,
    );
  }

  MealDraftEntry portion(String id, double grams) {
    double? per(double? v100) => v100 == null ? null : v100 * grams / 100;
    final decoded = canonicalFoodSource(source, sourceCode: sourceCode);
    return MealDraftEntry(
      id: id,
      label: label,
      quantity: grams,
      unit: 'g',
      kcal: per(kcal100),
      proteinG: per(proteinG100),
      carbsG: per(carbsG100),
      fatG: per(fatG100),
      fibreG: per(fibreG100),
      sugarG: per(sugarG100),
      satFatG: per(satFatG100),
      sodiumMg: per(sodiumMg100),
      ironMg: per(ironMg100),
      calciumMg: per(calciumMg100),
      foodKey: key,
      source: decoded.source,
      sourceCode: decoded.code,
      confirmed: true,
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

/// Where an effective nutrition target came from. Null origin on a snapshot
/// means no goal applies — never a default or a borrowed historical date.
enum NutritionTargetOrigin { dated, legacyUndated }

enum NutritionTargetWriteStatus { saved, conflict }

/// One optional energy/macro set. Null is unset. Zero grams is explicit.
class NutritionTargetValues {
  final double? energyKcal, proteinG, carbohydrateG, fatG;
  const NutritionTargetValues({
    this.energyKcal,
    this.proteinG,
    this.carbohydrateG,
    this.fatG,
  });

  static const empty = NutritionTargetValues();

  bool get hasAny =>
      energyKcal != null ||
      proteinG != null ||
      carbohydrateG != null ||
      fatG != null;
}

/// Effective targets for a selected local day.
///
/// [values] and [revision] always come from one dated row, or from the undated
/// prefs blob. [revision] is that row's revision only when [effectiveDay]
/// equals [day]; an inherited earlier boundary keeps [revision] null so a
/// write here is a new date. [legacyUndated] has no start date: [effectiveDay]
/// and [revision] stay null — never today's label as a fabricated origin.
class NutritionTargetSnapshot {
  final String day;
  final NutritionTargetValues values;
  final NutritionTargetOrigin? origin;
  final String? effectiveDay;
  final int? revision;
  const NutritionTargetSnapshot({
    required this.day,
    this.values = const NutritionTargetValues(),
    this.origin,
    this.effectiveDay,
    this.revision,
  }) : assert(
         origin != NutritionTargetOrigin.legacyUndated ||
             (effectiveDay == null && revision == null),
         'legacyUndated must not invent an effectiveDay',
       );
}

/// An actual dated change. Empty values are a stored "no target" boundary.
class NutritionTargetChange {
  final String validFromDay;
  final NutritionTargetValues values;
  final int revision;
  final DateTime createdAt, updatedAt;
  const NutritionTargetChange({
    required this.validFromDay,
    required this.values,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// Optimistic write outcome. [conflict] preserves the stored row.
class NutritionTargetWriteResult {
  final NutritionTargetWriteStatus status;
  final NutritionTargetChange? row;
  const NutritionTargetWriteResult._(this.status, this.row);
  const NutritionTargetWriteResult.saved(NutritionTargetChange row)
    : this._(NutritionTargetWriteStatus.saved, row);
  const NutritionTargetWriteResult.conflict([NutritionTargetChange? row])
    : this._(NutritionTargetWriteStatus.conflict, row);
  bool get saved => status == NutritionTargetWriteStatus.saved;
  bool get conflict => status == NutritionTargetWriteStatus.conflict;
}

void requireNutritionTargetValues(NutritionTargetValues values) {
  void energy(double? value, String name) {
    if (value == null) return;
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(
        value,
        name,
        'Energy must be a finite positive value when set.',
      );
    }
  }

  void grams(double? value, String name) {
    if (value == null) return;
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(
        value,
        name,
        'Gram targets must be finite and nonnegative when set.',
      );
    }
  }

  energy(values.energyKcal, 'energyKcal');
  grams(values.proteinG, 'proteinG');
  grams(values.carbohydrateG, 'carbohydrateG');
  grams(values.fatG, 'fatG');
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
  Future<ExerciseCatalogue> readExerciseCatalogue();
  Future<CustomExerciseWriteResult> createCustomExercise(
    CustomExerciseDraft draft,
  );
  Future<CustomExerciseWriteResult> updateCustomExercise({
    required ExerciseDefinitionSnapshot expected,
    required CustomExerciseDraft draft,
  });
  Future<List<FoodHit>> searchFoods(String query);
  Future<List<WorkoutTemplate>> readTemplates();
  Future<WorkoutTemplate> saveTemplate(WorkoutTemplate template);
  Future<void> archiveTemplate(String id);
  Future<String?> readPinnedTemplateId();
  Future<void> pinTemplate(String? id);
  Future<DayMeals> readMeals(String day);
  Future<NutritionWindow> readNutritionWindow(String endDay, {int days = 7});
  Future<List<FoodEntry>> readRecentFoods({int limit = 12});
  Future<FoodSnapshotResult> readFoodEntry(String id);
  Future<FoodSnapshotResult> saveFoodEntry(FoodEntry expected, FoodEntry next);
  Future<FoodSnapshotResult> removeFoodEntry(FoodEntry expected);
  Future<FoodSnapshotResult> restoreFoodEntry(FoodEntry snapshot);
  Future<MealDraft?> readMealDraft(String day, String meal);
  Future<void> saveMealDraft(MealDraft draft);
  /// Compare-and-save the retained draft for one day+meal slot.
  /// [expected] null means the slot must be absent. Non-null [expected] must
  /// match the retained snapshot. [saved] means the row is committed; reread
  /// for the persisted revision timestamp. Conflict writes nothing.
  Future<MealDraftSaveResult> compareAndSaveMealDraft({
    required MealDraft? expected,
    required MealDraft draft,
  });
  Future<void> discardMealDraft(String draftId);
  /// New inserts need a present matching retained draft. If the draft is
  /// already gone, succeeds only when every saved row already matches, with
  /// no writes. Draft mismatch is [MealDraftCommitResult.conflict], not a
  /// missing food row, and this result does not carry a [FoodEntry].
  Future<MealDraftCommitResult> commitMealDraft(MealDraft draft);
  Future<SessionDetail?> readSessionDetail(String sessionId);
  Future<void> recordLap(String sessionId, Lap lap);
  Future<List<Lap>> readLaps(String sessionId);
  /// Caffeine × stored SOL. [nights] must be at least 1.
  Future<CaffeineSleepPattern> readCaffeineSleepPattern(
    String endDay,
    int nights,
  );
  Future<List<JournalEntry>> readJournal(String day);
  Future<void> writeJournal(String day, String key, double value);
  Future<JournalDaySnapshot> readJournalDay(String day);
  Future<void> patchJournalDay(JournalDayPatch patch);
  /// Signed `journal_metric.water_ml` delta. Returns the committed amount
  /// without a follow-up read; null means the field is absent.
  Future<double?> adjustWater(String day, double deltaMl);
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
  /// Stored RMSSD / resting-pulse / respiration night scalar for [day], plus a
  /// 7/30/90 local-calendar history at the selected row's algorithm. [key] is
  /// HRV, resting pulse, or respiration. Pending or failed sleep/nap receipts
  /// withhold the hero and that history day; a finite stored scalar stays on
  /// [NightScalarDetail.storedForInfo]. Database failure throws.
  Future<NightScalarDetail> readNightScalarDetail(
    MetricKey key,
    String day,
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
  /// Coming night only. [now] is local-clock injectable; historical days
  /// return unavailable and never today's forecast.
  Future<SleepPlanSnapshot> readSleepPlan(String day, {DateTime? now});
  Future<NutritionTargetSnapshot> readNutritionTargets(String day);
  Future<List<NutritionTargetChange>> listNutritionTargetChanges();
  Future<NutritionTargetWriteResult> saveNutritionTargets(
    String day,
    NutritionTargetValues values, {
    int? expectedRevision,
  });
  Future<NutritionTargetWriteResult> clearNutritionTargets(
    String day, {
    int? expectedRevision,
  });
  Future<LabSnapshot> readLabs();
  Future<void> saveLabDraw(
    LabDraw draw, {
    LabDraw? replacing,
    bool replaceExisting = false,
  });
  Future<void> deleteLabDraw(String marker, String takenOn);
  Future<void> saveLabMarkerDef(LabMarkerDef def, {bool create = false});
  Future<void> deleteLabMarkerDef(String key);
  /// Newest [limit] history rows for the selected source. Null [limit] is an
  /// explicit full-source request. Series is the latest local calendar day,
  /// independent of [limit]. Inventory counts are all-time stored rows.
  Future<GlucoseSnapshot> readGlucose({String? sourceKey, int? limit});
  /// Durable import result is [GlucoseImportResult.outcome] even when the
  /// optional snapshot refresh fails. [GlucoseImportResult.refreshFailed]
  /// means stored rows were not reread; it is not an empty history. Snapshot
  /// refresh uses the hero history window (`limit: 1`), not a full-source scan.
  Future<GlucoseImportResult> importGlucose({DateTime? now});
  Future<void> setGlucoseSourceIncluded(
    String sourceKey, {
    required bool included,
  });
  /// Selected local civil day. Union of then-effective scheduled slots and
  /// every retained dose row. Missing answer is [MedicationSlotStatus.unknown],
  /// never skipped. [now] is injectable.
  Future<MedicationDay> readMedicationDay(String day, {DateTime? now});
  /// Current plan heads. Identity is the stable key, never a name slug.
  Future<List<MedicationPlan>> readMedicationPlans({bool activeOnly = true});
  Future<MedicationHistory> readMedicationHistory(
    String fromDay,
    String toDay, {
    DateTime? now,
  });
  /// Create or update. Missing update refuses. [MedicationMutationResult.committed]
  /// means the row is stored; [MedicationMutationResult.remindersFailed] must
  /// not retry the write.
  Future<MedicationMutationResult> saveMedicationPlan(
    MedicationPlanDraft draft, {
    DateTime? now,
  });
  Future<MedicationMutationResult> endMedicationPlan(
    String key, {
    DateTime? now,
  });
  Future<MedicationMutationResult> restartMedicationPlan(
    String key, {
    DateTime? now,
  });
  /// taken / skipped / clear. New rows freeze known slot metadata; updates
  /// preserve the original snapshot including nulls. Clear restores unknown
  /// and does not delete the plan.
  Future<MedicationMutationResult> saveMedicationEntry(
    MedicationEntryDraft draft, {
    DateTime? now,
  });
  /// Retry-only reminder refresh after [MedicationMutationResult.remindersFailed].
  /// Must not write plans or doses. Local delegates [AppState.refreshAiReminders].
  Future<void> refreshMedicationReminders();

  /// Runtime-owned profile/prefs. Strict parse throws; missing estimate and
  /// length-review keys default off. Local delegates AppState.
  Future<CycleSettings> readCycleSettings();
  Future<CycleWriteResult> saveCycleSettings(CycleSettings settings);

  /// Selected civil day. Valid starts/observations as-of that day. Entire read
  /// failure throws; a sibling bad row counts [CycleSnapshot.unreadableCount].
  /// [CycleSnapshot.unreadableStarts] is start-source trust, independent of
  /// estimate settings; [CycleSnapshot.cycleDay] is null when that is true.
  Future<CycleSnapshot> readCycle(String day, {DateTime? now});

  /// Measured nocturnal RHR and session HRV for the logged cycle containing
  /// [asOfDay], or the cycle that starts on [cycleStartDay] when that start is
  /// an actual readable start on or before [asOfDay]. A missing or deleted
  /// selected start is a typed reason with [CycleMeasurementsSnapshot.selected]
  /// null and no nights, never another cycle; remaining readable periods stay
  /// on the snapshot. Nested present-but-malformed RHR/HRV set
  /// [CycleNightMeasurement.rhrUnreadable] / [CycleNightMeasurement.hrvUnreadable]
  /// without dropping a valid sibling; out-of-range stored confidence is
  /// [CycleNightMetric.confidenceUnreadable] with confidence left null.
  /// Database failure throws; it is not an empty snapshot.
  Future<CycleMeasurementsSnapshot> readCycleMeasurements(
    String asOfDay, {
    String? cycleStartDay,
  });

  /// Twelve-calendar-month medians ending on [anchorEnd], paged by whole-year
  /// [pageOffset]. [anchorEnd] is an independent civil end date, not today;
  /// it must exist and must not follow local today of [now] (clock default).
  /// Tracking off, no contributing starts, or unreadable starts do not decode
  /// day payloads. Database failure throws.
  Future<CycleMediansSnapshot> readCycleMedians(
    String anchorEnd, {
    int pageOffset = 0,
    DateTime? now,
  });

  /// Twelve-calendar-month latest-night comparison ending on [anchorEnd],
  /// paged by whole-year [pageOffset]. Reuses [cycleMedianWindow]. [anchorEnd]
  /// is an independent civil end date, not today; it must exist and must not
  /// follow local today of [now] (clock default). Tracking off does not decode
  /// day payloads. Latest and prior-21 do not require starts. Same-cycle-day
  /// comparison withholds on unreadable starts, empty starts, or an unassigned
  /// latest. Per-metric latest is available, missing, unavailable (refused
  /// window source) or unreadable (corrupt/duplicate window source). Snapshot
  /// excluded/unreadable counts cover the displayed year and selected prior-21
  /// ranges, not unused query padding. Database failure throws.
  Future<CycleComparisonSnapshot> readCycleComparison(
    String anchorEnd, {
    int pageOffset = 0,
    DateTime? now,
  });

  /// Compare-and-swap. [expected] null creates. A changed date checks source
  /// and destination in one transaction and never overwrites another start.
  /// Already-matching current returns committed before the expected check.
  Future<CycleWriteResult> saveCycleStart(
    CycleStart desired, {
    CycleStart? expected,
    DateTime? now,
  });
  Future<CycleWriteResult> removeCycleStart(CycleStart expected);
  Future<CycleWriteResult> restoreCycleStart(CycleStart removed, {DateTime? now});
  Future<CycleWriteResult> saveCycleObservation(
    CycleObservation desired, {
    CycleObservation? expected,
    DateTime? now,
  });

  /// Retry-only after [CycleWriteResult.contextRefreshFailed]. Must not write
  /// starts or observations. Runtime implements AppState.refreshCycleContext.
  Future<void> refreshCycleContext();
}
