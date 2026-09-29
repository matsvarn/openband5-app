import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/g3/chrome.dart';
import 'package:openstrap_edge/openband/g3/day.dart';
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
