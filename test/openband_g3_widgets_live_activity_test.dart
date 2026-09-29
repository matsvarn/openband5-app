import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/live/live_activity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.fromMillisecondsSinceEpoch(1_790_667_660_000);

  test('start sends the actual sport and no unmeasured numbers', () {
    final payload = LiveActivity.startPayload(startedAt: now, sport: 'running');
    expect(payload['name'], 'Lauf');
    expect(payload['startedAtMs'], now.millisecondsSinceEpoch);
    expect(payload['hr'], isNull);
    expect(payload['signal'], 'none');
    expect(payload['strain'], isNull);
    expect(payload['paused'], false);
    expect(payload.keys, isNot(contains('calories')));
    expect(payload.keys, isNot(contains('targetKcal')));
  });

  test('fresh sample carries its stamp and the stored zone basis', () {
    final sample = now.subtract(const Duration(seconds: 3));
    final payload = LiveActivity.updatePayload(
      hr: 145,
      hrSampleAt: sample,
      signal: LiveSignal.live,
      zone: 3,
      zoneLowPct: 0.7,
      zoneHighPct: 0.8,
      zoneBasis: 'tanaka',
      zoneBasisBpm: 186,
      elapsed: const Duration(minutes: 24, seconds: 18),
      strain: 3.0,
      now: now,
    );
    expect(payload['hr'], 145);
    expect(payload['hrSampleAtMs'], sample.millisecondsSinceEpoch);
    expect(payload['signal'], 'live');
    expect(payload['zone'], 3);
    expect(payload['zoneLowPct'], 0.7);
    expect(payload['zoneHighPct'], 0.8);
    expect(payload['zoneBasis'], 'tanaka');
    expect(payload['zoneBasisBpm'], 186);
    expect(payload['elapsedSeconds'], 1458);
    expect(payload['paused'], false);
    expect(payload['strain'], 3.0);
    expect(payload.keys, isNot(contains('calories')));
  });

  test('weak or aged signal removes HR and zone even with a last number', () {
    for (final signal in [LiveSignal.weak, LiveSignal.live]) {
      final payload = LiveActivity.updatePayload(
        hr: 145,
        hrSampleAt: now.subtract(const Duration(seconds: 6)),
        signal: signal,
        zone: 3,
        zoneLowPct: 0.7,
        zoneHighPct: 0.8,
        zoneBasis: 'observed',
        zoneBasisBpm: 188,
        elapsed: const Duration(minutes: 2),
        strain: null,
        now: now,
      );
      expect(payload['hr'], isNull);
      expect(payload['zone'], isNull);
      expect(payload['zoneBasis'], 'observed');
      expect(payload['zoneBasisBpm'], 188);
      expect(payload['signal'], 'weak');
      expect(payload['strain'], isNull);
    }
  });

  test('below zone one keeps the source but withholds the percent band', () {
    final payload = LiveActivity.updatePayload(
      hr: 83,
      hrSampleAt: now,
      signal: LiveSignal.live,
      zone: null,
      zoneLowPct: null,
      zoneHighPct: null,
      zoneBasis: 'karvonen',
      zoneBasisBpm: 188,
      elapsed: const Duration(seconds: 20),
      strain: null,
      now: now,
    );
    expect(payload['hr'], 83);
    expect(payload['zone'], isNull);
    expect(payload['zoneLowPct'], isNull);
    expect(payload['zoneBasis'], 'karvonen');
    expect(payload['zoneBasisBpm'], 188);
  });

  test('paused payload freezes elapsed and withholds the last HR', () {
    final payload = LiveActivity.updatePayload(
      hr: 145,
      hrSampleAt: now,
      signal: LiveSignal.live,
      zone: 3,
      zoneLowPct: 0.7,
      zoneHighPct: 0.8,
      zoneBasis: 'tanaka',
      zoneBasisBpm: 186,
      elapsed: const Duration(minutes: 24, seconds: 18),
      paused: true,
      strain: 3.0,
      now: now,
    );
    expect(payload['paused'], true);
    expect(payload['elapsedSeconds'], 1458);
    expect(payload['signal'], 'none');
    expect(payload['hr'], isNull);
    expect(payload['zone'], isNull);
    expect(payload['zoneBasis'], 'tanaka');
  });

  test('missing sample or basis stays missing', () {
    final missing = LiveActivity.updatePayload(
      hr: null,
      hrSampleAt: null,
      signal: LiveSignal.none,
      zone: null,
      zoneLowPct: null,
      zoneHighPct: null,
      zoneBasis: null,
      zoneBasisBpm: null,
      elapsed: Duration.zero,
      strain: null,
      now: now,
    );
    expect(missing['hr'], isNull);
    expect(missing['signal'], 'none');
    expect(missing['zone'], isNull);
    expect(missing['zoneBasis'], isNull);
    expect(missing['strain'], isNull);

    final noBasis = LiveActivity.updatePayload(
      hr: 120,
      hrSampleAt: now,
      signal: LiveSignal.live,
      zone: 2,
      zoneLowPct: null,
      zoneHighPct: null,
      zoneBasis: null,
      zoneBasisBpm: null,
      elapsed: Duration.zero,
      strain: null,
      now: now,
    );
    expect(noBasis['hr'], 120);
    expect(noBasis['zone'], isNull);
  });

  test('updates an activity restored after a Dart process restart', () async {
    const channel = MethodChannel('openstrap/live_activity');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await LiveActivity.update(
      hr: null,
      hrSampleAt: null,
      signal: LiveSignal.none,
      zone: null,
      zoneLowPct: null,
      zoneHighPct: null,
      zoneBasis: null,
      zoneBasisBpm: null,
      elapsed: const Duration(seconds: 9),
      strain: null,
    );
    expect(calls, hasLength(1));
    expect(calls.single.method, 'update');
    final payload = calls.single.arguments as Map<Object?, Object?>;
    expect(payload['hr'], isNull);
    expect(payload['elapsedSeconds'], 9);
  });
}
