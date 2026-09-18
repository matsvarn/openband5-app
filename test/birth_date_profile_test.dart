import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('age is resolved on the recording date, including the birthday', () {
    final profile = PersonalProfile(birthDate: DateTime(1990, 9, 16));
    expect(profile.forDate(DateTime(2026, 9, 15, 23, 59)).ageYears, 35);
    expect(profile.forDate(DateTime(2026, 9, 16)).ageYears, 36);
    expect(profile.forDate(DateTime(2026, 9, 17)).ageYears, 36);
    expect(profile.forDate(DateTime(2020, 2, 1)).ageYears, 29);
  });

  test('February 29 birthdays advance on March 1 in non-leap years', () {
    final birth = DateTime(2000, 2, 29);
    expect(ageOnDate(birth, DateTime(2024, 2, 28)), 23);
    expect(ageOnDate(birth, DateTime(2024, 2, 29)), 24);
    expect(ageOnDate(birth, DateTime(2025, 2, 28)), 24);
    expect(ageOnDate(birth, DateTime(2025, 3, 1)), 25);
  });

  test('storage round-trips a calendar date without an age or a time', () {
    final profile = PersonalProfile.fromMap({
      'birth_date': '1990-09-16',
      'age': 99,
      'weight_kg': 75,
    });
    expect(profile.toMap(), {'birth_date': '1990-09-16', 'weight_kg': 75.0});
    expect(profile.forDate(DateTime(2026, 9, 16)).ageYears, 36);
    expect(birthDateString(DateTime.utc(1990, 9, 16)), '1990-09-16');
  });

  test('missing, legacy and invalid dates cannot supply a calculation age', () {
    for (final value in [
      null,
      34,
      '1990-02-31',
      '1990-13-01',
      '1990-2-1',
      '1990-01-01T00:00:00Z',
    ]) {
      expect(parseBirthDate(value), isNull);
    }
    expect(
      PersonalProfile.fromMap({'age': 34}).forDate(DateTime(2026)).ageYears,
      isNull,
    );
    expect(ageOnDate(DateTime(2026, 9, 16), DateTime(2026, 9, 15)), isNull);
    expect(parseBirthDate('2000-02-29'), DateTime(2000, 2, 29));
  });

  test(
    'saving replaces legacy age and clearing survives persistence',
    () async {
      SharedPreferences.setMockInitialValues({});
      final app = AppState.forTesting()..user = {'age': 34, 'name': 'Test'};
      addTearDown(app.dispose);
      final updated = await app.updateProfile({'birth_date': '1990-09-16'});
      expect(updated, {'birth_date': '1990-09-16', 'name': 'Test'});
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getKeys().map(prefs.getString).whereType<String>();
      expect(stored.map(jsonDecode), contains(equals(updated)));
      final cleared = await app.updateProfile({'birth_date': null});
      expect(PersonalProfile.fromMap(cleared).birthDate, isNull);
      expect(cleared, isNot(contains('age')));
    },
  );

  test('invalid and future dates do not change a saved profile', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    await app.updateProfile({'birth_date': '1990-09-16'});
    for (final invalid in ['1990-02-31', '9999-01-01']) {
      await expectLater(
        app.updateProfile({'birth_date': invalid}),
        throwsFormatException,
      );
      expect(app.user!['birth_date'], '1990-09-16');
    }
  });
}
