import 'package:flutter/material.dart';
import '../../../ui2/onboarding/welcome.dart' show ImportOutcome;
import '../band_parts.dart';
import '../chrome.dart' show OBLink, OBSheet, showOBInfoSheet;
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
  backgroundColor: Colors.transparent,
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
        child: OBSheet(
          title: title,
          subtitle:
              '${o.source}. Deine Daten auf dem iPhone wurden nicht überschrieben.',
          confirmLabel: 'Fertig',
          onConfirm: onClose,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              OBLink(
                'Details',
                onTap: () => showOBInfoSheet(
                  context,
                  title: 'Wiederherstellung',
                  paragraphs: [
                    '${o.restoredRows} übernommen · $skipped übersprungen · $rejected abgelehnt',
                  ],
                ),
              ),
              if (synthetic)
                Center(
                  child: Text(
                    'SYNTHETISCHE DATEN',
                    style: g.caps(color: g.muted, size: 11),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
