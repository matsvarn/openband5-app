// G3 Bausteine: behaviour (honest absence, targets, semantics, Dynamic Type)
// and a golden gallery of every Baustein row, light and dark.
//
// Paper `Bausteine · G3` (p-16-0) is canonical; tool/g3_review.py diffs the
// same specimens against Paper with Helvetica Neue. These goldens render the
// test font stack (Inter), like the rest of test/openband_goldens/.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/g3/charts.dart';
import 'package:openstrap_edge/openband/g3/chrome.dart';
import 'package:openstrap_edge/openband/g3/day.dart';
import 'package:openstrap_edge/openband/g3/g3_theme.dart';
import 'package:openstrap_edge/openband/g3/metrics.dart';
import 'package:openstrap_edge/openband/g3/specimens.dart';
import 'package:openstrap_edge/openband/theme.dart' show openBandTheme;

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
    expect(g3Number(-0.04, digits: 1), '0,0');
    expect(g3Count(6480), '6.480');
    expect(g3Count(null), '—');
  });

  group('honest absence', () {
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

  group('targets and semantics', () {
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
    for (final name in ['OBHrTrace', 'OBTrendChart.d30', 'OBNightCard.full']) {
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
            w.painter.runtimeType.toString().startsWith('_'),
      );
      for (final e in painted.evaluate()) {
        expect(
          find.ancestor(
            of: find.byWidget(e.widget),
            matching: find.byType(RepaintBoundary),
          ),
          findsWidgets,
          reason: '$name ${e.widget}',
        );
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
