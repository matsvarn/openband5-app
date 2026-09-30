import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/medication_data.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';

Map _load(String name) =>
    jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync())
        as Map;

SyntheticOpenBandRepository repo() => SyntheticOpenBandRepository.fromMaps(
      _load('day-summary.json'),
      _load('sleep-detail.json'),
    );

void main() {
  final now = SyntheticOpenBandRepository.medicationFixtureNow;

  test('fixture day lists Präparat A unknown and B upcoming', () async {
    final day = await repo().readMedicationDay(
      SyntheticOpenBandRepository.medicationFixtureDay,
      now: now,
    );
    expect(day.unreadableCount, 0);
    expect(day.entries, hasLength(2));
    final a = day.entries.singleWhere(
      (e) => e.key == SyntheticOpenBandRepository.medicationFixturePlanAKey,
    );
    final b = day.entries.singleWhere(
      (e) => e.key == SyntheticOpenBandRepository.medicationFixturePlanBKey,
    );
    expect(a.slotMin, 8 * 60);
    expect(a.status, MedicationSlotStatus.unknown);
    expect(a.snapshotLabel, 'Präparat A');
    expect(a.snapshotDoseValue, 1);
    expect(a.snapshotDoseUnit, 'Tablette');
    expect(a.orphan, isFalse);
    expect(b.slotMin, 20 * 60);
    expect(b.status, MedicationSlotStatus.upcoming);
    expect(b.snapshotLabel, 'Präparat B');
    expect(b.snapshotDoseUnit, 'Kapsel');
    expect(day.entries.any((e) => e.status == MedicationSlotStatus.skipped), isFalse);
  });

  test('history keeps prior taken and unknown without inventing skipped', () async {
    final hist = await repo().readMedicationHistory(
      '2026-09-13',
      '2026-09-15',
      now: now,
    );
    final priorA = hist.entries.singleWhere(
      (e) =>
          e.date == '2026-09-14' &&
          e.key == SyntheticOpenBandRepository.medicationFixturePlanAKey,
    );
    expect(priorA.status, MedicationSlotStatus.taken);
    expect(priorA.snapshotLabel, 'Präparat A');
    final priorB = hist.entries.singleWhere(
      (e) =>
          e.date == '2026-09-14' &&
          e.key == SyntheticOpenBandRepository.medicationFixturePlanBKey,
    );
    expect(priorB.status, MedicationSlotStatus.unknown);
    final legacy = hist.entries.singleWhere((e) => e.date == '2026-09-13');
    expect(legacy.status, MedicationSlotStatus.unknown);
    expect(legacy.snapshotLabel, isNull);
    expect(legacy.snapshotDoseUnit, isNull);
    expect(legacy.orphan, isTrue);
  });

  test('plans are current heads and empty schedule is representable', () async {
    final r = repo();
    final plans = await r.readMedicationPlans();
    expect(plans.map((p) => p.name), ['Präparat A', 'Präparat B']);
    final saved = await r.saveMedicationPlan(
      const MedicationPlanDraft(
        create: true,
        name: 'Ohne Zeiten',
        schedule: [],
      ),
      now: now,
    );
    expect(saved.committed, isTrue);
    expect(saved.remindersFailed, isFalse);
    expect(saved.plan!.schedule, isEmpty);
    expect(saved.plan!.doseValue, isNull);
    expect(saved.plan!.doseUnit, isNull);
  });

  test('missing update refuses and does not invent a plan', () async {
    final r = repo();
    await expectLater(
      r.saveMedicationPlan(
        const MedicationPlanDraft(
          create: false,
          key: 'missing-key',
          name: 'Ghost',
        ),
        now: now,
      ),
      throwsStateError,
    );
    final plans = await r.readMedicationPlans(activeOnly: false);
    expect(plans.any((p) => p.key == 'missing-key'), isFalse);
  });

  test('name collisions stay distinct identities', () async {
    final r = repo();
    final first = await r.saveMedicationPlan(
      const MedicationPlanDraft(create: true, name: 'Kollision'),
      now: now,
    );
    final second = await r.saveMedicationPlan(
      const MedicationPlanDraft(create: true, name: 'Kollision'),
      now: now.add(const Duration(minutes: 1)),
    );
    expect(first.plan!.key, isNot(second.plan!.key));
    expect(first.plan!.name, second.plan!.name);
  });

  test('end at 10 keeps 08 and drops 20; restart restores later slots', () async {
    final r = repo();
    final created = await r.saveMedicationPlan(
      const MedicationPlanDraft(
        create: true,
        name: 'Zwei Zeiten',
        schedule: [
          MedicationScheduleSlot(minuteOfDay: 8 * 60),
          MedicationScheduleSlot(minuteOfDay: 20 * 60),
        ],
      ),
      now: DateTime(2026, 9, 15, 7),
    );
    await r.saveMedicationEntry(
      MedicationEntryDraft(
        key: created.plan!.key,
        date: '2026-09-15',
        slotMin: 8 * 60,
        answer: MedicationEntryAnswer.taken,
        takenAt: DateTime(2026, 9, 15, 8, 5),
      ),
      now: DateTime(2026, 9, 15, 8, 5),
    );
    await r.endMedicationPlan(
      created.plan!.key,
      now: DateTime(2026, 9, 15, 10),
    );
    final ended = await r.readMedicationDay(
      '2026-09-15',
      now: DateTime(2026, 9, 15, 12),
    );
    final mine = ended.entries.where((e) => e.key == created.plan!.key).toList();
    expect(mine.map((e) => e.slotMin), [8 * 60]);
    expect(mine.single.status, MedicationSlotStatus.taken);
    await r.restartMedicationPlan(
      created.plan!.key,
      now: DateTime(2026, 9, 15, 12),
    );
    final again = await r.readMedicationDay(
      '2026-09-15',
      now: DateTime(2026, 9, 15, 12),
    );
    final slots =
        again.entries.where((e) => e.key == created.plan!.key).map((e) => e.slotMin);
    expect(slots, containsAll([8 * 60, 20 * 60]));
  });

  test('taken snapshot freezes; later rename does not backfill nulls', () async {
    final r = repo();
    final created = await r.saveMedicationPlan(
      const MedicationPlanDraft(
        create: true,
        name: 'Alt',
        doseValue: 1,
        doseUnit: 'Tablette',
        schedule: [MedicationScheduleSlot(minuteOfDay: 8 * 60)],
      ),
      now: DateTime(2026, 9, 15, 7),
    );
    await r.saveMedicationEntry(
      MedicationEntryDraft(
        key: created.plan!.key,
        date: '2026-09-15',
        slotMin: 8 * 60,
        answer: MedicationEntryAnswer.taken,
        takenAt: DateTime(2026, 9, 15, 8, 1),
      ),
      now: DateTime(2026, 9, 15, 8, 1),
    );
    await r.saveMedicationPlan(
      MedicationPlanDraft(
        create: false,
        key: created.plan!.key,
        name: 'Neu',
        doseValue: 2,
        doseUnit: 'Kapsel',
        schedule: const [MedicationScheduleSlot(minuteOfDay: 8 * 60)],
      ),
      now: DateTime(2026, 9, 15, 9),
    );
    final day = await r.readMedicationDay(
      '2026-09-15',
      now: DateTime(2026, 9, 15, 9, 41),
    );
    final row = day.entries.singleWhere((e) => e.key == created.plan!.key);
    expect(row.snapshotLabel, 'Alt');
    expect(row.snapshotDoseValue, 1);
    expect(row.snapshotDoseUnit, 'Tablette');
    expect(row.currentName, 'Neu');
    await r.saveMedicationEntry(
      MedicationEntryDraft(
        key: created.plan!.key,
        date: '2026-09-15',
        slotMin: 8 * 60,
        answer: MedicationEntryAnswer.skipped,
      ),
      now: DateTime(2026, 9, 15, 9, 50),
    );
    final skipped = (await r.readMedicationDay(
      '2026-09-15',
      now: DateTime(2026, 9, 15, 9, 50),
    ))
        .entries
        .singleWhere((e) => e.key == created.plan!.key);
    expect(skipped.status, MedicationSlotStatus.skipped);
    expect(skipped.snapshotLabel, 'Alt');
    expect(skipped.snapshotDoseUnit, 'Tablette');
  });

  test('clear restores unknown and does not delete the plan', () async {
    final r = repo();
    await r.saveMedicationEntry(
      const MedicationEntryDraft(
        key: SyntheticOpenBandRepository.medicationFixturePlanAKey,
        date: '2026-09-15',
        slotMin: 8 * 60,
        answer: MedicationEntryAnswer.skipped,
      ),
      now: now,
    );
    final cleared = await r.saveMedicationEntry(
      const MedicationEntryDraft(
        key: SyntheticOpenBandRepository.medicationFixturePlanAKey,
        date: '2026-09-15',
        slotMin: 8 * 60,
        answer: MedicationEntryAnswer.clear,
      ),
      now: now,
    );
    expect(cleared.committed, isTrue);
    expect(cleared.entry!.status, MedicationSlotStatus.unknown);
    final plans = await r.readMedicationPlans();
    expect(
      plans.any(
        (p) => p.key == SyntheticOpenBandRepository.medicationFixturePlanAKey,
      ),
      isTrue,
    );
  });

  test('future taken and nonfinite dose are refused', () async {
    final r = repo();
    await expectLater(
      r.saveMedicationEntry(
        MedicationEntryDraft(
          key: SyntheticOpenBandRepository.medicationFixturePlanAKey,
          date: '2026-09-15',
          slotMin: 8 * 60,
          answer: MedicationEntryAnswer.taken,
          takenAt: DateTime(2026, 9, 15, 18),
        ),
        now: now,
      ),
      throwsArgumentError,
    );
    await expectLater(
      r.saveMedicationPlan(
        const MedicationPlanDraft(
          create: true,
          name: 'Bad',
          doseValue: double.nan,
        ),
        now: now,
      ),
      throwsArgumentError,
    );
    await expectLater(
      r.readMedicationDay('2026-02-31', now: now),
      throwsArgumentError,
    );
  });

  test('committed write is not retried when reminders fail', () async {
    final r = repo()..failMedicationReminders = true;
    final result = await r.saveMedicationPlan(
      const MedicationPlanDraft(create: true, name: 'Nur gespeichert'),
      now: now,
    );
    expect(result.committed, isTrue);
    expect(result.remindersFailed, isTrue);
    expect(
      (await r.readMedicationPlans()).any((p) => p.name == 'Nur gespeichert'),
      isTrue,
    );
    r.failMedicationReminders = false;
    await r.refreshMedicationReminders();
  });

  test('committed mutation reports saved despite unrelated unreadable data', () async {
    final r = repo()
      ..corruptMedicationHeads = true
      ..failMedicationReminders = true;
    final saved = await r.saveMedicationPlan(
      const MedicationPlanDraft(
        create: true,
        name: 'Trotz',
        schedule: [MedicationScheduleSlot(minuteOfDay: 8 * 60)],
      ),
      now: now,
    );
    expect(saved.committed, isTrue);
    expect(saved.remindersFailed, isTrue);
    expect(saved.plan!.name, 'Trotz');
    final marked = await r.saveMedicationEntry(
      MedicationEntryDraft(
        key: saved.plan!.key,
        date: '2026-09-15',
        slotMin: 8 * 60,
        answer: MedicationEntryAnswer.taken,
        takenAt: DateTime(2026, 9, 15, 8, 2),
      ),
      now: now,
    );
    expect(marked.committed, isTrue);
    expect(marked.remindersFailed, isTrue);
    expect(marked.entry!.status, MedicationSlotStatus.taken);
    await expectLater(r.readMedicationPlans(), throwsFormatException);
    r.corruptMedicationHeads = false;
    r.failMedicationReminders = false;
    expect(
      (await r.readMedicationPlans()).any((p) => p.name == 'Trotz'),
      isTrue,
    );
  });

  test('read failure and corrupt heads are not a false empty list', () async {
    final failing = repo()..failMedicationRead = true;
    await expectLater(failing.readMedicationPlans(), throwsStateError);
    final corrupt = repo()..corruptMedicationHeads = true;
    await expectLater(corrupt.readMedicationPlans(), throwsFormatException);
  });

  test('write failure does not keep a partial plan', () async {
    final r = repo()..failMedicationWrite = true;
    await expectLater(
      r.saveMedicationPlan(
        const MedicationPlanDraft(create: true, name: 'Nein'),
        now: now,
      ),
      throwsStateError,
    );
    r.failMedicationWrite = false;
    expect(
      (await r.readMedicationPlans()).any((p) => p.name == 'Nein'),
      isFalse,
    );
  });

  test('Berlin DST gap and fold stay unavailable; valid 08 is instant', () {
    expect(
      medicationSlotInstant('2026-03-29', 2 * 60 + 30, zone: 'Europe/Berlin'),
      isNull,
    );
    expect(
      medicationSlotInstant('2026-10-25', 2 * 60 + 30, zone: 'Europe/Berlin'),
      isNull,
    );
    final spring8 =
        medicationSlotInstant('2026-03-29', 8 * 60, zone: 'Europe/Berlin');
    final autumn8 =
        medicationSlotInstant('2026-10-25', 8 * 60, zone: 'Europe/Berlin');
    expect(spring8, isNotNull);
    expect(spring8!.hour, 8);
    expect(autumn8, isNotNull);
    expect(autumn8!.hour, 8);
  });

  test('covering uses actual epoch, not the start of the saved minute', () {
    MedicationPlanRevision rev({
      required int id,
      required DateTime at,
      required bool active,
    }) =>
        MedicationPlanRevision(
          id: id,
          medKey: 'k',
          effectiveTs: at.millisecondsSinceEpoch,
          effectiveDate: '2026-09-15',
          effectiveMin: at.hour * 60 + at.minute,
          label: 'X',
          kind: MedicationKind.medication,
          schedule: const [
            MedicationScheduleSlot(minuteOfDay: 8 * 60),
            MedicationScheduleSlot(minuteOfDay: 20 * 60),
          ],
          active: active,
          origin: MedicationPlanOrigin.user,
        );
    final prior = rev(id: 1, at: DateTime(2026, 9, 15, 7), active: true);
    final afterSlot = rev(id: 2, at: DateTime(2026, 9, 15, 8, 0, 30), active: false);
    expect(revisionCoversSlot(afterSlot, '2026-09-15', 8 * 60), isFalse);
    expect(revisionCoversSlot(afterSlot, '2026-09-15', 20 * 60), isTrue);
    expect(
      coveringMedicationRevision(
        revisions: [prior, afterSlot],
        date: '2026-09-15',
        slotMin: 8 * 60,
      )!.id,
      1,
    );
    final atSlot = rev(id: 3, at: DateTime(2026, 9, 15, 8, 0, 0), active: false);
    expect(revisionCoversSlot(atSlot, '2026-09-15', 8 * 60), isTrue);
    final beforeNext = rev(id: 4, at: DateTime(2026, 9, 15, 7, 59, 59, 500), active: false);
    expect(revisionCoversSlot(beforeNext, '2026-09-15', 8 * 60), isTrue);
  });

  test('covering ignores caller zone; recorded civil cutoffs win', () {
    final ten = MedicationPlanRevision(
      id: 1,
      medKey: 'k',
      effectiveTs: DateTime(2026, 9, 15, 10).millisecondsSinceEpoch,
      effectiveDate: '2026-09-15',
      effectiveMin: 10 * 60,
      label: 'X',
      kind: MedicationKind.medication,
      schedule: const [
        MedicationScheduleSlot(minuteOfDay: 8 * 60),
        MedicationScheduleSlot(minuteOfDay: 20 * 60),
      ],
      active: true,
      origin: MedicationPlanOrigin.user,
    );
    for (final zone in [null, 'Europe/Berlin', 'America/New_York']) {
      expect(revisionCoversSlot(ten, '2026-09-15', 8 * 60, zone: zone), isFalse);
      expect(revisionCoversSlot(ten, '2026-09-15', 20 * 60, zone: zone), isTrue);
    }
    final seven = MedicationPlanRevision(
      id: 2,
      medKey: 'k',
      effectiveTs: DateTime(2026, 9, 15, 7).millisecondsSinceEpoch,
      effectiveDate: '2026-09-15',
      effectiveMin: 7 * 60,
      label: 'X',
      kind: MedicationKind.medication,
      schedule: const [MedicationScheduleSlot(minuteOfDay: 8 * 60)],
      active: true,
      origin: MedicationPlanOrigin.user,
    );
    expect(
      revisionCoversSlot(seven, '2026-09-15', 8 * 60, zone: 'America/New_York'),
      isTrue,
    );
  });

  test('DST gap/fold have no slot instant; same-minute cover does not invent one', () {
    expect(
      medicationSlotInstant('2026-03-29', 2 * 60 + 30, zone: 'Europe/Berlin'),
      isNull,
    );
    expect(
      medicationSlotInstant('2026-10-25', 2 * 60 + 30, zone: 'Europe/Berlin'),
      isNull,
    );
    final onMinute = MedicationPlanRevision(
      id: 1,
      medKey: 'k',
      effectiveTs: 1_700_000 * 60_000,
      effectiveDate: '2026-03-29',
      effectiveMin: 2 * 60 + 30,
      label: 'X',
      kind: MedicationKind.medication,
      schedule: const [MedicationScheduleSlot(minuteOfDay: 2 * 60 + 30)],
      active: true,
      origin: MedicationPlanOrigin.user,
    );
    expect(revisionCoversSlot(onMinute, '2026-03-29', 2 * 60 + 30), isTrue);
    final after = MedicationPlanRevision(
      id: 2,
      medKey: 'k',
      effectiveTs: onMinute.effectiveTs + 30 * 1000,
      effectiveDate: '2026-03-29',
      effectiveMin: 2 * 60 + 30,
      label: 'X',
      kind: MedicationKind.medication,
      schedule: const [MedicationScheduleSlot(minuteOfDay: 2 * 60 + 30)],
      active: false,
      origin: MedicationPlanOrigin.user,
    );
    expect(revisionCoversSlot(after, '2026-03-29', 2 * 60 + 30), isFalse);
    final resolved = resolveMedicationDay(
      date: '2026-03-29',
      now: DateTime(2026, 3, 29, 8),
      revisionsByKey: {
        'k': [onMinute],
      },
      doses: const [],
      zone: 'Europe/Berlin',
    );
    expect(resolved.entries, hasLength(1));
    expect(resolved.entries.single.status, MedicationSlotStatus.unavailable);
    expect(resolved.entries.single.scheduledAt, isNull);
  });

  test('non-finite schedule numbers are unreadable, not a crash', () {
    expect(
      parseMedicationScheduleEntry({
        'minute_of_day': double.infinity,
        'days': <int>[],
      }).unreadable,
      isTrue,
    );
    expect(
      parseMedicationScheduleEntry({
        'minute_of_day': 480,
        'days': [double.infinity],
      }).unreadable,
      isTrue,
    );
    expect(parseMedicationInt(double.infinity), isNull);
    expect(parseMedicationInt(double.nan), isNull);
    expect(parseMedicationStoredDose(double.infinity).unreadable, isTrue);
    expect(parseMedicationStoredDose(null).unreadable, isFalse);
    expect(parseMedicationActiveFlag(2), isNull);
    expect(parseMedicationActiveFlag(1), isTrue);
    expect(parseMedicationActiveFlag(0), isFalse);
  });

  test('corrupt schedule json is unreadable, never midnight', () {
    final parsed = parseMedicationScheduleList([
      {'minute_of_day': 480, 'days': []},
      {'oops': true},
    ]);
    expect(parsed.slots.single.minuteOfDay, 480);
    expect(parsed.unreadableCount, 1);
    expect(parseMedicationScheduleEntry({'minute_of_day': 0}).unreadable, isTrue);
  });
}
