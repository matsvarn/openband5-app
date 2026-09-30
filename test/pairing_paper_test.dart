import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/ui2/onboarding/pairing.dart';

Future<void> _pump(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  double width = 393,
  double height = 852,
  double scale = 1,
  VoidCallback? onPair,
  VoidCallback? onSkip,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      locale: const Locale('de'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('de')],
      theme: openBandTheme(
        Brightness.light,
      ).copyWith(platform: TargetPlatform.iOS),
      darkTheme: openBandTheme(
        Brightness.dark,
      ).copyWith(platform: TargetPlatform.iOS),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(top: 59, bottom: 34),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: RepaintBoundary(
        key: const ValueKey('capture'),
        child: PairingView(
          phase: PairPhase.idle,
          onPair: onPair ?? () {},
          onSkip: onSkip ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

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

  testWidgets('Paper pairing light and dark', (tester) async {
    await _pump(tester);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/pairing-light.png'),
    );
    await _pump(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/pairing-dark.png'),
    );
    expect(tester.getSize(find.byTooltip('Zurück')).height, 44);
    expect(tester.getSize(find.byTooltip('Information')).height, 44);
  });

  testWidgets('mini at 2x scrolls without squeezing actions', (tester) async {
    var pairs = 0;
    var skips = 0;
    await _pump(
      tester,
      width: 375,
      height: 812,
      scale: 2,
      onPair: () => pairs++,
      onSkip: () => skips++,
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'Verbinden')).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester
          .getSize(find.widgetWithText(TextButton, 'Später verbinden'))
          .height,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(find.text('Verbinden'));
    await tester.tap(find.text('Später verbinden'));
    expect(pairs, 1);
    expect(skips, 1);
    await tester.drag(find.byType(ListView), const Offset(0, -250));
    await tester.pump();
    expect(find.text('WHOOP-App schließen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
