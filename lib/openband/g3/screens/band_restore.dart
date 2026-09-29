import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../ui2/onboarding/welcome.dart' show ImportOutcome;
import '../band_parts.dart';
import '../chrome.dart' show OBActionPrimary, OBActionSecondary;
import '../g3_theme.dart';

Future<void> showG3RestoreReceipt(
  BuildContext context,
  ImportOutcome outcome, {
  bool synthetic = false,
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  barrierColor: Colors.black.withValues(alpha: .38),
  backgroundColor: G3.of(context).canvas,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (c) => G3RestoreReceiptSheet(
    outcome: outcome,
    synthetic: synthetic,
    onClose: () => Navigator.pop(c),
  ),
);

class G3RestoreReceiptSheet extends StatelessWidget {
  final ImportOutcome outcome;
  final VoidCallback onClose;
  final bool synthetic;
  const G3RestoreReceiptSheet({
    super.key,
    required this.outcome,
    required this.onClose,
    this.synthetic = false,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final o = outcome;
    final skipped = o.unchangedRows + o.restoreConflicts;
    final rejected = o.unreadableRows;
    final withheld = o.restoreConflicts > 0 || rejected > 0;
    final title = o.restoredRows > 0
        ? withheld
              ? 'Teilweise übernommen'
              : 'Übernommen'
        : withheld
        ? 'Nicht übernommen'
        : 'Unverändert';
    Widget count(String label, int value, {bool divided = false}) => Expanded(
      child: Container(
        padding: EdgeInsets.only(left: divided ? 14 : 0),
        decoration: divided
            ? BoxDecoration(
                border: Border(left: BorderSide(color: g.hairline)),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: g.t(
                11,
                15,
                weight: FontWeight.w700,
                color: g.muted,
                tracking: .08,
              ),
            ),
            Text('$value', style: g.t(22, 27, weight: FontWeight.w700)),
          ],
        ),
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
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: g.muted.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    key: const ValueKey('restore-title'),
                    style: g.t(20, 24, weight: FontWeight.w700, tracking: -.02),
                  ),
                ),
                IconButton(
                  tooltip: 'Schließen',
                  onPressed: onClose,
                  icon: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: g.chip,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(LucideIcons.x, size: 16, color: g.ink),
                  ),
                ),
              ],
            ),
            Text(
              '${o.source}. Deine Daten auf dem iPhone wurden nicht überschrieben.',
              style: g.t(14, 19, color: g.ink2),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                count('Übernommen', o.restoredRows),
                count('Übersprungen', skipped, divided: true),
                count('Abgelehnt', rejected, divided: true),
              ],
            ),
            if (o.unchangedRows > 0 ||
                o.restoreConflicts > 0 ||
                o.unreadableRows > 0 ||
                o.pendingRecalculations > 0) ...[
              const SizedBox(height: 18),
              OBSettingsGroup(
                key: const ValueKey('restore-reasons'),
                inset: true,
                children: [
                  if (o.unchangedRows > 0)
                    OBSettingsRow(
                      label: 'Unverändert',
                      detail: 'schon gleich auf dem iPhone',
                      value: '${o.unchangedRows}',
                    ),
                  if (o.restoreConflicts > 0)
                    OBSettingsRow(
                      label: 'Konflikt',
                      detail: 'lokal behalten',
                      value: '${o.restoreConflicts}',
                    ),
                  if (o.unreadableRows > 0)
                    OBSettingsRow(
                      label: 'Nicht lesbar',
                      detail: 'abgelehnt, nichts geschätzt',
                      value: '${o.unreadableRows}',
                    ),
                  if (o.pendingRecalculations > 0)
                    OBSettingsRow(
                      label: 'Neuberechnung',
                      detail: 'ausstehend',
                      value: '${o.pendingRecalculations}',
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OBActionSecondary(
                    'Details',
                    expand: true,
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      builder: (c) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Wiederherstellung',
                                style: g.t(20, 24, weight: FontWeight.w700),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${o.restoredRows} übernommen · $skipped übersprungen · $rejected abgelehnt',
                                style: g.t(14, 20),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () => Navigator.pop(c),
                                child: const Text('Schließen'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OBActionPrimary(
                    'Fertig',
                    expand: true,
                    onPressed: onClose,
                  ),
                ),
              ],
            ),
            if (synthetic) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'SYNTHETISCHE DATEN',
                  style: g.caps(color: g.muted, size: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
