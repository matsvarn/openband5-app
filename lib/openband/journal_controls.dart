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

void showOpenBandJournalInfo(
  BuildContext context, {
  required String title,
  required String body,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x52000000),
    elevation: 0,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _OpenBandInfoSheet(title: title, body: body),
  );
}

class _OpenBandInfoSheet extends StatelessWidget {
  final String title;
  final String body;
  const _OpenBandInfoSheet({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final media = MediaQuery.of(context);
    final paragraphs = body
        .split(RegExp(r'\r?\n+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
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
            child: CustomScrollView(
              shrinkWrap: true,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    media.viewPadding.bottom > 12
                        ? media.viewPadding.bottom
                        : 12,
                  ),
                  sliver: SliverToBoxAdapter(
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
                        for (final paragraph in paragraphs) ...[
                          const SizedBox(height: 12),
                          Text(
                            paragraph,
                            style: p.text(15).copyWith(height: 22 / 15),
                          ),
                        ],
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
              ],
            ),
          ),
        );
      },
    );
  }
}
