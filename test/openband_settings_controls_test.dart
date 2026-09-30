import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/settings_controls.dart';
import 'package:openstrap_edge/openband/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
    ]) {
      final loader = FontLoader(family)
        ..addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        );
      await loader.load();
    }
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await icons.load();
  });

  Future<void> pumpRow(
    WidgetTester tester, {
    Widget? leading,
    String label = 'Nachtverlauf',
    String value = '23:10–06:54',
    double scale = 1,
    double width = 375,
    VoidCallback? onTap,
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
            body: Align(
              alignment: Alignment.topCenter,
              child: OBCard(
                padding: EdgeInsets.zero,
                child: OBSettingsValueRow(
                  leading: leading,
                  label: label,
                  value: value,
                  chevron: true,
                  mutedValue: true,
                  onTap: onTap ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget leadingTile() => Container(
    width: 36,
    height: 36,
    color: Colors.blue,
    key: const ValueKey('leading-tile'),
  );

  testWidgets('leading is 36px with 12 gap and keeps 56 min height', (
    tester,
  ) async {
    await pumpRow(tester, leading: leadingTile());
    expect(tester.getSize(find.byType(OBSettingsValueRow)).height, 56);
    final tile = tester.getRect(find.byKey(const ValueKey('leading-tile')));
    expect(tile.width, 36);
    expect(tile.height, 36);
    final label = tester.getRect(find.text('Nachtverlauf'));
    expect(label.left, closeTo(tile.right + 12, 0.5));
    final value = tester.getRect(find.text('23:10–06:54'));
    final chevron = tester.getRect(find.byIcon(LucideIcons.chevronRight));
    expect(chevron.left, closeTo(value.right + 12, 0.5));
    expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
  });

  testWidgets('2x leading stacks label/value beside icon with 8 gap', (
    tester,
  ) async {
    await pumpRow(tester, leading: leadingTile(), scale: 2, width: 375);
    final row = tester.getSize(find.byType(OBSettingsValueRow));
    expect(row.height, greaterThan(56));
    expect(tester.takeException(), isNull);
    final tile = tester.getRect(find.byKey(const ValueKey('leading-tile')));
    final label = tester.getRect(find.text('Nachtverlauf'));
    final value = tester.getRect(find.text('23:10–06:54'));
    expect(label.left, closeTo(tile.right + 12, 0.5));
    expect(value.top, greaterThanOrEqualTo(label.bottom));
    expect(value.left, closeTo(label.left, 0.5));
    expect(label.right, lessThanOrEqualTo(375));
    expect(value.right, lessThanOrEqualTo(375));
  });

  testWidgets('without leading existing compact row is unchanged', (
    tester,
  ) async {
    await pumpRow(tester, leading: null, label: 'Warnen unter', value: '15 %');
    expect(tester.getSize(find.byType(OBSettingsValueRow)).height, 56);
    expect(find.byKey(const ValueKey('leading-tile')), findsNothing);
    final value = tester.getRect(find.text('15 %'));
    final chevron = tester.getRect(find.byIcon(LucideIcons.chevronRight));
    expect(chevron.left, closeTo(value.right + 4, 0.5));
  });
}
