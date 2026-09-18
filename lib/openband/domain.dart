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

abstract interface class OpenBandRepository {
  Future<OpenBandDay> readDay(String day);
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
