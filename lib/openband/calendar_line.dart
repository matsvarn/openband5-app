import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Calendar-positioned numeric line. Missing and non-finite slots remain gaps.
class OBCalendarLine extends StatelessWidget {
  const OBCalendarLine({
    super.key,
    required this.values,
    required this.days,
    this.zeroCentered = false,
    this.visible = true,
  });

  final List<double?> values;
  final int days;
  final bool zeroCentered;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final t = ((scaler.scale(12) / 12) - 1).clamp(0.0, 1.0);
    return SizedBox(
      width: double.infinity,
      height: 120 + 40 * t,
      child: Visibility(
        visible: visible,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: CustomPaint(
          painter: OBCalendarLinePainter(
            values: values,
            days: days,
            zeroCentered: zeroCentered,
            ink: OB.of(context).ink,
            axis: OB.of(context).muted,
            guide: OB.of(context).line,
            textScaler: scaler,
          ),
        ),
      ),
    );
  }
}

class OBCalendarLinePainter extends CustomPainter {
  const OBCalendarLinePainter({
    required this.values,
    required this.days,
    required this.zeroCentered,
    required this.ink,
    required this.axis,
    required this.guide,
    required this.textScaler,
  });

  final List<double?> values;
  final int days;
  final bool zeroCentered;
  final Color ink;
  final Color axis;
  final Color guide;
  final TextScaler textScaler;

  (double, double)? domain() {
    final finite = values.whereType<double>().where((v) => v.isFinite).toList();
    if (finite.isEmpty) return null;
    if (zeroCentered) {
      var bound = finite.map((v) => v.abs()).reduce(math.max).ceilToDouble();
      if (bound < 1) bound = 1;
      return (-bound, bound);
    }
    var low = finite.reduce(math.min).floorToDouble();
    var high = finite.reduce(math.max).ceilToDouble();
    if (low >= high) {
      low -= 1;
      high += 1;
    }
    return (low, high);
  }

  static String axisLabel(double value, {bool signed = false}) {
    final digits = value == value.round() ? 0 : 1;
    if (!signed) return obNumber(value, digits: digits);
    final number = obNumber(value.abs(), digits: digits);
    if (value == 0) return obNumber(value);
    return value > 0 ? '+$number' : '−$number';
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = domain();
    if (bounds == null || days <= 0) return;
    final low = bounds.$1;
    final high = bounds.$2;
    final span = high - low;
    if (!span.isFinite || span <= 0) return;

    final t = ((textScaler.scale(12) / 12) - 1).clamp(0.0, 1.0);
    final top = 8 + 16 * t;
    final bottom = 108 + 32 * t;
    final style = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      height: 1,
      color: axis,
    );
    final labels = <String>[
      axisLabel(high, signed: zeroCentered),
      axisLabel((high + low) / 2, signed: zeroCentered),
      axisLabel(low, signed: zeroCentered),
    ];
    var widestLabel = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      widestLabel = math.max(widestLabel, painter.width);
      painter.dispose();
    }
    final left = math.max(38 + 12 * t, widestLabel + 10);
    final plotWidth = math.max(0.0, size.width - left);
    if (plotWidth <= 0) return;
    double x(int i) => left + (i + .5) * plotWidth / days;
    double y(double value) => bottom - (value - low) / span * (bottom - top);

    void paintLabel(String text, double centerY) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          math.max(0, left - 10 - painter.width),
          centerY - painter.height / 2,
        ),
      );
      painter.dispose();
    }

    paintLabel(labels[0], top);
    paintLabel(labels[1], (top + bottom) / 2);
    paintLabel(labels[2], bottom);

    if (zeroCentered) {
      final zeroY = y(0);
      canvas.drawLine(
        Offset(left, zeroY),
        Offset(size.width, zeroY),
        Paint()
          ..color = guide
          ..strokeWidth = 1,
      );
    }

    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final point = Paint()..color = ink;
    final count = math.min(values.length, days);
    for (var i = 0; i < count; i++) {
      final value = values[i];
      if (value == null || !value.isFinite) continue;
      final at = Offset(x(i), y(value));
      if (i > 0) {
        final previous = values[i - 1];
        if (previous != null && previous.isFinite) {
          canvas.drawLine(Offset(x(i - 1), y(previous)), at, line);
        }
      }
      canvas.drawCircle(at, 2.5, point);
    }
  }

  @override
  bool shouldRepaint(covariant OBCalendarLinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.days != days ||
      oldDelegate.zeroCentered != zeroCentered ||
      oldDelegate.ink != ink ||
      oldDelegate.axis != axis ||
      oldDelegate.guide != guide ||
      oldDelegate.textScaler != textScaler;
}
