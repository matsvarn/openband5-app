import 'dart:async';
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
import 'package:openstrap_edge/openband/calendar_line.dart';
import 'package:openstrap_edge/openband/night_scalar_detail.dart';
import 'package:openstrap_edge/openband/night_signals.dart';
import 'package:openstrap_edge/openband/screens.dart';
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

  Widget app(
    Widget home, {
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) => MaterialApp(
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
    home: RepaintBoundary(key: const ValueKey('capture'), child: home),
  );

  Future<void> mountDetail(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    Size size = const Size(393, 852),
    OpenBandNightScalarRead? read,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await controller.refresh();
    await tester.pumpWidget(
      app(
        OpenBandNightScalarDetail(
          controller: controller,
          metricKey: MetricKey.skinTemperature,
          label: 'Hauttemperatur',
          unit: '',
          icon: LucideIcons.thermometer,
          color: (p) => p.ink,
          tint: (p) => p.well,
          digits: 1,
          read: read,
        ),
        brightness: brightness,
        scale: scale,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mountHealth(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await controller.refresh();
    await tester.pumpWidget(
      app(
        Scaffold(
          body: SafeArea(child: OpenBandHealth(controller: controller)),
        ),
        brightness: brightness,
        scale: scale,
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<String, NightScalarRow> paperRows(
    NightScalarUnit unit, {
    bool partial = false,
    String? resultSource,
    String? payloadSource,
  }) {
    final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
    final values = unit == NightScalarUnit.celsius
        ? kNightScalarPaperSkinTempC
        : kNightScalarPaperSkinTempSd;
    final start = days.length - values.length;
    final source = switch (unit) {
      NightScalarUnit.sd => 'band',
      NightScalarUnit.celsius => 'whoop_export',
      NightScalarUnit.unknown => 'cloud_v2',
    };
    return {
      for (var i = 0; i < values.length; i++)
        if (values[i] != null)
          days[start + i]: NightScalarRow(
            day: days[start + i],
            algoVersion: kAlgoVersion,
            value: values[i],
            partial: partial && days[start + i] == kNightScalarPaperDay,
            imported: unit == NightScalarUnit.celsius,
            rowSource: resultSource ?? source,
            source: payloadSource ?? source,
          ),
    };
  }

  void seed(
    NightScalarUnit unit, {
    bool partial = false,
    Map<String, NightScalarJob> sleepJobs = const {},
    String? resultSource,
    String? payloadSource,
  }) {
    final rows = paperRows(
      unit,
      partial: partial,
      resultSource: resultSource,
      payloadSource: payloadSource,
    );
    final source = switch (unit) {
      NightScalarUnit.sd => 'band',
      NightScalarUnit.celsius => 'whoop_export',
      NightScalarUnit.unknown => 'cloud_v2',
    };
    repo.seedNightScalarDetail(
      key: MetricKey.skinTemperature,
      selected: NightScalarRow(
        day: kNightScalarPaperDay,
        algoVersion: kAlgoVersion,
        value: unit == NightScalarUnit.celsius ? 33.2 : 0.4,
        partial: partial,
        imported: unit == NightScalarUnit.celsius,
        rowSource: resultSource ?? source,
        source: payloadSource ?? source,
        deviceFamily: 'gen5',
        computedAtMs: DateTime(2026, 9, 15, 7, 2).millisecondsSinceEpoch,
      ),
      matching: rows,
      sleepJobs: sleepJobs,
      currentAlgo: kAlgoVersion,
    );
  }

  Finder detailText(String text) => find.descendant(
    of: find.byKey(const ValueKey('night-scalar-detail')),
    matching: find.text(text),
  );

  testWidgets('Health temperature opens typed detail and returns', (
    tester,
  ) async {
    seed(NightScalarUnit.sd);
    await mountHealth(tester);
    final card = find.byKey(const ValueKey('hauttemperatur'));
    await tester.scrollUntilVisible(card, 180);
    await tester.ensureVisible(card);
    expect(
      find.descendant(of: card, matching: find.text('+0,4')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('SD')),
      findsOneWidget,
    );
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(detailText('Hauttemperatur'), findsOneWidget);
    expect(detailText('+0,4'), findsOneWidget);
    expect(find.byType(OpenBandNightSignals), findsNothing);
    await tester.tap(find.text('Quelle'));
    await tester.pumpAndSettle();
    expect(find.text('Über Hauttemperatur'), findsOneWidget);
    expect(find.byType(OpenBandNightSignals), findsNothing);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hauttemperatur')), findsOneWidget);
  });

  testWidgets('SD, Celsius, unknown and missing never borrow quantities', (
    tester,
  ) async {
    seed(NightScalarUnit.sd);
    await mountDetail(tester);
    expect(detailText('+0,4'), findsOneWidget);
    expect(detailText('Relative Abweichung'), findsOneWidget);
    expect(find.byType(OBCalendarLine), findsOneWidget);

    seed(NightScalarUnit.celsius);
    await mountDetail(tester);
    expect(detailText('33,2'), findsOneWidget);
    expect(detailText('°C'), findsOneWidget);
    expect(detailText('Importiert'), findsOneWidget);

    seed(NightScalarUnit.unknown);
    await mountDetail(tester);
    expect(detailText('—'), findsWidgets);
    expect(detailText('Einheit unbekannt'), findsOneWidget);
    expect(find.byType(OBSegmented), findsNothing);
    expect(find.byType(OBCalendarLine), findsNothing);
    await mountHealth(tester);
    final unknownCard = find.byKey(const ValueKey('hauttemperatur'));
    await tester.scrollUntilVisible(unknownCard, 180);
    expect(
      find.descendant(
        of: unknownCard,
        matching: find.text('Einheit unbekannt'),
      ),
      findsOneWidget,
    );

    repo.seedNightScalarDetail(
      key: MetricKey.skinTemperature,
      selected: null,
      matching: const {},
      currentAlgo: kAlgoVersion,
    );
    await mountDetail(tester);
    expect(detailText('Noch kein Nachtwert'), findsOneWidget);
    expect(find.byType(OBSegmented), findsNothing);
    expect(detailText('33,2'), findsNothing);
  });

  testWidgets('partial, read error and retry keep honest temperature state', (
    tester,
  ) async {
    seed(NightScalarUnit.sd, partial: true);
    await mountDetail(tester);
    expect(detailText('Unvollständige Nacht'), findsOneWidget);
    expect(find.text('14 von 30 · teils unvollständig'), findsOneWidget);

    repo.failNightScalarRead = true;
    await mountDetail(tester);
    expect(
      find.text('Nachtwerte konnten nicht geladen werden.'),
      findsOneWidget,
    );
    expect(detailText('+0,4'), findsNothing);
    repo.failNightScalarRead = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(detailText('+0,4'), findsOneWidget);
  });

  test('temperature and chart labels keep signs and Celsius half steps', () {
    expect(obTemperatureNumber(0.4, NightScalarUnit.sd), '+0,4');
    expect(obTemperatureNumber(0, NightScalarUnit.sd), '0,0');
    expect(obTemperatureNumber(-0.2, NightScalarUnit.sd), '−0,2');
    expect(obTemperatureNumber(33.2, NightScalarUnit.celsius), '33,2');
    expect(OBCalendarLinePainter.axisLabel(32.5), '32,5');
    expect(OBCalendarLinePainter.axisLabel(1, signed: true), '+1');
    expect(OBCalendarLinePainter.axisLabel(-1, signed: true), '−1');
  });

  testWidgets('periods retain actual calendar gaps and counts', (tester) async {
    seed(NightScalarUnit.sd);
    await mountDetail(tester);
    var line = tester.widget<OBCalendarLine>(find.byType(OBCalendarLine));
    expect(line.values, hasLength(30));
    expect(line.values.whereType<double>(), hasLength(14));
    expect(line.values[19], isNull);
    await tester.tap(find.text('7 Nächte'));
    await tester.pumpAndSettle();
    line = tester.widget<OBCalendarLine>(find.byType(OBCalendarLine));
    expect(line.values, hasLength(7));
    expect(find.text('7 von 7 Nächten'), findsOneWidget);
    await tester.tap(find.text('90 Nächte'));
    await tester.pumpAndSettle();
    line = tester.widget<OBCalendarLine>(find.byType(OBCalendarLine));
    expect(line.values, hasLength(90));
    expect(find.text('14 von 90 Nächten'), findsOneWidget);
  });

  testWidgets('Info preserves units, raw unknown value, metadata and conflicts', (
    tester,
  ) async {
    seed(NightScalarUnit.sd);
    await mountDetail(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Relative Abweichung in Standardabweichungen (SD), keine Temperatur in °C.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Band'), findsWidgets);
    expect(find.textContaining('WHOOP 5.0'), findsOneWidget);
    expect(find.textContaining('Algorithmus $kAlgoVersion'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();

    seed(
      NightScalarUnit.unknown,
      resultSource: 'band',
      payloadSource: 'cloud_v2',
    );
    await mountDetail(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Gespeicherter Wert: 0,4\nDie Einheit ist nicht belegt.',
      ),
      findsOneWidget,
    );
    expect(detailText('Uneindeutig'), findsOneWidget);
    expect(find.textContaining('Quellen: Band / Cloud-Import'), findsOneWidget);
    expect(find.textContaining('Gespeicherter Wert: 0,4 SD'), findsNothing);
    expect(find.textContaining('Gespeicherter Wert: 0,4 °C'), findsNothing);
  });

  testWidgets('Info discloses actual mixed-quantity exclusions', (
    tester,
  ) async {
    repo.nightScalarOverride = NightScalarDetail(
      day: kNightScalarPaperDay,
      key: NightScalarMetric.skinTemperature,
      nights: 30,
      currentAlgo: kAlgoVersion,
      state: NightScalarState.current,
      value: 0.4,
      unit: NightScalarUnit.sd,
      resultSource: 'band',
      payloadSource: 'band',
      counts: const NightScalarCounts(compared: 14, excludedUnit: 2),
      history: const [
        NightScalarHistoryNight(
          day: '2026-09-14',
          resultSource: 'band',
          payloadSource: 'whoop_export',
          gap: NightScalarGap.unit,
          unit: NightScalarUnit.unknown,
        ),
      ],
    );
    await mountDetail(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        '2 Nächte mit anderer oder unbekannter Einheit ausgeschlossen.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Quellenkonflikt: Band / WHOOP-Export'),
      findsOneWidget,
    );
  });

  testWidgets('pending and failed hide headline but retain saved raw in Info', (
    tester,
  ) async {
    for (final status in ['pending', 'failed']) {
      seed(
        NightScalarUnit.celsius,
        sleepJobs: {
          kNightScalarPaperDay: NightScalarJob(
            day: kNightScalarPaperDay,
            status: status,
          ),
        },
      );
      await mountDetail(tester);
      expect(detailText('33,2'), findsNothing);
      expect(
        detailText(
          status == 'pending'
              ? 'Auswertung läuft'
              : 'Auswertung fehlgeschlagen',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Information'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Gespeicherter Wert: 33,2 °C'),
        findsOneWidget,
      );
      expect(find.text('Schlaf ansehen'), findsOneWidget);
      await tester.tap(find.byTooltip('Schließen'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('out-of-order reads cannot replace the selected day', (
    tester,
  ) async {
    seed(NightScalarUnit.sd);
    final reads = <String, Completer<NightScalarDetail>>{};
    Future<NightScalarDetail> read(
      OpenBandRepository repository,
      MetricKey key,
      String day,
      int nights,
    ) {
      return (reads['$day/$nights'] ??= Completer<NightScalarDetail>()).future;
    }

    await mountDetail(tester, read: read);
    controller.selectDay('2026-09-14');
    await tester.pump();
    reads['2026-09-15/30']!.complete(
      NightScalarDetail(
        day: '2026-09-15',
        key: NightScalarMetric.skinTemperature,
        nights: 30,
        currentAlgo: kAlgoVersion,
        state: NightScalarState.current,
        value: 0.4,
        unit: NightScalarUnit.sd,
      ),
    );
    await tester.pump();
    expect(detailText('+0,4'), findsNothing);
    reads['2026-09-14/30']!.complete(
      NightScalarDetail(
        day: '2026-09-14',
        key: NightScalarMetric.skinTemperature,
        nights: 30,
        currentAlgo: kAlgoVersion,
        state: NightScalarState.current,
        value: -0.2,
        unit: NightScalarUnit.sd,
      ),
    );
    await tester.pumpAndSettle();
    expect(detailText('−0,2'), findsOneWidget);
  });

  testWidgets('320 and 375 2x scroll to source without overflow', (
    tester,
  ) async {
    seed(NightScalarUnit.sd);
    for (final config in [
      (const Size(320, 812), 1.0),
      (const Size(375, 812), 2.0),
    ]) {
      await mountDetail(tester, size: config.$1, scale: config.$2);
      await tester.scrollUntilVisible(find.text('Quelle'), 250);
      expect(find.text('Quelle'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Paper temperature variants match goldens', (tester) async {
    Future<void> golden(
      String name,
      NightScalarUnit? unit, {
      Brightness brightness = Brightness.light,
      bool partial = false,
      double scale = 1,
      Size size = const Size(393, 852),
    }) async {
      if (unit == null) {
        repo.seedNightScalarDetail(
          key: MetricKey.skinTemperature,
          selected: null,
          matching: const {},
          currentAlgo: kAlgoVersion,
        );
      } else {
        seed(unit, partial: partial);
      }
      await mountDetail(
        tester,
        brightness: brightness,
        scale: scale,
        size: size,
      );
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/$name.png'),
      );
    }

    await golden('temperature-sd-light', NightScalarUnit.sd);
    await golden(
      'temperature-sd-dark',
      NightScalarUnit.sd,
      brightness: Brightness.dark,
    );
    await golden('temperature-celsius-light', NightScalarUnit.celsius);
    await golden(
      'temperature-celsius-dark',
      NightScalarUnit.celsius,
      brightness: Brightness.dark,
    );
    await golden('temperature-unknown-light', NightScalarUnit.unknown);
    await golden(
      'temperature-unknown-dark',
      NightScalarUnit.unknown,
      brightness: Brightness.dark,
    );
    await golden('temperature-missing-light', null);
    await golden('temperature-missing-dark', null, brightness: Brightness.dark);
    await golden(
      'temperature-partial-light',
      NightScalarUnit.sd,
      partial: true,
    );
    await golden(
      'temperature-partial-dark',
      NightScalarUnit.sd,
      brightness: Brightness.dark,
      partial: true,
    );
    await golden(
      'temperature-2x-light',
      NightScalarUnit.sd,
      scale: 2,
      size: const Size(375, 812),
    );
    await golden(
      'temperature-2x-dark',
      NightScalarUnit.sd,
      brightness: Brightness.dark,
      scale: 2,
      size: const Size(375, 812),
    );

    seed(NightScalarUnit.sd);
    repo.failNightScalarRead = true;
    await mountDetail(tester);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/temperature-error-light.png'),
    );
    await mountDetail(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/temperature-error-dark.png'),
    );
  });
}
