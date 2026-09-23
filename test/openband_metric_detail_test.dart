import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/metric_detail.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
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

  late SyntheticOpenBandRepository repo;
  late OpenBandController controller;
  setUp(() {
    repo = SyntheticOpenBandRepository.fromMaps(
      jsonDecode(
            File(
              'docs/openband5/assets/fixtures/day-summary.json',
            ).readAsStringSync(),
          )
          as Map,
      jsonDecode(
            File(
              'docs/openband5/assets/fixtures/sleep-detail.json',
            ).readAsStringSync(),
          )
          as Map,
    );
    controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 18, 9, 41),
    );
  });
  tearDown(() => controller.dispose());

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    bool strain = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: OpenBandMetricDetail(
            controller: controller,
            metricKey: strain ? MetricKey.strain : MetricKey.hrv,
            label: strain ? 'Belastung' : 'HRV',
            subtitle: strain ? 'heute bis jetzt' : 'Herzratenvariabilität',
            unit: strain ? 'von 21' : 'ms',
            icon: strain ? LucideIcons.flame : LucideIcons.activity,
            color: strain ? (p) => p.strain : (p) => p.recovery,
            tint: strain ? (p) => p.strainTint : (p) => p.recoveryTint,
            digits: strain ? 1 : 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hrv detail routes to the night-scalar screen', (tester) async {
    await mount(tester);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('Nacht für Nacht'), findsOneWidget);
    expect(find.textContaining('von 30 Nächten'), findsOneWidget);
    expect(find.text('Nachtverlauf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('respiration detail routes to the night-scalar screen', (
    tester,
  ) async {
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: OpenBandMetricDetail(
          controller: controller,
          metricKey: MetricKey.respiration,
          label: 'Atmung',
          subtitle: 'Atemfrequenz',
          unit: '/min',
          icon: LucideIcons.wind,
          color: (p) => p.sleep,
          tint: (p) => p.sleepTint,
          digits: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('night-scalar-detail')), findsOneWidget);
    expect(find.text('ATMUNG'), findsWidgets);
    expect(find.text('Tag für Tag'), findsNothing);
    expect(find.text('Herzratenvariabilität'), findsNothing);
    await tester.scrollUntilVisible(find.text('Nachtverlauf'), 100);
    expect(find.text('Nachtverlauf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping 7 nights changes the observed count label', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('7 Nächte'));
    await tester.pumpAndSettle();
    expect(find.textContaining('von 7 Nächten'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('strain detail shows the day value without night rows', (
    tester,
  ) async {
    await mount(tester, strain: true);
    expect(find.text('1,6'), findsOneWidget);
    expect(find.text('Tag für Tag'), findsOneWidget);
    expect(find.textContaining('von 30 Tagen'), findsOneWidget);
    expect(find.text('Verlauf in der Nacht'), findsNothing);
    expect(find.text('So entsteht die Basis'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('strain missing scenario shows a dash hero', (tester) async {
    repo.scenario = SyntheticScenario.missing;
    await mount(tester, strain: true);
    expect(find.text('—'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing scenario shows dashes and no baseline', (tester) async {
    repo.scenario = SyntheticScenario.missing;
    await mount(tester);
    expect(find.text('—'), findsWidgets);
    expect(find.text('Noch kein Nachtwert'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching HRV to strain loads the generic day family', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Nachtverlauf'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: OpenBandMetricDetail(
          controller: controller,
          metricKey: MetricKey.strain,
          label: 'Belastung',
          subtitle: 'heute bis jetzt',
          unit: 'von 21',
          icon: LucideIcons.flame,
          color: (p) => p.strain,
          tint: (p) => p.strainTint,
          digits: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tag für Tag'), findsOneWidget);
    expect(find.text('Nachtverlauf'), findsNothing);
    expect(find.text('1,6'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
