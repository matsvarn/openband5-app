import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
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
    final p = P.of(context);
    final l = AppLocalizations.of(context);
    final label = l?.profileBirthDateLabel ?? 'Birth date';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: F.over.copyWith(color: p.ink3)),
        Row(
          children: [
            Expanded(
              child: Pressable(
                semanticLabel: label,
                onTap: () => _pick(context),
                child: Container(
                  constraints: const BoxConstraints(minHeight: S.tap),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(vertical: S.x3),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: p.line)),
                  ),
                  child: Text(
                    value == null
                        ? l?.profileBirthDateSelect ?? 'Select birth date'
                        : MaterialLocalizations.of(
                            context,
                          ).formatCompactDate(value!),
                    style: F.head.copyWith(
                      color: value == null ? p.ink3 : p.ink,
                    ),
                  ),
                ),
              ),
            ),
            if (value != null)
              IconButton(
                tooltip: l?.profileBirthDateClear ?? 'Clear birth date',
                onPressed: () => onChanged(null),
                icon: Icon(LucideIcons.x, color: p.ink3),
              ),
          ],
        ),
        const SizedBox(height: S.x1),
        Text(
          l?.profileBirthDateHelp ??
              'Your age is calculated for each recording. Leave this blank to keep age-dependent estimates unavailable.',
          style: F.cap.copyWith(color: p.ink3),
        ),
      ],
    );
  }
}
