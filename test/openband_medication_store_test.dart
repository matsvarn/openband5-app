import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/med_store.dart';
import 'package:openstrap_edge/openband/medication_data.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _path(String name) async =>
    p.join(await databaseFactory.getDatabasesPath(), name);

Future<void> _use(String name) async {
  await LocalDb.close();
  LocalDb.dbName = name;
  await databaseFactory.deleteDatabase(await _path(name));
}

const _v64MedDdl = [
  '''
  CREATE TABLE med_def (
    key TEXT PRIMARY KEY,
    label TEXT NOT NULL,
    dose_value REAL,
    dose_unit TEXT NOT NULL DEFAULT '',
    kind TEXT NOT NULL DEFAULT 'medication',
    schedule_json TEXT NOT NULL DEFAULT '[]',
    active INTEGER NOT NULL DEFAULT 1,
    note TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL
  )
''',
  '''
  CREATE TABLE med_dose (
    med_key TEXT NOT NULL,
    date TEXT NOT NULL,
    slot_min INTEGER NOT NULL,
    taken_ts INTEGER,
    skipped INTEGER NOT NULL DEFAULT 0,
    dose_value REAL,
    note TEXT NOT NULL DEFAULT '',
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (med_key, date, slot_min)
  )
''',
];

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async => LocalDb.close());

  test('v64 → 65 snapshots heads at migration now, not created_at', () async {
    const name = 'med_upgrade_v64.db';
    final path = await _path(name);
    await databaseFactory.deleteDatabase(path);
    final createdAt = DateTime(2026, 8, 1, 8).millisecondsSinceEpoch;
    final seeded = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 64,
        onCreate: (db, _) async {
          for (final s in _v64MedDdl) {
            await db.execute(s);
          }
        },
      ),
    );
    await seeded.insert('med_def', {
      'key': 'custom_legacy',
      'label': 'Legacy',
      'dose_value': 1,
      'dose_unit': 'mg',
      'kind': 'medication',
      'schedule_json':
          '[{"minute_of_day":480,"days":[1,2,3,4,5,6,7]}]',
      'active': 1,
      'note': '',
      'created_at': createdAt,
    });
    await seeded.insert('med_dose', {
      'med_key': 'custom_legacy',
      'date': '2026-08-20',
      'slot_min': 480,
      'taken_ts': 1,
      'skipped': 0,
      'dose_value': 1,
      'note': '',
      'updated_at': createdAt,
    });
    await seeded.close();

    await LocalDb.close();
    LocalDb.dbName = name;
    final db = await LocalDb.instance;
    expect(
      (await db.rawQuery('PRAGMA user_version')).first.values.first,
      68,
    );
    final revs = await MedDb.revisionsForKey(db, 'custom_legacy');
    expect(revs, hasLength(1));
    expect(revs.single.origin, MedicationPlanOrigin.migrated);
    expect(revs.single.effectiveTs, greaterThan(createdAt));
    expect(revs.single.label, 'Legacy');

    final before = await MedDb.readDay(
      db,
      '2026-08-20',
      now: DateTime(2026, 9, 15, 12),
    );
    expect(before.entries, hasLength(1));
    expect(before.entries.single.orphan, isTrue);
    expect(before.entries.single.snapshotLabel, isNull);
    expect(before.entries.single.snapshotDoseValue, 1);
    expect(before.entries.single.snapshotDoseUnit, isNull);

    await LocalDb.close();
    final reopened = await LocalDb.instance;
    expect(await MedDb.revisionsForKey(reopened, 'custom_legacy'), hasLength(1));
    final health = await LocalDb.schemaHealth();
    expect(health['ok'], isTrue, reason: '$health');
  });

  test('v63 → 65 ladder creates revision table without duplicates', () async {
    const name = 'med_upgrade_v63.db';
    final path = await _path(name);
    await databaseFactory.deleteDatabase(path);
    final seeded = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 63,
        onCreate: (db, _) async {
          for (final s in _v64MedDdl) {
            await db.execute(s);
          }
        },
      ),
    );
    await seeded.insert('med_def', {
      'key': 'custom_v63',
      'label': 'From63',
      'dose_value': null,
      'dose_unit': '',
      'kind': 'medication',
      'schedule_json': '[{"minute_of_day":480,"days":[]}]',
      'active': 1,
      'note': '',
      'created_at': 1,
    });
    await seeded.close();
    await LocalDb.close();
    LocalDb.dbName = name;
    final db = await LocalDb.instance;
    expect(
      (await db.rawQuery('PRAGMA user_version')).first.values.first,
      LocalDb.schemaVersion,
    );
    expect(await MedDb.revisionsForKey(db, 'custom_v63'), hasLength(1));
    await upgradeMedTables(db, now: DateTime(2026, 9, 21, 8));
    expect(await MedDb.revisionsForKey(db, 'custom_v63'), hasLength(1));
  });

  test('create identity, same-minute edits, covering uses later id', () async {
    await _use('med_same_minute.db');
    final db = await LocalDb.instance;
    final now = DateTime(2026, 9, 15, 10);
    final created = await MedDb.commitPlan(
      db,
      const MedicationPlanDraft(
        create: true,
        name: 'Zwei',
        schedule: [
          MedicationScheduleSlot(minuteOfDay: 8 * 60),
          MedicationScheduleSlot(minuteOfDay: 20 * 60),
        ],
      ),
      now: DateTime(2026, 9, 15, 7),
    );
    await MedDb.commitPlan(
      db,
      MedicationPlanDraft(
        create: false,
        key: created.key,
        name: 'Zwei',
        schedule: const [MedicationScheduleSlot(minuteOfDay: 8 * 60)],
      ),
      now: now,
    );
    await MedDb.commitPlan(
      db,
      MedicationPlanDraft(
        create: false,
        key: created.key,
        name: 'Zwei',
        schedule: const [
          MedicationScheduleSlot(minuteOfDay: 8 * 60),
          MedicationScheduleSlot(minuteOfDay: 20 * 60),
        ],
      ),
      now: now,
    );
    final revs = await MedDb.revisionsForKey(db, created.key);
    expect(revs.length, 3);
    expect(revs[1].effectiveTs, now.millisecondsSinceEpoch);
    expect(revs[2].effectiveTs, now.millisecondsSinceEpoch);
    expect(revs[1].id, lessThan(revs[2].id));
    final day = await MedDb.readDay(
      db,
      '2026-09-15',
      now: DateTime(2026, 9, 15, 10, 1),
    );
    expect(
      day.entries.where((e) => e.key == created.key).map((e) => e.slotMin),
      [8 * 60, 20 * 60],
    );
  });

  test('legacy dose update does not backfill null snapshot fields', () async {
    await _use('med_nofilback.db');
    final db = await LocalDb.instance;
    await db.insert('med_def', {
      'key': 'legacy',
      'label': 'NowNamed',
      'dose_value': 9,
      'dose_unit': 'mg',
      'kind': 'medication',
      'schedule_json': '[{"minute_of_day":480,"days":[]}]',
      'active': 1,
      'note': '',
      'created_at': 1,
    });
    await migrateMedPlanRevisions(db, now: DateTime(2026, 9, 15, 12));
    await db.insert('med_dose', {
      'med_key': 'legacy',
      'date': '2026-09-10',
      'slot_min': 480,
      'taken_ts': 100,
      'skipped': 0,
      'dose_value': 2,
      'note': '',
      'updated_at': 1,
    });
    await MedDb.markDose(
      db,
      const MedicationEntryDraft(
        key: 'legacy',
        date: '2026-09-10',
        slotMin: 480,
        answer: MedicationEntryAnswer.skipped,
      ),
      now: DateTime(2026, 9, 15, 12),
    );
    final row = (await db.query(
      'med_dose',
      where: 'med_key = ?',
      whereArgs: ['legacy'],
    ))
        .single;
    expect(row['label'], isNull);
    expect(row['dose_unit'], isNull);
    expect(row['dose_value'], 2);
    expect(row['skipped'], 1);
    expect(row['taken_ts'], isNull);
  });

  test('new dose freezes covering metadata; clear removes the row', () async {
    await _use('med_freeze.db');
    final db = await LocalDb.instance;
    final plan = await MedDb.commitPlan(
      db,
      const MedicationPlanDraft(
        create: true,
        name: 'Freeze',
        doseValue: 1,
        doseUnit: 'Tablette',
        schedule: [MedicationScheduleSlot(minuteOfDay: 8 * 60)],
      ),
      now: DateTime(2026, 9, 15, 7),
    );
    await MedDb.markDose(
      db,
      MedicationEntryDraft(
        key: plan.key,
        date: '2026-09-15',
        slotMin: 8 * 60,
        answer: MedicationEntryAnswer.taken,
        takenAt: DateTime(2026, 9, 15, 8, 2),
      ),
      now: DateTime(2026, 9, 15, 8, 2),
    );
    final stored = (await db.query('med_dose')).single;
    expect(stored['label'], 'Freeze');
    expect(stored['dose_unit'], 'Tablette');
    expect(stored['kind'], 'medication');
    expect(stored['taken_utc_offset_min'], isNotNull);
    await MedDb.markDose(
      db,
      MedicationEntryDraft(
        key: plan.key,
        date: '2026-09-15',
        slotMin: 8 * 60,
        answer: MedicationEntryAnswer.clear,
      ),
      now: DateTime(2026, 9, 15, 9),
    );
    expect(await db.query('med_dose'), isEmpty);
    final day = await MedDb.readDay(
      db,
      '2026-09-15',
      now: DateTime(2026, 9, 15, 9, 41),
    );
    expect(day.entries.single.status, MedicationSlotStatus.unknown);
  });

  test('corrupt head schedule throws rather than returning empty plans', () async {
    await _use('med_corrupt_head.db');
    final db = await LocalDb.instance;
    await db.insert('med_def', {
      'key': 'bad',
      'label': 'Bad',
      'dose_value': null,
      'dose_unit': '',
      'kind': 'medication',
      'schedule_json': 'not-json',
      'active': 1,
      'note': '',
      'created_at': 1,
    });
    await expectLater(MedDb.readPlans(db), throwsFormatException);
  });

  test('reminder instants refuse unreadable store and allow known empty', () async {
    await _use('med_remind.db');
    final db = await LocalDb.instance;
    final empty = await MedDb.upcomingReminderInstants(
      db,
      now: DateTime(2026, 9, 15, 9, 41),
    );
    expect(empty, isEmpty);
    await db.insert('med_def', {
      'key': 'r',
      'label': 'R',
      'dose_value': null,
      'dose_unit': '',
      'kind': 'medication',
      'schedule_json': '[{"minute_of_day":1200,"days":[]},{"bad":1}]',
      'active': 1,
      'note': '',
      'created_at': DateTime(2026, 9, 15, 7).millisecondsSinceEpoch,
    });
    await migrateMedPlanRevisions(db, now: DateTime(2026, 9, 15, 7));
    await expectLater(
      MedDb.upcomingReminderInstants(
        db,
        now: DateTime(2026, 9, 15, 9, 41),
      ),
      throwsFormatException,
    );
  });

  test('Berlin DST generated row is unavailable, not shifted', () async {
    await _use('med_dst.db');
    final db = await LocalDb.instance;
    final plan = await MedDb.commitPlan(
      db,
      const MedicationPlanDraft(
        create: true,
        name: 'DST',
        schedule: [MedicationScheduleSlot(minuteOfDay: 2 * 60 + 30)],
      ),
      now: DateTime(2026, 3, 28, 12),
    );
    final gap = await MedDb.readDay(
      db,
      '2026-03-29',
      now: DateTime(2026, 3, 29, 8),
      zone: 'Europe/Berlin',
    );
    final row = gap.entries.singleWhere((e) => e.key == plan.key);
    expect(row.status, MedicationSlotStatus.unavailable);
    expect(row.scheduledAt, isNull);
    final fold = await MedDb.readDay(
      db,
      '2026-10-25',
      now: DateTime(2026, 10, 25, 8),
      zone: 'Europe/Berlin',
    );
    expect(
      fold.entries.singleWhere((e) => e.key == plan.key).status,
      MedicationSlotStatus.unavailable,
    );
  });


  test('committed write returns without reading unrelated corrupt heads', () async {
    await _use('med_postcommit_corrupt.db');
    final db = await LocalDb.instance;
    await db.insert('med_def', {
      'key': 'bad-head',
      'label': 'Bad',
      'dose_value': null,
      'dose_unit': '',
      'kind': 'medication',
      'schedule_json': 'not-json',
      'active': 1,
      'note': '',
      'created_at': 1,
    });
    await expectLater(MedDb.readPlans(db), throwsFormatException);
    final plan = await MedDb.commitPlan(
      db,
      const MedicationPlanDraft(
        create: true,
        name: 'Trotz',
        schedule: [MedicationScheduleSlot(minuteOfDay: 8 * 60)],
      ),
      now: DateTime(2026, 9, 15, 7),
    );
    expect(plan.name, 'Trotz');
    expect(plan.revisionId, greaterThan(0));
    final taken = await MedDb.markDose(
      db,
      MedicationEntryDraft(
        key: plan.key,
        date: '2026-09-15',
        slotMin: 8 * 60,
        answer: MedicationEntryAnswer.taken,
        takenAt: DateTime(2026, 9, 15, 8, 1),
      ),
      now: DateTime(2026, 9, 15, 9, 41),
    );
    expect(taken, isNotNull);
    expect(taken!.status, MedicationSlotStatus.taken);
    final cleared = await MedDb.markDose(
      db,
      MedicationEntryDraft(
        key: plan.key,
        date: '2026-09-15',
        slotMin: 8 * 60,
        answer: MedicationEntryAnswer.clear,
      ),
      now: DateTime(2026, 9, 15, 9, 42),
    );
    expect(cleared!.status, MedicationSlotStatus.unknown);
    await expectLater(MedDb.readPlans(db), throwsFormatException);
  });

  test('legacy taken offset stays unknown when the instant is unchanged', () async {
    await _use('med_offset_preserve.db');
    final db = await LocalDb.instance;
    final plan = await MedDb.commitPlan(
      db,
      const MedicationPlanDraft(
        create: true,
        name: 'Offset',
        schedule: [MedicationScheduleSlot(minuteOfDay: 8 * 60)],
      ),
      now: DateTime(2026, 9, 15, 7),
    );
    await db.insert('med_dose', {
      'med_key': plan.key,
      'date': '2026-09-15',
      'slot_min': 480,
      'taken_ts': 100,
      'skipped': 0,
      'dose_value': 1,
      'note': '',
      'updated_at': 1,
      'label': 'Offset',
      'dose_unit': 'mg',
      'kind': 'medication',
    });
    final sameInstant = DateTime.fromMillisecondsSinceEpoch(100 * 1000);
    await MedDb.markDose(
      db,
      MedicationEntryDraft(
        key: plan.key,
        date: '2026-09-15',
        slotMin: 480,
        answer: MedicationEntryAnswer.taken,
        takenAt: sameInstant,
      ),
      now: DateTime(2026, 9, 15, 12),
    );
    final kept = (await db.query('med_dose')).single;
    expect(kept['taken_ts'], 100);
    expect(kept['taken_utc_offset_min'], isNull);
    await MedDb.markDose(
      db,
      MedicationEntryDraft(
        key: plan.key,
        date: '2026-09-15',
        slotMin: 480,
        answer: MedicationEntryAnswer.taken,
        takenAt: DateTime(2026, 9, 15, 8, 5),
      ),
      now: DateTime(2026, 9, 15, 12),
    );
    final changed = (await db.query('med_dose')).single;
    expect(changed['taken_ts'], isNot(100));
    expect(changed['taken_utc_offset_min'], isNotNull);
  });

  test('end/restart refuse a corrupt head instead of normalizing it', () async {
    await _use('med_end_corrupt.db');
    final db = await LocalDb.instance;
    await db.insert('med_def', {
      'key': 'broken',
      'label': 'Broken',
      'dose_value': 1,
      'dose_unit': 'mg',
      'kind': 'not-a-kind',
      'schedule_json': '[{"minute_of_day":480,"days":[]}]',
      'active': 1,
      'note': '',
      'created_at': 1,
    });
    await migrateMedPlanRevisions(db, now: DateTime(2026, 9, 15, 8));
    await expectLater(
      MedDb.setActive(
        db,
        'broken',
        active: false,
        now: DateTime(2026, 9, 15, 10),
      ),
      throwsFormatException,
    );
    final head = (await db.query(
      'med_def',
      where: 'key = ?',
      whereArgs: ['broken'],
    ))
        .single;
    expect(head['kind'], 'not-a-kind');
    expect(head['active'], 1);
    expect(
      await db.query(
        'med_plan_revision',
        where: 'med_key = ?',
        whereArgs: ['broken'],
      ),
      hasLength(1),
    );
    await expectLater(MedDb.revisionsForKey(db, 'broken'), throwsFormatException);
  });

  test('end 30s after 08:00 retains that slot; at or before 08:00 covers it', () async {
    await _use('med_cover_seconds.db');
    final db = await LocalDb.instance;
    final retained = await MedDb.commitPlan(
      db,
      const MedicationPlanDraft(
        create: true,
        name: 'Nachher',
        schedule: [
          MedicationScheduleSlot(minuteOfDay: 8 * 60),
          MedicationScheduleSlot(minuteOfDay: 20 * 60),
        ],
      ),
      now: DateTime(2026, 9, 15, 7),
    );
    await MedDb.setActive(
      db,
      retained.key,
      active: false,
      now: DateTime(2026, 9, 15, 8, 0, 30),
    );
    final after = await MedDb.readDay(
      db,
      '2026-09-15',
      now: DateTime(2026, 9, 15, 12),
    );
    expect(
      after.entries.where((e) => e.key == retained.key).map((e) => e.slotMin),
      [8 * 60],
    );

    final covers = await MedDb.commitPlan(
      db,
      const MedicationPlanDraft(
        create: true,
        name: 'Genau',
        schedule: [
          MedicationScheduleSlot(minuteOfDay: 8 * 60),
          MedicationScheduleSlot(minuteOfDay: 20 * 60),
        ],
      ),
      now: DateTime(2026, 9, 15, 7),
    );
    await MedDb.setActive(
      db,
      covers.key,
      active: false,
      now: DateTime(2026, 9, 15, 8, 0, 0),
    );
    final atSlot = await MedDb.readDay(
      db,
      '2026-09-15',
      now: DateTime(2026, 9, 15, 12),
    );
    expect(atSlot.entries.where((e) => e.key == covers.key), isEmpty);

    final before = await MedDb.commitPlan(
      db,
      const MedicationPlanDraft(
        create: true,
        name: 'Davor',
        schedule: [
          MedicationScheduleSlot(minuteOfDay: 8 * 60),
          MedicationScheduleSlot(minuteOfDay: 20 * 60),
        ],
      ),
      now: DateTime(2026, 9, 15, 7),
    );
    await MedDb.setActive(
      db,
      before.key,
      active: false,
      now: DateTime(2026, 9, 15, 7, 59, 59, 500),
    );
    final beforeDay = await MedDb.readDay(
      db,
      '2026-09-15',
      now: DateTime(2026, 9, 15, 12),
    );
    expect(beforeDay.entries.where((e) => e.key == before.key), isEmpty);
  });

  test('same-key corrupt revision rolls back markDose; no post-commit throw', () async {
    await _use('med_mark_samekey_corrupt.db');
    final db = await LocalDb.instance;
    await db.insert('med_def', {
      'key': 'broken',
      'label': 'Broken',
      'dose_value': 1,
      'dose_unit': 'mg',
      'kind': 'not-a-kind',
      'schedule_json': '[{"minute_of_day":480,"days":[]}]',
      'active': 1,
      'note': '',
      'created_at': 1,
    });
    await migrateMedPlanRevisions(db, now: DateTime(2026, 9, 15, 8));
    await expectLater(
      MedDb.markDose(
        db,
        const MedicationEntryDraft(
          key: 'broken',
          date: '2026-09-15',
          slotMin: 480,
          answer: MedicationEntryAnswer.taken,
        ),
        now: DateTime(2026, 9, 15, 9, 41),
      ),
      throwsFormatException,
    );
    expect(await db.query('med_dose'), isEmpty);
    await expectLater(
      MedDb.markDose(
        db,
        const MedicationEntryDraft(
          key: 'broken',
          date: '2026-09-15',
          slotMin: 480,
          answer: MedicationEntryAnswer.clear,
        ),
        now: DateTime(2026, 9, 15, 9, 42),
      ),
      throwsFormatException,
    );
  });

  test('corrupt kind/dose/active on a head is unreadable, not a valid plan', () async {
    await _use('med_corrupt_fields.db');
    final db = await LocalDb.instance;
    await db.insert('med_def', {
      'key': 'inf-dose',
      'label': 'Inf',
      'dose_value': double.infinity,
      'dose_unit': 'mg',
      'kind': 'medication',
      'schedule_json': '[{"minute_of_day":480,"days":[]}]',
      'active': 1,
      'note': '',
      'created_at': 1,
    });
    await expectLater(MedDb.readPlans(db), throwsFormatException);
    await db.delete('med_def');
    await db.insert('med_def', {
      'key': 'bad-active',
      'label': 'Flag',
      'dose_value': 1,
      'dose_unit': 'mg',
      'kind': 'medication',
      'schedule_json': '[{"minute_of_day":480,"days":[]}]',
      'active': 2,
      'note': '',
      'created_at': 1,
    });
    await expectLater(MedDb.readPlans(db), throwsFormatException);
  });

  test('day view counts a corrupt revision instead of generating from it', () async {
    await _use('med_day_corrupt_rev.db');
    final db = await LocalDb.instance;
    await db.insert('med_def', {
      'key': 'broken',
      'label': 'Broken',
      'dose_value': 1,
      'dose_unit': 'mg',
      'kind': 'not-a-kind',
      'schedule_json': '[{"minute_of_day":480,"days":[]}]',
      'active': 1,
      'note': '',
      'created_at': 1,
    });
    await migrateMedPlanRevisions(db, now: DateTime(2026, 9, 15, 7));
    await db.insert('med_dose', {
      'med_key': 'broken',
      'date': '2026-09-15',
      'slot_min': 480,
      'taken_ts': 1,
      'skipped': 0,
      'dose_value': 1,
      'note': '',
      'updated_at': 1,
      'label': 'Broken',
      'dose_unit': 'mg',
      'kind': 'medication',
    });
    final day = await MedDb.readDay(
      db,
      '2026-09-15',
      now: DateTime(2026, 9, 15, 12),
    );
    expect(day.unreadableCount, 1);
    expect(day.entries, hasLength(1));
    expect(day.entries.single.orphan, isTrue);
    expect(day.entries.single.status, MedicationSlotStatus.taken);
  });

  test('covering cutoffs stay on recorded civil time after a zone change', () async {
    await _use('med_cover_travel.db');
    final db = await LocalDb.instance;
    final plan = await MedDb.commitPlan(
      db,
      const MedicationPlanDraft(
        create: true,
        name: 'Reise',
        schedule: [
          MedicationScheduleSlot(minuteOfDay: 8 * 60),
          MedicationScheduleSlot(minuteOfDay: 20 * 60),
        ],
      ),
      now: DateTime(2026, 9, 15, 10),
    );
    for (final zone in ['Europe/Berlin', 'America/New_York']) {
      final day = await MedDb.readDay(
        db,
        '2026-09-15',
        now: DateTime(2026, 9, 15, 12),
        zone: zone,
      );
      expect(
        day.entries.where((e) => e.key == plan.key).map((e) => e.slotMin),
        [20 * 60],
        reason: zone,
      );
    }
  });

  test('migration keeps corrupt active=2 and Inf dose; does not arm them', () async {
    await _use('med_migrate_corrupt.db');
    final db = await LocalDb.instance;
    await db.insert('med_def', {
      'key': 'flag-two',
      'label': 'Flag',
      'dose_value': 1,
      'dose_unit': 'mg',
      'kind': 'medication',
      'schedule_json': '[{"minute_of_day":480,"days":[]}]',
      'active': 2,
      'note': '',
      'created_at': 1,
    });
    await db.insert('med_def', {
      'key': 'inf-dose',
      'label': 'Inf',
      'dose_value': double.infinity,
      'dose_unit': 'mg',
      'kind': 'medication',
      'schedule_json': '[{"minute_of_day":1200,"days":[]}]',
      'active': 1,
      'note': '',
      'created_at': 1,
    });
    await migrateMedPlanRevisions(db, now: DateTime(2026, 9, 15, 8));
    final flagRev = (await db.query(
      'med_plan_revision',
      where: 'med_key = ?',
      whereArgs: ['flag-two'],
    ))
        .single;
    expect(flagRev['active'], 2);
    expect(flagRev['origin'], 'migrated');
    final infRev = (await db.query(
      'med_plan_revision',
      where: 'med_key = ?',
      whereArgs: ['inf-dose'],
    ))
        .single;
    expect(infRev['dose_value'], isNotNull);
    expect(parseMedicationStoredDose(infRev['dose_value']).unreadable, isTrue);
    await expectLater(MedDb.readPlans(db), throwsFormatException);
    await expectLater(
      MedDb.upcomingReminderInstants(
        db,
        now: DateTime(2026, 9, 15, 9, 41),
      ),
      throwsFormatException,
    );
    final day = await MedDb.readDay(
      db,
      '2026-09-15',
      now: DateTime(2026, 9, 15, 12),
    );
    expect(day.unreadableCount, greaterThan(0));
    expect(
      day.entries.where((e) => e.key == 'flag-two' || e.key == 'inf-dose'),
      isEmpty,
    );
    await migrateMedPlanRevisions(db, now: DateTime(2026, 9, 16, 8));
    expect(await db.query('med_plan_revision'), hasLength(2));
  });

  test('editor read refuses a partial schedule that day view still counts', () async {
    await _use('med_partial_editor.db');
    final db = await LocalDb.instance;
    await db.insert('med_def', {
      'key': 'partial',
      'label': 'Partial',
      'dose_value': 1,
      'dose_unit': 'mg',
      'kind': 'medication',
      'schedule_json':
          '[{"minute_of_day":480,"days":[]},{"oops":true}]',
      'active': 1,
      'note': '',
      'created_at': DateTime(2026, 9, 15, 7).millisecondsSinceEpoch,
    });
    await migrateMedPlanRevisions(db, now: DateTime(2026, 9, 15, 7));
    await expectLater(MedDb.readPlans(db), throwsFormatException);
    await expectLater(MedDb.readPlan(db, 'partial'), throwsFormatException);
    await expectLater(
      MedDb.setActive(
        db,
        'partial',
        active: false,
        now: DateTime(2026, 9, 15, 10),
      ),
      throwsFormatException,
    );
    final day = await MedDb.readDay(
      db,
      '2026-09-15',
      now: DateTime(2026, 9, 15, 9, 41),
    );
    expect(day.unreadableCount, greaterThan(0));
    expect(day.entries.where((e) => e.key == 'partial'), isNotEmpty);
    expect(
      day.entries.singleWhere((e) => e.key == 'partial').slotMin,
      480,
    );
    await expectLater(
      MedDb.upcomingReminderInstants(
        db,
        now: DateTime(2026, 9, 15, 9, 41),
      ),
      throwsFormatException,
    );
  });

  test('failed migration snapshot is unreadable, not known-empty', () async {
    await _use('med_snapshot_fail.db');
    final db = await LocalDb.instance;
    await db.execute(
      "INSERT INTO med_def (key, label, dose_value, dose_unit, kind, "
      "schedule_json, active, note, created_at) VALUES ("
      "'hole', 'Hole', 1, '', 'medication', "
      "'[{\"minute_of_day\":480,\"days\":[]}]', 1, X'00FF', 1)",
    );
    await migrateMedPlanRevisions(db, now: DateTime(2026, 9, 15, 8));
    expect(
      await db.query(
        'med_plan_revision',
        where: 'med_key = ?',
        whereArgs: ['hole'],
      ),
      isEmpty,
    );
    final day = await MedDb.readDay(
      db,
      '2026-09-15',
      now: DateTime(2026, 9, 15, 12),
    );
    expect(day.unreadableCount, 1);
    expect(day.entries, isEmpty);
    await expectLater(
      MedDb.upcomingReminderInstants(
        db,
        now: DateTime(2026, 9, 15, 9, 41),
      ),
      throwsFormatException,
    );
  });

  test('head with no revision is unreadable at day and reminder reads', () async {
    await _use('med_missing_rev.db');
    final db = await LocalDb.instance;
    await db.insert('med_def', {
      'key': 'orphan-head',
      'label': 'Orphan',
      'dose_value': 1,
      'dose_unit': 'mg',
      'kind': 'medication',
      'schedule_json': '[{"minute_of_day":480,"days":[]}]',
      'active': 1,
      'note': '',
      'created_at': 1,
    });
    expect(
      await db.query(
        'med_plan_revision',
        where: 'med_key = ?',
        whereArgs: ['orphan-head'],
      ),
      isEmpty,
    );
    final day = await MedDb.readDay(
      db,
      '2026-09-15',
      now: DateTime(2026, 9, 15, 12),
    );
    expect(day.unreadableCount, 1);
    expect(
      day.entries.where((e) => e.key == 'orphan-head'),
      isEmpty,
    );
    final hist = await MedDb.readHistory(
      db,
      '2026-09-15',
      '2026-09-16',
      now: DateTime(2026, 9, 15, 12),
    );
    expect(hist.unreadableCount, 1);
    await expectLater(
      MedDb.upcomingReminderInstants(
        db,
        now: DateTime(2026, 9, 15, 9, 41),
      ),
      throwsFormatException,
    );
  });

  test('backup merge list includes revision history', () async {
    await _use('med_merge_src.db');
    expect(LocalDb.schemaVersion, 68);
    final db = await LocalDb.instance;
    await MedDb.commitPlan(
      db,
      const MedicationPlanDraft(
        create: true,
        key: 'keep-me',
        name: 'Keep',
        schedule: [MedicationScheduleSlot(minuteOfDay: 480)],
      ),
      now: DateTime(2026, 9, 15, 8),
    );
    final names = await LocalDb.tableNames();
    expect(names, contains('med_plan_revision'));
    final health = await LocalDb.schemaHealth();
    expect(health['ok'], isTrue, reason: '$health');
  });
}
