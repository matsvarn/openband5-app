/// Typed boundary for the OpenBand daily flow. Only repositories decode maps.
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
  recovery('readiness');

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
  factory PlannedSet.fromJson(Map<String, dynamic> j) => PlannedSet(
    id: j['id'] as String,
    type: j['type'] as String? ?? 'work',
    reps: (j['reps'] as num?)?.toInt(),
    seconds: (j['seconds'] as num?)?.toInt(),
    restSec: (j['restSec'] as num?)?.toInt(),
    loadKg: (j['loadKg'] as num?)?.toDouble(),
  );
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
  factory PlannedExercise.fromJson(Map<String, dynamic> j) => PlannedExercise(
    id: j['id'] as String,
    exerciseKey: j['exerciseKey'] as String,
    name: j['name'] as String,
    sets: [
      for (final s in j['sets'] as List)
        PlannedSet.fromJson(s as Map<String, dynamic>),
    ],
    note: j['note'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'exerciseKey': exerciseKey,
    'name': name,
    'sets': [for (final s in sets) s.toJson()],
    'note': note,
  };
}

/// A plan. Starting it creates a session snapshot; confirming a set turns it
/// into a recorded strength_set row. Editing the template never changes a
/// recorded session (B23).
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
  };
}

class SessionSplit {
  final int km, seconds;
  final double? avgHr;
  const SessionSplit({required this.km, required this.seconds, this.avgHr});
}

/// A confirmed set. Bodyweight is not a load of 0 kg: [loadKg] stays null.
class RecordedSet {
  final String exerciseKey;
  final int setIndex;
  final int? reps, seconds;
  final double? loadKg;
  final DateTime at;
  const RecordedSet({
    required this.exerciseKey,
    required this.setIndex,
    this.reps,
    this.seconds,
    this.loadKg,
    required this.at,
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

abstract interface class OpenBandRepository {
  Future<OpenBandDay> readDay(String day);
  Future<String> startStrengthSession(WorkoutTemplate template);
  Future<void> recordSet(String sessionId, RecordedSet set);
  Future<void> finishStrengthSession(String sessionId);
  Future<MuscleLoad> readMuscleLoad(String endDay, int days);
  Future<List<FoodHit>> searchFoods(String query);
  Future<List<WorkoutTemplate>> readTemplates();
  Future<WorkoutTemplate> saveTemplate(WorkoutTemplate template);
  Future<void> archiveTemplate(String id);
  Future<DayMeals> readMeals(String day);
  Future<MealDraft?> readMealDraft(String day, String meal);
  Future<void> saveMealDraft(MealDraft draft);
  Future<void> discardMealDraft(String draftId);
  Future<void> commitMealDraft(MealDraft draft);
  Future<SessionDetail?> readSessionDetail(String sessionId);
  Future<PatternSummary> readPattern(
    String habitKey,
    MetricKey outcome,
    String endDay,
    int nights,
  );
  Future<List<JournalEntry>> readJournal(String day);
  Future<void> writeJournal(String day, String key, double value);
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
}
