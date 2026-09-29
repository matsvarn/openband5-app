// G3 chart Bausteine: heart-rate trace with zone bands and gaps, zone rows,
// trend chart (7 / 30 / 90 days) with the personal band and gaps.
//
// Painters sit behind RepaintBoundary. Gaps stay gaps: a null value or a
// listed gap is drawn hollow and dashed, never interpolated.
import 'package:flutter/material.dart';

import '../alp_tokens.dart';
import '../theme.dart' show OBChevron;
import 'chrome.dart' show OBSegmented;
import 'g3_theme.dart';

void _dash(
  Canvas canvas,
  Path path,
  Color color, {
  double width = 1.5,
  double on = 3,
  double off = 3,
}) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;
  for (final m in path.computeMetrics()) {
    for (double d = 0; d < m.length; d += on + off) {
      canvas.drawPath(m.extractPath(d, d + on), paint);
    }
  }
}

// ---------------------------------------------------------------------------
// Heart-rate trace

class OBHrTrace extends StatelessWidget {
  /// (minute since start, bpm) samples.
  final List<(double, double)> samples;
  final double duration;

  /// Minutes without a trusted optical signal.
  final List<(double, double)> gaps;

  /// Plot range in bpm and the six zone edges Z1…Z5 in bpm (from the stored
  /// zone source; the widget draws them, it does not derive them).
  final double min, max;
  final List<double> zoneEdges;
  final String? average, peak;
  final (String, String, String) axis;
  final String gapLabel;

  /// Share of usable optical signal and its bar segments (flex, isGap).
  final String? signalShare;
  final List<(int, bool)> signalSegments;
  final String signalNote;
  const OBHrTrace({
    super.key,
    required this.samples,
    required this.duration,
    this.gaps = const [],
    this.min = 100,
    this.max = 180,
    required this.zoneEdges,
    this.average,
    this.peak,
    this.axis = ('', '', ''),
    this.gapLabel = '',
    this.signalShare,
    this.signalSegments = const [],
    this.signalNote = 'Lücke bleibt leer, nichts wird aufgefüllt.',
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    const w = 291.0, h = 150.0;
    double x(double t) => t / duration * w;
    double y(double v) => h * (max - v) / (max - min);
    final usable = samples.where(
      (s) =>
          s.$1.isFinite &&
          s.$2.isFinite &&
          !gaps.any((gap) => s.$1 > gap.$1 && s.$1 < gap.$2),
    );
    final peakAt = usable.isEmpty
        ? null
        : usable.reduce((a, b) => b.$2 > a.$2 ? b : a);
    Widget stat(String k, String? v) => Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(k, style: g.t(15, 18, color: g.ink2)),
        const SizedBox(width: 5),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Text(
            v ?? '—',
            style: g.t(
              40,
              44,
              weight: FontWeight.w700,
              color: v == null ? g.gap : g.ink,
              tracking: -.04,
            ),
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: g.raised(radius: AlpRadius.hero),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('HERZFREQUENZ', style: g.caps()),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '/min · 30-s-Mittel',
                  textAlign: TextAlign.right,
                  style: g.t(13, 16, color: g.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              stat('Ø', average),
              const SizedBox(width: 18),
              stat('max', peak),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: w,
                  height: h,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _HrPainter(
                        samples,
                        duration,
                        gaps,
                        min,
                        max,
                        zoneEdges,
                        peakAt,
                        g,
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < zoneEdges.length - 1; i++)
                  if (zoneEdges[i + 1] > min && zoneEdges[i] < max)
                    Positioned(
                      left: w + 8,
                      top:
                          (y(zoneEdges[i + 1].clamp(min, max)) +
                                  y(zoneEdges[i].clamp(min, max))) /
                              2 -
                          7,
                      child: Text(
                        'Z${i + 1}',
                        style: g.t(11, 14, color: g.muted),
                      ),
                    ),
                for (final (_, g1) in gaps)
                  Positioned(
                    left: x(g1) + 5,
                    top: h - 18,
                    child: Text(
                      gapLabel,
                      style: g.t(
                        11,
                        14,
                        weight: FontWeight.w500,
                        color: g.ink2,
                      ),
                    ),
                  ),
                if (peakAt != null && peak != null)
                  Positioned(
                    left: x(peakAt.$1) + 7,
                    top: y(peakAt.$2) - 3,
                    child: Text(
                      g3Number(peakAt.$2),
                      style: g.t(11, 14, weight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: w,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final t in [axis.$1, axis.$2, axis.$3])
                  Text(t, style: g.t(12, 16, color: g.muted)),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: g.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Optisches Signal verwertbar',
                        style: g.t(
                          13,
                          16,
                          weight: FontWeight.w500,
                          color: g.ink2,
                        ),
                      ),
                    ),
                    Text(
                      signalShare ?? '—',
                      style: g.t(13, 16, weight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                SizedBox(
                  height: 6,
                  child: Row(
                    children: [
                      for (final (i, (flex, gap))
                          in signalSegments.indexed) ...[
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          flex: flex,
                          child: gap
                              ? const G3Dashed(radius: 0)
                              : Container(
                                  decoration: BoxDecoration(
                                    color: g.ink,
                                    borderRadius: BorderRadius.horizontal(
                                      left: Radius.circular(i == 0 ? 3 : 0),
                                      right: Radius.circular(
                                        i == signalSegments.length - 1 ? 3 : 0,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Text(signalNote, style: g.t(12, 16, color: g.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HrPainter extends CustomPainter {
  final List<(double, double)> samples;
  final double duration;
  final List<(double, double)> gaps;
  final double min, max;
  final List<double> edges;
  final (double, double)? peak;
  final G3 g;
  _HrPainter(
    this.samples,
    this.duration,
    this.gaps,
    this.min,
    this.max,
    this.edges,
    this.peak,
    this.g,
  );

  @override
  void paint(Canvas canvas, Size size) {
    double x(double t) => t / duration * size.width;
    double y(double v) => size.height * (max - v) / (max - min);
    for (var i = 0; i < edges.length - 1 && i < 5; i++) {
      final lo = edges[i].clamp(min, max), hi = edges[i + 1].clamp(min, max);
      if (hi <= lo) continue;
      canvas.drawRect(
        Rect.fromLTRB(0, y(hi), size.width, y(lo)),
        Paint()..color = g.zoneTints[i],
      );
    }
    for (final (g0, g1) in gaps) {
      canvas.drawRect(
        Rect.fromLTRB(x(g0), 0, x(g1), size.height),
        Paint()..color = g.canvas,
      );
      for (final gx in [g0, g1]) {
        _dash(
          canvas,
          Path()
            ..moveTo(x(gx), 0)
            ..lineTo(x(gx), size.height),
          g.gap,
          width: 1,
          on: 2,
          off: 3,
        );
      }
    }
    final line = Paint()
      ..color = g.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final path = Path();
    var open = false;
    for (final (t, v) in samples) {
      if (!t.isFinite || !v.isFinite) {
        open = false;
        continue;
      }
      final inGap = gaps.any((gp) => t > gp.$1 && t < gp.$2);
      if (inGap) {
        open = false;
        continue;
      }
      if (open) {
        path.lineTo(x(t), y(v));
      } else {
        path.moveTo(x(t), y(v));
        open = true;
      }
      if (gaps.any((gp) => t == gp.$1)) open = false;
    }
    canvas.drawPath(path, line);
    if (peak case (final t, final v)) {
      canvas
        ..drawCircle(Offset(x(t), y(v)), 3.5, Paint()..color = g.canvas)
        ..drawCircle(
          Offset(x(t), y(v)),
          3.5,
          Paint()
            ..color = g.ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
    }
  }

  @override
  bool shouldRepaint(_HrPainter old) =>
      old.samples != samples || old.gaps != gaps || old.g.dark != g.dark;
}

// ---------------------------------------------------------------------------
// Zone rows

class OBZone {
  final int index;
  final String range;

  /// Minutes in the zone; null renders "—" and no bar.
  final int? minutes;
  const OBZone(this.index, this.range, this.minutes);
}

class OBZoneRows extends StatelessWidget {
  final List<OBZone> zones;

  /// Unit of the ranges ("% HFmax") and the stored zone source
  /// ("HFmax 186 · geschätzt aus Alter").
  final String basis, source;
  final VoidCallback? onBasis;
  const OBZoneRows({
    super.key,
    required this.zones,
    this.basis = '% HFmax',
    required this.source,
    this.onBasis,
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final longest = zones
        .map((z) => z.minutes ?? 0)
        .fold(1, (a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: g.raised(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('ZEIT IN ZONEN', style: g.caps()),
              const Spacer(),
              Text(basis, style: g.t(13, 16, color: g.muted)),
            ],
          ),
          const SizedBox(height: 8),
          for (final z in zones)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 30),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            'Z${z.index}',
                            style: g.t(14, 18, weight: FontWeight.w700),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            z.range,
                            style: g.t(12, 16, color: g.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (z.minutes ?? 0) / longest,
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            color: g.zones[z.index - 1],
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 52,
                    child: Text(
                      z.minutes == null ? '—' : '${z.minutes} Min.',
                      textAlign: TextAlign.right,
                      style: g.t(
                        14,
                        18,
                        weight: FontWeight.w700,
                        color: z.minutes == null ? g.gap : g.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: g.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(source, style: g.t(12, 16, color: g.muted)),
                ),
                if (onBasis != null)
                  Semantics(
                    button: true,
                    label: 'Grundlage der Zonen',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onBasis,
                      child: SizedBox(
                        height: 44,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Grundlage',
                                style: g.t(13, 16, weight: FontWeight.w700),
                              ),
                              const SizedBox(width: 2),
                              OBChevron(size: 12, color: g.muted),
                            ],
                          ),
                        ),
                      ),
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

// ---------------------------------------------------------------------------
// Trend chart

enum OBTrendPeriod { d7, d30, d90 }

/// Per-point mark decided by the caller: coloured only outside the personal
/// range, or a neutral ring when the metric has no better/worse direction.
enum OBTrendMark { none, better, worse, outside }

class OBTrendChart extends StatelessWidget {
  final String title;
  final OBTrendPeriod period;
  final List<double?> values;
  final List<OBTrendMark>? marks;
  final double min, max;
  final (double, double)? band;
  final (String, String)? bandLabels;
  final double? zero;

  /// Sparse entries (weight): separate points across empty days, no gap boxes.
  final bool sparse;
  final List<String> xLabels;
  final String? footLeft, footRight;
  final ValueChanged<OBTrendPeriod>? onPeriod;
  const OBTrendChart({
    super.key,
    required this.title,
    required this.period,
    required this.values,
    this.marks,
    required this.min,
    required this.max,
    this.band,
    this.bandLabels,
    this.zero,
    this.sparse = false,
    this.xLabels = const [],
    this.footLeft,
    this.footRight,
    this.onPeriod,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    const h = 150.0;
    double y(double v) => h - (v - min) / (max - min) * h;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: g.raised(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: g.caps())),
              OBSegmented(
                items: const ['7 T', '30 T', '90 T'],
                selected: period.index,
                onChanged: onPeriod == null
                    ? null
                    : (i) => onPeriod!(OBTrendPeriod.values[i]),
              ),
            ],
          ),
          const SizedBox(height: 0),
          SizedBox(
            height: 152,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 1,
                  width: 325,
                  height: h,
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _TrendPainter(this, g)),
                  ),
                ),
                if (band case (final lo, final hi))
                  if (bandLabels case (final l, final u)) ...[
                    Positioned(
                      left: 329,
                      top: y(hi) - 7,
                      child: Text(
                        u,
                        style: g.t(
                          11,
                          14,
                          weight: FontWeight.w500,
                          color: g.ink2,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 329,
                      top: y(lo) - 5,
                      child: Text(
                        l,
                        style: g.t(
                          11,
                          14,
                          weight: FontWeight.w500,
                          color: g.ink2,
                        ),
                      ),
                    ),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 325,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final t in xLabels)
                  Text(
                    t,
                    style: g.t(
                      12,
                      16,
                      weight: t.toLowerCase() == 'heute'
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: t.toLowerCase() == 'heute' ? g.ink : g.muted,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: g.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    footLeft ?? '',
                    style: g.t(12, 16, color: g.ink2),
                  ),
                ),
                if (footRight != null)
                  Text(
                    footRight!,
                    style: g.t(12, 16, weight: FontWeight.w500, color: g.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final OBTrendChart c;
  final G3 g;
  _TrendPainter(this.c, this.g);

  double? _value(int i) {
    final v = c.values[i];
    return v?.isFinite == true ? v : null;
  }

  Color? _mark(int i) => switch (c.marks == null || i >= c.marks!.length
      ? OBTrendMark.none
      : c.marks![i]) {
    OBTrendMark.better => g.betterMark,
    OBTrendMark.worse => g.worseMark,
    _ => null,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final n = c.values.length;
    double y(double v) => h - (v - c.min) / (c.max - c.min) * h;
    if (c.band case (final lo, final hi)) {
      canvas.drawRect(
        Rect.fromLTRB(0, y(hi), w, y(lo)),
        Paint()..color = g.band.withValues(alpha: .45),
      );
    }
    canvas.drawLine(Offset(0, h), Offset(w, h), Paint()..color = g.hairline);
    if (c.zero != null) {
      _dash(
        canvas,
        Path()
          ..moveTo(0, y(c.zero!))
          ..lineTo(w, y(c.zero!)),
        g.muted,
        width: 1,
      );
    }
    if (n == 0) return;
    if (c.period == OBTrendPeriod.d7) {
      final cw = w / n;
      for (var i = 0; i < n; i++) {
        final cx = cw * i + cw / 2;
        final v = _value(i);
        if (v == null) {
          _dash(
            canvas,
            Path()..addRRect(
              RRect.fromLTRBR(
                cx - 12,
                h - 36,
                cx + 12,
                h - 1,
                const Radius.circular(5),
              ),
            ),
            g.gap,
          );
          continue;
        }
        final color = _mark(i) ?? (i == n - 1 ? g.ink : g.bar);
        canvas.drawRRect(
          RRect.fromLTRBR(cx - 12, y(v), cx + 12, h, const Radius.circular(4)),
          Paint()..color = color,
        );
      }
      return;
    }
    final step = w / (n - 1);
    if (!c.sparse) {
      var i = 0;
      while (i < n) {
        if (_value(i) != null) {
          i++;
          continue;
        }
        var j = i;
        while (j < n && _value(j) == null) {
          j++;
        }
        final x0 = ((i - .5) * step).clamp(0.0, w),
            x1 = ((j - .5) * step).clamp(0.0, w);
        canvas.drawRect(Rect.fromLTRB(x0, 0, x1, h), Paint()..color = g.canvas);
        _dash(
          canvas,
          Path()..addRRect(
            RRect.fromLTRBR(
              x0 + .75,
              .75,
              x1 - .75,
              h - .75,
              const Radius.circular(3),
            ),
          ),
          g.gap,
          width: 1.2,
        );
        i = j;
      }
    }
    final line = Paint()
      ..color = g.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = c.period == OBTrendPeriod.d30 ? 2 : 1.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final path = Path();
    var open = false;
    for (var i = 0; i < n; i++) {
      final v = _value(i);
      if (v == null) {
        open = false;
        continue;
      }
      if (open) {
        path.lineTo(i * step, y(v));
      } else {
        path.moveTo(i * step, y(v));
        open = true;
      }
    }
    canvas.drawPath(path, line);
    for (var i = 0; i < n; i++) {
      final v = _value(i);
      if (v == null) continue;
      final o = Offset(i * step, y(v));
      final mark = _mark(i);
      final ring =
          c.marks != null &&
          i < c.marks!.length &&
          c.marks![i] == OBTrendMark.outside;
      if (mark != null) {
        canvas.drawCircle(
          o,
          c.period == OBTrendPeriod.d30 ? 3.2 : 2.6,
          Paint()..color = mark,
        );
      } else if (ring || c.sparse || c.period == OBTrendPeriod.d30) {
        final r = ring ? 4.0 : (c.sparse ? 3.2 : 2.6);
        canvas
          ..drawCircle(o, r, Paint()..color = g.canvas)
          ..drawCircle(
            o,
            r,
            Paint()
              ..color = g.ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = ring ? 2 : 1.5,
          );
      }
    }
    if (_value(n - 1) case final last?) {
      final o = Offset(w, y(last));
      canvas
        ..drawCircle(o, 5.5, Paint()..color = g.canvas)
        ..drawCircle(o, 4.5, Paint()..color = (_mark(n - 1) ?? g.ink));
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.c != c || old.g.dark != g.dark;
}
