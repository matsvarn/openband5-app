import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// A Messleiste: a value on a ticked track with labelled ends.
///
/// [value] null draws the empty track and no pointer. [baseLow]/[baseHigh]
/// shade the personal baseline; [target] draws a dashed goal mark. With
/// [fill] the track fills up to the value and the pointer is a hollow knob;
/// without it the pointer is a solid needle over the baseline band.
///
/// The captions are painted marks of the instrument, not text content: the
/// value they annotate is already stated as text beside the scale.
class OBScale extends StatelessWidget {
  final double min, max;
  final double? value, baseLow, baseHigh, target;
  final Color? fill;
  final int ticks;

  /// Left, centre and right captions under the ticks. Centre may be null.
  final (String, String?, String)? labels;

  /// Bold ink caption under the [target] mark, e.g. "Ziel 7h45".
  final String? targetLabel;
  final String? semanticsLabel;
  const OBScale({
    super.key,
    required this.min,
    required this.max,
    this.value,
    this.baseLow,
    this.baseHigh,
    this.target,
    this.fill,
    this.ticks = 10,
    this.labels,
    this.targetLabel,
    this.semanticsLabel,
  }) : assert(max > min);

  static const double trackHeight = 34;

  /// Paper: captions sit 3 pt under the track on a 12 pt line.
  static const double captionGap = 3;

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final scale = math.min(MediaQuery.textScalerOf(context).scale(1), 1.4);
    final captionHeight = labels == null ? 0.0 : captionGap + 12 * scale;
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: trackHeight + captionHeight,
        width: double.infinity,
        child: CustomPaint(
          painter: _ScalePainter(
            p: p,
            min: min,
            max: max,
            value: value,
            baseLow: baseLow,
            baseHigh: baseHigh,
            target: target,
            fill: fill,
            ticks: ticks,
            labels: labels,
            targetLabel: targetLabel,
            captionScale: scale,
            direction: Directionality.of(context),
          ),
        ),
      ),
    );
  }
}

class _ScalePainter extends CustomPainter {
  final OB p;
  final double min, max;
  final double? value, baseLow, baseHigh, target;
  final Color? fill;
  final int ticks;
  final (String, String?, String)? labels;
  final String? targetLabel;
  final double captionScale;
  final TextDirection direction;
  _ScalePainter({
    required this.p,
    required this.min,
    required this.max,
    required this.value,
    required this.baseLow,
    required this.baseHigh,
    required this.target,
    required this.fill,
    required this.ticks,
    required this.labels,
    required this.targetLabel,
    required this.captionScale,
    required this.direction,
  });

  double _x(double v, double w) =>
      ((v - min) / (max - min)).clamp(0.0, 1.0) * w;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    const top = 10.0, h = 10.0;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, w, h),
      const Radius.circular(5),
    );
    canvas.drawRRect(track, Paint()..color = p.line);
    if (baseLow != null && baseHigh != null) {
      final x0 = _x(baseLow!, w), x1 = _x(baseHigh!, w);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x0, top, x1, top + h),
          const Radius.circular(3),
        ),
        Paint()..color = p.gap,
      );
    }
    final v = value;
    if (v != null && fill != null) {
      canvas.save();
      canvas.clipRRect(track);
      canvas.drawRect(
        Rect.fromLTWH(0, top, _x(v, w), h),
        Paint()..color = fill!,
      );
      canvas.restore();
    }
    final tick = Paint()..color = p.muted;
    for (var i = 0; i <= ticks; i++) {
      final x = (w - 1) * i / ticks + .5;
      final major = i == 0 || i == ticks || i * 2 == ticks;
      tick.strokeWidth = major ? 1.4 : 1;
      canvas.drawLine(
        Offset(x, top + h + 5),
        Offset(x, top + h + (major ? 13 : 9)),
        tick,
      );
    }
    if (target != null) {
      final x = _x(target!, w);
      final dash = Paint()
        ..color = p.ink
        ..strokeWidth = 1.5;
      for (var y = 4.0; y < top + h + 6; y += 4) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 2), dash);
      }
    }
    if (v != null) {
      final x = _x(v, w).clamp(2.5, w - 2.5);
      final knob = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, top + h / 2), width: 5, height: 24),
        const Radius.circular(2.5),
      );
      if (fill != null) {
        canvas.drawRRect(knob, Paint()..color = p.card);
        canvas.drawRRect(
          knob,
          Paint()
            ..color = p.ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      } else {
        canvas.drawRRect(knob, Paint()..color = p.ink);
      }
    }
    final caption = labels;
    if (caption != null) _captions(canvas, size, caption);
  }

  void _captions(Canvas canvas, Size size, (String, String?, String) c) {
    final style = p
        .text(10 * captionScale, weight: FontWeight.w500, color: p.muted)
        .copyWith(height: 1.2, letterSpacing: 0);
    TextPainter lay(String text, double maxWidth, [TextStyle? s]) =>
        TextPainter(
          text: TextSpan(text: text, style: s ?? style),
          textDirection: direction,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: math.max(0, maxWidth));
    const y = OBScale.trackHeight + OBScale.captionGap;
    final w = size.width;
    final left = lay(c.$1, w / 3);
    final right = lay(c.$3, w / 3);
    left.paint(canvas, Offset(0, y));
    right.paint(canvas, Offset(w - right.width, y));
    Rect? taken;
    if (targetLabel != null && target != null) {
      final t = lay(
        targetLabel!,
        w / 2,
        style.copyWith(fontWeight: FontWeight.w700, color: p.ink),
      );
      final x = (_x(target!, w) - t.width / 2)
          .clamp(
            left.width + 6,
            math.max(left.width + 6, w - right.width - 6 - t.width),
          )
          .toDouble();
      t.paint(canvas, Offset(x, y));
      taken = Rect.fromLTWH(x - 6, y, t.width + 12, t.height);
      t.dispose();
    }
    if (c.$2 != null) {
      final mid = lay(c.$2!, w - left.width - right.width - 16);
      final x = (w - mid.width) / 2;
      final r = Rect.fromLTWH(x, y, mid.width, mid.height);
      if (taken == null || !taken.overlaps(r)) mid.paint(canvas, Offset(x, y));
      mid.dispose();
    }
    left.dispose();
    right.dispose();
  }

  @override
  bool shouldRepaint(_ScalePainter old) =>
      old.value != value ||
      old.baseLow != baseLow ||
      old.baseHigh != baseHigh ||
      old.target != target ||
      old.fill != fill ||
      old.min != min ||
      old.max != max ||
      old.labels != labels ||
      old.targetLabel != targetLabel ||
      old.captionScale != captionScale ||
      old.p.dark != p.dark;
}
