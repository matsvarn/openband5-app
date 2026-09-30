import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/adapters/_registry.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';

FlutterBluePlusException timeout() => FlutterBluePlusException(
  ErrorPlatform.fbp,
  'connect',
  FbpErrorCode.timeout.index,
  'Timed out after 20s',
);

class TestBluetoothDevice extends BluetoothDevice {
  TestBluetoothDevice() : super.fromId('AA:BB:CC:DD:EE:FF');

  bool linkUp = false;

  @override
  bool get isConnected => linkUp;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BleEngine engine(List<String> logs) {
    final e = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) {},
      log: logs.add,
      adapterStateStream: () => Stream.value(BluetoothAdapterState.on),
    );
    e.debugDeviceDisconnect = ({bool queue = true}) async {};
    e.debugConnectionStates = () => const Stream.empty();
    addTearDown(e.dispose);
    return e;
  }

  final device = BluetoothDevice.fromId('AA:BB:CC:DD:EE:FF');

  for (final linkUp in [true, false]) {
    test(
      linkUp
          ? 'owned timer probes before cancellation and keeps a landed link'
          : 'owned timer cancels an absent link once with the timeout shape',
      () {
        fakeAsync((async) {
          final logs = <String>[];
          final e = engine(logs);
          final pending = Completer<void>();
          final attempts = <Duration>[];
          final disconnects = <bool>[];
          final cancelsBeforeProbe = <List<bool>>[];
          var probes = 0;
          var completed = false;
          Object? failure;
          e.debugDeviceConnectWithTimeout = (duration) {
            attempts.add(duration);
            // Model FBP's own timer and cancel-before-throw, rather than
            // injecting a timeout error and bypassing that cancellation.
            return pending.future.timeout(
              duration,
              onTimeout: () async {
                await e.debugDeviceDisconnect!(queue: false);
                throw timeout();
              },
            );
          };
          e.debugDeviceDisconnect = ({bool queue = true}) async {
            disconnects.add(queue);
            if (!pending.isCompleted) {
              pending.completeError(StateError('native connect cancelled'));
            }
          };
          e.debugSystemConnected = (device, services) async {
            probes++;
            cancelsBeforeProbe.add(List.of(disconnects));
            expect(device.remoteId.str, 'AA:BB:CC:DD:EE:FF');
            expect(
              services.toSet(),
              kBandRegistry.map((b) => Guid(b.service)).toSet(),
            );
            return linkUp;
          };
          unawaited(
            e
                .debugConnectAttempt(device, const Duration(seconds: 20))
                .then(
                  (_) => completed = true,
                  onError: (Object error) {
                    failure = error;
                  },
                ),
          );
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 20));
          expect(probes, greaterThanOrEqualTo(1));
          expect(
            cancelsBeforeProbe.first,
            isEmpty,
            reason: 'probe must precede any cancel',
          );
          expect(attempts, [const Duration(hours: 24)]);
          if (linkUp) {
            expect(disconnects, isEmpty);
            pending.complete();
            async.flushMicrotasks();
            expect(completed, isTrue);
            expect(failure, isNull);
            expect(disconnects, isEmpty);
            expect(
              logs,
              contains(
                '[LINK] connect timer expired but the link is up — keeping it',
              ),
            );
          } else {
            expect(completed, isFalse);
            expect(disconnects, [false]);
            expect(
              failure,
              isA<FlutterBluePlusException>()
                  .having((e) => e.platform, 'platform', ErrorPlatform.fbp)
                  .having((e) => e.function, 'function', 'connect')
                  .having((e) => e.code, 'code', FbpErrorCode.timeout.index)
                  .having(
                    (e) => e.description,
                    'description',
                    'Timed out after 20s',
                  ),
            );
          }
          async.elapse(const Duration(seconds: 6));
          expect(disconnects, linkUp ? isEmpty : [false]);
        });
      },
    );
  }

  for (final duringProbe in [false, true]) {
    test(
      'timer keeps an own link ${duringProbe ? "arriving during the probe" : "without waiting for the connect future"}',
      () {
        fakeAsync((async) {
          final e = engine([]);
          final device = TestBluetoothDevice()..linkUp = !duringProbe;
          final pending = Completer<void>();
          var completed = false;
          var disconnects = 0;
          var probes = 0;
          e.debugDeviceConnectWithTimeout = (_) => pending.future;
          e.debugSystemConnected = (_, _) async {
            probes++;
            device.linkUp = true;
            return false;
          };
          e.debugDeviceDisconnect = ({bool queue = true}) async =>
              disconnects++;
          unawaited(
            e
                .debugConnectAttempt(device, const Duration(seconds: 20))
                .then((_) => completed = true),
          );
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 20));
          expect(completed, isTrue);
          expect(disconnects, 0);
          expect(probes, duringProbe ? 1 : 0);
          async.elapse(const Duration(seconds: 6));
          expect(disconnects, 0);
          pending.complete();
          async.flushMicrotasks();
        });
      },
    );
  }

  test('connect completing before the owned timer never probes or cancels', () {
    fakeAsync((async) {
      final e = engine([]);
      final pending = Completer<void>();
      var probes = 0;
      var disconnects = 0;
      var completed = false;
      e.debugDeviceConnectWithTimeout = (_) => pending.future;
      e.debugSystemConnected = (_, _) async {
        probes++;
        return true;
      };
      e.debugDeviceDisconnect = ({bool queue = true}) async {
        disconnects++;
      };
      unawaited(
        e
            .debugConnectAttempt(device, const Duration(seconds: 20))
            .then((_) => completed = true),
      );
      async.flushMicrotasks();
      pending.complete();
      async.flushMicrotasks();
      expect(completed, isTrue);
      async.elapse(const Duration(seconds: 26));
      expect(probes, 0);
      expect(disconnects, 0);
    });
  });

  test(
    'landed link recovery gives the pending future only five more seconds',
    () {
      fakeAsync((async) {
        final logs = <String>[];
        final e = engine(logs);
        final pending = Completer<void>();
        final disconnects = <bool>[];
        var linkUp = true;
        Object? failure;
        e.debugDeviceConnectWithTimeout = (_) => pending.future;
        e.debugSystemConnected = (_, _) async => linkUp;
        e.debugDeviceDisconnect = ({bool queue = true}) async {
          disconnects.add(queue);
          linkUp = false;
          pending.completeError(StateError('native connect cancelled'));
        };
        unawaited(
          e.debugConnectAttempt(device, const Duration(seconds: 20)).catchError(
            (Object error) {
              failure = error;
            },
          ),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 24));
        expect(disconnects, isEmpty);
        expect(failure, isNull);
        async.elapse(const Duration(seconds: 1));
        expect(disconnects, [false]);
        expect(
          logs,
          contains(
            '[LINK] link was up but connect did not complete within 5s — cancelling',
          ),
        );
        expect(
          failure,
          isA<FlutterBluePlusException>().having(
            (e) => e.code,
            'code',
            FbpErrorCode.timeout.index,
          ),
        );
      });
    },
  );

  for (final survivesCancellation in [false, true]) {
    test(
      survivesCancellation
          ? 'timer cancellation keeps a link only after a positive post-cancel probe'
          : 'late connect success cannot keep a link dropped by timer cancellation',
      () {
        fakeAsync((async) {
          final logs = <String>[];
          final e = engine(logs);
          final pending = Completer<void>();
          final cancellation = Completer<void>();
          final disconnects = <bool>[];
          final states = StreamController<BluetoothConnectionState>.broadcast();
          e.debugConnectionStates = () => states.stream;
          addTearDown(states.close);
          final device = TestBluetoothDevice();
          var linkUp = false;
          var completed = false;
          Object? failure;
          e.debugDeviceConnectWithTimeout = (_) => pending.future;
          e.debugSystemConnected = (_, _) async => linkUp;
          e.debugDeviceDisconnect = ({bool queue = true}) async {
            disconnects.add(queue);
            pending.complete();
            await cancellation.future;
            linkUp = true; // The restore central remains connected.
            device.linkUp = survivesCancellation;
            states.add(
              device.isConnected
                  ? BluetoothConnectionState.connected
                  : BluetoothConnectionState.disconnected,
            );
          };
          unawaited(
            e
                .debugConnectAttempt(device, const Duration(minutes: 20))
                .then(
                  (_) => completed = true,
                  onError: (Object error) => failure = error,
                ),
          );
          async.flushMicrotasks();
          async.elapse(const Duration(minutes: 19));
          expect(disconnects, isEmpty);
          expect(completed, isFalse);
          async.elapse(const Duration(minutes: 1));
          expect(disconnects, [false]);
          expect(completed, isFalse);
          cancellation.complete();
          async.flushMicrotasks();
          expect(completed, survivesCancellation);
          if (survivesCancellation) {
            expect(failure, isNull);
            expect(
              logs,
              contains(
                '[LINK] background connect completed after cancellation — keeping it',
              ),
            );
          } else {
            expect(
              failure,
              isA<FlutterBluePlusException>()
                  .having((e) => e.platform, 'platform', ErrorPlatform.fbp)
                  .having((e) => e.function, 'function', 'connect')
                  .having((e) => e.code, 'code', FbpErrorCode.timeout.index)
                  .having(
                    (e) => e.description,
                    'description',
                    'Timed out after 1200s',
                  ),
            );
            expect(
              logs,
              isNot(contains(contains('after cancellation — keeping it'))),
            );
          }
        });
      },
    );
  }

  test('non-timeout errors never probe or re-attach', () async {
    final e = engine([]);
    var probes = 0;
    e.debugDeviceConnect = () async => throw FlutterBluePlusException(
      ErrorPlatform.fbp,
      'connect',
      999,
      'not a timeout',
    );
    e.debugSystemConnected = (_, _) async {
      probes++;
      return true;
    };
    expect(await e.connectToRemoteId(device.remoteId.str), isFalse);
    expect(probes, 0);
  });

  test('suspension keeps the link and logs the attempt wall duration', () {
    fakeAsync((async) {
      final logs = <String>[];
      final e = engine(logs);
      e.debugConnectNow = async.getClock(DateTime(2026, 9, 30)).now;
      final pending = Completer<void>();
      var completed = false;
      e.debugDeviceConnectWithTimeout = (_) => pending.future;
      e.debugSystemConnected = (_, _) async => true;
      unawaited(
        e
            .debugConnectAttempt(device, const Duration(seconds: 20))
            .then((_) => completed = true),
      );
      async.flushMicrotasks();
      async.elapseBlocking(const Duration(hours: 3));
      async.elapse(Duration.zero);
      pending.complete();
      async.flushMicrotasks();
      expect(completed, isTrue);
      expect(
        logs,
        contains(contains('connect attempt took 10800s for a 20s timeout')),
      );
    });
  });

  test('failed connect episodes log first and tenth attempts', () async {
    final logs = <String>[];
    final e = engine(logs);
    e.debugDeviceConnect = () async => throw timeout();
    e.debugSystemConnected = (_, _) async => false;
    for (var i = 0; i < 10; i++) {
      await e.connectToRemoteId(device.remoteId.str);
    }
    expect(
      logs.where((s) => s.startsWith('[LINK] unreachable since')),
      hasLength(1),
    );
    expect(logs, contains(contains('10 failed attempts')));
  });
}
