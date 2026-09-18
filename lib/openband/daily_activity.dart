import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../data/day_label.dart';
import 'domain.dart';
import 'theme.dart';

class StepsCard extends StatelessWidget {
  final OpenBandDay day;
  final VoidCallback? onNutrition;
  const StepsCard({super.key, required this.day, this.onNutrition});

  void _details(BuildContext context, {bool intake = false}) {
    final p = OB.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                intake ? 'Ernährung & Wasser' : 'Schritte',
                style: p.text(18, weight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(obDate(day.day), style: p.text(13, color: p.muted)),
              const SizedBox(height: 16),
              if (intake) ...[
                Text(
                  '${day.intake.kcalIsFloor ? 'Mindestens ' : ''}${obNumber(day.intake.kcal)} kcal erfasst',
                  style: p.text(24, weight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  '${obNumber(day.intake.waterMl)} ml Wasser erfasst',
                  style: p.text(18),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Die Angaben stammen aus deinen Einträgen. Fehlende Mengen bleiben offen.',
                ),
                if (onNutrition != null && day.day == todayLabel()) ...[
                  const SizedBox(height: 16),
                  OBAction(
                    'Ernährung öffnen',
                    onPressed: () {
                      Navigator.pop(context);
                      onNutrition!();
                    },
                  ),
                ],
              ] else ...[
                Text(
                  obNumber(day.steps.value),
                  style: p.text(38, weight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                if (day.stepIntervals.isEmpty)
                  const Text(
                    'Für diesen Tag ist noch kein zeitlicher Verlauf verfügbar. Ein gespeicherter Tageswert bleibt davon unabhängig.',
                  )
                else
                  for (final interval in day.stepIntervals)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Text(
                        '${obTime(interval.start)}–${obTime(interval.end)} · ${obNumber(interval.steps)} Schritte',
                      ),
                    ),
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Schließen'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final kcal =
        '${day.intake.kcalIsFloor ? '≥' : ''}${obNumber(day.intake.kcal)} kcal';
    final water = '${obNumber(day.intake.waterMl)} ml';
    final last = day.stepIntervals.isEmpty ? null : day.stepIntervals.last.end;
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _details(context),
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            LucideIcons.footprints,
                            size: 16,
                            color: p.strain,
                          ),
                          const SizedBox(width: 6),
                          Text('Schritte', style: p.text(13)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 8,
                        children: [
                          Text(
                            obNumber(day.steps.value),
                            style: p.text(27, weight: FontWeight.w600),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              last != null
                                  ? 'bis ${obTime(last)}'
                                  : 'Tageswert',
                              style: p.text(11, color: p.muted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  height: 40,
                  child: day.stepIntervals.isEmpty
                      ? Semantics(
                          label: 'Schritteverlauf noch offen',
                          child: Icon(
                            LucideIcons.footprints,
                            color: p.strain.withValues(alpha: .4),
                            size: 34,
                          ),
                        )
                      : Semantics(
                          label:
                              'Schritteverlauf: ${day.stepIntervals.map((s) => '${obTime(s.start)} bis ${obTime(s.end)}, ${obNumber(s.steps)} Schritte').join('. ')}',
                          child: CustomPaint(
                            painter: _StepsPainter(day.stepIntervals, p.strain),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    _chip(
                      context,
                      kcal,
                      p.stageDeep,
                      () => _details(context, intake: true),
                    ),
                    _chip(
                      context,
                      water,
                      p.action,
                      () => _details(context, intake: true),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Schritte ansehen',
                onPressed: () => _details(context),
                icon: Icon(LucideIcons.chevronRight, color: p.muted, size: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    Color color,
    VoidCallback onTap,
  ) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(label, style: OB.of(context).text(13, color: color)),
            ),
          ),
        ),
      ),
    ),
  );
}

class _StepsPainter extends CustomPainter {
  final List<StepInterval> intervals;
  final Color color;
  _StepsPainter(this.intervals, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = intervals.map((v) => v.steps).fold<double>(0, math.max);
    if (maxValue <= 0) return;
    final start = intervals.first.start.millisecondsSinceEpoch;
    final span = intervals.last.end.millisecondsSinceEpoch - start;
    if (span <= 0) return;
    for (final interval in intervals) {
      final x =
          (interval.start.millisecondsSinceEpoch - start) / span * size.width;
      final width =
          (interval.end.difference(interval.start).inMilliseconds /
                      span *
                      size.width -
                  2)
              .clamp(.5, size.width);
      final height = interval.steps / maxValue * size.height;
      if (height <= 0) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - height, width, height),
          const Radius.circular(3),
        ),
        Paint()
          ..color = color.withValues(
            alpha: .52 + .48 * interval.steps / maxValue,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StepsPainter old) =>
      old.intervals != intervals || old.color != color;
}
