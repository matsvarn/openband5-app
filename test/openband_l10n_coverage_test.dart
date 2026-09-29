import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every English localization key has a German translation', () {
    Map<String, dynamic> read(String locale) =>
        jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
            as Map<String, dynamic>;

    final english = read('en');
    final german = read('de');
    final missing = english.keys
        .where((key) => !key.startsWith('@') && !german.containsKey(key))
        .toList()
      ..sort();

    expect(missing, isEmpty, reason: 'Missing German ARB keys: $missing');
  });
}
