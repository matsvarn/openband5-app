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
import 'package:openstrap_edge/openband/scale.dart';
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

  OBAction action(WidgetTester tester, String label) =>
      tester.widget<OBAction>(find.widgetWithText(OBAction, label));

  String shown(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('sleep-goal-value'))).data!;

  testWidgets(
    'unset goal shows emdash, no handle, and nothing to save',
    (tester) async {
      repo.weekendEstimate = null;
      await mountGoal(tester);
      expect(find.text('SCHLAFZIEL'), findsOneWidget);
      expect(find.text('EIGENES ZIEL'), findsOneWidget);
      expect(shown(tester), '—');
      expect(
        find.text('Tippe auf die Skala, um ein Ziel festzulegen.'),
        findsOneWidget,
      );
      expect(action(tester, '– 15 Min.').onPressed, isNull);
      expect(action(tester, '+ 15 Min.').onPressed, isNull);
      expect(action(tester, 'Speichern').onPressed, isNull);
      expect(
        find.text('Noch kein Wert – zu wenige Wochenend-Nächte.'),
        findsOneWidget,
      );
      expect(find.text('Ziel entfernen'), findsNothing);
      expect(find.text('Synthetische Daten'), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('sleep-goal-scale'))),
        isSemantics(label: 'Schlafziel', value: '', isSlider: true),
      );
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/sleep-goal-unset.png'),
      );
    },
    tags: const ['golden'],
  );

  testWidgets('production omits the synthetic footer', (tester) async {
    await mountGoal(tester, synthetic: false);
    expect(find.text('Synthetische Daten'), findsNothing);
    expect(find.text('Speichern'), findsOneWidget);
  });

  testWidgets('user target and dark render the stored duration', (
    tester,
  ) async {
    repo.weekendEstimate = null;
    await repo.saveSleepGoal('2026-09-15', 465);
    await mountGoal(tester);
    expect(shown(tester), '7h45');
    expect(action(tester, 'Speichern').onPressed, isNull);
    expect(find.text('Ziel entfernen'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('sleep-goal-scale'))),
      matchesSemantics(
        label: 'Schlafziel',
        value: '7h45',
        increasedValue: '8h00',
        decreasedValue: '7h30',
        isSlider: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/sleep-goal-target.png'),
    );
    await mountGoal(tester, brightness: Brightness.dark);
    expect(shown(tester), '7h45');
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
    expect(shown(tester), '7h45');
    expect(find.text('8h12'), findsOneWidget);
    expect(find.text('Stand 15. September'), findsOneWidget);
    expect(find.textContaining('Schlafbedarf'), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Wochenend-Schätzung')),
      matchesSemantics(
        label: 'Wochenend-Schätzung',
        value: '8h12 · Stand 15. September',
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

  testWidgets('steps and scale taps change only the draft until saved', (
    tester,
  ) async {
    await repo.saveSleepGoal('2026-09-15', 465);
    await mountGoal(tester);
    await tester.tap(find.text('+ 15 Min.'));
    await tester.pump();
    expect(shown(tester), '8h00');
    expect(action(tester, 'Speichern').onPressed, isNotNull);
    await tester.tap(find.text('– 15 Min.'));
    await tester.pump();
    expect(shown(tester), '7h45');
    expect(action(tester, 'Speichern').onPressed, isNull);

    // The scale spans 5–10 h; its right end is 10 h, its left end 5 h.
    final scale = tester.getRect(
      find.byKey(const ValueKey('sleep-goal-scale')),
    );
    await tester.tapAt(scale.centerRight - const Offset(1, 0));
    await tester.pump();
    expect(shown(tester), '10h00');
    await tester.tapAt(scale.centerLeft + const Offset(1, 0));
    await tester.pump();
    expect(shown(tester), '5h00');
    expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, 465);
  });

  testWidgets('goals outside the scale keep their value', (tester) async {
    await repo.saveSleepGoal('2026-09-15', 250);
    await mountGoal(tester);
    expect(shown(tester), '4h10');
    await tester.tap(find.text('– 15 Min.'));
    await tester.pump();
    expect(shown(tester), '3h55');
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

  testWidgets('set, save failure, retry, remove, and cancel', (tester) async {
    await mountGoal(tester);
    final scale = tester.getRect(
      find.byKey(const ValueKey('sleep-goal-scale')),
    );
    // 7h45 sits at 55 % of the 5–10 h scale.
    await tester.tapAt(Offset(scale.left + scale.width * .55, scale.center.dy));
    await tester.pump();
    expect(shown(tester), '7h45');

    repo.failSleepGoalWrite = true;
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(shown(tester), '7h45');
    expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, isNull);

    repo.failSleepGoalWrite = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, 465);
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(action(tester, 'Speichern').onPressed, isNull);

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
    expect(shown(tester), '—');
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
      expect(action(tester, '+ 15 Min.').onPressed, isNull);
      await tester.tap(find.text('Entfernen'));
      await tester.pump();
      expect(action(tester, '+ 15 Min.').onPressed, isNull);
      expect(action(tester, 'Speichern').onPressed, isNull);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Ziel entfernen'),
            )
            .onPressed,
        isNull,
      );
      expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, 465);
      gate.complete();
      await tester.pumpAndSettle();
      expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, isNull);
      expect(shown(tester), '—');

      await repo.saveSleepGoal('2026-09-15', 465);
      repo.sleepGoalWriteBarrier = null;
      await mountGoal(tester);
      repo.failSleepGoalWrite = true;
      await tester.tap(find.text('Ziel entfernen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();
      expect(shown(tester), '7h45');
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, 465);
      repo.failSleepGoalWrite = false;
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();
      expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, isNull);
      expect(shown(tester), '—');
    },
  );

  testWidgets('learned unknown stays emdash and read error retries', (
    tester,
  ) async {
    repo.weekendEstimate = null;
    await mountGoal(tester);
    expect(find.text('8h12'), findsNothing);
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
    expect(find.text('EIGENES ZIEL'), findsOneWidget);
  });

  testWidgets('small width and 2x text wrap without overflow', (tester) async {
    await repo.saveSleepGoal('2026-09-15', 465);
    await mountGoal(tester, width: 375, scale: 2);
    expect(tester.takeException(), isNull);
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
    expect(find.text('8h12'), findsOneWidget);
    expect(find.text('Synthetische Daten'), findsOneWidget);

    final scale = tester.getRect(
      find.byKey(const ValueKey('sleep-goal-scale')),
    );
    await tester.tapAt(scale.centerRight - const Offset(1, 0));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück').last);
    await tester.pumpAndSettle();
    // Schlaf re-reads the goal it cached for the day.
    expect(find.text('10h00'), findsOneWidget);
  });

  testWidgets('Heute updates its Schlaf goal after returning from Schlaf', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await repo.saveSleepGoal('2026-09-15', 465);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: OpenBandOverview(controller: controller, reduced: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    OBScale sleepScale() => tester
        .widgetList<OBScale>(find.byType(OBScale))
        .singleWhere((scale) => scale.max == 600);
    expect(sleepScale().target, 465);

    await tester.tap(find.bySemanticsLabel(RegExp(r'^Schlaf, ')).first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Schlafziel'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Schlafziel'));
    await tester.pumpAndSettle();
    final scale = tester.getRect(
      find.byKey(const ValueKey('sleep-goal-scale')),
    );
    await tester.tapAt(scale.centerRight - const Offset(1, 0));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect((await repo.readSleepGoal('2026-09-15')).targetMinutes, 600);
    await tester.tap(find.byTooltip('Zurück').last);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(OpenBandSleep))).pop();
    await tester.pumpAndSettle();
    expect(sleepScale().target, 600);
  });
}
