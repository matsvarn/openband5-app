import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/g3/chrome.dart';
import 'package:openstrap_edge/openband/g3/band_parts.dart' show OBSettingsRow;
import 'package:openstrap_edge/openband/g3/day.dart';
import 'package:openstrap_edge/openband/g3/g3_format.dart';
import 'package:openstrap_edge/openband/g3/g3_theme.dart';
import 'package:openstrap_edge/openband/g3/metrics.dart';
import 'package:openstrap_edge/openband/theme.dart'
    show OBChevron, openBandTheme;

Widget _frame(Widget child) => MaterialApp(
  theme: openBandTheme(Brightness.light),
  home: Scaffold(
    body: Center(child: SizedBox(width: 340, child: child)),
  ),
);

void main() {
  test('C-83 normalizes every audited date form', () {
    final tuesday = DateTime(2026, 9, 29, 9, 38);
    final monday = DateTime(2026, 9, 28, 9, 38);
    expect(g3DayLong(tuesday), 'Dienstag, 29. September');
    expect(g3NightOf(tuesday), 'Nacht zu Di 29.09');
    expect(g3DayShort(tuesday), 'Di 29.09');
    expect(g3DateShort(tuesday), '29.09');
    expect(g3DateShort(monday), '28.09');
    expect(g3Clock(DateTime(2026, 9, 29, 6, 4)), '06:04');
    expect(g3Weekday(tuesday), 'Di');
    expect(g3Weekday(DateTime(2026, 10, 4)), 'So');
    expect(g3Relative(tuesday, now: tuesday), 'heute 09:38');
    expect(g3Relative(monday, now: tuesday), 'gestern 09:38');
    expect(
      g3Relative(DateTime(2026, 9, 22, 9, 38), now: tuesday),
      'Di 22.09 09:38',
    );
    expect(g3DayLong(DateTime(2026, 9, 1)), 'Dienstag, 1. September');
    expect(g3DayShort(DateTime(2025, 9, 23)), 'Di 23.09');
    expect(g3DataThrough(tuesday, now: tuesday), 'Daten bis 09:38');
    expect(g3DataThrough(monday, now: tuesday), 'Daten bis gestern 09:38');
    expect(
      g3DataThrough(DateTime(2026, 9, 22, 9, 38), now: tuesday),
      'Daten bis Di 22.09 09:38',
    );
    expect(g3DataThrough(null, now: tuesday), 'Datenstand unbekannt');
  });

  test('C-84 uses compact durations, Unicode signs and spaced units', () {
    expect(g3Duration(438), '7h18');
    expect(g3Duration(42), '42 Min.');
    expect(g3Duration(119), '1h59');
    expect(g3Duration(600), '10h');
    expect(g3Duration(0), '0 Min.');
    expect(g3Duration(-27), '−27 Min.');
    expect(g3Duration(null), '—');
    expect(g3Signed(6.1, digits: 1), '+6,1');
    expect(g3Signed(-27, unit: 'Min.'), '−27 Min.');
    expect(g3Signed(10, unit: 'Min.'), '+10 Min.');
    expect(g3Signed(-5), '−5');
    expect(g3Signed(64, unit: '%'), '+64 %');
    expect(g3Signed(0), '0');
    expect(g3Signed(-0.04, digits: 1), '0,0');
    expect(g3Signed(null), '—');
  });

  testWidgets('day note uses the supplied heading', (tester) async {
    await tester.pumpWidget(
      _frame(
        const OBDayNote(
          state: OBNoteState.text,
          heading: 'FÜR DIE NACHT',
          headline: 'Zeit fürs Bett',
          reason: 'Dein Schlafbedarf',
        ),
      ),
    );
    expect(find.text('FÜR DIE NACHT'), findsOneWidget);
    expect(find.text('FÜR HEUTE'), findsNothing);
  });

  testWidgets('detail page exposes a full-width section and controller', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _frame(
        G3DetailPage(
          header: const Text('Titel'),
          fullWidthSection: const SizedBox(
            width: double.infinity,
            child: Text('Abschnitt'),
          ),
          scrollController: controller,
          children: const [Text('Inset')],
        ),
      ),
    );
    expect(controller.hasClients, isTrue);
    expect(
      tester.getTopLeft(find.text('Abschnitt')).dx,
      lessThan(tester.getTopLeft(find.text('Inset')).dx),
    );
  });

  testWidgets('label and card chevrons require a handler', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_frame(const G3LabelRow('ERHOLUNG')));
    expect(find.byType(OBChevron), findsNothing);
    await tester.pumpWidget(
      _frame(G3LabelRow('ERHOLUNG', onTap: () => taps++)),
    );
    expect(find.byType(OBChevron), findsOneWidget);
    await tester.tap(find.text('ERHOLUNG'));
    expect(taps, 1);

    await tester.pumpWidget(_frame(const OBCardHeader('KÖRPER')));
    expect(find.byType(OBChevron), findsNothing);
    await tester.pumpWidget(
      _frame(OBCardHeader('KÖRPER', onTap: () => taps++)),
    );
    expect(find.byType(OBChevron), findsOneWidget);
    await tester.tap(find.text('KÖRPER'));
    expect(taps, 2);
  });

  testWidgets('detail leads can use an info tap without a duplicate arrow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _frame(
        OBLeadMetric(
          label: 'HRV',
          state: OBLeadState.normal,
          value: 42,
          onTap: () {},
          showLabelArrow: false,
        ),
      ),
    );
    expect(find.byType(OBChevron), findsNothing);
  });

  testWidgets('shared rows and empty action show arrows only when tappable', (
    tester,
  ) async {
    final cases = <Widget>[
      const OBListRow(title: 'Liste'),
      const OBBodyRow(state: OBBodyState.missing, name: 'HRV'),
      const OBActivityRow(
        pictogram: Icon(LucideIcons.activity),
        title: 'Lauf',
        subtitle: 'Heute',
      ),
      const OBEmptyState(
        title: 'Leer',
        reason: 'Keine Daten',
        action: 'Öffnen',
      ),
    ];
    for (final child in cases) {
      await tester.pumpWidget(_frame(child));
      expect(find.byType(OBChevron), findsNothing);
    }
    final handled = <Widget>[
      OBListRow(title: 'Liste', onTap: () {}),
      OBBodyRow(state: OBBodyState.missing, name: 'HRV', onTap: () {}),
      OBActivityRow(
        pictogram: const Icon(LucideIcons.activity),
        title: 'Lauf',
        subtitle: 'Heute',
        onTap: () {},
      ),
      OBEmptyState(
        title: 'Leer',
        reason: 'Keine Daten',
        action: 'Öffnen',
        onAction: () {},
      ),
    ];
    for (final child in handled) {
      await tester.pumpWidget(_frame(child));
      expect(find.byType(OBChevron), findsOneWidget);
    }
  });

  testWidgets('shared headers leave empty slots for missing callbacks', (
    tester,
  ) async {
    await tester.pumpWidget(
      _frame(
        const OBPageHeader.hub(
          title: 'Heute',
          subtitle: 'Dienstag',
          band: OBBandCapsule(state: OBBandState.off),
        ),
      ),
    );
    expect(find.byIcon(LucideIcons.user), findsNothing);
    expect(find.byType(OBChevron), findsNothing);

    await tester.pumpWidget(
      _frame(
        const OBPageHeader.detail(
          title: 'HRV',
          backLabel: 'Heute',
          onBack: null,
        ),
      ),
    );
    expect(find.byIcon(LucideIcons.info), findsNothing);
    expect(find.byType(OBChevron), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is SizedBox && w.width == 44),
      findsNWidgets(2),
    );

    await tester.pumpWidget(
      _frame(
        const OBPageHeader.compact(
          title: 'Heute',
          band: OBBandCapsule(state: OBBandState.live),
        ),
      ),
    );
    expect(find.byIcon(LucideIcons.user), findsNothing);
  });

  testWidgets('shared links have a 44 pt target and invoke their handler', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_frame(OBLink('Methode', onTap: () => taps++)));
    final target = find.bySemanticsLabel('Methode');
    expect(tester.getSize(target).height, 44);
    expect(find.byType(OBChevron), findsOneWidget);
    await tester.tap(target);
    expect(taps, 1);
  });

  testWidgets('detail header and shared card contents follow one gutter', (
    tester,
  ) async {
    await tester.pumpWidget(
      _frame(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 230,
              child: G3DetailPage(
                header: Container(
                  key: const ValueKey('header'),
                  height: 44,
                  color: Colors.transparent,
                ),
                children: [
                  Container(
                    key: const ValueKey('content'),
                    height: 40,
                    color: Colors.transparent,
                  ),
                ],
              ),
            ),
            const OBPanel(hero: true, child: Text('hero')),
            const OBPanel(child: Text('normal')),
            const OBSectionHeader('ABSCHNITT', trailing: Text('3')),
            const OBSettingsRow(label: 'Version', value: '1.2'),
          ],
        ),
      ),
    );
    final header = tester.getRect(find.byKey(const ValueKey('header')));
    final content = tester.getRect(find.byKey(const ValueKey('content')));
    expect(content.top - header.bottom, 12);
    expect(content.left - header.left, 16);
    expect(
      tester.getRect(find.text('hero')).left,
      tester.getRect(find.text('normal')).left,
    );
    expect(
      tester.getRect(find.byType(OBSectionHeader)).right -
          tester.getRect(find.text('3')).right,
      16,
    );
    expect(
      tester.getRect(find.byType(OBSettingsRow)).right -
          tester.getRect(find.text('1.2')).right,
      0,
    );
  });

  testWidgets('explanation sheet has one close key and no dead actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _frame(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showOBInfoSheet(
              context,
              title: 'Methode',
              paragraphs: const ['Erster Satz.', 'Zweiter Satz.'],
            ),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('Methode'), findsOneWidget);
    expect(find.text('Erster Satz.'), findsOneWidget);
    expect(find.text('Zweiter Satz.'), findsOneWidget);
    expect(find.text('Abbrechen'), findsNothing);
    expect(find.text('Speichern'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('Methode'), findsNothing);
  });

  testWidgets('missing values and synthetic labels use shared styles', (
    tester,
  ) async {
    await tester.pumpWidget(
      _frame(
        const Column(children: [OBMissingValue(size: 36), G3SyntheticLabel()]),
      ),
    );
    expect(tester.widget<Text>(find.text('—')).style!.color, G3(false).gap);
    expect(find.text('SYNTHETISCHE DATEN'), findsOneWidget);
  });
}
