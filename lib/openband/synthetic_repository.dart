import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/lab_catalogue.dart';
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
  final Map<String, double> _strainByDay = {};
  WeekendSleepEstimate? weekendEstimate;
  SetupEvaluation? setupEvaluation;
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
  bool failJournalPatch = false;
  bool failJournalFieldsList = false;
  bool failJournalFieldsCreate = false;
  Future<void>? journalPatchBarrier;

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
  final Map<String, JournalFieldSpec> _journalFieldDefs = {};
  int _journalClock = 0;

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

  final Map<String, WorkoutTemplate> _templates = {};
  final Set<String> _archivedTemplates = {};
  String? _pinnedTemplateId;
  final Map<String, MealDraft> _mealDrafts = {};
  final Map<String, List<MealEntry>> _meals = {};
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
    _strength['synthetic-$priorDay-weight_training'] = _SyntheticStrength(
      plan: _templates['tpl-ganzkoerper-a']!,
      startedAt: priorAt,
    )..finished = true
     ..recorded.addAll([
      hist('bench_press', 1, priorAt, reps: 8, loadKg: 37.5, plannedSetId: 'bp-1'),
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
    _meals[_day] = [
      const MealEntry(
        id: 'm1',
        meal: 'breakfast',
        label: 'Haferflocken mit Milch',
        kcal: 380,
        proteinG: 14,
        carbsG: 58,
        fatG: 9,
      ),
      const MealEntry(id: 'm2', meal: 'breakfast', label: 'Kaffee'),
      const MealEntry(
        id: 'm3',
        meal: 'lunch',
        label: 'Linsensalat',
        kcal: 240,
        proteinG: 12,
        carbsG: 30,
        fatG: 6,
      ),
    ];
  }

  final Map<String, List<RecordedSet>> _liveSets = {};
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
    _strength['synthetic-paper-prior'] = _SyntheticStrength(
      plan: paper,
      startedAt: priorAt,
    )..finished = true
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
        runtime.recorded.any((s) => s.plannedSetId == set.plannedSetId)) {
      return;
    }
    var restSec = set.restSec;
    if (restSec == null && identity) {
      restSec = lookup.restBySet[set.plannedSetId!];
    }
    final stored = RecordedSet(
      exerciseKey: set.exerciseKey,
      setIndex: set.setIndex,
      reps: set.reps,
      seconds: set.seconds,
      loadKg: set.loadKg,
      at: set.at,
      plannedSetId: identity ? set.plannedSetId : null,
      exerciseId: identity
          ? (set.exerciseId ?? lookup.setExercise[set.plannedSetId])
          : set.exerciseId,
      restSec: restSec,
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
      );
    } else {
      runtime.added.add(
        PlannedExercise(
          id: exercise.id,
          exerciseKey: exercise.exerciseKey,
          name: exercise.name,
          sets: [set],
          note: exercise.note,
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

  ({Set<String> setIds, Map<String, String> setExercise, Map<String, int?> restBySet})
  _syntheticPlanLookup(_SyntheticStrength runtime) {
    final setIds = <String>{};
    final setExercise = <String, String>{};
    final restBySet = <String, int?>{};
    for (final e in [...runtime.plan.exercises, ...runtime.added]) {
      for (final s in e.sets) {
        setIds.add(s.id);
        setExercise[s.id] = e.id;
        restBySet[s.id] = s.restSec;
      }
    }
    return (setIds: setIds, setExercise: setExercise, restBySet: restBySet);
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

  @override
  Future<DayMeals> readMeals(String day) async {
    _seedPlans();
    final entries = _meals[day] ?? const [];
    NutrientSum sum(double? Function(MealEntry) pick) {
      var known = 0, unknown = 0;
      double total = 0;
      for (final e in entries) {
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
      entries: entries,
      kcal: sum((e) => e.kcal),
      proteinG: sum((e) => e.proteinG),
      carbsG: sum((e) => e.carbsG),
      fatG: sum((e) => e.fatG),
    );
  }

  @override
  Future<MealDraft?> readMealDraft(String day, String meal) async =>
      _mealDrafts['$day/$meal'];

  @override
  Future<void> saveMealDraft(MealDraft draft) async {
    _mealDrafts['${draft.day}/${draft.meal}'] = draft;
  }

  @override
  Future<void> discardMealDraft(String draftId) async {
    _mealDrafts.removeWhere((_, d) => d.id == draftId);
  }

  @override
  Future<void> commitMealDraft(MealDraft draft) async {
    _seedPlans();
    if (draft.entries.isEmpty) {
      throw ArgumentError('Ein leerer Entwurf wird nicht gespeichert.');
    }
    if (scenario == SyntheticScenario.saveFailure) {
      throw StateError('Speichern schlägt fehl.');
    }
    (_meals[draft.day] ??= []).addAll([
      for (final e in draft.entries)
        MealEntry(
          id: e.id,
          meal: draft.meal,
          label: e.label,
          kcal: e.kcal,
          proteinG: e.proteinG,
          carbsG: e.carbsG,
          fatG: e.fatG,
        ),
    ]);
    _mealDrafts.remove('${draft.day}/${draft.meal}');
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
  Future<PatternSummary> readPattern(
    String habitKey,
    MetricKey outcome,
    String endDay,
    int nights,
  ) async {
    final days = openBandDaysEnding(endDay, nights + 1);
    final series = {
      for (final p in await readMetricHistory(outcome, endDay, nights + 1))
        p.day: p.value,
    };
    return summarizePattern(
      {for (final d in days) d: _journal[d]?.metrics[habitKey]?.value},
      series,
      days,
    );
  }

  @override
  Future<List<JournalEntry>> readJournal(String day) async => [
    for (final e in (_journal[day]?.metrics ?? const {}).entries)
      JournalEntry(e.key, e.value.value),
  ];

  @override
  Future<void> writeJournal(String day, String key, double value) async {
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
      for (final f in [...kJournalFields, ..._journalFieldDefs.values]) f.key: f,
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
    final recovery = Map<String, dynamic>.from(_summary['recovery'] as Map);
    final todayKnown =
        scenario != SyntheticScenario.missing &&
        scenario != SyntheticScenario.processing;
    final source = switch (key) {
      MetricKey.hrv => {
        ..._hrvByDay,
        if (todayKnown) _day: (recovery['hrv_ms'] as num).toDouble(),
      },
      MetricKey.restingHr => {
        ..._rhrByDay,
        if (todayKnown) _day: (recovery['rhr_bpm'] as num).toDouble(),
      },
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

  @override
  Future<OpenBandDay> readDay(String day) async {
    if (day == _day) return _overlay(_baseDay());
    return OpenBandDay(
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
          ? DayMetric(_hrvByDay[day], baseline: _hrvByDay[day])
          : const DayMetric.missing(),
      restingHr: _rhrByDay.containsKey(day)
          ? DayMetric(_rhrByDay[day], baseline: _rhrByDay[day])
          : const DayMetric.missing(),
      synthetic: true,
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
      hrv: DayMetric(
        (recovery['hrv_ms'] as num).toDouble(),
        baseline: _hrvByDay[_previousDay(_day)],
      ),
      restingHr: DayMetric(
        (recovery['rhr_bpm'] as num).toDouble(),
        baseline: _rhrByDay[_previousDay(_day)],
      ),
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
}

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
