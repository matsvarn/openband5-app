// Pairing.
//
// The failure states are the screen. A hardware app that says "Couldn't pair"
// and offers a Retry button has told the user nothing and given them nowhere
// to go — the audit found exactly that here: a refused bond and a dismissed
// picker fell through to the same dead end. They are different problems with
// different fixes, and neither of them is the user's fault.
//
// There is also always a way out. Someone whose band is flat, or who is
// installing this before the hardware arrives, must be able to reach the app.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../ble/band_status_l10n.dart' show localizedBandStatus;
import '../../ble/ble_state.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../../openband/theme.dart';

/// Onboarding steps the user deliberately walked past.
///
/// [AppState.route] is derived purely from device + profile state, so a user
/// who skips pairing (band flat, hardware not arrived) or who leaves an
/// optional profile field blank would be bounced back to the same step
/// forever. The bypass is the user's answer to that, and it is theirs to
/// give — so it is recorded here rather than by weakening the conditions
/// AppState uses for everything else.
class OnboardingBypass {
  OnboardingBypass._();

  static const kPairing = 'onboard.skipped_pairing';
  static const kFirstSync = 'onboard.saw_first_sync';
  static const kProfile = 'onboard.saw_profile_setup';

  /// Bumped on every skip so the gate — which selects on the AppState route,
  /// not on SharedPreferences — rebuilds.
  static final revision = ValueNotifier<int>(0);

  static bool get pairingSkipped => Prefs.getBool(kPairing, false);
  static bool get firstSyncSeen => Prefs.getBool(kFirstSync, false);
  static bool get profileSeen => Prefs.getBool(kProfile, false);

  static void mark(String key) {
    Prefs.setBool(key, true);
    revision.value++;
  }

  // No `clear`. Un-skipping cannot walk the gate back to pairing: the shell
  // latches `onboarded` on its first frame and the gate sends pairing/profile
  // straight to the shell from then on. "Pair a band" pushes `RePair` instead
  // — see `profile/devices.dart`.
}

enum PairPhase {
  /// Nothing tried yet.
  idle,
  scanning,

  /// The phone's own Bluetooth stack refused us — permission, radio off, or no
  /// BLE at all. Nothing about the band is known yet, and every band-side
  /// instruction ("wake it, hold it close") is a wasted walk around the house.
  bluetoothBlocked,

  /// The scan completed and found nothing in range.
  notFound,

  /// The link came up but the band refused to bond. Distinct because the fix
  /// is in the phone's own Bluetooth settings, not in this app.
  bondRefused,

  /// The system picker was dismissed. Not an error — do not shout.
  cancelled,

  /// Anything else, with the real message attached.
  failed,
  paired,
}

/// The phone-side blocker behind a thrown pairing error, or null when the
/// failure is genuinely about the band.
///
/// [BleUnavailableException] is checked before the string matcher because it
/// carries the verdict already: its `adapterOff` case does not contain any of
/// the phrases the matcher looks for, so classifying it by text alone would
/// silently demote a radio-off to a band fault.
BleBlocker? pairBlocker(Object error) => error is BleUnavailableException
    ? error.blocker
    : classifyBleBlocker(error: error);

/// Classify a thrown pairing error. Pure — this is the whole reason the
/// distinct states exist rather than one "Couldn't pair".
PairPhase classifyPairError(Object error, {int bondRefusals = 0}) {
  // First, because this is the one failure that is not about the band at all.
  // It used to fall through to `failed` (or, via a null scan, to "No band in
  // range"), which sends someone who revoked a permission looking for hardware.
  if (pairBlocker(error) != null) return PairPhase.bluetoothBlocked;
  final s = error.toString().toLowerCase();
  if (s.contains('cancel') || s.contains('dismiss')) return PairPhase.cancelled;
  if (bondRefusals > 0 || s.contains('bond') || s.contains('encrypt')) {
    return PairPhase.bondRefused;
  }
  return PairPhase.failed;
}

class PairingScreen extends StatefulWidget {
  /// Gate callbacks are explicit because the gate is the navigator's sole
  /// route: it must change AppState instead of popping itself. Pushed re-pair
  /// screens omit [onBack] and provide [onPaired] for exactly one pop.
  final VoidCallback? onBack;
  final VoidCallback? onPaired;

  /// Walk past pairing and open the app anyway. Supplied only by the router.
  final VoidCallback? onSkip;

  const PairingScreen({super.key, this.onBack, this.onPaired, this.onSkip});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  PairPhase _phase = PairPhase.idle;
  String _detail = '';
  BleBlocker? _blocker;

  Future<void> _pair() async {
    final app = context.read<AppState>();
    setState(() {
      _phase = PairPhase.scanning;
      _detail = '';
      _blocker = null;
    });
    try {
      if (await app.accessorySetupSupported()) {
        await app.pairViaAccessorySetup();
      } else {
        final found = await app.scanForBand();
        if (found == null) {
          if (mounted) setState(() => _phase = PairPhase.notFound);
          return;
        }
        await app.pairWith(found);
      }
      if (!mounted) return;
      // AccessorySetup cancellation is platform-owned and has changed shape
      // across iOS releases. Persistence is the source of truth: a callback
      // returning normally without an actual paired row is not success.
      if (!app.isPaired) {
        setState(() => _phase = PairPhase.cancelled);
        return;
      }
      setState(() => _phase = PairPhase.paired);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _blocker = pairBlocker(e);
        _phase = classifyPairError(e, bondRefusals: app.device.bondRefusals);
        _detail = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext c) => PairingView(
    phase: _phase,
    detail: _detail,
    blocker: _blocker,
    onPair: _pair,
    onBack:
        widget.onBack ?? () => Navigator.of(c).pop(c.read<AppState>().isPaired),
    onContinue:
        widget.onPaired ??
        (widget.onBack == null ? () => Navigator.of(c).pop(true) : null),
    onSkip: widget.onSkip,
  );
}

class PairingView extends StatelessWidget {
  final PairPhase phase;
  final String detail;
  final VoidCallback onPair;
  final VoidCallback? onBack;
  final VoidCallback? onContinue;
  final VoidCallback? onSkip;
  final VoidCallback? onInfo;

  /// Which phone-side blocker, when [phase] is `bluetoothBlocked`.
  final BleBlocker? blocker;

  const PairingView({
    super.key,
    required this.phase,
    required this.onPair,
    this.onBack,
    this.onContinue,
    this.detail = '',
    this.blocker,
    this.onSkip,
    this.onInfo,
  });

  @override
  Widget build(BuildContext c) {
    final p = OB.of(c);
    final busy = phase == PairPhase.scanning;
    // The copy for this one lives in the BLE layer, so this screen and the
    // Devices screen cannot drift into two different accounts of one state.
    final blocked = phase == PairPhase.bluetoothBlocked
        ? localizedBandStatus(
            c,
            bandStatusFor(connection: 'disconnected', blocker: blocker),
          )
        : null;
    final stateDetail = phase == PairPhase.idle
        ? _s(
            c,
            'Noch nicht verbunden. Band nah ans iPhone halten.',
            'Not connected yet. Hold the band close to the phone.',
          )
        : blocked == null
        ? _body(c, phase, blocker)
        : blocked.fix ?? blocked.reason;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(
                title: _s(c, 'Band verbinden', 'Connect band'),
                subtitle: onSkip == null
                    ? ''
                    : _s(
                        c,
                        'Einrichtung · Schritt 1 von 3',
                        'Setup · Step 1 of 3',
                      ),
                onBack: onBack,
                onInfo: onInfo ?? () => _showInfo(c),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                children: [
                  if (onSkip != null) ...[
                    Row(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          Expanded(
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: i == 0
                                    ? p.ink
                                    : p.muted.withValues(alpha: .24),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          if (i < 2) const SizedBox(width: 6),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                  OBCard(
                    child: Column(
                      children: [
                        Container(
                          height: 126,
                          decoration: BoxDecoration(
                            color: p.well,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: p.line),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _PairDeviceIcon(icon: LucideIcons.watch),
                              const SizedBox(width: 16),
                              _PairLink(
                                activeBars: switch (phase) {
                                  PairPhase.paired => 4,
                                  PairPhase.scanning => 2,
                                  PairPhase.idle => 1,
                                  _ => 0,
                                },
                              ),
                              const SizedBox(width: 16),
                              _PairDeviceIcon(icon: LucideIcons.smartphone),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (busy)
                              SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  color: p.ink,
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(top: 6),
                                decoration: BoxDecoration(
                                  color: phase == PairPhase.paired
                                      ? p.led
                                      : p.muted,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    phase == PairPhase.idle
                                        ? 'WHOOP 5.0'
                                        : _title(c, phase, blocker),
                                    style: p.text(15, weight: FontWeight.w600),
                                  ),
                                  Text(
                                    stateDetail,
                                    style: p.text(13, color: p.muted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (phase != PairPhase.bluetoothBlocked) ...[
                    const SizedBox(height: 10),
                    OBCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      child: Column(
                        children: [
                          _PairStep(
                            '1',
                            _s(
                              c,
                              'Band tragen oder laden',
                              'Wear or charge the band',
                            ),
                          ),
                          _PairStep(
                            '2',
                            _s(c, 'Bluetooth einschalten', 'Turn on Bluetooth'),
                          ),
                          _PairStep(
                            '3',
                            _s(c, 'WHOOP-App schließen', 'Close the WHOOP app'),
                            last: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  OBAction(
                    _cta(c, phase),
                    ink: true,
                    onPressed: busy
                        ? null
                        : phase == PairPhase.paired
                        ? onContinue
                        : onPair,
                  ),
                  if (onSkip != null && phase != PairPhase.paired) ...[
                    const SizedBox(height: 10),
                    // Never disabled mid-scan: the escape hatch must not make
                    // someone wait out a scan they already chose to leave.
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: onSkip,
                        style: TextButton.styleFrom(
                          foregroundColor: p.muted,
                          minimumSize: const Size(44, 44),
                        ),
                        child: Text(
                          _s(c, 'Später verbinden', 'Connect later'),
                          style: p.text(
                            15,
                            weight: FontWeight.w600,
                            color: p.muted,
                          ),
                        ),
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

  void _showInfo(BuildContext context) {
    final p = OB.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _title(sheet, phase, blocker),
                style: p.text(18, weight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(_body(sheet, phase, blocker), style: p.text(14)),
              ..._advice(sheet, phase, detail),
              const SizedBox(height: 16),
              OBAction(
                _s(sheet, 'Schließen', 'Close'),
                ink: true,
                onPressed: () => Navigator.pop(sheet),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _title(BuildContext c, PairPhase phase, [BleBlocker? blocker]) {
    final l = AppLocalizations.of(c);
    return switch (phase) {
      PairPhase.bluetoothBlocked => localizedBandStatus(
        c,
        bandStatusFor(connection: 'disconnected', blocker: blocker),
      ).title,
      PairPhase.idle =>
        l?.pairingIdleTitle ?? 'Wake the band and hold it close',
      PairPhase.scanning => l?.pairingScanningTitle ?? 'Looking for your band',
      PairPhase.notFound => l?.pairingNotFoundTitle ?? 'No band in range',
      PairPhase.bondRefused =>
        l?.pairingBondRefusedTitle ?? 'The band refused the pairing',
      PairPhase.cancelled =>
        l?.pairingCancelledTitle ?? 'Pairing was cancelled',
      PairPhase.failed => l?.pairingFailedTitle ?? 'Pairing did not complete',
      PairPhase.paired => l?.pairingPairedTitle ?? 'Paired',
    };
  }

  static String _body(BuildContext c, PairPhase phase, [BleBlocker? blocker]) {
    final l = AppLocalizations.of(c);
    return switch (phase) {
      PairPhase.bluetoothBlocked => localizedBandStatus(
        c,
        bandStatusFor(connection: 'disconnected', blocker: blocker),
      ).reason,
      PairPhase.idle =>
        l?.pairingIdleBody ??
            'Take the band off the charger, put it on your wrist and keep the '
                'phone within arm’s reach.',
      PairPhase.scanning =>
        l?.pairingScanningBody ??
            'A band that has just come off the charger can take up to half a '
                'minute to start advertising.',
      PairPhase.notFound =>
        l?.pairingNotFoundBody ??
            'Nothing answered the scan. The band advertises only when it is '
                'awake and not already connected to another phone.',
      PairPhase.bondRefused =>
        l?.pairingBondRefusedBody ??
            'The link came up, but the band would not accept the encryption '
                'key. That is almost always a stale pairing record on this '
                'phone rather than a fault in the band.',
      PairPhase.cancelled =>
        l?.pairingCancelledBody ??
            'The system picker was dismissed before a band was chosen.',
      PairPhase.failed =>
        l?.pairingFailedBody ??
            'The band was reachable but the session did not finish.',
      PairPhase.paired => l?.pairingPairedBody ?? 'Setting up the first sync.',
    };
  }

  static String _cta(BuildContext c, PairPhase phase) {
    final l = AppLocalizations.of(c);
    return switch (phase) {
      PairPhase.idle => _s(c, 'Verbinden', 'Connect'),
      PairPhase.scanning => l?.pairingSearching ?? 'Searching…',
      PairPhase.cancelled =>
        l?.pairingOpenPickerAgain ?? 'Open the picker again',
      PairPhase.paired => l?.actionContinue ?? 'Continue',
      _ => l?.pairingTryAgain ?? 'Try again',
    };
  }

  /// The fix, spelled out, for the states that have one.
  List<Widget> _advice(BuildContext c, PairPhase phase, String detail) {
    final l = AppLocalizations.of(c);
    return switch (phase) {
      PairPhase.notFound => [
        const SizedBox(height: 24),
        OBNoticeCard(
          l?.pairingNotFoundAdviceTitle ?? 'Three things stop a band answering',
          l?.pairingNotFoundAdviceBody ??
              'It is still on the charger; it is out of range; or it is '
                  'still connected to another phone or to the vendor app.',
          fix:
              l?.pairingNotFoundAdviceFix ??
              'Force-quit the other app, then scan again',
          icon: LucideIcons.searchX,
        ),
      ],
      PairPhase.bondRefused => [
        const SizedBox(height: 24),
        OBNoticeCard(
          l?.pairingBondRefusedAdviceTitle ??
              'Forget the band in Bluetooth settings first',
          l?.pairingBondRefusedAdviceBody ??
              'Open the phone’s Bluetooth settings, forget the band, '
                  'then scan again here. The refused key is the old pairing '
                  'record, and only the system can clear it.',
          fix: l?.pairingBondRefusedAdviceFix ?? 'Open Bluetooth settings',
          icon: LucideIcons.unlink,
        ),
        if (detail.isNotEmpty) ...[const SizedBox(height: 12), _Detail(detail)],
      ],
      PairPhase.failed => [
        const SizedBox(height: 24),
        OBNoticeCard(
          l?.pairingFailedAdviceTitle ??
              'The band was found but the session did not finish',
          l?.pairingFailedAdviceBody ??
              'Scanning again from a metre away normally works.',
          icon: LucideIcons.triangleAlert,
        ),
        if (detail.isNotEmpty) ...[const SizedBox(height: 12), _Detail(detail)],
      ],
      _ => const [],
    };
  }
}

class _PairDeviceIcon extends StatelessWidget {
  final IconData icon;
  const _PairDeviceIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: p.card,
        shape: BoxShape.circle,
        border: Border.all(color: p.line),
        boxShadow: [
          BoxShadow(
            color: p.ink.withValues(alpha: .08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, size: 26, color: p.ink),
    );
  }
}

class _PairLink extends StatelessWidget {
  final int activeBars;
  const _PairLink({required this.activeBars});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: i < activeBars ? p.action : p.line,
              shape: BoxShape.circle,
            ),
          ),
          if (i < 3) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _PairStep extends StatelessWidget {
  final String number;
  final String label;
  final bool last;
  const _PairStep(this.number, this.label, {this.last = false});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: p.line)),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.well,
              shape: BoxShape.circle,
              border: Border.all(color: p.line),
            ),
            child: Text(number, style: p.text(13, weight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: p.text(15, weight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

bool _german(BuildContext context) =>
    Localizations.maybeLocaleOf(context)?.languageCode == 'de';

String _s(BuildContext context, String de, String en) =>
    _german(context) ? de : en;

/// The raw error, kept but demoted. It is useless to most people and the only
/// thing that helps in a bug report.
class _Detail extends StatelessWidget {
  final String text;
  const _Detail(this.text);

  @override
  Widget build(BuildContext c) {
    final p = OB.of(c);
    return OBCard(
      child: Text(text, style: p.text(13, color: p.muted)),
    );
  }
}
