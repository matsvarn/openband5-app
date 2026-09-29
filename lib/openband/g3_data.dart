import '../data/day_label.dart';
import '../data/journal_fields.dart';
import 'domain.dart' show MetricPoint, CaffeineSleepPattern, WeightHistory;

enum G3Metric {
  recovery,
  hrv,
  rhr,
  respRate,
  skinTempZ,
  sleepMinutes,
  strain,
  steps,
}

/// Skin temperature is a relative z-score, never an absolute °C reading.
enum G3ValueUnit {
  percent,
  milliseconds,
  bpm,
  breathsPerMinute,
  relativeZ,
  minutes,
  strain,
  steps,
}

extension G3MetricUnit on G3Metric {
  G3ValueUnit get unit => switch (this) {
    G3Metric.recovery => G3ValueUnit.percent,
    G3Metric.hrv => G3ValueUnit.milliseconds,
    G3Metric.rhr => G3ValueUnit.bpm,
    G3Metric.respRate => G3ValueUnit.breathsPerMinute,
    G3Metric.skinTempZ => G3ValueUnit.relativeZ,
    G3Metric.sleepMinutes => G3ValueUnit.minutes,
    G3Metric.strain => G3ValueUnit.strain,
    G3Metric.steps => G3ValueUnit.steps,
  };
}

enum BaselinePhase { trusted, building, none }

class BaselineStatus {
  const BaselineStatus(this.phase, {this.nightsHave, this.nightsNeeded});
  final BaselinePhase phase;
  final int? nightsHave;
  final int? nightsNeeded;
  int? get remaining => nightsHave == null || nightsNeeded == null
      ? null
      : (nightsNeeded! - nightsHave!).clamp(0, nightsNeeded!);
}

class PersonalRange {
  const PersonalRange(this.low, this.high, this.median);
  final double low, high, median;
  bool contains(double value) => value >= low && value <= high;
}

class G3Baseline {
  const G3Baseline(this.status, {this.range});
  final BaselineStatus status;
  final PersonalRange? range;
}

class G3Trend {
  const G3Trend({
    required this.metric,
    required this.points,
    required this.baseline,
    required this.valueCount,
    required this.insufficient,
  });
  final G3Metric metric;
  final List<MetricPoint> points;
  final G3Baseline baseline;
  final int valueCount;
  final int? insufficient;
}

G3Trend g3Trend(
  G3Metric metric,
  List<MetricPoint> points,
  G3Baseline baseline,
) {
  final count = points
      .where((p) => p.value != null && p.value!.isFinite)
      .length;
  return G3Trend(
    metric: metric,
    points: points,
    baseline: baseline,
    valueCount: count,
    insufficient: count < 7 ? 7 - count : null,
  );
}

class G3WeekValue {
  const G3WeekValue(this.day, this.value, {this.outOfRange});
  final String day;
  final double? value;
  final bool? outOfRange;
}

class G3WeekStrip {
  const G3WeekStrip({
    required this.metric,
    required this.days,
    this.range,
    this.goal,
  });
  final G3Metric metric;
  final List<G3WeekValue> days;
  final PersonalRange? range;
  final double? goal;
}

G3WeekStrip g3WeekStrip(
  G3Metric metric,
  List<MetricPoint> points, {
  PersonalRange? range,
  double? goal,
}) => G3WeekStrip(
  metric: metric,
  range: range,
  goal: goal,
  days: [
    for (final p in points)
      G3WeekValue(
        p.day,
        p.value,
        outOfRange: p.value == null || range == null
            ? null
            : !range.contains(p.value!),
      ),
  ],
);

enum G3ActivitySource { auto, manual, live }

class G3HrPoint {
  const G3HrPoint(this.at, this.meanBpm);
  final DateTime at;
  final double? meanBpm;
}

class G3SignalGap {
  const G3SignalGap(this.start, this.end);
  final DateTime start, end;
  Duration get duration => end.difference(start);
}

class G3ZoneBasis {
  const G3ZoneBasis({this.method, this.maxHr, this.maxHrSource});

  /// Stored zone method: tanaka/observed use %HRmax; karvonen uses %HR reserve.
  final String? method;
  final double? maxHr;
  final G3MaxHrSource? maxHrSource;
}

enum G3MaxHrSource { estimated, measured, userSet }

class G3Activity {
  const G3Activity({
    required this.id,
    required this.sport,
    required this.source,
    required this.confirmed,
    required this.start,
    required this.end,
    this.strain,
    this.avgHr,
    this.maxHr,
    this.zoneMinutes,
    this.zoneBasis,
    this.hrTrace = const [],
    this.signalGaps = const [],
    this.opticalShare,
    this.hrRecoveryOneMinute,
    this.priorHrrCount,
  });
  final String id, sport;
  final G3ActivitySource source;
  final bool confirmed;
  final DateTime start;
  final DateTime? end;
  Duration? get duration => end?.difference(start);
  final double? strain, avgHr, maxHr;

  /// Null for suggestions. Confirmed sessions are scored by the existing
  /// manual-session writer at save; absent substrate/anchors keep scores null.
  /// The normal session re-score can improve them after a later band drain.
  final List<double>? zoneMinutes;
  final G3ZoneBasis? zoneBasis;
  final List<G3HrPoint> hrTrace;
  final List<G3SignalGap> signalGaps;
  final double? opticalShare;
  final double? hrRecoveryOneMinute;
  final int? priorHrrCount;
}

class G3WeeklyLoad {
  const G3WeeklyLoad(this.days, {this.ctl, this.atl});
  final List<MetricPoint> days;
  final double? ctl, atl;
}

class G3AvailableValue {
  const G3AvailableValue(this.value, {this.gate});
  final double? value;
  final String? gate;
}

/// Stored analytics comparison of longer free nights with habitual sleep.
/// This is not a sum of shortfalls against the user's goal.
class G3SleepDebt {
  const G3SleepDebt({
    this.freeNightP75Hours,
    this.habitualMedianHours,
    this.debtHours,
    this.hasFreeNight,
    this.refusalNote,
  });
  final double? freeNightP75Hours, habitualMedianHours, debtHours;
  final bool? hasFreeNight;
  final String? refusalNote;
}

class G3SleepPlus {
  const G3SleepPlus({
    required this.regularity,
    required this.socialJetlag,
    required this.sleepDebt,
    required this.bedtime,
    required this.wake,
    this.needMinutes,
    this.goalMinutes,
    this.strainBonusMinutes,
    this.napCreditMinutes,
    this.napsIncomplete,
    this.typicalEfficiency,
  });
  final G3AvailableValue regularity, socialJetlag;
  final G3SleepDebt sleepDebt;
  final DateTime? bedtime, wake;
  final double? needMinutes, goalMinutes, strainBonusMinutes, napCreditMinutes;
  final bool? napsIncomplete;

  /// Null until the stored plan snapshot carries this source value.
  final double? typicalEfficiency;
}

class G3CheckInQuestion {
  const G3CheckInQuestion(this.field, this.value);
  final JournalFieldSpec field;
  final JournalMetricValue? value;
}

class G3CheckIn {
  const G3CheckIn(this.day, this.questions);
  final String day;
  final List<G3CheckInQuestion> questions;
  int get answered => questions.where((q) => q.value != null).length;
  int get total => questions.length;
}

class G3JournalPattern {
  const G3JournalPattern(this.pattern, {required this.pairedMinimum});
  final CaffeineSleepPattern pattern;
  final int pairedMinimum;
  int get remaining =>
      (pairedMinimum - pattern.pairedN).clamp(0, pairedMinimum);
}

enum G3WeightSource { manual, imported }

/// The four short daily ratings in the G3 check-in; definitions own their copy.
const kG3CheckInKeys = {'mood', 'sleep_quality', 'energy', 'stress'};

class G3Weight {
  const G3Weight(this.history, this.sources);
  final WeightHistory history;
  final Map<String, G3WeightSource> sources;
}

List<String> g3DaysEnding(String endDay, int days) {
  final start = localDayStartSec(endDay);
  if (start == null) throw ArgumentError.value(endDay, 'endDay');
  final d = DateTime.fromMillisecondsSinceEpoch(start * 1000);
  return [
    for (var i = days - 1; i >= 0; i--)
      dayLabelOf(DateTime(d.year, d.month, d.day - i)),
  ];
}
