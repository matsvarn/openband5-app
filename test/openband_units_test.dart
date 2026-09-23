import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/openband/units.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:openstrap_edge/ui2/profile/settings.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../integration_test/openband_review_test.dart'
    show
        reviewPageTransitionRunning,
        reviewPumpPageTransitions,
        reviewPumpPresentedFrame,
        reviewTimingContainsFrame,
        reviewTransitionUnsettled;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpView(
    WidgetTester tester, {
    UnitSystem selected = UnitSystem.metric,
    bool busy = false,
    bool synthetic = true,
    String? saveError,
    ValueChanged<UnitSystem>? onSelect,
    VoidCallback? onRetry,
    double scale = 1,
    double width = 393,
    double height = 852,
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('de'),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        locale: locale,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de'), Locale('en')],
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        darkTheme: openBandTheme(
          Brightness.dark,
        ).copyWith(platform: TargetPlatform.iOS),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
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
          child: Theme(
            data: openBandTheme(
              brightness,
            ).copyWith(platform: TargetPlatform.iOS),
            child: UnitsSettingsView(
              selected: selected,
              busy: busy,
              synthetic: synthetic,
              saveError: saveError,
              onSelect: onSelect,
              onRetry: onRetry,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<UnitsController> pumpHost(
    WidgetTester tester, {
    required UnitsController units,
    bool synthetic = true,
    double scale = 1,
    double width = 393,
    double height = 852,
    Locale locale = const Locale('de'),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(units.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<UnitsController>.value(
        value: units,
        child: ListenableBuilder(
          listenable: units,
          builder: (context, _) => MaterialApp(
            locale: locale,
            debugShowCheckedModeBanner: false,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('de'), Locale('en')],
            theme: openBandTheme(
              Brightness.light,
            ).copyWith(platform: TargetPlatform.iOS),
            darkTheme: openBandTheme(
              Brightness.dark,
            ).copyWith(platform: TargetPlatform.iOS),
            themeMode: ThemeMode.light,
            themeAnimationDuration: Duration.zero,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.only(top: 59, bottom: 34),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: UnitsSettings(controller: units, synthetic: synthetic),
          ),
        ),
      ),
    );
    await tester.pump();
    return units;
  }

  Future<void> pumpPushed(
    WidgetTester tester, {
    required UnitsController units,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(units.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<UnitsController>.value(
        value: units,
        child: ListenableBuilder(
          listenable: units,
          builder: (context, _) => MaterialApp(
            locale: const Locale('de'),
            debugShowCheckedModeBanner: false,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('de'), Locale('en')],
            theme: openBandTheme(
              Brightness.light,
            ).copyWith(platform: TargetPlatform.iOS),
            darkTheme: openBandTheme(
              Brightness.dark,
            ).copyWith(platform: TargetPlatform.iOS),
            themeMode: ThemeMode.light,
            themeAnimationDuration: Duration.zero,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 59, bottom: 34),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => UnitsSettings(
                          controller: units,
                          synthetic: true,
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  test('Paper preview uses UnitsController conversion', () {
    final metric = unitsPreviewSamples(UnitSystem.metric);
    expect(metric.distance, '5,00 km');
    expect(metric.pace, '5:00 /km');
    expect(metric.weight, '70 kg');
    expect(metric.height, '180 cm');
    final imperial = unitsPreviewSamples(UnitSystem.imperial);
    expect(imperial.distance, '3,11 mi');
    expect(imperial.pace, '8:03 /mi');
    expect(imperial.weight, '154 lb');
    expect(imperial.height, '5′11″');
  });

  testWidgets('Paper units frames', (tester) async {
    await pumpView(tester);
    expect(find.text('EINHEITEN'), findsOneWidget);
    expect(find.text('Metrisch'), findsOneWidget);
    expect(find.text('Imperial'), findsOneWidget);
    expect(find.text('Beispiel'), findsOneWidget);
    expect(find.text('Entfernung'), findsOneWidget);
    expect(find.text('5,00 km'), findsOneWidget);
    expect(find.text('5:00 /km'), findsOneWidget);
    expect(find.text('70 kg'), findsOneWidget);
    expect(find.text('180 cm'), findsOneWidget);
    expect(find.text('Synthetische Daten'), findsOneWidget);
    expect(find.byTooltip('Information'), findsNothing);
    expect(find.byKey(const ValueKey('units-preview-row')), findsOneWidget);
    expect(
      (tester.getRect(find.text('Entfernung')).center.dy -
              tester.getRect(find.text('5,00 km')).center.dy)
          .abs(),
      lessThan(2),
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/units-light.png'),
    );

    await pumpView(tester, selected: UnitSystem.imperial);
    expect(find.text('3,11 mi'), findsOneWidget);
    expect(find.text('8:03 /mi'), findsOneWidget);
    expect(find.text('154 lb'), findsOneWidget);
    expect(find.text('5′11″'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/units-imperial.png'),
    );

    await pumpView(
      tester,
      selected: UnitSystem.metric,
      brightness: Brightness.dark,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/units-dark.png'),
    );

    await pumpView(
      tester,
      selected: UnitSystem.imperial,
      brightness: Brightness.dark,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/units-imperial-dark.png'),
    );

    await pumpView(
      tester,
      saveError: 'Speichern fehlgeschlagen',
      onRetry: () {},
    );
    expect(find.byKey(const ValueKey('units-error')), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    expect(find.text('5,00 km'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/units-error.png'),
    );

    await pumpView(
      tester,
      selected: UnitSystem.metric,
      brightness: Brightness.dark,
      saveError: 'Speichern fehlgeschlagen',
      onRetry: () {},
    );
    expect(find.byKey(const ValueKey('units-error')), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('units-choice-metric')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/units-error-dark.png'),
    );

    await pumpView(
      tester,
      width: 375,
      height: 812,
      scale: 2,
      selected: UnitSystem.metric,
    );
    expect(tester.takeException(), isNull);
    final metric = tester.getRect(
      find.byKey(const ValueKey('units-choice-metric')),
    );
    expect(metric.height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byIcon(LucideIcons.check)), const Size(18, 18));
    expect(find.byKey(const ValueKey('units-preview-stacked')), findsOneWidget);
    _expectStackedUnbroken(tester, 'Entfernung', '5,00 km');
    _expectStackedUnbroken(tester, 'Tempo', '5:00 /km');
    _expectStackedUnbroken(tester, 'Gewicht', '70 kg');
    _expectStackedUnbroken(tester, 'Größe', '180 cm');
    expect(
      tester
          .getSize(find.byKey(const ValueKey('units-preview-distance')))
          .height,
      100,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/units-large.png'),
    );

    await pumpView(
      tester,
      width: 375,
      height: 812,
      scale: 2,
      selected: UnitSystem.metric,
      brightness: Brightness.dark,
    );
    expect(find.byKey(const ValueKey('units-preview-stacked')), findsOneWidget);
    _expectStackedUnbroken(tester, 'Entfernung', '5,00 km');
    expect(
      tester
          .getSize(find.byKey(const ValueKey('units-preview-distance')))
          .height,
      100,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/units-large-dark.png'),
    );

    await pumpView(
      tester,
      width: 375,
      height: 812,
      scale: 2,
      selected: UnitSystem.imperial,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('units-preview-stacked')), findsOneWidget);
    _expectStackedUnbroken(tester, 'Entfernung', '3,11 mi');
    _expectStackedUnbroken(tester, 'Tempo', '8:03 /mi');
    _expectStackedUnbroken(tester, 'Gewicht', '154 lb');
    _expectStackedUnbroken(tester, 'Größe', '5′11″');
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/units-large-imperial.png'),
    );
  }, tags: const ['golden']);

  testWidgets('production omits the synthetic footer', (tester) async {
    await pumpView(tester, synthetic: false);
    expect(find.text('Beispiel'), findsOneWidget);
    expect(find.text('Synthetische Daten'), findsNothing);
    expect(find.byKey(const ValueKey('units-synthetic')), findsNothing);
  });

  testWidgets('English labels and selected semantics', (tester) async {
    await pumpView(
      tester,
      locale: const Locale('en'),
      selected: UnitSystem.imperial,
      onSelect: (_) {},
    );
    expect(find.text('UNITS'), findsOneWidget);
    expect(find.text('Metric'), findsOneWidget);
    expect(find.text('Imperial'), findsOneWidget);
    expect(find.text('Metrisch'), findsNothing);
    expect(find.text('Beispiel'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('units-choice-imperial')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('units-choice-metric')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isNot(true),
    );
  });

  testWidgets('settings units row navigates and keeps the summary', (
    tester,
  ) async {
    var opened = 0;
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        theme: buildTheme(Brightness.light),
        home: MoreSettingsView(
          units: 'Metrisch',
          onOpenUnits: () => opened++,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Metrisch'), findsOneWidget);
    await tester.ensureVisible(find.text('Metrisch'));
    await tester.tap(find.text('Metrisch'));
    await tester.pump();
    expect(opened, 1);
    expect(find.text('Metrisch'), findsOneWidget);
    expect(find.text('Imperial'), findsNothing);
  });

  testWidgets('busy blocks a second tap', (tester) async {
    final taps = <UnitSystem>[];
    await pumpView(
      tester,
      busy: true,
      onSelect: taps.add,
    );
    await tester.tap(find.byKey(const ValueKey('units-choice-imperial')));
    await tester.pump();
    expect(taps, isEmpty);
  });

  testWidgets('busy disables retry', (tester) async {
    var taps = 0;
    await pumpView(
      tester,
      busy: true,
      saveError: 'Speichern fehlgeschlagen',
      onRetry: () => taps++,
    );
    expect(find.byKey(const ValueKey('units-error')), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('selection persists and reopens', (tester) async {
    final stored = <String, String>{};
    final units = UnitsController.seed(
      UnitSystem.metric,
      persist: (system) async {
        stored['units_system'] = system.name;
        return true;
      },
    );
    await pumpHost(tester, units: units);
    expect(units.system, UnitSystem.metric);
    expect(find.text('5,00 km'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('units-choice-imperial')));
    await tester.pumpAndSettle();
    expect(units.system, UnitSystem.imperial);
    expect(stored['units_system'], 'imperial');
    expect(find.text('3,11 mi'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('units-choice-imperial')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );

    SharedPreferences.setMockInitialValues({'units_system': 'imperial'});
    final reopened = await UnitsController.bootstrap();
    addTearDown(reopened.dispose);
    expect(reopened.system, UnitSystem.imperial);
  });

  testWidgets('screen busy blocks a second choice until persist settles', (
    tester,
  ) async {
    final gate = Completer<bool>();
    var calls = 0;
    final units = UnitsController.seed(
      UnitSystem.metric,
      persist: (_) {
        calls++;
        return gate.future;
      },
    );
    await pumpHost(tester, units: units);
    await tester.tap(find.byKey(const ValueKey('units-choice-imperial')));
    await tester.pump();
    expect(find.text('5,00 km'), findsOneWidget);
    expect(find.text('3,11 mi'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('units-choice-metric')));
    await tester.pump();
    expect(calls, 1);
    expect(units.system, UnitSystem.metric);
    gate.complete(true);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(units.system, UnitSystem.imperial);
    expect(find.text('3,11 mi'), findsOneWidget);
  });

  testWidgets('back during pending failed save keeps retry', (tester) async {
    final started = Completer<void>();
    final pending = Completer<bool>();
    var calls = 0;
    final units = UnitsController.seed(
      UnitSystem.metric,
      persist: (_) {
        calls++;
        if (calls == 1) {
          started.complete();
          return pending.future;
        }
        return Future<bool>.value(true);
      },
    );
    await pumpPushed(tester, units: units);
    await tester.tap(find.byKey(const ValueKey('units-choice-imperial')));
    await started.future;
    await tester.pump();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pump();
    expect(find.text('EINHEITEN'), findsOneWidget);
    expect(find.text('Erneut'), findsNothing);
    expect(
      tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop,
      isFalse,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('EINHEITEN'), findsOneWidget);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('EINHEITEN'), findsOneWidget);
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    expect(units.system, UnitSystem.metric);
    expect(find.text('5,00 km'), findsOneWidget);
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(units.system, UnitSystem.imperial);
    expect(find.text('3,11 mi'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Einheiten'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('successful save unlocks back', (tester) async {
    final started = Completer<void>();
    final pending = Completer<bool>();
    final units = UnitsController.seed(
      UnitSystem.metric,
      persist: (_) {
        started.complete();
        return pending.future;
      },
    );
    await pumpPushed(tester, units: units);
    await tester.tap(find.byKey(const ValueKey('units-choice-imperial')));
    await started.future;
    await tester.pump();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pump();
    expect(find.text('EINHEITEN'), findsOneWidget);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(units.system, UnitSystem.imperial);
    expect(find.text('EINHEITEN'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Einheiten'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('failed save keeps committed system and retry writes it', (
    tester,
  ) async {
    var fail = true;
    final stored = <String?>[null];
    final units = UnitsController.seed(
      UnitSystem.metric,
      persist: (system) async {
        if (fail) return false;
        stored[0] = system.name;
        return true;
      },
    );
    await pumpHost(tester, units: units);
    await tester.tap(find.byKey(const ValueKey('units-choice-imperial')));
    await tester.pumpAndSettle();
    expect(units.system, UnitSystem.metric);
    expect(find.text('5,00 km'), findsOneWidget);
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('units-choice-metric')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('units-choice-imperial')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isNot(true),
    );

    fail = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(units.system, UnitSystem.imperial);
    expect(stored[0], 'imperial');
    expect(find.text('3,11 mi'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('units-choice-imperial')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );
  });

  testWidgets(
    'review pumps nested routes without ModalRoute.of and keeps a spinner',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Widget host({required Key key}) => MaterialApp(
        key: key,
        debugShowCheckedModeBanner: false,
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        home: Navigator(
          onGenerateRoute: (settings) {
            if (settings.name == '/child') {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const Scaffold(
                  body: Column(
                    children: [
                      CircularProgressIndicator(),
                      Text('child'),
                    ],
                  ),
                ),
              );
            }
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    const CircularProgressIndicator(),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/child'),
                      child: const Text('open'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      await tester.pumpWidget(host(key: UniqueKey()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await reviewPumpPageTransitions(tester);
      await reviewPumpPresentedFrame(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(host(key: UniqueKey()));
      await tester.pump();
      await reviewPumpPageTransitions(tester);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('open'));
      await tester.pump();
      expect(reviewPageTransitionRunning(tester), isTrue);
      await reviewPumpPageTransitions(tester);
      expect(reviewPageTransitionRunning(tester), isFalse);
      expect(find.text('child'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review treats a dismissed enter animation as still in flight',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final primary = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 300),
      );
      addTearDown(primary.dispose);

      Widget page() => Directionality(
        textDirection: TextDirection.ltr,
        child: CupertinoPageTransition(
          primaryRouteAnimation: primary,
          secondaryRouteAnimation: kAlwaysDismissedAnimation,
          linearTransition: true,
          child: const Text('page'),
        ),
      );

      await tester.pumpWidget(page());
      expect(primary.isAnimating, isFalse);
      expect(primary.value, 0);
      expect(reviewPageTransitionRunning(tester), isTrue);

      primary.value = 1;
      await tester.pump();
      expect(primary.isAnimating, isFalse);
      expect(reviewPageTransitionRunning(tester), isFalse);
    },
  );

  testWidgets('covered secondary 1 is a settled background route', (
    tester,
  ) async {
    expect(
      reviewTransitionUnsettled(
        kAlwaysCompleteAnimation,
        kAlwaysCompleteAnimation,
      ),
      isFalse,
    );
    final secondary = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 300),
      value: 0.5,
    );
    addTearDown(secondary.dispose);
    expect(
      reviewTransitionUnsettled(kAlwaysCompleteAnimation, secondary),
      isTrue,
    );
    secondary.value = 1;
    expect(
      reviewTransitionUnsettled(kAlwaysCompleteAnimation, secondary),
      isFalse,
    );
  });

  test('review timing fence rejects stale batches', () {
    FrameTiming timing(int frameNumber) => FrameTiming(
      vsyncStart: 0,
      buildStart: 0,
      buildFinish: 0,
      rasterStart: 0,
      rasterFinish: 0,
      rasterFinishWallTime: 0,
      frameNumber: frameNumber,
    );
    expect(reviewTimingContainsFrame([timing(3), timing(4)], null), isFalse);
    expect(reviewTimingContainsFrame([timing(3), timing(4)], 7), isFalse);
    expect(reviewTimingContainsFrame([timing(3), timing(7)], 7), isTrue);
    expect(reviewTimingContainsFrame(const [], 7), isFalse);
  });
}

void _expectSingleLine(WidgetTester tester, String text) {
  final render = tester.renderObject<RenderParagraph>(find.text(text));
  expect(
    render.size.height,
    lessThanOrEqualTo(render.textScaler.scale(20) + 1),
    reason: '$text must stay on one line',
  );
}

void _expectStackedUnbroken(WidgetTester tester, String label, String value) {
  _expectSingleLine(tester, label);
  _expectSingleLine(tester, value);
  final labelRect = tester.getRect(find.text(label));
  final valueRect = tester.getRect(find.text(value));
  expect(
    labelRect.bottom,
    lessThanOrEqualTo(valueRect.top + 1),
    reason: '$label must stack above $value',
  );
  expect(
    valueRect.top - labelRect.bottom,
    closeTo(4, 1),
    reason: '$label/$value stacked gap is 4',
  );
}
