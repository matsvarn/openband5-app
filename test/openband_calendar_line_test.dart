import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/calendar_line.dart';
import 'package:openstrap_edge/openband/theme.dart';

void main() {
  const ink = Color(0xFF111111);
  const axis = Color(0xFF666666);
  const guide = Color(0xFFCCCCCC);

  OBCalendarLinePainter painter(
    List<double?> values, {
    bool zeroCentered = false,
    int days = 7,
  }) => OBCalendarLinePainter(
    values: values,
    days: days,
    zeroCentered: zeroCentered,
    ink: ink,
    axis: axis,
    guide: guide,
    textScaler: TextScaler.noScaling,
  );

  test('absolute and zero-centered domains are generic numeric extents', () {
    expect(painter([75.4, 75.0, 74.9]).domain(), (74.0, 76.0));
    expect(painter([-0.2, 0.4], zeroCentered: true).domain(), (-1.0, 1.0));
    expect(painter([null, double.nan, double.infinity]).domain(), isNull);
  });

  test(
    'axis labels preserve decimal comma and signed zero-centered labels',
    () {
      expect(OBCalendarLinePainter.axisLabel(75.5), '75,5');
      expect(OBCalendarLinePainter.axisLabel(1, signed: true), '+1');
      expect(OBCalendarLinePainter.axisLabel(-1, signed: true), '−1');
      expect(OBCalendarLinePainter.axisLabel(0, signed: true), '0');
    },
  );

  testWidgets('keeps chart size while hidden and exposes calendar slots', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: const Scaffold(
          body: OBCalendarLine(
            values: [75, null, 75.2, double.nan, 75.1, null, 75],
            days: 7,
            visible: false,
          ),
        ),
      ),
    );
    final line = tester.widget<OBCalendarLine>(find.byType(OBCalendarLine));
    expect(line.values, hasLength(7));
    expect(line.values[1], isNull);
    expect(tester.getSize(find.byType(OBCalendarLine)).height, 120);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is OBCalendarLinePainter,
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });
}
