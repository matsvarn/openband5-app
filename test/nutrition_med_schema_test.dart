// Schema 35 (nutrition) and 36 (medication), through the REAL ladder.
//
// The point is not that the CREATE ran. It is that a database seeded at v34 —
// what every existing install is — upgrades without throwing and accepts a
// write IMMEDIATELY, not on the next launch. onUpgrade runs inside one
// exclusive transaction, so a single throwing step rolls the whole ladder back
// and leaves the app permanently stuck on the loading screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/med_store.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/openband/medication_data.dart';

/// Enough of the v34 shape for the ladder to have something real to walk.
const _v34Ddl = [
  '''
  CREATE TABLE derived_day (
    date TEXT PRIMARY KEY, payload_json TEXT NOT NULL, version INTEGER NOT NULL,
    last_raw_ts INTEGER NOT NULL, computed_at INTEGER NOT NULL,
    rhr REAL, rmssd REAL, readiness REAL)
''',
  '''
  CREATE TABLE baselines (
    key TEXT PRIMARY KEY, payload_json TEXT NOT NULL, updated_at INTEGER NOT NULL)
''',
  '''
  CREATE TABLE metric_series (
    date TEXT NOT NULL, key TEXT NOT NULL, value REAL, PRIMARY KEY (date, key))
''',
  "CREATE TABLE journal (date TEXT PRIMARY KEY, "
      "tags_json TEXT NOT NULL DEFAULT '[]', "
      "note TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL)",
];

Future<String> _dbPath(String name) async =>
    p.join(await databaseFactory.getDatabasesPath(), name);

void main() {
  const name = 'migrate_from_v34_nutrition_test.db';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(await _dbPath(name));
  });

  test('v34 → 36 adds nutrition and medication, usable immediately', () async {
    final path = await _dbPath(name);
    await databaseFactory.deleteDatabase(path);
    final seeded = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 34,
        onCreate: (db, _) async {
          for (final s in _v34Ddl) {
            await db.execute(s);
          }
        },
      ),
    );
    await seeded.insert('journal', {
      'date': '2026-08-14',
      'tags_json': '["late meal"]',
      'note': 'kept',
      'updated_at': 1,
    });
    await seeded.close();

    await LocalDb.close();
    LocalDb.dbName = name;
    final db = await LocalDb.instance;

    expect(
      (await db.rawQuery('PRAGMA user_version')).first.values.first,
      LocalDb.schemaVersion,
    );
    expect(LocalDb.schemaVersion, greaterThanOrEqualTo(36));

    // Purely additive: what was already stored is untouched.
    final journal = await LocalDb.journalRows();
    expect(journal.single['note'], 'kept');

    // The tables work on this launch, not the next one.
    await NutritionDb.put(
      db,
      const FoodEntry(
        id: 'f1',
        date: '2026-08-14',
        meal: 'dinner',
        label: 'Chicken and rice',
        kcal: 620,
        proteinG: 48,
        confirmed: true,
      ),
    );
    final day = await NutritionDb.entriesForDay(db, '2026-08-14');
    expect(day.single.kcal, 620);
    // Every nutrient column is nullable, and an unwritten one stays NULL
    // rather than defaulting to a zero the user never claimed.
    expect(day.single.fibreG, isNull);

    final created = DateTime(2026, 8, 14, 7);
    await MedDb.commitPlan(
      db,
      const MedicationPlanDraft(
        create: true,
        key: 'custom_d',
        name: 'Vitamin D',
        doseValue: 2000,
        doseUnit: 'IU',
        schedule: [
          MedicationScheduleSlot(
            minuteOfDay: 480,
            weekdays: [1, 2, 3, 4, 5, 6, 7],
          ),
        ],
      ),
      now: created,
    );
    final plans = await MedDb.readPlans(db);
    expect(plans.single.name, 'Vitamin D');
    expect(plans.single.doseValue, 2000);
    expect(plans.single.doseUnit, 'IU');
    expect(plans.single.schedule.single.minuteOfDay, 480);
    final createdAt = plans.single.createdAtMs;
    expect(createdAt, isNotNull);
    expect(plans.single.revisionId, greaterThan(0));

    // An edit is a new revision. The head created_at stamp stays — restamping
    // it is not identity and is not how coverage is bounded.
    await MedDb.commitPlan(
      db,
      const MedicationPlanDraft(
        create: false,
        key: 'custom_d',
        name: 'Vitamin D3',
        doseValue: 4000,
        doseUnit: 'IU',
        schedule: [
          MedicationScheduleSlot(
            minuteOfDay: 480,
            weekdays: [1, 2, 3, 4, 5, 6, 7],
          ),
        ],
      ),
      now: DateTime(2026, 8, 14, 18),
    );
    final edited = await MedDb.readPlans(db);
    expect(edited.single.name, 'Vitamin D3');
    expect(edited.single.doseValue, 4000);
    expect(edited.single.createdAtMs, createdAt);

    await MedDb.markDose(
      db,
      const MedicationEntryDraft(
        key: 'custom_d',
        date: '2026-08-14',
        slotMin: 480,
        answer: MedicationEntryAnswer.taken,
      ),
      now: DateTime(2026, 8, 14, 8, 5),
    );
    final takenDay = await MedDb.readDay(
      db,
      '2026-08-14',
      now: DateTime(2026, 8, 14, 18),
    );
    expect(takenDay.entries.single.status, MedicationSlotStatus.taken);
    expect(takenDay.entries.single.takenAt, isNotNull);
    // Frozen at first write, not the renamed head.
    expect(takenDay.entries.single.snapshotLabel, 'Vitamin D');
    expect(takenDay.entries.single.currentName, 'Vitamin D3');

    // A missing answer is unknown, never a NULL taken_ts row pretending to be
    // skipped. The day before the plan existed has no generated slot.
    final earlier = await MedDb.readDay(
      db,
      '2026-08-13',
      now: DateTime(2026, 8, 14, 12),
    );
    expect(earlier.entries, isEmpty);

    final health = await LocalDb.schemaHealth();
    expect(health['ok'], isTrue, reason: '$health');
  });
}
