import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/main_gallery.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';

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
        await tester.tap(find.byTooltip('Schlafzeiten ändern'));
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
      await tester.tap(find.text('15. September').first);
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
      expect(find.text('7h18'), findsOneWidget);

      await mount();
      await tester.tap(find.text('15. September').first);
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
      await tester.tap(find.byTooltip('Schlafzeiten ändern'));
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

      await mount();
      await edit(variant: '-cancel');
      await press('Weiter bearbeiten');
      await tester.tap(find.byTooltip('Zurück').first);
      await tester.pumpAndSettle();
      await capture('draft-leave-confirmation');
      await press('Entwurf behalten');
      await tester.tap(find.byTooltip('Schlafzeiten ändern'));
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
      expect(find.text('7h18'), findsOneWidget);

      await mount(scale: 2);
      await capture('overview-large-text');
      await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
      await tester.pumpAndSettle();
      await capture('sleep-large-text');
      await tester.tap(find.byTooltip('Schlafzeiten ändern'));
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
      await tester.tap(find.text('15. September').first);
      await tester.pumpAndSettle();
      await capture('date-large-text');
      await press('14');
      await press('14. September ansehen');
      expect(find.bySemanticsLabel('Schlaf, 7h02 '), findsOneWidget);
    } finally {
      WidgetController.hitTestWarningShouldBeFatal = previousHitTestPolicy;
      semantics.dispose();
    }
  });
}
