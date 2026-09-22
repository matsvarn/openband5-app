import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/alp_tokens.dart';
import 'package:openstrap_edge/openband/settings_controls.dart';
import 'package:openstrap_edge/openband/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpRow(
    WidgetTester tester, {
    String label = 'Eigenes Schlafziel',
    String value = '',
    bool chevron = true,
    bool comfortable = false,
    bool interactive = true,
    VoidCallback? onTap,
    double scale = 1,
    double width = 375,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(scale),
            devicePixelRatio: 1,
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Align(
              alignment: Alignment.topCenter,
              child: ColoredBox(
                color: const Color(0xFFEEEEEE),
                child: OBCard(
                  padding: EdgeInsets.zero,
                  child: OBSettingsValueRow(
                    label: label,
                    value: value,
                    chevron: chevron,
                    comfortable: comfortable,
                    interactive: interactive,
                    onTap: onTap,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('compact default is 56pt with 10/14 padding', (tester) async {
    await pumpRow(tester, label: 'Warnen unter', value: '15 %', onTap: () {});
    expect(tester.getSize(find.byType(OBSettingsValueRow)).height, 56);
    final padding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(OBSettingsValueRow),
        matching: find.byType(Padding),
      ),
    );
    expect(
      padding.padding,
      const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
    );
    final labelStyle = tester.widget<Text>(find.text('Warnen unter')).style;
    expect(labelStyle?.fontSize, 15);
    expect(labelStyle?.fontWeight, FontWeight.w500);
    expect(labelStyle?.height, 1.36);
    expect(tester.widget<InkWell>(find.byType(InkWell)).borderRadius, isNull);
  });

  testWidgets('comfortable empty 2x stays inline and wraps', (tester) async {
    var taps = 0;
    final semantics = tester.ensureSemantics();
    try {
      await pumpRow(tester, comfortable: true, scale: 2, onTap: () => taps++);
      final row = tester.getSize(find.byType(OBSettingsValueRow));
      expect(row.height, greaterThanOrEqualTo(64));
      expect(row.height, greaterThanOrEqualTo(44));

      final padding = tester.widget<Padding>(
        find.descendant(
          of: find.byType(OBSettingsValueRow),
          matching: find.byType(Padding),
        ),
      );
      expect(
        padding.padding,
        const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      );
      final labelStyle = tester
          .widget<Text>(find.text('Eigenes Schlafziel'))
          .style;
      expect(labelStyle?.fontSize, 15);
      expect(labelStyle?.fontWeight, FontWeight.w500);
      expect(labelStyle?.height, 20 / 15);
      expect(
        tester.widget<InkWell>(find.byType(InkWell)).borderRadius,
        BorderRadius.circular(AlpRadius.card),
      );

      final label = tester.getRect(find.text('Eigenes Schlafziel'));
      final chevron = tester.getRect(find.byIcon(LucideIcons.chevronRight));
      expect(label.height, greaterThan(40));
      expect(chevron.left, greaterThan(label.left));
      expect(chevron.top, lessThan(label.bottom));
      expect(chevron.bottom, greaterThan(label.top));
      expect(chevron.width, 18);
      expect(chevron.height, 18);

      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(OBSettingsValueRow),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, Colors.transparent);

      final node = tester.getSemantics(find.byType(InkWell));
      expect(node.label, contains('Eigenes Schlafziel'));
      expect(node.flagsCollection.isButton, isTrue);

      await tester.tap(find.byType(OBSettingsValueRow));
      expect(taps, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('compact empty 2x keeps chevron in trailing lane', (tester) async {
    var taps = 0;
    await pumpRow(
      tester,
      label: 'Bei App-Mitteilungen vibrieren',
      scale: 2,
      onTap: () => taps++,
    );
    expect(tester.getSize(find.byType(OBSettingsValueRow)).height, greaterThanOrEqualTo(56));
    final label = tester.getRect(find.text('Bei App-Mitteilungen vibrieren'));
    final chevron = tester.getRect(find.byIcon(LucideIcons.chevronRight));
    expect(label.height, greaterThan(40));
    expect(chevron.left, greaterThan(label.left));
    expect(chevron.top, lessThan(label.bottom));
    expect(chevron.bottom, greaterThan(label.top));
    expect(chevron.width, 18);
    expect(chevron.height, 18);
    await tester.tap(find.byType(OBSettingsValueRow));
    expect(taps, 1);
  });

  testWidgets('393 empty long label stays inline and taps', (tester) async {
    var taps = 0;
    await pumpRow(
      tester,
      label: 'Bei App-Mitteilungen vibrieren',
      width: 393,
      onTap: () => taps++,
    );
    expect(
      tester.getSize(find.byType(OBSettingsValueRow)).height,
      greaterThanOrEqualTo(56),
    );
    final label = tester.getRect(find.text('Bei App-Mitteilungen vibrieren'));
    final chevron = tester.getRect(find.byIcon(LucideIcons.chevronRight));
    expect(chevron.left, greaterThan(label.left));
    expect(chevron.top, lessThan(label.bottom));
    expect(chevron.bottom, greaterThan(label.top));
    expect(chevron.width, 18);
    expect(chevron.height, 18);
    await tester.tap(find.byType(OBSettingsValueRow));
    expect(taps, 1);
  });

  testWidgets('comfortable nonempty 2x keeps compact stacking', (tester) async {
    await pumpRow(
      tester,
      label: 'Warnen unter',
      value: '15 %',
      comfortable: true,
      scale: 2,
      onTap: () {},
    );
    final label = tester.getRect(find.text('Warnen unter'));
    final value = tester.getRect(find.text('15 %'));
    expect(value.top, greaterThanOrEqualTo(label.bottom));
    expect(value.left, closeTo(label.left, 0.5));
  });

  testWidgets('disabled row does not tap', (tester) async {
    var taps = 0;
    await pumpRow(tester, interactive: false, onTap: () => taps++);
    await tester.tap(find.byType(OBSettingsValueRow), warnIfMissed: false);
    expect(taps, 0);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('375 2x weekday toggle stacks without overflow', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(375, 800),
            textScaler: TextScaler.linear(2),
            devicePixelRatio: 1,
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: OBCard(
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OBSettingsToggleRow(
                      label: 'Donnerstag',
                      value: true,
                      onToggle: () {},
                    ),
                    OBScheduleTimeToggleRow(
                      weekday: 'Donnerstag',
                      enabled: true,
                      timeLabel: '07:00',
                      onToggle: () {},
                      onPickTime: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final toggle = tester.getSize(find.byType(OBSettingsToggleRow));
    final schedule = tester.getSize(find.byType(OBScheduleTimeToggleRow));
    expect(toggle.width, 375);
    expect(schedule.width, 375);
    // Stacked large-text layout is taller scrollable content, not a flex clip.
    expect(toggle.height, greaterThan(56));
    expect(schedule.height, greaterThan(64));

    final toggleLabel = tester.getRect(find.text('Donnerstag').first);
    expect(toggleLabel.left, greaterThanOrEqualTo(0));
    expect(toggleLabel.right, lessThanOrEqualTo(375));
    final scheduleLabel = tester.getRect(find.text('Donnerstag').last);
    final time = tester.getRect(find.text('07:00'));
    expect(time.top, greaterThanOrEqualTo(scheduleLabel.bottom));
    expect(time.right, lessThanOrEqualTo(375));
  });
}
