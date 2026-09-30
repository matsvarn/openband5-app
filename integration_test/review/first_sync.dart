part of 'harness.dart';

Future<void> reviewFirstSync(ReviewHarness h) async {
  final tester = h.tester;
  Future<void> mountFirstSync({
    Brightness brightness = Brightness.light,
    bool receiving = true,
    SetupEvalState evalState = SetupEvalState.missing,
    bool evalError = false,
    double scale = 1,
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
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: firstSyncGalleryFrame(
          brightness: brightness,
          receiving: receiving,
          evalState: evalState,
          evalError: evalError,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  await mountFirstSync();
  expect(find.text('Auswertung heute'), findsOneWidget);
  expect(find.text('bis 06:54'), findsOneWidget);
  await h.capture('first-sync-light');
  await tester.tap(find.byTooltip('Information'));
  await tester.pumpAndSettle();
  await h.capture('first-sync-info');
  await tester.tap(find.text('Schließen'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Weiter'));
  await tester.pumpAndSettle();
  await mountFirstSync(brightness: Brightness.dark);
  await h.capture('first-sync-dark');
  await mountFirstSync(receiving: false, evalState: SetupEvalState.complete);
  expect(find.text('07:12'), findsOneWidget);
  await h.capture('first-sync-complete');
  await mountFirstSync(
    brightness: Brightness.dark,
    evalState: SetupEvalState.partial,
  );
  expect(find.text('Teilweise'), findsOneWidget);
  await h.capture('first-sync-partial-dark');
  await mountFirstSync(evalError: true);
  expect(find.text('Auswertung nicht geladen'), findsOneWidget);
  await h.capture('first-sync-read-error');
  await tester.tap(find.text('Erneut'));
  await tester.pumpAndSettle();
  expect(find.text('Auswertung nicht geladen'), findsOneWidget);
  await h.capture('first-sync-read-error-retry');
  await mountFirstSync(scale: 2);
  expect(find.text('Auswertung heute'), findsOneWidget);
  await h.capture('first-sync-2x');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}
