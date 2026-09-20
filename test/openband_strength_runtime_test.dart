// Strength runtime persistence: production SQLite, not the synthetic gallery.
//
// Start copies the template into a session-keyed snapshot. Sets carry stable
// planned identities. One live workout. Finish keeps the plan and logs.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

WorkoutTemplate _template({
  int version = 1,
  String name = 'Ganzkörper A',
  DateTime? updatedAt,
}) {
  PlannedExercise ex(String id, String key, String name, List<PlannedSet> sets) =>
      PlannedExercise(id: id, exerciseKey: key, name: name, sets: sets);
  return WorkoutTemplate(
    id: 'tpl-a',
    name: name,
    version: version,
    exercises: [
      ex('ex-bench-a', 'bench_press', 'Bank A', [
        const PlannedSet(id: 'set-a1', reps: 8, loadKg: 40, restSec: 90),
        const PlannedSet(id: 'set-a2', reps: 8, loadKg: 42.5, restSec: 90),
      ]),
      ex('ex-bench-b', 'bench_press', 'Bank B', [
        const PlannedSet(id: 'set-b1', reps: 10, loadKg: 30, restSec: 60),
      ]),
    ],
    updatedAt: updatedAt ?? DateTime(2026, 9, 1, 12),
  );
}

RecordedSet _setA1(DateTime at) => RecordedSet(
  exerciseKey: 'bench_press',
  setIndex: 1,
  reps: 8,
  loadKg: 40,
  at: at,
  plannedSetId: 'set-a1',
  exerciseId: 'ex-bench-a',
);

Future<void> _seedDoneStrength({
  required String id,
  required int startSec,
  required List<Map<String, Object?>> sets,
}) async {
  await LocalDb.putSession({
    'id': id,
    'start_ts': startSec,
    'end_ts': startSec + 3600,
    'type': 'weight_training',
    'status': 'done',
    'source': 'manual',
    'created_at': startSec * 1000,
  });
  await LocalDb.saveStrengthSets(id, sets);
}

Future<void> _seedLiveStrength({
  required String id,
  required int startSec,
  String type = 'weight_training',
}) async {
  await LocalDb.putSession({
    'id': id,
    'start_ts': startSec,
    'end_ts': null,
    'type': type,
    'status': 'live',
    'source': 'manual',
    'created_at': startSec * 1000,
  });
  await (await LocalDb.instance).insert('openband_strength_session', {
    'session_id': id,
    'template_id': 'tpl-a',
    'template_version': 1,
    'plan_json': jsonEncode(_template().toJson()),
    'skipped_json': '[]',
    'added_json': '[]',
    'created_at': startSec * 1000,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const dbName = 'openband_strength_runtime_test.db';

  late AppState app;
  late LocalOpenBandRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.close();
    LocalDb.dbName = dbName;
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), dbName),
    );
    app = AppState.forTesting();
    repo = LocalOpenBandRepository(app);
  });

  tearDown(() async {
    app.dispose();
    // _armLiveWorkout fires HrsLink.arm / PolarPmdLink.arm unawaited.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await LocalDb.close();
  });

  Future<void> reopen() async {
    app.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await LocalDb.close();
    app = AppState.forTesting();
    repo = LocalOpenBandRepository(app);
  }

  test('schema 63 is on create, upgrade, and repair', () async {
    expect(LocalDb.schemaVersion, 63);
    final db = await LocalDb.instance;
    expect(
      await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' "
        "AND name='openband_strength_session'",
      ),
      isNotEmpty,
    );
    final cols = await db.rawQuery('PRAGMA table_info(strength_set)');
    expect(
      cols.map((c) => c['name']),
      containsAll(['planned_set_id', 'exercise_id', 'load_json', 'definition_json']),
    );
    final snapCols = await db.rawQuery(
      'PRAGMA table_info(openband_strength_session)',
    );
    expect(snapCols.map((c) => c['name']), contains('rest_until_ts'));
    final sessionCols = await db.rawQuery('PRAGMA table_info(sessions)');
    expect(sessionCols.map((c) => c['name']), contains('hr_covered_sec'));

    await LocalDb.close();
    final oldName = 'openband_strength_from_57.db';
    final oldPath = p.join(await databaseFactory.getDatabasesPath(), oldName);
    await databaseFactory.deleteDatabase(oldPath);
    final old = await databaseFactory.openDatabase(
      oldPath,
      options: OpenDatabaseOptions(
        version: 57,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE marker (id INTEGER PRIMARY KEY)');
          await db.insert('marker', {'id': 1});
        },
      ),
    );
    await old.close();
    LocalDb.dbName = oldName;
    final upgraded = await LocalDb.instance;
    expect(
      (await upgraded.rawQuery('PRAGMA user_version')).first.values.first,
      63,
    );
    expect(
      await upgraded.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' "
        "AND name='openband_strength_session'",
      ),
      isNotEmpty,
    );
    expect(await upgraded.query('marker'), hasLength(1));
    await LocalDb.close();
    await databaseFactory.deleteDatabase(oldPath);
    LocalDb.dbName = dbName;
  });

  test('start snapshots the template across edit, archive, close/reopen', () async {
    final original = _template();
    await repo.saveTemplate(original);
    final id = await repo.startStrengthSession(original);
    expect(app.activeWorkout?.workoutId, id);

    await repo.saveTemplate(
      _template(version: 1, name: 'Edited later', updatedAt: DateTime(2026, 9, 19)),
    );
    await repo.archiveTemplate('tpl-a');

    await reopen();
    final active = await repo.readActiveStrengthSession();
    expect(active, isA<ActiveStrengthSession>());
    final saved = active as ActiveStrengthSession;
    expect(saved.sessionId, id);
    expect(saved.plan.name, 'Ganzkörper A');
    expect(saved.plan.version, 1);
    expect(saved.plan.exercises.map((e) => e.id), ['ex-bench-a', 'ex-bench-b']);
    expect(saved.plan.exercises.first.sets.map((s) => s.id), ['set-a1', 'set-a2']);
    expect(saved.plan.updatedAt, DateTime(2026, 9, 1, 12));
    expect(await repo.readTemplates(), isEmpty);
    await expectLater(
      repo.startStrengthSession(_template()),
      throwsA(isA<WorkoutBusy>()),
    );
    await repo.finishStrengthSession(id);
    expect(await repo.readActiveStrengthSession(), isA<NoActiveStrength>());
    expect(await LocalDb.openBandStrengthSession(id), isNotNull);
  });

  test('repeated exercise keys keep distinct planned set identities', () async {
    final id = await repo.startStrengthSession(_template());
    final at = DateTime(2026, 9, 15, 18);
    await repo.recordSet(
      id,
      RecordedSet(
        exerciseKey: 'bench_press',
        setIndex: 1,
        reps: 8,
        loadKg: 40,
        at: at,
        plannedSetId: 'set-a1',
        exerciseId: 'ex-bench-a',
      ),
    );
    await repo.recordSet(
      id,
      RecordedSet(
        exerciseKey: 'bench_press',
        setIndex: 1,
        reps: 10,
        loadKg: 30,
        at: at.add(const Duration(minutes: 4)),
        plannedSetId: 'set-b1',
        exerciseId: 'ex-bench-b',
      ),
    );
    await reopen();
    final active = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(active.recorded.map((s) => s.plannedSetId), ['set-a1', 'set-b1']);
    expect(active.recorded.map((s) => s.exerciseId), ['ex-bench-a', 'ex-bench-b']);
    expect(active.recorded.map((s) => s.reps), [8, 10]);
  });

  test('double start and another live workout are busy', () async {
    final t = _template();
    final first = repo.startStrengthSession(t);
    final second = repo.startStrengthSession(t);
    final results = await Future.wait([
      first.then<Object>((id) => id, onError: (Object e) => e),
      second.then<Object>((id) => id, onError: (Object e) => e),
    ]);
    expect(results.whereType<String>(), hasLength(1));
    expect(results.whereType<WorkoutBusy>(), hasLength(1));
    expect(await LocalDb.liveSessions(), hasLength(1));

    await repo.finishStrengthSession(results.whereType<String>().single);
    await app.startWorkout(type: 'run', workoutId: 'run-live');
    await expectLater(repo.startStrengthSession(t), throwsA(isA<WorkoutBusy>()));
    expect(app.activeWorkout?.workoutId, 'run-live');
  });

  test('a persistence rollback never activates a live runtime', () async {
    final db = await LocalDb.instance;
    await db.execute(
      'ALTER TABLE openband_strength_session RENAME TO openband_strength_hidden',
    );
    await expectLater(repo.startStrengthSession(_template()), throwsA(isA<Object>()));
    expect(app.activeWorkout, isNull);
    expect(await LocalDb.liveSessions(), isEmpty);
    expect(
      await db.query('sqlite_master', where: "name = 'openband_strength_session'"),
      isEmpty,
    );
    await db.execute(
      'ALTER TABLE openband_strength_hidden RENAME TO openband_strength_session',
    );
    final id = await repo.startStrengthSession(_template());
    expect(app.activeWorkout?.workoutId, id);
    expect(await LocalDb.liveSessions(), hasLength(1));
  });

  test('set write failure retries without duplicating identity', () async {
    final id = await repo.startStrengthSession(_template());
    final set = RecordedSet(
      exerciseKey: 'bench_press',
      setIndex: 1,
      reps: 8,
      loadKg: 40,
      at: DateTime(2026, 9, 15, 18),
      plannedSetId: 'set-a1',
      exerciseId: 'ex-bench-a',
    );
    final db = await LocalDb.instance;
    await db.execute('ALTER TABLE strength_set RENAME TO strength_set_hidden');
    await expectLater(repo.recordSet(id, set), throwsA(isA<Object>()));
    await db.execute('ALTER TABLE strength_set_hidden RENAME TO strength_set');
    await repo.recordSet(id, set);
    await repo.recordSet(id, set);
    expect(await LocalDb.strengthSets(id), hasLength(1));
    final active = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(active.recorded, hasLength(1));
    expect(active.recorded.single.plannedSetId, 'set-a1');
  });

  test('finish stops resume but retains the original plan and sets', () async {
    final id = await repo.startStrengthSession(_template());
    await repo.recordSet(
      id,
      RecordedSet(
        exerciseKey: 'bench_press',
        setIndex: 1,
        reps: 8,
        loadKg: 40,
        at: DateTime(2026, 9, 15, 18),
        plannedSetId: 'set-a1',
        exerciseId: 'ex-bench-a',
      ),
    );
    await repo.finishStrengthSession(id);
    expect(app.activeWorkout, isNull);
    expect(await repo.readActiveStrengthSession(), isA<NoActiveStrength>());
    final snap = await LocalDb.openBandStrengthSession(id);
    expect(snap, isNotNull);
    final plan = WorkoutTemplate.fromJson(
      jsonDecode(snap!['plan_json'] as String) as Map<String, dynamic>,
    );
    expect(plan.name, 'Ganzkörper A');
    expect(plan.exercises.first.id, 'ex-bench-a');
    expect(await LocalDb.strengthSets(id), hasLength(1));
    expect((await LocalDb.session(id))?['status'], 'done');
    final next = await repo.startStrengthSession(_template());
    expect(next, isNot(id));
  });

  test('corrupt snapshot is not absence and does not invent a plan', () async {
    await LocalDb.putSession({
      'id': 'bad-live',
      'start_ts': 1770000000,
      'end_ts': null,
      'type': 'weight_training',
      'status': 'live',
      'source': 'manual',
      'created_at': 1770000000000,
    });
    final db = await LocalDb.instance;
    await db.insert('openband_strength_session', {
      'session_id': 'bad-live',
      'template_id': 'tpl-a',
      'template_version': 1,
      'plan_json': '{',
      'skipped_json': '[]',
      'added_json': '[]',
      'created_at': 1770000000000,
    });
    final read = await repo.readActiveStrengthSession();
    expect(read, isA<CorruptActiveStrength>());
    expect((read as CorruptActiveStrength).sessionId, 'bad-live');
    await expectLater(
      repo.startStrengthSession(_template()),
      throwsA(isA<WorkoutBusy>()),
    );
  });

  test('rest countdown uses stored set time and the planned rest', () async {
    final id = await repo.startStrengthSession(_template());
    final at = DateTime(2026, 9, 15, 18, 0, 0);
    await repo.recordSet(
      id,
      RecordedSet(
        exerciseKey: 'bench_press',
        setIndex: 1,
        reps: 8,
        loadKg: 40,
        at: at,
        plannedSetId: 'set-a1',
        exerciseId: 'ex-bench-a',
      ),
    );
    await repo.skipPlannedSet(id, 'set-a2');
    await repo.addPlannedSet(
      id,
      const PlannedExercise(
        id: 'ex-bench-a',
        exerciseKey: 'bench_press',
        name: 'Bank A',
        sets: [],
      ),
      const PlannedSet(id: 'set-a3', reps: 6, loadKg: 45, restSec: 75),
    );
    await reopen();
    final active = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(active.restUntil(), at.add(const Duration(seconds: 90)));
    expect(active.recorded.single.at, at);
    expect(active.skippedPlannedSetIds, {'set-a2'});
    expect(active.added.single.sets.single.id, 'set-a3');
  });

  test('foreign session and set ids are rejected; same-id retry stays a no-op',
      () async {
    final id = await repo.startStrengthSession(_template());
    final at = DateTime(2026, 9, 15, 18);
    await app.startWorkout(type: 'run', workoutId: 'run-live');
    expect(await LocalDb.liveSessions(), hasLength(1));
    expect((await LocalDb.liveSessions()).single['id'], id);
    await expectLater(
      repo.recordSet('run-live', _setA1(at)),
      throwsA(isA<StateError>()),
    );

    await expectLater(
      repo.recordSet(
        id,
        RecordedSet(
          exerciseKey: 'bench_press',
          setIndex: 1,
          reps: 8,
          at: at,
          plannedSetId: 'not-on-plan',
          exerciseId: 'ex-bench-a',
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(repo.skipPlannedSet(id, 'nope'), throwsA(isA<ArgumentError>()));
    await expectLater(repo.skipRest('run-live'), throwsA(isA<StateError>()));
    await expectLater(
      repo.finishStrengthSession('run-live'),
      throwsA(isA<StateError>()),
    );
    await repo.recordSet(id, _setA1(at));
    await repo.recordSet(id, _setA1(at));
    expect(await LocalDb.strengthSets(id), hasLength(1));
  });

  test('skip and add serialize inside the live transaction', () async {
    final id = await repo.startStrengthSession(_template());
    await Future.wait([
      repo.skipPlannedSet(id, 'set-a2'),
      repo.skipPlannedSet(id, 'set-b1'),
    ]);
    await Future.wait([
      repo.addPlannedSet(
        id,
        const PlannedExercise(
          id: 'ex-bench-a',
          exerciseKey: 'bench_press',
          name: 'Bank A',
          sets: [],
        ),
        const PlannedSet(id: 'set-a3', reps: 6, loadKg: 45, restSec: 75),
      ),
      repo.addPlannedSet(
        id,
        const PlannedExercise(
          id: 'ex-bench-b',
          exerciseKey: 'bench_press',
          name: 'Bank B',
          sets: [],
        ),
        const PlannedSet(id: 'set-b2', reps: 8, loadKg: 32.5, restSec: 60),
      ),
    ]);
    final active =
        await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(active.skippedPlannedSetIds, {'set-a2', 'set-b1'});
    expect(
      active.added.expand((e) => e.sets).map((s) => s.id).toSet(),
      {'set-a3', 'set-b2'},
    );
    await expectLater(
      repo.addPlannedSet(
        id,
        const PlannedExercise(
          id: 'ex-bench-a',
          exerciseKey: 'bench_press',
          name: 'Bank A',
          sets: [],
        ),
        const PlannedSet(id: 'set-a3', reps: 6, loadKg: 45, restSec: 75),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a failed snapshot update does not keep a partial skip', () async {
    final id = await repo.startStrengthSession(_template());
    final db = await LocalDb.instance;
    await db.execute('''
      CREATE TRIGGER strength_skip_boom
      BEFORE UPDATE ON openband_strength_session
      BEGIN
        SELECT RAISE(ABORT, 'boom');
      END
    ''');
    await expectLater(repo.skipPlannedSet(id, 'set-a2'), throwsA(isA<Object>()));
    expect(
      (await LocalDb.openBandStrengthSession(id))!['skipped_json'],
      '[]',
    );
    await db.execute('DROP TRIGGER strength_skip_boom');
    await repo.skipPlannedSet(id, 'set-a2');
    expect(
      jsonDecode((await LocalDb.openBandStrengthSession(id))!['skipped_json'] as String),
      ['set-a2'],
    );
  });

  test('corrupt skip, add, and recorded rows are Corrupt, not empty success',
      () async {
    await LocalDb.putSession({
      'id': 'bad-lists',
      'start_ts': 1770000000,
      'end_ts': null,
      'type': 'weight_training',
      'status': 'live',
      'source': 'manual',
      'created_at': 1770000000000,
    });
    final db = await LocalDb.instance;
    await db.insert('openband_strength_session', {
      'session_id': 'bad-lists',
      'template_id': 'tpl-a',
      'template_version': 1,
      'plan_json': jsonEncode(_template().toJson()),
      'skipped_json': '{',
      'added_json': '[]',
      'created_at': 1770000000000,
    });
    expect(await repo.readActiveStrengthSession(), isA<CorruptActiveStrength>());

    await db.update(
      'openband_strength_session',
      {'skipped_json': '[]', 'added_json': '{'},
      where: 'session_id = ?',
      whereArgs: ['bad-lists'],
    );
    expect(await repo.readActiveStrengthSession(), isA<CorruptActiveStrength>());

    await db.update(
      'openband_strength_session',
      {'added_json': '[]'},
      where: 'session_id = ?',
      whereArgs: ['bad-lists'],
    );
    await db.insert('strength_set', {
      'session_id': 'bad-lists',
      'seq': 0,
      'exercise_key': 'bench_press',
      'set_index': 1,
      'reps': 8,
      'at_ts': null,
      'note': '',
    });
    final missingAt = await repo.readActiveStrengthSession();
    expect(missingAt, isA<CorruptActiveStrength>());
    expect((missingAt as CorruptActiveStrength).sessionId, 'bad-lists');
  });

  test('skip rest and +30 persist across reopen from stored rest_until_ts',
      () async {
    final id = await repo.startStrengthSession(_template());
    final at = DateTime(2026, 9, 15, 18, 0, 0);
    await repo.recordSet(id, _setA1(at));
    var active =
        await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(active.restUntil(), at.add(const Duration(seconds: 90)));
    await repo.extendRest(id);
    await reopen();
    active = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(active.restUntil(), at.add(const Duration(seconds: 120)));
    final nowish = DateTime.now();
    expect(active.restUntil()!.isBefore(nowish.subtract(const Duration(days: 1))),
        isTrue);
    await repo.skipRest(id);
    await reopen();
    active = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(active.restUntil(), isNull);
  });

  test('legacy weight_training without a snapshot is a resume route, not Corrupt',
      () async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await LocalDb.putSession({
      'id': 'legacy-wt',
      'start_ts': nowSec - 60,
      'end_ts': null,
      'type': 'weight_training',
      'status': 'live',
      'source': 'manual',
      'created_at': (nowSec - 60) * 1000,
    });
    final read = await repo.readActiveStrengthSession();
    expect(read, isA<LegacyActiveStrength>());
    expect((read as LegacyActiveStrength).sessionId, 'legacy-wt');
    await expectLater(
      repo.startStrengthSession(_template()),
      throwsA(isA<WorkoutBusy>()),
    );
    await app.startWorkout(type: 'run', workoutId: 'second-live');
    expect(await LocalDb.liveSessions(), hasLength(1));
    expect((await LocalDb.liveSessions()).single['id'], 'legacy-wt');
    await app.adoptLiveSession('legacy-wt');
    expect(app.activeWorkout?.workoutId, 'legacy-wt');
    await app.stopWorkout();
    expect(await repo.readActiveStrengthSession(), isA<NoActiveStrength>());
  });

  test('start, reconcile, and adopt cannot double-arm a durable live row',
      () async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final planJson = jsonEncode(_template().toJson());
    await LocalDb.putSession({
      'id': 'orphan-strength',
      'start_ts': nowSec - 120,
      'end_ts': null,
      'type': 'weight_training',
      'status': 'live',
      'source': 'manual',
      'created_at': (nowSec - 120) * 1000,
    });
    await (await LocalDb.instance).insert('openband_strength_session', {
      'session_id': 'orphan-strength',
      'template_id': 'tpl-a',
      'template_version': 1,
      'plan_json': planJson,
      'skipped_json': '[]',
      'added_json': '[]',
      'created_at': (nowSec - 120) * 1000,
    });

    final reconcile = app.debugReconcileOrphanedLiveWorkout();
    final legacyStart = app.startWorkout(type: 'run', workoutId: 'run-during');
    final adopt = app.adoptLiveSession('orphan-strength');
    final strengthStart = repo.startStrengthSession(_template());
    final results = await Future.wait([
      reconcile.then<Object>((_) => 'reconcile'),
      legacyStart.then<Object>((_) => 'start'),
      adopt.then<Object>((_) => 'adopt', onError: (Object e) => e),
      strengthStart.then<Object>((id) => id, onError: (Object e) => e),
    ]);
    expect(await LocalDb.liveSessions(), hasLength(1));
    expect((await LocalDb.liveSessions()).single['id'], 'orphan-strength');
    expect(app.activeWorkout?.workoutId, 'orphan-strength');
    expect(results.whereType<WorkoutBusy>(), isNotEmpty);
    await expectLater(
      repo.startStrengthSession(_template()),
      throwsA(isA<WorkoutBusy>()),
    );
  });

  test('strength older than 6h resumes with wall-clock elapsed, not invented effort',
      () async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final startSec = nowSec - 7 * 3600;
    await LocalDb.putSession({
      'id': 'old-strength',
      'start_ts': startSec,
      'end_ts': null,
      'type': 'weight_training',
      'status': 'live',
      'source': 'manual',
      'created_at': startSec * 1000,
    });
    await (await LocalDb.instance).insert('openband_strength_session', {
      'session_id': 'old-strength',
      'template_id': 'tpl-a',
      'template_version': 1,
      'plan_json': jsonEncode(_template().toJson()),
      'skipped_json': '[]',
      'added_json': '[]',
      'created_at': startSec * 1000,
    });
    await app.debugReconcileOrphanedLiveWorkout();
    expect(app.activeWorkout?.workoutId, 'old-strength');
    expect(app.activeWorkout?.caloriesOrNull, isNull);
    expect(app.activeWorkout?.hrCoveredSec, isNull);
    app.debugTickWorkout();
    expect(app.activeWorkout?.elapsed.inMinutes, greaterThanOrEqualTo(6 * 60));
    expect(app.activeWorkout?.caloriesOrNull, isNull);
    expect(app.activeWorkout?.hrCoveredSec, isNull);
    await app.stopWorkout();
    final row = await LocalDb.session('old-strength');
    expect(row?['status'], 'done');
    expect((row?['duration_min'] as num?)?.toInt(), greaterThanOrEqualTo(6 * 60));
    expect(row?['calories'], isNull);
    expect(row?['max_hr'], isNull);
    expect(row?['hr_covered_sec'], isNull);
  });

  test('deleteDays removes the strength snapshot with its session', () async {
    final id = await repo.startStrengthSession(_template());
    final at = DateTime(2026, 9, 15, 18);
    await repo.recordSet(id, _setA1(at));
    await repo.finishStrengthSession(id);
    final startTs = (await LocalDb.session(id))!['start_ts'] as int;
    final day = dayLabelOf(
      DateTime.fromMillisecondsSinceEpoch(startTs * 1000),
    );
    await LocalDb.deleteDays({day});
    expect(await LocalDb.openBandStrengthSession(id), isNull);
    expect(await LocalDb.strengthSets(id), isEmpty);
    expect(await LocalDb.session(id), isNull);
  });

  test('Start finalizes a stale live run then arms the requested workout',
      () async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await LocalDb.putSession({
      'id': 'stale-run',
      'start_ts': nowSec - 7 * 3600,
      'end_ts': null,
      'type': 'run',
      'status': 'live',
      'source': 'manual',
      'created_at': (nowSec - 7 * 3600) * 1000,
    });
    await app.startWorkout(type: 'run', workoutId: 'fresh-run');
    expect(app.activeWorkout?.workoutId, 'fresh-run');
    expect(await LocalDb.liveSessions(), hasLength(1));
    expect((await LocalDb.liveSessions()).single['id'], 'fresh-run');
    final stale = await LocalDb.session('stale-run');
    expect(stale?['status'], 'done');
    expect(stale?['end_ts_fabricated'], 1);
  });

  test('Start resumes a recent live run instead of inserting a second', () async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await LocalDb.putSession({
      'id': 'recent-run',
      'start_ts': nowSec - 60,
      'end_ts': null,
      'type': 'run',
      'status': 'live',
      'source': 'manual',
      'created_at': (nowSec - 60) * 1000,
    });
    await app.startWorkout(type: 'run', workoutId: 'fresh-run');
    expect(app.activeWorkout?.workoutId, 'recent-run');
    expect(await LocalDb.liveSessions(), hasLength(1));
    expect((await LocalDb.liveSessions()).single['id'], 'recent-run');
  });

  test('colliding Start taps serialize to one live row', () async {
    final first = app.startWorkout(type: 'run', workoutId: 'start-a');
    final second = app.startWorkout(type: 'run', workoutId: 'start-b');
    await Future.wait([first, second]);
    expect(await LocalDb.liveSessions(), hasLength(1));
    final liveId = (await LocalDb.liveSessions()).single['id'];
    expect(liveId, anyOf('start-a', 'start-b'));
    expect(app.activeWorkout?.workoutId, liveId);
  });

  test('a failed Start write does not arm a live engine', () async {
    final db = await LocalDb.instance;
    await db.execute('''
      CREATE TRIGGER start_session_boom
      BEFORE INSERT ON sessions
      BEGIN
        SELECT RAISE(ABORT, 'boom');
      END
    ''');
    try {
      await expectLater(
        app.startWorkout(type: 'run', workoutId: 'will-fail'),
        throwsA(isA<Object>()),
      );
      expect(app.activeWorkout, isNull);
      expect(await LocalDb.liveSessions(), isEmpty);
    } finally {
      await db.execute('DROP TRIGGER IF EXISTS start_session_boom');
    }
    await app.startWorkout(type: 'run', workoutId: 'after-fail');
    expect(app.activeWorkout?.workoutId, 'after-fail');
  });

  test('Start still arms after a concurrent reconcile finalizes a stale run',
      () async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await LocalDb.putSession({
      'id': 'stale-during-reconcile',
      'start_ts': nowSec - 7 * 3600,
      'end_ts': null,
      'type': 'other',
      'status': 'live',
      'source': 'manual',
      'created_at': (nowSec - 7 * 3600) * 1000,
    });
    final reconcile = app.debugReconcileOrphanedLiveWorkout();
    final start = app.startWorkout(type: 'run', workoutId: 'after-stale');
    await Future.wait([reconcile, start]);
    expect(app.activeWorkout?.workoutId, 'after-stale');
    expect((await LocalDb.liveSessions()).single['id'], 'after-stale');
    expect((await LocalDb.session('stale-during-reconcile'))?['status'], 'done');
  });

  test('template start finalizes a stale run then arms the strength snapshot',
      () async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await LocalDb.putSession({
      'id': 'stale-other',
      'start_ts': nowSec - 7 * 3600,
      'end_ts': null,
      'type': 'other',
      'status': 'live',
      'source': 'manual',
      'created_at': (nowSec - 7 * 3600) * 1000,
    });
    final id = await repo.startStrengthSession(_template());
    expect(app.activeWorkout?.workoutId, id);
    expect(id, isNot('stale-other'));
    expect(await LocalDb.liveSessions(), hasLength(1));
    expect((await LocalDb.liveSessions()).single['id'], id);
    expect(await LocalDb.openBandStrengthSession(id), isNotNull);
    final stale = await LocalDb.session('stale-other');
    expect(stale?['status'], 'done');
    expect(stale?['end_ts_fabricated'], 1);
    final active =
        await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(active.sessionId, id);
    expect(active.plan.name, 'Ganzkörper A');
  });

  test('template start refuses a recent live run after resuming it', () async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await LocalDb.putSession({
      'id': 'recent-other',
      'start_ts': nowSec - 90,
      'end_ts': null,
      'type': 'run',
      'status': 'live',
      'source': 'manual',
      'created_at': (nowSec - 90) * 1000,
    });
    await expectLater(
      repo.startStrengthSession(_template()),
      throwsA(isA<WorkoutBusy>()),
    );
    expect(app.activeWorkout?.workoutId, 'recent-other');
    expect(await LocalDb.liveSessions(), hasLength(1));
    expect((await LocalDb.liveSessions()).single['id'], 'recent-other');
    expect(await LocalDb.openBandStrengthSession('recent-other'), isNull);
  });

  test('template start refuses a live strength session and keeps its plan',
      () async {
    final first = await repo.startStrengthSession(_template());
    await repo.recordSet(first, _setA1(DateTime(2026, 9, 15, 18)));
    await expectLater(
      repo.startStrengthSession(_template(name: 'Zweites')),
      throwsA(isA<WorkoutBusy>()),
    );
    expect(app.activeWorkout?.workoutId, first);
    expect(await LocalDb.liveSessions(), hasLength(1));
    final active =
        await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(active.sessionId, first);
    expect(active.plan.name, 'Ganzkörper A');
    expect(active.recorded.single.plannedSetId, 'set-a1');
  });

  test('colliding template starts with a stale run serialize to one strength live',
      () async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await LocalDb.putSession({
      'id': 'stale-for-collide',
      'start_ts': nowSec - 8 * 3600,
      'end_ts': null,
      'type': 'run',
      'status': 'live',
      'source': 'manual',
      'created_at': (nowSec - 8 * 3600) * 1000,
    });
    final t = _template();
    final results = await Future.wait([
      repo.startStrengthSession(t).then<Object>((id) => id, onError: (Object e) => e),
      repo.startStrengthSession(t).then<Object>((id) => id, onError: (Object e) => e),
    ]);
    expect(results.whereType<String>(), hasLength(1));
    expect(results.whereType<WorkoutBusy>(), hasLength(1));
    final id = results.whereType<String>().single;
    expect(await LocalDb.liveSessions(), hasLength(1));
    expect((await LocalDb.liveSessions()).single['id'], id);
    expect(app.activeWorkout?.workoutId, id);
    expect(await LocalDb.openBandStrengthSession(id), isNotNull);
    expect((await LocalDb.session('stale-for-collide'))?['status'], 'done');
  });

  test('persist then dispose throws and leaves the live row for next launch',
      () async {
    app.debugAfterWorkoutPersist = () async {
      app.dispose();
    };
    await expectLater(
      repo.startStrengthSession(_template()),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Einheit konnte nicht gestartet werden.',
        ),
      ),
    );
    expect(app.activeWorkout, isNull);
    final live = await LocalDb.liveSessions();
    expect(live, hasLength(1));
    final id = live.single['id'] as String;
    expect(await LocalDb.openBandStrengthSession(id), isNotNull);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    app = AppState.forTesting();
    repo = LocalOpenBandRepository(app);
    await app.debugReconcileOrphanedLiveWorkout();
    expect(app.activeWorkout?.workoutId, id);
  });

  test('Start persist then dispose throws and keeps the durable live row',
      () async {
    app.debugAfterWorkoutPersist = () async {
      app.dispose();
    };
    await expectLater(
      app.startWorkout(type: 'run', workoutId: 'start-disposed'),
      throwsA(isA<StateError>()),
    );
    expect(app.activeWorkout, isNull);
    expect(await LocalDb.liveSessions(), hasLength(1));
    expect((await LocalDb.liveSessions()).single['id'], 'start-disposed');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    app = AppState.forTesting();
    repo = LocalOpenBandRepository(app);
  });

  test('adopt after persist-await throws when disposed and does not arm',
      () async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await LocalDb.putSession({
      'id': 'adopt-me',
      'start_ts': nowSec - 30,
      'end_ts': null,
      'type': 'run',
      'status': 'live',
      'source': 'manual',
      'created_at': (nowSec - 30) * 1000,
    });
    app.debugAfterWorkoutPersist = () async {
      app.dispose();
    };
    await expectLater(
      app.adoptLiveSession('adopt-me'),
      throwsA(isA<StateError>()),
    );
    expect(app.activeWorkout, isNull);
    expect((await LocalDb.session('adopt-me'))?['status'], 'live');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    app = AppState.forTesting();
    repo = LocalOpenBandRepository(app);
  });

  test('resumed LiveWorkoutState pins the same trainingZones as a fresh start',
      () async {
    app.user = {'birth_date': '${DateTime.now().year - 31}-12-31'};
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _seedLiveStrength(id: 'zoned-strength', startSec: nowSec - 120);
    await app.debugReconcileOrphanedLiveWorkout();
    final resumed = app.activeWorkout!;
    expect(resumed.zoneSet, isNotNull);
    expect(resumed.zoneSet!.source, 'tanaka');
    await app.stopWorkout();
    await app.startWorkout(type: 'run', workoutId: 'fresh-zoned');
    expect(app.activeWorkout?.zoneSet?.source, resumed.zoneSet!.source);
    expect(app.activeWorkout?.zoneSet?.maxHr, resumed.zoneSet!.maxHr);
  });

  test('seven-hour wall session persists partial HR coverage, not invented samples',
      () async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final startSec = nowSec - 7 * 3600;
    await _seedLiveStrength(id: 'covered-strength', startSec: startSec);
    await app.debugReconcileOrphanedLiveWorkout();
    final w = app.activeWorkout!;
    expect(w.hrCoveredSec, isNull);
    w.elapsed = const Duration(hours: 7);
    w.accrueHr(140);
    expect(w.hrCoveredSec, isNull);
    w.elapsed = const Duration(hours: 7, seconds: 3);
    w.accrueHr(142);
    expect(w.hrCoveredSec, 3);
    await app.stopWorkout();
    final row = await LocalDb.session('covered-strength');
    expect(row?['status'], 'done');
    expect((row?['start_ts'] as num?)?.toInt(), startSec);
    expect((row?['end_ts'] as num?)?.toInt(), greaterThan(startSec));
    expect((row?['duration_min'] as num?)?.toInt(), greaterThanOrEqualTo(6 * 60));
    expect((row?['hr_covered_sec'] as num?)?.toInt(), 3);
    expect(row?['calories'], isNull);
    final detail = await repo.readSessionDetail('covered-strength');
    expect(detail, isNotNull);
    expect(detail!.durationSec, greaterThanOrEqualTo(6 * 3600));
    expect(detail.hrCoveredSec, 3);
    expect(detail.kcal, isNull);
  });

  test(
    'label edit and same-window save keep billed coverage; a retime does not',
    () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final start = nowSec - 3 * 3600;
      final end = start + 1800;
      await LocalDb.putSession({
        'id': 'edit-covered',
        'start_ts': start,
        'end_ts': end,
        'type': 'run',
        'status': 'done',
        'duration_min': 30,
        'hr_covered_sec': 180,
        'source': 'manual',
        'created_at': start * 1000,
      });
      await LocalDb.setSessionType('edit-covered', 'cycling');
      expect(
        (await LocalDb.session('edit-covered'))?['hr_covered_sec'],
        180,
      );

      final workouts = LocalRepositoryImpl(
        getProfileMap: () => {
          'birth_date': '${DateTime.now().year - 31}-12-31',
          'weight_kg': 75.0,
          'height_cm': 180.0,
          'sex': 'm',
          'resting_hr': 55,
        },
      );
      await workouts.setWorkoutWindow(
        'edit-covered',
        startTs: start,
        endTs: end,
      );
      expect(
        (await LocalDb.session('edit-covered'))?['hr_covered_sec'],
        180,
      );
      final kept = await repo.readSessionDetail('edit-covered');
      expect(kept, isNotNull);
      expect(kept!.hrCoveredSec, 180);
      expect(kept.durationSec, end - start);

      final retimeStart = nowSec - 6 * 3600;
      final retimeEnd = retimeStart + 1800;
      await LocalDb.putSession({
        'id': 'retime-covered',
        'start_ts': retimeStart,
        'end_ts': retimeEnd,
        'type': 'run',
        'status': 'done',
        'duration_min': 30,
        'hr_covered_sec': 180,
        'source': 'manual',
        'created_at': retimeStart * 1000,
      });
      await workouts.setWorkoutWindow(
        'retime-covered',
        startTs: retimeStart,
        endTs: retimeEnd + 600,
      );
      final moved = await LocalDb.session('retime-covered');
      expect(moved?['hr_covered_sec'], isNull);
      expect((moved?['duration_min'] as num?)?.toInt(), 40);
      expect((moved?['start_ts'] as num?)?.toInt(), retimeStart);
      expect((moved?['end_ts'] as num?)?.toInt(), retimeEnd + 600);
      final unknown = await repo.readSessionDetail('retime-covered');
      expect(unknown, isNotNull);
      expect(unknown!.hrCoveredSec, isNull);
      expect(unknown.durationSec, 2400);
    },
  );

  test(
    'readPreviousStrengthSets maps exact prior exerciseKey+setIndex only',
    () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final older = nowSec - 3 * 86400;
      final prior = nowSec - 86400;
      final priorAt = DateTime.fromMillisecondsSinceEpoch(prior * 1000);
      await _seedDoneStrength(
        id: 'older-bench',
        startSec: older,
        sets: [
          {
            'exercise_key': 'bench_press',
            'set_index': 1,
            'reps': 8,
            'load_kg': 20,
            'at_ts': older + 60,
          },
        ],
      );
      await _seedDoneStrength(
        id: 'prior-match',
        startSec: prior,
        sets: [
          {
            'exercise_key': 'bench_press',
            'set_index': 1,
            'reps': 8,
            'load_kg': 37.5,
            'at_ts': prior + 60,
            'planned_set_id': 'hist-bp-1',
          },
          {
            'exercise_key': 'bench_press',
            'set_index': 2,
            'reps': 8,
            'at_ts': prior + 120,
          },
          {
            'exercise_key': 'plank',
            'set_index': 1,
            'hold_sec': 40,
            'at_ts': prior + 180,
          },
          {
            'exercise_key': 'row',
            'set_index': 1,
            'hold_sec': 30,
            'at_ts': prior + 240,
          },
        ],
      );
      await _seedDoneStrength(
        id: 'alias-bench',
        startSec: prior + 10,
        sets: [
          {
            'exercise_key': 'bench',
            'set_index': 1,
            'reps': 8,
            'load_kg': 99,
            'at_ts': prior + 300,
          },
        ],
      );

      final template = WorkoutTemplate(
        id: 'tpl-hist',
        name: 'Historie',
        version: 1,
        exercises: [
          PlannedExercise(
            id: 'ex-bench',
            exerciseKey: 'bench_press',
            name: 'Bank',
            sets: const [
              PlannedSet(id: 'set-1', reps: 8, loadKg: 40, restSec: 90),
              PlannedSet(id: 'set-2', reps: 8, loadKg: 40, restSec: 90),
              PlannedSet(id: 'set-3', reps: 8, loadKg: 40, restSec: 90),
            ],
          ),
          const PlannedExercise(
            id: 'ex-plank',
            exerciseKey: 'plank',
            name: 'Plank',
            sets: [PlannedSet(id: 'plank-1', seconds: 45, restSec: 60)],
          ),
          const PlannedExercise(
            id: 'ex-row',
            exerciseKey: 'row',
            name: 'Rudern',
            sets: [PlannedSet(id: 'row-1', reps: 10, loadKg: 30, restSec: 90)],
          ),
        ],
        updatedAt: DateTime(2026, 9, 1, 12),
      );
      final id = await repo.startStrengthSession(template);
      final startTs = ((await LocalDb.session(id))!['start_ts'] as num).toInt();
      await _seedDoneStrength(
        id: 'future-bench',
        startSec: startTs + 3600,
        sets: [
          {
            'exercise_key': 'bench_press',
            'set_index': 1,
            'reps': 8,
            'load_kg': 100,
            'at_ts': startTs + 3660,
          },
        ],
      );
      await repo.recordSet(
        id,
        RecordedSet(
          exerciseKey: 'bench_press',
          setIndex: 1,
          reps: 8,
          loadKg: 50,
          at: DateTime.fromMillisecondsSinceEpoch(startTs * 1000),
          plannedSetId: 'set-1',
          exerciseId: 'ex-bench',
        ),
      );

      final prev = await repo.readPreviousStrengthSets(id);
      expect(prev.keys.toSet(), {'set-1', 'set-2', 'plank-1'});
      expect(prev['set-1']!.loadKg, 37.5);
      expect(prev['set-1']!.reps, 8);
      expect(prev['set-1']!.at, priorAt.add(const Duration(seconds: 60)));
      expect(prev['set-1']!.plannedSetId, 'hist-bp-1');
      expect(prev['set-2']!.loadKg, isNull);
      expect(prev['set-2']!.reps, 8);
      expect(prev['plank-1']!.seconds, 40);
      expect(prev['plank-1']!.reps, isNull);
      expect(prev.containsKey('set-3'), isFalse);
      expect(prev.containsKey('row-1'), isFalse);

      await repo.addPlannedSet(
        id,
        PlannedExercise(
          id: 'ex-bench',
          exerciseKey: 'bench_press',
          name: 'Bank',
          sets: const [PlannedSet(id: 'set-4', reps: 8, loadKg: 40)],
        ),
        const PlannedSet(id: 'set-4', reps: 8, loadKg: 40),
      );
      final withAdded = await repo.readPreviousStrengthSets(id);
      expect(withAdded.containsKey('set-4'), isFalse);
      expect(withAdded['set-1']!.loadKg, 37.5);

      await expectLater(
        repo.readPreviousStrengthSets('no-such-session'),
        throwsA(isA<ArgumentError>()),
      );
      await (await LocalDb.instance).update(
        'openband_strength_session',
        {'plan_json': '{}'},
        where: 'session_id = ?',
        whereArgs: [id],
      );
      await expectLater(
        repo.readPreviousStrengthSets(id),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'two bench blocks keep 40 then 30 by exerciseId; copies omit unless unique',
    () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final prior = nowSec - 86400;
      await _seedDoneStrength(
        id: 'prior-two-bench',
        startSec: prior,
        sets: [
          {
            'exercise_key': 'bench_press',
            'set_index': 1,
            'reps': 8,
            'load_kg': 40,
            'at_ts': prior + 60,
            'exercise_id': 'ex-bench-a',
            'planned_set_id': 'set-a1',
          },
          {
            'exercise_key': 'bench_press',
            'set_index': 1,
            'reps': 10,
            'load_kg': 30,
            'at_ts': prior + 120,
            'exercise_id': 'ex-bench-b',
            'planned_set_id': 'set-b1',
          },
          {
            'exercise_key': 'row',
            'set_index': 1,
            'reps': 10,
            'load_kg': 15,
            'at_ts': prior + 180,
            'exercise_id': 'ex-row-old',
          },
          {
            'exercise_key': 'squat',
            'set_index': 1,
            'reps': 8,
            'load_kg': 40,
            'at_ts': prior + 200,
          },
          {
            'exercise_key': 'squat',
            'set_index': 1,
            'reps': 8,
            'load_kg': 30,
            'at_ts': prior + 240,
          },
        ],
      );

      final same = await repo.startStrengthSession(_template());
      final samePrev = await repo.readPreviousStrengthSets(same);
      expect(samePrev['set-a1']!.loadKg, 40);
      expect(samePrev['set-b1']!.loadKg, 30);
      expect(samePrev['set-a1']!.at.millisecondsSinceEpoch, (prior + 60) * 1000);
      await repo.finishStrengthSession(same);

      final copied = WorkoutTemplate(
        id: 'tpl-copied',
        name: 'Kopie',
        version: 1,
        exercises: [
          PlannedExercise(
            id: 'ex-bench-a2',
            exerciseKey: 'bench_press',
            name: 'Bank A',
            sets: const [
              PlannedSet(id: 'copy-a1', reps: 8, loadKg: 40, restSec: 90),
            ],
          ),
          PlannedExercise(
            id: 'ex-bench-b2',
            exerciseKey: 'bench_press',
            name: 'Bank B',
            sets: const [
              PlannedSet(id: 'copy-b1', reps: 10, loadKg: 30, restSec: 60),
            ],
          ),
          const PlannedExercise(
            id: 'ex-row-new',
            exerciseKey: 'row',
            name: 'Rudern',
            sets: [PlannedSet(id: 'copy-row', reps: 10, loadKg: 15, restSec: 90)],
          ),
          const PlannedExercise(
            id: 'ex-squat-new',
            exerciseKey: 'squat',
            name: 'Kniebeuge',
            sets: [PlannedSet(id: 'copy-sq', reps: 8, loadKg: 60, restSec: 90)],
          ),
        ],
        updatedAt: DateTime(2026, 9, 1, 12),
      );
      final copyId = await repo.startStrengthSession(copied);
      final copyPrev = await repo.readPreviousStrengthSets(copyId);
      expect(copyPrev.containsKey('copy-a1'), isFalse);
      expect(copyPrev.containsKey('copy-b1'), isFalse);
      expect(copyPrev.containsKey('copy-sq'), isFalse);
      expect(copyPrev['copy-row']!.loadKg, 15);
      expect(copyPrev['copy-row']!.reps, 10);
    },
  );

  test('recorded original load and definition snapshot survive reopen', () async {
    final curl = ExerciseDefinitionSnapshot(
      id: 'curl-custom',
      label: 'Kurzhantel-Curl',
      source: ExerciseDefinitionSource.stored,
      version: 1,
      mode: ExerciseCaptureMode.repetitions,
      equipment: ExerciseEquipmentCategory.dumbbell,
      loadBasis: ExerciseLoadBasis.perDevice,
      deviceCount: 2,
      repetitionBasis: ExerciseRepetitionBasis.perSide,
    );
    final plan = WorkoutTemplate(
      id: 'tpl-curl',
      name: 'Arme',
      version: 1,
      exercises: [
        PlannedExercise(
          id: 'ex-curl',
          exerciseKey: 'curl-custom',
          name: 'Kurzhantel-Curl',
          definition: curl,
          sets: [
            PlannedSet(
              id: 'set-curl-1',
              reps: 8,
              loadKg: 20,
              restSec: 90,
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
    final id = await repo.startStrengthSession(plan);
    await repo.recordSet(
      id,
      RecordedSet(
        exerciseKey: 'curl-custom',
        setIndex: 1,
        reps: 8,
        loadKg: 20,
        at: DateTime(2026, 9, 20, 18),
        plannedSetId: 'set-curl-1',
        exerciseId: 'ex-curl',
        load: OriginalLoadInput(
          value: 10,
          unit: ExerciseLoadUnit.kg,
          basis: ExerciseLoadBasis.perDevice,
          deviceCount: 2,
          repetitionBasis: ExerciseRepetitionBasis.perSide,
        ),
      ),
    );
    await reopen();
    final live = await repo.readActiveStrengthSession() as ActiveStrengthSession;
    expect(live.recorded.single.loadKg, 20);
    expect(live.recorded.single.loadKg! * live.recorded.single.reps!, 160);
    expect(live.recorded.single.load!.value, 10);
    expect(live.recorded.single.load!.basis, ExerciseLoadBasis.perDevice);
    expect(live.recorded.single.load!.deviceCount, 2);
    expect(live.recorded.single.definition!.id, 'curl-custom');
    expect(live.recorded.single.definition!.label, 'Kurzhantel-Curl');
    expect(live.plan.exercises.single.sets.single.loadKg, 20);
    expect(live.plan.exercises.single.sets.single.load!.value, 10);
  });

  test('contradictory recorded total is rejected and precise legacy load stays', () async {
    final id = await repo.startStrengthSession(_template());
    await expectLater(
      repo.recordSet(
        id,
        RecordedSet(
          exerciseKey: 'bench_press',
          setIndex: 1,
          reps: 8,
          loadKg: 10,
          at: DateTime(2026, 9, 20, 18),
          plannedSetId: 'set-a1',
          exerciseId: 'ex-bench-a',
          load: OriginalLoadInput(
            value: 10,
            unit: ExerciseLoadUnit.kg,
            basis: ExerciseLoadBasis.perDevice,
            deviceCount: 2,
          ),
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      (await repo.readActiveStrengthSession() as ActiveStrengthSession).recorded,
      isEmpty,
    );

    await LocalDb.saveStrengthSets('legacy-sess', [
      {
        'exercise_key': 'incline_db_press',
        'set_index': 1,
        'reps': 8,
        'load_kg': 62.55,
        'at_ts': 1770000000,
      },
    ]);
    final rows = await LocalDb.strengthSets('legacy-sess');
    expect(rows.single['load_kg'], 62.55);
    expect(rows.single['load_json'], isNull);
    expect(rows.single['definition_json'], isNull);

    await LocalDb.saveStrengthSets('meta-sess', [
      {
        'exercise_key': 'curl',
        'set_index': 1,
        'reps': 8,
        'load_kg': 20,
        'at_ts': 1770000100,
        'load_json': jsonEncode({
          'value': 10,
          'unit': 'kg',
          'basis': 'perDevice',
          'deviceCount': 2,
        }),
        'definition_json': jsonEncode({
          'id': 'curl',
          'label': 'Curl',
          'source': 'stored',
        }),
      },
    ]);
    final meta = await LocalDb.strengthSets('meta-sess');
    expect(meta.single['load_kg'], 20);
    expect(jsonDecode(meta.single['load_json'] as String)['value'], 10);
    expect(jsonDecode(meta.single['definition_json'] as String)['id'], 'curl');
  });

  test('saveStrengthSets rejects contradictory or malformed metadata atomically', () async {
    await expectLater(
      LocalDb.saveStrengthSets('bad-meta', [
        {
          'exercise_key': 'curl',
          'set_index': 1,
          'reps': 8,
          'load_kg': 10,
          'at_ts': 1,
          'load_json': jsonEncode({
            'value': 10,
            'unit': 'kg',
            'basis': 'perDevice',
            'deviceCount': 2,
          }),
        },
      ]),
      throwsA(isA<FormatException>()),
    );
    expect(await LocalDb.strengthSets('bad-meta'), isEmpty);

    await expectLater(
      LocalDb.saveStrengthSets('malformed-meta', [
        {
          'exercise_key': 'curl',
          'set_index': 1,
          'reps': 8,
          'load_kg': 20,
          'at_ts': 1,
          'load_json': '{',
        },
      ]),
      throwsA(isA<FormatException>()),
    );
    expect(await LocalDb.strengthSets('malformed-meta'), isEmpty);

    await expectLater(
      LocalDb.saveStrengthSets('bad-def', [
        {
          'exercise_key': 'curl',
          'set_index': 1,
          'reps': 8,
          'load_kg': 20,
          'at_ts': 1,
          'definition_json': jsonEncode({
            'id': 'other',
            'label': 'Curl',
            'source': 'stored',
          }),
        },
      ]),
      throwsA(isA<FormatException>()),
    );
    expect(await LocalDb.strengthSets('bad-def'), isEmpty);

    await expectLater(
      LocalDb.saveStrengthSets('mix-meta', [
        {
          'exercise_key': 'incline_db_press',
          'set_index': 1,
          'reps': 8,
          'load_kg': 62.55,
          'at_ts': 1,
        },
        {
          'exercise_key': 'curl',
          'set_index': 2,
          'reps': 8,
          'load_kg': 10,
          'at_ts': 2,
          'load_json': jsonEncode({
            'value': 10,
            'unit': 'kg',
            'basis': 'perDevice',
            'deviceCount': 2,
          }),
        },
      ]),
      throwsA(isA<FormatException>()),
    );
    expect(await LocalDb.strengthSets('mix-meta'), isEmpty);

    await LocalDb.saveStrengthSets('ok-meta', [
      {
        'exercise_key': 'curl',
        'set_index': 1,
        'reps': 8,
        'at_ts': 3,
        'note': 'keep',
        'rpe': 7,
        'load_json': jsonEncode({
          'value': 10,
          'unit': 'kg',
          'basis': 'perDevice',
          'deviceCount': 2,
          'mystery': true,
        }),
        'definition_json': jsonEncode({
          'id': 'curl',
          'label': 'Curl',
          'source': 'stored',
          'copiedFrom': 'import-x',
        }),
      },
    ]);
    final ok = (await LocalDb.strengthSets('ok-meta')).single;
    expect(ok['load_kg'], 20);
    expect(ok['note'], 'keep');
    expect(ok['rpe'], 7);
    expect(jsonDecode(ok['load_json'] as String)['mystery'], isTrue);
    expect(jsonDecode(ok['definition_json'] as String)['copiedFrom'], 'import-x');
  });

  test('saveStrengthSets omitted metadata keeps origin; load contradiction is atomic', () async {
    await LocalDb.saveStrengthSets('re-save', [
      {
        'exercise_key': 'curl',
        'set_index': 1,
        'reps': 8,
        'load_kg': 20,
        'at_ts': 1,
        'note': '',
        'load_json': jsonEncode({
          'value': 10,
          'unit': 'kg',
          'basis': 'perDevice',
          'deviceCount': 2,
        }),
        'definition_json': jsonEncode({
          'id': 'curl',
          'label': 'Curl',
          'source': 'stored',
          'copiedFrom': 'import-x',
        }),
      },
    ]);
    await LocalDb.saveStrengthSets('re-save', [
      {
        'exercise_key': 'curl',
        'set_index': 1,
        'reps': 9,
        'load_kg': 20,
        'at_ts': 1,
        'note': 'updated',
      },
    ]);
    var row = (await LocalDb.strengthSets('re-save')).single;
    expect(row['reps'], 9);
    expect(row['note'], 'updated');
    expect(row['load_kg'], 20);
    expect(jsonDecode(row['load_json'] as String)['deviceCount'], 2);
    expect(jsonDecode(row['definition_json'] as String)['copiedFrom'], 'import-x');

    await expectLater(
      LocalDb.saveStrengthSets('re-save', [
        {
          'exercise_key': 'curl',
          'set_index': 1,
          'reps': 10,
          'load_kg': 10,
          'at_ts': 1,
          'note': 'bad',
        },
      ]),
      throwsA(isA<FormatException>()),
    );
    row = (await LocalDb.strengthSets('re-save')).single;
    expect(row['reps'], 9);
    expect(row['note'], 'updated');
    expect(row['load_kg'], 20);
    expect(jsonDecode(row['load_json'] as String)['value'], 10);
    expect(jsonDecode(row['definition_json'] as String)['id'], 'curl');
  });
}
