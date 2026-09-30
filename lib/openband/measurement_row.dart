import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'alp_tokens.dart';
import 'theme.dart';

/// Canonical measurement row (Paper 3LIU-0): label + date leading, value +
/// unit trailing, chevron. Stacks at large text or a narrow width instead of
/// shrinking type.
class OBMeasurementRow extends StatelessWidget {
  final String label, date, value, unit;
  final VoidCallback? onTap;
  final String? semanticLabel;
  const OBMeasurementRow({
    super.key,
    required this.label,
    required this.date,
    required this.value,
    required this.unit,
    this.onTap,
    this.semanticLabel,
  });

  static bool stacks(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(17) > 22 ||
      MediaQuery.sizeOf(context).width < 360;

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked = stacks(context);
    final leading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text(
          label,
          style: p.text(17, weight: FontWeight.w600).copyWith(height: 22 / 17),
        ),
        Text(
          date,
          style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
        ),
      ],
    );
    final trailing = Column(
      crossAxisAlignment: stacked
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      spacing: 4,
      children: [
        Text(
          value,
          style: p.text(20, weight: FontWeight.w600).copyWith(height: 24 / 20),
        ),
        Text(
          unit,
          style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
        ),
      ],
    );
    final chevron = Icon(LucideIcons.chevronRight, size: 16, color: p.gap);
    final body = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: trailing),
                  chevron,
                ],
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: leading),
              const SizedBox(width: 12),
              SizedBox(width: 94, child: trailing),
              const SizedBox(width: 12),
              chevron,
            ],
          );
    return Semantics(
      button: onTap != null,
      label: semanticLabel ?? '$label, $date, $value $unit',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AlpRadius.card),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: body,
          ),
        ),
      ),
    );
  }
}
