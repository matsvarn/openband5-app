import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:openstrap_edge/app.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/live/live_activity.dart';
import 'package:openstrap_edge/openband/g3/screens/training_live.dart';
import 'package:openstrap_edge/openband/g3/screens/training_manual.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ManualWriter extends LocalRepository {
  int? startTs, endTs;
  String? sport;

  @override
  Future<Map<String, dynamic>> logManualWorkout({
    required int startTs,
    required int endTs,
    required String type,
  }) async {
    this.startTs = startTs;
    this.endTs = endTs;
    sport = type;
    return {'workout_id': 'saved-yoga', 'unscored': true, 'hr_samples': 0};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const dbName = 'openband_g3_live_durability_test.db';
  late AppState app;

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
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
  });

  tearDown(() async {
    app.dispose();
    await LocalDb.close();
  });

  test(
    'pause is banked on the live row and freezes HR and zone accrual',
    () async {
      app.user = {'birth_date': '${DateTime.now().year - 30}-01-01'};
      await app.startWorkout(workoutId: 'paused-ride', type: 'cycling');
      final reading = DeviceState()
        ..connection = 'connected'
        ..liveHr = 141
        ..liveHrAt = DateTime.now().millisecondsSinceEpoch;
      app.debugFeedEngineState('ring-A', reading);
      app.debugTickWorkout();
      final before = [...app.activeWorkout!.zoneSeconds];
      final coveredBefore = app.activeWorkout!.hrCoveredSec;
      final strainBefore = app.activeWorkout!.strain;
      await app.setWorkoutPaused(true);
      final row = await LocalDb.session('paused-ride');
      expect(row?['paused_at_ms'], isNotNull);
      expect(app.activeWorkout!.pausedAt, isNotNull);
      app.debugTickWorkout();
      expect(app.activeWorkout!.zoneSeconds, before);
      expect(app.activeWorkout!.hrCoveredSec, coveredBefore);
      expect(app.activeWorkout!.strain, strainBefore);
      await app.setWorkoutPaused(false);
      final resumed = await LocalDb.session('paused-ride');
      expect(resumed?['paused_at_ms'], isNull);
      expect((resumed?['paused_sec'] as num).toInt(), greaterThanOrEqualTo(0));
    },
  );

  test(
    'pause publishes absent HR and a frozen Live Activity clock, then resumes',
    () async {
      const channel = MethodChannel('openstrap/live_activity');
      final updates = <Map<Object?, Object?>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'update') {
              updates.add(call.arguments as Map<Object?, Object?>);
            }
            return null;
          });
      addTearDown(() async {
        await LiveActivity.end();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      await app.startWorkout(workoutId: 'activity-pause', type: 'cycling');
      final reading = DeviceState()
        ..connection = 'connected'
        ..liveHr = 141
        ..liveHrAt = DateTime.now().millisecondsSinceEpoch;
      app.debugFeedEngineState('ring-A', reading);
      app.debugTickWorkout();
      await app.setWorkoutPaused(true);
      final paused = updates.last;
      expect(paused['paused'], true);
      expect(paused['hr'], isNull);
      expect(paused['zone'], isNull);
      final frozen = paused['elapsedSeconds'];
      final workout = app.activeWorkout!;
      expect(
        workout
            .activeElapsed(workout.pausedAt!.add(const Duration(minutes: 3)))
            .inSeconds,
        frozen,
      );
      final covered = workout.hrCoveredSec;
      final zones = [...workout.zoneSeconds];
      final updateCount = updates.length;
      await Future<void>.delayed(const Duration(seconds: 5));
      app.debugTickWorkout();
      expect(updates.length, greaterThan(updateCount));
      expect(updates.last['paused'], true);
      expect(updates.last['elapsedSeconds'], frozen);
      expect(updates.last['hr'], isNull);
      expect(updates.last['zone'], isNull);
      expect(workout.hrCoveredSec, covered);
      expect(workout.zoneSeconds, zones);
      await app.setWorkoutPaused(false);
      expect(updates.last['paused'], false);
      expect(updates.last['elapsedSeconds'], isA<int>());
    },
  );

  test(
    'paused clock remains exact across fractional-second tick boundaries',
    () {
      final start = DateTime.fromMillisecondsSinceEpoch(100_100);
      final pause = DateTime.fromMillisecondsSinceEpoch(130_900);
      final workout = LiveWorkoutState(
        startTime: start,
        targetKcal: 0,
        pausedAt: pause,
        pausedSec: 5,
      );
      expect(workout.activeElapsed(pause).inSeconds, 25);
      expect(
        workout
            .activeElapsed(pause.add(const Duration(milliseconds: 200)))
            .inSeconds,
        25,
      );
      expect(
        workout.activeElapsed(pause.add(const Duration(minutes: 2))).inSeconds,
        25,
      );
    },
  );

  test('a paused row restores its active clock and saved duration', () async {
    final now = DateTime.now();
    final start = now.subtract(const Duration(minutes: 3));
    final pausedAt = now.subtract(const Duration(minutes: 2));
    await LocalDb.putSession({
      'id': 'restored-ride',
      'start_ts': start.millisecondsSinceEpoch ~/ 1000,
      'end_ts': null,
      'type': 'cycling',
      'status': 'live',
      'source': 'manual',
      'paused_sec': 20,
      'paused_at_ms': pausedAt.millisecondsSinceEpoch,
      'created_at': start.millisecondsSinceEpoch,
    });
    await app.debugReconcileOrphanedLiveWorkout();
    final restored = app.activeWorkout!;
    expect(restored.pausedAt, isNotNull);
    expect(
      restored.activeElapsed(DateTime.now()).inSeconds,
      inInclusiveRange(35, 45),
    );
    await app.setWorkoutPaused(false);
    expect(restored.pausedAt, isNull);
    await app.stopWorkout();
    final row = await LocalDb.session('restored-ride');
    expect(row?['status'], 'done');
    expect(row?['duration_min'], 0);
    expect((row?['paused_sec'] as num).toInt(), greaterThanOrEqualTo(140));
  });

  test('discard tears down a live workout without a done row', () async {
    await app.startWorkout(workoutId: 'discard-ride', type: 'cycling');
    expect((await LocalDb.session('discard-ride'))?['status'], 'live');
    await app.deleteWorkout('discard-ride');
    expect(await LocalDb.session('discard-ride'), isNull);
    expect(app.activeWorkout, isNull);
    app.debugTickWorkout();
  });

  testWidgets('manual save returns its id to the Training caller', (
    tester,
  ) async {
    await initializeDateFormatting('de_DE');
    final writer = _ManualWriter();
    app.repo = writer;
    final nav = GlobalKey<NavigatorState>();
    final start = DateTime.now().subtract(const Duration(hours: 2));
    final end = start.add(const Duration(minutes: 40));
    G3ManualSaved? result;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          navigatorKey: nav,
          theme: openBandTheme(Brightness.light),
          home: const Scaffold(body: Text('Training root')),
        ),
      ),
    );
    nav.currentState!
        .push(
          MaterialPageRoute<G3ManualSaved>(
            builder: (_) => G3ManualFlow(
              now: DateTime.now,
              initialStep: 2,
              initialStart: start,
              initialEnd: end,
              initialSpans: const [],
            ),
          ),
        )
        .then((value) => result = value);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Training root'), findsOneWidget);
    expect(result?.id, 'saved-yoga');
    expect(result?.sport, 'yoga');
    expect(writer.startTs, start.millisecondsSinceEpoch ~/ 1000);
    expect(writer.endTs, end.millisecondsSinceEpoch ~/ 1000);
  });

  test('weekly load keeps only the current stored refusal note', () async {
    final repo = LocalOpenBandRepository(app);
    await LocalDb.putBaseline(
      'crossday',
      jsonEncode({
        'built_for_day': '2026-09-29',
        'algo_version': kAlgoVersion,
        'load': {'value': null, 'note': 'need_baseline:have=11,need=14'},
      }),
    );
    final current = await repo.readWeeklyLoad('2026-09-29');
    expect(current.refusalNote, 'need_baseline:have=11,need=14');
    expect(current.daysHave, 11);
    expect(current.daysNeed, 14);
    final other = await repo.readWeeklyLoad('2026-09-28');
    expect(other.refusalNote, isNull);
    expect(other.daysHave, isNull);
  });

  test('confirmed zone minutes survive without trace JSON', () async {
    final start = DateTime(2026, 9, 29, 8);
    await LocalDb.putSession({
      'id': 'zones-no-trace',
      'start_ts': start.millisecondsSinceEpoch ~/ 1000,
      'end_ts':
          start.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000,
      'type': 'running',
      'status': 'done',
      'source': 'manual',
      'zone_min_json': jsonEncode([1, 2, 3, 4, 5]),
      'created_at': start.millisecondsSinceEpoch,
    });
    final activity = (await LocalOpenBandRepository(
      app,
    ).readActivities('2026-09-29')).single;
    expect(activity.zoneMinutes, [1, 2, 3, 4, 5]);
    expect(activity.zoneBasis, isNull);
  });

  testWidgets('unknown live row resumes on finishable G3 screen', (
    tester,
  ) async {
    final start = DateTime.now().subtract(const Duration(minutes: 2));
    app.activeWorkout = LiveWorkoutState(
      startTime: start,
      targetKcal: 300,
      type: 'unmapped_sensor_code',
      workoutId: 'unknown-live',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: openBandTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => resumeLiveSession(
                  context,
                  repository: LocalOpenBandRepository(app),
                ),
                child: const Text('resume'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('resume'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(G3LiveRun), findsOneWidget);
    expect(find.text('Beenden'), findsOneWidget);
  });
}
