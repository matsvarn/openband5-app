// Erste Übertragung — Einrichtung step 2 of 3, between pairing and profile.
//
// The band was just bonded; this screen shows what the first drain has
// already delivered. It never blocks: "Weiter zum Profil" is always enabled —
// a slow first sync is not a reason to trap someone on a progress page.
// The rows only report observed state (connection, transfer, stored
// frontier); there is no progress bar because the domain carries no
// progress value.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../openband/domain.dart';
import '../../openband/local_repository.dart';
import '../../openband/screens.dart' show OBSyncState;
import '../../openband/theme.dart';
import '../../state/app_state.dart';

class FirstSyncScreen extends StatefulWidget {
  final VoidCallback onDone;

  /// Reads the current band snapshot. Defaults to the production
  /// [LocalOpenBandRepository]; tests inject the synthetic fixture.
  final Future<BandSnapshot> Function()? readBand;

  const FirstSyncScreen({super.key, required this.onDone, this.readBand});

  @override
  State<FirstSyncScreen> createState() => _FirstSyncScreenState();
}

class _FirstSyncScreenState extends State<FirstSyncScreen> {
  BandSnapshot _band = const BandSnapshot();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_read()),
    );
    unawaited(_read());
  }

  Future<void> _read() async {
    try {
      final read =
          widget.readBand ??
          () => LocalOpenBandRepository(context.read<AppState>()).readBand();
      final band = await read();
      if (mounted) setState(() => _band = band);
    } catch (_) {
      // A failed status read keeps the last known observation, never a fake.
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = OB.of(c);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(
                title: 'Erste Übertragung',
                subtitle: 'Einrichtung · Schritt 2 von 3',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OBSyncState(band: _band, now: DateTime.now),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  OBCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Das Band erzählt von der letzten Nacht',
                          style: p.text(17, weight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Die Aufzeichnung wandert Stück für Stück aufs '
                          'Telefon. Schlaf, Puls und Belastung erscheinen, '
                          'sobald die Auswertung steht.',
                          style: p.text(15, color: p.muted),
                        ),
                        const SizedBox(height: 16),
                        _StatusRow(
                          label: 'Verbunden',
                          state: _band.connection == BandConnection.connected
                              ? _RowState.done
                              : _RowState.open,
                          trailing: _band.connection == BandConnection.connected
                              ? null
                              : '—',
                        ),
                        _StatusRow(
                          label: 'Nacht wird gelesen',
                          state: _band.transfer == TransferState.receiving
                              ? _RowState.active
                              : _RowState.open,
                          trailing: switch (_band.transfer) {
                            TransferState.receiving =>
                              'bis ${obTime(_band.latestStoredAt)}',
                            TransferState.interrupted => 'Unterbrochen',
                            TransferState.idle =>
                              _band.latestStoredAt == null
                                  ? '—'
                                  : obTime(_band.latestStoredAt),
                          },
                        ),
                        _StatusRow(
                          label: 'Auswertung',
                          state: _band.latestStoredAt == null
                              ? _RowState.open
                              : _RowState.done,
                          trailing: _band.latestStoredAt == null
                              ? '—'
                              : obTime(_band.latestStoredAt),
                          last: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Du kannst schon weiter — die Übertragung läuft im '
                    'Hintergrund zu Ende.',
                    style: p.text(13, color: p.muted),
                  ),
                  const SizedBox(height: 24),
                  OBAction('Weiter zum Profil', onPressed: widget.onDone),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _RowState { open, active, done }

class _StatusRow extends StatelessWidget {
  final String label;
  final _RowState state;
  final String? trailing;
  final bool last;
  const _StatusRow({
    required this.label,
    required this.state,
    this.trailing,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final icon = switch (state) {
      _RowState.done => Icon(LucideIcons.check, size: 16, color: p.recovery),
      _RowState.active => SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: p.action),
      ),
      _RowState.open => Icon(LucideIcons.circle, size: 16, color: p.gap),
    };
    return Semantics(
      label: trailing == null ? label : '$label $trailing',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: last
            ? null
            : BoxDecoration(
                border: Border(bottom: BorderSide(color: p.line)),
              ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: p.text(
                  15,
                  weight: state == _RowState.active
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: state == _RowState.open ? p.muted : p.ink,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: p.text(
                  13,
                  weight: FontWeight.w600,
                  display: true,
                  color: p.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
