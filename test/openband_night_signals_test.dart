import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/night_signals.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    for (final font in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
      (
        'packages/lucide_icons_flutter/Lucide',
        'packages/lucide_icons_flutter/assets/lucide.ttf',
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  SyntheticOpenBandRepository repo(SyntheticScenario scenario) =>
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
        scenario: scenario,
      );
  Future<void> mount(
    WidgetTester tester, {
    SyntheticScenario scenario = SyntheticScenario.complete,
    NightSignalKind kind = NightSignalKind.pulse,
    Brightness brightness = Brightness.light,
    double width = 393,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 852);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: openBandTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
          ),
          child: child!,
        ),
        home: OpenBandNightSignals(
          repository: repo(scenario),
          day: '2026-09-15',
          initial: kind,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final variant in [
    (
      'pulse',
      NightSignalKind.pulse,
      SyntheticScenario.complete,
      Brightness.light,
    ),
    ('hrv', NightSignalKind.hrv, SyntheticScenario.complete, Brightness.light),
    (
      'respiration',
      NightSignalKind.respiration,
      SyntheticScenario.complete,
      Brightness.light,
    ),
    (
      'sparse',
      NightSignalKind.pulse,
      SyntheticScenario.partial,
      Brightness.light,
    ),
    (
      'missing',
      NightSignalKind.hrv,
      SyntheticScenario.missingNightHrv,
      Brightness.light,
    ),
    (
      'dark',
      NightSignalKind.pulse,
      SyntheticScenario.complete,
      Brightness.dark,
    ),
  ]) {
    testWidgets('night ${variant.$1}', (tester) async {
      await mount(
        tester,
        kind: variant.$2,
        scenario: variant.$3,
        brightness: variant.$4,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('openband_goldens/night-${variant.$1}.png'),
      );
    }, tags: const ['golden']);
  }
  testWidgets(
    'selection visits the actual stored refusal and recovers with the next reading',
    (tester) async {
      await mount(tester, scenario: SyntheticScenario.partial);
      final semantics = tester.ensureSemantics();

      expect(find.text('00:10'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Nächster Messpunkt'));
        await tester.pumpAndSettle();
      }
      expect(find.text('02:10'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Puls, — bpm, 02:10, Keine Daten')),
        findsOneWidget,
      );
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('openband_goldens/night-gap-selected.png'),
      );
      await tester.tap(find.byTooltip('Nächster Messpunkt'));
      await tester.pumpAndSettle();
      expect(find.text('51'), findsOneWidget);
      await tester.tap(find.text('HRV'));
      await tester.pumpAndSettle();
      expect(find.text('60'), findsOneWidget);
      expect(find.text('23:40'), findsOneWidget);
      semantics.dispose();
    },
    tags: const ['golden'],
  );
  testWidgets(
    'compact screen at double text scale keeps metric controls usable',
    (tester) async {
      await mount(tester, width: 375, scale: 2);
      await tester.tap(find.text('Atmung'));
      await tester.pumpAndSettle();
      expect(find.text('14,2'), findsOneWidget);
      await tester.tap(find.byTooltip('Nächster Messpunkt'));
      await tester.pumpAndSettle();
      expect(find.text('00:13'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
