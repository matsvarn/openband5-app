part of 'screens.dart';

class OpenBandSleep extends StatefulWidget {
  final OpenBandController controller;
  final bool asTab;
  const OpenBandSleep({
    super.key,
    required this.controller,
    this.asTab = false,
  });

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
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  widget.asTab ? kOBTabBarContentInset : 24,
                ),
                children: [
                  G2PageHeader(
                    title: 'Schlaf',
                    backText: widget.asTab ? null : 'Heute',
                    showBack: !widget.asTab,
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
    final tabNavigator = Navigator.of(context);
    await pushFullScreen(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SleepEditor(
          controller: controller,
          onReturnToOverview: () =>
              tabNavigator.popUntil((route) => route.isFirst),
        ),
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
                              style: deltaColor == null || deltaColor == p.muted
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
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    final labelText = Text(label, style: p.text(14, color: p.muted));
    final valueText = Text(value, style: p.text(14, weight: FontWeight.w700));
    final valueRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [if (large) Flexible(child: valueText) else valueText],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: large
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: 4), valueRow],
            )
          : Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 20,
              runSpacing: 4,
              children: [labelText, valueRow],
            ),
    );
  }
}

Future<void> _sleepMethod(
  BuildContext context,
  OpenBandController controller,
) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
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
                  : obDuration(night.unobservedMinutes),
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
