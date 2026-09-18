import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/screens.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    final loader = FontLoader('Inter')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/Inter/Inter.ttf').readAsBytesSync(),
          ),
        ),
      );
    await loader.load();
    final display = FontLoader('Inter Tight')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              'assets/fonts/InterTight/InterTight[wght].ttf',
            ).readAsBytesSync(),
          ),
        ),
      );
    await display.load();
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
      activity:
          jsonDecode(
                File(
                  'docs/openband5/assets/fixtures/additional-flows.json',
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
    double scale = 1,
    double width = 393,
    double height = 852,
    bool reducedMotion = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
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
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: reducedMotion,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: AppShell(
            builder: (c, d) => d == ShellDomain.home
                ? OpenBandOverview(
                    controller: controller,
                    onProfile: () {},
                    onJournal: () {},
                  )
                : Center(child: Text(d.label)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('iOS back swipe keeps the edited draft for reopening', (
    tester,
  ) async {
    await mount(tester, reducedMotion: false);
    await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Schlafzeiten ändern'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sleep-onset')), '23:25');
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(1, 350), const Offset(360, 0));
    await tester.pumpAndSettle();
    expect(find.text('Schlafzeiten ändern'), findsNothing);
    expect((await repo.readDraft('2026-09-15'))?.onset.minute, 25);
    await tester.tap(find.byTooltip('Schlafzeiten ändern'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sleep-onset')))
          .controller
          ?.text,
      '23:25',
    );
  });

  testWidgets(
    'tab stacks retain the originating sleep route and selected day',
    (tester) async {
      await mount(tester);
      await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
      await tester.pumpAndSettle();
      final shell = tester.state<AppShellState>(find.byType(AppShell));
      shell.select(ShellDomain.workout);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Schlafzeiten ändern'), findsNothing);
      shell.select(ShellDomain.home);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Schlafzeiten ändern'), findsOneWidget);
      expect(controller.selectedDay, '2026-09-15');
    },
  );

  Future<void> edit(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Schlafzeiten ändern'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sleep-onset')), '23:25');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Änderung ansehen'));
    await tester.tap(find.text('Änderung ansehen'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'confirmed correction updates sleep and overview, preserving selected day',
    (tester) async {
      await mount(tester);
      await edit(tester);
      expect(find.text('7h29'), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/correction-preview.png'),
      );
      expect(controller.day!.sleep.duration.value, 438);
      await tester.tap(find.text('Schlafzeiten speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Schlaf aktualisiert'), findsWidgets);
      expect(controller.day!.sleep.duration.value, 428);
      expect(controller.day!.sleep.awakeMinutes, 21);
      await tester.ensureVisible(find.text('Zur Übersicht'));
      await tester.tap(find.text('Zur Übersicht'));
      await tester.pumpAndSettle();
      expect(find.text('7h08'), findsOneWidget);
      expect(controller.selectedDay, '2026-09-15');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'save failure retains draft and original result, retry commits once',
    (tester) async {
      repo.scenario = SyntheticScenario.saveFailure;
      await mount(tester);
      await edit(tester);
      await tester.tap(find.text('Schlafzeiten speichern'));
      await tester.pumpAndSettle();
      expect(
        find.text('Speichern fehlgeschlagen. Dein Entwurf bleibt erhalten.'),
        findsOneWidget,
      );
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/save-failure.png'),
      );
      final draft = await repo.readDraft('2026-09-15');
      expect(draft, isNotNull);
      expect(controller.day!.sleep.duration.value, 438);
      repo.scenario = SyntheticScenario.complete;
      await tester.ensureVisible(find.text('Erneut speichern'));
      await tester.tap(find.text('Erneut speichern'));
      await tester.pumpAndSettle();
      expect(controller.day!.correction!.id, draft!.id);
      expect(controller.day!.correction!.revision, 1);
    },
  );
  testWidgets(
    'failed calculation retains saved correction and supports retry',
    (tester) async {
      repo.scenario = SyntheticScenario.calculationFailure;
      await mount(tester);
      await edit(tester);
      await tester.tap(find.text('Schlafzeiten speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Auswertung offen'), findsWidgets);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/calculation-failure.png'),
      );
      expect(controller.day!.correction!.state, CorrectionState.failed);
      expect(controller.day!.sleep.duration.value, 438);
      repo.scenario = SyntheticScenario.complete;
      await tester.ensureVisible(find.text('Auswertung erneut starten'));
      await tester.tap(find.text('Auswertung erneut starten'));
      await tester.pumpAndSettle();
      expect(controller.day!.sleep.duration.value, 428);
    },
  );
  testWidgets('calendar selection is committed only after confirmation', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('15. September'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14'));
    await tester.pumpAndSettle();
    expect(controller.selectedDay, '2026-09-15');
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/date-selection.png'),
    );
    await tester.tap(find.byTooltip('Abbrechen'));
    await tester.pumpAndSettle();
    expect(controller.selectedDay, '2026-09-15');
    await tester.tap(find.text('15. September'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14. September ansehen'));
    await tester.pumpAndSettle();
    expect(controller.selectedDay, '2026-09-14');
    expect(controller.day!.recovery.value, isNull);
    expect(controller.day!.sleep.duration.value, 422);
  });
  testWidgets(
    'accessible values and tap targets include unobserved intervals',
    (tester) async {
      final semantics = tester.ensureSemantics();
      repo.scenario = SyntheticScenario.partial;
      await mount(tester);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Schlaf, ')).first);
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/sleep-partial.png'),
      );
      expect(
        find.bySemanticsLabel(RegExp('02:10 bis 02:34: Keine Daten')),
        findsWidgets,
      );
      semantics.dispose();
    },
  );

  for (final scenario in [
    SyntheticScenario.complete,
    SyntheticScenario.dense,
    SyntheticScenario.partial,
    SyntheticScenario.missing,
    SyntheticScenario.processing,
    SyntheticScenario.disconnected,
    SyntheticScenario.interrupted,
  ]) {
    testWidgets(
      'overview ${scenario.name} light and dark renders without overflow',
      (tester) async {
        repo.scenario = scenario;
        controller.updateBand(repo.band);
        await mount(tester);
        await expectLater(
          find.byKey(const ValueKey('capture')),
          matchesGoldenFile('openband_goldens/${scenario.name}-light.png'),
        );
        expect(tester.takeException(), isNull);
        await mount(tester, brightness: Brightness.dark);
        await expectLater(
          find.byKey(const ValueKey('capture')),
          matchesGoldenFile('openband_goldens/${scenario.name}-dark.png'),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    '375 pt and double text supports scrolling, editor and keyboard',
    (tester) async {
      await mount(tester, width: 375, height: 812, scale: 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/sleep-large.png'),
      );
      await tester.tap(find.byTooltip('Schlafzeiten ändern'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(
        find.byKey(const ValueKey('sleep-onset')),
        '23:25',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Änderung ansehen'));
      await tester.tap(find.text('Änderung ansehen'));
      await tester.pumpAndSettle();
      expect(find.text('7h29'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('time keyboard Next focuses wake time and Done dismisses it', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Schlafzeiten ändern'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sleep-onset')), '23:25');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sleep-wake')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sleep-wake')))
          .focusNode!
          .hasFocus,
      isFalse,
    );
    expect((await repo.readDraft('2026-09-15'))?.onset.minute, 25);
  });

  testWidgets(
    'draft write failure can retry without losing the entered times',
    (tester) async {
      repo.scenario = SyntheticScenario.draftFailure;
      await mount(tester);
      await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Schlafzeiten ändern'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('sleep-onset')),
        '23:25',
      );
      await tester.pumpAndSettle();
      expect(await repo.readDraft('2026-09-15'), isNull);
      expect(find.text('Entwurf erneut sichern'), findsOneWidget);
      repo.scenario = SyntheticScenario.complete;
      await tester.ensureVisible(find.text('Entwurf erneut sichern'));
      await tester.tap(find.text('Entwurf erneut sichern'));
      await tester.pumpAndSettle();
      expect((await repo.readDraft('2026-09-15'))?.onset.minute, 25);
      expect(find.text('Entwurf erneut sichern'), findsNothing);
    },
  );

  testWidgets(
    'back retains a draft and preview discard leaves the saved night intact',
    (tester) async {
      await mount(tester);
      await edit(tester);
      await tester.tap(find.text('Weiter bearbeiten'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zurück').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entwurf behalten'));
      await tester.pumpAndSettle();
      expect((await repo.readDraft('2026-09-15'))?.onset.minute, 25);
      await tester.tap(find.byTooltip('Schlafzeiten ändern'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Änderung ansehen'));
      await tester.tap(find.text('Änderung ansehen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Änderung verwerfen'));
      await tester.pumpAndSettle();
      expect(await repo.readDraft('2026-09-15'), isNull);
      expect(controller.day!.sleep.duration.value, 438);
      expect(controller.day!.correction, isNull);
    },
  );

  testWidgets(
    'small phone large text keeps calendar and activity actions usable',
    (tester) async {
      await mount(tester, width: 375, height: 812, scale: 2);
      await tester.tap(find.text('15. September'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('14'));
      await tester.tap(find.text('14'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('14. September ansehen'));
      await tester.tap(find.text('14. September ansehen'));
      await tester.pumpAndSettle();
      expect(controller.selectedDay, '2026-09-14');
      await tester.tap(find.text('14. September'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('15. September ansehen'), 200);
      await tester.tap(find.text('15. September ansehen'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byTooltip('Schritte ansehen'), 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Schritte ansehen'));
      await tester.pumpAndSettle();
      expect(find.text('00:00–01:00 · 0 Schritte'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completed correction can return to the night and restore automatic times',
    (tester) async {
      await mount(tester);
      await edit(tester);
      await tester.tap(find.text('Schlafzeiten speichern'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/correction-complete.png'),
      );
      await tester.tap(find.text('Nacht ansehen'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Schlafzeiten ändern'), findsOneWidget);
      expect(find.text('7h08'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Automatische Zeiten wiederherstellen'),
        300,
      );
      await tester.tap(find.text('Automatische Zeiten wiederherstellen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wiederherstellen'));
      await tester.pumpAndSettle();
      expect(controller.day!.sleep.duration.value, 438);
      expect(controller.day!.correction, isNull);
    },
  );
}
