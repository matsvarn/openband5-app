import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'alp_tokens.dart';
import 'theme.dart';

/// Compact Alpin confirm sheet (Paper 3SL4): title, close, ink confirm,
/// well cancel. Close and cancel keep the current work.
Future<bool?> showOpenBandConfirmSheet({
  required BuildContext context,
  required String title,
  String confirmLabel = 'Verwerfen',
  String cancelLabel = 'Weiter bearbeiten',
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (context) => OpenBandConfirmSheet(
      title: title,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
}

class OpenBandConfirmSheet extends StatelessWidget {
  final String title;
  final String confirmLabel;
  final String cancelLabel;
  const OpenBandConfirmSheet({
    super.key,
    required this.title,
    this.confirmLabel = 'Verwerfen',
    this.cancelLabel = 'Weiter bearbeiten',
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    Widget action({
      required String label,
      required Color background,
      required Color foreground,
      required VoidCallback onPressed,
      Key? key,
    }) {
      final style = p
          .text(15, weight: FontWeight.w600)
          .copyWith(height: 20 / 15, color: foreground);
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: key,
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: style,
          ),
          child: Text(label, textAlign: TextAlign.center, style: style),
        ),
      );
    }

    return Material(
      color: p.card,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AlpRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
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
                      onPressed: () => Navigator.pop(context, false),
                      padding: EdgeInsets.zero,
                      icon: Icon(LucideIcons.x, size: 20, color: p.ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            action(
              key: const ValueKey('ob-confirm-yes'),
              label: confirmLabel,
              background: p.ink,
              foreground: p.dark ? p.canvas : AlpColor.canvas,
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 12),
            action(
              key: const ValueKey('ob-confirm-no'),
              label: cancelLabel,
              background: p.well,
              foreground: p.ink,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
  }
}
