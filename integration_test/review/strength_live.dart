part of 'harness.dart';

Future<void> reviewStrengthLive(ReviewHarness h) async {
  final tester = h.tester;
  Future<SyntheticOpenBandRepository> openPaperLive({
    Brightness brightness = Brightness.light,
    double? scale,
    bool failWrites = false,
  }) async {
    final repository = await h.mount(brightness: brightness, scale: scale);
    final now = DateTime(2026, 9, 15, 18, 32, 14);
    await repository.seedPaperLiveStrength(
      startedAt: DateTime(2026, 9, 15, 18),
      now: now,
    );
    repository.failStrengthWrites = failWrites;
    final nav = tester
        .element(find.byType(AppShell).first)
        .findAncestorStateOfType<NavigatorState>();
    unawaited(
      nav!.push(
        MaterialPageRoute<void>(
          builder: (_) => OpenBandStrengthLive.resume(
            repository: repository,
            now: () => now,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return repository;
  }

  Finder inBank(Finder matching) => find.descendant(
    of: find.ancestor(
      of: find.text('Bankdrücken'),
      matching: find.byType(OBExerciseBlock),
    ),
    matching: matching,
  );

  // InkRipple._kFadeOutDuration=375ms; InkSparkle=617ms. 200ms theme
  // duration ends while confirmed ripple is still opaque (fade starts
  // 225/375). Cap stays under the 1s rest tick.
  Future<void> settleLiveTransition() async {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 16),
      EnginePhase.sendSemanticsUpdate,
      const Duration(milliseconds: 800),
    );
  }

  await openPaperLive();
  expect(find.text('1:24'), findsOneWidget);
  expect(
    Theme.of(tester.element(find.byType(OpenBandStrengthLive))).brightness,
    Brightness.light,
  );
  await h.capture('strength-live-light');

  await openPaperLive();
  await tester.tap(inBank(find.byTooltip('Übungsmenü')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('Satz 3 überspringen'), findsOneWidget);
  await h.capture('strength-menu');

  await openPaperLive();
  await tester.tap(inBank(find.byTooltip('Übungsmenü')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Satz 3 überspringen'));
  await settleLiveTransition();
  expect(find.text('Satz 3 überspringen'), findsNothing);
  expect(inBank(find.text('Übersprungen')), findsOneWidget);
  await h.capture('strength-skipped');

  await openPaperLive();
  await tester.tap(inBank(find.byTooltip('Satz hinzufügen')));
  await settleLiveTransition();
  expect(inBank(find.text('5')), findsOneWidget);
  await h.capture('strength-add');

  final failingLive = await openPaperLive(failWrites: true);
  final failNow = DateTime(2026, 9, 15, 18, 32, 14);
  expect(inBank(find.byTooltip('Satz 3 bestätigen')), findsOneWidget);
  await tester.tap(inBank(find.byTooltip('Satz 3 bestätigen')));
  await settleLiveTransition();
  expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
  await h.capture('strength-save-failure');
  failingLive.failStrengthWrites = false;
  await tester.tap(find.text('Erneut'));
  await settleLiveTransition();
  expect(find.text('Speichern fehlgeschlagen'), findsNothing);
  await h.capture('strength-save-retry');
  await tester.tap(find.byTooltip('Einklappen'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  unawaited(
    tester
        .element(find.byType(AppShell).first)
        .findAncestorStateOfType<NavigatorState>()!
        .push(
          MaterialPageRoute<void>(
            builder: (_) => OpenBandStrengthLive.resume(
              repository: failingLive,
              now: () => failNow,
            ),
          ),
        ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('62,5'), findsWidgets);
  await h.capture('strength-resume');

  await openPaperLive(brightness: Brightness.dark);
  expect(
    Theme.of(tester.element(find.byType(OpenBandStrengthLive))).brightness,
    Brightness.dark,
  );
  expect(find.text('Übersprungen'), findsNothing);
  await h.capture('strength-live-dark');
  await openPaperLive(scale: 2);
  expect(find.text('+30 s').hitTestable(), findsOneWidget);
  await h.capture('strength-live-large');
  await tester.tap(find.byTooltip('Einklappen'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
