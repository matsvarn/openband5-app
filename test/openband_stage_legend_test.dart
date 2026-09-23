import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/screens.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';

const _order = ['Tief', 'Leicht', 'REM', 'Wach', 'Im Bett'];

const _complete = SleepNight(
  duration: DayMetric(438),
  deepMinutes: 68,
  lightMinutes: 247,
  remMinutes: 123,
  awakeMinutes: 26,
  bedMinutes: 464,
);

Finder legend() => find.byType(OBStageLegend);

Finder legendText(String text) =>
    find.descendant(of: legend(), matching: find.text(text));

int firstRowCount(WidgetTester tester) {
  final ys = [
    for (final label in _order) tester.getTopLeft(legendText(label)).dy,
  ];
  return ys.where((y) => (y - ys.first).abs() < 1).length;
}

List<String> legendOrder(WidgetTester tester) {
  final items =
      [
        for (final label in _order)
          (label: label, offset: tester.getTopLeft(legendText(label))),
      ]..sort((a, b) {
        final row = a.offset.dy.compareTo(b.offset.dy);
        return row != 0 ? row : a.offset.dx.compareTo(b.offset.dx);
      });
  return [for (final item in items) item.label];
}

void expectUnclipped(
  WidgetTester tester,
  String text, {
  required double scale,
}) {
  final paragraph = tester.renderObject<RenderParagraph>(legendText(text));
  expect(paragraph.didExceedMaxLines, isFalse);
  final unconstrained = paragraph.getMaxIntrinsicWidth(double.infinity);
  expect(paragraph.size.width + 0.5, greaterThanOrEqualTo(unconstrained));
  expect(
    paragraph.size.height,
    lessThan(scale * 22),
    reason: '"$text" must stay on one line at ${scale}x',
  );
}

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

  Future<void> mountLegend(
    WidgetTester tester, {
    SleepNight night = _complete,
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 200,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: OB(brightness == Brightness.dark).well,
          body: Align(
            alignment: Alignment.topCenter,
            child: RepaintBoundary(
              key: const ValueKey('legend-capture'),
              child: ColoredBox(
                color: OB(brightness == Brightness.dark).well,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OBCard(
                    child: OBStageLegend(
                      key: const ValueKey('sleep-stage-legend'),
                      night: night,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mountSleep(
    WidgetTester tester, {
    SyntheticScenario scenario = SyntheticScenario.complete,
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = SyntheticOpenBandRepository.fromMaps(
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
    )..scenario = scenario;
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 18, 9, 41),
    );
    addTearDown(controller.dispose);
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
          child: child!,
        ),
        home: AppShell(
          builder: (c, d) => d == ShellDomain.home
              ? OpenBandOverview(controller: controller, onSync: () {})
              : Center(child: Text(d.label)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Schlaf, ')).first);
    await tester.pumpAndSettle();
  }

  test('five equal columns fit measured 1x widths', () {
    expect(
      OBStageLegend.columnsFor(
        width: 333,
        itemWidths: const [48, 55, 52, 60, 44],
      ),
      5,
    );
  });

  test('2x durations drop to two columns instead of shrinking', () {
    expect(
      OBStageLegend.columnsFor(
        width: 315,
        itemWidths: const [90, 110, 100, 140, 88],
      ),
      2,
    );
  });

  test('extreme widths fall back to one column', () {
    expect(
      OBStageLegend.columnsFor(
        width: 320,
        itemWidths: const [200, 210, 180, 220, 190],
      ),
      1,
    );
  });

  testWidgets('complete values stay in Paper order without a bed swatch', (
    tester,
  ) async {
    await mountLegend(tester);
    expect(legendOrder(tester), _order);
    expect(legendText('1h08'), findsOneWidget);
    expect(legendText('4h07'), findsOneWidget);
    expect(legendText('2h03'), findsOneWidget);
    expect(legendText('26 Min.'), findsOneWidget);
    expect(legendText('7h44'), findsOneWidget);
    expect(firstRowCount(tester), 5);
    expect(
      find.byKey(const ValueKey('sleep-stage-swatch-Tief')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sleep-stage-swatch-Leicht')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sleep-stage-swatch-REM')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sleep-stage-swatch-Wach')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sleep-stage-swatch-Im Bett')),
      findsNothing,
    );
    expect(
      find.descendant(of: legend(), matching: find.byType(FittedBox)),
      findsNothing,
    );
    for (final text in [
      'Tief',
      'Leicht',
      'REM',
      'Wach',
      'Im Bett',
      '26 Min.',
      '7h44',
    ]) {
      expectUnclipped(tester, text, scale: 1);
    }
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('legend-capture')),
      matchesGoldenFile('openband_goldens/stage-legend-light.png'),
    );
  }, tags: const ['golden']);

  testWidgets('dark legend keeps the same values', (tester) async {
    await mountLegend(tester, brightness: Brightness.dark);
    expect(legendOrder(tester), _order);
    expect(legendText('4h07'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sleep-stage-swatch-Im Bett')),
      findsNothing,
    );
    await expectLater(
      find.byKey(const ValueKey('legend-capture')),
      matchesGoldenFile('openband_goldens/stage-legend-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('375 2x uses two readable columns', (tester) async {
    await mountLegend(tester, width: 375, height: 420, scale: 2);
    expect(legendOrder(tester), _order);
    expect(firstRowCount(tester), 2);
    expect(legendText('Leicht'), findsOneWidget);
    expect(legendText('26 Min.'), findsOneWidget);
    for (final text in ['Leicht', 'Wach', 'Im Bett', '26 Min.', '7h44']) {
      expectUnclipped(tester, text, scale: 2);
    }
    expect(
      find.descendant(of: legend(), matching: find.byType(FittedBox)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('legend-capture')),
      matchesGoldenFile('openband_goldens/stage-legend-375-2x.png'),
    );
  }, tags: const ['golden']);

  testWidgets('320 2x falls back without clipping', (tester) async {
    await mountLegend(tester, width: 320, height: 640, scale: 2);
    expect(legendOrder(tester), _order);
    expect(firstRowCount(tester), lessThanOrEqualTo(2));
    for (final text in ['Leicht', '26 Min.', 'Im Bett']) {
      expectUnclipped(tester, text, scale: 2);
    }
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('legend-capture')),
      matchesGoldenFile('openband_goldens/stage-legend-320-2x.png'),
    );
  }, tags: const ['golden']);

  testWidgets('missing stage minutes stay dashes', (tester) async {
    await mountLegend(tester, night: const SleepNight(duration: DayMetric(1)));
    expect(legendOrder(tester), _order);
    expect(legendText('—'), findsNWidgets(5));
    expect(legendText('1h08'), findsNothing);
    expect(
      find.byKey(const ValueKey('sleep-stage-swatch-Im Bett')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('legend-capture')),
      matchesGoldenFile('openband_goldens/stage-legend-missing.png'),
    );
  }, tags: const ['golden']);

  testWidgets('all accepted widths and scales keep complete text readable', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final width in [393.0, 375.0, 320.0]) {
        for (final scale in [1.0, 2.0]) {
          await mountLegend(
            tester,
            brightness: brightness,
            width: width,
            height: scale == 1 ? 300 : 640,
            scale: scale,
          );
          expect(legendOrder(tester), _order);
          for (final text in [
            'Tief',
            'Leicht',
            'REM',
            'Wach',
            'Im Bett',
            '1h08',
            '4h07',
            '2h03',
            '26 Min.',
            '7h44',
          ]) {
            expectUnclipped(tester, text, scale: scale);
          }
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('missing values remain readable at accepted widths and scales', (
    tester,
  ) async {
    for (final width in [393.0, 375.0, 320.0]) {
      for (final scale in [1.0, 2.0]) {
        await mountLegend(
          tester,
          night: const SleepNight(duration: DayMetric(1)),
          width: width,
          height: scale == 1 ? 300 : 640,
          scale: scale,
        );
        expect(legendOrder(tester), _order);
        expect(legendText('—'), findsNWidgets(5));
        for (final label in _order) {
          expectUnclipped(tester, label, scale: scale);
        }
        for (final dash in legendText('—').evaluate()) {
          final paragraph = dash.renderObject as RenderParagraph;
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(
            paragraph.size.width + 0.5,
            greaterThanOrEqualTo(
              paragraph.getMaxIntrinsicWidth(double.infinity),
            ),
          );
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('production Sleep uses the shared legend', (tester) async {
    await mountSleep(tester);
    expect(find.byKey(const ValueKey('openband-sleep')), findsOneWidget);
    expect(find.byKey(const ValueKey('sleep-stage-legend')), findsOneWidget);
    expect(find.byType(OBStageLegend), findsOneWidget);
    final sleepCards = find.descendant(
      of: find.byKey(const ValueKey('openband-sleep')),
      matching: find.byType(OBCard),
    );
    final heroDuration = find.descendant(
      of: sleepCards.first,
      matching: find.text('7h18'),
    );
    expect(heroDuration, findsOneWidget);
    expect(legendOrder(tester), _order);
    expect(legendText('1h08'), findsOneWidget);
    expect(legendText('4h07'), findsOneWidget);
    expect(firstRowCount(tester), 5);
    expect(
      find.byKey(const ValueKey('sleep-stage-swatch-Im Bett')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('production Sleep keeps missing-night copy without a legend', (
    tester,
  ) async {
    await mountSleep(tester, scenario: SyntheticScenario.missing);
    expect(find.byKey(const ValueKey('openband-sleep')), findsOneWidget);
    expect(
      find.text('Für diese Nacht liegt noch kein Schlafwert vor.'),
      findsOneWidget,
    );
    expect(find.byType(OBStageLegend), findsNothing);
    expect(find.byKey(const ValueKey('sleep-stage-legend')), findsNothing);
  });

  testWidgets('partial night keeps real stage minutes', (tester) async {
    await mountSleep(tester, scenario: SyntheticScenario.partial);
    expect(find.byType(OBStageLegend), findsOneWidget);
    expect(legendOrder(tester), _order);
    expect(legendText('—'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
