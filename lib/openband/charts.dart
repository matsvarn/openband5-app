import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'domain.dart';
import 'theme.dart';

String stageName(NightStage? stage) => switch (stage) {
  NightStage.awake => 'Wach',
  NightStage.rem => 'REM',
  NightStage.light => 'Leicht',
  NightStage.deep => 'Tief',
  null => 'Keine Daten',
};
Color stageColor(OB p, NightStage? stage) => switch (stage) {
  NightStage.awake => p.wake,
  NightStage.rem => p.stageRem,
  NightStage.light => p.stageLight,
  NightStage.deep => p.stageDeep,
  null => p.line,
};

/// The night as a row of LED columns (Paper G2): deep is a full ink column,
/// light two thirds, REM under half, wake a hollow full-height outline. An
/// unobserved stretch is a short hollow stub. Only stored segments are drawn;
/// with none the caller shows the honest label instead.
class OBStageStrip extends StatelessWidget {
  final SleepNight night;
  final double height;
  const OBStageStrip({super.key, required this.night, this.height = 28});

  /// The stored segments read aloud, for any drawing of the night.
  static String describe(SleepNight night) => night.segments
      .map(
        (s) => '${obTime(s.start)} bis ${obTime(s.end)}: ${stageName(s.stage)}',
      )
      .join('. ');

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Semantics(
      label: describe(night),
      child: Container(
        height: height + 16,
        padding: const EdgeInsets.all(8),
        decoration: p.insetDecoration(radius: 10, color: p.line),
        child: CustomPaint(
          size: Size.infinite,
          painter: _StageStripPainter(p, night),
        ),
      ),
    );
  }
}

class _StageStripPainter extends CustomPainter {
  final OB p;
  final SleepNight night;
  _StageStripPainter(this.p, this.night);

  static double _level(NightStage stage) => switch (stage) {
    NightStage.deep => 1,
    NightStage.light => 20 / 28,
    NightStage.rem => 12 / 28,
    NightStage.awake => 1,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final segs = night.segments;
    if (segs.isEmpty) return;
    final start = segs.first.start, end = segs.last.end;
    final span = end.difference(start).inSeconds;
    if (span <= 0) return;
    const col = 4.7, gap = 1.47;
    final n = ((size.width + gap) / (col + gap)).floor();
    if (n <= 0) return;
    final step = (size.width - col) / (n > 1 ? n - 1 : 1);
    final outline = Paint()
      ..color = p.gap
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    var si = 0;
    for (var i = 0; i < n; i++) {
      final t = start.add(Duration(seconds: (span * (i + .5) / n).round()));
      while (si < segs.length - 1 && !segs[si].end.isAfter(t)) {
        si++;
      }
      final stage = segs[si].stage;
      final x = i * step;
      if (stage == null || stage == NightStage.awake) {
        final top = stage == null ? size.height * 16 / 28 : 0.0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x + .5, top + .5, x + col - .5, size.height - .5),
            const Radius.circular(1.5),
          ),
          outline,
        );
        continue;
      }
      final h = size.height * _level(stage);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, col, h),
          const Radius.circular(1.5),
        ),
        Paint()..color = stageColor(p, stage),
      );
    }
  }

  @override
  bool shouldRepaint(_StageStripPainter old) =>
      old.night != night || old.p.dark != p.dark;
}

class MetricRing extends StatelessWidget {
  final String label, value;
  final String? unit;
  final Color color, tint;
  final double? fraction;
  final SleepNight? night;
  final VoidCallback onTap;

  /// Value size — sleep's `7h18` is longer than a two-digit score.
  final double valueSize;
  final Color? unitColor;

  /// 0→1 load-in progress; scales the painted arcs. 1 when static.
  final double progress;
  const MetricRing({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    required this.color,
    required this.tint,
    this.fraction,
    this.night,
    this.valueSize = 32,
    this.unitColor,
    this.progress = 1,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: p.text(valueSize, weight: FontWeight.w800, display: true),
        ),
        if (unit != null)
          Text(
            unit!,
            style: p.text(
              10,
              weight: FontWeight.w600,
              color: unitColor ?? p.smallText(color),
            ),
          ),
      ],
    );
    return Semantics(
      button: true,
      label: '$label, $value ${unit ?? ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: ExcludeSemantics(
          child: Padding(
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (large)
                  text
                else
                  SizedBox(
                    width: 104,
                    height: 104,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size.square(104),
                          painter: _RingPainter(
                            p,
                            color,
                            tint,
                            fraction,
                            night,
                            progress,
                          ),
                        ),
                        text,
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Caption text: stays quiet when the system text size grows;
                  // the large-text fallback keeps semantics via the ring label.
                  textScaler: TextScaler.linear(
                    math.min(MediaQuery.textScalerOf(context).scale(1), 1.25),
                  ),
                  style: p.text(12, weight: FontWeight.w500, color: p.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final OB p;
  final Color color, tint;
  final double? fraction;
  final SleepNight? night;
  final double progress;
  static const strokeWidth = 11.0;
  _RingPainter(
    this.p,
    this.color,
    this.tint,
    this.fraction,
    this.night,
    this.progress,
  );
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.width - strokeWidth) / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = tint;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint);
    if (night case final n?) {
      final bed = n.bedMinutes;
      if (bed == null || bed <= 0) return;
      var start = -math.pi / 2;
      for (final part in [
        (n.remMinutes, p.stageRem),
        (n.lightMinutes, p.sleep),
        (n.deepMinutes, p.stageDeep),
        (n.awakeMinutes, p.wake),
      ]) {
        if (part.$1 == null) continue;
        final sweep = (part.$1! / bed).clamp(0.0, 1.0) * math.pi * 2 * progress;
        if (sweep > .025) {
          canvas.drawArc(
            rect,
            start + .02,
            math.max(0, sweep - .04),
            false,
            paint..color = part.$2,
          );
        }
        start += sweep;
      }
    } else if (fraction != null) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        fraction!.clamp(0.0, 1.0) * math.pi * 2 * progress,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.night != night ||
      old.fraction != fraction ||
      old.progress != progress ||
      old.p.dark != p.dark ||
      old.color != color ||
      old.tint != tint;
}

class NightChart extends StatelessWidget {
  final SleepNight night;
  final bool labels, showGapCaption;
  final DateTime? selectedOnset, selectedWake;
  const NightChart({
    super.key,
    required this.night,
    this.labels = false,
    this.showGapCaption = true,
    this.selectedOnset,
    this.selectedWake,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final available =
        night.onset != null && night.wake != null && night.segments.isNotEmpty;
    final summary = available
        ? night.segments
              .map(
                (s) =>
                    '${obTime(s.start)} bis ${obTime(s.end)}: ${stageName(s.stage)}',
              )
              .join('. ')
        : 'Keine Schlafphasen verfügbar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (labels)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(obTime(night.onset), style: p.text(13)),
                Text(obTime(night.wake), style: p.text(13)),
              ],
            ),
          ),
        Semantics(
          label: summary,
          button: available,
          child: InkWell(
            onTap: available
                ? () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (c) => SafeArea(
                      child: SizedBox(
                        height: MediaQuery.sizeOf(c).height * .75,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Schlafphasen',
                                      style: p.text(
                                        18,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Schließen',
                                    onPressed: () => Navigator.pop(c),
                                    icon: const Icon(LucideIcons.x, size: 20),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  20,
                                ),
                                children: [
                                  ...night.segments.map(
                                    (s) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            s.stage == null
                                                ? LucideIcons.ellipsis
                                                : LucideIcons.circle,
                                            size: 14,
                                            color: stageColor(p, s.stage),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  stageName(s.stage),
                                                  style: p.text(
                                                    14,
                                                    weight: FontWeight.w500,
                                                  ),
                                                ),
                                                Text(
                                                  '${obTime(s.start)}–${obTime(s.end)}',
                                                  style: p.text(
                                                    13,
                                                    color: p.muted,
                                                  ),
                                                ),
                                                Text(
                                                  obGapMinutes(
                                                    s.end
                                                            .difference(s.start)
                                                            .inSeconds /
                                                        60,
                                                  ),
                                                  style: p.text(
                                                    13,
                                                    color: p.muted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : null,
            child: RepaintBoundary(
              child: SizedBox(
                height: 84,
                child: available
                    ? CustomPaint(
                        painter: _NightPainter(
                          night,
                          p,
                          selectedOnset,
                          selectedWake,
                        ),
                      )
                    : Center(
                        child: Text(
                          'Noch keine Phasen',
                          style: p.text(13, color: p.muted),
                        ),
                      ),
              ),
            ),
          ),
        ),
        if (showGapCaption && (night.unobservedMinutes ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${obGapMinutes(night.unobservedMinutes!)} ohne Daten',
              style: p.text(13, color: p.muted),
            ),
          ),
      ],
    );
  }
}

class _NightPainter extends CustomPainter {
  final SleepNight night;
  final OB p;
  final DateTime? selectedOnset, selectedWake;
  _NightPainter(this.night, this.p, this.selectedOnset, this.selectedWake);
  @override
  void paint(Canvas canvas, Size size) {
    final start = night.onset!.millisecondsSinceEpoch;
    final span = night.wake!.millisecondsSinceEpoch - start;
    if (span <= 0) return;
    double x(DateTime t) =>
        ((t.millisecondsSinceEpoch - start) / span).clamp(0.0, 1.0) *
        size.width;
    double y(NightStage s) => switch (s) {
      NightStage.awake => 2,
      NightStage.rem => 23,
      NightStage.light => 43,
      NightStage.deep => 63,
    };
    NightSegment? previous;
    for (final s in night.segments) {
      final left = x(s.start), right = x(s.end);
      if (right <= left) continue;
      if (s.stage == null) {
        final gapPaint = Paint()
          ..color = p.muted.withValues(alpha: .3)
          ..strokeWidth = 1;
        for (var gx = left + 2; gx < right; gx += 5) {
          canvas.drawLine(Offset(gx, 20), Offset(gx, 74), gapPaint);
        }
        previous = null;
        continue;
      }
      if (previous != null &&
          previous.end == s.start &&
          previous.stage != null &&
          right - left >= 3 &&
          x(previous.end) - x(previous.start) >= 3) {
        canvas.drawLine(
          Offset(left, y(previous.stage!) + 8),
          Offset(left, y(s.stage!) + 8),
          Paint()
            ..color = p.sleep.withValues(alpha: .45)
            ..strokeWidth = 1,
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, y(s.stage!), math.max(.1, right - left), 16),
          const Radius.circular(3),
        ),
        Paint()..color = stageColor(p, s.stage),
      );
      previous = s;
    }
    for (final endpoint in [selectedOnset, selectedWake]) {
      if (endpoint == null) continue;
      canvas.drawLine(
        Offset(x(endpoint), 0),
        Offset(x(endpoint), size.height),
        Paint()
          ..color = p.action
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NightPainter old) =>
      old.night != night ||
      old.p.dark != p.dark ||
      old.selectedOnset != selectedOnset ||
      old.selectedWake != selectedWake;
}
