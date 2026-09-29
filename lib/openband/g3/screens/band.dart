import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../ble/band_status_l10n.dart' show localizedBandStatus;
import '../../../ble/ble_state.dart' show BandCondition, BandStatus;
import '../../domain.dart';
import '../../theme.dart' show obTime;
import '../band_parts.dart';
import '../chrome.dart' as chrome;
import '../g3_theme.dart';

/// A read-only view of the latest band observation. Production injects the
/// existing AppState notifier and repository read; no BLE work happens here.
BandStatus? bandIssueFor(BandStatus status) => status.isFault ? status : null;

class G3BandScreen extends StatefulWidget {
  final BandSnapshot? band;
  final DateTime now;
  final DateTime Function()? clock;
  final Listenable? bandUpdates;
  final Future<BandSnapshot> Function()? readBand;
  final BandDiagnostics? diagnostics;
  final Future<BandDiagnostics> Function()? readDiagnostics;
  final String? deviceName;
  final String? databaseSize;
  final Future<void> Function()? onDevices;
  final Future<void> Function()? onReconnect;
  final VoidCallback? onStatus;
  final VoidCallback? onBack;
  final OBBandIssue? issue;
  final OBBandIssue? Function()? readIssue;
  final BandStatus? status;
  final BandStatus? Function()? readStatus;
  final bool synthetic;

  const G3BandScreen({
    super.key,
    required this.band,
    required this.now,
    this.clock,
    this.bandUpdates,
    this.readBand,
    this.diagnostics,
    this.readDiagnostics,
    this.deviceName,
    this.databaseSize,
    this.onDevices,
    this.onReconnect,
    this.onStatus,
    this.onBack,
    this.issue,
    this.readIssue,
    this.status,
    this.readStatus,
    this.synthetic = false,
  });

  @override
  State<G3BandScreen> createState() => _G3BandScreenState();
}

class _G3BandScreenState extends State<G3BandScreen> {
  BandSnapshot? _band;
  BandDiagnostics? _diagnostics;
  OBBandIssue? _issue;
  BandStatus? _status;
  late DateTime _now;
  Timer? _clockTick;
  int _readVersion = 0;

  @override
  void initState() {
    super.initState();
    _band = widget.band;
    _diagnostics = widget.diagnostics;
    _issue = widget.readIssue?.call() ?? widget.issue;
    _status = widget.readStatus?.call() ?? widget.status;
    _now = widget.now;
    widget.bandUpdates?.addListener(_refreshBand);
    if (widget.clock != null) {
      _now = widget.clock!();
      _clockTick = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() => _now = widget.clock!());
      });
    }
    unawaited(_refreshBand());
  }

  @override
  void didUpdateWidget(G3BandScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bandUpdates != widget.bandUpdates) {
      oldWidget.bandUpdates?.removeListener(_refreshBand);
      widget.bandUpdates?.addListener(_refreshBand);
    }
    if (oldWidget.band != widget.band) _band = widget.band;
    if (oldWidget.diagnostics != widget.diagnostics) {
      _diagnostics = widget.diagnostics;
    }
    if (oldWidget.issue != widget.issue ||
        oldWidget.readIssue != widget.readIssue) {
      _issue = widget.readIssue?.call() ?? widget.issue;
    }
    if (oldWidget.status != widget.status ||
        oldWidget.readStatus != widget.readStatus) {
      _status = widget.readStatus?.call() ?? widget.status;
    }
    if (oldWidget.clock != widget.clock) {
      _clockTick?.cancel();
      _clockTick = widget.clock == null
          ? null
          : Timer.periodic(const Duration(minutes: 1), (_) {
              if (mounted) setState(() => _now = widget.clock!());
            });
    }
  }

  Future<void> _refreshBand() async {
    final issue = widget.readIssue?.call();
    if (mounted && widget.readIssue != null && issue != _issue) {
      setState(() => _issue = issue);
    }
    final status = widget.readStatus?.call();
    if (mounted && widget.readStatus != null && status != _status) {
      setState(() => _status = status);
    }
    final version = ++_readVersion;
    final readBand = widget.readBand;
    if (readBand != null) {
      try {
        final observed = await readBand();
        if (mounted && version == _readVersion) {
          setState(() {
            _band = observed;
            _now = widget.clock?.call() ?? _now;
          });
        }
      } catch (_) {
        // A failed read leaves the previous observation visible, with its time.
      }
    }
    final readDiagnostics = widget.readDiagnostics;
    if (readDiagnostics != null) {
      try {
        final observed = await readDiagnostics();
        if (mounted && version == _readVersion) {
          setState(() => _diagnostics = observed);
        }
      } catch (_) {
        // Keep the last observed, timestamped facts when this read fails.
      }
    }
  }

  Future<void> _openDevices() async {
    await widget.onDevices?.call();
    if (mounted) await _refreshBand();
  }

  Future<void> _reconnect() async {
    await widget.onReconnect?.call();
    if (mounted) await _refreshBand();
  }

  void _help() {
    final fault = _status == null ? null : bandIssueFor(_status!);
    final localized = fault == null
        ? null
        : localizedBandStatus(context, fault);
    final issue = _issue;
    final title =
        localized?.title ??
        switch (issue) {
          OBBandIssue.bluetoothOff => 'Bluetooth ist ausgeschaltet',
          null => 'Band nicht verbunden',
        };
    final text = localized == null
        ? switch (issue) {
            OBBandIssue.bluetoothOff =>
              'Bluetooth in den iPhone-Einstellungen einschalten und zur App zurückkehren.',
            null =>
              'Band näher ans iPhone bringen und die Verbindung erneut versuchen.',
          }
        : [localized.reason, ?localized.fix].join('\n\n');
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: G3.of(c).t(20, 24, weight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(text, style: G3.of(c).t(14, 20)),
              const SizedBox(height: 18),
              chrome.OBActionSecondary(
                'Schließen',
                onPressed: () => Navigator.pop(c),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    ++_readVersion;
    _clockTick?.cancel();
    widget.bandUpdates?.removeListener(_refreshBand);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final b = _band;
    final diagnostics = _diagnostics;
    final issue = _issue;
    final rawStatus = _status;
    final fault = rawStatus == null ? null : bandIssueFor(rawStatus);
    final localizedFault = fault == null
        ? null
        : localizedBandStatus(context, fault);
    final disconnected =
        localizedFault != null ||
        issue != null ||
        b?.connection == BandConnection.disconnected;
    final stored = diagnostics?.lastStoredSampleAt ?? b?.latestStoredAt;
    final issueTitle =
        localizedFault?.title ??
        switch (issue) {
          OBBandIssue.bluetoothOff => 'Bluetooth ist ausgeschaltet',
          null => 'Nicht verbunden',
        };
    final issueBody = localizedFault == null
        ? switch (issue) {
            OBBandIssue.bluetoothOff =>
              'Ohne Bluetooth erreicht das iPhone das Band nicht. Gespeichertes bleibt erhalten.',
            null =>
              stored == null
                  ? 'Band näher ans iPhone bringen. Noch kein bestätigter Datenstand liegt vor.'
                  : 'Band näher ans iPhone bringen. Was seit ${obTime(stored)} gemessen wurde, kommt beim Verbinden.',
          }
        : [localizedFault.reason, ?localizedFault.fix].join('\n\n');
    final action = localizedFault?.condition == BandCondition.bluetoothOff
        ? 'Bluetooth einschalten'
        : localizedFault != null
        ? 'Hilfe'
        : switch (issue) {
            OBBandIssue.bluetoothOff => 'Bluetooth einschalten',
            null => 'Verbinden',
          };
    final name = widget.deviceName?.trim();
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        child: Column(
          children: [
            chrome.OBPageHeader.detail(
              title: 'BAND',
              subtitle:
                  name == null || name.isEmpty || name.toLowerCase() == 'band'
                  ? null
                  : name,
              backLabel: 'Profil',
              onBack: widget.onBack ?? () => Navigator.of(context).maybePop(),
              onTrailing: widget.onStatus,
              trailingLabel: 'Datenstand',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                children: [
                  if (b == null)
                    OBSettingsGroup(
                      children: [
                        OBSettingsRow(
                          label: 'Bandstatus —',
                          detail: 'Noch kein Bandstatus geladen.',
                          onTap: widget.onDevices == null ? null : _openDevices,
                        ),
                      ],
                    )
                  else
                    OBBandHero(
                      band: b,
                      diagnostics: diagnostics,
                      now: _now,
                      onStatus: widget.onStatus,
                      issue: issue,
                      faultLabel: localizedFault?.title,
                    ),
                  if (b != null && disconnected) ...[
                    const SizedBox(height: 12),
                    OBBandActionNotice(
                      title: issueTitle,
                      body: issueBody,
                      action: action,
                      onAction:
                          localizedFault != null ||
                              issue == OBBandIssue.bluetoothOff
                          ? _help
                          : widget.onReconnect == null
                          ? null
                          : _reconnect,
                      onHelp: _help,
                    ),
                  ],
                  if (b?.transfer == TransferState.receiving ||
                      b?.transfer == TransferState.interrupted) ...[
                    const SizedBox(height: 12),
                    if (b!.transfer == TransferState.receiving)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.lockKeyhole,
                              size: 16,
                              color: g.muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Erst gespeichert, dann bestätigt: Das Band löscht nur Werte, die sicher auf dem iPhone liegen. App währenddessen offen lassen.',
                                style: g.t(13, 19, color: g.ink2),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      OBSettingsGroup(
                        children: [
                          OBSettingsRow(
                            label: 'Übertragung unterbrochen',
                            detail:
                                'Bereits gespeicherte Abschnitte bleiben erhalten.',
                            onTap: widget.onReconnect == null
                                ? null
                                : _reconnect,
                          ),
                        ],
                      ),
                  ],
                  if (!disconnected) ...[
                    const SizedBox(height: 24),
                    Text('GERÄT', style: g.caps(color: g.muted)),
                    const SizedBox(height: 8),
                    OBSettingsGroup(
                      children: [
                        OBSettingsRow(
                          label: 'Modell',
                          value: diagnostics?.model ?? '—',
                        ),
                        OBSettingsRow(
                          label: 'Firmware',
                          value: diagnostics?.firmwareVersion ?? '—',
                        ),
                        if (diagnostics?.deviceFamily != null)
                          OBSettingsRow(
                            label: 'Gerätefamilie',
                            value: diagnostics!.deviceFamily!,
                          ),
                        OBSettingsRow(
                          label: 'Datenbankdatei',
                          value: widget.databaseSize ?? '—',
                        ),
                      ],
                    ),
                    if (widget.onDevices != null) ...[
                      const SizedBox(height: 24),
                      Text('AM BAND', style: g.caps(color: g.muted)),
                      const SizedBox(height: 8),
                      OBSettingsGroup(
                        children: [
                          OBSettingsRow(
                            label: 'Band verwalten',
                            detail: 'Alarm, Akkumeldung und Kopplung',
                            onTap: _openDevices,
                          ),
                        ],
                      ),
                    ],
                  ],
                  if (b != null) ...[
                    const SizedBox(height: 22),
                    Center(
                      child: Text(
                        'Letzter Bandwert ${obTime(stored)} · Übertragung ${obTime(b.receivedAt)}',
                        textAlign: TextAlign.center,
                        style: g.t(12, 17, color: g.muted),
                      ),
                    ),
                  ],
                  if (widget.synthetic) ...[
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
          ],
        ),
      ),
    );
  }
}
