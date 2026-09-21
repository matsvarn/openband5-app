import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'domain.dart';
import 'theme.dart';

/// Calendar-positioned nightly line used by typed temperature quantities.
/// Missing nights remain gaps; points are never interpolated or resampled.
class OBNightLine extends StatelessWidget {
  const OBNightLine({
    super.key,
    required this.history,
    required this.nights,
    required this.unit,
    this.visible = true,
  });

  final List<NightScalarHistoryNight> history;
  final int nights;
  final NightScalarUnit unit;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final t = ((scaler.scale(12) / 12) - 1).clamp(0.0, 1.0);
    return SizedBox(
      key: const ValueKey('temperature-night-line'),
      width: double.infinity,
      height: 120 + 40 * t,
      child: Visibility(
        visible: visible,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: CustomPaint(
          painter: OBNightLinePainter(
            values: [for (final night in history) night.value],
            nights: nights,
            unit: unit,
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

class OBNightLinePainter extends CustomPainter {
  const OBNightLinePainter({
    required this.values,
    required this.nights,
    required this.unit,
    required this.ink,
    required this.axis,
    required this.guide,
    required this.textScaler,
  });

  final List<double?> values;
  final int nights;
  final NightScalarUnit unit;
  final Color ink;
  final Color axis;
  final Color guide;
  final TextScaler textScaler;

  (double, double)? _domain() {
    final finite = values.whereType<double>().where((v) => v.isFinite).toList();
    if (finite.isEmpty) return null;
    if (unit == NightScalarUnit.sd) {
      var bound = finite.map((v) => v.abs()).reduce(math.max).ceilToDouble();
      if (bound < 1) bound = 1;
      return (-bound, bound);
    }
    if (unit == NightScalarUnit.celsius) {
      var low = finite.reduce(math.min).floorToDouble();
      var high = finite.reduce(math.max).ceilToDouble();
      if (low >= high) {
        low -= 1;
        high += 1;
      }
      return (low, high);
    }
    return null;
  }

  static String axisLabel(double value, NightScalarUnit unit) {
    final digits = value == value.round() ? 0 : 1;
    if (unit == NightScalarUnit.celsius) {
      return obNumber(value, digits: digits);
    }
    final number = obNumber(value.abs(), digits: digits);
    if (value == 0) return obNumber(value);
    return value > 0 ? '+$number' : '−$number';
  }

  @override
  void paint(Canvas canvas, Size size) {
    final domain = _domain();
    if (domain == null || nights <= 0) return;
    final low = domain.$1;
    final high = domain.$2;
    final span = high - low;
    if (!span.isFinite || span <= 0) return;

    final t = ((textScaler.scale(12) / 12) - 1).clamp(0.0, 1.0);
    final left = 38 + 12 * t;
    final top = 8 + 16 * t;
    final bottom = 108 + 32 * t;
    final plotWidth = math.max(0.0, size.width - left);
    if (plotWidth <= 0) return;
    double x(int i) => left + (i + .5) * plotWidth / nights;
    double y(double value) => bottom - (value - low) / span * (bottom - top);

    final style = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      height: 1,
      color: axis,
    );
    void paintLabel(String text, double centerY) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
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

    paintLabel(axisLabel(high, unit), top);
    paintLabel(axisLabel((high + low) / 2, unit), (top + bottom) / 2);
    paintLabel(axisLabel(low, unit), bottom);

    if (unit == NightScalarUnit.sd) {
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
    final count = math.min(values.length, nights);
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
  bool shouldRepaint(covariant OBNightLinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.nights != nights ||
      oldDelegate.unit != unit ||
      oldDelegate.ink != ink ||
      oldDelegate.axis != axis ||
      oldDelegate.guide != guide ||
      oldDelegate.textScaler != textScaler;
}
