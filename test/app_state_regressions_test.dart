// Regression tests for a batch of AppState state-machine bugs.
//
// AppState.forTesting() builds the object graph WITHOUT running _init() and
// without touching a single platform plugin, so the logic below can be driven
// directly. Each group names the bug it guards.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/ble/ble_state.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/health/health_export.dart';
import 'package:openstrap_edge/notify/notification_center.dart';
import 'package:openstrap_edge/notify/notification_event.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/sync/headless_gate.dart';
import 'package:openstrap_edge/state/alarm_cancel.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/sync/paired_device.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart' as proto;

class _DisableEngine extends BleEngine {
  _DisableEngine()
      : super(onRecord: (_, _) async {}, onState: (_) {});

  AlarmDisableOutcome nextDisable = AlarmDisableOutcome.written;
  int disableCalls = 0;
  DateTime? lastSet;
  DateTime? setReturns;
  int setCalls = 0;
  Completer<AlarmDisableOutcome>? stallDisable;
  Completer<DateTime?>? stallSet;

  @override
  Future<AlarmOperationResult> applyAlarmIntent({DateTime? when, bool readOnly = false}) async {
    if (when == null) return AlarmOperationResult(disableOutcome: await disableAlarm());
    return AlarmOperationResult(armed: readOnly ? when : await setAlarm(when));
  }

  @override
  Future<AlarmDisableOutcome> disableAlarm({int? id}) async {
    disableCalls++;
    if (stallDisable != null) return stallDisable!.future;
    return nextDisable;
  }

  @override
  Future<DateTime?> setAlarm(
    DateTime when, {
    int index = 0,
    List<int>? haptics,
  }) async {
    setCalls++;
    lastSet = when;
    if (stallSet != null) return stallSet!.future;
    return setReturns ?? when;
  }
}

/// Real SET orchestration / command awaiter; only GATT is synthetic. Hold a
/// correlated reply AFTER its SET write so AppState receives lifecycle events
/// while the production command future (not an overridden setAlarm) is pending.
class _HeldAlarmReply {
  final int holdSetAt;
  final bool holdClock;
  final clockEntered = Completer<void>();
  final releaseClock = Completer<void>();
  final sent = Completer<void>();
  final opcodes = <int>[];
  late final BleEngine engine;
  late final AppState app;
  int _sets = 0;
  int? _heldSeq;

  _HeldAlarmReply({this.holdSetAt = 1, this.holdClock = false}) {
    engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {},
      onEvent: (id, ts, _) => app.debugHandleAlarmEvent(id, ts: ts));
    app = AppState.forTesting(engine: engine);
    app.device.connection = 'connected';
    engine.debugInstallFakeLink(
      band: proto.BandProfile.gen5,
      onWrite: (frame) async {
        final inner = proto.parseFrame(frame, profile: proto.BandProfile.gen5)!.inner;
        final opcode = inner[2];
        opcodes.add(opcode);
        if (holdClock && opcode == proto.Cmd.setClock) {
          clockEntered.complete();
          await releaseClock.future;
        }
        if (opcode == proto.Cmd.setAlarmTime && ++_sets == holdSetAt) {
          _heldSeq = inner[1];
          sent.complete();
        } else {
          _reply(inner[1], opcode);
        }
        return true;
      },
    );
  }

  void _reply(int seq, int opcode) => engine.debugAbsorbDecoded(
    proto.Decoded('cmd_response', {
      'opcode': opcode, 'req_seq': seq,
      'cmd_status': CommandAwaiter.statusSuccess,
    }),
  );

  void completeSet() => _reply(_heldSeq!, proto.Cmd.setAlarmTime);

  void event(int id, {int ts = 1, String role = 'events'}) {
    // Synthetic documented EVENT envelope, parsed by protocol and routed by
    // the real engine. It contains no echoed request or alarm target.
    final inner = Uint8List(12);
    inner[0] = proto.PacketType.event;
    inner[1] = 77;
    final bytes = ByteData.sublistView(inner);
    bytes.setUint16(2, id, Endian.little);
    bytes.setUint32(4, ts, Endian.little);
    final decoded = proto.parseEvent(inner, profile: proto.BandProfile.gen5)!;
    expect(decoded.decoded['req_seq'], isNull);
    expect(decoded.decoded['alarm_epoch'], isNull);
    engine.debugReceiveFrame(proto.Frame(inner, true, true), role: role);
  }
}

/// Actual engine failure handling; the hook replaces only GATT, not policy.
class _FailingCommand {
  final bool off;
  String mode;
  Future<void> Function()? beforeFailure;
  late final BleEngine engine;
  _FailingCommand({this.off = false, this.mode = 'writeFailed'}) {
    engine = BleEngine(onRecord: (_, _) async {}, onState: (_) {});
    engine.debugInstallFakeLink(band: proto.BandProfile.gen4, onWrite: (frame) async {
      final inner = proto.parseFrame(frame, profile: proto.BandProfile.gen4)!.inner;
      final op = inner[2];
      final failing = op == (off ? proto.Cmd.disableAlarm : proto.Cmd.setAlarmTime);
      if (failing) {
        await beforeFailure?.call();
        if (mode == 'writeFailed') return false;
      }
      final response = proto.parseCommandResponse(Uint8List.fromList([
        proto.PacketType.commandResponse, 0x55, op,
        failing && mode == 'zeroRejected' ? 0 : inner[1],
        failing && (mode == 'rejected' || mode == 'zeroRejected') ? 0 : 1,
      ]), profile: proto.BandProfile.gen4)!;
      engine.debugAbsorbDecoded(proto.Decoded('cmd_response', {
        'opcode': response.opcode, ...response.decoded,
      }));
      return true;
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_app_state_regressions_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  setUp(() async {
    AlarmOwner.resetForTest();
    SharedPreferences.setMockInitialValues({});
    await LocalDb.clearAlarmSchedule();
  });

  group('actual alarm command failure notification', () {
    final events = <NotificationEvent>[];
    late Future<bool> Function(NotificationEvent, {bool allowPermissionPrompt}) oldSink;
    setUp(() async {
      HeadlessSyncGate.resetForTest();
      await (await LocalDb.instance).delete('notif_fired');
      events.clear();
      oldSink = NotificationCenter.instance.presentSink;
      NotificationCenter.instance.presentSink = (e, {bool allowPermissionPrompt = true}) async {
        events.add(e);
        return true;
      };
      await const NotificationPrefs(quietEnabled: false).save();
    });
    tearDown(() => NotificationCenter.instance.presentSink = oldSink);
    Future<void> seed(bool off) async {
      final old = DateTime.now().add(const Duration(hours: 5));
      final previous = await AlarmOwner.choose(AlarmDesired.manual, when: old);
      await AlarmOwner.observe(previous, epoch: old.millisecondsSinceEpoch ~/ 1000, applied: true);
      await AlarmOwner.choose(off ? AlarmDesired.off : AlarmDesired.manual,
        when: off ? null : old.add(const Duration(hours: 1)));
    }
    Future<void> fail(_FailingCommand w) async {
      if (w.off) {
        expect((await AlarmOwner.reconcile(w.engine))?.failed, isTrue);
      } else {
        await expectLater(AlarmOwner.reconcile(w.engine), throwsStateError);
      }
    }
    Future<void> yieldForQueuedEmit() async {
      for (var i = 0; i < 16; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    Future<void> runQueuedBehindUnrelated(
      bool off, {
      required Future<void> Function() whileQueued,
      bool expectSetThrow = false,
    }) async {
      final hold = Completer<void>();
      final occupying = Completer<void>();
      NotificationCenter.instance.presentSink =
          (e, {bool allowPermissionPrompt = true}) async {
        if (e.title == 'Alarmfehler') {
          events.add(e);
          return true;
        }
        if (!occupying.isCompleted) occupying.complete();
        await hold.future;
        return true;
      };
      final blocking = NotificationCenter.instance.emit(NotificationEvent(
        dedupeKey: 'queue-blocker',
        category: NotifCategory.device,
        priority: NotifPriority.critical,
        title: 'blocker',
        body: 'b',
        date: todayLabel(),
      ));
      await occupying.future;
      final w = _FailingCommand(off: off);
      final gattDone = Completer<void>();
      w.beforeFailure = () async { gattDone.complete(); };
      final running = AlarmOwner.reconcile(w.engine);
      await gattDone.future;
      await yieldForQueuedEmit();
      try {
        await whileQueued();
      } finally {
        if (!hold.isCompleted) hold.complete();
      }
      if (expectSetThrow && !off) {
        await expectLater(running, throwsStateError);
      } else {
        await running;
      }
      await blocking;
      await yieldForQueuedEmit();
    }
    for (final off in [false, true]) {
      for (final mode in ['writeFailed', 'rejected']) {
        test('${off ? "DISABLE" : "SET"} $mode emits once, retains prior possibility', () async {
          await seed(off);
          final prior = (await AlarmOwner.load()).armedEpoch;
          final w = _FailingCommand(off: off, mode: mode);
          await fail(w);
          await fail(w);
          expect(events, hasLength(1));
          expect(events.single.title, 'Alarmfehler');
          expect(events.single.category, NotifCategory.device);
          expect(events.single.body, contains('weiterhin gespeichert'));
          expect((await AlarmOwner.load()).armedEpoch, prior);
          expect((await AlarmOwner.load()).disableWritten, isFalse);
          expect(AlarmOwner.readbackFor(w.engine, (await AlarmOwner.load()).generation).state,
            AlarmReadbackState.unknown);
        });
      }
      for (final pref in ['alarm', 'device', 'quiet']) {
        test('${off ? "DISABLE" : "SET"} preference $pref suppresses', () async {
          await seed(off);
          final minute = DateTime.now().hour * 60 + DateTime.now().minute;
          await NotificationPrefs(alarmLatchFailedEnabled: pref != 'alarm',
            deviceEnabled: pref != 'device', quietEnabled: pref == 'quiet',
            quietStartMin: minute, quietEndMin: (minute + 60) % 1440,
            criticalOverridesQuiet: false).save();
          await fail(_FailingCommand(off: off));
          expect(events, isEmpty);
          await const NotificationPrefs(quietEnabled: false).save();
          await fail(_FailingCommand(off: off));
          expect(events, hasLength(1), reason: 'suppression must not consume dedupe');
        });
      }
      test('${off ? "DISABLE" : "SET"} stale generation never emits', () async {
        await seed(off);
        final w = _FailingCommand(off: off);
        final entered = Completer<void>(), release = Completer<void>();
        w.beforeFailure = () async { entered.complete(); await release.future; };
        final running = AlarmOwner.reconcile(w.engine);
        await entered.future;
        final latest = await AlarmOwner.choose(AlarmDesired.manual,
          when: DateTime.now().add(const Duration(days: 2)));
        release.complete();
        await running;
        expect(events, isEmpty);
        expect((await AlarmOwner.load()).generation, latest.generation);
      });
      test('${off ? "DISABLE" : "SET"} reconnect cancellation never emits', () async {
        await seed(off);
        final w = _FailingCommand(off: off);
        w.beforeFailure = () async {
          w.engine.debugInstallFakeLink(band: proto.BandProfile.gen4, onWrite: (_) async => true);
        };
        await fail(w);
        expect(events, isEmpty);
      });
      test('${off ? "DISABLE" : "SET"} active headless failure does not request permission', () async {
        await seed(off);
        NotificationCenter.instance.presentSink = (e, {bool allowPermissionPrompt = true}) async {
          expect(allowPermissionPrompt, isFalse);
          events.add(e);
          return true;
        };
        await HeadlessSyncGate.tryRun('alarm-failure', () => fail(_FailingCommand(off: off)));
        expect(events, hasLength(1));
      });
      test('${off ? "DISABLE" : "SET"} revoked lease never emits', () async {
        await seed(off);
        final w = _FailingCommand(off: off);
        w.beforeFailure = () async { HeadlessSyncGate.currentLease!.revoke(); };
        await HeadlessSyncGate.tryRun('alarm-failure', () async {
          await AlarmOwner.reconcile(w.engine);
        });
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
      });
      for (final mode in ['unknown', 'zeroRejected']) {
        test('${off ? "DISABLE" : "SET"} $mode never emits', () async {
          await seed(off);
          final w = _FailingCommand(off: off, mode: mode);
          if (mode == 'zeroRejected') {
            await fail(w);
          } else {
            await AlarmOwner.reconcile(w.engine);
          }
          expect(events, isEmpty);
        });
      }
      test('${off ? "DISABLE" : "SET"} queued emit after newer choose never presents', () async {
        await seed(off);
        await runQueuedBehindUnrelated(off, whileQueued: () async {
          await AlarmOwner.choose(AlarmDesired.manual,
            when: DateTime.now().add(const Duration(days: 2)));
        });
        expect(events, isEmpty);
      });
      test('${off ? "DISABLE" : "SET"} queued emit after lease revoke never presents', () async {
        await seed(off);
        await HeadlessSyncGate.tryRun('alarm-failure', () async {
          await runQueuedBehindUnrelated(off, whileQueued: () async {
            HeadlessSyncGate.currentLease!.revoke();
          });
        });
        expect(events, isEmpty);
        await fail(_FailingCommand(off: off));
        expect(events, hasLength(1), reason: 'aborted present must not consume dedupe');
      });
    }
    test('queued emit with unchanged generation still presents once', () async {
      await seed(false);
      await runQueuedBehindUnrelated(false, expectSetThrow: true, whileQueued: () async {});
      expect(events, hasLength(1));
      expect(events.single.title, 'Alarmfehler');
      await fail(_FailingCommand(off: false));
      expect(events, hasLength(1));
    });
  });

  // ── 1. the serial heal must never RE-PAIR a band the user just unpaired ─────
  group('healedPairing (stale engine-state callback after unpair)', () {
    test('an unpaired app is NEVER re-paired from a stale engine state', () {
      // BleEngine._teardownSession leaves state.serial/state.address set, so a
      // late onState (e.g. the reconnect loop's finally → clearReconnecting →
      // _setPhase(idle) → onState) arrives with a perfectly clean serial long
      // after unpair() ran. The old guard (`cleanSn != paired?.serial`) was
      // TRUE for paired == null and rebuilt a PairedDevice from state.address,
      // silently re-pairing the removed band and bouncing the app back to the
      // Shell.
      expect(healedPairing(null, '4C2248092'), isNull);
      expect(healedPairing(null, "Abdul's WHOOP"), isNull);
    });

    test('an EXISTING pairing still gets its junk serial healed', () {
      final healed = healedPairing(PairedDevice('r-1', '?*?*'), '4C2248092');
      expect(healed, isNotNull);
      expect(healed!.remoteId, 'r-1');
      expect(healed.serial, '4C2248092');
    });

    test('a pairing with no serial yet gets one', () {
      expect(healedPairing(PairedDevice('r-1', null), '4C2248092')?.serial,
          '4C2248092');
    });

    test('no change when the serial already matches, or the report is junk',
        () {
      expect(healedPairing(PairedDevice('r-1', '4C2248092'), '4C2248092'),
          isNull);
      expect(healedPairing(PairedDevice('r-1', '4C2248092'), '?*?*'), isNull);
      expect(healedPairing(PairedDevice('r-1', '4C2248092'), null), isNull);
      expect(healedPairing(PairedDevice('r-1', '4C2248092'), '   '), isNull);
    });

    test('the remoteId is never invented — it always comes from the pairing',
        () {
      // Even with a clean serial, an empty remoteId means there is nothing
      // legitimate to write back.
      expect(healedPairing(PairedDevice('', null), '4C2248092'), isNull);
    });
  });

  // ── 5. (removed) the step-calibration live-consumer latch ─────────────────
  // The guided calibration walk was deleted in v56 along with the 1 Hz step
  // estimator that was its only consumer, so there is no longer an arming path
  // that can latch `_hasLiveConsumer`. The spot-check and workout consumers
  // keep their own latch coverage.

  // ── 6. `busy` must not latch true forever ──────────────────────────────────
  group('openSession (busy latch)', () {
    test('unpairing while the session is opening does not wedge busy',
        () async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      app.paired = PairedDevice('r-1', '4C2248092');
      // Simulate the user tapping Unpair inside openSession's own resume
      // window: the first thing openSession does after flipping busy is
      // notify, and unpair() nulls `paired`.
      app.addListener(() => app.paired = null);

      // Pre-fix this THREW (`paired!` sat outside the try) and left busy true,
      // so every later openSession()/syncNow() no-opped — "Sync now" was dead
      // until the process restarted.
      await app.openSession();

      expect(app.busy, isFalse);
      expect(app.paired, isNull);
      // And the state machine is genuinely usable again.
      await app.syncNow();
      expect(app.busy, isFalse);
    });
  });

  // ── 7. the orphan-workout reconcile must not clobber a live workout ────────
  group('_reconcileOrphanedLiveWorkout (startWorkout race)', () {
    test('a workout started inside the DB round-trip is not overwritten',
        () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await LocalDb.putSession({
        'id': 'stale-from-a-killed-run',
        'start_ts': nowSec - 600,
        'end_ts': null,
        'type': 'other',
        'status': 'live',
        'source': 'manual',
        'created_at': (nowSec - 600) * 1000,
      });

      final app = AppState.forTesting();
      addTearDown(app.dispose);

      // Kicked unawaited from _init(), one line before `initialized = true`
      // makes the shell interactive — so the user can start a workout inside
      // the round-trip.
      final reconcile = app.debugReconcileOrphanedLiveWorkout();
      app.activeWorkout = LiveWorkoutState(
        startTime: DateTime.now(),
        targetKcal: 300,
        workoutId: 'user-just-started-this',
        type: 'run',
      );
      await reconcile;

      expect(app.activeWorkout?.workoutId, 'user-just-started-this',
          reason: 'the stale row must never replace a genuinely live workout '
              '(the old timer became unreachable and double-counted at 2 Hz)');
    });

    test('with nothing live, a recent orphan is still resumed', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await LocalDb.putSession({
        'id': 'resumable',
        'start_ts': nowSec - 300,
        'end_ts': null,
        'type': 'run',
        'status': 'live',
        'source': 'manual',
        'created_at': (nowSec - 300) * 1000,
      });

      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await app.debugReconcileOrphanedLiveWorkout();
      expect(app.activeWorkout?.workoutId, 'resumable');
    });

    test('a resumed session keeps its ceiling, so the idle gate exists',
        () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await LocalDb.putSession({
        'id': 'resumable-gated',
        'start_ts': nowSec - 300,
        'end_ts': null,
        'type': 'run',
        'status': 'live',
        'source': 'manual',
        'created_at': (nowSec - 300) * 1000,
      });

      final app = AppState.forTesting();
      addTearDown(app.dispose);
      app.user = {'birth_date': '${DateTime.now().year - 31}-12-31'};
      await app.debugReconcileOrphanedLiveWorkout();

      expect(app.activeWorkout?.hrMax, closeTo(208.0 - 0.7 * 30, 1e-9),
          reason: 'without the ceiling the idle gate is null and '
              'WorkoutIdleWatch counts any positive reading as active — a '
              'forgotten session sitting at resting HR would never be asked '
              'about after an app restart, the exact case the watch is for');
    });

    test('a stale (past-ceiling) orphan is finalized locally but NEVER '
        'exported to Health', () async {
      // Its real end time is unknown — the reconcile stamps end_ts to
      // reconcile-time as an honest "we closed this out", not a fact. Writing
      // that fabricated span to Apple Health / Health Connect as a real
      // workout would be a lie in the user's own health records.
      const channel = MethodChannel('flutter_health');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return call.method == 'hasPermissions' ? false : true;
          });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      SharedPreferences.setMockInitialValues({kHealthSyncPref: true});

      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      const staleId = 'stale-past-ceiling';
      await LocalDb.putSession({
        'id': staleId,
        'start_ts': nowSec - 7 * 60 * 60, // 7h old, past the 6h ceiling
        'end_ts': null,
        'type': 'run',
        'status': 'live',
        'source': 'manual',
        'created_at': (nowSec - 7 * 60 * 60) * 1000,
      });

      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await app.debugReconcileOrphanedLiveWorkout();
      // exportWorkoutId is fired unawaited from the reconcile; give it a
      // chance to run before asserting nothing came through.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(calls, isEmpty,
          reason: 'a stale orphan has a fabricated end_ts and must never '
              'reach the platform health store');
      final row = await LocalDb.session(staleId);
      expect(row?['status'], 'done');
      expect(row?['end_ts'], isNotNull);
      expect(row?['end_ts_fabricated'], 1,
          reason: 'without this flag the row looks like any other finished '
              'workout and _writeOneWorkout would export it on the very next '
              'periodic exportAll pass, minutes later');
    });
  });

  // ── 9. a fired alarm must be cleared from state AND prefs ──────────────────
  group('alarm lifecycle (fired / strap-cleared)', () {
    final originalSink = NotificationCenter.instance.presentSink;
    tearDown(() => NotificationCenter.instance.presentSink = originalSink);

    Future<void> silenceOsPresent() async {
      NotificationCenter.instance.presentSink =
          (NotificationEvent e, {bool allowPermissionPrompt = true}) async =>
              true;
    }

    test('EXECUTED (event 57) clears the armed alarm and its persisted epoch',
        () async {
      SharedPreferences.setMockInitialValues({'alarm_epoch': 1785000000});
      await silenceOsPresent();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await app.debugRestoreAlarmFromPrefs();
      expect(app.alarmEpoch, 1785000000);

      app.debugHandleAlarmEvent(57);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Pre-fix this only logged + notified: alarmEpoch kept returning the past
      // epoch across relaunches (_init reloads `alarm_epoch`) and Profile's
      // "Smart alarm" row advertised a spent one-shot as the CURRENT alarm.
      expect(app.alarmEpoch, isNull);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(AlarmIntent.decode(prefs.getString(AlarmOwner.intentKey)!).armedEpoch, isNull);
      // `alarmFiredAt` had no reader in lib (alarm.dart derives its own arm
      // state from alarmConfirmed/alarmPending), so the getter is gone and
      // with it the only thing this line could assert on.
    });

    test('the app-side EXECUTED id (58) clears it too', () async {
      SharedPreferences.setMockInitialValues({'alarm_epoch': 1785000000});
      await silenceOsPresent();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await app.debugRestoreAlarmFromPrefs();

      app.debugHandleAlarmEvent(58);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(app.alarmEpoch, isNull);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(AlarmIntent.decode(prefs.getString(AlarmOwner.intentKey)!).armedEpoch, isNull);
    });

    test('historical event 59 preserves the persisted epoch',
        () async {
      SharedPreferences.setMockInitialValues({'alarm_epoch': 1785000000});
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await app.debugRestoreAlarmFromPrefs();

      app.debugHandleAlarmEvent(59);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(app.alarmEpoch, 1785000000);
      expect((await AlarmOwner.load()).armedEpoch, 1785000000);
      expect(app.alarmConfirmed, isFalse);
    });

    test('ALARM_SET (event 56) keeps epoch but cannot confirm current arm', () async {
      final epoch = DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;
      SharedPreferences.setMockInitialValues({'alarm_epoch': epoch});
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await app.debugRestoreAlarmFromPrefs();
      app.debugHandleAlarmEvent(56);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(app.alarmEpoch, epoch);
      expect(app.alarmConfirmed, isFalse);
      expect((await AlarmOwner.load()).armedEpoch, epoch);
    });
  });

  // ── 10. dispose must release EVERYTHING AppState owns ──────────────────────
  group('dispose', () {
    testWidgets('cancels every owned timer', (t) async {
      final app = AppState.forTesting();
      // _spotTimer, _breathingRecomputeTimer and _workoutTimer used to survive
      // dispose; each callback ends in notifyListeners() on a disposed
      // ChangeNotifier. An outstanding Timer fails this test outright.
      app.debugArmOwnedTimers();
      app.dispose();
    });

    testWidgets('disposes every owned notifier/observer', (t) async {
      final app = AppState.forTesting();
      app.dispose();
      void addTo(void Function(VoidCallback) add) =>
          expect(() => add(() {}), throwsA(isA<FlutterError>()));
      addTo(app.navRequest.addListener);
      addTo(app.screenRequest.addListener);
      addTo(app.insightsRevision.addListener);
      addTo(app.gestureSettings.addListener);
      // NotificationRelay holds a WidgetsBindingObserver, a 15-min heal
      // Timer.periodic and a StreamSubscription — its observer accumulated on
      // the binding across every hot restart.
      addTo(app.notificationRelay.addListener);
    });
  });

  // ── live HR must be a reading of NOW, not the last one the engine saw ───────
  group('AppState.liveHr freshness', () {
    int now() => DateTime.now().millisecondsSinceEpoch;

    AppState connected(int? hr, {int ageMs = 0}) {
      final app = AppState.forTesting();
      app.device.connection = 'connected';
      app.device.liveHr = hr;
      app.device.liveHrAt = hr == null ? null : now() - ageMs;
      return app;
    }

    test('a fresh reading from a connected band is the reading', () {
      final app = connected(142);
      addTearDown(app.dispose);
      expect(app.liveHr, 142);
    });

    test('a reading older than the window is absent, not stale', () {
      // Nothing clears DeviceState.liveHr on an unintentional drop —
      // _teardownSession never calls disableLiveStreams — so the raw field
      // reads like a measurement forever. 30 s is well past liveHrMaxAge (10 s).
      final app = connected(142, ageMs: 30 * 1000);
      addTearDown(app.dispose);
      expect(app.liveHr, isNull);
    });

    test('a disconnected band has no live HR however fresh the value looks',
        () {
      final app = connected(142);
      addTearDown(app.dispose);
      app.device.connection = 'disconnected';
      expect(app.liveHr, isNull);
    });

    test('the tick bills a fresh reading and skips an absent one', () {
      final app = connected(150);
      addTearDown(app.dispose);
      final w = LiveWorkoutState(
        startTime: DateTime.now().subtract(const Duration(minutes: 5)),
        targetKcal: 300,
        workoutId: 'w1',
        type: 'run',
      );
      app.activeWorkout = w;

      app.debugTickWorkout();
      expect(w.currentHr, 150);
      final billed = w.zoneSeconds.reduce((x, y) => x + y);
      final peak = w.maxHrSeen; // rolling-median, so not 150 off one sample
      expect(billed, 1, reason: 'one tick, one second in a zone');

      // The band drops mid-workout: the engine keeps its last value, the tick
      // must not keep billing it. Pre-fix this read `device.liveHr ?? 0` and
      // charged the stale 150 into zone-seconds, calories and strain for the
      // rest of the session, then persisted it on stop.
      app.device.liveHrAt = now() - 60 * 1000;
      app.debugTickWorkout();
      expect(w.currentHr, isNull, reason: 'absent is not zero');
      expect(w.zoneSeconds.reduce((x, y) => x + y), billed,
          reason: 'no zone-second for a second with no measurement');
      expect(w.maxHrSeen, peak, reason: 'the peak is untouched by an absence');
    });

    test('the tick consults the idle watch — a quiet session asks', () {
      // The wiring, not the policy (workout_idle_test.dart owns the policy):
      // a session 30 minutes old with no live HR must have produced an ask by
      // the end of one tick, and a session with real HR must not have.
      final app = connected(null);
      addTearDown(app.dispose);
      final w = LiveWorkoutState(
        startTime: DateTime.now().subtract(const Duration(minutes: 30)),
        targetKcal: 300,
        workoutId: 'w1',
        type: 'run',
      );
      app.activeWorkout = w;
      app.debugTickWorkout();
      expect(w.idleWatch.lastAskAt, isNotNull,
          reason: '30 quiet minutes into an open session, the watch asks');

      final active = connected(150);
      addTearDown(active.dispose);
      final w2 = LiveWorkoutState(
        startTime: DateTime.now().subtract(const Duration(minutes: 30)),
        targetKcal: 300,
        workoutId: 'w2',
        type: 'run',
      );
      active.activeWorkout = w2;
      active.debugTickWorkout();
      expect(w2.idleWatch.lastAskAt, isNull,
          reason: 'a real reading (no gate → any reading) is activity');
    });
  });

  group('durable last explicit alarm intent', () {
    DateTime target() => DateTime.now().add(const Duration(days: 1));
    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));
    Future<AppState> armed({AlarmDisableOutcome outcome = AlarmDisableOutcome.written}) async {
      final engine = _DisableEngine()..nextDisable = outcome;
      final app = AppState.forTesting(engine: engine);
      addTearDown(app.dispose);
      app.device.connection = 'connected';
      await app.setAlarm(target());
      return app;
    }

    for (final outcome in AlarmDisableOutcome.values) {
      test('$outcome preserves desired-off and never claims confirmed-off', () async {
        final app = await armed(outcome: outcome);
        final epoch = app.alarmEpoch;
        final request = app.disableAlarm();
        if (outcome == AlarmDisableOutcome.writeFailed || outcome == AlarmDisableOutcome.rejected) {
          await expectLater(request, throwsException);
        } else {
          await request;
        }
        expect(app.alarmEpoch, epoch);
        expect(app.alarmDisableOutstanding, isTrue);
        expect(app.alarmConfirmed, isFalse);
        expect((await AlarmOwner.load()).desired, AlarmDesired.off);
        expect(app.alarmSchedule.any((e) => e.enabled), isFalse);
        app.debugHandleAlarmEvent(59);
        await settle();
        expect(app.alarmEpoch, epoch);
        expect(app.alarmDisableOutstanding, isTrue);
        final restored = AppState.forTesting();
        addTearDown(restored.dispose);
        await restored.debugRestoreAlarmFromPrefs();
        expect(restored.alarmDisableOutstanding, isTrue);
      });
    }

    test('offline off and offline weekly edit survive restart', () async {
      final app = await armed();
      app.device.connection = 'disconnected';
      await app.disableAlarm();
      expect((await AlarmOwner.load()).desired, AlarmDesired.off);
      await app.setScheduleDay(weekday: 0, hour: 7, enabled: true);
      final restored = AppState.forTesting(engine: _DisableEngine());
      addTearDown(restored.dispose);
      await restored.debugRestoreAlarmFromPrefs();
      expect(restored.alarmSchedule[0].enabled, isTrue);
      restored.device.connection = 'connected';
      await restored.debugArmNextAlarmOccurrence();
      expect((restored.engine as _DisableEngine).setCalls, 1);
      expect(restored.alarmDisableOutstanding, isFalse);
    });

    test('manual supersedes weekly across automatic reconnect and restart', () async {
      final app = await armed();
      await app.setScheduleDay(weekday: 0, enabled: true);
      final when = target().add(const Duration(hours: 3));
      await app.setAlarm(when);
      final sets = (app.engine as _DisableEngine).setCalls;
      await app.debugArmNextAlarmOccurrence();
      expect((app.engine as _DisableEngine).setCalls, sets);
      final restored = AppState.forTesting();
      addTearDown(restored.dispose);
      await restored.debugRestoreAlarmFromPrefs();
      expect(restored.alarmEpoch, when.millisecondsSinceEpoch ~/ 1000);
      expect((await AlarmOwner.load()).desired, AlarmDesired.manual);
    });

    test('off / SET persistence failure prevents radio effects', () async {
      final app = await armed();
      final engine = app.engine as _DisableEngine;
      final before = await AlarmOwner.load();
      AlarmOwner.debugWrite = (_, _, _) async => false;
      await expectLater(app.disableAlarm(), throwsStateError);
      expect(engine.disableCalls, 0);
      expect((await AlarmOwner.load()).generation, before.generation);
      AlarmOwner.debugWrite = null;
      await app.disableAlarm();
      final sets = engine.setCalls;
      AlarmOwner.debugWrite = (_, _, _) async => false;
      await expectLater(app.setAlarm(target()), throwsStateError);
      await expectLater(app.setScheduleDay(weekday: 0, enabled: true), throwsStateError);
      expect(engine.setCalls, sets);
      expect((await AlarmOwner.load()).desired, AlarmDesired.off);
    });

    test('held markPending then newer SET is serialized in durable order', () async {
      final app = await armed();
      final entered = Completer<void>();
      final release = Completer<void>();
      AlarmOwner.debugWrite = (p, key, value) async {
        if (AlarmIntent.decode(value).desired == AlarmDesired.off && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
        return p.setString(key, value);
      };
      final cancel = app.disableAlarm();
      await entered.future;
      final when = target().add(const Duration(hours: 2));
      final set = app.setAlarm(when);
      release.complete();
      await Future.wait([cancel, set]);
      final intent = await AlarmOwner.load();
      expect(intent.desired, AlarmDesired.manual);
      expect(intent.armedEpoch, when.millisecondsSinceEpoch ~/ 1000);
      final restored = AppState.forTesting();
      addTearDown(restored.dispose);
      await restored.debugRestoreAlarmFromPrefs();
      restored.debugHandleAlarmEvent(59);
      expect(restored.alarmConfirmed, isFalse);
      expect(restored.alarmEpoch, intent.armedEpoch);
    });

    test('stale observation after newer SET cannot overwrite intent or epoch', () async {
      final app = await armed();
      await app.disableAlarm();
      final old = await AlarmOwner.load();
      final when = target().add(const Duration(hours: 2));
      await app.setAlarm(when);
      expect(await AlarmOwner.observe(old, disableWritten: true), isFalse);
      expect((await AlarmOwner.load()).armedEpoch, when.millisecondsSinceEpoch ~/ 1000);
      expect((await AlarmOwner.load()).desired, AlarmDesired.manual);
    });

    test('old56 in gen5 clock preparation and replay after SET/restart proves no current arm', () async {
      final wire = _HeldAlarmReply(holdClock: true);
      final app = wire.app;
      addTearDown(app.dispose);
      final when = target();
      final pending = app.setAlarm(when);
      await wire.clockEntered.future;
      expect(wire.opcodes, [proto.Cmd.setClock]);
      wire.event(56, ts: 1);
      expect((await AlarmOwner.load()).confirmed, isFalse);
      expect(app.alarmEpoch, isNull);
      expect(app.alarmPending, isFalse, reason: 'desired target alone is not a written arm');
      expect(app.alarmConfirmed, isFalse);
      wire.releaseClock.complete();
      await wire.sent.future;
      // Same old history event, now AFTER the SET opcode, through the real
      // data-role router. Neither its channel nor later arrival is causality.
      wire.event(56, ts: 1, role: 'data');
      expect((await AlarmOwner.load()).confirmed, isFalse);
      wire.completeSet();
      await pending;
      expect(app.alarmEpoch, when.millisecondsSinceEpoch ~/ 1000);
      final generation = (await AlarmOwner.load()).generation;
      for (final ts in [1, DateTime.now().millisecondsSinceEpoch ~/ 1000,
          when.millisecondsSinceEpoch ~/ 1000 + 90]) {
        wire.event(56, ts: ts);
        expect((await AlarmOwner.load()).confirmed, isFalse);
        expect(app.alarmConfirmed, isFalse);
      }
      final raw = (await SharedPreferences.getInstance()).getString(AlarmOwner.intentKey)!;
      AlarmOwner.resetForTest();
      SharedPreferences.setMockInitialValues({AlarmOwner.intentKey: raw});
      final restored = _HeldAlarmReply();
      addTearDown(restored.app.dispose);
      await restored.app.debugRestoreAlarmFromPrefs();
      restored.event(56, ts: 1, role: 'data');
      final after = await AlarmOwner.load();
      expect(after.generation, generation);
      expect(after.armedEpoch, when.millisecondsSinceEpoch ~/ 1000);
      expect(after.confirmed, isFalse);
      expect(restored.app.alarmConfirmed, isFalse);
    });

    test('legacy and JSON confirmation flags from historical56 are not trusted on restart', () async {
      final epoch = target().millisecondsSinceEpoch ~/ 1000;
      for (final stored in <Map<String, Object>>[
        {'alarm_epoch': epoch, 'alarm_epoch_confirmed': true},
        {AlarmOwner.intentKey: AlarmIntent(generation: 9,
          desired: AlarmDesired.manual, manualEpoch: epoch, armedEpoch: epoch,
          confirmed: true, applied: true).encode()},
      ]) {
        AlarmOwner.resetForTest();
        SharedPreferences.setMockInitialValues(stored);
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        await app.debugRestoreAlarmFromPrefs();
        expect(app.alarmEpoch, epoch);
        expect(app.alarmConfirmed, isFalse);
        expect((await AlarmOwner.load()).confirmed, isFalse);
      }
    });

    for (final route in ['manual', 'weekly']) {
      for (final later59 in [false, true]) {
        test('$route: uncorrelated 56 before reply stays uncertain across restart; later59=$later59', () async {
          final wire = _HeldAlarmReply(holdSetAt: route == 'grace' ? 2 : 1);
          final app = wire.app;
          addTearDown(app.dispose);
          final when = target();
          if (route == 'grace') await app.setAlarm(when);
          final Future<void> pending;
          if (route == 'weekly') {
            pending = app.setScheduleDay(weekday: when.weekday - 1,
              hour: when.hour, minute: when.minute, enabled: true);
          } else if (route == 'grace') {
            pending = app.debugOnAlarmGraceElapsed(when);
          } else {
            pending = app.setAlarm(when);
          }
          await wire.sent.future;
          expect(wire.engine.pendingCommandCount, 1);
          wire.event(56);
          final beforeReply = await AlarmOwner.load();
          expect(beforeReply.confirmed, isFalse,
            reason: '56 after write but before reply is still uncorrelated');
          if (later59) {
            app.debugHandleAlarmEvent(59);
            expect((await AlarmOwner.load()).confirmed, isFalse);
          }
          wire.completeSet();
          await pending;
          expect(app.alarmConfirmed, isFalse);
          final after = await AlarmOwner.load();
          expect(after.generation, beforeReply.generation);
          expect(after.applied, isTrue);
          expect(after.confirmed, isFalse);
          expect(after.armedEpoch, isNotNull);
          // Restore only the persisted record, with no owner/session memory.
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString(AlarmOwner.intentKey)!;
          AlarmOwner.resetForTest();
          SharedPreferences.setMockInitialValues({AlarmOwner.intentKey: raw});
          final restored = AppState.forTesting();
          addTearDown(restored.dispose);
          await restored.debugRestoreAlarmFromPrefs();
          expect(restored.alarmConfirmed, isFalse);
          expect(restored.alarmEpoch, after.armedEpoch);
          expect(restored.alarmDisableOutstanding, isFalse);
        });
      }
    }

    test('56 during old SET cannot resurrect a newer off intent', () async {
      final wire = _HeldAlarmReply();
      final app = wire.app;
      addTearDown(app.dispose);
      final set = app.setAlarm(target());
      await wire.sent.future;
      wire.event(56);
      expect((await AlarmOwner.load()).confirmed, isFalse);
      final cancel = app.disableAlarm();
      expect((await AlarmOwner.load()).desired, AlarmDesired.off);
      await settle();
      app.debugHandleAlarmEvent(56);
      app.debugHandleAlarmEvent(59);
      wire.completeSet();
      await Future.wait([set, cancel]);
      final after = await AlarmOwner.load();
      expect(after.desired, AlarmDesired.off);
      expect(after.confirmed, isFalse);
      expect(after.armedEpoch, isNull);
      expect(app.alarmDisableOutstanding, isTrue);
      expect(wire.opcodes.where((op) => op != proto.Cmd.getAlarmTime).last,
        proto.Cmd.disableAlarm);
    });

    test('56 during old SET cannot confirm a newer manual intent', () async {
      final wire = _HeldAlarmReply();
      final app = wire.app;
      addTearDown(app.dispose);
      final old = app.setAlarm(target());
      await wire.sent.future;
      wire.event(56);
      final confirmed = await AlarmOwner.load();
      expect(confirmed.confirmed, isFalse);
      final when = target().add(const Duration(hours: 1));
      final latest = app.setAlarm(when);
      expect((await AlarmOwner.load()).generation, confirmed.generation + 1);
      wire.completeSet();
      await Future.wait([old, latest]);
      final after = await AlarmOwner.load();
      expect(after.desired, AlarmDesired.manual);
      expect(after.armedEpoch, when.millisecondsSinceEpoch ~/ 1000);
      expect(after.confirmed, isFalse, reason: 'only the old SET received 56');
      expect(app.alarmConfirmed, isFalse);
    });

    test('same-generation next SET does not inherit the previous arm confirmation', () async {
      final wire = _HeldAlarmReply();
      final app = wire.app;
      addTearDown(app.dispose);
      app.device.connection = 'disconnected';
      final when = target();
      await app.setScheduleDay(weekday: when.weekday - 1,
        hour: when.hour, minute: when.minute, enabled: true);
      final intent = await AlarmOwner.load();
      await AlarmOwner.observe(intent, epoch: when.subtract(const Duration(days: 7))
        .millisecondsSinceEpoch ~/ 1000, confirmed: true, applied: true);
      await app.debugRestoreAlarmFromPrefs();
      app.device.connection = 'connected';
      final next = app.debugArmNextAlarmOccurrence();
      await wire.sent.future;
      expect((await AlarmOwner.load()).confirmed, isFalse);
      wire.completeSet();
      await next;
      expect((await AlarmOwner.load()).generation, intent.generation);
      expect(app.alarmConfirmed, isFalse);
    });

    test('delayed event merges current observation within the same generation', () async {
      final intent = await AlarmOwner.choose(AlarmDesired.manual, when: target());
      final epoch = target().millisecondsSinceEpoch ~/ 1000;
      await AlarmOwner.observe(intent, epoch: epoch, applied: true);
      // The event's UI snapshot predates the SET completion and has no epoch.
      await AlarmOwner.observeEvent(intent);
      expect((await AlarmOwner.load()).armedEpoch, epoch);
      expect((await AlarmOwner.load()).applied, isTrue);
      final off = await AlarmOwner.choose(AlarmDesired.off);
      await AlarmOwner.observe(off, epoch: epoch, disableWritten: true);
      await AlarmOwner.observeEvent(off);
      expect((await AlarmOwner.load()).disableWritten, isTrue);
      expect((await AlarmOwner.load()).desired, AlarmDesired.off);
    });

    test('crash after 59 before legacy schedule clear cannot resurrect rows', () async {
      await LocalDb.setAlarmScheduleDay(weekday: 0, hour: 7, minute: 0, enabled: true);
      final app = await armed();
      await app.disableAlarm();
      app.debugHandleAlarmEvent(59);
      await settle();
      // Deliberately never clear the old SQL schedule; simulate process death.
      expect((await LocalDb.alarmScheduleRows()).any((r) => r['enabled'] == 1), isTrue);
      AlarmOwner.resetForTest();
      final engine = _DisableEngine();
      final restored = AppState.forTesting(engine: engine);
      addTearDown(restored.dispose);
      await restored.debugRestoreAlarmFromPrefs();
      restored.device.connection = 'connected';
      await restored.debugArmNextAlarmOccurrence();
      expect(engine.setCalls, 0);
      expect(engine.disableCalls, 1);
      expect(restored.alarmDisableOutstanding, isTrue);
      // Same runner used by headless ignores those same rows.
      await AlarmOwner.reconcile(engine);
      expect(engine.setCalls, 0);
      expect(engine.disableCalls, 2);
    });

    test('old59 before and after new DISABLE write and restart stays unknown', () async {
      final app = await armed();
      await app.disableAlarm(); // A
      await app.setAlarm(target().add(const Duration(hours: 1))); // B
      final engine = app.engine as _DisableEngine;
      engine.stallDisable = Completer();
      final cancel = app.disableAlarm(); // C
      await settle();
      app.debugHandleAlarmEvent(59, ts: 100);
      expect(app.alarmConfirmed, isFalse);
      expect(app.alarmDisableOutstanding, isTrue);
      engine.stallDisable!.complete(AlarmDisableOutcome.written);
      await cancel;
      app.debugHandleAlarmEvent(59, ts: 2000000000);
      await settle();
      expect(app.alarmDisableOutstanding, isTrue);
      final restored = AppState.forTesting();
      addTearDown(restored.dispose);
      await restored.debugRestoreAlarmFromPrefs();
      restored.debugHandleAlarmEvent(59, ts: 2000000000);
      expect(restored.alarmConfirmed, isFalse);
      expect(restored.alarmDisableOutstanding, isTrue);
    });

    test('unknown readback grace never repeats SET or notifies latch failure', () async {
      final app = await armed();
      final engine = app.engine as _DisableEngine;
      final when = DateTime.fromMillisecondsSinceEpoch(app.alarmEpoch! * 1000);
      var notifications = 0;
      final oldSink = NotificationCenter.instance.presentSink;
      NotificationCenter.instance.presentSink = (e, {bool allowPermissionPrompt = true}) async {
        notifications++;
        return true;
      };
      addTearDown(() => NotificationCenter.instance.presentSink = oldSink);
      await app.debugOnAlarmGraceElapsed(when);
      await app.debugOnAlarmGraceElapsed(when);
      await app.debugArmNextAlarmOccurrence();
      expect(engine.setCalls, 1);
      expect(notifications, 0);
      await app.disableAlarm();
      await app.debugOnAlarmGraceElapsed(when);
      expect(engine.disableCalls, 1);
      expect(app.alarmDisableOutstanding, isTrue);
      expect(engine.setCalls, 1);
    });

    for (final token in ['pending', 'written', 'cancel_all', 'cancel_all_written']) {
      test('legacy $token migrates desired-off despite enabled rows', () async {
        SharedPreferences.setMockInitialValues({
          'alarm_epoch': 1785000000, AlarmCancelPrefs.intentKey: token,
        });
        await LocalDb.setAlarmScheduleDay(weekday: 0, hour: 7, minute: 0, enabled: true);
        final app = AppState.forTesting(engine: _DisableEngine());
        addTearDown(app.dispose);
        await app.debugRestoreAlarmFromPrefs();
        app.device.connection = 'connected';
        await app.debugArmNextAlarmOccurrence();
        expect((app.engine as _DisableEngine).setCalls, 0);
        expect(app.alarmDisableOutstanding, isTrue);
        expect(app.alarmSchedule.any((e) => e.enabled), isFalse);
      });
    }
  });
}
