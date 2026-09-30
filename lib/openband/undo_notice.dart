import 'package:flutter/material.dart';

import 'alp_tokens.dart';
import 'theme.dart';

/// Floating Alpin undo notice (Paper 41M7-0; large 438J-0, dark 43C9-0).
void showOpenBandUndoNotice({
  required BuildContext context,
  required ScaffoldMessengerState messenger,
  required String message,
  required String primaryLabel,
  required VoidCallback onPrimary,
  String? secondaryLabel,
  VoidCallback? onSecondary,
}) {
  final p = OB.of(context);
  final inverse = p.dark ? p.canvas : AlpColor.canvas;
  final bottom = 16.0 + MediaQuery.paddingOf(context).bottom;
  final largeText = MediaQuery.textScalerOf(context).scale(15) > 20;
  TextButton actionButton(String label, VoidCallback onPressed) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: inverse,
      minimumSize: const Size(44, 44),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    child: Text(
      label,
      style: p
          .text(15, weight: FontWeight.w600, color: inverse)
          .copyWith(height: 20 / 15),
    ),
  );
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      elevation: 0,
      duration: const Duration(seconds: 8),
      dismissDirection: DismissDirection.none,
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottom),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: largeText
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    message,
                    style: p.text(15, color: inverse).copyWith(height: 20 / 15),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      actionButton(primaryLabel, onPrimary),
                      if (secondaryLabel != null && onSecondary != null)
                        actionButton(secondaryLabel, onSecondary),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: p
                          .text(15, color: inverse)
                          .copyWith(height: 20 / 15),
                    ),
                  ),
                  actionButton(primaryLabel, onPrimary),
                  if (secondaryLabel != null && onSecondary != null)
                    actionButton(secondaryLabel, onSecondary),
                ],
              ),
      ),
    ),
  );
}
