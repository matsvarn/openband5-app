import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'alp_tokens.dart';
import 'charts.dart';
import 'controller.dart';
import 'day_picker.dart';
import 'domain.dart';
import 'daily_activity.dart';
import 'health.dart';
import 'metric_detail.dart';
import 'night_signals.dart';
import '../data/day_label.dart';
import '../ui2/profile/profile.dart' show SetRow;
import 'naps.dart';
import 'scale.dart';
import 'sleep_editor.dart';
import 'sleep_goal.dart';
import 'sleep_plan.dart';
import 'theme.dart';

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
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
            children: [
              _OverviewHeader(
                controller: controller,
                synthetic: day?.synthetic == true,
                onBand: () => showBandStatus(context, controller, onSync),
                onProfile: onProfile,
              ),
              const SizedBox(height: 16),
              if (controller.band.latestStoredAt != null &&
                  !OBSyncState.showsFor(controller.band, controller.now))
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
                OBSyncState(
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

class OBMetricCard extends StatelessWidget {
  final String label, unit;
  final DayMetric metric;
  final IconData icon;
  final Color color;
  final int digits;

  /// Metric for the verdict colour of the comparison; null keeps it ink.
  final MetricKey? metricKey;
  final VoidCallback? onTap;
  const OBMetricCard({
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
                                            dayMetricVerdict(metricKey!, metric),
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
enum OBSyncActionState { pending, failed }

class OBSyncState extends StatelessWidget {
  final BandSnapshot band;
  final VoidCallback? onResume;
  final DateTime Function() now;
  final bool showStoredTime;
  final OBSyncActionState? actionState;
  final String interruptedLabel;
  final String pendingLabel;
  final String failedLabel;
  final String resumeLabel;
  final String retryLabel;
  const OBSyncState({
    super.key,
    required this.band,
    this.onResume,
    required this.now,
    this.showStoredTime = true,
    this.actionState,
    this.interruptedLabel = 'Unterbrochen',
    this.pendingLabel = 'Verbindung wird hergestellt',
    this.failedLabel = 'Fortsetzen fehlgeschlagen',
    this.resumeLabel = 'Fortsetzen',
    this.retryLabel = 'Erneut',
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
    ) = switch (actionState) {
      OBSyncActionState.pending => (
        LucideIcons.refreshCw,
        p.action,
        pendingLabel,
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      OBSyncActionState.failed => (
        LucideIcons.bluetoothOff,
        p.warning,
        failedLabel,
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
                  retryLabel,
                  textAlign: TextAlign.center,
                  style: p.text(13, weight: FontWeight.w600, color: p.ink),
                ),
              ),
      ),
      null => switch (band.transfer) {
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
          p.warning,
          showStoredTime ? '$interruptedLabel · $stored' : interruptedLabel,
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
                    resumeLabel,
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
      },
    };
    if (icon == null) return const SizedBox.shrink();
    final actionable =
        actionState != null ||
        (band.transfer == TransferState.interrupted && onResume != null);
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

Future<void> showBandStatus(
  BuildContext context,
  OpenBandController controller,
  VoidCallback? onSync,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (c) {
    final p = OB.of(c);
    final b = controller.band;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('BAND · WHOOP 5.0', style: p.label(size: 11)),
            const SizedBox(height: 2),
            Text(
              'Dein Datenstand',
              style: p.text(24, weight: FontWeight.w700, display: true),
            ),
            const SizedBox(height: 14),
            OBCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  _Fact('Verbindung heute', switch (b.connection) {
                    BandConnection.connected => 'Verbunden',
                    BandConnection.connecting => 'Verbindung wird aufgebaut',
                    BandConnection.disconnected => 'Nicht verbunden',
                  }),
                  _Fact(
                    'Akku',
                    b.batteryPercent == null
                        ? 'Unbekannt'
                        : '${b.batteryPercent} %',
                  ),
                  _Fact(
                    'Akku beobachtet',
                    b.batteryObservedAt == null
                        ? 'Zeitpunkt unbekannt'
                        : '${obDate(b.batteryObservedAt!.toIso8601String().substring(0, 10))} · ${obTime(b.batteryObservedAt)}',
                  ),
                  _Fact(
                    'Gespeicherte Banddaten bis',
                    b.latestStoredAt == null
                        ? 'Noch keine bestätigten Daten'
                        : '${obDate(b.latestStoredAt!.toIso8601String().substring(0, 10))} · ${obTime(b.latestStoredAt)}',
                  ),
                  _Fact(
                    'Auf dem iPhone gespeichert',
                    b.receivedAt == null
                        ? 'Zeitpunkt unbekannt'
                        : obTime(b.receivedAt),
                  ),
                  _Fact(
                    'Nacht am ${obDate(controller.selectedDay)}',
                    controller.day == null
                        ? 'Wird geladen'
                        : _nightLabel(controller.day!.sleep),
                  ),
                  _Fact(
                    'Auswertung',
                    controller.calculating
                        ? 'Wird berechnet'
                        : controller.day?.sleep.duration.reason ??
                              _nightLabel(
                                controller.day?.sleep ?? const SleepNight(),
                              ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (onSync != null)
              OBAction(
                'Übertragung fortsetzen',
                onPressed: () {
                  Navigator.pop(c);
                  onSync();
                },
              ),
            const SizedBox(height: 10),
            OBAction(
              'Schließen',
              secondary: true,
              onPressed: () => Navigator.pop(c),
            ),
          ],
        ),
      ),
    );
  },
);

class OpenBandSleep extends StatefulWidget {
  final OpenBandController controller;
  const OpenBandSleep({super.key, required this.controller});

  /// Nights needed before a 30-night average ("Schnitt") is shown.
  static const int averageMinNights = 7;

  @override
  State<OpenBandSleep> createState() => _OpenBandSleepState();
}

/// Reads for the selected day, made once per day and refreshed with it —
/// not on every controller notification.
class _SleepReads {
  final String day;
  final Future<List<MetricPoint>> history;
  final Future<NapDay> naps;
  final Future<SleepPlanSnapshot>? plan;
  final Future<SleepGoalSnapshot> goal;
  _SleepReads(OpenBandController c, this.day, {required bool today})
    : history = c.repository.readMetricHistory(
        MetricKey.sleepDuration,
        day,
        30,
      ),
      naps = c.repository.readNaps(day),
      plan = today ? c.repository.readSleepPlan(day, now: c.now()) : null,
      goal = c.repository.readSleepGoal(day);
}

class _OpenBandSleepState extends State<OpenBandSleep> {
  OpenBandController get controller => widget.controller;
  _SleepReads? _reads;
  OpenBandDay? _readsFor;

  _SleepReads _readsNow(bool today) {
    final day = controller.day;
    if (_reads?.day != controller.selectedDay || !identical(_readsFor, day)) {
      _readsFor = day;
      _reads = _SleepReads(controller, controller.selectedDay, today: today);
    }
    return _reads!;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final p = OB.of(context);
      final day = controller.day;
      final night = day?.sleep ?? const SleepNight();
      final selected = controller.selectedDay;
      final today = selected == todayLabel(controller.now());
      final reads = _readsNow(today);
      return Scaffold(
        key: const ValueKey('openband-sleep'),
        body: SafeArea(
          child: FutureBuilder<List<MetricPoint>>(
            future: reads.history,
            builder: (context, history) {
              final points = history.data;
              final stored = [
                for (final e in points ?? const <MetricPoint>[])
                  if (e.value != null) e.value!,
              ];
              final average = stored.length >= OpenBandSleep.averageMinNights
                  ? stored.reduce((a, b) => a + b) / stored.length
                  : null;
              return ListView(
                key: PageStorageKey('openband.sleep.$selected'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  OBPageHeader(
                    title: 'Schlaf',
                    backText: 'Heute',
                    subtitle: '',
                    // Paper: pill 4 pt under the header; its hit area adds 2.
                    bottom: 2,
                    onInfo: () => _sleepMethod(context, controller),
                    infoLabel: 'Schlafwerte und Methode',
                  ),
                  Center(
                    child: OBDayPill(
                      label: obNightPillLabel(selected),
                      onTap: () => chooseOpenBandDay(context, controller),
                      onPrevious: () =>
                          controller.selectDay(_shiftDay(selected, -1)),
                      onNext: today
                          ? null
                          : () => controller.selectDay(_shiftDay(selected, 1)),
                    ),
                  ),
                  if (controller.loadError != null)
                    OBAction(
                      'Daten erneut laden',
                      onPressed: controller.refresh,
                    ),
                  if (controller.loading && day == null)
                    const Center(child: CircularProgressIndicator.adaptive()),
                  if (day != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 28, 8, 0),
                      child: _SleepHero(night: night, average: average),
                    ),
                    if (night.segments.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _Inset4(child: _NightLedCard(night: night)),
                    ],
                    if (night.duration.value != null) ...[
                      const SizedBox(height: 10),
                      _Inset4(
                        child: _StageRows(
                          key: const ValueKey('sleep-stage-rows'),
                          night: night,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (day.correction != null || controller.calculating)
                      _Inset4(child: CorrectionBanner(controller: controller)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
                      child: Text(
                        'IN DIESER NACHT',
                        style: p.label(size: 11).copyWith(height: 14 / 11),
                      ),
                    ),
                    _Inset4(
                      child: OBAdaptiveValues(
                        children: [
                          _NightTile(
                            label: 'HRV',
                            unit: 'ms',
                            metricKey: MetricKey.hrv,
                            metric: day.hrv,
                            onTap: () => OpenBandMetricDetail.push(
                              context,
                              backText: 'Schlaf',
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
                          _NightTile(
                            label: 'Puls',
                            unit: '/min',
                            metricKey: MetricKey.restingHr,
                            metric: day.restingHr,
                            onTap: () => OpenBandMetricDetail.push(
                              context,
                              backText: 'Schlaf',
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
                    ),
                    const SizedBox(height: 10),
                    _Inset4(
                      child: _LinkCard(
                        children: [
                          SetRow(
                            LucideIcons.chartLine,
                            p.ink,
                            'Nachtverlauf',
                            value: 'Puls · HRV · Atmung',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => OpenBandNightSignals(
                                  repository: controller.repository,
                                  day: selected,
                                ),
                              ),
                            ),
                          ),
                          _Later<NapDay>(
                            future: reads.naps,
                            builder: (naps) => SetRow(
                              LucideIcons.moon,
                              p.ink,
                              'Nickerchen',
                              value: _napsLabel(naps, today: today),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      OpenBandNaps(controller: controller),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Inset4(
                      child: _LinkCard(
                        children: [
                          if (reads.plan case final plan?)
                            _Later<SleepPlanSnapshot>(
                              future: plan,
                              builder: (plan) => SetRow(
                                LucideIcons.sunset,
                                p.ink,
                                'Heute Nacht',
                                value: _bedtimeLabel(plan),
                                onTap: () {
                                  final synthetic =
                                      controller.day?.synthetic == true;
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => OpenBandSleepPlan(
                                        repository: controller.repository,
                                        day: selected,
                                        now: controller.now,
                                        synthetic: synthetic,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          _Later<SleepGoalSnapshot>(
                            future: reads.goal,
                            builder: (goal) => SetRow(
                              LucideIcons.target,
                              p.ink,
                              'Schlafziel',
                              value: goal?.targetMinutes == null
                                  ? ''
                                  : obDuration(goal!.targetMinutes),
                              onTap: () => Navigator.of(context)
                                  .push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => OpenBandSleepGoal(
                                        repository: controller.repository,
                                        day: selected,
                                        synthetic:
                                            controller.day?.synthetic == true,
                                      ),
                                    ),
                                  )
                                  // The goal feeds the hero and the bars.
                                  .then((_) {
                                    if (!mounted) return;
                                    setState(() => _reads = null);
                                  }),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Inset4(
                      child: _Later<SleepGoalSnapshot>(
                        future: reads.goal,
                        builder: (goal) => _SleepDurationBars(
                          points: points,
                          error: history.hasError,
                          average: average,
                          goal: goal?.targetMinutes?.toDouble(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Inset4(
                      child: Tooltip(
                        message: 'Schlafzeiten ändern',
                        child: OBAction(
                          'Zeiten korrigieren',
                          secondary: true,
                          onPressed: () => _edit(context),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      );
    },
  );
  Future<void> _edit(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SleepEditor(controller: controller),
      ),
    );
  }
}

/// Paper insets page content 20 pt; the sleep list is padded 16 for its
/// header keys.
class _Inset4 extends StatelessWidget {
  final Widget child;
  const _Inset4({required this.child});
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: child);
}

/// Builds with the value once [future] resolves; null while loading or on
/// error, so the row stays usable without its trailing value.
class _Later<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(T? value) builder;
  const _Later({super.key, required this.future, required this.builder});
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snap) => builder(snap.hasError ? null : snap.data),
  );
}

String _shiftDay(String day, int days) {
  final d = DateTime.parse(day);
  return dayLabelOf(DateTime(d.year, d.month, d.day + days));
}

/// "Mo → Di 22.09": the night into the selected day.
String obNightPillLabel(String day) {
  String weekday(DateTime d) =>
      DateFormat('EEE', 'de_DE').format(d).replaceAll('.', '');
  final d = DateTime.parse(day);
  return '${weekday(DateTime(d.year, d.month, d.day - 1))} → '
      '${weekday(d)} ${DateFormat('dd.MM', 'de_DE').format(d)}';
}

String _napsLabel(NapDay? naps, {required bool today}) {
  if (naps == null || !naps.judged) return '';
  if (naps.sessions.isEmpty) return today ? 'heute keins' : 'keins';
  final n = naps.sessions.length;
  return naps.totalMin == null ? '$n×' : '$n× · ${obDuration(naps.totalMin)}';
}

String _bedtimeLabel(SleepPlanSnapshot? plan) {
  final minute = plan?.plan?.bedtimeMinuteOfDay;
  return minute == null ? '' : 'ins Bett ~${sleepPlanClockLabel(minute)}';
}

/// Duration hero (Paper G2 Schlaf): window, the night's sleep and its
/// distance to the 30-night average, then bed, wake and coverage.
class _SleepHero extends StatelessWidget {
  final SleepNight night;
  final double? average;
  const _SleepHero({required this.night, required this.average});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final value = night.duration.value;
    if (value == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Text(
            'Für diese Nacht liegt noch kein Schlafwert vor.',
            style: p.text(14, color: p.muted),
          ),
          if (night.duration.reason != null)
            Text(night.duration.reason!, style: p.text(14, color: p.muted)),
        ],
      );
    }
    final delta = average == null ? null : (value - average!).round();
    final gap = night.unobservedMinutes;
    final fact = p.text(13, color: p.muted).copyWith(height: 16 / 13);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        if (night.onset != null && night.wake != null)
          Text(
            'GESCHLAFEN · ${obTime(night.onset)} – ${obTime(night.wake)}',
            style: p.label(size: 11).copyWith(height: 14 / 11),
          ),
        () {
          final duration = FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              obDuration(value),
              style: p
                  .text(72, weight: FontWeight.w700)
                  .copyWith(height: 74 / 72, letterSpacing: -.04 * 72),
            ),
          );
          final note = delta == null
              ? null
              : Text(
                  delta == 0
                      ? 'wie der Schnitt'
                      : '${delta > 0 ? '+' : '−'}${obGapMinutes(delta.abs())} zum Schnitt',
                  style: p
                      .text(14, weight: FontWeight.w500, color: p.muted)
                      .copyWith(height: 18 / 14),
                );
          // Large text: the note goes under the duration instead of beside.
          if (MediaQuery.textScalerOf(context).scale(14) > 20) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [duration, ?note],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: 12,
            children: [
              duration,
              if (note != null) Flexible(child: note),
            ],
          );
        }(),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (night.bedMinutes != null)
              Text('Im Bett ${obDuration(night.bedMinutes)}', style: fact),
            if (night.awakeMinutes != null)
              Text('Wach ${obGapMinutes(night.awakeMinutes!)}', style: fact),
            if (night.segments.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  OBLed(on: true, color: gap == null ? null : p.warning),
                  Text(
                    gap == null ? 'Lückenlos' : '${obGapMinutes(gap)} Lücke',
                    style: p
                        .text(13, weight: FontWeight.w700)
                        .copyWith(height: 16 / 13),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// The night as a 4-row LED grid (Paper G2): one column per time slot, the
/// stage covering most of the slot lit. A slot mostly without data stays
/// dark rather than borrowing a neighbour's stage.
class _NightLedCard extends StatelessWidget {
  final SleepNight night;
  const _NightLedCard({required this.night});

  static const rows = ['WACH', 'REM', 'LEICHT', 'TIEF'];

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final rowLabel = p
        .text(9, weight: FontWeight.w500, color: p.muted)
        .copyWith(height: 12 / 9, letterSpacing: .1 * 9);
    final axis = p
        .text(10, weight: FontWeight.w500, color: p.muted)
        .copyWith(height: 12 / 10);
    // Paper's grid is 58 pt with a 44 pt label column; both grow with text
    // (clamped at 1.5x) so the four labels keep one size.
    final ts = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    final grid = math.max(58.0, 4 * 12 * ts + 2);
    final large = ts > 1.3;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: OBCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: p.insetDecoration(radius: 10, color: p.well),
              child: Row(
                children: [
                  SizedBox(
                    width: 44 * ts,
                    height: grid,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final r in rows)
                            Text(
                              r,
                              maxLines: 1,
                              softWrap: false,
                              style: rowLabel,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      label: OBStageStrip.describe(night),
                      child: CustomPaint(
                        size: Size.fromHeight(grid),
                        painter: _NightLedPainter(p, night),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (night.onset != null && night.wake != null)
              Padding(
                padding: EdgeInsets.only(left: 18 + 44 * ts, right: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Large text keeps onset and wake only.
                    for (final t
                        in large
                            ? [night.onset!, night.wake!]
                            : _sleepAxisTimes(night))
                      Text(obTime(t), style: axis),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NightLedPainter extends CustomPainter {
  final OB p;
  final SleepNight night;
  _NightLedPainter(this.p, this.night);

  // Paper's 300×68 grid: 51 columns on a 5.9 pitch, 4.4 wide; rows 14 on 18.
  static const columns = 51;

  static int? _row(NightStage? stage) => switch (stage) {
    NightStage.awake => 0,
    NightStage.rem => 1,
    NightStage.light => 2,
    NightStage.deep => 3,
    null => null,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final segments = night.segments;
    if (segments.isEmpty) return;
    final start = segments.first.start, end = segments.last.end;
    final span = end.difference(start).inSeconds;
    if (span <= 0) return;
    final sx = size.width / 300, sy = size.height / 68;
    final lit = [p.wake, p.stageRem, p.stageLight, p.stageDeep];
    lit[0] = p.gap;
    for (var c = 0; c < columns; c++) {
      final from = start.add(Duration(seconds: span * c ~/ columns));
      final to = start.add(Duration(seconds: span * (c + 1) ~/ columns));
      final cover = <int?, int>{};
      for (final s in segments) {
        final a = s.start.isAfter(from) ? s.start : from;
        final b = s.end.isBefore(to) ? s.end : to;
        final overlap = b.difference(a).inSeconds;
        if (overlap > 0) {
          final r = _row(s.stage);
          cover[r] = (cover[r] ?? 0) + overlap;
        }
      }
      int? best;
      var most = 0;
      cover.forEach((r, seconds) {
        if (seconds > most) (best, most) = (r, seconds);
      });
      for (var r = 0; r < 4; r++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(c * 5.9 * sx, r * 18 * sy, 4.4 * sx, 14 * sy),
            Radius.circular(1.2 * sx),
          ),
          Paint()..color = r == best ? lit[r] : p.line,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_NightLedPainter old) =>
      old.night != night || old.p.dark != p.dark;
}

/// Stage totals with their share of sleep (Paper G2): swatch, name, a bar
/// on 0–100 %, the duration and the percentage. Wake has no share of sleep.
class _StageRows extends StatelessWidget {
  final SleepNight night;
  const _StageRows({super.key, required this.night});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final sleep = [
      night.deepMinutes,
      night.lightMinutes,
      night.remMinutes,
    ].whereType<double>().fold<double>(0, (a, b) => a + b);
    final rows = [
      ('Tief', p.stageDeep, night.deepMinutes, true),
      ('Leicht', p.stageLight, night.lightMinutes, true),
      ('REM', p.stageRem, night.remMinutes, true),
      ('Wach', p.gap, night.awakeMinutes, false),
    ].where((r) => r.$3 != null).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return OBCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (final (i, (name, color, minutes, share)) in rows.indexed)
            Container(
              constraints: const BoxConstraints(minHeight: 50),
              decoration: i == rows.length - 1
                  ? null
                  : BoxDecoration(
                      border: Border(bottom: BorderSide(color: p.line)),
                    ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: share ? color : null,
                      border: share ? null : Border.all(color: color),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(
                    width: 76,
                    child: Text(
                      name,
                      style: p
                          .text(15, weight: FontWeight.w500)
                          .copyWith(height: 18 / 15),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 6,
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: p.line,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: share && sleep > 0
                          ? FractionallySizedBox(
                              heightFactor: 1,
                              widthFactor: (minutes! / sleep).clamp(0, 1),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                  Text(
                    share ? obDuration(minutes) : obGapMinutes(minutes!),
                    textAlign: TextAlign.right,
                    style: p
                        .text(16, weight: FontWeight.w700)
                        .copyWith(height: 20 / 16),
                  ),
                  SizedBox(
                    width: MediaQuery.textScalerOf(context).scale(40),
                    child: Text(
                      share && sleep > 0
                          ? '${(minutes! / sleep * 100).round()} %'
                          : '—',
                      textAlign: TextAlign.right,
                      style: p
                          .text(12, color: p.muted)
                          .copyWith(height: 16 / 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact night value (Paper G2 Schlaf): label, value, unit and the delta
/// to a trusted baseline. Non-current states show their reason instead.
class _NightTile extends StatelessWidget {
  final String label, unit;
  final MetricKey metricKey;
  final DayMetric metric;
  final VoidCallback onTap;
  const _NightTile({
    required this.label,
    required this.unit,
    required this.metricKey,
    required this.metric,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final m = metric;
    final comparable =
        m.value != null &&
        m.baseline != null &&
        (m.nightScalar == null || m.nightScalar == NightScalarState.current);
    final delta = comparable ? (m.value! - m.baseline!).round() : null;
    final status = obCompactMetricStatus(m, digits: 0);
    final deltaText = delta == null
        ? null
        : delta == 0
        ? '±0'
        : '${delta > 0 ? '+' : '−'}${delta.abs()}';
    final foot = m.value == null
        ? (status ?? '')
        : deltaText == null
        ? (status == null ? unit : '$unit · $status')
        : '$unit · $deltaText';
    final footStyle = p.text(12, color: p.muted).copyWith(height: 16 / 12);
    final deltaColor = deltaText == null
        ? null
        : obVerdictText(p, dayMetricVerdict(metricKey, m));
    return Semantics(
      button: true,
      label: '$label, ${obNumber(m.value)} $foot',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AlpRadius.card),
          child: OBCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Text(
                  '${label.toUpperCase()} ›',
                  style: p.label().copyWith(height: 12 / 10),
                ),
                Text(
                  obNumber(m.value),
                  style: p
                      .text(
                        24,
                        weight: FontWeight.w700,
                        color: m.value == null ? p.gap : p.ink,
                      )
                      .copyWith(height: 30 / 24),
                ),
                Text.rich(
                  deltaText == null || m.value == null
                      ? TextSpan(text: foot)
                      : TextSpan(
                          children: [
                            TextSpan(text: '$unit · '),
                            TextSpan(
                              text: deltaText,
                              style: deltaColor == null ||
                                      deltaColor == p.muted
                                  ? null
                                  : TextStyle(color: deltaColor),
                            ),
                          ],
                        ),
                  style: footStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A raised card of link rows with hairlines between them.
class _LinkCard extends StatelessWidget {
  final List<Widget> children;
  const _LinkCard({required this.children});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: p.line),
            c,
          ],
        ],
      ),
    );
  }
}

/// Thirty nights of sleep as bars (Paper G2): the goal as a dashed line,
/// a night without a stored value as a hollow stub, the selected night ink.
class _SleepDurationBars extends StatelessWidget {
  final List<MetricPoint>? points;
  final bool error;
  final double? average, goal;
  const _SleepDurationBars({
    required this.points,
    required this.error,
    required this.average,
    required this.goal,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final caption = p
        .text(10, weight: FontWeight.w500, color: p.muted)
        .copyWith(height: 12 / 10);
    final shown = points ?? const <MetricPoint>[];
    String short(String day) =>
        DateFormat('dd.MM', 'de_DE').format(DateTime.parse(day));
    final legend = [
      if (goal != null) '- - Ziel ${obDuration(goal)}',
      if (shown.any((e) => e.value == null)) 'hohl = keine Daten',
    ].join(' · ');
    return OBCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'SCHLAFDAUER · ${shown.length} NÄCHTE',
                  style: caption.copyWith(letterSpacing: .14 * 10),
                ),
              ),
              if (average != null)
                Text('Schnitt ${obDuration(average)}', style: caption),
            ],
          ),
          if (error)
            Text('Verlauf nicht lesbar.', style: p.text(13, color: p.muted))
          else
            Semantics(
              label:
                  'Schlafdauer der letzten ${shown.length} Nächte'
                  '${average == null ? '' : ', Schnitt ${obDuration(average)}'}',
              child: CustomPaint(
                size: const Size.fromHeight(56),
                painter: _DurationBarsPainter(p, shown, goal),
              ),
            ),
          if (shown.isNotEmpty)
            Row(
              children: [
                Text(short(shown.first.day), style: caption),
                Expanded(
                  child: Text(
                    legend,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: caption,
                  ),
                ),
                Text(short(shown.last.day), style: caption),
              ],
            ),
        ],
      ),
    );
  }
}

class _DurationBarsPainter extends CustomPainter {
  final OB p;
  final List<MetricPoint> points;
  final double? goal;
  _DurationBarsPainter(this.p, this.points, this.goal);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final values = [
      for (final e in points)
        if (e.value != null) e.value!,
    ];
    // Linear from zero on a fixed 12 h axis, so bars compare across days;
    // a longer night extends it.
    final top = [...values, ?goal].fold<double>(12 * 60, math.max);
    double y(double v) => size.height * (1 - v / top);
    // Paper: 7 pt bars on an 11 pt pitch across 321 pt.
    final pitch = size.width / (points.length - 4 / 11);
    final bw = pitch * 7 / 11;
    for (final (i, e) in points.indexed) {
      final x = i * pitch;
      final last = i == points.length - 1;
      if (e.value == null) {
        final stub = RRect.fromRectAndRadius(
          Rect.fromLTWH(x + .5, size.height - 12, bw - 1, 11.5),
          const Radius.circular(2),
        );
        _dashed(canvas, Path()..addRRect(stub), p.gap);
        continue;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x, y(e.value!), x + bw, size.height),
          const Radius.circular(2),
        ),
        Paint()..color = last ? p.ink : p.gap,
      );
    }
    if (goal != null) {
      final gy = y(goal!);
      _dashed(
        canvas,
        Path()
          ..moveTo(0, gy)
          ..lineTo(size.width, gy),
        p.ink,
        dash: 2,
        space: 3,
      );
    }
  }

  static void _dashed(
    Canvas canvas,
    Path path,
    Color color, {
    double dash = 2,
    double space = 2,
  }) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + space) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DurationBarsPainter old) =>
      old.points != points || old.goal != goal || old.p.dark != p.dark;
}

class CorrectionBanner extends StatelessWidget {
  final OpenBandController controller;
  const CorrectionBanner({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final correction = controller.day?.correction;
    final failed =
        correction?.state == CorrectionState.failed ||
        controller.calculationErrors.containsKey(controller.selectedDay);
    final complete =
        correction?.state == CorrectionState.complete &&
        !controller.calculating;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OBCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  complete
                      ? LucideIcons.circleCheck
                      : failed
                      ? LucideIcons.circleAlert
                      : LucideIcons.refreshCw,
                  color: complete ? p.led : p.action,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    complete
                        ? 'Schlaf aktualisiert'
                        : failed
                        ? 'Auswertung pausiert'
                        : 'Zeiten gespeichert',
                    style: p.text(14, weight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              complete
                  ? (correction?.automatic == true
                        ? 'Die automatische Erkennung wurde wiederhergestellt.'
                        : 'Die gespeicherten Zeiten wurden ausgewertet.')
                  : failed
                  ? 'Deine Korrektur bleibt gespeichert. Die letzte Schätzung ist noch nicht aktualisiert.'
                  : 'Schlaf und Erholung werden neu berechnet. Die vorherige Schätzung bleibt gekennzeichnet.',
              style: p.text(13, color: p.muted),
            ),
            if (correction != null) ...[
              const SizedBox(height: 6),
              Text(
                correction.automatic
                    ? 'Automatische Erkennung · ${obTime(correction.savedAt)} angefordert'
                    : '${obTime(correction.onset)}–${obTime(correction.wake)} · ${obTime(correction.savedAt)} gespeichert',
                style: p.text(12, color: p.muted),
              ),
              if (!complete && !controller.calculating)
                TextButton(
                  onPressed: () => controller.calculate(correction),
                  child: const Text('Auswertung erneut starten'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ActionRow(this.label, this.icon, this.onTap);
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Icon(icon, size: 19, color: p.action),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: p.text(14, weight: FontWeight.w500)),
            ),
            Icon(LucideIcons.chevronRight, size: 16, color: p.muted),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String label, value;
  const _Fact(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 20,
        runSpacing: 4,
        children: [
          Text(label, style: p.text(14, color: p.muted)),
          Text(value, style: p.text(14, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

Future<void> _sleepMethod(
  BuildContext context,
  OpenBandController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (c) {
    final p = OB.of(c);
    final night = controller.day?.sleep ?? const SleepNight();
    final correction = controller.day?.correction;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Schlafphasen & Daten',
              style: p.text(18, weight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Text(
              'Die Phasen sind Schätzungen aus deinen Aufzeichnungen. Der Ring zeigt ihre Anteile an der Zeit im Bett. Die Zahl in der Mitte ist die beobachtete Schlafdauer, kein Schlafscore.',
              style: p.text(14),
            ),
            const SizedBox(height: 12),
            Text(
              'Zeiten ändern grenzt die Nacht neu ein. Es ergänzt keine fehlenden Messungen. Schraffierte Abschnitte bleiben ohne Daten. Tippe auf den Phasenverlauf, um alle Zeitabschnitte zu lesen.',
              style: p.text(14),
            ),
            _Fact('Quelle', night.source),
            _Fact(
              'Aufzeichnungszone',
              night.recordingTimezone ?? 'Nicht gespeichert',
            ),
            _Fact(
              'Ohne Daten',
              night.unobservedMinutes == null
                  ? 'Nicht bestimmt'
                  : '${obNumber(night.unobservedMinutes)} Min.',
            ),
            if (correction != null && !correction.automatic)
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  restoreAutomaticSleep(
                    context,
                    controller,
                    controller.selectedDay,
                  );
                },
                child: const Text('Automatische Zeiten wiederherstellen'),
              ),
            OBAction('Schließen', onPressed: () => Navigator.pop(c)),
          ],
        ),
      ),
    );
  },
);
