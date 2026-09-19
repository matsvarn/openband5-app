import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/health.dart';
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
    );
  });
  tearDown(() => controller.dispose());

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
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
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: Scaffold(body: OpenBandHealth(controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('history covers exactly the requested nights, oldest first', () async {
    final points = await repo.readMetricHistory(MetricKey.hrv, '2026-09-15', 7);
    expect(points.map((p) => p.day), [
      '2026-09-09',
      '2026-09-10',
      '2026-09-11',
      '2026-09-12',
      '2026-09-13',
      '2026-09-14',
      '2026-09-15',
    ]);
    expect(points.last.value, isNotNull);
  });

  test('openBandDaysEnding crosses a month boundary', () {
    expect(openBandDaysEnding('2026-10-02', 3), [
      '2026-09-30',
      '2026-10-01',
      '2026-10-02',
    ]);
  });

  testWidgets('health hub renders light and dark', (tester) async {
    await mount(tester);
    expect(find.text('Gesundheit'), findsOneWidget);
    expect(find.text('7 Nächte'), findsWidgets);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/health-light.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/health-dark.png'),
    );
  });

  testWidgets('30 nights shows the observed count, never a filled gap', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('30 Nächte'));
    await tester.pumpAndSettle();
    expect(find.textContaining('von 30 Nächten'), findsWidgets);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/health-30.png'),
    );
  });

  testWidgets('missing night shows no values and no status', (tester) async {
    repo.scenario = SyntheticScenario.missing;
    await mount(tester);
    expect(find.text('Noch keine Werte'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/health-missing.png'),
    );
  });

  testWidgets('health hub at 2x reaches Laborwerte without overflow', (
    tester,
  ) async {
    final scrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    for (final width in [393.0, 375.0]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mount(tester, scale: 2, width: width);
      expect(find.text('Gesundheit'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final labs = find.byKey(const ValueKey('laborwerte'));
      await tester.scrollUntilVisible(labs, 300, scrollable: scrollable.first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(labs);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Vitamin B12'), findsOneWidget);
    }
  });
}
