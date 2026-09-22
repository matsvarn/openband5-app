import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/alp_tokens.dart';
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

  const title = 'Ernährungsziele';
  const body =
      'Eigene Tagesziele, keine Bedarfsschätzung.\n'
      'Änderungen gelten ab dem gewählten Datum. Leere Felder haben kein Ziel.\n'
      'Die Energie aus Makros kann vom Energieziel abweichen.';

  const longBody =
      'Eigene Tagesziele, keine Bedarfsschätzung.\n'
      'Änderungen gelten ab dem gewählten Datum. Leere Felder haben kein Ziel.\n'
      'Die Energie aus Makros kann vom Energieziel abweichen.\n'
      'Ein sehr langer Hinweistext prüft, dass der Bogen bei großem Inhalt '
      'scrollt statt über den Viewport zu laufen. Wiederholte Sätze halten den '
      'Block deutlich über die Bildschirmhöhe.\n'
      'Zweiter Block: Wiederholte Sätze halten den Block deutlich über die '
      'Bildschirmhöhe und dürfen keine Overflow-Fehler erzeugen.\n'
      'Dritter Block: Wiederholte Sätze halten den Block deutlich über die '
      'Bildschirmhöhe und dürfen keine Overflow-Fehler erzeugen.\n'
      'Vierter Block: Wiederholte Sätze halten den Block deutlich über die '
      'Bildschirmhöhe und dürfen keine Overflow-Fehler erzeugen.\n'
      'Fünfter Block: Wiederholte Sätze halten den Block deutlich über die '
      'Bildschirmhöhe und dürfen keine Overflow-Fehler erzeugen.';

  const groupedParagraphs = [
    'RMSSD · gespeicherter Wert\n14.–15. September · 23:10–06:54',
    'Bandmessung · WHOOP 5.0\nBerechnet am 15. September, 07:02\nAlgorithmus 90',
    'Basis 40 ms · 30 gültige Nächte\nStatus: Verlässlich',
  ];

  Future<void> openSheet(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double width = 393,
    double height = 852,
    double scale = 1,
    String sheetTitle = title,
    String sheetBody = body,
    List<String>? sheetParagraphs,
    List<OBInfoSheetAction> actions = const [],
    OBInfoSheetAction? primaryAction,
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
    showOpenBandJournalInfo(
      tester.element(find.byType(Scaffold)),
      title: sheetTitle,
      body: sheetBody,
      paragraphs: sheetParagraphs,
      actions: actions,
      primaryAction: primaryAction,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders title, ink paragraphs and actions in light and dark', (
    tester,
  ) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await openSheet(tester, brightness: brightness, width: 375, height: 812);
      expect(find.text(title), findsOneWidget);
      expect(
        find.text('Eigene Tagesziele, keine Bedarfsschätzung.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Änderungen gelten ab dem gewählten Datum. Leere Felder haben kein Ziel.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Die Energie aus Makros kann vom Energieziel abweichen.'),
        findsOneWidget,
      );
      expect(find.text('Schließen'), findsOneWidget);
      expect(find.byIcon(LucideIcons.x), findsOneWidget);
      expect(find.text('Synthetische Daten'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      expect(tester.takeException(), isNull);

      final first = tester.getRect(
        find.text('Eigene Tagesziele, keine Bedarfsschätzung.'),
      );
      final second = tester.getRect(
        find.text(
          'Änderungen gelten ab dem gewählten Datum. Leere Felder haben kein Ziel.',
        ),
      );
      expect(second.top - first.bottom, closeTo(12, 1.5));
      expect(first.height, closeTo(22, 1.5));
      expect(
        find.text(
          'Eigene Tagesziele, keine Bedarfsschätzung.\n'
          'Änderungen gelten ab dem gewählten Datum. Leere Felder haben kein Ziel.',
        ),
        findsNothing,
      );

      final close = tester.getRect(find.byType(IconButton));
      expect(close.width, greaterThanOrEqualTo(44));
      expect(close.height, greaterThanOrEqualTo(44));

      final barriers = tester.widgetList<ModalBarrier>(
        find.byType(ModalBarrier),
      );
      expect(barriers.any((b) => b.color == const Color(0x52000000)), isTrue);
    }
  });

  testWidgets('375 and 320 keep minimum hits and stay inside the viewport', (
    tester,
  ) async {
    for (final width in [375.0, 320.0]) {
      await openSheet(tester, width: width, height: width == 320 ? 568 : 812);
      expect(tester.takeException(), isNull);
      expect(find.byIcon(LucideIcons.x), findsOneWidget);
      expect(find.text('Schließen'), findsOneWidget);
      final close = tester.getRect(find.byType(IconButton));
      expect(close.width, greaterThanOrEqualTo(44));
      expect(close.height, greaterThanOrEqualTo(44));
      final action = tester.getRect(find.byType(FilledButton));
      expect(action.height, greaterThanOrEqualTo(44));
      expect(action.width, greaterThanOrEqualTo(44));
      final screen = tester.getRect(find.byType(MaterialApp));
      expect(action.bottom, lessThanOrEqualTo(screen.bottom - 34));
    }
  });

  testWidgets('2x and long body scroll instead of overflowing', (tester) async {
    await openSheet(
      tester,
      width: 375,
      height: 812,
      scale: 2,
      sheetBody: longBody,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
    expect(find.text('Schließen'), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await openSheet(
      tester,
      width: 320,
      height: 568,
      scale: 2,
      sheetBody: longBody,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
    await tester.ensureVisible(find.text('Schließen'));
    expect(find.text('Schließen'), findsOneWidget);
  });

  testWidgets('320 2x long body keeps heading below real top 59', (
    tester,
  ) async {
    await openSheet(
      tester,
      width: 320,
      height: 812,
      scale: 2,
      sheetBody: longBody,
    );
    expect(tester.takeException(), isNull);
    final titleRect = tester.getRect(find.text(title));
    final closeRect = tester.getRect(find.byType(IconButton));
    expect(titleRect.top, greaterThanOrEqualTo(59));
    expect(closeRect.top, greaterThanOrEqualTo(59));
    await tester.ensureVisible(find.text('Schließen'));
    await tester.pumpAndSettle();
    final action = tester.getRect(find.byType(FilledButton));
    expect(action.height, greaterThanOrEqualTo(44));
    expect(action.top, greaterThanOrEqualTo(59));
    expect(action.bottom, lessThanOrEqualTo(812 - 34));
    expect(tester.takeException(), isNull);
  });

  testWidgets('close icon and Schließen both dismiss the sheet', (
    tester,
  ) async {
    await openSheet(tester);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.x), findsNothing);
    expect(find.text('Schließen'), findsNothing);

    showOpenBandJournalInfo(
      tester.element(find.byType(Scaffold)),
      title: title,
      body: body,
    );
    await tester.pumpAndSettle();
    expect(find.text('Schließen'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('Schließen'), findsNothing);
    expect(find.byIcon(LucideIcons.x), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit paragraphs keep inner newlines without 12 gaps', (
    tester,
  ) async {
    await openSheet(
      tester,
      width: 375,
      height: 812,
      sheetParagraphs: [
        '  ',
        groupedParagraphs[0],
        '',
        groupedParagraphs[1],
        ' \n ',
        groupedParagraphs[2],
      ],
    );
    expect(find.text(groupedParagraphs[0]), findsOneWidget);
    expect(find.text(groupedParagraphs[1]), findsOneWidget);
    expect(find.text(groupedParagraphs[2]), findsOneWidget);
    expect(find.text('RMSSD · gespeicherter Wert'), findsNothing);
    expect(find.text('Eigene Tagesziele, keine Bedarfsschätzung.'), findsNothing);

    final first = tester.getRect(find.text(groupedParagraphs[0]));
    final second = tester.getRect(find.text(groupedParagraphs[1]));
    final third = tester.getRect(find.text(groupedParagraphs[2]));
    expect(first.height, closeTo(44, 2));
    expect(second.height, closeTo(66, 2));
    expect(third.height, closeTo(44, 2));
    expect(second.top - first.bottom, closeTo(12, 1.5));
    expect(third.top - second.bottom, closeTo(12, 1.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('2x 375 long paragraphs and actions scroll', (tester) async {
    const longGrouped = [
      'Eigene Tagesziele, keine Bedarfsschätzung.\n'
          'Änderungen gelten ab dem gewählten Datum. Leere Felder haben kein Ziel.',
      'Die Energie aus Makros kann vom Energieziel abweichen.\n'
          'Ein sehr langer Hinweistext prüft, dass der Bogen bei großem Inhalt '
          'scrollt statt über den Viewport zu laufen. Wiederholte Sätze halten den '
          'Block deutlich über die Bildschirmhöhe.',
      'Zweiter Block: Wiederholte Sätze halten den Block deutlich über die '
          'Bildschirmhöhe und dürfen keine Overflow-Fehler erzeugen.\n'
          'Dritter Block: Wiederholte Sätze halten den Block deutlich über die '
          'Bildschirmhöhe und dürfen keine Overflow-Fehler erzeugen.\n'
          'Vierter Block: Wiederholte Sätze halten den Block deutlich über die '
          'Bildschirmhöhe und dürfen keine Overflow-Fehler erzeugen.\n'
          'Fünfter Block: Wiederholte Sätze halten den Block deutlich über die '
          'Bildschirmhöhe und dürfen keine Overflow-Fehler erzeugen.',
    ];
    await openSheet(
      tester,
      width: 375,
      height: 812,
      scale: 2,
      sheetBody: '',
      sheetParagraphs: longGrouped,
      actions: const [OBInfoSheetAction(id: 'hrv', label: 'HRV · Quellen')],
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
    expect(find.text(longGrouped[0]), findsOneWidget);
    final close = find.widgetWithText(OBAction, 'Schließen');
    expect(close.hitTestable(), findsOneWidget);
    final body = find.byKey(const ValueKey('journal-info-body'));
    await tester.scrollUntilVisible(
      find.text('HRV · Quellen'),
      80,
      scrollable: find.descendant(of: body, matching: find.byType(Scrollable)),
    );
    expect(find.text('HRV · Quellen'), findsOneWidget);
    expect(close.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('action result closes the sheet and returns the id', (
    tester,
  ) async {
    await openSheet(
      tester,
      sheetBody: '',
      sheetParagraphs: groupedParagraphs,
    );
    expect(find.text(groupedParagraphs[0]), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();
    expect(find.text(groupedParagraphs[0]), findsNothing);

    final future = showOpenBandJournalInfo(
      tester.element(find.byType(Scaffold)),
      title: title,
      paragraphs: groupedParagraphs,
      actions: const [OBInfoSheetAction(id: 'hrv', label: 'HRV · Quellen')],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('HRV · Quellen'));
    await tester.pumpAndSettle();
    expect(await future, 'hrv');
    expect(find.text('Schließen'), findsNothing);
    expect(find.text('HRV · Quellen'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primaryAction returns id; X, barrier and default close return null', (
    tester,
  ) async {
    const sleep = OBInfoSheetAction(id: 'sleep', label: 'Schlaf ansehen');
    await openSheet(tester);
    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();

    final defaultClose = showOpenBandJournalInfo(
      tester.element(find.byType(Scaffold)),
      title: title,
      body: body,
    );
    await tester.pumpAndSettle();
    expect(find.text('Schließen'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(await defaultClose, isNull);

    final xFuture = showOpenBandJournalInfo(
      tester.element(find.byType(Scaffold)),
      title: title,
      body: body,
      primaryAction: sleep,
    );
    await tester.pumpAndSettle();
    expect(find.text('Schlaf ansehen'), findsOneWidget);
    expect(find.text('Schließen'), findsNothing);
    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();
    expect(await xFuture, isNull);

    final barrierFuture = showOpenBandJournalInfo(
      tester.element(find.byType(Scaffold)),
      title: title,
      body: body,
      primaryAction: sleep,
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 80));
    await tester.pumpAndSettle();
    expect(await barrierFuture, isNull);

    final primaryFuture = showOpenBandJournalInfo(
      tester.element(find.byType(Scaffold)),
      title: title,
      body: body,
      primaryAction: sleep,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schlaf ansehen'));
    await tester.pumpAndSettle();
    expect(await primaryFuture, 'sleep');
    expect(find.text('Schlaf ansehen'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primaryAction stays pinned at 2x with long body', (tester) async {
    await openSheet(
      tester,
      width: 375,
      height: 812,
      scale: 2,
      sheetBody: longBody,
      actions: const [OBInfoSheetAction(id: 'hrv', label: 'HRV · Quellen')],
      primaryAction: const OBInfoSheetAction(
        id: 'sleep',
        label: 'Schlaf ansehen',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Schließen'), findsNothing);
    final primary = find.widgetWithText(OBAction, 'Schlaf ansehen');
    expect(primary.hitTestable(), findsOneWidget);
    final primaryRect = tester.getRect(primary);
    expect(primaryRect.bottom, lessThanOrEqualTo(812 - 34 + 1));
    expect(primaryRect.top, greaterThanOrEqualTo(59));
    final bodyScroll = find.byKey(const ValueKey('journal-info-body'));
    await tester.scrollUntilVisible(
      find.text('HRV · Quellen'),
      80,
      scrollable: find.descendant(
        of: bodyScroll,
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('HRV · Quellen'), findsOneWidget);
    expect(primary.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('info sheet goldens light, dark and 2x', (tester) async {
    Future<void> capture(
      String name, {
      Brightness brightness = Brightness.light,
      double width = 393,
      double height = 852,
      double scale = 1,
      String sheetTitle = title,
    }) async {
      await openSheet(
        tester,
        brightness: brightness,
        width: width,
        height: height,
        scale: scale,
        sheetTitle: sheetTitle,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('openband_goldens/$name.png'),
      );
    }

    await capture('info-sheet-light');
    await capture('info-sheet-dark', brightness: Brightness.dark);
    await capture(
      'info-sheet-2x',
      width: 375,
      height: 812,
      scale: 2,
      sheetTitle: 'Ernährungs-\nziele',
    );
  });

  Future<void> pumpChips(
    WidgetTester tester, {
    double width = 393,
    double height = 852,
    double scale = 1,
    Brightness brightness = Brightness.light,
    required List<({String label, bool selected})> chips,
    ValueChanged<String>? onTap,
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
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chip in chips)
                  OBJournalChip(
                    label: chip.label,
                    selected: chip.selected,
                    onTap: () => onTap?.call(chip.label),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('OBJournalChip shrink-wraps, colors, and stays safe at 320 2x', (
    tester,
  ) async {
    final taps = <String>[];
    await pumpChips(
      tester,
      width: 320,
      height: 568,
      chips: const [
        (label: 'Kurz', selected: false),
        (label: 'Auch', selected: true),
        (label: 'Sehr langer Chiptext für schmale Breite', selected: false),
      ],
      onTap: taps.add,
    );
    expect(tester.takeException(), isNull);

    final shortChips = tester.widgetList<OBJournalChip>(
      find.byType(OBJournalChip),
    );
    expect(shortChips.length, 3);
    final kurzChip = tester.getRect(find.byType(OBJournalChip).at(0));
    final auchChip = tester.getRect(find.byType(OBJournalChip).at(1));
    expect(kurzChip.width, lessThan(200));
    expect(auchChip.width, lessThan(200));
    expect(auchChip.left, greaterThan(kurzChip.right));
    expect(kurzChip.height, greaterThanOrEqualTo(44));
    expect(auchChip.height, greaterThanOrEqualTo(44));

    Color materialColor(Finder label) {
      return tester
          .widget<Material>(
            find.ancestor(of: label, matching: find.byType(Material)).first,
          )
          .color!;
    }

    expect(materialColor(find.text('Kurz')), AlpColor.well);
    expect(materialColor(find.text('Auch')), AlpColor.ink);

    await tester.tap(find.text('Kurz'));
    expect(taps, ['Kurz']);

    await pumpChips(
      tester,
      width: 320,
      height: 568,
      scale: 2,
      chips: const [
        (label: 'Kurz', selected: false),
        (label: 'Auch', selected: true),
        (label: 'Sehr langer Chiptext für schmale Breite', selected: false),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(OBJournalChip), findsNWidgets(3));
    final scaled = tester.getRect(find.byType(OBJournalChip).at(0));
    expect(scaled.width, lessThan(320));
    expect(scaled.height, greaterThanOrEqualTo(44));
  });

  testWidgets('OBJournalChip wrap golden', (tester) async {
    await pumpChips(
      tester,
      chips: const [
        (label: 'Arbeit', selected: true),
        (label: 'Sport', selected: false),
        (label: 'Reise', selected: false),
        (label: 'Krankheit', selected: true),
      ],
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/info-sheet-chips.png'),
    );
  });
}
