import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:latlong2/latlong.dart';
import 'package:openstrap_edge/gps/route_models.dart';
import 'package:openstrap_edge/gps/route_tracker.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/run_live.dart';
import 'package:openstrap_edge/openband/session.dart';
import 'package:openstrap_edge/openband/strength_live.dart';
import 'package:openstrap_edge/openband/template_editor.dart';
import 'package:openstrap_edge/openband/training.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

/// Serves a transparent 1×1 PNG for every tile so the live-map test never
/// touches the network.
class _StubTileProvider extends TileProvider {
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQAB'
    'h6FO1AAAAABJRU5ErkJggg==',
  );
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_png);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
    ]) {
      final loader = FontLoader(family)
        ..addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        );
      await loader.load();
    }
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await icons.load();
  });

  late SyntheticOpenBandRepository repo;
  late OpenBandController controller;
  setUp(() {
    repo = SyntheticOpenBandRepository.fromMaps(
      run:
          jsonDecode(
                File(
                  'docs/openband5/assets/fixtures/run-detail.json',
                ).readAsStringSync(),
              )
              as Map,
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
    controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
    );
  });
  tearDown(() => controller.dispose());

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: Scaffold(
            body: OpenBandTraining(
              controller: controller,
              onStart: (_) {},
              onStartTemplate: (_) async {},
              onOpenTemplates: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('sessions window is inclusive and sorted newest first', () async {
    final week = await repo.readSessions('2026-09-15', 7);
    expect(week.map((s) => s.day), ['2026-09-14', '2026-09-13', '2026-09-12']);
    expect(week.map((s) => s.durationMin), [25, 45, 32]);
    expect(week.first.strain, isNotNull);
    expect(week.last.strain, isNull);
    final month = await repo.readSessions('2026-09-15', 30);
    expect(month.length, 5);
    expect(await repo.readSessions('2026-07-01', 7), isEmpty);
  });

  testWidgets('training hub renders light and dark', (tester) async {
    await mount(tester);
    expect(find.text('Training'), findsOneWidget);
    expect(find.text('102'), findsOneWidget);
    expect(find.text('3 Einheiten'), findsOneWidget);
    expect(find.bySemanticsLabel('Kraft starten'), findsOneWidget);
    expect(find.text('Ganzkörper A'), findsOneWidget);
    expect(find.text('4 Übungen'), findsOneWidget);
    expect(find.text('Als Nächstes'), findsNothing);
    expect(find.byTooltip('Vorlagen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/training-light.png'),
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/templates-hub.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/training-dark.png'),
    );
  });

  test('template save bumps the version and refuses an empty plan', () async {
    final first = (await repo.readTemplates()).firstWhere(
      (t) => t.id == 'tpl-ganzkoerper-a',
    );
    final saved = await repo.saveTemplate(first);
    expect(saved.version, 2);
    expect(saved.workSets, 12);
    await expectLater(
      repo.saveTemplate(
        WorkoutTemplate(
          id: 'x',
          name: ' ',
          version: 0,
          exercises: const [],
          updatedAt: DateTime(2026),
        ),
      ),
      throwsArgumentError,
    );
  });

  testWidgets('session detail renders the run fixture exactly', (tester) async {
    final run = (await repo.readSessions('2026-09-15', 7)).first;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: OpenBandSession(repository: repo, session: run),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('5,00'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('5:00'), findsOneWidget);
    expect(find.text('Belastung 5,9'), findsOneWidget);
    expect(find.text('327'), findsOneWidget);
    expect(find.text('−20'), findsOneWidget);
    expect(find.text('−32'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/session-run.png'),
    );
    expect(
      await repo.readSessionDetail('synthetic-2026-09-13-weight_training'),
      isNull,
    );
  });

  testWidgets('live strength: confirming a set records it, rest timer runs', (
    tester,
  ) async {
    final template = (await repo.readTemplates()).firstWhere(
      (t) => t.id == 'tpl-ganzkoerper-a',
    );
    var now = DateTime(2026, 9, 15, 18);
    repo.strengthNow = () => now;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: OpenBandStrengthLive(
            repository: repo,
            template: template,
            now: () => now,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Bankdrücken'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '42,5');
    await tester.tap(find.byTooltip('Satz 1 bestätigen').first);
    await tester.pump();
    now = now.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('1:10'), findsOneWidget);
    expect(find.text('ZULETZT'), findsWidgets);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/strength-live.png'),
    );
    await tester.tap(find.text('Fertig'));
    await tester.pump();
    final load = await repo.readMuscleLoad('2026-09-15', 7);
    expect(load.setsByMuscle['Brust'], 4);
    expect(load.setsByMuscle['Beine'], 3);
  });

  testWidgets('live run keeps pause and active time apart', (tester) async {
    final run = ValueNotifier(
      const LiveRun(
        elapsedSec: 962,
        pausedSec: 60,
        distanceM: 2840,
        heartRate: 154,
        zone: 3,
        gps: true,
      ),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: OpenBandRunLive(run: run, onPause: () {}, onLap: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2,84'), findsOneWidget);
    expect(find.text('15:02'), findsOneWidget);
    expect(find.text('5:18'), findsOneWidget);
    expect(find.text('154 · Z3'), findsOneWidget);
    expect(find.text('davon 1:00 pausiert'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/run-live.png'),
    );
    run.value = const LiveRun(elapsedSec: 962, pausedSec: 60, paused: true);
    await tester.pump();
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('Weiter'), findsOneWidget);
    expect(find.text('Beenden'), findsOneWidget);
  });

  testWidgets('live run shows the route map when a tracker is bound', (
    tester,
  ) async {
    final tracker = RouteTracker(sink: (_) async {});
    addTearDown(tracker.dispose);
    tracker.path.value = const [
      RouteVertex(LatLng(52.5200, 13.4050), 3),
      RouteVertex(LatLng(52.5210, 13.4060), 3),
      RouteVertex(LatLng(52.5220, 13.4070), 4),
    ];
    tracker.current.value = const LatLng(52.5220, 13.4070);
    final run = ValueNotifier(
      const LiveRun(elapsedSec: 962, distanceM: 2840, gps: true, laps: 2),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        home: OpenBandRunLive(
          run: run,
          tracker: tracker,
          tileProvider: _StubTileProvider(),
          mapAllowed: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Karte ohne GPS nicht verfügbar'), findsNothing);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('Runde 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('recordLap freezes laps into the session detail', () async {
    const id = 'synthetic-2026-09-14-running';
    await repo.recordLap(
      id,
      Lap(
        index: 1,
        elapsedSec: 600,
        pausedSec: 0,
        distanceM: 2000,
        at: DateTime(2026, 9, 14, 7, 15),
      ),
    );
    final detail = await repo.readSessionDetail(id);
    expect(detail?.laps.length, 1);
    expect(detail?.laps.single.distanceM, 2000);
  });

  testWidgets('session detail lists recorded laps', (tester) async {
    const id = 'synthetic-2026-09-14-running';
    await repo.recordLap(
      id,
      Lap(
        index: 1,
        elapsedSec: 600,
        pausedSec: 0,
        distanceM: 2000,
        at: DateTime(2026, 9, 14, 7, 15),
      ),
    );
    final run = (await repo.readSessions('2026-09-15', 7)).first;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        home: OpenBandSession(repository: repo, session: run),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Runde 1 · 10:00 · 2,00 km'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('template editor saves a new plan and bumps an edited one', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WorkoutTemplate? saved;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  saved = await Navigator.of(ctx).push(
                    MaterialPageRoute<WorkoutTemplate>(
                      builder: (_) => OpenBandTemplateEditor(repository: repo),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Vorlage speichern'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Oberkörper B');
    await tester.tap(find.text('Übung hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eigene Übung'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'Klimmzug');
    await tester.enterText(find.byType(TextField).at(3), '6');
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')).evaluate().isEmpty
          ? find.byType(OpenBandTemplateEditor)
          : find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/template-editor.png'),
    );
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();
    expect(saved?.name, 'Oberkörper B');
    expect(saved?.version, 1);
    expect(
      saved?.exercises.single.exerciseKey,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ),
      ),
    );
    expect(saved?.exercises.single.exerciseKey, isNot('klimmzug'));
    expect(saved?.exercises.single.sets.length, 1);
    expect(saved?.exercises.single.sets.first.reps, 6);
    expect(saved?.exercises.single.sets.first.loadKg, isNull);
    expect((await repo.readTemplates()).length, 3);
  });

  testWidgets('empty window shows an empty state, not zero minutes', (
    tester,
  ) async {
    controller.selectedDay = '2026-07-01';
    await mount(tester);
    expect(find.text('Noch keine Einheiten'), findsOneWidget);
    expect(find.text('Letzte 30 Tage'), findsOneWidget);
    expect(find.textContaining('Übertragung'), findsNothing);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('keine Einheit'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/training-empty.png'),
    );
  });

  testWidgets('hub read failure is not an empty success', (tester) async {
    repo.failTemplateRead = true;
    await mount(tester);
    expect(find.text('Vorlagen konnten nicht geladen werden.'), findsOneWidget);
    expect(find.text('Keine Vorlagen'), findsNothing);
    expect(find.text('Ganzkörper A'), findsNothing);
    expect(find.text('Als Nächstes'), findsNothing);
  });

  testWidgets('hub without templates has no phantom row', (tester) async {
    repo.clearTemplates();
    await mount(tester);
    expect(find.text('Ganzkörper A'), findsNothing);
    expect(find.text('Starten'), findsNothing);
    expect(find.text('Training'), findsOneWidget);
  });
}
