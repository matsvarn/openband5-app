import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../openband/g3/g3_theme.dart';
import '../ui2.dart';

class BirthDateField extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  const BirthDateField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  Future<void> _pick(BuildContext context) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: value != null && !value!.isAfter(today) ? value : null,
      firstDate: value != null && value!.year < 1900 ? value! : DateTime(1900),
      lastDate: today,
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null && context.mounted) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final l = AppLocalizations.of(context);
    final label = l?.profileBirthDateLabel ?? 'Birth date';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: g.caps(color: g.muted)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Pressable(
                semanticLabel: label,
                onTap: () => _pick(context),
                child: Container(
                  constraints: const BoxConstraints(minHeight: S.tap),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: g.pressed(radius: 14),
                  child: Text(
                    value == null
                        ? l?.profileBirthDateSelect ?? 'Select birth date'
                        : MaterialLocalizations.of(
                            context,
                          ).formatCompactDate(value!),
                    style: g.t(17, 22, color: value == null ? g.muted : g.ink),
                  ),
                ),
              ),
            ),
            if (value != null)
              IconButton(
                tooltip: l?.profileBirthDateClear ?? 'Clear birth date',
                onPressed: () => onChanged(null),
                icon: Icon(LucideIcons.x, color: g.muted),
              ),
          ],
        ),
        const SizedBox(height: S.x1),
        Text(
          l?.profileBirthDateHelp ??
              'Your age is calculated for each recording. Leave this blank to keep age-dependent estimates unavailable.',
          style: g.t(13, 18, color: g.muted),
        ),
      ],
    );
  }
}
