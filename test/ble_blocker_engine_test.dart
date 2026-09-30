import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/ble/ble_state.dart';

class _Adapter {
  BluetoothAdapterState state;
  final streams = <StreamController<BluetoothAdapterState>>[];

  _Adapter(this.state);

  Stream<BluetoothAdapterState> freshStream() {
    late final StreamController<BluetoothAdapterState> controller;
    controller = StreamController<BluetoothAdapterState>(
      onListen: () => controller.add(state),
    );
    streams.add(controller);
    return controller.stream;
  }

  void report(BluetoothAdapterState next) {
    state = next;
    for (final stream in streams) {
      if (!stream.isClosed) stream.add(next);
    }
  }

  Future<void> close() async {
    for (final stream in streams) {
      await stream.close();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unknown then on ignores the early connect error; off then on clears',
    () async {
      final states = _Adapter(BluetoothAdapterState.unknown);
      final logs = <String>[];
      final engine = BleEngine(
        onRecord: (sample, raw) async {},
        onState: (_) {},
        adapterStateStream: states.freshStream,
        log: logs.add,
      );
      addTearDown(() async {
        engine.dispose();
        await states.close();
      });

      expect(
        classifyBleBlocker(
          adapterState: 'unknown',
          error: Exception('Bluetooth must be turned on'),
        ),
        isNull,
      );
      states.report(BluetoothAdapterState.on);
      await Future<void>.delayed(Duration.zero);
      expect(engine.bluetoothBlocker, isNull);

      states.report(BluetoothAdapterState.off);
      await Future<void>.delayed(Duration.zero);
      expect(engine.bluetoothBlocker, BleBlocker.adapterOff);
      expect(engine.bandStatus.condition, BandCondition.bluetoothOff);
      states.report(BluetoothAdapterState.unknown);
      await engine.refreshBluetoothBlocker();
      expect(engine.bluetoothBlocker, BleBlocker.adapterOff);
      states.report(BluetoothAdapterState.on);
      await Future<void>.delayed(Duration.zero);
      expect(engine.bluetoothBlocker, isNull);
      expect(logs, contains(contains('blocker set: adapterOff (adapter=off)')));
      expect(logs, contains(contains('blocker cleared (adapter=on)')));
    },
  );

  test(
    'a scan sees off through its own single-subscription adapter stream',
    () async {
      final adapter = _Adapter(BluetoothAdapterState.off);
      final engine = BleEngine(
        onRecord: (_, _) async {},
        onState: (_) {},
        adapterStateStream: adapter.freshStream,
      );
      addTearDown(() async {
        engine.dispose();
        await adapter.close();
      });

      await expectLater(
        engine.scan(),
        throwsA(
          isA<BleUnavailableException>().having(
            (e) => e.blocker,
            'blocker',
            BleBlocker.adapterOff,
          ),
        ),
      );
      expect(engine.bandStatus.condition, BandCondition.bluetoothOff);
      expect(adapter.streams.length, greaterThanOrEqualTo(2));
    },
  );

  test('adapter listener subscribes again after a platform stream error',
      () async {
    var streams = 0;
    final engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) {},
      adapterStateStream: () {
        streams++;
        return streams == 1
            ? Stream.error(StateError('adapter stream failed'))
            : Stream.value(BluetoothAdapterState.off);
      },
    );
    addTearDown(engine.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(streams, 2);
    expect(engine.bluetoothBlocker, BleBlocker.adapterOff);
  });

  test(
    'a scan permission error survives a repeated adapter on',
    () async {
      final adapter = _Adapter(BluetoothAdapterState.on);
      final engine = BleEngine(
        onRecord: (_, _) async {},
        onState: (_) {},
        adapterStateStream: adapter.freshStream,
      );
      addTearDown(() async {
        engine.dispose();
        await adapter.close();
      });

      engine.debugStartScan = () async =>
          throw Exception('Need android.permission.BLUETOOTH_SCAN');
      await expectLater(
        engine.scan(),
        throwsA(
          isA<BleUnavailableException>().having(
            (e) => e.blocker,
            'blocker',
            BleBlocker.permissionDenied,
          ),
        ),
      );
      expect(engine.bluetoothBlocker, BleBlocker.permissionDenied);

      // A resume re-reads an adapter that is still on: the refusal stands.
      adapter.report(BluetoothAdapterState.on);
      await engine.refreshBluetoothBlocker();
      expect(engine.bluetoothBlocker, BleBlocker.permissionDenied);

      // Stale "off" text with the radio on is not a second blocker.
      engine.debugStartScan = () async =>
          throw Exception('Bluetooth must be turned on');
      expect(await engine.scan(), isNull);
      expect(engine.bluetoothBlocker, BleBlocker.permissionDenied);
    },
  );

  test('stale off text with the adapter on sets no blocker', () async {
    final adapter = _Adapter(BluetoothAdapterState.on);
    final engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) {},
      adapterStateStream: adapter.freshStream,
    );
    addTearDown(() async {
      engine.dispose();
      await adapter.close();
    });

    engine.debugStartScan = () async =>
        throw Exception('Bluetooth must be turned on');
    expect(await engine.scan(), isNull);
    expect(engine.bluetoothBlocker, isNull);
  });

  test('a blocker from the adapter clears when the adapter turns on', () async {
    final adapter = _Adapter(BluetoothAdapterState.unauthorized);
    final engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) {},
      adapterStateStream: adapter.freshStream,
    );
    addTearDown(() async {
      engine.dispose();
      await adapter.close();
    });

    await engine.refreshBluetoothBlocker();
    expect(engine.bluetoothBlocker, BleBlocker.permissionDenied);

    adapter.report(BluetoothAdapterState.on);
    await engine.refreshBluetoothBlocker();
    expect(engine.bluetoothBlocker, isNull);
  });

  test('connect timeout is dated only with adapter on', () async {
    for (final radio in [BluetoothAdapterState.on, BluetoothAdapterState.off]) {
      final adapter = _Adapter(radio);
      final logs = <String>[];
      final engine = BleEngine(
        onRecord: (_, _) async {},
        onState: (_) {},
        adapterStateStream: adapter.freshStream,
        log: logs.add,
      );
      engine.debugDeviceConnect = () async =>
          throw TimeoutException('Timed out after 20s');
      engine.debugConnectionStates = () => const Stream.empty();
      await Future<void>.delayed(Duration.zero);

      expect(await engine.connectToRemoteId('AA:BB:CC:DD:EE:FF'), isFalse);
      expect(
        engine.state.lastConnectFailedAt,
        radio == BluetoothAdapterState.on ? isNotNull : isNull,
        reason: logs.join('\n'),
      );
      engine.dispose();
      await adapter.close();
    }
  });
}
