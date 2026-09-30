// UnitsController pace formatting — regression coverage for a real user
// report: a near-zero GPS distance divided into real elapsed time produced
// an absurd "189:xx" style pace.
//
// The honest answer is NULL, not '—'. A formatter cannot know why a value is
// missing, and a bare dash rendered into a stat slot is a defect on its own —
// the callers now drop the stat instead of drawing a placeholder.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('UnitsController pace sanity ceiling', () {
    test('formatPace answers null for an absurdly slow pace, not the raw '
        'number', () {
      // 1000 min/km — the exact class of number the bug produced.
      expect(UnitsController.formatPace(1000 * 60), isNull);
    });

    test('formatPace still shows a real, plausible pace normally', () {
      expect(UnitsController.formatPace(5 * 60 + 30), '5:30');
    });

    test('pace() returns null (never "— /km") for a near-zero distance '
        'over real elapsed time — the exact bed-jitter scenario', () {
      final u = UnitsController.seed(UnitSystem.metric);
      // 1 metre over 60 seconds — GPS noise, not a real 60 min/km pace.
      expect(u.pace(1, 60), isNull);
    });

    test('pace() returns a normal formatted pace for real distance/time', () {
      final u = UnitsController.seed(UnitSystem.metric);
      // 1 km in 5:30 → "5:30 /km".
      expect(u.pace(1000, 5 * 60 + 30), '5:30 /km');
    });

    test('paceFromSpeed() returns null consistently, never "— /km"', () {
      final u = UnitsController.seed(UnitSystem.metric);
      expect(u.paceFromSpeed(null), isNull);
      expect(u.paceFromSpeed(0), isNull);
    });
  });

  group('imperial', () {
    final u = UnitsController.seed(UnitSystem.imperial);

    test('distance converts and labels in miles', () {
      // 5 km = 3.107 mi.
      expect(u.distance(5000), '3.11 mi');
      expect(u.distanceUnit, 'mi');
    });

    test('pace is per mile, not per km', () {
      // 5:00/km over 5 km is 8:03/mi (5 min × 1.609344).
      expect(u.pace(5000, 25 * 60), '8:03 /mi');
    });

    test('speed reads mph', () {
      // 10 m/s = 22.4 mph.
      expect(u.speed(10), '22.4 mph');
    });

    test('metric is unchanged', () {
      final m = UnitsController.seed(UnitSystem.metric);
      expect(m.distance(5000), '5.00 km');
      expect(m.pace(5000, 25 * 60), '5:00 /km');
      expect(m.speed(10), '36.0 km/h');
    });
  });

  group('durable persist', () {
    test('false persist keeps the last committed system', () async {
      final u = UnitsController.seed(
        UnitSystem.metric,
        persist: (_) async => false,
      );
      addTearDown(u.dispose);
      expect(await u.setSystem(UnitSystem.imperial), isFalse);
      expect(u.system, UnitSystem.metric);
    });

    test('thrown persist keeps the last committed system', () async {
      final u = UnitsController.seed(
        UnitSystem.metric,
        persist: (_) async => throw Exception('disk'),
      );
      addTearDown(u.dispose);
      expect(await u.setSystem(UnitSystem.imperial), isFalse);
      expect(u.system, UnitSystem.metric);
    });

    test('delayed persist does not show the new selection early', () async {
      final gate = Completer<bool>();
      final u = UnitsController.seed(
        UnitSystem.metric,
        persist: (_) => gate.future,
      );
      addTearDown(u.dispose);
      final pending = u.setSystem(UnitSystem.imperial);
      expect(u.system, UnitSystem.metric);
      gate.complete(true);
      expect(await pending, isTrue);
      expect(u.system, UnitSystem.imperial);
    });

    test('overlapping setSystem cannot apply out of order', () async {
      final imperialStarted = Completer<void>();
      final imperialGate = Completer<void>();
      final writes = <UnitSystem>[];
      final u = UnitsController.seed(
        UnitSystem.metric,
        persist: (system) async {
          writes.add(system);
          if (system == UnitSystem.imperial) {
            imperialStarted.complete();
            await imperialGate.future;
          }
          return true;
        },
      );
      addTearDown(u.dispose);
      final first = u.setSystem(UnitSystem.imperial);
      await imperialStarted.future;
      final second = u.setSystem(UnitSystem.metric);
      expect(u.system, UnitSystem.metric);
      imperialGate.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(u.system, UnitSystem.metric);
      expect(writes, [UnitSystem.imperial, UnitSystem.metric]);
    });

    test('successful first persist stays visible if the later write fails',
        () async {
      SharedPreferences.setMockInitialValues({});
      final imperialStarted = Completer<void>();
      final imperialGate = Completer<void>();
      final u = UnitsController.seed(
        UnitSystem.metric,
        persist: (system) async {
          if (system == UnitSystem.imperial) {
            imperialStarted.complete();
            await imperialGate.future;
          }
          if (system == UnitSystem.metric) return false;
          final prefs = await SharedPreferences.getInstance();
          return prefs.setString('units_system', system.name);
        },
      );
      addTearDown(u.dispose);
      final first = u.setSystem(UnitSystem.imperial);
      await imperialStarted.future;
      final second = u.setSystem(UnitSystem.metric);
      expect(u.system, UnitSystem.metric);
      imperialGate.complete();
      expect(await first, isTrue);
      expect(await second, isFalse);
      expect(u.system, UnitSystem.imperial);
      expect(
        (await SharedPreferences.getInstance()).getString('units_system'),
        'imperial',
      );
      final reopened = await UnitsController.bootstrap();
      addTearDown(reopened.dispose);
      expect(reopened.system, UnitSystem.imperial);
    });

    test('dispose during persist still records the saved system', () async {
      final started = Completer<void>();
      final gate = Completer<bool>();
      final u = UnitsController.seed(
        UnitSystem.metric,
        persist: (_) async {
          started.complete();
          return gate.future;
        },
      );
      final pending = u.setSystem(UnitSystem.imperial);
      await started.future;
      u.dispose();
      gate.complete(true);
      expect(await pending, isTrue);
      expect(u.system, UnitSystem.imperial);
    });

    test('default persist writes units_system', () async {
      SharedPreferences.setMockInitialValues({});
      final u = UnitsController.seed(UnitSystem.metric);
      addTearDown(u.dispose);
      expect(await u.setSystem(UnitSystem.imperial), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('units_system'), 'imperial');
      expect(u.system, UnitSystem.imperial);
    });

    test('bootstrap reads units_system', () async {
      SharedPreferences.setMockInitialValues({'units_system': 'imperial'});
      final u = await UnitsController.bootstrap();
      addTearDown(u.dispose);
      expect(u.system, UnitSystem.imperial);

      SharedPreferences.setMockInitialValues({});
      final metric = await UnitsController.bootstrap();
      addTearDown(metric.dispose);
      expect(metric.system, UnitSystem.metric);
    });
  });
}
