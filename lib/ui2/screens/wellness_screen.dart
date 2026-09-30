// Wellness — softer than Health, same system.
//
// Health tells you what your body did. Wellness is where you tell it back, and
// where the app explains itself. Three sub-tabs: Mind, Recovery, Habits.
// Medication lives on the canonical OpenBand screen pushed over Journal, not
// here. Cycle tracking is an OpenBand route from Journal/Settings, not a tab.
//
// Habits are a CONSISTENCY, never a streak. "5 of 7 days" cannot reset to
// zero, so a missed day costs a day rather than costing everything.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_analytics/onehz.dart' show journalFieldLagDays;
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../data/day_label.dart';
import '../../data/journal_fields.dart';
import '../../l10n/app_localizations.dart';
import '../../models/metric.dart' show whyFromNote;
import '../../state/app_state.dart';
import '../../stress/breath_phases.dart';
import '../ui2.dart';
import '../../openband/journal_editor.dart';
import '../../openband/journal_fields.dart';
import '../../openband/local_repository.dart';
import 'calm_breathing.dart';
import 'driver_breakdown.dart';
import 'home_screen.dart' show envValue, metricOf;
import 'journal_compose.dart';
import 'start_card.dart';
import 'metric_detail.dart' show detailScaffold;
import 'sleep_detail.dart';

class WellnessScreen extends StatefulWidget {
  const WellnessScreen({super.key});

  /// Fallback labels only — index bookkeeping uses `.length`, and the actual
  /// display labels are localized in `build`.
  static const tabs = ['Mind', 'Recovery', 'Habits'];

  @override
  State<WellnessScreen> createState() => _WellnessScreenState();
}

class _WellnessScreenState extends State<WellnessScreen> with RevisionReload {
  int _tab = 0;

  /// Habit consistency is read over a fortnight: long enough that one bad week
  /// does not read as collapse, short enough to still be about now.
  static const _habitDays = 14;

  /// Read on every use, never captured once: the shell keeps this tab alive in
  /// its IndexedStack, so a field initialiser would still be yesterday after
  /// midnight and habit ticks would land on yesterday's date.
  String get _date => todayLabel();
  bool _loading = true;

  /// One journal write at a time. `putJournalMetrics` deletes the day and
  /// re-inserts it, so two quick taps both read the same day and the second
  /// erased the first.
  bool _writingField = false;

  Map<String, dynamic> _stress = const {};
  Map<String, dynamic> _insights = const {};

  /// The four readiness inputs, each already carrying its reading, this user's
  /// own centre and spread, the signed contribution and the MDC gate. Assembled
  /// by [driverFacts] from three stored things; nothing here computes.
  List<DriverFacts> _drivers = const [];
  Map<String, JournalMetricValue> _todayFields = {};
  List<JournalFieldSpec> _habits = const [];
  List<JournalFieldSpec> _fields = const [];
  Map<String, Map<String, JournalMetricValue>> _habitHistory = const {};
  List<Map<String, dynamic>> _breathing = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Readiness drivers, insights and journal metrics all move under this tab
  /// when a derive or an import runs — and it is one of the three the shell
  /// keeps alive forever, so it read them once and stopped.
  @override
  void reload() => _load();

  Future<void> _load() async {
    final t = beginRead(#wellness);
    final app = context.read<AppState>();
    final repo = app.repo;

    final breathing = await app.breathingHistory(limit: 5);

    var stress = const <String, dynamic>{};
    var insights = const <String, dynamic>{};
    var fields = <String, JournalMetricValue>{};
    var driverRows = const <DriverFacts>[];
    var specs = const <JournalFieldSpec>[];
    if (repo != null) {
      stress = await repo.getDayStress(_date);
      insights = await repo.getInsights();
      // `readiness_glassbox.breakdown`, NOT `.drivers` — drivers is already
      // filtered to the inputs that cleared the smallest-worthwhile-change
      // gate, so an input that sat inside its usual spread was never in it and
      // the screen could not say "and this one did nothing". Same array
      // ReadinessDetail renders, so the two agree by construction.
      final gb = envValue(insights['readiness_glassbox']);
      final bd = gb?['breakdown'];
      // The baselines block: centre, spread, delta and MDC per input. Written
      // on every derive since long before anything read it.
      final heart = await repo.getDayHeart(_date);
      final charts = <String, Object?>{};
      for (final k in driverChartKeys) {
        charts[k] = await repo.getChart(k);
      }
      driverRows = driverFacts(
        breakdown: [
          for (final r in (bd is List ? bd : const []))
            if (r is Map) r.cast<String, dynamic>(),
        ],
        baselines: heart['baselines'] is Map
            ? (heart['baselines'] as Map).cast<String, dynamic>()
            : null,
        charts: charts,
      );
      fields = await repo.getJournalMetrics(_date);
      specs = await repo.getJournalFields();
    }
    // Day arithmetic, not a subtracted duration: a DST day is 23 or 25 hours
    // long and `now - 13 days` lands on the wrong calendar date across one.
    final now = DateTime.now();
    final since = dayLabelOf(
      DateTime(now.year, now.month, now.day - (_habitDays - 1)),
    );
    final history = await LocalDb.journalMetricsByDay(sinceDaysEpoch: since);

    if (!stillNewest(#wellness, t)) return;
    setState(() {
      _breathing = breathing;
      _stress = stress;
      _insights = insights;
      _drivers = driverRows;
      _todayFields = {...fields};
      // A habit is a custom field with a ceiling of one — a per-day yes/no.
      // That is exactly what journal_field_def already stores, which is why
      // there is no habit table.
      _habits = [
        for (final s in specs)
          if (s.custom && s.max == 1) s,
      ];
      _fields = specs;
      _habitHistory = history;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final last = _breathing.isEmpty ? null : _breathing.first;
    final labels = [
      l?.wellnessTabMind ?? 'Mind',
      l?.wellnessTabRecovery ?? 'Recovery',
      l?.wellnessTabHabits ?? 'Habits',
    ];
    final tab = _tab.clamp(0, labels.length - 1);
    // Same rule as Workout: the LIST drops its side padding and hands it to
    // every child except the hero, which is how that one runs edge to edge.
    // The card cannot escape its own parent — a negative margin asserts and an
    // OverflowBox takes an unbounded height in a scroll view and blanks the
    // whole tab. Padding the siblings is ordinary layout and does neither.
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, S.x4, 0, S.x16),
      children: [
        for (final w in <Widget>[
          ScreenTitle(l?.wellnessTitle ?? 'Wellness'),
          SubTabs(labels, tab, (i) => setState(() => _tab = i),
              color: C.domMind),
          const SizedBox(height: S.x5),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            // Mind is the only tab here with something to START. The other
            // two are logs and reviews.
            if (tab == 0) ...[
              StartCard(
                label: l?.wellnessStartASitting ?? 'START A SITTING',
                // What the picker actually offers. Three, not the number of
                // things on this tab.
                count: kBreathPatterns.length,
                noun: l?.wellnessExercisesNoun ?? 'exercises',
                sub: last == null
                    ? (l?.wellnessPickOneAndGo ?? 'Pick one and go')
                    : (l?.wellnessLastMinutes(
                            (_reading(last['seconds']) ?? 0) ~/ 60) ??
                        'Last: ${(_reading(last['seconds']) ?? 0) ~/ 60} min'),
                asset: 'mascot_wellness.png',
                accent: C.domMind,
                deep: C.teal,
                // Sized so the CHARACTER matches Workout's, not the frame.
                // Two corrections got us here: the asset carried ~30%
                // transparent padding (cropped away), and what is left still
                // has a soft halo above the head, so the figure is 87% of the
                // frame height where the workout mascot is 100% of its own.
                // 145 x 0.87 puts the character at ~126, the same as Workout.
                // Not cropped tighter than this on purpose — the halo is nearly
                // opaque, so trimming it slices a hard arc through the artwork.
                // The 118 here was originally compensating for
                // ~30% transparent padding baked into the asset, which made
                // the art render a third smaller than the workout one at the
                // same height. The asset is cropped to its own alpha bounds,
                // so the height is the art's height and the two mascots read
                // as the same size. Still slightly wider than tall (1.03 vs
                // 0.93), and at 126 that is 130 px — narrower than the padded
                // asset was, so the copy has more room than before, not less.
                mascotHeight: 145,
                onTap: () async {
                  await Navigator.of(c).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const CalmBreathing()),
                  );
                  await _load();
                },
              ),
              const SizedBox(height: S.x4),
            ],
            [_mind, _recovery, _habitsTab][tab](c),
          ],
        ])
          if (w is StartCard)
            w
          else
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.x4),
                child: w),
      ],
    );
  }

  // ── MIND ─────────────────────────────────────────────────────────────────

  Widget _mind(BuildContext c) {
    final l = AppLocalizations.of(c);
    // Same rule as `_recovery`'s coach block, and for the same reason: this
    // runs inside `build`, so a leaf of the wrong type here costs the whole
    // screen rather than this one card. See [_reading].
    final stress = _stress['stress'];
    final score = _reading(stress is Map ? stress['score'] : null);
    final level = stress is Map && stress['level'] is String
        ? _stressLevelLabel(l, stress['level'] as String)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The "Paced breathing / Begin" ActionCard used to sit here. It is the
        // hero card above now — same destination, same last-sitting line, one
        // door instead of two.
        MoodPicker(
          value: _todayFields['mood']?.value.round(),
          onChanged: (v) => _setField('mood', v?.toDouble()),
        ),
        const SizedBox(height: S.x4),
        ActionCard(
          l?.wellnessWriteTheDayDown ?? 'Write the day down',
          // Named from the field specs the journal actually holds. The old
          // literal listed four fields and went stale the moment a custom one
          // was added.
          _journalSubtitle(l),
          l?.wellnessOpen ?? 'Open',
          LucideIcons.notebookPen,
          C.blue,
          onTap: () async {
            final app = context.read<AppState>();
            await Navigator.of(c).push(
              MaterialPageRoute<void>(
                builder: (_) => OpenBandJournalEditor(
                  repository: LocalOpenBandRepository(app),
                  day: _date,
                ),
              ),
            );
            await _load();
          },
        ),
        Section(
          l?.wellnessStressLastNight ?? 'Stress last night',
          score == null
              // "Last night had none" was a claim about a gate this screen
              // never read — the stress payload carries no reason, so the card
              // states what stress IS and stops there.
              ? StatusCard(
                  l?.wellnessNoStressTitle ?? 'No stress reading last night',
                  l?.wellnessNoStressBody ??
                      'Stress is read from beat timing while you were resting '
                          'overnight, and last night produced no reading.',
                  icon: LucideIcons.activity,
                )
              : SignalCard(
                  LucideIcons.activity,
                  C.purple,
                  l?.wellnessAutonomicTension ?? 'Autonomic tension',
                  score.round().toString(),
                  unit: '/100',
                  sub: (level ?? '').toUpperCase(),
                ),
        ),
      ],
    );
  }

  /// What the journal will actually ask you, read off its own field specs.
  String _journalSubtitle(AppLocalizations? l) {
    // Not `.toLowerCase()`: these are user-entered/localized field labels
    // (acronyms like HRV, or nouns a language capitalizes) — lowercasing
    // them here would corrupt content the join has no business rewriting.
    final names = [for (final f in _fields) f.label];
    if (names.isEmpty) {
      return l?.wellnessJournalDefaultSubtitle ??
          'Anything you want to remember about today';
    }
    if (names.length <= 4) {
      final joined = names.join(', ');
      return l?.wellnessJournalSubtitleShort(joined) ?? '$joined and a note';
    }
    final joined = names.take(4).join(', ');
    final more = names.length - 4;
    return l?.wellnessJournalSubtitleLong(joined, more) ??
        '$joined and $more more, plus a note';
  }

  Future<void> _setField(String key, double? v) async {
    final repo = context.read<AppState>().repo;
    if (repo == null || _writingField) return;
    setState(() => _writingField = true);
    try {
      // Dirty-only patch of this key. A full-day replace used to wipe every
      // other field written since this tab last loaded.
      final snap = await repo.readJournalDay(_date);
      await repo.patchJournalDay(
        JournalDayPatch.fromBase(
          snap,
          metrics: {
            key: v == null
                ? null
                : JournalMetricValue(
                    v,
                    atMinuteOfDay: snap.metrics[key]?.atMinuteOfDay,
                  ),
          },
        ),
      );
      await _load();
    } on JournalConflict {
      await _load();
    } finally {
      if (mounted) setState(() => _writingField = false);
    }
  }

  // ── RECOVERY ─────────────────────────────────────────────────────────────

  Widget _recovery(BuildContext c) {
    final l = AppLocalizations.of(c);
    final coach = _insights['sleep_coach'];
    final coachMap = coach is Map ? coach.cast<String, dynamic>() : null;
    final needSec = _nested(coachMap, 'need', 'need_sec');
    final bedMin = _nested(coachMap, 'bedtime', 'bedtime_min_of_day');
    final wakeMin = _nested(coachMap, 'wake', 'wake_min_of_day');
    final napMin = _reading(coachMap?['nap_credit_min']);
    final strainMin = _reading(coachMap?['strain_bonus_min']);
    final debtH = _nested(_insights, 'sleep_debt', 'debt_hours');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The one recommendation on this screen, and only when all three of
        // its inputs are real: a measured debt worth acting on, a learned need,
        // and a target bedtime to name. No debt, no card — the widget does not
        // get an invented reason so that it can appear.
        if (debtH != null && debtH >= .75 && needSec != null && bedMin != null)
          Padding(
            padding: const EdgeInsets.only(bottom: S.x5),
            child: Recommendation(
              l?.wellnessTurnInBy(formatMinuteOfDay(bedMin.round())) ??
                  'Turn in by ${formatMinuteOfDay(bedMin.round())}',
              l?.wellnessDebtBody(_hm(debtH * 60), _hm(needSec / 60)) ??
                  'You are ${_hm(debtH * 60)} down against your own need, and '
                      'tonight\'s is ${_hm(needSec / 60)}.',
              l?.wellnessSeeWhatLastNightCost ?? 'See what last night cost you',
              color: C.indigo,
              onTap: () => Navigator.of(c).push(
                MaterialPageRoute<void>(builder: (_) => const SleepDetail()),
              ),
            ),
          ),
        Section(
          l?.wellnessWhatChargedAndDrained ?? 'What charged and drained you',
          // Two words and a full stop, before: "hrv", "rhr". No reading, no
          // usual, no direction, no size, and no way to tell a move that
          // mattered from one inside the noise — all of which were already
          // being written on every derive and read by nothing.
          _drivers.isEmpty
              ? StatusCard(
                  l?.wellnessNoDriversTitle ?? 'No readiness drivers yet',
                  whyFromNote(metricOf(_stress['readiness']).note) ??
                      (l?.wellnessNoDriversBody ??
                          'Needs enough nights to know what normal looks like '
                              'for you.'),
                  icon: LucideIcons.sparkles,
                )
              : DriverBreakdown(_drivers),
        ),
        Section(
          l?.wellnessSleepNeedTonight ?? 'Sleep need tonight',
          needSec == null
              // The coach's own reason for the absent need — it names the
              // input that is actually missing. "Not enough of them yet" named
              // nothing, and was printed for every cause the estimator has.
              ? StatusCard(
                  l?.wellnessNoSleepNeedTitle ?? 'No sleep need yet',
                  whyFromNote(_noteOf(coachMap?['need'])) ??
                      (l?.wellnessNoSleepNeedBody ??
                          'Nothing recorded says why there is no need for '
                              'tonight.'),
                  icon: LucideIcons.bedDouble,
                )
              : Surface(
                  child: Column(
                    children: [
                      MetricRow(
                        LucideIcons.bedDouble,
                        C.blue,
                        l?.wellnessTonightsNeed ?? 'Tonight\'s need',
                        _hm(needSec / 60),
                      ),
                      // Null here means "we do not know", which is why it is a
                      // missing row rather than "+0 min".
                      if (debtH != null)
                        MetricRow(
                          LucideIcons.trendingDown,
                          C.orange,
                          l?.wellnessSleepDebt ?? 'Sleep debt',
                          _hm(debtH * 60),
                        ),
                      if (strainMin != null)
                        MetricRow(
                          LucideIcons.flame,
                          C.purple,
                          l?.wellnessAddedForStrain ?? 'Added for strain',
                          '${strainMin.round()}',
                          unit: 'min',
                        ),
                      if (napMin != null)
                        MetricRow(
                          LucideIcons.sun,
                          C.yellow,
                          l?.wellnessCreditedFromNaps ?? 'Credited from naps',
                          '${napMin.round()}',
                          unit: 'min',
                        ),
                      if (bedMin != null)
                        MetricRow(
                          LucideIcons.moon,
                          C.indigo,
                          l?.wellnessTargetBedtime ?? 'Target bedtime',
                          formatMinuteOfDay(bedMin.round()),
                        ),
                      if (wakeMin != null)
                        MetricRow(
                          LucideIcons.sunrise,
                          C.orange,
                          l?.wellnessTargetWake ?? 'Target wake',
                          formatMinuteOfDay(wakeMin.round()),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ── HABITS ───────────────────────────────────────────────────────────────

  Widget _habitsTab(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final h in _habits)
          Padding(
            padding: const EdgeInsets.only(bottom: S.x3),
            child: Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          h.label,
                          style: F.body.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _Check(
                        on: (_todayFields[h.key]?.value ?? 0) >= 1,
                        // Null while a write is in flight: the tick is a
                        // read-modify-write of the whole day, and a second tap
                        // during the first one used to erase it.
                        onTap: _writingField
                            ? null
                            : () => _setField(
                                h.key,
                                (_todayFields[h.key]?.value ?? 0) >= 1
                                    ? null
                                    : 1,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x3),
                  Consistency(
                    _habitDaysDone(h.key),
                    _habitDays,
                    l?.wellnessDaysYouDidIt ?? 'Days you did it',
                    C.domMind,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: S.x4),
        BigButton(
          l?.wellnessAddAHabit ?? 'Add a habit',
          icon: LucideIcons.plus,
          color: C.domMind,
          soft: true,
          onTap: () => _openCustomFields(c),
        ),
        // MIND-01/04/12 — the whole dose-response and habit-difference half of
        // journal analysis, plus the weekday test, behind ONE door. It has
        // lived here computed-and-discarded for months; putting the rows on
        // this tab would bury the thing the tab is for, which is ticking.
        const SizedBox(height: S.x5),
        ActionCard(
          l?.wellnessWhatYouLogTitle ?? 'What you log, against your numbers',
          l?.wellnessWhatYouLogSubtitle ??
              'Dose, habit difference, and the day of the week',
          l?.wellnessOpen ?? 'Open',
          LucideIcons.scatterChart,
          C.domMind,
          onTap: () => Navigator.of(c).push(
            MaterialPageRoute<void>(builder: (_) => const JournalFindings()),
          ),
        ),
      ],
    );
  }

  int _habitDaysDone(String key) {
    var n = 0;
    for (final day in _habitHistory.values) {
      if ((day[key]?.value ?? 0) >= 1) n++;
    }
    return n;
  }

  Future<void> _openCustomFields(BuildContext c) async {
    final app = context.read<AppState>();
    await Navigator.of(c).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OpenBandJournalFields(
          repository: LocalOpenBandRepository(app),
          day: _date,
        ),
      ),
    );
    if (mounted) await _load();
  }

}

// ── helpers ────────────────────────────────────────────────────────────────

/// Pull a number out of a nested `Metric` envelope whose `value` is itself an
/// object — `{value: {need_sec: …}}`. Returns null rather than parsing the
/// envelope as a scalar, which would read a real value object as an absence.
double? _nested(Map<String, dynamic>? blk, String key, String field) {
  final m = blk?[key];
  if (m is! Map) return null;
  final v = m['value'];
  return _reading(v is Map ? v[field] : v);
}

/// A stored leaf as a number this screen can print, or null.
///
/// TESTED, NEVER CAST, and the finite check is not belt-and-braces. Every
/// caller of this is evaluated inside `_recovery`, which `build` CALLS — so a
/// throw here is not a broken card, it is `WellnessScreen.build` failing, the
/// whole domain replaced by an `ErrorWidget`, and `RenderErrorBox` painting
/// `0xF0C0C0C0` over the page. On a release build that is a flat grey screen
/// with a working nav bar beside it and nothing anywhere that says why.
///
/// Two ways in, and neither is hypothetical enough to leave open:
///   · `x as num?` tolerates null and NOTHING ELSE, so one leaf stored as a
///     String — an older artifact, a hand-edited backup, an import — throws.
///   · `.round()` throws `UnsupportedError` on NaN and infinity, and every
///     number here is rounded a few lines later (`_hm`, `formatMinuteOfDay`,
///     the strain and nap rows). `1e999` in JSON decodes to `Infinity`.
///
/// The write seam already learned this: `sanitizeForJson` nulls a non-finite
/// leaf rather than letting `jsonEncode` throw, because "the artifact is a bag
/// of independent metrics, so it must degrade one field at a time". Same rule,
/// read side. A leaf we cannot read is ABSENT — which every branch below
/// already renders honestly — instead of costing the screen.
double? _reading(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

/// The `note` off a metric envelope, when there is one and it is prose.
///
/// `(x as Map?)?['note'] as String?` was two unguarded casts on the ABSENCE
/// branch — the one that renders for every account that has no learned sleep
/// need yet, which is the widest audience this screen has.
String? _noteOf(Object? envelope) {
  if (envelope is! Map) return null;
  final note = envelope['note'];
  return note is String ? note : null;
}

String _hm(double minutes) {
  final sign = minutes < 0 ? '−' : '';
  final t = minutes.abs().round();
  return t < 60 ? '$sign${t}m' : '$sign${t ~/ 60}h ${t % 60}m';
}

/// A label and a sentence. Used by journal findings and habit effects, both of
/// which genuinely have only those two things.
///
/// It is NOT the readiness driver row any more — that claim ("the glass box
/// does not emit per-driver point contributions") was wrong, and it is what
/// kept "What charged and drained you" printing two bare words. The breakdown
/// carries a weight, a signed contribution and a spread gate per input, and
/// the baselines block carries the reading, the centre, the spread and the MDC.
/// See [DriverBreakdown].
class DriverRow extends StatelessWidget {
  const DriverRow({super.key, required this.label, required this.detail});

  final String label, detail;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.dot, size: 18, color: p.on(C.domMind)),
          const SizedBox(width: S.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: F.body.copyWith(color: p.ink)),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: F.over.copyWith(color: p.ink3, height: 1.4),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The pinned analytics package returns 'low'/'normal'/'elevated'/'high' —
/// English regardless of locale. Map to the localized word before display.
String? _stressLevelLabel(AppLocalizations? l, String raw) {
  switch (raw) {
    case 'low':
      return l?.wellnessStressLevelLow ?? raw;
    case 'normal':
      return l?.wellnessStressLevelNormal ?? raw;
    case 'elevated':
      return l?.wellnessStressLevelElevated ?? raw;
    case 'high':
      return l?.wellnessStressLevelHigh ?? raw;
    default:
      return raw;
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.on, required this.onTap});
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final box = AnimatedContainer(
      duration: motion(c, Motion.base),
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? p.fill(C.green) : p.card2,
        border: on ? null : Border.all(color: p.line, width: 1.6),
      ),
      child: on
          ? Icon(LucideIcons.check, size: 15, color: p.inkOnFill)
          : const SizedBox.shrink(),
    );
    if (onTap == null) return box;
    final l = AppLocalizations.of(c);
    return Pressable(
      semanticLabel: on
          ? (l?.actionDone ?? 'Done')
          : (l?.wellnessMarkDone ?? 'Mark done'),
      onTap: onTap,
      child: box,
    );
  }
}

// ══════════════════ WHAT YOU LOG, AGAINST YOUR NUMBERS ══════════════════
//
// MIND-01 (dose response), MIND-04 (habits), MT-06 (caffeine timing),
// MT-07 (alcohol phrasing) and MIND-12 (weekday) all answer the same question
// from the same place, so they are one screen behind one tap rather than five
// cards competing on the Habits tab.
//
// EVERYTHING HERE IS ASSOCIATION ON YOUR OWN DAYS. Never cause, never a
// recommendation, never a nudge. The confound is total and stated: the days you
// do a thing are days you were already that kind of day.
//
// The empty state is the DEFAULT outcome, not an error. 9 built-in numeric
// fields × 4 outcomes is 36 simultaneous tests, so a per-test gate manufactures
// about two findings per user out of pure noise; analytics corrects the whole
// grid with Benjamini-Hochberg and most people will see nothing. A screen that
// cannot say "nothing separated itself" is a screen that will invent something.

class JournalFindings extends StatefulWidget {
  /// Non-null skips the repository, the way every other detail screen here
  /// takes its fixture.
  final List<Map<String, dynamic>>? rows;
  final Map<String, dynamic>? weekday;

  const JournalFindings({super.key, this.rows, this.weekday});

  @override
  State<JournalFindings> createState() => _JournalFindingsState();
}

class _JournalFindingsState extends State<JournalFindings> {
  List<Map<String, dynamic>> _rows = const [];
  Map<String, dynamic> _weekday = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.rows != null) {
      _rows = widget.rows!;
      _weekday = widget.weekday ?? const {};
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = context.read<AppState>().repo;
    if (repo == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final j = await repo.getJournalInsights(range: '90d');
      final w = await repo.getWeekdayEffect();
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final e in (j['numeric_insights'] as List? ?? const []))
            if (e is Map) e.cast<String, dynamic>(),
        ];
        _weekday = w;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final title = l?.wellnessWhatYouLogScreenTitle ?? 'What you log';
    if (_loading) {
      return detailScaffold(c, title, const [
        SizedBox(height: S.x8),
        Center(child: CircularProgressIndicator()),
      ]);
    }
    final p = P.of(c);
    final doses = [
      for (final r in _rows)
        if (r['binary'] != true) r,
    ];
    final habits = [
      for (final r in _rows)
        if (r['binary'] == true) r,
    ];
    return detailScaffold(c, title, [
      const SizedBox(height: S.x2),
      if (_rows.isEmpty)
        StatusCard(
          l?.wellnessNothingSeparatedTitle ?? 'Nothing separated itself yet',
          l?.wellnessNothingSeparatedBody ??
              'Everything you log is tested against your recovery, HRV, '
                  'resting heart rate and sleep efficiency. Nothing has '
                  'cleared the bar yet.',
          icon: LucideIcons.scatterChart,
        )
      else ...[
        if (habits.isNotEmpty)
          Section(
            l?.wellnessTheDaysYouDidIt ?? 'The days you did it',
            _list(c, habits),
          ),
        if (doses.isNotEmpty)
          Section(
            l?.wellnessHowMuchAndWhatFollowed ?? 'How much, and what followed',
            _list(c, doses),
          ),
        const SizedBox(height: S.x2),
        Text(
          l?.wellnessLinkNeverCause ??
              'A link on your own days — never a cause. The days you do a '
                  'thing are days you were already that kind of day.',
          style: F.over.copyWith(color: p.ink3, height: 1.5),
        ),
      ],
      Section(
        l?.wellnessWhichDayOfWeek ?? 'Which day of the week',
        _weekdayCard(c),
      ),
    ]);
  }

  Widget _list(BuildContext c, List<Map<String, dynamic>> rows) {
    final l = AppLocalizations.of(c);
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Column(
        children: [
          for (final r in rows)
            DriverRow(label: _headline(l, r), detail: _detail(l, r)),
        ],
      ),
    );
  }

  // ── copy ────────────────────────────────────────────────────────────────

  /// MT-07's whole change: the outcome's own units on the days she logged it,
  /// not a rank correlation read out loud. "On the 11 nights you logged
  /// alcohol, your resting HR ran 6 bpm higher" is the same finding the rho
  /// carried and a sentence a person can check against their own memory.
  String _headline(AppLocalizations? l, Map<String, dynamic> r) {
    final field = (r['field_label'] ?? '').toString();
    final outcome = (r['outcome_label'] ?? '').toString();
    final unit = (r['unit'] ?? '').toString();
    if (r['binary'] == true) {
      final delta = (r['delta'] as num?)?.toDouble() ?? 0;
      final direction = delta > 0
          ? (l?.wellnessHigher ?? 'higher')
          : (l?.wellnessLower ?? 'lower');
      final n = '${r['n_with']}';
      final amount = _amount(delta.abs(), unit);
      return l?.wellnessHeadlineBinary(n, field, outcome, amount, direction) ??
          'On the $n days you logged $field, $outcome ran $amount $direction';
    }
    final n = '${r['n']}';
    final slope = (r['slope_per_unit'] as num?)?.toDouble();
    final rho = (r['rho'] as num?)?.toDouble() ?? 0;
    if (slope == null) {
      final direction = rho > 0
          ? (l?.wellnessHigher ?? 'higher')
          : (l?.wellnessLower ?? 'lower');
      return l?.wellnessHeadlineNoSlope(n, field, direction, outcome) ??
          'On the $n days you logged $field, more of it went with '
              '$direction $outcome';
    }
    final (per, step) = _perUnit(l, r);
    final direction = slope > 0
        ? (l?.wellnessHigher ?? 'higher')
        : (l?.wellnessLower ?? 'lower');
    final amount = _amount((slope * per).abs(), unit);
    return l?.wellnessHeadlineSlope(n, field, outcome, amount, direction, step) ??
        'On the $n days you logged $field, $outcome ran '
            '$amount $direction per $step';
  }

  /// MIND-02 — WHICH NIGHT this row is about.
  ///
  /// Outcomes labelled with a date come from the night that ENDED on that
  /// morning, while the journal row is written at bedtime and describes the
  /// daytime. So analytics pairs each field at its own lag: behaviour (coffee,
  /// alcohol, water, steps) lands on the night that FOLLOWS, and a
  /// retrospective self-report (mood, sleep quality, soreness) already
  /// describes the night that just finished. It is never a blanket shift — the
  /// two kinds point in opposite directions and one constant breaks half of
  /// them.
  ///
  /// Said out loud on every row, because the alignment changed underneath
  /// findings people had already read, and a finding that quietly means a
  /// different night is a different finding.
  String _alignment(AppLocalizations? l, Map<String, dynamic> r) {
    // Read from the same constant analytics paired on, so the sentence cannot
    // drift away from the arithmetic.
    final field = (r['field'] ?? '').toString();
    // The two derived caffeine-timing keys carry caffeine's own lag.
    final lag =
        journalFieldLagDays[field] ??
        (field.startsWith('caffeine') ? journalFieldLagDays['caffeine'] : null);
    if (lag == null) {
      return l?.wellnessMatchedSameDay ?? 'Matched against the same day\'s numbers.';
    }
    return lag > 0
        ? (l?.wellnessMatchedNightFollowed ??
            'Matched against the night that followed.')
        : (l?.wellnessMatchedNightEnded ??
            'Matched against the night that ended that morning.');
  }

  String _detail(AppLocalizations? l, Map<String, dynamic> r) {
    final when = _alignment(l, r);
    if (r['binary'] == true) {
      final d = (r['cohens_d'] as num?)?.toDouble();
      final n = '${r['n_without']}';
      final against = l?.wellnessAgainstDaysYouDidNot(n) ??
          'Against the $n days you did not';
      return '$against'
          '${d == null ? '' : ' · d ${d.abs().toStringAsFixed(1)}'}. $when';
    }
    final lo = (r['rho_low'] as num?)?.toDouble();
    final hi = (r['rho_high'] as num?)?.toDouble();
    final rho = (r['rho'] as num?)?.toDouble();
    final ci = (lo == null || hi == null)
        ? ''
        : ' (${l?.wellnessRangeTo(lo.toStringAsFixed(2), hi.toStringAsFixed(2)) ?? '${lo.toStringAsFixed(2)} to ${hi.toStringAsFixed(2)}'})';
    final base = rho == null
        ? ''
        : (l?.wellnessRankCorrelation(rho.toStringAsFixed(2), ci) ??
            'Rank correlation ${rho.toStringAsFixed(2)}$ci. ');
    // MT-06's own ceiling, said where the finding is: `at_min` is the LAST
    // occurrence, so timing cannot tell two coffees from five, and a late
    // stressful day produces both the late coffee and the bad night.
    if (r['field'] == 'caffeine_last_min') {
      return '$base$when ${l?.wellnessCaffeineCaveat ?? 'This is your last '
          'caffeine of the day only — two cups and five look identical '
          'here, so "later" can quietly mean "more". A long, stressful day '
          'produces both the late coffee and the poor night.'}';
    }
    return '$base$when'.trim();
  }

  /// How to say one step of this field. Minutes-past-midnight is unreadable per
  /// minute, so caffeine timing is stated per HOUR later — a slope, never a
  /// cutoff time, which is a threshold read off a dozen self-reported points.
  (double, String) _perUnit(AppLocalizations? l, Map<String, dynamic> r) {
    if (r['field'] == 'caffeine_last_min') {
      return (60.0, l?.wellnessHourLater ?? 'hour later');
    }
    final u = (r['field_unit'] ?? '').toString();
    // Singular: the phrase is "per unit", "per mg", "per point".
    final one = u.isEmpty
        ? (l?.wellnessPointUnit ?? 'point')
        : (u.endsWith('s') ? u.substring(0, u.length - 1) : u);
    return (1.0, one);
  }

  String _amount(double v, String unit) {
    final n = v >= 10 ? v.round().toString() : v.toStringAsFixed(1);
    return unit.isEmpty ? n : '$n $unit';
  }

  // ── MIND-12 ─────────────────────────────────────────────────────────────

  /// Two gates, and both of them refusing is the normal answer. Kruskal-Wallis
  /// across the seven groups, then a permutation test on the biggest gap — the
  /// second one is what pays for having looked at seven days and reported the
  /// worst. Without it this is a machine for manufacturing weekday
  /// superstitions.
  Widget _weekdayCard(BuildContext c) {
    final l = AppLocalizations.of(c);
    if (_weekday['present'] != true) {
      return StatusCard(
        l?.wellnessNotEnoughWeeksTitle ?? 'Not enough weeks yet',
        l?.wellnessNotEnoughWeeksBody ??
            'Comparing seven weekdays needs at least eight weeks of days, '
                'with five of every weekday in them.',
        icon: LucideIcons.calendarDays,
      );
    }
    if (_weekday['meaningful'] != true) {
      return StatusCard(
        l?.wellnessNoDayStandsOutTitle ?? 'No day of the week stands out',
        l?.wellnessNoDayStandsOutBody ??
            'No day stands apart from the other six once we account for '
                'having checked all seven.',
        icon: LucideIcons.calendarDays,
      );
    }
    final day = (_weekday['peak_weekday'] as num?)?.toInt() ?? 1;
    final delta = (_weekday['peak_delta'] as num?)?.toDouble() ?? 0;
    final n = (_weekday['n_by_weekday'] as Map?)?['$day'];
    final direction = delta > 0
        ? (l?.wellnessHigher ?? 'higher')
        : (l?.wellnessLower ?? 'lower');
    final weekdayPlural = _weekdayPlural(l, day);
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      child: DriverRow(
        label: l?.wellnessWeekdayHeadline(
              weekdayPlural,
              '${delta.abs().round()}',
              direction,
            ) ??
            '${_weekdayName(day)}s: readiness runs '
                '${delta.abs().round()} $direction than your overall median',
        detail: l?.wellnessWeekdayDetail('$n') ??
            'From $n of them. A weekday is not a cause — it is a container '
                'for what you do on it. Nothing here is advice.',
      ),
    );
  }
}

/// The localized plural weekday name ("Mondays"), for [weekday] 1 = Monday.
String _weekdayPlural(AppLocalizations? l, int weekday) {
  final fallback = '${_weekdayName(weekday)}s';
  return switch (weekday) {
    1 => l?.wellnessPluralMonday ?? fallback,
    2 => l?.wellnessPluralTuesday ?? fallback,
    3 => l?.wellnessPluralWednesday ?? fallback,
    4 => l?.wellnessPluralThursday ?? fallback,
    5 => l?.wellnessPluralFriday ?? fallback,
    6 => l?.wellnessPluralSaturday ?? fallback,
    _ => l?.wellnessPluralSunday ?? fallback,
  };
}

const _kWeekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _weekdayName(int weekday) => _kWeekdayNames[(weekday - 1).clamp(0, 6)];
