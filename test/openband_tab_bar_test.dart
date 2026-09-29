import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/release_scope.dart';
import 'package:openstrap_edge/openband/tab_bar.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';

Widget _bar(
  Brightness brightness, {
  double textScale = 1,
  ValueChanged<ShellDomain>? onSelect,
}) => MaterialApp(
  theme: openBandTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: RepaintBoundary(
            key: const ValueKey('bar-golden'),
            child: OBTabBar(
              domains: kOpenBandReleaseDomains,
              selected: ShellDomain.home,
              onSelect: onSelect ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  testWidgets('four reachable, labelled tab targets survive large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 180);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    ShellDomain? tapped;
    await tester.pumpWidget(
      _bar(
        Brightness.light,
        textScale: 2,
        onSelect: (domain) => tapped = domain,
      ),
    );
    for (final (domain, label, index) in [
      ('home', 'Heute', 1),
      ('sleep', 'Schlaf', 2),
      ('workout', 'Training', 3),
      ('wellness', 'Journal', 4),
    ]) {
      final tab = find.byKey(ValueKey('ob-tab-$domain'));
      expect(tab, findsOneWidget);
      expect(tester.getSize(tab).height, greaterThanOrEqualTo(44));
      expect(
        find.bySemanticsLabel('$label, Tab, $index von 4'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(tab).flagsCollection.isSelected.toBoolOrNull(),
        index == 1,
      );
    }
    await tester.tap(find.byKey(const ValueKey('ob-tab-sleep')));
    expect(tapped, ShellDomain.sleep);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('floating bar matches the light and dark references', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(786, 360);
    addTearDown(tester.view.reset);
    for (final (brightness, name) in [
      (Brightness.light, 'light'),
      (Brightness.dark, 'dark'),
    ]) {
      await tester.pumpWidget(_bar(brightness));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('bar-golden')),
        matchesGoldenFile('openband_goldens/openband_tab_bar_$name.png'),
      );
    }
  }, tags: const ['golden']);
}
