import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../data/day_label.dart';
import 'controller.dart';
import 'domain.dart';
import 'health.dart';
import 'night_scalar_detail.dart';
import 'screens.dart';
import 'theme.dart';

bool _isNightScalar(MetricKey key) => switch (key) {
  MetricKey.hrv ||
  MetricKey.restingHr ||
  MetricKey.respiration ||
  MetricKey.skinTemperature => true,
  MetricKey.recovery || MetricKey.sleepDuration || MetricKey.strain => false,
};

/// Full-screen metric detail (Paper "Messwert-Detail"): hero, night-for-night
/// bars and the rows leading into sleep and the baseline explanation.
class OpenBandMetricDetail extends StatefulWidget {
  final OpenBandController controller;
  final MetricKey metricKey;
  final String label, subtitle, unit;
  final IconData icon;
  final Color Function(OB) color, tint;
  final int digits;
  const OpenBandMetricDetail({
    super.key,
    required this.controller,
    required this.metricKey,
    required this.label,
    required this.subtitle,
    required this.unit,
    required this.icon,
    required this.color,
    required this.tint,
    this.digits = 0,
  });

  static void push(
    BuildContext context, {
    required OpenBandController controller,
    required MetricKey metricKey,
    required String label,
    required String subtitle,
    required String unit,
    required IconData icon,
    required Color Function(OB) color,
    required Color Function(OB) tint,
    int digits = 0,
  }) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => OpenBandMetricDetail(
        controller: controller,
        metricKey: metricKey,
        label: label,
        subtitle: subtitle,
        unit: unit,
        icon: icon,
        color: color,
        tint: tint,
        digits: digits,
      ),
    ),
  );

  @override
  State<OpenBandMetricDetail> createState() => _OpenBandMetricDetailState();
}

class _OpenBandMetricDetailState extends State<OpenBandMetricDetail> {
  static const _nightOptions = [7, 30, 90];
  int _nights = 30;
  int _generation = 0;
  List<MetricPoint>? _points;
  bool _error = false;
  late String _heardDay;

  bool get _nightScalar => _isNightScalar(widget.metricKey);

  @override
  void initState() {
    super.initState();
    _heardDay = widget.controller.selectedDay;
    widget.controller.addListener(_onController);
    if (!_nightScalar) _load();
  }

  @override
  void didUpdateWidget(OpenBandMetricDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = !identical(
      oldWidget.controller,
      widget.controller,
    );
    if (controllerChanged) {
      oldWidget.controller.removeListener(_onController);
      _heardDay = widget.controller.selectedDay;
      widget.controller.addListener(_onController);
    }
    final wasNight = _isNightScalar(oldWidget.metricKey);
    if (wasNight && !_nightScalar) {
      _nights = 30;
      _points = null;
      _error = false;
      _load();
      return;
    }
    if (!_nightScalar &&
        (oldWidget.metricKey != widget.metricKey || controllerChanged)) {
      _load();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _generation++;
    super.dispose();
  }

  void _onController() {
    final day = widget.controller.selectedDay;
    if (day == _heardDay) return;
    _heardDay = day;
    if (!_nightScalar) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final controller = widget.controller;
    final repository = controller.repository;
    final key = widget.metricKey;
    final day = controller.selectedDay;
    final nights = _nights;
    if (mounted) {
      setState(() {
        _points = null;
        _error = false;
      });
    }
    bool current() =>
        mounted &&
        generation == _generation &&
        identical(controller, widget.controller) &&
        identical(repository, widget.controller.repository) &&
        key == widget.metricKey &&
        day == widget.controller.selectedDay &&
        nights == _nights;
    try {
      final points = await repository.readMetricHistory(key, day, nights);
      if (!current()) return;
      setState(() {
        _points = points;
        _error = false;
      });
    } catch (_) {
      if (!current()) return;
      setState(() => _error = true);
    }
  }

  // Strain is scored per waking day, everything else per night; the copy and
  // the onward links follow that, and strain carries no baseline at all.
  bool get _nightly => widget.metricKey != MetricKey.strain;
  String get _period => _nightly ? 'Nächte' : 'Tage';

  DayMetric _metric(OpenBandDay day) => switch (widget.metricKey) {
    MetricKey.hrv => day.hrv,
    MetricKey.restingHr => day.restingHr,
    MetricKey.respiration => day.respiration,
    MetricKey.skinTemperature => day.skinTemperature,
    MetricKey.recovery => day.recovery,
    MetricKey.sleepDuration => day.sleep.duration,
    MetricKey.strain => day.strain,
  };

  void _basis(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (c) {
      final p = OB.of(c);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'So entsteht die Basis',
                style: p.text(18, weight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                'Die Basis ist ein exponentiell gewichteter Mittelwert deiner '
                'letzten 30 Nächte mit Messung: neuere Nächte zählen stärker, '
                'Ausreißer werden gedämpft. Fehlende Nächte zählen nicht.',
              ),
              const SizedBox(height: 12),
              OBAction('Schließen', onPressed: () => Navigator.pop(c)),
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    if (_nightScalar) {
      return OpenBandNightScalarDetail(
        controller: widget.controller,
        metricKey: widget.metricKey,
        label: widget.label,
        unit: widget.unit,
        icon: widget.icon,
        color: widget.color,
        tint: widget.tint,
        digits: widget.digits,
      );
    }
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final p = OB.of(context);
        final color = widget.color(p);
        final tint = widget.tint(p);
        final day = widget.controller.day;
        final metric = day == null ? const DayMetric.missing() : _metric(day);
        return Scaffold(
          backgroundColor: p.canvas,
          appBar: AppBar(
            backgroundColor: p.canvas,
            centerTitle: true,
            title: Column(
              children: [
                Text(widget.label, style: p.text(17, weight: FontWeight.w700)),
                Text(widget.subtitle, style: p.text(12, color: p.muted)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Info',
                onPressed: () {},
                icon: Icon(LucideIcons.info, size: 18, color: p.muted),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              OBCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    Row(
                      children: [
                        Icon(widget.icon, size: 16, color: color),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            widget.controller.selectedDay == todayLabel()
                                ? (_nightly ? 'Nacht auf heute' : 'Heute')
                                : obDayTitle(widget.controller.selectedDay),
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
                          obNumber(metric.value, digits: widget.digits),
                          style: p.text(
                            44,
                            weight: FontWeight.w800,
                            display: true,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.unit,
                          style: p.text(
                            14,
                            weight: FontWeight.w500,
                            color: p.muted,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      metric.value == null || metric.baseline == null
                          ? obMetricStatus(metric.value, metric.baseline)
                          : obMetricComparisonStatus(
                              metric.value!,
                              metric.baseline!,
                              digits: widget.digits,
                            ),
                      style: p.text(
                        13,
                        weight: FontWeight.w600,
                        color: metric.baseline != null && metric.value != null
                            ? p.smallText(color)
                            : p.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OBSegmented(
                labels: [for (final n in _nightOptions) '$n $_period'],
                selected: _nightOptions.indexOf(_nights),
                onChanged: (i) => setState(() {
                  _nights = _nightOptions[i];
                  _load();
                }),
              ),
              const SizedBox(height: 12),
              OBCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _nightly ? 'Nacht für Nacht' : 'Tag für Tag',
                            style: p.text(
                              13,
                              weight: FontWeight.w600,
                              color: p.muted,
                            ),
                          ),
                        ),
                        Text(
                          '${_points?.where((e) => e.value != null).length ?? 0} von $_nights ${_nightly ? 'Nächten' : 'Tagen'}',
                          style: p.text(
                            13,
                            weight: FontWeight.w500,
                            color: p.muted,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 100,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _NightBarsPainter(
                          _points,
                          metric.baseline,
                          color,
                          tint,
                          p.gap,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        if (_points?.isNotEmpty == true)
                          Text(
                            DateFormat(
                              'd. MMM',
                              'de_DE',
                            ).format(DateTime.parse(_points!.first.day)),
                            style: p.text(
                              12,
                              weight: FontWeight.w500,
                              color: p.muted,
                            ),
                          ),
                        const Spacer(),
                        if (metric.baseline != null)
                          Text(
                            'Basis ${obNumber(metric.baseline)}',
                            style: p.text(
                              12,
                              weight: FontWeight.w600,
                              color: p.smallText(color),
                            ),
                          ),
                        const Spacer(),
                        if (_points?.isNotEmpty == true)
                          Text(
                            DateFormat(
                              'd. MMM',
                              'de_DE',
                            ).format(DateTime.parse(_points!.last.day)),
                            style: p.text(
                              12,
                              weight: FontWeight.w500,
                              color: p.muted,
                            ),
                          ),
                      ],
                    ),
                    if (_error)
                      Text(
                        'Verlauf konnte nicht geladen werden.',
                        style: p.text(13, color: p.danger),
                      ),
                  ],
                ),
              ),
              if (_nightly) const SizedBox(height: 12),
              if (_nightly)
                OBCard(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                  child: Column(
                    children: [
                      _row(
                        p,
                        LucideIcons.moon,
                        p.sleep,
                        p.sleepTint,
                        'Verlauf in der Nacht',
                        day?.sleep.onset != null && day?.sleep.wake != null
                            ? '${obTime(day!.sleep.onset)} – ${obTime(day.sleep.wake)}'
                            : '—',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                OpenBandSleep(controller: widget.controller),
                          ),
                        ),
                      ),
                      Container(height: 1, color: p.line),
                      _row(
                        p,
                        LucideIcons.info,
                        p.ink,
                        p.well,
                        'So entsteht die Basis',
                        '30 Nächte',
                        () => _basis(context),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(
    OB p,
    IconData icon,
    Color fg,
    Color bg,
    String label,
    String trailing,
    VoidCallback onTap,
  ) => InkWell(
    onTap: onTap,
    child: SizedBox(
      height: 52,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: p.text(15, weight: FontWeight.w500)),
          ),
          Text(trailing, style: p.text(13, color: p.muted)),
          const SizedBox(width: 4),
          Icon(LucideIcons.chevronRight, size: 14, color: p.gap),
        ],
      ),
    ),
  );
}

/// Night-for-night bars: one 8-px bar per night, a tinted 4-px line at the
/// baseline, a dashed gap marker for nights without a measurement. The scale
/// comes from observed values (10 % padding) and always includes the baseline.
class _NightBarsPainter extends CustomPainter {
  final List<MetricPoint>? points;
  final double? baseline;
  final Color color, tint, gap;
  _NightBarsPainter(
    this.points,
    this.baseline,
    this.color,
    this.tint,
    this.gap,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final points = this.points ?? const <MetricPoint>[];
    if (points.isEmpty) return;
    final values = [
      for (final pt in points)
        if (pt.value != null) pt.value!,
      ?baseline,
    ];
    if (values.isEmpty) return;
    var lo = values.reduce(math.min), hi = values.reduce(math.max);
    final pad = math.max((hi - lo) * .1, 1e-9);
    lo -= pad;
    hi += pad;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    if (baseline != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, y(baseline!) - 2, size.width, 4),
        Paint()..color = tint,
      );
    }
    final slot = size.width / points.length;
    final first = points.indexWhere((p) => p.value != null);
    final last = points.lastIndexWhere((p) => p.value != null);
    for (final (i, pt) in points.indexed) {
      final cx = i * slot + slot / 2;
      if (pt.value == null) {
        // A gap marker means "missing between observed nights"; before the
        // first or after the last observation there is simply nothing yet.
        if (i < first || i > last) continue;
        final paint = Paint()
          ..color = gap
          ..strokeWidth = 2;
        for (var yy = 0.0; yy < size.height; yy += 8) {
          canvas.drawLine(
            Offset(cx, yy),
            Offset(cx, math.min(yy + 4, size.height)),
            paint,
          );
        }
        continue;
      }
      final top = y(pt.value!);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(cx - 4, top, cx + 4, size.height),
          const Radius.circular(3),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NightBarsPainter old) =>
      old.points != points ||
      old.baseline != baseline ||
      old.color != color ||
      old.tint != tint ||
      old.gap != gap;
}
