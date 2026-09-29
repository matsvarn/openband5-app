// G3 Bausteine: behaviour (honest absence, targets, semantics, Dynamic Type)
// and a golden gallery of every Baustein row, light and dark.
//
// Paper `Bausteine · G3` (p-16-0) is canonical; tool/g3_review.py diffs the
// same specimens against Paper with Helvetica Neue. These goldens render the
// test font stack (Inter), like the rest of test/openband_goldens/.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/g3/charts.dart';
import 'package:openstrap_edge/openband/g3/chrome.dart';
import 'package:openstrap_edge/openband/g3/day.dart';
import 'package:openstrap_edge/openband/g3/g3_theme.dart';
import 'package:openstrap_edge/openband/g3/metrics.dart';
import 'package:openstrap_edge/openband/g3/specimens.dart';
import 'package:openstrap_edge/openband/theme.dart'
    show OBChevron, openBandTheme;

final _frames =
    (jsonDecode(
              File(
                'docs/openband5/design/paper-g3/frames.json',
              ).readAsStringSync(),
            )
            as Map)['components']
        as Map;

/// Paper node width of each specimen (pt); null = intrinsic.
double? _width(String name) {
  const w = {
    'OBPageHeader': 393.0,
    'OBSyncState': 393.0,
    'OBSectionHeader': 393.0,
    'OBFooterStamp': 393.0,
    'OBSheet': 393.0,
    'OBLeadMetric': 321.0,
    'OBSecondaryMetric': 148.0,
    'OBBodyRow': 327.0,
    'OBCardHeader': 325.0,
    'OBDayValueRow': 325.0,
    'OBMetricCard': 172.0,
    'OBFormField': 353.0,
  };
  final base = name.split('.').first;
  if (w.containsKey(base)) return w[base];
  const intrinsic = {
    'OBChip',
    'OBBandCapsule',
    'OBIconButton',
    'OBActionPrimary',
    'OBActionSecondary',
    'OBPillButton',
    'OBSegmented',
  };
  return intrinsic.contains(base) ? null : 361.0;
}

Widget _app(Widget child, {bool dark = false, double textScale = 1}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: openBandTheme(dark ? Brightness.dark : Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          size: const Size(393, 852),
        ),
        child: Material(color: G3(dark).page, child: child),
      ),
    );

Widget _specimen(String name, bool dark) {
  final g = G3(dark);
  final bg = _frames[name]?['background'] == 'canvas' ? g.canvas : g.page;
  final w = _width(name);
  return Container(
    color: bg,
    padding: const EdgeInsets.all(8),
    alignment: Alignment.topLeft,
    child: w == null
        ? g3Specimens[name]!()
        : SizedBox(width: w, child: g3Specimens[name]!()),
  );
}

CustomPainter _painter(WidgetTester tester, String name) => tester
    .widget<CustomPaint>(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter.runtimeType.toString() == name,
      ),
    )
    .painter!;

Future<Color> _paintPixel(
  CustomPainter painter,
  int x,
  int y, {
  int width = 326,
  int height = 150,
}) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final offset = (y * width + x) * 4;
  final result = Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
  image.dispose();
  return result;
}

/// Golden families: file name → Paper layer names.
const _families = {
  'navigation': [
    'OBPageHeader.hub',
    'OBPageHeader.detail',
    'OBPageHeader.compact',
  ],
  'sync-band': [
    'OBSyncState.live',
    'OBSyncState.partial',
    'OBSyncState.stale',
    'OBSyncState.never',
    'OBSyncState.past',
    'OBBandCapsule.live',
    'OBBandCapsule.off',
    'OBBandCapsule.none',
    'OBIconButton',
  ],
  'lead-metric': [
    'OBLeadMetric.normal',
    'OBLeadMetric.better',
    'OBLeadMetric.worse',
    'OBLeadMetric.plain',
    'OBLeadMetric.building',
    'OBLeadMetric.missing',
  ],
  'secondary-panel': [
    'OBSecondaryMetric.goal',
    'OBSecondaryMetric.plain',
    'OBSecondaryMetric.missing',
    'OBPanel.hero',
    'OBPanel',
  ],
  'day-note': [
    'OBDayNote.action',
    'OBDayNote.reminded',
    'OBDayNote.text',
    'OBDayNote.absent',
  ],
  'activity-checkin': [
    'OBActivityRow.auto',
    'OBActivityRow.confirmed',
    'OBCheckIn.question',
    'OBCheckIn.answered',
    'OBCheckIn.later',
  ],
  'week': [
    'OBSegmented.week',
    'OBSegmented.week.sleep',
    'OBWeekBars.recovery',
    'OBWeekBars.sleep',
    'OBWeekBars.empty',
  ],
  'night': ['OBNightCard.full', 'OBNightCard.gap', 'OBNightCard.missing'],
  'body': [
    'OBBodyRow.range',
    'OBBodyRow.plain',
    'OBBodyRow.building',
    'OBBodyRow.missing',
    'OBBodyRow.deviation',
    'OBMetricCard.default',
    'OBMetricCard.missing',
  ],
  'section-list': [
    'OBSectionHeader',
    'OBSectionHeader.plain',
    'OBCardHeader',
    'OBListRow.default',
    'OBListRow.value',
  ],
  'keys-chips': [
    'OBActionPrimary',
    'OBActionSecondary',
    'OBPillButton',
    'OBSegmented',
    'OBSegmented.range',
    'OBChip.delta',
    'OBChip.better',
    'OBChip.worse',
    'OBChip.tag',
    'OBChip.basis',
  ],
  'sheet-states': ['OBSheet', 'OBEmptyState', 'OBErrorBlock'],
  'training': ['OBHrTrace', 'OBZoneRows'],
  'trend': ['OBTrendChart.d7', 'OBTrendChart.d30', 'OBTrendChart.d90'],
  'day-verlauf-form': [
    'OBStepsCard.default',
    'OBStepsCard.missing',
    'OBFooterStamp',
    'OBDateStrip',
    'OBStatRow',
    'OBDayValueRow.default',
    'OBDayValueRow.gap',
    'OBFormField.number',
  ],
};

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

  test(
    'every Paper Baustein except the shell ones has a specimen and a golden family',
    () {
      final registered = _frames.keys.cast<String>().toSet();
      final inFamilies = _families.values.expand((v) => v).toSet();
      expect(registered.difference(g3Specimens.keys.toSet()), isEmpty);
      expect(registered.difference(inFamilies), isEmpty);
    },
  );

  test('numbers are German and never turn a missing value into zero', () {
    expect(g3Number(7.5, digits: 1), '7,5');
    expect(g3Number(-31), '−31');
    expect(g3Number(.4, digits: 1, signed: true), '+0,4');
    expect(g3Number(null), '—');
    expect(g3Number(double.nan), '—');
    expect(g3Number(double.infinity), '—');
    expect(g3Number(double.negativeInfinity), '—');
    expect(g3Number(-0.04, digits: 1), '0,0');
    expect(g3Count(6480), '6.480');
    expect(g3Count(null), '—');
  });

  group('honest absence', () {
    testWidgets('non-finite lead values refuse the value and pointer', (
      tester,
    ) async {
      for (final bad in [double.nan, double.infinity]) {
        await tester.pumpWidget(
          _app(
            SizedBox(
              width: 321,
              child: OBLeadMetric(
                label: 'ERHOLUNG',
                state: OBLeadState.normal,
                value: bad,
                scale: const G3Scale(min: 0, max: 100),
              ),
            ),
          ),
        );
        expect(find.text('—'), findsOneWidget);
        expect(find.byType(G3Scale), findsNothing);
      }
    });

    testWidgets('non-finite secondary fill and goal leave an empty track', (
      tester,
    ) async {
      for (final bad in [double.nan, double.infinity]) {
        await tester.pumpWidget(
          _app(
            SizedBox(
              width: 361,
              child: OBSecondaryMetric(
                label: 'SCHLAF',
                value: '7h',
                fill: bad,
                goal: (bad, 'Ziel'),
                start: '0h',
                end: '10h',
              ),
            ),
          ),
        );
        expect(find.text('Ziel'), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) => w is Positioned && w.width == 2 && w.height == 14,
          ),
          findsNothing,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is Positioned && w.height == 6 && w.width != null,
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
      'non-finite week bars, body pointer, day share and spark are absent',
      (tester) async {
        for (final bad in [double.nan, double.infinity]) {
          await tester.pumpWidget(
            _app(
              SizedBox(
                width: 361,
                child: OBWeekBars(bars: [OBWeekBar('Mo', bad)], max: 100),
              ),
            ),
          );
          expect(find.byType(G3Dashed), findsOneWidget);

          await tester.pumpWidget(
            _app(
              SizedBox(
                width: 327,
                child: OBBodyRow(
                  state: OBBodyState.deviation,
                  name: 'Temperatur',
                  value: '0,2',
                  at: bad,
                ),
              ),
            ),
          );
          expect(
            find.byWidgetPredicate(
              (w) => w is Positioned && w.width == 4 && w.height == 18,
            ),
            findsNothing,
          );

          await tester.pumpWidget(
            _app(
              SizedBox(
                width: 325,
                child: OBDayValueRow(date: 'Mo', value: '80', share: bad),
              ),
            ),
          );
          expect(find.byType(G3Dashed), findsOneWidget);
          expect(find.text('80'), findsOneWidget);

          await tester.pumpWidget(
            _app(
              SizedBox(
                width: 172,
                child: OBMetricCard(
                  label: 'Wert',
                  value: '80',
                  spark: [bad, 0.5],
                ),
              ),
            ),
          );
          expect(
            find.byWidgetPredicate(
              (w) => w is Container && w.constraints?.minWidth == 6,
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('a lead metric without a value refuses instead of scaling', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const OBLeadMetric(
            label: 'ERHOLUNG',
            state: OBLeadState.normal,
            value: null,
            delta: '6',
            scale: G3Scale(min: 0, max: 100, band: (58, 80)),
          ),
        ),
      );
      expect(find.text('—'), findsOneWidget);
      expect(find.byType(G3Scale), findsNothing);
      expect(find.byType(OBChip), findsNothing);
    });

    testWidgets(
      'building shows the stored have/need as tiles, not a percentage',
      (tester) async {
        await tester.pumpWidget(
          _app(
            const SizedBox(
              width: 321,
              child: OBLeadMetric(
                label: 'ERHOLUNG',
                state: OBLeadState.building,
                have: 9,
                need: 14,
              ),
            ),
          ),
        );
        expect(find.text('9 von 14 Nächten'), findsOneWidget);
        expect(find.text('Basis: noch 5 Nächte'), findsOneWidget);
        expect(find.textContaining('%'), findsNothing);
        expect(find.byType(G3Dashed), findsNWidgets(5));
      },
    );

    testWidgets('skin temperature is a unitless deviation, never °C', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          SizedBox(width: 327, child: g3Specimens['OBBodyRow.deviation']!()),
        ),
      );
      expect(find.textContaining('°C'), findsNothing);
      expect(find.text('kühler'), findsOneWidget);
      expect(find.text('wärmer'), findsOneWidget);
    });

    testWidgets('an unconfirmed auto activity shows no zones', (tester) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 361,
            child: OBActivityRow(
              pictogram: const SizedBox(),
              title: 'Lauf',
              subtitle: '07:58–08:40 · 42 Min.',
              unconfirmed: true,
              strain: '+6,1',
              zoneMinutes: const [0, 4, 19, 16, 3],
            ),
          ),
        ),
      );
      expect(find.byType(OBZoneStrip), findsNothing);
      expect(find.text('Zonen nach Bestätigung'), findsOneWidget);
    });

    testWidgets('missing week values are hollow slots, not short bars', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(SizedBox(width: 361, child: g3Specimens['OBWeekBars.empty']!())),
      );
      expect(find.byType(G3Dashed), findsNWidgets(7));
    });

    testWidgets('steps without a transfer read "—" and draw no bars', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          SizedBox(width: 361, child: g3Specimens['OBStepsCard.missing']!()),
        ),
      );
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Ziel festlegen'), findsNothing);
    });

    testWidgets('zone rows name the % HFmax basis and a null zone is "—"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 361,
            child: OBZoneRows(
              zones: [OBZone(3, '70–80 %', null)],
              source: 'HFmax 186 · geschätzt aus Alter',
            ),
          ),
        ),
      );
      expect(find.text('% HFmax'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('Pulsreserve'), findsNothing);
    });
  });

  group('chart paint', () {
    testWidgets('30-day worse endpoint keeps its mark colour', (tester) async {
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 361,
            child: OBTrendChart(
              title: 'TREND',
              period: OBTrendPeriod.d30,
              values: [60, 20],
              marks: [OBTrendMark.none, OBTrendMark.worse],
              min: 0,
              max: 100,
              band: (40, 80),
            ),
          ),
        ),
      );
      expect(
        await tester.runAsync(
          () => _paintPixel(_painter(tester, '_TrendPainter'), 323, 120),
        ),
        G3(false).worseMark,
      );
    });

    testWidgets('heart-rate peak ignores samples inside optical gaps', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 361,
            child: OBHrTrace(
              samples: [(0, 140), (5, 190)],
              duration: 10,
              gaps: [(4, 6)],
              min: 100,
              max: 200,
              zoneEdges: [],
              peak: '190',
            ),
          ),
        ),
      );
      expect(
        await tester.runAsync(
          () =>
              _paintPixel(_painter(tester, '_HrPainter'), 146, 15, width: 291),
        ),
        isNot(G3(false).ink),
      );
      expect(find.text('140'), findsOneWidget);

      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 361,
            child: OBHrTrace(
              samples: [(5, 190)],
              duration: 10,
              gaps: [(4, 6)],
              min: 100,
              max: 200,
              zoneEdges: [],
              peak: '190',
            ),
          ),
        ),
      );
      expect(find.text('140'), findsNothing);
    });

    testWidgets('sparse trend leaves null and non-finite days empty', (
      tester,
    ) async {
      for (final missing in [null, double.nan, double.infinity]) {
        await tester.pumpWidget(
          _app(
            SizedBox(
              width: 361,
              child: OBTrendChart(
                title: 'TREND',
                period: OBTrendPeriod.d30,
                values: [80, missing, 20],
                min: 0,
                max: 100,
                sparse: true,
              ),
            ),
          ),
        );
        expect(
          await tester.runAsync(
            () => _paintPixel(_painter(tester, '_TrendPainter'), 162, 75),
          ),
          isNot(G3(false).ink),
        );
      }
    });
  });

  group('targets and semantics', () {
    testWidgets('error message and retry are separate semantics nodes', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          Semantics(
            label: 'Status',
            child: OBErrorBlock(
              title: 'Band getrennt',
              reason: 'Verbindung fehlgeschlagen.',
              retryLabel: 'Verbinden',
              onRetry: () {},
            ),
          ),
        ),
      );
      final message = tester.getSemantics(
        find.text('Verbindung fehlgeschlagen.'),
      );
      final action = tester.getSemantics(find.bySemanticsLabel('Verbinden'));
      expect(message.label, contains('Verbindung fehlgeschlagen.'));
      expect(action.label, 'Verbinden');
      expect(message.id, isNot(action.id));
      expect(action.flagsCollection.isButton, isTrue);
      semantics.dispose();
    });

    testWidgets('icon key stays separate from a labeled block', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          Semantics(
            label: 'Bandstatus',
            child: Column(
              children: [
                const Text('Band getrennt'),
                OBIconButton(
                  icon: Icons.bluetooth,
                  label: 'Band verbinden',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );
      final message = tester.getSemantics(find.text('Band getrennt'));
      final action = tester.getSemantics(
        find.bySemanticsLabel('Band verbinden'),
      );
      expect(message.label, contains('Band getrennt'));
      expect(message.id, isNot(action.id));
      expect(action.flagsCollection.isButton, isTrue);
      semantics.dispose();
    });

    testWidgets('small actions have 44 pt targets and no false chevrons', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              OBSegmented(
                items: const ['7 T', '30 T'],
                selected: 0,
                onChanged: (_) {},
              ),
              OBSectionHeader(
                'ABSCHNITT',
                action: 'Hinzufügen',
                onAction: () {},
              ),
              OBDateStrip(days: [('Mo', '1')], selected: 0, onCalendar: () {}),
              OBZoneRows(zones: const [], source: 'HFmax', onBasis: () {}),
              OBFormField.number(
                label: 'WERT',
                controller: TextEditingController(),
                unit: 'kg',
                when: 'Heute',
                onTime: () {},
              ),
              const OBSyncState(kind: OBSyncKind.live, text: 'Aktuell'),
            ],
          ),
        ),
      );
      for (final label in [
        '7 T',
        'Hinzufügen',
        'Kalender',
        'Grundlage der Zonen',
        'Zeit ändern',
      ]) {
        final size = tester.getSize(find.bySemanticsLabel(label));
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
      }
      expect(
        find.descendant(
          of: find.byType(OBSyncState),
          matching: find.byType(OBChevron),
        ),
        findsNothing,
      );
      expect(
        tester.getSize(find.bySemanticsLabel('Aktuell')).height,
        greaterThanOrEqualTo(44),
      );

      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              OBSectionHeader('ABSCHNITT', action: 'Hinzufügen'),
              OBZoneRows(zones: [], source: 'HFmax'),
              OBSyncState(kind: OBSyncKind.live, text: 'Aktuell'),
            ],
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(OBSectionHeader),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Grundlage der Zonen'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(OBSyncState),
          matching: find.byType(OBChevron),
        ),
        findsNothing,
      );
    });

    testWidgets('answered check-in change has a 44 pt target', (tester) async {
      await tester.pumpWidget(
        _app(
          OBCheckIn(
            state: OBCheckInState.answered,
            progress: '1 von 4',
            question: 'Frage?',
            answered: 'Ja',
            onChange: () {},
          ),
        ),
      );
      expect(
        tester.getSize(find.bySemanticsLabel('Antwort ändern')).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('scaled track labels stay inside their widgets', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              const SizedBox(
                width: 361,
                child: G3Scale(
                  min: 0,
                  max: 100,
                  ticks: [G3Tick(0, 'Start'), G3Tick(100, 'Ende')],
                ),
              ),
              const SizedBox(
                width: 361,
                child: OBSecondaryMetric(
                  label: 'SCHLAF',
                  value: '7h',
                  fill: .6,
                  goal: (.8, 'Ziel 8h'),
                  start: '0h',
                  end: '10h',
                ),
              ),
            ],
          ),
          textScale: 1.3,
        ),
      );
      final scaleBottom = tester.getBottomLeft(find.byType(G3Scale)).dy;
      for (final label in ['Start', 'Ende']) {
        expect(
          tester.getBottomLeft(find.text(label)).dy,
          lessThanOrEqualTo(scaleBottom),
        );
      }
      final secondaryBottom = tester
          .getBottomLeft(find.byType(OBSecondaryMetric))
          .dy;
      for (final label in ['0h', 'Ziel 8h', '10h']) {
        expect(
          tester.getBottomLeft(find.text(label)).dy,
          lessThanOrEqualTo(secondaryBottom),
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('secondary goal caption follows its fraction', (tester) async {
      Future<double> left(double fraction) async {
        await tester.pumpWidget(
          _app(
            SizedBox(
              width: 361,
              child: OBSecondaryMetric(
                label: 'SCHLAF',
                value: '7h',
                goal: (fraction, 'Ziel 8h'),
                start: '0h',
                end: '10h',
              ),
            ),
          ),
        );
        return tester.getTopLeft(find.text('Ziel 8h')).dx;
      }

      final leftGoal = await left(.25);
      final rightGoal = await left(.75);
      expect(rightGoal - leftGoal, greaterThan(100));
      expect(
        tester.getTopRight(find.text('Ziel 8h')).dx,
        lessThan(tester.getTopLeft(find.text('10h')).dx),
      );
    });
    testWidgets('header keys keep 44 pt targets and German labels', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              g3Specimens['OBPageHeader.hub']!(),
              OBPageHeader.detail(
                title: 'ERHOLUNG',
                backLabel: 'Heute',
                onBack: () {},
              ),
            ],
          ),
        ),
      );
      for (final label in [
        'Profil',
        'Zurück zu Heute',
        'Erklärung',
        'Band verbunden, Akku 64 Prozent',
      ]) {
        final size = tester.getSize(find.bySemanticsLabel(label));
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
      }
    });

    testWidgets('note reminder and check-in keys are 44 pt and tappable', (
      tester,
    ) async {
      var reminded = 0, later = 0;
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              SizedBox(
                width: 361,
                child: OBDayNote(
                  state: OBNoteState.action,
                  headline: 'Heute früher ins Bett.',
                  reason: 'Schlaf 27 Min. unter Ziel.',
                  actionTitle: '22:20 ins Bett',
                  actionSubtitle: 'für 8h05 Schlafbedarf bis 06:54',
                  onRemind: () => reminded++,
                ),
              ),
              SizedBox(
                width: 361,
                child: OBCheckIn(
                  state: OBCheckInState.question,
                  progress: '1 von 4',
                  question: 'Gestern Abend Alkohol?',
                  onLater: () => later++,
                ),
              ),
            ],
          ),
        ),
      );
      final remind = find.bySemanticsLabel('Erinnern: 22:20 ins Bett');
      expect(tester.getSize(remind).height, greaterThanOrEqualTo(44));
      await tester.tap(remind);
      await tester.tap(find.bySemanticsLabel('Später'));
      expect((reminded, later), (1, 1));
      for (final l in ['Nein', 'Ja', 'Später']) {
        expect(
          tester.getSize(find.bySemanticsLabel(l)).height,
          greaterThanOrEqualTo(44),
          reason: l,
        );
      }
    });

    testWidgets('a segment without data is announced and cannot be chosen', (
      tester,
    ) async {
      int? chosen;
      await tester.pumpWidget(
        _app(
          Center(
            child: OBSegmented(
              items: const ['Erholung', 'Schlaf'],
              selected: 1,
              disabled: const {0},
              onChanged: (i) => chosen = i,
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Erholung, noch keine Werte'));
      expect(chosen, isNull);
    });
  });

  testWidgets('painters sit behind RepaintBoundary', (tester) async {
    for (final (name, painterName) in [
      ('OBHrTrace', '_HrPainter'),
      ('OBTrendChart.d30', '_TrendPainter'),
      ('OBNightCard.full', '_HypnoPainter'),
    ]) {
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: SizedBox(width: 361, child: g3Specimens[name]!()),
          ),
        ),
      );
      final painted = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter != null &&
            w.painter.runtimeType.toString() == painterName,
      );
      expect(painted, findsWidgets);
      for (final e in painted.evaluate()) {
        Widget? parent;
        e.visitAncestorElements((ancestor) {
          parent = ancestor.widget;
          return false;
        });
        expect(parent, isA<RepaintBoundary>(), reason: '$name ${e.widget}');
      }
    }
  });

  testWidgets('Dynamic Type 200 %: every Baustein lays out without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overflowing = <String>[];
    for (final name in g3Specimens.keys) {
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(child: _specimen(name, false)),
          textScale: 2,
        ),
      );
      if (tester.takeException() != null) overflowing.add(name);
    }
    expect(overflowing, isEmpty);
  });

  group('gallery', () {
    for (final MapEntry(key: file, value: names) in _families.entries) {
      testWidgets('g3 $file', (tester) async {
        tester.view.physicalSize = const Size(900, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        Widget column(bool dark) => Theme(
          data: openBandTheme(dark ? Brightness.dark : Brightness.light),
          child: Container(
            width: 440,
            color: G3(dark).page,
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final n in names)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _specimen(n, dark),
                  ),
              ],
            ),
          ),
        );
        await tester.pumpWidget(
          _app(
            Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: const ValueKey('gallery'),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [column(false), column(true)],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(const ValueKey('gallery')),
          matchesGoldenFile('openband_goldens/g3-$file.png'),
        );
      }, tags: const ['golden']);
    }
  });
}
