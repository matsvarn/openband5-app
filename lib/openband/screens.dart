import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'alp_tokens.dart';
import 'charts.dart';
import 'controller.dart';
import 'day_picker.dart';
import 'g3/band_parts.dart';
import 'g3/chrome.dart' as g3chrome;
import 'g3/g3_format.dart';
import 'g3/metrics.dart' show OBChip, OBChipKind;
import 'g3/g3_theme.dart';
import 'domain.dart';
import 'daily_activity.dart';
import 'health.dart';
import 'metric_detail.dart';
import 'night_signals.dart';
import '../data/day_label.dart';
import '../ui2/app_shell.dart' show pushFullScreen;
import '../ui2/profile/profile.dart' show SetRow;
import 'naps.dart';
import 'scale.dart';
import 'sleep_editor.dart';
import 'sleep_goal.dart';
import 'sleep_plan.dart';
import 'theme.dart';
import 'tab_bar.dart';

part 'screens_sleep.dart';

class OpenBandOverview extends StatefulWidget {
  final OpenBandController controller;
  final VoidCallback? onProfile, onJournal, onNutrition, onTraining, onSync;

  /// Paper order for the reduced release: rings, night, HRV and Ruhepuls,
  /// then Alle Messwerte. Steps stay, without water or energy.
  final bool reduced;
  const OpenBandOverview({
    super.key,
    required this.controller,
    this.onProfile,
    this.onJournal,
    this.onNutrition,
    this.onTraining,
    this.onSync,
    this.reduced = false,
  });

  @override
  State<OpenBandOverview> createState() => _OpenBandOverviewState();
}

class _OpenBandOverviewState extends State<OpenBandOverview> {
  OpenBandController get controller => widget.controller;
  bool get reduced => widget.reduced;
  VoidCallback? get onProfile => widget.onProfile;
  VoidCallback? get onJournal => widget.onJournal;
  VoidCallback? get onNutrition => widget.onNutrition;
  VoidCallback? get onTraining => widget.onTraining;
  VoidCallback? get onSync => widget.onSync;
  int _goalRevision = 0;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final p = OB.of(context);
      final day = controller.day;
      void sleep() async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OpenBandSleep(controller: controller),
          ),
        );
        if (mounted) setState(() => _goalRevision++);
      }

      return ColoredBox(
        color: p.canvas,
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            key: const PageStorageKey('openband.overview'),
            padding: EdgeInsets.fromLTRB(
              20,
              6,
              20,
              reduced ? kOBTabBarContentInset : 40,
            ),
            children: [
              _OverviewHeader(
                controller: controller,
                synthetic: day?.synthetic == true,
                onBand: () => showBandStatus(context, controller, onSync),
                onProfile: onProfile,
              ),
              const SizedBox(height: 16),
              if (controller.band.latestStoredAt != null &&
                  !G2SyncState.showsFor(controller.band, controller.now))
                _DataStrip(
                  band: controller.band,
                  night: day?.sleep,
                  onTap: () => showBandStatus(context, controller, onSync),
                ),
              if (controller.loadError != null)
                OBCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daten konnten nicht geladen werden.',
                        style: p.text(14),
                      ),
                      TextButton(
                        onPressed: controller.refresh,
                        child: const Text('Erneut laden'),
                      ),
                    ],
                  ),
                ),
              if (day == null && controller.loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                ),
              if (day != null) ...[
                G2SyncState(
                  band: controller.band,
                  onResume: onSync,
                  now: controller.now,
                ),
                if (day.correction != null || controller.calculating) ...[
                  CorrectionBanner(controller: controller),
                  const SizedBox(height: 12),
                ],
                OBCard(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: _RingTrio(
                    key: ValueKey(_goalRevision),
                    day: day,
                    controller: controller,
                    onSleep: sleep,
                  ),
                ),
                _OverviewSection(
                  title: 'Deine Nacht',
                  top: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _NightSummaryRow(night: day.sleep, onOpen: sleep),
                      const SizedBox(height: 10),
                      OBAdaptiveValues(
                        children: [
                          _VitalTile(
                            label: 'HRV · MS',
                            metricKey: MetricKey.hrv,
                            metric: day.hrv,
                            controller: controller,
                            onTap: () => OpenBandMetricDetail.push(
                              context,
                              backText: 'Heute',
                              controller: controller,
                              metricKey: MetricKey.hrv,
                              label: 'HRV',
                              subtitle: 'Herzratenvariabilität',
                              unit: 'ms',
                              icon: LucideIcons.activity,
                              color: (p) => p.ink,
                              tint: (p) => p.line,
                            ),
                          ),
                          _VitalTile(
                            label: 'PULS · /MIN',
                            metricKey: MetricKey.restingHr,
                            metric: day.restingHr,
                            controller: controller,
                            onTap: () => OpenBandMetricDetail.push(
                              context,
                              backText: 'Heute',
                              controller: controller,
                              metricKey: MetricKey.restingHr,
                              label: 'Ruhepuls',
                              subtitle: 'in der Nacht',
                              unit: '/min',
                              icon: LucideIcons.heart,
                              color: (p) => p.ink,
                              tint: (p) => p.line,
                            ),
                          ),
                        ],
                      ),
                      if (reduced) ...[
                        const SizedBox(height: 10),
                        _MesswerteRow(
                          onOpen: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => OpenBandHealth(
                                controller: controller,
                                bandMetricsOnly: true,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _OverviewSection(
                  title: 'Dein Tag',
                  top: 24,
                  trailing: controller.band.latestStoredAt == null
                      ? null
                      : 'bis ${obTime(controller.band.latestStoredAt)}',
                  child: StepsCard(
                    day: day,
                    now: controller.now,
                    onNutrition: reduced ? null : onNutrition,
                    showIntake: !reduced,
                  ),
                ),
                if (!reduced && onJournal != null) ...[
                  const SizedBox(height: 10),
                  OBCard(
                    child: _ActionRow(
                      'Dein Journal',
                      LucideIcons.notebookPen,
                      onJournal!,
                    ),
                  ),
                ],
                if (!reduced && onTraining != null) ...[
                  const SizedBox(height: 10),
                  OBCard(
                    child: _ActionRow(
                      'Training',
                      LucideIcons.dumbbell,
                      onTraining!,
                    ),
                  ),
                ],
                _BandFooter(band: controller.band),
              ],
              if (day == null &&
                  !controller.loading &&
                  controller.loadError == null)
                OBCard(
                  child: Text(
                    'Keine Daten für diesen Tag.',
                    style: p.text(14, color: p.muted),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

String _nightLabel(SleepNight night) => switch (night.duration.readiness) {
  MetricReadiness.processing => 'Schlaf wird ausgewertet',
  MetricReadiness.partial => 'Nacht teilweise erfasst',
  MetricReadiness.unreliable => 'Schlaf noch nicht verlässlich',
  _ =>
    night.duration.value == null
        ? 'Noch keine Nacht'
        : (night.unobservedMinutes ?? 0) > 0
        ? 'Nacht mit Datenlücke'
        : 'Nacht erfasst',
};

String? _sleepDelta(DayMetric duration) {
  final v = duration.value, b = duration.baseline;
  if (v == null || b == null) return null;
  final d = (v - b).round();
  return d == 0 ? 'wie Basis' : '${d > 0 ? '+' : '−'}${obGapMinutes(d.abs())}';
}

/// Onset, the full hours nearest one and two thirds through the night, wake.
List<DateTime> _sleepAxisTimes(SleepNight night) {
  final onset = night.onset!, wake = night.wake!;
  final spanMin = wake.difference(onset).inMinutes;
  DateTime nearestHour(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour + (t.minute >= 30 ? 1 : 0));
  return [
    onset,
    nearestHour(onset.add(Duration(minutes: spanMin ~/ 3))),
    nearestHour(onset.add(Duration(minutes: spanMin * 2 ~/ 3))),
    wake,
  ];
}

/// Spaced-caps section label over its content (Paper G2: 10 pt to content).
class _OverviewSection extends StatelessWidget {
  final String title;
  final String? trailing;
  final double top;
  final Widget child;
  const _OverviewSection({
    required this.title,
    required this.child,
    this.trailing,
    this.top = 10,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final caption = p.text(11, weight: FontWeight.w500, color: p.muted);
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: p.label(size: 11).copyWith(height: 14 / 11),
                  ),
                ),
                if (trailing != null)
                  Text(trailing!, style: caption.copyWith(height: 14 / 11)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Paper G2 night panel: "NACHT ›" and the window, the stage strip in its
/// recess, then the four stored stage totals edge to edge. Without stored
/// stages the honest label stands in.
class _NightSummaryRow extends StatelessWidget {
  final SleepNight night;
  final VoidCallback onOpen;
  const _NightSummaryRow({required this.night, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final facts = OBStageLegend.facts(
      night,
      p,
      onlyStored: true,
    ).where((f) => f.swatch != null).toList();
    final window = night.onset == null || night.wake == null
        ? null
        : '${obTime(night.onset)} – ${obTime(night.wake)}';
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    Widget fact(({String label, Color? swatch, String value}) f, bool end) =>
        Column(
          crossAxisAlignment: end
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            Text(
              f.label.toUpperCase(),
              style: p.label().copyWith(letterSpacing: 1.2, height: 12 / 10),
            ),
            Text(
              f.value,
              maxLines: 1,
              style: p
                  .text(15, weight: FontWeight.w700)
                  .copyWith(height: 18 / 15),
            ),
          ],
        );
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AlpRadius.card),
        child: OBCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'NACHT ›',
                      style: p.label(size: 11).copyWith(height: 14 / 11),
                    ),
                  ),
                  if (window != null)
                    Text(
                      window,
                      style: p
                          .text(12, weight: FontWeight.w500, color: p.muted)
                          .copyWith(height: 16 / 12),
                    ),
                ],
              ),
              if (night.segments.isNotEmpty) OBStageStrip(night: night),
              if (facts.isEmpty)
                Text(_nightLabel(night), style: p.text(13, color: p.muted))
              else if (large)
                Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: [for (final f in facts) fact(f, false)],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, f) in facts.indexed)
                      fact(f, i == facts.length - 1 && facts.length > 1),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A night value tile (Paper G2): spaced label and the delta to the
/// baseline on top, the value and the last seven nights as bars below.
/// Non-current states show their reason in the delta slot, never a number.
class _VitalTile extends StatefulWidget {
  final String label;
  final MetricKey metricKey;
  final DayMetric metric;
  final OpenBandController controller;
  final VoidCallback onTap;
  const _VitalTile({
    required this.label,
    required this.metricKey,
    required this.metric,
    required this.controller,
    required this.onTap,
  });

  @override
  State<_VitalTile> createState() => _VitalTileState();
}

class _VitalTileState extends State<_VitalTile> {
  late String _day;
  // Not a lazy `late` initializer: it must capture the result the history was
  // read for now, not whenever it is first compared.
  OpenBandDay? _loadedFor;
  late Future<List<MetricPoint>> _history;

  @override
  void initState() {
    super.initState();
    _day = widget.controller.selectedDay;
    _loadedFor = widget.controller.day;
    _history = _read();
  }

  Future<List<MetricPoint>> _read() => widget.controller.repository
      .readMetricHistory(widget.metricKey, widget.controller.selectedDay, 7);

  // Re-read with every new day result, not only a new day: after a sync or a
  // re-derivation (an algorithm bump re-derives old nights last) the history
  // changes under the same selected day, and a once-read list kept the gaps.
  @override
  void didUpdateWidget(_VitalTile old) {
    super.didUpdateWidget(old);
    final c = widget.controller;
    if (c.selectedDay != _day || !identical(c.day, _loadedFor)) {
      _day = c.selectedDay;
      _loadedFor = c.day;
      _history = _read();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final m = widget.metric;
    final status = obCompactMetricStatus(m, digits: 0);
    final comparable =
        m.value != null &&
        m.baseline != null &&
        (m.nightScalar == null || m.nightScalar == NightScalarState.current);
    final delta = comparable ? (m.value! - m.baseline!).round() : null;
    final corner = delta != null
        ? (delta == 0 ? '±0' : '${delta > 0 ? '+' : '−'}${delta.abs()}')
        : (m.value == null ? null : status);
    final verdict = delta == null
        ? null
        : dayMetricVerdict(widget.metricKey, m);
    return Semantics(
      button: true,
      label:
          '${widget.label}, ${obNumber(m.value)}${status == null ? '' : ', $status'}',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AlpRadius.card),
          child: ExcludeSemantics(
            child: OBCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  // A status too wide to share the line wraps under the
                  // label instead of cutting the unit off.
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    runSpacing: 2,
                    children: [
                      Text(
                        widget.label,
                        maxLines: 1,
                        style: p.label().copyWith(height: 12 / 10),
                      ),
                      if (corner != null)
                        Text(
                          corner,
                          maxLines: 1,
                          style: p
                              .text(
                                11,
                                weight:
                                    delta != null &&
                                        verdict != MetricVerdict.normal
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: delta == null
                                    ? p.muted
                                    : obVerdictText(p, verdict) ?? p.ink,
                              )
                              .copyWith(height: 14 / 11),
                        ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          obNumber(m.value),
                          style: p
                              .text(
                                28,
                                weight: FontWeight.w700,
                                color: m.value == null ? p.gap : p.ink,
                              )
                              .copyWith(height: 1, letterSpacing: -.56),
                        ),
                      ),
                      FutureBuilder<List<MetricPoint>>(
                        future: _history,
                        builder: (context, snap) => SizedBox(
                          width: 56,
                          height: 22,
                          child: CustomPaint(
                            painter: _WeekBarsPainter(
                              p,
                              snap.hasError ? const [] : snap.data ?? const [],
                              newest: obVerdictMark(p, verdict) ?? p.ink,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Seven nights as bars scaled to their own spread; the newest is ink. A
/// night without a value is a hollow stub, not a zero.
class _WeekBarsPainter extends CustomPainter {
  final OB p;
  final List<MetricPoint> points;

  /// Colour of the newest bar: ink, or its verdict colour.
  final Color newest;
  _WeekBarsPainter(this.p, this.points, {required this.newest});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final shown = points.length > 7
        ? points.sublist(points.length - 7)
        : points;
    final values = [
      for (final e in shown)
        if (e.value != null) e.value!,
    ];
    if (values.isEmpty) return;
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    final span = hi - lo;
    const n = 7;
    // Paper's 80×24 grid scaled uniformly into the box, centred vertically.
    final u = size.width / 80;
    final bw = 8 * u, pitch = 12 * u;
    final bottom = (size.height + 24 * u) / 2;
    final offset = (n - shown.length) * pitch;
    for (final (i, e) in shown.indexed) {
      final x = offset + i * pitch;
      if (e.value == null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + .5, bottom - 4.5, bw - 1, 4),
            const Radius.circular(1),
          ),
          Paint()
            ..color = p.gap
            ..style = PaintingStyle.stroke,
        );
        continue;
      }
      final f = span <= 0 ? .6 : .45 + .425 * (e.value! - lo) / span;
      final h = 24 * u * f;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, bottom - h, bw, h),
          const Radius.circular(1.5),
        ),
        Paint()..color = i == shown.length - 1 ? newest : p.gap,
      );
    }
  }

  @override
  bool shouldRepaint(_WeekBarsPainter old) =>
      old.points != points || old.newest != newest || old.p.dark != p.dark;
}

/// Heute's header (Paper G2): day title with its picker chevron, the date
/// line, then the battery key and the profile key.
class _OverviewHeader extends StatelessWidget {
  final OpenBandController controller;
  final bool synthetic;
  final VoidCallback onBand;
  final VoidCallback? onProfile;
  const _OverviewHeader({
    required this.controller,
    required this.synthetic,
    required this.onBand,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    final dateStyle = p
        .text(11, weight: FontWeight.w500, color: p.muted)
        .copyWith(letterSpacing: 0.12 * 11, height: 14 / 11);
    final title = Semantics(
      button: true,
      child: InkWell(
        onTap: () => chooseOpenBandDay(context, controller),
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      obDayTitle(controller.selectedDay, controller.now()),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: p
                          .text(26, weight: FontWeight.w700)
                          .copyWith(height: 32 / 26, letterSpacing: -.52),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OBChevron(direction: AxisDirection.down, color: p.muted),
                ],
              ),
              Text(
                synthetic
                    ? '${_dateLine(controller.selectedDay)} · SYNTHETISCHE DATEN'
                    : _dateLine(controller.selectedDay),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dateStyle,
              ),
            ],
          ),
        ),
      ),
    );
    final keys = <Widget>[
      _BandPill(band: controller.band, onTap: onBand),
      if (onProfile != null)
        OBKey(
          tooltip: 'Profil',
          height: 40,
          padding: EdgeInsets.zero,
          onTap: onProfile,
          child: Icon(LucideIcons.user, size: 18, color: p.ink),
        ),
    ];
    if (large) {
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [title, ...keys],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: title),
          ),
          for (final (i, k) in keys.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            k,
          ],
        ],
      ),
    );
  }
}

/// "Letzter Bandwert 07:41 · Übertragung 07:42" — only the times that exist.
class _BandFooter extends StatelessWidget {
  final BandSnapshot band;
  const _BandFooter({required this.band});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final parts = [
      if (band.latestStoredAt != null)
        'Letzter Bandwert ${obTime(band.latestStoredAt)}',
      if (band.receivedAt != null) 'Übertragung ${obTime(band.receivedAt)}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Text(
        parts.join(' · '),
        textAlign: TextAlign.center,
        style: p
            .text(11, weight: FontWeight.w500, color: p.muted)
            .copyWith(letterSpacing: .66, height: 14 / 11),
      ),
    );
  }
}

/// The three Messleisten on one raised panel, hairlines between rows. Values
/// grow in on load unless animations are disabled.
class _RingTrio extends StatefulWidget {
  final OpenBandDay day;
  final OpenBandController controller;
  final VoidCallback onSleep;
  const _RingTrio({
    super.key,
    required this.day,
    required this.controller,
    required this.onSleep,
  });

  @override
  State<_RingTrio> createState() => _RingTrioState();
}

class _RingTrioState extends State<_RingTrio> {
  late String _goalDay = widget.day.day;
  late OpenBandDay _goalFor = widget.day;
  late Future<SleepGoalSnapshot> _goal = _readGoal();

  Future<SleepGoalSnapshot> _readGoal() =>
      widget.controller.repository.readSleepGoal(widget.day.day);

  @override
  void didUpdateWidget(_RingTrio old) {
    super.didUpdateWidget(old);
    if (widget.day.day != _goalDay || !identical(widget.day, _goalFor)) {
      _goalDay = widget.day.day;
      _goalFor = widget.day;
      _goal = _readGoal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final day = widget.day;
    final controller = widget.controller;
    final today = day.day == todayLabel(controller.now());
    return FutureBuilder<SleepGoalSnapshot>(
      future: _goal,
      builder: (context, snap) {
        final goal = snap.hasError
            ? null
            : snap.data?.targetMinutes?.toDouble();
        final sleepGoal = _sleepGoalDelta(day.sleep.duration.value, goal);
        final recoveryVerdict = dayMetricVerdict(
          MetricKey.recovery,
          day.recovery,
        );
        final recoveryDelta = recoveryVerdict == null
            ? null
            : _signed((day.recovery.value! - day.recovery.baseline!).round());
        Widget trio(double progress) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Messleiste(
              label: 'Erholung',
              value: obNumber(day.recovery.value),
              unit: day.recovery.value == null ? 'kein Wert' : 'von 100',
              delta: recoveryDelta,
              deltaColor: obVerdictText(p, recoveryVerdict),
              deltaSpoken: 'zur Basis',
              valueColor: day.recovery.value == null ? p.gap : p.ink,
              scale: OBScale(
                min: 0,
                max: 100,
                value: _grow(day.recovery.value, progress),
                fill: p.ink,
                mark: obVerdictMark(p, recoveryVerdict),
                markEdge: obVerdictText(p, recoveryVerdict),
                labels: ('0', '50', '100'),
              ),
              onTap: () => OpenBandMetricDetail.push(
                context,
                backText: 'Heute',
                controller: controller,
                metricKey: MetricKey.recovery,
                label: 'Erholung',
                subtitle: 'aus der Nacht',
                unit: 'von 100',
                icon: LucideIcons.heartPulse,
                // Colour means a verdict (G2); Erholung has no range yet.
                color: (p) => p.ink,
                tint: (p) => p.line,
              ),
            ),
            Container(height: 1, color: p.line),
            _Messleiste(
              label: 'Schlaf',
              value: obDuration(day.sleep.duration.value),
              unit: _sleepDelta(day.sleep.duration),
              delta: sleepGoal.text,
              deltaColor: obVerdictText(p, sleepGoal.verdict),
              deltaSpoken: 'zum Ziel',
              valueColor: day.sleep.duration.value == null ? p.gap : p.ink,
              scale: OBScale(
                min: 0,
                max: 600,
                value: _grow(day.sleep.duration.value, progress),
                target: goal,
                targetLabel: goal == null ? null : 'Ziel ${obDuration(goal)}',
                fill: p.sleep,
                mark: obVerdictMark(p, sleepGoal.verdict),
                markEdge: obVerdictText(p, sleepGoal.verdict),
                labels: ('0 h', '5 h', '10 h'),
              ),
              onTap: widget.onSleep,
            ),
            Container(height: 1, color: p.line),
            _Messleiste(
              label: 'Belastung',
              value: obNumber(day.strain.value, digits: 1),
              unit: day.strain.value == null
                  ? 'kein Wert'
                  : today
                  ? 'läuft'
                  : 'von 21',
              valueColor: day.strain.value == null ? p.gap : p.ink,
              scale: OBScale(
                min: 0,
                max: 21,
                value: _grow(day.strain.value, progress),
                fill: p.strain,
                labels: ('0', '10,5', '21'),
              ),
              onTap: () => OpenBandMetricDetail.push(
                context,
                backText: 'Heute',
                controller: controller,
                metricKey: MetricKey.strain,
                label: 'Belastung',
                subtitle: 'heute bis jetzt',
                unit: 'von 21',
                icon: LucideIcons.flame,
                digits: 1,
                color: (p) => p.strain,
                tint: (p) => p.strainTint,
              ),
            ),
          ],
        );
        if (MediaQuery.disableAnimationsOf(context)) return trio(1);
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, progress, _) => trio(progress),
        );
      },
    );
  }

  static double? _grow(double? v, double t) => v == null ? null : v * t;
}

String _signed(int d) => d == 0 ? '±0' : '${d > 0 ? '+' : '−'}${d.abs()}';

/// Sleep against the goal: green once met; short of it the gap is stated
/// muted — a short night is not an alarm. Nothing without both values.
({String? text, MetricVerdict? verdict}) _sleepGoalDelta(
  double? minutes,
  double? goal,
) {
  if (minutes == null || goal == null) return (text: null, verdict: null);
  final d = (minutes - goal).round();
  final size = d.abs() < 60 ? '${d.abs()} Min.' : obDuration(d.abs());
  return (
    text: d == 0 ? '±0' : '${d > 0 ? '+' : '−'}$size',
    verdict: d >= 0 ? MetricVerdict.better : MetricVerdict.normal,
  );
}

/// One Messleiste row (Paper G2): 108-pt reading column — spaced label over
/// the value, a short note beside it — and the scale filling the rest.
/// Stacks under the value at large text.
class _Messleiste extends StatelessWidget {
  final String label, value;
  final String? unit;

  /// Delta beside the label (Paper G2), coloured by verdict; [deltaSpoken]
  /// names what it is measured against for VoiceOver.
  final String? delta, deltaSpoken;
  final Color? deltaColor;
  final Color valueColor;
  final Widget scale;
  final VoidCallback onTap;
  const _Messleiste({
    required this.label,
    required this.value,
    required this.unit,
    this.delta,
    this.deltaSpoken,
    this.deltaColor,
    required this.valueColor,
    required this.scale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    // "von 100" is the scale's right end and a delta lives on Schlaf; only
    // a state note ("läuft", "kein Wert") sits beside the value.
    final note = unit == 'läuft' || unit == 'kein Wert' ? unit : null;
    final reading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${label.toUpperCase()} ›',
                maxLines: 1,
                style: p.label().copyWith(height: 12 / 10),
              ),
            ),
            if (delta != null)
              Text(
                delta!,
                maxLines: 1,
                style: p
                    .text(
                      11,
                      weight: deltaColor == p.muted
                          ? FontWeight.w500
                          : FontWeight.w700,
                      color: deltaColor ?? p.ink,
                    )
                    .copyWith(height: 14 / 11),
              ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: p
                      .text(34, weight: FontWeight.w700, color: valueColor)
                      .copyWith(height: 36 / 34, letterSpacing: -.03 * 34),
                ),
              ),
            ),
            if (note != null) ...[
              const SizedBox(width: 4),
              Text(
                note,
                maxLines: 1,
                style: p.text(11, color: p.muted).copyWith(height: 14 / 11),
              ),
            ],
          ],
        ),
      ],
    );
    return Semantics(
      button: true,
      label:
          '$label, $value ${unit ?? ''}${delta == null ? '' : ', $delta ${deltaSpoken ?? ''}'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: large
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [reading, const SizedBox(height: 8), scale],
                  )
                : Row(
                    children: [
                      SizedBox(width: 108, child: reading),
                      const SizedBox(width: 13),
                      Expanded(child: scale),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Verdict colours (G2 rule: colour marks only the delta text and today's
/// marker). Inside the normal range the delta is muted; without a verdict
/// the caller keeps its neutral style.
Color? obVerdictText(OB p, MetricVerdict? v) => switch (v) {
  MetricVerdict.better => p.better,
  MetricVerdict.worse => p.worse,
  MetricVerdict.normal => p.muted,
  null => null,
};

Color? obVerdictMark(OB p, MetricVerdict? v) => switch (v) {
  MetricVerdict.better => p.betterMark,
  MetricVerdict.worse => p.worseMark,
  _ => null,
};

/// "DI 15.09" under the day title.
String _dateLine(String day) {
  final d = DateTime.parse(day);
  final weekday = DateFormat('EEE', 'de_DE').format(d).replaceAll('.', '');
  return '${weekday.toUpperCase()} ${DateFormat('dd.MM', 'de_DE').format(d)}';
}

/// "Daten bis HH:mm" strip under the header: the stored-data edge and the
/// night's coverage, tapping into the Datenstand sheet. Only built when
/// [BandSnapshot.latestStoredAt] exists — no fabricated freshness.
class _DataStrip extends StatelessWidget {
  final BandSnapshot band;
  final SleepNight? night;
  final VoidCallback onTap;
  const _DataStrip({
    required this.band,
    required this.night,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final at = band.latestStoredAt!;
    final missing = night?.unobservedMinutes ?? 0;
    final gap = missing > 0;
    final coverage = night == null
        ? null
        : night!.duration.value == null
        ? _nightLabel(night!)
        : gap
        ? 'Nacht · ${obGapMinutes(missing)} Lücke'
        : 'Nacht lückenlos';
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Semantics(
        label:
            'Daten bis ${obTime(at)}${coverage == null ? '' : ', $coverage'}',
        button: true,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: p.insetDecoration(radius: 22),
              child: Row(
                children: [
                  OBLed(
                    on: band.connection == BandConnection.connected,
                    color: gap ? p.warning : null,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    flex: 0,
                    fit: FlexFit.loose,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * .55,
                      ),
                      child: Text(
                        'Daten bis ${obTime(at)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: p.text(13, weight: FontWeight.w700),
                      ),
                    ),
                  ),
                  if (coverage != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        coverage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: p.text(13, color: p.muted),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  OBChevron(color: p.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MesswerteRow extends StatelessWidget {
  final VoidCallback onOpen;
  const _MesswerteRow({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return InkWell(
      key: const ValueKey('alle-messwerte'),
      onTap: onOpen,
      borderRadius: BorderRadius.circular(24),
      child: OBCard(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: [
              CustomPaint(
                size: const Size.square(20),
                painter: _PulsePainter(p.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Alle Messwerte',
                  style: p
                      .text(15, weight: FontWeight.w700)
                      .copyWith(height: 18 / 15),
                ),
              ),
              if (MediaQuery.textScalerOf(context).scale(14) <= 20) ...[
                Text('Atmung · Haut', style: p.text(13, color: p.muted)),
                const SizedBox(width: 12),
              ],
              Text('›', style: p.text(16, color: p.gap).copyWith(height: 1.25)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paper's pulse glyph: M3 12h4l2-5 4 10 2-5h6 on a 24 grid, stroke 1.8.
class _PulsePainter extends CustomPainter {
  final Color color;
  const _PulsePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final points = [(3, 12), (7, 12), (9, 7), (13, 17), (15, 12), (21, 12)];
    canvas.drawPath(
      Path()..addPolygon([
        for (final (x, y) in points) Offset(x * s, y * s),
      ], false),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.color != color;
}

class OBStageLegend extends StatelessWidget {
  final SleepNight night;

  /// Omit stages whose stored minutes are absent. A dash is not a stage.
  final bool onlyStored;
  const OBStageLegend({
    super.key,
    required this.night,
    this.onlyStored = false,
  });

  static const double swatchSize = 8;
  static const double swatchGap = 6;
  static const double fiveColumnGap = 8;
  static const double wrappedColumnGap = 12;
  static const double rowGap = 16;
  static const double labelValueGap = 2;

  static TextStyle labelStyle(OB p, double size) => p
      .text(size, weight: FontWeight.w500, color: p.muted)
      .copyWith(height: 14 / 12, letterSpacing: 0);

  static TextStyle valueStyle(OB p, double size) => p
      .text(size, weight: FontWeight.w700, display: true)
      .copyWith(height: 20 / 17, letterSpacing: -0.02 * size);

  static List<({String label, Color? swatch, String value})> facts(
    SleepNight night,
    OB p, {
    bool onlyStored = false,
  }) => [
    if (!onlyStored || night.deepMinutes != null)
      (
        label: 'Tief',
        swatch: p.stageDeep,
        value: obDuration(night.deepMinutes),
      ),
    if (!onlyStored || night.lightMinutes != null)
      (
        label: 'Leicht',
        swatch: p.stageLight,
        value: obDuration(night.lightMinutes),
      ),
    if (!onlyStored || night.remMinutes != null)
      (label: 'REM', swatch: p.stageRem, value: obDuration(night.remMinutes)),
    if (!onlyStored || night.awakeMinutes != null)
      (
        label: 'Wach',
        swatch: p.wake,
        value: night.awakeMinutes == null
            ? '—'
            : '${obNumber(night.awakeMinutes)} Min.',
      ),
    if (!onlyStored || night.bedMinutes != null)
      (label: 'Im Bett', swatch: null, value: obDuration(night.bedMinutes)),
  ];

  static int columnsFor({
    required double width,
    required List<double> itemWidths,
  }) {
    if (!(width > 0) || itemWidths.isEmpty) return 1;
    for (var n = 5; n >= 1; n--) {
      final gap = n == 5 ? fiveColumnGap : wrappedColumnGap;
      final col = n == 1 ? width : (width - gap * (n - 1)) / n;
      if (col > 0 && itemWidths.every((w) => w <= col)) return n;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    final labels = labelStyle(p, scaler.scale(12));
    final values = valueStyle(p, scaler.scale(17));
    final items = facts(night, p, onlyStored: onlyStored);
    final itemWidths = <double>[];
    for (final item in items) {
      final labelWidth =
          (item.swatch == null ? 0.0 : swatchSize + swatchGap) +
          _textWidth(item.label, labels, TextScaler.noScaling, dir);
      final valueWidth = _textWidth(
        item.value,
        values,
        TextScaler.noScaling,
        dir,
      );
      itemWidths.add(labelWidth > valueWidth ? labelWidth : valueWidth);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : itemWidths.fold<double>(0, (a, b) => a + b) + fiveColumnGap * 4;
        final columns = columnsFor(width: width, itemWidths: itemWidths);
        final gap = columns == 5 ? fiveColumnGap : wrappedColumnGap;
        final colW = columns == 1
            ? width
            : (width - gap * (columns - 1)) / columns;
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: Wrap(
            spacing: gap,
            runSpacing: rowGap,
            children: [
              for (final item in items)
                SizedBox(
                  width: colW,
                  child: _StageFact(
                    label: item.label,
                    swatch: item.swatch,
                    value: item.value,
                    labelStyle: labels,
                    valueStyle: values,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StageFact extends StatelessWidget {
  final String label, value;
  final Color? swatch;
  final TextStyle labelStyle, valueStyle;
  const _StageFact({
    required this.label,
    required this.swatch,
    required this.value,
    required this.labelStyle,
    required this.valueStyle,
  });

  @override
  Widget build(BuildContext context) => Column(
    key: ValueKey('sleep-stage-$label'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (swatch != null) ...[
            Container(
              key: ValueKey('sleep-stage-swatch-$label'),
              width: OBStageLegend.swatchSize,
              height: OBStageLegend.swatchSize,
              decoration: BoxDecoration(
                color: swatch,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: OBStageLegend.swatchGap),
          ],
          Text(label, style: labelStyle),
        ],
      ),
      const SizedBox(height: OBStageLegend.labelValueGap),
      Text(value, style: valueStyle),
    ],
  );
}

class OBAdaptiveValues extends StatelessWidget {
  final List<Widget> children;
  const OBAdaptiveValues({super.key, required this.children});
  @override
  Widget build(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) > 20
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final child in children)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: child),
          ],
        )
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: children[i]),
            ],
          ],
        );
}

String obMetricComparisonStatus(
  double value,
  double baseline, {
  required int digits,
}) {
  if (digits == 0) return obMetricStatus(value, baseline);
  final difference = value - baseline;
  var halfUnit = .5;
  for (var i = 0; i < digits; i++) {
    halfUnit /= 10;
  }
  if (difference.abs() < halfUnit) return 'wie Basis';
  return '${difference > 0 ? '+' : '−'}${obNumber(difference.abs(), digits: digits)} '
      '${difference > 0 ? 'über' : 'unter'} Basis';
}

String obTemperatureNumber(double? value, NightScalarUnit? unit) {
  if (value == null || !value.isFinite) return '—';
  final number = obNumber(value.abs(), digits: 1);
  if (unit != NightScalarUnit.sd || value == 0) {
    return obNumber(value, digits: 1);
  }
  return value > 0 ? '+$number' : '−$number';
}

String? obCompactMetricStatus(DayMetric metric, {required int digits}) {
  if (metric.unit == NightScalarUnit.unknown) {
    return metric.reason ?? kNightScalarUnknownUnitLabel;
  }
  switch (metric.nightScalar) {
    case NightScalarState.pending:
      return kNightScalarPendingLabel;
    case NightScalarState.failed:
      return kNightScalarFailedLabel;
    case NightScalarState.unknown:
    case NightScalarState.outdated:
      return kNightScalarOpenLabel;
    case NightScalarState.missing:
      return 'Kein Nachtwert';
    case NightScalarState.unreadable:
      return 'Nicht lesbar';
    case NightScalarState.partial:
      return 'Unvollständig';
    case NightScalarState.older:
      return 'Ältere Berechnung';
    case NightScalarState.current:
      if (metric.value == null || metric.baseline == null) return null;
      return obMetricComparisonStatus(
        metric.value!,
        metric.baseline!,
        digits: digits,
      );
    case null:
      if (metric.value == null || metric.baseline == null) return null;
      return obMetricComparisonStatus(
        metric.value!,
        metric.baseline!,
        digits: digits,
      );
  }
}

class G2MetricCard extends StatelessWidget {
  final String label, unit;
  final DayMetric metric;
  final IconData icon;
  final Color color;
  final int digits;

  /// Metric for the verdict colour of the comparison; null keeps it ink.
  final MetricKey? metricKey;
  final VoidCallback? onTap;
  const G2MetricCard({
    super.key,
    required this.label,
    required this.unit,
    required this.metric,
    required this.icon,
    required this.color,
    this.digits = 0,
    this.metricKey,
    this.onTap,
  }) : assert(digits >= 0);
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final status = obCompactMetricStatus(metric, digits: digits);
    final temperature = metric.unit != null;
    final displayUnit = switch (metric.unit) {
      NightScalarUnit.sd => 'SD',
      NightScalarUnit.celsius => '°C',
      NightScalarUnit.unknown => '',
      null => unit,
    };
    final displayValue = temperature
        ? obTemperatureNumber(metric.value, metric.unit)
        : obNumber(metric.value, digits: digits);
    final compared =
        status != null &&
        metric.value != null &&
        metric.baseline != null &&
        (metric.nightScalar == null ||
            metric.nightScalar == NightScalarState.current);
    final labelSize = scaler.scale(13);
    final valueSize = scaler.scale(34);
    final unitSize = scaler.scale(14);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AlpRadius.card),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: OBCard(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 84),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: p
                            .text(
                              labelSize,
                              weight: FontWeight.w600,
                              color: p.muted,
                            )
                            .copyWith(height: 18 / 13, letterSpacing: 0.4),
                      ),
                    ),
                    if (onTap != null)
                      Text(' ›', style: p.text(labelSize, color: p.muted)),
                  ],
                ),
                _MetricValueUnit(
                  value: displayValue,
                  unit: metric.value == null || displayUnit.isEmpty
                      ? null
                      : displayUnit,
                  valueSize: valueSize,
                  unitSize: unitSize,
                ),
                if (status != null)
                  Text(
                    status,
                    style: p
                        .text(
                          labelSize,
                          weight: compared ? FontWeight.w700 : FontWeight.w500,
                          color: compared
                              ? (metricKey == null
                                        ? null
                                        : obVerdictText(
                                            p,
                                            dayMetricVerdict(
                                              metricKey!,
                                              metric,
                                            ),
                                          )) ??
                                    p.ink
                              : p.muted,
                        )
                        .copyWith(height: 18 / 13, letterSpacing: 0),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paper value + unit on one baseline when they fit; stacks at large text or
/// a narrow card instead of shrinking or truncating the figure.
class _MetricValueUnit extends StatelessWidget {
  final String value;
  final String? unit;
  final double valueSize, unitSize;
  const _MetricValueUnit({
    required this.value,
    required this.unit,
    required this.valueSize,
    required this.unitSize,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final valueStyle = p
        .text(valueSize, weight: FontWeight.w700, display: true)
        .copyWith(height: 36 / 34);
    final unitStyle = p
        .text(unitSize, weight: FontWeight.w500, color: p.muted)
        .copyWith(height: 18 / 14, letterSpacing: 0);
    final unitText = unit;
    if (unitText == null || unitText.isEmpty) {
      return Text(value, style: valueStyle);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final dir = Directionality.of(context);
        final rowWidth =
            _textWidth(value, valueStyle, TextScaler.noScaling, dir) +
            4 +
            _textWidth(unitText, unitStyle, TextScaler.noScaling, dir);
        final stack =
            constraints.hasBoundedWidth && rowWidth > constraints.maxWidth;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: valueStyle),
              Text(unitText, style: unitStyle),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: valueStyle),
            const SizedBox(width: 4),
            Text(unitText, style: unitStyle),
          ],
        );
      },
    );
  }
}

double _textWidth(
  String text,
  TextStyle style,
  TextScaler scaler,
  TextDirection dir,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: dir,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Sync status pill under the overview header. Says nothing when there is
/// nothing to say — a progress track would need a real progress value, which
/// [BandSnapshot] does not carry, so none is drawn. Passive states retain their
/// compact geometry; the interactive resume state guarantees a 44-point hit
/// area and grows with text rather than shrinking its button below that.
class G2SyncState extends StatelessWidget {
  final BandSnapshot band;
  final VoidCallback? onResume;
  final DateTime Function() now;
  const G2SyncState({
    super.key,
    required this.band,
    this.onResume,
    required this.now,
  });

  /// Whether the passive strip has something to say for [band].
  static bool showsFor(BandSnapshot band, DateTime Function() now) =>
      switch (band.transfer) {
        TransferState.receiving || TransferState.interrupted => true,
        TransferState.idle => switch (band.receivedAt) {
          final at? => now().difference(at).inMinutes.abs() <= 10,
          null => false,
        },
      };

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stored = 'bis ${obTime(band.latestStoredAt)}';
    final (
      IconData? icon,
      Color? iconColor,
      String? text,
      Widget? trailing,
    ) = switch (band.transfer) {
      TransferState.receiving => (
        LucideIcons.refreshCw,
        p.action,
        'Band wird gelesen',
        Text(
          stored,
          style: p.text(
            13,
            weight: FontWeight.w700,
            display: true,
            color: p.muted,
          ),
        ),
      ),
      TransferState.interrupted => (
        LucideIcons.bluetoothOff,
        p.ink,
        'Unterbrochen · $stored',
        onResume == null
            ? null
            : TextButton(
                onPressed: onResume,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Fortsetzen',
                  textAlign: TextAlign.center,
                  style: p.text(13, weight: FontWeight.w600, color: p.ink),
                ),
              ),
      ),
      TransferState.idle => switch (band.receivedAt) {
        final at? when now().difference(at).inMinutes.abs() <= 10 => (
          LucideIcons.check,
          p.led,
          'Gespeichert $stored',
          Text(
            'vor ${now().difference(at).inMinutes.abs()} Min.',
            style: p.text(13, weight: FontWeight.w500, color: p.muted),
          ),
        ),
        _ => (null, null, null, null),
      },
    };
    if (icon == null) return const SizedBox.shrink();
    final actionable =
        band.transfer == TransferState.interrupted && onResume != null;
    final stackAction =
        trailing != null && MediaQuery.textScalerOf(context).scale(13) > 18;
    final content = stackAction
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: iconColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text!,
                      style: p.text(13, weight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              Align(alignment: Alignment.centerRight, child: trailing),
            ],
          )
        : Row(
            spacing: 10,
            children: [
              Icon(icon, size: 16, color: iconColor),
              Expanded(
                child: Text(text!, style: p.text(13, weight: FontWeight.w600)),
              ),
              ?trailing,
            ],
          );
    return Semantics(
      label: text,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          constraints: BoxConstraints(minHeight: actionable ? 44 : 40),
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: stackAction ? 4 : 0,
          ),
          decoration: p.insetDecoration(radius: 22),
          child: content,
        ),
      ),
    );
  }
}

class _BandPill extends StatelessWidget {
  final BandSnapshot band;
  final VoidCallback onTap;
  const _BandPill({required this.band, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final pct = band.batteryPercent;
    return Semantics(
      label:
          'Band, ${band.connection == BandConnection.connected ? 'verbunden' : 'nicht verbunden'}, Akku ${pct == null ? 'unbekannt' : '$pct Prozent'}',
      button: true,
      excludeSemantics: true,
      child: OBKey(
        height: 40,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            SizedBox(
              width: 10,
              height: 16,
              child: CustomPaint(painter: _BatteryGlyph(p, pct)),
            ),
            Text(
              pct == null ? '—' : '$pct %',
              style: p
                  .text(14, weight: FontWeight.w700)
                  .copyWith(height: 18 / 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// Upright battery outline filled to the observed charge; empty when the
/// charge is unknown.
class _BatteryGlyph extends CustomPainter {
  final OB p;
  final int? percent;
  _BatteryGlyph(this.p, this.percent);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
        const Radius.circular(2.5),
      ),
      Paint()
        ..color = p.muted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final pct = percent;
    if (pct == null) return;
    final inner = size.height - 6;
    final h = inner * (pct.clamp(0, 100) / 100);
    if (h <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3, 3 + inner - h, size.width - 6, h),
        const Radius.circular(1),
      ),
      Paint()..color = p.ink,
    );
  }

  @override
  bool shouldRepaint(_BatteryGlyph old) =>
      old.percent != percent || old.p.dark != p.dark;
}

String _relativeTime(DateTime at, DateTime now) {
  if (at.isAfter(now)) return 'Zeit unbekannt';
  return 'vor ${g3Duration(now.difference(at).inMinutes)}';
}

String bandStatusValuesHeading(String selectedDay, DateTime now) =>
    selectedDay == todayLabel(now)
    ? 'WERTE FÜR HEUTE'
    : 'WERTE FÜR ${g3DateShort(DateTime.parse(selectedDay))}';

Future<void> showBandStatus(
  BuildContext context,
  OpenBandController controller,
  VoidCallback? onSync,
) {
  final diagnosticsRead = controller.repository
      .readBandDiagnostics()
      .then<BandDiagnostics?>((value) => value, onError: (Object _) => null);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: .38),
    backgroundColor: Colors.transparent,
    builder: (c) {
      final g = G3.of(c);
      final b = controller.band;
      final day = controller.day;
      final ready = day == null
          ? const <(String, DayMetric)>[]
          : <(String, DayMetric)>[
              ('Erholung', day.recovery),
              ('Belastung', day.strain),
              ('HRV', day.hrv),
              ('Ruhepuls', day.restingHr),
            ];
      return FutureBuilder<BandDiagnostics?>(
        future: diagnosticsRead,
        builder: (c, result) {
          final diagnostics = result.data;
          final stored = diagnostics?.lastStoredSampleAt ?? b.latestStoredAt;
          final battery = diagnostics?.battery;
          final batteryPercent = battery?.percent ?? b.batteryPercent;
          final batteryObservedAt = battery?.observedAt ?? b.batteryObservedAt;
          final coverage = diagnostics?.coverage;
          final unreadPages = diagnostics?.backlog?.unreadPages;
          final sleepDetail =
              day?.sleep.onset == null || day?.sleep.wake == null
              ? 'Schlafzeit unbekannt'
              : 'Schlaf ${obTime(day!.sleep.onset)}–${obTime(day.sleep.wake)}';
          final coverageDetail = coverage?.coveragePercent != null
              ? '24 h: ${coverage!.coveragePercent!.round()} %'
              : coverage?.recordedSeconds != null
              ? '24 h: ${coverage!.recordedSeconds} Sek. aufgezeichnet · Anteil unbekannt'
              : null;
          final wristOff = coverage?.wristOffIntervals;
          final largeText = MediaQuery.textScalerOf(c).scale(15) > 22;
          return SizedBox(
            height: MediaQuery.sizeOf(c).height * (largeText ? .96 : .88),
            child: SafeArea(
              child: g3chrome.OBSheet(
                title: 'Dein Datenstand',
                child: Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 20),
                          children: [
                            OBFrontierCard(
                              storedAt: stored,
                              now: controller.now(),
                              caption: unreadPages == null
                                  ? null
                                  : '$unreadPages Bandseiten ungelesen · Stand ${g3Relative(diagnostics!.backlog!.observedAt, now: controller.now())}',
                              rightLabel: stored == null
                                  ? null
                                  : 'letzter Wert ${_relativeTime(stored, controller.now())}',
                            ),
                            const SizedBox(height: 14),
                            OBSettingsGroup(
                              children: [
                                ListenableBuilder(
                                  listenable: controller,
                                  builder: (c, _) => OBSettingsRow(
                                    label: 'Verbindung',
                                    stackAtLargeText: true,
                                    detail: batteryPercent == null
                                        ? 'Akku —'
                                        : 'Akku $batteryPercent %${batteryObservedAt == null ? '' : ' · gemessen ${obTime(batteryObservedAt)}'}',
                                    value: bandStatusLabel(
                                      c,
                                      b.connection,
                                      controller.bandStatus,
                                    ),
                                  ),
                                ),
                                OBSettingsRow(
                                  label: 'Aktualität',
                                  stackAtLargeText: true,
                                  detail: b.receivedAt != null
                                      ? '${_relativeTime(b.receivedAt!, controller.now())} übertragen'
                                      : stored != null
                                      ? 'letzter gespeicherter Wert ${_relativeTime(stored, controller.now())}'
                                      : 'Noch kein Empfang',
                                  value: stored == null
                                      ? '—'
                                      : g3DataThrough(
                                          stored,
                                          now: controller.now(),
                                        ),
                                ),
                                OBSettingsRow(
                                  label: 'Abdeckung',
                                  stackAtLargeText: true,
                                  detail: [
                                    sleepDetail,
                                    ?coverageDetail,
                                    if (wristOff?.isNotEmpty == true)
                                      '${wristOff!.length} beobachtete Ablegephase${wristOff.length == 1 ? '' : 'n'}',
                                  ].join(' · '),
                                  value: day == null
                                      ? '—'
                                      : day.sleep.duration.value != null &&
                                            day.sleep.unobservedMinutes == 0
                                      ? 'Nacht lückenlos'
                                      : _nightLabel(day.sleep),
                                ),
                                OBSettingsRow(
                                  label: 'Auswertung',
                                  stackAtLargeText: true,
                                  detail: day?.calculatedAt == null
                                      ? null
                                      : obTime(day!.calculatedAt),
                                  value: controller.calculating
                                      ? 'Wird berechnet'
                                      : day?.calculatedAt == null
                                      ? '—'
                                      : day!.sleep.duration.readiness ==
                                                MetricReadiness.partial ||
                                            day.sleep.duration.readiness ==
                                                MetricReadiness.unreliable
                                      ? 'Teilweise'
                                      : 'Fertig',
                                ),
                              ],
                            ),
                            if (ready.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Text(
                                bandStatusValuesHeading(
                                  controller.selectedDay,
                                  controller.now(),
                                ),
                                style: g.caps(color: g.muted),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final item in ready)
                                    if (largeText)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: g.chip,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          '${item.$1} · ${item.$2.value != null && item.$2.readiness == MetricReadiness.available ? 'bereit' : '—'}',
                                          style: g.t(11, 16, color: g.ink2),
                                        ),
                                      )
                                    else
                                      OBChip(
                                        OBChipKind.tag,
                                        '${item.$1} · ${item.$2.value != null && item.$2.readiness == MetricReadiness.available ? 'bereit' : '—'}',
                                      ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          children: [
                            if (onSync != null) ...[
                              g3chrome.OBActionPrimary(
                                'Übertragung fortsetzen',
                                expand: true,
                                height: largeText ? 88 : 48,
                                onPressed: () {
                                  Navigator.pop(c);
                                  onSync();
                                },
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (onSync == null)
                              g3chrome.OBActionPrimary(
                                'Schließen',
                                expand: true,
                                height: largeText ? 64 : 48,
                                onPressed: () => Navigator.pop(c),
                              )
                            else
                              g3chrome.OBActionSecondary(
                                'Schließen',
                                expand: true,
                                height: largeText ? 64 : 48,
                                onPressed: () => Navigator.pop(c),
                              ),
                            if (day?.synthetic == true) ...[
                              const SizedBox(height: 12),
                              Text(
                                'SYNTHETISCHE DATEN',
                                style: g.caps(color: g.muted, size: 11),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
