import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/gestures/device_action.dart';
import 'package:openstrap_edge/l10n/app_localizations.dart';
import 'package:openstrap_edge/main_gallery.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/ui2/profile/gestures.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final frames = <Map<String, Object?>>[];

  testWidgets('native first-flow visual review with isolated synthetic data', (
    tester,
  ) async {
    await initializeDateFormatting('de_DE');
    final semantics = tester.ensureSemantics();
    final previousHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    try {
      Future<void> press(String text) async {
        final target = find.text(text);
        if (target.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            target,
            200,
            scrollable: find.byType(Scrollable).last,
          );
        } else {
          await tester.ensureVisible(target);
        }
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<void> pressSleepEditor() async {
        final target = find.byTooltip('Schlafzeiten ändern');
        await tester.scrollUntilVisible(
          target,
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<SyntheticOpenBandRepository> mount({
        SyntheticScenario scenario = SyntheticScenario.complete,
        Brightness brightness = Brightness.light,
        double? scale,
      }) async {
        final repository = await loadGalleryRepository();
        repository.scenario = scenario;
        await tester.pumpWidget(
          OpenBandGallery(
            key: UniqueKey(),
            repository: repository,
            showControls: false,
            initialBrightness: brightness,
            initialTextScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        return repository;
      }

      Future<void> pop() async {
        final back = find.byType(BackButton);
        if (back.evaluate().isNotEmpty) {
          await tester.tap(back);
        } else {
          await tester
              .element(find.byType(Scaffold).first)
              .findAncestorStateOfType<NavigatorState>()
              ?.maybePop();
        }
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        expect(tester.takeException(), isNull);
        // UIKit chrome animates independently of Flutter's scheduled frames.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        const port = int.fromEnvironment('OPENBAND_REVIEW_PORT');
        if (port == 0) {
          await binding.takeScreenshot(name);
        } else {
          final client = HttpClient();
          try {
            final request = await client.getUrl(
              Uri.parse('http://127.0.0.1:$port/capture/$name'),
            );
            final response = await request.close();
            await response.drain<void>();
            if (response.statusCode != 200) {
              throw StateError('Native display capture failed: $name');
            }
          } finally {
            client.close(force: true);
          }
        }
        binding.reportData ??= <String, dynamic>{};
        final view = tester.view;
        frames.add({
          'name': name,
          'synthetic': true,
          'logicalWidth': view.physicalSize.width / view.devicePixelRatio,
          'logicalHeight': view.physicalSize.height / view.devicePixelRatio,
          'devicePixelRatio': view.devicePixelRatio,
          'keyboardInset': view.viewInsets.bottom / view.devicePixelRatio,
          'captureKind': port == 0 ? 'flutter-surface' : 'simulator-display',
          'semantics': binding.renderViews
              .map(
                (renderView) => renderView
                    .owner
                    ?.semanticsOwner
                    ?.rootSemanticsNode
                    ?.toStringDeep(),
              )
              .whereType<String>()
              .join('\n'),
        });
        binding.reportData!['frames'] = frames;
      }

      Future<void> edit({
        String variant = '',
        bool captureEntry = false,
      }) async {
        await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
        await tester.pumpAndSettle();
        await pressSleepEditor();
        await tester.pumpAndSettle();
        if (captureEntry) await capture('correction-entry$variant');
        await tester.enterText(
          find.byKey(const ValueKey('sleep-onset')),
          '23:25',
        );
        await tester.pumpAndSettle();
        await capture('correction-keyboard$variant');
        await tester.ensureVisible(find.text('Änderung ansehen'));
        await tester.tap(find.text('Änderung ansehen'));
        await tester.pumpAndSettle();
        expect(find.text('7h29'), findsOneWidget);
      }

      for (final scenario in [
        SyntheticScenario.complete,
        SyntheticScenario.dense,
        SyntheticScenario.partial,
        SyntheticScenario.missing,
        SyntheticScenario.processing,
        SyntheticScenario.disconnected,
        SyntheticScenario.interrupted,
      ]) {
        for (final brightness in Brightness.values) {
          await mount(scenario: scenario, brightness: brightness);
          await capture('overview-${scenario.name}-${brightness.name}');
          if ([
            SyntheticScenario.complete,
            SyntheticScenario.dense,
            SyntheticScenario.partial,
            SyntheticScenario.missing,
            SyntheticScenario.processing,
          ].contains(scenario)) {
            await tester.tap(find.bySemanticsLabel(RegExp(r'^Schlaf, ')).first);
            await tester.pumpAndSettle();
            await capture('sleep-${scenario.name}-${brightness.name}');
          }
        }
      }

      await mount();
      await tester.tap(find.text(obDayTitle('2026-09-15')));
      await tester.pumpAndSettle();
      await capture('date-selection');
      await tester.tap(find.byTooltip('Abbrechen'));
      await tester.pumpAndSettle();
      await edit(captureEntry: true);
      await capture('correction-preview');
      await press('Schlafzeiten speichern');
      expect(find.text('Schlaf aktualisiert'), findsWidgets);
      await capture('correction-complete');
      await press('Zur Übersicht');
      expect(find.bySemanticsLabel('Schlaf, 7h08 '), findsOneWidget);
      await capture('overview-corrected');

      final failing = await mount(scenario: SyntheticScenario.saveFailure);
      await edit(variant: '-save-failure');
      await press('Schlafzeiten speichern');
      expect(await failing.readDraft('2026-09-15'), isNotNull);
      await capture('save-failure');
      failing.scenario = SyntheticScenario.complete;
      await press('Erneut speichern');
      expect(find.text('Schlaf aktualisiert'), findsWidgets);
      await capture('save-retry-complete');

      final calculationFailure = await mount(
        scenario: SyntheticScenario.calculationFailure,
      );
      await edit(variant: '-calculation-failure');
      await press('Schlafzeiten speichern');
      expect(find.text('Auswertung erneut starten'), findsOneWidget);
      await capture('calculation-failure');
      calculationFailure.scenario = SyntheticScenario.complete;
      await press('Auswertung erneut starten');
      await capture('calculation-retry-complete');
      await press('Nacht ansehen');
      await tester.scrollUntilVisible(
        find.byTooltip('Schlafzeiten ändern'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Schlafzeiten ändern'), findsOneWidget);
      await capture('sleep-corrected');

      final pending = await mount(brightness: Brightness.dark);
      final calculation = Completer<void>();
      pending.calculationBarrier = calculation.future;
      await edit(variant: '-dark', captureEntry: true);
      await capture('correction-preview-dark');
      await press('Schlafzeiten speichern');
      expect(find.text('Zeiten gespeichert'), findsWidgets);
      await capture('correction-pending-dark');
      calculation.complete();
      await tester.pumpAndSettle();
      await capture('correction-complete-dark');
      await press('Automatische Zeiten wiederherstellen');
      await capture('restore-confirmation-dark');
      await press('Wiederherstellen');
      expect((await pending.readDay('2026-09-15')).sleep.duration.value, 438);
      expect(find.text('7h18'), findsNWidgets(2));

      await mount();
      await tester.tap(find.text(obDayTitle('2026-09-15')));
      await tester.pumpAndSettle();
      await press('14');
      await capture('date-selected-night');
      await press('14. September ansehen');
      expect(find.bySemanticsLabel('Schlaf, 7h02 '), findsOneWidget);
      await capture('overview-historical');

      final draftFailure = await mount(
        scenario: SyntheticScenario.draftFailure,
      );
      await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
      await tester.pumpAndSettle();
      await pressSleepEditor();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('sleep-onset')),
        '23:25',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Entwurf erneut sichern'));
      await capture('draft-save-failure');
      draftFailure.scenario = SyntheticScenario.complete;
      await press('Entwurf erneut sichern');
      expect((await draftFailure.readDraft('2026-09-15'))?.onset.minute, 25);

      await mount(scenario: SyntheticScenario.partial);
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Schlaf, ')).first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsLabel(RegExp('02:10 bis 02:34: Keine Daten')).first,
      );
      await tester.pumpAndSettle();
      await capture('sleep-phases');
      await tester.tap(find.byTooltip('Schließen'));
      await tester.pumpAndSettle();

      final cancelled = await mount();
      await edit(variant: '-cancel');
      await press('Weiter bearbeiten');
      await tester.tap(find.byTooltip('Zurück').first);
      await tester.pumpAndSettle();
      await capture('draft-leave-confirmation');
      await press('Entwurf behalten');
      await pressSleepEditor();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sleep-onset')))
            .controller
            ?.text,
        '23:25',
      );
      await press('Änderung ansehen');
      await press('Änderung verwerfen');
      expect(await cancelled.readDraft('2026-09-15'), isNull);
      expect((await cancelled.readDay('2026-09-15')).sleep.duration.value, 438);
      expect(find.text('7h18'), findsNWidgets(2));

      await mount(scale: 2);
      await capture('overview-large-text');
      await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
      await tester.pumpAndSettle();
      await capture('sleep-large-text');
      await pressSleepEditor();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('sleep-onset')),
        '23:25',
      );
      await tester.pumpAndSettle();
      await capture('correction-large-keyboard');
      await tester.ensureVisible(find.byKey(const ValueKey('sleep-wake')));
      await tester.enterText(find.byKey(const ValueKey('sleep-wake')), '06:54');
      await tester.pumpAndSettle();
      await capture('correction-large-wake-keyboard');
      await press('Änderung ansehen');
      await capture('correction-large-preview');
      await press('Schlafzeiten speichern');
      await capture('correction-large-complete');
      await press('Zur Übersicht');
      await tester.tap(find.text(obDayTitle('2026-09-15')));
      await tester.pumpAndSettle();
      await capture('date-large-text');
      await press('14');
      await press('14. September ansehen');
      expect(find.bySemanticsLabel('Schlaf, 7h02 '), findsOneWidget);

      // ── Hub- und Flow-Captures der neuen Oberflächen ──
      await mount();
      await press('Gesundheit');
      await capture('health-hub');
      await press('30 Nächte');
      await capture('health-30');

      await press('Training');
      await capture('training-hub');
      await tester.tap(find.text('Starten'));
      await tester.pump(const Duration(seconds: 1));
      await capture('strength-live');
      await tester.tap(find.byTooltip('Einklappen'));
      await tester.pumpAndSettle();
      // 'Laufen' trifft Quick-Start-Tile und Zuletzt-Zeile; die Zeile ist letztere.
      await tester.ensureVisible(find.text('Laufen').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Laufen').last);
      await tester.pumpAndSettle();
      await capture('session-run');
      await pop();
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
      await capture('run-live');
      await tester.tap(find.byTooltip('Einklappen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Neue Vorlage'));
      await tester.pumpAndSettle();
      await capture('template-editor');
      await pop();
      await tester.pumpAndSettle();

      await press('Journal');
      await capture('journal-hub');
      await tester.tap(find.bySemanticsLabel('Gut'));
      await tester.pumpAndSettle();
      await capture('journal-answered');
      await tester.tap(find.text('Ernährung').first);
      await tester.pumpAndSettle();
      await capture('nutrition-day');
      await tester.tap(find.byTooltip('Frühstück ergänzen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'hafer');
      await tester.pumpAndSettle();
      await capture('food-search');
      await tester.tap(find.text('Haferflocken'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      await capture('meal-draft-preview');
      await tester.tap(find.text('Entwurf behalten'));
      await tester.pumpAndSettle();

      for (final brightness in Brightness.values) {
        for (final phoneActions in [true, false]) {
          var chosen = DeviceAction.none;
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              debugShowCheckedModeBanner: false,
              locale: const Locale('de'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              theme: openBandTheme(brightness),
              home: StatefulBuilder(
                builder: (context, setState) => BandGesturesView(
                  chosen: chosen,
                  supported: {
                    DeviceAction.none,
                    ...DeviceAction.values.where((a) => a.isInApp),
                    if (phoneActions) ...{
                      DeviceAction.ringPhone,
                      DeviceAction.torch,
                    },
                  },
                  onPick: (value) => setState(() => chosen = value),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final state = phoneActions ? 'available' : 'unavailable';
          await capture('gestures-$state-${brightness.name}');
          if (phoneActions) {
            await press('Wasser protokollieren');
            expect(chosen, DeviceAction.logWater);
            await capture('gestures-selected-${brightness.name}');
          }
        }
      }

      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          debugShowCheckedModeBanner: false,
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: openBandTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: BandGesturesView(
            chosen: DeviceAction.none,
            supported: {
              DeviceAction.none,
              ...DeviceAction.values.where((a) => a.isInApp),
              DeviceAction.ringPhone,
              DeviceAction.torch,
            },
            onPick: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture('gestures-large-text');
      await press('Taschenlampe');
      await capture('gestures-large-text-scrolled');

      for (final brightness in [Brightness.light, Brightness.dark]) {
        await mount(brightness: brightness);
        await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
        await tester.pumpAndSettle();
        await press('Nachtverlauf');
        await capture('night-pulse-${brightness.name}');
        await press('HRV');
        expect(find.text('60'), findsOneWidget);
        await capture('night-hrv-${brightness.name}');
        await press('Atmung');
        expect(find.text('14,2'), findsOneWidget);
        await capture('night-respiration-${brightness.name}');
        await tester.tap(
          find.byTooltip('Nachtverlauf: Quelle und Darstellung'),
        );
        await tester.pumpAndSettle();
        await capture('night-info-${brightness.name}');
        await press('Schließen');
      }
      for (final scenario in [
        SyntheticScenario.partial,
        SyntheticScenario.missingNightHrv,
      ]) {
        await mount(scenario: scenario);
        await tester.tap(find.bySemanticsLabel(RegExp(r'^Schlaf, ')));
        await tester.pumpAndSettle();
        await press('Nachtverlauf');
        if (scenario == SyntheticScenario.partial) {
          for (var i = 0; i < 2; i++) {
            await tester.tap(find.byTooltip('Nächster Messpunkt'));
            await tester.pumpAndSettle();
          }
          expect(find.text('02:10'), findsOneWidget);
          expect(find.text('—'), findsOneWidget);
          await capture('night-gap-selected');
        } else {
          await press('HRV');
          expect(find.text('Keine HRV-Werte'), findsOneWidget);
          await capture('night-hrv-missing');
        }
      }
      await mount(scale: 2);
      await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
      await tester.pumpAndSettle();
      await press('Nachtverlauf');
      await press('Atmung');
      await capture('night-large-text');
    } finally {
      WidgetController.hitTestWarningShouldBeFatal = previousHitTestPolicy;
      semantics.dispose();
    }
  });
}
