import 'dart:convert';

import '../data/db.dart';
import '../data/journal_fields.dart';
import '../data/nutrition_store.dart';
import '../data/day_label.dart';
import '../data/series_codec.dart';
import '../compute/derivation_engine.dart' show kAlgoVersion;
import '../compute/nap_edits.dart';
import '../state/app_state.dart';
import 'domain.dart';
import 'theme.dart';
import 'time.dart';

/// SQLite-backed boundary for the first OpenBand daily/sleep-correction flow.
/// All legacy Map payloads are decoded here; callers only see typed values.
class LocalOpenBandRepository implements OpenBandRepository {
  LocalOpenBandRepository(this.app);

  final AppState app;

  @override
  Future<NightSignals> readNightSignals(String day) async {
    _requireDay(day);
    final correction = await LocalDb.openBandSleepCorrection(day);
    final zone = correction?['recording_timezone']?.toString();
    if (correction != null && correction['status'] != 'complete') {
      return NightSignals(
        day: day,
        recordingTimezone: zone,
        processing: correction['status'] != 'failed',
      );
    }
    final row = await LocalDb.dayResult(day);
    if (row == null || row['skipped'] == 1) {
      return NightSignals(day: day, recordingTimezone: zone);
    }
    final payload = _payload(row['payload_json']);
    if (payload == null) {
      throw const FormatException('Stored night signals are unreadable.');
    }
    final start = _signalTime(_at(payload, 'sleep.window.value.onset_ms'));
    final end = _signalTime(_at(payload, 'sleep.window.value.offset_ms'));
    if (start == null || end == null || !end.isAfter(start)) {
      return NightSignals(day: day, recordingTimezone: zone);
    }

    final selectedVersion = (row['algo_version'] as num?)?.toInt();
    final neighborDays = [
      for (final id in _nightCandidateDays(day, start, end))
        if (id != day) id,
    ];
    final pulseSources = [_curveReadings(payload, 'hr_curve', start, end)];
    final respSources = [_curveReadings(payload, 'resp_day', start, end)];
    if (selectedVersion != null && neighborDays.isNotEmpty) {
      final neighborRows = await LocalDb.servedDayResultsForDays(neighborDays);
      final neighborCorrections = await LocalDb.openBandSleepCorrectionsForDays(
        neighborDays,
      );
      for (final id in neighborDays) {
        final neighborRow = neighborRows[id];
        if (neighborRow == null) continue;
        final neighborVersion = (neighborRow['algo_version'] as num?)?.toInt();
        final neighborCorrection = neighborCorrections[id];
        if (neighborRow['skipped'] == 1 ||
            neighborVersion != selectedVersion ||
            (neighborCorrection != null &&
                neighborCorrection['status'] != 'complete')) {
          continue;
        }
        final neighborPayload = _payload(neighborRow['payload_json']);
        if (neighborPayload == null) continue;
        pulseSources.add(
          _curveReadings(neighborPayload, 'hr_curve', start, end),
        );
        respSources.add(
          _curveReadings(neighborPayload, 'resp_day', start, end),
        );
      }
    }

    final selectedPartial = row['partial'] == 1;
    NightSignalSeries storedCurve(
      List<NightSignalReading> readings,
      Duration gap,
    ) => NightSignalSeries(
      readings: readings,
      maxConnectingGap: gap,
      // Calendar-day downsampled curves do not prove continuous overnight coverage.
      partial: readings.isNotEmpty,
    );

    List<NightSignalReading> withinNight(List<NightSignalReading> readings) =>
        List.unmodifiable(
          readings
            ..removeWhere((r) => r.at.isBefore(start) || !r.at.isBefore(end))
            ..sort((a, b) => a.at.compareTo(b.at)),
        );

    final origin = _signalTime(_at(payload, 'hrv_night_shape.origin_ms'));
    final rawBins = _at(payload, 'hrv_night_shape.value.bins');
    final hrv = <NightSignalReading>[];
    if (origin != null && rawBins is List) {
      for (final bin in rawBins) {
        if (bin is! Map) continue;
        final offset = _double(bin['t']);
        if (offset == null || offset < 0) continue;
        final at = _signalTime(origin.millisecondsSinceEpoch + offset * 1000);
        if (at == null) continue;
        final value = _double(bin['rmssd_ms']);
        final lower = _double(bin['lo_ms']);
        final upper = _double(bin['hi_ms']);
        final hasBand =
            value != null &&
            lower != null &&
            upper != null &&
            lower <= value &&
            value <= upper;
        hrv.add(
          NightSignalReading(
            at,
            hasBand ? value : null,
            bounds: hasBand ? (lower: lower, upper: upper) : null,
          ),
        );
      }
    }
    final hrvReadings = withinNight(hrv);
    return NightSignals(
      day: day,
      window: (start: start, end: end),
      recordingTimezone: zone,
      series: {
        NightSignalKind.pulse: storedCurve(
          _unionNightReadings(pulseSources),
          const Duration(minutes: 1),
        ),
        NightSignalKind.respiration: storedCurve(
          _unionNightReadings(respSources),
          const Duration(minutes: 5, seconds: 2),
        ),
        NightSignalKind.hrv: NightSignalSeries(
          readings: hrvReadings,
          maxConnectingGap: const Duration(minutes: 30),
          partial: selectedPartial || hrvReadings.any((r) => r.value == null),
          reason: _stringAt(payload, 'hrv_night_shape.note'),
        ),
      },
    );
  }

  static DateTime? _signalTime(Object? raw, {bool seconds = false}) {
    final value = _double(raw);
    if (value == null) return null;
    final ms = value * (seconds ? 1000 : 1);
    if (ms.abs() > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
  }

  static const _kNightCandidatePad = Duration(hours: 16);
  static const _kMaxNightCandidateDays = 16;

  /// Civil-date labels that may own calendar-day curves intersecting [start, end).
  /// ±16h around the absolute window covers IANA UTC−12..+14 plus DST.
  static Set<String> _nightCandidateDays(
    String selected,
    DateTime start,
    DateTime end,
  ) {
    final lo = start.toUtc().subtract(_kNightCandidatePad);
    final hi = end.toUtc().add(_kNightCandidatePad);
    var cursor = DateTime(lo.year, lo.month, lo.day);
    final last = DateTime(hi.year, hi.month, hi.day);
    final out = <String>{selected};
    while (!cursor.isAfter(last)) {
      out.add(dayLabelOf(cursor));
      if (out.length > _kMaxNightCandidateDays) {
        throw const FormatException('Stored night signals are unreadable.');
      }
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return out;
  }

  static List<NightSignalReading> _curveReadings(
    Map<String, dynamic> payload,
    String key,
    DateTime start,
    DateTime end,
  ) {
    final raw = _at(payload, 'series.$key');
    if (raw == null) return const [];
    if (raw is! List) return const [];
    final readings = <NightSignalReading>[];
    for (final item in raw) {
      if (item is! Map) return const [];
      final at = _signalTime(item['t'], seconds: true);
      if (at == null) return const [];
      if (at.isBefore(start) || !at.isBefore(end)) continue;
      readings.add(NightSignalReading(at, _double(item['v'])));
    }
    return readings;
  }

  static List<NightSignalReading> _unionNightReadings(
    List<List<NightSignalReading>> sources,
  ) {
    final byMs = <int, Set<double?>>{};
    for (final source in sources) {
      for (final reading in source) {
        (byMs[reading.at.millisecondsSinceEpoch] ??= {}).add(reading.value);
      }
    }
    final times = byMs.keys.toList()..sort();
    return List.unmodifiable([
      for (final ms in times)
        NightSignalReading(
          DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
          byMs[ms]!.length == 1 ? byMs[ms]!.single : null,
        ),
    ]);
  }

  @override
  Future<OpenBandDay> readDay(String day) async {
    _requireDay(day);
    final repository = app.repo;
    if (repository == null) {
      throw StateError('Local repository is not initialized.');
    }

    final row = await LocalDb.dayResult(day);
    final payload = _payload(row?['payload_json']);
    if (row != null && payload == null) {
      throw const FormatException('Stored day result is unreadable.');
    }
    // Legacy day readers intentionally borrow the latest complete night when
    // today has no row. A selected-day view must refuse that fallback.
    final values = await Future.wait<Map<String, dynamic>>([
      row == null ? Future.value({}) : repository.getDaySleep(day),
      row == null ? Future.value({}) : repository.getDayHeart(day),
      row == null ? Future.value({}) : repository.getDayHrv(day),
      row == null ? Future.value({}) : repository.getDayStrain(day),
      repository.getDaySteps(day),
    ]);
    final sleepMap = values[0],
        heart = values[1],
        hrvMap = values[2],
        strainMap = values[3],
        stepsMap = values[4];
    final db = await LocalDb.instance;
    final nutrition = rollupDay(
      day,
      await NutritionDb.entriesForDay(db, day),
      today: todayLabel(),
    );
    final journal = await repository.getJournalMetrics(day);
    final correctionRow = await LocalDb.openBandSleepCorrection(day);
    final provenanceRows = await LocalDb.metricSeriesVersions();
    String? source;
    for (final candidate in provenanceRows) {
      if (candidate['date'] == day) {
        source = candidate['source']?.toString();
        break;
      }
    }

    final historyRows = await LocalDb.metricSeries('tst_min');
    final throughDay = [
      for (final r in historyRows)
        if ((r['date'] as String?) case final d? when d.compareTo(day) <= 0)
          (day: d, minutes: (r['value'] as num?)?.toDouble()),
    ];
    final history = throughDay.length <= 8
        ? throughDay
        : throughDay.sublist(throughDay.length - 8);

    final onset = _epochSeconds(sleepMap['onset_ts']);
    final wake = _epochSeconds(sleepMap['wake_ts']);
    final unobserved = _unobservedMinutes(payload);
    final duration = _metric(
      sleepMap['duration_min'],
      reason: sleepMap['note']?.toString(),
      partial: unobserved != null && unobserved > 0,
      processing: app.deriving || app.derivePending,
    );
    final recordingTimezone = correctionRow?['recording_timezone']?.toString();

    return OpenBandDay(
      day: day,
      sleep: SleepNight(
        onset: onset == null ? null : recordedTime(onset, recordingTimezone),
        wake: wake == null ? null : recordedTime(wake, recordingTimezone),
        recordingTimezone: recordingTimezone?.isEmpty == true
            ? null
            : recordingTimezone,
        duration: duration,
        bedMinutes: _double(sleepMap['in_bed_min']),
        awakeMinutes: _double(sleepMap['awake_min']),
        remMinutes: _double(sleepMap['rem_min']),
        lightMinutes: _double(sleepMap['light_min']),
        deepMinutes: _double(sleepMap['deep_min']),
        unobservedMinutes: unobserved,
        segments: _segments(payload),
        source: source == null || source.isEmpty ? 'unknown' : source,
        history: history,
      ),
      recovery: _metric(
        heart['recovery'],
        reason:
            _stringAt(payload, 'clinical.readiness_composite.note') ??
            _nestedReason(heart, 'recovery'),
        processing: app.deriving || app.derivePending,
      ),
      strain: _metric(
        strainMap['strain'],
        reason: strainMap['note']?.toString(),
        processing: app.deriving || app.derivePending,
      ),
      hrv: _metric(
        hrvMap['rmssd'],
        baseline: _numAt(payload, 'baselines.hrv.baseline')?.toDouble(),
        reason: _envelopeReason(hrvMap['hrv_time']),
        processing: app.deriving || app.derivePending,
      ),
      restingHr: _metric(
        heart['resting_hr'],
        baseline: _numAt(payload, 'baselines.resting_hr.baseline')?.toDouble(),
        reason:
            _stringAt(payload, 'clinical.resting_hr.note') ??
            _nestedReason(heart, 'resting_hr'),
        processing: app.deriving || app.derivePending,
      ),
      // day_total is the derived day's published result. Resolved spans may be
      // useful detail but are not silently substituted for a missing metric.
      steps: _metric(
        stepsMap['day_total'],
        reason: stepsMap['note']?.toString(),
        processing: app.deriving || app.derivePending,
      ),
      stepIntervals: [
        for (final span
            in stepsMap['spans'] is List ? stepsMap['spans'] as List : const [])
          if (span is Map &&
              span['start_ts'] is num &&
              span['end_ts'] is num &&
              span['steps'] is num)
            StepInterval(
              _epochSeconds(span['start_ts'])!,
              _epochSeconds(span['end_ts'])!,
              (span['steps'] as num).toDouble(),
            ),
      ],
      calculatedAt: row?['computed_at'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (row!['computed_at'] as num).toInt(),
            )
          : null,
      intake: DayIntake(
        kcal: nutrition.kcal.value,
        kcalIsFloor: nutrition.kcal.isFloor,
        waterMl: journal['water_ml']?.value,
      ),
      correction: _correction(correctionRow),
      synthetic: payload?['synthetic'] == true,
    );
  }

  /// Live connection/receive state is intentionally separate from durable
  /// storage. [latestStoredAt] is the persisted band frontier, never lastRxAt.
  @override
  Future<String> startStrengthSession(WorkoutTemplate template) async {
    // One live engine: AppState owns the running session (streams, tallies,
    // the sessions row on stop). A second start path would be the bug.
    if (app.activeWorkout != null) {
      throw StateError('Eine Einheit läuft bereits.');
    }
    final id = 'w${DateTime.now().millisecondsSinceEpoch}';
    app.startWorkout(type: 'weight_training', workoutId: id);
    if (app.activeWorkout?.workoutId != id) {
      throw StateError('Einheit konnte nicht gestartet werden.');
    }
    return id;
  }

  @override
  Future<void> recordSet(String sessionId, RecordedSet set) async {
    final existing = await LocalDb.strengthSets(sessionId);
    await LocalDb.saveStrengthSets(sessionId, [
      ...existing,
      {
        'exercise_key': set.exerciseKey,
        'set_index': set.setIndex,
        'reps': set.reps,
        'load_kg': set.loadKg,
        'hold_sec': set.seconds,
        'at_ts': set.at.millisecondsSinceEpoch ~/ 1000,
      },
    ]);
  }

  @override
  Future<void> finishStrengthSession(String sessionId) async {
    if (app.activeWorkout?.workoutId != sessionId) {
      throw StateError('Diese Einheit läuft nicht mehr.');
    }
    await app.stopWorkout();
  }

  @override
  Future<MuscleLoad> readMuscleLoad(String endDay, int days) async {
    final sessions = await readSessions(endDay, days);
    final db = await LocalDb.instance;
    final defs = {
      for (final r in await db.query('exercise_def'))
        r['key'] as String:
            (jsonDecode(r['muscles_json'] as String? ?? '{}')
                    as Map<String, dynamic>)
                .keys
                .toList(),
    };
    final byMuscle = <String, int>{};
    var unmapped = 0;
    for (final s in sessions.where((s) => !s.live)) {
      for (final row in await LocalDb.strengthSets(s.id)) {
        final muscles = defs[row['exercise_key'] as String];
        if (muscles == null || muscles.isEmpty) {
          unmapped++;
          continue;
        }
        for (final m in muscles) {
          byMuscle[m] = (byMuscle[m] ?? 0) + 1;
        }
      }
    }
    return MuscleLoad(byMuscle, unmapped);
  }

  @override
  Future<List<FoodHit>> searchFoods(String query) async {
    final db = await LocalDb.instance;
    return [
      for (final r in await NutritionDb.searchFoods(db, query))
        FoodHit(
          key: r['key'] as String,
          label: r['label'] as String,
          brand: r['brand'] as String? ?? '',
          servingG: (r['serving_g'] as num?)?.toDouble(),
          kcal100: (r['kcal_100'] as num?)?.toDouble(),
          proteinG100: (r['protein_g_100'] as num?)?.toDouble(),
          carbsG100: (r['carbs_g_100'] as num?)?.toDouble(),
          fatG100: (r['fat_g_100'] as num?)?.toDouble(),
        ),
    ];
  }

  @override
  Future<List<WorkoutTemplate>> readTemplates() async => [
    for (final r in await LocalDb.openBandTemplates())
      WorkoutTemplate(
        id: r['id'] as String,
        name: r['name'] as String,
        version: r['version'] as int,
        exercises: [
          for (final e in jsonDecode(r['exercises_json'] as String) as List)
            PlannedExercise.fromJson(e as Map<String, dynamic>),
        ],
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      ),
  ];

  @override
  Future<WorkoutTemplate> saveTemplate(WorkoutTemplate template) async {
    if (template.name.trim().isEmpty || template.exercises.isEmpty) {
      throw ArgumentError('Eine Vorlage braucht Namen und eine Übung.');
    }
    final now = DateTime.now();
    final version = await LocalDb.putOpenBandTemplate({
      'id': template.id,
      'name': template.name.trim(),
      'exercises_json': jsonEncode([
        for (final e in template.exercises) e.toJson(),
      ]),
      'archived': 0,
      'updated_at': now.millisecondsSinceEpoch,
    });
    return WorkoutTemplate(
      id: template.id,
      name: template.name.trim(),
      version: version,
      exercises: template.exercises,
      updatedAt: now,
    );
  }

  @override
  Future<void> archiveTemplate(String id) =>
      LocalDb.archiveOpenBandTemplate(id);

  @override
  Future<DayMeals> readMeals(String day) async {
    _requireDay(day);
    final db = await LocalDb.instance;
    final rollup = rollupDay(
      day,
      await NutritionDb.entriesForDay(db, day),
      today: todayLabel(),
    );
    NutrientSum sum(NutrientTotal t) =>
        NutrientSum(t.value, t.known, t.unknown);
    return DayMeals(
      day: day,
      entries: [
        for (final e in rollup.entries)
          MealEntry(
            id: e.id,
            meal: e.meal,
            label: e.label,
            kcal: e.kcal,
            proteinG: e.proteinG,
            carbsG: e.carbsG,
            fatG: e.fatG,
          ),
      ],
      kcal: sum(rollup.kcal),
      proteinG: sum(rollup.protein),
      carbsG: sum(rollup.carbs),
      fatG: sum(rollup.fat),
    );
  }

  @override
  Future<MealDraft?> readMealDraft(String day, String meal) async {
    final r = await LocalDb.openBandMealDraft(day, meal);
    if (r == null) return null;
    return MealDraft(
      id: r['draft_id'] as String,
      day: day,
      meal: meal,
      entries: [
        for (final e in jsonDecode(r['entries_json'] as String) as List)
          MealDraftEntry.fromJson(e as Map<String, dynamic>),
      ],
      updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
    );
  }

  @override
  Future<void> saveMealDraft(MealDraft draft) => LocalDb.putOpenBandMealDraft({
    'draft_id': draft.id,
    'day_id': draft.day,
    'meal': draft.meal,
    'entries_json': jsonEncode([for (final e in draft.entries) e.toJson()]),
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  });

  @override
  Future<void> discardMealDraft(String draftId) =>
      LocalDb.deleteOpenBandMealDraft(draftId);

  @override
  Future<void> commitMealDraft(MealDraft draft) async {
    if (draft.entries.isEmpty) {
      throw ArgumentError('Ein leerer Entwurf wird nicht gespeichert.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await LocalDb.commitOpenBandMealDraft(draft.id, [
      for (final e in draft.entries)
        FoodEntry(
          id: e.id,
          date: draft.day,
          meal: draft.meal,
          label: e.label,
          foodKey: e.foodKey,
          quantity: e.quantity,
          unit: e.unit,
          kcal: e.kcal,
          proteinG: e.proteinG,
          carbsG: e.carbsG,
          fatG: e.fatG,
          confirmed: true,
        ).toRow(now),
    ]);
  }

  @override
  Future<SessionDetail?> readSessionDetail(String sessionId) async {
    final stored = await LocalDb.openBandSessionDetail(sessionId);
    if (stored != null) {
      return SessionDetail.fromJson(
        jsonDecode(stored['payload_json'] as String) as Map<String, dynamic>,
      );
    }
    final repository = app.repo;
    final row = await LocalDb.session(sessionId);
    if (repository == null || row == null) return null;
    if (row['status'] == 'live') return null;
    final workout = await repository.getWorkout(sessionId);
    final splits = await LocalDb.workoutSplits(sessionId);
    final startTs = row['start_ts'] as int;
    final endTs = row['end_ts'] as int?;
    final zones = switch (row['zone_min_json']) {
      final String z => [
        for (final m in jsonDecode(z) as List) ((m as num) * 60).round(),
      ],
      _ => null,
    };
    final detail = SessionDetail(
      sessionId: sessionId,
      type: row['type'] as String,
      day: dayLabelOf(DateTime.fromMillisecondsSinceEpoch(startTs * 1000)),
      start: DateTime.fromMillisecondsSinceEpoch(startTs * 1000),
      algoVersion: kAlgoVersion,
      durationSec: endTs == null
          ? switch (row['duration_min'] as int?) {
              null => null,
              final m => m * 60,
            }
          : endTs - startTs,
      avgHr: (workout['avg_hr'] as num?)?.toDouble(),
      maxHr: (workout['max_hr'] as num?)?.toInt(),
      strain: (row['strain'] as num?)?.toDouble(),
      kcal: (row['calories'] as num?)?.toDouble(),
      zoneSec: zones,
      splits: [
        for (final s in splits)
          SessionSplit(
            km: s['km'] as int,
            seconds: s['duration_sec'] as int,
            avgHr: (s['avg_hr'] as num?)?.toDouble(),
          ),
      ],
      laps: await readLaps(sessionId),
    );
    await LocalDb.putOpenBandSessionDetail({
      'session_id': sessionId,
      'algo_version': kAlgoVersion,
      'computed_at': DateTime.now().millisecondsSinceEpoch,
      'payload_json': jsonEncode(detail.toJson()),
    });
    return detail;
  }

  @override
  Future<void> recordLap(String sessionId, Lap lap) => LocalDb.putOpenBandLap({
    'session_id': sessionId,
    'lap_index': lap.index,
    'at_ts': lap.at.millisecondsSinceEpoch ~/ 1000,
    'elapsed_sec': lap.elapsedSec,
    'paused_sec': lap.pausedSec,
    'distance_m': lap.distanceM,
  });

  @override
  Future<List<Lap>> readLaps(String sessionId) async => [
    for (final row in await LocalDb.openBandLaps(sessionId))
      Lap(
        index: row['lap_index'] as int,
        elapsedSec: row['elapsed_sec'] as int,
        pausedSec: row['paused_sec'] as int,
        distanceM: (row['distance_m'] as num?)?.toDouble(),
        at: DateTime.fromMillisecondsSinceEpoch((row['at_ts'] as int) * 1000),
      ),
  ];

  @override
  Future<PatternSummary> readPattern(
    String habitKey,
    MetricKey outcome,
    String endDay,
    int nights,
  ) async {
    _requireDay(endDay);
    final days = openBandDaysEnding(endDay, nights + 1);
    final journal = await LocalDb.journalMetricsByDay(
      sinceDaysEpoch: days.first,
    );
    final rows = await LocalDb.metricSeries(outcome.series);
    return summarizePattern(
      {for (final e in journal.entries) e.key: e.value[habitKey]?.value},
      {
        for (final r in rows)
          r['date'] as String: (r['value'] as num?)?.toDouble(),
      },
      days,
    );
  }

  @override
  Future<List<JournalEntry>> readJournal(String day) async {
    _requireDay(day);
    final repository = app.repo;
    if (repository == null) {
      throw StateError('Local repository is not initialized.');
    }
    final values = await repository.getJournalMetrics(day);
    return [for (final e in values.entries) JournalEntry(e.key, e.value.value)];
  }

  @override
  Future<void> writeJournal(String day, String key, double value) async {
    _requireDay(day);
    final repository = app.repo;
    if (repository == null) {
      throw StateError('Local repository is not initialized.');
    }
    await repository.postJournalMetrics(day, {key: JournalMetricValue(value)});
  }

  @override
  Future<List<TrainingSession>> readSessions(String endDay, int days) async {
    _requireDay(endDay);
    final window = openBandDaysEnding(endDay, days);
    final first = DateTime.parse(window.first);
    final end = DateTime.parse(endDay);
    final fromTs =
        DateTime(first.year, first.month, first.day).millisecondsSinceEpoch ~/
        1000;
    final toTs =
        DateTime(end.year, end.month, end.day + 1).millisecondsSinceEpoch ~/
            1000 -
        1;
    final rows = await LocalDb.sessionsInRange(fromTs, toTs);
    return [
      for (final r in rows)
        if (r['start_ts'] case final int startTs)
          TrainingSession(
            id: r['id'] as String,
            day: dayLabelOf(
              DateTime.fromMillisecondsSinceEpoch(startTs * 1000),
            ),
            type: r['type'] as String,
            start: DateTime.fromMillisecondsSinceEpoch(startTs * 1000),
            durationMin: (r['duration_min'] as num?)?.toInt(),
            strain: (r['strain'] as num?)?.toDouble(),
            kcal: (r['calories'] as num?)?.toDouble(),
            live: r['status'] == 'live',
          ),
    ];
  }

  @override
  Future<List<MetricPoint>> readMetricHistory(
    MetricKey key,
    String endDay,
    int nights,
  ) async {
    _requireDay(endDay);
    final days = openBandDaysEnding(endDay, nights);
    final rows = await LocalDb.metricSeries(key.series);
    final byDay = {
      for (final r in rows)
        r['date'] as String: (r['value'] as num?)?.toDouble(),
    };
    return [for (final d in days) MetricPoint(d, byDay[d])];
  }

  Future<BandSnapshot> readBand() async {
    final battery = await LocalDb.latestBandBatterySample(
      deviceId: LocalDb.kPrimaryDeviceId,
    );
    final ledger = await LocalDb.syncLedgerEntry();
    final storedThrough = await LocalDb.getCursorInt('rec_ts_hw');
    final connection = switch (app.status) {
      'connected' => BandConnection.connected,
      'connecting' || 'reconnecting' => BandConnection.connecting,
      _ => BandConnection.disconnected,
    };
    final ledgerStatus = ledger?['status']?.toString();
    final transfer = app.syncingNow
        ? TransferState.receiving
        : (const {
                'interrupted',
                'failed',
                'link_lost',
                'partial',
                'session_end',
                'aborted',
                'stuck',
                'commit_failed',
                'tail_commit_failed',
                'ack_failed',
                'requested',
                'range_seen',
                'trim_refused',
              }.contains(ledgerStatus)
              ? TransferState.interrupted
              : TransferState.idle);
    return BandSnapshot(
      connection: connection,
      transfer: transfer,
      batteryPercent: (battery?['battery_pct'] as num?)?.round(),
      batteryObservedAt: _epochSeconds(battery?['ts']),
      latestStoredAt: _epochSeconds(storedThrough),
      // No existing durable row records the wall-clock commit time for every
      // stored frontier advance. lastDataAt is only BLE receipt, so it cannot
      // honestly populate a field the UI labels as stored.
      receivedAt: null,
    );
  }

  @override
  Future<Set<String>> sleepDays() => LocalDb.daysWithSleepTst();

  @override
  Future<SleepDraft?> readDraft(String day) async {
    _requireDay(day);
    final row = await LocalDb.openBandSleepDraft(day);
    return row == null ? null : _draft(row);
  }

  @override
  Future<void> saveDraft(SleepDraft draft) async {
    _validateDraft(draft);
    await LocalDb.putOpenBandSleepDraft(
      dayId: draft.day,
      draftId: draft.id,
      onsetMs: draft.onset.millisecondsSinceEpoch,
      wakeMs: draft.wake.millisecondsSinceEpoch,
      recordingTimezone: draft.recordingTimezone,
    );
  }

  @override
  Future<void> discardDraft(String day) async {
    _requireDay(day);
    await LocalDb.deleteOpenBandSleepDraft(day);
  }

  @override
  Future<SleepCorrection> saveCorrection(SleepDraft draft) async {
    _validateDraft(draft);
    final row = await LocalDb.commitOpenBandSleepCorrection(
      dayId: draft.day,
      draftId: draft.id,
      onsetMs: draft.onset.millisecondsSinceEpoch,
      wakeMs: draft.wake.millisecondsSinceEpoch,
      recordingTimezone: draft.recordingTimezone,
    );
    return _correction(row)!;
  }

  @override
  Future<void> recalculate(SleepCorrection correction) async {
    _requireDay(correction.day);
    await app.recalculateOpenBandSleepCorrection(
      day: correction.day,
      correctionId: correction.id,
      revision: correction.revision,
    );
  }

  @override
  Future<void> restoreAutomatic(String day) async {
    _requireDay(day);
    final row = await LocalDb.restoreOpenBandAutomatic(day);
    await app.recalculateOpenBandSleepCorrection(
      day: day,
      correctionId: row['correction_id'] as String,
      revision: (row['revision'] as num).toInt(),
    );
  }

  @override
  Future<SleepGoalSnapshot> readSleepGoal(String day) async {
    _requireDay(day);
    final row = await LocalDb.sleepGoalPeriodAsOf(day);
    final raw = (await LocalDb.baseline('crossday'))?['payload_json'];
    Map<String, dynamic>? artifact;
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          artifact = decoded;
        } else if (decoded is Map) {
          artifact = decoded.cast<String, dynamic>();
        }
      } catch (_) {
        artifact = null;
      }
    }
    return SleepGoalSnapshot(
      period: row == null ? null : _sleepGoalPeriod(row),
      weekendEstimate: weekendSleepEstimateFromCrossday(
        artifact,
        selectedDay: day,
        algoVersion: kAlgoVersion,
      ),
    );
  }

  @override
  Future<void> saveSleepGoal(String day, int minutes) async {
    _requireDay(day);
    if (minutes < kSleepGoalMinMinutes || minutes > kSleepGoalMaxMinutes) {
      throw ArgumentError.value(
        minutes,
        'minutes',
        'Duration must be 1–1440 minutes.',
      );
    }
    await LocalDb.putSleepGoalPeriod(validFromDay: day, minutes: minutes);
  }

  @override
  Future<void> clearSleepGoal(String day) async {
    _requireDay(day);
    await LocalDb.putSleepGoalPeriod(validFromDay: day, minutes: null);
  }

  static SleepGoalPeriod _sleepGoalPeriod(Map<String, dynamic> row) =>
      SleepGoalPeriod(
        validFromDay: row['valid_from_day'] as String,
        minutes: (row['minutes'] as num?)?.toInt(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (row['created_at'] as num).toInt(),
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['updated_at'] as num).toInt(),
        ),
      );

  @override
  Future<NapDay> readNaps(String day) async {
    _requireDay(day);
    final row = await LocalDb.dayResult(day);
    final rawPayload = row?['payload_json'];
    final payload = _payload(rawPayload);
    // Unreadable derived output must not hide the durable ledger.
    final payloadUnreadable =
        row != null && rawPayload != null && '$rawPayload'.isNotEmpty && payload == null;
    final usable =
        row != null &&
        row['skipped'] != 1 &&
        row['partial'] != 1 &&
        payload != null;
    final block = payload?['naps'];
    final value = block is Map ? block['value'] : null;
    final inputs = block is Map ? block['inputs_used'] : null;
    final userOnly =
        inputs is List && inputs.length == 1 && '${inputs.first}' == 'user';
    var listCorrupt = false;
    final derivedDetected = <NapMap>[];
    if (usable && value is List) {
      for (final n in value) {
        if (n is! Map) {
          listCorrupt = true;
          continue;
        }
        final parsed = _detectedFromResult(n.cast<String, dynamic>());
        if (parsed == null) {
          if (n['source'] != 'manual') listCorrupt = true;
          continue;
        }
        derivedDetected.add(parsed);
      }
    } else if (usable && value != null) {
      listCorrupt = true;
    }
    // Detector coverage from a complete, well-formed result only. Manuals on
    // an unjudged day, skipped/partial rows, and corrupt lists never claim a
    // measured empty day.
    final judged = usable && value is List && !userOnly && !listCorrupt;
    const String? zone = null;
    final edits = await LocalDb.napEdits(day);
    final ledger = _ledgerEdits(edits);
    final merged = applyNapEdits(judged ? derivedDetected : const [], ledger);
    final originByStart = <int, (int, int)>{
      for (final r in edits)
        if (r['source'] == 'manual' &&
            _epochSec(r['start_ts']) != null &&
            _epochSec(r['origin_start_ts']) != null &&
            _epochSec(r['origin_end_ts']) != null)
          _epochSec(r['start_ts'])!: (
            _epochSec(r['origin_start_ts'])!,
            _epochSec(r['origin_end_ts'])!,
          ),
    };
    final job = _napJob(await LocalDb.napRecalcJob(day));
    final open =
        job != null && job.state != CorrectionState.complete;
    final scalars = payload?['scalars'];
    final storedTotal = scalars is Map
        ? _durationMin(scalars['nap_min'])
        : null;
    return NapDay(
      day: day,
      judged: judged,
      sessions: [
        for (final n in merged)
          ?_sessionFromMerged(
            n,
            zone,
            originByStart[_epochSec(n['start'])],
          ),
      ],
      totalMin: judged && !open ? storedTotal : null,
      rejected: [
        for (final r in edits)
          if (r['source'] == 'rejected')
            ?_sessionFromEdit(r, zone, NapSource.detected),
      ],
      job: job,
      recordingTimezone: zone,
      note: payloadUnreadable
          ? 'Auswertung unlesbar.'
          : (block is Map ? block['note']?.toString() : null),
    );
  }

  @override
  Future<int> addNap({
    required String day,
    required DateTime start,
    required DateTime end,
  }) async {
    _requireDay(day);
    await _validateNapWindow(day, start, end);
    return LocalDb.putNapEdit(
      dayId: day,
      startTs: start.millisecondsSinceEpoch ~/ 1000,
      endTs: end.millisecondsSinceEpoch ~/ 1000,
      source: 'manual',
    );
  }

  @override
  Future<int> editNap({
    required String day,
    required NapSession original,
    required DateTime start,
    required DateTime end,
  }) async {
    _requireDay(day);
    await _validateNapWindow(
      day,
      start,
      end,
      ignoringStartTs: original.startTs,
    );
    final originStart =
        original.originStartTs ??
        (original.source == NapSource.detected ? original.startTs : null);
    final originEnd =
        original.originEndTs ??
        (original.source == NapSource.detected ? original.endTs : null);
    final newStart = start.millisecondsSinceEpoch ~/ 1000;
    final newEnd = end.millisecondsSinceEpoch ~/ 1000;
    final deletes = [
      if (original.startTs != newStart) original.startTs,
    ];
    // Detected lineage is always origin + optional override. Same-start
    // override is a manual at the origin PK (rejection cannot coexist).
    // A moved override is rejected-at-origin plus manual-at-new. Moving
    // back onto origin replaces that rejection with the manual.
    if (originStart != null && originEnd != null) {
      if (newStart == originStart) {
        return LocalDb.commitNapLedger(
          dayId: day,
          deletes: deletes,
          puts: [
            (
              startTs: newStart,
              endTs: newEnd,
              source: 'manual',
              originStartTs: originStart,
              originEndTs: originEnd,
            ),
          ],
        );
      }
      return LocalDb.commitNapLedger(
        dayId: day,
        deletes: deletes,
        puts: [
          (
            startTs: originStart,
            endTs: originEnd,
            source: 'rejected',
            originStartTs: null,
            originEndTs: null,
          ),
          (
            startTs: newStart,
            endTs: newEnd,
            source: 'manual',
            originStartTs: originStart,
            originEndTs: originEnd,
          ),
        ],
      );
    }
    return LocalDb.commitNapLedger(
      dayId: day,
      deletes: deletes,
      puts: [
        (
          startTs: newStart,
          endTs: newEnd,
          source: 'manual',
          originStartTs: null,
          originEndTs: null,
        ),
      ],
    );
  }

  @override
  Future<int> removeNap({
    required String day,
    required NapSession session,
  }) async {
    _requireDay(day);
    if (!session.fromDetected) {
      return LocalDb.deleteNapEdit(day, session.startTs);
    }
    final originStart = session.originStartTs ?? session.startTs;
    final originEnd = session.originEndTs ?? session.endTs;
    if (session.startTs == originStart) {
      return LocalDb.putNapEdit(
        dayId: day,
        startTs: originStart,
        endTs: originEnd,
        source: 'rejected',
      );
    }
    return LocalDb.commitNapLedger(
      dayId: day,
      deletes: [session.startTs],
      puts: [
        (
          startTs: originStart,
          endTs: originEnd,
          source: 'rejected',
          originStartTs: null,
          originEndTs: null,
        ),
      ],
    );
  }

  @override
  Future<int> restoreNap({
    required String day,
    required NapSession rejected,
  }) async {
    _requireDay(day);
    return LocalDb.deleteNapEdit(day, rejected.startTs);
  }

  @override
  Future<void> recalculateNaps({
    required String day,
    required int revision,
  }) async {
    _requireDay(day);
    await app.recalculateNaps(day: day, revision: revision);
  }

  Future<void> _validateNapWindow(
    String day,
    DateTime start,
    DateTime end, {
    int? ignoringStartTs,
  }) async {
    // Pipeline day keys are device-local. Do not use a night-correction zone.
    if (dayLabelOf(start) != day) {
      throw ArgumentError('Gehört zu einem anderen Tag.');
    }
    final startTs = start.millisecondsSinceEpoch ~/ 1000;
    final endTs = end.millisecondsSinceEpoch ~/ 1000;
    if (!manualNapWindowIsValid(startTs, endTs)) {
      throw ArgumentError('5 Minuten bis 6 Stunden.');
    }
    final others = <NapMap>[];
    for (final label in _neighborDays(day)) {
      others.addAll(
        await _napWindowsOn(
          label,
          ignoringStartTs: label == day ? ignoringStartTs : null,
        ),
      );
    }
    if (napOverlapsExisting(startTs, endTs, others)) {
      throw ArgumentError('Überlappt ein Nickerchen.');
    }
    if (await _overlapsMainSleep(day, startTs, endTs)) {
      throw ArgumentError('Überlappt den Nachtschlaf.');
    }
  }

  Future<List<NapMap>> _napWindowsOn(
    String day, {
    int? ignoringStartTs,
  }) async {
    final row = await LocalDb.dayResult(day);
    final payload = _payload(row?['payload_json']);
    final usable =
        row != null &&
        row['skipped'] != 1 &&
        row['partial'] != 1 &&
        payload != null;
    final value = payload?['naps'] is Map ? payload!['naps']['value'] : null;
    final detected = <NapMap>[
      if (usable && value is List)
        for (final n in value)
          if (n is Map)
            if (_detectedFromResult(n.cast<String, dynamic>()) case final d?)
              if (_epochSec(d['start']) != ignoringStartTs) d,
    ];
    final edits = [
      for (final e in _ledgerEdits(await LocalDb.napEdits(day)))
        if (!(e.kind == NapEditKind.added && e.startSec == ignoringStartTs))
          e,
    ];
    return applyNapEdits(detected, edits);
  }

  Future<bool> _overlapsMainSleep(String day, int startTs, int endTs) async {
    for (final label in _neighborDays(day)) {
      final bounds = await _storedSleepBounds(label);
      if (bounds != null && startTs < bounds.$2 && bounds.$1 < endTs) {
        return true;
      }
    }
    return false;
  }

  Future<(int, int)?> _storedSleepBounds(String day) async {
    final override = await LocalDb.getSleepOverride(day);
    if (override != null && override['source'] != 'rejected') {
      final a = _epochSec(override['onset_ts']);
      final b = _epochSec(override['offset_ts']);
      if (a != null && b != null && b > a) return (a, b);
    }
    final correction = await LocalDb.openBandSleepCorrection(day);
    if (correction != null && correction['action'] != 'automatic') {
      final onsetMs = _epochSec(correction['onset_ms']);
      final wakeMs = _epochSec(correction['wake_ms']);
      if (onsetMs != null && wakeMs != null && wakeMs > onsetMs) {
        return (onsetMs ~/ 1000, wakeMs ~/ 1000);
      }
    }
    final row = await LocalDb.dayResult(day);
    if (row == null || row['skipped'] == 1) return null;
    final payload = _payload(row['payload_json']);
    final onsetMs = _numAt(payload, 'sleep.window.value.onset_ms');
    final offsetMs = _numAt(payload, 'sleep.window.value.offset_ms');
    if (onsetMs == null || offsetMs == null) return null;
    final a = (onsetMs / 1000).round();
    final b = (offsetMs / 1000).round();
    if (b <= a) return null;
    return (a, b);
  }

  static List<String> _neighborDays(String day) {
    final p = DateTime.parse(day);
    return [
      dayLabelOf(DateTime(p.year, p.month, p.day - 1)),
      day,
      dayLabelOf(DateTime(p.year, p.month, p.day + 1)),
    ];
  }

  static List<NapEdit> _ledgerEdits(List<Map<String, dynamic>> rows) => [
    for (final r in rows)
      if ((r['source'] == 'manual' || r['source'] == 'rejected') &&
          _epochSec(r['start_ts']) != null &&
          _epochSec(r['end_ts']) != null &&
          _epochSec(r['end_ts'])! > _epochSec(r['start_ts'])!)
        NapEdit(
          kind: r['source'] == 'rejected'
              ? NapEditKind.rejected
              : NapEditKind.added,
          startSec: _epochSec(r['start_ts'])!,
          endSec: _epochSec(r['end_ts'])!,
        ),
  ];

  static NapMap? _detectedFromResult(Map<String, dynamic> n) {
    if (n['source'] == 'manual') return null;
    final start = _epochSec(n['start']);
    final end = _epochSec(n['end']);
    if (start == null || end == null || end <= start) return null;
    if (n.containsKey('duration_min') && n['duration_min'] != null) {
      final dur = _durationMin(n['duration_min'], maxSec: end - start);
      if (dur == null) return null;
      return {'start': start, 'end': end, 'duration_min': dur};
    }
    return {'start': start, 'end': end};
  }

  static NapSession? _sessionFromMerged(
    NapMap n,
    String? zone,
    (int, int)? origin,
  ) {
    final start = _epochSec(n['start']);
    final end = _epochSec(n['end']);
    if (start == null || end == null || end <= start) return null;
    final manual = n['source'] == 'manual';
    final stored = n.containsKey('duration_min')
        ? _durationMin(n['duration_min'], maxSec: end - start)
        : null;
    if (n.containsKey('duration_min') &&
        n['duration_min'] != null &&
        stored == null) {
      return null;
    }
    return NapSession(
      start: recordedTime(
        DateTime.fromMillisecondsSinceEpoch(start * 1000),
        zone,
      ),
      end: recordedTime(
        DateTime.fromMillisecondsSinceEpoch(end * 1000),
        zone,
      ),
      source: manual ? NapSource.manual : NapSource.detected,
      durationMin: manual ? (stored ?? ((end - start) / 60).round()) : stored,
      originStartTs: origin?.$1,
      originEndTs: origin?.$2,
    );
  }

  static NapSession? _sessionFromEdit(
    Map<String, dynamic> row,
    String? zone,
    NapSource source,
  ) {
    final start = _epochSec(row['start_ts']);
    final end = _epochSec(row['end_ts']);
    if (start == null || end == null || end <= start) return null;
    return NapSession(
      start: recordedTime(
        DateTime.fromMillisecondsSinceEpoch(start * 1000),
        zone,
      ),
      end: recordedTime(
        DateTime.fromMillisecondsSinceEpoch(end * 1000),
        zone,
      ),
      source: source,
      durationMin: source == NapSource.manual
          ? ((end - start) / 60).round()
          : null,
    );
  }

  static int? _epochSec(Object? v) {
    if (v is! num || !v.isFinite) return null;
    return v.toInt();
  }

  static int? _durationMin(Object? v, {int? maxSec}) {
    if (v is! num || !v.isFinite) return null;
    final n = v.round();
    if (n < 0) return null;
    if (maxSec != null && n * 60 > maxSec) return null;
    return n;
  }

  static NapJob? _napJob(Map<String, dynamic>? row) {
    if (row == null) return null;
    final status = row['status']?.toString() ?? 'pending';
    return NapJob(
      day: row['day_id'] as String,
      revision: (row['revision'] as num).toInt(),
      requestedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['requested_at'] as num).toInt(),
      ),
      state: switch (status) {
        'calculating' => CorrectionState.calculating,
        'complete' => CorrectionState.complete,
        'failed' => CorrectionState.failed,
        _ => CorrectionState.pending,
      },
      error: row['error']?.toString(),
    );
  }

  static SleepDraft _draft(Map<String, dynamic> row) => SleepDraft(
    id: row['draft_id'] as String,
    day: row['day_id'] as String,
    onset: recordedTime(
      DateTime.fromMillisecondsSinceEpoch((row['onset_ms'] as num).toInt()),
      row['recording_timezone'] as String?,
    ),
    wake: recordedTime(
      DateTime.fromMillisecondsSinceEpoch((row['wake_ms'] as num).toInt()),
      row['recording_timezone'] as String?,
    ),
    recordingTimezone: row['recording_timezone'] as String?,
  );

  static SleepCorrection? _correction(Map<String, dynamic>? row) {
    if (row == null) return null;
    final onset = (row['onset_ms'] as num?)?.toInt();
    final wake = (row['wake_ms'] as num?)?.toInt();
    // An automatic restore can exist without a prior correction. The supplied
    // contract has non-null bounds, so there is no honest typed receipt to
    // expose in that one state; its durable job still remains queryable/retryable.
    if (onset == null || wake == null) return null;
    final status = row['status']?.toString() ?? 'pending';
    return SleepCorrection(
      id: row['correction_id'] as String,
      day: row['day_id'] as String,
      onset: DateTime.fromMillisecondsSinceEpoch(onset),
      wake: DateTime.fromMillisecondsSinceEpoch(wake),
      savedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['saved_at'] as num).toInt(),
      ),
      revision: (row['revision'] as num).toInt(),
      state: switch (status) {
        'calculating' => CorrectionState.calculating,
        'complete' => CorrectionState.complete,
        'failed' => CorrectionState.failed,
        _ => CorrectionState.pending,
      },
      automatic: row['action'] == 'automatic',
      error: row['error']?.toString(),
    );
  }

  static DayMetric _metric(
    Object? raw, {
    String? reason,
    double? baseline,
    required bool processing,
    bool partial = false,
  }) {
    final value = _double(raw);
    if (value != null) {
      return DayMetric(
        value,
        baseline: baseline,
        readiness: partial
            ? MetricReadiness.partial
            : MetricReadiness.available,
        reason: partial ? 'Ein Teil der Nacht wurde nicht erfasst.' : null,
      );
    }
    final cleanReason = reason?.trim();
    final lower = cleanReason?.toLowerCase() ?? '';
    final readiness = processing
        ? MetricReadiness.processing
        : lower.contains('unreliable') || lower.contains('quality')
        ? MetricReadiness.unreliable
        : lower.contains('unsupported') || lower.contains('unknown_device')
        ? MetricReadiness.unsupported
        : lower.contains('partial') || lower.contains('coverage')
        ? MetricReadiness.partial
        : MetricReadiness.missing;
    return DayMetric(
      null,
      readiness: readiness,
      reason: processing
          ? 'Die Auswertung läuft.'
          : lower.contains('baseline') || lower.contains('history')
          ? 'Es fehlen noch vergleichbare Nächte.'
          : readiness == MetricReadiness.unreliable
          ? 'Die Signalqualität reicht nicht aus.'
          : readiness == MetricReadiness.unsupported
          ? 'Für diese Quelle noch nicht verfügbar.'
          : readiness == MetricReadiness.partial
          ? 'Die Aufzeichnung ist noch unvollständig.'
          : 'Für diesen Wert fehlen ausreichende Daten.',
      baseline: baseline,
    );
  }

  static String? _nestedReason(Map<String, dynamic> map, String key) {
    final absent = map['absent'];
    if (absent is Map) return _envelopeReason(absent[key]);
    return null;
  }

  static String? _envelopeReason(Object? envelope) {
    if (envelope is Map) {
      final note = envelope['note'];
      if (note != null && note.toString().isNotEmpty) return note.toString();
    }
    return null;
  }

  static Map<String, dynamic>? _payload(Object? json) {
    if (json is! String || json.isEmpty) return null;
    try {
      return SeriesCodec.decodePayloadJson(json);
    } catch (_) {
      try {
        final decoded = jsonDecode(json);
        return decoded is Map ? decoded.cast<String, dynamic>() : null;
      } catch (_) {
        return null;
      }
    }
  }

  static List<NightSegment> _segments(Map<String, dynamic>? payload) {
    final series = payload?['series'];
    final raw = series is Map ? series['hypnogram'] : null;
    if (raw is! List) return const [];
    final result = <NightSegment>[];
    final windowStartMs = _numAt(payload, 'sleep.window.value.onset_ms');
    final windowEndMs = _numAt(payload, 'sleep.window.value.offset_ms');
    final windowStart = windowStartMs == null
        ? null
        : (windowStartMs / 1000).floor();
    final windowEnd = windowEndMs == null ? null : (windowEndMs / 1000).ceil();
    int? previousEnd;
    for (final item in raw) {
      if (item is! Map) continue;
      final start = (item['start'] as num?)?.toInt();
      final end = (item['end'] as num?)?.toInt();
      if (start == null || end == null || end <= start) continue;
      final gapStart = previousEnd ?? windowStart;
      if (gapStart != null && start > gapStart) {
        result.add(
          NightSegment(
            DateTime.fromMillisecondsSinceEpoch(gapStart * 1000),
            DateTime.fromMillisecondsSinceEpoch(start * 1000),
            null,
          ),
        );
      }
      result.add(
        NightSegment(
          DateTime.fromMillisecondsSinceEpoch(start * 1000),
          DateTime.fromMillisecondsSinceEpoch(end * 1000),
          _stage(item['stage']),
        ),
      );
      previousEnd = end;
    }
    if (previousEnd != null && windowEnd != null && windowEnd > previousEnd) {
      result.add(
        NightSegment(
          DateTime.fromMillisecondsSinceEpoch(previousEnd * 1000),
          DateTime.fromMillisecondsSinceEpoch(windowEnd * 1000),
          null,
        ),
      );
    }
    return result;
  }

  static Object? _at(Map<String, dynamic>? map, String path) {
    Object? current = map;
    for (final part in path.split('.')) {
      if (current is! Map) return null;
      current = current[part];
    }
    return current;
  }

  static num? _numAt(Map<String, dynamic>? map, String path) {
    final value = _at(map, path);
    return value is num ? value : null;
  }

  static String? _stringAt(Map<String, dynamic>? map, String path) {
    final value = _at(map, path);
    return value is String && value.isNotEmpty ? value : null;
  }

  static NightStage? _stage(Object? raw) => switch (raw?.toString()) {
    'wake' || 'awake' => NightStage.awake,
    'rem' => NightStage.rem,
    'light' => NightStage.light,
    'deep' => NightStage.deep,
    _ => null,
  };

  static double? _unobservedMinutes(Map<String, dynamic>? payload) {
    final segments = _segments(payload);
    if (segments.isEmpty) return null;
    var seconds = 0;
    for (final segment in segments) {
      if (segment.stage == null) {
        seconds += segment.end.difference(segment.start).inSeconds;
      }
    }
    return seconds / 60.0;
  }

  static DateTime? _epochSeconds(Object? value) {
    final seconds = (value as num?)?.toInt();
    return seconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  static double? _double(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;

  static DateTime _requireDay(String day) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
      throw ArgumentError.value(day, 'day', 'Expected YYYY-MM-DD.');
    }
    final parsed = DateTime.tryParse(day);
    if (parsed == null || dayLabelOf(parsed) != day) {
      throw ArgumentError.value(day, 'day', 'Invalid calendar day.');
    }
    return parsed;
  }

  static void _validateDraft(SleepDraft draft) {
    _requireDay(draft.day);
    if (draft.id.trim().isEmpty) {
      throw ArgumentError.value(draft.id, 'id', 'Draft id is required.');
    }
    final span = draft.wake.difference(draft.onset);
    if (span <= Duration.zero || span > const Duration(hours: 24)) {
      throw ArgumentError(
        'Sleep bounds must be positive and at most 24 hours.',
      );
    }
    if (dayLabelOf(recordedTime(draft.wake, draft.recordingTimezone)) !=
        draft.day) {
      throw ArgumentError('Sleep wake time must belong to the selected day.');
    }
  }
}
