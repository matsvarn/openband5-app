import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/ai/journal_ai.dart' show kJournalPresetTags;
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/journal.dart';
import 'package:openstrap_edge/openband/journal_controls.dart';
import 'package:openstrap_edge/openband/journal_editor.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
    double scale = 1,
    double width = 393,
    double height = 852,
    String day = '2026-09-15',
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
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
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: SizedBox(
          width: width,
          height: height,
          child: RepaintBoundary(
            key: const ValueKey('capture'),
            child: OpenBandJournalEditor(repository: repo, day: day),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectStackedGroupFullWidth(WidgetTester tester, String label) {
    final width = tester.view.physicalSize.width;
    expect(tester.getTopLeft(find.text(label).first).dx, closeTo(30, 1));
    final card = tester.getRect(
      find
          .ancestor(of: find.text(label).first, matching: find.byType(OBCard))
          .first,
    );
    expect(card.left, closeTo(16, 1));
    expect(card.right, closeTo(width - 16, 1));
  }

  testWidgets('empty values, missing booleans, all built-ins', (tester) async {
    await mount(tester);
    expect(find.text('Tagesjournal'), findsOneWidget);
    expect(find.text('15. September'), findsOneWidget);
    for (final label in [
      'Stimmung',
      'Schlafqualität',
      'Energie',
      'Stress',
      'Muskelkater',
      'Koffein nach 14 Uhr',
      'Alkohol am Abend',
      'Vorm Schlafen gelesen',
      'Wasser',
      'Koffein',
      'Alkohol',
      'Bildschirm vorm Schlafen',
      'Gewicht',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('—'), findsWidgets);
    expect(find.text('Ja'), findsNWidgets(3));
    expect(find.text('Nein'), findsNWidgets(3));
    expect(find.byIcon(LucideIcons.frown), findsOneWidget);
    expect(find.byIcon(LucideIcons.annoyed), findsOneWidget);
    expect(find.byIcon(LucideIcons.meh), findsOneWidget);
    expect(find.byIcon(LucideIcons.smile), findsOneWidget);
    expect(find.byIcon(LucideIcons.laugh), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(OpenBandJournalEditor),
        matching: find.byType(Divider),
      ),
      findsNothing,
    );
    final capsule = tester.getRect(
      find.byKey(const ValueKey('journal-yesno-capsule')).first,
    );
    expect(capsule.height, 32);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-editor-empty.png'),
    );
  });

  testWidgets('existing values, tags and note, dirty patch keeps siblings', (
    tester,
  ) async {
    repo.seedJournalEditor(filled: true, withCustom: true);
    await mount(tester);
    expect(find.text('4 / 5'), findsNWidgets(2));
    expect(find.text('200 mg · 10:30'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('journal-note')))
          .controller!
          .text,
      'Später Spaziergang.',
    );
    expect(find.text('Spaziergang'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('journal-tags-row'))).height,
      56,
    );
    expect(find.text('Magnesium'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Energie')).dy -
          tester.getTopLeft(find.text('Schlafqualität')).dy,
      closeTo(56, 1),
    );
    expect(
      tester.getTopLeft(find.text('Alkohol am Abend')).dy -
          tester.getTopLeft(find.text('Koffein nach 14 Uhr')).dy,
      closeTo(56, 1),
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('journal-yesno-capsule')).first)
          .height,
      32,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('journal-save'))).bottom,
      closeTo(818, 1.5),
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-editor.png'),
    );

    await tester.tap(find.bySemanticsLabel('Stimmung Sehr gut'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();

    final snap = await repo.readJournalDay('2026-09-15');
    expect(snap.metrics['mood']!.value, 5);
    expect(snap.metrics['caffeine_mg']!.value, 200);
    expect(snap.metrics['caffeine_mg']!.atMinuteOfDay, 630);
    expect(snap.note, 'Später Spaziergang.');
    expect(snap.tags, ['Spaziergang']);
  });

  testWidgets('value blank clears; time stays until edited', (tester) async {
    repo.seedJournalEditor(filled: true);
    await mount(tester);
    await tester.ensureVisible(find.text('Koffein').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Koffein').last);
    await tester.pumpAndSettle();
    expect(find.text('Zuletzt'), findsOneWidget);
    expect(find.text('10:30'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    final snap = await repo.readJournalDay('2026-09-15');
    expect(snap.metrics.containsKey('caffeine_mg'), isFalse);
    expect(snap.metrics['water_ml']!.value, 750);
  });

  testWidgets('out-of-range dose is refused in the sheet', (tester) async {
    repo.seedJournalEditor(filled: true);
    await mount(tester);
    await tester.tap(find.bySemanticsLabel('Stimmung Sehr gut'));
    await tester.pump();
    await tester.ensureVisible(find.text('Koffein').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Koffein').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '5001');
    await tester.tap(find.text('Übernehmen'));
    await tester.pump();
    expect(find.text('Übernehmen'), findsOneWidget);
    expect(find.text('Koffein: 0–1000 mg'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('journal-value')))
          .controller!
          .text,
      '5001',
    );
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('200 mg'), findsOneWidget);
    await tester.tap(find.text('Koffein').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '250');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Übernehmen'), findsNothing);
    await tester.ensureVisible(find.textContaining('250 mg'));
    expect(find.textContaining('250 mg · 10:30'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    final snap = await repo.readJournalDay('2026-09-15');
    expect(snap.metrics['caffeine_mg']!.value, 250);
    expect(snap.metrics['caffeine_mg']!.atMinuteOfDay, 630);
    expect(snap.metrics['mood']!.value, 5);
    expect(snap.metrics['water_ml']!.value, 750);
  });

  testWidgets(
    'stored out-of-range dose is not rewritten by an unrelated edit',
    (tester) async {
      repo.seedJournalEditor(
        filled: true,
        metrics: const {
          'caffeine_mg': JournalMetricValue(5001, atMinuteOfDay: 630),
        },
      );
      await mount(tester);
      await tester.tap(find.bySemanticsLabel('Stimmung Sehr gut'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('journal-save')));
      await tester.pumpAndSettle();
      final snap = await repo.readJournalDay('2026-09-15');
      expect(snap.metrics['caffeine_mg']!.value, 5001);
      expect(snap.metrics['caffeine_mg']!.atMinuteOfDay, 630);
      expect(snap.metrics['mood']!.value, 5);
    },
  );

  testWidgets('zero dose is stored and distinct from missing', (tester) async {
    await mount(tester);
    await tester.ensureVisible(find.text('Wasser'));
    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '0');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    final snap = await repo.readJournalDay('2026-09-15');
    expect(snap.metrics['water_ml']!.value, 0);
  });

  testWidgets('whitespace note is not rewritten by an unrelated mood edit', (
    tester,
  ) async {
    repo.seedJournalEditor(filled: true);
    const note = '  keep me\n';
    final before = await repo.readJournalDay('2026-09-15');
    await repo.patchJournalDay(JournalDayPatch.fromBase(before, note: note));
    final seeded = await repo.readJournalDay('2026-09-15');
    final rev = seeded.journalUpdatedAt;
    await mount(tester);
    await tester.tap(find.bySemanticsLabel('Stimmung Sehr gut'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    final snap = await repo.readJournalDay('2026-09-15');
    expect(snap.note, note);
    expect(snap.journalUpdatedAt, rev);
    expect(snap.metrics['mood']!.value, 5);
  });

  testWidgets('dose 2.75 open and apply keeps the stored amount', (
    tester,
  ) async {
    repo.seedJournalEditor(filled: true);
    final before = await repo.readJournalDay('2026-09-15');
    await repo.patchJournalDay(
      JournalDayPatch.fromBase(
        before,
        metrics: const {
          'alcohol_units': JournalMetricValue(2.75, atMinuteOfDay: 630),
        },
      ),
    );
    await mount(tester);
    await tester.ensureVisible(find.text('Alkohol'));
    await tester.tap(find.text('Alkohol'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('journal-value')))
          .controller!
          .text,
      '2.75',
    );
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    final snap = await repo.readJournalDay('2026-09-15');
    expect(snap.metrics['alcohol_units']!.value, 2.75);
    expect(snap.metrics['alcohol_units']!.atMinuteOfDay, 630);
  });

  testWidgets('dose time-only edit keeps 2.75', (tester) async {
    repo.seedJournalEditor(filled: true);
    final before = await repo.readJournalDay('2026-09-15');
    await repo.patchJournalDay(
      JournalDayPatch.fromBase(
        before,
        metrics: const {
          'alcohol_units': JournalMetricValue(2.75, atMinuteOfDay: 630),
        },
      ),
    );
    await mount(tester);
    await tester.ensureVisible(find.text('Alkohol'));
    await tester.tap(find.text('Alkohol'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('journal-value')))
          .controller!
          .text,
      '2.75',
    );
    await tester.tap(find.text('10:30'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '11');
    await tester.enterText(find.byType(TextFormField).last, '45');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    final snap = await repo.readJournalDay('2026-09-15');
    expect(snap.metrics['alcohol_units']!.value, 2.75);
    expect(snap.metrics['alcohol_units']!.atMinuteOfDay, 11 * 60 + 45);
  });

  testWidgets('explicit 2.8 changes the dose; 22.5 is not parsed as 225', (
    tester,
  ) async {
    repo.seedJournalEditor(filled: true);
    final before = await repo.readJournalDay('2026-09-15');
    await repo.patchJournalDay(
      JournalDayPatch.fromBase(
        before,
        metrics: const {
          'alcohol_units': JournalMetricValue(2.75, atMinuteOfDay: 630),
        },
      ),
    );
    await mount(tester);
    await tester.ensureVisible(find.text('Alkohol'));
    await tester.tap(find.text('Alkohol'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '2.8');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Gewicht'));
    await tester.tap(find.text('Gewicht'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '22.5');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    final snap = await repo.readJournalDay('2026-09-15');
    expect(snap.metrics['alcohol_units']!.value, 2.8);
    expect(snap.metrics['alcohol_units']!.atMinuteOfDay, 630);
    expect(snap.metrics['weight_kg']!.value, 22.5);
  });

  testWidgets('fields back without write does not claim a save', (
    tester,
  ) async {
    repo.seedJournalEditor(filled: true);
    await mount(tester);
    await tester.ensureVisible(find.text('Eigene Felder'));
    await tester.tap(find.text('Eigene Felder'));
    await tester.pumpAndSettle();
    expect(find.text('Keine eigenen Felder.'), findsOneWidget);
    repo.failJournalFieldsList = true;
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Feld gespeichert. Liste nicht geladen.'), findsNothing);
    expect(find.text('Felder nicht geladen.'), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    repo.failJournalFieldsList = false;
    await tester.ensureVisible(find.text('Erneut'));
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Felder nicht geladen.'), findsNothing);
  });

  testWidgets('failed save keeps draft; conflict keeps draft', (tester) async {
    repo.seedJournalEditor(filled: true);
    await mount(tester);
    await tester.tap(find.bySemanticsLabel('Stimmung Sehr gut'));
    await tester.pump();
    repo.failJournalPatch = true;
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.byType(OpenBandJournalEditor), findsOneWidget);
    expect((await repo.readJournalDay('2026-09-15')).metrics['mood']!.value, 4);

    repo.failJournalPatch = false;
    final other = await repo.readJournalDay('2026-09-15');
    await repo.patchJournalDay(
      JournalDayPatch.fromBase(
        other,
        metrics: const {'mood': JournalMetricValue(2)},
      ),
    );
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag wurde inzwischen geändert.'), findsOneWidget);
    expect(find.text('Neu laden'), findsOneWidget);
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(find.text('Verwerfen und neu laden'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ob-confirm-no')));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandJournalEditor), findsOneWidget);
  });

  testWidgets('back confirmation keeps draft on cancel', (tester) async {
    repo.seedJournalEditor(filled: true);
    await mount(tester);
    await tester.tap(find.bySemanticsLabel('Stimmung Sehr gut'));
    await tester.pump();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Änderungen verwerfen?'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/journal-discard.png'),
    );
    await tester.tap(find.text('Weiter bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandJournalEditor), findsOneWidget);
  });

  testWidgets('load error retries; save busy does not double-write', (
    tester,
  ) async {
    repo.failJournalRead = true;
    await mount(tester);
    expect(find.text('Journal nicht geladen'), findsOneWidget);
    final errorCard = tester.getRect(find.byType(OBCard).first);
    final retry = tester.getRect(find.widgetWithText(FilledButton, 'Erneut'));
    expect(retry.width, closeTo(errorCard.width - 28, 2));
    expect(
      (retry.left + retry.right) / 2,
      closeTo((errorCard.left + errorCard.right) / 2, 2),
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-editor-load-error.png'),
    );
    repo.failJournalRead = false;
    repo.seedJournalEditor(filled: true);
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('4 / 5'), findsNWidgets(2));

    final gate = Completer<void>();
    repo.journalPatchBarrier = gate.future;
    await tester.tap(find.bySemanticsLabel('Stimmung Erschöpft'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect((await repo.readJournalDay('2026-09-15')).metrics['mood']!.value, 1);
  });

  testWidgets('dark editor', (tester) async {
    repo.seedJournalEditor(filled: true, withCustom: true);
    await mount(tester, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-editor-dark.png'),
    );
  });

  testWidgets('2x text still has 44pt targets', (tester) async {
    repo.seedJournalEditor(filled: true);
    await mount(tester, scale: 2, width: 320, height: 900);
    expect(tester.takeException(), isNull);
    expect(find.text('Tagesjournal'), findsOneWidget);
    expect(find.text('Ausgeblendet'), findsNothing);
    expectStackedGroupFullWidth(tester, 'Schlafqualität');
    expectStackedGroupFullWidth(tester, 'Energie');
    expectStackedGroupFullWidth(tester, 'Wasser');
    final save = tester.getRect(find.byKey(const ValueKey('journal-save')));
    expect(save.height, greaterThanOrEqualTo(44));
    final capsule = tester.getRect(
      find.byKey(const ValueKey('journal-yesno-capsule')).first,
    );
    expect(capsule.height, greaterThanOrEqualTo(36));
  });

  testWidgets('full 2x editor does not mark ordinary rows hidden', (
    tester,
  ) async {
    repo.seedJournalEditor(filled: true, withCustom: true);
    await mount(tester, scale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Ausgeblendet'), findsNothing);
    expect(find.text('Schlafqualität'), findsOneWidget);
    expect(find.text('Magnesium'), findsOneWidget);
    expectStackedGroupFullWidth(tester, 'Schlafqualität');
    expectStackedGroupFullWidth(tester, 'Energie');
    expectStackedGroupFullWidth(tester, 'Muskelkater');
    expectStackedGroupFullWidth(tester, 'Wasser');
    expectStackedGroupFullWidth(tester, 'Magnesium');
    expect(
      tester
          .getRect(
            find
                .ancestor(
                  of: find.text('Schlafqualität'),
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .height,
      closeTo(108, 2),
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-editor-2x.png'),
    );
  });

  testWidgets('tags store English identities; unknown custom text kept', (
    tester,
  ) async {
    await mount(tester);
    await tester.ensureVisible(find.text('Tags'));
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('journal-tags-sheet')),
        matching: find.text('Koffein'),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('journal-tag-custom')),
      'Spaziergang',
    );
    await tester.ensureVisible(find.byTooltip('Tag hinzufügen'));
    await tester.tap(find.byTooltip('Tag hinzufügen'));
    await tester.pump();
    await tester.ensureVisible(find.text('Übernehmen'));
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    final snap = await repo.readJournalDay('2026-09-15');
    expect(snap.tags, ['caffeine', 'Spaziergang']);
  });

  Rect tagChipRect(WidgetTester tester, String label) {
    return tester.getRect(find.widgetWithText(OBJournalChip, label));
  }

  Future<void> openTagsSheet(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Tags'));
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
  }

  Future<void> expectTagsSheetChrome(
    WidgetTester tester, {
    required double safeTop,
    required double visibleBottom,
  }) async {
    final sheet = find.byKey(const ValueKey('journal-tags-sheet'));
    expect(tester.getRect(sheet).top, greaterThanOrEqualTo(safeTop));
    final header = find.descendant(of: sheet, matching: find.text('Tags'));
    final close = find.descendant(
      of: sheet,
      matching: find.byTooltip('Schließen'),
    );
    final apply = find.widgetWithText(FilledButton, 'Übernehmen');
    for (final target in [header, close, apply]) {
      expect(target.hitTestable(), findsOneWidget);
      final rect = tester.getRect(target);
      expect(rect.top, greaterThanOrEqualTo(safeTop));
      expect(rect.bottom, lessThanOrEqualTo(visibleBottom + 0.5));
    }
  }

  testWidgets('tags sheet wraps content-width chips', (tester) async {
    repo.seedJournalEditor(filled: true);
    await mount(tester);
    await openTagsSheet(tester);
    final koffein = tagChipRect(tester, 'Koffein');
    final alkohol = tagChipRect(tester, 'Alkohol');
    final walk = tagChipRect(tester, 'Spaziergang');
    expect(koffein.height, greaterThanOrEqualTo(44));
    expect(alkohol.height, greaterThanOrEqualTo(44));
    expect(walk.height, greaterThanOrEqualTo(44));
    expect(koffein.width, lessThan(200));
    expect(alkohol.width, lessThan(200));
    expect(walk.width, lessThan(200));
    expect(koffein.top, closeTo(alkohol.top, 1));
    expect(koffein.right, lessThan(alkohol.left));
    final sheet = tester.getRect(
      find.byKey(const ValueKey('journal-tags-sheet')),
    );
    expect(sheet.top, closeTo(362, 4));
    final apply = tester.getRect(
      find.widgetWithText(FilledButton, 'Übernehmen'),
    );
    expect(apply.top, closeTo(770, 4));
    expect(apply.height, greaterThanOrEqualTo(48));
    expect(apply.center.dy, lessThan(852));
    expect(apply.center.dy, greaterThan(0));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/journal-tags.png'),
    );
  });

  testWidgets('dark tags sheet', (tester) async {
    repo.seedJournalEditor(filled: true);
    await mount(tester, brightness: Brightness.dark);
    await openTagsSheet(tester);
    expect(tagChipRect(tester, 'Spaziergang').width, lessThan(200));
    expect(tester.getRect(find.text('Übernehmen')).center.dy, lessThan(852));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/journal-tags-dark.png'),
    );
  });

  testWidgets('tags wrap at 320 and 2x; long labels wrap; apply reachable', (
    tester,
  ) async {
    repo.seedJournalEditor(filled: true);
    await mount(tester, width: 320, height: 852);
    await openTagsSheet(tester);
    final compact = tagChipRect(tester, 'Koffein');
    expect(compact.width, lessThan(200));
    expect(compact.height, greaterThanOrEqualTo(44));
    expect(compact.top, closeTo(tagChipRect(tester, 'Alkohol').top, 1));
    expect(tester.getRect(find.text('Übernehmen')).center.dy, lessThan(852));

    const longLabel = 'Sehr langer selbstgewählter Tagname für den Umbruchtest';
    await tester.enterText(
      find.byKey(const ValueKey('journal-tag-custom')),
      longLabel,
    );
    await tester.ensureVisible(find.byTooltip('Tag hinzufügen'));
    await tester.tap(find.byTooltip('Tag hinzufügen'));
    await tester.pump();
    final longChip = tagChipRect(tester, longLabel);
    expect(longChip.width, lessThanOrEqualTo(280));
    expect(longChip.height, greaterThanOrEqualTo(44));
    expect(
      tester
          .getSize(
            find.descendant(
              of: find.byKey(const ValueKey('journal-tags-sheet')),
              matching: find.text(longLabel),
            ),
          )
          .height,
      greaterThan(20),
    );
    expect(
      longChip.right,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('journal-tags-sheet'))).right +
            0.5,
      ),
    );
    await tester.ensureVisible(find.text('Übernehmen'));
    expect(tester.getRect(find.text('Übernehmen')).center.dy, lessThan(852));

    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    await mount(tester, scale: 2, width: 320, height: 812);
    await openTagsSheet(tester);
    final scaled = tagChipRect(tester, 'Koffein');
    expect(scaled.width, lessThan(240));
    expect(scaled.height, greaterThanOrEqualTo(44));
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(() => tester.view.resetViewInsets());
    await tester.pumpAndSettle();
    await expectTagsSheetChrome(tester, safeTop: 59, visibleBottom: 812 - 336);
    final custom = find.byKey(const ValueKey('journal-tag-custom'));
    await tester.ensureVisible(custom);
    await tester.pumpAndSettle();
    await tester.tap(custom);
    await tester.pump();
    await expectTagsSheetChrome(tester, safeTop: 59, visibleBottom: 812 - 336);
    expect(custom.hitTestable(), findsOneWidget);
    await tester.enterText(custom, 'Yoga');
    await tester.ensureVisible(find.byTooltip('Tag hinzufügen'));
    await tester.tap(find.byTooltip('Tag hinzufügen'));
    await tester.pump();
    await expectTagsSheetChrome(tester, safeTop: 59, visibleBottom: 812 - 336);
    await tester.ensureVisible(custom);
    expect(custom.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('journal-tags-sheet')), findsNothing);
  });

  testWidgets('375 keyboard keeps tags header and Apply fixed', (tester) async {
    repo.seedJournalEditor(filled: true);
    await mount(tester, width: 375, height: 812);
    await openTagsSheet(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 344);
    addTearDown(() => tester.view.resetViewInsets());
    await tester.pumpAndSettle();
    const safeTop = 59.0;
    const visibleBottom = 812.0 - 344.0;
    await expectTagsSheetChrome(
      tester,
      safeTop: safeTop,
      visibleBottom: visibleBottom,
    );
    final custom = find.byKey(const ValueKey('journal-tag-custom'));
    await tester.ensureVisible(custom);
    await tester.pumpAndSettle();
    await tester.tap(custom);
    await tester.pump();
    await expectTagsSheetChrome(
      tester,
      safeTop: safeTop,
      visibleBottom: visibleBottom,
    );
    expect(custom.hitTestable(), findsOneWidget);
    await tester.enterText(custom, 'Yoga');
    await tester.ensureVisible(find.byTooltip('Tag hinzufügen'));
    await tester.tap(find.byTooltip('Tag hinzufügen'));
    await tester.pump();
    await expectTagsSheetChrome(
      tester,
      safeTop: safeTop,
      visibleBottom: visibleBottom,
    );
    await tester.ensureVisible(custom);
    expect(custom.hitTestable(), findsOneWidget);
    expect(find.widgetWithText(OBJournalChip, 'Yoga'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<void> seedTags(List<String> tags) async {
    repo.seedJournalEditor(filled: true);
    final base = await repo.readJournalDay('2026-09-15');
    await repo.patchJournalDay(JournalDayPatch.fromBase(base, tags: tags));
  }

  void expectTagValueFitsCard(WidgetTester tester, String value) {
    final card = tester.getRect(find.byKey(const ValueKey('journal-tags-row')));
    final painted = tester.getRect(find.text(value));
    expect(card.height, greaterThan(56));
    expect(painted.top, greaterThanOrEqualTo(card.top + 13.5));
    expect(painted.bottom, lessThanOrEqualTo(card.bottom + 0.5));
    expect(painted.left, greaterThanOrEqualTo(card.left + 13.5));
    expect(painted.right, lessThanOrEqualTo(card.right - 13.5));
    expect(tester.takeException(), isNull);
  }

  testWidgets('2x tags row stacks label then wrapping value', (tester) async {
    await seedTags(['Spaziergang', 'Yoga']);
    await mount(tester, scale: 2);
    await tester.ensureVisible(find.text('Tags'));
    await tester.pumpAndSettle();
    expectTagValueFitsCard(tester, 'Spaziergang, Yoga');
    expect(
      tester.getTopLeft(find.text('Spaziergang, Yoga')).dy -
          tester.getTopLeft(find.text('Tags')).dy,
      closeTo(48, 2),
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-tags-large.png'),
    );
  });

  testWidgets('dark 2x tags row stacks', (tester) async {
    await seedTags(['Spaziergang', 'Yoga']);
    await mount(tester, scale: 2, brightness: Brightness.dark);
    await tester.ensureVisible(find.text('Tags'));
    await tester.pumpAndSettle();
    expectTagValueFitsCard(tester, 'Spaziergang, Yoga');
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-tags-large-dark.png'),
    );
  });

  testWidgets('320 2x long tags wrap inside the card', (tester) async {
    const tags = [
      'Spaziergang',
      'poor sleep',
      'screens late',
      'late meal',
      'meds',
      'workout',
      'Sehr langer selbstgewählter Tagname für den Umbruchtest',
    ];
    await seedTags(tags);
    await mount(tester, scale: 2, width: 320, height: 900);
    await tester.ensureVisible(find.text('Tags'));
    await tester.pumpAndSettle();
    expectTagValueFitsCard(tester, tags.map(journalTagLabel).join(', '));
  });

  testWidgets('1x 393 long preset tags fit the card', (tester) async {
    await seedTags(kJournalPresetTags);
    await mount(tester);
    await tester.ensureVisible(find.text('Tags'));
    await tester.pumpAndSettle();
    expectTagValueFitsCard(
      tester,
      kJournalPresetTags.map(journalTagLabel).join(', '),
    );
  });

  testWidgets('fields return keeps draft and shows hidden dirty values', (
    tester,
  ) async {
    repo.seedJournalEditor(filled: true, withCustom: true);
    await mount(tester);
    expect(find.text('Ausgeblendet'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Stimmung Sehr gut'));
    await tester.pump();
    await tester.ensureVisible(find.text('Magnesium'));
    await tester.tap(find.text('Magnesium'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '500');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Eigene Felder'));
    await tester.tap(find.text('Eigene Felder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Magnesium').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ausblenden'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Ausgeblendet'), findsWidgets);
    expect(find.textContaining('500'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    final snap = await repo.readJournalDay('2026-09-15');
    expect(snap.metrics['mood']!.value, 5);
    expect(snap.metrics['custom_magnesium']!.value, 500);
  });

  testWidgets('rating apply keeps imported time', (tester) async {
    repo.seedJournalEditor(filled: true);
    final before = await repo.readJournalDay('2026-09-15');
    await repo.patchJournalDay(
      JournalDayPatch.fromBase(
        before,
        metrics: const {'energy': JournalMetricValue(4, atMinuteOfDay: 855)},
      ),
    );
    await mount(tester);
    await tester.ensureVisible(find.text('Energie'));
    await tester.tap(find.text('Energie'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5').last);
    await tester.pump();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    final snap = await repo.readJournalDay('2026-09-15');
    expect(snap.metrics['energy']!.value, 5);
    expect(snap.metrics['energy']!.atMinuteOfDay, 855);
    expect(snap.metrics['sleep_quality']!.value, 4);
  });

  testWidgets('rating remove clears the entire answer', (tester) async {
    repo.seedJournalEditor(filled: true);
    final before = await repo.readJournalDay('2026-09-15');
    await repo.patchJournalDay(
      JournalDayPatch.fromBase(
        before,
        metrics: const {'energy': JournalMetricValue(4, atMinuteOfDay: 855)},
      ),
    );
    await mount(tester);
    await tester.ensureVisible(find.text('Energie'));
    await tester.tap(find.text('Energie'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wert entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    final snap = await repo.readJournalDay('2026-09-15');
    expect(snap.metrics.containsKey('energy'), isFalse);
    expect(snap.metrics['sleep_quality']!.value, 4);
  });

  testWidgets('missing boolean can be set and cleared', (tester) async {
    await mount(tester);
    await tester.tap(find.bySemanticsLabel('Koffein nach 14 Uhr: Ja'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Koffein nach 14 Uhr: Ja'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    final snap = await repo.readJournalDay('2026-09-15');
    expect(snap.metrics.containsKey('caffeine_late'), isFalse);
  });

  testWidgets('save failure retries on the same production editor', (
    tester,
  ) async {
    repo.seedJournalEditor(filled: true);
    await mount(tester);
    await tester.tap(find.bySemanticsLabel('Stimmung Sehr gut'));
    await tester.pump();
    repo.failJournalPatch = true;
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    repo.failJournalPatch = false;
    await tester.tap(find.byKey(const ValueKey('journal-save')));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandJournalEditor), findsNothing);
    expect((await repo.readJournalDay('2026-09-15')).metrics['mood']!.value, 5);
  });

  testWidgets('info discloses day and time, not implementation', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.text('Tagesjournal'), findsWidgets);
    expect(
      find.text(
        'Felder gelten für diesen Kalendertag. Eine Menge behält die letzte Uhrzeit, bis du sie änderst.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('schreibt nur geänderte Werte'), findsNothing);
    expect(find.textContaining('Keine Sorge'), findsNothing);
  });

  testWidgets('note and tags scroll fully above sticky save', (tester) async {
    repo.seedJournalEditor(filled: true);
    await mount(tester);
    await tester.ensureVisible(find.text('Tags'));
    await tester.pumpAndSettle();
    final tags = tester.getRect(find.text('Tags'));
    final save = tester.getRect(find.byKey(const ValueKey('journal-save')));
    expect(tags.bottom, lessThanOrEqualTo(save.top + 0.5));
    await tester.ensureVisible(find.byKey(const ValueKey('journal-note')));
    await tester.pumpAndSettle();
    final note = tester.getRect(find.byKey(const ValueKey('journal-note')));
    expect(note.bottom, lessThanOrEqualTo(save.top + 0.5));
  });

  testWidgets('375 2x keyboard keeps last fields above save', (tester) async {
    repo.seedJournalEditor(filled: true);
    await mount(tester, scale: 2, width: 375, height: 812);
    expectStackedGroupFullWidth(tester, 'Schlafqualität');
    expectStackedGroupFullWidth(tester, 'Wasser');
    await tester.ensureVisible(find.byKey(const ValueKey('journal-note')));
    await tester.tap(find.byKey(const ValueKey('journal-note')));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(() => tester.view.resetViewInsets());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('journal-note')));
    await tester.pumpAndSettle();
    final note = tester.getRect(find.byKey(const ValueKey('journal-note')));
    final save = tester.getRect(find.byKey(const ValueKey('journal-save')));
    expect(note.bottom, lessThanOrEqualTo(save.top + 0.5));
    await tester.ensureVisible(find.text('Tags'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('Tags')).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('journal-save'))).top + 0.5,
      ),
    );
  });

  testWidgets('hub onEdit opens the displayed day', (tester) async {
    String? opened;
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
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
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: OpenBandJournal(
            controller: controller,
            onEdit: (day) async => opened = day,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weitere Angaben'));
    await tester.pumpAndSettle();
    expect(opened, '2026-09-15');
  });
}
