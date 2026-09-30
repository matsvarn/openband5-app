import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Isolated OpenBand glucose history plot.
///
/// Signature:
/// `OBGlucoseChart({super.key, required List<({DateTime at, double value})> readings, required String unit})`
///
/// [readings] are already-filtered finite samples from one source in one
/// known [unit]. Presentation only: no unit conversion, metric computation,
/// medical ranges, interpolation, smoothing, or invented coverage.
/// Latest-calendar-day filtering is caller-owned.
///
/// Empty [readings] keeps the Verlauf heading and unit and shows "—" — the
/// plot and axes are omitted so no bound, time range, or sample count is
/// fabricated. A single point is drawn at the plot center with that actual
/// timestamp. A flat series uses finite nice bounds so y-mapping never
/// divides by zero. If stored finite values cannot form a representable
/// numeric viewport or leave a readable chart lane, the plot and axes are
/// omitted with "—" as well; semantics still report the stored points and
/// time range.
class OBGlucoseChart extends StatelessWidget {
  const OBGlucoseChart({super.key, required this.readings, required this.unit});

  final List<({DateTime at, double value})> readings;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final heading = p
        .text(15, weight: FontWeight.w600)
        .copyWith(height: 20 / 15);
    final unitStyle = p.text(13, color: p.muted).copyWith(height: 18 / 13);
    final viewport = _viewport();
    return LayoutBuilder(
      builder: (context, constraints) {
        final renderableViewport =
            viewport != null &&
                _hasReadableLane(context, p, viewport, constraints.maxWidth)
            ? viewport
            : null;
        return Semantics(
          label: _semanticsLabel(renderableViewport),
          child: ExcludeSemantics(
            child: OBCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                spacing: 16,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      Expanded(child: Text('Verlauf', style: heading)),
                      Expanded(
                        child: Text(
                          unit,
                          textAlign: TextAlign.right,
                          style: unitStyle,
                        ),
                      ),
                    ],
                  ),
                  if (renderableViewport == null)
                    Text('—', style: p.text(15, color: p.muted))
                  else
                    _plot(context, p, renderableViewport),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _plot(BuildContext context, OB p, (double, double, double) viewport) {
    final scaler = MediaQuery.textScalerOf(context);
    final axisStyle = p.text(12, color: p.muted).copyWith(height: 18 / 12);
    final direction = Directionality.of(context);
    final (lo, hi, step) = viewport;
    final digits = _decimals(step);
    final highText = obNumber(hi, digits: digits);
    final lowText = obNumber(lo, digits: digits);
    final (start, end) = _span(readings);
    final times = start == end
        ? [start]
        : [start, start.add(end.difference(start) ~/ 2), end];
    final high = _measure(highText, axisStyle, scaler, direction);
    final low = _measure(lowText, axisStyle, scaler, direction);
    final axisLane = math.max(34.0, math.max(high.width, low.width));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            Expanded(
              child: SizedBox(
                height: 160,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    return CustomPaint(
                      size: Size(w, 160),
                      painter: _GlucosePlotPainter(
                        dots: [
                          for (final r in readings)
                            Offset(
                              _x(r.at, start, end, w),
                              _y(r.value, lo, hi),
                            ),
                        ],
                        line: p.line,
                        sleep: p.sleep,
                      ),
                    );
                  },
                ),
              ),
            ),
            SizedBox(
              width: axisLane,
              height: 160,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 12 - high.height / 2,
                    left: 0,
                    width: axisLane,
                    child: Text(highText, style: axisStyle),
                  ),
                  Positioned(
                    top: 140 - low.height / 2,
                    left: 0,
                    width: axisLane,
                    child: Text(lowText, style: axisStyle),
                  ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(right: 10 + axisLane),
          child: times.length == 1
              ? Center(child: Text(obTime(times.first), style: axisStyle))
              : Row(
                  children: [
                    for (final (i, at) in times.indexed)
                      Expanded(
                        child: Text(
                          obTime(at),
                          textAlign: i == 0
                              ? TextAlign.left
                              : i == times.length - 1
                              ? TextAlign.right
                              : TextAlign.center,
                          style: axisStyle,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  bool _hasReadableLane(
    BuildContext context,
    OB p,
    (double, double, double) viewport,
    double width,
  ) {
    if (!width.isFinite) return true;
    final (lo, hi, step) = viewport;
    final digits = _decimals(step);
    final style = p.text(12, color: p.muted).copyWith(height: 18 / 12);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final high = _measure(
      obNumber(hi, digits: digits),
      style,
      scaler,
      direction,
    );
    final low = _measure(
      obNumber(lo, digits: digits),
      style,
      scaler,
      direction,
    );
    final axisLane = math.max(34.0, math.max(high.width, low.width));
    final plotWidth = width - 32 - 10 - axisLane;
    return plotWidth > 12;
  }

  (double, double, double)? _viewport() {
    if (readings.isEmpty) return null;
    final bounds = _niceBounds([for (final r in readings) r.value]);
    if (bounds == null) return null;
    final (lo, hi, step) = bounds;
    if (obNumber(hi, digits: _decimals(step)) ==
        obNumber(lo, digits: _decimals(step))) {
      return null;
    }
    for (final r in readings) {
      if (!_y(r.value, lo, hi).isFinite) return null;
    }
    return bounds;
  }

  String _semanticsLabel((double, double, double)? viewport) {
    if (readings.isEmpty) return 'Verlauf, keine Messpunkte, $unit';
    final (start, end) = _span(readings);
    final n = readings.length;
    final count = n == 1 ? '1 Messpunkt' : '$n Messpunkte';
    final range = start == end
        ? obTime(start)
        : '${obTime(start)} bis ${obTime(end)}';
    final base = 'Verlauf, $count, $range, $unit';
    if (viewport == null) return '$base, Darstellung nicht möglich';
    return base;
  }
}

class _GlucosePlotPainter extends CustomPainter {
  _GlucosePlotPainter({
    required this.dots,
    required this.line,
    required this.sleep,
  });

  final List<Offset> dots;
  final Color line, sleep;

  @override
  void paint(Canvas canvas, Size size) {
    final guides = Paint()
      ..color = line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, 12), Offset(size.width, 12), guides);
    canvas.drawLine(Offset(0, 140), Offset(size.width, 140), guides);
    final fill = Paint()..color = sleep;
    for (final dot in dots) {
      canvas.drawCircle(dot, 3.5, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _GlucosePlotPainter old) =>
      old.line != line || old.sleep != sleep || old.dots != dots;
}

(DateTime, DateTime) _span(List<({DateTime at, double value})> readings) {
  var start = readings.first.at;
  var end = start;
  for (final r in readings) {
    if (r.at.isBefore(start)) start = r.at;
    if (r.at.isAfter(end)) end = r.at;
  }
  return (start, end);
}

double _x(DateTime at, DateTime start, DateTime end, double width) {
  if (width <= 0) return 0;
  final span = end.difference(start).inMicroseconds;
  if (span == 0) return width / 2;
  return 6 + at.difference(start).inMicroseconds / span * (width - 12);
}

double _y(double value, double lo, double hi) {
  final span = hi - lo;
  if (span == 0) return 76;
  return 12 + (hi - value) / span * 128;
}

(double, double, double)? _niceBounds(List<double> values) {
  var lo = values.first;
  var hi = lo;
  for (final v in values) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  var span = hi - lo;
  if (span == 0) {
    final mag = math.max(lo.abs(), 1.0);
    if (!mag.isFinite) return null;
    span = mag * 0.2;
    lo -= span / 2;
    hi += span / 2;
  }
  if (!span.isFinite || span <= 0) return null;
  final paddedLo = lo - span * 0.05;
  final paddedHi = hi + span * 0.05;
  final padded = paddedHi - paddedLo;
  if (!padded.isFinite) return null;
  final niceRange = _niceNum(padded, round: false);
  if (niceRange == null) return null;
  final step = _niceNum(niceRange / 4, round: true);
  if (step == null || step == 0) return null;
  final minRatio = paddedLo / step;
  final maxRatio = paddedHi / step;
  if (!minRatio.isFinite || !maxRatio.isFinite) return null;
  var niceMin = minRatio.floorToDouble() * step;
  var niceMax = maxRatio.ceilToDouble() * step;
  if (niceMax - niceMin == 0) {
    niceMin -= step;
    niceMax += step;
  }
  final view = niceMax - niceMin;
  if (!niceMin.isFinite || !niceMax.isFinite || !view.isFinite || view <= 0) {
    return null;
  }
  return (niceMin, niceMax, step);
}

double? _niceNum(double range, {required bool round}) {
  final abs = range.abs();
  if (!abs.isFinite || abs == 0) return null;
  final log10 = math.log(abs) / math.ln10;
  if (!log10.isFinite) return null;
  final exp = log10.floor();
  final denom = math.pow(10, exp).toDouble();
  if (!denom.isFinite || denom == 0) return null;
  final frac = abs / denom;
  final nf = round
      ? (frac < 1.5
            ? 1.0
            : frac < 3
            ? 2.0
            : frac < 7
            ? 5.0
            : 10.0)
      : (frac <= 1
            ? 1.0
            : frac <= 2
            ? 2.0
            : frac <= 5
            ? 5.0
            : 10.0);
  final out = nf * denom;
  return out.isFinite ? out : null;
}

int _decimals(double step) {
  if (!step.isFinite || step.abs() >= 1) return 0;
  final digits = -(math.log(step.abs()) / math.ln10).floor();
  if (!digits.isFinite) return 0;
  return digits.clamp(1, 15);
}

Size _measure(
  String text,
  TextStyle style,
  TextScaler scaler,
  TextDirection direction,
) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textScaler: scaler,
  )..layout();
  return Size(tp.width.ceilToDouble(), tp.height);
}
