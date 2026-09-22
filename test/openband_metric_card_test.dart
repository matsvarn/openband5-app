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
import 'package:openstrap_edge/openband/screens.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';

import '../integration_test/openband_review_test.dart'
    show
        reviewCaptureFilter,
        reviewEnsureRequestedCaptures,
        reviewPumpPageTransitions,
        reviewTapHeaderBack;

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

  const trustedHrv = StoredNightBaseline(
    value: kNightScalarPaperHrvBaseline,
    status: kNightScalarTrustedBaseline,
  );
  const trustedRhr = StoredNightBaseline(
    value: kNightScalarPaperRhrBaseline,
    status: kNightScalarTrustedBaseline,
  );

  DayMetric hrvOf(
    NightScalarState state, {
    double? value,
    StoredNightBaseline? baseline,
  }) =>
      dayMetricFromNightScalar(state: state, value: value, baseline: baseline);

  DayMetric rhrOf(
    NightScalarState state, {
    double? value,
    StoredNightBaseline? baseline,
  }) =>
      dayMetricFromNightScalar(state: state, value: value, baseline: baseline);

  Future<void> mountPair(
    WidgetTester tester, {
    required DayMetric hrv,
    required DayMetric rhr,
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 400,
    VoidCallback? onHrv,
    VoidCallback? onRhr,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: openBandTheme(brightness).scaffoldBackgroundColor,
          body: RepaintBoundary(
            key: const ValueKey('capture'),
            child: Builder(
              builder: (context) {
                final p = OB.of(context);
                return ColoredBox(
                  color: p.canvas,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: OBAdaptiveValues(
                      children: [
                        OBMetricCard(
                          label: 'HRV',
                          unit: 'ms',
                          metric: hrv,
                          icon: LucideIcons.activity,
                          color: p.recovery,
                          onTap: onHrv,
                        ),
                        OBMetricCard(
                          label: 'Ruhepuls',
                          unit: '/min',
                          metric: rhr,
                          icon: LucideIcons.heart,
                          color: p.pulse,
                          onTap: onRhr,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> expectPairGolden(
    WidgetTester tester,
    String name, {
    required DayMetric hrv,
    required DayMetric rhr,
    double scale = 1,
    double width = 393,
    double height = 400,
  }) async {
    await mountPair(
      tester,
      hrv: hrv,
      rhr: rhr,
      width: width,
      height: height,
      scale: scale,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/metric-card-$name-light.png'),
    );
    await mountPair(
      tester,
      hrv: hrv,
      rhr: rhr,
      width: width,
      height: height,
      scale: scale,
      brightness: Brightness.dark,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/metric-card-$name-dark.png'),
    );
  }

  testWidgets('trusted current shows delta, not a unit-less emdash', (
    tester,
  ) async {
    await expectPairGolden(
      tester,
      'trusted',
      hrv: hrvOf(NightScalarState.current, value: 48, baseline: trustedHrv),
      rhr: rhrOf(NightScalarState.current, value: 54, baseline: trustedRhr),
    );
    await mountPair(
      tester,
      hrv: hrvOf(NightScalarState.current, value: 48, baseline: trustedHrv),
      rhr: rhrOf(NightScalarState.current, value: 54, baseline: trustedRhr),
    );
    expect(find.text('48'), findsOneWidget);
    expect(find.text('ms'), findsOneWidget);
    expect(find.text('+8 über Basis'), findsOneWidget);
    expect(find.text('54'), findsOneWidget);
    expect(find.text('/min'), findsOneWidget);
    expect(find.text('−2 unter Basis'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('equality uses wie Basis in the metric color row', (
    tester,
  ) async {
    await mountPair(
      tester,
      hrv: hrvOf(NightScalarState.current, value: 40, baseline: trustedHrv),
      rhr: rhrOf(NightScalarState.current, value: 56, baseline: trustedRhr),
    );
    expect(find.text('wie Basis'), findsNWidgets(2));
    expect(find.text('Kein Nachtwert'), findsNothing);
  });

  testWidgets('current without a trusted baseline has no comparison row', (
    tester,
  ) async {
    await expectPairGolden(
      tester,
      'no-baseline',
      hrv: hrvOf(NightScalarState.current, value: 48),
      rhr: rhrOf(
        NightScalarState.current,
        value: 54,
        baseline: const StoredNightBaseline(value: 56, status: 'provisional'),
      ),
    );
    await mountPair(
      tester,
      hrv: hrvOf(NightScalarState.current, value: 48),
      rhr: rhrOf(
        NightScalarState.current,
        value: 54,
        baseline: const StoredNightBaseline(value: 56, status: 'provisional'),
      ),
    );
    expect(find.text('48'), findsOneWidget);
    expect(find.text('54'), findsOneWidget);
    expect(find.textContaining('Basis'), findsNothing);
  });

  testWidgets('missing shows Kein Nachtwert and emdash without a unit', (
    tester,
  ) async {
    await expectPairGolden(
      tester,
      'missing',
      hrv: hrvOf(NightScalarState.missing),
      rhr: rhrOf(NightScalarState.missing),
    );
    await mountPair(
      tester,
      hrv: hrvOf(NightScalarState.missing),
      rhr: rhrOf(NightScalarState.missing),
    );
    expect(find.text('Kein Nachtwert'), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('ms'), findsNothing);
    expect(find.text('/min'), findsNothing);
  });

  testWidgets('partial keeps the value and a muted Unvollständig row', (
    tester,
  ) async {
    await expectPairGolden(
      tester,
      'partial',
      hrv: hrvOf(NightScalarState.partial, value: 48),
      rhr: rhrOf(NightScalarState.partial, value: 54),
    );
    await mountPair(
      tester,
      hrv: hrvOf(NightScalarState.partial, value: 48),
      rhr: rhrOf(NightScalarState.partial, value: 54),
    );
    expect(find.text('Unvollständig'), findsNWidgets(2));
    expect(find.text('48'), findsOneWidget);
    expect(find.textContaining('Basis'), findsNothing);
  });

  testWidgets('pending withholds the value', (tester) async {
    await expectPairGolden(
      tester,
      'pending',
      hrv: hrvOf(NightScalarState.pending, value: 48),
      rhr: rhrOf(NightScalarState.pending, value: 54),
    );
    await mountPair(
      tester,
      hrv: hrvOf(NightScalarState.pending, value: 48),
      rhr: rhrOf(NightScalarState.pending, value: 54),
    );
    expect(find.text(kNightScalarPendingLabel), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('48'), findsNothing);
    expect(find.text('ms'), findsNothing);
  });

  testWidgets('failed withholds the value', (tester) async {
    await expectPairGolden(
      tester,
      'failed',
      hrv: hrvOf(NightScalarState.failed),
      rhr: rhrOf(NightScalarState.failed),
    );
    await mountPair(
      tester,
      hrv: hrvOf(NightScalarState.failed),
      rhr: rhrOf(NightScalarState.failed),
    );
    expect(find.text(kNightScalarFailedLabel), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('ms'), findsNothing);
  });

  testWidgets('older keeps the value without a comparison', (tester) async {
    await expectPairGolden(
      tester,
      'older',
      hrv: hrvOf(NightScalarState.older, value: 48),
      rhr: rhrOf(NightScalarState.older, value: 54),
    );
    await mountPair(
      tester,
      hrv: hrvOf(NightScalarState.older, value: 48),
      rhr: rhrOf(NightScalarState.older, value: 54),
    );
    expect(find.text('Ältere Berechnung'), findsNWidgets(2));
    expect(find.text('48'), findsOneWidget);
    expect(find.textContaining('Basis'), findsNothing);
  });

  testWidgets('unreadable withholds the value', (tester) async {
    await expectPairGolden(
      tester,
      'unreadable',
      hrv: hrvOf(NightScalarState.unreadable),
      rhr: rhrOf(NightScalarState.unreadable),
    );
    await mountPair(
      tester,
      hrv: hrvOf(NightScalarState.unreadable),
      rhr: rhrOf(NightScalarState.unreadable),
    );
    expect(find.text('Nicht lesbar'), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('ms'), findsNothing);
  });

  testWidgets('unknown and outdated share Auswertung offen without a value', (
    tester,
  ) async {
    await expectPairGolden(
      tester,
      'open',
      hrv: hrvOf(NightScalarState.unknown),
      rhr: rhrOf(NightScalarState.outdated),
    );
    await mountPair(
      tester,
      hrv: hrvOf(NightScalarState.unknown),
      rhr: rhrOf(NightScalarState.outdated),
    );
    expect(find.text(kNightScalarOpenLabel), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('ms'), findsNothing);
    expect(find.text('/min'), findsNothing);
  });

  testWidgets('375 at 2x uses full-width cards without shrinking text', (
    tester,
  ) async {
    await expectPairGolden(
      tester,
      'large',
      hrv: hrvOf(NightScalarState.current, value: 48, baseline: trustedHrv),
      rhr: rhrOf(NightScalarState.current, value: 54, baseline: trustedRhr),
      width: 375,
      height: 520,
      scale: 2,
    );
    await mountPair(
      tester,
      hrv: hrvOf(NightScalarState.current, value: 48, baseline: trustedHrv),
      rhr: rhrOf(NightScalarState.current, value: 54, baseline: trustedRhr),
      width: 375,
      height: 520,
      scale: 2,
    );
    expect(find.text('+8 über Basis'), findsOneWidget);
    expect(find.text('−2 unter Basis'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(OBMetricCard).first).width, 343);
  });

  testWidgets('narrow 320 stacks value and unit when they cannot share a row', (
    tester,
  ) async {
    await mountPair(
      tester,
      hrv: hrvOf(NightScalarState.current, value: 48, baseline: trustedHrv),
      rhr: rhrOf(NightScalarState.current, value: 54, baseline: trustedRhr),
      width: 320,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/metric-card-narrow-320.png'),
    );
    expect(find.text('48'), findsOneWidget);
    expect(find.text('Ruhepuls'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-night DayMetric keeps a concise value and trusted delta', (
    tester,
  ) async {
    await mountPair(
      tester,
      hrv: const DayMetric(48, baseline: 40),
      rhr: const DayMetric.missing(),
    );
    expect(find.text('48'), findsOneWidget);
    expect(find.text('+8 über Basis'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Kein Nachtwert'), findsNothing);
    expect(find.text('Basis noch offen'), findsNothing);
  });

  testWidgets('tapping the overview HRV card opens night scalar detail', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = SyntheticOpenBandRepository.fromMaps(
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
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 18, 9, 41),
    );
    addTearDown(controller.dispose);
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
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: AppShell(
          builder: (c, d) => d == ShellDomain.home
              ? OpenBandOverview(controller: controller, onSync: () {})
              : Center(child: Text(d.label)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('HRV · MS'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('night-scalar-detail')), findsOneWidget);
    expect(find.text('HRV'), findsWidgets);
  });

  testWidgets('header back brings a scrolled Sleep control on-screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: ListView(
                      children: [
                        const OBPageHeader(title: 'Schlaf', subtitle: ''),
                        const SizedBox(height: 720),
                        Builder(
                          builder: (inner) => TextButton(
                            onPressed: () => Navigator.of(inner).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const Scaffold(
                                  body: OBPageHeader(
                                    title: 'Ruhepuls',
                                    subtitle: '',
                                  ),
                                ),
                              ),
                            ),
                            child: const Text('open'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              child: const Text('sleep'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('sleep'));
    await tester.pump();
    await reviewPumpPageTransitions(tester);
    await tester.scrollUntilVisible(find.text('open'), 200);
    await tester.tap(find.text('open'));
    await tester.pump();
    await reviewPumpPageTransitions(tester);
    expect(find.text('Ruhepuls'), findsOneWidget);
    await reviewTapHeaderBack(tester);
    expect(find.text('Ruhepuls'), findsNothing);
    expect(find.text('open'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('open'), 200);
    expect(find.byTooltip('Zurück').hitTestable(), findsNothing);
    await reviewTapHeaderBack(tester);
    expect(find.text('Schlaf'), findsNothing);
    expect(find.text('sleep'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('omitted capture selection keeps every checkpoint', () {
    expect(reviewCaptureFilter(''), isNull);
    reviewEnsureRequestedCaptures(null, const <String>[]);
    reviewEnsureRequestedCaptures(null, const ['night-cards-overview-light']);
  });

  test('valid capture subset is exact names after trim', () {
    expect(
      reviewCaptureFilter('night-cards-overview-light, night-cards-sleep-2x'),
      {'night-cards-overview-light', 'night-cards-sleep-2x'},
    );
    reviewEnsureRequestedCaptures(
      {'night-cards-overview-light', 'night-cards-sleep-2x'},
      const [
        'night-cards-overview-light',
        'night-cards-sleep-2x',
        'night-cards-overview-dark',
      ],
    );
  });

  test('typo in requested captures fails after the run', () {
    expect(reviewCaptureFilter('night-cards-overveiw-light'), {
      'night-cards-overveiw-light',
    });
    expect(
      () => reviewEnsureRequestedCaptures(
        {'night-cards-overveiw-light', 'night-cards-sleep-2x'},
        const ['night-cards-sleep-2x'],
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('night-cards-overveiw-light'),
        ),
      ),
    );
  });

  test('whitespace-only capture selection is refused', () {
    expect(
      () => reviewCaptureFilter('   '),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('OPENBAND_REVIEW_CAPTURES is empty'),
        ),
      ),
    );
    expect(() => reviewCaptureFilter(', ,'), throwsA(isA<StateError>()));
  });
}
