import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/screens.dart';
import 'package:openstrap_edge/openband/sleep_goal.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    for (final font in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
      (
        'packages/lucide_icons_flutter/Lucide',
        'packages/lucide_icons_flutter/assets/lucide.ttf',
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  late SyntheticOpenBandRepository repo;
  late OpenBandController controller;

  setUp(() {
    repo = SyntheticOpenBandRepository.fromMaps(
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
      now: () => DateTime(2026, 9, 18, 9, 41),
    );
  });
  tearDown(() => controller.dispose());

  Future<void> mountGoal(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double width = 393,
    double height = 852,
    double scale = 1,
    bool synthetic = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: OpenBandSleepGoal(
            key: UniqueKey(),
            repository: repo,
            day: '2026-09-15',
            synthetic: synthetic,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mountEditor(
    WidgetTester tester, {
    int? targetMinutes,
    bool synthetic = true,
    Brightness brightness = Brightness.light,
    double width = 393,
    double height = 852,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: OpenBandSleepGoalEditor(
            repository: repo,
            day: '2026-09-15',
            targetMinutes: targetMinutes,
            synthetic: synthetic,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('unset own target shows emdash and set action', (tester) async {
    repo.weekendEstimate = null;
    await mountGoal(tester);
    expect(find.text('Eigenes Ziel'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('Ziel festlegen'), findsOneWidget);
    expect(find.text('Wochenend-Schätzung'), findsOneWidget);
    expect(find.text('Ziel entfernen'), findsNothing);
    expect(find.text('Synthetische Daten'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-goal-unset.png'),
    );
  }, tags: const ['golden']);

  testWidgets('production omits the synthetic footer', (tester) async {
    await mountGoal(tester, synthetic: false);
    expect(find.text('Synthetische Daten'), findsNothing);
    expect(find.text('Ziel festlegen'), findsOneWidget);
  });

  testWidgets('user target and dark render the stored duration', (
    tester,
  ) async {
    repo.weekendEstimate = null;
    await repo.saveSleepGoal('2026-09-15', 465);
    await mountGoal(tester);
    expect(find.text('7 h 45'), findsOneWidget);
    expect(find.text('Ändern'), findsOneWidget);
    expect(find.text('Ziel entfernen'), findsOneWidget);
    expect(find.text('Synthetische Daten'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-goal-target.png'),
    );
    await mountGoal(tester, brightness: Brightness.dark);
    expect(find.text('7 h 45'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-goal-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('target plus stored weekend estimate stays unclamped', (
    tester,
  ) async {
    await repo.saveSleepGoal('2026-09-15', 465);
    await mountGoal(tester);
    expect(find.text('7 h 45'), findsOneWidget);
    expect(find.text('8 h 12 · Stand 15. September'), findsOneWidget);
    expect(find.textContaining('Schlafbedarf'), findsNothing);
    expect(find.text('Synthetische Daten'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Wochenend-Schätzung')),
      matchesSemantics(
        label: 'Wochenend-Schätzung',
        value: '8 h 12 · Stand 15. September',
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.bySemanticsLabel('Wochenend-Schätzung'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        '75. Perzentil der Wochenendnächte. Keine Messung des Schlafbedarfs.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-goal-estimate.png'),
    );
  }, tags: const ['golden']);

  testWidgets(
    'editor starts blank and save stays disabled until a valid choice',
    (tester) async {
      await mountEditor(tester, synthetic: false);
      expect(find.text('Schlafziel bearbeiten'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sleep-goal-hours')))
            .controller
            ?.text,
        '',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sleep-goal-minutes')))
            .controller
            ?.text,
        '',
      );
      expect(
        tester
            .widget<OBAction>(find.widgetWithText(OBAction, 'Speichern'))
            .onPressed,
        isNull,
      );
      expect(find.text('Synthetische Daten'), findsNothing);
    },
  );

  testWidgets('filled editor prefills 7h45 from the saved target', (
    tester,
  ) async {
    await mountEditor(tester, targetMinutes: 465);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sleep-goal-hours')))
          .controller
          ?.text,
      '7',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sleep-goal-minutes')))
          .controller
          ?.text,
      '45',
    );
    expect(
      tester
          .widget<OBAction>(find.widgetWithText(OBAction, 'Speichern'))
          .onPressed,
      isNotNull,
    );
    expect(find.text('Synthetische Daten'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-goal-editor.png'),
    );
  }, tags: const ['golden']);

  testWidgets('filled editor renders in dark', (tester) async {
    await mountEditor(tester, targetMinutes: 465, brightness: Brightness.dark);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sleep-goal-hours')))
          .controller
          ?.text,
      '7',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sleep-goal-minutes')))
          .controller
          ?.text,
      '45',
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-goal-editor-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('filled editor at 375 and 2x wraps without overflow', (
    tester,
  ) async {
    await mountEditor(tester, targetMinutes: 465, width: 375, scale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Stunden'), findsOneWidget);
    expect(find.text('Speichern'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sleep-goal-hours')))
          .controller
          ?.text,
      '7',
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-goal-editor-2x.png'),
    );
  }, tags: const ['golden']);

  testWidgets('edit prefills the selected-day target and leaves unset blank', (
    tester,
  ) async {
    await repo.saveSleepGoal('2026-09-15', 465);
    await mountGoal(tester);
    await tester.tap(find.text('Ändern'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sleep-goal-hours')))
          .controller
          ?.text,
      '7',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sleep-goal-minutes')))
          .controller
          ?.text,
      '45',
    );
    expect(
      tester
          .widget<OBAction>(find.widgetWithText(OBAction, 'Speichern'))
          .onPressed,
      isNotNull,
    );
    expect(find.text('Synthetische Daten'), findsOneWidget);
  });

  testWidgets('goal info keeps wake-day copy and omits the blank-state line', (
    tester,
  ) async {
    await mountGoal(tester);
    await tester.tap(find.byTooltip('Schlafziel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kein voreingestelltes Ziel'), findsNothing);
    expect(find.textContaining('Aufwachtag'), findsOneWidget);
    expect(
      find.textContaining(
        'Die Wochenend-Schätzung ist das 75. Perzentil der Wochenendnächte, kein eigenes Ziel.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('set, cancel, save failure, remove, and historic day', (
    tester,
  ) async {
    await mountGoal(tester);
    await tester.tap(find.text('Ziel festlegen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sleep-goal-hours')), '7');
    await tester.enterText(
      find.byKey(const ValueKey('sleep-goal-minutes')),
      '45',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Zurück').last);
    await tester.pumpAndSettle();
    expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, isNull);
    expect(find.text('Ziel festlegen'), findsOneWidget);

    await tester.tap(find.text('Ziel festlegen'));
    await tester.pumpAndSettle();
    repo.failSleepGoalWrite = true;
    await tester.enterText(find.byKey(const ValueKey('sleep-goal-hours')), '7');
    await tester.enterText(
      find.byKey(const ValueKey('sleep-goal-minutes')),
      '45',
    );
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.textContaining('Eintrag bleibt'), findsNothing);
    expect(find.text('Selbst eintragen'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sleep-goal-hours')))
          .controller
          ?.text,
      '7',
    );
    expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, isNull);

    repo.failSleepGoalWrite = false;
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('7 h 45'), findsOneWidget);

    await tester.tap(find.text('Ziel entfernen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('15. September'), findsWidgets);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, 465);

    await tester.tap(find.text('Ziel entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, isNull);
    expect(find.text('Ziel festlegen'), findsOneWidget);
  });

  testWidgets(
    'remove stays busy until persist ends and retries after failure',
    (tester) async {
      await repo.saveSleepGoal('2026-09-15', 465);
      final gate = Completer<void>();
      repo.sleepGoalWriteBarrier = gate.future;
      await mountGoal(tester);
      await tester.tap(find.text('Ziel entfernen'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OBAction>(find.widgetWithText(OBAction, 'Ändern'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Entfernen'));
      await tester.pump();
      expect(
        tester
            .widget<OBAction>(find.widgetWithText(OBAction, 'Ändern'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Ziel entfernen'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Ändern'));
      await tester.pump();
      expect(find.text('Schlafziel bearbeiten'), findsNothing);
      expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, 465);
      gate.complete();
      await tester.pumpAndSettle();
      expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, isNull);
      expect(find.text('Ziel festlegen'), findsOneWidget);

      await repo.saveSleepGoal('2026-09-15', 465);
      repo.sleepGoalWriteBarrier = null;
      await mountGoal(tester);
      repo.failSleepGoalWrite = true;
      await tester.tap(find.text('Ziel entfernen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();
      expect(find.text('7 h 45'), findsOneWidget);
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsOneWidget);
      expect(find.textContaining('Eintrag bleibt'), findsNothing);
      expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, 465);
      repo.failSleepGoalWrite = false;
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();
      expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, isNull);
      expect(find.text('Ziel festlegen'), findsOneWidget);
    },
  );

  testWidgets('learned unknown stays emdash and read error retries', (
    tester,
  ) async {
    repo.weekendEstimate = null;
    await mountGoal(tester);
    expect(find.text('8 h 12 · Stand 15. September'), findsNothing);
    expect(find.text('—'), findsWidgets);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Wochenend-Schätzung')),
      matchesSemantics(
        label: 'Wochenend-Schätzung',
        value: '—',
        isButton: true,
        hasTapAction: true,
      ),
    );

    repo.failSleepGoalRead = true;
    await mountGoal(tester);
    expect(find.text('Erneut laden'), findsOneWidget);
    repo.failSleepGoalRead = false;
    await tester.tap(find.text('Erneut laden'));
    await tester.pumpAndSettle();
    expect(find.text('Eigenes Ziel'), findsOneWidget);
  });

  testWidgets('small width and 2x text wrap without overflow', (tester) async {
    await repo.saveSleepGoal('2026-09-15', 465);
    await mountGoal(tester, width: 375, scale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Wochenend-Schätzung'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Ziel entfernen'),
      80,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-goal-2x.png'),
    );
  }, tags: const ['golden']);

  testWidgets('OpenBandSleep reaches Schlafziel for the selected wake day', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: openBandTheme(Brightness.light),
        home: OpenBandSleep(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Schlafziel'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Schlafziel'));
    await tester.pumpAndSettle();
    expect(find.text('Ab 15. September'), findsOneWidget);
    expect(find.text('8 h 12 · Stand 15. September'), findsOneWidget);
    expect(find.text('Synthetische Daten'), findsOneWidget);
  });
}
