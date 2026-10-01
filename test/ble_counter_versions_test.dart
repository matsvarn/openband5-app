import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_state.dart';

void main() {
  test('interleaved v24/v26 counters compare only within their version', () {
    final d = CounterRegressionDetector();
    for (var i = 0; i < 5; i++) {
      expect(d.feed(100 + i, recType: 24), isFalse);
      expect(d.feed(10 + i, recType: 26), isFalse);
    }
    expect(d.regressions, 0);
    expect(d.feed(2, recType: 26), isTrue);
    expect(d.regressions, 1);
    expect(d.feed(106, recType: 24), isFalse);
    expect(d.feed(2, recType: 26), isFalse);
    expect(d.regressions, 1);
  });
  test('reseed applies to each version and preserves lifetime total', () {
    final d = CounterRegressionDetector(seedCounter: 100);
    expect(d.feed(1, recType: 24), isTrue);
    expect(d.feed(200, recType: 26), isFalse);
    d.reseed(50);
    expect(d.feed(60, recType: 24), isFalse);
    expect(d.feed(60, recType: 26), isFalse);
    expect(d.regressions, 1);
    expect(d.feed(5, recType: 26), isTrue);
    expect(d.regressions, 2);
  });
}
