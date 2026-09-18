import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/session.dart';
import 'package:openstrap_edge/openband/training.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

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
              onStartTemplate: (_) {},
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
    expect(find.text('4 Übungen · 12 Arbeitssätze'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/training-light.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/training-dark.png'),
    );
  });

  test('template save bumps the version and refuses an empty plan', () async {
    final first = (await repo.readTemplates()).single;
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

  testWidgets('empty window shows an empty state, not zero minutes', (
    tester,
  ) async {
    controller.selectedDay = '2026-07-01';
    await mount(tester);
    expect(find.text('Noch keine Einheiten'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('keine Einheit'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/training-empty.png'),
    );
  });
}
