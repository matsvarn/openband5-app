import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/naps.dart';
import 'package:openstrap_edge/openband/screens.dart';
import 'package:openstrap_edge/openband/sleep_editor.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

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
  late OpenBandController controller;

  setUp(() {
    repo = SyntheticOpenBandRepository.fromMaps(
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
    controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
    );
  });
  tearDown(() => controller.dispose());

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    Widget? home,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: RepaintBoundary(key: const ValueKey('capture'), child: child!),
        ),
        home: home ?? OpenBandNaps(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('list shows detected nap and is reachable from sleep', (
    tester,
  ) async {
    await mount(tester, home: OpenBandSleep(controller: controller));
    await tester.scrollUntilVisible(
      find.text('Nickerchen'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Nickerchen'));
    await tester.pumpAndSettle();
    expect(find.text('14:10–14:42'), findsOneWidget);
    expect(find.text('Erkannt'), findsOneWidget);
    expect(find.text('32'), findsWidgets);
    expect(find.text('32 Min.'), findsOneWidget);
    expect(find.text('1 Nickerchen'), findsOneWidget);
    expect(find.text('Synthetische Daten'), findsOneWidget);
    expect(find.text('Selbst eingetragen'), findsNothing);
  });

  testWidgets('add, edit, remove and restore a nap', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Nickerchen ergänzen'));
    await tester.pumpAndSettle();
    expect(find.text('Nickerchen ergänzen'), findsWidgets);
    expect(find.text('Selbst eingetragen'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('nap-start')), '16:00');
    await tester.enterText(find.byKey(const ValueKey('nap-end')), '16:40');
    await tester.pumpAndSettle();
    expect(find.text('40 Minuten'), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('16:00–16:40'), findsOneWidget);
    expect(find.text('Manuell'), findsOneWidget);

    await tester.tap(find.text('16:00–16:40'));
    await tester.pumpAndSettle();
    expect(find.text('Nickerchen bearbeiten'), findsOneWidget);
    expect(find.text('40 Minuten'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('nap-start')), '16:10');
    await tester.enterText(find.byKey(const ValueKey('nap-end')), '16:50');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Änderungen speichern'));
    await tester.pumpAndSettle();
    expect(find.text('16:10–16:50'), findsOneWidget);
    expect(find.text('Manuell'), findsOneWidget);

    await tester.tap(find.text('14:10–14:42'));
    await tester.pumpAndSettle();
    expect(find.text('32 Minuten'), findsOneWidget);
    await tester.tap(find.text('Nickerchen entfernen'));
    await tester.pumpAndSettle();
    expect(find.text('14:10–14:42 entfernen?'), findsOneWidget);
    await tester.tap(find.text('Entfernen').last);
    await tester.pumpAndSettle();
    expect(find.text('14:10–14:42'), findsOneWidget);
    expect(find.text('Wiederherstellen'), findsOneWidget);
    expect(find.text('Erkannt'), findsNothing);

    await tester.tap(find.text('Wiederherstellen'));
    await tester.pumpAndSettle();
    expect(find.text('Erkannt'), findsOneWidget);
    expect(find.text('14:10–14:42'), findsWidgets);
  });

  testWidgets('cancel does not write', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Nickerchen ergänzen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('nap-start')), '17:00');
    await tester.enterText(find.byKey(const ValueKey('nap-end')), '17:20');
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('17:00–17:20'), findsNothing);
    expect((await repo.readNaps('2026-09-15')).sessions, hasLength(1));
  });

  testWidgets('save failure keeps the editor', (tester) async {
    repo.scenario = SyntheticScenario.saveFailure;
    await mount(tester);
    await tester.tap(find.text('Nickerchen ergänzen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Nickerchen ergänzen'), findsWidgets);
    expect(find.text('Erneut speichern'), findsOneWidget);
    expect(find.text('Dein Eintrag bleibt erhalten'), findsNothing);
  });

  testWidgets('calculation failure keeps edits and offers retry', (
    tester,
  ) async {
    repo.scenario = SyntheticScenario.calculationFailure;
    await mount(tester);
    await tester.tap(find.text('Nickerchen ergänzen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('nap-start')), '16:00');
    await tester.enterText(find.byKey(const ValueKey('nap-end')), '16:40');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Gespeichert · Auswertung offen'), findsOneWidget);
    expect(find.text('Erneut auswerten'), findsOneWidget);
    expect(find.text('Dein Eintrag bleibt erhalten'), findsNothing);
    expect(find.text('16:00–16:40'), findsOneWidget);
    expect(find.text('14:10–14:42'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('72'), findsNothing);
    expect((await repo.readNaps('2026-09-15')).totalMin, isNull);
    expect((await repo.readNaps('2026-09-15')).sessions, hasLength(2));
    repo.scenario = SyntheticScenario.complete;
    await tester.tap(find.text('Erneut auswerten'));
    await tester.pumpAndSettle();
    expect(find.text('Erneut auswerten'), findsNothing);
    expect(find.text('16:00–16:40'), findsOneWidget);
  });

  test(
    'synthetic complete total stays unknown if any duration is unknown',
    () async {
      final start = DateTime(2026, 9, 15, 14, 10);
      repo.seedNaps(
        NapDay(
          day: '2026-09-15',
          judged: true,
          sessions: [
            NapSession(
              start: start,
              end: start.add(const Duration(minutes: 32)),
              source: NapSource.detected,
            ),
          ],
        ),
      );

      await repo.recalculateNaps(day: '2026-09-15', revision: 1);

      expect((await repo.readNaps('2026-09-15')).totalMin, isNull);
    },
  );

  testWidgets('judged empty is zero, unknown is an em dash', (tester) async {
    repo.seedNaps(const NapDay(day: '2026-09-15', judged: true, totalMin: 0));
    await mount(tester);
    expect(find.text('Keine Nickerchen erkannt'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.text('Noch nicht bestimmbar'), findsNothing);
    expect(find.text('1 Nickerchen'), findsNothing);

    repo.seedNaps(const NapDay(day: '2026-09-15'));
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Noch nicht bestimmbar'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('Keine Nickerchen erkannt'), findsNothing);
    expect(find.text('1 Nickerchen'), findsNothing);
  });

  testWidgets('list and editor wrap at 375 and 2x text without overflow', (
    tester,
  ) async {
    await mount(tester, width: 375, scale: 2, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    expect(find.text('14:10–14:42'), findsOneWidget);
    expect(find.text('Gerätezeit'), findsNothing);
    await tester.tap(find.text('Nickerchen ergänzen'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('nap-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('nap-end')), findsOneWidget);
    final field = tester.getSize(find.byKey(const ValueKey('nap-start')));
    expect(field.width, greaterThan(88));
    expect(field.height, greaterThan(24));
  });

  testWidgets('nap icon sits at card padding and durations align', (
    tester,
  ) async {
    final early = DateTime(2026, 9, 15, 14, 10);
    final late = DateTime(2026, 9, 15, 16);
    repo.seedNaps(
      NapDay(
        day: '2026-09-15',
        judged: true,
        totalMin: 50,
        sessions: [
          NapSession(
            start: early,
            end: DateTime(2026, 9, 15, 14, 42),
            source: NapSource.detected,
            durationMin: 32,
          ),
          NapSession(
            start: late,
            end: DateTime(2026, 9, 15, 16, 18),
            source: NapSource.manual,
            durationMin: 18,
          ),
        ],
      ),
    );
    await mount(tester, width: 375);
    final time = find.text('14:10–14:42');
    final card = tester.getRect(
      find.ancestor(of: time, matching: find.byType(OBCard)).first,
    );
    final icon = tester.getRect(
      find.byKey(ValueKey('nap-icon-${early.millisecondsSinceEpoch ~/ 1000}')),
    );
    expect(icon.left, closeTo(card.left + 14, 1.5));
    expect(icon.width, 36);
    final d32 = tester.getRect(find.text('32 Min.'));
    final d18 = tester.getRect(find.text('18 Min.'));
    expect(d32.right, closeTo(d18.right, 1.5));
  });

  testWidgets('at 375 2x duration stacks on the time column left lane', (
    tester,
  ) async {
    await mount(tester, width: 375, scale: 2);
    expect(tester.takeException(), isNull);
    final time = tester.getRect(find.text('14:10–14:42'));
    final duration = tester.getRect(find.text('32 Min.'));
    expect(time.overlaps(duration), isFalse);
    expect(duration.left, closeTo(time.left, 1.5));
    expect(duration.top, greaterThanOrEqualTo(time.bottom - 2));
  });

  testWidgets('removed row restore control stays tappable at 2x', (
    tester,
  ) async {
    await mount(tester, width: 375, scale: 2);
    await tester.scrollUntilVisible(
      find.text('14:10–14:42'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('14:10–14:42'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Nickerchen entfernen'),
      200,
      scrollable: find
          .ancestor(of: find.text('Beginn'), matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(find.text('Nickerchen entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final restore = find.text('Wiederherstellen');
    expect(restore, findsOneWidget);
    final time = tester.getRect(find.text('14:10–14:42'));
    final button = tester.getRect(
      find.ancestor(of: restore, matching: find.byType(TextButton)),
    );
    expect(time.overlaps(button), isFalse);
    expect(button.height, greaterThanOrEqualTo(44));
  });

  testWidgets('restore recalculates the original day after selection changes', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('14:10–14:42'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nickerchen entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pumpAndSettle();
    expect(find.text('Wiederherstellen'), findsOneWidget);

    final held = Completer<void>();
    repo.restoreBarrier = held.future;
    repo.napRecalcCalls.clear();
    await tester.tap(find.text('Wiederherstellen'));
    await tester.pump();
    await tester.pump();
    unawaited(controller.selectDay('2026-09-14'));
    await tester.pump();
    expect(controller.selectedDay, '2026-09-14');
    held.complete();
    await tester.pumpAndSettle();
    expect(controller.selectedDay, '2026-09-14');
    expect(repo.napRecalcCalls.map((c) => c.day), ['2026-09-15']);
    expect(find.text('Wiederherstellen fehlgeschlagen.'), findsNothing);
  });

  testWidgets('shared sleep time fields wrap at 2x instead of clipping', (
    tester,
  ) async {
    await mount(
      tester,
      width: 375,
      scale: 2,
      home: SleepEditor(controller: controller),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('sleep-onset')), findsOneWidget);
    expect(find.byKey(const ValueKey('sleep-wake')), findsOneWidget);
    final onset = tester.getSize(find.byKey(const ValueKey('sleep-onset')));
    expect(onset.width, greaterThan(88));
    expect(onset.height, lessThan(200));
    final dates = find.widgetWithText(TextButton, '14. September');
    expect(dates, findsWidgets);
    for (var i = 0; i < dates.evaluate().length; i++) {
      final size = tester.getSize(dates.at(i));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('nap list golden light', (tester) async {
    await mount(tester);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/naps-list-light.png'),
    );
  });

  testWidgets('nap list golden dark', (tester) async {
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/naps-list-dark.png'),
    );
  });

  testWidgets('nap editor golden', (tester) async {
    await mount(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Nickerchen ergänzen'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/naps-editor.png'),
    );
  });

  testWidgets('nap edit golden', (tester) async {
    await mount(tester);
    await tester.tap(find.text('14:10–14:42'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/naps-edit.png'),
    );
  });

  testWidgets('nap recalc failure golden', (tester) async {
    repo.scenario = SyntheticScenario.calculationFailure;
    await mount(tester);
    await tester.tap(find.text('Nickerchen ergänzen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('nap-start')), '16:00');
    await tester.enterText(find.byKey(const ValueKey('nap-end')), '16:40');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('—'), findsWidgets);
    expect(find.text('16:00–16:40'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/naps-error.png'),
    );
  });

  testWidgets('nap list golden at 375 2x', (tester) async {
    await mount(tester, width: 375, scale: 2);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/naps-large-text.png'),
    );
  });
}
