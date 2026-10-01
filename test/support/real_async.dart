/// Repeats [step] until [done] holds or [timeout] of real time has passed, and
/// returns whether [done] held. Callers assert afterwards, so a failure names
/// the real expectation rather than a timeout.
///
/// For widget tests that wait on real asynchronous work, such as SQLite reads
/// through the FFI isolate inside `tester.runAsync`. Counting a fixed number
/// of short real-time turns is a flake: a budget that is long enough on an
/// idle laptop runs out on a loaded CI runner. The deadline only matters when
/// the work is slow; a fast run returns as soon as [done] holds.
Future<bool> untilReal(
  bool Function() done,
  Future<void> Function() step, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final clock = Stopwatch()..start();
  while (!done()) {
    if (clock.elapsed >= timeout) return false;
    await step();
  }
  return true;
}
