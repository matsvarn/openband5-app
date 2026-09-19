import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'alp_tokens.dart';
import 'controller.dart';
import 'domain.dart';
import 'metric_detail.dart';
import 'screens.dart';
import 'theme.dart';

class OpenBandHealth extends StatefulWidget {
  final OpenBandController controller;
  const OpenBandHealth({super.key, required this.controller});
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
      return ColoredBox(
        color: p.canvas,
        child: ListView(
          key: const PageStorageKey('openband.health'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Gesundheit',
                style: p.text(30, weight: FontWeight.w800, display: true),
              ),
            ),
            const SizedBox(height: 12),
            OBSegmented(
              labels: const ['7 Nächte', '30 Nächte'],
              selected: nights == 7 ? 0 : 1,
              onChanged: (i) => setState(() => nights = i == 0 ? 7 : 30),
            ),
            const SizedBox(height: 12),
            if (day != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: OBMetricCard(
                      label: 'HRV',
                      unit: 'ms',
                      metric: day.hrv,
                      icon: LucideIcons.activity,
                      color: p.recovery,
                      tint: p.recoveryTint,
                      day: day.day,
                      onTap: () => OpenBandMetricDetail.push(
                        context,
                        controller: c,
                        metricKey: MetricKey.hrv,
                        label: 'HRV',
                        subtitle: 'Herzratenvariabilität',
                        unit: 'ms',
                        icon: LucideIcons.activity,
                        color: (p) => p.recovery,
                        tint: (p) => p.recoveryTint,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OBMetricCard(
                      label: 'Ruhepuls',
                      unit: '/min',
                      metric: day.restingHr,
                      icon: LucideIcons.heart,
                      color: p.pulse,
                      tint: p.pulseTint,
                      day: day.day,
                      onTap: () => OpenBandMetricDetail.push(
                        context,
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
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            for (final (key, label, unit, icon, color, tint) in [
              (
                MetricKey.hrv,
                'HRV',
                'ms',
                LucideIcons.activity,
                p.recovery,
                p.recoveryTint,
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
                p.recovery,
                p.recoveryTint,
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
                      MetricKey.recovery => null,
                    },
                    error: snapshot.hasError,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class OBSegmented extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  const OBSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(AlpRadius.row),
      ),
      child: Row(
        children: [
          for (final (i, label) in labels.indexed)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                child: InkWell(
                  onTap: () => onChanged(i),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? p.ink : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      label,
                      style: p.text(
                        14,
                        weight: FontWeight.w600,
                        color: i == selected ? p.card : p.muted,
                      ),
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

class OBTrendCard extends StatelessWidget {
  final String label, unit;
  final IconData icon;
  final Color color, tint;
  final int nights;
  final List<MetricPoint>? points;
  final double? baseline;
  final bool error;
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
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final values = points?.where((e) => e.value != null).toList() ?? const [];
    final last = values.isEmpty ? null : values.last.value;
    final observed = values.length;
    final status = error
        ? ('Verlauf konnte nicht geladen werden', p.danger)
        : points == null
        ? ('', p.muted)
        : observed == 0
        ? ('Noch keine Werte', p.muted)
        : observed < nights
        ? ('$observed von $nights Nächten', p.muted)
        : (obMetricStatus(last, baseline, unit: unit), p.smallText(color));
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
                obNumber(last),
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
                '$label, $nights Nächte, ${observed == 0 ? 'keine Werte' : '$observed Werte, zuletzt ${obNumber(last)} $unit'}',
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
}

String obMetricStatus(double? value, double? baseline, {String unit = ''}) {
  if (baseline == null) return 'Basis noch offen';
  if (value == null) return '—';
  final d = value - baseline;
  if (d.abs() < .5) return 'im Bereich';
  return '${d > 0 ? '+' : '−'}${obNumber(d.abs())} ${d > 0 ? 'über' : 'unter'} Basis';
}

class _TrendPainter extends CustomPainter {
  final List<MetricPoint> points;
  final double? baseline;
  final Color color, tint, gap, ring;
  _TrendPainter(
    this.points,
    this.baseline,
    this.color,
    this.tint,
    this.gap,
    this.ring,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final values = [for (final p in points) p.value].nonNulls.toList();
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
      final band = Paint()..color = tint;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, y(b) - 8, size.width, y(b) + 8),
          const Radius.circular(4),
        ),
        band,
      );
    }
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final first = points.indexWhere((p) => p.value != null);
    final last = points.lastIndexWhere((p) => p.value != null);
    Path? path;
    int? lastIndex;
    for (var i = 0; i < points.length; i++) {
      final v = points[i].value;
      if (v == null) {
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
        path = Path()..moveTo(x(i), y(v));
        if (lastIndex != null) {
          canvas.drawCircle(Offset(x(i), y(v)), 2.5, Paint()..color = color);
        }
      } else {
        path.lineTo(x(i), y(v));
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

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.points != points ||
      old.baseline != baseline ||
      old.color != color ||
      old.tint != tint ||
      old.gap != gap ||
      old.ring != ring;
}
