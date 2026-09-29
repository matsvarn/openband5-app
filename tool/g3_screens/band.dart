import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/data/auto_backup.dart' show BackupCadence;
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/day_picker.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/screens/band.dart';
import 'package:openstrap_edge/openband/g3/band_parts.dart' show OBBandIssue;
import 'package:openstrap_edge/openband/g3/screens/band_restore.dart';
import 'package:openstrap_edge/openband/screens.dart'
    show OpenBandOverview, showBandStatus;
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/ui2/onboarding/first_sync.dart';
import 'package:openstrap_edge/ui2/onboarding/pairing.dart';
import 'package:openstrap_edge/ui2/onboarding/welcome.dart' show ImportOutcome;
import 'package:openstrap_edge/ui2/profile/data.dart';
import 'package:openstrap_edge/ui2/profile/profile.dart';
import 'env.dart';

final _now = DateTime(2026, 9, 29, 9, 41);
final _stored = DateTime(2026, 9, 29, 9, 38);
final _baseBand = BandSnapshot(
  connection: BandConnection.connected,
  latestStoredAt: _stored,
  receivedAt: _stored,
  batteryPercent: 64,
  batteryObservedAt: _stored,
);

SyntheticOpenBandRepository _syntheticBandRepository() =>
    SyntheticOpenBandRepository.fromMaps(
      jsonDecode(
            File(
              'docs/openband5/assets/fixtures/day-summary.json',
            ).readAsStringSync(),
          )
          as Map,
      jsonDecode(
            File(
              'docs/openband5/assets/fixtures/sleep-detail.json',
            ).readAsStringSync(),
          )
          as Map,
      scenario: SyntheticScenario.g3Sample,
    );

Widget _profile({bool? notificationsAllowed}) => ProfileHomeView(
  releaseReduced: true,
  synthetic: true,
  stats: ProfileStats(
    name: 'Mats',
    sources: 1,
    storageBytes: 4509715661,
    notificationsAllowed: notificationsAllowed,
  ),
  user: const {
    'name': 'Mats',
    'birth_date': '1995-09-21',
    'height_cm': 182.0,
    'weight_kg': 78.4,
  },
  band: _baseBand,
  bandName: 'WHOOP 5.0',
  languageLabel: 'Deutsch',
  onEdit: () {},
  onBand: () {},
  onData: () {},
  onSettings: () {},
  onNotifications: () {},
  onDismissNotificationWarning: () {},
  onLanguage: () {},
);

Widget _band(G3Env env, [BandSnapshot? band, OBBandIssue? issue]) =>
    G3BandScreen(
      band: env.band(() => band ?? _baseBand),
      now: env.now(() => _now)(),
      readDiagnostics: band == null
          ? () => env.repository(_syntheticBandRepository).readBandDiagnostics()
          : null,
      databaseSize: env.real ? null : '4,2 GB',
      onDevices: () async {},
      onReconnect: () async {},
      issue: issue,
      synthetic: !env.real,
    );

Widget _data({ImportOutcome? outcome, String? note, bool failed = false}) =>
    DataScreenView(
      synthetic: true,
      cadence: BackupCadence.daily,
      now: _now,
      lastBackupAt: DateTime(2026, 9, failed ? 28 : 29, 3),
      outcome: outcome,
      note: note,
      noteFailed: failed,
      backupFailed: failed,
      onBackupNow: () {},
      onExportDatabase: () {},
      onExportEncrypted: () {},
      onExportCsv: () {},
      onImport: () {},
      onReanalyze: () {},
      onAutomatic: (_) {},
    );

Widget _first(BandSnapshot band, SetupEvalState eval) => FirstSyncView(
  band: band,
  evaluation: SetupEvaluation(
    day: '2026-09-29',
    currentAlgo: 98,
    state: eval,
    computedAt: eval == SetupEvalState.complete ? _now : null,
  ),
  now: _now,
  onDone: () {},
  onResume: () {},
  synthetic: true,
);

final Map<String, G3ScreenBuilder> _frames = {
  'band-profil-hell': (env) => env.real ? null : _profile(),
  'band-profil-dunkel': (env) => env.real ? null : _profile(),
  'band-profil-mitteilungen-nicht-erlaubt-hell': (env) =>
      env.real ? null : _profile(notificationsAllowed: false),
  'band-band-verbunden-hell': (env) => _band(env),
  'band-band-verbunden-dunkel': (env) => _band(env),
  'band-band-uebertragung-laeuft-hell': (env) => env.real
      ? null
      : _band(
          env,
          BandSnapshot(
            connection: BandConnection.connected,
            transfer: TransferState.receiving,
            latestStoredAt: DateTime(2026, 9, 29, 8, 14),
            batteryPercent: 64,
          ),
        ),
  'band-band-getrennt-hell': (env) => env.real
      ? null
      : _band(
          env,
          BandSnapshot(
            connection: BandConnection.disconnected,
            latestStoredAt: DateTime(2026, 9, 28, 23, 10),
            batteryPercent: 64,
          ),
        ),
  'band-band-bluetooth-aus-hell': (env) => env.real
      ? null
      : _band(
          env,
          BandSnapshot(
            connection: BandConnection.disconnected,
            latestStoredAt: DateTime(2026, 9, 28, 23, 10),
            batteryPercent: 64,
          ),
          OBBandIssue.bluetoothOff,
        ),
  'band-band-nicht-gefunden-hell': (env) => null,
  'band-einrichtung-band-verbinden-hell': (env) => env.real
      ? null
      : PairingView(
          phase: PairPhase.idle,
          onPair: () {},
          onSkip: () {},
          synthetic: true,
        ),
  'band-einrichtung-erste-uebertragung-laeuft-hell': (env) => env.real
      ? null
      : _first(
          BandSnapshot(
            connection: BandConnection.connected,
            transfer: TransferState.receiving,
            latestStoredAt: DateTime(2026, 9, 29, 9, 28),
          ),
          SetupEvalState.pending,
        ),
  'band-einrichtung-erste-uebertragung-unterbrochen-hell': (env) => env.real
      ? null
      : _first(
          BandSnapshot(
            connection: BandConnection.disconnected,
            transfer: TransferState.interrupted,
            latestStoredAt: DateTime(2026, 9, 29, 9, 28),
          ),
          SetupEvalState.partial,
        ),
  'band-einrichtung-erste-uebertragung-unterbrochen-dunkel': (env) => env.real
      ? null
      : _first(
          BandSnapshot(
            connection: BandConnection.disconnected,
            transfer: TransferState.interrupted,
            latestStoredAt: DateTime(2026, 9, 29, 9, 28),
          ),
          SetupEvalState.partial,
        ),
  'band-einrichtung-erste-uebertragung-fertig-hell': (env) =>
      env.real ? null : _first(_baseBand, SetupEvalState.complete),
  'band-daten-und-sicherung-hell': (env) => env.real ? null : _data(),
  'band-daten-und-sicherung-dunkel': (env) => env.real ? null : _data(),
  'band-daten-und-sicherung-teilweise-uebernommen-hell': (env) =>
      env.real ? null : const _RestorePreview(),
  'band-daten-und-sicherung-sicherung-fehlgeschlagen-hell': (env) => env.real
      ? null
      : _data(note: 'Zu wenig freier Speicher auf dem iPhone.', failed: true),
  'band-dein-datenstand-hell': (env) => _SheetPreview(status: true, env: env),
  'band-dein-datenstand-dunkel': (env) => _SheetPreview(status: true, env: env),
  'band-dein-datenstand-verbunden-mit-rueckstand-hell': (env) =>
      env.real ? null : _SheetPreview(status: true, backlog: true, env: env),
  'band-datum-waehlen-hell': (env) => _SheetPreview(status: false, env: env),
  'band-datum-waehlen-dunkel': (env) => _SheetPreview(status: false, env: env),
};

final Map<String, G3ScreenBuilder> bandScreens = {
  for (final entry in _frames.entries)
    entry.key: (env) {
      final child = entry.value(env);
      if (child == null) return null;
      return FutureBuilder<void>(
        future: initializeDateFormatting('de_DE'),
        builder: (context, snapshot) =>
            snapshot.connectionState == ConnectionState.done
            ? Localizations.override(
                context: context,
                locale: const Locale('de'),
                delegates: GlobalMaterialLocalizations.delegates,
                child: child,
              )
            : const SizedBox.shrink(),
      );
    },
};

class _SheetPreview extends StatefulWidget {
  final bool status;
  final bool backlog;
  final G3Env env;
  const _SheetPreview({
    required this.status,
    required this.env,
    this.backlog = false,
  });
  @override
  State<_SheetPreview> createState() => _SheetPreviewState();
}

class _RestorePreview extends StatefulWidget {
  const _RestorePreview();
  @override
  State<_RestorePreview> createState() => _RestorePreviewState();
}

class _RestorePreviewState extends State<_RestorePreview> {
  static const outcome = ImportOutcome(
    source: 'OpenBand-Sicherung',
    restoredRows: 12,
    unchangedRows: 3,
    restoreConflicts: 1,
    unreadableRows: 1,
    pendingRecalculations: 2,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showG3RestoreReceipt(context, outcome, synthetic: true);
    });
  }

  @override
  Widget build(BuildContext context) => _data(outcome: outcome);
}

class _SheetPreviewState extends State<_SheetPreview> {
  OpenBandController? controller;
  bool opened = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await initializeDateFormatting('de_DE');
    Map? summary;
    Map? detail;
    if (!widget.env.real) {
      summary =
          jsonDecode(
                await rootBundle.loadString(
                  'docs/openband5/assets/fixtures/day-summary.json',
                ),
              )
              as Map;
      detail =
          jsonDecode(
                await rootBundle.loadString(
                  'docs/openband5/assets/fixtures/sleep-detail.json',
                ),
              )
              as Map;
    }
    final repository = widget.env.repository(
      () => SyntheticOpenBandRepository.fromMaps(
        summary!,
        detail!,
        scenario: SyntheticScenario.g3Sample,
      ),
    );
    final b = widget.backlog
        ? BandSnapshot(
            connection: BandConnection.connected,
            latestStoredAt: DateTime(2026, 9, 29, 7, 42),
            batteryPercent: 64,
          )
        : _baseBand;
    final c = OpenBandController(
      repository: repository,
      initialDay: widget.env.day(widget.status ? '2026-09-29' : '2026-09-27'),
      band: widget.env.band(() => b),
      now: widget.env.now(() => _now),
    );
    await c.refresh();
    if (!mounted) {
      c.dispose();
      return;
    }
    setState(() => controller = c);
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c != null && !opened) {
      opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.status) {
          showBandStatus(context, c, null);
        } else {
          chooseOpenBandDay(context, c);
        }
      });
    }
    return c == null
        ? const Scaffold(body: SizedBox.shrink())
        : Scaffold(body: OpenBandOverview(controller: c, reduced: true));
  }
}
