import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/domain.dart';

void main() {
  test('gaps under five minutes are not surfaced', () {
    expect(significantSleepGap(null), isNull);
    expect(significantSleepGap(0), isNull);
    expect(significantSleepGap(4.9), isNull);
  });

  test('gaps of five minutes or more are surfaced unchanged', () {
    expect(significantSleepGap(5), 5);
    expect(significantSleepGap(24), 24);
  });
}
