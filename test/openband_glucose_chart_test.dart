import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/glucose_chart.dart';
import 'package:openstrap_edge/openband/theme.dart';

List<({DateTime at, double value})> fixtureReadings() {
  final raw =
      jsonDecode(
            File(
              'docs/openband5/assets/fixtures/glucose-source.json',
            ).readAsStringSync(),
          )
          as Map;
  final values = raw['values'] as List;
  final start = DateTime(2026, 9, 15, 7, 0);
  final step = Duration(minutes: raw['step_minutes'] as int);
  return [
    for (var i = 0; i < values.length; i++)
      if (values[i] != null)
        (at: start.add(step * i), value: (values[i] as num).toDouble()),
  ];
}

List<String> visibleStrings(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

List<double> axisNumbers(WidgetTester tester) {
  final out = <double>[];
  for (final s in visibleStrings(tester)) {
    if (s.contains(':')) continue;
    final parsed = double.tryParse(s.replaceAll(',', '.'));
    if (parsed != null) out.add(parsed);
  }
  return out;
}

Rect glyphBox(WidgetTester tester, String text) {
  final box = tester.getRect(find.text(text));
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
  final w = paragraph.getMaxIntrinsicWidth(double.infinity);
  return switch (tester.widget<Text>(find.text(text)).textAlign) {
    TextAlign.right => Rect.fromLTWH(box.right - w, box.top, w, box.height),
    TextAlign.center => Rect.fromLTWH(
      box.center.dx - w / 2,
      box.top,
      w,
      box.height,
    ),
    _ => Rect.fromLTWH(box.left, box.top, w, box.height),
  };
}

void expectInsideCard(WidgetTester tester) {
  expect(find.byType(FittedBox), findsNothing);
  expect(tester.takeException(), isNull);
  final card = tester.getRect(find.byType(OBCard));
  for (final text in find.byType(Text).evaluate()) {
    final box = tester.getRect(find.byWidget(text.widget));
    expect(box.left, greaterThanOrEqualTo(card.left - 1));
    expect(box.right, lessThanOrEqualTo(card.right + 1));
  }
}

void expectUnitAtContentEdge(WidgetTester tester, Finder unit) {
  final card = tester.getRect(find.byType(OBCard));
  final glyphs = glyphBox(tester, tester.widget<Text>(unit).data!);
  expect(glyphs.right, closeTo(card.right - 16, 2));
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
  });

  Future<void> mount(
    WidgetTester tester, {
    required List<({DateTime at, double value})> readings,
    String unit = 'mmol/L',
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 400,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final p = OB(brightness == Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: Size(width, height),
            textScaler: TextScaler.linear(scale),
            padding: EdgeInsets.zero,
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: RepaintBoundary(
              key: const ValueKey('capture'),
              child: Material(
                color: p.canvas,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OBGlucoseChart(readings: readings, unit: unit),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('fixture light golden', (tester) async {
    await mount(tester, readings: fixtureReadings());
    expect(find.text('Verlauf'), findsOneWidget);
    expect(find.text('mmol/L'), findsOneWidget);
    expect(find.text('4,5'), findsOneWidget);
    expect(find.text('6,5'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('07:30'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(
      glyphBox(tester, '07:00').right,
      lessThan(glyphBox(tester, '07:30').left),
    );
    expect(
      glyphBox(tester, '07:30').right,
      lessThan(glyphBox(tester, '08:00').left),
    );
    expect(find.byType(CustomPaint), findsOneWidget);
    expectUnitAtContentEdge(tester, find.text('mmol/L'));
    expectInsideCard(tester);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-chart.png'),
    );
  }, tags: const ['golden']);

  testWidgets('fixture dark golden', (tester) async {
    await mount(
      tester,
      readings: fixtureReadings(),
      brightness: Brightness.dark,
    );
    expect(find.text('4,5'), findsOneWidget);
    expect(find.text('6,5'), findsOneWidget);
    expectUnitAtContentEdge(tester, find.text('mmol/L'));
    expectInsideCard(tester);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-chart-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('fixture 375 2x golden does not overflow', (tester) async {
    await mount(
      tester,
      readings: fixtureReadings(),
      width: 375,
      height: 812,
      scale: 2,
    );
    expect(find.text('4,5'), findsOneWidget);
    expect(find.text('6,5'), findsOneWidget);
    expectUnitAtContentEdge(tester, find.text('mmol/L'));
    expectInsideCard(tester);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-chart-375-2x.png'),
    );
  }, tags: const ['golden']);

  testWidgets('empty omits fabricated axes and shows an honest dash', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await mount(tester, readings: const []);
    expect(find.text('Verlauf'), findsOneWidget);
    expect(find.text('mmol/L'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.byType(CustomPaint), findsNothing);
    expect(find.text('4,5'), findsNothing);
    expect(find.text('6,5'), findsNothing);
    expect(find.text('07:00'), findsNothing);
    expect(
      find.bySemanticsLabel('Verlauf, keine Messpunkte, mmol/L'),
      findsOneWidget,
    );
    expectUnitAtContentEdge(tester, find.text('mmol/L'));
    expectInsideCard(tester);
    semantics.dispose();
  });

  testWidgets(
    'single point uses the actual timestamp and does not invent a range',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(
        tester,
        readings: [(at: DateTime(2026, 9, 15, 7, 0), value: 5.2)],
      );
      expect(find.text('07:00'), findsOneWidget);
      expect(find.text('07:30'), findsNothing);
      expect(find.text('08:00'), findsNothing);
      expect(
        find.bySemanticsLabel('Verlauf, 1 Messpunkt, 07:00, mmol/L'),
        findsOneWidget,
      );
      expectInsideCard(tester);
      semantics.dispose();
    },
  );

  testWidgets('flat series keeps finite distinct bounds', (tester) async {
    await mount(
      tester,
      readings: [
        (at: DateTime(2026, 9, 15, 7, 0), value: 5.2),
        (at: DateTime(2026, 9, 15, 8, 0), value: 5.2),
      ],
    );
    final bounds = axisNumbers(tester);
    expect(bounds, hasLength(2));
    expect(bounds.toSet(), hasLength(2));
    expect(bounds.every((v) => v.isFinite), isTrue);
    expect(bounds.reduce(mathMin), lessThanOrEqualTo(5.2));
    expect(bounds.reduce(mathMax), greaterThanOrEqualTo(5.2));
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expectInsideCard(tester);
  });

  testWidgets('mg/dL uses a numeric viewport and never converts the raw unit', (
    tester,
  ) async {
    await mount(
      tester,
      readings: [
        (at: DateTime(2026, 9, 15, 7, 0), value: 90),
        (at: DateTime(2026, 9, 15, 8, 0), value: 140),
      ],
      unit: 'mg/dL',
    );
    expect(find.text('mg/dL'), findsOneWidget);
    expect(find.text('mmol/L'), findsNothing);
    expect(find.text('4,5'), findsNothing);
    expect(find.text('6,5'), findsNothing);
    final bounds = axisNumbers(tester);
    expect(bounds, hasLength(2));
    expect(bounds.reduce(mathMin), lessThanOrEqualTo(90));
    expect(bounds.reduce(mathMax), greaterThanOrEqualTo(140));
    expectInsideCard(tester);
  });

  testWidgets('time axis uses absolute timestamps across midnight', (
    tester,
  ) async {
    await mount(
      tester,
      readings: [
        (at: DateTime(2026, 9, 15, 23, 0), value: 5.0),
        (at: DateTime(2026, 9, 16, 0, 0), value: 5.2),
        (at: DateTime(2026, 9, 16, 1, 0), value: 5.4),
      ],
    );
    expect(find.text('23:00'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('01:00'), findsOneWidget);
    expectInsideCard(tester);
  });

  testWidgets(
    'time labels use absolute elapsed time across a DST spring-forward',
    (tester) async {
      final start = DateTime(2026, 3, 29, 1, 0);
      final end = DateTime(2026, 3, 29, 4, 0);
      final mid = start.add(end.difference(start) ~/ 2);
      await mount(
        tester,
        readings: [
          (at: start, value: 5.0),
          (at: DateTime(2026, 3, 29, 3, 0), value: 5.2),
          (at: end, value: 5.4),
        ],
      );
      expect(find.text(obTime(start)), findsOneWidget);
      expect(find.text(obTime(mid)), findsOneWidget);
      expect(find.text(obTime(end)), findsOneWidget);
      expectInsideCard(tester);
    },
  );

  testWidgets('fixture semantics count stored points, not padded samples', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await mount(tester, readings: fixtureReadings());
    expect(fixtureReadings(), hasLength(11));
    expect(
      find.bySemanticsLabel('Verlauf, 11 Messpunkte, 07:00 bis 08:00, mmol/L'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('long unit and large text wrap without overflow', (tester) async {
    await mount(
      tester,
      readings: fixtureReadings(),
      unit: 'millimol pro Liter (mmol/L)',
      width: 375,
      height: 812,
      scale: 2,
    );
    expect(find.textContaining('millimol pro Liter'), findsOneWidget);
    expect(
      tester.getSize(find.textContaining('millimol pro Liter')).height,
      greaterThan(36),
    );
    expectUnitAtContentEdge(tester, find.text('millimol pro Liter (mmol/L)'));
    expectInsideCard(tester);
  });

  testWidgets(
    'extreme finite values omit the plot instead of overflowing the viewport',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(
        tester,
        readings: [
          (at: DateTime(2026, 9, 15, 7, 0), value: 1e308),
          (at: DateTime(2026, 9, 15, 8, 0), value: -1e308),
        ],
      );
      expect(find.text('Verlauf'), findsOneWidget);
      expect(find.text('mmol/L'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.byType(CustomPaint), findsNothing);
      expect(find.text('07:00'), findsNothing);
      expect(find.text('08:00'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Verlauf, 2 Messpunkte, 07:00 bis 08:00, mmol/L, Darstellung nicht möglich',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('finite axis labels that leave no chart lane omit the plot', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await mount(
      tester,
      readings: [
        (at: DateTime(2026, 9, 15, 7, 0), value: 1e45),
        (at: DateTime(2026, 9, 15, 8, 0), value: 1.1e45),
      ],
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.byType(CustomPaint), findsNothing);
    expect(
      find.bySemanticsLabel(
        'Verlauf, 2 Messpunkte, 07:00 bis 08:00, mmol/L, Darstellung nicht möglich',
      ),
      findsOneWidget,
    );
    expectInsideCard(tester);
    semantics.dispose();
  });

  testWidgets('tiny distinct values keep a finite numeric viewport', (
    tester,
  ) async {
    await mount(
      tester,
      readings: [
        (at: DateTime(2026, 9, 15, 7, 0), value: 1e-15),
        (at: DateTime(2026, 9, 15, 8, 0), value: 2e-15),
      ],
    );
    expect(find.text('—'), findsNothing);
    expect(find.byType(CustomPaint), findsOneWidget);
    final bounds = axisNumbers(tester);
    expect(bounds, hasLength(2));
    expect(bounds.toSet(), hasLength(2));
    expect(bounds.every((v) => v.isFinite), isTrue);
    expect(bounds.reduce(mathMin), lessThanOrEqualTo(1e-15));
    expect(bounds.reduce(mathMax), greaterThanOrEqualTo(2e-15));
    expect(bounds.every((v) => v.abs() < 1e-10), isTrue);
    expect(tester.takeException(), isNull);
  });
}

double mathMin(double a, double b) => a < b ? a : b;
double mathMax(double a, double b) => a > b ? a : b;
