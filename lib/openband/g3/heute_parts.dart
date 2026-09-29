// Heute-only parts. The shared check-in Baustein asks yes/no questions; the
// G3 check-in stores four 1–5 ratings (kG3CheckInKeys), so Heute renders
// them with this rating row in the same Baustein language.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'chrome.dart' show OBActionSecondary;
import 'g3_theme.dart';

/// Question and end labels for a check-in rating key.
({String question, String low, String high}) heuteRatingCopy(
  String key,
) => switch (key) {
  'mood' => (question: 'Wie ist deine Stimmung?', low: 'schlecht', high: 'gut'),
  'sleep_quality' => (
    question: 'Wie hast du geschlafen?',
    low: 'schlecht',
    high: 'gut',
  ),
  'energy' => (
    question: 'Wie viel Energie hast du?',
    low: 'wenig',
    high: 'viel',
  ),
  'stress' => (question: 'Wie gestresst bist du?', low: 'wenig', high: 'sehr'),
  _ => (question: key, low: '1', high: '5'),
};

/// One rating question (1…[max]) in the check-in card, with the last answer
/// above it. "Später" never penalises.
class OBCheckInRating extends StatelessWidget {
  final String progress;
  final String question, low, high;
  final int max;

  /// The previous answer ("Stimmung: 4 von 5"), with its change action.
  final String? answered;
  final VoidCallback? onChange;
  final ValueChanged<int>? onRate;
  final VoidCallback? onLater;
  const OBCheckInRating({
    super.key,
    required this.progress,
    required this.question,
    required this.low,
    required this.high,
    this.max = 5,
    this.answered,
    this.onChange,
    this.onRate,
    this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
      decoration: g.pressed(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.notebookPen, size: 16, color: g.ink),
              const SizedBox(width: 8),
              Text('CHECK-IN', style: g.caps()),
              const Spacer(),
              Text(
                progress,
                style: g.t(12, 16, weight: FontWeight.w500, color: g.ink2),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (answered != null) ...[
            Row(
              children: [
                Icon(LucideIcons.check, size: 16, color: g.ink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    answered!,
                    style: g.t(14, 18, weight: FontWeight.w500, color: g.ink2),
                  ),
                ),
                if (onChange != null)
                  Semantics(
                    button: true,
                    label: 'Antwort ändern',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onChange,
                      child: SizedBox(
                        height: 44,
                        child: Center(
                          child: Text(
                            'Ändern',
                            style: g.t(13, 16, weight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
          ],
          Text(
            question,
            style: g.t(19, 24, weight: FontWeight.w700, tracking: -.015),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 1; i <= max; i++) ...[
                if (i > 1) const SizedBox(width: 6),
                Expanded(
                  child: Semantics(
                    label: '$question $i von $max',
                    excludeSemantics: true,
                    button: true,
                    child: OBActionSecondary(
                      '$i',
                      height: 40,
                      expand: true,
                      onPressed: onRate == null ? null : () => onRate!(i),
                    ),
                  ),
                ),
              ],
            ],
          ),
          Row(
            children: [
              Text(low, style: g.t(12, 16, color: g.muted)),
              const Spacer(),
              Text(high, style: g.t(12, 16, color: g.muted)),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Semantics(
              button: true,
              label: 'Später',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onLater,
                child: SizedBox(
                  width: 80,
                  height: 44,
                  child: Center(
                    child: Text(
                      'Später',
                      style: g.t(
                        14,
                        18,
                        weight: FontWeight.w500,
                        color: g.ink2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
