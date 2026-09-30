import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/ble/ble_state.dart';
import 'package:openstrap_edge/sync/sync_policy.dart';

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
    e.debugConnectionStates = () => const Stream.empty();
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
        expect(attempts, [
          drainer ? const Duration(seconds: 20) : const Duration(minutes: 20),
        ]);
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
              expect(timeout, const Duration(seconds: 20));
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
