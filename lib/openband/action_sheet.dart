import 'package:flutter/material.dart';

import 'domain.dart';
import 'theme.dart';

class OpenBandSheetAction<T> {
  const OpenBandSheetAction(this.label, this.value, {this.danger = false});
  final String label;
  final T value;
  final bool danger;
}

enum AddExerciseChoice { library, custom, customTimed }

Future<T?> showOpenBandActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<OpenBandSheetAction<T>> actions,
}) {
  final p = OB.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (c) {
      final sheet = OB.of(c);
      Widget action(OpenBandSheetAction<T> item) => InkWell(
        onTap: () => Navigator.pop(c, item.value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              item.label,
              style: sheet
                  .text(15, color: item.danger ? sheet.danger : sheet.ink)
                  .copyWith(height: 20 / 15),
            ),
          ),
        ),
      );
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(c).height * 0.7,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: sheet
                      .text(18, weight: FontWeight.w600)
                      .copyWith(height: 24 / 18),
                ),
                const SizedBox(height: 12),
                for (final item in actions) action(item),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<TemplateMenuChoice?> showTemplateActionSheet(
  BuildContext context, {
  required WorkoutTemplate template,
  required bool pinned,
}) {
  return showOpenBandActionSheet<TemplateMenuChoice>(
    context,
    title: template.name,
    actions: [
      const OpenBandSheetAction('Bearbeiten', TemplateMenuChoice.edit),
      const OpenBandSheetAction('Duplizieren', TemplateMenuChoice.duplicate),
      OpenBandSheetAction(
        pinned ? 'Nicht mehr anheften' : 'Anheften',
        pinned ? TemplateMenuChoice.unpin : TemplateMenuChoice.pin,
      ),
      const OpenBandSheetAction(
        'Archivieren',
        TemplateMenuChoice.archive,
        danger: true,
      ),
    ],
  );
}

Future<AddExerciseChoice?> showAddExerciseSheet(BuildContext context) {
  return showOpenBandActionSheet<AddExerciseChoice>(
    context,
    title: 'Übung hinzufügen',
    actions: const [
      OpenBandSheetAction('Bibliothek', AddExerciseChoice.library),
      OpenBandSheetAction('Eigene Übung', AddExerciseChoice.custom),
      OpenBandSheetAction('Eigene Zeitübung', AddExerciseChoice.customTimed),
    ],
  );
}
