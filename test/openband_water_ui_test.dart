import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/openband/water.dart';

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

  Future<void> seedWater(double? ml, {String day = '2026-09-15'}) async {
    if (ml == null) return;
    repo.seedJournalEditor(
      day: day,
      metrics: {'water_ml': JournalMetricValue(ml)},
    );
  }

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
    String day = '2026-09-15',
    OpenBandRepository? repository,
    FutureOr<void> Function()? onSaved,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _Host(
        repository: repository ?? repo,
        day: day,
        onSaved: onSaved,
        brightness: brightness,
        scale: scale,
        width: width,
        height: height,
        cardKey: UniqueKey(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> expectSheetChrome(
    WidgetTester tester, {
    required double safeTop,
    required double visibleBottom,
  }) async {
    final sheet = find.byKey(const ValueKey('journal-value-sheet'));
    expect(sheet, findsOneWidget);
    expect(tester.getRect(sheet).top, greaterThanOrEqualTo(safeTop));
    for (final target in [
      find.descendant(of: sheet, matching: find.text('Wasser')),
      find.descendant(of: sheet, matching: find.byTooltip('Schließen')),
      find.widgetWithText(FilledButton, 'Speichern'),
    ]) {
      expect(target.hitTestable(), findsOneWidget);
      final rect = tester.getRect(target);
      expect(rect.top, greaterThanOrEqualTo(safeTop));
      expect(rect.bottom, lessThanOrEqualTo(visibleBottom + 0.5));
    }
  }

  testWidgets('recorded amount, empty dash, +/- persist on the selected day', (
    tester,
  ) async {
    await seedWater(1250);
    var saved = 0;
    await mount(tester, onSaved: () => saved++);
    expect(find.text('1.250'), findsOneWidget);
    expect(find.text('ml'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('water-plus')));
    await tester.pumpAndSettle();
    expect(find.text('1.500'), findsOneWidget);
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      1500,
    );
    expect(saved, 1);
    await tester.tap(find.byKey(const ValueKey('water-minus')));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      1250,
    );
    expect(
      (await repo.readJournalDay('2026-09-14')).metrics.containsKey('water_ml'),
      isFalse,
    );
  });

  testWidgets('unknown minus stays absent; zero minus clears', (tester) async {
    await mount(tester);
    expect(find.text('—'), findsOneWidget);
    final minus = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('water-minus')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(minus.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('water-plus')));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      250,
    );

    await seedWater(0);
    await mount(tester);
    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('water-minus')));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics.containsKey('water_ml'),
      isFalse,
    );
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('manual save, clear, cancel, and zero stay distinct', (
    tester,
  ) async {
    await seedWater(1250);
    await mount(tester);
    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    expect(find.text('Menge'), findsNothing);
    expect(find.text('Zuletzt'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '2000');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      2000,
    );

    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      2000,
    );

    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '0');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      0,
    );

    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wert entfernen'));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics.containsKey('water_ml'),
      isFalse,
    );
  });

  testWidgets('read failure is not empty; retry loads the recorded amount', (
    tester,
  ) async {
    await seedWater(1250);
    repo.failJournalRead = true;
    await mount(tester);
    expect(find.text('Nicht geladen'), findsOneWidget);
    expect(find.text('—'), findsNothing);
    expect(find.text('1.250'), findsNothing);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    repo.failJournalRead = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('1.250'), findsOneWidget);
    expect(find.text('Nicht geladen'), findsNothing);
  });

  testWidgets('write failure does not change the shown amount', (tester) async {
    await seedWater(1250);
    var saved = 0;
    await mount(tester, onSaved: () => saved++);
    repo.failJournalPatch = true;
    await tester.tap(find.byKey(const ValueKey('water-plus')));
    await tester.pumpAndSettle();
    expect(find.text('1.250'), findsOneWidget);
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.byKey(const ValueKey('water-plus')), findsNothing);
    expect(find.byKey(const ValueKey('water-minus')), findsNothing);
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      1250,
    );
    expect(saved, 0);
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('1.250'), findsOneWidget);
    expect(saved, 0);
    repo.failJournalPatch = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('1.500'), findsOneWidget);
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(saved, 1);
  });

  testWidgets('absolute edit conflicts instead of overriding a delta', (
    tester,
  ) async {
    await seedWater(1250);
    await mount(tester);
    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '2000');
    await repo.adjustWater('2026-09-15', 250);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag wurde geändert'), findsOneWidget);
    expect(find.text('Neu laden'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('journal-value')))
          .controller!
          .text,
      '2000',
    );
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      1500,
    );
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('journal-value')))
          .controller!
          .text,
      '1500',
    );
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '1800');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      1800,
    );
  });

  testWidgets('save failure keeps entered text; conflict reload is explicit', (
    tester,
  ) async {
    await seedWater(1250);
    await mount(tester);
    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '900');
    repo.failJournalPatch = true;
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('Speichern'), findsNothing);
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('journal-value')))
          .controller!
          .text,
      '900',
    );
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      1250,
    );
    repo.failJournalPatch = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      900,
    );
  });

  testWidgets('post-write read failure retries read only', (tester) async {
    await seedWater(1250);
    await mount(tester);
    repo.failJournalRead = true;
    await tester.tap(find.byKey(const ValueKey('water-plus')));
    await tester.pumpAndSettle();
    expect(find.text('1.500'), findsOneWidget);
    expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
    expect(find.text('Nicht geladen'), findsNothing);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.byKey(const ValueKey('water-plus')), findsNothing);
    repo.failJournalRead = false;
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      1500,
    );
    repo.failJournalRead = true;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('1.500'), findsOneWidget);
    expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
    repo.failJournalRead = false;
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      1500,
    );
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('1.500'), findsOneWidget);
    expect(find.text('Laden fehlgeschlagen'), findsNothing);
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      1500,
    );
  });

  testWidgets('rapid plus waits for the in-flight write', (tester) async {
    await seedWater(1250);
    await mount(tester);
    final gate = Completer<void>();
    repo.journalPatchBarrier = gate.future;
    await tester.tap(find.byKey(const ValueKey('water-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('water-plus')));
    await tester.pump();
    gate.complete();
    repo.journalPatchBarrier = null;
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      1500,
    );
  });

  testWidgets(
    'late reads and writes from an old day do not land on the new one',
    (tester) async {
      await seedWater(1250, day: '2026-09-15');
      await seedWater(500, day: '2026-09-14');
      final readGate = Completer<void>();
      repo.journalReadBarrier = readGate.future;
      await tester.pumpWidget(_SwitchHost(repository: repo, day: '2026-09-15'));
      await tester.pump();
      final host = tester.state<_SwitchHostState>(find.byType(_SwitchHost));
      host.setDay('2026-09-14');
      await tester.pump();
      readGate.complete();
      repo.journalReadBarrier = null;
      await tester.pumpAndSettle();
      expect(find.text('500'), findsOneWidget);
      expect(find.text('1.250'), findsNothing);

      final writeGate = Completer<void>();
      repo.journalPatchBarrier = writeGate.future;
      await tester.tap(find.byKey(const ValueKey('water-plus')));
      await tester.pump();
      host.setDay('2026-09-15');
      await tester.pump();
      writeGate.complete();
      repo.journalPatchBarrier = null;
      await tester.pumpAndSettle();
      expect(find.text('1.250'), findsOneWidget);
      expect(
        (await repo.readJournalDay('2026-09-14')).metrics['water_ml']!.value,
        750,
      );
      expect(
        (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
        1250,
      );
    },
  );

  testWidgets('late completion from a replaced repository is ignored', (
    tester,
  ) async {
    await seedWater(1250);
    final other = galleryRepo();
    other.seedJournalEditor(
      metrics: const {'water_ml': JournalMetricValue(400)},
    );
    final gate = Completer<void>();
    repo.journalReadBarrier = gate.future;
    await tester.pumpWidget(
      _Host(
        repository: repo,
        day: '2026-09-15',
        brightness: Brightness.light,
        scale: 1,
        width: 393,
        height: 852,
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      _Host(
        repository: other,
        day: '2026-09-15',
        brightness: Brightness.light,
        scale: 1,
        width: 393,
        height: 852,
      ),
    );
    await tester.pump();
    gate.complete();
    repo.journalReadBarrier = null;
    await tester.pumpAndSettle();
    expect(find.text('400'), findsOneWidget);
    expect(find.text('1.250'), findsNothing);
  });

  testWidgets('public amount sheet keeps header and save in the safe area', (
    tester,
  ) async {
    await seedWater(1250);
    await mount(tester, width: 375, height: 812);
    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await expectSheetChrome(tester, safeTop: 59, visibleBottom: 812);

    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    await mount(tester, width: 375, height: 812, scale: 2);
    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await expectSheetChrome(tester, safeTop: 59, visibleBottom: 812);

    tester.view.viewInsets = const FakeViewPadding(bottom: 308);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await expectSheetChrome(tester, safeTop: 59, visibleBottom: 812 - 308);
    expect(find.text('Menge'), findsNothing);
    expect(
      find.byKey(const ValueKey('journal-value')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('canonical card goldens', (tester) async {
    await seedWater(1250);
    await mount(tester);
    await expectLater(
      find.byKey(const ValueKey('water-card')),
      matchesGoldenFile('openband_goldens/water-light.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('water-card')),
      matchesGoldenFile('openband_goldens/water-dark.png'),
    );
    repo = galleryRepo();
    await mount(tester);
    await expectLater(
      find.byKey(const ValueKey('water-card')),
      matchesGoldenFile('openband_goldens/water-empty.png'),
    );
    await seedWater(1250);
    await mount(tester, scale: 2, width: 375, height: 812);
    await expectLater(
      find.byKey(const ValueKey('water-card')),
      matchesGoldenFile('openband_goldens/water-2x.png'),
    );
    repo.failJournalRead = true;
    await seedWater(1250);
    await mount(tester);
    await expectLater(
      find.byKey(const ValueKey('water-card')),
      matchesGoldenFile('openband_goldens/water-read-error.png'),
    );
  }, tags: const ['golden']);

  testWidgets('canonical amount sheet goldens', (tester) async {
    await seedWater(1250);
    await mount(tester);
    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/water-sheet.png'),
    );
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    await mount(tester, brightness: Brightness.dark);
    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/water-sheet-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('callback throw still refreshes; retry is read only', (
    tester,
  ) async {
    await seedWater(1250);
    var calls = 0;
    await mount(
      tester,
      onSaved: () {
        calls++;
        if (calls == 1) throw StateError('parent refresh');
      },
    );
    await tester.tap(find.byKey(const ValueKey('water-plus')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('1.500'), findsOneWidget);
    expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
    expect(calls, 1);
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      1500,
    );
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('Laden fehlgeschlagen'), findsNothing);
    expect(find.text('1.500'), findsOneWidget);
    expect(calls, 2);
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      1500,
    );
    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '1800');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      1800,
    );
  });

  testWidgets('sheet conflict reload keeps text until a successful read', (
    tester,
  ) async {
    await seedWater(1250);
    await mount(tester);
    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '2000');
    await repo.adjustWater('2026-09-15', 250);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag wurde geändert'), findsOneWidget);
    repo.failJournalRead = true;
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
    expect(find.text('Neu laden'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('journal-value')))
          .controller!
          .text,
      '2000',
    );
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('journal-value')))
          .controller!
          .text,
      '2000',
    );
    repo.failJournalRead = false;
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(find.text('Laden fehlgeschlagen'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('journal-value')))
          .controller!
          .text,
      '1500',
    );
  });

  testWidgets(
    'post-sheet read stays busy so plus cannot race a stale baseline',
    (tester) async {
      await seedWater(1250);
      await mount(tester);
      await tester.tap(find.text('Wasser'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('journal-value')),
        '2000',
      );
      final gate = Completer<void>();
      repo.journalReadBarrier = gate.future;
      await tester.tap(find.text('Speichern'));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        if (find
            .byKey(const ValueKey('journal-value-sheet'))
            .evaluate()
            .isEmpty) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byKey(const ValueKey('journal-value-sheet')), findsNothing);
      expect(find.text('2.000'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('water-plus')));
      await tester.pump();
      gate.complete();
      repo.journalReadBarrier = null;
      await tester.pumpAndSettle();
      expect(
        (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
        2000,
      );
      expect(find.text('2.000'), findsOneWidget);
    },
  );

  testWidgets('day change while the sheet is open does not commit', (
    tester,
  ) async {
    await seedWater(1250, day: '2026-09-15');
    await seedWater(500, day: '2026-09-14');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_SessionHost(repository: repo, day: '2026-09-15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '2000');
    tester
        .state<_SessionHostState>(find.byType(_SessionHost))
        .setDay('2026-09-14');
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('journal-value-sheet')), findsNothing);
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      1250,
    );
    expect(
      (await repo.readJournalDay('2026-09-14')).metrics['water_ml']!.value,
      500,
    );
    expect(find.text('500'), findsOneWidget);
  });

  testWidgets('unmount with an open sheet is safe', (tester) async {
    await seedWater(1250);
    await mount(tester);
    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('error, conflict, and large IME goldens', (tester) async {
    await seedWater(1250);
    await mount(tester);
    repo.failJournalPatch = true;
    await tester.tap(find.byKey(const ValueKey('water-plus')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('water-card')),
      matchesGoldenFile('openband_goldens/water-write-error.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    repo.failJournalPatch = true;
    await tester.tap(find.byKey(const ValueKey('water-plus')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('water-card')),
      matchesGoldenFile('openband_goldens/water-write-error-dark.png'),
    );
    repo.failJournalPatch = false;

    await mount(tester);
    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '1500');
    repo.failJournalPatch = true;
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/water-sheet-save-error.png'),
    );
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    repo.failJournalPatch = false;

    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-value')), '2000');
    await repo.adjustWater('2026-09-15', 250);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/water-sheet-conflict.png'),
    );
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();

    repo = galleryRepo();
    await seedWater(1250);
    await mount(tester, scale: 2, width: 375, height: 812);
    await tester.tap(find.text('Wasser'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 308);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/water-sheet-2x-ime.png'),
    );
  }, tags: const ['golden']);

  Future<void> pumpRevision(
    WidgetTester tester, {
    required OpenBandRepository repository,
    int revision = 0,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _RevisionHost(repository: repository, revision: revision),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('same State rereads water when revision moves', (tester) async {
    final spy = _countingRepo()
      ..seedJournalEditor(
        metrics: const {'water_ml': JournalMetricValue(1250)},
      );
    await pumpRevision(tester, repository: spy);
    expect(find.text('1.250'), findsOneWidget);
    expect(spy.reads, 1);
    await spy.writeJournal('2026-09-15', 'water_ml', 2000);
    tester.state<_RevisionHostState>(find.byType(_RevisionHost)).setRevision(1);
    await tester.pumpAndSettle();
    expect(find.text('2.000'), findsOneWidget);
    expect(spy.reads, 2);
  });

  testWidgets(
    'revision during an in-flight plus does not duplicate or revert',
    (tester) async {
      final spy = _countingRepo()
        ..seedJournalEditor(
          metrics: const {'water_ml': JournalMetricValue(1250)},
        );
      await pumpRevision(tester, repository: spy);
      expect(spy.reads, 1);
      final gate = Completer<void>();
      spy.journalPatchBarrier = gate.future;
      await tester.tap(find.byKey(const ValueKey('water-plus')));
      await tester.pump();
      tester
          .state<_RevisionHostState>(find.byType(_RevisionHost))
          .setRevision(1);
      await tester.pump();
      expect(find.text('1.250'), findsOneWidget);
      expect(find.text('Speichern fehlgeschlagen'), findsNothing);
      gate.complete();
      spy.journalPatchBarrier = null;
      await tester.pumpAndSettle();
      expect(find.text('1.500'), findsOneWidget);
      expect(
        (await spy.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
        1500,
      );
      expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    },
  );

  testWidgets(
    'revision keeps sheet text and conflict until the sheet settles',
    (tester) async {
      await seedWater(1250);
      await pumpRevision(tester, repository: repo);
      await tester.tap(find.text('Wasser'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('journal-value')),
        '2000',
      );
      await repo.writeJournal('2026-09-15', 'water_ml', 1800);
      tester
          .state<_RevisionHostState>(find.byType(_RevisionHost))
          .setRevision(1);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('journal-value')))
            .controller!
            .text,
        '2000',
      );
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Eintrag wurde geändert'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('journal-value')))
            .controller!
            .text,
        '2000',
      );
      tester
          .state<_RevisionHostState>(find.byType(_RevisionHost))
          .setRevision(2);
      await tester.pump();
      expect(find.text('Eintrag wurde geändert'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('journal-value')))
            .controller!
            .text,
        '2000',
      );
      await tester.tap(find.byTooltip('Schließen'));
      await tester.pumpAndSettle();
      expect(find.text('1.800'), findsOneWidget);
    },
  );

  testWidgets('revision during a failed delta keeps the retry', (tester) async {
    await seedWater(1250);
    await pumpRevision(tester, repository: repo);
    repo.failJournalPatch = true;
    await tester.tap(find.byKey(const ValueKey('water-plus')));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    await repo.writeJournal('2026-09-15', 'water_ml', 900);
    tester.state<_RevisionHostState>(find.byType(_RevisionHost)).setRevision(1);
    await tester.pumpAndSettle();
    expect(find.text('1.250'), findsOneWidget);
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    repo.failJournalPatch = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['water_ml']!.value,
      1150,
    );
  });

  testWidgets('rebuilds with the same revision do not reread', (tester) async {
    final spy = _countingRepo()
      ..seedJournalEditor(
        metrics: const {'water_ml': JournalMetricValue(1250)},
      );
    await pumpRevision(tester, repository: spy);
    expect(spy.reads, 1);
    final host = tester.state<_RevisionHostState>(find.byType(_RevisionHost));
    host.rebuild();
    await tester.pump();
    host.rebuild();
    await tester.pump();
    host.setRevision(0);
    await tester.pumpAndSettle();
    expect(spy.reads, 1);
    expect(find.text('1.250'), findsOneWidget);
  });
}

class _CountingRepo extends SyntheticOpenBandRepository {
  int reads = 0;
  _CountingRepo(super.summary, super.detail) : super.fromMaps();

  @override
  Future<JournalDaySnapshot> readJournalDay(String day) async {
    reads++;
    return super.readJournalDay(day);
  }
}

_CountingRepo _countingRepo() => _CountingRepo(
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

class _RevisionHost extends StatefulWidget {
  final OpenBandRepository repository;
  final int revision;
  const _RevisionHost({required this.repository, required this.revision});

  @override
  State<_RevisionHost> createState() => _RevisionHostState();
}

class _RevisionHostState extends State<_RevisionHost> {
  late int revision = widget.revision;

  void setRevision(int next) => setState(() => revision = next);

  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('de'),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('de')],
      theme: openBandTheme(
        Brightness.light,
      ).copyWith(platform: TargetPlatform.iOS),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 59, bottom: 34),
          viewPadding: const EdgeInsets.only(top: 59, bottom: 34),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) {
          final p = OB.of(context);
          return Scaffold(
            backgroundColor: p.canvas,
            body: Align(
              alignment: Alignment.topCenter,
              child: OpenBandWaterCard(
                repository: widget.repository,
                day: '2026-09-15',
                revision: revision,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SwitchHost extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  const _SwitchHost({required this.repository, required this.day});

  @override
  State<_SwitchHost> createState() => _SwitchHostState();
}

class _SwitchHostState extends State<_SwitchHost> {
  late String day = widget.day;

  void setDay(String next) => setState(() => day = next);

  @override
  Widget build(BuildContext context) {
    return _Host(
      repository: widget.repository,
      day: day,
      brightness: Brightness.light,
      scale: 1,
      width: 393,
      height: 852,
    );
  }
}

class _Host extends StatelessWidget {
  final OpenBandRepository repository;
  final String day;
  final FutureOr<void> Function()? onSaved;
  final Brightness brightness;
  final double scale;
  final double width;
  final double height;
  final Key? cardKey;
  const _Host({
    required this.repository,
    required this.day,
    this.onSaved,
    required this.brightness,
    required this.scale,
    required this.width,
    required this.height,
    this.cardKey,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('de'),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('de')],
      theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(top: 59, bottom: 34),
          viewPadding: const EdgeInsets.only(top: 59, bottom: 34),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) {
          final p = OB.of(context);
          return Scaffold(
            backgroundColor: p.canvas,
            body: SizedBox(
              width: width,
              height: height,
              child: RepaintBoundary(
                key: const ValueKey('capture'),
                child: ColoredBox(
                  color: p.canvas,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: RepaintBoundary(
                        key: const ValueKey('water-card'),
                        child: OpenBandWaterCard(
                          key: cardKey,
                          repository: repository,
                          day: day,
                          onSaved: onSaved,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SessionHost extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  const _SessionHost({required this.repository, required this.day});

  @override
  State<_SessionHost> createState() => _SessionHostState();
}

class _SessionHostState extends State<_SessionHost> {
  late String day = widget.day;

  void setDay(String next) => setState(() => day = next);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('de'),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('de')],
      theme: openBandTheme(
        Brightness.light,
      ).copyWith(platform: TargetPlatform.iOS),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 59, bottom: 34),
          viewPadding: const EdgeInsets.only(top: 59, bottom: 34),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) {
          final p = OB.of(context);
          return Scaffold(
            backgroundColor: p.canvas,
            body: Align(
              alignment: Alignment.topCenter,
              child: OpenBandWaterCard(repository: widget.repository, day: day),
            ),
          );
        },
      ),
    );
  }
}
