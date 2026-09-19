// The coach's write tools, at the seam where a model's arguments meet a store.
//
// Two failure modes are worth pinning here and nowhere else:
//   • a tool that reports success and writes nothing (P2's `set_step_goal`);
//   • a tool that writes what it was asked and DESTROYS what it was not —
//     a full-day replace would erase the morning's mood; only action-provided
//     keys are patched.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/coach/coach_actions.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';

class _FakeRepo extends LocalRepository {
  Map<String, JournalMetricValue> stored = {};
  Map<String, int> revs = {};
  String? wroteDay;
  Map<String, JournalMetricValue?>? lastPatch;

  @override
  Future<List<JournalFieldSpec>> getJournalFields({
    bool includeHidden = false,
  }) async => kJournalFields;

  @override
  Future<Map<String, JournalMetricValue>> getJournalMetrics(String date) async =>
      Map.of(stored);

  @override
  Future<JournalDaySnapshot> readJournalDay(String day) async =>
      JournalDaySnapshot(
        day: day,
        metrics: Map.of(stored),
        metricUpdatedAt: Map.of(revs),
        tags: const [],
        note: '',
        journalUpdatedAt: 0,
        fields: kJournalFields,
      );

  @override
  Future<void> patchJournalDay(JournalDayPatch patch) async {
    wroteDay = patch.day;
    lastPatch = Map.of(patch.metrics);
    for (final e in patch.metrics.entries) {
      if (e.value == null) {
        stored.remove(e.key);
        revs.remove(e.key);
      } else {
        stored[e.key] = e.value!;
        revs[e.key] = (revs[e.key] ?? 0) + 1;
      }
    }
  }
}

void main() {
  group('argument coercion — the model is an untrusted caller', () {
    test('a relative word is not a date', () {
      expect(
        () => CoachActions.day('yesterday'),
        throwsA(isA<CoachActionError>()),
      );
      expect(CoachActions.day('2026-08-14'), '2026-08-14');
    });

    test('an empty date means today, in LOCAL time', () {
      final now = DateTime(2026, 8, 14, 23, 30);
      expect(CoachActions.day(null, now: now), '2026-08-14');
    });

    test('a time must be a real time of day', () {
      expect(CoachActions.minuteOfDay('08:30'), 8 * 60 + 30);
      expect(() => CoachActions.minuteOfDay('25:00'),
          throwsA(isA<CoachActionError>()));
      expect(() => CoachActions.minuteOfDay('half eight'),
          throwsA(isA<CoachActionError>()));
    });

    test('local wall clock is what epochOf converts, not UTC', () {
      final sec = CoachActions.epochOf('2026-08-14', 7 * 60 + 15);
      final back = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
      expect(back.hour, 7);
      expect(back.minute, 15);
      expect(back.day, 14);
    });
  });

  group('log_journal_fields', () {
    test('patches only the given keys rather than replacing the day', () async {
      final repo = _FakeRepo()
        ..stored = {'mood': const JournalMetricValue(4)}
        ..revs = {'mood': 1};
      await CoachActions.logJournalFields(repo, {
        'date': '2026-08-14',
        'fields': {'water_ml': 1000},
      });
      expect(repo.wroteDay, '2026-08-14');
      expect(repo.lastPatch?.keys, ['water_ml']);
      expect(repo.stored['water_ml']?.value, 1000);
      // The morning's mood survives the afternoon's water.
      expect(repo.stored['mood']?.value, 4);
    });

    test('an unknown field is refused, not invented', () async {
      final repo = _FakeRepo();
      await expectLater(
        CoachActions.logJournalFields(repo, {
          'fields': {'hydration_score': 8},
        }),
        throwsA(isA<CoachActionError>()),
      );
      expect(repo.wroteDay, isNull);
    });

    test('a time only rides along on a field that carries one', () async {
      final repo = _FakeRepo();
      await CoachActions.logJournalFields(repo, {
        'date': '2026-08-14',
        'time': '21:00',
        'fields': {'caffeine_mg': 80, 'water_ml': 250},
      });
      expect(repo.stored['caffeine_mg']?.atMinuteOfDay, 21 * 60);
      expect(repo.stored['water_ml']?.atMinuteOfDay, isNull);
    });

    test('value-only caffeine keeps the stored dose time', () async {
      final repo = _FakeRepo()
        ..stored = {
          'caffeine_mg': const JournalMetricValue(180, atMinuteOfDay: 855),
          'mood': const JournalMetricValue(3),
        }
        ..revs = {'caffeine_mg': 1, 'mood': 1};
      await CoachActions.logJournalFields(repo, {
        'date': '2026-08-14',
        'fields': {'caffeine_mg': 250},
      });
      expect(repo.lastPatch?.keys, ['caffeine_mg']);
      expect(repo.stored['caffeine_mg']?.value, 250);
      expect(repo.stored['caffeine_mg']?.atMinuteOfDay, 855);
      expect(repo.stored['mood']?.value, 3);
    });

    test('an explicit time updates the stored caffeine dose time', () async {
      final repo = _FakeRepo()
        ..stored = {
          'caffeine_mg': const JournalMetricValue(180, atMinuteOfDay: 855),
        }
        ..revs = {'caffeine_mg': 1};
      await CoachActions.logJournalFields(repo, {
        'date': '2026-08-14',
        'time': '21:00',
        'fields': {'caffeine_mg': 250},
      });
      expect(repo.stored['caffeine_mg']?.value, 250);
      expect(repo.stored['caffeine_mg']?.atMinuteOfDay, 21 * 60);
    });
  });

  group('setStepGoal actually stores something (P2)', () {
    test('a process with no profile writer FAILS instead of pretending', () {
      final repo = LocalRepositoryImpl(getProfileMap: () => {});
      expect(repo.setStepGoal(9000), throwsA(isA<RepositoryException>()));
    });

    test('the goal reaches the writer', () async {
      Map<String, dynamic>? seen;
      final repo = LocalRepositoryImpl(
        getProfileMap: () => {'name': 'x'},
        saveProfileFields: (f) async {
          seen = f;
          return {'name': 'x', ...f};
        },
      );
      final out = await repo.setStepGoal(9000);
      expect(seen, {'step_goal': 9000});
      expect(out['step_goal'], 9000);
    });

    test('an absurd goal is refused at the boundary', () {
      final repo = LocalRepositoryImpl(
        getProfileMap: () => {},
        saveProfileFields: (f) async => f,
      );
      expect(repo.setStepGoal(3), throwsA(isA<RepositoryException>()));
      expect(repo.setStepGoal(900000), throwsA(isA<RepositoryException>()));
    });
  });
}
