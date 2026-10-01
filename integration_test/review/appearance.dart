part of 'harness.dart';

Future<void> reviewAppearance(ReviewHarness h) async {
  final tester = h.tester;
  Future<void> mountAppearance({
    required Brightness brightness,
    AppThemeChoice selected = AppThemeChoice.system,
    String? saveError,
    double? scale,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale ?? 1)),
          child: child!,
        ),
        home: AppearanceSettingsView(
          selected: selected,
          synthetic: true,
          saveError: saveError,
          onSelect: (_) {},
          onRetry: saveError == null ? null : () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  await mountAppearance(brightness: Brightness.light);
  expect(find.bySemanticsLabel('Darstellung'), findsOneWidget);
  expect(find.text('System'), findsOneWidget);
  await h.capture('appearance-light');
  await mountAppearance(
    brightness: Brightness.dark,
    selected: AppThemeChoice.dark,
  );
  await h.capture('appearance-dark');
  await mountAppearance(
    brightness: Brightness.light,
    saveError: 'Speichern fehlgeschlagen',
  );
  expect(find.text('Erneut'), findsOneWidget);
  await h.capture('appearance-error');
  await mountAppearance(
    brightness: Brightness.dark,
    selected: AppThemeChoice.dark,
    saveError: 'Speichern fehlgeschlagen',
  );
  expect(find.text('Erneut'), findsOneWidget);
  await h.capture('appearance-error-dark');
  await mountAppearance(brightness: Brightness.light, scale: 2);
  await h.capture('appearance-large');

  var failAppearance = true;
  var liveTheme = ThemeController.seed(
    AppThemeChoice.system,
    Brightness.light,
    persist: (_) async {
      if (failAppearance) throw Exception('disk full');
      return true;
    },
  );
  try {
    Future<void> mountLiveAppearance() async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: liveTheme,
          child: ListenableBuilder(
            listenable: liveTheme,
            builder: (context, _) => MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('de'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              theme: openBandTheme(Brightness.light),
              darkTheme: openBandTheme(Brightness.dark),
              themeMode: liveTheme.materialThemeMode,
              themeAnimationDuration: Duration.zero,
              home: AppearanceSettings(synthetic: true, controller: liveTheme),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Brightness appearanceThemeBrightness() =>
        Theme.of(tester.element(find.byType(AppearanceSettings))).brightness;

    await mountLiveAppearance();
    await tester.tap(find.byKey(const ValueKey('appearance-choice-dark')));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(liveTheme.choice, AppThemeChoice.system);
    expect(appearanceThemeBrightness(), Brightness.light);
    await h.capture('appearance-live-save-failure');
    failAppearance = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(liveTheme.choice, AppThemeChoice.dark);
    expect(liveTheme.effective, Brightness.dark);
    expect(appearanceThemeBrightness(), Brightness.dark);
    await h.capture('appearance-live-save-retry');

    await tester.tap(find.byKey(const ValueKey('appearance-choice-system')));
    await tester.pumpAndSettle();
    expect(liveTheme.choice, AppThemeChoice.system);
    expect(liveTheme.effective, Brightness.light);
    expect(appearanceThemeBrightness(), Brightness.light);
    await h.capture('appearance-live-system');

    liveTheme.updatePlatformBrightness(Brightness.dark);
    await tester.pumpAndSettle();
    expect(liveTheme.choice, AppThemeChoice.system);
    expect(liveTheme.effective, Brightness.dark);
    expect(appearanceThemeBrightness(), Brightness.dark);
    await h.capture('appearance-live-system-os-dark');

    final reopenedChoice = liveTheme.choice;
    final previous = liveTheme;
    liveTheme = ThemeController.seed(
      reopenedChoice,
      Brightness.dark,
      persist: (_) async => true,
    );
    previous.dispose();
    await mountLiveAppearance();
    expect(liveTheme.choice, AppThemeChoice.system);
    expect(liveTheme.effective, Brightness.dark);
    expect(appearanceThemeBrightness(), Brightness.dark);
    await h.capture('appearance-live-reopen');
  } finally {
    liveTheme.dispose();
  }
}
