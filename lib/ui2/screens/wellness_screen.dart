import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ui2.dart';

/// A label and a sentence. Used by journal findings and habit effects, both of
/// which genuinely have only those two things.
///
/// It is NOT the readiness driver row any more — that claim ("the glass box
/// does not emit per-driver point contributions") was wrong, and it is what
/// kept "What charged and drained you" printing two bare words. The breakdown
/// carries a weight, a signed contribution and a spread gate per input, and
/// the baselines block carries the reading, the centre, the spread and the MDC.
/// See [DriverBreakdown].
class DriverRow extends StatelessWidget {
  const DriverRow({super.key, required this.label, required this.detail});

  final String label, detail;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.dot, size: 18, color: p.on(C.domMind)),
          const SizedBox(width: S.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: F.body.copyWith(color: p.ink)),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: F.over.copyWith(color: p.ink3, height: 1.4),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
