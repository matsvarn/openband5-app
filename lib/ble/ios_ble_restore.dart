// iOS CoreBluetooth state-restoration bridge.
//
// The native BleRestoreManager (ios/Runner/BleRestoreManager.swift) holds a no-timeout
// pending connect to the paired band so iOS relaunches the app when the band reappears —
// even from terminated. When that fires, native invokes `wake` here and we run the same
// headless drain the periodic task uses, then tell native we're done so it re-arms.
//
// No-op on Android (the Edge Tracking foreground service keeps the process + live
// connection alive there — no restore central needed).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../sync/background_sync.dart';
import '../sync/file_log.dart';
import '../sync/headless_gate.dart';
import '../sync/band_ownership.dart';
import 'ble_engine.dart';

class IosBleRestore {
  static const _ch = MethodChannel('openstrap/ble_restore');

  /// Set true while the app holds a live foreground session (BleEngine connected).
  /// A wake-triggered headless sync would otherwise fight flutter_blue_plus for the
  /// band, so we skip it — the foreground session is already draining.
  static bool foregroundActive = false;

  @visibleForTesting
  static Future<void> Function(String) logSink = FileLog.write;

  @visibleForTesting
  static bool Function()? debugBandLinkHeld;

  @visibleForTesting
  static int handoffMaxPolls = 80;

  @visibleForTesting
  static Duration handoffPoll = const Duration(milliseconds: 500);

  /// Register the wake handler and tell native Flutter is ready. Call once at startup.
  static Future<void> init() async {
    if (!Platform.isIOS) return;
    registerHandler();
    try {
      await _ch.invokeMethod('ready');
    } catch (_) {}
  }

  @visibleForTesting
  static void registerHandler() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'log') {
        if (call.arguments is String) {
          // Native lines carry their own timestamp and [ble-restore] tag.
          await logSink(call.arguments as String);
        }
        return null;
      }
      if (call.method != 'wake') return null;
      if (foregroundActive || BandOwnership.foregroundIntent) {
        await _ackWake();
        await _waitForForegroundLink();
        await _done();
        return null;
      }
      // Shared gate with the BGProcessingTask/BGAppRefreshTask entry points
      // (HeadlessSyncGate): if another headless sync is mid-flight, skip this
      // wake without wakeAck or syncDone. Native's 60-second watchdog releases
      // this unaccepted handoff, including a connected restore peripheral.
      await HeadlessSyncGate.tryRun<void>('ble_restore_wake', () async {
        await _ackWake();
        try {
          await runHeadlessSync();
        } catch (e) {
          debugPrint('[ios-restore] headless sync threw: $e');
        } finally {
          await _done();
        }
      });
      return null;
    });
  }

  /// Tell native whether the app currently owns the live connection (via
  /// flutter_blue_plus). While true, the restore central must NOT arm a competing
  /// pending connect to the same peripheral. Set false (then [arm]) to hand the band
  /// to the restore path for background relaunch.
  static Future<void> setOwnsBand(bool owns) async {
    if (!Platform.isIOS) return;
    try {
      await _ch.invokeMethod('setOwnsBand', owns);
    } catch (_) {}
  }

  /// Tell native that an accessory was just provisioned via the ASK picker (first-time
  /// pairing). This is the cue for the native restore central to be CREATED — it is
  /// deliberately deferred at launch on a fresh install so the ASK picker can be shown
  /// with NO CBCentralManager alive (else `showPicker` fails with "CBManager is active
  /// with global permissions"). Must be called BEFORE any flutter_blue_plus call.
  static Future<void> provisioned(String remoteId) async {
    if (!Platform.isIOS) return;
    try {
      await _ch.invokeMethod('provisioned', remoteId);
    } catch (_) {}
  }

  /// Arm restoration for this band (its iOS peripheral UUID == PairedDevice.remoteId).
  static Future<void> arm(String remoteId) async {
    if (!Platform.isIOS) return;
    try {
      await _ch.invokeMethod('arm', remoteId);
    } catch (_) {}
  }

  /// Atomic recovery hand-off for the hot disconnect path: combines
  /// [setOwnsBand]\(false\) + [arm] into ONE native round trip instead of two
  /// separately-awaited calls. Two calls left a window — a process suspension
  /// between them — where `appOwnsBand` could already be false with nothing
  /// armed to replace it, i.e. no one left watching for the band at all. The
  /// native side also wraps this in a short `beginBackgroundTask` extension.
  /// See `AppState._armRecovery`.
  static Future<void> armRecoveryNow(String remoteId) async {
    if (!Platform.isIOS) return;
    foregroundActive = false;
    try {
      await _ch.invokeMethod('armRecoveryNow', remoteId);
    } catch (_) {}
  }

  /// Stop restoration (sign-out / unpair).
  static Future<void> disarm() async {
    if (!Platform.isIOS) return;
    try {
      await _ch.invokeMethod('disarm');
    } catch (_) {}
  }

  /// Arm restoration for a SET of bands in one round trip. Native accepts either a
  /// String (one band, today's [arm]) or a list.
  ///
  /// NOT called in M4: Dart's arm policy stays primary-only (see §7.3's ceiling —
  /// only the primary gets background restore on iOS). This exists so the native
  /// side has a Dart-side counterpart to test against, and so the day a second
  /// framed band is background-restorable the change is one call site, not a
  /// channel redesign.
  static Future<void> armAll(List<String> remoteIds) async {
    if (!Platform.isIOS || remoteIds.isEmpty) return;
    try {
      await _ch.invokeMethod('arm', remoteIds);
    } catch (_) {}
  }

  /// Forget ONE band's restoration without touching the others. [disarm] with no
  /// argument still means "forget everything", which is what unpair wants.
  static Future<void> disarmOne(String remoteId) async {
    if (!Platform.isIOS) return;
    try {
      await _ch.invokeMethod('disarm', remoteId);
    } catch (_) {}
  }

  /// Release the restore central WITHOUT forgetting any band — the ASK-picker
  /// prerequisite. See devices.dart's addFramedBand flow; this is NOT [disarm], and
  /// confusing the two loses the primary's restore key.
  static Future<void> releaseCentralForPicker() async {
    if (!Platform.isIOS) return;
    try {
      await _ch.invokeMethod('releaseCentralForPicker');
    } catch (_) {}
  }

  static Future<void> _waitForForegroundLink() async {
    bool held() => debugBandLinkHeld?.call() ?? BleEngine.anyBandLinkHeld;
    if (held()) return;
    var polls = 0;
    while (!held() && polls < handoffMaxPolls) {
      await Future<void>.delayed(handoffPoll);
      polls++;
    }
    await logSink(
      held()
          ? '[ble-restore] foreground link taken over after $polls polls'
          : '[ble-restore] foreground link not taken over after $polls polls',
    );
  }

  static Future<void> _ackWake() async {
    try {
      await _ch.invokeMethod('wakeAck');
    } catch (_) {}
  }

  static Future<void> _done() async {
    try {
      await _ch.invokeMethod('syncDone');
    } catch (_) {}
  }
}
