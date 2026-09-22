// Erste Übertragung — Einrichtung step 2 of 3, between pairing and profile.
//
// Three independent rows: connection, last stored band time, and today's
// evaluation at the current algorithm. Continue never blocks.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart';
import '../../openband/domain.dart';
import '../../openband/local_repository.dart';
import '../../openband/screens.dart' show OBSyncActionState, OBSyncState;
import '../../openband/settings_controls.dart';
import '../../openband/theme.dart';
import '../../state/app_state.dart';

enum SetupStatusIcon { open, active, done }

class FirstSyncScreen extends StatefulWidget {
  final VoidCallback onDone;
  final VoidCallback? onBack;

  /// Reads the current band snapshot. Defaults to the production
  /// [LocalOpenBandRepository]; tests inject the synthetic fixture.
  final Future<BandSnapshot> Function()? readBand;

  /// Current-local-day evaluation. Injected together with [readBand].
  final Future<SetupEvaluation> Function(String day)? readSetupEvaluation;

  /// Starts or reclaims the production session. With injected reads this must
  /// also be injected; synthetic hosts never resolve [AppState] implicitly.
  final Future<void> Function()? onResume;

  final DateTime Function()? now;
  final bool synthetic;

  const FirstSyncScreen({
    super.key,
    required this.onDone,
    this.onBack,
    this.readBand,
    this.readSetupEvaluation,
    this.onResume,
    this.now,
    this.synthetic = false,
  });

  @override
  State<FirstSyncScreen> createState() => _FirstSyncScreenState();
}

class _FirstSyncScreenState extends State<FirstSyncScreen> {
  BandSnapshot? _band;
  SetupEvaluation? _evaluation;
  bool _bandError = false;
  bool _evalError = false;
  Timer? _poll;
  int _gen = 0;
  bool _reading = false;
  bool _queued = false;
  bool _resuming = false;
  bool _resumePending = false;
  bool _resumeFailed = false;

  DateTime Function() get _clock => widget.now ?? DateTime.now;

  @override
  void initState() {
    super.initState();
    if ((widget.readBand == null) != (widget.readSetupEvaluation == null)) {
      throw StateError(
        'FirstSyncScreen requires both readBand and readSetupEvaluation, or neither.',
      );
    }
    _poll = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_read()),
    );
    unawaited(_read());
  }

  Future<BandSnapshot> _loadBand() {
    final injected = widget.readBand;
    if (injected != null) return injected();
    return LocalOpenBandRepository(context.read<AppState>()).readBand();
  }

  Future<SetupEvaluation> _loadEval(String day) {
    final injected = widget.readSetupEvaluation;
    if (injected != null) return injected(day);
    return LocalOpenBandRepository(
      context.read<AppState>(),
    ).readSetupEvaluation(day);
  }

  void _dropStaleEval() {
    final day = todayLabel(_clock());
    if (_evaluation != null && _evaluation!.day != day) {
      _evaluation = null;
      _evalError = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _read() async {
    _dropStaleEval();
    if (_reading) {
      _queued = true;
      return;
    }
    _reading = true;
    final gen = _gen;
    try {
      do {
        _queued = false;
        final day = todayLabel(_clock());
        await _readOnce(gen, day);
        if (!mounted || gen != _gen) return;
        if (todayLabel(_clock()) != day) _queued = true;
      } while (mounted && _queued && gen == _gen);
    } finally {
      _reading = false;
    }
    if (mounted && _queued && gen == _gen) unawaited(_read());
  }

  Future<void> _readOnce(int gen, String day) async {
    try {
      final band = await _loadBand();
      if (!mounted || gen != _gen) return;
      final resumeSettled =
          _resumePending && band.connection != BandConnection.connecting;
      setState(() {
        _band = band;
        _bandError = false;
        if (resumeSettled) {
          _resumePending = false;
          _resumeFailed =
              band.connection == BandConnection.disconnected ||
              band.transfer == TransferState.interrupted;
        } else if (band.connection == BandConnection.connected &&
            band.transfer != TransferState.interrupted) {
          // A later supervisor reconnect is equally real evidence. Do not
          // leave a stale failed-action label beside a freshly connected row.
          _resumeFailed = false;
        }
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      if (!_bandError) setState(() => _bandError = true);
    }
    if (!mounted || gen != _gen) return;
    if (todayLabel(_clock()) != day) return;

    try {
      final next = await _loadEval(day);
      if (!mounted || gen != _gen) return;
      if (todayLabel(_clock()) != day) return;
      final evaluation = next.day == day ? next : null;
      if (_evaluation == evaluation && !_evalError) return;
      setState(() {
        _evaluation = evaluation;
        _evalError = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      if (todayLabel(_clock()) != day) return;
      if (_evalError && _evaluation == null) return;
      setState(() {
        _evaluation = null;
        _evalError = true;
      });
    }
  }

  Future<void> _resume() async {
    if (_resuming || _resumePending) return;
    final injected = widget.onResume;
    // An injected repository is a synthetic/test boundary. Never cross it to
    // a production AppState merely because its host omitted an action seam.
    if (widget.readBand != null && injected == null) return;
    setState(() {
      _resuming = true;
      _resumeFailed = false;
    });
    try {
      if (injected != null) {
        await injected();
      } else {
        await context.read<AppState>().openSession();
      }
      if (!mounted) return;
      final band = await _loadBand();
      if (!mounted) return;
      setState(() {
        _band = band;
        _bandError = false;
        _resumePending = band.connection == BandConnection.connecting;
        _resumeFailed =
            !_resumePending &&
            (band.connection == BandConnection.disconnected ||
                band.transfer == TransferState.interrupted);
      });
      // Resume and read-retry stay separate actions, but a successful session
      // attempt may also have completed today's evaluation while it ran.
      unawaited(_read());
    } catch (_) {
      if (!mounted) return;
      setState(() => _resumeFailed = true);
    } finally {
      if (mounted) setState(() => _resuming = false);
    }
  }

  @override
  void dispose() {
    _gen++;
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FirstSyncView(
      band: _band,
      evaluation: _evaluation,
      bandError: _bandError,
      evalError: _evalError,
      now: _clock(),
      onDone: widget.onDone,
      onBack: widget.onBack,
      onRetry: () => unawaited(_read()),
      onResume: widget.readBand != null && widget.onResume == null
          ? null
          : () => unawaited(_resume()),
      resumeBusy: _resuming || _resumePending,
      resumeFailed: _resumeFailed,
      synthetic: widget.synthetic,
    );
  }
}

/// Production, gallery and golden host for first-setup status.
class FirstSyncView extends StatelessWidget {
  final BandSnapshot? band;
  final SetupEvaluation? evaluation;
  final bool bandError;
  final bool evalError;
  final DateTime now;
  final VoidCallback onDone;
  final VoidCallback? onBack;
  final VoidCallback? onRetry;
  final VoidCallback? onResume;
  final bool resumeBusy;
  final bool resumeFailed;
  final bool synthetic;

  const FirstSyncView({
    super.key,
    this.band,
    this.evaluation,
    this.bandError = false,
    this.evalError = false,
    required this.now,
    required this.onDone,
    this.onBack,
    this.onRetry,
    this.onResume,
    this.resumeBusy = false,
    this.resumeFailed = false,
    this.synthetic = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(
                title: _s(context, 'Erste Übertragung', 'First transfer'),
                subtitle: _s(context, 'Schritt 2 von 3', 'Step 2 of 3'),
                onBack: onBack,
                showBack: onBack != null || Navigator.canPop(context),
                onInfo: () => _info(context),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  OBSetupStatusCard(
                    band: band,
                    evaluation: evaluation,
                    now: now,
                  ),
                  if (band?.transfer == TransferState.interrupted ||
                      resumeBusy ||
                      resumeFailed) ...[
                    const SizedBox(height: 12),
                    OBSyncState(
                      band: band ?? const BandSnapshot(),
                      now: () => now,
                      onResume: onResume,
                      showStoredTime: false,
                      actionState: resumeBusy
                          ? OBSyncActionState.pending
                          : resumeFailed
                          ? OBSyncActionState.failed
                          : null,
                      interruptedLabel: _s(
                        context,
                        'Unterbrochen',
                        'Interrupted',
                      ),
                      pendingLabel: _s(
                        context,
                        'Verbindung wird hergestellt',
                        'Connecting',
                      ),
                      failedLabel: _s(
                        context,
                        'Fortsetzen fehlgeschlagen',
                        'Resume failed',
                      ),
                      resumeLabel: _s(context, 'Fortsetzen', 'Resume'),
                      retryLabel: _s(context, 'Erneut', 'Try again'),
                    ),
                  ],
                  if (evalError) ...[
                    const SizedBox(height: 12),
                    OBSettingsErrorCard(
                      message: _s(
                        context,
                        'Auswertung nicht geladen',
                        'Evaluation not loaded',
                      ),
                      retryLabel: _s(context, 'Erneut', 'Try again'),
                      onRetry: onRetry,
                    ),
                  ],
                  if (bandError) ...[
                    const SizedBox(height: 12),
                    OBSettingsErrorCard(
                      message: _s(
                        context,
                        'Bandstatus nicht geladen',
                        'Band status not loaded',
                      ),
                      retryLabel: _s(context, 'Erneut', 'Try again'),
                      onRetry: onRetry,
                    ),
                  ],
                  if (synthetic) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Synthetische Daten',
                      textAlign: TextAlign.center,
                      style: p
                          .text(12, color: p.muted)
                          .copyWith(height: 16 / 12),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, bottom),
              child: OBAction(
                _s(context, 'Weiter zum Profil', 'Continue to profile'),
                ink: true,
                onPressed: onDone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OBSetupStatusCard extends StatelessWidget {
  final BandSnapshot? band;
  final SetupEvaluation? evaluation;
  final DateTime now;

  const OBSetupStatusCard({
    super.key,
    this.band,
    this.evaluation,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final connection = _connection(context, band);
    final stored = _stored(context, band, now);
    final eval = _eval(context, evaluation);
    return OBCard(
      child: Column(
        children: [
          _StatusRow(
            label: _s(context, 'Verbindung', 'Connection'),
            value: connection.$2,
            icon: connection.$1,
          ),
          _StatusRow(
            label: _s(context, 'Auf dem iPhone', 'On iPhone'),
            value: stored.$2,
            icon: stored.$1,
          ),
          _StatusRow(
            label: _s(context, 'Auswertung heute', "Today's evaluation"),
            value: eval.$2,
            icon: eval.$1,
            last: true,
          ),
        ],
      ),
    );
  }
}

(SetupStatusIcon, String) _connection(
  BuildContext context,
  BandSnapshot? band,
) {
  if (band == null) return (SetupStatusIcon.open, '—');
  return switch (band.connection) {
    BandConnection.connected => (
      SetupStatusIcon.done,
      _s(context, 'Verbunden', 'Connected'),
    ),
    BandConnection.connecting => (SetupStatusIcon.active, '—'),
    BandConnection.disconnected => (SetupStatusIcon.open, '—'),
  };
}

(SetupStatusIcon, String) _stored(
  BuildContext context,
  BandSnapshot? band,
  DateTime now,
) {
  if (band == null) return (SetupStatusIcon.open, '—');
  final frontier = _frontier(context, band.latestStoredAt, now);
  return switch (band.transfer) {
    TransferState.receiving => (SetupStatusIcon.active, frontier),
    TransferState.interrupted => (SetupStatusIcon.open, frontier),
    TransferState.idle => (
      band.latestStoredAt == null ? SetupStatusIcon.open : SetupStatusIcon.done,
      frontier,
    ),
  };
}

(SetupStatusIcon, String) _eval(
  BuildContext context,
  SetupEvaluation? evaluation,
) {
  if (evaluation == null) return (SetupStatusIcon.open, '—');
  return switch (evaluation.state) {
    SetupEvalState.complete => (
      SetupStatusIcon.done,
      obTime(evaluation.computedAt),
    ),
    SetupEvalState.pending => (
      SetupStatusIcon.active,
      _s(context, 'Ausstehend', 'Pending'),
    ),
    SetupEvalState.failed => (
      SetupStatusIcon.open,
      _s(context, 'Fehlgeschlagen', 'Failed'),
    ),
    SetupEvalState.partial => (
      SetupStatusIcon.open,
      _s(context, 'Teilweise', 'Partial'),
    ),
    SetupEvalState.missing ||
    SetupEvalState.stale ||
    SetupEvalState.unavailable => (SetupStatusIcon.open, '—'),
  };
}

String _frontier(BuildContext context, DateTime? stored, DateTime now) {
  if (stored == null) return '—';
  final time = obTime(stored);
  final sameDay = dayLabelOf(stored) == todayLabel(now);
  final dated = sameDay
      ? time
      : '${DateFormat(_german(context) ? 'd.M.' : 'd MMM', _german(context) ? 'de_DE' : 'en').format(stored)} $time';
  return '${_s(context, 'bis', 'until')} $dated';
}

bool _stackStatusRows(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(15) > 20 ||
    MediaQuery.sizeOf(context).width < 360;

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final SetupStatusIcon icon;
  final bool last;
  const _StatusRow({
    required this.label,
    required this.value,
    required this.icon,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final open = icon == SetupStatusIcon.open;
    final mark = switch (icon) {
      SetupStatusIcon.done => Icon(
        LucideIcons.circleCheck,
        size: 20,
        color: p.led,
      ),
      SetupStatusIcon.active => Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: p.action, width: 2),
        ),
      ),
      SetupStatusIcon.open => Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: p.line, width: 2),
        ),
      ),
    };
    final labelStyle = p
        .text(15, weight: FontWeight.w500, color: open ? p.muted : p.ink)
        .copyWith(height: 20 / 15);
    final valueStyle = p
        .text(15, weight: FontWeight.w600, display: true, color: p.muted)
        .copyWith(height: 20 / 15);
    final stack = _stackStatusRows(context);
    final shown = value;
    return Semantics(
      label: '$label $shown',
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: last
            ? null
            : BoxDecoration(
                border: Border(bottom: BorderSide(color: p.line)),
              ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: stack
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              SizedBox(width: 20, height: 20, child: Center(child: mark)),
              const SizedBox(width: 12),
              Expanded(
                child: stack
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: labelStyle),
                          Text(shown, style: valueStyle),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: Text(label, style: labelStyle)),
                          const SizedBox(width: 8),
                          Text(
                            shown,
                            textAlign: TextAlign.right,
                            style: valueStyle,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _german(BuildContext context) =>
    Localizations.maybeLocaleOf(context)?.languageCode == 'de';

String _s(BuildContext context, String de, String en) =>
    _german(context) ? de : en;

void _info(BuildContext context) {
  final p = OB.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.card,
    builder: (sheet) {
      final sp = OB.of(sheet);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _s(sheet, 'Erste Übertragung', 'First transfer'),
                style: sp.text(18, weight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                _s(
                  sheet,
                  'Auf dem iPhone ist der zuletzt vollständig gespeicherte Bandzeitpunkt.',
                  'On iPhone is the last fully stored band time.',
                ),
                style: sp.text(14),
              ),
              const SizedBox(height: 8),
              Text(
                _s(
                  sheet,
                  'Auswertung heute gilt für den aktuellen Kalendertag und die aktuelle Berechnungsversion.',
                  "Today's evaluation refers to the current local day and the current calculation version.",
                ),
                style: sp.text(14),
              ),
              const SizedBox(height: 16),
              OBAction(
                _s(sheet, 'Schließen', 'Close'),
                onPressed: () => Navigator.pop(sheet),
              ),
            ],
          ),
        ),
      );
    },
  );
}
