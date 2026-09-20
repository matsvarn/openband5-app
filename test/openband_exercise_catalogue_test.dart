import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _dbPath(String name) async =>
    p.join(await databaseFactory.getDatabasesPath(), name);

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

  test('presets are the single source for the shipped 18 identities', () {
    expect(kExercisePresets, hasLength(18));
    expect(exerciseLibrary, hasLength(18));
    expect(
      [for (final e in kExercisePresets) e.id],
      [for (final e in exerciseLibrary) e.key],
    );
    for (final e in kExercisePresets) {
      final legacy = exerciseByKey(e.id);
      expect(legacy, isNotNull, reason: e.id);
      expect(legacy!.label, e.labelEn);
      expect(legacy.muscles, e.legacyMuscleShares);
      expect(legacy.step, e.loadIncrement);
    }
    expect(exerciseByKey('row'), isNull);
    expect(exerciseByKey('squat'), isNull);
    expect(exerciseByKey('pullup'), isNull);
    expect(exerciseByKey('chin_up'), isNull);
    expect(exercisePresetById('row'), isNull);
    expect(exercisePresetById('squat'), isNull);
    expect(exercisePresetById('pullup'), isNull);
    expect(exercisePresetById('chin_up'), isNull);

    final hanging = exercisePresetById('hanging_leg_raise')!;
    expect(hanging.loadIncrement, 0);
    expect(hanging.mode, ExerciseCaptureMode.repetitions);
    expect(exercisePresetById('plank')!.mode, ExerciseCaptureMode.time);
    expect(exercisePresetById('overhead_press')!.equipment, isNull);
    expect(exercisePresetById('overhead_extension')!.equipment, isNull);
    expect(exercisePresetById('hip_thrust')!.equipment, isNull);
  });

  test('search ANDs groups and ORs within muscle or equipment', () {
    final cat = assembleExerciseCatalogue(const []);
    expect(cat.unreadableCount, 0);
    expect(cat.entries, hasLength(18));

    expect(
      {for (final e in filterExerciseCatalogue(cat.entries, query: 'bankdrücken'))
        e.id},
      {'bench_press', 'incline_db_press'},
    );
    expect(
      filterExerciseCatalogue(cat.entries, query: 'klimmzug').single.id,
      'pull_up',
    );
    expect(
      filterExerciseCatalogue(cat.entries, query: 'bench press').single.id,
      'bench_press',
    );
    expect(
      filterExerciseCatalogue(cat.entries, query: 'hanging').single.id,
      'hanging_leg_raise',
    );

    final push = filterExerciseCatalogue(
      cat.entries,
      muscles: {'chest', 'shoulders'},
    );
    expect(
      {for (final e in push) e.id},
      containsAll(['bench_press', 'overhead_press', 'cable_fly']),
    );
    expect(push.any((e) => e.id == 'barbell_curl'), isFalse);

    final loaded = filterExerciseCatalogue(
      cat.entries,
      equipment: {'barbell', 'cable'},
    );
    expect(loaded.any((e) => e.id == 'bench_press'), isTrue);
    expect(loaded.any((e) => e.id == 'cable_fly'), isTrue);
    expect(loaded.any((e) => e.id == 'plank'), isFalse);
    expect(loaded.any((e) => e.id == 'overhead_press'), isFalse);

    final anded = filterExerciseCatalogue(
      cat.entries,
      query: 'press',
      muscles: {'chest'},
      equipment: {'barbell'},
    );
    expect(anded.single.id, 'bench_press');
  });

  test('stored rows overlay by exact id and keep unknown imported metadata', () {
    final cat = assembleExerciseCatalogue([
      {
        'key': 'row',
        'label': 'Rudern',
        'muscles_json': '{"mystery":1}',
        'equipment': 'kettlebell',
        'unilateral': 1,
        'custom': 1,
        'created_at': 1700000000,
        'definition_json': jsonEncode({
          'copiedFrom': 'import-x',
          'mysteryFlag': true,
        }),
      },
      {
        'key': 'bench_press',
        'label': 'Imported bench',
        'muscles_json': '{}',
        'equipment': '',
        'unilateral': 0,
        'custom': 1,
        'created_at': 1700000001,
      },
    ]);
    expect(cat.unreadableCount, 0);
    expect(cat.byId('row')!.label, 'Rudern');
    expect(cat.byId('row')!.mode, isNull);
    expect(cat.byId('row')!.selectable, isFalse);
    expect(cat.byId('row')!.equipment, isNull);
    expect(cat.byId('row')!.retained['muscles_json'], '{"mystery":1}');
    expect(cat.byId('row')!.retained['copiedFrom'], 'import-x');
    expect(cat.byId('row')!.source, ExerciseDefinitionSource.stored);
    expect(cat.byId('bench_press')!.label, 'Imported bench');
    expect(cat.byId('bench_press')!.selectable, isFalse);
    expect(cat.byId('bench_press')!.source, ExerciseDefinitionSource.stored);
    expect(cat.byId('plank')!.selectable, isTrue);
    expect(exerciseByKey('bench_press')!.label, 'Bench press');
  });

  test('malformed rows are a partial load with a distinct unread count', () {
    final cat = assembleExerciseCatalogue([
      {
        'key': 'ok_custom',
        'label': 'Eigen',
        'muscles_json': '{}',
        'equipment': 'dumbbell',
        'unilateral': 0,
        'custom': 1,
        'created_at': 1,
        'definition_json': jsonEncode({
          'mode': 'repetitions',
          'labelDe': 'Eigen',
        }),
      },
      {
        'key': 'bad_json',
        'label': 'Broken',
        'muscles_json': '{}',
        'equipment': '',
        'created_at': 2,
        'definition_json': '{not json',
      },
      {
        'key': 'future_mode',
        'label': 'Hold',
        'muscles_json': '{}',
        'equipment': '',
        'created_at': 3,
        'definition_json': jsonEncode({'mode': 'isometric'}),
      },
      {
        'label': 'no-key',
        'muscles_json': '{}',
        'created_at': 4,
      },
    ]);
    expect(cat.unreadableCount, 3);
    expect(cat.byId('ok_custom')!.selectable, isTrue);
    expect(cat.byId('ok_custom')!.mode, ExerciseCaptureMode.repetitions);
    expect(cat.entries.where((e) => e.id == 'bad_json'), isEmpty);
    expect(cat.entries, isNotEmpty);
    expect(cat.byId('plank'), isNotNull);
  });

  test(
    'old schema 61 upgrades to 62 and two repairs keep user rows',
    () async {
      const name = 'exercise_def_old_schema.db';
      created.add(name);
      final path = await _dbPath(name);
      await databaseFactory.deleteDatabase(path);
      final old = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 61,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE exercise_def (
                key TEXT PRIMARY KEY,
                label TEXT NOT NULL,
                muscles_json TEXT NOT NULL DEFAULT '{}',
                equipment TEXT NOT NULL DEFAULT '',
                unilateral INTEGER NOT NULL DEFAULT 0,
                custom INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL
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
            });
            await db.insert('exercise_def', {
              'key': 'chin_up',
              'label': 'Untergriff',
              'muscles_json': '{}',
              'equipment': 'bodyweight',
              'unilateral': 0,
              'custom': 1,
              'created_at': 1770000001,
            });
          },
        ),
      );
      await old.close();

      Future<void> reopenAndCheck() async {
        await LocalDb.close();
        LocalDb.dbName = name;
        final db = await LocalDb.instance;
        expect(LocalDb.schemaVersion, 62);
        expect((await db.rawQuery('PRAGMA user_version')).first.values.first, 62);
        final cols = {
          for (final c in await db.rawQuery('PRAGMA table_info(exercise_def)'))
            c['name'] as String,
        };
        expect(cols, containsAll(['source', 'version', 'definition_json']));
        final rows = await db.query('exercise_def', orderBy: 'created_at ASC');
        expect(rows, hasLength(2));
        expect(rows[0]['key'], 'row');
        expect(rows[0]['label'], 'Rudern');
        expect(rows[0]['created_at'], 1770000000);
        expect(rows[1]['key'], 'chin_up');
        expect(rows[1]['created_at'], 1770000001);
        expect(
          rows.map((r) => r['key']),
          isNot(containsAll(['bench_press', 'plank'])),
        );
      }

      await reopenAndCheck();
      await reopenAndCheck();

      SharedPreferences.setMockInitialValues({});
      Prefs.debugReset();
      await Prefs.ensureLoaded();
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final repo = LocalOpenBandRepository(app);
      final cat = await repo.readExerciseCatalogue();
      expect(cat.unreadableCount, 0);
      expect(cat.byId('row')!.label, 'Rudern');
      expect(cat.byId('row')!.selectable, isFalse);
      expect(cat.byId('chin_up')!.id, 'chin_up');
      expect(cat.byId('chin_up')!.equipment, ExerciseEquipmentCategory.bodyweight);
      expect(cat.byId('pull_up')!.id, 'pull_up');
      expect(cat.byId('plank')!.mode, ExerciseCaptureMode.time);
    },
  );

  test('read failure throws instead of an empty success', () async {
    const name = 'exercise_def_read_fail.db';
    created.add(name);
    await LocalDb.close();
    LocalDb.dbName = name;
    await databaseFactory.deleteDatabase(await _dbPath(name));
    final db = await LocalDb.instance;
    await db.execute('DROP TABLE exercise_def');
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final repo = LocalOpenBandRepository(app);
    await expectLater(repo.readExerciseCatalogue(), throwsA(isA<Object>()));
  });

  test('malformed stored definition is counted after a real sqlite read', () async {
    const name = 'exercise_def_partial.db';
    created.add(name);
    await LocalDb.close();
    LocalDb.dbName = name;
    await databaseFactory.deleteDatabase(await _dbPath(name));
    final db = await LocalDb.instance;
    await db.insert('exercise_def', {
      'key': 'ok_custom',
      'label': 'Eigen',
      'muscles_json': '{}',
      'equipment': 'dumbbell',
      'unilateral': 0,
      'custom': 1,
      'created_at': 9,
      'definition_json': jsonEncode({'mode': 'repetitions'}),
    });
    await db.insert('exercise_def', {
      'key': 'broken',
      'label': 'Broken',
      'muscles_json': '{}',
      'equipment': '',
      'unilateral': 0,
      'custom': 1,
      'created_at': 10,
      'definition_json': '{',
    });
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final cat = await LocalOpenBandRepository(app).readExerciseCatalogue();
    expect(cat.unreadableCount, 1);
    expect(cat.byId('ok_custom')!.selectable, isTrue);
    expect(cat.byId('broken'), isNull);
    expect(cat.byId('bench_press'), isNotNull);
  });

  test('planned set mode is explicit and legacy seconds stay timed', () {
    final emptyTimed = PlannedSet(id: 't', mode: PlannedSetMode.time);
    expect(emptyTimed.seconds, isNull);
    expect(emptyTimed.reps, isNull);
    expect(emptyTimed.isTimed, isTrue);
    final back = PlannedSet.fromJson(emptyTimed.toJson());
    expect(back.mode, PlannedSetMode.time);
    expect(back.seconds, isNull);
    expect(back.toJson().containsKey('mode'), isTrue);

    final legacyTime = PlannedSet.fromJson({
      'id': 'old-t',
      'seconds': 45,
      'restSec': 60,
    });
    expect(legacyTime.mode, isNull);
    expect(legacyTime.effectiveMode, PlannedSetMode.time);
    expect(legacyTime.toJson().containsKey('mode'), isFalse);

    final legacyReps = PlannedSet.fromJson({'id': 'old-r', 'reps': 8});
    expect(legacyReps.mode, isNull);
    expect(legacyReps.effectiveMode, isNull);
    expect(legacyReps.isTimed, isFalse);

    final both = PlannedSet.fromJson({
      'id': 'old-both',
      'reps': 5,
      'seconds': 20,
    });
    expect(both.reps, 5);
    expect(both.seconds, 20);
    expect(both.mode, isNull);

    expect(
      () => PlannedSet.fromJson({
        'id': 'bad',
        'mode': 'time',
        'reps': 8,
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => PlannedSet.fromJson({
        'id': 'bad2',
        'mode': 'repetitions',
        'seconds': 30,
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => PlannedSet.fromJson({
        'id': 'bad3',
        'mode': 'time',
        'reps': 5,
        'seconds': 20,
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => PlannedSet.fromJson({'id': 'bad4', 'mode': 'hold'}),
      throwsA(isA<FormatException>()),
    );
  });

  test('empty timed set survives template save, reopen and start snapshot', () async {
    const name = 'exercise_timed_set_roundtrip.db';
    created.add(name);
    await LocalDb.close();
    LocalDb.dbName = name;
    await databaseFactory.deleteDatabase(await _dbPath(name));
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final repo = LocalOpenBandRepository(app);
    final plank = kExercisePresets.singleWhere((e) => e.id == 'plank');
    final plan = WorkoutTemplate(
      id: 'tpl-timed',
      name: 'Halt',
      version: 0,
      exercises: [
        PlannedExercise(
          id: 'ex-plank',
          exerciseKey: 'plank',
          name: 'Unterarmstütz',
          definition: plank.asEntry.snapshot(),
          sets: [const PlannedSet(id: 'set-empty', mode: PlannedSetMode.time)],
        ),
      ],
      updatedAt: DateTime(2026, 9, 20),
    );
    await repo.saveTemplate(plan);
    final stored = (await repo.readTemplates()).single;
    expect(stored.exercises.single.sets.single.mode, PlannedSetMode.time);
    expect(stored.exercises.single.sets.single.seconds, isNull);
    expect(stored.exercises.single.definition!.id, 'plank');
    expect(stored.exercises.single.definition!.mode, ExerciseCaptureMode.time);

    final sessionId = await repo.startStrengthSession(stored);
    final active = await repo.readActiveStrengthSession();
    expect(active, isA<ActiveStrengthSession>());
    final live = active as ActiveStrengthSession;
    expect(live.sessionId, sessionId);
    expect(live.plan.exercises.single.sets.single.mode, PlannedSetMode.time);
    expect(live.plan.exercises.single.sets.single.seconds, isNull);
    expect(live.plan.exercises.single.definition!.id, 'plank');
    expect(strengthPlanSlots(live.plan, const []).single.timed, isTrue);
  });

  test('copying a plan keeps mode and does not rebind history', () {
    final source = WorkoutTemplate(
      id: 'src',
      name: 'A',
      version: 1,
      exercises: [
        PlannedExercise(
          id: 'ex',
          exerciseKey: 'row',
          name: 'Rudern',
          definition: ExerciseDefinitionSnapshot(
            id: 'row',
            label: 'Rudern',
            source: ExerciseDefinitionSource.stored,
            mode: ExerciseCaptureMode.repetitions,
            version: 3,
          ),
          sets: const [
            PlannedSet(id: 's', mode: PlannedSetMode.time),
          ],
        ),
      ],
      updatedAt: DateTime(2026, 9, 20),
    );
    final copy = copyWorkoutTemplate(source, at: DateTime(2026, 9, 21));
    expect(copy.exercises.single.exerciseKey, 'row');
    expect(copy.exercises.single.definition!.id, 'row');
    expect(copy.exercises.single.definition!.version, 3);
    expect(copy.exercises.single.sets.single.mode, PlannedSetMode.time);
    expect(copy.exercises.single.id, isNot(source.exercises.single.id));
  });

  test('snapshot retained roundtrips without nesting provenance', () {
    var snap = ExerciseDefinitionSnapshot.fromJson({
      'id': 'row',
      'label': 'Rudern',
      'source': 'stored',
      'copiedFrom': 'import-x',
      'mysteryFlag': true,
      'retained': {'muscles_json': '{"mystery":1}'},
    });
    expect(snap.retained['copiedFrom'], 'import-x');
    expect(snap.retained['mysteryFlag'], isTrue);
    expect(snap.retained['muscles_json'], '{"mystery":1}');
    expect(snap.retained.containsKey('retained'), isFalse);
    for (var i = 0; i < 3; i++) {
      final json = snap.toJson();
      expect(json['retained'], isA<Map>());
      expect((json['retained'] as Map).containsKey('retained'), isFalse);
      expect(json.containsKey('copiedFrom'), isFalse);
      snap = ExerciseDefinitionSnapshot.fromJson(json);
    }
    expect(snap.retained['copiedFrom'], 'import-x');
    expect(snap.retained['mysteryFlag'], isTrue);
    expect(snap.retained['muscles_json'], '{"mystery":1}');
    expect(snap.retained.containsKey('retained'), isFalse);
  });

  test('malformed stored preset id is not replaced by the seed', () {
    final cat = assembleExerciseCatalogue([
      {
        'key': 'bench_press',
        'label': 'Broken bench',
        'muscles_json': '{}',
        'equipment': '',
        'created_at': 1,
        'definition_json': '{',
      },
      {
        'key': 'ok_custom',
        'label': 'Eigen',
        'muscles_json': '{}',
        'equipment': 'dumbbell',
        'created_at': 2,
        'definition_json': jsonEncode({'mode': 'repetitions'}),
      },
    ]);
    expect(cat.unreadableCount, 1);
    expect(cat.byId('bench_press'), isNull);
    expect(cat.byId('ok_custom')!.selectable, isTrue);
    expect(cat.byId('plank')!.selectable, isTrue);
  });

  test('strict stored-row validation counts each bad row', () {
    Map<String, Object?> row(
      String key,
      String label, [
      Map<String, Object?> extra = const {},
    ]) => {
      'key': key,
      'label': label,
      'muscles_json': '{}',
      'equipment': '',
      'created_at': 1,
      ...extra,
    };

    final cat = assembleExerciseCatalogue([
      row('good', 'Eigen', {
        'definition_json': jsonEncode({'mode': 'repetitions'}),
      }),
      row('bad_def_type', 'X', {'definition_json': 12}),
      row('bad_def_list', 'X', {
        'definition_json': ['nope'],
      }),
      row('empty_label', ''),
      row('bad_muscles', 'X', {
        'definition_json': jsonEncode({
          'mode': 'repetitions',
          'primaryMuscles': 'chest',
        }),
      }),
      row('bad_muscle_items', 'X', {
        'definition_json': jsonEncode({
          'mode': 'repetitions',
          'primaryMuscles': [1, 2],
        }),
      }),
      row('frac_version', 'X', {'version': 1.5}),
      row('neg_version', 'X', {'version': -1}),
      row('nan_version', 'X', {'version': double.nan}),
      row('neg_step', 'X', {
        'definition_json': jsonEncode({'loadIncrement': -1}),
      }),
      row('inf_step', 'X', {
        'definition_json': '{"loadIncrement":"inf"}',
      }),
      {'key': 9, 'label': 'X', 'muscles_json': '{}', 'created_at': 1},
    ]);
    expect(cat.unreadableCount, 11);
    expect(cat.byId('good')!.selectable, isTrue);
    expect(cat.byId('plank'), isNotNull);
    expect(cat.byId('bad_def_type'), isNull);
    expect(cat.byId('empty_label'), isNull);
  });

  test('explicit unknown JSON equipment is not replaced by the column', () {
    final cat = assembleExerciseCatalogue([
      {
        'key': 'row',
        'label': 'Rudern',
        'muscles_json': '{}',
        'equipment': 'barbell',
        'created_at': 1,
        'definition_json': jsonEncode({'equipment': 'kettlebell'}),
      },
    ]);
    expect(cat.unreadableCount, 0);
    expect(cat.byId('row')!.equipment, isNull);
    expect(cat.byId('row')!.retained['equipment'], 'kettlebell');
  });

  test('snapshot lists are frozen against later source mutation', () {
    final muscles = ['chest'];
    final secondary = ['triceps'];
    final retained = <String, Object?>{'copiedFrom': 'import-x'};
    final entry = ExerciseCatalogueEntry(
      id: 'custom',
      label: 'Eigen',
      primaryMuscles: muscles,
      secondaryMuscles: secondary,
      source: ExerciseDefinitionSource.stored,
      mode: ExerciseCaptureMode.repetitions,
      retained: retained,
    );
    final snap = entry.snapshot();
    muscles.add('back');
    secondary.add('core');
    retained['copiedFrom'] = 'mutated';
    expect(snap.primaryMuscles, ['chest']);
    expect(snap.secondaryMuscles, ['triceps']);
    expect(snap.retained['copiedFrom'], 'import-x');
    expect(
      () => snap.primaryMuscles.add('shoulders'),
      throwsUnsupportedError,
    );
  });

  test('whitespace keys stay distinct from preset ids', () {
    final cat = assembleExerciseCatalogue([
      {
        'key': 'bench_press ',
        'label': '  Spaced  ',
        'muscles_json': '{}',
        'equipment': '',
        'created_at': 1,
        'definition_json': jsonEncode({'mode': 'repetitions'}),
      },
      {
        'key': 'row ',
        'label': 'Rudern spaced',
        'muscles_json': '{}',
        'equipment': '',
        'created_at': 2,
        'definition_json': jsonEncode({'mode': 'repetitions'}),
      },
      {
        'key': 'row',
        'label': 'Rudern',
        'muscles_json': '{}',
        'equipment': '',
        'created_at': 3,
        'definition_json': jsonEncode({'mode': 'repetitions'}),
      },
    ]);
    expect(cat.unreadableCount, 0);
    expect(cat.byId('bench_press ')!.id, 'bench_press ');
    expect(cat.byId('bench_press ')!.label, 'Spaced');
    expect(cat.byId('bench_press ')!.source, ExerciseDefinitionSource.stored);
    expect(cat.byId('bench_press')!.source, ExerciseDefinitionSource.preset);
    expect(cat.byId('bench_press')!.label, 'Bankdrücken');
    expect(cat.byId('bench_press')!.selectable, isTrue);
    expect(cat.byId('row ')!.label, 'Rudern spaced');
    expect(cat.byId('row')!.label, 'Rudern');
    expect(cat.byId('row')!.source, ExerciseDefinitionSource.stored);
    expect(
      () => ExerciseDefinitionSnapshot.fromJson({
        'id': 'row ',
        'label': '   ',
        'source': 'stored',
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      ExerciseDefinitionSnapshot.fromJson({
        'id': 'row ',
        'label': '  Rudern  ',
        'source': 'stored',
      }).id,
      'row ',
    );
  });

  test('row and definition source stay in retained, not as typed source', () {
    final cat = assembleExerciseCatalogue([
      {
        'key': 'row',
        'label': 'Rudern',
        'muscles_json': '{}',
        'equipment': '',
        'created_at': 1,
        'source': 'imported',
        'definition_json': jsonEncode({'source': 'preset'}),
      },
    ]);
    final entry = cat.byId('row')!;
    expect(entry.source, ExerciseDefinitionSource.stored);
    expect(entry.retained['source'], 'imported');
    expect(entry.retained['definition_source'], 'preset');
    final snap = entry.snapshot();
    expect(snap.source, ExerciseDefinitionSource.stored);
    expect(snap.retained['source'], 'imported');
    expect(snap.retained['definition_source'], 'preset');
  });

  test('nested retained values are frozen and survive reload', () {
    final nested = <String, Object?>{'inner': 'a'};
    final tags = <Object?>['x'];
    final retained = <String, Object?>{'meta': nested, 'tags': tags};
    final snap = ExerciseCatalogueEntry(
      id: 'custom',
      label: 'Eigen',
      source: ExerciseDefinitionSource.stored,
      retained: retained,
    ).snapshot();
    nested['inner'] = 'b';
    tags.add('y');
    expect((snap.retained['meta'] as Map)['inner'], 'a');
    expect(snap.retained['tags'], ['x']);
    expect(
      () => (snap.retained['meta'] as Map)['inner'] = 'c',
      throwsUnsupportedError,
    );
    expect(
      () => (snap.retained['tags'] as List).add('z'),
      throwsUnsupportedError,
    );

    var loaded = ExerciseDefinitionSnapshot.fromJson({
      'id': 'custom',
      'label': 'Eigen',
      'source': 'stored',
      'equipment': 'kettlebell',
      'retained': {
        'meta': {'inner': 'a'},
        'tags': ['x'],
        'copiedFrom': 'import-x',
      },
    });
    expect(loaded.equipment, isNull);
    expect(loaded.retained['equipment'], 'kettlebell');
    for (var i = 0; i < 3; i++) {
      loaded = ExerciseDefinitionSnapshot.fromJson(loaded.toJson());
    }
    expect(loaded.retained['equipment'], 'kettlebell');
    expect((loaded.retained['meta'] as Map)['inner'], 'a');
    expect(loaded.retained['tags'], ['x']);
    expect(loaded.retained['copiedFrom'], 'import-x');
    expect(
      () => (loaded.retained['meta'] as Map)['inner'] = 'z',
      throwsUnsupportedError,
    );
  });

  test('definition snapshot id must match the planned exercise key', () {
    final json = {
      'id': 'ex',
      'exerciseKey': 'plank',
      'name': 'Unterarmstütz',
      'sets': [
        {'id': 's', 'mode': 'time'},
      ],
      'definition': {
        'id': 'row',
        'label': 'Rudern',
        'source': 'stored',
      },
    };
    expect(
      () => PlannedExercise.fromJson(json),
      throwsA(isA<FormatException>()),
    );
    json['definition'] = {
      'id': 'plank',
      'label': 'Unterarmstütz',
      'source': 'preset',
    };
    final ok = PlannedExercise.fromJson(json);
    expect(ok.definition!.id, 'plank');
    expect(ok.exerciseKey, 'plank');
  });

  test('unknown equipment filter matches unassigned rows', () {
    final cat = assembleExerciseCatalogue(const []);
    expect(kExerciseEquipmentUnknown, 'unknown');
    final unknown = filterExerciseCatalogue(
      cat.entries,
      equipment: {kExerciseEquipmentUnknown},
    );
    expect(unknown.any((e) => e.id == 'overhead_press'), isTrue);
    expect(unknown.any((e) => e.id == 'hip_thrust'), isTrue);
    expect(unknown.any((e) => e.id == 'bench_press'), isFalse);
    expect(unknown.any((e) => e.id == 'plank'), isFalse);
  });
}
