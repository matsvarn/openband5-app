import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/gestures/device_action.dart';
import 'package:openstrap_edge/gestures/gesture_settings.dart';
import 'package:openstrap_edge/l10n/app_localizations.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/ui2/profile/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Inter')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/Inter/Inter.ttf').readAsBytesSync(),
          ),
        ),
      );
    await font.load();
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await icons.load();
  });

  Future<GestureSettings> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    bool phoneActions = true,
    double width = 393,
    double scale = 1,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = GestureSettings()
      ..supported = {
        DeviceAction.none,
        ...DeviceAction.values.where((a) => a.isInApp),
        if (phoneActions) ...{DeviceAction.ringPhone, DeviceAction.torch},
      };
    addTearDown(settings.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, width == 375 ? 812 : 852);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: openBandTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('gestures-capture'),
          child: ListenableBuilder(
            listenable: settings,
            builder: (context, _) => BandGesturesView(
              chosen: settings.doubleTap,
              supported: settings.supported,
              onPick: settings.setDoubleTap,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  for (final brightness in Brightness.values) {
    testWidgets('Alpin gestures ${brightness.name}', (tester) async {
      await mount(tester, brightness: brightness);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('gestures-capture')),
        matchesGoldenFile('openband_goldens/gestures-${brightness.name}.png'),
      );
    }, tags: const ['golden']);
  }

  testWidgets('selecting water persists the action shown as selected', (
    tester,
  ) async {
    final settings = await mount(tester);
    await tester.tap(find.text('Wasser protokollieren'));
    await tester.pumpAndSettle();
    expect(settings.doubleTap, DeviceAction.logWater);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('gesture_double_tap'), 'log_water');
    expect(
      find.bySemanticsLabel(
        RegExp('Wasser protokollieren.*Ausgewählt', caseSensitive: false),
      ),
      findsOneWidget,
    );
    await expectLater(
      find.byKey(const ValueKey('gestures-capture')),
      matchesGoldenFile('openband_goldens/gestures-saved.png'),
    );
  }, tags: const ['golden']);

  testWidgets('unavailable phone actions explain the missing choices', (
    tester,
  ) async {
    await mount(tester, phoneActions: false);
    expect(find.text('Mein Telefon klingeln lassen'), findsNothing);
    expect(find.text('Taschenlampe'), findsNothing);
    expect(find.text('Wasser protokollieren'), findsOneWidget);
    expect(find.text('Telefonaktionen nicht verfügbar'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('gestures-capture')),
      matchesGoldenFile('openband_goldens/gestures-unavailable.png'),
    );
  }, tags: const ['golden']);

  testWidgets('all choices remain reachable on a small phone with large text', (
    tester,
  ) async {
    final settings = await mount(tester, width: 375, scale: 2);
    await tester.scrollUntilVisible(find.text('Taschenlampe'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taschenlampe'));
    await tester.pumpAndSettle();
    expect(settings.doubleTap, DeviceAction.torch);
    expect(tester.takeException(), isNull);
  });
}
