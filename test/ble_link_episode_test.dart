import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_state.dart';

void main() {
  late DateTime now;
  late LinkEpisodeTracker tracker;
  setUp(() {
    now = DateTime(2026, 9, 30, 8);
    tracker = LinkEpisodeTracker(now: () => now);
  });
  test('first failure starts an episode, every tenth reports, ready resets', () {
    final start = now;
    expect(
      tracker.connectFailed(),
      '[LINK] unreachable since ${start.toIso8601String()}',
    );
    for (var i = 2; i < 10; i++) {
      now = now.add(const Duration(seconds: 5));
      expect(tracker.connectFailed(), isNull);
    }
    expect(tracker.connectFailed(), contains('10 failed attempts'));
    expect(tracker.unreachableSince, start);
    now = start.add(const Duration(hours: 13));
    tracker.linkUp();
    expect(
      tracker.ready(),
      '[LINK] reachable again after 46800s, 10 failed attempts since ${start.toIso8601String()}',
    );
    expect(tracker.failedAttempts, 0);
    expect(tracker.unreachableSince, isNull);
    expect(tracker.ready(), isNull);
  });
  test('link down uses real link duration and earlier outage time', () {
    tracker.linkUp();
    final up = now;
    now = now.add(const Duration(minutes: 2));
    expect(
      tracker.linkDown(
        reason: '8/supervision timeout',
        lastRxAt: now.subtract(const Duration(seconds: 7)),
      ),
      '[LINK] down reason=8/supervision timeout after 120s last_rx=7s',
    );
    expect(tracker.lastLinkUp, up);
    expect(tracker.lastLinkDown, now);
    expect(tracker.lastDownReason, '8/supervision timeout');
    final down = now;
    now = now.add(const Duration(seconds: 30));
    expect(
      tracker.connectFailed(),
      '[LINK] unreachable since ${down.toIso8601String()}',
    );
    now = now.add(const Duration(seconds: 30));
    tracker.linkUp();
    expect(tracker.ready(), contains('after 60s, 1 failed attempts'));
  });
  test(
    'cold link down reports unknown observations without fabricating ages',
    () {
      expect(
        tracker.linkDown(reason: 'unknown'),
        '[LINK] down reason=unknown after unknown last_rx=unknown',
      );
      now = now.add(const Duration(seconds: 5));
      tracker.linkUp();
      expect(tracker.ready(), contains('after 5s, 0 failed attempts'));
    },
  );
  test('flapping setup cannot move an existing outage start forward', () {
    final start = now;
    tracker.connectFailed();
    now = now.add(const Duration(seconds: 15));
    tracker.linkUp();
    now = now.add(const Duration(seconds: 15));
    tracker.linkDown(reason: '19/central disconnect');
    expect(tracker.unreachableSince, start);
    expect(tracker.failedAttempts, 1);
    now = now.add(const Duration(seconds: 15));
    tracker.linkUp();
    expect(tracker.ready(), contains('after 45s, 1 failed attempts'));
  });
  test('a second outage starts fresh after ready', () {
    tracker.connectFailed();
    tracker.linkUp();
    tracker.ready();
    now = now.add(const Duration(minutes: 1));
    tracker.linkDown(reason: 'unknown');
    final down = now;
    now = now.add(const Duration(seconds: 1));
    expect(tracker.connectFailed(), contains(down.toIso8601String()));
    expect(tracker.failedAttempts, 1);
  });
}
