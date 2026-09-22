// The two prompts that ASK you to log something — medication and the daily
// check-in — as pure policy. No plugins: nothing here schedules, it only
// decides what would be scheduled and when.
//
// Three properties are pinned, because each one is a bug this app has already
// shipped:
//
//   · every new id is on NotificationService.schedulableIds. A slot absent
//     from that list is dropped silently at the gate and never fires once —
//     which is what happened to the movement nudge for its whole life.
//   · a prompt does not fire for something already logged. A reminder to take
//     a pill already taken is how people turn every notification off.
//   · the tap route resolves to a real destination. The audit found one
//     notification saying "tap to log it" that landed on a screen which did
//     not exist, and another whose route mapped to null.

import 'package:flutter_test/flutter_test.dart';

import 'package:openstrap_edge/app.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/medication.dart';
import 'package:openstrap_edge/openband/nutrition_route.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/app_shell.dart' show ShellDomain;
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/notify/notification_center.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/notify/notification_service.dart';
import 'package:openstrap_edge/notify/tap_router.dart';

MedReminderInstant _instant(
  DateTime at, {
  String key = 'a',
  String? date,
  int? slotMin,
}) =>
    (
      key: key,
      date: date ?? todayLabel(at),
      slotMin: slotMin ?? at.hour * 60 + at.minute,
      at: at,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the scheduler allow-list', () {
    test('takes the check-in and the whole medication band', () {
      expect(NotificationService.maySchedule(NotificationService.idCheckIn),
          isTrue);
      for (var i = 0; i < NotificationService.maxMedSlots; i++) {
        expect(
            NotificationService.maySchedule(NotificationService.idMedsBase + i),
            isTrue,
            reason: 'med slot $i');
      }
    });

    test('and still refuses the ids either side of the band', () {
      expect(NotificationService.maySchedule(NotificationService.idMedsBase - 1),
          isFalse);
      expect(
          NotificationService.maySchedule(
              NotificationService.idMedsBase + NotificationService.maxMedSlots),
          isFalse);
    });

    test('the bands are disjoint from the hydration one', () {
      for (var i = 0; i < NotificationService.maxMedSlots; i++) {
        expect(NotificationService.isWaterSlot(NotificationService.idMedsBase + i),
            isFalse);
      }
      expect(NotificationService.isMedSlot(NotificationService.idCheckIn), isFalse);
      expect(NotificationService.isMedSlot(NotificationService.idStillness), isFalse);
    });
  });

  group('the check-in knows when it has already been answered', () {
    test('any rating counts, and one is enough', () {
      for (final f in kJournalFields.where((f) => f.isRating)) {
        expect(
            NotificationCenter.checkInDone({f.key: const JournalMetricValue(3)}),
            isTrue,
            reason: f.key);
      }
    });

    test('a dose logged as it happened is not a self-report', () {
      // Water at lunchtime says nothing about whether the day has been
      // reflected on — this is the case that would otherwise silence the
      // prompt for anyone who uses the water reminder.
      expect(
          NotificationCenter.checkInDone(
              const {'water_ml': JournalMetricValue(500)}),
          isFalse);
      expect(
          NotificationCenter.checkInDone(
              const {'caffeine_mg': JournalMetricValue(200)}),
          isFalse);
      expect(NotificationCenter.checkInDone(const {}), isFalse);
    });
  });

  group('the check-in follows the person', () {
    const off = NotificationPrefs();
    const on = NotificationPrefs(checkInEnabled: true);

    test('off by default — nothing is armed for anyone who did not ask', () {
      expect(NotificationCenter.checkInMinute(off, 23 * 60), isNull);
    });

    test('an hour before the bedtime the coach learned', () {
      expect(NotificationCenter.checkInMinute(on, 21 * 60), 20 * 60);
      // A late chronotype is asked later, not at everyone else's 20:30.
      expect(NotificationCenter.checkInMinute(on, 22 * 60 + 30), 21 * 60 + 30);
    });

    test('no bedtime yet → the stated fixed fallback', () {
      expect(NotificationCenter.checkInMinute(on, null),
          NotificationCenter.checkInFallbackMin);
    });

    test('never inside the quiet window, whatever the bedtime says', () {
      // 01:00 bedtime. Minus an hour is midnight, which is the middle of the
      // window the user asked not to be interrupted in.
      final t = NotificationCenter.checkInMinute(on, 25 * 60)!;
      expect(t, 21 * 60 + 30); // quietStart 22:00, minus the half-hour margin
      expect(on.inQuietHours(t), isFalse);
    });

    test('never before the day has happened', () {
      // A 17:00 bedtime would put the prompt at 16:00.
      expect(NotificationCenter.checkInMinute(on, 17 * 60),
          NotificationCenter.checkInEarliestMin);
    });

    test('a quiet window that swallows the evening arms nothing', () {
      const all = NotificationPrefs(
          checkInEnabled: true, quietStartMin: 12 * 60, quietEndMin: 11 * 60);
      expect(NotificationCenter.checkInMinute(all, null), isNull);
    });
  });

  group('the check-in does not ask twice', () {
    const on = NotificationPrefs(checkInEnabled: true);

    test('a day already written is not asked about again', () {
      expect(
          NotificationCenter.checkInSlot(on, null,
              doneToday: true, nowMin: 12 * 60),
          isNull);
    });

    test('but tomorrow is still armed once tonight has passed', () {
      // 21:00, journal written, slot was 20:30 — that instance is behind us, so
      // the one being armed is tomorrow's and the day it asks about is not
      // written yet.
      expect(
          NotificationCenter.checkInSlot(on, null,
              doneToday: true, nowMin: 21 * 60),
          NotificationCenter.checkInFallbackMin);
    });

    test('an unwritten day arms normally', () {
      expect(
          NotificationCenter.checkInSlot(on, null,
              doneToday: false, nowMin: 12 * 60),
          NotificationCenter.checkInFallbackMin);
    });
  });

  group('medication prompts consume already-resolved instants', () {
    final now = DateTime(2026, 8, 20, 10, 0);
    const on = NotificationPrefs(medsEnabled: true);
    final upcoming = [
      _instant(DateTime(2026, 8, 20, 20), key: 'd3'),
      _instant(DateTime(2026, 8, 21, 8), key: 'd3'),
      _instant(DateTime(2026, 8, 21, 20), key: 'd3'),
      _instant(DateTime(2026, 8, 22, 8), key: 'd3'),
      _instant(DateTime(2026, 8, 22, 20), key: 'd3'),
    ];

    test('off by default', () {
      expect(
        NotificationCenter.medReminderPlan(
          const NotificationPrefs(),
          upcoming,
          now: now,
        ),
        isEmpty,
      );
    });

    test('unknown source is a no-op plan — the caller preserves', () {
      expect(
        NotificationCenter.medReminderPlan(on, null, now: now),
        isEmpty,
      );
    });

    test('known empty cancels by producing nothing to arm', () {
      expect(
        NotificationCenter.medReminderPlan(on, const [], now: now),
        isEmpty,
      );
    });

    test('soonest first, past instants dropped, 3-day horizon', () {
      final s = NotificationCenter.medReminderPlan(on, [
        _instant(DateTime(2026, 8, 20, 8), key: 'past'),
        ...upcoming,
        _instant(DateTime(2026, 8, 23, 8), key: 'beyond'),
      ], now: now);
      expect(s.length, 5);
      expect(s.first.at, DateTime(2026, 8, 20, 20));
      for (var i = 1; i < s.length; i++) {
        expect(s[i].at.isAfter(s[i - 1].at), isTrue);
      }
      expect(s.any((x) => x.at.day == 23), isFalse);
    });

    test('two pills at the same minute are one interruption', () {
      final s = NotificationCenter.medReminderPlan(on, [
        _instant(DateTime(2026, 8, 20, 20), key: 'a'),
        _instant(DateTime(2026, 8, 20, 20), key: 'b'),
        _instant(DateTime(2026, 8, 21, 20), key: 'a'),
        _instant(DateTime(2026, 8, 21, 20), key: 'b'),
      ], now: now);
      expect(s.length, 2);
    });

    test('never more slots than the id band, ids 2300+, no drug names', () {
      final many = [
        for (var i = 0; i < 16; i++)
          _instant(now.add(Duration(hours: i + 1)), key: 'm$i'),
      ];
      final s = NotificationCenter.medReminderPlan(on, many, now: now);
      expect(s.length, NotificationService.maxMedSlots);
      for (var i = 0; i < s.length; i++) {
        expect(s[i].id, NotificationService.idMedsBase + i);
        expect(NotificationService.maySchedule(s[i].id), isTrue);
        expect(s[i].title, 'Medication');
        expect(s[i].body, 'A dose is due.');
        expect(s[i].title.toLowerCase(), isNot(contains('m$i')));
        expect(s[i].body.toLowerCase(), isNot(contains('mg')));
        expect(s[i].route, kRouteMeds);
      }
    });
  });

  group('both prompts have somewhere to land', () {
    test('the check-in opens the journal it is asking you to write', () {
      final t = resolveTapRoute(kRouteJournalCompose);
      expect(t.screen, kRouteJournalCompose);
      expect(screenForRoute(kRouteJournalCompose), isNotNull);
    });

    test('the medication reminder pushes OpenBandMedications over Journal', () {
      final t = resolveTapRoute(kRouteMeds);
      expect(t.screen, kRouteMeds);
      expect(domainForRoute(kRouteMeds), ShellDomain.wellness);
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final screen = screenForRoute(
        kRouteMeds,
        repository: LocalOpenBandRepository(app),
      );
      expect(screen, isA<OpenBandMedications>());
      expect((screen! as OpenBandMedications).day, todayLabel());
      expect(screenForRoute(kRouteWater), isA<OpenBandNutritionRoute>());
    });

    test('an unknown route still falls back to Home rather than crashing', () {
      expect(resolveTapRoute('/nope').tab, 0);
      expect(resolveTapRoute('/nope').screen, isNull);
    });
  });
}
