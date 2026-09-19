import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/gestures/device_action.dart';
import 'package:openstrap_edge/l10n/app_localizations.dart';
import 'package:openstrap_edge/main_gallery.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/openband/notification_settings.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/ui2/profile/alarm.dart';
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
      Finder verticalScrollable() => find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );

      Future<void> press(String text) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final target = find.text(text);
        if (target.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            target,
            200,
            scrollable: verticalScrollable().last,
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
          scrollable: verticalScrollable().last,
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

      Future<SyntheticOpenBandRepository> openSleepGoal({
        SyntheticScenario scenario = SyntheticScenario.complete,
        Brightness brightness = Brightness.light,
        double? scale,
        int? targetMinutes,
        bool estimate = true,
      }) async {
        final repository = await mount(
          scenario: scenario,
          brightness: brightness,
          scale: scale,
        );
        if (!estimate) repository.weekendEstimate = null;
        if (targetMinutes != null) {
          await repository.saveSleepGoal('2026-09-15', targetMinutes);
        }
        await tester.tap(find.bySemanticsLabel('Schlaf, 7h18 '));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Schlafziel'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Schlafziel'));
        await tester.pumpAndSettle();
        return repository;
      }

      await openSleepGoal();
      expect(find.text('Ziel festlegen'), findsOneWidget);
      expect(find.text('7 h 45'), findsNothing);
      await capture('sleep-goal-unset');
      await press('Ziel festlegen');
      await capture('sleep-goal-editor');
      await tester.enterText(
        find.byKey(const ValueKey('sleep-goal-hours')),
        '7',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sleep-goal-minutes')),
        '45',
      );
      await tester.pumpAndSettle();
      await press('Speichern');
      expect(find.text('7 h 45'), findsOneWidget);
      expect(find.text('8 h 12 · Stand 15. September'), findsOneWidget);
      await capture('sleep-goal-estimate');
      await tester.tap(find.bySemanticsLabel('Wochenend-Schätzung'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '75. Perzentil der Wochenendnächte. Keine Messung des Schlafbedarfs.',
        ),
        findsOneWidget,
      );
      await capture('sleep-goal-estimate-info');
      await press('Schließen');
      await openSleepGoal(targetMinutes: 465);
      await press('Ändern');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sleep-goal-hours')))
            .controller
            ?.text,
        '7',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sleep-goal-minutes')))
            .controller
            ?.text,
        '45',
      );
      await capture('sleep-goal-editor-target');
      await openSleepGoal(
        brightness: Brightness.dark,
        targetMinutes: 465,
        estimate: false,
      );
      expect(find.text('7 h 45'), findsOneWidget);
      expect(find.text('Ändern'), findsOneWidget);
      expect(find.text('8 h 12 · Stand 15. September'), findsNothing);
      await capture('sleep-goal-dark');
      await press('Ändern');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sleep-goal-hours')))
            .controller
            ?.text,
        '7',
      );
      await capture('sleep-goal-editor-dark');
      await openSleepGoal(scale: 2, targetMinutes: 465);
      expect(find.text('7 h 45'), findsOneWidget);
      expect(find.text('8 h 12 · Stand 15. September'), findsOneWidget);
      await capture('sleep-goal-2x');
      await press('Ändern');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sleep-goal-hours')))
            .controller
            ?.text,
        '7',
      );
      await capture('sleep-goal-editor-2x');
      final failingGoal = await openSleepGoal();
      failingGoal.failSleepGoalWrite = true;
      await press('Ziel festlegen');
      await tester.enterText(
        find.byKey(const ValueKey('sleep-goal-hours')),
        '7',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sleep-goal-minutes')),
        '45',
      );
      await tester.pumpAndSettle();
      await press('Speichern');
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      await capture('sleep-goal-error');

      // ── Hub- und Flow-Captures der neuen Oberflächen ──
      await mount();
      await press('Gesundheit');
      await capture('health-hub');
      await press('30 Nächte');
      await capture('health-30');

      await press('Laborwerte');
      await capture('labs-list');
      await press('Ferritin');
      await capture('labs-detail');
      await tester.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
      await tester.pumpAndSettle();
      await capture('labs-editor');
      await tester.enterText(find.byKey(const ValueKey('lab-value')), '53');
      await tester.pumpAndSettle();
      await capture('labs-editor-keyboard');
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      await press('Verwerfen');
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      await press('Wert hinzufügen');
      await capture('labs-chooser');
      await press('Ferritin');
      await capture('labs-add');
      await tester.enterText(find.byKey(const ValueKey('lab-value')), '40');
      await tester.pumpAndSettle();
      await press('Speichern');
      await capture('labs-add-success');
      await press('Ferritin');
      await tester.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
      await tester.pumpAndSettle();
      await press('Wert entfernen');
      await capture('labs-delete-confirm');
      await tester.tap(find.text('Wert entfernen').last);
      await tester.pumpAndSettle();
      await capture('labs-delete-success');
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();

      final failingDelete = await mount();
      failingDelete.failLabWrites = true;
      await press('Gesundheit');
      await press('Laborwerte');
      await press('Ferritin');
      await tester.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
      await tester.pumpAndSettle();
      await press('Wert entfernen');
      await tester.tap(find.text('Wert entfernen').last);
      await tester.pumpAndSettle();
      expect(find.text('Nicht entfernt.'), findsOneWidget);
      await capture('labs-delete-failure');

      await mount(brightness: Brightness.dark);
      await press('Gesundheit');
      await press('Laborwerte');
      await capture('labs-list-dark');
      await press('Ferritin');
      await capture('labs-detail-dark');
      await tester.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
      await tester.pumpAndSettle();
      await capture('labs-editor-dark');
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();

      final emptyLabs = await mount();
      await emptyLabs.deleteLabDraw('ferritin', '2026-09-15');
      await emptyLabs.deleteLabDraw('ferritin', '2026-06-12');
      await emptyLabs.deleteLabDraw('ferritin', '2026-03-04');
      await emptyLabs.deleteLabDraw('vitamin_b12', '2026-09-15');
      await emptyLabs.deleteLabDraw('vitamin_d', '2026-09-15');
      await press('Gesundheit');
      await press('Laborwerte');
      await capture('labs-empty');

      final failingLabs = await mount();
      failingLabs.failLabWrites = true;
      await press('Gesundheit');
      await press('Laborwerte');
      await press('Ferritin');
      await tester.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('lab-value')), '53');
      await tester.pumpAndSettle();
      await press('Speichern');
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      await capture('labs-save-failure');

      await mount();
      await press('Gesundheit');
      await press('Laborwerte');
      await press('Vitamin D (25-OH)');
      expect(find.text('Befundbereich unbekannt'), findsNothing);
      expect(find.text('Befundbereich'), findsWidgets);
      expect(find.text('—'), findsWidgets);
      await capture('labs-bounds-missing');
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      await press('Eigene Marker');
      await press('Marker anlegen');
      await tester.enterText(
        find.byKey(const ValueKey('lab-def-name')),
        'Kupfer',
      );
      await tester.enterText(
        find.byKey(const ValueKey('lab-def-unit')),
        'µg/dL',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await capture('labs-custom-marker');

      await mount(brightness: Brightness.dark);
      await press('Gesundheit');
      await press('Laborwerte');
      await press('Eigene Marker');
      await press('Marker anlegen');
      await tester.enterText(
        find.byKey(const ValueKey('lab-def-name')),
        'Kupfer',
      );
      await tester.enterText(
        find.byKey(const ValueKey('lab-def-unit')),
        'µg/dL',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await capture('labs-custom-dark');

      await mount(scale: 2);
      await press('Gesundheit');
      await capture('health-large-text');
      await press('Laborwerte');
      await capture('labs-list-large');
      await press('Ferritin');
      await capture('labs-detail-large');
      await press('Wert hinzufügen');
      await capture('labs-editor-large');

      await mount();
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

      Future<void> mountAlarm({
        DateTime? at,
        AlarmArmState state = AlarmArmState.none,
        bool connected = true,
        bool scheduleEnabled = true,
        bool failing = false,
        Brightness brightness = Brightness.light,
        double scale = 1,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: openBandTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: AlarmGallerySession(
              armedAt: at,
              now: galleryAlarmNow,
              state: state,
              connected: connected,
              scheduleEnabled: scheduleEnabled,
              failing: failing,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Finder wednesdayTime() => find.descendant(
        of: find.byKey(const ValueKey('alarm-day-2')),
        matching: find.text('07:00'),
      );

      await mountAlarm(at: galleryAlarmAt, state: AlarmArmState.storedSeconds);
      await capture('alarm-ready');
      await tester.tap(find.byType(CupertinoSwitch).at(2));
      await tester.pumpAndSettle();
      expect(wednesdayTime(), findsNothing);
      await tester.tap(find.byType(CupertinoSwitch).at(2));
      await tester.pumpAndSettle();
      expect(wednesdayTime(), findsOneWidget);
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.storedSeconds,
        brightness: Brightness.dark,
      );
      await capture('alarm-ready-dark');
      await mountAlarm(at: galleryAlarmAt, state: AlarmArmState.unknown);
      await capture('alarm-light');
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.unknown,
        brightness: Brightness.dark,
      );
      await capture('alarm-dark');
      await mountAlarm(at: galleryAlarmAt, state: AlarmArmState.pending);
      await capture('alarm-pending');
      await mountAlarm(scheduleEnabled: false);
      await capture('alarm-none');
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.allSlotsInactive,
        scheduleEnabled: false,
      );
      await capture('alarm-slots-inactive');
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.allSlotsInactive,
        scheduleEnabled: false,
        brightness: Brightness.dark,
      );
      await capture('alarm-slots-inactive-dark');
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.unknown,
        connected: false,
      );
      await capture('alarm-offline');
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.pending,
        failing: true,
      );
      await tester.tap(find.text('Ausschalten'));
      await tester.pumpAndSettle();
      await capture('alarm-error');
      await mountAlarm(at: galleryAlarmAt, state: AlarmArmState.unknown);
      await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
      await tester.pumpAndSettle();
      await capture('alarm-timepicker');
      await tester.tap(find.text('Abbrechen').first);
      await tester.pumpAndSettle();
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.unknown,
        brightness: Brightness.dark,
      );
      await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
      await tester.pumpAndSettle();
      await capture('alarm-timepicker-dark');
      await tester.tap(find.text('Abbrechen').first);
      await tester.pumpAndSettle();
      await mountAlarm(at: galleryAlarmAt, state: AlarmArmState.storedSeconds);
      await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '88');
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await capture('alarm-timepicker-input');
      await tester.tap(find.text('Abbrechen').first);
      await tester.pumpAndSettle();
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.storedSeconds,
        scale: 2,
      );
      await capture('alarm-large-text');
      await tester.tap(find.bySemanticsLabel(RegExp(r'Uhrzeit Mittwoch')));
      await tester.pumpAndSettle();
      await capture('alarm-timepicker-large');
      await tester.tap(find.text('Abbrechen').first);
      await tester.pumpAndSettle();
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.offPending,
        scheduleEnabled: false,
      );
      await capture('alarm-off-pending');
      await tester.tap(find.text('Erneut ausschalten'));
      await tester.pumpAndSettle();
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.offPending,
        scheduleEnabled: false,
        brightness: Brightness.dark,
      );
      await capture('alarm-off-pending-dark');
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.offPending,
        scheduleEnabled: false,
        connected: false,
      );
      await capture('alarm-off-offline');
      await mountAlarm(
        at: galleryAlarmAt,
        state: AlarmArmState.offPending,
        scheduleEnabled: false,
        failing: true,
      );
      await tester.tap(find.text('Erneut ausschalten'));
      await tester.pumpAndSettle();
      await capture('alarm-off-retry-error');
      Future<void> openNaps() async {
        await tester.tap(find.bySemanticsLabel(RegExp(r'^Schlaf, ')).first);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Nickerchen'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Nickerchen'));
        await tester.pumpAndSettle();
      }

      await mount();
      await openNaps();
      expect(find.text('14:10–14:42'), findsOneWidget);
      expect(find.text('Erkannt'), findsOneWidget);
      await capture('naps-list');
      await press('Nickerchen ergänzen');
      expect(find.text('Selbst eingetragen'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('nap-start')), '16:00');
      await tester.enterText(find.byKey(const ValueKey('nap-end')), '16:40');
      await tester.pumpAndSettle();
      expect(find.text('40 Minuten'), findsOneWidget);
      await capture('naps-add');
      await press('Speichern');
      expect(find.text('16:00–16:40'), findsOneWidget);
      expect(find.text('Manuell'), findsOneWidget);
      await tester.tap(find.text('14:10–14:42'));
      await tester.pumpAndSettle();
      await capture('naps-edit');
      await press('Nickerchen entfernen');
      expect(find.text('14:10–14:42 entfernen?'), findsOneWidget);
      await tester.tap(find.text('Entfernen').last);
      await tester.pumpAndSettle();
      expect(find.text('Wiederherstellen'), findsOneWidget);
      await capture('naps-removed');
      await press('Wiederherstellen');
      expect(find.text('Erkannt'), findsOneWidget);

      final napFail = await mount(
        scenario: SyntheticScenario.calculationFailure,
      );
      await openNaps();
      await press('Nickerchen ergänzen');
      await tester.enterText(find.byKey(const ValueKey('nap-start')), '16:00');
      await tester.enterText(find.byKey(const ValueKey('nap-end')), '16:40');
      await press('Speichern');
      expect(find.text('Gespeichert · Auswertung offen'), findsOneWidget);
      expect(find.text('Erneut auswerten'), findsOneWidget);
      expect(find.text('16:00–16:40'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      expect(find.text('72'), findsNothing);
      await capture('naps-recalc-failure');
      napFail.scenario = SyntheticScenario.complete;
      await press('Erneut auswerten');
      expect(find.text('16:00–16:40'), findsOneWidget);
      await capture('naps-recalc-retry');

      final empty = await mount();
      empty.seedNaps(
        const NapDay(day: '2026-09-15', judged: true, totalMin: 0),
      );
      await openNaps();
      expect(find.text('Keine Nickerchen erkannt'), findsOneWidget);
      await capture('naps-empty');

      final unknown = await mount();
      unknown.seedNaps(const NapDay(day: '2026-09-15'));
      await openNaps();
      expect(find.text('Noch nicht bestimmbar'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      await capture('naps-unknown');

      await mount(brightness: Brightness.dark);
      await openNaps();
      await capture('naps-dark');
      await press('Nickerchen ergänzen');
      await capture('naps-add-dark');

      await mount(scale: 2);
      await openNaps();
      expect(tester.takeException(), isNull);
      await capture('naps-large-text');
      await press('Nickerchen ergänzen');
      expect(tester.takeException(), isNull);
      await capture('naps-add-large-text');
      Future<void> revealNotification(Finder target) async {
        final scrollable = find.byType(Scrollable).last;
        if (target.evaluate().isEmpty) {
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pumpAndSettle();
        }
        await tester.scrollUntilVisible(target, 200, scrollable: scrollable);
        await tester.pumpAndSettle();
      }

      Future<void> mountNotifications({
        required Brightness brightness,
        bool loaded = true,
        bool? granted = true,
        String? saveError,
        String? applyError,
        String? permissionError,
        NotificationPrefs prefs = openBandPaperNotificationPrefs,
        double? scale,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: openBandTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale ?? 1)),
              child: child!,
            ),
            home: NotificationSettingsView(
              synthetic: true,
              loaded: loaded,
              granted: granted,
              prefs: prefs,
              saveError: saveError,
              applyError: applyError,
              permissionError: permissionError,
              onChanged: (_) async {},
              onRequestPermission: () {},
              onRetrySave: saveError == null ? null : () {},
              onRetryApply: applyError == null ? null : () {},
              onRetryPermission: permissionError == null ? null : () {},
            ),
          ),
        );
        if (loaded) {
          await tester.pumpAndSettle();
        } else {
          await tester.pump(const Duration(milliseconds: 350));
        }
      }

      for (final brightness in Brightness.values) {
        await mountNotifications(brightness: brightness);
        await capture('notifications-${brightness.name}');
      }
      await mountNotifications(
        brightness: Brightness.light,
        loaded: false,
        granted: null,
      );
      await capture('notifications-loading');
      await mountNotifications(brightness: Brightness.light, granted: false);
      await capture('notifications-denied');
      await mountNotifications(
        brightness: Brightness.light,
        saveError: 'Speichern fehlgeschlagen',
      );
      await capture('notifications-error');
      await mountNotifications(
        brightness: Brightness.light,
        applyError: 'Gespeichert. Anwenden fehlgeschlagen',
      );
      await capture('notifications-apply-error');
      await mountNotifications(
        brightness: Brightness.dark,
        applyError: 'Gespeichert. Anwenden fehlgeschlagen',
      );
      await capture('notifications-apply-error-dark');
      await mountNotifications(
        brightness: Brightness.light,
        permissionError: 'internal',
      );
      await capture('notifications-permission-unknown');
      await mountNotifications(brightness: Brightness.light);
      await revealNotification(find.byKey(const ValueKey('quiet-start')));
      await tester.tap(find.byKey(const ValueKey('quiet-start')));
      await tester.pumpAndSettle();
      await capture('notifications-quiet-time');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountNotifications(brightness: Brightness.dark);
      await revealNotification(find.byKey(const ValueKey('quiet-start')));
      await tester.tap(find.byKey(const ValueKey('quiet-start')));
      await tester.pumpAndSettle();
      await capture('notifications-quiet-time-dark');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountNotifications(brightness: Brightness.light);
      await revealNotification(find.byKey(const ValueKey('quiet-start')));
      await tester.tap(find.byKey(const ValueKey('quiet-start')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '88');
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await capture('notifications-quiet-time-input');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountNotifications(brightness: Brightness.light, scale: 2);
      await revealNotification(find.byKey(const ValueKey('quiet-start')));
      await tester.tap(find.byKey(const ValueKey('quiet-start')));
      await tester.pumpAndSettle();
      await capture('notifications-quiet-time-large');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountNotifications(brightness: Brightness.light);
      await revealNotification(find.byKey(const ValueKey('notif-battery')));
      await tester.tap(find.byKey(const ValueKey('notif-battery')));
      await tester.pumpAndSettle();
      await capture('notifications-choice');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountNotifications(brightness: Brightness.dark);
      await revealNotification(find.byKey(const ValueKey('notif-battery')));
      await tester.tap(find.byKey(const ValueKey('notif-battery')));
      await tester.pumpAndSettle();
      await capture('notifications-choice-dark');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountNotifications(brightness: Brightness.light, scale: 2);
      await revealNotification(find.byKey(const ValueKey('notif-battery')));
      await tester.tap(find.byKey(const ValueKey('notif-battery')));
      await tester.pumpAndSettle();
      await capture('notifications-choice-large');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      var live = openBandPaperNotificationPrefs;
      final applied = <NotificationPrefs>[];
      var reminders = 0;
      var failSave = false;

      Future<void> mountLive({
        Brightness brightness = Brightness.light,
        double scale = 1,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: openBandTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                alwaysUse24HourFormat: true,
              ),
              child: child!,
            ),
            home: NotificationSettings(
              synthetic: true,
              loadPrefs: () async => live,
              persistPrefs: (prefs) async {
                if (failSave) throw Exception('disk full');
                live = prefs;
              },
              readPermission: () async => true,
              onRefreshReminders: () async => reminders++,
              onArmWater: (prefs) async => applied.add(prefs),
              onRefreshBattery: (prefs) async => applied.add(prefs),
              relaySupported: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      CupertinoSwitch notifSwitch(Key key) {
        return tester.widget<CupertinoSwitch>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(CupertinoSwitch),
          ),
        );
      }

      Future<void> tapLiveSwitch(Key key) async {
        final sw = find.descendant(
          of: find.byKey(key),
          matching: find.byType(CupertinoSwitch),
        );
        await revealNotification(sw);
        await tester.pumpAndSettle();
        await tester.tap(sw);
        await tester.pumpAndSettle();
      }

      await mountLive();
      expect(notifSwitch(const ValueKey('notif-health')).value, isTrue);
      final remindersBeforeToggle = reminders;
      await tapLiveSwitch(const ValueKey('notif-health'));
      expect(live.healthEnabled, isFalse);
      expect(notifSwitch(const ValueKey('notif-health')).value, isFalse);
      expect(reminders, greaterThan(remindersBeforeToggle));
      expect(applied, isNotEmpty);
      expect(applied.last.healthEnabled, isFalse);

      await revealNotification(find.byKey(const ValueKey('notif-battery')));
      await tester.tap(find.byKey(const ValueKey('notif-battery')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notification-choice')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notification-choice-25')));
      await tester.pumpAndSettle();
      expect(live.batteryAlertPct, 25);
      expect(find.text('25 %'), findsOneWidget);
      expect(applied.last.batteryAlertPct, 25);

      await tester.tap(find.byKey(const ValueKey('notif-battery')));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('notification-choice-25')))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('notification-choice-20')))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isNot(true),
      );
      await tester.tapAt(const Offset(20, 150));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notification-choice')), findsNothing);
      expect(live.batteryAlertPct, 25);

      await revealNotification(
        find.byKey(const ValueKey('notif-water-interval')),
      );
      await tester.tap(find.byKey(const ValueKey('notif-water-interval')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notification-choice-180')));
      await tester.pumpAndSettle();
      expect(live.waterIntervalMin, 180);
      expect(find.text('3h'), findsOneWidget);
      expect(applied.last.waterIntervalMin, 180);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('quiet-start')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('quiet-start')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_outlined), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, '21');
      await tester.enterText(find.byType(TextFormField).last, '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(live.quietStartMin, 21 * 60 + 30);
      expect(find.text('21:30'), findsOneWidget);
      expect(applied.last.quietStartMin, 21 * 60 + 30);

      await capture('notifications-live');

      failSave = true;
      final remindersBeforeFail = reminders;
      await tapLiveSwitch(const ValueKey('notif-health'));
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      expect(notifSwitch(const ValueKey('notif-health')).value, isFalse);
      expect(live.healthEnabled, isFalse);
      expect(live.batteryAlertPct, 25);
      expect(reminders, remindersBeforeFail);
      await capture('notifications-live-save-failure');
      failSave = false;
      await tester.tap(find.text('Erneut'));
      await tester.pumpAndSettle();
      expect(find.text('Speichern fehlgeschlagen'), findsNothing);
      expect(live.healthEnabled, isTrue);
      expect(notifSwitch(const ValueKey('notif-health')).value, isTrue);
      expect(applied.last.healthEnabled, isTrue);
      expect(reminders, greaterThan(remindersBeforeFail));
      await capture('notifications-live-save-retry');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountLive(scale: 2);
      expect(find.text('25 %'), findsOneWidget);
      await capture('notifications-live-large');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('quiet-start')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('21:30'), findsOneWidget);
      await capture('notifications-live-large-quiet');
    } finally {
      WidgetController.hitTestWarningShouldBeFatal = previousHitTestPolicy;
      semantics.dispose();
    }
  });
}
