import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/appearance.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';
import 'package:openstrap_edge/theme/tokens.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    AppThemeChoice selected = AppThemeChoice.system,
    bool busy = false,
    bool synthetic = true,
    String? saveError,
    ValueChanged<AppThemeChoice>? onSelect,
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
            child: AppearanceSettingsView(
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

  Future<ThemeController> pumpHost(
    WidgetTester tester, {
    required ThemeController theme,
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
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: ListenableBuilder(
          listenable: theme,
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
            themeMode: theme.materialThemeMode,
            themeAnimationDuration: Duration.zero,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.only(top: 59, bottom: 34),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: AppearanceSettings(controller: theme, synthetic: synthetic),
          ),
        ),
      ),
    );
    await tester.pump();
    return theme;
  }

  Future<void> pumpPushed(
    WidgetTester tester, {
    required ThemeController theme,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: ListenableBuilder(
          listenable: theme,
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
            themeMode: theme.materialThemeMode,
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
                        builder: (_) => AppearanceSettings(
                          controller: theme,
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

  Brightness hostBrightness(WidgetTester tester) => Theme.of(
    tester.element(find.byType(AppearanceSettings)),
  ).brightness;

  testWidgets('Paper appearance frames', (tester) async {
    await pumpView(tester);
    expect(find.text('DARSTELLUNG'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Hell'), findsOneWidget);
    expect(find.text('Dunkel'), findsOneWidget);
    expect(find.text('Synthetische Daten'), findsOneWidget);
    expect(find.byTooltip('Information'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/appearance-light.png'),
    );

    await pumpView(tester, selected: AppThemeChoice.dark, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/appearance-dark.png'),
    );

    await pumpView(
      tester,
      saveError: 'Speichern fehlgeschlagen',
      onRetry: () {},
    );
    expect(find.byKey(const ValueKey('appearance-error')), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/appearance-error.png'),
    );

    await pumpView(
      tester,
      selected: AppThemeChoice.dark,
      brightness: Brightness.dark,
      saveError: 'Speichern fehlgeschlagen',
      onRetry: () {},
    );
    expect(find.byKey(const ValueKey('appearance-error')), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('appearance-choice-dark')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/appearance-error-dark.png'),
    );

    await pumpView(
      tester,
      width: 375,
      height: 812,
      scale: 2,
      selected: AppThemeChoice.system,
    );
    expect(tester.takeException(), isNull);
    final system = tester.getRect(
      find.byKey(const ValueKey('appearance-choice-system')),
    );
    expect(system.height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byIcon(LucideIcons.check)), const Size(18, 18));
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/appearance-large.png'),
    );
  });

  testWidgets('English labels and selected semantics', (tester) async {
    await pumpView(
      tester,
      locale: const Locale('en'),
      selected: AppThemeChoice.light,
      onSelect: (_) {},
    );
    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Hell'), findsNothing);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('appearance-choice-light')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('appearance-choice-system')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isNot(true),
    );
  });

  testWidgets('busy blocks a second tap', (tester) async {
    final taps = <AppThemeChoice>[];
    await pumpView(
      tester,
      busy: true,
      onSelect: taps.add,
    );
    await tester.tap(find.byKey(const ValueKey('appearance-choice-dark')));
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
    expect(find.byKey(const ValueKey('appearance-error')), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    await tester.tap(find.text('Erneut'));
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('selection persists, reopens, and follows OS brightness', (
    tester,
  ) async {
    final stored = <String, String>{};
    final theme = ThemeController.seed(
      AppThemeChoice.system,
      Brightness.light,
      persist: (choice) async {
        stored['theme_choice'] = choice.name;
        return true;
      },
    );
    await pumpHost(tester, theme: theme);
    expect(theme.choice, AppThemeChoice.system);
    expect(theme.effective, Brightness.light);
    expect(AppColors.active, kLightPalette);

    await tester.tap(find.byKey(const ValueKey('appearance-choice-dark')));
    await tester.pumpAndSettle();
    expect(theme.choice, AppThemeChoice.dark);
    expect(theme.effective, Brightness.dark);
    expect(hostBrightness(tester), Brightness.dark);
    expect(stored['theme_choice'], 'dark');
    expect(AppColors.active, kDarkPalette);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('appearance-choice-dark')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );

    SharedPreferences.setMockInitialValues({'theme_choice': 'dark'});
    final reopened = await ThemeController.bootstrap();
    addTearDown(reopened.dispose);
    expect(reopened.choice, AppThemeChoice.dark);
    expect(reopened.effective, Brightness.dark);

    await tester.tap(find.byKey(const ValueKey('appearance-choice-system')));
    await tester.pumpAndSettle();
    expect(theme.choice, AppThemeChoice.system);
    expect(stored['theme_choice'], 'system');
    expect(hostBrightness(tester), Brightness.light);
    theme.updatePlatformBrightness(Brightness.dark);
    await tester.pumpAndSettle();
    expect(theme.effective, Brightness.dark);
    expect(hostBrightness(tester), Brightness.dark);
    expect(AppColors.active, kDarkPalette);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('appearance-choice-system')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );

    theme.updatePlatformBrightness(Brightness.light);
    await tester.pumpAndSettle();
    expect(theme.effective, Brightness.light);
    expect(hostBrightness(tester), Brightness.light);
    expect(AppColors.active, kLightPalette);

    await tester.tap(find.byKey(const ValueKey('appearance-choice-light')));
    await tester.pumpAndSettle();
    theme.updatePlatformBrightness(Brightness.dark);
    await tester.pumpAndSettle();
    expect(theme.choice, AppThemeChoice.light);
    expect(theme.effective, Brightness.light);
    expect(hostBrightness(tester), Brightness.light);
    expect(AppColors.active, kLightPalette);
  });

  testWidgets('screen busy blocks a second choice until persist settles', (
    tester,
  ) async {
    final gate = Completer<bool>();
    var calls = 0;
    final theme = ThemeController.seed(
      AppThemeChoice.system,
      Brightness.light,
      persist: (_) {
        calls++;
        return gate.future;
      },
    );
    await pumpHost(tester, theme: theme);
    await tester.tap(find.byKey(const ValueKey('appearance-choice-dark')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('appearance-choice-light')));
    await tester.pump();
    expect(calls, 1);
    expect(theme.choice, AppThemeChoice.system);
    gate.complete(true);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(theme.choice, AppThemeChoice.dark);
  });

  testWidgets('back during pending failed save keeps retry', (tester) async {
    final started = Completer<void>();
    final pending = Completer<bool>();
    var calls = 0;
    final theme = ThemeController.seed(
      AppThemeChoice.system,
      Brightness.light,
      persist: (_) {
        calls++;
        if (calls == 1) {
          started.complete();
          return pending.future;
        }
        return Future<bool>.value(true);
      },
    );
    await pumpPushed(tester, theme: theme);
    await tester.tap(find.byKey(const ValueKey('appearance-choice-dark')));
    await started.future;
    await tester.pump();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pump();
    expect(find.text('DARSTELLUNG'), findsOneWidget);
    expect(find.text('Erneut'), findsNothing);
    expect(
      tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop,
      isFalse,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('DARSTELLUNG'), findsOneWidget);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('DARSTELLUNG'), findsOneWidget);
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    expect(theme.choice, AppThemeChoice.system);
    expect(hostBrightness(tester), Brightness.light);
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(theme.choice, AppThemeChoice.dark);
    expect(hostBrightness(tester), Brightness.dark);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Darstellung'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('successful save unlocks back', (tester) async {
    final started = Completer<void>();
    final pending = Completer<bool>();
    final theme = ThemeController.seed(
      AppThemeChoice.system,
      Brightness.light,
      persist: (_) {
        started.complete();
        return pending.future;
      },
    );
    await pumpPushed(tester, theme: theme);
    await tester.tap(find.byKey(const ValueKey('appearance-choice-dark')));
    await started.future;
    await tester.pump();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pump();
    expect(find.text('DARSTELLUNG'), findsOneWidget);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(theme.choice, AppThemeChoice.dark);
    expect(find.text('DARSTELLUNG'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Darstellung'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('failed save keeps committed choice and retry writes it', (
    tester,
  ) async {
    var fail = true;
    final stored = <String?>[null];
    final theme = ThemeController.seed(
      AppThemeChoice.system,
      Brightness.light,
      persist: (choice) async {
        if (fail) return false;
        stored[0] = choice.name;
        return true;
      },
    );
    await pumpHost(tester, theme: theme);
    await tester.tap(find.byKey(const ValueKey('appearance-choice-dark')));
    await tester.pumpAndSettle();
    expect(theme.choice, AppThemeChoice.system);
    expect(hostBrightness(tester), Brightness.light);
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('appearance-choice-system')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('appearance-choice-dark')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isNot(true),
    );

    fail = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(theme.choice, AppThemeChoice.dark);
    expect(hostBrightness(tester), Brightness.dark);
    expect(stored[0], 'dark');
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('appearance-choice-dark')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );
  });

  test('overlapping setChoice cannot apply out of order', () async {
    final darkStarted = Completer<void>();
    final darkGate = Completer<void>();
    final writes = <AppThemeChoice>[];
    final theme = ThemeController.seed(
      AppThemeChoice.system,
      Brightness.light,
      persist: (choice) async {
        writes.add(choice);
        if (choice == AppThemeChoice.dark) {
          darkStarted.complete();
          await darkGate.future;
        }
        return true;
      },
    );
    addTearDown(theme.dispose);
    final first = theme.setChoice(AppThemeChoice.dark);
    await darkStarted.future;
    final second = theme.setChoice(AppThemeChoice.light);
    expect(theme.choice, AppThemeChoice.system);
    darkGate.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(theme.choice, AppThemeChoice.light);
    expect(writes, [AppThemeChoice.dark, AppThemeChoice.light]);
  });

  test('successful first persist stays visible if the later write fails', () async {
    SharedPreferences.setMockInitialValues({});
    final darkStarted = Completer<void>();
    final darkGate = Completer<void>();
    final theme = ThemeController.seed(
      AppThemeChoice.system,
      Brightness.light,
      persist: (choice) async {
        if (choice == AppThemeChoice.dark) {
          darkStarted.complete();
          await darkGate.future;
        }
        if (choice == AppThemeChoice.light) return false;
        final prefs = await SharedPreferences.getInstance();
        return prefs.setString('theme_choice', choice.name);
      },
    );
    addTearDown(theme.dispose);
    final first = theme.setChoice(AppThemeChoice.dark);
    await darkStarted.future;
    final second = theme.setChoice(AppThemeChoice.light);
    expect(theme.choice, AppThemeChoice.system);
    darkGate.complete();
    expect(await first, isTrue);
    expect(await second, isFalse);
    expect(theme.choice, AppThemeChoice.dark);
    expect(
      (await SharedPreferences.getInstance()).getString('theme_choice'),
      'dark',
    );
    final reopened = await ThemeController.bootstrap();
    addTearDown(reopened.dispose);
    expect(reopened.choice, AppThemeChoice.dark);
  });

  test('dispose during persist still records the saved choice', () async {
    final started = Completer<void>();
    final gate = Completer<bool>();
    final theme = ThemeController.seed(
      AppThemeChoice.system,
      Brightness.light,
      persist: (_) async {
        started.complete();
        return gate.future;
      },
    );
    final pending = theme.setChoice(AppThemeChoice.dark);
    await started.future;
    theme.dispose();
    gate.complete(true);
    expect(await pending, isTrue);
    expect(theme.choice, AppThemeChoice.dark);
  });

  test('false persist and thrown persist keep the last committed choice', () async {
    final theme = ThemeController.seed(
      AppThemeChoice.system,
      Brightness.light,
      persist: (_) async => false,
    );
    addTearDown(theme.dispose);
    expect(await theme.setChoice(AppThemeChoice.dark), isFalse);
    expect(theme.choice, AppThemeChoice.system);

    final throwing = ThemeController.seed(
      AppThemeChoice.light,
      Brightness.light,
      persist: (_) async => throw Exception('disk'),
    );
    addTearDown(throwing.dispose);
    expect(await throwing.setChoice(AppThemeChoice.dark), isFalse);
    expect(throwing.choice, AppThemeChoice.light);
  });

  test('default persist writes theme_choice', () async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController.seed(
      AppThemeChoice.system,
      Brightness.light,
    );
    addTearDown(theme.dispose);
    expect(await theme.setChoice(AppThemeChoice.dark), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_choice'), 'dark');
    expect(theme.choice, AppThemeChoice.dark);
  });

  testWidgets('bootstrap reads theme_choice and follows OS for system', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'theme_choice': 'light'});
    final light = await ThemeController.bootstrap();
    addTearDown(light.dispose);
    expect(light.choice, AppThemeChoice.light);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    SharedPreferences.setMockInitialValues({});
    final system = await ThemeController.bootstrap();
    addTearDown(system.dispose);
    expect(system.choice, AppThemeChoice.system);
    expect(system.effective, Brightness.dark);
  });
}
