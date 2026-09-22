import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/health.dart';
import 'package:openstrap_edge/openband/night_scalar_detail.dart';
import 'package:openstrap_edge/openband/night_signals.dart';
import 'package:openstrap_edge/openband/sleep_editor.dart';
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
      initialDay: kNightScalarPaperDay,
      band: repo.band,
      now: () => DateTime(2026, 9, 18, 9, 41),
    );
  });
  tearDown(() => controller.dispose());

  Future<void> mountHealth(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    Size size = const Size(393, 852),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
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
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(body: OpenBandHealth(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mountDetail(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    Size size = const Size(393, 852),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
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
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: OpenBandNightScalarDetail(
            controller: controller,
            metricKey: MetricKey.respiration,
            label: 'Atmung',
            unit: '/min',
            icon: LucideIcons.wind,
            color: (p) => p.sleep,
            tint: (p) => p.sleepTint,
            digits: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder detailText(String text) => find.descendant(
    of: find.byKey(const ValueKey('night-scalar-detail')),
    matching: find.text(text),
  );

  Finder cardText(String text) => find.descendant(
    of: find.byKey(const ValueKey('atemfrequenz')),
    matching: find.text(text),
  );

  void seedPaper({
    NightScalarRow? selected,
    Map<String, NightScalarRow>? matching,
    Map<String, NightScalarJob> sleepJobs = const {},
    Map<String, NightScalarJob> napJobs = const {},
    NightScalarEnvelope? envelope,
  }) {
    repo.seedNightScalarDetail(
      key: MetricKey.respiration,
      selected:
          selected ??
          NightScalarRow(
            day: kNightScalarPaperDay,
            algoVersion: kAlgoVersion,
            value: kNightScalarPaperRespRate,
            computedAtMs: DateTime(2026, 9, 15, 7, 2).millisecondsSinceEpoch,
            sleepSource: 'auto',
            deviceFamily: 'gen5',
            envelope: envelope,
            windowStartMs: DateTime(2026, 9, 14, 23, 10).millisecondsSinceEpoch,
            windowEndMs: DateTime(2026, 9, 15, 6, 54).millisecondsSinceEpoch,
          ),
      matching: matching ?? _paperResp(),
      sleepJobs: sleepJobs,
      napJobs: napJobs,
      currentAlgo: kAlgoVersion,
    );
  }

  testWidgets('Health Atemfrequenz opens Atmung, night curve, then back', (
    tester,
  ) async {
    seedPaper();
    await mountHealth(tester);
    expect(find.text('Atemfrequenz'), findsOneWidget);
    expect(cardText('16,0'), findsOneWidget);
    expect(cardText('/min'), findsOneWidget);
    expect(find.text('Deaktiviert'), findsNothing);
    expect(find.text('Bald'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('atemfrequenz')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('night-scalar-detail')), findsOneWidget);
    expect(detailText('Atmung'), findsOneWidget);
    expect(detailText('16,0'), findsOneWidget);
    expect(detailText('HRV'), findsNothing);
    expect(detailText('Ruhepuls'), findsNothing);
    expect(detailText('RMSSD'), findsNothing);
    expect(find.text('Herzratenvariabilität'), findsNothing);
    await tester.tap(find.text('Nachtverlauf'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandNightSignals), findsOneWidget);
    final tabs = tester.widget<OBSegmented>(
      find.byWidgetPredicate(
        (widget) =>
            widget is OBSegmented &&
            widget.labels.contains('Puls') &&
            widget.labels.contains('Atmung'),
      ),
    );
    expect(tabs.selected, NightSignalKind.respiration.index);
    expect(find.text('Puls'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandNightSignals), findsNothing);
    expect(detailText('16,0'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('night-scalar-detail')), findsNothing);
    expect(find.text('Atemfrequenz'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('decimal value and baseline comparison stay exact', (
    tester,
  ) async {
    final selected = NightScalarRow(
      day: kNightScalarPaperDay,
      algoVersion: kAlgoVersion,
      value: 16.5,
      baseline: const StoredNightBaseline(value: 16.1, status: 'trusted'),
      windowStartMs: DateTime(2026, 9, 14, 23, 10).millisecondsSinceEpoch,
      windowEndMs: DateTime(2026, 9, 15, 6, 54).millisecondsSinceEpoch,
    );
    final matching = _paperResp()
      ..[kNightScalarPaperDay] = NightScalarRow(
        day: kNightScalarPaperDay,
        algoVersion: kAlgoVersion,
        value: 16.5,
      );
    seedPaper(selected: selected, matching: matching);
    await mountHealth(tester);
    expect(cardText('16,5'), findsOneWidget);
    expect(cardText('+0,4 über Basis'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('atemfrequenz')));
    await tester.pumpAndSettle();
    expect(detailText('16,5'), findsOneWidget);
    expect(detailText('+0,4 über Basis'), findsOneWidget);
    expect(detailText('Basis 16,1\u00A0/min'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('main light and dark match Paper 16/min with real gaps', (
    tester,
  ) async {
    seedPaper();
    await mountDetail(tester);
    expect(detailText('Atmung'), findsOneWidget);
    expect(detailText('16,0'), findsOneWidget);
    expect(detailText('DI., 15. SEPT.'), findsOneWidget);
    expect(detailText('Basis noch offen'), findsOneWidget);
    expect(detailText('15 von 30 Nächten'), findsOneWidget);
    expect(detailText('Nachtverlauf'), findsOneWidget);
    final chart = tester.widget<NightScalarChart>(
      find.byType(NightScalarChart),
    );
    expect(chart.bars, hasLength(30));
    expect(chart.bars.take(15).every((bar) => bar.value == null), isTrue);
    expect(chart.bars.skip(15).every((bar) => bar.value != null), isTrue);
    expect(find.textContaining('23:10'), findsOneWidget);
    expect(find.text('+8 über Basis'), findsNothing);
    expect(find.textContaining('Normalbereich'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/resp-main.png'),
    );
    await mountDetail(tester, brightness: Brightness.dark);
    expect(detailText('16,0'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/resp-dark.png'),
    );
  });

  testWidgets('7 and 90 ranges keep the stored 16 and actual counts', (
    tester,
  ) async {
    seedPaper();
    await mountDetail(tester);
    await tester.tap(find.text('7 Nächte'));
    await tester.pumpAndSettle();
    expect(find.textContaining('von 7 Nächten'), findsOneWidget);
    expect(detailText('16,0'), findsOneWidget);
    await tester.tap(find.text('90 Nächte'));
    await tester.pumpAndSettle();
    expect(find.text('15 von 90 Nächten'), findsOneWidget);
    expect(detailText('16,0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full missing is a dash, not a borrowed prior or RHR', (
    tester,
  ) async {
    repo.seedNightScalarDetail(
      key: MetricKey.respiration,
      selected: null,
      matching: const {},
      currentAlgo: kAlgoVersion,
    );
    await mountDetail(tester);
    expect(detailText('Noch kein Nachtwert'), findsOneWidget);
    expect(detailText('0 von 30 Nächten'), findsOneWidget);
    expect(detailText('16,0'), findsNothing);
    expect(detailText('HRV'), findsNothing);
    expect(detailText('Ruhepuls'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/resp-missing.png'),
    );
    await mountDetail(tester, brightness: Brightness.dark);
    expect(detailText('0 von 30 Nächten'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/resp-missing-dark.png'),
    );
  });

  testWidgets('missing compact card stays a dash', (tester) async {
    repo.seedNightScalarDetail(
      key: MetricKey.respiration,
      selected: null,
      matching: const {},
      currentAlgo: kAlgoVersion,
    );
    await mountHealth(tester);
    expect(cardText('—'), findsOneWidget);
    expect(cardText('16,0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial selected keeps 16 without a delta', (tester) async {
    final matching = _paperResp();
    matching[kNightScalarPaperDay] = NightScalarRow(
      day: kNightScalarPaperDay,
      algoVersion: kAlgoVersion,
      value: kNightScalarPaperRespRate,
      partial: true,
    );
    seedPaper(
      selected: NightScalarRow(
        day: kNightScalarPaperDay,
        algoVersion: kAlgoVersion,
        value: kNightScalarPaperRespRate,
        partial: true,
        windowStartMs: DateTime(2026, 9, 14, 23, 10).millisecondsSinceEpoch,
        windowEndMs: DateTime(2026, 9, 15, 6, 54).millisecondsSinceEpoch,
      ),
      matching: matching,
    );
    await mountDetail(tester);
    expect(detailText('Unvollständige Nacht'), findsOneWidget);
    expect(detailText('16,0'), findsOneWidget);
    expect(find.textContaining('teils unvollständig'), findsOneWidget);
    expect(find.text('+8 über Basis'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/resp-partial.png'),
    );
    await mountDetail(tester, brightness: Brightness.dark);
    expect(detailText('Unvollständige Nacht'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/resp-partial-dark.png'),
    );
  });

  testWidgets('pending withholds 16; failed is not a successful calculation', (
    tester,
  ) async {
    seedPaper(
      sleepJobs: {
        kNightScalarPaperDay: const NightScalarJob(
          day: kNightScalarPaperDay,
          status: 'pending',
        ),
      },
    );
    await mountDetail(tester);
    expect(detailText('Auswertung läuft'), findsOneWidget);
    expect(detailText('16,0'), findsNothing);
    expect(find.text('Schlafzeiten ändern'), findsNothing);

    repo.seedNightScalarDetail(
      key: MetricKey.respiration,
      selected: NightScalarRow(
        day: kNightScalarPaperDay,
        algoVersion: kAlgoVersion,
        value: kNightScalarPaperRespRate,
        computedAtMs: DateTime(2026, 9, 15, 7, 2).millisecondsSinceEpoch,
        sleepSource: 'auto',
        deviceFamily: 'gen5',
        windowStartMs: DateTime(2026, 9, 14, 23, 10).millisecondsSinceEpoch,
        windowEndMs: DateTime(2026, 9, 15, 6, 54).millisecondsSinceEpoch,
      ),
      matching: _paperResp(),
      sleepJobs: {
        kNightScalarPaperDay: const NightScalarJob(
          day: kNightScalarPaperDay,
          status: 'failed',
        ),
      },
      napJobs: {
        kNightScalarPaperDay: const NightScalarJob(
          day: kNightScalarPaperDay,
          status: 'failed',
        ),
      },
      currentAlgo: kAlgoVersion,
    );
    await mountDetail(tester);
    expect(detailText('Auswertung fehlgeschlagen'), findsOneWidget);
    expect(detailText('16,0'), findsNothing);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Zuletzt gespeichert'), findsOneWidget);
    expect(find.text('Schlaf ansehen'), findsOneWidget);
    await tester.tap(find.text('Schlaf ansehen'));
    await tester.pumpAndSettle();
    expect(find.byType(SleepEditor), findsOneWidget);
    expect(find.byType(OpenBandNightSignals), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read error retries without claiming HRV', (tester) async {
    seedPaper();
    repo.failNightScalarRead = true;
    await mountDetail(tester);
    expect(
      find.text('Nachtwerte konnten nicht geladen werden.'),
      findsOneWidget,
    );
    expect(find.text('Erneut'), findsOneWidget);
    expect(detailText('16,0'), findsNothing);
    expect(detailText('HRV'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/resp-error.png'),
    );
    await mountDetail(tester, brightness: Brightness.dark);
    expect(find.text('Erneut'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/resp-error-dark.png'),
    );
    repo.failNightScalarRead = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(detailText('16,0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('info says Atemfrequenz and only stored RSA fields', (
    tester,
  ) async {
    seedPaper();
    await mountDetail(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.text('Über Atmung'), findsOneWidget);
    expect(
      find.textContaining('Atemfrequenz · gespeicherter Wert'),
      findsOneWidget,
    );
    expect(find.textContaining('RMSSD'), findsNothing);
    expect(find.textContaining('Ruhepuls'), findsNothing);
    expect(find.textContaining('Qualitätswert'), findsNothing);
    expect(find.textContaining('Normalbereich'), findsNothing);
    expect(find.textContaining('gelernt'), findsNothing);
    expect(find.textContaining('0,5'), findsNothing);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();

    seedPaper(
      envelope: const NightScalarEnvelope(
        tier: 'HIGH',
        confidence: 0.8,
        inputsUsed: ['rr'],
        note: 'rsa ok',
        brpm: 16.5,
        peakHz: 0.275,
        power: 1.25,
        source: 'rr_spectrum',
      ),
    );
    await mountDetail(tester);
    expect(detailText('16,0'), findsOneWidget);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Stufe HIGH'), findsOneWidget);
    expect(find.textContaining('Qualitätswert 0,8 / 1'), findsOneWidget);
    expect(find.textContaining('Eingaben rr'), findsOneWidget);
    expect(find.textContaining('Hinweis: rsa ok'), findsOneWidget);
    expect(find.textContaining('RSA-Atemfrequenz 16,5 /min'), findsOneWidget);
    expect(find.textContaining('Spektralspitze 0,275 Hz'), findsOneWidget);
    expect(find.textContaining('Spektralleistung 1,25'), findsOneWidget);
    expect(find.textContaining('Methode rr_spectrum'), findsOneWidget);
    expect(find.textContaining('Unsicherheit'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('375, 320 and 2x keep the stored 16', (tester) async {
    seedPaper();
    for (final size in const [Size(375, 812), Size(320, 812)]) {
      await mountDetail(tester, size: size);
      expect(detailText('16,0'), findsOneWidget);
      expect(detailText('15 von 30 Nächten'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await mountDetail(tester, scale: 2, size: const Size(375, 812));
    expect(detailText('16,0'), findsOneWidget);
    expect(find.textContaining('von 30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Map<String, NightScalarRow> _paperResp({int? algo}) {
  final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
  final start = days.length - kNightScalarPaperResp.length;
  return {
    for (var i = 0; i < kNightScalarPaperResp.length; i++)
      days[start + i]: NightScalarRow(
        day: days[start + i],
        algoVersion: algo ?? kAlgoVersion,
        value: kNightScalarPaperResp[i],
      ),
  };
}
