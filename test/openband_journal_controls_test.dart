import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/journal_controls.dart';
import 'package:openstrap_edge/openband/theme.dart';

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

  Future<void> openHost(
    WidgetTester tester, {
    double width = 393,
    double height = 852,
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 59, bottom: 34),
            viewInsets: EdgeInsets.zero,
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
  }

  testWidgets('action result closes the sheet and returns the id', (
    tester,
  ) async {
    await openHost(tester);
    final future = showOpenBandJournalInfo(
      tester.element(find.byType(Scaffold)),
      title: 'Vergleich',
      body:
          'Verglichen wird die letzte gespeicherte Nacht je Messwert.\n'
          '21 Tage davor: mindestens zwei Nächte.',
      actions: const [
        OBInfoSheetAction(id: 'rhr', label: 'Ruhepuls · Quellen'),
        OBInfoSheetAction(id: 'hrv', label: 'HRV · Quellen'),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Ruhepuls · Quellen'), findsOneWidget);
    expect(find.text('HRV · Quellen'), findsOneWidget);
    expect(find.text('Schließen'), findsOneWidget);
    await tester.tap(find.text('Ruhepuls · Quellen'));
    await tester.pumpAndSettle();
    expect(await future, 'rhr');
    expect(find.text('Schließen'), findsNothing);
    expect(find.text('Ruhepuls · Quellen'), findsNothing);
  });

  testWidgets('2x keeps body scrollable and close pinned', (tester) async {
    await openHost(tester, width: 375, height: 812, scale: 2);
    showOpenBandJournalInfo(
      tester.element(find.byType(Scaffold)),
      title: 'Vergleich',
      body:
          'Verglichen wird die letzte gespeicherte Nacht je Messwert. Die Differenz bezieht sich auf den Mittelwert der genannten Nächte.\n'
          '21 Tage davor: mindestens zwei Nächte. Gleicher Zyklustag: mindestens drei frühere Zyklen im gewählten Zeitraum. Abstände über 60 Tage werden nicht zugeordnet.\n'
          'Ein sehr langer Hinweistext prüft, dass Aktionen im Körper scrollen.\n'
          'Zweiter Block: Wiederholte Sätze halten den Block deutlich über die Bildschirmhöhe.\n'
          'Dritter Block: Wiederholte Sätze halten den Block deutlich über die Bildschirmhöhe.',
      actions: const [
        OBInfoSheetAction(id: 'rhr', label: 'Ruhepuls · Quellen'),
      ],
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
    final close = find.widgetWithText(OBAction, 'Schließen');
    expect(close.hitTestable(), findsOneWidget);
    final closeRect = tester.getRect(close);
    expect(closeRect.bottom, lessThanOrEqualTo(812 - 34 + 1));
    final body = find.byKey(const ValueKey('journal-info-body'));
    expect(body, findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Ruhepuls · Quellen'),
      80,
      scrollable: find.descendant(of: body, matching: find.byType(Scrollable)),
    );
    expect(find.text('Ruhepuls · Quellen'), findsOneWidget);
    expect(close.hitTestable(), findsOneWidget);
  });

  testWidgets('existing callers without actions still close only', (
    tester,
  ) async {
    await openHost(tester);
    showOpenBandJournalInfo(
      tester.element(find.byType(Scaffold)),
      title: 'Ernährungsziele',
      body: 'Eigene Tagesziele, keine Bedarfsschätzung.',
    );
    await tester.pumpAndSettle();
    expect(find.text('Ruhepuls · Quellen'), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('Schließen'), findsNothing);
  });
}
