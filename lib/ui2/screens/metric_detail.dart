// The shared metric drill-down — density 2 of 3.
//
// Glance (a row on Health) → MetricDetail (your normal range, what moves it,
// how this week compares) → Nerd stats (everything, in mono). There is no
// "advanced mode" switch: depth is a place you walk to, not a preference you
// set, so the same person gets the shallow read on Monday and the deep one
// when something looks wrong.
//
// Every metric goes through THIS screen. Forty bespoke detail screens is how
// the old UI ended up with forty different opinions about what a chart is.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../ble/adapters/signals.dart';
import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../ui2.dart';
import 'home_screen.dart';
import '../profile/devices.dart' show DeviceOption;

// ═══════════════════ the vocabulary ═══════════════════

/// What a metric key means on screen, and whether we are willing to draw it.
class MetricSpec {
  /// The alias `getChart` / `getTrend` understand (`_trendKey` maps it on).
  final String chartKey;
  final String title;
  final String unit;
  final Color color;
  final IconData icon;
  final bool higherBetter;

  /// Non-null when this metric must NOT be charted. The string is the honest
  /// reason, shown as a `StatusCard` in place of the chart.
  final String? suppress;
  final String? suppressFix;

  /// How it is computed, and who published the method. Rendered by Nerd stats.
  final String method;
  final String citation;

  /// The INPUT SIGNALS this metric physically needs. A device that does not
  /// declare every one of them cannot produce it, which is what makes the
  /// per-device filter and its three visibility gates computable from the
  /// registry with no query at all (final-plan §6.1, §6.5).
  ///
  /// SUPERSET, not intersection: a device qualifies only when its
  /// `BandAdapter.signals` covers all of these. Readiness has four inputs, so a
  /// chest strap that supplies two of them cannot serve a readiness chart, and
  /// offering it one would be a control that can only ever draw an empty axis.
  ///
  /// Empty is the honest default: a metric nobody has classified declares no
  /// requirement, every gate below evaluates false, and the screen is today's.
  final Set<InputSignal> requires;

  const MetricSpec({
    required this.chartKey,
    required this.title,
    this.unit = '',
    this.color = C.blue,
    this.icon = LucideIcons.activity,
    this.higherBetter = true,
    this.suppress,
    this.suppressFix,
    this.method = '',
    this.citation = '',
    this.requires = const {},
  });
}

const _specs = <String, MetricSpec>{
  'resting_hr': MetricSpec(
    chartKey: 'resting_hr',
    title: 'Resting heart rate',
    unit: 'bpm',
    color: C.red,
    icon: LucideIcons.heart,
    higherBetter: false,
    method: 'The lowest sustained sleeping heart rate of the night, taken over '
        'a rolling window of the overnight series. Not a spot reading, and not '
        'a daytime minimum.',
    citation: 'Nocturnal heart-rate minimum; personal baseline, not population',
    requires: {InputSignal.hr1Hz},
  ),
  'hrv': MetricSpec(
    chartKey: 'hrv',
    title: 'HRV',
    unit: 'ms',
    color: C.green,
    icon: LucideIcons.activity,
    method: 'RMSSD over the longest artefact-free window during sleep. Beat '
        'timing is recovered from the band\'s 1 Hz records and corrected by '
        'the Lipponen–Tarvainen method before any statistic is taken. '
        'Pulse-derived, so this is PRV: real and trendable, but not ECG HRV.',
    citation: 'Task Force 1996 · Lipponen & Tarvainen 2019',
    requires: {InputSignal.rrIntervals},
  ),
  'readiness': MetricSpec(
    chartKey: 'recovery',
    title: 'Readiness',
    color: C.green,
    icon: LucideIcons.batteryCharging,
    // The weights are DATA — `readiness_glassbox` emits one per input and the
    // Readiness screen renders them. Repeating them as prose here meant two
    // surfaces could disagree about the same composite, silently, forever.
    method: 'A weighted composite of a handful of inputs, each scored against '
        'your own history. Every input\'s weight, and whether last night had '
        'enough history to use it, is listed on the Readiness screen. Missing '
        'inputs are re-weighted, never zero-filled.',
    citation: 'Plews 2013 (lnRMSSD) · Hopkins smallest-worthwhile-change gate',
    requires: {
      InputSignal.rrIntervals,
      InputSignal.hr1Hz,
      InputSignal.accel1Hz,
      InputSignal.skinTempRaw,
    },
  ),
  'resp_rate': MetricSpec(
    chartKey: 'resp_rate',
    title: 'Respiratory rate',
    unit: 'br/min',
    color: C.teal,
    icon: LucideIcons.wind,
    higherBetter: false,
    method: 'Breathing rate recovered from respiratory sinus arrhythmia — the '
        'periodic modulation breathing imposes on beat timing — over a grid of '
        'candidate rates.',
    citation: 'Pimentel 2017',
    requires: {InputSignal.rrIntervals},
  ),
  'sleep': MetricSpec(
    chartKey: 'sleep',
    title: 'Time asleep',
    unit: 'min',
    color: C.blue,
    icon: LucideIcons.moon,
    method: 'Total sleep time from the wrist z-angle sleep window, staged by a '
        'combined actigraphy and heart-rate model.',
    citation: 'van Hees 2015 · Webster / Cole–Kripke rescoring',
    requires: {InputSignal.accel1Hz, InputSignal.hr1Hz},
  ),
  'efficiency': MetricSpec(
    chartKey: 'efficiency',
    title: 'Sleep efficiency',
    unit: '%',
    color: C.blue,
    icon: LucideIcons.bedDouble,
    method: 'Time asleep as a fraction of time in bed.',
    citation: 'AASM sleep-accounting definitions',
    requires: {InputSignal.accel1Hz, InputSignal.hr1Hz},
  ),
  'deep': MetricSpec(
    chartKey: 'deep',
    title: 'Deep sleep',
    unit: 'min',
    color: C.blue,
    icon: LucideIcons.moon,
    method: 'A low-confidence overlay: a wrist sensor cannot see slow-wave '
        'activity, so deep sleep here is heart-rate flatness inside NREM.',
    citation: 'Cole–Kripke wake spine + HRV overlay',
    requires: {InputSignal.accel1Hz, InputSignal.hr1Hz},
  ),
  'rem': MetricSpec(
    chartKey: 'rem',
    title: 'REM sleep',
    unit: 'min',
    color: C.teal,
    icon: LucideIcons.moon,
    method: 'Staged from beat-timing variability and movement. A wrist sensor '
        'separates REM from light sleep only approximately.',
    citation: 'Webster / Cole–Kripke rescoring + HRV staging',
    requires: {InputSignal.accel1Hz, InputSignal.hr1Hz},
  ),
  'steps': MetricSpec(
    chartKey: 'steps',
    title: 'Steps',
    unit: 'steps',
    color: C.green,
    icon: LucideIcons.footprints,
    method: 'Counted, never modelled. A step count comes from a gait-capable '
        'counter: the band\'s 100 Hz pedometer while it streams, or your '
        'phone\'s. Each stretch of the day is counted by whichever of the two '
        'was actually recording it, and a stretch both covered is counted '
        'once, so a session never takes the day from the sensor that carried '
        'the rest of it. There is no 1 Hz estimate — walking cadence sits above what '
        'one sample a second can resolve, so a day with no counter behind it '
        'reports no steps rather than a guess.',
    citation: 'AN-2554 pedometer · phone pedometer (HealthKit / Health Connect)',
    // Deliberately EMPTY — see final-plan §4.6. Steps are resolved by
    // `live_coverage_policy.dart`, which ranks by SPAN not device and credits
    // by overlap subtraction; a device-ownership filter on this screen would
    // be a per-device view of a quantity that is explicitly not per-device
    // (and would reintroduce the 622-vs-18,856 double count, db.dart:2166-2172).
    requires: {},
  ),
  'calories': MetricSpec(
    chartKey: 'calories',
    title: 'Active energy',
    unit: 'kcal',
    color: C.orange,
    icon: LucideIcons.flame,
    method: 'Heart-rate-to-energy regression over the waking span, anchored on '
        'your weight, age and sex. An estimate, and sensitive to all three.',
    citation: 'Keytel 2005 · Harris–Benedict / Mifflin BMR floor',
    requires: {InputSignal.hr1Hz},
  ),
  'strain': MetricSpec(
    chartKey: 'strain',
    title: 'Strain',
    color: C.purple,
    icon: LucideIcons.zap,
    method: 'Cardiovascular load over the day, compressed onto a 0–21 scale.',
    citation: 'Banister TRIMP family · log-compressed',
    requires: {InputSignal.hr1Hz},
  ),
  'trimp': MetricSpec(
    chartKey: 'trimp',
    title: 'Training load',
    color: C.purple,
    icon: LucideIcons.dumbbell,
    method: 'Training impulse: time in each heart-rate zone, weighted by the '
        'physiological cost of that zone.',
    citation: 'Banister 1975 · Edwards 1993',
    requires: {InputSignal.hr1Hz},
  ),
  'stress': MetricSpec(
    chartKey: 'stress',
    title: 'Stress',
    color: C.purple,
    icon: LucideIcons.brain,
    higherBetter: false,
    method: 'Baevsky stress index over a resting window: a histogram measure of '
        'how tightly beat intervals cluster. There is deliberately no fallback '
        'when the resting window is missing.',
    citation: 'Baevsky 2008',
    requires: {InputSignal.rrIntervals},
  ),
  'dip': MetricSpec(
    chartKey: 'dip',
    title: 'Nocturnal HR dip',
    unit: '%',
    color: C.indigo,
    icon: LucideIcons.trendingDown,
    method: 'How far sleeping heart rate falls below the waking average.',
    citation: 'Nocturnal dipping literature; personal baseline',
    requires: {InputSignal.hr1Hz},
  ),
  'hrr': MetricSpec(
    chartKey: 'hrr',
    title: 'Heart-rate recovery',
    unit: 'bpm',
    color: C.red,
    icon: LucideIcons.heartPulse,
    method: 'The drop in heart rate over the 60 seconds after a bout ends, '
        'averaged across the day\'s bouts.',
    citation: 'Cole 1999 (HRR-60)',
    requires: {InputSignal.hr1Hz},
  ),
  'lf_hf': MetricSpec(
    chartKey: 'lf_hf',
    title: 'LF / HF',
    color: C.purple,
    icon: LucideIcons.audioWaveform,
    method: 'The ratio of low- to high-frequency power in beat-interval '
        'variability, from a Lomb–Scargle periodogram (the series is unevenly '
        'sampled, so an FFT would be wrong).',
    citation: 'Laguna 1998 · Bigger 1992',
    requires: {InputSignal.rrIntervals},
  ),
  'hrv_cv': MetricSpec(
    chartKey: 'hrv_cv',
    title: 'HRV stability',
    unit: '%',
    color: C.green,
    icon: LucideIcons.activity,
    higherBetter: false,
    method: 'Night-to-night coefficient of variation of RMSSD.',
    citation: 'Within-user dispersion',
    requires: {InputSignal.rrIntervals},
  ),
  'brv': MetricSpec(
    chartKey: 'brv',
    title: 'Breathing variability',
    color: C.teal,
    icon: LucideIcons.wind,
    higherBetter: false,
    method: 'Coefficient of variation of per-window respiratory rate across '
        'the night.',
    citation: 'Within-user dispersion',
    requires: {InputSignal.rrIntervals},
  ),
  // Both of these were written to `metric_series` on every derive since v55 and
  // had no spec, so nothing could open them — `specOf` fell through to a
  // generic entry titled "nap min". They are 17/17 on real data.
  'nap_min': MetricSpec(
    chartKey: 'nap_min',
    title: 'Daytime sleep',
    unit: 'min',
    color: C.indigo,
    icon: LucideIcons.moon,
    method: 'Minutes of sleep detected OUTSIDE the main night: the same wrist '
        'z-angle window detector the night uses, confirmed by a heart-rate dip. '
        'Naps are counted separately and never folded into time asleep.',
    citation: 'van Hees 2015 window detection + nocturnal HR dip',
    requires: {InputSignal.accel1Hz, InputSignal.hr1Hz},
  ),
  'active_min': MetricSpec(
    chartKey: 'active_min',
    title: 'Movement minutes',
    unit: 'min',
    color: C.green,
    icon: LucideIcons.activity,
    method: 'Minutes whose acceleration sits above a movement floor. That floor '
        'is pooled from your own recent days once there are enough of them, and '
        'a population one before that. This is activity VOLUME, not locomotion: '
        'steps are counted by a pedometer and are never derived from it.',
    citation: 'ENMO over a personal dynamic-range floor',
    requires: {InputSignal.accel1Hz},
  ),
  'wear': MetricSpec(
    chartKey: 'wear',
    title: 'Wear time',
    unit: 'min',
    color: C.green,
    icon: LucideIcons.watch,
    method: 'Minutes with a band record present. The band logs to flash only '
        'while it is on a wrist, so record presence IS wear.',
    citation: 'Record-presence, not heart-rate validity',
    requires: {InputSignal.accel1Hz},
  ),

  // ── charted nowhere, on purpose ──
  'skin_temp': MetricSpec(
    chartKey: 'skin_temp',
    title: 'Skin temperature',
    color: C.orange,
    icon: LucideIcons.thermometer,
    higherBetter: false,
    suppress: 'A deviation, not a temperature. Imported nights carry different '
              'units, so they are not charted together.',
    suppressFix: 'Shown tonight on Vitals',
    method: 'The night\'s mean raw sensor reading, expressed as distance from '
        'your own recent nights. There is no conversion to degrees anywhere in '
        'the path.',
    citation: 'Relative only — uncalibrated ADC',
    requires: {InputSignal.skinTempRaw},
  ),
  // `spo2`, `odi_per_hour` and `strain_effort` used to live here as cards that
  // existed only to explain that they were empty. A metric this app does not
  // produce has no entry, no card and no key. See docs/internal/UI_ROADMAP.md.
  //
  // `rmssd_whole`, `stress_si` and `brv_slope` used to live here too, on the
  // same mistake in a quieter form: three fully written specs — title, unit,
  // colour, method, citation — whose whole rendered content was a card saying
  // they cannot be charted. Each is a bundle scalar and none of the three keys
  // is ever written to `metric_series`, so the series behind them is 0 rows and
  // always was. Nothing in the tree ever constructed them, the Explore
  // catalogue excludes them by name, and a spec that can only ever explain its
  // own emptiness is the absent-forever rule again. `stress` and `brv` are the
  // charted forms of two of the three and they stay.
};

MetricSpec specOf(String key) =>
    _specs[key] ??
    MetricSpec(chartKey: key, title: key.replaceAll('_', ' '));

/// Which cross-day percentile block and journal outcome, if any, belongs to
/// this metric. Only four outcomes are correlated by the journal engine.
const _outcomeOf = {
  'hrv': 'rmssd',
  'resting_hr': 'rhr',
  'readiness': 'readiness',
  'efficiency': 'efficiency',
};

// ═══════════════════ the screen ═══════════════════

class MetricData {
  /// DATED points, not bare values. `metric_series` holds one row per DERIVED
  /// day rather than one per calendar day, so a compacted list lets 22 stored
  /// days masquerade as 30 continuous ones — the chart then joins straight
  /// across a sync gap and calls the newest stored point "Today".
  final List<ChartPoint> series;

  /// L4 — THE DENOMINATOR. Worn minutes for the same days, off the same
  /// `getChart` call. A long trend drawn without it is an attendance chart
  /// wearing a physiology label: it cannot make a sparse month comparable, only
  /// refuse to pretend one is.
  final List<ChartPoint> wear;
  final Map<String, dynamic>? percentile;
  final List<Map<String, dynamic>> movers;

  /// Days this install actually has a derived record for. Nothing prunes
  /// `day_result` or `metric_series`, so this is the true horizon — and it is
  /// what decides which range buttons exist.
  final int daysAvailable;

  /// Noon stamps on the days where the algorithm version CHANGED — the days
  /// either side were not produced the same way.
  ///
  /// `getChart` has attached this to every result all along and the only thing
  /// reading it was the briefing engine, so a trend drew straight through a
  /// release boundary. This export holds three versions of the same days and
  /// readiness moved across them: 2026-08-08 went 43.8 → 47.9.
  final List<int> algoBreaks;

  /// The daily step-goal target, read from the profile. Only ever loaded for
  /// `key == 'steps'` — every other metric leaves it at the default and never
  /// draws it.
  final int stepGoal;

  /// WHICH DEVICES CONTRIBUTED TO EACH DAY in this series, keyed by day label.
  ///
  /// A DAY, NOT A SPAN. `MetricDetail`'s scrubber is per-calendar-day
  /// (`_dayOfSlot`), so a day with two contributing devices has no single
  /// owner and claiming one would be fabricated precision (final-plan §1.4,
  /// §4.4). Values are `device_id`s — `''` is the primary band.
  ///
  /// EMPTY on every single-device day, and on every day derived before schema
  /// 50: `metric_series_version.coverage_devices` is NULL there and NULL is
  /// never retro-filled with a guess. An empty map makes every gate in §8
  /// false, which is what keeps this screen byte-identical for one device.
  final Map<String, List<String>> coverage;

  /// WHAT WAS PHYSICALLY RECORDING on each day, keyed by day label, from
  /// `device_coverage` — which is written at ingest and never pruned, so it
  /// answers for days whose substrate is long gone.
  ///
  /// Loaded ONLY when [coverage] already shows two or more distinct devices
  /// across the window. Its single job is the middle row of §6.2's table:
  /// separating "your ring was on your finger and produced nothing" from
  /// "nothing was on your body". A single-device install never pays for it.
  final Map<String, List<String>> recording;

  /// The filter's rows. Registry facts crossed with [coverage] — see
  /// [_deviceOptions]. Empty means no filter is drawn.
  final List<DeviceOption> sources;

  /// The device whose data [series] holds, or NULL for the merged view.
  ///
  /// Null is the ONLY value on this screen in M6: `metric_series` holds one
  /// merged value per day and a per-device daily trend does not exist and must
  /// not be faked (final-plan §6.4, §7.3). Selecting a device DIMS the days it
  /// did not contribute to; it does not re-query.
  final String? viewingDeviceId;

  const MetricData({
    this.series = const [],
    this.wear = const [],
    this.percentile,
    this.movers = const [],
    this.daysAvailable = 0,
    this.algoBreaks = const [],
    this.stepGoal = kDefaultStepGoal,
    this.coverage = const {},
    this.recording = const {},
    this.sources = const [],
    this.viewingDeviceId,
  });

  static Future<MetricData> load(
    LocalRepository repo,
    String key, {
    /// Registry-only candidates, from `signalCandidates(app, requires: …)`.
    /// Const-empty default so every existing caller and every test compiles
    /// unchanged and gets today's screen.
    List<DeviceOption> candidates = const [],
  }) async {
    final spec = specOf(key);
    if (spec.suppress != null) return const MetricData();
    final chart = await repo.getChart(
      spec.chartKey,
      signals: {for (final s in spec.requires) s.name},
    );
    final days = await repo.availableDays();
    final outcome = _outcomeOf[key];
    final stepGoal = key == 'steps'
        ? ((await repo.getProfile())['step_goal'] as num?)?.toInt() ??
            kDefaultStepGoal
        : kDefaultStepGoal;

    Map<String, dynamic>? pct;
    var movers = const <Map<String, dynamic>>[];
    if (outcome != null) {
      final cd = await repo.getInsights();
      final all = cd['percentiles'];
      final one = all is Map ? all[outcome] : null;
      pct = envValue(one);
      final j = await repo.getJournalInsights(range: '90d');
      final ins = j['insights'];
      movers = [
        for (final e in (ins is List ? ins : const []))
          if (e is Map && e['outcome'] == outcome) e.cast<String, dynamic>(),
      ];
    }
    final coverage = _coverageOf(chart['coverage_devices']);
    final recording = _coverageOf(chart['coverage_recording']);
    return MetricData(
      series: pointsOf(chart),
      wear: pointsOf({'points': chart['wear']}),
      percentile: pct,
      movers: movers,
      daysAvailable: days.length,
      algoBreaks: [
        for (final b in (chart['algo_breaks'] as List? ?? const []))
          if (b is Map && b['t'] is num) (b['t'] as num).round(),
      ],
      stepGoal: stepGoal,
      coverage: coverage,
      recording: recording,
      sources: _deviceOptions(candidates, coverage),
      // viewingDeviceId stays null: see the field's doc.
    );
  }
}

/// `{day: [deviceId, …]}` out of a `getChart` payload. A malformed or absent
/// key is an EMPTY map, never a partial one — a half-read coverage map would
/// attribute a day to fewer devices than actually fed it, which is the one
/// error this whole feature exists to avoid making.
Map<String, List<String>> _coverageOf(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, List<String>>{};
  for (final e in raw.entries) {
    final day = e.key;
    final ids = e.value;
    if (day is! String || ids is! List) continue;
    out[day] = [for (final v in ids) if (v is String) v];
  }
  return out;
}

/// Registry candidacy crossed with what the window actually holds.
///
/// A candidate with no coverage anywhere in the window stays SELECTABLE and
/// gains a reason — "you may ask this device, and the answer for this window is
/// nothing" is a different statement from "this device cannot answer at all",
/// and §6.3 draws both.
List<DeviceOption> _deviceOptions(
  List<DeviceOption> candidates,
  Map<String, List<String>> coverage,
) {
  if (candidates.length < 2) return const [];
  final seen = {for (final ids in coverage.values) ...ids};
  return [
    for (final o in candidates)
      if (!o.selectable || seen.contains(o.deviceId))
        o
      else
        (
          deviceId: o.deviceId,
          label: o.label,
          selectable: true,
          reason: 'no data in this range',
        ),
  ];
}

// ═══════════════════ shared detail chrome ═══════════════════

/// Every detail screen is the same frame: a back bar, then a scroll. Keeping it
/// in one function is the reason the back affordance is in the same place on
/// all of them.
Widget detailScaffold(BuildContext c, String title, List<Widget> body,
    {String sub = '', Widget? trailing}) {
  final p = P.of(c);
  return Scaffold(
    backgroundColor: p.bg,
    body: SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x4),
          child: NavBar(title,
              sub: sub,
              trailing: trailing,
              onBack: () => Navigator.of(c).maybePop()),
        ),
        Expanded(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x12),
              children: body),
        ),
      ]),
    ),
  );
}

// ═══════════════════ which day a detail screen is showing ═══════════════════
//
// Nothing prunes `day_result`, so an install holds every day it has ever
// derived — and until this existed every single-day screen resolved `days.first`
// and stopped there. The chart on this screen would happily draw the night
// somebody's sleep collapsed and offer no way into it.

/// The day a single-day screen should load: the one it was OPENED with when
/// that day exists, else the screen's own idea of now, else the newest day on
/// disk.
///
/// [want] is the day the caller asked for and [prefer] the screen's own
/// resolution (`today_day`, a held-over night). With no [want] this is exactly
/// what every loader did inline, which is why passing no day changes nothing.
String? pickDay(List<String> days, String? want, [String? prefer]) {
  final d = want ?? prefer;
  // No derived days at all: there is nothing to fall back TO, so the caller's
  // own answer stands or the screen renders its absence.
  if (days.isEmpty) return d;
  if (d != null && days.contains(d)) return d;
  return days.first;
}

/// 'Today' when it is, otherwise the day itself. Never "N days ago" — a
/// control you steer with needs the name of the place, not the distance to it.
String dayNavLabel(String? day) =>
    (_dayBehind(day) ?? 1) <= 0 ? 'Today' : prettyDay(day);

int? _dayBehind(String? dayId) {
  final d = dayId == null ? null : DateTime.tryParse(dayId);
  return d == null ? null : calendarDaysBetween(d, DateTime.now());
}

/// The calendar, restricted to the days that exist. A picker that offers an
/// empty day is a dead end, so [days] greys out everything it does not contain.
Future<String?> chooseDay(
    BuildContext c, List<String> days, String? current) async {
  if (days.isEmpty) return null;
  final have = days.toSet();
  final sorted = [...days]..sort(); // oldest → newest
  final first = DateTime.parse(sorted.first);
  final last = DateTime.parse(sorted.last);
  final want = DateTime.tryParse(current ?? '') ?? last;
  final picked = await showDatePicker(
    context: c,
    initialDate: want.isBefore(first) ? first : (want.isAfter(last) ? last : want),
    firstDate: first,
    lastDate: last,
    selectableDayPredicate: (d) => have.contains(dayLabelOf(d)),
    helpText: AppLocalizations.of(c)?.metricDetailChooseDayHelp ?? 'Choose a day',
  );
  return picked == null ? null : dayLabelOf(picked);
}

/// The day stepper every single-day screen wears under its nav bar.
///
/// [days] is `availableDays()` — NEWEST FIRST, and only days that derived. Both
/// arrows and the picker walk that list, so there is no way to steer onto a day
/// this install has no record of. With fewer than two days there is nowhere to
/// go and the control renders nothing rather than two dead arrows.
class DayNav extends StatelessWidget {
  final String? day;
  final List<String> days;
  final ValueChanged<String> onDay;

  const DayNav({
    super.key,
    required this.day,
    required this.days,
    required this.onDay,
  });

  @override
  Widget build(BuildContext c) {
    if (days.length < 2) return const SizedBox.shrink();
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final i = days.indexOf(day ?? '');
    // days is newest first: the OLDER day is further down the list.
    final older = i < 0 ? days.first : (i + 1 < days.length ? days[i + 1] : null);
    final newer = i > 0 ? days[i - 1] : null;

    Widget arrow(IconData icon, String label, String? to) => Opacity(
          opacity: to == null ? .35 : 1,
          child: Pressable(
            onTap: to == null ? null : () => onDay(to),
            semanticLabel: label,
            child: Icon(icon, size: 20, color: p.ink),
          ),
        );

    return Container(
      decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
      child: Row(children: [
        arrow(LucideIcons.chevronLeft, l?.metricDetailPreviousDay ?? 'Previous day',
            older),
        Expanded(
          child: Pressable(
            onTap: () async {
              final picked = await chooseDay(c, days, day);
              if (picked != null && picked != day) onDay(picked);
            },
            semanticLabel: l?.metricDetailChooseDayShowing(dayNavLabel(day)) ??
                'Choose a day. Showing ${dayNavLabel(day)}',
            child: Text(
              dayNavLabel(day),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        arrow(LucideIcons.chevronRight, l?.metricDetailNextDay ?? 'Next day', newer),
      ]),
    );
  }
}

/// [DayNav] and the gap under it, spread into a `detailScaffold` body — or
/// nothing at all when there is only one day to look at.
List<Widget> dayNavRow(
        String? day, List<String> days, ValueChanged<String> onDay) =>
    days.length < 2
        ? const []
        : [
            DayNav(day: day, days: days, onDay: onDay),
            const SizedBox(height: S.x3),
          ];

/// A plain door onto another screen. Deliberately quiet: a doorway is not a
/// card, and a metric screen that grows a second loud card stops having a
/// headline.
Widget detailLinkRow(BuildContext c, IconData icon, String title, String sub,
    VoidCallback onTap) {
  final p = P.of(c);
  return Pressable(
    onTap: onTap,
    semanticLabel: '$title: $sub',
    child: Container(
      padding: const EdgeInsets.all(S.x4),
      decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
      child: Row(children: [
        Icon(icon, size: 17, color: p.ink3),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            Text(sub, style: F.over.copyWith(color: p.ink3)),
          ]),
        ),
        Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
      ]),
    ),
  );
}

/// The door into density 3 — the screen the user sees as "Nerd stats". Kept
/// deliberately plain: it is a workbench entrance, not a feature, and it now
/// reads as a companion to the picture above it rather than as the place the
/// interesting numbers are hiding.
///
/// The identifier stays `investigateRow` to match `investigate.dart` and the
/// `investigate_row` gallery key; only the string changed.
Widget investigateRow(BuildContext c, VoidCallback onTap) => detailLinkRow(
    c,
    LucideIcons.cpu,
    AppLocalizations.of(c)?.metricDetailNerdStatsTitle ?? 'Nerd stats',
    // One line at 1x. A subtitle that wraps makes this row taller than every
    // other `detailLinkRow` in the app, which is a layout change dressed up as
    // a copy change — keep it at or under the old string's length.
    AppLocalizations.of(c)?.metricDetailNerdStatsSub ??
        'The figures behind the picture',
    onTap);

/// A two-column legend. Used by the hypnogram and the overnight stack.
class Legend extends StatelessWidget {
  final List<(String, Color)> items;
  const Legend(this.items, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Wrap(
      spacing: S.x4,
      runSpacing: S.x2,
      children: [
        for (final e in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: e.$2, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(e.$1, style: F.over.copyWith(color: p.ink2)),
          ]),
      ],
    );
  }
}

/// The mono table Nerd stats is built from — label left, value right, both in
/// a fixed-pitch face so columns line up and nothing pretends to be prose.
class MonoTable extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const MonoTable(this.title, this.rows, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    // A row with nothing behind it is dropped, not dashed. On a workbench an
    // em-dash reads as "we tried and got nothing", which is indistinguishable
    // from "this metric does not apply to this night".
    final present = [for (final r in rows) if (r.$2 != '—' && r.$2.isNotEmpty) r];
    if (present.isEmpty) return const SizedBox.shrink();
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(), style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: S.x3),
        for (final r in present)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(r.$1,
                        style: F.cap
                            .copyWith(color: p.ink3, fontFamily: 'Menlo')),
                  ),
                  const SizedBox(width: S.x3),
                  Flexible(
                    child: Text(r.$2,
                        textAlign: TextAlign.right,
                        style: F.cap.copyWith(
                            color: p.ink,
                            fontFamily: 'Menlo',
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
          ),
      ]),
    );
  }
}
