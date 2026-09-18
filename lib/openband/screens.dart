import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'alp_tokens.dart';
import 'charts.dart';
import 'controller.dart';
import 'day_picker.dart';
import 'domain.dart';
import 'daily_activity.dart';
import 'health.dart';
import 'sleep_editor.dart';
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
                              onTap: () => showMetric(
                                context,
                                'Erholung',
                                day.recovery,
                                '/ 100',
                                day.day,
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
                              onTap: () => showMetric(
                                context,
                                'Belastung',
                                day.strain,
                                '/ 21',
                                day.day,
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
                if (controller.band.transfer != TransferState.idle)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OBCard(
                      child: Row(
                        children: [
                          Icon(
                            controller.band.transfer ==
                                    TransferState.interrupted
                                ? LucideIcons.bluetoothOff
                                : LucideIcons.refreshCw,
                            size: 18,
                            color: p.action,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              controller.band.transfer ==
                                      TransferState.interrupted
                                  ? 'Übertragung unterbrochen. Gespeicherte Werte bleiben erhalten.'
                                  : 'Banddaten werden gespeichert.',
                              style: p.text(13),
                            ),
                          ),
                          if (onSync != null)
                            IconButton(
                              tooltip: 'Übertragung fortsetzen',
                              onPressed: onSync,
                              icon: const Icon(LucideIcons.refreshCw, size: 18),
                            ),
                        ],
                      ),
                    ),
                  ),
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
                    ),
                    OBMetricCard(
                      label: 'Ruhepuls',
                      metric: day.restingHr,
                      unit: '/min',
                      icon: LucideIcons.heart,
                      color: p.pulse,
                      tint: p.pulseTint,
                      day: day.day,
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
                StepsCard(day: day, onNutrition: onNutrition),
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
  const OBMetricCard({
    super.key,
    required this.label,
    required this.unit,
    required this.metric,
    required this.icon,
    required this.color,
    required this.tint,
    required this.day,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final status = obMetricStatus(metric.value, metric.baseline);
    final statusColor = status.endsWith('Basis') && metric.value != null
        ? p.smallText(color)
        : p.muted;
    return InkWell(
      onTap: () => showMetric(context, label, metric, unit, day),
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
                    '${night.onset == null ? '' : '${night.onset!.day}./'}${obDate(controller.selectedDay)}${day?.synthetic == true ? ' · Synthetische Daten' : ''}',
                onDate: () => chooseOpenBandDay(context, controller),
                onInfo: () => _sleepMethod(context, night),
                infoLabel: 'Schlafwerte und Methode',
              ),
              if (controller.loadError != null)
                OBAction('Daten erneut laden', onPressed: controller.refresh),
              if (controller.loading && day == null)
                const Center(child: CircularProgressIndicator.adaptive()),
              if (day != null) ...[
                OBCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  obDuration(night.duration.value),
                                  style: p.text(38, weight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Schlaf',
                                  style: p.text(13, color: p.muted),
                                ),
                              ],
                            ),
                          ),
                          if (night.onset != null && night.wake != null)
                            IconButton(
                              tooltip: 'Schlafzeiten ändern',
                              onPressed: () => _edit(context),
                              icon: const Icon(LucideIcons.pencil, size: 19),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (night.duration.value == null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            night.duration.reason ??
                                'Für diese Nacht liegt noch kein Schlafwert vor.',
                            style: p.text(14, color: p.muted),
                          ),
                        ),
                      NightChart(night: night, labels: true),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final part in [
                            (NightStage.rem, night.remMinutes),
                            (NightStage.light, night.lightMinutes),
                            (NightStage.deep, night.deepMinutes),
                            (NightStage.awake, night.awakeMinutes),
                          ])
                            if (part.$2 != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: stageColor(
                                    p,
                                    part.$1,
                                  ).withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${stageName(part.$1)} ${part.$1 == NightStage.awake ? '${obNumber(part.$2)} Min.' : obDuration(part.$2)}',
                                  style: p.text(
                                    13,
                                    color: switch (part.$1) {
                                      NightStage.rem ||
                                      NightStage.light => p.sleepText,
                                      NightStage.deep => p.stageDeep,
                                      NightStage.awake => p.strainText,
                                    },
                                  ),
                                ),
                              ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${obDuration(night.bedMinutes)} im Bett',
                        style: p.text(13, color: p.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (day.correction != null)
                  CorrectionBanner(controller: controller),
                _AdaptiveValues(
                  children: [
                    OBMetricCard(
                      label: 'Ruhepuls',
                      unit: '/min',
                      metric: day.restingHr,
                      icon: LucideIcons.heart,
                      color: p.pulse,
                      tint: p.pulseTint,
                      day: day.day,
                    ),
                    OBMetricCard(
                      label: 'HRV',
                      unit: 'ms',
                      metric: day.hrv,
                      icon: LucideIcons.activity,
                      color: p.recovery,
                      tint: p.recoveryTint,
                      day: day.day,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (night.history.isNotEmpty)
                  OBCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Deine Woche',
                          style: p.text(15, weight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        _SleepHistory(night.history, p),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                OBCard(
                  child: Column(
                    children: [
                      _ActionRow(
                        'Schlafzeiten prüfen',
                        LucideIcons.clock3,
                        () => _edit(context),
                      ),
                      _ActionRow(
                        'Schlafphasen & Daten',
                        LucideIcons.chartNoAxesCombined,
                        () => _sleepMethod(context, night),
                      ),
                      _Fact('Quelle', night.source),
                      _Fact(
                        'Aufzeichnungszone',
                        night.recordingTimezone ?? 'Nicht gespeichert',
                      ),
                    ],
                  ),
                ),
                if (day.correction != null && !day.correction!.automatic)
                  TextButton(
                    onPressed: () => restoreAutomaticSleep(
                      context,
                      controller,
                      controller.selectedDay,
                    ),
                    child: const Text('Automatische Zeiten wiederherstellen'),
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

class _SleepHistory extends StatelessWidget {
  final List<({String day, double? minutes})> history;
  final OB p;
  const _SleepHistory(this.history, this.p);
  @override
  Widget build(BuildContext context) {
    final entries = history.length > 7
        ? history.sublist(history.length - 7)
        : history;
    return Semantics(
      label: entries
          .map((e) => '${obDate(e.day)}: ${obDuration(e.minutes)} Schlaf')
          .join('. '),
      child: Column(
        children: [
          SizedBox(
            height: 54,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final e in entries)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        height: e.minutes == null
                            ? 2
                            : ((e.minutes! / 600) * 54).clamp(3, 54),
                        decoration: BoxDecoration(
                          color: e.minutes == null
                              ? p.line
                              : p.sleep.withValues(alpha: .65),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                obDate(entries.first.day),
                style: p.text(12, color: p.muted),
              ),
              Text(obDate(entries.last.day), style: p.text(12, color: p.muted)),
            ],
          ),
        ],
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

Future<void> showMetric(
  BuildContext context,
  String title,
  DayMetric metric,
  String unit,
  String day,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (c) {
    final p = OB.of(c);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: p.text(18, weight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(
              '${obNumber(metric.value, digits: title == 'Belastung' ? 1 : 0)} $unit',
              style: p.text(32, weight: FontWeight.w600),
            ),
            _Fact('Tag', obDate(day)),
            if (metric.baseline != null)
              _Fact('Persönliche Basis', '${obNumber(metric.baseline)} $unit'),
            Text(
              metric.reason ??
                  (metric.value == null
                      ? 'Für diesen Tag fehlt eine ausreichende Datengrundlage.'
                      : 'Gespeicherter, auf dem Gerät berechneter Wert. Fehlende Eingänge werden nicht ergänzt.'),
              style: p.text(14, color: p.muted),
            ),
            const SizedBox(height: 12),
            OBAction('Schließen', onPressed: () => Navigator.pop(c)),
          ],
        ),
      ),
    );
  },
);
Future<void> _sleepMethod(
  BuildContext context,
  SleepNight night,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (c) {
    final p = OB.of(c);
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
              'Ohne Daten',
              night.unobservedMinutes == null
                  ? 'Nicht bestimmt'
                  : '${obNumber(night.unobservedMinutes)} Min.',
            ),
            OBAction('Schließen', onPressed: () => Navigator.pop(c)),
          ],
        ),
      ),
    );
  },
);
