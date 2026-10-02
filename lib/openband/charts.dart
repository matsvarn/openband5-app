import 'package:flutter/material.dart';
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
