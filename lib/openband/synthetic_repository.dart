import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/lab_catalogue.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/data/nutrition_targets.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'time.dart';

enum SyntheticScenario {
  complete,
  dense,
  partial,
  missing,
  missingNightHrv,
  processing,
  disconnected,
  interrupted,
  draftFailure,
  saveFailure,
  calculationFailure,
}

/// Isolated Paper inputs for [SyntheticOpenBandRepository.seedCaffeineSleepPattern].
///
/// Last wake is the selected [endDay]; journal `caffeine_late` sits on D and
/// stored `sol_min` on D+1. Read still goes through the public producer.
enum SyntheticCaffeineSleepSeed {
  /// 7× Ja then 11× Nein, SOL 24 vs 12 (producer delta +12). Needs nights ≥ 18.
  paperMeaningful,

  /// One Ja on the day before [endDay], no stored SOL.
  unavailable,

  /// Five lag-1 pairs 1,0,1,0,1 at 24/12 — below producer floors.
  insufficient,

  /// Eighteen even/odd flags, SOL 20 + Random(11)×8. Needs nights ≥ 18.
  nonmeaningful,

  /// Paper 18 eligible pairs plus one rejected lag-1 wake. Needs nights ≥ 18.
  partialMeaningful,
}

/// Paper VO2max row: 14 September 2026, 42.0 ml/kg/min, Spiroergometrie.
const String kSyntheticVo2PaperId = 'vo2-paper';
const String kSyntheticVo2PaperDay = '2026-09-14';
const double kSyntheticVo2PaperValue = 42;
const String kSyntheticVo2PaperMethod = 'Spiroergometrie';

class _NightScalarSeed {
  _NightScalarSeed({
    this.selected,
    Map<String, NightScalarRow> matching = const {},
    Set<String> otherVersionDays = const {},
    Set<String> seriesOnlyDays = const {},
    Map<String, NightScalarJob> sleepJobs = const {},
    Map<String, NightScalarJob> napJobs = const {},
    this.recordingTimezone,
    this.currentAlgo,
  }) : matching = Map<String, NightScalarRow>.from(matching),
       otherVersionDays = Set<String>.from(otherVersionDays),
       seriesOnlyDays = Set<String>.from(seriesOnlyDays),
       sleepJobs = Map<String, NightScalarJob>.from(sleepJobs),
       napJobs = Map<String, NightScalarJob>.from(napJobs);

  final NightScalarRow? selected;
  final Map<String, NightScalarRow> matching;
  final Set<String> otherVersionDays;
  final Set<String> seriesOnlyDays;
  final Map<String, NightScalarJob> sleepJobs;
  final Map<String, NightScalarJob> napJobs;
  final String? recordingTimezone;
  final int? currentAlgo;

  NightScalarRow? rowFor(String day) =>
      selected?.day == day ? selected : matching[day];
}

/// Isolated in-memory [OpenBandRepository] driven by design fixtures.
///
/// ponytail: sleep totals after a correction clip fixture intervals and sum
/// observed stages. Not analytics restaging — swap when DerivationEngine owns
/// this read model.
class SyntheticOpenBandRepository implements OpenBandRepository {
  SyntheticScenario scenario;
  Future<void>? calculationBarrier;
  Future<void>? restoreBarrier;
  final List<({String day, int revision})> napRecalcCalls = [];

  final Map<String, dynamic> _summary;
  final Map<String, dynamic> _detail;
  final Map? activity;
  final Map<String, SleepDraft> _drafts = {};
  final Map<String, SleepCorrection> _corrections = {};
  final Map<String, NapDay> _naps = {};
  final Map<String, List<NapSession>> _napRejected = {};
  int _napRevision = 0;
  final Map<String, SleepNight> _applied = {};
  final Map<String, SleepGoalPeriod> _sleepGoals = {};
  final Map<String, NutritionTargetChange> _nutritionTargets = {};
  final Map<String, double> _sleepByDay = {};
  final Map<String, double> _hrvByDay = {};
  final Map<String, double> _rhrByDay = {};
  final Map<String, double> _respByDay = {};
  final Map<String, double> _strainByDay = {};
  WeekendSleepEstimate? weekendEstimate;
  SetupEvaluation? setupEvaluation;
  Map<String, dynamic>? sleepPlanArtifact;
  List<SleepPlanInputJob> sleepPlanJobs = const [];
  List<SleepPlanDayObservation> sleepPlanObservations = const [];
  bool failSleepPlanRead = false;
  DateTime Function() sleepPlanNow = DateTime.now;
  bool failSetupEvaluation = false;
  bool failSleepGoalRead = false;
  bool failSleepGoalWrite = false;
  Future<void>? sleepGoalWriteBarrier;
  bool failNutritionTargetRead = false;
  bool failNutritionTargetWrite = false;
  Future<void>? nutritionTargetWriteBarrier;
  String Function() nutritionToday = () => todayLabel();
  Map<String, dynamic>? legacyUndatedProfile;
  bool failTemplateRead = false;
  bool failTemplateWrite = false;
  bool failPin = false;
  bool failPinRead = false;
  Future<void>? templateWriteBarrier;
  bool failJournalRead = false;
  Future<void>? journalReadBarrier;
  bool failVo2Read = false;
  bool failVo2Write = false;
  DateTime Function() vo2Now = DateTime.now;
  bool failJournalPatch = false;
  bool failJournalFieldsList = false;
  bool failJournalFieldsCreate = false;
  Future<void>? journalPatchBarrier;
  bool failCaffeineSleepPattern = false;
  Future<CaffeineSleepPattern>? caffeineSleepPatternPending;
  String? _caffeineSleepPatternRequest;
  int _caffeineSleepPatternGeneration = 0;
  bool failMealsRead = false;
  bool failFoodRead = false;
  bool failFoodWrite = false;
  Future<void>? foodWriteBarrier;

  @override
  Future<NightSignals> readNightSignals(String day) async {
    final current = await readDay(day);
    final night = current.sleep;
    if (scenario == SyntheticScenario.missing ||
        day != _day ||
        night.onset == null ||
        night.wake == null ||
        (current.correction != null &&
            current.correction!.state != CorrectionState.complete)) {
      return NightSignals(
        day: day,
        synthetic: true,
        processing:
            current.correction?.state == CorrectionState.pending ||
            current.correction?.state == CorrectionState.calculating,
      );
    }
    if (scenario == SyntheticScenario.processing) {
      return NightSignals(day: day, synthetic: true, processing: true);
    }
    final start = parseRecordedTime(
      night.onset!,
      obTime(night.onset),
      zone: _timezone,
    )!;
    final end = parseRecordedTime(
      night.wake!,
      obTime(night.wake),
      zone: _timezone,
    )!;
    final raw = Map<String, dynamic>.from(
      _detail[scenario == SyntheticScenario.partial
                  ? 'night_signals_sparse'
                  : 'night_signals']
              as Map? ??
          const {},
    );
    if (scenario == SyntheticScenario.missingNightHrv) raw['hrv'] = const [];
    return NightSignals(
      day: day,
      synthetic: true,
      recordingTimezone: _timezone,
      window: (start: start, end: end),
      series: {
        for (final kind in NightSignalKind.values)
          kind: NightSignalSeries(
            partial: true,
            maxConnectingGap: kind == NightSignalKind.hrv
                ? const Duration(hours: 1)
                : const Duration(minutes: 3),
            readings: [
              for (final row in raw[kind.name] as List? ?? const [])
                if (DateTime.parse(row['at'] as String).isBefore(end) &&
                    !DateTime.parse(row['at'] as String).isBefore(start))
                  NightSignalReading(
                    DateTime.parse(row['at'] as String),
                    (row['value'] as num?)?.toDouble(),
                    bounds: row['lower'] == null
                        ? null
                        : (
                            lower: (row['lower'] as num).toDouble(),
                            upper: (row['upper'] as num).toDouble(),
                          ),
                  ),
            ],
          ),
      },
    );
  }

  late final String _day;
  late final String _timezone;
  late final DateTime _onset;
  late final DateTime _wake;
  late final List<NightSegment> _segments;
  late final List<NightSegment> _partialSegments;
  late final List<({String day, double? minutes})> _history;
  late final BandSnapshot _baseBand;

  /// Optional run-detail fixture (docs/openband5/assets/fixtures/run-detail.json).
  final Map? run;

  SyntheticOpenBandRepository.fromMaps(
    Map summary,
    Map detail, {
    this.scenario = SyntheticScenario.complete,
    this.activity,
    this.run,
  }) : _summary = Map<String, dynamic>.from(summary),
       _detail = Map<String, dynamic>.from(detail) {
    _day = _summary['day'] as String;
    _timezone = (_summary['timezone'] ?? _detail['timezone']) as String;
    weekendEstimate = WeekendSleepEstimate(
      asOfDay: _day,
      algoVersion: kAlgoVersion,
      builtAtEpoch: DateTime(2026, 9, 15, 7, 42).millisecondsSinceEpoch ~/ 1000,
      osdHours: 8.2,
      confidence: 0.6,
    );
    final sleep = Map<String, dynamic>.from(_summary['sleep'] as Map);
    _onset = _at(_previousDay(_day), sleep['start'] as String);
    _wake = _at(_day, sleep['end'] as String);
    _segments = [
      for (final raw in _detail['phase_segments'] as List)
        _segment(Map<String, dynamic>.from(raw as Map)),
    ];
    _partialSegments = _withGap(
      _segments,
      _onset.add(const Duration(hours: 3)),
      _onset.add(const Duration(hours: 3, minutes: 24)),
    );
    final prior = _nums(sleep['prior_seven_sleep_minutes']);
    _history = [
      for (var i = 0; i < prior.length; i++)
        (day: _shift(_day, i - prior.length), minutes: prior[i]),
    ];
    for (final row in _history) {
      _sleepByDay[row.day] = row.minutes!;
    }
    _sleepByDay[_day] = (sleep['sleep_minutes'] as num).toDouble();
    _indexBaseline(
      _nums(
        Map<String, dynamic>.from(_summary['recovery'] as Map)['hrv_baseline'],
      ),
      _hrvByDay,
    );
    _indexBaseline(
      _nums(
        Map<String, dynamic>.from(_summary['recovery'] as Map)['rhr_baseline'],
      ),
      _rhrByDay,
    );
    _indexBaseline(
      _nums(
        Map<String, dynamic>.from(_summary['recovery'] as Map)['resp_baseline'],
      ),
      _respByDay,
    );
    _indexBaseline(const [
      1.4,
      1.9,
      0.8,
      2.1,
      1.6,
      1.1,
      1.8,
      0.9,
      2.0,
      1.5,
      1.3,
      1.7,
      1.0,
      1.2,
    ], _strainByDay);
    final saved = _at(_day, _summary['latest_saved_local'] as String);
    _baseBand = BandSnapshot(
      connection: BandConnection.connected,
      transfer: TransferState.idle,
      batteryPercent: (_summary['battery_percent'] as num).toInt(),
      batteryObservedAt: saved,
      latestStoredAt: saved,
    );
    _labResults.addAll(const [
      LabDraw(
        marker: 'ferritin',
        takenOn: '2026-09-15',
        value: 52,
        unit: 'ng/mL',
        reportLow: 30,
        reportHigh: 400,
        updatedAt: 1,
      ),
      LabDraw(
        marker: 'ferritin',
        takenOn: '2026-06-12',
        value: 46,
        unit: 'ng/mL',
        reportLow: 30,
        reportHigh: 400,
        updatedAt: 1,
      ),
      LabDraw(
        marker: 'ferritin',
        takenOn: '2026-03-04',
        value: 33,
        unit: 'ng/mL',
        reportLow: 30,
        reportHigh: 400,
        updatedAt: 1,
      ),
      LabDraw(
        marker: 'vitamin_b12',
        takenOn: '2026-09-15',
        value: 410,
        unit: 'pg/mL',
        updatedAt: 1,
      ),
      LabDraw(
        marker: 'vitamin_d',
        takenOn: '2026-09-15',
        value: 37,
        unit: 'ng/mL',
        updatedAt: 1,
      ),
    ]);
    _seedFixtureGlucose();
    _seedFixtureMedication();
    _seedFixtureCycle();
    _seedFixtureCycleNights();
  }

  BandSnapshot get band {
    switch (scenario) {
      case SyntheticScenario.disconnected:
        return BandSnapshot(
          connection: BandConnection.disconnected,
          transfer: TransferState.idle,
          batteryPercent: _baseBand.batteryPercent,
          batteryObservedAt: _baseBand.batteryObservedAt,
          latestStoredAt: _baseBand.latestStoredAt,
          receivedAt: _baseBand.receivedAt,
        );
      case SyntheticScenario.interrupted:
        return BandSnapshot(
          connection: BandConnection.connected,
          transfer: TransferState.interrupted,
          batteryPercent: _baseBand.batteryPercent,
          batteryObservedAt: _baseBand.batteryObservedAt,
          latestStoredAt: _baseBand.latestStoredAt,
          receivedAt: _baseBand.receivedAt,
        );
      default:
        return _baseBand;
    }
  }

  final Map<String, _SynthJournalDay> _journal = {};
  final Map<String, List<Map<String, Object?>>> _vo2 = {};
  final Map<String, JournalFieldSpec> _journalFieldDefs = {};
  int _journalClock = 0;
  final Map<String, double?> _solMin = {};
  final Map<String, String> _solIneligible = {};

  void seedJournalEditor({
    String? day,
    bool filled = false,
    bool withCustom = false,
    Map<String, JournalMetricValue>? metrics,
  }) {
    final id = day ?? _day;
    if (withCustom) {
      _journalFieldDefs['custom_magnesium'] = const JournalFieldSpec(
        key: 'custom_magnesium',
        label: 'Magnesium',
        kind: JournalFieldKind.dose,
        unit: 'mg',
        max: 1000,
        step: 50,
        hasTime: true,
        custom: true,
      );
      _journalFieldDefs['custom_meditation'] = const JournalFieldSpec(
        key: 'custom_meditation',
        label: 'Meditation',
        kind: JournalFieldKind.duration,
        unit: 'min',
        max: 120,
        step: 5,
        custom: true,
        hidden: true,
      );
    }
    if (!filled && metrics == null) return;
    final row = _journal[id] ??= _SynthJournalDay();
    if (filled) {
      row.metrics.addAll({
        'mood': const JournalMetricValue(4),
        'sleep_quality': const JournalMetricValue(4),
        'energy': const JournalMetricValue(4),
        'stress': const JournalMetricValue(2),
        'caffeine_late': const JournalMetricValue(1),
        'water_ml': const JournalMetricValue(750),
        'caffeine_mg': const JournalMetricValue(200, atMinuteOfDay: 630),
        'screens_min': const JournalMetricValue(30),
        'weight_kg': const JournalMetricValue(78),
        if (withCustom)
          'custom_magnesium': const JournalMetricValue(400, atMinuteOfDay: 855),
      });
      row.tags = ['Spaziergang'];
      row.note = 'Später Spaziergang.';
      row.journalUpdatedAt = _nextJournalRev(row.journalUpdatedAt);
    }
    if (metrics != null) row.metrics.addAll(metrics);
    for (final key in row.metrics.keys) {
      row.metricUpdatedAt[key] = _nextJournalRev(row.metricUpdatedAt[key] ?? 0);
    }
  }

  /// Isolated tests/gallery only. Writes dated `weight_kg` into existing
  /// journal storage so later edits/deletes are visible to
  /// [readWeightHistory]. Does not invent profile fallback rows.
  void seedWeightHistory({
    List<String>? dates,
    List<double>? enteredKg,
  }) {
    final days = dates ?? kWeightPaperDates;
    final values = enteredKg ?? kWeightPaperEnteredKg;
    if (days.length != values.length) {
      throw ArgumentError('weight history dates and values must align.');
    }
    for (var i = 0; i < days.length; i++) {
      if (!isJournalDayId(days[i])) {
        throw ArgumentError.value(days[i], 'dates', 'Expected YYYY-MM-DD.');
      }
      final row = _journal[days[i]] ??= _SynthJournalDay();
      row.metrics[kWeightJournalField] = JournalMetricValue(values[i]);
      row.metricUpdatedAt[kWeightJournalField] = _nextJournalRev(
        row.metricUpdatedAt[kWeightJournalField] ?? 0,
      );
    }
  }

  /// Isolated tests/gallery only. Stores the Paper entry
  /// [kSyntheticVo2PaperDay], [kSyntheticVo2PaperValue] ml/kg/min, declared
  /// method [kSyntheticVo2PaperMethod], through the same mutation path as
  /// [createVo2Entry]. [removed] appends a real delete. [corruptHead] appends
  /// an unreadable higher revision; the older 42.0 stays in the chain and is
  /// not the head. Edits and conflicts use [editVo2Entry]. An id that was
  /// never stored is missing. Profile weight and resting heart rate are left
  /// untouched. Read and write failure flags do not apply to seeding.
  void seedVo2Paper({bool removed = false, bool corruptHead = false}) {
    if (_vo2.containsKey(kSyntheticVo2PaperId)) {
      throw StateError('VO2 paper entry is already seeded.');
    }
    final created = _vo2Write(
      op: _Vo2Op.create,
      id: kSyntheticVo2PaperId,
      expectedRevision: 0,
      measuredOn: kSyntheticVo2PaperDay,
      valueMlKgMin: kSyntheticVo2PaperValue,
      declaredMethod: kSyntheticVo2PaperMethod,
    );
    if (created is! Vo2Committed || created.retry) {
      throw StateError('VO2 paper seed did not store a revision.');
    }
    if (removed) {
      final deleted = _vo2Write(
        op: _Vo2Op.delete,
        id: kSyntheticVo2PaperId,
        expectedRevision: created.revision.revision,
      );
      if (deleted is! Vo2Committed || deleted.retry) {
        throw StateError('VO2 paper seed did not remove the revision.');
      }
    }
    if (corruptHead) _vo2AppendCorruptHead(kSyntheticVo2PaperId);
  }

  final Map<String, WorkoutTemplate> _templates = {};
  final Set<String> _archivedTemplates = {};
  String? _pinnedTemplateId;
  final Map<String, MealDraft> _mealDrafts = {};
  final Map<String, FoodEntry> _foodEntries = {};
  bool _seeded = false;

  void _seedPlans() {
    if (_seeded) return;
    _seeded = true;
    // B23 synthetic plan Ganzkörper A: four exercises, twelve work sets.
    PlannedExercise ex(String key, String name, List<PlannedSet> sets) =>
        PlannedExercise(
          id: 'ex-$key',
          exerciseKey: key,
          name: name,
          sets: sets,
        );
    List<PlannedSet> reps(String key, int reps, double kg) => [
      for (var i = 1; i <= 3; i++)
        PlannedSet(id: '$key-$i', reps: reps, loadKg: kg, restSec: 90),
    ];
    _templates['tpl-ganzkoerper-a'] = WorkoutTemplate(
      id: 'tpl-ganzkoerper-a',
      name: 'Ganzkörper A',
      version: 1,
      exercises: [
        ex('bench_press', 'Bankdrücken', reps('bp', 8, 40)),
        ex('row', 'Rudern', reps('row', 10, 30)),
        ex('squat', 'Kniebeuge', reps('sq', 8, 60)),
        ex('plank', 'Plank', [
          for (var i = 1; i <= 3; i++)
            PlannedSet(id: 'plank-$i', seconds: 45, restSec: 60),
        ]),
      ],
      updatedAt: _at(_shift(_day, -2), '19:00'),
    );
    List<PlannedSet> light(String key) => [
      for (var i = 1; i <= 3; i++)
        PlannedSet(id: '$key-$i', reps: 10, restSec: 60),
    ];
    _templates['tpl-ganzkoerper-b'] = WorkoutTemplate(
      id: 'tpl-ganzkoerper-b',
      name: 'Ganzkörper B',
      version: 1,
      exercises: [
        ex('ohp', 'Überkopfdrücken', light('ohp')),
        ex('rdl', 'Kreuzheben', light('rdl')),
        ex('lunge', 'Ausfallschritt', light('lunge')),
        ex('pullup', 'Klimmzug', light('pullup')),
        ex('curl', 'Curl', light('curl')),
      ],
      updatedAt: _at(_shift(_day, -4), '18:00'),
    );
    RecordedSet hist(
      String key,
      int index,
      DateTime at, {
      int? reps,
      int? seconds,
      double? loadKg,
      String? plannedSetId,
    }) => RecordedSet(
      exerciseKey: key,
      setIndex: index,
      reps: reps,
      seconds: seconds,
      loadKg: loadKg,
      at: at,
      plannedSetId: plannedSetId,
      exerciseId: 'ex-$key',
    );
    final priorDay = _shift(_day, -2);
    final priorAt = _at(priorDay, '18:10');
    _strength['synthetic-$priorDay-weight_training'] =
        _SyntheticStrength(
            plan: _templates['tpl-ganzkoerper-a']!,
            startedAt: priorAt,
          )
          ..finished = true
          ..recorded.addAll([
            hist(
              'bench_press',
              1,
              priorAt,
              reps: 8,
              loadKg: 37.5,
              plannedSetId: 'bp-1',
            ),
            hist(
              'bench_press',
              2,
              priorAt.add(const Duration(minutes: 3)),
              reps: 8,
              loadKg: 37.5,
              plannedSetId: 'bp-2',
            ),
            hist(
              'bench_press',
              3,
              priorAt.add(const Duration(minutes: 6)),
              reps: 8,
              loadKg: 37.5,
              plannedSetId: 'bp-3',
            ),
            hist(
              'row',
              1,
              priorAt.add(const Duration(minutes: 10)),
              reps: 10,
              loadKg: 32.5,
              plannedSetId: 'row-1',
            ),
            hist(
              'row',
              2,
              priorAt.add(const Duration(minutes: 13)),
              reps: 10,
              loadKg: 32.5,
              plannedSetId: 'row-2',
            ),
            hist(
              'row',
              3,
              priorAt.add(const Duration(minutes: 16)),
              reps: 10,
              loadKg: 32.5,
              plannedSetId: 'row-3',
            ),
            hist(
              'squat',
              1,
              priorAt.add(const Duration(minutes: 20)),
              reps: 8,
              loadKg: 62.5,
              plannedSetId: 'sq-1',
            ),
            hist(
              'squat',
              2,
              priorAt.add(const Duration(minutes: 23)),
              reps: 8,
              loadKg: 62.5,
              plannedSetId: 'sq-2',
            ),
            hist(
              'squat',
              3,
              priorAt.add(const Duration(minutes: 26)),
              reps: 8,
              loadKg: 62.5,
              plannedSetId: 'sq-3',
            ),
            hist(
              'plank',
              1,
              priorAt.add(const Duration(minutes: 30)),
              seconds: 40,
              plannedSetId: 'plank-1',
            ),
            hist(
              'plank',
              2,
              priorAt.add(const Duration(minutes: 32)),
              seconds: 40,
              plannedSetId: 'plank-2',
            ),
            hist(
              'plank',
              3,
              priorAt.add(const Duration(minutes: 34)),
              seconds: 40,
              plannedSetId: 'plank-3',
            ),
          ]);
    _foodEntries['m1'] = FoodEntry(
      id: 'm1',
      date: _day,
      meal: 'breakfast',
      label: 'Haferflocken mit Milch',
      kcal: 380,
      proteinG: 14,
      carbsG: 58,
      fatG: 9,
      source: FoodSource.manual,
      sourceCode: 'manual',
      confirmed: true,
      createdAt: 1,
      updatedAt: 1,
    );
    _foodEntries['m2'] = FoodEntry(
      id: 'm2',
      date: _day,
      meal: 'breakfast',
      label: 'Kaffee',
      source: FoodSource.manual,
      sourceCode: 'manual',
      createdAt: 2,
      updatedAt: 2,
    );
    _foodEntries['m3'] = FoodEntry(
      id: 'm3',
      date: _day,
      meal: 'lunch',
      label: 'Linsensalat',
      kcal: 240,
      proteinG: 12,
      carbsG: 30,
      fatG: 6,
      source: FoodSource.manual,
      sourceCode: 'manual',
      confirmed: true,
      createdAt: 3,
      updatedAt: 3,
    );
  }

  final Map<String, List<RecordedSet>> _liveSets = {};
  final Map<String, Map<String, Object?>> _exerciseDefs = {};
  final Map<String, _SyntheticStrength> _strength = {};
  String? _activeStrengthId;
  final List<LabDraw> _labResults = [];
  final Map<String, LabMarkerDef> _labDefs = {};
  bool failLabWrites = false;
  bool failLabReads = false;
  int labWriteCount = 0;
  Future<void> Function()? beforeLabWrite;
  DateTime Function() strengthNow = DateTime.now;
  bool failStrengthWrites = false;
  bool failStrengthStart = false;
  bool failStrengthStartAfterCommit = false;
  bool legacyActiveStrength = false;
  int failStrengthReadRemaining = 0;
  int strengthStartCount = 0;
  int strengthWriteCount = 0;
  Future<void> Function()? beforeStrengthWrite;

  void seedLabDraw(LabDraw draw) => _labResults.add(draw);

  static const _glucoseFixtureValues = <double?>[
    5.0,
    5.1,
    5.2,
    5.1,
    5.3,
    null,
    null,
    5.8,
    6.3,
    5.9,
    5.6,
    5.4,
    5.2,
  ];

  static const _glucoseFixtureSourceName =
      'Sensor-App (synthetisch) via Apple Health';
  static const glucoseFixtureSourceKey = 'synthetic:glucose-source';

  final List<GlucoseReading> _glucoseReadings = [];
  final Set<String> _glucoseExcluded = {};
  GlucoseAttempt _glucoseAttempt = GlucoseAttempt.none;
  bool failGlucoseReads = false;
  bool failGlucoseImport = false;
  bool emptyGlucoseImport = false;
  bool failGlucoseExclusionWrite = false;
  HealthMeasurementImportStatus? glucoseImportFailureStatus;

  static final medicationFixtureNow = DateTime(2026, 9, 15, 9, 41);
  static const medicationFixtureDay = '2026-09-15';
  static const medicationFixturePlanAKey = 'synthetic-med-a';
  static const medicationFixturePlanBKey = 'synthetic-med-b';

  bool failMedicationRead = false;
  bool failMedicationWrite = false;
  bool failMedicationReminders = false;
  bool corruptMedicationHeads = false;
  final Map<String, MedicationPlan> _medPlans = {};
  final Map<String, List<MedicationPlanRevision>> _medRevisions = {};
  final List<MedicationStoredDose> _medDoses = [];
  int _medRevisionSeq = 0;

  static const cycleFixtureDay = '2026-09-15';
  static const cycleFixtureStarts = [
    '2026-06-01',
    '2026-06-29',
    '2026-07-31',
    '2026-08-24',
  ];
  static final cycleFixtureNow = DateTime(2026, 9, 15, 12);
  static const cycleMedianFixtureStarts = [
    '2026-06-29',
    '2026-07-31',
    '2026-08-24',
  ];
  static const cycleMedianFixtureAnchor = '2026-09-15';
  static final cycleMedianFixtureNow = DateTime(2026, 9, 15, 12);
  static const cycleComparisonFixtureStarts = [
    '2026-05-28',
    '2026-06-29',
    '2026-07-31',
    '2026-08-24',
  ];
  static const cycleComparisonFixtureAnchor = '2026-09-15';
  static final cycleComparisonFixtureNow = DateTime(2026, 9, 15, 12);
  static const cycleComparisonFixtureSameDayRhr = [50.0, 52.0, 54.0];
  static const cycleComparisonFixtureSameDayHrv = [45.0, 47.0, 49.0];
  static const cycleComparisonFixtureCurrentRhrAdd = 2.0;
  static const cycleComparisonFixtureCurrentHrvAdd = 3.0;

  bool failCycleRead = false;
  bool failCycleWrite = false;
  bool failCycleContextRefresh = false;
  bool failCycleMeasurementsRead = false;
  bool failCycleMediansRead = false;
  bool failCycleComparisonRead = false;
  int cycleContextRefreshCalls = 0;
  CycleSettings cycleSettings = const CycleSettings(
    enabled: true,
    estimatesEnabled: true,
    lengthReviewEnabled: false,
  );
  final Map<String, CycleStart> _cycleStarts = {};
  final Map<String, CycleObservation> _cycleObservations = {};
  final List<Map<Object?, Object?>> _cycleUnreadableStarts = [];
  final List<Map<Object?, Object?>> _cycleUnreadableObservations = [];
  final Map<String, CycleNightSourceRow> _cycleNights = {};

  void seedGlucoseReading(GlucoseReading reading) =>
      _glucoseReadings.add(reading);

  void clearGlucoseReadings() => _glucoseReadings.clear();

  void retagGlucoseUnit(String uuid, String rawUnit) {
    final i = _glucoseReadings.indexWhere((r) => r.uuid == uuid);
    if (i < 0) return;
    final r = _glucoseReadings[i];
    _glucoseReadings[i] = GlucoseReading(
      uuid: r.uuid,
      measuredAt: r.measuredAt,
      value: r.value,
      rawUnit: rawUnit,
      unitKind: glucoseUnitKind(rawUnit),
      source: r.source,
      importedAt: r.importedAt,
    );
  }

  void _seedFixtureGlucose() {
    final imported = DateTime(2026, 9, 15, 9, 40);
    final query = DateTime(2026, 9, 15, 9, 41);
    const source = GlucoseSourceIdentity(
      key: glucoseFixtureSourceKey,
      sourceName: _glucoseFixtureSourceName,
      provenance: GlucoseSourceProvenance.synthetic,
    );
    for (var i = 0; i < _glucoseFixtureValues.length; i++) {
      final v = _glucoseFixtureValues[i];
      if (v == null) continue;
      final at = DateTime(2026, 9, 15, 7, i * 5);
      _glucoseReadings.add(
        GlucoseReading(
          uuid: 'glucose-fixture-${at.hour.toString().padLeft(2, '0')}'
              '${at.minute.toString().padLeft(2, '0')}',
          measuredAt: at,
          value: v,
          rawUnit: kGlucoseUnitMillimolePerLiter,
          unitKind: GlucoseUnitKind.millimolePerLiter,
          source: source,
          importedAt: imported,
        ),
      );
    }
    _glucoseAttempt = GlucoseAttempt(
      status: HealthMeasurementImportStatus.stored,
      attemptedAt: query,
      storedCount: 11,
      writtenCount: 11,
    );
  }

  /// Writes bounded journal × stored-SOL maps. Does not return a canned result.
  void seedCaffeineSleepPattern(
    String endDay, {
    SyntheticCaffeineSleepSeed seed =
        SyntheticCaffeineSleepSeed.paperMeaningful,
  }) {
    _invalidateCaffeineSleepPattern();
    for (final day in _journal.values) {
      day.metrics.remove(CaffeineSleepPattern.field);
      day.metricUpdatedAt.remove(CaffeineSleepPattern.field);
    }
    _solMin.clear();
    _solIneligible.clear();
    switch (seed) {
      case SyntheticCaffeineSleepSeed.paperMeaningful:
        _seedPaperMeaningfulPairs(endDay);
      case SyntheticCaffeineSleepSeed.unavailable:
        _setCaffeine(openBandDaysEnding(endDay, 2).first, 1);
      case SyntheticCaffeineSleepSeed.insufficient:
        _seedCaffeineSleepLag1(
          endDay,
          flags: const [1.0, 0.0, 1.0, 0.0, 1.0],
          sols: const [24.0, 12.0, 24.0, 12.0, 24.0],
        );
      case SyntheticCaffeineSleepSeed.nonmeaningful:
        final rng = math.Random(11);
        _seedCaffeineSleepLag1(
          endDay,
          flags: [for (var i = 0; i < 18; i++) i.isEven ? 1.0 : 0.0],
          sols: [for (var i = 0; i < 18; i++) 20 + rng.nextDouble() * 8],
        );
      case SyntheticCaffeineSleepSeed.partialMeaningful:
        _seedPaperMeaningfulPairs(endDay);
        final extra = openBandDaysEnding(endDay, 20);
        _setCaffeine(extra.first, 1);
        _solMin[extra[1]] = 40;
        _solIneligible[extra[1]] = 'rejected';
    }
  }

  void _seedPaperMeaningfulPairs(String endDay) {
    _seedCaffeineSleepLag1(
      endDay,
      flags: [
        for (var i = 0; i < 7; i++) 1.0,
        for (var i = 0; i < 11; i++) 0.0,
      ],
      sols: [
        for (var i = 0; i < 7; i++) 24.0,
        for (var i = 0; i < 11; i++) 12.0,
      ],
    );
  }

  void _seedCaffeineSleepLag1(
    String endDay, {
    required List<double> flags,
    required List<double> sols,
  }) {
    final days = openBandDaysEnding(endDay, flags.length + 1);
    for (var i = 0; i < flags.length; i++) {
      _setCaffeine(days[i], flags[i]);
      _solMin[days[i + 1]] = sols[i];
    }
  }

  void _setCaffeine(String day, double value) {
    final row = _journal[day] ??= _SynthJournalDay();
    row.metrics[CaffeineSleepPattern.field] = JournalMetricValue(value);
    row.metricUpdatedAt[CaffeineSleepPattern.field] = _nextJournalRev(
      row.metricUpdatedAt[CaffeineSleepPattern.field] ?? 0,
    );
  }

  /// Paper live proof: Bankdrücken 4× with two confirmed sets and 1:24 of a
  /// 2:00 rest remaining, Kniebeuge 4× with no history. Uses the same start
  /// and record path as production.
  Future<String> seedPaperLiveStrength({
    required DateTime startedAt,
    required DateTime now,
  }) async {
    _seedPlans();
    _strength.removeWhere((_, runtime) => runtime.finished);
    const bench = PlannedExercise(
      id: 'ex-paper-bench',
      exerciseKey: 'bench_press',
      name: 'Bankdrücken',
      note: 'Langhantel',
      sets: [
        PlannedSet(id: 'paper-bp-1', reps: 8, loadKg: 60, restSec: 120),
        PlannedSet(id: 'paper-bp-2', reps: 8, loadKg: 62.5, restSec: 120),
        PlannedSet(id: 'paper-bp-3', reps: 8, loadKg: 62.5, restSec: 120),
        PlannedSet(id: 'paper-bp-4', reps: 8, loadKg: 62.5, restSec: 120),
      ],
    );
    const squat = PlannedExercise(
      id: 'ex-paper-squat',
      exerciseKey: 'squat',
      name: 'Kniebeuge',
      note: 'Langhantel',
      sets: [
        PlannedSet(id: 'paper-sq-1', reps: 8, loadKg: 80, restSec: 150),
        PlannedSet(id: 'paper-sq-2', reps: 8, loadKg: 80, restSec: 150),
        PlannedSet(id: 'paper-sq-3', reps: 8, loadKg: 80, restSec: 150),
        PlannedSet(id: 'paper-sq-4', reps: 8, loadKg: 80, restSec: 150),
      ],
    );
    final paper = WorkoutTemplate(
      id: 'tpl-paper-live',
      name: 'Ganzkörper A',
      version: 1,
      exercises: const [bench, squat],
      updatedAt: startedAt,
    );
    final priorAt = startedAt.subtract(const Duration(days: 1));
    _strength['synthetic-paper-prior'] =
        _SyntheticStrength(plan: paper, startedAt: priorAt)
          ..finished = true
          ..recorded.addAll([
            RecordedSet(
              exerciseKey: 'bench_press',
              setIndex: 1,
              reps: 8,
              loadKg: 60,
              at: priorAt,
              plannedSetId: 'paper-bp-1',
              exerciseId: bench.id,
            ),
            RecordedSet(
              exerciseKey: 'bench_press',
              setIndex: 2,
              reps: 8,
              loadKg: 60,
              at: priorAt.add(const Duration(minutes: 3)),
              plannedSetId: 'paper-bp-2',
              exerciseId: bench.id,
            ),
            RecordedSet(
              exerciseKey: 'bench_press',
              setIndex: 3,
              reps: 7,
              loadKg: 60,
              at: priorAt.add(const Duration(minutes: 6)),
              plannedSetId: 'paper-bp-3',
              exerciseId: bench.id,
            ),
          ]);
    final previousNow = strengthNow;
    strengthNow = () => startedAt;
    final id = await startStrengthSession(paper);
    strengthNow = previousNow;
    await recordSet(
      id,
      RecordedSet(
        exerciseKey: 'bench_press',
        setIndex: 1,
        reps: 8,
        loadKg: 60,
        at: startedAt.add(const Duration(minutes: 2)),
        plannedSetId: 'paper-bp-1',
        exerciseId: bench.id,
        restSec: 120,
      ),
    );
    await recordSet(
      id,
      RecordedSet(
        exerciseKey: 'bench_press',
        setIndex: 2,
        reps: 8,
        loadKg: 62.5,
        at: now.subtract(const Duration(seconds: 36)),
        plannedSetId: 'paper-bp-2',
        exerciseId: bench.id,
        restSec: 120,
      ),
    );
    return id;
  }

  void seedCorruptActiveStrength({String sessionId = 'synthetic-corrupt'}) {
    _activeStrengthId = sessionId;
  }

  static const _muscles = {
    'bench_press': ['Brust', 'Trizeps'],
    'row': ['Rücken', 'Bizeps'],
    'squat': ['Beine', 'Gesäß'],
  };
  static const _foods = [
    FoodHit(
      key: 'oats',
      label: 'Haferflocken',
      servingG: 60,
      kcal100: 372,
      proteinG100: 13.5,
      carbsG100: 58.7,
      fatG100: 7,
      fibreG100: 10.6,
      ironMg100: 4.7,
      source: FoodSource.verified,
      sourceCode: 'verified',
    ),
    FoodHit(
      key: 'milk',
      label: 'Milch 1,5 %',
      brand: 'Verifiziert',
      servingG: 200,
      kcal100: 47,
      proteinG100: 3.4,
      carbsG100: 4.9,
      fatG100: 1.5,
    ),
    FoodHit(key: 'coffee', label: 'Kaffee schwarz', servingG: 200),
  ];

  @override
  Future<String> startStrengthSession(WorkoutTemplate template) async {
    strengthStartCount++;
    if (failStrengthStart) {
      throw StateError('Einheit konnte nicht gestartet werden.');
    }
    if (_activeStrengthId != null) throw const WorkoutBusy();
    if (template.exercises.isEmpty) {
      throw ArgumentError('Eine Vorlage braucht Namen und eine Übung.');
    }
    final id = 'synthetic-live-${_liveSets.length + 1}';
    _liveSets[id] = [];
    _strength[id] = _SyntheticStrength(
      plan: WorkoutTemplate.fromJson(template.toJson()),
      startedAt: strengthNow(),
    );
    _activeStrengthId = id;
    if (failStrengthStartAfterCommit) {
      throw StateError('Startantwort fehlgeschlagen.');
    }
    return id;
  }

  Future<void> _awaitStrengthWrite() async {
    strengthWriteCount++;
    final hold = beforeStrengthWrite;
    if (hold != null) await hold();
  }

  @override
  Future<void> recordSet(String sessionId, RecordedSet set) async {
    await _awaitStrengthWrite();
    if (failStrengthWrites) {
      throw StateError('Speichern schlägt fehl.');
    }
    final runtime = _strength[sessionId];
    if (runtime == null || runtime.finished) {
      throw StateError('Diese Einheit läuft nicht mehr.');
    }
    final identity = set.plannedSetId != null && set.plannedSetId!.isNotEmpty;
    final lookup = _syntheticPlanLookup(runtime);
    if (identity && !lookup.setIds.contains(set.plannedSetId)) {
      throw ArgumentError.value(set.plannedSetId, 'plannedSetId');
    }
    if (identity &&
        set.exerciseId != null &&
        lookup.setExercise[set.plannedSetId] != set.exerciseId) {
      throw ArgumentError.value(set.exerciseId, 'exerciseId');
    }
    if (identity &&
        lookup.setExerciseKey[set.plannedSetId] != null &&
        lookup.setExerciseKey[set.plannedSetId]!.isNotEmpty &&
        set.exerciseKey != lookup.setExerciseKey[set.plannedSetId]) {
      throw ArgumentError.value(set.exerciseKey, 'exerciseKey');
    }
    if (identity &&
        runtime.recorded.any((s) => s.plannedSetId == set.plannedSetId)) {
      return;
    }
    var restSec = set.restSec;
    if (restSec == null && identity) {
      restSec = lookup.restBySet[set.plannedSetId!];
    }
    final bound = bindRecordedStrengthSet(
      set: set,
      planExerciseId: identity ? lookup.setExercise[set.plannedSetId] : null,
      planExerciseKey: identity ? lookup.setExerciseKey[set.plannedSetId] : null,
      planDefinition: identity ? lookup.setDefinition[set.plannedSetId] : null,
    );
    final stored = RecordedSet(
      exerciseKey: bound.exerciseKey,
      setIndex: bound.setIndex,
      reps: bound.reps,
      seconds: bound.seconds,
      loadKg: bound.loadKg,
      at: bound.at,
      plannedSetId: identity ? bound.plannedSetId : null,
      exerciseId: identity
          ? (bound.exerciseId ?? lookup.setExercise[set.plannedSetId])
          : bound.exerciseId,
      restSec: restSec,
      load: bound.load,
      definition: bound.definition,
    );
    runtime.recorded.add(stored);
    runtime.restEndsAt = restSec != null && restSec > 0
        ? set.at.add(Duration(seconds: restSec))
        : null;
    (_liveSets[sessionId] ??= []).add(stored);
  }

  @override
  Future<void> skipPlannedSet(String sessionId, String plannedSetId) async {
    await _awaitStrengthWrite();
    if (failStrengthWrites) {
      throw StateError('Speichern schlägt fehl.');
    }
    final runtime = _strength[sessionId];
    if (runtime == null || runtime.finished) {
      throw StateError('Diese Einheit läuft nicht mehr.');
    }
    if (!_syntheticPlanLookup(runtime).setIds.contains(plannedSetId)) {
      throw ArgumentError.value(plannedSetId, 'plannedSetId');
    }
    runtime.skipped.add(plannedSetId);
  }

  @override
  Future<void> addPlannedSet(
    String sessionId,
    PlannedExercise exercise,
    PlannedSet set,
  ) async {
    await _awaitStrengthWrite();
    if (failStrengthWrites) {
      throw StateError('Speichern schlägt fehl.');
    }
    final runtime = _strength[sessionId];
    if (runtime == null || runtime.finished) {
      throw StateError('Diese Einheit läuft nicht mehr.');
    }
    if (set.id.isEmpty) {
      throw const FormatException('Planned set is missing a stable id.');
    }
    if (_syntheticPlanLookup(runtime).setIds.contains(set.id)) {
      throw ArgumentError.value(set.id, 'set.id');
    }
    final i = runtime.added.indexWhere((e) => e.id == exercise.id);
    if (i >= 0) {
      runtime.added[i] = PlannedExercise(
        id: runtime.added[i].id,
        exerciseKey: runtime.added[i].exerciseKey,
        name: runtime.added[i].name,
        sets: [...runtime.added[i].sets, set],
        note: runtime.added[i].note,
        definition: runtime.added[i].definition,
      );
    } else {
      runtime.added.add(
        PlannedExercise(
          id: exercise.id,
          exerciseKey: exercise.exerciseKey,
          name: exercise.name,
          sets: [set],
          note: exercise.note,
          definition: exercise.definition,
        ),
      );
    }
  }

  @override
  Future<void> skipRest(String sessionId) async {
    await _awaitStrengthWrite();
    if (failStrengthWrites) {
      throw StateError('Speichern schlägt fehl.');
    }
    final runtime = _strength[sessionId];
    if (runtime == null || runtime.finished) {
      throw StateError('Diese Einheit läuft nicht mehr.');
    }
    runtime.restEndsAt = null;
  }

  @override
  Future<void> extendRest(String sessionId, {int seconds = 30}) async {
    await _awaitStrengthWrite();
    if (failStrengthWrites) {
      throw StateError('Speichern schlägt fehl.');
    }
    if (seconds <= 0) {
      throw ArgumentError.value(seconds, 'seconds');
    }
    final runtime = _strength[sessionId];
    if (runtime == null || runtime.finished) {
      throw StateError('Diese Einheit läuft nicht mehr.');
    }
    final until = runtime.restEndsAt;
    if (until == null) {
      throw StateError('Keine Pause läuft.');
    }
    runtime.restEndsAt = until.add(Duration(seconds: seconds));
  }

  @override
  Future<ActiveStrengthRuntime> readActiveStrengthSession() async {
    if (failStrengthReadRemaining > 0) {
      failStrengthReadRemaining--;
      throw StateError('Einheit konnte nicht gelesen werden.');
    }
    if (legacyActiveStrength) {
      return LegacyActiveStrength(_activeStrengthId ?? 'legacy-wt');
    }
    final id = _activeStrengthId;
    if (id == null) return const NoActiveStrength();
    final runtime = _strength[id];
    if (runtime == null) return CorruptActiveStrength(id);
    return ActiveStrengthSession(
      sessionId: id,
      plan: runtime.plan,
      recorded: List.unmodifiable(runtime.recorded),
      skippedPlannedSetIds: Set.unmodifiable(runtime.skipped),
      added: List.unmodifiable(runtime.added),
      startedAt: runtime.startedAt,
      restEndsAt: runtime.restEndsAt,
    );
  }

  @override
  Future<Map<String, RecordedSet>> readPreviousStrengthSets(
    String sessionId,
  ) async {
    _seedPlans();
    final current = _strength[sessionId];
    if (current == null) {
      throw ArgumentError.value(sessionId, 'sessionId');
    }
    final slots = strengthPlanSlots(current.plan, current.added);
    final latestByExercise = <String, List<RecordedSet>>{};
    final latestStart = <String, DateTime>{};
    for (final e in _strength.entries) {
      if (e.key == sessionId) continue;
      final runtime = e.value;
      if (!runtime.finished) continue;
      if (!runtime.startedAt.isBefore(current.startedAt)) continue;
      final byKey = <String, List<RecordedSet>>{};
      for (final s in runtime.recorded) {
        (byKey[s.exerciseKey] ??= []).add(s);
      }
      for (final key in byKey.keys) {
        final seen = latestStart[key];
        if (seen != null && !runtime.startedAt.isAfter(seen)) continue;
        latestStart[key] = runtime.startedAt;
        latestByExercise[key] = byKey[key]!;
      }
    }
    return previousStrengthSetsFromLatest(
      slots: slots,
      latestByExercise: latestByExercise,
    );
  }

  ({
    Set<String> setIds,
    Map<String, String> setExercise,
    Map<String, String> setExerciseKey,
    Map<String, ExerciseDefinitionSnapshot> setDefinition,
    Map<String, int?> restBySet,
  })
  _syntheticPlanLookup(_SyntheticStrength runtime) {
    final setIds = <String>{};
    final setExercise = <String, String>{};
    final setExerciseKey = <String, String>{};
    final setDefinition = <String, ExerciseDefinitionSnapshot>{};
    final restBySet = <String, int?>{};
    for (final e in [...runtime.plan.exercises, ...runtime.added]) {
      for (final s in e.sets) {
        setIds.add(s.id);
        setExercise[s.id] = e.id;
        setExerciseKey[s.id] = e.exerciseKey;
        if (e.definition != null) setDefinition[s.id] = e.definition!;
        restBySet[s.id] = s.restSec;
      }
    }
    return (
      setIds: setIds,
      setExercise: setExercise,
      setExerciseKey: setExerciseKey,
      setDefinition: setDefinition,
      restBySet: restBySet,
    );
  }

  @override
  Future<void> finishStrengthSession(String sessionId) async {
    await _awaitStrengthWrite();
    if (failStrengthWrites) {
      throw StateError('Speichern schlägt fehl.');
    }
    final runtime = _strength[sessionId];
    if (runtime == null || _activeStrengthId != sessionId) {
      throw StateError('Diese Einheit läuft nicht mehr.');
    }
    runtime.finished = true;
    _activeStrengthId = null;
  }

  @override
  Future<MuscleLoad> readMuscleLoad(String endDay, int days) async {
    // B19 synthetic strength session on day -2: 3×8×60 + 3×8×40 + 3×10×30.
    final window = openBandDaysEnding(endDay, days).toSet();
    if (!window.contains(_shift(_day, -2))) return const MuscleLoad({}, 0);
    final byMuscle = <String, int>{};
    for (final key in ['squat', 'bench_press', 'row']) {
      for (final m in _muscles[key]!) {
        byMuscle[m] = (byMuscle[m] ?? 0) + 3;
      }
    }
    for (final s in _liveSets.values.expand((v) => v)) {
      final muscles = _muscles[s.exerciseKey];
      if (muscles == null) continue;
      for (final m in muscles) {
        byMuscle[m] = (byMuscle[m] ?? 0) + 1;
      }
    }
    return MuscleLoad(byMuscle, 0);
  }

  @override
  Future<ExerciseCatalogue> readExerciseCatalogue() async =>
      assembleExerciseCatalogue(_exerciseDefs.values);

  @override
  Future<CustomExerciseWriteResult> createCustomExercise(
    CustomExerciseDraft draft,
  ) async {
    requireCustomExerciseDraft(draft);
    final id = draft.id ?? newCustomExerciseId();
    if (exercisePresetById(id) != null) {
      throw ArgumentError.value(id, 'id');
    }
    if (_exerciseDefs.containsKey(id)) {
      return customExerciseCreateAgainstExisting(
        existing: _exerciseDefs[id]!,
        draft: draft,
        id: id,
      );
    }
    final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final row = encodeCustomExerciseRow(
      draft: draft,
      id: id,
      version: 1,
      createdAt: createdAt,
    );
    _exerciseDefs[id] = row;
    return CustomExerciseWriteResult.saved(parseStoredExerciseDef(row));
  }

  @override
  Future<CustomExerciseWriteResult> updateCustomExercise({
    required ExerciseDefinitionSnapshot expected,
    required CustomExerciseDraft draft,
  }) async {
    requireCustomExerciseDraft(draft);
    final id = draft.id ?? expected.id;
    if (id != expected.id) {
      throw ArgumentError.value(draft.id, 'id');
    }
    if (exercisePresetById(id) != null) {
      throw ArgumentError.value(id, 'id');
    }
    final expectedVersion = expected.version;
    if (expectedVersion == null) {
      throw ArgumentError.notNull('expected.version');
    }
    final currentRow = _exerciseDefs[id];
    if (currentRow == null) {
      return const CustomExerciseWriteResult.conflict();
    }
    ExerciseCatalogueEntry current;
    try {
      current = parseStoredExerciseDef(currentRow);
    } on FormatException {
      return const CustomExerciseWriteResult.conflict();
    }
    if (!isExplicitCustomExerciseRow(currentRow)) {
      return CustomExerciseWriteResult.conflict(current);
    }
    if (current.version != expectedVersion ||
        !customExerciseSnapshotsEqual(current.snapshot(), expected)) {
      return CustomExerciseWriteResult.conflict(current);
    }
    final createdAt = (currentRow['created_at'] as num?)?.toInt();
    if (createdAt == null) {
      throw const FormatException('Exercise definition is unreadable.');
    }
    final next = encodeCustomExerciseRow(
      draft: draft,
      id: id,
      version: expectedVersion + 1,
      createdAt: createdAt,
      retained: current.retained,
    );
    next['created_at'] = createdAt;
    _exerciseDefs[id] = next;
    return CustomExerciseWriteResult.saved(parseStoredExerciseDef(next));
  }

  @override
  Future<List<FoodHit>> searchFoods(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final f in _foods)
        if (f.label.toLowerCase().contains(q)) f,
    ];
  }

  @override
  Future<List<WorkoutTemplate>> readTemplates() async {
    _seedPlans();
    if (failTemplateRead) {
      throw StateError('Vorlagen konnten nicht geladen werden.');
    }
    return [
      for (final t in _templates.values)
        if (!_archivedTemplates.contains(t.id)) t,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<WorkoutTemplate> saveTemplate(WorkoutTemplate template) async {
    _seedPlans();
    if (templateWriteBarrier != null) await templateWriteBarrier;
    if (failTemplateWrite) throw StateError('Speichern fehlgeschlagen');
    if (template.name.trim().isEmpty || template.exercises.isEmpty) {
      throw ArgumentError('Eine Vorlage braucht Namen und eine Übung.');
    }
    final saved = WorkoutTemplate(
      id: template.id,
      name: template.name.trim(),
      version: (_templates[template.id]?.version ?? 0) + 1,
      exercises: template.exercises,
      updatedAt: DateTime.now(),
    );
    _templates[template.id] = saved;
    _archivedTemplates.remove(template.id);
    return saved;
  }

  @override
  Future<void> archiveTemplate(String id) async {
    _seedPlans();
    if (templateWriteBarrier != null) await templateWriteBarrier;
    if (failTemplateWrite) throw StateError('Archivieren fehlgeschlagen');
    if (!_templates.containsKey(id)) return;
    _archivedTemplates.add(id);
    if (_pinnedTemplateId == id) _pinnedTemplateId = null;
  }

  @override
  Future<String?> readPinnedTemplateId() async {
    _seedPlans();
    if (failPinRead) throw StateError('Anheften fehlgeschlagen');
    return _pinnedTemplateId;
  }

  @override
  Future<void> pinTemplate(String? id) async {
    _seedPlans();
    if (templateWriteBarrier != null) await templateWriteBarrier;
    if (failPin) throw StateError('Anheften fehlgeschlagen');
    if (id == null || id.isEmpty) {
      _pinnedTemplateId = null;
      return;
    }
    if (!_templates.containsKey(id) || _archivedTemplates.contains(id)) {
      throw StateError('Anheften fehlgeschlagen');
    }
    _pinnedTemplateId = id;
  }

  void clearTemplates() {
    _seedPlans();
    _templates.clear();
    _archivedTemplates.clear();
    _pinnedTemplateId = null;
  }

  List<FoodEntry> _entriesOn(String day) => [
    for (final e in _foodEntries.values)
      if (e.date == day) e,
  ]..sort((a, b) {
    // Match NutritionDb.entriesForDay: at_ts ASC (NULL first), created_at ASC.
    // Do not coalesce epoch seconds with ledger milliseconds.
    if (a.atTs == null && b.atTs != null) return -1;
    if (a.atTs != null && b.atTs == null) return 1;
    if (a.atTs != null && b.atTs != null) {
      final at = a.atTs!.compareTo(b.atTs!);
      if (at != 0) return at;
    }
    final created = (a.createdAt ?? 0).compareTo(b.createdAt ?? 0);
    if (created != 0) return created;
    return a.id.compareTo(b.id);
  });

  @override
  Future<DayMeals> readMeals(String day) async {
    if (failMealsRead) throw StateError('synthetic meals read failure');
    _seedPlans();
    final foods = _entriesOn(day);
    NutrientSum sum(double? Function(FoodEntry) pick) {
      var known = 0, unknown = 0;
      double total = 0;
      for (final e in foods) {
        final v = pick(e);
        if (v == null) {
          unknown++;
        } else {
          known++;
          total += v;
        }
      }
      return NutrientSum(known == 0 ? null : total, known, unknown);
    }

    return DayMeals(
      day: day,
      entries: [for (final e in foods) MealEntry.fromFood(e)],
      kcal: sum((e) => e.kcal),
      proteinG: sum((e) => e.proteinG),
      carbsG: sum((e) => e.carbsG),
      fatG: sum((e) => e.fatG),
    );
  }

  @override
  Future<NutritionWindow> readNutritionWindow(
    String endDay, {
    int days = 7,
  }) async {
    if (failMealsRead) throw StateError('synthetic meals read failure');
    if (!isLabCalendarDay(endDay)) {
      throw ArgumentError.value(endDay, 'endDay', 'Expected a real YYYY-MM-DD day.');
    }
    if (days < 1) {
      throw ArgumentError.value(days, 'days', 'Window length must be at least 1.');
    }
    _seedPlans();
    final labels = openBandDaysEnding(endDay, days);
    final today = nutritionToday();
    return NutritionWindow([
      for (final label in labels)
        rollupDay(label, _entriesOn(label), today: today),
    ]);
  }

  @override
  Future<List<FoodEntry>> readRecentFoods({int limit = 12}) async {
    if (failFoodRead) throw StateError('synthetic food read failure');
    _seedPlans();
    final rows = _foodEntries.values.toList()
      ..sort((a, b) {
        final created = (b.createdAt ?? 0).compareTo(a.createdAt ?? 0);
        if (created != 0) return created;
        return a.id.compareTo(b.id);
      });
    final out = <FoodEntry>[];
    final seen = <String>{};
    for (final e in rows) {
      final key = (e.foodKey != null && e.foodKey!.isNotEmpty)
          ? 'k:${e.foodKey}'
          : 'l:${e.label}\u0000${e.sourceCode}';
      if (!seen.add(key)) continue;
      out.add(e);
      if (out.length == limit) break;
    }
    return out;
  }

  @override
  Future<FoodSnapshotResult> readFoodEntry(String id) async {
    if (failFoodRead) throw StateError('synthetic food read failure');
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Food id is required.');
    }
    _seedPlans();
    final current = _foodEntries[id];
    if (current == null) return const FoodSnapshotResult.conflict();
    return FoodSnapshotResult.saved(current);
  }

  @override
  Future<FoodSnapshotResult> saveFoodEntry(
    FoodEntry expected,
    FoodEntry next,
  ) async {
    if (foodWriteBarrier != null) await foodWriteBarrier;
    if (failFoodWrite) throw StateError('synthetic food write failure');
    if (next.id != expected.id) {
      throw ArgumentError.value(next.id, 'id', 'Edited snapshot id must match.');
    }
    requireFoodEntryWrite(next);
    _seedPlans();
    final current = _foodEntries[expected.id];
    if (current == null || !foodEntriesEqual(current, expected)) {
      return FoodSnapshotResult.conflict(current);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final clean = next.sanitised;
    final saved = FoodEntry(
      id: clean.id,
      date: clean.date,
      meal: clean.meal,
      label: clean.label,
      atTs: clean.atTs,
      foodKey: clean.foodKey,
      quantity: clean.quantity,
      unit: clean.unit,
      kcal: clean.kcal,
      proteinG: clean.proteinG,
      carbsG: clean.carbsG,
      fatG: clean.fatG,
      fibreG: clean.fibreG,
      sugarG: clean.sugarG,
      satFatG: clean.satFatG,
      sodiumMg: clean.sodiumMg,
      ironMg: clean.ironMg,
      calciumMg: clean.calciumMg,
      source: clean.source,
      sourceCode: clean.sourceCode,
      confirmed: clean.confirmed,
      note: clean.note,
      createdAt: current.createdAt ?? now,
      updatedAt: now,
    );
    _foodEntries[saved.id] = saved;
    return FoodSnapshotResult.saved(saved);
  }

  @override
  Future<FoodSnapshotResult> removeFoodEntry(FoodEntry expected) async {
    if (foodWriteBarrier != null) await foodWriteBarrier;
    if (failFoodWrite) throw StateError('synthetic food write failure');
    if (expected.id.trim().isEmpty) {
      throw ArgumentError.value(expected.id, 'id', 'Food id is required.');
    }
    _seedPlans();
    final current = _foodEntries[expected.id];
    if (current == null || !foodEntriesEqual(current, expected)) {
      return FoodSnapshotResult.conflict(current);
    }
    _foodEntries.remove(expected.id);
    return FoodSnapshotResult.saved(current);
  }

  @override
  Future<FoodSnapshotResult> restoreFoodEntry(FoodEntry snapshot) async {
    if (foodWriteBarrier != null) await foodWriteBarrier;
    if (failFoodWrite) throw StateError('synthetic food write failure');
    requireFoodEntryWrite(snapshot);
    _seedPlans();
    final current = _foodEntries[snapshot.id];
    final clean = snapshot.sanitised;
    if (current != null) {
      if (foodEntriesEqual(current, snapshot.sanitised)) {
        return FoodSnapshotResult.saved(current);
      }
      return FoodSnapshotResult.conflict(current);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final saved = FoodEntry(
      id: clean.id,
      date: clean.date,
      meal: clean.meal,
      label: clean.label,
      atTs: clean.atTs,
      foodKey: clean.foodKey,
      quantity: clean.quantity,
      unit: clean.unit,
      kcal: clean.kcal,
      proteinG: clean.proteinG,
      carbsG: clean.carbsG,
      fatG: clean.fatG,
      fibreG: clean.fibreG,
      sugarG: clean.sugarG,
      satFatG: clean.satFatG,
      sodiumMg: clean.sodiumMg,
      ironMg: clean.ironMg,
      calciumMg: clean.calciumMg,
      source: clean.source,
      sourceCode: clean.sourceCode,
      confirmed: clean.confirmed,
      note: clean.note,
      createdAt: clean.createdAt ?? snapshot.createdAt ?? now,
      updatedAt: clean.updatedAt ?? snapshot.updatedAt ?? now,
    );
    _foodEntries[saved.id] = saved;
    return FoodSnapshotResult.saved(saved);
  }

  void seedFoodEntry(FoodEntry entry) {
    _seedPlans();
    _foodEntries[entry.id] = entry;
  }

  @override
  Future<MealDraft?> readMealDraft(String day, String meal) async =>
      _mealDrafts['$day/$meal'];

  @override
  Future<void> saveMealDraft(MealDraft draft) async {
    if (!isLabCalendarDay(draft.day)) {
      throw ArgumentError.value(draft.day, 'day', 'Expected a real YYYY-MM-DD day.');
    }
    if (draft.id.trim().isEmpty) {
      throw ArgumentError.value(draft.id, 'id', 'Draft id is required.');
    }
    for (final entry in draft.entries) {
      requireFoodEntryWrite(foodEntryFromDraft(draft, entry));
    }
    final persisted = jsonDecode(
      jsonEncode([for (final e in draft.entries) e.toJson()]),
    );
    _mealDrafts['${draft.day}/${draft.meal}'] = MealDraft(
      id: draft.id,
      day: draft.day,
      meal: draft.meal,
      entries: [
        for (final e in persisted as List)
          MealDraftEntry.fromJson(e as Map<String, dynamic>),
      ],
      updatedAt: draft.updatedAt,
    );
  }

  @override
  Future<MealDraftSaveResult> compareAndSaveMealDraft({
    required MealDraft? expected,
    required MealDraft draft,
  }) async {
    requireMealDraftCompare(expected: expected, draft: draft);
    if (scenario == SyntheticScenario.saveFailure) {
      throw StateError('Speichern schlägt fehl.');
    }
    if (foodWriteBarrier != null) await foodWriteBarrier;
    if (failFoodWrite) throw StateError('synthetic food write failure');
    final key = '${draft.day}/${draft.meal}';
    final stored = _mealDrafts[key];
    if (expected == null) {
      if (stored != null) return MealDraftSaveResult.conflict;
    } else if (stored == null ||
        !mealDraftRevisionMatches(expected, stored)) {
      return MealDraftSaveResult.conflict;
    }
    for (final other in _mealDrafts.values) {
      if (other.id == draft.id &&
          (other.day != draft.day || other.meal != draft.meal)) {
        return MealDraftSaveResult.conflict;
      }
    }
    final persisted = jsonDecode(
      jsonEncode([for (final e in draft.entries) e.toJson()]),
    );
    final nextRev = nextMealDraftRevision(
      stored?.updatedAt.millisecondsSinceEpoch,
      DateTime.now().millisecondsSinceEpoch,
    );
    _mealDrafts[key] = MealDraft(
      id: draft.id,
      day: draft.day,
      meal: draft.meal,
      entries: [
        for (final e in persisted as List)
          MealDraftEntry.fromJson(e as Map<String, dynamic>),
      ],
      updatedAt: DateTime.fromMillisecondsSinceEpoch(nextRev),
    );
    return MealDraftSaveResult.saved;
  }

  @override
  Future<void> discardMealDraft(String draftId) async {
    _mealDrafts.removeWhere((_, d) => d.id == draftId);
  }

  @override
  Future<MealDraftCommitResult> commitMealDraft(MealDraft draft) async {
    _seedPlans();
    if (draft.id.trim().isEmpty) {
      throw ArgumentError.value(draft.id, 'id', 'Draft id is required.');
    }
    if (draft.entries.isEmpty) {
      throw ArgumentError('Ein leerer Entwurf wird nicht gespeichert.');
    }
    if (scenario == SyntheticScenario.saveFailure) {
      throw StateError('Speichern schlägt fehl.');
    }
    if (foodWriteBarrier != null) await foodWriteBarrier;
    if (failFoodWrite) throw StateError('synthetic food write failure');
    if (!isLabCalendarDay(draft.day)) {
      throw ArgumentError.value(draft.day, 'day', 'Expected a real YYYY-MM-DD day.');
    }
    final entries = [
      for (final e in draft.entries) foodEntryFromDraft(draft, e),
    ];
    for (final entry in entries) {
      requireFoodEntryWrite(entry);
    }
    MealDraft? stored;
    for (final d in _mealDrafts.values) {
      if (d.id == draft.id) {
        stored = d;
        break;
      }
    }
    var allowInsert = false;
    if (stored != null) {
      if (stored.day != draft.day || stored.meal != draft.meal) {
        return MealDraftCommitResult.conflict;
      }
      final storedJson = jsonEncode([for (final e in stored.entries) e.toJson()]);
      final expectedJson = jsonEncode([
        for (final e in draft.entries) e.toJson(),
      ]);
      if (storedJson != expectedJson) {
        return MealDraftCommitResult.conflict;
      }
      allowInsert = true;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final pending = <String, FoodEntry>{};
    for (final entry in entries) {
      final clean = entry.sanitised;
      final current = _foodEntries[entry.id];
      if (current == null) {
        if (!allowInsert) {
          return MealDraftCommitResult.conflict;
        }
        pending[clean.id] = FoodEntry(
          id: clean.id,
          date: clean.date,
          meal: clean.meal,
          label: clean.label,
          atTs: clean.atTs,
          foodKey: clean.foodKey,
          quantity: clean.quantity,
          unit: clean.unit,
          kcal: clean.kcal,
          proteinG: clean.proteinG,
          carbsG: clean.carbsG,
          fatG: clean.fatG,
          fibreG: clean.fibreG,
          sugarG: clean.sugarG,
          satFatG: clean.satFatG,
          sodiumMg: clean.sodiumMg,
          ironMg: clean.ironMg,
          calciumMg: clean.calciumMg,
          source: clean.source,
          sourceCode: clean.sourceCode,
          confirmed: clean.confirmed,
          note: clean.note,
          createdAt: clean.createdAt ?? now,
          updatedAt: now,
        );
        continue;
      }
      if (!foodEntriesEqual(current, clean, ledger: false)) {
        return MealDraftCommitResult.conflict;
      }
    }
    if (allowInsert) {
      _foodEntries.addAll(pending);
      _mealDrafts.removeWhere((_, d) => d.id == draft.id);
    }
    return MealDraftCommitResult.saved;
  }

  @override
  Future<SessionDetail?> readSessionDetail(String sessionId) async {
    final r = run;
    if (r == null || !sessionId.endsWith('-running')) return null;
    final day = sessionId.substring(
      'synthetic-'.length,
      'synthetic-'.length + 10,
    );
    final zones = [
      for (final s in r['zone_seconds_0_to_5'] as List) (s as num).toInt(),
    ];
    final splits = r['split_seconds'] as List;
    return SessionDetail(
      sessionId: sessionId,
      type: 'running',
      day: day,
      start: _at(day, r['start'] as String),
      algoVersion: 0,
      durationSec: (r['duration_seconds'] as num).toInt(),
      pauseSec: (r['pause_seconds'] as num).toInt(),
      distanceM: (r['distance_m'] as num).toDouble(),
      avgHr: (r['hr_mean'] as num).toDouble(),
      maxHr: (r['hr_max'] as num).toInt(),
      hrCoveredSec: (r['duration_seconds'] as num).toInt(),
      strain: (r['strain_0_21'] as num).toDouble(),
      kcal: (r['bout_kcal'] as num).toDouble(),
      hrr60: ((r['hrr60'] as Map)['drop_bpm'] as num).toInt(),
      hrr120: ((r['hrr120'] as Map)['drop_bpm'] as num).toInt(),
      zoneSec: zones,
      splits: [
        for (final (i, s) in splits.indexed)
          SessionSplit(km: i + 1, seconds: (s as num).toInt()),
      ],
      laps: List.unmodifiable(_laps[sessionId] ?? const []),
    );
  }

  final Map<String, List<Lap>> _laps = {};

  @override
  Future<void> recordLap(String sessionId, Lap lap) async {
    (_laps[sessionId] ??= []).add(lap);
  }

  @override
  Future<List<Lap>> readLaps(String sessionId) async =>
      List.unmodifiable(_laps[sessionId] ?? const []);

  @override
  Future<CaffeineSleepPattern> readCaffeineSleepPattern(
    String endDay,
    int nights,
  ) {
    final request =
        '$endDay/$nights/$_caffeineSleepPatternGeneration/$failCaffeineSleepPattern';
    if (_caffeineSleepPatternRequest == request &&
        caffeineSleepPatternPending != null) {
      return caffeineSleepPatternPending!;
    }
    final Future<CaffeineSleepPattern> pending;
    if (nights < 1) {
      pending = Future<CaffeineSleepPattern>.error(
        ArgumentError.value(nights, 'nights', 'Expected at least 1 night.'),
      )..ignore();
    } else if (failCaffeineSleepPattern) {
      pending = Future<CaffeineSleepPattern>.error(
        StateError('synthetic caffeine sleep pattern failure'),
      )..ignore();
    } else {
      pending = Zone.root.run(
        () => _produceCaffeineSleepPattern(endDay, nights),
      );
    }
    _caffeineSleepPatternRequest = request;
    caffeineSleepPatternPending = pending;
    return pending;
  }

  void _invalidateCaffeineSleepPattern() {
    _caffeineSleepPatternGeneration++;
    _caffeineSleepPatternRequest = null;
    caffeineSleepPatternPending = null;
  }

  Future<CaffeineSleepPattern> _produceCaffeineSleepPattern(
    String endDay,
    int nights,
  ) async {
    if (failCaffeineSleepPattern) {
      throw StateError('synthetic caffeine sleep pattern failure');
    }
    if (nights < 1) {
      throw ArgumentError.value(nights, 'nights', 'Expected at least 1 night.');
    }
    final days = openBandDaysEnding(endDay, nights + 1);
    final journal = [
      for (final d in days)
        if (_journal[d]?.metrics[CaffeineSleepPattern.field]?.value
            case final v? when v == 0.0 || v == 1.0)
          {
            'date': d,
            'values': {CaffeineSleepPattern.field: v},
          },
    ];
    final outcomes = [
      for (final d in days) _solIneligible.containsKey(d) ? null : _solMin[d],
    ];
    final availableOutcomes = [
      for (var i = 1; i < outcomes.length; i++)
        if (outcomes[i] != null) i,
    ].length;
    final partial = days.any(_solIneligible.containsKey);
    if (journal.isEmpty || availableOutcomes == 0) {
      return CaffeineSleepPattern.fromProducer(
        empty: true,
        binary: false,
        insufficient: true,
        meaningful: false,
        n: 0,
        endDay: endDay,
        startDay: days.first,
        nights: nights,
        algoVersion: kAlgoVersion,
        partial: partial,
        availableOutcomes: availableOutcomes,
      );
    }
    final produced = await Isolate.run(
      () => _syntheticCaffeineSleepCorrelate({
        'dates': days,
        'journal': journal,
        'sol': outcomes,
      }),
    );
    return CaffeineSleepPattern.fromProducer(
      empty: produced['empty'] == true,
      binary: produced['binary'] == true,
      insufficient: produced['insufficient'] == true,
      meaningful: produced['meaningful'] == true,
      n: (produced['n'] as num?)?.toInt() ?? 0,
      nWith: (produced['nWith'] as num?)?.toInt(),
      nWithout: (produced['nWithout'] as num?)?.toInt(),
      delta: (produced['delta'] as num?)?.toDouble(),
      note: produced['note'] as String?,
      endDay: endDay,
      startDay: days.first,
      nights: nights,
      algoVersion: kAlgoVersion,
      partial: partial,
      availableOutcomes: availableOutcomes,
    );
  }

  @override
  Future<List<JournalEntry>> readJournal(String day) async => [
    for (final e in (_journal[day]?.metrics ?? const {}).entries)
      JournalEntry(e.key, e.value.value),
  ];

  @override
  Future<void> writeJournal(String day, String key, double value) async {
    if (key == CaffeineSleepPattern.field) _invalidateCaffeineSleepPattern();
    final row = _journal[day] ??= _SynthJournalDay();
    final prev = row.metrics[key];
    row.metrics[key] = JournalMetricValue(
      value,
      atMinuteOfDay: prev?.atMinuteOfDay,
    );
    row.metricUpdatedAt[key] = _nextJournalRev(row.metricUpdatedAt[key] ?? 0);
  }

  @override
  Future<JournalDaySnapshot> readJournalDay(String day) async {
    if (journalReadBarrier != null) await journalReadBarrier;
    if (failJournalRead) throw StateError('synthetic journal read failure');
    final row = _journal[day];
    return JournalDaySnapshot(
      day: day,
      metrics: {...?row?.metrics},
      metricUpdatedAt: {...?row?.metricUpdatedAt},
      tags: [...?row?.tags],
      note: row?.note ?? '',
      journalUpdatedAt: row?.journalUpdatedAt ?? 0,
      fields: await listJournalFields(),
    );
  }

  @override
  Future<void> patchJournalDay(JournalDayPatch patch) async {
    if (!isJournalDayId(patch.day)) {
      throw ArgumentError.value(patch.day, 'day', 'Expected YYYY-MM-DD.');
    }
    final fields = <String, JournalFieldSpec>{
      for (final f in [...kJournalFields, ..._journalFieldDefs.values])
        f.key: f,
    };
    for (final e in patch.metrics.entries) {
      if (e.key.isEmpty || !fields.containsKey(e.key)) {
        throw ArgumentError.value(e.key, 'field', 'Unknown journal field.');
      }
      if (e.value == null) continue;
      validateJournalPatchMetric(fields[e.key]!, e.value!);
    }
    if (journalPatchBarrier != null) await journalPatchBarrier;
    if (failJournalPatch) throw StateError('synthetic journal save failure');
    final row = _journal[patch.day] ??= _SynthJournalDay();
    final conflicts = <String>[];
    for (final key in patch.metrics.keys) {
      final stored = row.metrics[key];
      final storedRev = row.metricUpdatedAt[key] ?? 0;
      final expectedRev = patch.expectedMetricUpdatedAt[key] ?? 0;
      if (storedRev != expectedRev || stored != patch.expectedMetrics[key]) {
        conflicts.add(key);
      }
    }
    final journalDirty = patch.tags != null || patch.note != null;
    if (journalDirty) {
      final expectedRev = patch.expectedJournalUpdatedAt ?? 0;
      if (row.journalUpdatedAt != expectedRev) {
        conflicts.add('journal');
      } else {
        if (patch.expectedNote != null && row.note != patch.expectedNote) {
          conflicts.add('journal');
        }
        if (patch.expectedTags != null) {
          final a = row.tags.toSet();
          final b = patch.expectedTags!.toSet();
          if (a.length != b.length || !a.containsAll(b)) {
            conflicts.add('journal');
          }
        }
      }
    }
    if (conflicts.isNotEmpty) {
      throw JournalConflict(patch.day, fields: conflicts);
    }
    if (patch.metrics.containsKey(CaffeineSleepPattern.field)) {
      _invalidateCaffeineSleepPattern();
    }
    for (final e in patch.metrics.entries) {
      if (e.value == null) {
        row.metrics.remove(e.key);
        row.metricUpdatedAt.remove(e.key);
      } else {
        row.metrics[e.key] = e.value!;
        row.metricUpdatedAt[e.key] = _nextJournalRev(
          row.metricUpdatedAt[e.key] ?? 0,
        );
      }
    }
    if (journalDirty) {
      if (patch.tags != null) row.tags = [...patch.tags!];
      if (patch.note != null) row.note = patch.note!;
      row.journalUpdatedAt = _nextJournalRev(row.journalUpdatedAt);
    }
  }

  @override
  Future<WeightHistory> readWeightHistory(String endDay, int days) async {
    requireWeightHistoryDay(endDay);
    requireWeightHistoryDays(days);
    if (journalReadBarrier != null) await journalReadBarrier;
    if (failJournalRead) throw StateError('synthetic journal read failure');
    return buildWeightHistory(
      endDay: endDay,
      days: days,
      rows: [
        for (final e in _journal.entries)
          if (e.value.metrics[kWeightJournalField] case final metric?)
            WeightStoredRow(
              date: e.key,
              value: metric.value,
              updatedAt: e.value.metricUpdatedAt[kWeightJournalField],
              atMinuteOfDay: metric.atMinuteOfDay,
            ),
      ],
    );
  }

  @override
  Future<double?> adjustWater(String day, double deltaMl) async {
    if (!isJournalDayId(day)) {
      throw ArgumentError.value(day, 'day', 'Expected YYYY-MM-DD.');
    }
    if (!deltaMl.isFinite) {
      throw ArgumentError.value(
        deltaMl,
        'deltaMl',
        'Water delta must be finite.',
      );
    }
    if (journalPatchBarrier != null) await journalPatchBarrier;
    if (failJournalPatch) throw StateError('synthetic journal save failure');
    final max = kJournalFieldsByKey['water_ml']!.max;
    final row = _journal[day];
    final stored = row?.metrics['water_ml'];
    if (stored == null) {
      if (deltaMl <= 0) return null;
      final value = deltaMl.clamp(0.0, max).toDouble();
      final created = _journal[day] ??= _SynthJournalDay();
      created.metrics['water_ml'] = JournalMetricValue(value);
      created.metricUpdatedAt['water_ml'] = _nextJournalRev(0);
      return value;
    }
    if (stored.value == 0 && deltaMl < 0) {
      row!.metrics.remove('water_ml');
      row.metricUpdatedAt.remove('water_ml');
      return null;
    }
    final value = (stored.value + deltaMl).clamp(0.0, max).toDouble();
    row!.metrics['water_ml'] = JournalMetricValue(
      value,
      atMinuteOfDay: stored.atMinuteOfDay,
    );
    row.metricUpdatedAt['water_ml'] = _nextJournalRev(
      row.metricUpdatedAt['water_ml'] ?? 0,
    );
    return value;
  }

  int _nextJournalRev(int stored) {
    _journalClock += 1;
    return _journalClock > stored ? _journalClock : stored + 1;
  }

  @override
  Future<List<JournalFieldSpec>> listJournalFields({
    bool includeHidden = false,
  }) async {
    if (failJournalFieldsList) {
      throw StateError('synthetic journal fields list failure');
    }
    final custom =
        _journalFieldDefs.values
            .where((f) => includeHidden || !f.hidden)
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
    return [...kJournalFields, ...custom];
  }

  @override
  Future<JournalFieldSpec> createJournalField(JournalFieldSpec spec) async {
    if (failJournalFieldsCreate) {
      throw StateError('synthetic journal field create failure');
    }
    final prepared = preparedCustomJournalField(spec);
    if (_journalFieldDefs.containsKey(prepared.key)) {
      throw StateError('journal field already exists: ${prepared.key}');
    }
    for (final day in _journal.values) {
      if (day.metrics.containsKey(prepared.key)) {
        throw StateError(
          'journal field key is already recorded: ${prepared.key}',
        );
      }
    }
    return _journalFieldDefs[prepared.key] = prepared;
  }

  @override
  Future<void> hideJournalField(String key) async {
    if (kJournalFieldsByKey.containsKey(key) || key.isEmpty) {
      throw ArgumentError.value(
        key,
        'key',
        'Cannot hide a built-in journal field.',
      );
    }
    final existing = _journalFieldDefs[key];
    if (existing == null) return;
    _journalFieldDefs[key] = JournalFieldSpec(
      key: existing.key,
      label: existing.label,
      kind: existing.kind,
      unit: existing.unit,
      max: existing.max,
      step: existing.step,
      hasTime: existing.hasTime,
      custom: true,
      hidden: true,
    );
  }

  @override
  Future<void> restoreJournalField(String key) async {
    final existing = _journalFieldDefs[key];
    if (existing == null) {
      throw StateError('journal field not found: $key');
    }
    _journalFieldDefs[key] = JournalFieldSpec(
      key: existing.key,
      label: existing.label,
      kind: existing.kind,
      unit: existing.unit,
      max: existing.max,
      step: existing.step,
      hasTime: existing.hasTime,
      custom: true,
      hidden: false,
    );
  }

  @override
  Future<List<TrainingSession>> readSessions(String endDay, int days) async {
    final window = openBandDaysEnding(endDay, days).toSet();
    // B20 synthetic period: 9.–15.09. = 32 + 45 + 25 minutes, comparison
    // week 35 + 43. Only the run carries strain/energy (run-detail fixture).
    final all = [
      (-13, 'cycling', '17:40', 35, null, null),
      (-9, 'weight_training', '18:05', 43, null, null),
      (-3, 'cycling', '17:32', 32, null, null),
      (-2, 'weight_training', '18:10', 45, null, null),
      (-1, 'running', '07:05', 25, 5.8716, 327.2537),
    ];
    return [
      for (final (offset, type, time, minutes, strain, kcal) in all.reversed)
        if (_shift(_day, offset) case final day when window.contains(day))
          TrainingSession(
            id: 'synthetic-$day-$type',
            day: day,
            type: type,
            start: _at(day, time),
            durationMin: minutes,
            strain: strain,
            kcal: kcal,
          ),
    ];
  }

  @override
  Future<List<MetricPoint>> readMetricHistory(
    MetricKey key,
    String endDay,
    int nights,
  ) async {
    if (key == MetricKey.hrv ||
        key == MetricKey.restingHr ||
        key == MetricKey.respiration ||
        key == MetricKey.skinTemperature) {
      return nightScalarHistoryPoints(
        await readNightScalarDetail(key, endDay, nights),
      );
    }
    final recovery = Map<String, dynamic>.from(_summary['recovery'] as Map);
    final todayKnown =
        scenario != SyntheticScenario.missing &&
        scenario != SyntheticScenario.processing;
    final source = switch (key) {
      MetricKey.hrv ||
      MetricKey.restingHr ||
      MetricKey.respiration ||
      MetricKey.skinTemperature => const <String, double>{},
      MetricKey.recovery => {
        if (todayKnown) _day: (recovery['score'] as num).toDouble(),
      },
      MetricKey.sleepDuration => {
        for (final e in _sleepByDay.entries)
          if (e.key != _day) e.key: e.value,
        // Today's stored duration follows the scenario (partial night etc.),
        // exactly what readDay reports, so hero and trend never disagree.
        if (todayKnown) _day: ?(await readDay(_day)).sleep.duration.value,
      },
      MetricKey.strain => {
        ..._strainByDay,
        if (todayKnown) _day: ?(await readDay(_day)).strain.value,
      },
    };
    return [
      for (final d in openBandDaysEnding(endDay, nights))
        MetricPoint(d, source[d]),
    ];
  }

  bool failNightScalarRead = false;
  NightScalarDetail? nightScalarOverride;
  final Map<NightScalarMetric, _NightScalarSeed> _nightScalarSeeds = {};

  /// Per-metric seed. [key] defaults to HRV so existing callers stay HRV-only.
  /// Name [MetricKey.restingHr], [MetricKey.respiration], or
  /// [MetricKey.skinTemperature] to seed those. The other metrics are not
  /// invented. Pass the same [sleepJobs]/[napJobs] on both seeds when they
  /// share a correction. Skin temperature is never fabricated from Paper
  /// recovery maps — seed explicitly, including [seedPaperSkinTemperature].
  void seedNightScalarDetail({
    MetricKey key = MetricKey.hrv,
    NightScalarRow? selected,
    Map<String, NightScalarRow> matching = const {},
    Set<String> otherVersionDays = const {},
    Set<String> seriesOnlyDays = const {},
    Map<String, NightScalarJob> sleepJobs = const {},
    Map<String, NightScalarJob> napJobs = const {},
    String? recordingTimezone,
    int? currentAlgo,
  }) {
    _nightScalarSeeds[nightScalarMetricOf(key)] = _NightScalarSeed(
      selected: selected,
      matching: matching,
      otherVersionDays: otherVersionDays,
      seriesOnlyDays: seriesOnlyDays,
      sleepJobs: sleepJobs,
      napJobs: napJobs,
      recordingTimezone: recordingTimezone,
      currentAlgo: currentAlgo,
    );
  }

  /// Trailing Paper skin-temperature positions ending [kNightScalarPaperDay].
  /// The 15-value fixture is the last 15 of 30; 7 and 90 take the trailing
  /// overlap (last 7 of the fixture, or the fixture as the last 15 of 90).
  /// SD is `band`; Celsius is `whoop_export` + imported; unknown is `cloud_v2`.
  void seedPaperSkinTemperature({
    NightScalarUnit unit = NightScalarUnit.sd,
    String day = kNightScalarPaperDay,
    int nights = 30,
  }) {
    final days = nightScalarDaysEnding(day, nights);
    final paper = switch (unit) {
      NightScalarUnit.celsius => kNightScalarPaperSkinTempC,
      NightScalarUnit.sd || NightScalarUnit.unknown =>
        kNightScalarPaperSkinTempSd,
    };
    final take = paper.length < days.length ? paper.length : days.length;
    final paperOffset = paper.length - take;
    final dayOffset = days.length - take;
    final matching = <String, NightScalarRow>{};
    NightScalarRow? selected;
    final payloadSource = switch (unit) {
      NightScalarUnit.sd => 'band',
      NightScalarUnit.celsius => 'whoop_export',
      NightScalarUnit.unknown => 'cloud_v2',
    };
    for (var i = 0; i < take; i++) {
      final id = days[dayOffset + i];
      final value = paper[paperOffset + i];
      if (value == null) continue;
      final row = NightScalarRow(
        day: id,
        algoVersion: kAlgoVersion,
        value: value,
        imported: unit == NightScalarUnit.celsius,
        source: payloadSource,
        rowSource: payloadSource,
      );
      matching[id] = row;
      if (id == day) selected = row;
    }
    seedNightScalarDetail(
      key: MetricKey.skinTemperature,
      selected: selected,
      matching: matching,
    );
  }

  NightScalarDetail? _nightScalarOverrideFor(
    NightScalarMetric metric,
    String day,
  ) {
    final override = nightScalarOverride;
    if (override == null || override.key != metric || override.day != day) {
      return null;
    }
    return override;
  }

  @override
  Future<NightScalarDetail> readNightScalarDetail(
    MetricKey key,
    String day,
    int nights,
  ) async {
    if (failNightScalarRead) {
      throw StateError('synthetic night scalar read failure');
    }
    final metric = nightScalarMetricOf(key);
    final override = _nightScalarOverrideFor(metric, day);
    if (override != null) return override;
    final days = nightScalarDaysEnding(day, nights);
    final seed = _nightScalarSeeds[metric];
    if (seed != null) {
      return buildNightScalarDetail(
        day: day,
        key: metric,
        nights: nights,
        currentAlgo: seed.currentAlgo ?? kAlgoVersion,
        days: days,
        selected: seed.rowFor(day),
        matching: seed.matching,
        otherVersionDays: seed.otherVersionDays,
        seriesOnlyDays: seed.seriesOnlyDays,
        sleepJobs: seed.sleepJobs,
        napJobs: seed.napJobs,
        recordingTimezone: seed.recordingTimezone,
      );
    }
    if (_nightScalarSeeds.isNotEmpty) {
      return buildNightScalarDetail(
        day: day,
        key: metric,
        nights: nights,
        currentAlgo: kAlgoVersion,
        days: days,
      );
    }
    return _produceNightScalarDetail(metric, day, days);
  }

  NightScalarDetail _produceNightScalarDetail(
    NightScalarMetric key,
    String day,
    List<String> days,
  ) {
    final byDay = switch (key) {
      NightScalarMetric.hrv => _hrvByDay,
      NightScalarMetric.rhr => _rhrByDay,
      NightScalarMetric.respiration => _respByDay,
      NightScalarMetric.skinTemperature => const <String, double>{},
    };
    final recovery = Map<String, dynamic>.from(_summary['recovery'] as Map);
    final onFixtureDay = day == _day;
    final missing = scenario == SyntheticScenario.missing;
    final processing = onFixtureDay && scenario == SyntheticScenario.processing;
    final failed =
        onFixtureDay && scenario == SyntheticScenario.calculationFailure;
    final selectedPartial =
        onFixtureDay && scenario == SyntheticScenario.partial;
    double? selectedValue;
    if (onFixtureDay && !missing) {
      selectedValue = switch (key) {
        NightScalarMetric.hrv => (recovery['hrv_ms'] as num).toDouble(),
        NightScalarMetric.rhr => (recovery['rhr_bpm'] as num).toDouble(),
        NightScalarMetric.respiration =>
          (recovery['resp_per_min'] as num).toDouble(),
        NightScalarMetric.skinTemperature => null,
      };
    } else if (!onFixtureDay) {
      selectedValue = byDay[day];
    }
    final baselineValue = onFixtureDay && selectedValue != null
        ? switch (key) {
            NightScalarMetric.hrv => kNightScalarPaperHrvBaseline,
            NightScalarMetric.rhr => kNightScalarPaperRhrBaseline,
            NightScalarMetric.respiration => null,
            NightScalarMetric.skinTemperature => null,
          }
        : null;
    NightScalarRow? selected;
    if (selectedValue != null) {
      selected = NightScalarRow(
        day: day,
        algoVersion: kAlgoVersion,
        partial: selectedPartial,
        value: selectedValue,
        computedAtMs: onFixtureDay
            ? _baseBand.latestStoredAt?.millisecondsSinceEpoch
            : null,
        baseline: baselineValue == null
            ? null
            : StoredNightBaseline(value: baselineValue),
        windowStartMs: onFixtureDay ? _onset.millisecondsSinceEpoch : null,
        windowEndMs: onFixtureDay ? _wake.millisecondsSinceEpoch : null,
      );
    }
    final matching = <String, NightScalarRow>{
      for (final id in days)
        if (id == day && selected != null)
          id: selected
        else if (!(missing && id == _day) && byDay[id] != null)
          id: NightScalarRow(
            day: id,
            algoVersion: kAlgoVersion,
            value: byDay[id],
          ),
    };
    return buildNightScalarDetail(
      day: day,
      key: key,
      nights: days.length,
      currentAlgo: kAlgoVersion,
      days: days,
      selected: selected,
      matching: matching,
      sleepJobs: {
        if (processing) day: NightScalarJob(day: day, status: 'pending'),
      },
      napJobs: {
        if (failed) day: NightScalarJob(day: day, status: 'failed'),
      },
    );
  }

  @override
  Future<OpenBandDay> readDay(String day) async {
    if (day == _day) return _withNightScalarCards(_overlay(_baseDay()));
    return _withNightScalarCards(
      OpenBandDay(
        day: day,
        sleep: SleepNight(
          duration: _sleepByDay.containsKey(day)
              ? DayMetric(_sleepByDay[day])
              : const DayMetric.missing(),
          history: _history
              .where((sample) => sample.day.compareTo(day) <= 0)
              .toList(),
          recordingTimezone: _timezone,
        ),
        recovery: const DayMetric.missing(),
        strain: const DayMetric.missing(),
        hrv: _hrvByDay.containsKey(day)
            ? DayMetric(_hrvByDay[day])
            : const DayMetric.missing(),
        restingHr: _rhrByDay.containsKey(day)
            ? DayMetric(_rhrByDay[day])
            : const DayMetric.missing(),
        respiration: _respByDay.containsKey(day)
            ? DayMetric(_respByDay[day])
            : const DayMetric.missing(),
        synthetic: true,
      ),
    );
  }

  OpenBandDay _withNightScalarCards(OpenBandDay day) {
    DayMetric card({
      required NightScalarMetric metric,
      required DayMetric published,
    }) {
      NightScalarUnit? unitOf(NightScalarRow? row, [NightScalarDetail? detail]) {
        if (metric != NightScalarMetric.skinTemperature) return null;
        if (detail != null) return detail.unit;
        if (row == null) return null;
        return nightScalarSkinTemperatureUnit(
          resultSource: row.rowSource,
          payloadSource: row.payloadUnreadable ? null : row.source,
          imported: row.payloadUnreadable ? false : row.imported,
        );
      }

      final override = _nightScalarOverrideFor(metric, day.day);
      if (override != null) {
        return dayMetricFromNightScalar(
          state: override.state,
          value: override.value,
          baseline: metric == NightScalarMetric.skinTemperature
              ? null
              : override.baseline,
          unit: unitOf(null, override),
        );
      }
      final seed = _nightScalarSeeds[metric];
      if (seed != null) {
        final selected = seed.rowFor(day.day);
        final overlay = nightScalarJobsOverlay(
          sleep: seed.sleepJobs[day.day],
          nap: seed.napJobs[day.day],
          row: selected,
          storedAlgo: selected?.algoVersion,
          storedComputedAt: selected?.computedAtMs,
        );
        return dayMetricFromNightScalar(
          state: nightScalarPublishedState(
            overlay: overlay,
            selected: selected,
            currentAlgo: seed.currentAlgo ?? kAlgoVersion,
            value: selected?.value,
          ),
          value: selected?.value,
          baseline: metric == NightScalarMetric.skinTemperature
              ? null
              : selected?.baseline,
          unit: unitOf(selected),
        );
      }
      if (_nightScalarSeeds.isNotEmpty) {
        return dayMetricFromNightScalar(
          state: NightScalarState.missing,
        );
      }
      NightScalarRow? selected;
      if (metric != NightScalarMetric.skinTemperature &&
          !(scenario == SyntheticScenario.missing && day.day == _day)) {
        if (day.day == _day) {
          selected = NightScalarRow(
            day: day.day,
            algoVersion: kAlgoVersion,
            partial: scenario == SyntheticScenario.partial,
            computedAtMs: _baseBand.latestStoredAt?.millisecondsSinceEpoch,
            windowStartMs: _onset.millisecondsSinceEpoch,
            windowEndMs: _wake.millisecondsSinceEpoch,
          );
        } else if (published.value != null) {
          selected = NightScalarRow(day: day.day, algoVersion: kAlgoVersion);
        }
      }
      final overlay = nightScalarJobsOverlay(
        sleep: (scenario == SyntheticScenario.processing && day.day == _day)
            ? NightScalarJob(day: day.day, status: 'pending')
            : null,
        nap: (scenario == SyntheticScenario.calculationFailure &&
                day.day == _day)
            ? NightScalarJob(day: day.day, status: 'failed')
            : null,
        row: selected,
        storedAlgo: selected?.algoVersion,
        storedComputedAt: selected?.computedAtMs,
      );
      return dayMetricFromNightScalar(
        state: nightScalarPublishedState(
          overlay: overlay,
          selected: selected,
          currentAlgo: kAlgoVersion,
          value: published.value,
        ),
        value: published.value,
        baseline: selected?.baseline,
        unit: unitOf(selected),
      );
    }

    return OpenBandDay(
      day: day.day,
      sleep: day.sleep,
      recovery: day.recovery,
      strain: day.strain,
      hrv: card(metric: NightScalarMetric.hrv, published: day.hrv),
      restingHr: card(metric: NightScalarMetric.rhr, published: day.restingHr),
      respiration: card(
        metric: NightScalarMetric.respiration,
        published: day.respiration,
      ),
      skinTemperature: card(
        metric: NightScalarMetric.skinTemperature,
        published: day.skinTemperature,
      ),
      steps: day.steps,
      stepIntervals: day.stepIntervals,
      calculatedAt: day.calculatedAt,
      intake: day.intake,
      correction: day.correction,
      synthetic: day.synthetic,
    );
  }

  @override
  Future<SetupEvaluation> readSetupEvaluation(String day) async {
    if (failSetupEvaluation) {
      throw const FormatException('Stored day result is unreadable.');
    }
    if (setupEvaluation != null) {
      return SetupEvaluation(
        day: day,
        currentAlgo: setupEvaluation!.currentAlgo,
        storedAlgo: setupEvaluation!.storedAlgo,
        computedAt: setupEvaluation!.computedAt,
        state: day == setupEvaluation!.day
            ? setupEvaluation!.state
            : SetupEvalState.missing,
      );
    }
    if (day != _day) {
      return SetupEvaluation(
        day: day,
        currentAlgo: kAlgoVersion,
        state: SetupEvalState.missing,
      );
    }
    final computed = _at(_day, '07:12');
    switch (scenario) {
      case SyntheticScenario.missing:
        return SetupEvaluation(
          day: day,
          currentAlgo: kAlgoVersion,
          state: SetupEvalState.missing,
        );
      case SyntheticScenario.processing:
        return SetupEvaluation(
          day: day,
          currentAlgo: kAlgoVersion,
          state: SetupEvalState.pending,
        );
      case SyntheticScenario.partial:
        return SetupEvaluation(
          day: day,
          currentAlgo: kAlgoVersion,
          storedAlgo: kAlgoVersion,
          state: SetupEvalState.partial,
        );
      case SyntheticScenario.calculationFailure:
        return SetupEvaluation(
          day: day,
          currentAlgo: kAlgoVersion,
          storedAlgo: kAlgoVersion,
          state: SetupEvalState.failed,
        );
      default:
        return SetupEvaluation(
          day: day,
          currentAlgo: kAlgoVersion,
          storedAlgo: kAlgoVersion,
          computedAt: computed,
          state: SetupEvalState.complete,
        );
    }
  }

  @override
  Future<Set<String>> sleepDays() async {
    final days = _sleepByDay.keys.toSet();
    if (scenario == SyntheticScenario.missing) days.remove(_day);
    return days;
  }

  @override
  Future<SleepDraft?> readDraft(String day) async => _drafts[day];

  @override
  Future<void> saveDraft(SleepDraft draft) async {
    if (scenario == SyntheticScenario.draftFailure) {
      throw StateError('synthetic draft failure');
    }
    _drafts[draft.day] = draft;
  }

  @override
  Future<void> discardDraft(String day) async {
    _drafts.remove(day);
  }

  @override
  Future<SleepCorrection> saveCorrection(SleepDraft draft) async {
    _drafts[draft.day] = draft;
    if (scenario == SyntheticScenario.saveFailure) {
      throw StateError('synthetic save failure');
    }
    final prev = _corrections[draft.day];
    final unchanged =
        prev != null &&
        prev.id == draft.id &&
        prev.onset == draft.onset &&
        prev.wake == draft.wake;
    if (unchanged) return prev;
    _applied.remove(draft.day);
    final revision = prev == null || prev.id != draft.id
        ? 1
        : prev.revision + 1;
    final saved = SleepCorrection(
      id: draft.id,
      day: draft.day,
      onset: draft.onset,
      wake: draft.wake,
      savedAt: _at(_day, '07:48'),
      revision: revision,
      state: CorrectionState.pending,
    );
    _corrections[draft.day] = saved;
    return saved;
  }

  @override
  Future<void> recalculate(SleepCorrection correction) async {
    await calculationBarrier;
    final stored = _corrections[correction.day] ?? correction;
    if (scenario == SyntheticScenario.calculationFailure) {
      _corrections[correction.day] = SleepCorrection(
        id: stored.id,
        day: stored.day,
        onset: stored.onset,
        wake: stored.wake,
        savedAt: stored.savedAt,
        revision: stored.revision,
        state: CorrectionState.failed,
        error: 'synthetic calculation failure',
      );
      throw StateError('synthetic calculation failure');
    }
    final source = scenario == SyntheticScenario.partial
        ? _partialSegments
        : _segments;
    _applied[stored.day] = _nightFrom(
      _clip(source, stored.onset, stored.wake),
      stored.onset,
      stored.wake,
    );
    _corrections[stored.day] = SleepCorrection(
      id: stored.id,
      day: stored.day,
      onset: stored.onset,
      wake: stored.wake,
      savedAt: stored.savedAt,
      revision: stored.revision,
      state: CorrectionState.complete,
    );
  }

  @override
  Future<void> restoreAutomatic(String day) async {
    _drafts.remove(day);
    _corrections.remove(day);
    _applied.remove(day);
  }

  @override
  Future<LabSnapshot> readLabs() async {
    if (beforeLabWrite != null) await beforeLabWrite!();
    if (failLabReads) throw StateError('synthetic lab read failure');
    final results = [..._labResults]
      ..sort((a, b) => b.takenOn.compareTo(a.takenOn));
    return LabSnapshot(
      results: List.unmodifiable(results),
      custom: List.unmodifiable(_labDefs.values),
    );
  }

  @override
  Future<void> saveLabDraw(
    LabDraw draw, {
    LabDraw? replacing,
    bool replaceExisting = false,
  }) async {
    if (failLabWrites) throw StateError('synthetic lab save failure');
    if (beforeLabWrite != null) await beforeLabWrite!();
    if (!draw.readable) {
      throw ArgumentError('Laborwert unvollständig oder ungültig.');
    }
    if (draw.reportLow != null &&
        draw.reportHigh != null &&
        draw.reportLow! > draw.reportHigh!) {
      throw ArgumentError('Untere Grenze liegt über der oberen.');
    }
    labWriteCount++;
    final dest = _labIndex(draw.marker, draw.takenOn);
    final origin = replacing == null
        ? -1
        : _labIndex(replacing.marker, replacing.takenOn);
    final same =
        origin >= 0 &&
        replacing!.marker == draw.marker &&
        replacing.takenOn == draw.takenOn;
    if (dest >= 0 && !same && !replaceExisting) {
      throw LabDrawCollision(draw.marker, draw.takenOn);
    }
    if (origin >= 0 && !same) {
      _labResults.removeAt(origin);
    }
    final updated = LabDraw(
      marker: draw.marker,
      takenOn: draw.takenOn,
      value: draw.value,
      unit: draw.unit,
      note: draw.note,
      reportLow: draw.reportLow,
      reportHigh: draw.reportHigh,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      extras: draw.extras,
    );
    final nowDest = _labIndex(draw.marker, draw.takenOn);
    if (nowDest >= 0) {
      _labResults[nowDest] = updated;
    } else {
      _labResults.add(updated);
    }
  }

  @override
  Future<void> deleteLabDraw(String marker, String takenOn) async {
    if (failLabWrites) throw StateError('synthetic lab delete failure');
    if (beforeLabWrite != null) await beforeLabWrite!();
    labWriteCount++;
    _labResults.removeWhere((r) => r.marker == marker && r.takenOn == takenOn);
  }

  @override
  Future<void> saveLabMarkerDef(LabMarkerDef def, {bool create = false}) async {
    if (failLabWrites) throw StateError('synthetic lab save failure');
    if (beforeLabWrite != null) await beforeLabWrite!();
    labWriteCount++;
    if (!def.key.startsWith('custom_') ||
        def.key == 'custom_' ||
        kLabMarkersByKey.containsKey(def.key) ||
        def.label.trim().isEmpty ||
        def.unit.trim().isEmpty) {
      throw ArgumentError('Marker unvollständig.');
    }
    if (create && _labDefs.containsKey(def.key)) {
      throw LabMarkerCollision(def.key);
    }
    final existing = _labDefs[def.key];
    _labDefs[def.key] = LabMarkerDef(
      key: def.key,
      label: def.label.trim(),
      unit: def.unit.trim(),
      category: def.category,
      decimals: def.decimals,
      refLow: def.refLow,
      refHigh: def.refHigh,
      createdAt: existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> deleteLabMarkerDef(String key) async {
    if (failLabWrites) throw StateError('synthetic lab delete failure');
    if (_labResults.any((r) => r.marker == key)) {
      throw StateError('lab marker still has results');
    }
    _labDefs.remove(key);
  }

  @override
  Future<GlucoseSnapshot> readGlucose({String? sourceKey, int? limit}) async {
    if (failGlucoseReads) throw StateError('synthetic glucose read failure');
    if (limit != null && limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'Must be at least 1.');
    }
    final settings = [
      for (final key in _glucoseExcluded)
        {'source_key': key, 'excluded': 1},
    ];
    return buildGlucoseSnapshot(
      rows: [
        for (final r in _glucoseReadings) _syntheticGlucoseRow(r),
      ],
      settings: settings,
      receipt: _syntheticGlucoseReceipt(),
      sourceKey: sourceKey,
      limit: limit,
    );
  }

  @override
  Future<GlucoseImportResult> importGlucose({DateTime? now}) async {
    final attemptedAt = now ?? DateTime(2026, 9, 15, 9, 41);
    late final HealthMeasurementImportOutcome outcome;
    if (failGlucoseImport) {
      final status = glucoseImportFailureStatus ??
          HealthMeasurementImportStatus.readFailed;
      _glucoseAttempt = GlucoseAttempt(
        status: status,
        attemptedAt: attemptedAt,
      );
      outcome = HealthMeasurementImportOutcome(
        status: status,
        attemptedAt: attemptedAt,
      );
    } else if (emptyGlucoseImport) {
      _glucoseAttempt = GlucoseAttempt(
        status: HealthMeasurementImportStatus.empty,
        attemptedAt: attemptedAt,
      );
      outcome = HealthMeasurementImportOutcome(
        status: HealthMeasurementImportStatus.empty,
        attemptedAt: attemptedAt,
      );
    } else {
      _glucoseAttempt = GlucoseAttempt(
        status: HealthMeasurementImportStatus.stored,
        attemptedAt: attemptedAt,
        storedCount: _glucoseReadings.length,
      );
      outcome = HealthMeasurementImportOutcome(
        status: HealthMeasurementImportStatus.stored,
        attemptedAt: attemptedAt,
        storedCount: _glucoseReadings.length,
      );
    }
    try {
      final snapshot = await readGlucose(limit: 1);
      return GlucoseImportResult(outcome: outcome, snapshot: snapshot);
    } catch (_) {
      return GlucoseImportResult(outcome: outcome, refreshFailed: true);
    }
  }

  @override
  Future<void> setGlucoseSourceIncluded(
    String sourceKey, {
    required bool included,
  }) async {
    if (failGlucoseExclusionWrite) {
      throw StateError('synthetic glucose exclusion write failure');
    }
    if (sourceKey.isEmpty) {
      throw ArgumentError.value(sourceKey, 'sourceKey', 'Required.');
    }
    if (included) {
      _glucoseExcluded.remove(sourceKey);
    } else {
      _glucoseExcluded.add(sourceKey);
    }
  }

  Map<String, dynamic> _syntheticGlucoseRow(GlucoseReading r) => {
        'uuid': r.uuid,
        'ts': r.measuredAt.millisecondsSinceEpoch ~/ 1000,
        'kind': 'glucose',
        'value': r.value,
        'unit': r.rawUnit,
        'source': r.source.sourceName,
        'source_id': r.source.sourceId,
        'source_key': r.source.key,
        'imported_at': r.importedAt == null
            ? null
            : r.importedAt!.millisecondsSinceEpoch ~/ 1000,
      };

  Map<String, dynamic>? _syntheticGlucoseReceipt() {
    if (_glucoseAttempt.status == HealthMeasurementImportStatus.notAttempted) {
      return null;
    }
    final at = _glucoseAttempt.attemptedAt;
    return {
      'outcome': _glucoseAttempt.status.name,
      'last_attempt_at': at == null ? null : at.millisecondsSinceEpoch ~/ 1000,
      'stored_count': _glucoseAttempt.storedCount,
      'written_count': _glucoseAttempt.writtenCount,
      'invalid_count': _glucoseAttempt.invalidCount,
      'ignored_count': _glucoseAttempt.ignoredCount,
    };
  }

  int _labIndex(String marker, String takenOn) =>
      _labResults.indexWhere((r) => r.marker == marker && r.takenOn == takenOn);

  @override
  Future<SleepGoalSnapshot> readSleepGoal(String day) async {
    if (failSleepGoalRead) {
      throw StateError('synthetic sleep goal read failure');
    }
    return SleepGoalSnapshot(
      period: _sleepGoalAsOf(day),
      weekendEstimate: weekendEstimate?.asOfDay == day ? weekendEstimate : null,
    );
  }

  @override
  Future<void> saveSleepGoal(String day, int minutes) async {
    await sleepGoalWriteBarrier;
    if (failSleepGoalWrite) {
      throw StateError('synthetic sleep goal write failure');
    }
    if (minutes < kSleepGoalMinMinutes || minutes > kSleepGoalMaxMinutes) {
      throw ArgumentError.value(
        minutes,
        'minutes',
        'Duration must be 1–1440 minutes.',
      );
    }
    _writeSleepGoal(day, minutes);
  }

  @override
  Future<void> clearSleepGoal(String day) async {
    await sleepGoalWriteBarrier;
    if (failSleepGoalWrite) {
      throw StateError('synthetic sleep goal write failure');
    }
    _writeSleepGoal(day, null);
  }

  @override
  Future<SleepPlanSnapshot> readSleepPlan(String day, {DateTime? now}) async {
    if (failSleepPlanRead) {
      throw StateError('synthetic sleep plan read failure');
    }
    if (!isLabCalendarDay(day)) {
      throw ArgumentError.value(day, 'day', 'Expected YYYY-MM-DD.');
    }
    return sleepPlanFromStoredCrossday(
      requestedDay: day,
      now: now ?? sleepPlanNow(),
      algoVersion: kAlgoVersion,
      artifact: sleepPlanArtifact,
      jobs: sleepPlanJobs,
      observations: sleepPlanObservations,
    );
  }

  SleepGoalPeriod? _sleepGoalAsOf(String day) {
    SleepGoalPeriod? best;
    for (final period in _sleepGoals.values) {
      if (period.validFromDay.compareTo(day) > 0) continue;
      if (best == null ||
          period.validFromDay.compareTo(best.validFromDay) > 0) {
        best = period;
      }
    }
    return best;
  }

  void _writeSleepGoal(String day, int? minutes) {
    final now = DateTime.now();
    final previous = _sleepGoals[day];
    _sleepGoals[day] = SleepGoalPeriod(
      validFromDay: day,
      minutes: minutes,
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
    );
  }

  @override
  Future<NutritionTargetSnapshot> readNutritionTargets(String day) async {
    if (failNutritionTargetRead) {
      throw StateError('synthetic nutrition target read failure');
    }
    if (!isLabCalendarDay(day)) {
      throw ArgumentError.value(day, 'day', 'Expected YYYY-MM-DD.');
    }
    final applied = _nutritionTargetAsOf(day);
    if (applied != null) {
      return NutritionTargetSnapshot(
        day: day,
        values: applied.values,
        origin: NutritionTargetOrigin.dated,
        effectiveDay: applied.validFromDay,
        revision: applied.validFromDay == day ? applied.revision : null,
      );
    }
    if (day != nutritionToday()) {
      return NutritionTargetSnapshot(day: day);
    }
    final legacy = NutritionTargetValues(
      energyKcal: decodeOptionalEnergy(
        legacyUndatedProfile?[kLegacyEnergyTargetKey],
      ),
      proteinG: decodeOptionalGrams(
        legacyUndatedProfile?[kLegacyProteinTargetKey],
      ),
    );
    if (!legacy.hasAny) {
      return NutritionTargetSnapshot(day: day);
    }
    return NutritionTargetSnapshot(
      day: day,
      values: legacy,
      origin: NutritionTargetOrigin.legacyUndated,
    );
  }

  @override
  Future<List<NutritionTargetChange>> listNutritionTargetChanges() async {
    if (failNutritionTargetRead) {
      throw StateError('synthetic nutrition target read failure');
    }
    final rows = _nutritionTargets.values.toList()
      ..sort((a, b) => a.validFromDay.compareTo(b.validFromDay));
    return List.unmodifiable(rows);
  }

  @override
  Future<NutritionTargetWriteResult> saveNutritionTargets(
    String day,
    NutritionTargetValues values, {
    int? expectedRevision,
  }) async {
    await nutritionTargetWriteBarrier;
    if (failNutritionTargetWrite) {
      throw StateError('synthetic nutrition target write failure');
    }
    if (!isLabCalendarDay(day)) {
      throw ArgumentError.value(day, 'day', 'Expected YYYY-MM-DD.');
    }
    requireNutritionTargetValues(values);
    return _putNutritionTargets(day, values, expectedRevision);
  }

  @override
  Future<NutritionTargetWriteResult> clearNutritionTargets(
    String day, {
    int? expectedRevision,
  }) async {
    await nutritionTargetWriteBarrier;
    if (failNutritionTargetWrite) {
      throw StateError('synthetic nutrition target write failure');
    }
    if (!isLabCalendarDay(day)) {
      throw ArgumentError.value(day, 'day', 'Expected YYYY-MM-DD.');
    }
    return _putNutritionTargets(
      day,
      const NutritionTargetValues(),
      expectedRevision,
    );
  }

  NutritionTargetChange? _nutritionTargetAsOf(String day) {
    NutritionTargetChange? best;
    for (final period in _nutritionTargets.values) {
      if (period.validFromDay.compareTo(day) > 0) continue;
      if (best == null ||
          period.validFromDay.compareTo(best.validFromDay) > 0) {
        best = period;
      }
    }
    return best;
  }

  NutritionTargetWriteResult _putNutritionTargets(
    String day,
    NutritionTargetValues values,
    int? expectedRevision,
  ) {
    final existing = _nutritionTargets[day];
    if (expectedRevision == null) {
      if (existing != null) {
        return NutritionTargetWriteResult.conflict(existing);
      }
    } else {
      if (existing == null) {
        return const NutritionTargetWriteResult.conflict();
      }
      if (existing.revision != expectedRevision) {
        return NutritionTargetWriteResult.conflict(existing);
      }
    }
    final now = DateTime.now();
    final row = NutritionTargetChange(
      validFromDay: day,
      values: values,
      revision: existing == null ? 1 : expectedRevision! + 1,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    _nutritionTargets[day] = row;
    return NutritionTargetWriteResult.saved(row);
  }

  static const nutritionGoalFixture = NutritionTargetValues(
    energyKcal: 2000,
    proteinG: 125,
    carbohydrateG: 240,
    fatG: 60,
  );

  static const nutritionGoalFutureFixture = NutritionTargetValues(
    energyKcal: 2100,
    proteinG: 131.25,
    carbohydrateG: 252,
    fatG: 63,
  );

  /// Gallery/native fixture. Not a production default.
  Future<void> seedNutritionGoals({bool withFuture = true}) async {
    nutritionToday = () => '2026-09-15';
    _nutritionTargets.clear();
    await saveNutritionTargets('2026-09-15', nutritionGoalFixture);
    if (withFuture) {
      await saveNutritionTargets('2026-09-20', nutritionGoalFutureFixture);
    }
  }

  NapDay _defaultNaps(String day) {
    if (scenario == SyntheticScenario.missing) {
      return NapDay(day: day, recordingTimezone: _timezone);
    }
    final start = _at(day, '14:10');
    final end = _at(day, '14:42');
    return NapDay(
      day: day,
      judged: true,
      sessions: [
        NapSession(
          start: start,
          end: end,
          source: NapSource.detected,
          durationMin: 32,
        ),
      ],
      totalMin: 32,
      recordingTimezone: _timezone,
    );
  }

  @override
  Future<NapDay> readNaps(String day) async {
    final stored = _naps[day] ?? _defaultNaps(day);
    final open =
        stored.job != null && stored.job!.state != CorrectionState.complete;
    return NapDay(
      day: stored.day,
      judged: stored.judged,
      sessions: stored.sessions,
      totalMin: stored.judged && !open ? stored.totalMin : null,
      rejected: List.unmodifiable(_napRejected[day] ?? const []),
      job: stored.job,
      recordingTimezone: stored.recordingTimezone ?? _timezone,
      note: stored.note,
    );
  }

  void seedNaps(NapDay day) => _naps[day.day] = day;

  NapDay _withJob(
    NapDay day,
    int revision,
    CorrectionState state, {
    String? error,
  }) => NapDay(
    day: day.day,
    judged: day.judged,
    sessions: day.sessions,
    totalMin:
        day.judged &&
            state == CorrectionState.complete &&
            day.sessions.every((session) => session.durationMin != null)
        ? day.sessions.fold<int>(
            0,
            (total, session) => total + session.durationMin!,
          )
        : null,
    rejected: day.rejected,
    job: NapJob(
      day: day.day,
      revision: revision,
      state: state,
      requestedAt: _at(_day, '07:48'),
      error: error,
    ),
    recordingTimezone: day.recordingTimezone ?? _timezone,
    note: day.note,
  );

  void _ensureNaps(String day) {
    _naps[day] ??= _defaultNaps(day);
  }

  Future<int> _commitSyntheticNap(String day, NapDay next) async {
    if (scenario == SyntheticScenario.saveFailure) {
      throw StateError('synthetic save failure');
    }
    _napRevision += 1;
    _naps[day] = _withJob(next, _napRevision, CorrectionState.pending);
    return _napRevision;
  }

  @override
  Future<int> addNap({
    required String day,
    required DateTime start,
    required DateTime end,
  }) async {
    _ensureNaps(day);
    final current = await readNaps(day);
    final session = NapSession(
      start: start,
      end: end,
      source: NapSource.manual,
      durationMin: end.difference(start).inMinutes,
    );
    return _commitSyntheticNap(
      day,
      NapDay(
        day: day,
        judged: current.judged,
        sessions: [...current.sessions, session]
          ..sort((a, b) => a.start.compareTo(b.start)),
        totalMin: current.totalMin,
        recordingTimezone: current.recordingTimezone,
        note: current.note,
      ),
    );
  }

  @override
  Future<int> editNap({
    required String day,
    required NapSession original,
    required DateTime start,
    required DateTime end,
  }) async {
    _ensureNaps(day);
    final current = await readNaps(day);
    final originStart =
        original.originStartTs ??
        (original.source == NapSource.detected ? original.startTs : null);
    final originEnd =
        original.originEndTs ??
        (original.source == NapSource.detected ? original.endTs : null);
    final edited = NapSession(
      start: start,
      end: end,
      source: NapSource.manual,
      durationMin: end.difference(start).inMinutes,
      originStartTs: originStart,
      originEndTs: originEnd,
    );
    var rejected = [
      for (final r in current.rejected)
        if (r.startTs != original.startTs && r.startTs != originStart) r,
    ];
    if (originStart != null &&
        originEnd != null &&
        edited.startTs != originStart) {
      rejected.add(
        NapSession(
          start: DateTime.fromMillisecondsSinceEpoch(originStart * 1000),
          end: DateTime.fromMillisecondsSinceEpoch(originEnd * 1000),
          source: NapSource.detected,
        ),
      );
    }
    _napRejected[day] = rejected;
    final sessions = [
      for (final n in current.sessions)
        if (n.startTs != original.startTs) n,
      edited,
    ]..sort((a, b) => a.start.compareTo(b.start));
    return _commitSyntheticNap(
      day,
      NapDay(
        day: day,
        judged: current.judged,
        sessions: sessions,
        recordingTimezone: current.recordingTimezone,
        note: current.note,
      ),
    );
  }

  @override
  Future<int> removeNap({
    required String day,
    required NapSession session,
  }) async {
    _ensureNaps(day);
    final current = await readNaps(day);
    if (session.fromDetected) {
      final originStart = session.originStartTs ?? session.startTs;
      final originEnd = session.originEndTs ?? session.endTs;
      _napRejected[day] = [
        for (final r in current.rejected)
          if (r.startTs != originStart) r,
        NapSession(
          start: DateTime.fromMillisecondsSinceEpoch(originStart * 1000),
          end: DateTime.fromMillisecondsSinceEpoch(originEnd * 1000),
          source: NapSource.detected,
        ),
      ];
    }
    return _commitSyntheticNap(
      day,
      NapDay(
        day: day,
        judged: current.judged,
        sessions: [
          for (final n in current.sessions)
            if (n.startTs != session.startTs) n,
        ],
        recordingTimezone: current.recordingTimezone,
        note: current.note,
      ),
    );
  }

  @override
  Future<int> restoreNap({
    required String day,
    required NapSession rejected,
  }) async {
    await restoreBarrier;
    _ensureNaps(day);
    final current = await readNaps(day);
    _napRejected[day] = [
      for (final n in _napRejected[day] ?? const <NapSession>[])
        if (n.startTs != rejected.startTs) n,
    ];
    return _commitSyntheticNap(
      day,
      NapDay(
        day: day,
        judged: current.judged,
        sessions: [...current.sessions, rejected]
          ..sort((a, b) => a.start.compareTo(b.start)),
        recordingTimezone: current.recordingTimezone,
        note: current.note,
      ),
    );
  }

  @override
  Future<void> recalculateNaps({
    required String day,
    required int revision,
  }) async {
    napRecalcCalls.add((day: day, revision: revision));
    await calculationBarrier;
    final current = _naps[day] ?? _defaultNaps(day);
    if (scenario == SyntheticScenario.calculationFailure) {
      _naps[day] = _withJob(
        current,
        revision,
        CorrectionState.failed,
        error: 'synthetic calculation failure',
      );
      throw StateError('synthetic calculation failure');
    }
    _naps[day] = _withJob(current, revision, CorrectionState.complete);
  }

  List<NightSegment> get _denseSegments {
    final output = <NightSegment>[];
    var start = _onset;
    var i = 0;
    const stages = [
      NightStage.light,
      NightStage.light,
      NightStage.rem,
      NightStage.light,
      NightStage.deep,
      NightStage.light,
      NightStage.awake,
      NightStage.light,
    ];
    while (start.isBefore(_wake)) {
      final minutes = i % 9 == 0 ? 1 : 2 + (i * 7 % 14);
      final candidate = start.add(Duration(minutes: minutes));
      final end = candidate.isAfter(_wake) ? _wake : candidate;
      output.add(
        NightSegment(start, end, i == 37 ? null : stages[i % stages.length]),
      );
      start = end;
      i++;
    }
    return output;
  }

  OpenBandDay _baseDay() {
    final recovery = Map<String, dynamic>.from(_summary['recovery'] as Map);
    final sleep =
        _applied[_day] ??
        (scenario == SyntheticScenario.dense
            ? _nightFrom(_denseSegments, _onset, _wake)
            : scenario == SyntheticScenario.partial
            ? _nightFrom(_partialSegments, _onset, _wake)
            : _nightFrom(_segments, _onset, _wake));
    return OpenBandDay(
      day: _day,
      sleep: sleep,
      recovery: DayMetric((recovery['score'] as num).toDouble()),
      strain: DayMetric((_summary['day_strain'] as num).toDouble()),
      hrv: DayMetric((recovery['hrv_ms'] as num).toDouble()),
      restingHr: DayMetric((recovery['rhr_bpm'] as num).toDouble()),
      respiration: DayMetric((recovery['resp_per_min'] as num).toDouble()),
      steps: DayMetric((_summary['steps'] as num).toDouble()),
      calculatedAt: _baseBand.latestStoredAt,
      stepIntervals: [
        if (activity?['steps'] case final Map steps)
          for (var i = 0; i < (steps['counts'] as List).length; i++)
            StepInterval(
              _at(_day, steps['hour_start_local'][i] as String),
              i == (steps['counts'] as List).length - 1
                  ? _at(_day, steps['last_interval_end'] as String)
                  : _at(_day, steps['hour_start_local'][i + 1] as String),
              (steps['counts'][i] as num).toDouble(),
            ),
      ],
      intake: DayIntake(
        kcal: ((_summary['nutrition'] as Map)['known_kcal'] as num).toDouble(),
        waterMl: ((_summary['nutrition'] as Map)['water_ml'] as num).toDouble(),
        kcalIsFloor:
            ((_summary['nutrition'] as Map)['incomplete_entries'] as num) > 0,
      ),
      correction: _corrections[_day],
      synthetic: true,
    );
  }

  OpenBandDay _overlay(OpenBandDay day) {
    switch (scenario) {
      case SyntheticScenario.missing:
        return OpenBandDay(
          day: day.day,
          correction: day.correction,
          synthetic: true,
        );
      case SyntheticScenario.processing:
        DayMetric pending(DayMetric m) => DayMetric(
          m.value,
          readiness: MetricReadiness.processing,
          baseline: m.baseline,
          reason: m.reason,
          nightScalar: m.nightScalar,
          unit: m.unit,
        );
        return OpenBandDay(
          day: day.day,
          sleep: SleepNight(
            onset: day.sleep.onset,
            wake: day.sleep.wake,
            recordingTimezone: day.sleep.recordingTimezone,
            duration: pending(day.sleep.duration),
            bedMinutes: day.sleep.bedMinutes,
            awakeMinutes: day.sleep.awakeMinutes,
            remMinutes: day.sleep.remMinutes,
            lightMinutes: day.sleep.lightMinutes,
            deepMinutes: day.sleep.deepMinutes,
            unobservedMinutes: day.sleep.unobservedMinutes,
            segments: day.sleep.segments,
            source: day.sleep.source,
            history: day.sleep.history,
          ),
          recovery: pending(day.recovery),
          strain: pending(day.strain),
          hrv: pending(day.hrv),
          restingHr: pending(day.restingHr),
          respiration: pending(day.respiration),
          skinTemperature: pending(day.skinTemperature),
          steps: pending(day.steps),
          stepIntervals: day.stepIntervals,
          calculatedAt: day.calculatedAt,
          intake: day.intake,
          correction: day.correction,
          synthetic: true,
        );
      default:
        return day;
    }
  }

  SleepNight _nightFrom(
    List<NightSegment> segments,
    DateTime onset,
    DateTime wake,
  ) {
    var awake = 0.0, rem = 0.0, light = 0.0, deep = 0.0, unobserved = 0.0;
    for (final s in segments) {
      final minutes = s.end.difference(s.start).inMinutes.toDouble();
      switch (s.stage) {
        case NightStage.awake:
          awake += minutes;
        case NightStage.rem:
          rem += minutes;
        case NightStage.light:
          light += minutes;
        case NightStage.deep:
          deep += minutes;
        case null:
          unobserved += minutes;
      }
    }
    final sleep = rem + light + deep;
    final partial = unobserved > 0;
    return SleepNight(
      onset: onset,
      wake: wake,
      recordingTimezone: _timezone,
      duration: DayMetric(
        sleep,
        readiness: partial
            ? MetricReadiness.partial
            : MetricReadiness.available,
      ),
      bedMinutes: wake.difference(onset).inMinutes.toDouble(),
      awakeMinutes: awake,
      remMinutes: rem,
      lightMinutes: light,
      deepMinutes: deep,
      unobservedMinutes: partial ? unobserved : null,
      segments: List.unmodifiable(segments),
      history: _history,
    );
  }

  NightSegment _segment(Map<String, dynamic> raw) {
    return NightSegment(
      _onset.add(Duration(minutes: (raw['start_min'] as num).toInt())),
      _onset.add(Duration(minutes: (raw['end_min'] as num).toInt())),
      _stage(raw['stage'] as String?),
    );
  }

  static NightStage? _stage(String? name) => switch (name) {
    'awake' => NightStage.awake,
    'rem' => NightStage.rem,
    'light' => NightStage.light,
    'deep' => NightStage.deep,
    _ => null,
  };

  static List<NightSegment> _clip(
    List<NightSegment> segments,
    DateTime start,
    DateTime end,
  ) {
    final out = <NightSegment>[];
    for (final s in segments) {
      final a = s.start.isAfter(start) ? s.start : start;
      final b = s.end.isBefore(end) ? s.end : end;
      if (!b.isAfter(a)) continue;
      out.add(NightSegment(a, b, s.stage));
    }
    return out;
  }

  static List<NightSegment> _withGap(
    List<NightSegment> segments,
    DateTime gapStart,
    DateTime gapEnd,
  ) {
    final out = <NightSegment>[];
    var gapEmitted = false;
    for (final s in segments) {
      if (!s.end.isAfter(gapStart) || !s.start.isBefore(gapEnd)) {
        out.add(s);
        continue;
      }
      if (s.start.isBefore(gapStart)) {
        out.add(NightSegment(s.start, gapStart, s.stage));
      }
      if (!gapEmitted) {
        out.add(NightSegment(gapStart, gapEnd, null));
        gapEmitted = true;
      }
      if (s.end.isAfter(gapEnd)) {
        out.add(NightSegment(gapEnd, s.end, s.stage));
      }
    }
    if (!gapEmitted) out.add(NightSegment(gapStart, gapEnd, null));
    return out;
  }

  void _indexBaseline(List<double> values, Map<String, double> into) {
    for (var i = 0; i < values.length; i++) {
      into[_shift(_day, i - values.length)] = values[i];
    }
  }

  static List<double> _nums(dynamic raw) => [
    for (final n in raw as List) (n as num).toDouble(),
  ];

  static DateTime _at(String day, String hm) {
    final p = day.split('-').map(int.parse).toList();
    final t = hm.split(':').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2], t[0], t[1]);
  }

  static String _previousDay(String day) => _shift(day, -1);

  static String _shift(String day, int days) {
    final p = day.split('-').map(int.parse).toList();
    return dayLabelOf(DateTime(p[0], p[1], p[2]).add(Duration(days: days)));
  }

  void _seedFixtureMedication() {
    const prior = '2026-09-14';
    final knownAt = DateTime(2026, 9, 14, 7);
    _putSynthPlan(
      MedicationPlanDraft(
        create: true,
        key: medicationFixturePlanAKey,
        name: 'Präparat A',
        doseValue: 1,
        doseUnit: 'Tablette',
        schedule: const [
          MedicationScheduleSlot(minuteOfDay: 8 * 60),
        ],
      ),
      now: knownAt,
    );
    _putSynthPlan(
      MedicationPlanDraft(
        create: true,
        key: medicationFixturePlanBKey,
        name: 'Präparat B',
        doseValue: 1,
        doseUnit: 'Kapsel',
        schedule: const [
          MedicationScheduleSlot(minuteOfDay: 20 * 60),
        ],
      ),
      now: knownAt,
    );
    _medDoses.add(
      MedicationStoredDose(
        medKey: medicationFixturePlanAKey,
        date: prior,
        slotMin: 8 * 60,
        takenTsSeconds: DateTime(2026, 9, 14, 8, 4).millisecondsSinceEpoch ~/ 1000,
        doseValue: 1,
        doseUnit: 'Tablette',
        label: 'Präparat A',
        kind: MedicationKind.medication,
        takenUtcOffsetMinutes: DateTime(2026, 9, 14, 8, 4).timeZoneOffset.inMinutes,
      ),
    );
    _medDoses.add(
      const MedicationStoredDose(
        medKey: medicationFixturePlanAKey,
        date: '2026-09-13',
        slotMin: 8 * 60,
      ),
    );
  }

  void _requireMedicationReadable() {
    if (failMedicationRead) {
      throw StateError('synthetic medication read failure');
    }
    if (corruptMedicationHeads) {
      throw const FormatException('Stored medication plan is unreadable.');
    }
  }

  void _requireMedicationWritable() {
    if (failMedicationWrite) {
      throw StateError('synthetic medication write failure');
    }
  }

  Map<String, String> get _medCurrentNames => {
        for (final p in _medPlans.values) p.key: p.name,
      };

  MedicationPlan _putSynthPlan(MedicationPlanDraft draft, {required DateTime now}) {
    requireMedicationPlanDraft(draft);
    final name = draft.name.trim();
    final existing = draft.key == null ? null : _medPlans[draft.key];
    if (!draft.create && existing == null) {
      throw StateError('No medication plan "${draft.key}" to update.');
    }
    if (draft.create && existing != null) {
      throw StateError('Medication plan "${draft.key}" already exists.');
    }
    final key = draft.create
        ? (draft.key?.trim().isNotEmpty == true
            ? draft.key!.trim()
            : newMedicationPlanId())
        : draft.key!.trim();
    final ts = now.millisecondsSinceEpoch;
    final id = ++_medRevisionSeq;
    final rev = MedicationPlanRevision(
      id: id,
      medKey: key,
      effectiveTs: ts,
      effectiveDate: dayLabelOf(now),
      effectiveMin: now.hour * 60 + now.minute,
      label: name,
      doseValue: draft.doseValue,
      doseUnit: draft.doseUnit?.trim().isEmpty == true ? null : draft.doseUnit?.trim(),
      kind: draft.kind,
      note: draft.note,
      schedule: draft.schedule,
      active: draft.active,
      origin: MedicationPlanOrigin.user,
    );
    (_medRevisions[key] ??= []).add(rev);
    final plan = MedicationPlan(
      key: key,
      name: name,
      doseValue: draft.doseValue,
      doseUnit: rev.doseUnit,
      kind: draft.kind,
      note: draft.note,
      schedule: draft.schedule,
      active: draft.active,
      createdAtMs: existing?.createdAtMs ?? now.millisecondsSinceEpoch,
      revisionId: id,
      effectiveTs: ts,
      effectiveDate: rev.effectiveDate,
      effectiveMin: rev.effectiveMin,
      origin: rev.origin,
    );
    _medPlans[key] = plan;
    return plan;
  }

  Future<MedicationMutationResult> _synthWriteResult({
    MedicationPlan? plan,
    MedicationDayEntry? entry,
  }) async {
    try {
      await refreshMedicationReminders();
      return MedicationMutationResult.saved(plan: plan, entry: entry);
    } catch (_) {
      return MedicationMutationResult.savedRemindersFailed(
        plan: plan,
        entry: entry,
      );
    }
  }

  MedicationDayEntry? _entryOnDay(MedicationDay day, String key, int slotMin) {
    for (final e in day.entries) {
      if (e.key == key && e.slotMin == slotMin) return e;
    }
    return null;
  }

  @override
  Future<MedicationDay> readMedicationDay(String day, {DateTime? now}) async {
    _requireMedicationReadable();
    if (!isMedicationCalendarDay(day)) {
      throw ArgumentError.value(day, 'day', 'Invalid calendar day.');
    }
    return _synthDay(day, now ?? DateTime.now());
  }

  @override
  Future<List<MedicationPlan>> readMedicationPlans({
    bool activeOnly = true,
  }) async {
    _requireMedicationReadable();
    final plans = _medPlans.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (activeOnly) {
      return [for (final p in plans) if (p.active) p];
    }
    return plans;
  }

  @override
  Future<MedicationHistory> readMedicationHistory(
    String fromDay,
    String toDay, {
    DateTime? now,
  }) async {
    _requireMedicationReadable();
    final at = now ?? DateTime.now();
    final entries = <MedicationDayEntry>[];
    var unreadable = 0;
    for (final day in medicationCivilDays(fromDay, toDay)) {
      final resolved = resolveMedicationDay(
        date: day,
        now: at,
        revisionsByKey: _medRevisions,
        doses: _medDoses,
        currentNames: _medCurrentNames,
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

  @override
  Future<MedicationMutationResult> saveMedicationPlan(
    MedicationPlanDraft draft, {
    DateTime? now,
  }) async {
    _requireMedicationWritable();
    final plan = _putSynthPlan(draft, now: now ?? DateTime.now());
    return _synthWriteResult(plan: plan);
  }

  @override
  Future<MedicationMutationResult> endMedicationPlan(
    String key, {
    DateTime? now,
  }) async {
    return _synthSetActive(key, active: false, now: now);
  }

  @override
  Future<MedicationMutationResult> restartMedicationPlan(
    String key, {
    DateTime? now,
  }) async {
    return _synthSetActive(key, active: true, now: now);
  }

  MedicationDay _synthDay(String day, DateTime now) {
    final resolved = resolveMedicationDay(
      date: day,
      now: now,
      revisionsByKey: _medRevisions,
      doses: _medDoses,
      currentNames: _medCurrentNames,
    );
    return MedicationDay(
      day: day,
      entries: resolved.entries,
      unreadableCount: resolved.unreadableCount,
    );
  }

  Future<MedicationMutationResult> _synthSetActive(
    String key, {
    required bool active,
    DateTime? now,
  }) async {
    _requireMedicationWritable();
    final current = _medPlans[key.trim()];
    if (current == null) {
      throw StateError('No medication plan "$key" to update.');
    }
    if (current.scheduleUnreadableCount > 0) {
      throw FormatException(
        'Stored medication plan "${current.key}" has an unreadable schedule.',
      );
    }
    final plan = _putSynthPlan(
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
      now: now ?? DateTime.now(),
    );
    return _synthWriteResult(plan: plan);
  }

  @override
  Future<MedicationMutationResult> saveMedicationEntry(
    MedicationEntryDraft draft, {
    DateTime? now,
  }) async {
    _requireMedicationWritable();
    final at = now ?? DateTime.now();
    requireMedicationEntryDraft(draft, now: at);
    final key = draft.key.trim();
    final previous = List<MedicationStoredDose>.from(_medDoses);
    final MedicationDayEntry? entry;
    try {
      if (draft.answer == MedicationEntryAnswer.clear) {
        _medDoses.removeWhere(
          (d) =>
              d.medKey == key && d.date == draft.date && d.slotMin == draft.slotMin,
        );
        entry = _entryOnDay(_synthDay(draft.date, at), key, draft.slotMin);
      } else {
        final idx = _medDoses.indexWhere(
          (d) =>
              d.medKey == key && d.date == draft.date && d.slotMin == draft.slotMin,
        );
        final covering = coveringMedicationRevision(
          revisions: _medRevisions[key] ?? const [],
          date: draft.date,
          slotMin: draft.slotMin,
        );
        final takenAt = draft.answer == MedicationEntryAnswer.taken
            ? (draft.takenAt ?? at)
            : null;
        final takenSeconds =
            takenAt == null ? null : takenAt.millisecondsSinceEpoch ~/ 1000;
        if (idx >= 0) {
          final prev = _medDoses[idx];
          final offset = prev.takenTsSeconds == takenSeconds
              ? prev.takenUtcOffsetMinutes
              : takenAt?.timeZoneOffset.inMinutes;
          _medDoses[idx] = MedicationStoredDose(
            medKey: prev.medKey,
            date: prev.date,
            slotMin: prev.slotMin,
            takenTsSeconds: takenSeconds,
            skipped: draft.answer == MedicationEntryAnswer.skipped,
            doseValue: prev.doseValue,
            doseUnit: prev.doseUnit,
            label: prev.label,
            kind: prev.kind,
            note: draft.note ?? prev.note,
            takenUtcOffsetMinutes: offset,
          );
        } else {
          _medDoses.add(
            MedicationStoredDose(
              medKey: key,
              date: draft.date,
              slotMin: draft.slotMin,
              takenTsSeconds: takenSeconds,
              skipped: draft.answer == MedicationEntryAnswer.skipped,
              doseValue: covering?.doseValue,
              doseUnit: covering?.doseUnit,
              label: covering?.label,
              kind: covering?.kind,
              note: draft.note ?? '',
              takenUtcOffsetMinutes: takenAt?.timeZoneOffset.inMinutes,
            ),
          );
        }
        entry = _entryOnDay(_synthDay(draft.date, at), key, draft.slotMin);
      }
    } on Object {
      _medDoses
        ..clear()
        ..addAll(previous);
      rethrow;
    }
    return _synthWriteResult(entry: entry);
  }

  @override
  Future<void> refreshMedicationReminders() async {
    if (failMedicationReminders) {
      throw StateError('synthetic medication reminder refresh failure');
    }
  }

  void seedCycleStart(CycleStart start) => _cycleStarts[start.date] = start;

  void seedCycleObservation(CycleObservation observation) =>
      _cycleObservations[observation.date] = observation;

  void seedUnreadableCycleStart(Map<Object?, Object?> row) =>
      _cycleUnreadableStarts.add(row);

  void seedUnreadableCycleObservation(Map<Object?, Object?> row) =>
      _cycleUnreadableObservations.add(row);

  void seedCycleNightSource(CycleNightSourceRow row) =>
      _cycleNights[row.day] = row;

  void clearCycleNightSources() => _cycleNights.clear();

  /// Opt-in Paper median fixture. Default cycle seeding stays 4 starts and
  /// one selected-cycle night run so existing cycle tests do not change.
  void seedCycleMedianFixture({
    bool includeRhr = true,
    bool includeHrv = true,
  }) {
    _cycleStarts
      ..clear()
      ..addAll({
        for (final date in cycleMedianFixtureStarts)
          date: CycleStart(date: date, kind: kCycleStartKind),
      });
    _cycleUnreadableStarts.clear();
    _cycleNights.clear();
    for (final date in cycleMedianFixtureStarts) {
      seedCyclePaperNightsFrom(
        date,
        includeRhr: includeRhr,
        includeHrv: includeHrv,
      );
    }
  }

  void seedCyclePaperNightsFrom(
    String start, {
    bool includeRhr = true,
    bool includeHrv = true,
    num rhrAdd = 0,
    num hrvAdd = 0,
  }) {
    final last = cycleAddDays(start, kCyclePaperRhr.length - 1);
    final days = cycleCivilDaysInclusive(start, last);
    for (var i = 0; i < days.length; i++) {
      final rhrRaw = includeRhr ? kCyclePaperRhr[i] : null;
      final hrvRaw = includeHrv ? kCyclePaperHrv[i] : null;
      final rhr = rhrRaw == null ? null : rhrRaw + rhrAdd;
      final hrv = hrvRaw == null ? null : hrvRaw + hrvAdd;
      if (rhr == null && hrv == null) continue;
      final day = days[i];
      _cycleNights[day] = CycleNightSourceRow(
        day: day,
        algoVersion: kAlgoVersion,
        payload: cycleNightSourcePayload(
          rhr: rhr,
          hrv: hrv,
          onsetMs: cycleNightOnsetMs(day),
          offsetMs: cycleNightOffsetMs(day),
        ),
      );
    }
  }

  /// Opt-in Paper comparison fixture. Default cycle seeding stays 4 starts
  /// (including 2026-06-01) and one selected-cycle night run.
  void seedCycleComparisonFixture({
    bool includeRhr = true,
    bool includeHrv = true,
  }) {
    _cycleStarts
      ..clear()
      ..addAll({
        for (final date in cycleComparisonFixtureStarts)
          date: CycleStart(date: date, kind: kCycleStartKind),
      });
    _cycleUnreadableStarts.clear();
    _cycleNights.clear();
    final current = cycleComparisonFixtureStarts.last;
    for (final date in cycleComparisonFixtureStarts) {
      final last = date == current;
      seedCyclePaperNightsFrom(
        date,
        includeRhr: includeRhr,
        includeHrv: includeHrv,
        rhrAdd: last ? cycleComparisonFixtureCurrentRhrAdd : 0,
        hrvAdd: last ? cycleComparisonFixtureCurrentHrvAdd : 0,
      );
    }
    for (var i = 0; i < cycleComparisonFixtureStarts.length - 1; i++) {
      final start = cycleComparisonFixtureStarts[i];
      if (includeRhr) {
        _overrideCycleNightMetric(
          cycleAddDays(start, 22),
          rhr: cycleComparisonFixtureSameDayRhr[i],
        );
      }
      if (includeHrv) {
        _overrideCycleNightMetric(
          cycleAddDays(start, 21),
          hrv: cycleComparisonFixtureSameDayHrv[i],
        );
      }
    }
  }

  void _overrideCycleNightMetric(
    String day, {
    double? rhr,
    double? hrv,
  }) {
    final existing = _cycleNights[day];
    final parsed = existing == null
        ? null
        : parseCycleNightSource(existing, algoVersion: kAlgoVersion);
    _cycleNights[day] = CycleNightSourceRow(
      day: day,
      algoVersion: kAlgoVersion,
      payload: cycleNightSourcePayload(
        rhr: rhr ?? parsed?.rhr?.value,
        hrv: hrv ?? parsed?.hrv?.value,
        onsetMs: cycleNightOnsetMs(day),
        offsetMs: cycleNightOffsetMs(day),
      ),
    );
  }

  void clearCycleLogs() {
    _cycleStarts.clear();
    _cycleObservations.clear();
    _cycleUnreadableStarts.clear();
    _cycleUnreadableObservations.clear();
  }

  void _seedFixtureCycle() {
    for (final date in cycleFixtureStarts) {
      _cycleStarts[date] = CycleStart(date: date, kind: kCycleStartKind);
    }
  }

  void _seedFixtureCycleNights() {
    seedCyclePaperNightsFrom(kCyclePaperStartDay);
  }

  CycleLogParse _synthCycleLog(String day) => parseCycleLog(
        startRows: [
          for (final s in _cycleStarts.values)
            {'date': s.date, 'kind': s.kind, 'note': s.note},
          ..._cycleUnreadableStarts,
        ],
        observationRows: [
          for (final o in _cycleObservations.values)
            {
              'date': o.date,
              'symptoms_json': jsonEncode(o.tags),
              'note': o.note,
              'updated_at': o.updatedAt,
            },
          ..._cycleUnreadableObservations,
        ],
        asOf: day,
      );

  void _requireCycleReadable() {
    if (failCycleRead) throw StateError('synthetic cycle read failure');
  }

  void _requireCycleWritable() {
    if (failCycleWrite) throw StateError('synthetic cycle write failure');
  }

  @override
  Future<CycleSettings> readCycleSettings() async {
    _requireCycleReadable();
    return cycleSettings;
  }

  @override
  Future<CycleWriteResult> saveCycleSettings(CycleSettings settings) async {
    _requireCycleWritable();
    cycleSettings = settings;
    return _cycleWriteResult(settings: settings);
  }

  @override
  Future<CycleSnapshot> readCycle(String day, {DateTime? now}) async {
    _requireCycleReadable();
    requireCycleCalendarDay(day);
    final parsed = _synthCycleLog(day);
    return buildCycleSnapshot(
      day: day,
      settings: cycleSettings,
      starts: parsed.starts,
      observations: parsed.observations,
      unreadableCount: parsed.unreadableCount,
      unreadableStarts: parsed.unreadableStarts,
    );
  }

  @override
  Future<CycleMeasurementsSnapshot> readCycleMeasurements(
    String asOfDay, {
    String? cycleStartDay,
  }) async {
    if (failCycleMeasurementsRead || failCycleRead) {
      throw StateError('synthetic cycle measurements read failure');
    }
    requireCycleCalendarDay(asOfDay, 'asOfDay');
    if (cycleStartDay != null) {
      requireCycleCalendarDay(cycleStartDay, 'cycleStartDay');
    }
    return buildCycleMeasurementsSnapshot(
      asOfDay: asOfDay,
      settings: cycleSettings,
      log: _synthCycleLog(asOfDay),
      cycleStartDay: cycleStartDay,
      algoVersion: kAlgoVersion,
      rows: _cycleNights.values.toList(),
    );
  }

  @override
  Future<CycleMediansSnapshot> readCycleMedians(
    String anchorEnd, {
    int pageOffset = 0,
    DateTime? now,
  }) async {
    if (failCycleMediansRead || failCycleRead) {
      throw StateError('synthetic cycle medians read failure');
    }
    requireCycleCalendarDay(anchorEnd, 'anchorEnd');
    final at = now ?? DateTime.now();
    if (cycleDateIsAfterToday(anchorEnd, at)) {
      throw ArgumentError.value(
        anchorEnd,
        'anchorEnd',
        'Cycle median anchor cannot be after local today.',
      );
    }
    final window = cycleMedianWindow(
      anchorEnd: anchorEnd,
      pageOffset: pageOffset,
    );
    return buildCycleMediansSnapshot(
      settings: cycleSettings,
      log: _synthCycleLog(window.endDay),
      algoVersion: kAlgoVersion,
      window: window,
      rows: _cycleNights.values.toList(),
    );
  }

  @override
  Future<CycleComparisonSnapshot> readCycleComparison(
    String anchorEnd, {
    int pageOffset = 0,
    DateTime? now,
  }) async {
    if (failCycleComparisonRead || failCycleRead) {
      throw StateError('synthetic cycle comparison read failure');
    }
    requireCycleCalendarDay(anchorEnd, 'anchorEnd');
    final at = now ?? DateTime.now();
    if (cycleDateIsAfterToday(anchorEnd, at)) {
      throw ArgumentError.value(
        anchorEnd,
        'anchorEnd',
        'Cycle median anchor cannot be after local today.',
      );
    }
    final window = cycleMedianWindow(
      anchorEnd: anchorEnd,
      pageOffset: pageOffset,
    );
    return buildCycleComparisonSnapshot(
      settings: cycleSettings,
      log: _synthCycleLog(window.endDay),
      algoVersion: kAlgoVersion,
      window: window,
      rows: _cycleNights.values.toList(),
    );
  }

  @override
  Future<CycleWriteResult> saveCycleStart(
    CycleStart desired, {
    CycleStart? expected,
    DateTime? now,
  }) async {
    _requireCycleWritable();
    if (desired.kind.isEmpty) {
      throw ArgumentError.value(desired.kind, 'kind', 'Cycle kind is required.');
    }
    final at = now ?? DateTime.now();
    requireCycleWriteDay(desired.date, at);
    if (expected != null) {
      requireCycleCalendarDay(expected.date, 'expected.date');
    }
    final atDesired = _cycleStarts[desired.date];
    if (expected == null) {
      if (atDesired == desired) {
        return _cycleWriteResult(start: atDesired);
      }
      if (atDesired != null) {
        return CycleWriteResult.conflict(currentStart: atDesired);
      }
      _cycleStarts[desired.date] = desired;
      return _cycleWriteResult(start: desired);
    }
    if (expected.date == desired.date) {
      if (atDesired == desired) {
        return _cycleWriteResult(start: atDesired);
      }
      if (atDesired != expected) {
        return CycleWriteResult.conflict(currentStart: atDesired);
      }
      _cycleStarts[desired.date] = desired;
      return _cycleWriteResult(start: desired);
    }
    final atSource = _cycleStarts[expected.date];
    if (atDesired == desired && atSource == null) {
      return _cycleWriteResult(start: atDesired);
    }
    if (atSource != expected) {
      return CycleWriteResult.conflict(currentStart: atSource);
    }
    if (atDesired != null) {
      return CycleWriteResult.conflict(currentStart: atDesired);
    }
    final previous = Map<String, CycleStart>.from(_cycleStarts);
    try {
      _cycleStarts.remove(expected.date);
      _cycleStarts[desired.date] = desired;
      return _cycleWriteResult(start: desired);
    } on Object {
      _cycleStarts
        ..clear()
        ..addAll(previous);
      rethrow;
    }
  }

  @override
  Future<CycleWriteResult> removeCycleStart(CycleStart expected) async {
    _requireCycleWritable();
    requireCycleCalendarDay(expected.date, 'expected.date');
    final current = _cycleStarts[expected.date];
    if (current == null) {
      return _cycleWriteResult(start: expected);
    }
    if (current != expected) {
      return CycleWriteResult.conflict(currentStart: current);
    }
    _cycleStarts.remove(expected.date);
    return _cycleWriteResult(start: expected);
  }

  @override
  Future<CycleWriteResult> restoreCycleStart(
    CycleStart removed, {
    DateTime? now,
  }) async {
    _requireCycleWritable();
    if (removed.kind.isEmpty) {
      throw ArgumentError.value(removed.kind, 'kind', 'Cycle kind is required.');
    }
    final at = now ?? DateTime.now();
    requireCycleWriteDay(removed.date, at);
    final current = _cycleStarts[removed.date];
    if (current == removed) {
      return _cycleWriteResult(start: current);
    }
    if (current != null) {
      return CycleWriteResult.conflict(currentStart: current);
    }
    _cycleStarts[removed.date] = removed;
    return _cycleWriteResult(start: removed);
  }

  @override
  Future<CycleWriteResult> saveCycleObservation(
    CycleObservation desired, {
    CycleObservation? expected,
    DateTime? now,
  }) async {
    _requireCycleWritable();
    final at = now ?? DateTime.now();
    requireCycleWriteDay(desired.date, at);
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
    final current = _cycleObservations[desired.date];
    if (desired.isClear) {
      if (current == null) return _cycleWriteResult();
      if (cycleObservationsContentEqual(current, desired)) {
        _cycleObservations.remove(desired.date);
        return _cycleWriteResult();
      }
      if (expected != null && current != expected) {
        return CycleWriteResult.conflict(currentObservation: current);
      }
      if (expected == null) {
        return CycleWriteResult.conflict(currentObservation: current);
      }
      _cycleObservations.remove(desired.date);
      return _cycleWriteResult();
    }
    if (cycleObservationsContentEqual(current, desired)) {
      return _cycleWriteResult(observation: current);
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
      tags: List<String>.unmodifiable(desired.tags),
      note: desired.note,
      updatedAt: at.millisecondsSinceEpoch,
    );
    _cycleObservations[desired.date] = saved;
    return _cycleWriteResult(observation: saved);
  }

  @override
  Future<void> refreshCycleContext() async {
    cycleContextRefreshCalls++;
    if (failCycleContextRefresh) {
      throw StateError('synthetic cycle context refresh failure');
    }
  }

  Future<CycleWriteResult> _cycleWriteResult({
    CycleStart? start,
    CycleObservation? observation,
    CycleSettings? settings,
  }) async {
    try {
      await refreshCycleContext();
      return CycleWriteResult.saved(
        start: start,
        observation: observation,
        settings: settings,
      );
    } catch (_) {
      return CycleWriteResult.savedContextRefreshFailed(
        start: start,
        observation: observation,
        settings: settings,
      );
    }
  }

  @override
  Future<Vo2List> readVo2Entries() async {
    if (failVo2Read) throw StateError('synthetic vo2 read failure');
    return _vo2List();
  }

  @override
  Future<Vo2Detail> readVo2Entry(String id) async {
    if (failVo2Read) throw StateError('synthetic vo2 read failure');
    return _vo2Detail(id);
  }

  @override
  Future<Vo2WriteResult> createVo2Entry({
    required String id,
    required String measuredOn,
    required double valueMlKgMin,
    String? declaredMethod,
  }) async {
    if (failVo2Write) throw StateError('synthetic vo2 save failure');
    return _vo2Write(
      op: _Vo2Op.create,
      id: id,
      expectedRevision: 0,
      measuredOn: measuredOn,
      valueMlKgMin: valueMlKgMin,
      declaredMethod: declaredMethod,
    );
  }

  @override
  Future<Vo2WriteResult> editVo2Entry({
    required String id,
    required int expectedRevision,
    required String measuredOn,
    required double valueMlKgMin,
    String? declaredMethod,
  }) async {
    if (failVo2Write) throw StateError('synthetic vo2 save failure');
    return _vo2Write(
      op: _Vo2Op.edit,
      id: id,
      expectedRevision: expectedRevision,
      measuredOn: measuredOn,
      valueMlKgMin: valueMlKgMin,
      declaredMethod: declaredMethod,
    );
  }

  @override
  Future<Vo2WriteResult> removeVo2Entry({
    required String id,
    required int expectedRevision,
  }) async {
    if (failVo2Write) throw StateError('synthetic vo2 save failure');
    return _vo2Write(
      op: _Vo2Op.delete,
      id: id,
      expectedRevision: expectedRevision,
    );
  }

  @override
  Future<Vo2WriteResult> restoreVo2Entry({
    required String id,
    required int expectedRevision,
  }) async {
    if (failVo2Write) throw StateError('synthetic vo2 save failure');
    return _vo2Write(
      op: _Vo2Op.restore,
      id: id,
      expectedRevision: expectedRevision,
    );
  }

  Vo2List _vo2List() {
    final ids = _vo2.keys.toList()..sort();
    var rowCount = 0;
    var corrupt = 0;
    final entries = <Vo2ListEntry>[];
    for (final id in ids) {
      final chain = _vo2[id]!;
      rowCount += chain.length;
      final head = tryParseVo2Row(_vo2Last(chain));
      if (head == null) {
        corrupt += 1;
        entries.add(Vo2ListEntry(id: id, head: null, corrupt: true));
      } else {
        entries.add(Vo2ListEntry(id: id, head: head, corrupt: false));
      }
    }
    return Vo2List(entries: entries, corruptCount: corrupt, rowCount: rowCount);
  }

  Vo2Detail _vo2Detail(String id) {
    if (!isVo2EntryId(id)) {
      return Vo2Detail(
        id: id,
        head: null,
        missing: true,
        headCorrupt: false,
        revisions: const [],
        corruptRevisionCount: 0,
      );
    }
    final chain = _vo2[id];
    if (chain == null || chain.isEmpty) {
      return Vo2Detail(
        id: id,
        head: null,
        missing: true,
        headCorrupt: false,
        revisions: const [],
        corruptRevisionCount: 0,
      );
    }
    final slots = <Vo2RevisionSlot>[];
    for (final raw in _vo2Ordered(chain)) {
      final parsed = tryParseVo2Row(raw);
      final revision = raw['revision'];
      slots.add(
        Vo2RevisionSlot(
          revision: parsed?.revision ?? (revision is int ? revision : null),
          value: parsed,
          corrupt: parsed == null,
        ),
      );
    }
    final last = slots.last;
    return Vo2Detail(
      id: id,
      head: last.corrupt ? null : last.value,
      missing: false,
      headCorrupt: last.corrupt,
      revisions: slots,
      corruptRevisionCount: slots.where((slot) => slot.corrupt).length,
    );
  }

  Vo2WriteResult _vo2Write({
    required _Vo2Op op,
    required String id,
    required int expectedRevision,
    String? measuredOn,
    double? valueMlKgMin,
    String? declaredMethod,
  }) {
    final method = normalizeVo2Method(declaredMethod);
    if (!_vo2InputOk(
      op: op,
      id: id,
      expectedRevision: expectedRevision,
      measuredOn: measuredOn,
      valueMlKgMin: valueMlKgMin,
    )) {
      return const Vo2WriteRejected(Vo2RejectReason.invalid);
    }
    final nowMs = vo2Now().millisecondsSinceEpoch;
    final chain = _vo2[id];
    if (chain == null || chain.isEmpty) {
      if (op != _Vo2Op.create) {
        return const Vo2WriteRejected(Vo2RejectReason.missing);
      }
      final created = Vo2Revision(
        id: id,
        revision: 1,
        measuredOn: measuredOn!,
        valueMlKgMin: valueMlKgMin!,
        declaredMethod: method,
        createdAt: nowMs,
        updatedAt: nowMs,
        deleted: false,
      );
      _vo2[id] = [_vo2Row(created)];
      return Vo2Committed(created);
    }
    final head = tryParseVo2Row(_vo2Last(chain));
    if (head == null) return const Vo2WriteConflict(headCorrupt: true);
    if (head.revision == expectedRevision) {
      if (!_vo2Applies(op, head)) return Vo2WriteConflict(head: head);
      final next = _vo2Next(
        op: op,
        head: head,
        nowMs: nowMs,
        measuredOn: measuredOn,
        valueMlKgMin: valueMlKgMin,
        method: method,
      );
      chain.add(_vo2Row(next));
      return Vo2Committed(next);
    }
    if (head.revision == expectedRevision + 1 &&
        _vo2IsRetry(
          chain: chain,
          op: op,
          head: head,
          expectedRevision: expectedRevision,
          measuredOn: measuredOn,
          valueMlKgMin: valueMlKgMin,
          method: method,
        )) {
      return Vo2Committed(head, retry: true);
    }
    return Vo2WriteConflict(head: head);
  }

  void _vo2AppendCorruptHead(String id) {
    final chain = _vo2[id];
    if (chain == null || chain.isEmpty) {
      throw StateError('VO2 corrupt head needs a stored chain.');
    }
    final parsed = tryParseVo2Row(_vo2Last(chain));
    final revision = (parsed?.revision ?? chain.length) + 1;
    chain.add({
      'id': id,
      'revision': revision,
      'measured_on': 'not-a-day',
      'value_ml_kg_min': 99,
      'declared_method': parsed?.declaredMethod,
      'created_at': parsed?.createdAt ?? 0,
      'updated_at': (parsed?.updatedAt ?? 0) + 1,
      'deleted': 0,
      'origin': kVo2Origin,
      'unit': kVo2Unit,
    });
  }
}

enum _Vo2Op { create, edit, delete, restore }

bool _vo2InputOk({
  required _Vo2Op op,
  required String id,
  required int expectedRevision,
  String? measuredOn,
  double? valueMlKgMin,
}) {
  if (!isVo2EntryId(id)) return false;
  if (op == _Vo2Op.create) {
    if (expectedRevision != 0) return false;
  } else if (expectedRevision < 1) {
    return false;
  }
  if (op == _Vo2Op.create || op == _Vo2Op.edit) {
    if (measuredOn == null || !isVo2CivilDay(measuredOn)) return false;
    if (valueMlKgMin == null || !isVo2Value(valueMlKgMin)) return false;
  }
  return true;
}

bool _vo2Applies(_Vo2Op op, Vo2Revision head) {
  switch (op) {
    case _Vo2Op.create:
      return false;
    case _Vo2Op.edit:
    case _Vo2Op.delete:
      return !head.deleted;
    case _Vo2Op.restore:
      return head.deleted;
  }
}

Vo2Revision _vo2Next({
  required _Vo2Op op,
  required Vo2Revision head,
  required int nowMs,
  String? measuredOn,
  double? valueMlKgMin,
  String? method,
}) {
  return Vo2Revision(
    id: head.id,
    revision: head.revision + 1,
    measuredOn: op == _Vo2Op.edit ? measuredOn! : head.measuredOn,
    valueMlKgMin: op == _Vo2Op.edit ? valueMlKgMin! : head.valueMlKgMin,
    declaredMethod: op == _Vo2Op.edit ? method : head.declaredMethod,
    createdAt: head.createdAt,
    updatedAt: nowMs > head.updatedAt ? nowMs : head.updatedAt + 1,
    deleted: op == _Vo2Op.delete,
  );
}

/// Retry only when [op] could have produced [head] from the expected base.
/// Restore requires that base to be deleted, so a same-value edit is not a
/// successful restore.
bool _vo2IsRetry({
  required List<Map<String, Object?>> chain,
  required _Vo2Op op,
  required Vo2Revision head,
  required int expectedRevision,
  String? measuredOn,
  double? valueMlKgMin,
  String? method,
}) {
  if (op == _Vo2Op.create) {
    return !head.deleted &&
        head.revision == 1 &&
        head.measuredOn == measuredOn &&
        head.valueMlKgMin == valueMlKgMin &&
        head.declaredMethod == method &&
        head.origin == kVo2Origin &&
        head.unit == kVo2Unit;
  }
  Vo2Revision? base;
  for (final raw in chain) {
    if (raw['revision'] == expectedRevision) {
      base = tryParseVo2Row(raw);
      break;
    }
  }
  if (base == null ||
      base.revision != expectedRevision ||
      base.createdAt != head.createdAt) {
    return false;
  }
  switch (op) {
    case _Vo2Op.create:
      return false;
    case _Vo2Op.edit:
      return !base.deleted &&
          !head.deleted &&
          head.measuredOn == measuredOn &&
          head.valueMlKgMin == valueMlKgMin &&
          head.declaredMethod == method;
    case _Vo2Op.delete:
      return !base.deleted &&
          head.deleted &&
          head.measuredOn == base.measuredOn &&
          head.valueMlKgMin == base.valueMlKgMin &&
          head.declaredMethod == base.declaredMethod &&
          head.origin == base.origin &&
          head.unit == base.unit;
    case _Vo2Op.restore:
      return base.deleted &&
          !head.deleted &&
          head.measuredOn == base.measuredOn &&
          head.valueMlKgMin == base.valueMlKgMin &&
          head.declaredMethod == base.declaredMethod &&
          head.origin == base.origin &&
          head.unit == base.unit;
  }
}

List<Map<String, Object?>> _vo2Ordered(List<Map<String, Object?>> chain) {
  final ordered = [...chain];
  ordered.sort((a, b) {
    final ar = a['revision'];
    final br = b['revision'];
    if (ar is int && br is int) return ar.compareTo(br);
    if (ar is int) return -1;
    if (br is int) return 1;
    return 0;
  });
  return ordered;
}

Map<String, Object?> _vo2Last(List<Map<String, Object?>> chain) =>
    _vo2Ordered(chain).last;

Map<String, Object?> _vo2Row(Vo2Revision revision) => {
  'id': revision.id,
  'revision': revision.revision,
  'measured_on': revision.measuredOn,
  'value_ml_kg_min': revision.valueMlKgMin,
  'declared_method': revision.declaredMethod,
  'created_at': revision.createdAt,
  'updated_at': revision.updatedAt,
  'deleted': revision.deleted ? 1 : 0,
  'origin': revision.origin,
  'unit': revision.unit,
};

class _SyntheticStrength {
  _SyntheticStrength({required this.plan, required this.startedAt});
  final WorkoutTemplate plan;
  final DateTime startedAt;
  final List<RecordedSet> recorded = [];
  final Set<String> skipped = {};
  final List<PlannedExercise> added = [];
  DateTime? restEndsAt;
  bool finished = false;
}

class _SynthJournalDay {
  final Map<String, JournalMetricValue> metrics = {};
  final Map<String, int> metricUpdatedAt = {};
  List<String> tags = [];
  String note = '';
  int journalUpdatedAt = 0;
}

Map<String, Object?> _syntheticCaffeineSleepCorrelate(
  Map<String, Object?> input,
) {
  final dates = (input['dates'] as List).cast<String>();
  final journal = [
    for (final row in input['journal'] as List)
      ana.JournalNumericDay((row as Map)['date'] as String, {
        for (final e in (row['values'] as Map).entries)
          e.key as String: (e.value as num).toDouble(),
      }),
  ];
  final corr = ana.journalNumericCorrelations(
    journal: journal,
    dates: dates,
    outcomes: {
      CaffeineSleepPattern.outcome: [
        for (final v in input['sol'] as List) (v as num?)?.toDouble(),
      ],
    },
    fieldLagDays: const {
      CaffeineSleepPattern.field: CaffeineSleepPattern.lagDays,
    },
  );
  if (corr.isEmpty || corr.first.effects.isEmpty) {
    return const {'empty': true, 'n': 0};
  }
  final field = corr.first;
  final effect = field.effects.first;
  return {
    'empty': false,
    'binary': effect.binary,
    'insufficient': effect.insufficient,
    'meaningful': effect.meaningful,
    'n': effect.n,
    'nWith': effect.nWith,
    'nWithout': effect.nWithout,
    'delta': effect.delta,
    'note': effect.note,
    'lagDays': field.lagDays,
  };
}
