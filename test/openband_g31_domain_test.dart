import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/alp_tokens.dart';
import 'package:openstrap_edge/openband/g3/charts.dart';
import 'package:openstrap_edge/openband/g3/chrome.dart';
import 'package:openstrap_edge/openband/g3/day.dart';
import 'package:openstrap_edge/openband/g3/g3_theme.dart';
import 'package:openstrap_edge/openband/g3/metrics.dart';
import 'package:openstrap_edge/openband/theme.dart'
    show OB, OBChevron, openBandTheme;

Widget _frame(Widget child, {bool dark = false}) => MaterialApp(
  theme: openBandTheme(dark ? Brightness.dark : Brightness.light),
  home: Scaffold(
    body: Center(child: SizedBox(width: 361, child: child)),
  ),
);

Color _bar(WidgetTester tester, String day) =>
    (tester.widget<Container>(find.byKey(ValueKey('week-bar-$day'))).decoration!
            as BoxDecoration)
        .color!;

void main() {
  setUpAll(() async {
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

  test('domain roles use the approved light and dark hues', () {
    for (final (dark, expected) in [
      (
        false,
        [
          const Color(0xFF1B6294),
          const Color(0xFF5F48C5),
          const Color(0xFF9D376A),
        ],
      ),
      (
        true,
        [
          const Color(0xFF6FB6E6),
          const Color(0xFFA898F0),
          const Color(0xFFE58AB7),
        ],
      ),
    ]) {
      final g = G3(dark);
      for (final (i, domain) in [
        G3Domain.recovery,
        G3Domain.sleep,
        G3Domain.load,
      ].indexed) {
        expect(g.domainHue(domain), expected[i]);
        expect(g.domainBar(domain), isNot(g.domainHue(domain)));
        expect(g.domainTint(domain), isNot(g.domainBar(domain)));
      }
      expect(g.domainHue(G3Domain.neutral), g.ink);
      expect(g.domainBar(G3Domain.neutral), g.bar);
      expect(g.normalBand(G3Domain.neutral), g.band);
      expect(g.zonesFor(G3Domain.neutral), isNot(g.zonesFor(G3Domain.load)));
      expect(
        g.hypnoLaneFor(G3Domain.neutral),
        isNot(g.hypnoLaneFor(G3Domain.sleep)),
      );
    }
    expect(AlpColor.domainRecoveryBar, const Color(0xFFA9C6DE));
    expect(AlpColor.darkDomainSleepTint, const Color(0xFF28233F));
  });

  test('legacy sleep stages stay grey until a G3 metric opts in', () {
    expect(OB(false).stageDeep, const Color(0xFF1B1B1A));
    expect(OB(false).stageLight, const Color(0xFF6A6A66));
    expect(OB(true).stageDeep, const Color(0xFFEDEDE9));
    expect(OB(true).stageLight, const Color(0xFF9A9A94));
    expect(G3(true).stageFor(G3Domain.neutral, 2), OB(true).stageLight);
    expect(G3(true).stageFor(G3Domain.sleep, 2), AlpColor.darkStageLight);
  });

  testWidgets('domain colours header only; lead and chevron remain neutral', (
    tester,
  ) async {
    await tester.pumpWidget(
      _frame(
        OBLeadMetric(
          label: 'ERHOLUNG',
          glyph: LucideIcons.heartPulse,
          domain: G3Domain.recovery,
          state: OBLeadState.normal,
          value: 74,
          onTap: () {},
          scale: const G3Scale(min: 0, max: 100, value: 74, band: (58, 80)),
        ),
      ),
    );
    final g = G3(false);
    expect(
      tester.widget<Text>(find.text('ERHOLUNG')).style!.color,
      g.domainHue(G3Domain.recovery),
    );
    expect(
      tester.widget<Icon>(find.byIcon(LucideIcons.heartPulse)).color,
      g.domainHue(G3Domain.recovery),
    );
    expect(tester.widget<OBChevron>(find.byType(OBChevron)).color, g.muted);
    final lead = tester.widget<Text>(find.text('74'));
    expect((lead.textSpan! as TextSpan).children!.first.style!.color, g.ink);
    expect(
      tester.widget<G3Scale>(find.byType(G3Scale)).domain,
      G3Domain.recovery,
    );
    expect(
      tester
          .widget<ColoredBox>(find.byKey(const ValueKey('scale-normal-band')))
          .color,
      g.domainBar(G3Domain.recovery),
    );
  });

  testWidgets('neutral is the header and control default', (tester) async {
    await tester.pumpWidget(
      _frame(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OBCardHeader('JOURNAL'),
            OBActionPrimary('Weiter', onPressed: () {}),
          ],
        ),
      ),
    );
    expect(
      tester.widget<OBCardHeader>(find.byType(OBCardHeader)).domain,
      G3Domain.neutral,
    );
    expect(
      tester.widget<Text>(find.text('JOURNAL')).style!.color,
      G3(false).ink,
    );
    expect(find.byType(OBChevron), findsNothing);
    expect(
      tester.widget<Text>(find.text('Weiter')).style!.color,
      isNot(G3(false).domainHue(G3Domain.load)),
    );
  });

  testWidgets('domain header alone does not imply a tap target', (
    tester,
  ) async {
    await tester.pumpWidget(
      _frame(
        const OBCardHeader(
          'SCHLAF',
          domain: G3Domain.sleep,
          glyph: LucideIcons.moon,
        ),
      ),
    );
    expect(
      tester.widget<Text>(find.text('SCHLAF')).style!.color,
      G3(false).domainHue(G3Domain.sleep),
    );
    expect(find.byType(OBChevron), findsNothing);
    expect(tester.widget<G3LabelRow>(find.byType(G3LabelRow)).onTap, isNull);
  });

  testWidgets('detail title takes identity while the back control stays ink', (
    tester,
  ) async {
    await tester.pumpWidget(
      _frame(
        OBPageHeader.detail(
          title: 'ERHOLUNG',
          backLabel: 'Heute',
          onBack: () {},
          domain: G3Domain.recovery,
        ),
      ),
    );
    final g = G3(false);
    expect(
      tester.widget<Text>(find.text('ERHOLUNG')).style!.color,
      g.domainHue(G3Domain.recovery),
    );
    expect(tester.widget<Text>(find.text('Heute')).style!.color, g.ink);
    expect(tester.widget<OBChevron>(find.byType(OBChevron)).color, g.ink);
  });

  testWidgets(
    'week uses tint, past bar, today hue and out-of-range amber on top',
    (tester) async {
      await tester.pumpWidget(
        _frame(
          const OBWeekBars(
            domain: G3Domain.recovery,
            max: 100,
            band: (58, 80),
            bars: [
              OBWeekBar('Mo', 66),
              OBWeekBar('Di', 49, deviation: G3Deviation.worse),
              OBWeekBar('Mi', 86, deviation: G3Deviation.better),
              OBWeekBar('Heute', 74, today: true),
            ],
          ),
        ),
      );
      final g = G3(false);
      expect(_bar(tester, 'Mo'), g.domainBar(G3Domain.recovery));
      expect(_bar(tester, 'Di'), g.worseMark);
      expect(_bar(tester, 'Mi'), g.betterMark);
      expect(_bar(tester, 'Heute'), g.domainHue(G3Domain.recovery));
      expect(_bar(tester, 'Di'), isNot(g.domainHue(G3Domain.recovery)));
    },
  );

  testWidgets('steps use the current hour hue and older hours bar tone', (
    tester,
  ) async {
    await tester.pumpWidget(
      _frame(
        const OBStepsCard(
          domain: G3Domain.load,
          total: 240,
          note: 'bis 09:38',
          hourly: [100, 120, 20],
          goalLabel: null,
        ),
      ),
    );
    Color color(int hour) =>
        (tester
                    .widget<Container>(find.byKey(ValueKey('steps-hour-$hour')))
                    .decoration!
                as BoxDecoration)
            .color!;
    final g = G3(false);
    expect(color(0), g.domainBar(G3Domain.load));
    expect(color(2), g.domainHue(G3Domain.load));
    expect(tester.widget<Text>(find.text('240')).style!.color, g.ink);
  });

  for (final dark in [false, true]) {
    testWidgets('G3.1 domain components ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final g = G3(dark);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: openBandTheme(dark ? Brightness.dark : Brightness.light),
          home: Material(
            color: g.page,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const OBSectionHeader(
                    'ERHOLUNG',
                    domain: G3Domain.recovery,
                    glyph: LucideIcons.heartPulse,
                  ),
                  OBPanel(
                    child: OBLeadMetric(
                      label: 'ERHOLUNG',
                      glyph: LucideIcons.heartPulse,
                      domain: G3Domain.recovery,
                      state: OBLeadState.normal,
                      value: 74,
                      delta: '6',
                      caption: 'über deinem Median 68',
                      scale: const G3Scale(
                        min: 0,
                        max: 100,
                        value: 74,
                        band: (58, 80),
                        ticks: [
                          G3Tick(0, '0'),
                          G3Tick(58, '58'),
                          G3Tick(80, '80'),
                          G3Tick(100, '100'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const OBWeekBars(
                    domain: G3Domain.recovery,
                    max: 100,
                    band: (58, 80),
                    bars: [
                      OBWeekBar('Mi', 66),
                      OBWeekBar('Do', 55, deviation: G3Deviation.worse),
                      OBWeekBar('Fr', 62),
                      OBWeekBar('Sa', 71),
                      OBWeekBar('So', 49, deviation: G3Deviation.worse),
                      OBWeekBar('Mo', 63),
                      OBWeekBar('Heute', 74, today: true),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const OBWeekBars(
                    domain: G3Domain.sleep,
                    max: 600,
                    goal: 465,
                    labelsBelow: true,
                    bars: [
                      OBWeekBar('Mi', 422, label: '7h02'),
                      OBWeekBar('Do', 391, label: '6h31'),
                      OBWeekBar('Fr', 460, label: '7h40'),
                      OBWeekBar('Sa', 485, label: '8h05'),
                      OBWeekBar('So', 372, label: '6h12'),
                      OBWeekBar('Mo', 445, label: '7h25'),
                      OBWeekBar('Heute', 438, label: '7h18', today: true),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const OBTrendChart(
                    title: 'VERLAUF',
                    domain: G3Domain.recovery,
                    period: OBTrendPeriod.d7,
                    values: [66, 55, 62, 71, 49, 63, 74],
                    marks: [
                      OBTrendMark.none,
                      OBTrendMark.worse,
                      OBTrendMark.none,
                      OBTrendMark.better,
                      OBTrendMark.worse,
                      OBTrendMark.none,
                      OBTrendMark.none,
                    ],
                    min: 0,
                    max: 100,
                    band: (58, 80),
                    xLabels: ['Mi', 'Do', 'Fr', 'Sa', 'So', 'Mo', 'heute'],
                  ),
                  const SizedBox(height: 12),
                  const OBTrendChart(
                    title: 'BELASTUNG',
                    domain: G3Domain.load,
                    period: OBTrendPeriod.d30,
                    values: [
                      8.2,
                      12.6,
                      10.1,
                      7.0,
                      11.0,
                      4.3,
                      13.4,
                      8.8,
                      11.0,
                      9.4,
                    ],
                    min: 0,
                    max: 21,
                    xLabels: ['31.08', '14.09', 'heute'],
                  ),
                  const SizedBox(height: 12),
                  OBPanel(
                    child: const OBHrTrace(
                      domain: G3Domain.load,
                      samples: [
                        (0, 108),
                        (5, 124),
                        (10, 143),
                        (15, 149),
                        (20, 155),
                        (25, 148),
                        (30, 165),
                        (35, 145),
                        (42, 116),
                      ],
                      duration: 42,
                      zoneEdges: [93, 111, 130, 149, 167, 186],
                      axis: ('07:58', '08:19', '08:40'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OBPanel(
                    child: const OBHypnogram(
                      domain: G3Domain.sleep,
                      totalMinutes: 120,
                      segments: [
                        OBStageSegment(OBStage.deep, 0, 24),
                        OBStageSegment(OBStage.light, 25, 63),
                        OBStageSegment(OBStage.rem, 64, 92),
                        OBStageSegment(OBStage.wake, 93, 120),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const OBZoneRows(
                    domain: G3Domain.load,
                    source: 'HFmax 186',
                    zones: [
                      OBZone(1, '', 3),
                      OBZone(2, '', 9),
                      OBZone(3, '', 17),
                      OBZone(4, '', 11),
                      OBZone(5, '', 2),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const OBActivityRow(
                    domain: G3Domain.load,
                    pictogram: Icon(LucideIcons.activity),
                    title: 'Lauf',
                    subtitle: '07:58–08:40 · 42 Min.',
                    strain: '+6,1',
                  ),
                  const SizedBox(height: 12),
                  const OBStepsCard(
                    domain: G3Domain.load,
                    total: 6480,
                    note: 'bis 09:38',
                    goalLabel: null,
                    hourly: [0, 0, 0, 0, 0, 0, 10, 80, 420, 250],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'openband_goldens/g31-domain-components-${dark ? 'dark' : 'light'}.png',
        ),
      );
    }, tags: const ['golden']);
  }
}
