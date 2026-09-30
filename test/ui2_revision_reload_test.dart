// A write landed underneath a screen that is already on screen. Does it show?
//
// Nutrition is a pushed Alpin route, not a shell-kept IndexedStack tab.
// The live-tab RevisionReload pin stays on Home / Health / Workout / Wellness.
//
// The test below writes UNDERNEATH a live route and asserts the screen
// updates while keeping the SAME State object. Asserting only that the text
// appears would pass for the same wrong reason switching tabs does — a fresh
// widget reading the database for the first time.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/nutrition_route.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/state/app_state.dart';

/// The rows an import would have written, behind the repo the screen reads.
class _JournalRepo extends LocalRepository {
  Map<String, JournalMetricValue> journal = const {};
  int reads = 0;

  @override
  Future<Map<String, dynamic>> getToday() async => const {};
  @override
  Future<Map<String, JournalMetricValue>> getJournalMetrics(String date) async {
    reads++;
    return journal;
  }

  @override
  Future<JournalDaySnapshot> readJournalDay(String day) async {
    reads++;
    return JournalDaySnapshot(
      day: day,
      metrics: journal,
      metricUpdatedAt: {for (final e in journal.entries) e.key: 1},
      tags: const [],
      note: '',
      journalUpdatedAt: 0,
      fields: kJournalFields,
    );
  }
}

class _RepoSpy implements OpenBandRepository {
  _RepoSpy(this.inner);
  final OpenBandRepository inner;
  int journalReads = 0;
  int mealReads = 0;
  int dayReads = 0;

  @override
  Future<JournalDaySnapshot> readJournalDay(String day) {
    journalReads++;
    return inner.readJournalDay(day);
  }

  @override
  Future<DayMeals> readMeals(String day) {
    mealReads++;
    return inner.readMeals(day);
  }

  @override
  Future<OpenBandDay> readDay(String day) {
    dayReads++;
    return inner.readDay(day);
  }

  @override
  Future<NutritionTargetSnapshot> readNutritionTargets(String day) =>
      inner.readNutritionTargets(day);

  @override
  Future<void> writeJournal(String day, String key, double value) =>
      inner.writeJournal(day, key, value);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _until(WidgetTester t, Finder f, {int n = 60}) async {
  for (var i = 0; i < n && f.evaluate().isEmpty; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump();
  }
}

SyntheticOpenBandRepository _galleryRepo() =>
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
    );

Widget _app({required AppState app, required Widget home}) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: openBandTheme(Brightness.light),
        locale: const Locale('de'),
        home: home,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_revision_reload_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('water logged underneath the live route reaches it', (t) async {
    t.view.physicalSize = const Size(390 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final repo = _JournalRepo()
      ..journal = const {'water_ml': JournalMetricValue(750)};
    app.repo = repo;

    await t.pumpWidget(
      _app(
        app: app,
        home: const OpenBandNutritionRoute(date: '2026-09-15'),
      ),
    );
    await _until(t, find.text('750'));
    expect(find.text('750'), findsOneWidget);

    final before = t.state(find.byType(OpenBandNutritionRoute));

    repo.journal = const {'water_ml': JournalMetricValue(1500)};
    app.bumpInsights();
    await _until(t, find.text('1.500'));

    expect(find.text('1.500'), findsOneWidget);
    expect(
      identical(t.state(find.byType(OpenBandNutritionRoute)), before),
      isTrue,
      reason: 'the screen was remounted — that is the workaround, not the fix',
    );
  });

  testWidgets('a rebuild is not a write', (t) async {
    t.view.physicalSize = const Size(390 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final inner = _galleryRepo();
    await inner.writeJournal('2026-09-15', 'water_ml', 750);
    final repo = _RepoSpy(inner);
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
    );
    addTearDown(controller.dispose);

    await t.pumpWidget(
      _app(
        app: app,
        home: OpenBandNutritionRoute(controller: controller),
      ),
    );
    await _until(t, find.text('750'));
    final journal = repo.journalReads;
    final meals = repo.mealReads;
    final days = repo.dayReads;
    expect(journal, greaterThan(0));

    for (var i = 0; i < 5; i++) {
      app.notifyListeners();
      await t.pump();
    }
    expect(
      repo.journalReads,
      journal,
      reason: 'the screen re-read with nothing having landed',
    );
    expect(
      repo.mealReads,
      meals,
      reason: 'the screen re-read meals with nothing having landed',
    );
    expect(
      repo.dayReads,
      days,
      reason: 'a borrowed controller was refreshed on an AppState tick',
    );
  });

  testWidgets('an AppState replacement rebinds the same owned route', (
    t,
  ) async {
    t.view.physicalSize = const Size(390 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    final firstApp = AppState.forTesting();
    final secondApp = AppState.forTesting();
    addTearDown(firstApp.dispose);
    addTearDown(secondApp.dispose);
    firstApp.repo = _JournalRepo()
      ..journal = const {'water_ml': JournalMetricValue(750)};
    secondApp.repo = _JournalRepo()
      ..journal = const {'water_ml': JournalMetricValue(1500)};

    Widget host(AppState app) => _app(
      app: app,
      home: const OpenBandNutritionRoute(date: '2026-09-15'),
    );

    await t.pumpWidget(host(firstApp));
    await _until(t, find.text('750'));
    final before = t.state(find.byType(OpenBandNutritionRoute));

    await t.pumpWidget(host(secondApp));
    await _until(t, find.text('1.500'));

    expect(find.text('1.500'), findsOneWidget);
    expect(
      identical(t.state(find.byType(OpenBandNutritionRoute)), before),
      isTrue,
      reason:
          'provider replacement remounted the route instead of rebinding it',
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('nutrition ledger written underneath the live route reaches it', (
    t,
  ) async {
    t.view.physicalSize = const Size(390 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    final today = todayLabel();
    await t.runAsync(() async {
      final db = await LocalDb.instance;
      await NutritionDb.put(
        db,
        FoodEntry(
          id: 'external-ledger',
          date: today,
          meal: 'breakfast',
          label: 'Externer Hafer',
          kcal: 310,
          confirmed: true,
        ),
      );
    });

    final app = AppState.forTesting();
    addTearDown(app.dispose);
    app.repo = _JournalRepo();

    await t.pumpWidget(
      _app(
        app: app,
        home: OpenBandNutritionRoute(date: today),
      ),
    );
    await _until(t, find.text('Externer Hafer'));
    expect(find.text('Externer Hafer'), findsOneWidget);

    final before = t.state(find.byType(OpenBandNutritionRoute));

    await t.runAsync(() async {
      final db = await LocalDb.instance;
      await NutritionDb.put(
        db,
        FoodEntry(
          id: 'external-ledger-2',
          date: today,
          meal: 'lunch',
          label: 'Importierte Linsen',
          kcal: 240,
          confirmed: true,
        ),
      );
    });
    app.bumpInsights();
    await _until(t, find.text('Importierte Linsen'));

    expect(find.text('Importierte Linsen'), findsOneWidget);
    expect(
      identical(t.state(find.byType(OpenBandNutritionRoute)), before),
      isTrue,
      reason: 'the screen was remounted — that is the workaround, not the fix',
    );
  });

  testWidgets(
    'saved zero target stays visible and formatting follows text size',
    (t) async {
      t.view.physicalSize = const Size(390 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      addTearDown(() => t.platformDispatcher.clearTextScaleFactorTestValue());

      const day = '2026-09-14';
      await t.runAsync(() async {
        final db = await LocalDb.instance;
        await NutritionDb.put(
          db,
          const FoodEntry(
            id: 'zero-protein-target',
            date: day,
            meal: 'dinner',
            label: 'Linsen mit Reis',
            kcal: 510,
            proteinG: 87,
            carbsG: 62,
            fatG: 9,
            confirmed: true,
          ),
        );
        final written = await LocalDb.putNutritionTargetPeriod(
          validFromDay: day,
          proteinG: 0,
        );
        expect(written.conflict, isFalse);
      });

      final app = AppState.forTesting();
      addTearDown(app.dispose);
      app.repo = _JournalRepo();

      await t.pumpWidget(
        _app(
          app: app,
          home: const OpenBandNutritionRoute(date: day),
        ),
      );
      await _until(t, find.text('87 / 0 g'));

      expect(find.text('87 / 0 g'), findsOneWidget);
      expect(find.byKey(const ValueKey('macro-protein-track')), findsOneWidget);
      expect(find.text('KH'), findsOneWidget);

      final before = t.state(find.byType(OpenBandNutritionRoute));
      t.platformDispatcher.textScaleFactorTestValue = 2;
      await t.pump();

      expect(find.text('Kohlenhydrate'), findsOneWidget);
      expect(find.text('87 / 0 g'), findsOneWidget);
      expect(
        identical(t.state(find.byType(OpenBandNutritionRoute)), before),
        isTrue,
      );
    },
  );

  test('every AppState importer raises the signal', () {
    final src = File('lib/state/app_state.dart').readAsStringSync();
    for (final m in const [
      'Future<int> importNoopCsv(',
      'Future<int> importWhoopCsvs(',
      'Future<BackupImportReceipt> importEdgeBackup(',
    ]) {
      final at = src.indexOf(m);
      expect(at, greaterThan(0), reason: '$m has moved or been renamed');
      final body = src.substring(at, at + 2600);
      expect(
        body,
        contains('bumpInsights()'),
        reason: '$m writes durable rows and no screen is told',
      );
    }
  });

  test('the screens the shell keeps alive re-read', () {
    for (final f in const [
      'home_screen',
      'health_screen',
      'workout_screen',
      'wellness_screen',
    ]) {
      expect(
        File('lib/ui2/screens/$f.dart').readAsStringSync(),
        contains('with RevisionReload'),
        reason: '$f loads once and never reads again',
      );
    }
  });
}
