import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/g3/charts.dart';
import 'package:openstrap_edge/openband/g3/chrome.dart';
import 'package:openstrap_edge/openband/g3/screens/heute.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

Widget _app(Widget child, double scale, bool bold, {bool dark = false}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: openBandTheme(dark ? Brightness.dark : Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale), boldText: bold),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

void _visibleSegments(WidgetTester tester, Finder control, double width) {
  final rect = tester.getRect(control);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(width));
  for (final text
      in find.descendant(of: control, matching: find.byType(Text)).evaluate()) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byWidget(text.widget),
        matching: find.byType(RichText),
      ),
    );
    final painted = paragraph.localToGlobal(Offset.zero) & paragraph.size;
    expect(painted.left, greaterThanOrEqualTo(rect.left));
    expect(painted.right, lessThanOrEqualTo(rect.right));
    expect(painted.bottom, lessThanOrEqualTo(rect.bottom));
    expect(
      paragraph.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(paragraph.size.width + .01),
      reason:
          '${(text.widget as Text).data} must remain a complete single line',
    );
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });

  for (final size in [const Size(393, 852), const Size(375, 812)]) {
    for (final scale in [1.0, 1.15, 1.3, 1.5]) {
      for (final bold in [false, true]) {
        final description =
            '${size.width.toInt()} pt, scale $scale, bold $bold';
        testWidgets(
          'Heute week segments stay visible and tappable: $description',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            Map fixture(String name) =>
                jsonDecode(
                      File(
                        'docs/openband5/assets/fixtures/$name.json',
                      ).readAsStringSync(),
                    )
                    as Map;
            final repo = SyntheticOpenBandRepository.fromMaps(
              fixture('day-summary'),
              fixture('sleep-detail'),
              scenario: SyntheticScenario.g3Sample,
            );
            final controller = OpenBandController(
              repository: repo,
              initialDay: '2026-09-29',
              band: repo.band,
              now: () => DateTime(2026, 9, 29, 10),
            );
            addTearDown(controller.dispose);
            await controller.refresh();
            await tester.pumpWidget(
              _app(
                OpenBandHeute(
                  controller: controller,
                  reminder: MemoryHeuteReminder(),
                ),
                scale,
                bold,
              ),
            );
            await tester.pumpAndSettle();
            final header = find.byWidgetPredicate(
              (w) => w is OBSectionHeader && w.text == 'WOCHE',
            );
            await tester.scrollUntilVisible(
              header,
              250,
              scrollable: find.byType(Scrollable).first,
            );
            await Scrollable.ensureVisible(
              tester.element(header),
              alignment: .35,
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final control = find.descendant(
              of: header,
              matching: find.byType(OBSegmented),
            );
            _visibleSegments(tester, control, size.width);
            final target = find.descendant(
              of: control,
              matching: find.bySemanticsLabel('Belastung'),
            );
            final rect = tester.getRect(target);
            expect(rect.right, lessThanOrEqualTo(size.width));
            expect(rect.width, greaterThanOrEqualTo(44));
            expect(rect.height, greaterThanOrEqualTo(44));
            await tester.tap(target);
            await tester.pumpAndSettle();
            expect(tester.widget<OBSegmented>(control).selected, 2);
            _visibleSegments(tester, control, size.width);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          'trend range segments stay visible and tappable: $description',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            var period = OBTrendPeriod.d30;
            await tester.pumpWidget(
              _app(
                SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: StatefulBuilder(
                      builder: (context, setState) => OBTrendChart(
                        title: 'ms · 30 TAGE',
                        period: period,
                        values: const [40, 48],
                        min: 30,
                        max: 60,
                        onPeriod: (value) => setState(() => period = value),
                      ),
                    ),
                  ),
                ),
                scale,
                bold,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final control = find.byType(OBSegmented);
            _visibleSegments(tester, control, size.width);
            final target = find.bySemanticsLabel('90 T');
            expect(tester.getRect(target).right, lessThanOrEqualTo(size.width));
            expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
            expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
            await tester.tap(target);
            await tester.pumpAndSettle();
            expect(period, OBTrendPeriod.d90);
            _visibleSegments(tester, control, size.width);
            expect(tester.takeException(), isNull);
          },
        );
        testWidgets('night segments stay visible and tappable: $description', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var selected = 0;
          await tester.pumpWidget(
            _app(
              Padding(
                padding: const EdgeInsets.all(16),
                child: StatefulBuilder(
                  builder: (context, setState) => OBSegmented(
                    items: const ['Puls', 'HRV', 'Atemfrequenz'],
                    selected: selected,
                    expand: true,
                    onChanged: (value) => setState(() => selected = value),
                  ),
                ),
              ),
              scale,
              bold,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final control = find.byType(OBSegmented);
          _visibleSegments(tester, control, size.width);
          final target = find.bySemanticsLabel('Atemfrequenz');
          expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
          expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
          await tester.tap(target);
          await tester.pumpAndSettle();
          expect(selected, 2);
          _visibleSegments(tester, control, size.width);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  for (final width in [393.0, 375.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'week header at 150 percent bold ${width.toInt()} ${dark ? "dark" : "light"}',
        (tester) async {
          tester.view.physicalSize = Size(width, width == 393 ? 852 : 812);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            _app(
              RepaintBoundary(
                key: const ValueKey('week'),
                child: ColoredBox(
                  color: openBandTheme(
                    dark ? Brightness.dark : Brightness.light,
                  ).scaffoldBackgroundColor,
                  child: SizedBox(
                    height: 150,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: OBSectionHeader(
                        'WOCHE',
                        trailing: OBSegmented(
                          items: const ['Erholung', 'Schlaf', 'Belastung'],
                          selected: 2,
                          onChanged: (_) {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              1.5,
              true,
              dark: dark,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(const ValueKey('week')),
            matchesGoldenFile(
              'openband_goldens/g31-week-bold-150-${width.toInt()}-${dark ? "dark" : "light"}.png',
            ),
          );
        },
        tags: const ['golden'],
      );
    }
  }
}
