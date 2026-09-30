import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/ble/ble_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unknown then on ignores the early connect error; off then on clears',
    () async {
      final states = StreamController<BluetoothAdapterState>.broadcast(
        sync: true,
      );
      final logs = <String>[];
      final engine = BleEngine(
        onRecord: (sample, raw) async {},
        onState: (_) {},
        adapterStates: states.stream,
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
      states.add(BluetoothAdapterState.unknown);
      states.add(BluetoothAdapterState.on);
      expect(engine.bluetoothBlocker, isNull);

      states.add(BluetoothAdapterState.off);
      expect(engine.bluetoothBlocker, BleBlocker.adapterOff);
      expect(engine.bandStatus.condition, BandCondition.bluetoothOff);
      states.add(BluetoothAdapterState.on);
      expect(engine.bluetoothBlocker, isNull);
      expect(logs, contains(contains('blocker set: adapterOff (adapter=off)')));
      expect(logs, contains(contains('blocker cleared (adapter=on)')));
    },
  );
}
