import 'dart:async';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BleEngine engine(List<String> logs) {
    final e = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) {},
      log: logs.add,
      adapterStateStream: () => Stream.value(BluetoothAdapterState.on),
    );
    e.debugConnectionStates = () => const Stream.empty();
    addTearDown(e.dispose);
    return e;
  }

  test('timeout re-attaches once for 5s and continues normal setup', () async {
    final logs = <String>[];
    final e = engine(logs);
    final attempts = <Duration>[];
    e.debugDeviceConnectWithTimeout = (duration) async {
      attempts.add(duration);
      if (attempts.length == 1) throw timeout();
    };
    e.debugSystemConnected = (device, services) async {
      expect(device.remoteId.str, 'AA:BB:CC:DD:EE:FF');
      expect(
        services.toSet(),
        kBandRegistry.map((b) => Guid(b.service)).toSet(),
      );
      return true;
    };
    // Real setup is reached; this desktop host has no GATT peripheral.
    await e.connectToRemoteId('AA:BB:CC:DD:EE:FF');
    expect(attempts, [const Duration(seconds: 20), const Duration(seconds: 5)]);
    expect(logs, contains(contains('[BOOT gen5]')));
    expect(logs, isNot(contains(startsWith('connect failed:'))));
    expect(logs, contains(contains('system-connected')));
  });

  test(
    'timeout without a system link keeps the existing failure path',
    () async {
      final logs = <String>[];
      final e = engine(logs);
      var probes = 0;
      var attempts = 0;
      e.debugDeviceConnect = () async {
        attempts++;
        throw timeout();
      };
      e.debugSystemConnected = (_, _) async {
        probes++;
        return false;
      };
      expect(await e.connectToRemoteId('AA:BB:CC:DD:EE:FF'), isFalse);
      expect(probes, 1);
      expect(attempts, 1);
      expect(e.state.lastConnectFailedAt, isNotNull);
      expect(e.bluetoothBlocker, isNull);
    },
  );

  test(
    'failed re-attach is bounded to one and preserves timeout classification',
    () async {
      final e = engine([]);
      var attempts = 0;
      e.debugDeviceConnect = () async {
        attempts++;
        throw timeout();
      };
      e.debugSystemConnected = (_, _) async => true;
      expect(await e.connectToRemoteId('AA:BB:CC:DD:EE:FF'), isFalse);
      expect(attempts, 2);
      expect(e.state.lastConnectFailedAt, isNotNull);
      expect(e.bluetoothBlocker, isNull);
    },
  );

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
    expect(await e.connectToRemoteId('AA:BB:CC:DD:EE:FF'), isFalse);
    expect(probes, 0);
  });

  test(
    'suspension logs wall duration for both initial and re-attach attempts',
    () async {
      final logs = <String>[];
      final e = engine(logs);
      var now = DateTime(2026, 9, 30);
      e.debugConnectNow = () => now;
      e.debugDeviceConnectWithTimeout = (duration) async {
        now = now.add(duration + const Duration(seconds: 6));
        throw timeout();
      };
      e.debugSystemConnected = (_, _) async => true;
      await e.connectToRemoteId('AA:BB:CC:DD:EE:FF');
      expect(
        logs,
        contains(contains('connect attempt took 26s for a 20s timeout')),
      );
      expect(
        logs,
        contains(contains('connect attempt took 11s for a 5s timeout')),
      );
    },
  );

  test('failed connect episodes log first and tenth attempts', () async {
    final logs = <String>[];
    final e = engine(logs);
    e.debugDeviceConnect = () async => throw timeout();
    e.debugSystemConnected = (_, _) async => false;
    for (var i = 0; i < 10; i++) {
      await e.connectToRemoteId('AA:BB:CC:DD:EE:FF');
    }
    expect(
      logs.where((s) => s.startsWith('[LINK] unreachable since')),
      hasLength(1),
    );
    expect(logs, contains(contains('10 failed attempts')));
  });
}
