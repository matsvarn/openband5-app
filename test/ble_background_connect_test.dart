import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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
    'engine selects and logs the long timeout, drainer stays short',
    () async {
      for (final drainer in [false, true]) {
        final logs = <String>[];
        final e = engine(logs, drainer: drainer)..setBackground(true);
        final attempts = <Duration>[];
        e.debugDeviceConnectWithTimeout = (timeout) async {
          attempts.add(timeout);
          throw StateError('synthetic connect failure');
        };
        expect(await e.connectToRemoteId('AA:BB:CC:DD:EE:FF'), isFalse);
        expect(attempts, [const Duration(hours: 24)]);
        expect(
          logs.where(
            (line) =>
                line == '[LINK] background pending connect (up to 20 min)',
          ),
          hasLength(drainer ? 0 : 1),
        );
      }
    },
  );

  for (final landedBeforeProbe in [true, false]) {
    testWidgets(
      landedBeforeProbe
          ? 'foreground return keeps a link ahead of the session listener'
          : 'successful connect keeps the link when cancellation loses the race',
      (tester) async {
        final logs = <String>[];
        final e = engine(logs)..setBackground(true);
        final pending = Completer<void>();
        final cancels = <bool>[];
        e.debugDeviceConnectWithTimeout = (_) => pending.future;
        e.debugSystemConnected = (_, _) async => landedBeforeProbe;
        e.debugDeviceDisconnect = ({bool queue = true}) async {
          cancels.add(queue);
        };
        final connect = e.connectToRemoteId('AA:BB:CC:DD:EE:FF');
        await tester.pump();
        try {
          e.setBackground(false);
          await tester.pump();
          expect(
            cancels.where((queue) => !queue),
            hasLength(landedBeforeProbe ? 0 : 1),
          );
          pending.complete();
          await tester.pump();
          await tester.pump(const Duration(seconds: 16));
          await finishConnect(tester, connect);
          expect(logs, contains(contains('[BOOT gen5]')));
          expect(logs, isNot(contains(startsWith('connect failed:'))));
          expect(
            logs,
            contains(
              contains(
                landedBeforeProbe
                    ? 'foreground — background connect already landed, keeping it'
                    : 'background connect completed after cancellation — keeping it',
              ),
            ),
          );
        } finally {
          if (!pending.isCompleted) pending.complete();
          await tester.pump();
          await tester.pump(const Duration(seconds: 16));
          await finishConnect(tester, connect);
        }
      },
    );
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
