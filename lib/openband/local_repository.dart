import 'dart:convert';
import 'dart:isolate';

import 'package:openstrap_analytics/onehz.dart' as ana;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../data/cycle_store.dart';
import '../data/db.dart';
import '../data/journal_fields.dart';
import '../data/lab_catalogue.dart';
import '../data/med_store.dart';
import '../data/nutrition_store.dart';
import '../data/nutrition_targets.dart';
import '../data/day_label.dart';
import '../data/series_codec.dart';
import '../compute/derivation_engine.dart' show kAlgoVersion;
import '../compute/nap_edits.dart';
import '../health/health_measurement_import.dart';
import '../state/app_state.dart';
import 'domain.dart';
import 'theme.dart';
import 'time.dart';

/// SQLite-backed boundary for the first OpenBand daily/sleep-correction flow.
/// All legacy Map payloads are decoded here; callers only see typed values.
class LocalOpenBandRepository implements OpenBandRepository {
  LocalOpenBandRepository(
    this.app, {
    ImportedMeasurementImporter? measurementImporter,
    Future<GlucoseSnapshot> Function()? glucoseRefresh,
    Future<void> Function()? reminderRefresh,
    Future<CycleSettings> Function()? cycleSettingsRead,
    Future<void> Function(CycleSettings)? cycleSettingsSave,
    Future<void> Function()? cycleContextRefresh,
  })  : _measurementImporter = measurementImporter,
        _glucoseRefresh = glucoseRefresh,
        _reminderRefresh = reminderRefresh,
        _cycleSettingsRead = cycleSettingsRead,
        _cycleSettingsSave = cycleSettingsSave,
        _cycleContextRefresh = cycleContextRefresh;

  final AppState app;
  final ImportedMeasurementImporter? _measurementImporter;
  final Future<GlucoseSnapshot> Function()? _glucoseRefresh;
  final Future<void> Function()? _reminderRefresh;
  final Future<CycleSettings> Function()? _cycleSettingsRead;
  final Future<void> Function(CycleSettings)? _cycleSettingsSave;
  final Future<void> Function()? _cycleContextRefresh;

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

    final db = await LocalDb.instance;
    final snapshot = await db.transaction((txn) async {
      final selectedRows = await txn.rawQuery(
        'SELECT day_id, skipped, partial, algo_version, computed_at, '
        'rhr, rmssd, payload_json, source '
        'FROM day_result '
        'WHERE day_id = ? AND algo_version <= ? '
        'ORDER BY algo_version DESC LIMIT 1',
        [day, kAlgoVersion],
      );
      final sleepRows = await txn.rawQuery(
        'SELECT c.day_id AS day_id, '
        'c.correction_id AS correction_id, '
        'c.revision AS revision, '
        'c.action AS action, '
        'c.onset_ms AS onset_ms, '
        'c.wake_ms AS wake_ms, '
        'c.saved_at AS saved_at, '
        'c.recording_timezone AS recording_timezone, '
        'j.correction_id AS job_correction_id, '
        'j.revision AS job_revision, '
        'j.status AS status, '
        'j.error AS error, '
        'j.result_algo_version AS result_algo_version, '
        'j.result_computed_at AS result_computed_at '
        'FROM openband_sleep_correction c '
        'LEFT JOIN openband_calculation_job j '
        'ON j.day_id = c.day_id '
        'AND j.correction_id = c.correction_id '
        'AND j.revision = c.revision '
        'WHERE c.day_id = ?',
        [day],
      );
      final napRows = await txn.query(
        'nap_recalc_job',
        where: 'day_id = ?',
        whereArgs: [day],
        limit: 1,
      );
      return (
        selected: selectedRows.isEmpty
            ? null
            : Map<String, Object?>.from(selectedRows.first),
        sleep: sleepRows,
        nap: napRows,
      );
    });
    final row = snapshot.selected;
    final payload = _payload(row?['payload_json']);
    // Unreadable payload fails the whole day. Cards never see
    // NightScalarState.unreadable; typed detail still reports that gap.
    if (row != null && payload == null) {
      throw const FormatException('Stored day result is unreadable.');
    }
    NightScalarJob? sleepJob;
    if (snapshot.sleep.isNotEmpty) {
      sleepJob = nightScalarSleepJobFromRow(
        Map<String, Object?>.from(snapshot.sleep.first),
      );
    }
    NightScalarJob? napJob;
    if (snapshot.nap.isNotEmpty) {
      napJob = nightScalarNapJobFromRow(
        Map<String, Object?>.from(snapshot.nap.first),
      );
    }
    NightScalarRow? selectedRow;
    if (row != null) {
      selectedRow = NightScalarRow(
        day: day,
        algoVersion: (row['algo_version'] as num?)?.toInt(),
        skipped: row['skipped'] == 1,
        partial: row['partial'] == 1,
        computedAtMs: (row['computed_at'] as num?)?.toInt(),
        imported: nightScalarJsonTrue(_at(payload, 'imported')),
        source: nightScalarLabel(_at(payload, 'source')),
        rowSource: nightScalarLabel(row['source']),
        sleepSource: nightScalarLabel(_at(payload, 'sleep_source')),
        windowStartMs: nightScalarMillis(
          _numAt(payload, 'sleep.window.value.onset_ms'),
        ),
        windowEndMs: nightScalarMillis(
          _numAt(payload, 'sleep.window.value.offset_ms'),
        ),
      );
    }
    final overlay = nightScalarJobsOverlay(
      sleep: sleepJob,
      nap: napJob,
      row: selectedRow,
      storedAlgo: selectedRow?.algoVersion,
      storedComputedAt: selectedRow?.computedAtMs,
    );
    DayMetric nightCard(
      Object? sqlScalar,
      String baselineRoot, {
      NightScalarUnit? unit,
      bool allowBaseline = true,
    }) {
      final stored = allowBaseline
          ? nightScalarBaseline(
              value: _numAt(payload, 'baselines.$baselineRoot.baseline'),
              status: _stringAt(payload, 'baselines.$baselineRoot.status'),
              nValid: _at(payload, 'baselines.$baselineRoot.n_valid'),
              nightsSinceUpdate: _at(
                payload,
                'baselines.$baselineRoot.nights_since_update',
              ),
              note: _stringAt(payload, 'baselines.$baselineRoot.note'),
            )
          : null;
      final value = nightScalarFinite(sqlScalar);
      return dayMetricFromNightScalar(
        state: nightScalarPublishedState(
          overlay: overlay,
          selected: selectedRow,
          currentAlgo: kAlgoVersion,
          value: value,
        ),
        value: value,
        baseline: stored,
        unit: unit,
      );
    }

    // Legacy day readers stay outside the snapshot. Cards already have SQL
    // rmssd/rhr from the selected row; getDayHrv/getDayHeart envelopes are
    // a different source and are not consulted for those scalars.
    final values = await Future.wait<Map<String, dynamic>>([
      row == null ? Future.value({}) : repository.getDaySleep(day),
      row == null ? Future.value({}) : repository.getDayHeart(day),
      row == null ? Future.value({}) : repository.getDayStrain(day),
      repository.getDaySteps(day),
    ]);
    final sleepMap = values[0],
        heart = values[1],
        strainMap = values[2],
        stepsMap = values[3];
    final nutrition = rollupDay(
      day,
      await NutritionDb.entriesForDay(db, day),
      today: todayLabel(),
    );
    final journal = await repository.getJournalMetrics(day);
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
    String? recordingTimezone;
    Map<String, dynamic>? correctionRow;
    if (snapshot.sleep.isNotEmpty) {
      correctionRow = Map<String, dynamic>.from(snapshot.sleep.first);
      recordingTimezone = nightScalarLabel(
        correctionRow['recording_timezone'],
      );
    }

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
      hrv: nightCard(row?['rmssd'], 'hrv'),
      restingHr: nightCard(row?['rhr'], 'resting_hr'),
      respiration: nightCard(_numAt(payload, 'scalars.resp_rate'), 'resp'),
      skinTemperature: nightCard(
        _numAt(payload, 'scalars.skin_temp_z'),
        'skin_temp',
        allowBaseline: false,
        unit: selectedRow == null
            ? null
            : nightScalarSkinTemperatureUnit(
                resultSource: selectedRow.rowSource,
                payloadSource: selectedRow.source,
                imported: selectedRow.imported,
              ),
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
    // Persistence lands before activation; success is not advertised on
    // rollback.
    if (template.exercises.isEmpty) {
      throw ArgumentError('Eine Vorlage braucht Namen und eine Übung.');
    }
    final snapshot = WorkoutTemplate.fromJson(template.toJson());
    try {
      return await app.startDurableStrengthWorkout(
        templateId: snapshot.id,
        templateVersion: snapshot.version,
        planJson: jsonEncode(snapshot.toJson()),
      );
    } on StateError catch (e) {
      if (e.message == 'Eine Einheit läuft bereits.') {
        throw const WorkoutBusy();
      }
      rethrow;
    }
  }

  @override
  Future<void> recordSet(String sessionId, RecordedSet set) async {
    await LocalDb.recordOpenBandStrengthSet(
      sessionId: sessionId,
      exerciseKey: set.exerciseKey,
      setIndex: set.setIndex,
      reps: set.reps,
      holdSec: set.seconds,
      loadKg: set.loadKg,
      atTs: set.at.millisecondsSinceEpoch ~/ 1000,
      plannedSetId: set.plannedSetId,
      exerciseId: set.exerciseId,
      restSec: set.restSec,
      loadJson: set.load == null ? null : jsonEncode(set.load!.toJson()),
      definitionJson: set.definition == null
          ? null
          : jsonEncode(set.definition!.toJson()),
    );
  }

  @override
  Future<void> skipPlannedSet(String sessionId, String plannedSetId) =>
      LocalDb.skipOpenBandPlannedSet(sessionId, plannedSetId);

  @override
  Future<void> addPlannedSet(
    String sessionId,
    PlannedExercise exercise,
    PlannedSet set,
  ) => LocalDb.addOpenBandPlannedSet(
    sessionId: sessionId,
    exercise: exercise.toJson(),
    set: set.toJson(),
  );

  @override
  Future<void> skipRest(String sessionId) =>
      LocalDb.skipOpenBandRest(sessionId);

  @override
  Future<void> extendRest(String sessionId, {int seconds = 30}) =>
      LocalDb.extendOpenBandRest(sessionId, seconds: seconds);

  @override
  Future<ActiveStrengthRuntime> readActiveStrengthSession() async {
    final live = await LocalDb.liveSessions();
    if (live.isEmpty) return const NoActiveStrength();
    for (final row in live) {
      final type = row['type'] as String? ?? '';
      final id = row['id'] as String?;
      if (id == null) continue;
      final snap = await LocalDb.openBandStrengthSession(id);
      if (snap != null) {
        final sets = await LocalDb.strengthSets(id);
        return _decodeActiveStrength(row, snap, sets);
      }
      if (type == 'weight_training') {
        return LegacyActiveStrength(id);
      }
    }
    return const NoActiveStrength();
  }

  @override
  Future<Map<String, RecordedSet>> readPreviousStrengthSets(
    String sessionId,
  ) async {
    final snap = await LocalDb.openBandStrengthSession(sessionId);
    final row = await LocalDb.session(sessionId);
    final startTs = (row?['start_ts'] as num?)?.toInt();
    if (snap == null || startTs == null) {
      throw ArgumentError.value(sessionId, 'sessionId');
    }
    final planJson = snap['plan_json'];
    if (planJson is! String) {
      throw const FormatException('Strength plan snapshot is unreadable.');
    }
    final plan = WorkoutTemplate.fromJson(
      jsonDecode(planJson) as Map<String, dynamic>,
    );
    final added = _addedExercises(snap['added_json']);
    final slots = strengthPlanSlots(plan, added);
    final keys = [for (final s in slots) s.exerciseKey];
    final rows = await LocalDb.completedStrengthSetsBefore(
      beforeStartTs: startTs,
      excludeSessionId: sessionId,
      exerciseKeys: keys,
    );
    final latestSession = <String, String>{};
    final latestByExercise = <String, List<RecordedSet>>{};
    for (final prior in rows) {
      final key = prior['exercise_key'] as String? ?? '';
      if (key.isEmpty) continue;
      final sid = prior['prior_session_id'] as String;
      final seen = latestSession[key];
      if (seen == null) {
        latestSession[key] = sid;
      } else if (seen != sid) {
        continue;
      }
      try {
        (latestByExercise[key] ??= []).add(_recordedFromRow(prior));
      } on FormatException {
        continue;
      }
    }
    return previousStrengthSetsFromLatest(
      slots: slots,
      latestByExercise: latestByExercise,
    );
  }

  @override
  Future<void> finishStrengthSession(String sessionId) async {
    final snap = await LocalDb.openBandStrengthSession(sessionId);
    if (snap == null) {
      throw StateError('Diese Einheit läuft nicht mehr.');
    }
    if (app.activeWorkout?.workoutId != sessionId) {
      try {
        await app.adoptLiveSession(sessionId);
      } on StateError catch (e) {
        if (e.message == 'Eine Einheit läuft bereits.') {
          throw const WorkoutBusy();
        }
        rethrow;
      }
    }
    if (app.activeWorkout?.workoutId != sessionId) {
      throw StateError('Diese Einheit läuft nicht mehr.');
    }
    await app.stopWorkout();
  }

  ActiveStrengthRuntime _decodeActiveStrength(
    Map<String, dynamic> sessionRow,
    Map<String, dynamic> snap,
    List<Map<String, Object?>> setRows,
  ) {
    final id = sessionRow['id'] as String;
    try {
      final plan = WorkoutTemplate.fromJson(
        jsonDecode(snap['plan_json'] as String) as Map<String, dynamic>,
      );
      final added = _addedExercises(snap['added_json']);
      final skipped = _stringSet(snap['skipped_json']);
      final startTs = (sessionRow['start_ts'] as num?)?.toInt();
      if (startTs == null) return CorruptActiveStrength(id);
      final restUntilTs = (snap['rest_until_ts'] as num?)?.toInt();
      return ActiveStrengthSession(
        sessionId: id,
        plan: plan,
        recorded: [for (final row in setRows) _recordedFromRow(row)],
        skippedPlannedSetIds: skipped,
        added: added,
        startedAt: DateTime.fromMillisecondsSinceEpoch(startTs * 1000),
        restEndsAt: restUntilTs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(restUntilTs * 1000),
      );
    } catch (_) {
      return CorruptActiveStrength(id);
    }
  }

  static RecordedSet _recordedFromRow(Map<String, Object?> row) {
    final atTs = (row['at_ts'] as num?)?.toInt();
    final exerciseKey = row['exercise_key'] as String? ?? '';
    if (atTs == null || exerciseKey.isEmpty) {
      throw const FormatException('Recorded set is unreadable.');
    }
    return RecordedSet(
      exerciseKey: exerciseKey,
      setIndex: (row['set_index'] as num?)?.toInt() ?? 0,
      reps: (row['reps'] as num?)?.toInt(),
      seconds: (row['hold_sec'] as num?)?.toInt(),
      loadKg: (row['load_kg'] as num?)?.toDouble(),
      at: DateTime.fromMillisecondsSinceEpoch(atTs * 1000),
      plannedSetId: row['planned_set_id'] as String?,
      exerciseId: row['exercise_id'] as String?,
      restSec: (row['rest_sec'] as num?)?.toInt(),
      load: _loadFromRow(row['load_json']),
      definition: _definitionFromRow(row['definition_json'], exerciseKey),
    );
  }

  static OriginalLoadInput? _loadFromRow(Object? raw) {
    if (raw == null) return null;
    if (raw is! String || raw.isEmpty) {
      throw const FormatException('Recorded set is unreadable.');
    }
    return OriginalLoadInput.decode(raw);
  }

  static ExerciseDefinitionSnapshot? _definitionFromRow(
    Object? raw,
    String exerciseKey,
  ) {
    if (raw == null) return null;
    if (raw is! String || raw.isEmpty) {
      throw const FormatException('Recorded set is unreadable.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Exercise definition snapshot is unreadable.');
    }
    final snap = ExerciseDefinitionSnapshot.fromJson(
      Map<String, dynamic>.from(decoded),
    );
    if (snap.id != exerciseKey) {
      throw const FormatException('Exercise definition snapshot is unreadable.');
    }
    return snap;
  }

  static Set<String> _stringSet(Object? raw) {
    if (raw is! String) {
      throw const FormatException('Strength skipped snapshot is unreadable.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Strength skipped snapshot is unreadable.');
    }
    final out = <String>{};
    for (final v in decoded) {
      if (v is! String || v.isEmpty) {
        throw const FormatException('Strength skipped snapshot is unreadable.');
      }
      out.add(v);
    }
    return out;
  }

  static List<PlannedExercise> _addedExercises(Object? raw) {
    if (raw is! String) {
      throw const FormatException('Strength added snapshot is unreadable.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Strength added snapshot is unreadable.');
    }
    return [
      for (final e in decoded)
        PlannedExercise.fromJson(e as Map<String, dynamic>),
    ];
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
  Future<ExerciseCatalogue> readExerciseCatalogue() async =>
      assembleExerciseCatalogue(await LocalDb.exerciseDefRows());

  @override
  Future<CustomExerciseWriteResult> createCustomExercise(
    CustomExerciseDraft draft,
  ) => LocalDb.createCustomExercise(draft);

  @override
  Future<CustomExerciseWriteResult> updateCustomExercise({
    required ExerciseDefinitionSnapshot expected,
    required CustomExerciseDraft draft,
  }) => LocalDb.updateCustomExercise(expected: expected, draft: draft);

  @override
  Future<List<FoodHit>> searchFoods(String query) async {
    final db = await LocalDb.instance;
    return [
      for (final r in await NutritionDb.searchFoods(db, query))
        FoodHit.fromDef(r),
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
  Future<void> archiveTemplate(String id) async {
    await LocalDb.archiveOpenBandTemplate(id);
  }

  @override
  Future<String?> readPinnedTemplateId() async =>
      LocalDb.openBandPinnedTemplateId();

  @override
  Future<void> pinTemplate(String? id) async {
    await LocalDb.putOpenBandPinnedTemplate(
      id == null || id.isEmpty ? null : id,
    );
  }

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
      entries: [for (final e in rollup.entries) MealEntry.fromFood(e)],
      kcal: sum(rollup.kcal),
      proteinG: sum(rollup.protein),
      carbsG: sum(rollup.carbs),
      fatG: sum(rollup.fat),
    );
  }

  @override
  Future<NutritionWindow> readNutritionWindow(
    String endDay, {
    int days = 7,
  }) async {
    _requireDay(endDay);
    if (days < 1) {
      throw ArgumentError.value(days, 'days', 'Window length must be at least 1.');
    }
    final labels = openBandDaysEnding(endDay, days);
    final db = await LocalDb.instance;
    final byDay = await NutritionDb.entriesSince(db, labels.first);
    final today = todayLabel();
    return NutritionWindow([
      for (final label in labels)
        rollupDay(label, byDay[label] ?? const [], today: today),
    ]);
  }

  @override
  Future<List<FoodEntry>> readRecentFoods({int limit = 12}) async {
    final db = await LocalDb.instance;
    return NutritionDb.recent(db, limit: limit);
  }

  @override
  Future<FoodSnapshotResult> readFoodEntry(String id) async {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Food id is required.');
    }
    final current = await LocalDb.openBandFoodEntry(id);
    if (current == null) return const FoodSnapshotResult.conflict();
    return FoodSnapshotResult.saved(current);
  }

  @override
  Future<FoodSnapshotResult> saveFoodEntry(
    FoodEntry expected,
    FoodEntry next,
  ) async {
    if (next.id != expected.id) {
      throw ArgumentError.value(next.id, 'id', 'Edited snapshot id must match.');
    }
    requireFoodEntryWrite(next);
    final result = await LocalDb.saveOpenBandFoodEntryIfUnchanged(
      expected: expected,
      next: next,
    );
    return result.conflict
        ? FoodSnapshotResult.conflict(result.current)
        : FoodSnapshotResult.saved(result.current);
  }

  @override
  Future<FoodSnapshotResult> removeFoodEntry(FoodEntry expected) async {
    if (expected.id.trim().isEmpty) {
      throw ArgumentError.value(expected.id, 'id', 'Food id is required.');
    }
    final result = await LocalDb.deleteOpenBandFoodEntryIfUnchanged(expected);
    return result.conflict
        ? FoodSnapshotResult.conflict(result.current)
        : FoodSnapshotResult.saved(result.current);
  }

  @override
  Future<FoodSnapshotResult> restoreFoodEntry(FoodEntry snapshot) async {
    requireFoodEntryWrite(snapshot);
    final result = await LocalDb.restoreOpenBandFoodEntry(snapshot);
    return result.conflict
        ? FoodSnapshotResult.conflict(result.current)
        : FoodSnapshotResult.saved(result.current);
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
  Future<void> saveMealDraft(MealDraft draft) {
    _requireDay(draft.day);
    if (draft.id.trim().isEmpty) {
      throw ArgumentError.value(draft.id, 'id', 'Draft id is required.');
    }
    if (draft.meal.trim().isEmpty) {
      throw ArgumentError.value(draft.meal, 'meal', 'Meal is required.');
    }
    for (final entry in draft.entries) {
      requireFoodEntryWrite(foodEntryFromDraft(draft, entry));
    }
    return LocalDb.putOpenBandMealDraft({
      'draft_id': draft.id,
      'day_id': draft.day,
      'meal': draft.meal,
      'entries_json': jsonEncode([for (final e in draft.entries) e.toJson()]),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<MealDraftSaveResult> compareAndSaveMealDraft({
    required MealDraft? expected,
    required MealDraft draft,
  }) async {
    requireMealDraftCompare(expected: expected, draft: draft);
    final saved = await LocalDb.compareAndSaveOpenBandMealDraft(
      row: {
        'draft_id': draft.id,
        'day_id': draft.day,
        'meal': draft.meal,
        'entries_json': jsonEncode([
          for (final e in draft.entries) e.toJson(),
        ]),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      expected: expected == null
          ? null
          : {
              'draft_id': expected.id,
              'day_id': expected.day,
              'meal': expected.meal,
              'entries_json': jsonEncode([
                for (final e in expected.entries) e.toJson(),
              ]),
              'updated_at': expected.updatedAt.millisecondsSinceEpoch,
            },
    );
    return saved ? MealDraftSaveResult.saved : MealDraftSaveResult.conflict;
  }

  @override
  Future<void> discardMealDraft(String draftId) =>
      LocalDb.deleteOpenBandMealDraft(draftId);

  @override
  Future<MealDraftCommitResult> commitMealDraft(MealDraft draft) async {
    _requireDay(draft.day);
    if (draft.id.trim().isEmpty) {
      throw ArgumentError.value(draft.id, 'id', 'Draft id is required.');
    }
    if (draft.entries.isEmpty) {
      throw ArgumentError('Ein leerer Entwurf wird nicht gespeichert.');
    }
    final entries = [
      for (final e in draft.entries) foodEntryFromDraft(draft, e),
    ];
    for (final entry in entries) {
      requireFoodEntryWrite(entry);
    }
    final result = await LocalDb.commitOpenBandMealDraft(
      draftId: draft.id,
      entries: entries,
      expectedEntries: [for (final e in draft.entries) e.toJson()],
      expectedDay: draft.day,
      expectedMeal: draft.meal,
    );
    return result.conflict
        ? MealDraftCommitResult.conflict
        : MealDraftCommitResult.saved;
  }

  @override
  Future<SessionDetail?> readSessionDetail(String sessionId) async {
    final stored = await LocalDb.openBandSessionDetail(sessionId);
    if (stored != null) {
      return SessionDetail.fromJson(
        jsonDecode(stored['payload_json'] as String) as Map<String, dynamic>,
      );
    }
    final row = await LocalDb.session(sessionId);
    if (row == null) return null;
    if (row['status'] == 'live') return null;
    final repository = app.repo;
    final workout = repository == null
        ? null
        : await repository.getWorkout(sessionId);
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
      avgHr: (workout?['avg_hr'] as num?)?.toDouble() ??
          (row['avg_hr'] as num?)?.toDouble(),
      maxHr: (workout?['max_hr'] as num?)?.toInt() ??
          (row['max_hr'] as num?)?.toInt(),
      strain: (row['strain'] as num?)?.toDouble(),
      kcal: (row['calories'] as num?)?.toDouble(),
      hrCoveredSec: (row['hr_covered_sec'] as num?)?.toInt(),
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
  Future<CaffeineSleepPattern> readCaffeineSleepPattern(
    String endDay,
    int nights,
  ) async {
    _requireDay(endDay);
    if (nights < 1) {
      throw ArgumentError.value(nights, 'nights', 'Expected at least 1 night.');
    }
    final days = openBandDaysEnding(endDay, nights + 1);
    final startDay = days.first;
    final daySet = days.toSet();
    final db = await LocalDb.instance;
    final snapshot = await db.transaction((txn) async {
      final journalRows = await txn.query(
        'journal_metric',
        columns: ['date', 'value'],
        where: 'field = ? AND date >= ? AND date <= ?',
        whereArgs: [CaffeineSleepPattern.field, startDay, endDay],
      );
      final solRows = await txn.rawQuery(
        'SELECT date, value FROM metric_series '
        'WHERE key = ? AND value IS NOT NULL '
        'AND date >= ? AND date <= ? '
        'AND date NOT IN ('
        'SELECT date FROM metric_series_version '
        'WHERE date >= ? AND date <= ? '
        "AND date IS NOT NULL AND source IS NOT NULL AND source <> 'band' "
        'UNION '
        'SELECT r.day_id FROM day_result r '
        'JOIN (SELECT day_id, MAX(algo_version) AS v FROM day_result '
        'WHERE algo_version <= ? AND day_id >= ? AND day_id <= ? '
        'GROUP BY day_id) m '
        'ON r.day_id = m.day_id AND r.algo_version = m.v '
        'WHERE r.day_id >= ? AND r.day_id <= ? '
        "AND r.day_id IS NOT NULL AND r.payload_json LIKE '%\"imported\":true%'"
        ')',
        [
          CaffeineSleepPattern.outcome,
          startDay,
          endDay,
          startDay,
          endDay,
          kAlgoVersion,
          startDay,
          endDay,
          startDay,
          endDay,
        ],
      );
      final versionRows = await txn.query(
        'metric_series_version',
        columns: ['date', 'algo_version'],
        where: 'date >= ? AND date <= ?',
        whereArgs: [startDay, endDay],
      );
      final dayRows = await txn.rawQuery(
        'SELECT day_id, skipped, partial, '
        'json_valid(payload_json) AS payload_valid, '
        'CASE WHEN json_valid(payload_json) = 1 '
        "THEN json_extract(payload_json, '\$.sleep_source') END "
        'AS sleep_source '
        'FROM day_result '
        'WHERE day_id >= ? AND day_id <= ? AND algo_version = ?',
        [startDay, endDay, kAlgoVersion],
      );
      final correctionRows = await txn.rawQuery(
        'SELECT c.day_id AS day_id, '
        'c.correction_id AS correction_id, '
        'c.revision AS revision, '
        'j.correction_id AS job_correction_id, '
        'j.revision AS job_revision, '
        'j.status AS status, '
        'j.result_algo_version AS result_algo_version, '
        'j.result_computed_at AS result_computed_at '
        'FROM openband_sleep_correction c '
        'LEFT JOIN openband_calculation_job j '
        'ON j.day_id = c.day_id '
        'AND j.correction_id = c.correction_id '
        'AND j.revision = c.revision '
        'WHERE c.day_id >= ? AND c.day_id <= ?',
        [startDay, endDay],
      );
      return (
        journalRows: journalRows,
        solRows: solRows,
        versionRows: versionRows,
        dayRows: dayRows,
        correctionRows: correctionRows,
      );
    });

    final stampAlgo = <String, int>{};
    for (final r in snapshot.versionRows) {
      final date = r['date'];
      final version = (r['algo_version'] as num?)?.toInt();
      if (date is String && version != null && daySet.contains(date)) {
        stampAlgo[date] = version;
      }
    }
    final blockedJob = <String>{};
    for (final r in snapshot.correctionRows) {
      final date = r['day_id'];
      if (date is! String || !daySet.contains(date)) continue;
      if (!_currentCompleteSleepJob(r)) blockedJob.add(date);
    }
    const knownSources = {
      'auto',
      'auto_fallback',
      'manual',
      'confirmed',
      'none',
      'rejected',
    };
    final currentDays =
        <
          String,
          ({bool skipped, bool partial, bool corrupt, String? source})
        >{};
    var partial = false;
    for (final r in snapshot.dayRows) {
      final date = r['day_id'];
      if (date is! String || !daySet.contains(date)) continue;
      final valid = r['payload_valid'] == 1;
      final source = r['sleep_source']?.toString();
      final sourceInvalid =
          valid && source != null && !knownSources.contains(source);
      if (!valid || sourceInvalid) {
        partial = true;
        currentDays[date] = (
          skipped: r['skipped'] == 1,
          partial: r['partial'] == 1,
          corrupt: true,
          source: source,
        );
        continue;
      }
      currentDays[date] = (
        skipped: r['skipped'] == 1,
        partial: r['partial'] == 1,
        corrupt: false,
        source: source,
      );
    }

    final solByDay = <String, double>{};
    for (final r in snapshot.solRows) {
      final date = r['date'];
      final value = (r['value'] as num?)?.toDouble();
      if (date is! String || !daySet.contains(date)) continue;
      if (value == null || !value.isFinite || value < 0) {
        partial = true;
        continue;
      }
      solByDay[date] = value;
    }

    bool eligible(String day) {
      if (stampAlgo[day] != kAlgoVersion) return false;
      final row = currentDays[day];
      if (row == null || row.skipped || row.partial || row.corrupt) {
        return false;
      }
      if (row.source != 'manual' && row.source != 'confirmed') return false;
      if (blockedJob.contains(day)) return false;
      return true;
    }

    final outcomes = [for (final d in days) eligible(d) ? solByDay[d] : null];
    final availableOutcomes = [
      for (var i = 1; i < days.length; i++)
        if (outcomes[i] != null) i,
    ].length;

    final caffeineByDay = <String, double>{};
    for (final r in snapshot.journalRows) {
      final date = r['date'];
      final value = (r['value'] as num?)?.toDouble();
      if (date is! String || !daySet.contains(date) || value == null) continue;
      if (value != 0.0 && value != 1.0) continue;
      caffeineByDay[date] = value;
    }

    // Omitting a stored SOL or answered night for eligibility / version /
    // correction / corrupt input is partial. Empty calendar days are not.
    for (var i = 0; i + 1 < days.length; i++) {
      if (caffeineByDay[days[i]] == null || outcomes[i + 1] != null) {
        continue;
      }
      final wake = days[i + 1];
      final row = currentDays[wake];
      final stamp = stampAlgo[wake];
      final gated =
          blockedJob.contains(wake) ||
          (stamp != null && stamp != kAlgoVersion) ||
          (row != null &&
              (row.skipped ||
                  row.partial ||
                  row.corrupt ||
                  (row.source != 'manual' && row.source != 'confirmed')));
      if (solByDay[wake] != null || gated) {
        partial = true;
        break;
      }
    }

    final journal = <Map<String, Object>>[
      for (final d in days)
        if (caffeineByDay[d] case final v?)
          {
            'date': d,
            'values': {CaffeineSleepPattern.field: v},
          },
    ];

    if (journal.isEmpty || availableOutcomes == 0) {
      return CaffeineSleepPattern.fromProducer(
        empty: true,
        binary: false,
        insufficient: true,
        meaningful: false,
        n: 0,
        endDay: endDay,
        startDay: startDay,
        nights: nights,
        algoVersion: kAlgoVersion,
        partial: partial,
        availableOutcomes: availableOutcomes,
      );
    }

    final produced = await Isolate.run(
      () => _caffeineSleepCorrelate({
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
      startDay: startDay,
      nights: nights,
      algoVersion: kAlgoVersion,
      partial: partial,
      availableOutcomes: availableOutcomes,
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
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'Journal field is required.');
    }
    if (!value.isFinite) {
      throw ArgumentError.value(
        value,
        'value',
        'Journal value must be finite.',
      );
    }
    final repository = app.repo;
    if (repository == null) {
      throw StateError('Local repository is not initialized.');
    }
    await repository.upsertJournalMetric(day, key, value);
  }

  @override
  Future<JournalDaySnapshot> readJournalDay(String day) async {
    _requireDay(day);
    final repository = app.repo;
    if (repository == null) {
      throw StateError('Local repository is not initialized.');
    }
    return repository.readJournalDay(day);
  }

  @override
  Future<void> patchJournalDay(JournalDayPatch patch) async {
    _requireDay(patch.day);
    final repository = app.repo;
    if (repository == null) {
      throw StateError('Local repository is not initialized.');
    }
    await repository.patchJournalDay(patch);
  }

  @override
  Future<double?> adjustWater(String day, double deltaMl) async {
    _requireDay(day);
    if (!deltaMl.isFinite) {
      throw ArgumentError.value(
        deltaMl,
        'deltaMl',
        'Water delta must be finite.',
      );
    }
    return LocalDb.applyJournalMetricDelta(
      date: day,
      field: 'water_ml',
      delta: deltaMl,
      max: kJournalFieldsByKey['water_ml']!.max,
    );
  }

  @override
  Future<List<JournalFieldSpec>> listJournalFields({
    bool includeHidden = false,
  }) async {
    final custom = await LocalDb.journalFieldDefs(includeHidden: includeHidden);
    return [...kJournalFields, ...custom];
  }

  @override
  Future<JournalFieldSpec> createJournalField(JournalFieldSpec spec) =>
      LocalDb.putJournalFieldDef(spec);

  @override
  Future<void> hideJournalField(String key) => LocalDb.hideJournalFieldDef(key);

  @override
  Future<void> restoreJournalField(String key) =>
      LocalDb.restoreJournalFieldDef(key);

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
    if (key == MetricKey.hrv ||
        key == MetricKey.restingHr ||
        key == MetricKey.respiration ||
        key == MetricKey.skinTemperature) {
      return nightScalarHistoryPoints(
        await readNightScalarDetail(key, endDay, nights),
      );
    }
    _requireDay(endDay);
    final days = openBandDaysEnding(endDay, nights);
    final rows = await LocalDb.metricSeries(key.series);
    final byDay = {
      for (final r in rows)
        r['date'] as String: (r['value'] as num?)?.toDouble(),
    };
    return [for (final d in days) MetricPoint(d, byDay[d])];
  }

  @override
  Future<NightScalarDetail> readNightScalarDetail(
    MetricKey key,
    String day,
    int nights,
  ) async {
    _requireDay(day);
    final metric = nightScalarMetricOf(key);
    requireNightScalarNights(nights);
    final days = nightScalarDaysEnding(day, nights);
    final startDay = days.first;
    final sqlColumn = metric.sqlColumn;
    final baselineRoot = metric.baselinePath;
    final seriesKey = metric.series;
    final scalarKey = metric.payloadScalar;
    final db = await LocalDb.instance;
    final snapshot = await db.transaction((txn) async {
      final selectedRows = await txn.rawQuery(
        'SELECT day_id, skipped, partial, algo_version, computed_at, '
        'rhr, rmssd, payload_json, source '
        'FROM day_result '
        'WHERE day_id = ? AND algo_version <= ? '
        'ORDER BY algo_version DESC LIMIT 1',
        [day, kAlgoVersion],
      );
      final selectedMap =
          selectedRows.isEmpty ? null : Map<String, Object?>.from(selectedRows.first);
      Map<String, Object?>? selectedProjected;
      if (selectedMap != null) {
        final selectedRaw = selectedMap['payload_json'];
        final projected = await Isolate.run(
          () => projectNightScalarPayloads(
            [selectedRaw],
            baselineRoot,
            scalarKey,
          ),
        );
        final first = projected.first;
        selectedProjected =
            first == null ? null : Map<String, Object?>.from(first);
        selectedMap.remove('payload_json');
      }
      final selectedAlgo = (selectedMap?['algo_version'] as num?)?.toInt();
      final historyAnchor = selectedAlgo ?? kAlgoVersion;
      final matchingRows = <Map<String, Object?>>[];
      var offset = 0;
      while (true) {
        final batch = await txn.query(
          'day_result',
          columns: [
            'day_id',
            'skipped',
            'partial',
            'algo_version',
            'computed_at',
            ?sqlColumn,
            'payload_json',
            'source',
          ],
          where: 'day_id >= ? AND day_id <= ? AND algo_version = ?',
          whereArgs: [startDay, day, historyAnchor],
          orderBy: 'day_id ASC',
          limit: kNightScalarPayloadBatchSize,
          offset: offset,
        );
        if (batch.isEmpty) break;
        final rawPayloads = [for (final r in batch) r['payload_json']];
        final payloads = await Isolate.run(
          () => projectNightScalarPayloads(
            rawPayloads,
            baselineRoot,
            scalarKey,
          ),
        );
        for (var i = 0; i < batch.length; i++) {
          final r = Map<String, Object?>.from(batch[i])..remove('payload_json');
          final projected = i < payloads.length ? payloads[i] : null;
          r['projected'] =
              projected == null ? null : Map<String, Object?>.from(projected);
          matchingRows.add(r);
        }
        offset += batch.length;
        if (batch.length < kNightScalarPayloadBatchSize) break;
      }
      final otherRows = await txn.rawQuery(
        'SELECT DISTINCT day_id FROM day_result '
        'WHERE day_id >= ? AND day_id <= ? AND algo_version != ?',
        [startDay, day, historyAnchor],
      );
      final seriesRows = await txn.rawQuery(
        'SELECT date, value FROM metric_series '
        'WHERE key = ? AND date >= ? AND date <= ? AND value IS NOT NULL',
        [seriesKey, startDay, day],
      );
      final sleepRows = await txn.rawQuery(
        'SELECT c.day_id AS day_id, '
        'c.correction_id AS correction_id, '
        'c.revision AS revision, '
        'c.action AS action, '
        'c.onset_ms AS onset_ms, '
        'c.wake_ms AS wake_ms, '
        'c.recording_timezone AS recording_timezone, '
        'j.correction_id AS job_correction_id, '
        'j.revision AS job_revision, '
        'j.status AS status, '
        'j.result_algo_version AS result_algo_version, '
        'j.result_computed_at AS result_computed_at '
        'FROM openband_sleep_correction c '
        'LEFT JOIN openband_calculation_job j '
        'ON j.day_id = c.day_id '
        'AND j.correction_id = c.correction_id '
        'AND j.revision = c.revision '
        'WHERE c.day_id >= ? AND c.day_id <= ?',
        [startDay, day],
      );
      final napRows = await txn.rawQuery(
        'SELECT day_id, revision, status, '
        'result_algo_version, result_computed_at '
        'FROM nap_recalc_job '
        'WHERE day_id >= ? AND day_id <= ?',
        [startDay, day],
      );
      return (
        selected: selectedMap,
        selectedProjected: selectedProjected,
        matching: matchingRows,
        other: otherRows,
        series: seriesRows,
        sleep: sleepRows,
        nap: napRows,
      );
    });

    NightScalarRow rowFrom(
      Map<String, Object?> r, {
      required Object? scalar,
      Map<String, Object?>? projected,
    }) {
      final valid = projected != null;
      return NightScalarRow(
        day: r['day_id'] as String,
        algoVersion: (r['algo_version'] as num?)?.toInt(),
        skipped: r['skipped'] == 1,
        partial: r['partial'] == 1,
        payloadUnreadable: !valid,
        value: nightScalarFinite(scalar),
        computedAtMs: (r['computed_at'] as num?)?.toInt(),
        imported: valid && nightScalarJsonTrue(projected['imported']),
        source: valid ? nightScalarLabel(projected['source']) : null,
        rowSource: nightScalarLabel(r['source']),
        sleepSource: valid ? nightScalarLabel(projected['sleep_source']) : null,
        deviceFamily: valid ? nightScalarLabel(projected['device_family']) : null,
        baseline: valid
            ? nightScalarBaseline(
                value: projected['baseline_value'],
                status: projected['baseline_status'],
                nValid: projected['baseline_n_valid'],
                nightsSinceUpdate: projected['baseline_nights_since_update'],
                note: projected['baseline_note'],
              )
            : null,
        windowStartMs: valid ? nightScalarMillis(projected['onset_ms']) : null,
        windowEndMs: valid ? nightScalarMillis(projected['offset_ms']) : null,
        envelope: valid && metric == NightScalarMetric.respiration
            ? nightScalarEnvelope(projected['envelope'])
            : null,
      );
    }

    Object? selectedScalar(Map<String, Object?> r, Map<String, Object?>? projected) {
      if (sqlColumn != null) return r[sqlColumn];
      return projected?['scalar'];
    }

    final selected = snapshot.selected == null
        ? null
        : rowFrom(
            snapshot.selected!,
            scalar: selectedScalar(
              snapshot.selected!,
              snapshot.selectedProjected,
            ),
            projected: snapshot.selectedProjected,
          );
    final matching = <String, NightScalarRow>{
      for (final r in snapshot.matching)
        if (r['day_id'] is String)
          r['day_id'] as String: rowFrom(
            r,
            scalar: selectedScalar(
              r,
              r['projected'] as Map<String, Object?>?,
            ),
            projected: r['projected'] as Map<String, Object?>?,
          ),
    };
    final matchingDays = matching.keys.toSet();
    final otherVersionDays = {
      for (final r in snapshot.other)
        if (r['day_id'] is String && !matchingDays.contains(r['day_id']))
          r['day_id'] as String,
    };
    final seriesOnlyDays = {
      for (final r in snapshot.series)
        if (r['date'] is String &&
            nightScalarFinite(r['value']) != null &&
            !matchingDays.contains(r['date']) &&
            !otherVersionDays.contains(r['date']))
          r['date'] as String,
    };
    final sleepJobs = <String, NightScalarJob>{
      for (final r in snapshot.sleep)
        if (r['day_id'] is String)
          r['day_id'] as String: nightScalarSleepJobFromRow(
            Map<String, Object?>.from(r),
          ),
    };
    final napJobs = <String, NightScalarJob>{
      for (final r in snapshot.nap)
        if (r['day_id'] is String)
          r['day_id'] as String: nightScalarNapJobFromRow(
            Map<String, Object?>.from(r),
          ),
    };
    String? recordingTimezone;
    for (final r in snapshot.sleep) {
      if (r['day_id'] == day) {
        recordingTimezone = nightScalarLabel(r['recording_timezone']);
        break;
      }
    }
    return buildNightScalarDetail(
      day: day,
      key: metric,
      nights: nights,
      currentAlgo: kAlgoVersion,
      days: days,
      selected: selected,
      matching: matching,
      otherVersionDays: otherVersionDays,
      seriesOnlyDays: seriesOnlyDays,
      sleepJobs: sleepJobs,
      napJobs: napJobs,
      recordingTimezone: recordingTimezone,
    );
  }

  @override
  Future<SetupEvaluation> readSetupEvaluation(String day) async {
    _requireDay(day);
    final row = await LocalDb.dayResult(day);
    final sleepJob = await LocalDb.openBandSleepCorrection(day);
    final napJob = await LocalDb.napRecalcJob(day);
    final storedAlgo = (row?['algo_version'] as num?)?.toInt();
    final computedAtMs = (row?['computed_at'] as num?)?.toInt();
    final computedAt = _computedAt(computedAtMs);

    var state = SetupEvalState.missing;
    if (row != null) {
      if (storedAlgo == null) {
        throw const FormatException('Stored day result is unreadable.');
      }
      if (storedAlgo != kAlgoVersion) {
        state = SetupEvalState.stale;
      } else if (row['skipped'] == 1) {
        state = SetupEvalState.unavailable;
      } else if (row['partial'] == 1) {
        state = SetupEvalState.partial;
      } else {
        if (_payload(row['payload_json']) == null || computedAt == null) {
          throw const FormatException('Stored day result is unreadable.');
        }
        state = SetupEvalState.complete;
      }
    }

    final jobState = _jobOutcome(sleepJob);
    final napState = _jobOutcome(napJob);
    if (jobState == SetupEvalState.failed ||
        napState == SetupEvalState.failed) {
      state = SetupEvalState.failed;
    } else if (jobState == SetupEvalState.pending ||
        napState == SetupEvalState.pending) {
      state = SetupEvalState.pending;
    }

    return SetupEvaluation(
      day: day,
      currentAlgo: kAlgoVersion,
      storedAlgo: storedAlgo,
      computedAt: state == SetupEvalState.complete ? computedAt : null,
      state: state,
    );
  }

  /// Same overlay as [readDay]: the current-revision sleep/nap job status
  /// is the outcome. A later unrelated [LocalDb.putDayResult] cannot dismiss
  /// pending or failed.
  static SetupEvalState? _jobOutcome(Map<String, dynamic>? job) {
    if (job == null) return null;
    final status = job['status']?.toString();
    if (status == 'complete') return null;
    if (status == 'failed') return SetupEvalState.failed;
    return SetupEvalState.pending;
  }

  /// A stored SOL is current only when the matching job receipt is complete at
  /// this build's algo, with a computed timestamp. Missing job, revision
  /// mismatch, or complete-without-receipt is unknown recalculation state.
  static bool _currentCompleteSleepJob(Map<String, dynamic> row) {
    final jobId = row['job_correction_id']?.toString();
    final correctionId = row['correction_id']?.toString();
    final jobRev = (row['job_revision'] as num?)?.toInt();
    final corrRev = (row['revision'] as num?)?.toInt();
    final status = row['status']?.toString();
    final resultAlgo = (row['result_algo_version'] as num?)?.toInt();
    final resultAt = (row['result_computed_at'] as num?)?.toInt();
    return jobId != null &&
        jobId == correctionId &&
        jobRev != null &&
        jobRev == corrRev &&
        status == 'complete' &&
        resultAlgo == kAlgoVersion &&
        resultAt != null &&
        resultAt > 0;
  }

  static DateTime? _computedAt(int? ms) {
    if (ms == null || ms <= 0 || ms.abs() > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
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
  Future<SleepPlanSnapshot> readSleepPlan(String day, {DateTime? now}) async {
    _requireDay(day);
    final clock = now ?? DateTime.now();
    final today = todayLabel(clock);
    if (day != today) {
      return SleepPlanSnapshot.unavailable(day, today);
    }
    final db = await LocalDb.instance;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'baselines',
        where: 'key = ?',
        whereArgs: ['crossday'],
        limit: 1,
      );
      Map<String, dynamic>? artifact;
      var unreadable = false;
      if (rows.isEmpty) {
        artifact = null;
      } else {
        final raw = rows.first['payload_json'];
        if (raw is! String || raw.isEmpty) {
          unreadable = true;
        } else {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map<String, dynamic>) {
              artifact = decoded;
            } else if (decoded is Map) {
              artifact = decoded.cast<String, dynamic>();
            } else {
              unreadable = true;
            }
          } on FormatException {
            unreadable = true;
          }
        }
      }
      final window = sleepPlanContributingDays(artifact, planDay: today);
      final observations = await _sleepPlanObservations(txn, window ?? const []);
      final fetchDays = [
        for (final row in observations)
          if (row.inFetchWindow) row.day,
      ];
      final sleepDays = <String>{
        ...?window,
        ...fetchDays,
      }.toList();
      final jobs = await _sleepPlanJobs(
        txn,
        sleepDays: sleepDays,
        napDay: today,
      );
      return sleepPlanFromStoredCrossday(
        requestedDay: day,
        now: clock,
        algoVersion: kAlgoVersion,
        artifact: artifact,
        unreadable: unreadable,
        jobs: jobs,
        contributingDays: window,
        observations: observations,
      );
    });
  }

  Future<List<SleepPlanDayObservation>> _sleepPlanObservations(
    DatabaseExecutor txn,
    List<String> contributing,
  ) async {
    const servedJoin =
        'JOIN (SELECT day_id, MAX(algo_version) AS v FROM day_result '
        'WHERE algo_version <= ? GROUP BY day_id) m '
        'ON r.day_id = m.day_id AND r.algo_version = m.v';
    const columns = 'SELECT r.day_id, r.computed_at, r.skipped FROM day_result r ';
    final fetch = await txn.rawQuery(
      '$columns $servedJoin ORDER BY r.day_id DESC LIMIT ?',
      [kAlgoVersion, kSleepPlanProducerFetchLimit],
    );
    final byDay = <String, SleepPlanDayObservation>{};
    void add(Map<String, Object?> row, {required bool inFetchWindow}) {
      final dayId = row['day_id'];
      if (dayId is! String || dayId.isEmpty) return;
      final prev = byDay[dayId];
      byDay[dayId] = SleepPlanDayObservation(
        day: dayId,
        computedAtMs: sleepPlanMillis(row['computed_at']),
        skipped: (row['skipped'] as num?)?.toInt() == 1,
        inFetchWindow: inFetchWindow || (prev?.inFetchWindow ?? false),
      );
    }

    for (final row in fetch) {
      add(row, inFetchWindow: true);
    }
    final extra = [
      for (final day in contributing)
        if (!byDay.containsKey(day)) day,
    ];
    if (extra.isNotEmpty) {
      final placeholders = List.filled(extra.length, '?').join(',');
      final rows = await txn.rawQuery(
        '$columns $servedJoin WHERE r.day_id IN ($placeholders)',
        [kAlgoVersion, ...extra],
      );
      for (final row in rows) {
        add(row, inFetchWindow: false);
      }
    }
    return byDay.values.toList();
  }

  Future<List<SleepPlanInputJob>> _sleepPlanJobs(
    DatabaseExecutor txn, {
    required List<String> sleepDays,
    required String napDay,
  }) async {
    final jobs = <SleepPlanInputJob>[];
    if (sleepDays.isNotEmpty) {
      final placeholders = List.filled(sleepDays.length, '?').join(',');
      final corrections = await txn.rawQuery(
        'SELECT c.day_id AS day_id, j.status AS status, '
        'j.result_computed_at AS result_computed_at '
        'FROM openband_sleep_correction c '
        'LEFT JOIN openband_calculation_job j ON j.day_id = c.day_id '
        'AND j.correction_id = c.correction_id AND j.revision = c.revision '
        'WHERE c.day_id IN ($placeholders)',
        sleepDays,
      );
      final allowed = sleepDays.toSet();
      for (final row in corrections) {
        final dayId = row['day_id'];
        if (dayId is! String || !allowed.contains(dayId)) continue;
        jobs.add(
          SleepPlanInputJob(
            day: dayId,
            kind: SleepPlanJobKind.sleepCorrection,
            status: row['status']?.toString() ?? 'pending',
            resultComputedAtMs: sleepPlanMillis(row['result_computed_at']),
          ),
        );
      }
    }
    final naps = await txn.query(
      'nap_recalc_job',
      columns: ['day_id', 'status', 'result_computed_at'],
      where: 'day_id = ?',
      whereArgs: [napDay],
    );
    for (final row in naps) {
      final dayId = row['day_id'];
      if (dayId is! String || dayId != napDay) continue;
      jobs.add(
        SleepPlanInputJob(
          day: dayId,
          kind: SleepPlanJobKind.napRecalc,
          status: row['status']?.toString() ?? 'pending',
          resultComputedAtMs: sleepPlanMillis(row['result_computed_at']),
        ),
      );
    }
    return jobs;
  }

  @override
  Future<NutritionTargetSnapshot> readNutritionTargets(String day) async {
    _requireDay(day);
    final applied = await LocalDb.nutritionTargetPeriodAsOf(day);
    if (applied != null) {
      final effectiveDay = applied['valid_from_day'] as String;
      return NutritionTargetSnapshot(
        day: day,
        values: _nutritionValues(applied),
        origin: NutritionTargetOrigin.dated,
        effectiveDay: effectiveDay,
        revision: effectiveDay == day
            ? (applied['revision'] as num).toInt()
            : null,
      );
    }
    if (day != todayLabel()) {
      return NutritionTargetSnapshot(day: day);
    }
    final legacy = _legacyUndatedValues(await _legacyProfileMap());
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
    final rows = await LocalDb.nutritionTargetPeriods();
    return [for (final row in rows) _nutritionChange(row)];
  }

  @override
  Future<NutritionTargetWriteResult> saveNutritionTargets(
    String day,
    NutritionTargetValues values, {
    int? expectedRevision,
  }) async {
    _requireDay(day);
    requireNutritionTargetValues(values);
    return _putNutritionTargets(
      day,
      values,
      expectedRevision: expectedRevision,
    );
  }

  @override
  Future<NutritionTargetWriteResult> clearNutritionTargets(
    String day, {
    int? expectedRevision,
  }) async {
    _requireDay(day);
    return _putNutritionTargets(
      day,
      const NutritionTargetValues(),
      expectedRevision: expectedRevision,
    );
  }

  Future<NutritionTargetWriteResult> _putNutritionTargets(
    String day,
    NutritionTargetValues values, {
    int? expectedRevision,
  }) async {
    final result = await LocalDb.putNutritionTargetPeriod(
      validFromDay: day,
      energyKcal: values.energyKcal,
      proteinG: values.proteinG,
      carbsG: values.carbohydrateG,
      fatG: values.fatG,
      expectedRevision: expectedRevision,
    );
    if (result.conflict) {
      return NutritionTargetWriteResult.conflict(
        result.row == null ? null : _nutritionChange(result.row!),
      );
    }
    return NutritionTargetWriteResult.saved(_nutritionChange(result.row!));
  }

  /// Prefs is the source blob. A present unreadable/non-map value throws
  /// [FormatException] — not [AppState.user], which can be a stale decode of
  /// an earlier good blob, and not an empty snapshot (that would claim "no
  /// targets"). Absent key may use in-memory [AppState.user]:
  /// [AppState.forTesting] never loads prefs, and production `_loadProfile`
  /// fills `user` from this same key. Never writes the blob.
  Future<Map<String, dynamic>?> _legacyProfileMap() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(kLegacyProfilePrefsKey)) return app.user;
    final raw = prefs.getString(kLegacyProfilePrefsKey);
    if (raw == null) {
      throw const FormatException('Stored nutrition profile is unreadable.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw const FormatException('Stored nutrition profile is unreadable.');
  }

  static NutritionTargetValues _legacyUndatedValues(
    Map<String, dynamic>? profile,
  ) {
    if (profile == null) return const NutritionTargetValues();
    return NutritionTargetValues(
      energyKcal: decodeOptionalEnergy(profile[kLegacyEnergyTargetKey]),
      proteinG: decodeOptionalGrams(profile[kLegacyProteinTargetKey]),
    );
  }

  static NutritionTargetValues _nutritionValues(Map<String, dynamic> row) =>
      NutritionTargetValues(
        energyKcal: decodeOptionalEnergy(row['energy_kcal']),
        proteinG: decodeOptionalGrams(row['protein_g']),
        carbohydrateG: decodeOptionalGrams(row['carbs_g']),
        fatG: decodeOptionalGrams(row['fat_g']),
      );

  static NutritionTargetChange _nutritionChange(Map<String, dynamic> row) =>
      NutritionTargetChange(
        validFromDay: row['valid_from_day'] as String,
        values: _nutritionValues(row),
        revision: (row['revision'] as num).toInt(),
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
        row != null &&
        rawPayload != null &&
        '$rawPayload'.isNotEmpty &&
        payload == null;
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
    final open = job != null && job.state != CorrectionState.complete;
    final scalars = payload?['scalars'];
    final storedTotal = scalars is Map
        ? _durationMin(scalars['nap_min'])
        : null;
    return NapDay(
      day: day,
      judged: judged,
      sessions: [
        for (final n in merged)
          ?_sessionFromMerged(n, zone, originByStart[_epochSec(n['start'])]),
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
    final deletes = [if (original.startTs != newStart) original.startTs];
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

  Future<List<NapMap>> _napWindowsOn(String day, {int? ignoringStartTs}) async {
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
        if (!(e.kind == NapEditKind.added && e.startSec == ignoringStartTs)) e,
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
      end: recordedTime(DateTime.fromMillisecondsSinceEpoch(end * 1000), zone),
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
      end: recordedTime(DateTime.fromMillisecondsSinceEpoch(end * 1000), zone),
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

  @override
  Future<LabSnapshot> readLabs() async {
    final rows = await LocalDb.labResults();
    final defs = await LocalDb.labMarkerDefs();
    return LabSnapshot(
      results: [for (final r in rows) _labDraw(r)],
      custom: [for (final d in defs) _labDef(d)],
      sex: app.user?['sex']?.toString(),
    );
  }

  @override
  Future<void> saveLabDraw(
    LabDraw draw, {
    LabDraw? replacing,
    bool replaceExisting = false,
  }) async {
    _requireLabDraw(draw);
    final from = replacing;
    if (from != null &&
        (from.marker != draw.marker || from.takenOn != draw.takenOn)) {
      try {
        await LocalDb.relocateLabResult(
          fromMarker: from.marker,
          fromTakenOn: from.takenOn,
          toMarker: draw.marker,
          toTakenOn: draw.takenOn,
          value: draw.value,
          unit: draw.unit,
          note: draw.note,
          reportLow: draw.reportLow,
          reportHigh: draw.reportHigh,
          replaceDestination: replaceExisting,
        );
      } on StateError {
        throw LabDrawCollision(draw.marker, draw.takenOn);
      }
      return;
    }
    try {
      await LocalDb.putLabResult(
        marker: draw.marker,
        takenOn: draw.takenOn,
        value: draw.value,
        unit: draw.unit,
        note: draw.note,
        reportLow: draw.reportLow,
        reportHigh: draw.reportHigh,
        replaceExisting: from != null || replaceExisting,
      );
    } on StateError {
      throw LabDrawCollision(draw.marker, draw.takenOn);
    }
  }

  @override
  Future<void> deleteLabDraw(String marker, String takenOn) =>
      LocalDb.deleteLabResult(marker, takenOn);

  @override
  Future<void> saveLabMarkerDef(LabMarkerDef def, {bool create = false}) async {
    final label = def.label.trim();
    final unit = def.unit.trim();
    if (label.isEmpty || unit.isEmpty) {
      throw ArgumentError('Marker braucht Namen und Einheit.');
    }
    if (def.decimals < 0 || def.decimals > 3) {
      throw ArgumentError('Ungültige Genauigkeit.');
    }
    if (kLabMarkersByKey.containsKey(def.key) ||
        !def.key.startsWith('custom_') ||
        def.key == 'custom_') {
      throw ArgumentError('Eingebaute Marker lassen sich nicht überschreiben.');
    }
    if (def.refLow != null &&
        def.refHigh != null &&
        def.refLow! > def.refHigh!) {
      throw ArgumentError('Untere Grenze liegt über der oberen.');
    }
    try {
      await LocalDb.putLabMarkerDef({
        'key': def.key,
        'label': label,
        'unit': unit,
        'category': def.category,
        'decimals': def.decimals,
        'ref_low': def.refLow,
        'ref_high': def.refHigh,
      }, replaceExisting: !create);
    } on StateError {
      throw LabMarkerCollision(def.key);
    }
  }

  @override
  Future<void> deleteLabMarkerDef(String key) async {
    final held = await LocalDb.labResults(marker: key);
    if (held.isNotEmpty) {
      throw StateError('lab marker still has results');
    }
    await LocalDb.deleteLabMarkerDef(key);
  }

  static LabDraw _labDraw(Map<String, Object?> row) {
    const known = {
      'marker',
      'taken_on',
      'value',
      'unit',
      'note',
      'report_low',
      'report_high',
      'updated_at',
    };
    final raw = row['value'];
    final value = raw is num ? raw.toDouble() : double.nan;
    return LabDraw(
      marker: '${row['marker'] ?? ''}',
      takenOn: '${row['taken_on'] ?? ''}',
      value: value.isFinite ? value : double.nan,
      unit: '${row['unit'] ?? ''}',
      note: '${row['note'] ?? ''}',
      reportLow: _double(row['report_low']),
      reportHigh: _double(row['report_high']),
      updatedAt: (row['updated_at'] as num?)?.toInt() ?? 0,
      extras: {
        for (final e in row.entries)
          if (!known.contains(e.key)) e.key: e.value,
      },
    );
  }

  static LabMarkerDef _labDef(Map<String, Object?> row) => LabMarkerDef(
    key: '${row['key'] ?? ''}',
    label: '${row['label'] ?? row['key'] ?? ''}',
    unit: '${row['unit'] ?? ''}',
    category: '${row['category'] ?? 'other'}',
    decimals: (row['decimals'] as num?)?.toInt() ?? 1,
    refLow: _double(row['ref_low']),
    refHigh: _double(row['ref_high']),
    createdAt: (row['created_at'] as num?)?.toInt() ?? 0,
  );

  static void _requireLabDraw(LabDraw draw) {
    if (!draw.readable) {
      throw ArgumentError('Laborwert unvollständig oder ungültig.');
    }
    if (draw.reportLow != null &&
        draw.reportHigh != null &&
        draw.reportLow! > draw.reportHigh!) {
      throw ArgumentError('Untere Grenze liegt über der oberen.');
    }
  }

  @override
  Future<GlucoseSnapshot> readGlucose({String? sourceKey, int? limit}) async {
    if (limit != null && limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'Must be at least 1.');
    }
    final read = await LocalDb.importedMeasurementGlucoseRead(
      kind: kKindGlucose,
      sourceKey: sourceKey,
      limit: limit,
    );
    return _glucoseSnapshotFromRead(read, limit: limit);
  }

  @override
  Future<GlucoseImportResult> importGlucose({DateTime? now}) async {
    final importer = _measurementImporter ?? ImportedMeasurementImporter();
    final outcome = await importer.sync(
      types: ImportedMeasurementImporter.glucoseOnly,
      now: now,
    );
    try {
      final snapshot =
          await (_glucoseRefresh ?? () => readGlucose(limit: 1))();
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
    if (sourceKey.isEmpty) {
      throw ArgumentError.value(sourceKey, 'sourceKey', 'Required.');
    }
    await LocalDb.setImportedMeasurementSourceExcluded(
      kind: kKindGlucose,
      sourceKey: sourceKey,
      excluded: !included,
    );
  }

  @override
  Future<MedicationDay> readMedicationDay(String day, {DateTime? now}) async {
    _requireDay(day);
    if (!isMedicationCalendarDay(day)) {
      throw ArgumentError.value(day, 'day', 'Invalid calendar day.');
    }
    final db = await LocalDb.instance;
    return MedDb.readDay(db, day, now: now ?? DateTime.now());
  }

  @override
  Future<List<MedicationPlan>> readMedicationPlans({
    bool activeOnly = true,
  }) async {
    final db = await LocalDb.instance;
    return MedDb.readPlans(db, activeOnly: activeOnly);
  }

  @override
  Future<MedicationHistory> readMedicationHistory(
    String fromDay,
    String toDay, {
    DateTime? now,
  }) async {
    if (!isMedicationCalendarDay(fromDay)) {
      throw ArgumentError.value(fromDay, 'fromDay', 'Invalid calendar day.');
    }
    if (!isMedicationCalendarDay(toDay)) {
      throw ArgumentError.value(toDay, 'toDay', 'Invalid calendar day.');
    }
    final db = await LocalDb.instance;
    return MedDb.readHistory(
      db,
      fromDay,
      toDay,
      now: now ?? DateTime.now(),
    );
  }

  @override
  Future<MedicationMutationResult> saveMedicationPlan(
    MedicationPlanDraft draft, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final db = await LocalDb.instance;
    final plan = await MedDb.commitPlan(db, draft, now: at);
    return _medicationWriteResult(plan: plan);
  }

  @override
  Future<MedicationMutationResult> endMedicationPlan(
    String key, {
    DateTime? now,
  }) async {
    return _setPlanActive(key, active: false, now: now);
  }

  @override
  Future<MedicationMutationResult> restartMedicationPlan(
    String key, {
    DateTime? now,
  }) async {
    return _setPlanActive(key, active: true, now: now);
  }

  @override
  Future<MedicationMutationResult> saveMedicationEntry(
    MedicationEntryDraft draft, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final db = await LocalDb.instance;
    final entry = await MedDb.markDose(db, draft, now: at);
    return _medicationWriteResult(entry: entry);
  }

  @override
  Future<void> refreshMedicationReminders() async {
    await (_reminderRefresh ?? app.refreshAiReminders)();
  }

  Future<MedicationMutationResult> _setPlanActive(
    String key, {
    required bool active,
    DateTime? now,
  }) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(key, 'key');
    }
    final at = now ?? DateTime.now();
    final db = await LocalDb.instance;
    final plan = await MedDb.setActive(
      db,
      trimmed,
      active: active,
      now: at,
    );
    return _medicationWriteResult(plan: plan);
  }

  Future<MedicationMutationResult> _medicationWriteResult({
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

  @override
  Future<CycleSettings> readCycleSettings() {
    return (_cycleSettingsRead ?? app.readCycleSettings)();
  }

  @override
  Future<CycleWriteResult> saveCycleSettings(CycleSettings settings) async {
    await (_cycleSettingsSave ?? app.saveCycleSettings)(settings);
    return _cycleWriteResult(settings: settings);
  }

  @override
  Future<CycleSnapshot> readCycle(String day, {DateTime? now}) async {
    requireCycleCalendarDay(day);
    final settings = await readCycleSettings();
    final db = await LocalDb.instance;
    return CycleStore.read(db, day: day, settings: settings);
  }

  @override
  Future<CycleMeasurementsSnapshot> readCycleMeasurements(
    String asOfDay, {
    String? cycleStartDay,
  }) async {
    requireCycleCalendarDay(asOfDay, 'asOfDay');
    if (cycleStartDay != null) {
      requireCycleCalendarDay(cycleStartDay, 'cycleStartDay');
    }
    final settings = await readCycleSettings();
    final db = await LocalDb.instance;
    final snapshot = await db.transaction((txn) async {
      final parsed = await CycleStore.load(txn, asOf: asOfDay);
      final selection = selectCycleMeasurementRange(
        asOfDay: asOfDay,
        settings: settings,
        log: parsed,
        cycleStartDay: cycleStartDay,
      );
      final visibleStart = selection.visibleStart;
      final periodEnd = selection.selected?.endDay;
      final rows = visibleStart == null || periodEnd == null
          ? const <CycleNightSourceRow>[]
          : await _readExactAlgoCycleNights(
              txn,
              startDay: visibleStart,
              endDay: periodEnd,
            );
      return (parsed: parsed, rows: rows);
    });

    return buildCycleMeasurementsSnapshot(
      asOfDay: asOfDay,
      settings: settings,
      log: snapshot.parsed,
      cycleStartDay: cycleStartDay,
      algoVersion: kAlgoVersion,
      rows: snapshot.rows,
    );
  }

  @override
  Future<CycleMediansSnapshot> readCycleMedians(
    String anchorEnd, {
    int pageOffset = 0,
    DateTime? now,
  }) async {
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
    final settings = await readCycleSettings();
    final db = await LocalDb.instance;
    final snapshot = await db.transaction((txn) async {
      final parsed = await CycleStore.load(txn, asOf: window.endDay);
      final preview = buildCycleMediansSnapshot(
        settings: settings,
        log: parsed,
        algoVersion: kAlgoVersion,
        window: window,
      );
      if (!_cycleMediansNeedsNightRows(preview)) {
        return (parsed: parsed, rows: const <CycleNightSourceRow>[]);
      }
      return (
        parsed: parsed,
        rows: await _readExactAlgoCycleNights(
          txn,
          startDay: window.startDay,
          endDay: window.endDay,
        ),
      );
    });
    return buildCycleMediansSnapshot(
      settings: settings,
      log: snapshot.parsed,
      algoVersion: kAlgoVersion,
      window: window,
      rows: snapshot.rows,
    );
  }

  @override
  Future<CycleComparisonSnapshot> readCycleComparison(
    String anchorEnd, {
    int pageOffset = 0,
    DateTime? now,
  }) async {
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
    final settings = await readCycleSettings();
    final db = await LocalDb.instance;
    final snapshot = await db.transaction((txn) async {
      final parsed = await CycleStore.load(txn, asOf: window.endDay);
      if (!settings.enabled) {
        return (parsed: parsed, rows: const <CycleNightSourceRow>[]);
      }
      return (
        parsed: parsed,
        rows: await _readExactAlgoCycleNights(
          txn,
          startDay: cycleComparisonQueryStart(window),
          endDay: window.endDay,
        ),
      );
    });
    return buildCycleComparisonSnapshot(
      settings: settings,
      log: snapshot.parsed,
      algoVersion: kAlgoVersion,
      window: window,
      rows: snapshot.rows,
    );
  }

  @override
  Future<CycleWriteResult> saveCycleStart(
    CycleStart desired, {
    CycleStart? expected,
    DateTime? now,
  }) async {
    final db = await LocalDb.instance;
    final written = await CycleStore.saveStart(
      db,
      desired,
      expected: expected,
      now: now ?? DateTime.now(),
    );
    if (!written.committed) return written;
    return _cycleWriteResult(start: written.start);
  }

  @override
  Future<CycleWriteResult> removeCycleStart(CycleStart expected) async {
    final db = await LocalDb.instance;
    final written = await CycleStore.removeStart(db, expected);
    if (!written.committed) return written;
    return _cycleWriteResult(start: written.start);
  }

  @override
  Future<CycleWriteResult> restoreCycleStart(
    CycleStart removed, {
    DateTime? now,
  }) async {
    final db = await LocalDb.instance;
    final written = await CycleStore.restoreStart(
      db,
      removed,
      now: now ?? DateTime.now(),
    );
    if (!written.committed) return written;
    return _cycleWriteResult(start: written.start);
  }

  @override
  Future<CycleWriteResult> saveCycleObservation(
    CycleObservation desired, {
    CycleObservation? expected,
    DateTime? now,
  }) async {
    final db = await LocalDb.instance;
    final written = await CycleStore.saveObservation(
      db,
      desired,
      expected: expected,
      now: now ?? DateTime.now(),
    );
    if (!written.committed) return written;
    return _cycleWriteResult(observation: written.observation);
  }

  @override
  Future<void> refreshCycleContext() {
    return (_cycleContextRefresh ?? app.refreshCycleContext)();
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
}

GlucoseSnapshot _glucoseSnapshotFromRead(
  ImportedGlucoseRead read, {
  required int? limit,
}) {
  var unreadable = read.identityUnreadable + read.importedAtUnreadable;
  final unreadTokens = <Object>{};
  void markUnread(Map<String, dynamic> row) {
    unreadTokens.add((row['uuid'], row['ts'], row['source_key']));
  }

  final excluded = <String>{};
  for (final s in read.settings) {
    final key = s['source_key'];
    if (key is! String) {
      if (key != null) unreadable++;
      continue;
    }
    if (key.isEmpty) continue;
    if (s['excluded'] == 1 || s['excluded'] == '1') excluded.add(key);
  }

  final byKey = <String, GlucoseSourceInventoryItem>{};
  for (final g in read.groups) {
    final row = read.latestRows[g.key];
    final latest = row == null ? null : glucoseReadingFromStored(row);
    if (row != null && latest == null) markUnread(row);
    byKey[g.key] = GlucoseSourceInventoryItem(
      source: latest?.source ??
          glucoseSourceFromStored(sourceKey: g.key, sourceName: ''),
      excluded: excluded.contains(g.key),
      lastMeasuredAt: latest?.measuredAt,
      lastImportedAt: glucoseDateTimeFromEpochSeconds(g.lastImportedAt),
      readingCount: g.storedCount,
    );
  }
  for (final key in excluded) {
    byKey.putIfAbsent(
      key,
      () => GlucoseSourceInventoryItem(
        source: glucoseSourceFromStored(sourceKey: key, sourceName: ''),
        excluded: true,
      ),
    );
  }

  final history = <GlucoseReading>[];
  for (final row in read.historyRows) {
    final r = glucoseReadingFromStored(row);
    if (r == null) {
      markUnread(row);
      continue;
    }
    if (limit != null && history.length >= limit) break;
    history.add(r);
  }

  for (final row in read.historyLookaheadUnread) {
    markUnread(row);
  }

  final dayReadings = <GlucoseReading>[];
  for (final row in read.dayRows) {
    final r = glucoseReadingFromStored(row);
    if (r == null) {
      markUnread(row);
      continue;
    }
    dayReadings.add(r);
  }
  dayReadings.sort(compareGlucoseNewestFirst);

  final selectedKey = read.selectedKey;
  final selectedExcluded =
      selectedKey != null && excluded.contains(selectedKey);
  final sources = byKey.values.toList()
    ..sort((a, b) => a.source.key.compareTo(b.source.key));
  final receipt = decodeGlucoseReceipt(read.receipt);

  return assembleBoundedGlucoseSnapshot(
    sources: sources,
    history: history,
    dayReadings: dayReadings,
    receiptAttempt: receipt,
    selected: selectedKey == null
        ? null
        : (byKey[selectedKey]?.source ??
            glucoseSourceFromStored(sourceKey: selectedKey, sourceName: '')),
    selectedKey: selectedKey,
    selectedExcluded: selectedExcluded,
    truncated: read.historyTruncated,
    unreadableCount: unreadable + unreadTokens.length + receipt.unreadable,
  );
}

/// Bounded raw `payload_json` page for cycle-night reads. A twelve-month
/// window is walked in these chunks so 365/366 fat strings are never held
/// together; decode is isolate Dart last-wins on needed keys only.
const int kCycleNightPayloadBatchSize = 32;

bool _cycleMediansNeedsNightRows(CycleMediansSnapshot snap) {
  return switch (snap.reason) {
    CycleMediansReason.available ||
    CycleMediansReason.insufficientDays =>
      true,
    CycleMediansReason.trackingDisabled ||
    CycleMediansReason.emptyStarts ||
    CycleMediansReason.unreadableStarts ||
    CycleMediansReason.longPeriods =>
      false,
  };
}

/// Exact [kAlgoVersion] nights in [startDay]..=[endDay], date-ordered.
/// Corrections load once; payloads query in [kCycleNightPayloadBatchSize]
/// batches, project off-isolate, then drop the raw batch before the next.
Future<List<CycleNightSourceRow>> _readExactAlgoCycleNights(
  DatabaseExecutor txn, {
  required String startDay,
  required String endDay,
}) async {
  final correctionRows = await txn.rawQuery(
    'SELECT c.day_id AS day_id, '
    'c.correction_id AS correction_id, '
    'c.revision AS revision, '
    'c.action AS action, '
    'c.onset_ms AS onset_ms, '
    'c.wake_ms AS wake_ms, '
    'j.correction_id AS job_correction_id, '
    'j.revision AS job_revision, '
    'j.status AS status, '
    'j.result_algo_version AS result_algo_version, '
    'j.result_computed_at AS result_computed_at '
    'FROM openband_sleep_correction c '
    'LEFT JOIN openband_calculation_job j '
    'ON j.day_id = c.day_id '
    'AND j.correction_id = c.correction_id '
    'AND j.revision = c.revision '
    'WHERE c.day_id >= ? AND c.day_id <= ?',
    [startDay, endDay],
  );
  final correctionRowsByDay = <String, Map<String, dynamic>>{};
  final blockedJob = <String>{};
  for (final r in correctionRows) {
    final date = r['day_id'];
    if (date is! String) continue;
    final mapped = Map<String, dynamic>.from(r);
    correctionRowsByDay[date] = mapped;
    if (!LocalOpenBandRepository._currentCompleteSleepJob(mapped)) {
      blockedJob.add(date);
    }
  }

  final rows = <CycleNightSourceRow>[];
  var offset = 0;
  while (true) {
    final dayRows = await txn.query(
      'day_result',
      columns: [
        'day_id',
        'skipped',
        'partial',
        'payload_json',
        'computed_at',
      ],
      where: 'day_id >= ? AND day_id <= ? AND algo_version = ?',
      whereArgs: [startDay, endDay, kAlgoVersion],
      orderBy: 'day_id ASC',
      limit: kCycleNightPayloadBatchSize,
      offset: offset,
    );
    if (dayRows.isEmpty) break;
    final rawPayloads = [for (final r in dayRows) r['payload_json']];
    // dart:convert last-wins; sqlite json_extract is first-wins. Needed keys
    // only, off-isolate, so unused series never expand on the UI isolate.
    final payloads = await Isolate.run(
      () => _projectCycleNightPayloads(rawPayloads),
    );
    for (var i = 0; i < dayRows.length; i++) {
      final r = dayRows[i];
      final date = r['day_id'];
      if (date is! String) continue;
      final payload = i < payloads.length ? payloads[i] : null;
      final correction = correctionRowsByDay[date];
      final published =
          correction != null && !blockedJob.contains(date) ? correction : null;
      rows.add(
        CycleNightSourceRow(
          day: date,
          algoVersion: kAlgoVersion,
          skipped: r['skipped'] == 1,
          partial: r['partial'] == 1,
          payload: payload == null ? null : Map<String, Object?>.from(payload),
          payloadUnreadable: payload == null,
          jobBlocked: blockedJob.contains(date),
          computedAtMs: (r['computed_at'] as num?)?.toInt(),
          resultComputedAtMs:
              (published?['result_computed_at'] as num?)?.toInt(),
          correctionAction: published?['action']?.toString(),
          correctionOnsetMs: (published?['onset_ms'] as num?)?.toInt(),
          correctionWakeMs: (published?['wake_ms'] as num?)?.toInt(),
        ),
      );
    }
    offset += dayRows.length;
    if (dayRows.length < kCycleNightPayloadBatchSize) break;
  }
  return rows;
}

const _kCycleNightPayloadKeys = [
  'imported',
  'sleep_source',
  'sleep',
  'clinical',
];

List<Map<String, Object?>?> _projectCycleNightPayloads(List<Object?> raws) {
  return [for (final raw in raws) _projectCycleNightPayload(raw)];
}

Map<String, Object?>? _projectCycleNightPayload(Object? json) {
  if (json is! String || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    final out = <String, Object?>{};
    for (final key in _kCycleNightPayloadKeys) {
      if (decoded.containsKey(key)) out[key] = decoded[key];
    }
    return out;
  } catch (_) {
    return null;
  }
}

/// Isolate entry: one field × one outcome, lag 1. Returns a sendable map.
Map<String, Object?> _caffeineSleepCorrelate(Map<String, Object?> input) {
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
