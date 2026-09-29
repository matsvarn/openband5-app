import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/g3/chrome.dart';
import 'package:openstrap_edge/openband/g3/day.dart';
import 'package:openstrap_edge/openband/g3/g3_format.dart';
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
    expect(g3Relative(tuesday, now: tuesday), 'heute 09:38');
    expect(g3Relative(monday, now: tuesday), 'gestern 09:38');
    expect(
      g3Relative(DateTime(2026, 9, 22, 9, 38), now: tuesday),
      'Di 22.09 09:38',
    );
    expect(g3DayLong(DateTime(2026, 9, 1)), 'Dienstag, 1. September');
    expect(g3DayShort(DateTime(2025, 9, 23)), 'Di 23.09');
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
}
