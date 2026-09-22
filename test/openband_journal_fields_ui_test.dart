import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/openband/journal_controls.dart';
import 'package:openstrap_edge/openband/journal_fields.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

SyntheticOpenBandRepository galleryRepo() =>
    SyntheticOpenBandRepository.fromMaps(
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
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

  late SyntheticOpenBandRepository repo;
  setUp(() => repo = galleryRepo());

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        debugShowCheckedModeBanner: false,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: SizedBox(
          width: 393,
          height: 852,
          child: RepaintBoundary(
            key: const ValueKey('capture'),
            child: OpenBandJournalFields(repository: repo, day: '2026-09-15'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('create hide restore; list refresh failure does not recreate', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Eigene Felder'), findsOneWidget);
    expect(find.text('Keine eigenen Felder.'), findsOneWidget);

    await tester.tap(find.text('Feld hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.text('Die Feldart lässt sich nach dem Speichern nicht ändern.'),
      findsOneWidget,
    );
    expect(find.textContaining('Kennung'), findsNothing);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('journal-field-name')),
      'Magnesium',
    );
    repo.failJournalFieldsList = true;
    await tester.tap(find.text('Speichern').first);
    await tester.pumpAndSettle();
    expect(find.text('Feld gespeichert. Liste nicht geladen.'), findsOneWidget);
    repo.failJournalFieldsList = false;
    final created = await repo.listJournalFields(includeHidden: true);
    expect(created.where((f) => f.label == 'Magnesium').length, 1);
    final key = created.singleWhere((f) => f.label == 'Magnesium').key;
    expect(key.startsWith('custom_'), isTrue);
    expect(key.contains('magnesium'), isFalse);

    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Magnesium'), findsWidgets);
    expect(
      (await repo.listJournalFields(
        includeHidden: true,
      )).where((f) => f.label == 'Magnesium').length,
      1,
    );

    await tester.tap(find.text('Magnesium').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ausblenden'));
    await tester.pumpAndSettle();
    expect(find.text('Magnesium'), findsNothing);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.text('Ausgeblendet'));
    await tester.pumpAndSettle();
    expect(find.text('Meditation'), findsNothing);
    expect(find.text('Magnesium'), findsOneWidget);
    await tester.tap(find.text('Magnesium'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einblenden'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Magnesium'), findsWidgets);
    expect(
      (await repo.listJournalFields()).singleWhere((f) => f.key == key).hidden,
      isFalse,
    );
  });

  testWidgets('hidden list restore of seeded field', (tester) async {
    repo.seedJournalEditor(withCustom: true);
    await mount(tester);
    expect(find.text('Magnesium'), findsOneWidget);
    expect(find.text('15. September'), findsNothing);
    final card = tester.getRect(
      find
          .ancestor(
            of: find.byKey(const ValueKey('journal-field-custom_magnesium')),
            matching: find.byType(OBCard),
          )
          .first,
    );
    expect(card.height, closeTo(80, 1));
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('journal-fields-hidden')),
        matching: find.byType(OBCard),
      ),
      findsNothing,
    );
    expect(find.byTooltip('Information'), findsOneWidget);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Ausgeblendete Felder bleiben im Verlauf. Du kannst sie wieder einblenden.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Kennung'), findsNothing);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-fields.png'),
    );
    await tester.tap(find.text('Ausgeblendet'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Ausgeblendete Felder bleiben im Verlauf. Du kannst sie wieder einblenden.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Kennung'), findsNothing);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('Meditation'), findsOneWidget);
    await tester.tap(find.text('Meditation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einblenden'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(
      (await repo.listJournalFields()).any(
        (f) => f.key == 'custom_meditation' && !f.hidden,
      ),
      isTrue,
    );
  });

  testWidgets('new field does not attach old slug history', (tester) async {
    await repo.createJournalField(
      const JournalFieldSpec(
        key: 'custom_magnesium',
        label: 'Old magnesium',
        kind: JournalFieldKind.dose,
        unit: 'mg',
        max: 1000,
        step: 50,
        custom: true,
        hidden: true,
      ),
    );
    final empty = await repo.readJournalDay('2026-09-15');
    await repo.patchJournalDay(
      JournalDayPatch.fromBase(
        empty,
        metrics: const {'custom_magnesium': JournalMetricValue(400)},
      ),
    );
    await mount(tester);
    await tester.tap(find.text('Feld hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('journal-field-name')),
      'Magnesium',
    );
    await tester.tap(find.text('Speichern').first);
    await tester.pumpAndSettle();
    final defs = await repo.listJournalFields();
    final created = defs.singleWhere((f) => f.label == 'Magnesium');
    expect(created.key, isNot('custom_magnesium'));
    final snap = await repo.readJournalDay('2026-09-15');
    expect(snap.metrics['custom_magnesium']!.value, 400);
    expect(snap.metrics.containsKey(created.key), isFalse);
  });

  testWidgets('fields list load error retries production widgets', (
    tester,
  ) async {
    repo.failJournalFieldsList = true;
    await mount(tester);
    expect(find.text('Felder nicht geladen'), findsOneWidget);
    repo.failJournalFieldsList = false;
    repo.seedJournalEditor(withCustom: true);
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Magnesium'), findsOneWidget);
  });

  testWidgets('create post-commit list retry does not duplicate', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Feld hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.text('15. September'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('journal-field-name')),
      'Omega',
    );
    repo.failJournalFieldsList = true;
    await tester.tap(find.text('Speichern').first);
    await tester.pumpAndSettle();
    expect(find.text('Feld gespeichert. Liste nicht geladen.'), findsOneWidget);
    repo.failJournalFieldsList = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(
      (await repo.listJournalFields(
        includeHidden: true,
      )).where((f) => f.label == 'Omega').length,
      1,
    );
  });

  testWidgets(
    'committed create back returns the field; precommit keeps draft',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Feld hinzufügen'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('journal-field-name')),
        'Omega',
      );
      repo.failJournalFieldsCreate = true;
      await tester.tap(find.text('Speichern').first);
      await tester.pumpAndSettle();
      expect(find.text('Feld nicht gespeichert.'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('journal-field-name')))
            .controller!
            .text,
        'Omega',
      );
      expect(find.text('Speichern'), findsOneWidget);
      repo.failJournalFieldsCreate = false;
      repo.failJournalFieldsList = true;
      await tester.tap(find.text('Speichern').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Feld gespeichert. Liste nicht geladen.'),
        findsOneWidget,
      );
      expect(find.text('Speichern'), findsNothing);
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      expect(find.text('Omega'), findsOneWidget);
      expect(
        find.text('Feld gespeichert. Liste nicht geladen.'),
        findsOneWidget,
      );
      repo.failJournalFieldsList = false;
      expect(
        (await repo.listJournalFields(
          includeHidden: true,
        )).where((f) => f.label == 'Omega').length,
        1,
      );
    },
  );

  testWidgets('type sheet wraps content-width chips', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Feld hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menge'));
    await tester.pumpAndSettle();
    final menge = tester.getRect(find.widgetWithText(OBJournalChip, 'Menge'));
    final dauer = tester.getRect(find.widgetWithText(OBJournalChip, 'Dauer'));
    expect(menge.height, greaterThanOrEqualTo(44));
    expect(dauer.height, greaterThanOrEqualTo(44));
    expect(menge.width, lessThan(200));
    expect(dauer.width, lessThan(200));
    expect(menge.top, closeTo(dauer.top, 1));
    expect(menge.right, lessThan(dauer.left));
    expect(tester.takeException(), isNull);
  });
}
