import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/ble/ble_state.dart';
import 'package:openstrap_edge/sync/sync_policy.dart';

// Stream cancellation may complete outside the widget clock's zone. Flush that
// boundary, then advance fake timers; never await a parked connect blindly.
Future<bool> finishConnect(WidgetTester tester, Future<bool> connect) async {
  bool? result;
  unawaited(connect.then((value) => result = value));
  for (var i = 0; i < 5 && result == null; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(seconds: 16));
  }
  expect(result, isNotNull, reason: 'connect must release the operation lock');
  return result!;
}

class TestBluetoothDevice extends BluetoothDevice {
  TestBluetoothDevice() : super.fromId('AA:BB:CC:DD:EE:FF');

  bool linkUp = false;

  @override
  bool get isConnected => linkUp;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BleEngine engine(List<String> logs, {bool drainer = false}) {
    final e = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) {},
      log: logs.add,
      isBackgroundDrainer: drainer,
      adapterStateStream: () => Stream.value(BluetoothAdapterState.on),
    );
    e.debugIsIOS = true;
    e.debugSystemConnected = (_, _) async => false;
    final states = StreamController<BluetoothConnectionState>.broadcast();
    e.debugConnectionStates = () => states.stream;
    addTearDown(states.close);
    e.debugDeviceDisconnect = ({bool queue = true}) async {};
    addTearDown(e.dispose);
    return e;
  }

  test('only the background iOS app gets 20 minutes', () {
    for (final ios in [false, true]) {
      for (final background in [false, true]) {
        for (final drainer in [false, true]) {
          expect(
            connectTimeoutFor(
              ios: ios,
              background: background,
              backgroundDrainer: drainer,
            ),
            ios && background && !drainer
                ? const Duration(minutes: 20)
                : const Duration(seconds: 20),
          );
        }
      }
    }
  });

  test('background iOS app keeps policy delay before any pending attempt', () {
    final e = engine([])..setBackground(true);
    expect(e.reconnectDelay(5).inSeconds, inInclusiveRange(24, 30));
  });

  test(
    'reconnect gap is minimal only after a pending background iOS attempt',
    () {
      final policy = ReconnectPolicy(jitterFraction: 0);
      final policyDelay = policy.delayFor(5);
      expect(policyDelay, const Duration(seconds: 30));
      for (final ios in [false, true]) {
        for (final background in [false, true]) {
          for (final drainer in [false, true]) {
            for (final pending in [false, true]) {
              expect(
                reconnectDelayFor(
                  ios: ios,
                  background: background,
                  backgroundDrainer: drainer,
                  lastAttemptPending: pending,
                  policyDelay: policyDelay,
                ),
                ios && background && !drainer && pending
                    ? const Duration(seconds: 1)
                    : const Duration(seconds: 30),
              );
            }
          }
        }
      }
    },
  );

  test('foreground, Android and drainer keep the reconnect policy delay', () {
    for (final ios in [false, true]) {
      for (final background in [false, true]) {
        for (final drainer in [false, true]) {
          if (ios && background && !drainer) continue;
          final e = engine([], drainer: drainer)
            ..debugIsIOS = ios
            ..setBackground(background);
          expect(
            e.reconnectPolicy.baseDelayFor(5),
            const Duration(seconds: 30),
          );
          expect(
            e.reconnectDelay(5).inSeconds,
            inInclusiveRange(24, 30),
            reason:
                'attempt 5 keeps the policy jitter around its 30-second base',
          );
        }
      }
    }
  });

  test('long pending connect expires before the supervisor restarts it', () {
    ReconnectSupervisorAction action(Duration elapsed) => superviseReconnect(
      paired: true,
      keepAlive: true,
      connected: false,
      loopRunning: true,
      autoReconnectPaused: false,
      attemptRunningFor: elapsed,
    );
    final timeout = connectTimeoutFor(
      ios: true,
      background: true,
      backgroundDrainer: false,
    );
    expect(timeout, kIosBackgroundConnectTimeout);
    expect(action(timeout), ReconnectSupervisorAction.none);
    expect(
      action(const Duration(minutes: 25)),
      ReconnectSupervisorAction.restartStale,
    );
    expect(timeout, lessThan(const Duration(minutes: 25)));
  });

  test(
    'immediate platform error keeps policy delay and never logs pending connect',
    () async {
      for (final drainer in [false, true]) {
        final logs = <String>[];
        final e = engine(logs, drainer: drainer)..setBackground(true);
        final attempts = <Duration>[];
        e.debugDeviceConnectWithTimeout = (timeout) async {
          attempts.add(timeout);
          throw PlatformException(
            code: 'connect',
            message: 'Peripheral not found',
          );
        };
        expect(await e.connectToRemoteId('AA:BB:CC:DD:EE:FF'), isFalse);
        expect(attempts, [const Duration(hours: 24)]);
        expect(e.reconnectDelay(5).inSeconds, inInclusiveRange(24, 30));
        expect(
          logs.where(
            (line) =>
                line == '[LINK] background pending connect (up to 20 min)',
          ),
          isEmpty,
        );
      }
    },
  );

  test('pending log waits one second and is emitted only once', () {
    fakeAsync((async) {
      final logs = <String>[];
      final e = engine(logs)..setBackground(true);
      final pending = Completer<void>();
      e.debugDeviceConnectWithTimeout = (_) => pending.future;
      unawaited(
        e.debugConnectAttempt(
          BluetoothDevice.fromId('AA:BB:CC:DD:EE:FF'),
          kIosBackgroundConnectTimeout,
        ),
      );
      async.flushMicrotasks();
      expect(logs, isEmpty);
      async.elapse(const Duration(milliseconds: 999));
      expect(logs, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(logs, ['[LINK] background pending connect (up to 20 min)']);
      pending.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));
      expect(logs, ['[LINK] background pending connect (up to 20 min)']);
      expect(e.reconnectDelay(5), const Duration(seconds: 1));
    });
  });

  testWidgets(
    'background timer expiry rearms after one second and reports failure',
    (tester) async {
      final logs = <String>[];
      final e = engine(logs)..setBackground(true);
      final pending = Completer<void>();
      e.debugDeviceConnectWithTimeout = (_) => pending.future;
      final connect = e.connectToRemoteId('AA:BB:CC:DD:EE:FF');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        logs.where(
          (line) => line == '[LINK] background pending connect (up to 20 min)',
        ),
        hasLength(1),
      );
      await tester.pump(const Duration(minutes: 20));
      expect(await finishConnect(tester, connect), isFalse);
      expect(e.reconnectDelay(5), const Duration(seconds: 1));
      expect(e.state.lastConnectFailedAt, isNotNull);
      expect(logs, contains(startsWith('[LINK] unreachable since')));
      expect(e.holdsBandLink, isFalse);
      expect(BleEngine.bandClaimed, isFalse);
      pending.completeError(StateError('late native cancellation'));
      await tester.pump();
    },
  );

  for (final elapsed in [
    const Duration(milliseconds: 4999),
    const Duration(seconds: 5),
  ]) {
    test(
      'background failure after ${elapsed.inMilliseconds}ms uses the matching gap',
      () {
        fakeAsync((async) {
          final e = engine([])..setBackground(true);
          e.debugConnectNow = async.getClock(DateTime(2026, 10, 1)).now;
          final pending = Completer<void>();
          e.debugDeviceConnectWithTimeout = (_) => pending.future;
          var failed = false;
          unawaited(
            e
                .debugConnectAttempt(
                  BluetoothDevice.fromId('AA:BB:CC:DD:EE:FF'),
                  kIosBackgroundConnectTimeout,
                )
                .catchError((Object _) {
                  failed = true;
                }),
          );
          async.flushMicrotasks();
          async.elapse(elapsed);
          pending.completeError(StateError('native connect failed'));
          async.flushMicrotasks();
          expect(failed, isTrue);
          if (elapsed >= const Duration(seconds: 5)) {
            expect(e.reconnectDelay(5), const Duration(seconds: 1));
          } else {
            expect(e.reconnectDelay(5).inSeconds, inInclusiveRange(24, 30));
          }
          e.debugDeviceConnectWithTimeout = (_) async =>
              throw StateError('immediate retry failure');
          unawaited(
            e
                .debugConnectAttempt(
                  BluetoothDevice.fromId('AA:BB:CC:DD:EE:FF'),
                  kIosBackgroundConnectTimeout,
                )
                .catchError((Object _) {}),
          );
          async.flushMicrotasks();
          expect(
            e.reconnectDelay(5).inSeconds,
            inInclusiveRange(24, 30),
            reason:
                'the previous pending attempt must not leak into this retry',
          );
        });
      },
    );
  }

  testWidgets('foreground system-only link completes within five seconds', (
    tester,
  ) async {
    final logs = <String>[];
    final e = engine(logs)..setBackground(true);
    final pending = Completer<void>();
    final cancels = <bool>[];
    e.debugDeviceConnectWithTimeout = (_) => pending.future;
    e.debugSystemConnected = (_, _) async => true;
    e.debugDeviceDisconnect = ({bool queue = true}) async {
      cancels.add(queue);
    };
    final connect = e.connectToRemoteId('AA:BB:CC:DD:EE:FF');
    await tester.pump();
    try {
      e.setBackground(false);
      await tester.pump();
      expect(cancels.where((queue) => !queue), isEmpty);
      expect(
        logs,
        isNot(contains(contains('background connect already landed'))),
        reason: 'a system-only link must wait for this central to connect',
      );
      await tester.pump(const Duration(seconds: 4));
      pending.complete();
      await tester.pump();
      await finishConnect(tester, connect);
      expect(logs, contains(contains('[BOOT gen5]')));
      expect(logs, isNot(contains(startsWith('connect failed:'))));
      expect(
        logs,
        contains(
          '[LINK] foreground — background connect already landed, keeping it',
        ),
      );
    } finally {
      if (!pending.isCompleted) pending.complete();
      await finishConnect(tester, connect);
    }
  });

  testWidgets(
    'foreground system-only link cancels within five seconds and releases lock',
    (tester) async {
      final logs = <String>[];
      final e = engine(logs)..setBackground(true);
      final pending = Completer<void>();
      final cancels = <bool>[];
      e.debugDeviceConnectWithTimeout = (_) => pending.future;
      e.debugSystemConnected = (_, _) async => true;
      // Native cancellation need not settle a stuck connect future.
      e.debugDeviceDisconnect = ({bool queue = true}) async =>
          cancels.add(queue);
      final connect = e.connectToRemoteId('AA:BB:CC:DD:EE:FF');
      await tester.pump();
      try {
        e.setBackground(false);
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        expect(cancels.where((queue) => !queue), isEmpty);
        await tester.pump(const Duration(seconds: 1));
        expect(cancels.where((queue) => !queue), hasLength(1));
        expect(await finishConnect(tester, connect), isFalse);
        expect(e.holdsBandLink, isFalse);
        expect(BleEngine.bandClaimed, isFalse);
        expect(e.state.lastConnectFailedAt, isNull);
        expect(logs, isNot(contains(startsWith('[LINK] unreachable since'))));
        expect(logs, isNot(contains(contains('[BOOT gen5]'))));
        var nextAttemptRan = false;
        e.debugDeviceConnectWithTimeout = (_) async {
          nextAttemptRan = true;
          throw StateError('next foreground attempt');
        };
        expect(
          await finishConnect(tester, e.connectToRemoteId('AA:BB:CC:DD:EE:FF')),
          isFalse,
        );
        expect(nextAttemptRan, isTrue);
        // A late result from the cancelled attempt must not affect its successor.
        pending.complete();
        await tester.pump(const Duration(minutes: 20));
        expect(cancels.where((queue) => !queue), hasLength(1));
        expect(logs, isNot(contains(contains('[BOOT gen5]'))));
      } finally {
        if (!pending.isCompleted) pending.complete();
        await finishConnect(tester, connect);
      }
    },
  );

  testWidgets('post-cancel system-only link fails without gen5 bootstrap', (
    tester,
  ) async {
    final logs = <String>[];
    final e = engine(logs)..setBackground(true);
    final pending = Completer<void>();
    final cancellation = Completer<void>();
    var systemUp = false;
    e.debugDeviceConnectWithTimeout = (_) => pending.future;
    e.debugSystemConnected = (_, _) async => systemUp;
    e.debugDeviceDisconnect = ({bool queue = true}) async {
      if (!queue) {
        pending.complete();
        await cancellation.future;
        systemUp = true;
      }
    };
    final connect = e.connectToRemoteId('AA:BB:CC:DD:EE:FF');
    await tester.pump();
    try {
      e.setBackground(false);
      await tester.pump();
      cancellation.complete();
      await tester.pump();
      expect(await finishConnect(tester, connect), isFalse);
      expect(logs, isNot(contains(contains('[BOOT gen5]'))));
      expect(
        logs,
        contains('[LINK] background pending connect cancelled (foreground)'),
      );
      expect(e.holdsBandLink, isFalse);
    } finally {
      if (!pending.isCompleted) pending.complete();
      if (!cancellation.isCompleted) cancellation.complete();
      await finishConnect(tester, connect);
    }
  });

  for (final foregroundReturn in [true, false]) {
    for (final survivesCancellation in [false, true]) {
      testWidgets(
        '${foregroundReturn ? "foreground" : "disconnect"} cancellation '
        '${survivesCancellation ? "keeps a verified surviving link" : "rejects late success after link drops"}',
        (tester) async {
          final logs = <String>[];
          final e = engine(logs)..setBackground(true);
          final pending = Completer<void>();
          final cancellation = Completer<void>();
          final cancels = <bool>[];
          final states = StreamController<BluetoothConnectionState>.broadcast();
          e.debugConnectionStates = () => states.stream;
          addTearDown(states.close);
          final device = TestBluetoothDevice();
          var linkUp = false;
          e.debugDeviceConnectWithTimeout = (_) => pending.future;
          e.debugSystemConnected = (_, _) async => linkUp;
          e.debugDeviceDisconnect = ({bool queue = true}) async {
            cancels.add(queue);
            if (!queue) {
              await cancellation.future;
              linkUp = survivesCancellation;
              device.linkUp = survivesCancellation;
              states.add(
                linkUp
                    ? BluetoothConnectionState.connected
                    : BluetoothConnectionState.disconnected,
              );
            }
          };
          final connect = e.connect(device);
          await tester.pump();
          Future<void>? disconnect;
          try {
            if (foregroundReturn) {
              e.setBackground(false);
            } else {
              disconnect = e.disconnect();
            }
            await tester.pump();
            expect(cancels.where((queue) => !queue), hasLength(1));
            // FBP's connect future may succeed while disconnect is still running.
            pending.complete();
            await tester.pump();
            expect(logs, isNot(contains(contains('[BOOT gen5]'))));
            cancellation.complete();
            await tester.pump();
            expect(await finishConnect(tester, connect), isFalse);
            if (disconnect != null) {
              await tester.runAsync(() => disconnect!);
            }
            if (survivesCancellation) {
              expect(logs, contains(contains('[BOOT gen5]')));
              expect(logs, isNot(contains(startsWith('connect failed:'))));
              expect(
                logs,
                contains(
                  '[LINK] background connect completed after cancellation — keeping it',
                ),
              );
            } else {
              expect(logs, isNot(contains(contains('[BOOT gen5]'))));
              expect(
                logs,
                contains(
                  '[LINK] background pending connect cancelled (${foregroundReturn ? "foreground" : "disconnect"})',
                ),
              );
              expect(e.holdsBandLink, isFalse);
              expect(BleEngine.bandClaimed, isFalse);
              expect(e.state.connection, 'disconnected');
            }
          } finally {
            if (!pending.isCompleted) pending.complete();
            if (!cancellation.isCompleted) cancellation.complete();
            await finishConnect(tester, connect);
            if (disconnect != null) {
              await tester.runAsync(() => disconnect!);
            }
          }
        },
      );
    }
  }

  for (final foregroundReturn in [true, false]) {
    test(
      foregroundReturn
          ? 'foreground return cancels pending connect and releases ownership'
          : 'disconnect cancels pending connect before waiting for the operation lock',
      () async {
        final logs = <String>[];
        final e = engine(logs)..setBackground(true);
        final started = Completer<void>();
        final pending = Completer<void>();
        var cancels = 0;
        e.debugDeviceConnectWithTimeout = (_) {
          started.complete();
          return pending.future;
        };
        e.debugDeviceDisconnect = ({bool queue = true}) async {
          if (!pending.isCompleted) expect(queue, isFalse);
          cancels++;
          if (!pending.isCompleted) {
            pending.completeError(StateError('cancelled'));
          }
        };
        final connect = e.connectToRemoteId('AA:BB:CC:DD:EE:FF');
        await started.future;
        Future<void>? disconnect;
        try {
          expect(e.holdsBandLink, isTrue);
          if (foregroundReturn) {
            e.setBackground(false);
          } else {
            disconnect = e.disconnect();
          }
          await Future<void>.delayed(Duration.zero);
          expect(
            cancels,
            greaterThanOrEqualTo(1),
            reason:
                'native cancellation must happen before the connect resolves',
          );
          expect(await connect, isFalse);
          if (disconnect != null) await disconnect;
          expect(e.holdsBandLink, isFalse);
          expect(BleEngine.bandClaimed, isFalse);
          expect(e.state.connection, 'disconnected');
          expect(e.state.lastConnectFailedAt, isNull);
          expect(logs, isNot(contains(startsWith('[LINK] unreachable since'))));
          expect(
            logs,
            contains(
              '[LINK] background pending connect cancelled (${foregroundReturn ? "foreground" : "disconnect"})',
            ),
          );
          if (foregroundReturn) {
            expect(
              logs,
              contains(
                '[LINK] foreground — cancelling the background pending connect',
              ),
            );
            e.debugDeviceConnectWithTimeout = (timeout) async {
              expect(timeout, const Duration(hours: 24));
              throw StateError('next foreground attempt');
            };
            expect(await e.connectToRemoteId('AA:BB:CC:DD:EE:FF'), isFalse);
            expect(logs, contains(contains('next foreground attempt')));
          }
        } finally {
          if (!pending.isCompleted) {
            pending.completeError(StateError('test cleanup'));
          }
          await connect;
          if (disconnect != null) await disconnect;
        }
      },
    );
  }
}
