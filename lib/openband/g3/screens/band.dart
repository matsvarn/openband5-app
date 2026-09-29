import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain.dart';
import '../../theme.dart' show obTime;
import '../band_parts.dart';
import '../g3_theme.dart';

/// Band facts that the current read model can actually establish.
class G3BandScreen extends StatelessWidget {
  final BandSnapshot? band;
  final DateTime now;
  final String? databaseSize;
  final VoidCallback? onDevices;
  final VoidCallback? onBack;

  const G3BandScreen({
    super.key,
    required this.band,
    required this.now,
    this.databaseSize,
    this.onDevices,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final b = band;
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                    icon: const Icon(LucideIcons.chevronLeft),
                    label: const Text('Heute'),
                    style: TextButton.styleFrom(
                      foregroundColor: g.ink,
                      minimumSize: const Size(44, 44),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text('BAND', style: g.caps()),
                        Text('WHOOP 5.0', style: g.t(13, 18, color: g.muted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 70),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                children: [
                  if (b == null)
                    OBSettingsGroup(
                      children: [
                        OBSettingsRow(
                          label: 'Bandstatus —',
                          detail: 'Noch kein Bandstatus geladen.',
                          onTap: onDevices,
                        ),
                      ],
                    )
                  else
                    OBBandHero(band: b, now: now),
                  if (b?.transfer == TransferState.receiving ||
                      b?.transfer == TransferState.interrupted) ...[
                    const SizedBox(height: 12),
                    OBSettingsGroup(
                      children: [
                        OBSettingsRow(
                          label: b!.transfer == TransferState.receiving
                              ? 'Übertragung läuft'
                              : 'Übertragung unterbrochen',
                          detail: b.transfer == TransferState.receiving
                              ? 'Gespeichertes bleibt auf dem iPhone. Keine Fortschrittsangabe verfügbar.'
                              : 'Bereits gespeicherte Abschnitte bleiben erhalten.',
                          onTap: onDevices,
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('GERÄT', style: g.caps(color: g.muted)),
                  const SizedBox(height: 8),
                  OBSettingsGroup(
                    children: [
                      const OBSettingsRow(label: 'Modell', value: 'WHOOP 5.0'),
                      const OBSettingsRow(label: 'Firmware', value: '—'),
                      OBSettingsRow(
                        label: 'Datenbankdatei',
                        value: databaseSize ?? '—',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (onDevices != null) ...[
                    Text('AM BAND', style: g.caps(color: g.muted)),
                    const SizedBox(height: 8),
                    OBSettingsGroup(
                      children: [
                        OBSettingsRow(
                          label: 'Band verwalten',
                          detail: 'Alarm, Akkumeldung und Kopplung',
                          onTap: onDevices,
                        ),
                      ],
                    ),
                  ],
                  if (b != null) ...[
                    const SizedBox(height: 22),
                    Center(
                      child: Text(
                        'Letzter gespeicherter Wert ${obTime(b.latestStoredAt)} · Empfang ${obTime(b.receivedAt)}',
                        textAlign: TextAlign.center,
                        style: g.t(12, 17, color: g.muted),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
