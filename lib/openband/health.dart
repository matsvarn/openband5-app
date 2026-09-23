import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'controller.dart';
import 'domain.dart';
import '../ui2/profile/profile.dart' show SetRow;
import 'glucose.dart';
import 'labs.dart';
import 'alp_tokens.dart';
import 'metric_detail.dart';
import 'scale.dart';
import 'screens.dart';
import 'settings_controls.dart';
import 'theme.dart';
import 'vo2.dart';
import 'weight.dart';

class OpenBandHealth extends StatefulWidget {
  final OpenBandController controller;

  /// Stored band metrics only, with a back header titled Messwerte.
  /// Weight, manual VO₂, labs and glucose stay on the full Gesundheit tab.
  final bool bandMetricsOnly;
  const OpenBandHealth({
    super.key,
    required this.controller,
    this.bandMetricsOnly = false,
  });
  @override
  State<OpenBandHealth> createState() => _OpenBandHealthState();
}

class _OpenBandHealthState extends State<OpenBandHealth> {
  int nights = 7;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final p = OB.of(context);
      final c = widget.controller;
      final day = c.day;
      final page = ColoredBox(
        color: p.canvas,
        child: ListView(
          key: const PageStorageKey('openband.health'),
          padding: EdgeInsets.fromLTRB(
            16,
            widget.bandMetricsOnly ? 0 : 4,
            16,
            24,
          ),
          children: [
            if (widget.bandMetricsOnly)
              OBPageHeader(
                title: 'Messwerte',
                subtitle: obNightPillLabel(c.selectedDay),
                backText: 'Heute',
              )
            else
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'Gesundheit',
                  style: p.text(30, weight: FontWeight.w800, display: true),
                ),
              ),
            SizedBox(height: widget.bandMetricsOnly ? 6 : 12),
            if (!widget.bandMetricsOnly) ...[
              OBSegmented(
                labels: const ['7 Nächte', '30 Nächte'],
                selected: nights == 7 ? 0 : 1,
                onChanged: (i) => setState(() => nights = i == 0 ? 7 : 30),
              ),
              const SizedBox(height: 12),
            ],
            if (day != null && widget.bandMetricsOnly) ...[
              const _MesswertLegend(),
              const SizedBox(height: 14),
              for (final spec in _messwerte(p, day)) ...[
                _MesswertCard(
                  key: spec.key == MetricKey.respiration
                      ? const ValueKey('atemfrequenz')
                      : spec.key == MetricKey.skinTemperature
                      ? const ValueKey('hauttemperatur')
                      : null,
                  spec: spec,
                  onTap: () => spec.open(context, c),
                ),
                const SizedBox(height: 10),
              ],
            ] else if (day != null) ...[
              OBAdaptiveValues(
                children: [
                  OBMetricCard(
                    label: 'HRV',
                    metricKey: MetricKey.hrv,
                    unit: 'ms',
                    metric: day.hrv,
                    icon: LucideIcons.activity,
                    color: p.ink,
                    onTap: () => OpenBandMetricDetail.push(
                      context,
                      backText: widget.bandMetricsOnly ? 'Messwerte' : null,
                      controller: c,
                      metricKey: MetricKey.hrv,
                      label: 'HRV',
                      subtitle: 'Herzratenvariabilität',
                      unit: 'ms',
                      icon: LucideIcons.activity,
                      color: (p) => p.ink,
                      tint: (p) => p.line,
                    ),
                  ),
                  OBMetricCard(
                    label: 'Ruhepuls',
                    metricKey: MetricKey.restingHr,
                    unit: '/min',
                    metric: day.restingHr,
                    icon: LucideIcons.heart,
                    color: p.pulse,
                    onTap: () => OpenBandMetricDetail.push(
                      context,
                      backText: widget.bandMetricsOnly ? 'Messwerte' : null,
                      controller: c,
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
              const SizedBox(height: 10),
              OBAdaptiveValues(
                children: [
                  OBMetricCard(
                    key: const ValueKey('atemfrequenz'),
                    label: 'Atemfrequenz',
                    metricKey: MetricKey.respiration,
                    unit: '/min',
                    metric: day.respiration,
                    icon: LucideIcons.wind,
                    digits: 1,
                    color: p.sleep,
                    onTap: () => OpenBandMetricDetail.push(
                      context,
                      backText: widget.bandMetricsOnly ? 'Messwerte' : null,
                      controller: c,
                      metricKey: MetricKey.respiration,
                      label: 'Atmung',
                      subtitle: 'Atemfrequenz',
                      unit: '/min',
                      icon: LucideIcons.wind,
                      color: (p) => p.sleep,
                      tint: (p) => p.sleepTint,
                      digits: 1,
                    ),
                  ),
                  OBMetricCard(
                    key: const ValueKey('hauttemperatur'),
                    label: 'Hauttemperatur',
                    unit: '',
                    metric: day.skinTemperature,
                    icon: LucideIcons.thermometer,
                    digits: 1,
                    color: p.ink,
                    onTap: () => OpenBandMetricDetail.push(
                      context,
                      backText: widget.bandMetricsOnly ? 'Messwerte' : null,
                      controller: c,
                      metricKey: MetricKey.skinTemperature,
                      label: 'Hauttemperatur',
                      subtitle: '',
                      unit: '',
                      icon: LucideIcons.thermometer,
                      color: (p) => p.ink,
                      tint: (p) => p.well,
                      digits: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (!widget.bandMetricsOnly)
              for (final (key, label, unit, icon, color, tint) in [
                (
                  MetricKey.hrv,
                  'HRV',
                  'ms',
                  LucideIcons.activity,
                  p.ink,
                  p.line,
                ),
                (
                  MetricKey.restingHr,
                  'Ruhepuls',
                  '/min',
                  LucideIcons.heart,
                  p.pulse,
                  p.pulseTint,
                ),
                (
                  MetricKey.recovery,
                  'Erholung',
                  'von 100',
                  LucideIcons.heartPulse,
                  p.ink,
                  p.line,
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FutureBuilder<List<MetricPoint>>(
                    key: ValueKey('${key.name}-$nights-${c.selectedDay}'),
                    future: c.repository.readMetricHistory(
                      key,
                      c.selectedDay,
                      nights,
                    ),
                    builder: (context, snapshot) => OBTrendCard(
                      label: label,
                      unit: unit,
                      icon: icon,
                      color: color,
                      tint: tint,
                      nights: nights,
                      points: snapshot.data,
                      baseline: switch (key) {
                        MetricKey.hrv => day?.hrv.baseline,
                        MetricKey.restingHr => day?.restingHr.baseline,
                        MetricKey.respiration => day?.respiration.baseline,
                        MetricKey.skinTemperature => null,
                        MetricKey.recovery => null,
                        MetricKey.sleepDuration => day?.sleep.duration.baseline,
                        MetricKey.strain => day?.strain.baseline,
                      },
                      error: snapshot.hasError,
                    ),
                  ),
                ),
            if (!widget.bandMetricsOnly) ...[
              OBCard(
                padding: EdgeInsets.zero,
                child: _HealthWeightRow(
                  key: ValueKey('weight-${c.selectedDay}'),
                  repository: c.repository,
                  endDay: c.selectedDay,
                  now: c.now,
                  refreshRequest: c.refreshRequest,
                ),
              ),
              const SizedBox(height: 10),
              OBCard(
                padding: EdgeInsets.zero,
                child: _HealthVo2Row(
                  key: ValueKey('vo2-${c.selectedDay}'),
                  repository: c.repository,
                  endDay: c.selectedDay,
                  now: c.now,
                  refreshRequest: c.refreshRequest,
                ),
              ),
              const SizedBox(height: 10),
              OBCard(
                child: SetRow(
                  LucideIcons.flaskConical,
                  p.muted,
                  'Laborwerte',
                  key: const ValueKey('laborwerte'),
                  onTap: () => OpenBandLabs.push(
                    context,
                    repository: c.repository,
                    now: c.now,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OBCard(
                child: SetRow(
                  LucideIcons.droplet,
                  p.muted,
                  'Glukose',
                  key: const ValueKey('glukose'),
                  onTap: () => OpenBandGlucose.push(
                    context,
                    repository: c.repository,
                    now: c.now,
                    synthetic: c.day?.synthetic == true,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
      return page;
    },
  );
}

class _HealthVo2Row extends StatefulWidget {
  const _HealthVo2Row({
    super.key,
    required this.repository,
    required this.endDay,
    required this.now,
    required this.refreshRequest,
  });

  final OpenBandRepository repository;
  final String endDay;
  final DateTime Function() now;
  final int refreshRequest;

  @override
  State<_HealthVo2Row> createState() => _HealthVo2RowState();
}

class _HealthVo2RowState extends State<_HealthVo2Row> {
  late Future<Vo2List> _entries = _read();

  Future<Vo2List> _read() {
    final repository = widget.repository;
    final future = Future<Vo2List>.sync(repository.readVo2Entries);
    future.ignore();
    return future;
  }

  @override
  void didUpdateWidget(covariant _HealthVo2Row oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.endDay != widget.endDay ||
        oldWidget.refreshRequest != widget.refreshRequest) {
      _entries = _read();
    }
  }

  Vo2Revision? _latest(Vo2List? list) {
    if (list == null) return null;
    final entries = <Vo2Revision>[];
    for (final item in list.entries) {
      final head = item.head;
      if (head != null &&
          !head.deleted &&
          head.measuredOn.compareTo(widget.endDay) <= 0) {
        entries.add(head);
      }
    }
    entries.sort((a, b) {
      final byDay = b.measuredOn.compareTo(a.measuredOn);
      return byDay != 0 ? byDay : a.id.compareTo(b.id);
    });
    return entries.isEmpty ? null : entries.first;
  }

  String _date(String day) {
    final date = DateTime.parse(day);
    return DateFormat(
      date.year == widget.now().year ? 'd. MMM' : 'd. MMM y',
      'de_DE',
    ).format(date);
  }

  Future<void> _open(BuildContext context) async {
    await OpenBandVo2.push(
      context,
      repository: widget.repository,
      endDay: widget.endDay,
      now: widget.now,
    );
    if (!mounted) return;
    setState(() {
      _entries = _read();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return FutureBuilder<Vo2List>(
      future: _entries,
      builder: (context, snapshot) {
        final loaded =
            snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError;
        final list = loaded ? snapshot.data : null;
        final latest = _latest(list);
        final hasUnreadable = (list?.corruptCount ?? 0) > 0;
        final value = latest == null
            ? '—'
            : '${obNumber(latest.valueMlKgMin, digits: 1)} $kVo2Unit';
        final subtitle = snapshot.hasError
            ? 'Laden fehlgeschlagen'
            : latest == null
            ? hasUnreadable
                  ? 'Eintrag nicht lesbar'
                  : 'Eingetragen'
            : hasUnreadable
            ? 'Eingetragen · ${_date(latest.measuredOn)}\nTeilweise lesbar'
            : 'Eingetragen · ${_date(latest.measuredOn)}';
        return OBSettingsValueRow(
          key: const ValueKey('vo2-health-row'),
          label: 'VO₂max',
          value: value,
          subtitle: subtitle,
          labelWeight: FontWeight.w600,
          valueWeight: FontWeight.w700,
          chevron: true,
          mutedValue: latest == null,
          leading: DecoratedBox(
            decoration: BoxDecoration(
              color: p.well,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(LucideIcons.activity, size: 18, color: p.ink),
          ),
          onTap: () => _open(context),
        );
      },
    );
  }
}

class _HealthWeightRow extends StatefulWidget {
  const _HealthWeightRow({
    super.key,
    required this.repository,
    required this.endDay,
    required this.now,
    required this.refreshRequest,
  });

  final OpenBandRepository repository;
  final String endDay;
  final DateTime Function() now;
  final int refreshRequest;

  @override
  State<_HealthWeightRow> createState() => _HealthWeightRowState();
}

class _HealthWeightRowState extends State<_HealthWeightRow> {
  late Future<WeightHistory> _history = _read();

  Future<WeightHistory> _read() {
    final repository = widget.repository;
    final endDay = widget.endDay;
    final future = Future<WeightHistory>.sync(
      () => repository.readWeightHistory(endDay, 7),
    );
    // Observe an error immediately. FutureBuilder receives the same future
    // and retains its error snapshot even if the read finishes before rebuild.
    future.ignore();
    return future;
  }

  @override
  void didUpdateWidget(covariant _HealthWeightRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.endDay != widget.endDay ||
        oldWidget.refreshRequest != widget.refreshRequest) {
      _history = _read();
    }
  }

  String _date(String day) {
    final date = DateTime.parse(day);
    return DateFormat(
      date.year == widget.now().year ? 'd. MMM' : 'd. MMM y',
      'de_DE',
    ).format(date);
  }

  Future<void> _openWeight(BuildContext context) async {
    await OpenBandWeight.push(
      context,
      repository: widget.repository,
      endDay: widget.endDay,
      now: widget.now,
    );
    if (!mounted) return;
    final history = _read();
    setState(() {
      _history = history;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return FutureBuilder<WeightHistory>(
      future: _history,
      builder: (context, snapshot) {
        final loaded =
            snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError;
        final latest = loaded ? snapshot.data?.latest : null;
        final value = latest == null
            ? '—'
            : '${obNumber(latest.value, digits: 1)} kg';
        final subtitle = snapshot.hasError
            ? 'Journal · Laden fehlgeschlagen'
            : latest == null
            ? 'Journal'
            : 'Journal · ${_date(latest.day)}';
        return OBSettingsValueRow(
          label: 'Gewicht',
          value: value,
          subtitle: subtitle,
          labelWeight: FontWeight.w600,
          valueWeight: FontWeight.w700,
          chevron: true,
          mutedValue: latest == null,
          leading: DecoratedBox(
            decoration: BoxDecoration(
              color: p.foodTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(LucideIcons.scale, size: 18, color: p.food),
          ),
          onTap: () => _openWeight(context),
        );
      },
    );
  }
}

class OBSegmented extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool compact;
  final List<bool>? enabled;
  const OBSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.compact = false,
    this.enabled,
  });

  bool _on(int i) => enabled == null || (i < enabled!.length && enabled![i]);

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    if (compact) {
      final scaled = MediaQuery.textScalerOf(context).scale(14) / 14;
      final width = (102.0 * scaled).clamp(102.0, 146.0);
      final inner = (34.0 * scaled).clamp(34.0, 44.0);
      final wellH = inner + 6;
      final rowH = wellH < 44 ? 44.0 : wellH;
      return SizedBox(
        width: width,
        height: rowH,
        child: Stack(
          alignment: Alignment.center,
          children: [
            IgnorePointer(
              child: Container(
                width: width,
                height: wellH,
                padding: const EdgeInsets.all(3),
                decoration: p.insetDecoration(radius: 14),
                child: Row(
                  children: [
                    for (final (i, _) in labels.indexed) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        child: Opacity(
                          opacity: _on(i) ? 1 : 0.38,
                          child: Container(
                            height: inner,
                            decoration: BoxDecoration(
                              color: i == selected ? p.card : null,
                              borderRadius: BorderRadius.circular(11),
                              boxShadow: i == selected ? p.raised : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, label) in labels.indexed) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == selected,
                        enabled: _on(i),
                        child: InkWell(
                          onTap: _on(i) ? () => onChanged(i) : null,
                          borderRadius: BorderRadius.circular(11),
                          child: Align(
                            child: Opacity(
                              opacity: _on(i) ? 1 : 0.38,
                              child: Text(
                                label,
                                style: p
                                    .text(
                                      14,
                                      weight: i == selected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: i == selected ? p.ink : p.muted,
                                    )
                                    .copyWith(height: 18 / 14),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final stacked =
            constraints.maxWidth.isFinite &&
            !_fitsEqualColumns(constraints.maxWidth, scaler, p, context);
        return stacked
            ? _stacked(p, scaler)
            : _horizontal(p, scaler, constraints.maxWidth);
      },
    );
  }

  TextStyle _plainStyle(OB p, bool chosen) => p
      .text(
        14,
        weight: chosen ? FontWeight.w700 : FontWeight.w500,
        color: chosen ? p.ink : p.muted,
      )
      .copyWith(height: 18 / 14);

  // Text fontSize 14 + height 18/14 follows scaler.scale(14) * 18/14.
  // scaler.scale(18) diverges on nonlinear accessibility scalers and clips.
  double _lineHeight(TextScaler scaler) => scaler.scale(14) * 18 / 14;

  bool _fitsEqualColumns(
    double maxWidth,
    TextScaler scaler,
    OB p,
    BuildContext context,
  ) {
    if (labels.isEmpty) return true;
    const wellPad = 3.0;
    const gap = 2.0;
    const side = 4.0;
    final inner = maxWidth - wellPad * 2 - gap * (labels.length - 1);
    if (inner <= 0) return false;
    final col = inner / labels.length;
    final dir = Directionality.of(context);
    final fitStyle = _plainStyle(p, true);
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: fitStyle),
        textDirection: dir,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      if (width + side * 2 > col) return false;
    }
    return true;
  }

  Widget _horizontal(OB p, TextScaler scaler, double maxWidth) {
    final line = _lineHeight(scaler);
    final inner = line > 34 ? line : 34.0;
    final wellH = inner + 6;
    final rowH = wellH < 44 ? 44.0 : wellH;
    return SizedBox(
      width: maxWidth.isFinite ? maxWidth : null,
      height: rowH,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Container(
              width: maxWidth.isFinite ? maxWidth : null,
              height: wellH,
              padding: const EdgeInsets.all(3),
              decoration: p.insetDecoration(radius: 14),
              child: Row(
                children: [
                  for (final (i, _) in labels.indexed) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      child: Opacity(
                        opacity: _on(i) ? 1 : 0.38,
                        child: Container(
                          height: inner,
                          decoration: BoxDecoration(
                            color: i == selected ? p.card : null,
                            borderRadius: BorderRadius.circular(11),
                            boxShadow: i == selected ? p.raised : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, label) in labels.indexed) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == selected,
                      enabled: _on(i),
                      child: InkWell(
                        onTap: _on(i) ? () => onChanged(i) : null,
                        borderRadius: BorderRadius.circular(11),
                        child: Align(
                          child: Opacity(
                            opacity: _on(i) ? 1 : 0.38,
                            child: Text(
                              label,
                              maxLines: 1,
                              softWrap: false,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.visible,
                              style: _plainStyle(p, i == selected),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stacked(OB p, TextScaler scaler) {
    final line = _lineHeight(scaler);
    final rowMin = 16 + line < 44 ? 44.0 : 16 + line;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(3),
      decoration: p.insetDecoration(radius: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          for (final (i, label) in labels.indexed)
            Semantics(
              button: true,
              selected: i == selected,
              enabled: _on(i),
              child: Opacity(
                opacity: _on(i) ? 1 : 0.38,
                child: InkWell(
                  onTap: _on(i) ? () => onChanged(i) : null,
                  borderRadius: BorderRadius.circular(11),
                  child: Container(
                    constraints: BoxConstraints(minHeight: rowMin),
                    padding: const EdgeInsets.all(8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? p.card : null,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: i == selected ? p.raised : null,
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.visible,
                      style: _plainStyle(p, i == selected),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Numeric sourced chart slot. Caption is display copy; [semantics] is the
/// longer accessibility name. No civil-date identity is required.
class OBSourcedSample {
  const OBSourcedSample({this.value, this.caption, this.semantics});

  final double? value;
  final String? caption;
  final String? semantics;
}

class OBTrendCard extends StatelessWidget {
  final String label, unit;
  final IconData icon;
  final Color color, tint;
  final int nights;
  final List<MetricPoint>? points;
  final List<OBSourcedSample> samples;
  final double? baseline;
  final bool error;
  final String Function(double?)? format;
  final bool sourced;
  final String? coverage;
  final String? axisStart;
  final String? axisEnd;
  final int? selectedIndex;
  final ValueChanged<int>? onSelect;
  final Key? plotKey;
  final bool bars;
  const OBTrendCard({
    super.key,
    required this.label,
    required this.unit,
    required this.icon,
    required this.color,
    required this.tint,
    required this.nights,
    required this.points,
    this.baseline,
    this.error = false,
    this.format,
  }) : sourced = false,
       samples = const [],
       coverage = null,
       axisStart = null,
       axisEnd = null,
       selectedIndex = null,
       onSelect = null,
       plotKey = null,
       bars = false;

  const OBTrendCard.sourced({
    super.key,
    required this.label,
    required this.unit,
    required this.icon,
    required this.color,
    required this.tint,
    required List<OBSourcedSample> points,
    this.coverage,
    this.axisStart,
    this.axisEnd,
    this.selectedIndex,
    this.onSelect,
    this.plotKey,
    this.format,
    this.bars = false,
  }) : nights = 0,
       baseline = null,
       error = false,
       sourced = true,
       samples = points,
       points = null;

  @override
  Widget build(BuildContext context) {
    if (sourced) return _buildSourced(context);
    final p = OB.of(context);
    final values =
        points?.where((e) => _trendFinite(e.value)).toList() ?? const [];
    final last = values.isEmpty ? null : values.last.value;
    final observed = values.length;
    final hasPartial = values.any((e) => e.partial);
    final countCaption = '$observed von $nights Nächten';
    final status = error
        ? ('Verlauf konnte nicht geladen werden', p.danger)
        : points == null
        ? ('', p.muted)
        : observed == 0
        ? ('Noch keine Werte', p.muted)
        : hasPartial
        ? ('$countCaption · teilweise', p.muted)
        : observed < nights
        ? (countCaption, p.muted)
        : (
            format != null && baseline != null && last != null
                ? _durationStatus(last, baseline!)
                : obMetricStatus(last, baseline, unit: unit),
            p.smallText(color),
          );
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: p.text(13, weight: FontWeight.w600, color: p.muted),
                ),
              ),
              Text(
                '$nights Nächte',
                style: p.text(13, weight: FontWeight.w500, color: p.muted),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                format?.call(last) ?? obNumber(last),
                style: p.text(28, weight: FontWeight.w800, display: true),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: p.text(14, weight: FontWeight.w500, color: p.muted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  status.$1,
                  style: p.text(13, weight: FontWeight.w600, color: status.$2),
                ),
              ),
            ],
          ),
          Semantics(
            label:
                '$label, $nights Nächte, ${observed == 0 ? 'keine Werte' : '$observed Werte, zuletzt ${obNumber(last)} $unit${hasPartial ? ', teilweise' : ''}'}',
            child: ExcludeSemantics(
              child: SizedBox(
                height: 88,
                width: double.infinity,
                child: points == null
                    ? null
                    : CustomPaint(
                        painter: _TrendPainter(
                          points!,
                          baseline,
                          color,
                          tint,
                          p.gap,
                          p.card,
                        ),
                      ),
              ),
            ),
          ),
          if (points case final pts? when pts.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final d in [pts.first.day, pts.last.day])
                  Text(
                    DateFormat('d. MMM', 'de_DE').format(DateTime.parse(d)),
                    style: p.text(12, weight: FontWeight.w500, color: p.muted),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSourced(BuildContext context) {
    final p = OB.of(context);
    final pts = samples;
    final scaler = MediaQuery.textScalerOf(context);
    final stacked = scaler.scale(15) > 20;
    final geom = bars
        ? _SourcedPlotGeom.bars(scaler)
        : _SourcedPlotGeom.of(scaler);
    final idx = selectedIndex;
    final shown = idx != null && idx >= 0 && idx < pts.length ? pts[idx] : null;
    final raw = shown?.value;
    final value = _trendFinite(raw) ? raw : null;
    final valueText = format?.call(value) ?? obNumber(value);
    final dateText = shown?.caption;
    final bounds = bars
        ? _sourcedBarBounds([for (final pt in pts) pt.value])
        : _sourcedTrendBounds([for (final pt in pts) pt.value]);
    final hasPlot = bounds != null;
    final titleStyle = p.text(15, weight: FontWeight.w600);
    final coverageStyle = p
        .text(13, weight: FontWeight.w500, color: p.muted)
        .copyWith(height: 18 / 13);
    final title = Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: titleStyle)),
      ],
    );
    final coverageLabel = coverage?.trim();
    final hasCoverage = coverageLabel != null && coverageLabel.isNotEmpty;
    final coverageText = Text(coverageLabel ?? '', style: coverageStyle);
    final header = !hasCoverage
        ? title
        : stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 4), coverageText],
          )
        : Row(
            children: [
              Expanded(child: title),
              coverageText,
            ],
          );
    final slot = idx ?? 0;
    final canDecrease = hasPlot && pts.length > 1 && slot > 0;
    final canIncrease = hasPlot && pts.length > 1 && slot < pts.length - 1;
    String slotPhrase(int i) {
      if (i < 0 || i >= pts.length) return 'kein Wert';
      final pt = pts[i];
      final day = pt.semantics ?? pt.caption ?? '';
      if (!_trendFinite(pt.value)) {
        return day.isEmpty ? 'kein Wert' : '$day, kein Wert';
      }
      final number = format?.call(pt.value) ?? obNumber(pt.value);
      return day.isEmpty ? '$number $unit' : '$day, $number $unit';
    }

    final dateStyle = p
        .text(13, weight: FontWeight.w500, color: p.muted)
        .copyWith(height: 18 / 13);
    final valueStyle = p
        .text(28, weight: FontWeight.w800, display: true)
        .copyWith(height: 34 / 28);
    final unitStyle = p.text(14, weight: FontWeight.w500, color: p.muted);
    final valueAndUnit = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(valueText, style: valueStyle),
        const SizedBox(width: 8),
        Text(unit, style: unitStyle),
      ],
    );
    final Widget valueBlock;
    if (stacked) {
      valueBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          valueAndUnit,
          if (dateText != null && dateText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(dateText, style: dateStyle),
          ],
        ],
      );
    } else {
      valueBlock = Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(valueText, style: valueStyle),
          const SizedBox(width: 8),
          Text(unit, style: unitStyle),
          if (dateText != null && dateText.isNotEmpty) ...[
            const SizedBox(width: 12),
            Flexible(child: Text(dateText, style: dateStyle)),
          ],
        ],
      );
    }

    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          header,
          valueBlock,
          if (hasPlot)
            Semantics(
              key: plotKey,
              label: hasCoverage
                  ? '$label, $coverageLabel, ${slotPhrase(slot)}'
                  : '$label, ${slotPhrase(slot)}',
              value: slotPhrase(slot),
              increasedValue: canIncrease ? slotPhrase(slot + 1) : null,
              decreasedValue: canDecrease ? slotPhrase(slot - 1) : null,
              onIncrease: canIncrease && onSelect != null
                  ? () => onSelect!(slot + 1)
                  : null,
              onDecrease: canDecrease && onSelect != null
                  ? () => onSelect!(slot - 1)
                  : null,
              child: ExcludeSemantics(
                child: SizedBox(
                  height: geom.height,
                  width: double.infinity,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      void pick(Offset local) {
                        if (onSelect == null || pts.isEmpty) return;
                        onSelect!(
                          bars
                              ? _sourcedBarHitIndex(
                                  local.dx,
                                  width,
                                  pts.length,
                                  geom,
                                )
                              : _sourcedHitIndex(
                                  local.dx,
                                  width,
                                  pts.length,
                                  geom,
                                ),
                        );
                      }

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => pick(d.localPosition),
                        onHorizontalDragUpdate: (d) => pick(d.localPosition),
                        child: CustomPaint(
                          painter: _TrendPainter.sourced(
                            [for (final pt in pts) pt.value],
                            color,
                            bounds.$1,
                            bounds.$2,
                            selectedIndex,
                            geom,
                            p.text(12, color: p.muted),
                            scaler,
                            Directionality.of(context),
                            bars: bars,
                            restColor: p.muted,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          if (hasPlot &&
              bars &&
              pts.length == 1 &&
              (axisEnd ?? axisStart) != null)
            Padding(
              padding: EdgeInsets.only(left: geom.left, right: geom.right),
              child: Center(
                child: Text(
                  axisEnd ?? axisStart!,
                  style: p.text(12, weight: FontWeight.w500, color: p.muted),
                ),
              ),
            )
          else if (hasPlot && axisStart != null && axisEnd != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (bars)
                  Flexible(
                    child: Text(
                      axisStart!,
                      style: p.text(
                        12,
                        weight: FontWeight.w500,
                        color: p.muted,
                      ),
                    ),
                  )
                else
                  Text(
                    axisStart!,
                    style: p.text(12, weight: FontWeight.w500, color: p.muted),
                  ),
                if (bars)
                  Flexible(
                    child: Text(
                      axisEnd!,
                      textAlign: TextAlign.end,
                      style: p.text(
                        12,
                        weight: FontWeight.w500,
                        color: p.muted,
                      ),
                    ),
                  )
                else
                  Text(
                    axisEnd!,
                    style: p.text(12, weight: FontWeight.w500, color: p.muted),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

String _durationStatus(double value, double baseline) {
  final d = (value - baseline).round();
  if (d == 0) return 'wie Basis';
  return '${d > 0 ? '+' : '−'}${obGapMinutes(d.abs())} '
      '${d > 0 ? 'über' : 'unter'} Basis';
}

String obMetricStatus(double? value, double? baseline, {String unit = ''}) {
  if (baseline == null) return 'Basis noch offen';
  if (value == null) return '—';
  final d = value - baseline;
  if (d.abs() < .5) return 'wie Basis';
  return '${d > 0 ? '+' : '−'}${obNumber(d.abs())} ${d > 0 ? 'über' : 'unter'} Basis';
}

bool _trendFinite(double? value) => value != null && value.isFinite;

(double, double)? _sourcedTrendBounds(Iterable<double?> values) {
  double? lo;
  double? hi;
  for (final value in values) {
    if (!_trendFinite(value)) continue;
    lo = lo == null || value! < lo ? value : lo;
    hi = hi == null || value! > hi ? value : hi;
  }
  if (lo == null || hi == null) return null;
  lo -= 2;
  hi += 2;
  lo = (lo / 2).floorToDouble() * 2;
  hi = (hi / 2).ceilToDouble() * 2;
  if (lo >= hi) {
    lo -= 2;
    hi += 2;
  }
  return (lo, hi);
}

(double, double)? _sourcedBarBounds(Iterable<double?> values) {
  double? hi;
  for (final value in values) {
    if (!_trendFinite(value) || value! <= 0) continue;
    hi = hi == null || value > hi ? value : hi;
  }
  if (hi == null) return null;
  var upper = (hi / 10).ceil() * 10.0;
  if (upper <= 0) upper = 10;
  return (0, upper);
}

class _SourcedPlotGeom {
  const _SourcedPlotGeom({
    required this.height,
    required this.left,
    required this.right,
    required this.yTop,
    required this.yBottom,
    required this.topBaseline,
    required this.bottomBaseline,
  });

  final double height;
  final double left;
  final double right;
  final double yTop;
  final double yBottom;
  final double topBaseline;
  final double bottomBaseline;

  factory _SourcedPlotGeom.of(TextScaler scaler) {
    final t = scaler.scale(12) / 12;
    return _SourcedPlotGeom(
      height: 88 + 16 * (t - 1),
      left: 26 + 18 * (t - 1),
      right: 4,
      yTop: 10 + 18 * (t - 1),
      yBottom: 78 + 12 * (t - 1),
      topBaseline: 15 + 10 * (t - 1),
      bottomBaseline: 81 + 15 * (t - 1),
    );
  }

  factory _SourcedPlotGeom.bars(TextScaler scaler) {
    final t = scaler.scale(12) / 12;
    return _SourcedPlotGeom(
      height: 132 + 16 * (t - 1),
      left: 28 + 16 * (t - 1),
      right: 4 + 4 * (t - 1),
      yTop: 12 + 18 * (t - 1),
      yBottom: 124 + 12 * (t - 1),
      topBaseline: 16 + 10 * (t - 1),
      bottomBaseline: 127 + 15 * (t - 1),
    );
  }
}

int _sourcedHitIndex(double x, double width, int n, _SourcedPlotGeom geom) {
  if (n <= 1) return 0;
  final plotW = width - geom.left - geom.right;
  if (plotW <= 0) return 0;
  final t = ((x - geom.left) / plotW).clamp(0.0, 1.0);
  return (t * (n - 1)).round();
}

int _sourcedBarHitIndex(double x, double width, int n, _SourcedPlotGeom geom) {
  if (n <= 1) return 0;
  final plotW = width - geom.left - geom.right;
  if (plotW <= 0) return 0;
  final t = ((x - geom.left) / plotW).clamp(0.0, 1.0);
  return (t * n).floor().clamp(0, n - 1);
}

class _TrendPainter extends CustomPainter {
  final List<MetricPoint> points;
  final List<double?> values;
  final double? baseline;
  final Color color, tint, gap, ring;
  final bool sourced;
  final double? lo;
  final double? hi;
  final int? selectedIndex;
  final _SourcedPlotGeom? geom;
  final TextStyle? axisStyle;
  final TextScaler? textScaler;
  final TextDirection? textDirection;
  final bool bars;
  final Color? restColor;

  _TrendPainter(
    this.points,
    this.baseline,
    this.color,
    this.tint,
    this.gap,
    this.ring,
  ) : sourced = false,
      values = const [],
      lo = null,
      hi = null,
      selectedIndex = null,
      geom = null,
      axisStyle = null,
      textScaler = null,
      textDirection = null,
      bars = false,
      restColor = null;

  _TrendPainter.sourced(
    this.values,
    this.color,
    double this.lo,
    double this.hi,
    this.selectedIndex,
    _SourcedPlotGeom this.geom,
    TextStyle this.axisStyle,
    TextScaler this.textScaler,
    TextDirection this.textDirection, {
    this.bars = false,
    this.restColor,
  }) : points = const [],
       baseline = null,
       tint = color,
       gap = color,
       ring = color,
       sourced = true;

  bool _usable(MetricPoint point) => _trendFinite(point.value);

  @override
  void paint(Canvas canvas, Size size) {
    if (sourced) {
      if (bars) {
        _paintBars(canvas, size);
      } else {
        _paintSourced(canvas, size);
      }
      return;
    }
    final values = [
      for (final p in points)
        if (_usable(p)) p.value!,
    ];
    if (values.isEmpty) return;
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (baseline case final b?) {
      lo = lo < b ? lo : b;
      hi = hi > b ? hi : b;
    }
    final pad = (hi - lo) * .2 + 1;
    lo -= pad;
    hi += pad;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    final step = points.length > 1 ? size.width / (points.length - 1) : 0.0;
    double x(int i) => points.length > 1 ? i * step : size.width / 2;

    if (baseline case final b?) {
      canvas.drawLine(
        Offset(0, y(b)),
        Offset(size.width, y(b)),
        Paint()
          ..color = gap
          ..strokeWidth = 1,
      );
    }
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final first = points.indexWhere(_usable);
    final last = points.lastIndexWhere(_usable);
    Path? path;
    int? lastIndex;
    for (var i = 0; i < points.length; i++) {
      final v = points[i].value;
      if (!_trendFinite(v)) {
        if (i > first && i < last) {
          final dash = Paint()
            ..color = gap
            ..strokeWidth = 1.5;
          for (var yy = 4.0; yy < size.height; yy += 8) {
            canvas.drawLine(Offset(x(i), yy), Offset(x(i), yy + 4), dash);
          }
        }
        path = null;
        continue;
      }
      if (path == null) {
        path = Path()..moveTo(x(i), y(v!));
        final isolatedFirst =
            lastIndex == null &&
            (i == points.length - 1 || !_usable(points[i + 1]));
        if (lastIndex != null || isolatedFirst) {
          canvas.drawCircle(Offset(x(i), y(v)), 2.5, Paint()..color = color);
        }
      } else {
        path.lineTo(x(i), y(v!));
      }
      canvas.drawPath(path, line);
      path = Path()..moveTo(x(i), y(v));
      lastIndex = i;
    }
    if (lastIndex case final i?) {
      final end = Offset(x(i), y(points[i].value!));
      canvas.drawCircle(end, 6, Paint()..color = ring);
      canvas.drawCircle(end, 4, Paint()..color = color);
    }
  }

  void _paintSourced(Canvas canvas, Size size) {
    final g = geom!;
    final low = lo!;
    final high = hi!;
    final span = high - low;
    if (span <= 0 || !span.isFinite) return;
    final plotW = size.width - g.left - g.right;
    if (plotW <= 0) return;
    double x(int i) => values.length > 1
        ? g.left + i * plotW / (values.length - 1)
        : g.left + plotW / 2;
    double y(double v) => g.yBottom - (v - low) / span * (g.yBottom - g.yTop);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Path? path;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (!_trendFinite(v)) {
        path = null;
        continue;
      }
      final at = Offset(x(i), y(v!));
      if (path == null) {
        path = Path()..moveTo(at.dx, at.dy);
      } else {
        path.lineTo(at.dx, at.dy);
        canvas.drawPath(path, line);
        path = Path()..moveTo(at.dx, at.dy);
      }
    }
    final mark = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (!_trendFinite(v)) continue;
      final selected = i == selectedIndex;
      canvas.drawCircle(Offset(x(i), y(v!)), selected ? 4 : 2, mark);
    }
    final style = axisStyle;
    if (style == null) return;
    void label(String text, double baseline) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: textDirection ?? TextDirection.ltr,
        textScaler: textScaler ?? TextScaler.noScaling,
      )..layout();
      final alphabetic = painter.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      painter.paint(canvas, Offset(0, baseline - alphabetic));
      painter.dispose();
    }

    label(obNumber(high), g.topBaseline);
    label(obNumber(low), g.bottomBaseline);
  }

  void _paintBars(Canvas canvas, Size size) {
    final g = geom!;
    final high = hi!;
    if (high <= 0 || !high.isFinite) return;
    final plotW = size.width - g.left - g.right;
    if (plotW <= 0) return;
    final n = values.length;
    if (n <= 0) return;
    final step = plotW / n;
    final barW = math.min(18.0, step * 0.72);
    final rest = restColor ?? color;
    final span = g.yBottom - g.yTop;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (!_trendFinite(v) || v! <= 0) continue;
      final h = v / high * span;
      if (h <= 0) continue;
      final x = n == 1 ? g.left + (plotW - barW) / 2 : g.left + i * step;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, g.yBottom - h, barW, h),
          const Radius.circular(3),
        ),
        Paint()..color = i == selectedIndex ? color : rest,
      );
    }
    final style = axisStyle;
    if (style == null) return;
    void label(String text, double baseline) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: textDirection ?? TextDirection.ltr,
        textScaler: textScaler ?? TextScaler.noScaling,
      )..layout();
      final alphabetic = painter.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      painter.paint(canvas, Offset(0, baseline - alphabetic));
      painter.dispose();
    }

    label(obNumber(high), g.topBaseline);
    label(obNumber(0), g.bottomBaseline);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.points != points ||
      old.values != values ||
      old.baseline != baseline ||
      old.color != color ||
      old.tint != tint ||
      old.gap != gap ||
      old.ring != ring ||
      old.sourced != sourced ||
      old.lo != lo ||
      old.hi != hi ||
      old.selectedIndex != selectedIndex ||
      old.geom != geom ||
      old.axisStyle != axisStyle ||
      old.textScaler != textScaler ||
      old.textDirection != textDirection ||
      old.bars != bars ||
      old.restColor != restColor;
}

/// One Messwerte row (Paper G2): which metric, its window on the scale and
/// the detail it opens.
typedef _Messwert = ({
  MetricKey key,
  String label,
  String unit,
  DayMetric metric,
  int digits,
  double lo,
  double hi,
  double step,
  void Function(BuildContext, OpenBandController) open,
});

List<_Messwert> _messwerte(OB p, OpenBandDay day) {
  void Function(BuildContext, OpenBandController) detail(
    MetricKey key,
    String label,
    String subtitle,
    String unit,
    IconData icon, {
    int digits = 0,
  }) =>
      (context, c) => OpenBandMetricDetail.push(
        context,
        backText: 'Messwerte',
        controller: c,
        metricKey: key,
        label: label,
        subtitle: subtitle,
        unit: unit,
        icon: icon,
        color: (p) => p.ink,
        tint: (p) => p.line,
        digits: digits,
      );
  return [
    (
      key: MetricKey.hrv,
      label: 'HRV',
      unit: 'ms',
      metric: day.hrv,
      digits: 0,
      lo: 20,
      hi: 70,
      step: 10,
      open: detail(
        MetricKey.hrv,
        'HRV',
        'Herzratenvariabilität',
        'ms',
        LucideIcons.activity,
      ),
    ),
    (
      key: MetricKey.restingHr,
      label: 'Ruhepuls',
      unit: '/min',
      metric: day.restingHr,
      digits: 0,
      lo: 40,
      hi: 70,
      step: 10,
      open: detail(
        MetricKey.restingHr,
        'Ruhepuls',
        'in der Nacht',
        '/min',
        LucideIcons.heart,
      ),
    ),
    (
      key: MetricKey.respiration,
      label: 'Atemfrequenz',
      unit: '/min',
      metric: day.respiration,
      digits: 1,
      lo: 10,
      hi: 22,
      step: 2,
      open: detail(
        MetricKey.respiration,
        'Atmung',
        'Atemfrequenz',
        '/min',
        LucideIcons.wind,
        digits: 1,
      ),
    ),
    (
      key: MetricKey.skinTemperature,
      label: 'Hauttemperatur',
      unit: 'SD',
      metric: day.skinTemperature,
      digits: 1,
      lo: -3,
      hi: 3,
      step: 1,
      open: detail(
        MetricKey.skinTemperature,
        'Hauttemperatur',
        '',
        '',
        LucideIcons.thermometer,
        digits: 1,
      ),
    ),
  ];
}

class _MesswertLegend extends StatelessWidget {
  const _MesswertLegend();
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final style = p.text(12, color: p.muted).copyWith(height: 16 / 12);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Container(
                width: 18,
                height: 8,
                decoration: BoxDecoration(
                  color: p.gap,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Text('deine Basis (30 Nächte)', style: style),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: p.ink,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('letzte Nacht', style: style),
            ],
          ),
        ],
      ),
    );
  }
}

/// A night value on its scale (Paper G2 Messwerte): value and comparison
/// on top, the needle over the normal range below. Colour only for a
/// verdict against a trusted range; a missing value is an inset card with
/// the reason and no scale.
class _MesswertCard extends StatelessWidget {
  final _Messwert spec;
  final VoidCallback onTap;
  const _MesswertCard({super.key, required this.spec, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final m = spec.metric;
    final skin = spec.key == MetricKey.skinTemperature;
    final sd = !skin || m.unit == NightScalarUnit.sd;
    final value = sd ? m.value : null;
    final verdict = skin ? null : dayMetricVerdict(spec.key, m);
    final spread = m.baselineSpread;
    // Skin temperature is already a z against its baseline: the analytics'
    // normal range is ±1 SD.
    final band = skin
        ? (-1.0, 1.0)
        : m.baseline == null || spread == null
        ? null
        : (m.baseline! - 1.253 * spread, m.baseline! + 1.253 * spread);
    String n(double v) => obNumber(v, digits: spec.digits);
    // Scale ends in whole units read as "10", not "10,0".
    String end(double v) =>
        obNumber(v, digits: v == v.roundToDouble() ? 0 : spec.digits);
    String comparison() {
      if (value == null) {
        return obCompactMetricStatus(m, digits: spec.digits) ??
            'Kein Nachtwert';
      }
      if (skin) return 'relativ zu deiner Basis';
      if (verdict == null) {
        return obCompactMetricStatus(m, digits: spec.digits) ??
            'Basis noch offen';
      }
      final d = value - m.baseline!;
      final shown = n(d.abs());
      if (verdict == MetricVerdict.normal) {
        return n(d.abs()) == n(0)
            ? 'wie üblich'
            : '${d > 0 ? '+' : '−'}$shown · im Bereich';
      }
      return '${d > 0 ? '+' : '−'}$shown ${d > 0 ? 'über' : 'unter'} Basis';
    }

    final strong =
        verdict == MetricVerdict.better || verdict == MetricVerdict.worse;
    // The window grows to hold the value and the range, in whole steps.
    double lo = spec.lo, hi = spec.hi;
    for (final v in [?value, ?band?.$1, ?band?.$2]) {
      while (v < lo) {
        lo -= spec.step;
      }
      while (v > hi) {
        hi += spec.step;
      }
    }
    final unitSuffix = spec.unit == 'ms' ? ' ms' : '';
    final label = p.label().copyWith(height: 12 / 10);
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text('${spec.label.toUpperCase()} ›', style: label),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                spacing: 4,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value == null
                            ? '—'
                            : skin
                            ? obTemperatureNumber(value, m.unit)
                            : n(value),
                        style: p
                            .text(
                              32,
                              weight: FontWeight.w700,
                              color: value == null ? p.gap : p.ink,
                            )
                            .copyWith(
                              height: 34 / 32,
                              letterSpacing: -.02 * 32,
                            ),
                      ),
                    ),
                  ),
                  if (value != null)
                    Text(
                      spec.unit,
                      style: p
                          .text(13, color: p.muted)
                          .copyWith(height: 16 / 13),
                    ),
                ],
              ),
            ],
          ),
        ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Text(
              comparison(),
              textAlign: TextAlign.right,
              maxLines: 2,
              style: p
                  .text(
                    13,
                    weight: strong ? FontWeight.w700 : FontWeight.w400,
                    color: obVerdictText(p, verdict) ?? p.muted,
                  )
                  .copyWith(height: 16 / 13),
            ),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      label:
          '${spec.label}, ${value == null ? 'kein Wert' : n(value)} ${spec.unit}, ${comparison()}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: value == null
            ? Container(
                padding: const EdgeInsets.all(16),
                decoration: p.insetDecoration(radius: AlpRadius.card),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    header,
                    Text(
                      m.reason ??
                          'Für diese Nacht liegt kein Wert vor. Es wird '
                              'keiner geschätzt.',
                      style: p
                          .text(12, color: p.muted)
                          .copyWith(height: 17 / 12),
                    ),
                  ],
                ),
              )
            : OBCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    header,
                    OBScale(
                      min: lo,
                      max: hi,
                      value: value,
                      baseLow: band?.$1,
                      baseHigh: band?.$2,
                      captionGap: 8,
                      mark: obVerdictMark(p, verdict),
                      labels: (
                        '${end(lo)}$unitSuffix',
                        band == null
                            ? null
                            : skin
                            ? 'Bereich ±1 SD'
                            : 'Basis ${n(band.$1)}–${n(band.$2)}',
                        '${end(hi)}$unitSuffix',
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
