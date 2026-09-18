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
    final last = day.stepIntervals.isEmpty ? null : day.stepIntervals.last.end;
    return OBCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: _DayValue(
              label: 'Schritte',
              icon: LucideIcons.footprints,
              color: p.strain,
              value: obNumber(day.steps.value),
              unit: last != null ? 'bis ${obTime(last)}' : null,
              onTap: () => _details(context),
              child: day.stepIntervals.isEmpty
                  ? null
                  : Semantics(
                      label:
                          'Schritteverlauf: ${day.stepIntervals.map((s) => '${obTime(s.start)} bis ${obTime(s.end)}, ${obNumber(s.steps)} Schritte').join('. ')}',
                      child: SizedBox(
                        height: 24,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _StepsPainter(day.stepIntervals, p.strain),
                        ),
                      ),
                    ),
            ),
          ),
          Expanded(
            flex: 2,
            child: _DayValue(
              label: 'Wasser',
              icon: LucideIcons.droplet,
              color: p.sleep,
              value: day.intake.waterMl == null
                  ? '—'
                  : obNumber(day.intake.waterMl! / 1000, digits: 2),
              unit: day.intake.waterMl == null ? null : 'l',
              onTap: () => _details(context, intake: true),
            ),
          ),
          Expanded(
            flex: 2,
            child: _DayValue(
              label: 'Energie',
              icon: LucideIcons.utensils,
              color: p.food,
              value: obNumber(day.intake.kcal),
              unit: day.intake.kcal == null ? null : 'kcal',
              onTap: () => _details(context, intake: true),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayValue extends StatelessWidget {
  final String label, value;
  final String? unit;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final Widget? child;
  const _DayValue({
    required this.label,
    required this.value,
    this.unit,
    required this.icon,
    required this.color,
    required this.onTap,
    this.child,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Semantics(
      button: true,
      label: '$label $value ${unit ?? ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        label,
                        style: p.text(
                          12,
                          weight: FontWeight.w600,
                          color: p.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 4,
                  children: [
                    Text(
                      value,
                      style: p.text(22, weight: FontWeight.w800, display: true),
                    ),
                    if (unit != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          unit!,
                          style: p.text(
                            12,
                            weight: FontWeight.w500,
                            color: p.muted,
                          ),
                        ),
                      ),
                  ],
                ),
                ?child,
              ],
            ),
          ),
        ),
      ),
    );
  }
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
