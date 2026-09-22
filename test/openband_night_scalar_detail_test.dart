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

  late _GateRepo repo;
  late OpenBandController controller;

  setUp(() {
    repo = _GateRepo();
    controller = OpenBandController(
      repository: repo,
      initialDay: kNightScalarPaperDay,
      band: repo.band,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
  });
  tearDown(() => controller.dispose());

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    MetricKey key = MetricKey.hrv,
    double scale = 1,
    Size size = const Size(393, 852),
    bool refresh = true,
    bool settle = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (refresh) await controller.refresh();
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
            metricKey: key,
            label: _nightLabel(key),
            unit: _nightUnit(key),
            icon: _nightIcon(key),
            color: _nightColor(key),
            tint: _nightTint(key),
            digits: _nightDigits(key),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  test('90-night bars do not overlap', () {
    const plot = 307.0;
    const left = 26.0;
    final width = NightScalarBarsPainter.barWidth(plot, 90);
    final slot = NightScalarBarsPainter.slotWidth(plot, 90);
    expect(width, lessThanOrEqualTo(slot));
    final first = NightScalarBarsPainter.barLeft(0, 90, left, plot, width);
    final second = NightScalarBarsPainter.barLeft(1, 90, left, plot, width);
    expect(first + width, lessThanOrEqualTo(second + 1e-6));
    expect(NightScalarBarsPainter.barWidth(plot, 30), 6);
    expect(NightScalarBarsPainter.barWidth(plot, 7), 14);
    final seven = NightScalarBarsPainter.barWidth(plot, 7);
    final sevenSlot = NightScalarBarsPainter.slotWidth(plot, 7);
    expect(seven, lessThanOrEqualTo(sevenSlot));
    final sevenFirst = NightScalarBarsPainter.barLeft(0, 7, left, plot, seven);
    final sevenSecond = NightScalarBarsPainter.barLeft(1, 7, left, plot, seven);
    expect(sevenFirst + seven, lessThanOrEqualTo(sevenSecond + 1e-6));
    expect(sevenFirst, closeTo(left + 0.5 * sevenSlot - seven / 2, 1e-6));
  });

  test('baseline stroke is 1.5px at half opacity at any scale', () {
    expect(NightScalarBarsPainter.baselineAlpha, 0.5);
    expect(NightScalarBarsPainter.baselineStrokeWidth, 1.5);
  });

  testWidgets('chart baseline paints 1.5px at alpha 0.5 at normal and large', (
    tester,
  ) async {
    const color = Color(0xFFE0457B);
    Future<void> pumpAt(double scale) {
      return tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 333,
                height: 120 + 40 * (scale - 1).clamp(0.0, 1.0),
                child: CustomPaint(
                  painter: NightScalarBarsPainter(
                    bars: [(day: '2026-09-15', value: 54)],
                    nights: 30,
                    baseline: 56,
                    color: color,
                    axisColor: const Color(0xFF5C6880),
                    textScaler: TextScaler.linear(scale),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    await pumpAt(1);
    expect(
      find.byType(CustomPaint),
      paints..line(color: color.withValues(alpha: 0.5), strokeWidth: 1.5),
    );
    await pumpAt(2);
    expect(
      find.byType(CustomPaint),
      paints..line(color: color.withValues(alpha: 0.5), strokeWidth: 1.5),
    );
  });

  testWidgets('hrv complete light and dark', (tester) async {
    _seedTrusted(repo);
    await mount(tester);
    expect(find.text('HRV'), findsWidgets);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('Nacht auf heute'), findsOneWidget);
    expect(find.text('+8 über Basis'), findsOneWidget);
    expect(find.text('15 von 30 Nächten'), findsOneWidget);
    expect(find.text('Nachtverlauf'), findsOneWidget);
    expect(find.textContaining('23:10'), findsOneWidget);
    expect(find.text('Persönliche Basis'), findsOneWidget);
    expect(find.text('40 ms'), findsOneWidget);
    expect(find.text('Herzratenvariabilität'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/hrv.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/hrv-dark.png'),
    );
  });

  testWidgets('rhr complete uses heart icon', (tester) async {
    _seedTrusted(repo, key: MetricKey.restingHr);
    await mount(tester, key: MetricKey.restingHr);
    expect(find.text('Ruhepuls'), findsWidgets);
    expect(find.text('54'), findsOneWidget);
    expect(find.text('−2 unter Basis'), findsOneWidget);
    expect(find.text('56 /min'), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(LucideIcons.heart).first).icon,
      LucideIcons.heart,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/rhr.png'),
    );
  });

  testWidgets('rhr footer keeps value and unit on one line at 375 and 393', (
    tester,
  ) async {
    for (final width in [375.0, 393.0]) {
      _seedTrusted(repo, key: MetricKey.restingHr);
      await mount(tester, key: MetricKey.restingHr, size: Size(width, 852));
      final basis = find.textContaining('Basis 56');
      expect(basis, findsOneWidget);
      expect(tester.getSize(basis).height, 16);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('rhr 2x 375 stacks the footer without splitting the unit', (
    tester,
  ) async {
    _seedTrusted(repo, key: MetricKey.restingHr);
    await mount(
      tester,
      key: MetricKey.restingHr,
      scale: 2,
      size: const Size(375, 812),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.textContaining('Basis 56'), 300);
    final basis = find.textContaining('Basis 56');
    expect(basis, findsOneWidget);
    expect(tester.getSize(basis).height, 32);
    expect(find.textContaining('/min'), findsWidgets);
  });

  testWidgets('null baseline status with a finite value cannot imply a delta', (
    tester,
  ) async {
    repo.seedNightScalarDetail(
      selected: _selected(baseline: const StoredNightBaseline(value: 40)),
      matching: _paperHrv(),
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('Basis noch offen'), findsOneWidget);
    expect(find.text('+8 über Basis'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'arbitrary baseline status with a finite value cannot imply a delta',
    (tester) async {
      repo.seedNightScalarDetail(
        selected: _selected(
          baseline: const StoredNightBaseline(value: 40, status: 'ready'),
        ),
        matching: _paperHrv(),
        currentAlgo: kAlgoVersion,
      );
      await mount(tester);
      expect(find.text('48'), findsOneWidget);
      expect(find.text('Basis noch offen'), findsOneWidget);
      expect(find.text('+8 über Basis'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('7 and 90 ranges update the readable count', (tester) async {
    _seedTrusted(repo);
    await mount(tester);
    await tester.tap(find.text('7 Nächte'));
    await tester.pumpAndSettle();
    expect(find.text('7 von 7 Nächten'), findsOneWidget);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('+8 über Basis'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/hrv-seven.png'),
    );
    await tester.tap(find.text('90 Nächte'));
    await tester.pumpAndSettle();
    expect(find.text('15 von 90 Nächten'), findsOneWidget);
    await mount(tester, brightness: Brightness.dark);
    await tester.tap(find.text('7 Nächte'));
    await tester.pumpAndSettle();
    expect(find.text('7 von 7 Nächten'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/hrv-seven-dark.png'),
    );
  });

  testWidgets(
    'selected-missing withholds the hero and keeps 14 earlier nights',
    (tester) async {
      repo.scenario = SyntheticScenario.missing;
      await mount(tester);
      expect(find.text('Noch kein Nachtwert'), findsOneWidget);
      expect(find.text('14 von 30 Nächten'), findsOneWidget);
      expect(find.text('0 von 30 Nächten'), findsNothing);
      expect(find.text('+8 über Basis'), findsNothing);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/hrv-missing.png'),
      );
    },
  );

  testWidgets('full-missing shows zero history and no invented bars', (
    tester,
  ) async {
    repo.seedNightScalarDetail(
      selected: null,
      matching: const {},
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    expect(find.text('Noch kein Nachtwert'), findsOneWidget);
    expect(find.text('0 von 30 Nächten'), findsOneWidget);
    expect(find.text('14 von 30 Nächten'), findsNothing);
    expect(find.text('48'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/hrv-full-missing.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    expect(find.text('0 von 30 Nächten'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/hrv-full-missing-dark.png'),
    );
  });

  testWidgets('partial night is labeled, not compared away', (tester) async {
    repo.scenario = SyntheticScenario.partial;
    await mount(tester);
    expect(find.text('Unvollständige Nacht'), findsOneWidget);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('+8 über Basis'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending withholds the selected value and keeps history', (
    tester,
  ) async {
    repo.scenario = SyntheticScenario.processing;
    await mount(tester);
    expect(find.text('Auswertung läuft'), findsOneWidget);
    expect(find.text('48'), findsNothing);
    expect(find.textContaining('von 30 Nächten'), findsOneWidget);
    expect(find.text('Nachtverlauf'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/hrv-pending.png'),
    );
  });

  testWidgets('failed withholds and info shows last stored plus sleep action', (
    tester,
  ) async {
    repo.scenario = SyntheticScenario.calculationFailure;
    await mount(tester);
    expect(find.text('Auswertung fehlgeschlagen'), findsOneWidget);
    expect(find.text('48'), findsNothing);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.text('Auswertung'), findsOneWidget);
    expect(find.textContaining('Auswertung fehlgeschlagen.'), findsOneWidget);
    expect(find.textContaining('Zuletzt gespeichert'), findsOneWidget);
    expect(find.text('Schlaf ansehen'), findsOneWidget);
    expect(find.text('Schließen'), findsNothing);
    expect(find.textContaining('So entsteht die Basis'), findsNothing);
    await tester.tap(find.text('Schlaf ansehen'));
    await tester.pumpAndSettle();
    expect(find.byType(SleepEditor), findsOneWidget);
    expect(find.text('Schlafzeiten ändern'), findsOneWidget);
    expect(find.byType(OpenBandNightSignals), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sql read error shows retry card and retry reloads', (
    tester,
  ) async {
    repo.failNightScalarRead = true;
    await mount(tester);
    expect(
      find.text('Nachtwerte konnten nicht geladen werden.'),
      findsOneWidget,
    );
    expect(find.text('Erneut'), findsOneWidget);
    expect(find.text('48'), findsNothing);
    repo.failNightScalarRead = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('48'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('older calculation is labeled and not claimed current', (
    tester,
  ) async {
    repo.seedNightScalarDetail(
      selected: _selected(algo: 80),
      matching: _paperHrv(algo: 80),
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    expect(find.text('Ältere Berechnung'), findsOneWidget);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('+8 über Basis'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('baseline unknown keeps the value and opens basis info', (
    tester,
  ) async {
    repo.seedNightScalarDetail(
      selected: NightScalarRow(
        day: kNightScalarPaperDay,
        algoVersion: kAlgoVersion,
        value: 48,
        windowStartMs: _onsetStamp,
        windowEndMs: _wakeStamp,
      ),
      matching: _paperHrv(),
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('Basis noch offen'), findsOneWidget);
    expect(find.text('+8 über Basis'), findsNothing);
    await tester.tap(find.text('Persönliche Basis'));
    await tester.pumpAndSettle();
    expect(find.text('Persönliche Basis'), findsWidgets);
    expect(find.textContaining('Basis noch offen'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown baseline status cannot imply a trusted delta', (
    tester,
  ) async {
    repo.seedNightScalarDetail(
      selected: _selected(
        baseline: const StoredNightBaseline(value: 40, status: 'unknown'),
      ),
      matching: _paperHrv(),
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('Basis noch offen'), findsOneWidget);
    expect(find.text('+8 über Basis'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provisional baseline shows the scalar without a delta', (
    tester,
  ) async {
    repo.seedNightScalarDetail(
      selected: _selected(
        baseline: const StoredNightBaseline(
          value: 40,
          status: 'provisional',
          nValid: 4,
        ),
      ),
      matching: _paperHrv(),
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('Vorläufige Basis'), findsOneWidget);
    expect(find.textContaining('vorläufig'), findsWidgets);
    expect(find.text('+8 über Basis'), findsNothing);
    expect(tester.getSize(find.textContaining('Basis 40')).height, 16);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/hrv-provisional.png'),
    );
  });

  testWidgets('stale baseline shows the scalar without a delta', (
    tester,
  ) async {
    repo.seedNightScalarDetail(
      selected: _selected(
        baseline: const StoredNightBaseline(value: 40, status: 'stale'),
      ),
      matching: _paperHrv(),
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    expect(find.text('Basis veraltet'), findsOneWidget);
    expect(find.textContaining('veraltet'), findsWidgets);
    expect(find.text('+8 über Basis'), findsNothing);
    expect(tester.getSize(find.textContaining('Basis 40')).height, 16);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/hrv-stale.png'),
    );
  });

  testWidgets('unknown receipt is Auswertung offen and locks night signals', (
    tester,
  ) async {
    repo.seedNightScalarDetail(
      selected: _selected(),
      matching: _paperHrv(),
      sleepJobs: {
        kNightScalarPaperDay: NightScalarJob(
          day: kNightScalarPaperDay,
          status: 'queued',
        ),
      },
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    expect(find.text('Auswertung offen'), findsOneWidget);
    expect(find.text('48'), findsNothing);
    await tester.tap(find.text('Nachtverlauf'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandNightSignals), findsNothing);
    expect(find.byType(SleepEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('outdated receipt is withheld as Auswertung offen', (
    tester,
  ) async {
    repo.seedNightScalarDetail(
      selected: _selected(computedAtMs: 1000),
      matching: _paperHrv(),
      sleepJobs: {
        kNightScalarPaperDay: NightScalarJob(
          day: kNightScalarPaperDay,
          status: 'complete',
          resultAlgo: kAlgoVersion,
          resultComputedAt: 2000,
        ),
      },
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    expect(find.text('Auswertung offen'), findsOneWidget);
    expect(find.text('48'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unreadable is not treated as a known absence', (tester) async {
    repo.seedNightScalarDetail(
      selected: NightScalarRow(
        day: kNightScalarPaperDay,
        algoVersion: kAlgoVersion,
        payloadUnreadable: true,
        value: 48,
      ),
      matching: _paperHrv(),
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    expect(find.text('Nachtwert nicht lesbar'), findsOneWidget);
    expect(find.text('Noch kein Nachtwert'), findsNothing);
    expect(find.text('48'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('info uses stored metadata and night row opens night signals', (
    tester,
  ) async {
    repo.seedNightScalarDetail(
      selected: _selected(
        sleepSource: 'auto',
        deviceFamily: 'gen5',
        baseline: const StoredNightBaseline(
          value: 40,
          status: 'trusted',
          nValid: 30,
        ),
        computedAtMs: DateTime(2026, 9, 15, 7, 2).millisecondsSinceEpoch,
      ),
      matching: _paperHrv(),
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.text('Über HRV'), findsOneWidget);
    expect(find.textContaining('RMSSD · gespeicherter Wert'), findsOneWidget);
    expect(find.textContaining('Nachtwert'), findsNothing);
    expect(
      find.textContaining('Schlaf automatisch · WHOOP 5.0'),
      findsOneWidget,
    );
    expect(find.textContaining('Status: Verlässlich'), findsOneWidget);
    expect(find.textContaining('gen5'), findsNothing);
    expect(find.textContaining('trusted'), findsNothing);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nachtverlauf'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandNightSignals), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('known and unknown import sources never expose storage keys', (
    tester,
  ) async {
    repo.seedNightScalarDetail(
      selected: NightScalarRow(
        day: kNightScalarPaperDay,
        algoVersion: kAlgoVersion,
        value: 48,
        imported: true,
        source: 'cloud_v2',
        baseline: const StoredNightBaseline(value: 40, status: 'trusted'),
      ),
      matching: {
        ..._paperHrv(),
        '2026-09-14': const NightScalarRow(
          day: '2026-09-14',
          algoVersion: kAlgoVersion,
          value: 42,
          imported: true,
          source: 'opaque_backend_key',
        ),
      },
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cloud-Import'), findsWidgets);
    expect(find.textContaining('Import 1'), findsWidgets);
    expect(find.textContaining('cloud_v2'), findsNothing);
    expect(find.textContaining('opaque_backend_key'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recording timezone controls both window dates and clocks', (
    tester,
  ) async {
    repo.seedNightScalarDetail(
      selected: NightScalarRow(
        day: kNightScalarPaperDay,
        algoVersion: kAlgoVersion,
        value: 48,
        baseline: const StoredNightBaseline(value: 40, status: 'trusted'),
        windowStartMs: DateTime.utc(2026, 9, 14, 21, 10).millisecondsSinceEpoch,
        windowEndMs: DateTime.utc(2026, 9, 15, 4, 54).millisecondsSinceEpoch,
      ),
      matching: _paperHrv(),
      recordingTimezone: 'Europe/Berlin',
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    expect(find.text('23:10–06:54'), findsOneWidget);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('14.–15. September · 23:10–06:54'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending baseline sheet labels value and status as previous', (
    tester,
  ) async {
    repo.seedNightScalarDetail(
      selected: _selected(
        baseline: const StoredNightBaseline(
          value: 40,
          status: 'trusted',
          nValid: 30,
        ),
      ),
      matching: _paperHrv(),
      sleepJobs: {
        kNightScalarPaperDay: const NightScalarJob(
          day: kNightScalarPaperDay,
          status: 'pending',
        ),
      },
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    await tester.tap(find.text('Persönliche Basis'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vorherige Basis 40 ms'), findsOneWidget);
    expect(
      find.textContaining('Vorheriger Status: Verlässlich'),
      findsOneWidget,
    );
    expect(find.textContaining('\nStatus: Verlässlich'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('withheld night row does not open night signals', (tester) async {
    repo.scenario = SyntheticScenario.processing;
    await mount(tester);
    await tester.tap(find.text('Nachtverlauf'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandNightSignals), findsNothing);
    expect(find.byType(SleepEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'in-flight calculation overlay locks night signals until it settles',
    (tester) async {
      _seedTrusted(repo);
      await mount(tester);
      expect(find.text('48'), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronRight), findsNWidgets(2));

      final hold = Completer<void>();
      repo.calculationBarrier = hold.future;
      unawaited(
        controller.calculate(
          SleepCorrection(
            id: 'calc',
            day: kNightScalarPaperDay,
            onset: DateTime(2026, 9, 14, 23, 10),
            wake: DateTime(2026, 9, 15, 6, 54),
            savedAt: DateTime(2026, 9, 15, 7, 48),
            revision: 1,
            state: CorrectionState.pending,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Auswertung läuft'), findsOneWidget);
      expect(find.text('48'), findsNothing);
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
      await tester.tap(find.text('Nachtverlauf'));
      await tester.pump();
      expect(find.byType(OpenBandNightSignals), findsNothing);

      hold.complete();
      await tester.pumpAndSettle();
      expect(find.text('48'), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronRight), findsNWidgets(2));
      await tester.tap(find.text('Nachtverlauf'));
      await tester.pumpAndSettle();
      expect(find.byType(OpenBandNightSignals), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'delayed refresh locks night signals until the typed read settles',
    (tester) async {
      _seedTrusted(repo);
      await mount(tester);
      expect(find.text('48'), findsOneWidget);
      repo.delayReads = true;
      unawaited(controller.refresh());
      await tester.pump();
      await tester.pump();
      expect(find.text('48'), findsNothing);
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
      await tester.tap(find.text('Nachtverlauf'));
      await tester.pump();
      expect(find.byType(OpenBandNightSignals), findsNothing);
      expect(repo.pendingReads, hasLength(1));

      repo.completeRead(0);
      await tester.pumpAndSettle();
      expect(find.text('48'), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronRight), findsNWidgets(2));
      await tester.tap(find.text('Nachtverlauf'));
      await tester.pumpAndSettle();
      expect(find.byType(OpenBandNightSignals), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settled missing still opens honest no-data night signals', (
    tester,
  ) async {
    repo.scenario = SyntheticScenario.missing;
    await mount(tester);
    expect(find.text('Noch kein Nachtwert'), findsOneWidget);
    expect(find.byIcon(LucideIcons.chevronRight), findsNWidgets(2));
    await tester.tap(find.text('Nachtverlauf'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandNightSignals), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unreadable night row does not open night signals', (
    tester,
  ) async {
    repo.seedNightScalarDetail(
      selected: NightScalarRow(
        day: kNightScalarPaperDay,
        algoVersion: kAlgoVersion,
        payloadUnreadable: true,
        value: 48,
      ),
      matching: _paperHrv()..remove(kNightScalarPaperDay),
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    await tester.tap(find.text('Nachtverlauf'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandNightSignals), findsNothing);
    expect(find.byType(SleepEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial older discloses both states in info', (tester) async {
    repo.seedNightScalarDetail(
      selected: _selected(algo: 80, partial: true),
      matching: _paperHrv(algo: 80),
      currentAlgo: kAlgoVersion,
    );
    await mount(tester);
    expect(find.text('Unvollständige Nacht'), findsOneWidget);
    await tester.tap(find.byTooltip('Information'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unvollständige Nacht.'), findsOneWidget);
    expect(find.textContaining('Ältere Berechnung.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('historical partial nights qualify the readable count', (
    tester,
  ) async {
    _seedPartialHistory(repo);
    await mount(tester);
    expect(find.textContaining('von 30 · teils unvollständig'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial count header stays one line at ordinary width', (
    tester,
  ) async {
    Future<void> expectCanonicalSelectedPartial() async {
      expect(find.text('Unvollständige Nacht'), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
      expect(find.text('15 von 30 · teils unvollständig'), findsOneWidget);
      expect(find.textContaining('Basis 40'), findsOneWidget);
      expect(find.text('Basis noch offen'), findsNothing);
      expect(find.text('+8 über Basis'), findsNothing);
      expect(tester.takeException(), isNull);
    }

    Future<void> expectOneLine() async {
      final title = tester.getRect(find.text('Nacht für Nacht'));
      final count = tester.getRect(find.textContaining('teils unvollständig'));
      expect(title.height, 18);
      expect(count.height, 18);
      expect(count.top, closeTo(title.top, 0.5));
      expect(title.width, lessThan(150));
      expect(count.left, closeTo(title.right + 8, 1));
      expect(tester.takeException(), isNull);
    }

    _seedSelectedPartial(repo);
    await mount(tester);
    await expectCanonicalSelectedPartial();
    await expectOneLine();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/hrv-partial.png'),
    );

    _seedSelectedPartial(repo);
    await mount(tester, size: const Size(375, 812));
    await expectCanonicalSelectedPartial();
    await expectOneLine();

    _seedSelectedPartial(repo);
    await mount(tester, size: const Size(320, 812));
    await expectCanonicalSelectedPartial();

    _seedSelectedPartial(repo);
    await mount(tester, scale: 2, size: const Size(375, 812));
    expect(find.text('Unvollständige Nacht'), findsOneWidget);
    expect(find.textContaining('teils unvollständig'), findsOneWidget);
    expect(find.textContaining('Basis 40'), findsOneWidget);
    expect(find.text('+8 über Basis'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'independent 7 then 30 then 7 responses cannot paint stale data',
    (tester) async {
      _seedTrusted(repo);
      await mount(tester);
      repo.delayReads = true;

      await tester.tap(find.text('7 Nächte'));
      await tester.pump();
      await tester.tap(find.text('30 Nächte'));
      await tester.pump();
      await tester.tap(find.text('7 Nächte'));
      await tester.pump();
      expect(repo.pendingReads, hasLength(3));
      expect(find.textContaining('von 30 Nächten'), findsNothing);

      repo.completeRead(2);
      await tester.pumpAndSettle();
      expect(find.text('7 von 7 Nächten'), findsOneWidget);
      repo.completeRead(1);
      repo.completeRead(0);
      await tester.pumpAndSettle();
      expect(find.text('7 von 7 Nächten'), findsOneWidget);
      expect(find.text('15 von 30 Nächten'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'controller refresh clears old content until typed read settles',
    (tester) async {
      _seedTrusted(repo);
      await mount(tester);
      expect(find.text('48'), findsOneWidget);
      repo.delayReads = true;
      unawaited(controller.refresh());
      await tester.pump();
      await tester.pump();
      expect(find.text('48'), findsNothing);
      expect(find.textContaining('von 30 Nächten'), findsNothing);
      expect(repo.pendingReads, hasLength(1));
      repo.completeRead(0);
      await tester.pumpAndSettle();
      expect(find.text('48'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('band notify does not reload night scalars', (tester) async {
    await mount(tester);
    final before = repo.reads;
    controller.updateBand(const BandSnapshot(batteryPercent: 41));
    await tester.pump();
    expect(repo.reads, before);
    expect(find.text('48'), findsOneWidget);
  });

  testWidgets('selectDay does not keep the previous hero', (tester) async {
    await mount(tester);
    expect(find.text('48'), findsOneWidget);
    await tester.runAsync(() => controller.selectDay('2026-09-13'));
    await tester.pump();
    await tester.pump();
    expect(controller.selectedDay, '2026-09-13');
    expect(find.text('48'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delayed same-day repository swap clears the old snapshot', (
    tester,
  ) async {
    _seedTrusted(repo);
    await mount(tester);
    expect(find.text('48'), findsOneWidget);

    final previous = controller;
    final nextRepo = _GateRepo();
    nextRepo.seedNightScalarDetail(
      selected: NightScalarRow(
        day: kNightScalarPaperDay,
        algoVersion: kAlgoVersion,
        value: 32,
        computedAtMs: 1000,
        baseline: const StoredNightBaseline(
          value: kNightScalarPaperHrvBaseline,
          status: 'trusted',
        ),
        windowStartMs: _onsetStamp,
        windowEndMs: _wakeStamp,
      ),
      matching: _paperHrv(),
      currentAlgo: kAlgoVersion,
    );
    nextRepo.delayReads = true;
    controller = OpenBandController(
      repository: nextRepo,
      initialDay: kNightScalarPaperDay,
      band: nextRepo.band,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
    addTearDown(previous.dispose);
    await mount(tester, settle: false);
    await tester.pump();
    expect(find.text('48'), findsNothing);
    expect(find.text('32'), findsNothing);
    expect(nextRepo.pendingReads, isNotEmpty);
    nextRepo.completeRead(0);
    await tester.pumpAndSettle();
    expect(find.text('32'), findsOneWidget);
    expect(find.text('48'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2x 375 does not overflow and keeps a reliable count', (
    tester,
  ) async {
    _seedTrusted(repo);
    await mount(tester, scale: 2, size: const Size(375, 812));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('von 30 Nächten'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/hrv-large.png'),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('Nachtverlauf'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/hrv-large-lower.png'),
    );
  });
}

int get _onsetStamp => DateTime(2026, 9, 14, 23, 10).millisecondsSinceEpoch;
int get _wakeStamp => DateTime(2026, 9, 15, 6, 54).millisecondsSinceEpoch;

String _nightLabel(MetricKey key) => switch (key) {
  MetricKey.hrv => 'HRV',
  MetricKey.restingHr => 'Ruhepuls',
  MetricKey.respiration => 'Atmung',
  MetricKey.skinTemperature => 'Hauttemperatur',
  MetricKey.recovery ||
  MetricKey.sleepDuration ||
  MetricKey.strain => throw ArgumentError.value(key),
};

int _nightDigits(MetricKey key) => switch (key) {
  MetricKey.respiration || MetricKey.skinTemperature => 1,
  MetricKey.hrv || MetricKey.restingHr => 0,
  MetricKey.recovery ||
  MetricKey.sleepDuration ||
  MetricKey.strain => throw ArgumentError.value(key),
};

String _nightUnit(MetricKey key) => switch (key) {
  MetricKey.hrv => 'ms',
  MetricKey.restingHr || MetricKey.respiration => '/min',
  MetricKey.skinTemperature => '',
  MetricKey.recovery ||
  MetricKey.sleepDuration ||
  MetricKey.strain => throw ArgumentError.value(key),
};

IconData _nightIcon(MetricKey key) => switch (key) {
  MetricKey.hrv => LucideIcons.activity,
  MetricKey.restingHr => LucideIcons.heart,
  MetricKey.respiration => LucideIcons.wind,
  MetricKey.skinTemperature => LucideIcons.thermometer,
  MetricKey.recovery ||
  MetricKey.sleepDuration ||
  MetricKey.strain => throw ArgumentError.value(key),
};

Color Function(OB) _nightColor(MetricKey key) => switch (key) {
  MetricKey.hrv => (p) => p.recovery,
  MetricKey.restingHr => (p) => p.pulse,
  MetricKey.respiration => (p) => p.sleep,
  MetricKey.skinTemperature => (p) => p.ink,
  MetricKey.recovery ||
  MetricKey.sleepDuration ||
  MetricKey.strain => throw ArgumentError.value(key),
};

Color Function(OB) _nightTint(MetricKey key) => switch (key) {
  MetricKey.hrv => (p) => p.recoveryTint,
  MetricKey.restingHr => (p) => p.pulseTint,
  MetricKey.respiration => (p) => p.sleepTint,
  MetricKey.skinTemperature => (p) => p.well,
  MetricKey.recovery ||
  MetricKey.sleepDuration ||
  MetricKey.strain => throw ArgumentError.value(key),
};

void _seedTrusted(_GateRepo repo, {MetricKey key = MetricKey.hrv}) {
  switch (key) {
    case MetricKey.hrv:
      repo.seedNightScalarDetail(
        key: key,
        selected: _selected(
          baseline: const StoredNightBaseline(
            value: kNightScalarPaperHrvBaseline,
            status: 'trusted',
          ),
        ),
        matching: _paperHrv(),
        currentAlgo: kAlgoVersion,
      );
    case MetricKey.restingHr:
      repo.seedNightScalarDetail(
        key: key,
        selected: NightScalarRow(
          day: kNightScalarPaperDay,
          algoVersion: kAlgoVersion,
          value: 54,
          computedAtMs: 1000,
          baseline: const StoredNightBaseline(
            value: kNightScalarPaperRhrBaseline,
            status: 'trusted',
          ),
          windowStartMs: _onsetStamp,
          windowEndMs: _wakeStamp,
        ),
        matching: _paperRhr(),
        currentAlgo: kAlgoVersion,
      );
    case MetricKey.respiration:
      repo.seedNightScalarDetail(
        key: key,
        selected: NightScalarRow(
          day: kNightScalarPaperDay,
          algoVersion: kAlgoVersion,
          value: kNightScalarPaperRespRate,
          computedAtMs: 1000,
          windowStartMs: _onsetStamp,
          windowEndMs: _wakeStamp,
        ),
        matching: _paperResp(),
        currentAlgo: kAlgoVersion,
      );
    case MetricKey.recovery:
    case MetricKey.sleepDuration:
    case MetricKey.strain:
    case MetricKey.skinTemperature:
      throw ArgumentError.value(key);
  }
}

void _seedPartialHistory(_GateRepo repo) {
  final matching = _paperHrv();
  final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
  matching[days[20]] = NightScalarRow(
    day: days[20],
    algoVersion: kAlgoVersion,
    value: 36,
    partial: true,
  );
  repo.seedNightScalarDetail(
    selected: _selected(),
    matching: matching,
    currentAlgo: kAlgoVersion,
  );
}

void _seedSelectedPartial(_GateRepo repo) {
  final matching = _paperHrv();
  matching[kNightScalarPaperDay] = NightScalarRow(
    day: kNightScalarPaperDay,
    algoVersion: kAlgoVersion,
    value: kNightScalarPaperHrv.last,
    partial: true,
  );
  repo.seedNightScalarDetail(
    selected: _selected(
      partial: true,
      baseline: const StoredNightBaseline(
        value: kNightScalarPaperHrvBaseline,
        status: 'trusted',
        nValid: 30,
      ),
    ),
    matching: matching,
    currentAlgo: kAlgoVersion,
  );
}

NightScalarRow _selected({
  int? algo,
  bool partial = false,
  StoredNightBaseline? baseline,
  int? computedAtMs,
  String? sleepSource,
  String? deviceFamily,
}) => NightScalarRow(
  day: kNightScalarPaperDay,
  algoVersion: algo ?? kAlgoVersion,
  partial: partial,
  value: 48,
  computedAtMs: computedAtMs ?? 1000,
  sleepSource: sleepSource,
  deviceFamily: deviceFamily,
  baseline:
      baseline ??
      const StoredNightBaseline(value: kNightScalarPaperHrvBaseline),
  windowStartMs: _onsetStamp,
  windowEndMs: _wakeStamp,
);

Map<String, NightScalarRow> _paperHrv({int? algo}) {
  final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
  final start = days.length - kNightScalarPaperHrv.length;
  return {
    for (var i = 0; i < kNightScalarPaperHrv.length; i++)
      days[start + i]: NightScalarRow(
        day: days[start + i],
        algoVersion: algo ?? kAlgoVersion,
        value: kNightScalarPaperHrv[i],
      ),
  };
}

Map<String, NightScalarRow> _paperRhr({int? algo}) {
  final days = nightScalarDaysEnding(kNightScalarPaperDay, 30);
  final start = days.length - kNightScalarPaperRhr.length;
  return {
    for (var i = 0; i < kNightScalarPaperRhr.length; i++)
      days[start + i]: NightScalarRow(
        day: days[start + i],
        algoVersion: algo ?? kAlgoVersion,
        value: kNightScalarPaperRhr[i],
      ),
  };
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

class _GateRepo extends SyntheticOpenBandRepository {
  _GateRepo()
    : super.fromMaps(
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

  bool delayReads = false;
  final List<Completer<void>> pendingReads = [];
  int reads = 0;
  MetricKey? lastKey;
  String? lastDay;
  int? lastNights;

  @override
  Future<NightScalarDetail> readNightScalarDetail(
    MetricKey key,
    String day,
    int nights,
  ) async {
    reads++;
    lastKey = key;
    lastDay = day;
    lastNights = nights;
    if (delayReads) {
      final hold = Completer<void>();
      pendingReads.add(hold);
      await hold.future;
    }
    return super.readNightScalarDetail(key, day, nights);
  }

  void completeRead(int index) => pendingReads[index].complete();
}
