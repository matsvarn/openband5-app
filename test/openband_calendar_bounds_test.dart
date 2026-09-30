import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/calendar.dart';
import 'package:openstrap_edge/openband/theme.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('de_DE'));

  Future<void> pump(
    WidgetTester tester, {
    required DateTime now,
    required DateTime month,
    required DateTime selected,
    DateTime? lastDate,
    bool allowFuture = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: _MonthHost(
            now: now,
            initialMonth: month,
            initialSelected: selected,
            lastDate: lastDate,
            allowFuture: allowFuture,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('default cap stays today and still marks today', (tester) async {
    final now = DateTime(2026, 9, 15, 9, 41);
    await pump(
      tester,
      now: now,
      month: DateTime(2026, 9),
      selected: DateTime(2026, 9, 14),
    );
    expect(tester.widget<OBCalendar>(find.byType(OBCalendar)).lastDate, isNull);
    expect(_dayEnabled(tester, '15. September 2026'), isTrue);
    expect(_dayEnabled(tester, '16. September 2026'), isFalse);
    expect(_todayRing(tester, '15. September 2026'), isTrue);
    expect(_todayRing(tester, '14. September 2026'), isFalse);
    expect(_monthButton(tester, 'Nächster Monat').onPressed, isNull);
  });

  testWidgets('allowFuture without lastDate keeps later months open', (
    tester,
  ) async {
    await pump(
      tester,
      now: DateTime(2026, 9, 15, 9, 41),
      month: DateTime(2026, 9),
      selected: DateTime(2026, 9, 15),
      allowFuture: true,
    );
    expect(_dayEnabled(tester, '16. September 2026'), isTrue);
    expect(_monthButton(tester, 'Nächster Monat').onPressed, isNotNull);
    await tester.tap(find.byTooltip('Nächster Monat'));
    await tester.pumpAndSettle();
    expect(find.text('Oktober 2026'), findsOneWidget);
    expect(_dayEnabled(tester, '16. Oktober 2026'), isTrue);
  });

  testWidgets('allowFuture false still caps at today when lastDate is later', (
    tester,
  ) async {
    await pump(
      tester,
      now: DateTime(2026, 9, 15, 9, 41),
      month: DateTime(2026, 9),
      selected: DateTime(2026, 9, 15),
      lastDate: DateTime(2026, 10, 20, 9, 41),
    );
    expect(_dayEnabled(tester, '15. September 2026'), isTrue);
    expect(_dayEnabled(tester, '16. September 2026'), isFalse);
    expect(_monthButton(tester, 'Nächster Monat').onPressed, isNull);
  });

  testWidgets('explicit lastDate caps a future-capable calendar', (
    tester,
  ) async {
    await pump(
      tester,
      now: DateTime(2026, 9, 15, 9, 41),
      month: DateTime(2026, 9),
      selected: DateTime(2026, 9, 14),
      lastDate: DateTime(2026, 10, 5, 9, 41),
      allowFuture: true,
    );
    expect(_todayRing(tester, '15. September 2026'), isTrue);
    expect(_dayEnabled(tester, '16. September 2026'), isTrue);
    expect(_monthButton(tester, 'Nächster Monat').onPressed, isNotNull);
    await tester.tap(find.byTooltip('Nächster Monat'));
    await tester.pumpAndSettle();
    expect(find.text('Oktober 2026'), findsOneWidget);
    expect(_dayEnabled(tester, '5. Oktober 2026'), isTrue);
    expect(_dayEnabled(tester, '6. Oktober 2026'), isFalse);
    expect(_todayRing(tester, '5. Oktober 2026'), isFalse);
    expect(_monthButton(tester, 'Nächster Monat').onPressed, isNull);
  });

  testWidgets('historical lastDate does not become today', (tester) async {
    await pump(
      tester,
      now: DateTime(2026, 9, 15, 9, 41),
      month: DateTime(2026, 9),
      selected: DateTime(2026, 9, 9),
      lastDate: DateTime(2026, 9, 10, 23, 59),
    );
    expect(_dayEnabled(tester, '10. September 2026'), isTrue);
    expect(_dayEnabled(tester, '11. September 2026'), isFalse);
    expect(_todayRing(tester, '10. September 2026'), isFalse);
    expect(_todayRing(tester, '15. September 2026'), isTrue);
    expect(_dayEnabled(tester, '15. September 2026'), isFalse);
    expect(find.text('Heute'), findsNothing);
  });

  testWidgets('lastDate compares the civil day, not the clock time', (
    tester,
  ) async {
    await pump(
      tester,
      now: DateTime(2026, 9, 1, 8),
      month: DateTime(2026, 9),
      selected: DateTime(2026, 9, 1),
      lastDate: DateTime(2026, 9, 15, 23, 59),
      allowFuture: true,
    );
    expect(_dayEnabled(tester, '15. September 2026'), isTrue);
    expect(_dayEnabled(tester, '16. September 2026'), isFalse);
    expect(_monthButton(tester, 'Nächster Monat').onPressed, isNull);
  });
}

class _MonthHost extends StatefulWidget {
  const _MonthHost({
    required this.now,
    required this.initialMonth,
    required this.initialSelected,
    required this.allowFuture,
    this.lastDate,
  });

  final DateTime now;
  final DateTime initialMonth;
  final DateTime initialSelected;
  final DateTime? lastDate;
  final bool allowFuture;

  @override
  State<_MonthHost> createState() => _MonthHostState();
}

class _MonthHostState extends State<_MonthHost> {
  late DateTime month = widget.initialMonth;
  late DateTime selected = widget.initialSelected;

  @override
  Widget build(BuildContext context) {
    return OBCalendar(
      month: month,
      selected: selected,
      now: widget.now,
      lastDate: widget.lastDate,
      allowFuture: widget.allowFuture,
      onSelect: (date) => setState(() {
        selected = date;
        month = DateTime(date.year, date.month);
      }),
      onPrevMonth: () =>
          setState(() => month = DateTime(month.year, month.month - 1)),
      onNextMonth: () =>
          setState(() => month = DateTime(month.year, month.month + 1)),
    );
  }
}

IconButton _monthButton(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
      ),
    );

Finder _dayCell(String fragment) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics && _civilLabel(widget.properties.label, fragment),
);

bool _civilLabel(String? label, String fragment) {
  if (label == null) return false;
  final at = label.indexOf(fragment);
  if (at < 0) return false;
  if (at == 0) return true;
  final before = label.codeUnitAt(at - 1);
  return before < 0x30 || before > 0x39;
}

bool _dayEnabled(WidgetTester tester, String fragment) =>
    tester.widget<Semantics>(_dayCell(fragment)).properties.enabled ?? false;

bool _todayRing(WidgetTester tester, String fragment) {
  final material = tester.widget<Material>(
    find.descendant(of: _dayCell(fragment), matching: find.byType(Material)),
  );
  return (material.shape! as RoundedRectangleBorder).side.width > 0;
}
