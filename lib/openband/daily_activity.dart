import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../data/day_label.dart';
import 'domain.dart';
import 'alp_tokens.dart';
import 'theme.dart';

class StepsCard extends StatelessWidget {
  final OpenBandDay day;
  final DateTime Function() now;
  final VoidCallback? onNutrition;
  final bool showIntake;
  const StepsCard({
    super.key,
    required this.day,
    required this.now,
    this.onNutrition,
    this.showIntake = true,
  });

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
                  '${obNumber(day.intake.kcal)} kcal erfasst',
                  style: p.text(24, weight: FontWeight.w600),
                ),
                if (day.intake.kcalIsFloor) ...[
                  const SizedBox(height: 8),
                  Text('Teilweise', style: p.text(13, color: p.muted)),
                ],
                const SizedBox(height: 12),
                Text(
                  '${obNumber(day.intake.waterMl)} ml Wasser erfasst',
                  style: p.text(18),
                ),
                if (onNutrition != null) ...[
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
                  const Text('Kein Stundenverlauf.')
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
    if (!showIntake) {
      return _ReleaseStepsCard(
        day: day,
        now: now,
        onOpen: () => _details(context),
      );
    }
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
                  : Builder(
                      builder: (context) {
                        final buckets = stepsByHour(day.stepIntervals);
                        return Semantics(
                          label:
                              'Schritteverlauf: ${buckets.indexed.where((e) => e.$2 > 0).map((e) => '${e.$1.toString().padLeft(2, '0')}:00 ${obNumber(e.$2.round())} Schritte').join(', ')}',
                          child: SizedBox(
                            height: 40,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _StepsPainter(
                                buckets,
                                day.day == todayLabel() ? now().hour : 23,
                                p.strain,
                                p.strainTint,
                                p.line,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          if (showIntake)
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
          if (showIntake)
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

/// Paper G2 Schritte card: spaced label over the count, 24 hourly bars at
/// the right — ink where steps were counted, grey stubs for recorded empty
/// hours, pale stubs for hours not yet reached.
class _ReleaseStepsCard extends StatelessWidget {
  final OpenBandDay day;
  final DateTime Function() now;
  final VoidCallback onOpen;
  const _ReleaseStepsCard({
    required this.day,
    required this.now,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final buckets = day.stepIntervals.isEmpty
        ? const <double>[]
        : stepsByHour(day.stepIntervals);
    final last = day.stepIntervals.isEmpty ? null : day.stepIntervals.last.end;
    final reached = day.day == todayLabel() ? (last?.hour ?? now().hour) : 23;
    return Semantics(
      button: true,
      label:
          'Schritte ${obNumber(day.steps.value)}${last == null ? '' : ' bis ${obTime(last)}'}',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(AlpRadius.card),
          child: ExcludeSemantics(
            child: OBCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: 4,
                      children: [
                        Text(
                          'SCHRITTE',
                          style: p.label(size: 11).copyWith(height: 14 / 11),
                        ),
                        Text(
                          obNumber(day.steps.value),
                          style: p
                              .text(
                                28,
                                weight: FontWeight.w700,
                                color: day.steps.value == null ? p.gap : p.ink,
                              )
                              .copyWith(height: 34 / 28, letterSpacing: -.56),
                        ),
                      ],
                    ),
                  ),
                  if (buckets.isNotEmpty)
                    SizedBox(
                      width: 120,
                      height: 36,
                      child: CustomPaint(
                        painter: _HourBarsPainter(p, buckets, reached),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HourBarsPainter extends CustomPainter {
  final OB p;
  final List<double> buckets;
  final int reached;
  _HourBarsPainter(this.p, this.buckets, this.reached);
  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = buckets.fold<double>(0, math.max);
    final pitch = size.width / 24, w = pitch * .6;
    for (var h = 0; h < 24; h++) {
      final v = buckets[h];
      final height = v > 0 && maxValue > 0
          ? math.max(5.0, size.height * v / maxValue)
          : 3.0;
      final color = v > 0 ? p.ink : (h <= reached ? p.gap : p.inset);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(h * pitch, size.height - height, w, height),
          const Radius.circular(1),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_HourBarsPainter old) =>
      old.buckets != buckets || old.reached != reached || old.p.dark != p.dark;
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

/// Splits [StepInterval]s into 24 local hour buckets; an interval crossing an
/// hour boundary contributes to each hour proportionally to its overlap.
List<double> stepsByHour(List<StepInterval> intervals) {
  final hours = List<double>.filled(24, 0);
  for (final s in intervals) {
    final totalMs = s.end.difference(s.start).inMilliseconds;
    if (totalMs <= 0) continue;
    var start = s.start;
    while (start.isBefore(s.end)) {
      final hourEnd = DateTime(
        start.year,
        start.month,
        start.day,
        start.hour + 1,
      );
      final sliceEnd = hourEnd.isBefore(s.end) ? hourEnd : s.end;
      hours[start.hour] +=
          s.steps * sliceEnd.difference(start).inMilliseconds / totalMs;
      start = sliceEnd;
    }
  }
  return hours;
}

class _StepsPainter extends CustomPainter {
  final List<double> buckets;
  final int currentHour;
  final Color color, tint, line;
  _StepsPainter(
    this.buckets,
    this.currentHour,
    this.color,
    this.tint,
    this.line,
  );
  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = buckets.fold<double>(0, math.max);
    const gap = 3.0;
    final width = (size.width - 23 * gap) / 24;
    for (var h = 0; h < 24; h++) {
      final v = buckets[h];
      final (height, paint) = v > 0
          ? (math.max(4.0, size.height * v / maxValue), Paint()..color = color)
          : (3.0, Paint()..color = h <= currentHour ? tint : line);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(h * (width + gap), size.height - height, width, height),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StepsPainter old) =>
      old.buckets != buckets ||
      old.currentHour != currentHour ||
      old.color != color ||
      old.tint != tint ||
      old.line != line;
}
