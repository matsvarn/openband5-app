import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ios_ble_restore.dart';
import 'package:openstrap_edge/sync/background_sync.dart';
import 'package:openstrap_edge/sync/band_ownership.dart';
import 'package:openstrap_edge/sync/file_log.dart';
import 'package:openstrap_edge/sync/headless_gate.dart';

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
    IosBleRestore.handoffMaxPolls = 80;
    IosBleRestore.handoffPoll = const Duration(milliseconds: 500);
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
    IosBleRestore.debugBandLinkHeld = null;
    IosBleRestore.logSink = FileLog.write;
    IosBleRestore.handoffMaxPolls = 80;
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
        expect(calls, ['wakeAck']);
        held = true;
        await tester.pump(const Duration(milliseconds: 500));
        await wake;
        expect(calls, ['wakeAck', 'syncDone']);
        expect(logs, contains(contains('taken over after 2 polls')));
      },
    );
  }
  testWidgets('wake releases native at bound when never taken over', (
    tester,
  ) async {
    IosBleRestore.foregroundActive = true;
    IosBleRestore.handoffMaxPolls = 4;
    final wake = nativeCall('wake');
    await tester.pump();
    expect(calls, ['wakeAck']);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(calls, ['wakeAck']);
    await tester.pump(const Duration(milliseconds: 500));
    await wake;
    expect(calls, ['wakeAck', 'syncDone']);
    expect(logs, contains(contains('not taken over after 4 polls')));
  });
  test('suspension does not spend the awake poll budget', () {
    fakeAsync((async) {
      IosBleRestore.foregroundActive = true;
      IosBleRestore.handoffMaxPolls = 4;
      var completed = false;
      unawaited(nativeCall('wake').then((_) => completed = true));
      async.flushMicrotasks();
      for (var i = 0; i < 3; i++) {
        // Advance the clock without running timers, matching suspension.
        // Resume then runs one overdue poll.
        async.elapseBlocking(const Duration(hours: 3));
        async.elapse(Duration.zero);
        expect(
          calls,
          isNot(contains('syncDone')),
          reason: 'only ${i + 1} awake polls ran',
        );
        expect(completed, isFalse);
      }
      async.elapseBlocking(const Duration(hours: 3));
      async.elapse(Duration.zero);
      expect(completed, isTrue);
      expect(calls, ['wakeAck', 'syncDone']);
      expect(logs, contains(contains('not taken over after 4 polls')));
    });
  });
  test(
    'headless wake acknowledges before starting work and completing',
    () async {
      final lease = BandOwnership.tryAcquireHeadless()!;
      addTearDown(() => BandOwnership.release(lease));
      backgroundSyncLogSink = (line) async {
        expect(calls, ['wakeAck']);
        logs.add(line);
      };
      await nativeCall('wake');
      expect(logs, contains(contains('[bgsync] skipped — foreground')));
      expect(calls, ['wakeAck', 'syncDone']);
    },
  );
  test(
    'busy headless gate leaves an unaccepted wake to the native watchdog',
    () async {
      final pending = Completer<void>();
      final running = HeadlessSyncGate.tryRun<void>(
        'other_wake',
        () => pending.future,
      );
      try {
        await nativeCall('wake');
        expect(calls, isEmpty);
      } finally {
        pending.complete();
        await running;
      }
    },
  );
  testWidgets('already-held link releases native immediately', (tester) async {
    IosBleRestore.foregroundActive = true;
    held = true;
    await nativeCall('wake');
    expect(calls, ['wakeAck', 'syncDone']);
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
