part of 'harness.dart';

Future<void> reviewTrainingTemplates(ReviewHarness h) async {
  final tester = h.tester;
  await h.mount();
  await h.press('Training');
  await h.capture('training-hub');
  await tester.tap(find.text('Starten'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await h.capture('strength-live');
  await tester.tap(find.byTooltip('Einklappen'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  // 'Laufen' trifft Quick-Start-Tile und Zuletzt-Zeile; die Zeile ist letztere.
  await tester.ensureVisible(find.text('Laufen').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Laufen').last);
  await tester.pumpAndSettle();
  await h.capture('session-run');
  await reviewTapHeaderBack(tester);
  // Das Quick-Start-Tile liegt über der Liste; erst ganz nach oben
  // flingen (die Liste lädt Zeilen lazy — 'Laufen' allein trifft
  // sonst wieder die Zuletzt-Zeile).
  for (var i = 0; i < 5; i++) {
    await tester.fling(
      find.byType(Scrollable).last,
      const Offset(0, 500),
      3000,
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Laufen').first);
  await tester.pumpAndSettle();
  await h.capture('run-live');
  await tester.tap(find.bySemanticsLabel('Einheit einklappen'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Vorlagen'));
  await tester.pumpAndSettle();
  await h.capture('templates-list');
  await tester.tap(find.byTooltip('Aktionen').first);
  await tester.pumpAndSettle();
  await h.capture('templates-menu');
  await tester.tap(find.text('Anheften'));
  await tester.pumpAndSettle();
  await h.capture('templates-pinned');
  await tester.tap(find.byTooltip('Aktionen').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Bearbeiten'));
  await tester.pumpAndSettle();
  expect(find.byType(OpenBandTemplateEditor).hitTestable(), findsOneWidget);
  await h.capture('template-editor');
  await reviewTapHeaderBack(tester);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Neue Vorlage'));
  await tester.pumpAndSettle();
  await h.capture('template-editor-create');
  await reviewTapHeaderBack(tester);
  await tester.pumpAndSettle();
  await reviewTapHeaderBack(tester);
  await tester.pumpAndSettle();
  await h.capture('templates-hub');

  await h.mount(brightness: Brightness.dark);
  await h.press('Training');
  await tester.tap(find.byTooltip('Vorlagen'));
  await tester.pumpAndSettle();
  await h.capture('templates-dark');
  await tester.tap(find.byTooltip('Aktionen').first);
  await tester.pumpAndSettle();
  await h.capture('templates-menu-dark');
  await tester.tapAt(const Offset(10, 100));
  await tester.pumpAndSettle();

  final emptyTemplates = await h.mount();
  emptyTemplates.clearTemplates();
  await h.press('Training');
  await tester.tap(find.byTooltip('Vorlagen'));
  await tester.pumpAndSettle();
  expect(find.text('Keine Vorlagen'), findsOneWidget);
  await h.capture('templates-empty');

  final templateReadFail = await h.mount();
  templateReadFail.failTemplateRead = true;
  await h.press('Training');
  await tester.tap(find.byTooltip('Vorlagen'));
  await tester.pumpAndSettle();
  expect(find.text('Vorlagen konnten nicht geladen werden.'), findsOneWidget);
  expect(find.text('Keine Vorlagen'), findsNothing);
  await h.capture('templates-error');

  await h.mount(scale: 2);
  await h.press('Training');
  await tester.tap(find.byTooltip('Vorlagen'));
  await tester.pumpAndSettle();
  await h.capture('templates-2x');
}
