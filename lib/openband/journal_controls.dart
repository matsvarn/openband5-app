import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'alp_tokens.dart';
import 'theme.dart';

const kJournalMoodLabels = ['Erschöpft', 'Müde', 'Okay', 'Gut', 'Sehr gut'];

const kJournalMoodIcons = [
  LucideIcons.frown,
  LucideIcons.annoyed,
  LucideIcons.meh,
  LucideIcons.smile,
  LucideIcons.laugh,
];

/// Canonical 3G8T mood scale: 52pt wells, Lucide faces, ink selection.
class OBJournalMoodScale extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  final String semanticPrefix;
  const OBJournalMoodScale({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticPrefix = 'Stimmung',
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Row(
      spacing: 8,
      children: [
        for (var i = 1; i <= 5; i++)
          Expanded(
            child: Semantics(
              button: true,
              selected: value == i,
              label: '$semanticPrefix ${kJournalMoodLabels[i - 1]}',
              child: InkWell(
                onTap: () => onChanged(value == i ? null : i),
                borderRadius: BorderRadius.circular(14),
                child: ExcludeSemantics(
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == i ? p.ink : p.well,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      kJournalMoodIcons[i - 1],
                      size: 24,
                      color: value == i ? p.card : p.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Canonical yes/no: unknown is unselected; tapping the selection clears it.
/// Parent owns thin separators. 32 food-tint wells, 16 food stroke, 32/44 pills.
class OBJournalYesNo extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool? value;
  final ValueChanged<bool?> onChanged;
  final bool enabled;
  final bool hiddenDraft;
  const OBJournalYesNo({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.hiddenDraft = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked =
        MediaQuery.textScalerOf(context).scale(15) > 20 ||
        MediaQuery.sizeOf(context).width < 360;
    final line = MediaQuery.textScalerOf(context).scale(18);
    final visualHeight = stacked ? (line > 32 ? line : 32.0) : 32.0;
    final hitHeight = stacked
        ? (visualHeight > 44 ? visualHeight : 44.0)
        : 44.0;
    Widget pill(String text, bool yes) {
      final selected = value == yes;
      return Semantics(
        button: true,
        selected: selected,
        label: '$label: $text',
        child: InkWell(
          onTap: enabled ? () => onChanged(selected ? null : yes) : null,
          customBorder: const StadiumBorder(),
          child: ExcludeSemantics(
            child: SizedBox(
              height: hitHeight,
              child: Center(
                child: Container(
                  key: yes ? const ValueKey('journal-yesno-capsule') : null,
                  height: visualHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? p.ink : p.well,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    text,
                    style: p
                        .text(
                          13,
                          weight: FontWeight.w600,
                          color: selected ? p.card : p.ink,
                        )
                        .copyWith(height: 18 / 13),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final iconWell = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.foodTint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 16, color: p.food),
    );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: p.text(15, weight: FontWeight.w500)),
        if (hiddenDraft)
          Text('Ausgeblendet', style: p.text(12, color: p.muted)),
      ],
    );
    final pills = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pill('Ja', true),
        const SizedBox(width: 6),
        pill('Nein', false),
      ],
    );
    return stacked
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    iconWell,
                    const SizedBox(width: 12),
                    Expanded(child: title),
                  ],
                ),
                const SizedBox(height: 8),
                pills,
              ],
            ),
          )
        : SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  iconWell,
                  const SizedBox(width: 12),
                  Expanded(child: title),
                  pills,
                ],
              ),
            ),
          );
  }
}

/// Alpin journal/filter pill. Shrink-wraps to the label so a Wrap can
/// place several chips on one row; long labels wrap instead of overflowing.
class OBJournalChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const OBJournalChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Material(
      color: selected ? p.ink : p.well,
      borderRadius: BorderRadius.circular(AlpRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Align(
              alignment: Alignment.center,
              widthFactor: 1,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: p
                    .text(14)
                    .copyWith(
                      height: 19 / 14,
                      color: selected ? p.card : p.ink,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OBInfoSheetAction {
  const OBInfoSheetAction({required this.id, required this.label});
  final Object id;
  final String label;
}

Future<Object?> showOpenBandJournalInfo(
  BuildContext context, {
  required String title,
  required String body,
  List<OBInfoSheetAction> actions = const [],
}) {
  return showModalBottomSheet<Object>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x52000000),
    elevation: 0,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _OpenBandInfoSheet(
      title: title,
      body: body,
      actions: actions,
    ),
  );
}

class _OpenBandInfoSheet extends StatelessWidget {
  final String title;
  final String body;
  final List<OBInfoSheetAction> actions;
  const _OpenBandInfoSheet({
    required this.title,
    required this.body,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final media = MediaQuery.of(context);
    final paragraphs = body
        .split(RegExp(r'\r?\n+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final safeBottom = media.viewPadding.bottom > media.padding.bottom
        ? media.viewPadding.bottom
        : media.padding.bottom;
    final bottom = safeBottom > 12 ? safeBottom : 12.0;
    final opsz = MediaQuery.textScalerOf(context).scale(15).clamp(14.0, 32.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Material(
          color: p.card,
          elevation: 0,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AlpRadius.card),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: p
                                .text(18, weight: FontWeight.w600)
                                .copyWith(height: 24 / 18),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: IconButton(
                            tooltip: 'Schließen',
                            onPressed: () => Navigator.pop(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 44,
                              height: 44,
                            ),
                            icon: Icon(
                              LucideIcons.x,
                              size: 20,
                              color: p.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: CustomScrollView(
                        key: const ValueKey('journal-info-body'),
                        shrinkWrap: true,
                        slivers: [
                          SliverToBoxAdapter(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final (i, paragraph)
                                    in paragraphs.indexed) ...[
                                  if (i > 0) const SizedBox(height: 12),
                                  Text(
                                    paragraph,
                                    style: p
                                        .text(15)
                                        .copyWith(
                                          height: 22 / 15,
                                          fontVariations: [
                                            FontVariation('opsz', opsz),
                                          ],
                                        ),
                                  ),
                                ],
                                for (final action in actions) ...[
                                  const SizedBox(height: 12),
                                  OBAction(
                                    action.label,
                                    secondary: true,
                                    ink: true,
                                    onPressed: () => Navigator.pop(
                                      context,
                                      action.id,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OBAction(
                    'Schließen',
                    ink: true,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
