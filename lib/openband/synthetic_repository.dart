import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/theme.dart';

enum SyntheticScenario {
  complete,
  dense,
  partial,
  missing,
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

  final Map<String, dynamic> _summary;
  final Map<String, dynamic> _detail;
  final Map? activity;
  final Map<String, SleepDraft> _drafts = {};
  final Map<String, SleepCorrection> _corrections = {};
  final Map<String, SleepNight> _applied = {};
  final Map<String, double> _sleepByDay = {};
  final Map<String, double> _hrvByDay = {};
  final Map<String, double> _rhrByDay = {};

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
    final saved = _at(_day, _summary['latest_saved_local'] as String);
    _baseBand = BandSnapshot(
      connection: BandConnection.connected,
      transfer: TransferState.idle,
      batteryPercent: (_summary['battery_percent'] as num).toInt(),
      batteryObservedAt: saved,
      latestStoredAt: saved,
    );
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

  final Map<String, Map<String, double>> _journal = {};
  final Map<String, WorkoutTemplate> _templates = {};
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
    final id = 'synthetic-live-${_liveSets.length + 1}';
    _liveSets[id] = [];
    return id;
  }

  @override
  Future<void> recordSet(String sessionId, RecordedSet set) async {
    (_liveSets[sessionId] ??= []).add(set);
  }

  @override
  Future<void> finishStrengthSession(String sessionId) async {}

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
    return _templates.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<WorkoutTemplate> saveTemplate(WorkoutTemplate template) async {
    _seedPlans();
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
    return saved;
  }

  @override
  Future<void> archiveTemplate(String id) async {
    _seedPlans();
    _templates.remove(id);
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
      {for (final d in days) d: _journal[d]?[habitKey]},
      series,
      days,
    );
  }

  @override
  Future<List<JournalEntry>> readJournal(String day) async => [
    for (final e in (_journal[day] ?? const {}).entries)
      JournalEntry(e.key, e.value),
  ];

  @override
  Future<void> writeJournal(String day, String key, double value) async {
    (_journal[day] ??= {})[key] = value;
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
