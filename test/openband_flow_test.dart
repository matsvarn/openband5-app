import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/daily_activity.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/screens.dart';
import 'package:openstrap_edge/openband/scale.dart';
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
      now: () => DateTime(2026, 9, 18, 9, 41),
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
                    onSync: () {},
                  )
                : Center(child: Text(d.label)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pressSleepEditor(WidgetTester tester) async {
    final target = find.byTooltip('Schlafzeiten ändern');
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('metric card digits format value and comparison consistently', (
    tester,
  ) async {
    const preciseKey = ValueKey('metric-precise');
    const defaultKey = ValueKey('metric-default');
    const missingKey = ValueKey('metric-missing');
    const roundedKey = ValueKey('metric-rounded-comparison');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              OBMetricCard(
                key: preciseKey,
                label: 'Atmung präzise',
                unit: '/min',
                metric: DayMetric(16.5, baseline: 16),
                icon: Icons.air,
                color: Colors.blue,
                digits: 1,
              ),
              OBMetricCard(
                key: defaultKey,
                label: 'Atmung Standard',
                unit: '/min',
                metric: DayMetric(16.5, baseline: 16),
                icon: Icons.air,
                color: Colors.blue,
              ),
              OBMetricCard(
                key: missingKey,
                label: 'Atmung fehlt',
                unit: '/min',
                metric: DayMetric(null, baseline: 16),
                icon: Icons.air,
                color: Colors.blue,
                digits: 1,
              ),
              OBMetricCard(
                key: roundedKey,
                label: 'Atmung rundet',
                unit: '/min',
                metric: DayMetric(16.54, baseline: 16.5),
                icon: Icons.air,
                color: Colors.blue,
                digits: 1,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Finder inside(Key key, String text) =>
        find.descendant(of: find.byKey(key), matching: find.text(text));

    expect(inside(preciseKey, '16,5'), findsOneWidget);
    expect(inside(preciseKey, '+0,5 über Basis'), findsOneWidget);
    expect(inside(defaultKey, '17'), findsOneWidget);
    expect(inside(defaultKey, '+1 über Basis'), findsOneWidget);
    expect(inside(missingKey, '—'), findsOneWidget);
    expect(inside(missingKey, '/min'), findsNothing);
    expect(inside(missingKey, 'Basis noch offen'), findsNothing);
    expect(inside(roundedKey, '16,5'), findsOneWidget);
    expect(inside(roundedKey, 'wie Basis'), findsOneWidget);
    expect(find.text('+0,0 über Basis'), findsNothing);
    expect(find.text('−0,0 unter Basis'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS back swipe keeps the edited draft for reopening', (
    tester,
  ) async {
    await mount(tester, reducedMotion: false);
    await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
    await tester.pumpAndSettle();
    await pressSleepEditor(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sleep-onset')), '23:25');
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(1, 350), const Offset(360, 0));
    await tester.pumpAndSettle();
    expect(find.text('SCHLAFZEITEN ÄNDERN'), findsNothing);
    expect((await repo.readDraft('2026-09-15'))?.onset.minute, 25);
    await pressSleepEditor(tester);
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
      await tester.scrollUntilVisible(
        find.byTooltip('Schlafzeiten ändern'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.byTooltip('Schlafzeiten ändern'), findsOneWidget);
      expect(controller.selectedDay, '2026-09-15');
    },
  );

  Future<void> edit(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
    await tester.pumpAndSettle();
    await pressSleepEditor(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sleep-onset')), '23:25');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  testWidgets('five-minute controls update the persisted draft', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
    await tester.pumpAndSettle();
    await pressSleepEditor(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('− 5').first);
    await tester.pumpAndSettle();
    expect((await repo.readDraft('2026-09-15'))?.onset.minute, 5);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sleep-onset')))
          .controller
          ?.text,
      '23:05',
    );
  });

  testWidgets(
    'confirmed correction updates sleep and overview, preserving selected day',
    (tester) async {
      await mount(tester);
      await edit(tester);
      expect((await repo.readDraft('2026-09-15'))?.onset.minute, 25);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/correction-edit.png'),
      );
      expect(controller.day!.sleep.duration.value, 438);
      await tester.tap(find.text('Schlafzeiten speichern'));
      await tester.pumpAndSettle();
      expect(find.text('SCHLAF AKTUALISIERT'), findsWidgets);
      expect(controller.day!.sleep.duration.value, 428);
      expect(controller.day!.sleep.awakeMinutes, 21);
      await tester.ensureVisible(find.text('Zur Übersicht'));
      await tester.tap(find.text('Zur Übersicht'));
      await tester.pumpAndSettle();
      expect(find.text('7h08'), findsOneWidget);
      expect(controller.selectedDay, '2026-09-15');
      expect(tester.takeException(), isNull);
    },
    tags: const ['golden'],
  );

  testWidgets('correction edit renders in dark mode', (tester) async {
    await mount(tester, brightness: Brightness.dark);
    await edit(tester);
    expect((await repo.readDraft('2026-09-15'))?.onset.minute, 25);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/correction-edit-dark.png'),
    );
    expect(controller.day!.sleep.duration.value, 438);
    expect(tester.takeException(), isNull);
  }, tags: const ['golden']);

  testWidgets(
    'save failure retains draft and original result, retry commits once',
    (tester) async {
      repo.scenario = SyntheticScenario.saveFailure;
      await mount(tester);
      await edit(tester);
      await tester.tap(find.text('Schlafzeiten speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Speichern fehlgeschlagen.'), findsOneWidget);
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
    tags: const ['golden'],
  );
  testWidgets(
    'failed calculation retains saved correction and supports retry',
    (tester) async {
      repo.scenario = SyntheticScenario.calculationFailure;
      await mount(tester);
      await edit(tester);
      await tester.tap(find.text('Schlafzeiten speichern'));
      await tester.pumpAndSettle();
      expect(find.text('AUSWERTUNG OFFEN'), findsWidgets);
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
    tags: const ['golden'],
  );
  testWidgets(
    'calendar selection is committed only after confirmation',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text(obDayTitle('2026-09-15')));
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
      await tester.tap(find.text(obDayTitle('2026-09-15')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('14'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('14. September ansehen'));
      await tester.pumpAndSettle();
      expect(controller.selectedDay, '2026-09-14');
      expect(controller.day!.recovery.value, isNull);
      expect(controller.day!.sleep.duration.value, 422);
    },
    tags: const ['golden'],
  );
  testWidgets('band status separates stored frontier from receipt time', (
    tester,
  ) async {
    controller.dispose();
    controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
    await mount(tester);
    await tester.tap(find.text('64 %'));
    await tester.pumpAndSettle();
    expect(find.text('letzter Wert vor 1 h 59'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(OBScale),
      ),
      findsOneWidget,
    );
    expect(find.text('64 % · gemessen 07:42'), findsOneWidget);
    expect(find.text('15.09 · 07:42'), findsOneWidget);
    expect(find.text('Auf dem iPhone gespeichert'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
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
      expect(find.byKey(const ValueKey('sleep-stage-rows')), findsOneWidget);
      expect(find.textContaining('Im Bett'), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/sleep-partial.png'),
      );
      await tester.scrollUntilVisible(
        find.textContaining('SCHLAFDAUER'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.scrollUntilVisible(
        find.text('Zeiten korrigieren'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Zeiten korrigieren'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('02:10 bis 02:34: Keine Daten')),
        findsWidgets,
      );
      semantics.dispose();
    },
    tags: const ['golden'],
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
      tags: const ['golden'],
    );
  }
  test('stepsByHour splits a boundary-crossing interval by duration', () {
    final buckets = stepsByHour([
      StepInterval(
        DateTime(2026, 9, 15, 6, 50),
        DateTime(2026, 9, 15, 7, 10),
        200,
      ),
      StepInterval(
        DateTime(2026, 9, 15, 12, 0),
        DateTime(2026, 9, 15, 12, 30),
        300,
      ),
    ]);
    expect(buckets.length, 24);
    expect(buckets[6], 100);
    expect(buckets[7], 100);
    expect(buckets[12], 300);
    expect(buckets.fold<double>(0, (a, b) => a + b), 500);
  });

  testWidgets('Belastung ring opens the strain day detail', (tester) async {
    await mount(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Belastung, ')));
    await tester.pumpAndSettle();
    expect(find.text('BELASTUNG'), findsWidgets);
    expect(find.text('TAG FÜR TAG'), findsOneWidget);
    expect(find.textContaining('von 30 Tagen'), findsOneWidget);
    expect(find.text('Verlauf in der Nacht'), findsNothing);
    expect(find.text('So entsteht die Basis'), findsNothing);
  });

  testWidgets('interrupted transfer shows the sync pill with a resume action', (
    tester,
  ) async {
    repo.scenario = SyntheticScenario.interrupted;
    controller.updateBand(repo.band);
    await mount(tester);
    // Fixture latest_saved_local is 07:42.
    expect(find.text('Unterbrochen · bis 07:42'), findsOneWidget);
    expect(find.text('Fortsetzen'), findsOneWidget);
  });

  testWidgets(
    '375 pt and double text supports scrolling, editor and keyboard',
    (tester) async {
      await mount(tester, width: 375, height: 812, scale: 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('sleep-stage-rows')), findsOneWidget);
      expect(find.text('Leicht'), findsOneWidget);
      expect(find.text('4h07'), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/sleep-large.png'),
      );
      await tester.scrollUntilVisible(find.text('Zeiten korrigieren'), 300);
      await pressSleepEditor(tester);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(
        find.byKey(const ValueKey('sleep-onset')),
        '23:25',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sleep-onset')))
            .controller
            ?.text,
        '23:25',
      );
      expect(tester.takeException(), isNull);
    },
    tags: const ['golden'],
  );
  testWidgets('time keyboard Next focuses wake time and Done dismisses it', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
    await tester.pumpAndSettle();
    await pressSleepEditor(tester);
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
      await pressSleepEditor(tester);
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
    'back retains a draft and discard leaves the saved night intact',
    (tester) async {
      await mount(tester);
      await edit(tester);
      await tester.tap(find.byTooltip('Zurück').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entwurf behalten'));
      await tester.pumpAndSettle();
      expect((await repo.readDraft('2026-09-15'))?.onset.minute, 25);
      await pressSleepEditor(tester);
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
      await tester.tap(find.text(obDayTitle('2026-09-15')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('14'));
      await tester.tap(find.text('14'));
      await tester.pumpAndSettle();
      final previousDay = find.widgetWithText(
        FilledButton,
        '14. September ansehen',
      );
      await tester.scrollUntilVisible(
        previousDay,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(previousDay);
      await tester.pumpAndSettle();
      expect(controller.selectedDay, '2026-09-14');
      await tester.tap(find.text(obDayTitle('2026-09-14')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      final selectedDay = find.widgetWithText(
        FilledButton,
        '15. September ansehen',
      );
      await tester.scrollUntilVisible(
        selectedDay,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(selectedDay);
      await tester.pumpAndSettle();
      expect(controller.selectedDay, '2026-09-15');
      await tester.scrollUntilVisible(
        find.bySemanticsLabel(RegExp('^Schritte ')),
        300,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel(RegExp('^Schritte ')));
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
      // Back at the kept scroll position; the hero above shows the
      // corrected night.
      await tester.scrollUntilVisible(
        find.text('7h08'),
        -250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('7h08'), findsOneWidget);
      // The restore action lives in the info sheet now.
      await tester.scrollUntilVisible(
        find.byTooltip('Schlafwerte und Methode'),
        -250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Schlafwerte und Methode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Automatische Zeiten wiederherstellen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wiederherstellen'));
      await tester.pumpAndSettle();
      expect(controller.day!.sleep.duration.value, 438);
      expect(controller.day!.correction, isNull);
    },
    tags: const ['golden'],
  );
}
