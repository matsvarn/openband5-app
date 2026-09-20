import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _dbPath(String name) async =>
    p.join(await databaseFactory.getDatabasesPath(), name);

CustomExerciseDraft _curlDraft({
  String? id,
  String label = 'Kurzhantel-Curl',
}) => CustomExerciseDraft(
  id: id,
  label: label,
  mode: ExerciseCaptureMode.repetitions,
  equipment: ExerciseEquipmentCategory.dumbbell,
  loadBasis: ExerciseLoadBasis.perDevice,
  deviceCount: 2,
  repetitionBasis: ExerciseRepetitionBasis.perSide,
  primaryMuscles: const ['biceps'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final created = <String>[];

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await LocalDb.close();
    for (final n in created) {
      await databaseFactory.deleteDatabase(await _dbPath(n));
    }
  });

  Future<LocalOpenBandRepository> sqliteRepo(String name) async {
    created.add(name);
    await LocalDb.close();
    LocalDb.dbName = name;
    await databaseFactory.deleteDatabase(await _dbPath(name));
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    return LocalOpenBandRepository(app);
  }

  test('sqlite create, update, reopen keeps identity and created_at', () async {
    final repo = await sqliteRepo('custom_ex_create.db');
    final created = await repo.createCustomExercise(_curlDraft());
    expect(created.saved, isTrue);
    final first = created.current!;
    expect(first.id, isNot(equals('Kurzhantel-Curl')));
    expect(first.id, isNot(equals('bench_press')));
    expect(first.label, 'Kurzhantel-Curl');
    expect(first.source, ExerciseDefinitionSource.stored);
    expect(first.version, 1);
    expect(first.mode, ExerciseCaptureMode.repetitions);
    expect(first.equipment, ExerciseEquipmentCategory.dumbbell);
    expect(first.loadBasis, ExerciseLoadBasis.perDevice);
    expect(first.deviceCount, 2);
    expect(first.repetitionBasis, ExerciseRepetitionBasis.perSide);
    expect(first.primaryMuscles, ['biceps']);
    expect(first.selectable, isTrue);
    final createdAt = first.retained['created_at'];

    final renamed = await repo.updateCustomExercise(
      expected: first.snapshot(),
      draft: _curlDraft(label: 'Curl neutral'),
    );
    expect(renamed.saved, isTrue);
    expect(renamed.current!.id, first.id);
    expect(renamed.current!.label, 'Curl neutral');
    expect(renamed.current!.version, 2);
    expect(renamed.current!.retained['created_at'], createdAt);

    await LocalDb.close();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    LocalDb.dbName = 'custom_ex_create.db';
    final reopened = LocalOpenBandRepository(app);
    final cat = await reopened.readExerciseCatalogue();
    expect(cat.byId(first.id)!.label, 'Curl neutral');
    expect(cat.byId(first.id)!.version, 2);
    expect(cat.byId(first.id)!.retained['created_at'], createdAt);
    expect(cat.byId('bench_press')!.source, ExerciseDefinitionSource.preset);
  });

  test('duplicate labels keep distinct ids; preset ids cannot be overwritten', () async {
    final repo = await sqliteRepo('custom_ex_ids.db');
    final a = (await repo.createCustomExercise(_curlDraft())).current!;
    final b = (await repo.createCustomExercise(_curlDraft())).current!;
    expect(a.label, b.label);
    expect(a.id, isNot(b.id));

    await expectLater(
      repo.createCustomExercise(_curlDraft(id: 'bench_press')),
      throwsArgumentError,
    );
    expect(
      (await repo.readExerciseCatalogue()).byId('bench_press')!.source,
      ExerciseDefinitionSource.preset,
    );

    final replay = await repo.createCustomExercise(_curlDraft(id: a.id));
    expect(replay.saved, isTrue);
    expect(replay.current!.id, a.id);
    expect(replay.current!.version, 1);
    expect(replay.current!.retained['created_at'], a.retained['created_at']);

    final collide = await repo.createCustomExercise(
      _curlDraft(id: a.id, label: 'Anders'),
    );
    expect(collide.conflict, isTrue);
    expect(collide.current!.id, a.id);
    expect(collide.current!.label, a.label);
    expect(collide.current!.version, 1);
    expect(collide.current!.retained['created_at'], a.retained['created_at']);
  });

  test('version/snapshot conflict does not write; imported rows are not custom', () async {
    final repo = await sqliteRepo('custom_ex_cas.db');
    final first = (await repo.createCustomExercise(_curlDraft())).current!;
    final stale = first.snapshot();
    final ok = await repo.updateCustomExercise(
      expected: first.snapshot(),
      draft: _curlDraft(label: 'v2'),
    );
    expect(ok.saved, isTrue);
    final clash = await repo.updateCustomExercise(
      expected: stale,
      draft: _curlDraft(label: 'stale'),
    );
    expect(clash.conflict, isTrue);
    expect(clash.current!.label, 'v2');
    expect(clash.current!.version, 2);

    final db = await LocalDb.instance;
    await db.insert('exercise_def', {
      'key': 'row',
      'label': 'Rudern',
      'muscles_json': '{}',
      'equipment': 'kettlebell',
      'unilateral': 0,
      'custom': 1,
      'created_at': 1770000000,
      'source': 'imported',
      'version': 1,
      'definition_json': jsonEncode({
        'mode': 'repetitions',
        'loadBasis': 'band',
        'copiedFrom': 'import-x',
      }),
    });
    final imported = (await repo.readExerciseCatalogue()).byId('row')!;
    expect(imported.loadBasis, isNull);
    expect(imported.retained['loadBasis'], 'band');
    expect(imported.retained['copiedFrom'], 'import-x');
    final blocked = await repo.updateCustomExercise(
      expected: imported.snapshot(),
      draft: _curlDraft(id: 'row', label: 'Nope'),
    );
    expect(blocked.conflict, isTrue);
    expect((await repo.readExerciseCatalogue()).byId('row')!.label, 'Rudern');
  });

  test('invalid new saves and malformed stored rows stay honest', () async {
    final repo = await sqliteRepo('custom_ex_invalid.db');
    await expectLater(
      repo.createCustomExercise(
        CustomExerciseDraft(
          label: '   ',
          mode: ExerciseCaptureMode.repetitions,
          equipment: ExerciseEquipmentCategory.other,
          loadBasis: ExerciseLoadBasis.total,
          repetitionBasis: ExerciseRepetitionBasis.total,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repo.createCustomExercise(
        CustomExerciseDraft(
          label: 'Fly',
          mode: ExerciseCaptureMode.repetitions,
          equipment: ExerciseEquipmentCategory.dumbbell,
          loadBasis: ExerciseLoadBasis.perDevice,
          repetitionBasis: ExerciseRepetitionBasis.perSide,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repo.createCustomExercise(
        CustomExerciseDraft(
          label: 'Plank',
          mode: ExerciseCaptureMode.time,
          equipment: ExerciseEquipmentCategory.bodyweight,
          loadBasis: ExerciseLoadBasis.bodyweight,
          repetitionBasis: ExerciseRepetitionBasis.total,
        ),
      ),
      throwsArgumentError,
    );
    expect(await LocalDb.exerciseDefRows(), isEmpty);

    final other = await repo.createCustomExercise(
      CustomExerciseDraft(
        label: 'Eigen',
        mode: ExerciseCaptureMode.time,
        equipment: ExerciseEquipmentCategory.other,
        loadBasis: ExerciseLoadBasis.bodyweight,
      ),
    );
    expect(other.current!.equipment, ExerciseEquipmentCategory.other);
    expect(
      filterExerciseCatalogue(
        (await repo.readExerciseCatalogue()).entries,
        equipment: {kExerciseEquipmentUnknown},
      ).any((e) => e.id == other.current!.id),
      isFalse,
    );

    final db = await LocalDb.instance;
    await db.insert('exercise_def', {
      'key': 'broken',
      'label': 'Broken',
      'muscles_json': '{}',
      'equipment': '',
      'created_at': 1,
      'definition_json': '{',
    });
    final cat = await repo.readExerciseCatalogue();
    expect(cat.unreadableCount, greaterThanOrEqualTo(1));
    expect(cat.byId('broken'), isNull);
  });

  test('schema 62 upgrades to 63 and repair keeps historic totals', () async {
    const name = 'custom_ex_from_62.db';
    created.add(name);
    final path = await _dbPath(name);
    await databaseFactory.deleteDatabase(path);
    final old = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 62,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE exercise_def (
              key TEXT PRIMARY KEY,
              label TEXT NOT NULL,
              muscles_json TEXT NOT NULL DEFAULT '{}',
              equipment TEXT NOT NULL DEFAULT '',
              unilateral INTEGER NOT NULL DEFAULT 0,
              custom INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              source TEXT,
              version INTEGER,
              definition_json TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE strength_set (
              session_id TEXT NOT NULL,
              seq INTEGER NOT NULL,
              exercise_key TEXT NOT NULL,
              set_index INTEGER NOT NULL,
              reps INTEGER,
              load_kg REAL,
              rpe INTEGER,
              hold_sec INTEGER,
              rest_sec INTEGER,
              at_ts INTEGER,
              note TEXT NOT NULL DEFAULT '',
              planned_set_id TEXT,
              exercise_id TEXT,
              PRIMARY KEY (session_id, seq)
            )
          ''');
          await db.insert('exercise_def', {
            'key': 'row',
            'label': 'Rudern',
            'muscles_json': '{}',
            'equipment': '',
            'unilateral': 0,
            'custom': 1,
            'created_at': 1770000000,
            'source': 'imported',
            'version': 4,
            'definition_json': jsonEncode({
              'copiedFrom': 'import-x',
              'mode': 'repetitions',
            }),
          });
          await db.insert('strength_set', {
            'session_id': 'sess-old',
            'seq': 0,
            'exercise_key': 'incline_db_press',
            'set_index': 1,
            'reps': 8,
            'load_kg': 62.55,
            'at_ts': 1770000100,
            'note': '',
          });
        },
      ),
    );
    await old.close();

    Future<void> reopenAndCheck() async {
      await LocalDb.close();
      LocalDb.dbName = name;
      final db = await LocalDb.instance;
      expect(LocalDb.schemaVersion, 63);
      expect((await db.rawQuery('PRAGMA user_version')).first.values.first, 63);
      final cols = {
        for (final c in await db.rawQuery('PRAGMA table_info(strength_set)'))
          c['name'] as String,
      };
      expect(cols, containsAll(['load_json', 'definition_json']));
      final def = (await db.query('exercise_def')).single;
      expect(def['key'], 'row');
      expect(def['label'], 'Rudern');
      expect(def['created_at'], 1770000000);
      expect(def['version'], 4);
      final set = (await db.query('strength_set')).single;
      expect(set['load_kg'], 62.55);
      expect(set['load_json'], isNull);
      expect(set['definition_json'], isNull);
    }

    await reopenAndCheck();
    await reopenAndCheck();

    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final cat = await LocalOpenBandRepository(app).readExerciseCatalogue();
    expect(cat.byId('row')!.label, 'Rudern');
    expect(cat.byId('row')!.loadBasis, isNull);
    expect(cat.byId('incline_db_press')!.loadBasis, isNull);
  });

  test('snapshots survive rename and template copy', () async {
    final repo = await sqliteRepo('custom_ex_snap.db');
    final def = (await repo.createCustomExercise(_curlDraft())).current!;
    final plan = WorkoutTemplate(
      id: 'tpl',
      name: 'Arme',
      version: 0,
      exercises: [
        PlannedExercise(
          id: 'ex',
          exerciseKey: def.id,
          name: def.label,
          definition: def.snapshot(),
          sets: [
            PlannedSet(
              id: 's1',
              reps: 8,
              loadKg: 20,
              load: OriginalLoadInput(
                value: 10,
                unit: ExerciseLoadUnit.kg,
                basis: ExerciseLoadBasis.perDevice,
                deviceCount: 2,
                repetitionBasis: ExerciseRepetitionBasis.perSide,
              ),
            ),
          ],
        ),
      ],
      updatedAt: DateTime(2026, 9, 20),
    );
    await repo.saveTemplate(plan);
    await repo.updateCustomExercise(
      expected: def.snapshot(),
      draft: _curlDraft(label: 'Umbenannt'),
    );
    final stored = (await repo.readTemplates()).single;
    expect(stored.exercises.single.definition!.label, 'Kurzhantel-Curl');
    expect(stored.exercises.single.definition!.id, def.id);
    expect(stored.exercises.single.sets.single.loadKg, 20);

    final copy = copyWorkoutTemplate(stored, at: DateTime(2026, 9, 21));
    expect(copy.exercises.single.definition!.label, 'Kurzhantel-Curl');
    expect(copy.exercises.single.sets.single.load!.value, 10);
    expect(copy.exercises.single.sets.single.loadKg, 20);
    expect(copy.exercises.single.id, isNot(stored.exercises.single.id));
  });

  test('sqlite and synthetic record the same curl load semantics', () async {
    Future<void> exercise(OpenBandRepository repo) async {
      final def = (await repo.createCustomExercise(_curlDraft())).current!;
      final snap = def.snapshot();
      final plan = WorkoutTemplate(
        id: 'tpl-curl',
        name: 'Arme',
        version: 1,
        exercises: [
          PlannedExercise(
            id: 'ex-curl',
            exerciseKey: def.id,
            name: def.label,
            definition: snap,
            sets: [
              PlannedSet(
                id: 'set-curl',
                reps: 8,
                restSec: 60,
                load: OriginalLoadInput(
                  value: 10,
                  unit: ExerciseLoadUnit.kg,
                  basis: ExerciseLoadBasis.perDevice,
                  deviceCount: 2,
                  repetitionBasis: ExerciseRepetitionBasis.perSide,
                  side: ExerciseSetSide.both,
                ),
              ),
              const PlannedSet(
                id: 'set-left',
                reps: 8,
                restSec: 60,
              ),
              const PlannedSet(
                id: 'set-right',
                reps: 8,
                restSec: 60,
              ),
              const PlannedSet(id: 'set-body', reps: 10, restSec: 60),
              const PlannedSet(id: 'set-help', reps: 8, restSec: 60),
              const PlannedSet(id: 'set-zero', reps: 5, restSec: 60),
              PlannedSet(
                id: 'set-lb',
                reps: 8,
                restSec: 60,
                load: OriginalLoadInput(
                  value: 10,
                  unit: ExerciseLoadUnit.lb,
                  basis: ExerciseLoadBasis.total,
                ),
              ),
              const PlannedSet(
                id: 'set-mixed',
                reps: 5,
                seconds: 20,
              ),
            ],
          ),
        ],
        updatedAt: DateTime(2026, 9, 20),
      );
      final decoded = PlannedSet.fromJson(plan.exercises.single.sets.first.toJson());
      expect(decoded.loadKg, 20);

      final sessionId = await repo.startStrengthSession(plan);
      final at = DateTime(2026, 9, 20, 18);
      await repo.recordSet(
        sessionId,
        RecordedSet(
          exerciseKey: def.id,
          setIndex: 1,
          reps: 8,
          at: at,
          plannedSetId: 'set-curl',
          exerciseId: 'ex-curl',
          load: OriginalLoadInput(
            value: 10,
            unit: ExerciseLoadUnit.kg,
            basis: ExerciseLoadBasis.perDevice,
            deviceCount: 2,
            repetitionBasis: ExerciseRepetitionBasis.perSide,
            side: ExerciseSetSide.both,
          ),
        ),
      );
      await repo.recordSet(
        sessionId,
        RecordedSet(
          exerciseKey: def.id,
          setIndex: 2,
          reps: 8,
          at: at.add(const Duration(minutes: 1)),
          plannedSetId: 'set-left',
          exerciseId: 'ex-curl',
          load: OriginalLoadInput(
            value: 10,
            unit: ExerciseLoadUnit.kg,
            basis: ExerciseLoadBasis.perDevice,
            deviceCount: 1,
            repetitionBasis: ExerciseRepetitionBasis.perSide,
            side: ExerciseSetSide.left,
          ),
        ),
      );
      await repo.recordSet(
        sessionId,
        RecordedSet(
          exerciseKey: def.id,
          setIndex: 3,
          reps: 8,
          at: at.add(const Duration(minutes: 2)),
          plannedSetId: 'set-right',
          exerciseId: 'ex-curl',
          load: OriginalLoadInput(
            value: 10,
            unit: ExerciseLoadUnit.kg,
            basis: ExerciseLoadBasis.perDevice,
            deviceCount: 1,
            repetitionBasis: ExerciseRepetitionBasis.perSide,
            side: ExerciseSetSide.right,
          ),
        ),
      );
      await repo.recordSet(
        sessionId,
        RecordedSet(
          exerciseKey: def.id,
          setIndex: 4,
          reps: 10,
          at: at.add(const Duration(minutes: 3)),
          plannedSetId: 'set-body',
          exerciseId: 'ex-curl',
          load: OriginalLoadInput(basis: ExerciseLoadBasis.bodyweight),
        ),
      );
      await repo.recordSet(
        sessionId,
        RecordedSet(
          exerciseKey: def.id,
          setIndex: 5,
          reps: 8,
          at: at.add(const Duration(minutes: 4)),
          plannedSetId: 'set-help',
          exerciseId: 'ex-curl',
          load: OriginalLoadInput(
            value: 12,
            unit: ExerciseLoadUnit.kg,
            basis: ExerciseLoadBasis.assistance,
          ),
        ),
      );
      await repo.recordSet(
        sessionId,
        RecordedSet(
          exerciseKey: def.id,
          setIndex: 6,
          reps: 5,
          loadKg: 0,
          at: at.add(const Duration(minutes: 5)),
          plannedSetId: 'set-zero',
          exerciseId: 'ex-curl',
          load: OriginalLoadInput(
            value: 0,
            unit: ExerciseLoadUnit.kg,
            basis: ExerciseLoadBasis.total,
          ),
        ),
      );
      await repo.recordSet(
        sessionId,
        RecordedSet(
          exerciseKey: def.id,
          setIndex: 7,
          reps: 8,
          at: at.add(const Duration(minutes: 6)),
          plannedSetId: 'set-lb',
          exerciseId: 'ex-curl',
          load: OriginalLoadInput(
            value: 10,
            unit: ExerciseLoadUnit.lb,
            basis: ExerciseLoadBasis.total,
          ),
        ),
      );

      final live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded, hasLength(7));
      expect(live.recorded[0].loadKg, 20);
      expect(live.recorded[0].loadKg! * live.recorded[0].reps!, 160);
      expect(live.recorded[0].definition!.id, def.id);
      expect(live.recorded[0].definition!.label, def.label);
      expect(live.recorded[1].loadKg, 10);
      expect(live.recorded[1].load!.side, ExerciseSetSide.left);
      expect(live.recorded[2].loadKg, 10);
      expect(live.recorded[3].loadKg, isNull);
      expect(live.recorded[4].loadKg, isNull);
      expect(live.recorded[4].load!.value, 12);
      expect(live.recorded[5].loadKg, 0);
      expect(live.recorded[6].loadKg, 10 * kKilogramsPerPound);
      expect(live.plan.exercises.single.sets[7].reps, 5);
      expect(live.plan.exercises.single.sets[7].seconds, 20);
      expect(live.plan.exercises.single.sets[7].mode, isNull);
    }

    await exercise(await sqliteRepo('custom_ex_record_sqlite.db'));
    await exercise(
      SyntheticOpenBandRepository.fromMaps(
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/day-summary.json',
              ).readAsStringSync(),
            )
            as Map,
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/sleep-detail.json',
              ).readAsStringSync(),
            )
            as Map,
      ),
    );
  });

  test('empty optional muscles and other equipment are accepted', () async {
    final repo = await sqliteRepo('custom_ex_other.db');
    final saved = await repo.createCustomExercise(
      CustomExerciseDraft(
        label: 'Eigen',
        mode: ExerciseCaptureMode.repetitions,
        equipment: ExerciseEquipmentCategory.other,
        equipmentRef: 'garage-band',
        loadBasis: ExerciseLoadBasis.addedLoad,
        repetitionBasis: ExerciseRepetitionBasis.total,
      ),
    );
    expect(saved.current!.primaryMuscles, isEmpty);
    expect(saved.current!.secondaryMuscles, isEmpty);
    expect(saved.current!.equipment, ExerciseEquipmentCategory.other);
    expect(saved.current!.equipmentRef, 'garage-band');
    expect(saved.current!.loadBasis, ExerciseLoadBasis.addedLoad);
  });

  test('primary and secondary muscles cannot overlap', () async {
    final repo = await sqliteRepo('custom_ex_muscles.db');
    await expectLater(
      repo.createCustomExercise(
        CustomExerciseDraft(
          label: 'Curl',
          mode: ExerciseCaptureMode.repetitions,
          equipment: ExerciseEquipmentCategory.dumbbell,
          loadBasis: ExerciseLoadBasis.perDevice,
          deviceCount: 2,
          repetitionBasis: ExerciseRepetitionBasis.perSide,
          primaryMuscles: const ['biceps'],
          secondaryMuscles: const ['biceps', 'forearm'],
        ),
      ),
      throwsArgumentError,
    );
    expect(await LocalDb.exerciseDefRows(), isEmpty);
  });

  test('synthetic create replay keeps created_at; different payload conflicts', () async {
    final repo = SyntheticOpenBandRepository.fromMaps(
      jsonDecode(
            File(
              'docs/openband5/assets/fixtures/day-summary.json',
            ).readAsStringSync(),
          )
          as Map,
      jsonDecode(
            File(
              'docs/openband5/assets/fixtures/sleep-detail.json',
            ).readAsStringSync(),
          )
          as Map,
    );
    final id = newCustomExerciseId();
    final first = (await repo.createCustomExercise(_curlDraft(id: id))).current!;
    final replay = await repo.createCustomExercise(_curlDraft(id: id));
    expect(replay.saved, isTrue);
    expect(replay.current!.id, id);
    expect(replay.current!.version, 1);
    expect(replay.current!.retained['created_at'], first.retained['created_at']);
    final clash = await repo.createCustomExercise(
      _curlDraft(id: id, label: 'Anders'),
    );
    expect(clash.conflict, isTrue);
    expect(clash.current!.label, first.label);
    expect(clash.current!.version, 1);
  });

  test('blank assisted planned set survives save and reopen', () async {
    final blank = PlannedSet(
      id: 's-help',
      reps: 8,
      load: OriginalLoadInput(
        basis: ExerciseLoadBasis.assistance,
        unit: ExerciseLoadUnit.kg,
      ),
    );
    final decoded = PlannedSet.fromJson(blank.toJson());
    expect(decoded.loadKg, isNull);
    expect(decoded.load!.value, isNull);
    expect(decoded.load!.unit, ExerciseLoadUnit.kg);
    expect(decoded.load!.basis, ExerciseLoadBasis.assistance);

    final supplied = PlannedSet.fromJson(
      PlannedSet(
        id: 's-help-2',
        reps: 8,
        load: OriginalLoadInput(
          value: 12,
          unit: ExerciseLoadUnit.kg,
          basis: ExerciseLoadBasis.assistance,
        ),
      ).toJson(),
    );
    expect(supplied.loadKg, isNull);
    expect(supplied.load!.value, 12);

    final repo = await sqliteRepo('custom_ex_assist_plan.db');
    await repo.saveTemplate(
      WorkoutTemplate(
        id: 'tpl-assist',
        name: 'Assist',
        version: 0,
        exercises: [
          PlannedExercise(
            id: 'ex',
            exerciseKey: 'pull_up',
            name: 'Klimmzug',
            sets: [blank],
          ),
        ],
        updatedAt: DateTime(2026, 9, 20),
      ),
    );
    await LocalDb.close();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    LocalDb.dbName = 'custom_ex_assist_plan.db';
    final stored =
        (await LocalOpenBandRepository(app).readTemplates()).single;
    final set = stored.exercises.single.sets.single;
    expect(set.id, 's-help');
    expect(set.loadKg, isNull);
    expect(set.load!.value, isNull);
    expect(set.load!.unit, ExerciseLoadUnit.kg);
    expect(set.load!.basis, ExerciseLoadBasis.assistance);
  });

  test('record retry after commit ignores contradictory or malformed payload', () async {
    Future<void> exercise(OpenBandRepository repo, {required bool sqlite}) async {
      final def = (await repo.createCustomExercise(_curlDraft())).current!;
      final sessionId = await repo.startStrengthSession(
        WorkoutTemplate(
          id: 'tpl-retry',
          name: 'Arme',
          version: 1,
          exercises: [
            PlannedExercise(
              id: 'ex-curl',
              exerciseKey: def.id,
              name: def.label,
              definition: def.snapshot(),
              sets: [
                PlannedSet(
                  id: 'set-curl',
                  reps: 8,
                  restSec: 60,
                  load: OriginalLoadInput(
                    value: 10,
                    unit: ExerciseLoadUnit.kg,
                    basis: ExerciseLoadBasis.perDevice,
                    deviceCount: 2,
                  ),
                ),
              ],
            ),
          ],
          updatedAt: DateTime(2026, 9, 20),
        ),
      );
      final at = DateTime(2026, 9, 20, 18);
      await repo.recordSet(
        sessionId,
        RecordedSet(
          exerciseKey: def.id,
          setIndex: 1,
          reps: 8,
          at: at,
          plannedSetId: 'set-curl',
          exerciseId: 'ex-curl',
          load: OriginalLoadInput(
            value: 10,
            unit: ExerciseLoadUnit.kg,
            basis: ExerciseLoadBasis.perDevice,
            deviceCount: 2,
          ),
        ),
      );
      await repo.recordSet(
        sessionId,
        RecordedSet(
          exerciseKey: def.id,
          setIndex: 1,
          reps: 8,
          loadKg: 10,
          at: at.add(const Duration(seconds: 1)),
          plannedSetId: 'set-curl',
          exerciseId: 'ex-curl',
          load: OriginalLoadInput(
            value: 10,
            unit: ExerciseLoadUnit.kg,
            basis: ExerciseLoadBasis.perDevice,
            deviceCount: 2,
          ),
        ),
      );
      final live =
          await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.recorded, hasLength(1));
      expect(live.recorded.single.loadKg, 20);
      expect(live.recorded.single.load!.value, 10);
      if (sqlite) {
        await LocalDb.recordOpenBandStrengthSet(
          sessionId: sessionId,
          exerciseKey: def.id,
          setIndex: 1,
          reps: 8,
          loadKg: 10,
          atTs: at.millisecondsSinceEpoch ~/ 1000,
          plannedSetId: 'set-curl',
          exerciseId: 'ex-curl',
          loadJson: '{',
        );
        final rows = await LocalDb.strengthSets(sessionId);
        expect(rows, hasLength(1));
        expect(rows.single['load_kg'], 20);
      }
    }

    await exercise(
      await sqliteRepo('custom_ex_record_retry.db'),
      sqlite: true,
    );
    await exercise(
      SyntheticOpenBandRepository.fromMaps(
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/day-summary.json',
              ).readAsStringSync(),
            )
            as Map,
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/sleep-detail.json',
              ).readAsStringSync(),
            )
            as Map,
      ),
      sqlite: false,
    );
  });
}
