part of 'harness.dart';

Future<void> reviewUnits(ReviewHarness h) async {
  final tester = h.tester;
  Future<void> mountUnits({
    required Brightness brightness,
    UnitSystem selected = UnitSystem.metric,
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
        home: UnitsSettingsView(
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

  await mountUnits(brightness: Brightness.light);
  expect(find.text('Einheiten'), findsOneWidget);
  expect(find.text('Metrisch'), findsOneWidget);
  expect(find.text('5,00 km'), findsOneWidget);
  await h.capture('units-light');
  await mountUnits(brightness: Brightness.light, selected: UnitSystem.imperial);
  expect(find.text('3,11 mi'), findsOneWidget);
  await h.capture('units-imperial');
  await mountUnits(brightness: Brightness.dark, selected: UnitSystem.metric);
  await h.capture('units-dark');
  await mountUnits(brightness: Brightness.dark, selected: UnitSystem.imperial);
  await h.capture('units-imperial-dark');
  await mountUnits(
    brightness: Brightness.light,
    saveError: 'Speichern fehlgeschlagen',
  );
  expect(find.text('Erneut'), findsOneWidget);
  await h.capture('units-error');
  await mountUnits(
    brightness: Brightness.dark,
    selected: UnitSystem.metric,
    saveError: 'Speichern fehlgeschlagen',
  );
  expect(find.text('Erneut'), findsOneWidget);
  await h.capture('units-error-dark');
  await mountUnits(brightness: Brightness.light, scale: 2);
  expect(find.text('Entfernung'), findsOneWidget);
  expect(find.text('5,00 km'), findsOneWidget);
  expect(find.byKey(const ValueKey('units-preview-stacked')), findsOneWidget);
  await h.capture('units-large');
  await mountUnits(
    brightness: Brightness.dark,
    selected: UnitSystem.metric,
    scale: 2,
  );
  expect(find.text('Entfernung'), findsOneWidget);
  expect(find.byKey(const ValueKey('units-preview-stacked')), findsOneWidget);
  await h.capture('units-large-dark');
  await mountUnits(
    brightness: Brightness.light,
    selected: UnitSystem.imperial,
    scale: 2,
  );
  expect(find.text('3,11 mi'), findsOneWidget);
  expect(find.text('8:03 /mi'), findsOneWidget);
  expect(find.text('5′11″'), findsOneWidget);
  expect(find.byKey(const ValueKey('units-preview-stacked')), findsOneWidget);
  await h.capture('units-large-imperial');

  var failUnits = true;
  var liveUnits = UnitsController.seed(
    UnitSystem.metric,
    persist: (_) async {
      if (failUnits) throw Exception('disk full');
      return true;
    },
  );
  try {
    Future<void> mountLiveUnits() async {
      await tester.pumpWidget(
        ChangeNotifierProvider<UnitsController>.value(
          key: UniqueKey(),
          value: liveUnits,
          child: ListenableBuilder(
            listenable: liveUnits,
            builder: (context, _) => MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('de'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              theme: openBandTheme(Brightness.light),
              darkTheme: openBandTheme(Brightness.dark),
              themeMode: ThemeMode.light,
              themeAnimationDuration: Duration.zero,
              home: UnitsSettings(synthetic: true, controller: liveUnits),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await mountLiveUnits();
    await tester.tap(find.byKey(const ValueKey('units-choice-imperial')));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(liveUnits.system, UnitSystem.metric);
    expect(find.text('5,00 km'), findsOneWidget);
    await h.capture('units-live-save-failure');
    failUnits = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(liveUnits.system, UnitSystem.imperial);
    expect(find.text('3,11 mi'), findsOneWidget);
    await h.capture('units-live-save-retry');

    final reopenedSystem = liveUnits.system;
    final previousUnits = liveUnits;
    liveUnits = UnitsController.seed(
      reopenedSystem,
      persist: (_) async => true,
    );
    previousUnits.dispose();
    await mountLiveUnits();
    expect(liveUnits.system, UnitSystem.imperial);
    expect(find.text('3,11 mi'), findsOneWidget);
    await h.capture('units-live-reopen');
  } finally {
    liveUnits.dispose();
  }
}
