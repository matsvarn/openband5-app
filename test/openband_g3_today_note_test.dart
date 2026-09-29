import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/g3_data.dart';
import 'package:openstrap_edge/openband/today_note.dart';

void main() {
  const trusted = G3Baseline(
    BaselineStatus(BaselinePhase.trusted),
    range: PersonalRange(58, 80, 68),
  );
  const building = G3Baseline(
    BaselineStatus(BaselinePhase.building, nightsHave: 11, nightsNeeded: 14),
  );
  final now = DateTime(2026, 9, 29, 9, 41);
  final bed = DateTime(2026, 9, 29, 22, 18);
  final wake = DateTime(2026, 9, 30, 6, 54);

  TodayNote? note({
    double? recovery,
    G3Baseline baseline = trusted,
    int? sleep,
    int? goal,
    double? need,
    DateTime? bedtime,
    DateTime? wakeTime,
    String day = '2026-09-29',
  }) => todayNote(
    derivedDay: day,
    now: now,
    recovery: recovery,
    recoveryBaseline: baseline,
    sleepMinutes: sleep,
    sleepGoalMinutes: goal,
    sleepNeedMinutes: need,
    suggestedBedtime: bedtime,
    suggestedWake: wakeTime,
  );

  test('all missing and stale derived day abstain', () {
    expect(note(), isNull);
    expect(
      note(
        recovery: 74,
        sleep: 438,
        goal: 465,
        need: 485,
        bedtime: bed,
        wakeTime: wake,
        day: '2026-09-28',
      ),
      isNull,
    );
  });

  test('every recovery branch uses the trusted stored range', () {
    expect(note(recovery: 81)!.headline, 'Besser erholt als üblich.');
    expect(note(recovery: 80)!.headline, 'Gut erholt.');
    expect(note(recovery: 68)!.reason, 'Erholung über Median');
    expect(note(recovery: 67)!.headline, 'Normal erholt.');
    expect(note(recovery: 58)!.reason, 'Erholung unter Median');
    expect(note(recovery: 57)!.headline, 'Weniger erholt als üblich.');
    expect(note(recovery: 57)!.reason, 'Erholung unter deinem Bereich');
    expect(note(recovery: 74, baseline: building), isNull);
  });

  test('sleep threshold needs real sleep, goal and suggested bedtime', () {
    expect(note(sleep: 438, goal: 465), isNull);
    expect(note(sleep: 438, bedtime: bed), isNull);
    expect(note(goal: 465, bedtime: bed), isNull);
    expect(note(sleep: 438, goal: 465, bedtime: bed), isNull);
    expect(note(sleep: 450, goal: 465, need: 485, bedtime: bed), isNull);
    expect(
      note(sleep: 449, goal: 465, need: 485, bedtime: bed)!.headline,
      'Heute früher ins Bett.',
    );
    expect(
      note(sleep: 449, goal: 465, need: 485, bedtime: bed)!.action,
      isNull,
    );
  });

  test('sample note uses only shown facts and plan times', () {
    final result = note(
      recovery: 74,
      sleep: 438,
      goal: 465,
      need: 485,
      bedtime: bed,
      wakeTime: wake,
    )!;
    expect(result.headline, 'Gut erholt. Heute früher ins Bett.');
    expect(result.reason, 'Erholung über Median, Schlaf 27 Min. unter Ziel');
    expect(result.action!.label, '22:20 ins Bett');
    expect(result.action!.sub, 'für 8h05 Schlafbedarf bis 06:54');
    expect(result.action!.reminderAt, DateTime(2026, 9, 29, 22, 5));
  });

  test(
    'building note adds the real gate only when sleep supplies headline',
    () {
      final result = note(
        baseline: building,
        sleep: 438,
        goal: 465,
        need: 485,
        bedtime: bed,
        wakeTime: wake,
      )!;
      expect(result.headline, 'Heute früher ins Bett.');
      expect(result.reason, 'Schlaf 27 Min. unter Ziel, Erholung ab Nacht 14');
      expect(
        note(
          baseline: const G3Baseline(BaselineStatus(BaselinePhase.building)),
          sleep: 438,
          goal: 465,
          need: 485,
          bedtime: bed,
        )!.reason,
        'Schlaf 27 Min. unter Ziel',
      );
    },
  );
}
