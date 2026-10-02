part of 'app_state.dart';

/// Active workout tracking (in-memory only).
class LiveWorkoutState {
  final DateTime startTime;
  final double targetKcal;
  final String? workoutId; // local session id (for the breakdown on finish)
  final String type; // exercise type label
  Duration elapsed = Duration.zero;
  int pausedSec;
  DateTime? pausedAt;

  int totalPausedSec(DateTime now) =>
      pausedSec +
      (pausedAt == null
          ? 0
          : now.difference(pausedAt!).inSeconds.clamp(0, 1 << 30));

  Duration activeElapsed(DateTime now) => Duration(
    seconds: ((pausedAt ?? now).difference(startTime).inSeconds - pausedSec)
        .clamp(0, 1 << 30),
  );

  /// Live kcal for the bout so far. Zero here is ambiguous on its own — read
  /// [caloriesOrNull] anywhere a user can see it.
  ///
  /// RECOMPUTED from the retained per-minute series on every sample, not
  /// accrued. Same reason [strain] is: [restingHr] is loaded asynchronously and
  /// can land after the session starts, and it sets the gate that decides
  /// whether a minute is billed at the active or the resting rate. An
  /// incremental tally could only ever have corrected the seconds after the
  /// anchor arrived, leaving the earlier ones scored against a guess.
  double calories = 0.0;

  /// Whether the calorie estimate has run even once this session.
  ///
  /// Separate from [Profile.hasCalorieAnchors] because "can we score this" and
  /// "did we score this" are different questions and both have a zero-shaped
  /// answer. A complete profile whose band never delivered a heart rate — the
  /// link dropped, the strap was off — accrues nothing, and reporting that as
  /// 0 kcal claims a measurement that was never taken. Strain already reports
  /// that case as absent; this makes calories agree.
  bool _caloriesScored = false;

  /// Live kcal, or null when this session cannot be costed at all — the
  /// profile lacks the anchors Keytel needs, no resting HR has arrived to set
  /// the bout gate, or no heart rate ever landed. Absent beats fabricated, and
  /// absent also beats a confident zero.
  int? get caloriesOrNull => _caloriesScored ? calories.round() : null;

  /// Re-cost the bout so far. The only writer of [calories].
  ///
  /// Uses the SAME published rates, coefficients and activity gate as
  /// `Calories.estimateBoutCalories`, which is what the substrate re-score and
  /// every manually logged session run on — so the figure on the live gauge
  /// survives its own re-score. It used to bill the raw Keytel active rate for
  /// every second the band reported a heart rate, with no gate and no resting
  /// floor, which roughly doubled the cost of warm-up, rest between sets and
  /// cool-down against what the re-score would later say about the same stream.
  ///
  /// PER SAMPLE, not per minute. [_secondsByBpm] holds how many seconds the
  /// bout spent at each whole-bpm value, so this reproduces
  /// `estimateBoutCalories`'s sample-by-sample billing exactly while staying
  /// O(distinct bpm) in memory instead of retaining every raw sample.
  ///
  /// It scored per MINUTE, off the mean of each minute, and that lost the two
  /// things the re-score gets right:
  ///
  ///   * The gate is per sample there and was per minute-mean here. A minute
  ///     that straddles the gate — 30 s at 93 and 30 s at 94 against a 93.76
  ///     gate — billed as a whole resting minute (1.19 kcal) where the
  ///     re-score bills half of it active (3.63). About 146 kcal adrift over a
  ///     zone-2 hour, in a stream that never looks unusual.
  ///   * The seconds were wrong. A completed minute billed a flat 60 s no
  ///     matter how few samples backed it, and the minute in progress billed
  ///     `_minuteCount`, a SAMPLE count used as a second count — 12 s instead
  ///     of 60 at a 5 s notify rate.
  void _scoreCalories() {
    final rhr = restingHr;
    // Local copy: a public final field does not type-promote across the guard.
    final maxHr = hrMax;
    // The re-score refuses to invent a 220/60 anchor pair, so neither does
    // this. A resting HR landing later re-scores the whole bout.
    if (!profile.hasCalorieAnchors || rhr == null || maxHr == null) {
      _caloriesScored = false;
      calories = 0.0;
      return;
    }
    // THE gate, from the one place that defines it. This used to be the
    // arithmetic inlined below, which is the third copy of it — and
    // `Calories`' own docstring says a second copy is how the day and the bout
    // came to disagree in the first place. It also got none of the anchor
    // validation: a non-finite resting HR makes the gate NaN, every
    // `bpm < gate` is then false, and EVERY sample bills at the active rate.
    // Null means the anchors cannot define a gate, and the live gauge abstains
    // exactly as the re-score does.
    final gate = ana.Calories.activeGateHr(maxHr, rhr);
    if (gate == null) {
      _caloriesScored = false;
      calories = 0.0;
      return;
    }
    if (_secondsByBpm.isEmpty && _lastSampleHr == null) {
      _caloriesScored = false;
      calories = 0.0;
      return;
    }

    final age = profile.ageYears!.toDouble();
    final weightKg = profile.weightKg!;
    final coeffs = ana.Calories.resolveCoeffs(workoutSex(profile.sex));
    // Height is not a Keytel term; it only moves the Harris-Benedict resting
    // floor. Defaulted to match `computeManualSessionStats`, so the two paths
    // cannot disagree for a profile that carries no height.
    final heightCm = profile.heightCm ?? 170.0;
    final restingRate = ana.Calories.restingKcalPerS(
      coeffs,
      weightKg,
      heightCm,
      age,
    );

    var kcal = 0.0;
    void bill(int bpm, double seconds) {
      final rate = bpm < gate
          ? restingRate
          : ana.Calories.activeKcalPerS(
              coeffs,
              bpm.toDouble(),
              maxHr,
              weightKg,
              age,
            );
      kcal += rate * seconds;
    }

    _secondsByBpm.forEach(bill);
    // The newest sample has no successor yet, so its own duration is unknown.
    // `estimateBoutCalories` gives the final sample one representative second;
    // matching that is what keeps the gauge and the re-score equal at every
    // instant rather than only at the end.
    final trailing = _lastSampleHr;
    if (trailing != null) bill(trailing, 1.0);

    calories = kcal;
    _caloriesScored = true;
  }

  /// Headline 0–21 strain, or null when the profile lacks an anchor the
  /// Banister formula needs. Recomputed on every HR sample by [accrueHr] — it
  /// is NOT accrued incrementally any more. The old `strain += %HRR * 0.01`
  /// per second was uncited and uncapped: it read 25.33 where the canonical
  /// method reads 11.62 for the same hour, and passed the top of its own 0–21
  /// scale after ~50 minutes of hard work, which the gauge silently clamped.
  double? strain;

  /// The live heart rate this session is currently being scored against, or
  /// null when the band is not delivering one (dropped, or stalled — see
  /// [AppState.liveHr]). Null, not 0: a session with no reading is unmeasured,
  /// not resting, and `_zoneFor(0)` is a real answer to a question nobody asked.
  int? currentHr;
  int maxHrSeen = 0; // spike-suppressed peak live HR this session (issue #127)

  /// Rolling-median accumulator behind [maxHrSeen] — smooths the live 1 Hz HR
  /// at accrual so a transient PPG motion spike can't set the session max (or
  /// fire a spurious "new max!"). Same window + reject as the on-read recompute.
  final RollingMaxHr _hrPeak;

  /// Seconds spent in each HR zone (index 0..5 = Z0 rest .. Z5 max), tallied at
  /// 1 Hz by _tickWorkout. Z1..Z5 are persisted as `zone_min` on stop.
  final List<double> zoneSeconds = List<double>.filled(6, 0);

  /// The persisted `zone_min` payload: minutes in Z1..Z5 (index 0 = Z1 — the
  /// 5-element shape the Time-in-Zones bar parses). Z0 (rest) is excluded.
  List<double> zoneMinutes() => [
    for (var z = 1; z <= 5; z++)
      double.parse((zoneSeconds[z] / 60.0).toStringAsFixed(2)),
  ];

  /// Anchors for the live strain score. Held on the session because a workout
  /// must be scored against the profile it was performed under, not whatever
  /// the profile happens to say when the session ends.
  final Profile profile;

  /// THE HR ceiling for this session — `estimatedMaxHr(age, family)`, resolved
  /// once at start from the athlete's age and the strap measuring the window.
  /// Null when either is missing, and then strain, calories and the zone split
  /// all abstain: there is no ceiling to be a percentage of.
  ///
  /// This is the STRAIN/CALORIE anchor only. The zone split reads [zoneSet],
  /// which may be banded on a MEASURED ceiling while this stays the age
  /// estimate — see the comment there.
  final double? hrMax;

  /// THE zone set this session's per-second split is binned with (TS-04),
  /// resolved once at start from `trainingZones` — the same function the day
  /// pipeline and the detail screen's `zone_bands` use, so the live gauge, the
  /// persisted `zone_min` and the recomputed bands cannot disagree about one
  /// heartbeat.
  ///
  /// Deliberately NOT derived from [hrMax]. Once the band has observed a
  /// ceiling, zones move onto it and onto the measured resting HR; strain does
  /// not, because moving it would rewrite every strain score ever shown. Two
  /// anchors, named, beats one anchor quietly used for both.
  final ana.HeartRateZoneSet? zoneSet;

  /// Resting-HR anchor for the strain score. NOT final: the measured nightly
  /// value is loaded asynchronously, so a session can begin before it lands.
  /// [AppState._refreshNightlyRhr] back-fills it here when it arrives, and the
  /// next HR sample re-scores through it — otherwise the session would be
  /// stuck unscored for its whole duration over a read that finished a
  /// fraction of a second after it started.
  double? restingHr;

  /// The user's personal quiet-waking HRR level strain subtracts its baseline
  /// at (edge#226) — the trailing median of measured days, loaded with the
  /// resting-HR refresh. Deliberately not measured off this session's own
  /// minutes: the session's median IS the effort being scored, so a hard
  /// workout would subtract itself away. Null ⇒ the scorer abstains.
  double? quietHrr;

  /// Per-minute mean HR, the unit Banister TRIMP weights. Live HR arrives at
  /// 1 Hz, so it is folded into the current minute here rather than kept as
  /// thousands of raw samples.
  /// DENSE — index IS the session minute, `null` where no sample arrived.
  ///
  /// This used to be a plain `List<double>` that only grew when a minute had
  /// samples, so a band dropout from minute 10 to 20 produced a 30-entry list
  /// for a 40-minute session. The summary drawn the moment you press stop maps
  /// index to x, so it joined minute 9 straight to minute 21 and drew every
  /// later reading ten minutes early — while the SAME session reopened from
  /// History was dense (`_denseMinutes`) and showed the gap correctly.
  final List<double?> _perMinute = [];
  int _minuteBucket = -1;
  double _minuteSum = 0;
  int _minuteCount = 0;

  /// Per-minute means INCLUDING the minute still in progress, so the live
  /// gauge moves within the first minute instead of sitting at zero for 60 s.
  /// Dense: one slot per session minute, `null` for a minute nothing reached.
  List<double?> perMinuteHrDense() {
    final out = <double?>[..._perMinute];
    if (_minuteCount > 0 && _minuteBucket >= 0) {
      while (out.length <= _minuteBucket) {
        out.add(null);
      }
      out[_minuteBucket] = _minuteSum / _minuteCount;
    }
    return out;
  }

  /// The same series with the holes removed — for statistics (strain, mean),
  /// which want the readings and not the time axis.
  List<double> perMinuteHr() => [for (final v in perMinuteHrDense()) ?v];

  /// Closed HR sample-to-sample seconds from [_secondsByBpm]. Null until a
  /// billed interval exists — unknown is not zero, and a lone unbilled sample
  /// has not covered any time yet.
  int? get hrCoveredSec {
    if (_secondsByBpm.isEmpty) return null;
    var total = 0.0;
    for (final s in _secondsByBpm.values) {
      total += s;
    }
    return total.round();
  }

  /// Seconds the bout has spent at each whole-bpm value — the calorie series.
  ///
  /// Deliberately NOT the per-minute means above. `estimateBoutCalories`, which
  /// the substrate re-score and every manually logged session run on, decides
  /// active-vs-resting per SAMPLE and weights each sample by the elapsed time to
  /// the next one. A per-minute mean cannot express either: it collapses a
  /// minute that straddles the activity gate onto one side of it, and it has no
  /// idea how many seconds actually backed the samples in it.
  ///
  /// A histogram rather than a sample list because heart rate is a small
  /// integer — this is bounded at a couple of hundred entries for a bout of any
  /// length, while retaining raw 1 Hz samples is not.
  final Map<int, double> _secondsByBpm = {};

  /// The most recent accepted sample, still unbilled: its duration is the time
  /// until the NEXT sample, which has not arrived. Also what makes a gap in the
  /// stream bill correctly — the sample before a contact-loss gap is charged
  /// for the gap, capped, exactly as the re-score charges it.
  int? _lastSampleHr;
  double? _lastSampleSec;

  void breakHrSpan() {
    _lastSampleHr = null;
    _lastSampleSec = null;
  }

  /// A stream that stops for longer than this stopped being one bout; billing
  /// the pre-gap heart rate across an hour of no data would invent the hour.
  ///
  /// Taken from the analytics constant rather than restated, because the whole
  /// point of this scoring path is that it gives up at the same instant the
  /// re-score of the same stream does. A second literal 150.0 here would agree
  /// today and diverge silently the day the published cap moved.
  static const double _gapCapS = ana.Calories.defaultMergeGapCapS;

  LiveWorkoutState({
    required this.startTime,
    required this.targetKcal,
    this.pausedSec = 0,
    this.pausedAt,
    this.workoutId,
    this.type = 'other',
    int? age,
    this.profile = const Profile(),
    this.hrMax,
    this.zoneSet,
    this.restingHr,
    this.quietHrr,
  }) : _hrPeak = RollingMaxHr(age: age),
       idleWatch = WorkoutIdleWatch(startedAt: startTime);

  /// The forgotten-session watch — see [WorkoutIdleWatch]. Anchored on
  /// [startTime], which for a session the reconcile path rehydrated is the
  /// ORIGINAL start hours ago: the most forgotten a workout can be is exactly
  /// when the first tick should already be allowed to ask.
  final WorkoutIdleWatch idleWatch;

  /// Feed a live HR sample; updates the spike-suppressed [maxHrSeen], the
  /// per-minute accumulator behind strain, the per-bpm second counts behind
  /// calories, and both derived figures.
  ///
  /// A non-positive reading is off-skin, not a heart rate, so it is dropped —
  /// but the time it covers is NOT thrown away. It is billed to the last real
  /// sample when the next one arrives, capped at [_gapCapS], which is what
  /// `estimateBoutCalories` does with the same gap once the zeros have been
  /// filtered out of the stream it re-scores.
  void accrueHr(int hr) {
    if (hr <= 0) return;
    _hrPeak.add(hr);
    if (_hrPeak.max > maxHrSeen) maxHrSeen = _hrPeak.max;

    // Close out the previous sample: its duration is the time until this one.
    // Sub-second and out-of-order arrivals fall back to one second, matching
    // `estimateBoutCalories`'s handling of a non-positive gap.
    final nowSec = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final prevHr = _lastSampleHr;
    final prevSec = _lastSampleSec;
    if (prevHr != null && prevSec != null) {
      final gap = nowSec - prevSec;
      final dur = gap > 0 ? math.min(gap, _gapCapS) : 1.0;
      _secondsByBpm[prevHr] = (_secondsByBpm[prevHr] ?? 0) + dur;
    }
    _lastSampleHr = hr;
    _lastSampleSec = nowSec;

    // Fold into the current minute, measured from the session start so the
    // buckets are the session's own minutes rather than wall-clock ones.
    final minute = elapsed.inMinutes;
    if (minute != _minuteBucket) {
      // Close the finished bucket AT ITS OWN INDEX, padding the minutes that
      // produced nothing with null rather than skipping them.
      if (_minuteCount > 0 && _minuteBucket >= 0) {
        while (_perMinute.length <= _minuteBucket) {
          _perMinute.add(null);
        }
        _perMinute[_minuteBucket] = _minuteSum / _minuteCount;
      }
      _minuteBucket = minute;
      _minuteSum = 0;
      _minuteCount = 0;
    }
    _minuteSum += hr;
    _minuteCount++;

    // ONE strain method across the app (see strainFromPerMinuteHr). Null when
    // an anchor is missing — the gauge shows "—" rather than a number built on
    // an invented HRmax or resting HR.
    strain = strainFromPerMinuteHr(
      perMinuteHr(),
      profile: profile,
      restingHr: restingHr,
      hrMax: hrMax,
      quietHrr: quietHrr,
    );

    // Calories re-score off the same series, through the same estimator the
    // substrate re-score uses, so both live figures on the gauge mean the same
    // thing the finished session will.
    _scoreCalories();
  }
}
