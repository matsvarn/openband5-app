import 'package:flutter/material.dart';
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
import '../ui2/profile/profile.dart' show SetRow;
import 'naps.dart';
import 'sleep_editor.dart';
import 'sleep_goal.dart';
import 'theme.dart';

class OpenBandOverview extends StatelessWidget {
  final OpenBandController controller;
  final VoidCallback? onProfile, onJournal, onNutrition, onTraining, onSync;
  const OpenBandOverview({
    super.key,
    required this.controller,
    this.onProfile,
    this.onJournal,
    this.onNutrition,
    this.onTraining,
    this.onSync,
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final p = OB.of(context);
      final day = controller.day;
      void sleep() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OpenBandSleep(controller: controller),
        ),
      );
      return ColoredBox(
        color: p.canvas,
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            key: const PageStorageKey('openband.overview'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 0, 0),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => chooseOpenBandDay(context, controller),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              obDayTitle(controller.selectedDay),
                              style: p.text(
                                30,
                                weight: FontWeight.w800,
                                display: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Icon(
                              LucideIcons.chevronDown,
                              size: 18,
                              color: p.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _BandPill(
                          band: controller.band,
                          onTap: () =>
                              showBandStatus(context, controller, onSync),
                        ),
                        if (onProfile != null) ...[
                          const SizedBox(width: 8),
                          _CircleButton(
                            tooltip: 'Profil',
                            icon: LucideIcons.userRound,
                            onPressed: onProfile!,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (day?.synthetic == true)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  child: Text(
                    'Synthetische Daten',
                    style: p.text(12, color: p.muted),
                  ),
                ),
              const SizedBox(height: 12),
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
                OBCard(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: p.well,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: _AdaptiveValues(
                          children: [
                            MetricRing(
                              label: 'Schlaf',
                              value: obDuration(day.sleep.duration.value),
                              unit: _sleepDelta(day.sleep.duration),
                              color: p.sleep,
                              tint: p.sleepTint,
                              night: day.sleep,
                              onTap: sleep,
                            ),
                            MetricRing(
                              label: 'Erholung',
                              value: obNumber(day.recovery.value),
                              unit: day.recovery.value == null
                                  ? null
                                  : 'von 100',
                              color: p.recovery,
                              tint: p.recoveryTint,
                              fraction: day.recovery.value == null
                                  ? null
                                  : day.recovery.value! / 100,
                              onTap: () => OpenBandMetricDetail.push(
                                context,
                                controller: controller,
                                metricKey: MetricKey.recovery,
                                label: 'Erholung',
                                subtitle: 'aus der Nacht',
                                unit: 'von 100',
                                icon: LucideIcons.heartPulse,
                                color: (p) => p.recovery,
                                tint: (p) => p.recoveryTint,
                              ),
                            ),
                            MetricRing(
                              label: 'Belastung',
                              value: obNumber(day.strain.value, digits: 1),
                              unit: day.strain.value == null ? null : 'von 21',
                              color: p.strain,
                              tint: p.strainTint,
                              fraction: day.strain.value == null
                                  ? null
                                  : day.strain.value! / 21,
                              onTap: () => OpenBandMetricDetail.push(
                                context,
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
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: sleep,
                        borderRadius: BorderRadius.circular(12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: p.sleepTint,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  LucideIcons.moon,
                                  size: 18,
                                  color: p.sleep,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  (day.sleep.unobservedMinutes ?? 0) > 0
                                      ? '${obGapMinutes(day.sleep.unobservedMinutes!)} fehlen'
                                      : day.sleep.duration.value != null &&
                                            day.sleep.duration.readiness ==
                                                MetricReadiness.available
                                      ? 'Schlaf ansehen'
                                      : _nightLabel(day.sleep),
                                  style: p.text(15, weight: FontWeight.w600),
                                ),
                              ),
                              if (day.sleep.duration.value != null &&
                                  MediaQuery.textScalerOf(context).scale(14) <=
                                      20) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        ((day.sleep.unobservedMinutes ?? 0) > 0
                                                ? p.strain
                                                : p.recovery)
                                            .withValues(alpha: .1),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    (day.sleep.unobservedMinutes ?? 0) > 0
                                        ? 'Teilweise'
                                        : 'Nacht erfasst',
                                    style: p.text(
                                      12,
                                      color:
                                          (day.sleep.unobservedMinutes ?? 0) > 0
                                          ? p.strainText
                                          : p.recoveryText,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Icon(
                                LucideIcons.chevronRight,
                                size: 14,
                                color: p.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (day.correction != null || controller.calculating)
                  CorrectionBanner(controller: controller),
                _AdaptiveValues(
                  children: [
                    OBMetricCard(
                      label: 'HRV',
                      metric: day.hrv,
                      unit: 'ms',
                      icon: LucideIcons.activity,
                      color: p.recovery,
                      tint: p.recoveryTint,
                      day: day.day,
                      onTap: () => OpenBandMetricDetail.push(
                        context,
                        controller: controller,
                        metricKey: MetricKey.hrv,
                        label: 'HRV',
                        subtitle: 'Herzratenvariabilität',
                        unit: 'ms',
                        icon: LucideIcons.activity,
                        color: (p) => p.recovery,
                        tint: (p) => p.recoveryTint,
                      ),
                    ),
                    OBMetricCard(
                      label: 'Ruhepuls',
                      metric: day.restingHr,
                      unit: '/min',
                      icon: LucideIcons.heart,
                      color: p.pulse,
                      tint: p.pulseTint,
                      day: day.day,
                      onTap: () => OpenBandMetricDetail.push(
                        context,
                        controller: controller,
                        metricKey: MetricKey.restingHr,
                        label: 'Ruhepuls',
                        subtitle: 'in der Nacht',
                        unit: '/min',
                        icon: LucideIcons.heart,
                        color: (p) => p.pulse,
                        tint: (p) => p.pulseTint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: sleep,
                  borderRadius: BorderRadius.circular(20),
                  child: OBCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Deine Nacht',
                                style: p.text(15, weight: FontWeight.w600),
                              ),
                            ),
                            Text(
                              '${obTime(day.sleep.onset)}–${obTime(day.sleep.wake)}',
                              style: p.text(12, color: p.muted),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              LucideIcons.chevronRight,
                              size: 14,
                              color: p.muted,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        NightChart(night: day.sleep, showGapCaption: false),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            spacing: 20,
                            runSpacing: 4,
                            children: [
                              Text(
                                '${obDuration(day.sleep.bedMinutes)} im Bett',
                                style: p.text(12, color: p.muted),
                              ),
                              Text(
                                '${obNumber(day.sleep.awakeMinutes)} Min. wach',
                                style: p.text(12, color: p.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                StepsCard(
                  day: day,
                  now: controller.now,
                  onNutrition: onNutrition,
                ),
                const SizedBox(height: 12),
                if (onJournal != null)
                  OBCard(
                    child: _ActionRow(
                      'Dein Journal',
                      LucideIcons.notebookPen,
                      onJournal!,
                    ),
                  ),
                if (onTraining != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OBCard(
                      child: _ActionRow(
                        'Training',
                        LucideIcons.dumbbell,
                        onTraining!,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => showBandStatus(context, controller, onSync),
                  child: Text(
                    'Datenstand · ${controller.band.latestStoredAt == null ? 'noch offen' : obTime(controller.band.latestStoredAt)}',
                    style: p.text(12, color: p.muted),
                  ),
                ),
              ],
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

String _sleepDeltaLabel(DayMetric duration) {
  final d = (duration.value! - duration.baseline!).round();
  if (d == 0) return 'wie Basis';
  return '${d > 0 ? '+' : '−'}${obGapMinutes(d.abs())} '
      '${d > 0 ? 'über' : 'unter'} Basis';
}

String _sleepEfficiency(SleepNight night) {
  final v = night.duration.value, bed = night.bedMinutes;
  if (v == null || bed == null || bed <= 0) return '—';
  return '${(v / bed * 100).round()} %';
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

Widget _sleepStageFact(OB p, String label, Color? swatch, String value) =>
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: swatch ?? p.well,
                  borderRadius: BorderRadius.circular(2),
                  border: swatch == null ? Border.all(color: p.line) : null,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: p.text(11, weight: FontWeight.w600, color: p.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: p.text(15, weight: FontWeight.w700, display: true),
            ),
          ),
        ],
      ),
    );

class _AdaptiveValues extends StatelessWidget {
  final List<Widget> children;
  const _AdaptiveValues({required this.children});
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

class OBMetricCard extends StatelessWidget {
  final String label, unit, day;
  final DayMetric metric;
  final IconData icon;
  final Color color, tint;
  final VoidCallback? onTap;
  const OBMetricCard({
    super.key,
    required this.label,
    required this.unit,
    required this.metric,
    required this.icon,
    required this.color,
    required this.tint,
    required this.day,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final status = obMetricStatus(metric.value, metric.baseline);
    final statusColor = status.endsWith('Basis') && metric.value != null
        ? p.smallText(color)
        : p.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AlpRadius.card),
      child: OBCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          style: p.text(
                            13,
                            weight: FontWeight.w600,
                            color: p.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        obNumber(metric.value),
                        style: p.text(
                          34,
                          weight: FontWeight.w800,
                          display: true,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        unit,
                        style: p.text(
                          14,
                          weight: FontWeight.w500,
                          color: p.muted,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    status,
                    style: p.text(
                      13,
                      weight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            OBRangePill(metric: metric, color: color, tint: tint),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  const _CircleButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: p.card,
        foregroundColor: p.ink,
        fixedSize: const Size(40, 40),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}

/// 40-px sync status pill under the overview header. Says nothing when there
/// is nothing to say — a progress track would need a real progress value,
/// which [BandSnapshot] does not carry, so none is drawn.
class OBSyncState extends StatelessWidget {
  final BandSnapshot band;
  final VoidCallback? onResume;
  final DateTime Function() now;
  const OBSyncState({
    super.key,
    required this.band,
    this.onResume,
    required this.now,
  });

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
        p.warning,
        'Unterbrochen · $stored',
        onResume == null
            ? null
            : TextButton(
                onPressed: onResume,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Fortsetzen',
                  style: p.text(13, weight: FontWeight.w600, color: p.action),
                ),
              ),
      ),
      TransferState.idle => switch (band.receivedAt) {
        final at? when now().difference(at).inMinutes.abs() <= 10 => (
          LucideIcons.check,
          p.recovery,
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
    return Semantics(
      label: text,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            spacing: 10,
            children: [
              Icon(icon, size: 16, color: iconColor),
              Expanded(
                child: Text(text!, style: p.text(13, weight: FontWeight.w600)),
              ),
              ?trailing,
            ],
          ),
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
    return Semantics(
      label:
          'Band, ${band.connection == BandConnection.connected ? 'verbunden' : 'nicht verbunden'}, Akku ${band.batteryPercent == null ? 'unbekannt' : '${band.batteryPercent} Prozent'}',
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: ExcludeSemantics(
          child: Container(
            height: 40,
            padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 17,
                  height: 22,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(LucideIcons.watch, size: 17, color: p.ink),
                      Positioned(
                        left: 9,
                        top: 12,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: band.connection == BandConnection.connected
                                ? p.recovery
                                : p.gap,
                            shape: BoxShape.circle,
                            border: Border.all(color: p.card, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  band.batteryPercent == null
                      ? '—'
                      : '${band.batteryPercent} %',
                  style: p.text(15, weight: FontWeight.w700, display: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
            Text('Dein Datenstand', style: p.text(18, weight: FontWeight.w600)),
            const SizedBox(height: 16),
            _Fact('Verbindung heute', switch (b.connection) {
              BandConnection.connected => 'Verbunden',
              BandConnection.connecting => 'Verbindung wird aufgebaut',
              BandConnection.disconnected => 'Nicht verbunden',
            }),
            _Fact(
              'Akku',
              b.batteryPercent == null ? 'Unbekannt' : '${b.batteryPercent} %',
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
            const SizedBox(height: 12),
            if (onSync != null)
              OBAction(
                'Übertragung fortsetzen',
                onPressed: () {
                  Navigator.pop(c);
                  onSync();
                },
              ),
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

class OpenBandSleep extends StatelessWidget {
  final OpenBandController controller;
  const OpenBandSleep({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final p = OB.of(context);
      final day = controller.day;
      final night = day?.sleep ?? const SleepNight();
      return Scaffold(
        body: SafeArea(
          top: false,
          child: ListView(
            key: PageStorageKey('openband.sleep.${controller.selectedDay}'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              OBPageHeader(
                title: 'Schlaf',
                subtitle:
                    '${night.onset == null ? '' : '${night.onset!.day}./'}${obDate(controller.selectedDay)}',
                onDate: () => chooseOpenBandDay(context, controller),
                onInfo: () => _sleepMethod(context, controller),
                infoLabel: 'Schlafwerte und Methode',
              ),
              if (controller.loadError != null)
                OBAction('Daten erneut laden', onPressed: controller.refresh),
              if (controller.loading && day == null)
                const Center(child: CircularProgressIndicator.adaptive()),
              if (day != null) ...[
                OBCard(
                  child: night.duration.value == null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Für diese Nacht liegt noch kein Schlafwert vor.',
                              style: p.text(14, color: p.muted),
                            ),
                            if (night.duration.reason != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                night.duration.reason!,
                                style: p.text(14, color: p.muted),
                              ),
                            ],
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 12,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      obDuration(night.duration.value),
                                      style: p.text(
                                        34,
                                        weight: FontWeight.w800,
                                        display: true,
                                      ),
                                    ),
                                    if (night.duration.baseline != null) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        _sleepDeltaLabel(night.duration),
                                        style: p.text(
                                          13,
                                          weight: FontWeight.w600,
                                          color: p.smallText(p.sleep),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Effizienz',
                                      style: p.text(
                                        13,
                                        weight: FontWeight.w600,
                                        color: p.muted,
                                      ),
                                    ),
                                    Text(
                                      _sleepEfficiency(night),
                                      style: p.text(
                                        17,
                                        weight: FontWeight.w700,
                                        display: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: p.well,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: NightChart(
                                night: night,
                                labels: false,
                                showGapCaption: false,
                              ),
                            ),
                            if (night.onset != null && night.wake != null)
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  for (final t in _sleepAxisTimes(night))
                                    Text(
                                      obTime(t),
                                      style: p.text(
                                        12,
                                        weight: FontWeight.w500,
                                        color: p.muted,
                                      ),
                                    ),
                                ],
                              ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sleepStageFact(
                                  p,
                                  'Tief',
                                  p.stageDeep,
                                  obDuration(night.deepMinutes),
                                ),
                                _sleepStageFact(
                                  p,
                                  'Leicht',
                                  p.stageLight,
                                  obDuration(night.lightMinutes),
                                ),
                                _sleepStageFact(
                                  p,
                                  'REM',
                                  p.stageRem,
                                  obDuration(night.remMinutes),
                                ),
                                _sleepStageFact(
                                  p,
                                  'Wach',
                                  p.wake,
                                  night.awakeMinutes == null
                                      ? '—'
                                      : '${obNumber(night.awakeMinutes)} Min.',
                                ),
                                _sleepStageFact(
                                  p,
                                  'Im Bett',
                                  null,
                                  obDuration(night.bedMinutes),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                if (day.correction != null || controller.calculating)
                  CorrectionBanner(controller: controller),
                _AdaptiveValues(
                  children: [
                    OBMetricCard(
                      label: 'HRV',
                      unit: 'ms',
                      metric: day.hrv,
                      icon: LucideIcons.activity,
                      color: p.recovery,
                      tint: p.recoveryTint,
                      day: day.day,
                      onTap: () => OpenBandMetricDetail.push(
                        context,
                        controller: controller,
                        metricKey: MetricKey.hrv,
                        label: 'HRV',
                        subtitle: 'Herzratenvariabilität',
                        unit: 'ms',
                        icon: LucideIcons.activity,
                        color: (p) => p.recovery,
                        tint: (p) => p.recoveryTint,
                      ),
                    ),
                    OBMetricCard(
                      label: 'Ruhepuls',
                      unit: '/min',
                      metric: day.restingHr,
                      icon: LucideIcons.heart,
                      color: p.pulse,
                      tint: p.pulseTint,
                      day: day.day,
                      onTap: () => OpenBandMetricDetail.push(
                        context,
                        controller: controller,
                        metricKey: MetricKey.restingHr,
                        label: 'Ruhepuls',
                        subtitle: 'in der Nacht',
                        unit: '/min',
                        icon: LucideIcons.heart,
                        color: (p) => p.pulse,
                        tint: (p) => p.pulseTint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OBCard(
                  child: Column(
                    children: [
                      SetRow(
                        LucideIcons.chartNoAxesCombined,
                        p.sleep,
                        'Nachtverlauf',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => OpenBandNightSignals(
                              repository: controller.repository,
                              day: controller.selectedDay,
                            ),
                          ),
                        ),
                      ),
                      SetRow(
                        LucideIcons.moon,
                        p.sleep,
                        'Nickerchen',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                OpenBandNaps(controller: controller),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OBCard(
                  child: SetRow(
                    LucideIcons.target,
                    p.sleep,
                    'Schlafziel',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OpenBandSleepGoal(
                          repository: controller.repository,
                          day: controller.selectedDay,
                          synthetic: controller.day?.synthetic == true,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<MetricPoint>>(
                  future: controller.repository.readMetricHistory(
                    MetricKey.sleepDuration,
                    controller.selectedDay,
                    30,
                  ),
                  builder: (context, snapshot) => OBTrendCard(
                    label: 'Schlafdauer',
                    unit: '',
                    icon: LucideIcons.moon,
                    color: p.sleep,
                    tint: p.sleepTint,
                    nights: 30,
                    points: snapshot.data,
                    baseline: night.duration.baseline,
                    error: snapshot.hasError,
                    format: obDuration,
                  ),
                ),
                const SizedBox(height: 12),
                Tooltip(
                  message: 'Schlafzeiten ändern',
                  child: OBAction(
                    'Zeiten korrigieren',
                    secondary: true,
                    onPressed: () => _edit(context),
                  ),
                ),
              ],
            ],
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
                  color: complete ? p.recovery : p.action,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 20,
        runSpacing: 4,
        children: [
          Text(label, style: p.text(13, color: p.muted)),
          Text(value, style: p.text(14)),
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
