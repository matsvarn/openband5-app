// `g3_review.py --real` renders personal data: the harness refuses any
// output folder outside OpenBand5Lab/ui-review-real/.
import 'package:flutter_test/flutter_test.dart';

import '../tool/g3_screens/env.dart';

void main() {
  const home = '/Users/tester';
  const root = '$home/Library/Application Support/OpenBand5Lab/ui-review-real';

  test('accepts a stamp folder under ui-review-real', () {
    expect(g3RealOut({'HOME': home, 'G3_OUT': '$root/20260929-0941'}), '$root/20260929-0941');
  });

  test('requires G3_OUT', () {
    expect(() => g3RealOut({'HOME': home}), throwsStateError);
    expect(() => g3RealOut({'HOME': home, 'G3_OUT': ''}), throwsStateError);
  });

  test('refuses the repo, build/, the root itself and a way out with ..', () {
    for (final out in [
      'build/g3-review-real',
      '/tmp/g3',
      root,
      '$root/../ui-review/x',
      '$home/Library/Application Support/OpenBand5Lab/ui-review-real-x/y',
    ]) {
      expect(() => g3RealOut({'HOME': home, 'G3_OUT': out}), throwsStateError, reason: out);
    }
  });
}
