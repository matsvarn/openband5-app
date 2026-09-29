import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../ui2/onboarding/welcome.dart' show ImportOutcome;
import '../band_parts.dart';
import '../g3_theme.dart';

Future<void> showG3RestoreReceipt(
  BuildContext context,
  ImportOutcome outcome,
) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  barrierColor: Colors.black.withValues(alpha: .38),
  backgroundColor: G3.of(context).canvas,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (c) =>
      G3RestoreReceiptSheet(outcome: outcome, onClose: () => Navigator.pop(c)),
);

class G3RestoreReceiptSheet extends StatelessWidget {
  final ImportOutcome outcome;
  final VoidCallback onClose;
  const G3RestoreReceiptSheet({
    super.key,
    required this.outcome,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final o = outcome;
    final skipped = o.unchangedRows + o.restoreConflicts;
    final rejected = o.unreadableRows;
    Widget count(String label, int value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: g.caps(color: g.muted)),
          Text('$value', style: g.t(27, 32, weight: FontWeight.w700)),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: g.muted.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Teilweise übernommen',
                    style: g.t(24, 29, weight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Schließen',
                  onPressed: onClose,
                  icon: const Icon(LucideIcons.x),
                ),
              ],
            ),
            Text(
              'Deine vorhandenen Daten wurden nicht überschrieben.',
              style: g.t(13, 19, color: g.muted),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                count('ÜBERNOMMEN', o.restoredRows),
                count('ÜBERSPRUNGEN', skipped),
                count('ABGELEHNT', rejected),
              ],
            ),
            const SizedBox(height: 18),
            OBSettingsGroup(
              children: [
                if (o.unchangedRows > 0)
                  OBSettingsRow(
                    label: 'Unverändert',
                    detail: 'Schon gleich auf dem iPhone',
                    value: '${o.unchangedRows}',
                  ),
                if (o.restoreConflicts > 0)
                  OBSettingsRow(
                    label: 'Konflikt',
                    detail: 'Lokaler Stand behalten',
                    value: '${o.restoreConflicts}',
                  ),
                if (o.unreadableRows > 0)
                  OBSettingsRow(
                    label: 'Nicht lesbar',
                    detail: 'Abgelehnt, nichts geschätzt',
                    value: '${o.unreadableRows}',
                  ),
                if (o.pendingRecalculations > 0)
                  OBSettingsRow(
                    label: 'Neuberechnung',
                    detail: 'Noch ausstehend',
                    value: '${o.pendingRecalculations}',
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onClose,
              style: FilledButton.styleFrom(
                backgroundColor: g.ink,
                foregroundColor: g.onInk,
                minimumSize: const Size(44, 52),
              ),
              child: const Text('Fertig'),
            ),
          ],
        ),
      ),
    );
  }
}
