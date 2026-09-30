import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ios_ble_restore.dart';
import 'package:openstrap_edge/sync/background_sync.dart';
import 'package:openstrap_edge/sync/band_ownership.dart';
import 'package:openstrap_edge/sync/file_log.dart';

Future<void> nativeCall(String method, [Object? arguments]) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'openstrap/ble_restore',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  final logs = <String>[];
  var held = false;
  setUp(() {
    calls.clear();
    logs.clear();
    held = false;
    BandOwnership.resetForTest();
    IosBleRestore.foregroundActive = false;
    IosBleRestore.handoffTimeout = const Duration(seconds: 40);
    IosBleRestore.handoffPoll = const Duration(milliseconds: 500);
    IosBleRestore.handoffNow = () => TestWidgetsFlutterBinding.instance.clock.now();
    IosBleRestore.debugBandLinkHeld = () => held;
    IosBleRestore.logSink = (line) async {
      logs.add(line);
    };
    IosBleRestore.registerHandler();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('openstrap/ble_restore'),
          (call) async {
            calls.add(call.method);
            return null;
          },
        );
  });
  tearDown(() {
    BandOwnership.resetForTest();
    IosBleRestore.foregroundActive = false;
    IosBleRestore.handoffNow = DateTime.now;
    IosBleRestore.debugBandLinkHeld = null;
    IosBleRestore.logSink = FileLog.write;
    IosBleRestore.handoffTimeout = const Duration(seconds: 40);
    IosBleRestore.handoffPoll = const Duration(milliseconds: 500);
    backgroundSyncLogSink = FileLog.write;
    const MethodChannel('openstrap/ble_restore').setMethodCallHandler(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('openstrap/ble_restore'),
          null,
        );
  });

  for (final intentOnly in [false, true]) {
    testWidgets(
      'wake waits for takeover with foreground ${intentOnly ? "intent" : "active"}',
      (tester) async {
        IosBleRestore.foregroundActive = !intentOnly;
        BandOwnership.markForegroundIntent(intentOnly);
        final wake = nativeCall('wake');
        await tester.pump();
        expect(calls, isNot(contains('syncDone')));
        await tester.pump(const Duration(milliseconds: 500));
        expect(calls, isEmpty);
        held = true;
        await tester.pump(const Duration(milliseconds: 500));
        await wake;
        expect(calls, ['syncDone']);
        expect(logs, contains(contains('taken over after 1.0s')));
      },
    );
  }
  testWidgets('wake releases native at bound when never taken over', (
    tester,
  ) async {
    IosBleRestore.foregroundActive = true;
    IosBleRestore.handoffTimeout = const Duration(seconds: 2);
    final wake = nativeCall('wake');
    await tester.pump();
    expect(calls, isEmpty);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 500));
    await wake;
    expect(calls, ['syncDone']);
    expect(logs, contains(contains('not taken over within 2s')));
  });
  testWidgets('already-held link releases native immediately', (tester) async {
    IosBleRestore.foregroundActive = true;
    held = true;
    await nativeCall('wake');
    expect(calls, ['syncDone']);
  });
  test('native log keeps its timestamp and reaches field log', () async {
    const line =
        '2026-09-30T10:00:00Z [ble-restore] didDisconnect code=6 description=timed out';
    await nativeCall('log', line);
    expect(logs, [line]);
    expect(calls, isEmpty);
  });
  test('headless refusal reaches field log', () async {
    backgroundSyncLogSink = (line) async {
      logs.add(line);
    };
    BandOwnership.markForegroundIntent(true);
    expect(await runHeadlessSync(), isTrue);
    expect(logs, contains(contains('[bgsync] skipped — foreground')));
  });
}
