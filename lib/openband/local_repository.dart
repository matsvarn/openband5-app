import 'dart:convert';

import '../data/db.dart';
import '../data/nutrition_store.dart';
import '../data/day_label.dart';
import '../data/series_codec.dart';
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
