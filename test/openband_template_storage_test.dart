import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const dbName = 'openband_template_storage_test.db';
  late AppState app;
  late LocalOpenBandRepository repo;

  WorkoutTemplate plan({
    String id = 'tpl-a',
    String name = 'Ganzkörper A',
    String exerciseId = 'ex-a',
    String setId = 'set-a',
  }) => WorkoutTemplate(
    id: id,
    name: name,
    version: 0,
    exercises: [
      PlannedExercise(
        id: exerciseId,
        exerciseKey: 'bench_press',
        name: 'Bankdrücken',
        sets: [PlannedSet(id: setId, reps: 8, loadKg: 40)],
      ),
    ],
    updatedAt: DateTime(2026, 9, 19),
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await LocalDb.close();
    LocalDb.dbName = dbName;
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/$dbName');
    SharedPreferences.setMockInitialValues({});
    Prefs.debugReset();
    await Prefs.ensureLoaded();
    app = AppState.forTesting();
    repo = LocalOpenBandRepository(app);
  });

  tearDown(() async {
    app.dispose();
    await LocalDb.close();
  });

  test('save, pin, archive and restore keep recorded sets', () async {
    final saved = await repo.saveTemplate(plan());
    expect(saved.version, 1);
    expect((await repo.readTemplates()).single.id, 'tpl-a');
    await repo.pinTemplate('tpl-a');
    expect(await repo.readPinnedTemplateId(), 'tpl-a');

    await LocalDb.saveStrengthSets('w-frozen', [
      {
        'exercise_key': 'bench_press',
        'set_index': 1,
        'reps': 8,
        'load_kg': 42.5,
        'at_ts': 1780000000,
      },
    ]);
    await repo.archiveTemplate('tpl-a');
    expect(await repo.readTemplates(), isEmpty);
    expect(await repo.readPinnedTemplateId(), isNull);
    final rows = await (await LocalDb.instance).query(
      'openband_workout_template',
      where: 'id = ?',
      whereArgs: ['tpl-a'],
    );
    expect(rows.single['archived'], 1);
    expect(await LocalDb.strengthSets('w-frozen'), isNotEmpty);
    expect(
      await LocalDb.strengthSets('w-frozen').then((r) => r.single['load_kg']),
      42.5,
    );

    await (await LocalDb.instance).update(
      'openband_workout_template',
      {'archived': 0},
      where: 'id = ?',
      whereArgs: ['tpl-a'],
    );
    expect((await repo.readTemplates()).single.id, 'tpl-a');
    expect(await repo.readPinnedTemplateId(), isNull);
  });

  test('duplicate persists a new plan without rewriting the source', () async {
    final source = await repo.saveTemplate(plan());
    final copy = await repo.saveTemplate(copyWorkoutTemplate(source));
    final other = await repo.saveTemplate(copyWorkoutTemplate(source));
    expect(copy.id, isNot(source.id));
    expect(copy.id, isNot(other.id));
    expect(copy.name, 'Ganzkörper A · Kopie');
    expect(copy.exercises.single.id, isNot(source.exercises.single.id));
    expect(
      copy.exercises.single.sets.single.id,
      isNot(source.exercises.single.sets.single.id),
    );
    final stored = await repo.readTemplates();
    expect(stored.map((t) => t.id).toSet(), {source.id, copy.id, other.id});
    expect(
      stored.firstWhere((t) => t.id == source.id).exercises.single.id,
      source.exercises.single.id,
    );
    expect(stored.firstWhere((t) => t.id == source.id).name, 'Ganzkörper A');
  });

  test(
    'pin and archive share one sqlite domain across close and reopen',
    () async {
      await repo.saveTemplate(plan());
      await repo.pinTemplate('tpl-a');
      await LocalDb.close();
      expect(await repo.readPinnedTemplateId(), 'tpl-a');
      expect((await repo.readTemplates()).single.id, 'tpl-a');

      await repo.archiveTemplate('tpl-a');
      await LocalDb.close();
      expect(await repo.readTemplates(), isEmpty);
      expect(await repo.readPinnedTemplateId(), isNull);
      final rows = await (await LocalDb.instance).query(
        'openband_workout_template',
        where: 'id = ?',
        whereArgs: ['tpl-a'],
      );
      expect(rows.single['archived'], 1);
    },
  );

  test(
    'pin rejects archived or missing ids and keeps the previous pin',
    () async {
      await repo.saveTemplate(plan());
      await repo.saveTemplate(
        plan(
          id: 'tpl-b',
          name: 'Ganzkörper B',
          exerciseId: 'ex-b',
          setId: 'set-b',
        ),
      );
      await repo.pinTemplate('tpl-a');
      await repo.archiveTemplate('tpl-b');

      await expectLater(repo.pinTemplate('tpl-b'), throwsA(isA<StateError>()));
      expect(await repo.readPinnedTemplateId(), 'tpl-a');
      expect((await repo.readTemplates()).map((t) => t.id), ['tpl-a']);

      await expectLater(
        repo.pinTemplate('tpl-gone'),
        throwsA(isA<StateError>()),
      );
      expect(await repo.readPinnedTemplateId(), 'tpl-a');

      await repo.pinTemplate(null);
      expect(await repo.readPinnedTemplateId(), isNull);
      await expectLater(
        repo.pinTemplate('tpl-gone'),
        throwsA(isA<StateError>()),
      );
      expect(await repo.readPinnedTemplateId(), isNull);
    },
  );

  test(
    'archive rolls back when pin delete fails after the archived update',
    () async {
      await repo.saveTemplate(plan());
      await repo.pinTemplate('tpl-a');
      final db = await LocalDb.instance;
      await db.execute('''
        CREATE TRIGGER fail_pinned_delete
        BEFORE DELETE ON openband_pinned_template
        BEGIN SELECT RAISE(ABORT, 'pin delete blocked'); END
      ''');

      await expectLater(repo.archiveTemplate('tpl-a'), throwsA(anything));
      expect((await repo.readTemplates()).single.id, 'tpl-a');
      expect(await repo.readPinnedTemplateId(), 'tpl-a');
      final rows = await db.query(
        'openband_workout_template',
        where: 'id = ?',
        whereArgs: ['tpl-a'],
      );
      expect(rows.single['archived'], 0);
    },
  );

  test('a failed pin write does not invent a pin', () async {
    await repo.saveTemplate(plan());
    final db = await LocalDb.instance;
    await db.execute('PRAGMA query_only = ON');
    await expectLater(repo.pinTemplate('tpl-a'), throwsA(anything));
    await db.execute('PRAGMA query_only = OFF');
    expect(await repo.readPinnedTemplateId(), isNull);
    await repo.pinTemplate('tpl-a');
    expect(await repo.readPinnedTemplateId(), 'tpl-a');
    await repo.pinTemplate(null);
    expect(await repo.readPinnedTemplateId(), isNull);
  });

  test('a second start is refused while a session is owned', () async {
    final template = await repo.saveTemplate(plan());
    final id = await repo.startStrengthSession(template);
    expect(app.activeWorkout?.workoutId, id);
    await expectLater(
      repo.startStrengthSession(template),
      throwsA(isA<WorkoutBusy>()),
    );
    expect(app.activeWorkout?.workoutId, id);
    await app.stopWorkout();
    expect(app.activeWorkout, isNull);
  });
}
