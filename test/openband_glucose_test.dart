import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/glucose.dart';
import 'package:openstrap_edge/openband/health.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

Map<String, dynamic> _daySummary() => Map<String, dynamic>.from(
  jsonDecode(
        File(
          'docs/openband5/assets/fixtures/day-summary.json',
        ).readAsStringSync(),
      )
      as Map,
);

Map<String, dynamic> _sleepDetail() => Map<String, dynamic>.from(
  jsonDecode(
        File(
          'docs/openband5/assets/fixtures/sleep-detail.json',
        ).readAsStringSync(),
      )
      as Map,
);

Map<String, dynamic> _glucoseFixture() => Map<String, dynamic>.from(
  jsonDecode(
        File(
          'docs/openband5/assets/fixtures/glucose-source.json',
        ).readAsStringSync(),
      )
      as Map,
);

class _GlucoseRepo extends SyntheticOpenBandRepository {
  _GlucoseRepo() : super.fromMaps(_daySummary(), _sleepDetail());

  Completer<void>? gate;
  Completer<void>? importGate;
  int reads = 0;
  String? lastSourceKey;
  int? lastLimit;
  bool failAfterFirst = false;
  bool failNextRead = false;
  bool failRefreshAfterImport = false;
  bool returnDefaultSnapshot = false;
  GlucoseSnapshot Function(GlucoseSnapshot)? transform;

  @override
  Future<GlucoseSnapshot> readGlucose({String? sourceKey, int? limit}) async {
    reads++;
    lastSourceKey = sourceKey;
    lastLimit = limit;
    final hold = gate;
    if (hold != null) await hold.future;
    if (failNextRead) {
      failNextRead = false;
      throw StateError('synthetic glucose refresh failure');
    }
    if (failAfterFirst && reads > 1) {
      throw StateError('synthetic glucose read failure');
    }
    final snap = await super.readGlucose(sourceKey: sourceKey, limit: limit);
    return transform?.call(snap) ?? snap;
  }

  @override
  Future<GlucoseImportResult> importGlucose({DateTime? now}) async {
    final hold = importGate;
    if (hold != null) await hold.future;
    final result = await super.importGlucose(now: now);
    if (failRefreshAfterImport) {
      failNextRead = true;
      return GlucoseImportResult(
        outcome: result.outcome,
        snapshot: null,
        refreshFailed: true,
      );
    }
    if (returnDefaultSnapshot) {
      failNextRead = true;
      return result;
    }
    return result;
  }
}

const _otherSource = GlucoseSourceIdentity(
  key: 'apple:com.other.app',
  sourceName: 'Sensor-App',
  sourceId: 'com.other.app',
  provenance: GlucoseSourceProvenance.apple,
);

const _fixtureSource = GlucoseSourceIdentity(
  key: SyntheticOpenBandRepository.glucoseFixtureSourceKey,
  sourceName: 'Sensor-App (synthetisch) via Apple Health',
  provenance: GlucoseSourceProvenance.synthetic,
);

void _seedPaged(_GlucoseRepo repo, {required int extra}) {
  for (var i = 0; i < extra; i++) {
    repo.seedGlucoseReading(
      GlucoseReading(
        uuid: 'page-$i',
        measuredAt: DateTime(2026, 9, 14, 23, 59).subtract(Duration(minutes: i)),
        value: i == 189 ? 7.7 : 4.0,
        rawUnit: kGlucoseUnitMillimolePerLiter,
        unitKind: GlucoseUnitKind.millimolePerLiter,
        source: _fixtureSource,
        importedAt: DateTime(2026, 9, 15, 9, 40),
      ),
    );
  }
}

void _seedOther(_GlucoseRepo repo) {
  repo.seedGlucoseReading(
    GlucoseReading(
      uuid: 'other-1000',
      measuredAt: DateTime(2026, 9, 15, 10, 0),
      value: 6.1,
      rawUnit: kGlucoseUnitMillimolePerLiter,
      unitKind: GlucoseUnitKind.millimolePerLiter,
      source: _otherSource,
      importedAt: DateTime(2026, 9, 15, 9, 40),
    ),
  );
}

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

  setUp(() => repo = _GlucoseRepo());

  Future<void> mount(
    WidgetTester tester, {
    OpenBandRepository? repository,
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
    String? sourceKey,
    bool synthetic = true,
    TargetPlatform platform = TargetPlatform.iOS,
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
        theme: openBandTheme(brightness).copyWith(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            key: const ValueKey('capture'),
            child: child,
          ),
        ),
        home: OpenBandGlucose(
          repository: repository ?? repo,
          now: () => DateTime(2026, 9, 15, 9, 41),
          synthetic: synthetic,
          sourceKey: sourceKey,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('fixture has 11 points, 2 gaps, and distinct Paper clocks', () {
    final fixture = _glucoseFixture();
    expect(fixture['latest'], '08:00');
    expect(fixture['imported_at'], '09:40');
    expect(fixture['last_query_at'], '09:41');
    final values = (fixture['values'] as List).cast<num?>();
    expect(values.whereType<num>(), hasLength(11));
    expect(values.where((v) => v == null), hasLength(2));
  });

  test('synthetic snapshot matches fixture clocks and values', () async {
    final snap = await repo.readGlucose();
    expect(snap.history, hasLength(11));
    expect(snap.history.map((r) => r.measuredAt), isNot(contains(DateTime(2026, 9, 15, 7, 25))));
    expect(snap.history.map((r) => r.measuredAt), isNot(contains(DateTime(2026, 9, 15, 7, 30))));
    expect(snap.lastMeasuredAt, DateTime(2026, 9, 15, 8, 0));
    expect(snap.lastImportedAt, DateTime(2026, 9, 15, 9, 40));
    expect(snap.attempt.attemptedAt, DateTime(2026, 9, 15, 9, 41));
    expect(
      glucoseStamp(
        snap.lastMeasuredAt,
        now: DateTime(2026, 9, 15, 9, 41),
      ),
      '15. Sep., 08:00',
    );
    expect(
      glucoseStamp(
        DateTime(2025, 9, 15, 8, 0),
        now: DateTime(2026, 9, 15, 9, 41),
      ),
      '15. Sep. 2025, 08:00',
    );
  });

  test('glucoseStamp uses the default clock and local calendar years', () {
    final clock = DateTime.now();
    final prior = DateTime(clock.year - 1, 9, 15, 8, 0);
    expect(glucoseStamp(prior), '15. Sep. ${prior.year}, 08:00');
    expect(
      glucoseStamp(DateTime(clock.year, 9, 15, 8, 0)),
      '15. Sep., 08:00',
    );

    final utcWall = DateTime.utc(2026, 9, 15, 6, 0);
    final localWall = utcWall.toLocal();
    final wallTime =
        '${localWall.hour.toString().padLeft(2, '0')}:'
        '${localWall.minute.toString().padLeft(2, '0')}';
    expect(
      glucoseStamp(utcWall, now: DateTime(localWall.year, 9, 20)),
      endsWith(', $wallTime'),
    );
    expect(
      glucoseStamp(utcWall, now: DateTime(localWall.year, 9, 20)),
      startsWith('${localWall.day}. '),
    );

    const utcCandidates = [
      (2025, 12, 31, 23, 30),
      (2026, 1, 1, 0, 30),
    ];
    DateTime? utc;
    DateTime? local;
    for (final c in utcCandidates) {
      final instant = DateTime.utc(c.$1, c.$2, c.$3, c.$4, c.$5);
      final loc = instant.toLocal();
      if (loc.year != instant.year) {
        utc = instant;
        local = loc;
        break;
      }
    }
    if (utc == null || local == null) return;
    final sameYear = DateTime(local.year, 6, 15);
    final stamp = glucoseStamp(utc, now: sameYear);
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    expect(stamp, '${local.day}. ${_stampMonth(local.month)}, $time');
    expect(stamp, isNot(contains('${utc.year}')));
    final otherYear = DateTime(local.year == 2026 ? 2024 : local.year + 2, 6, 15);
    final withYear = glucoseStamp(utc, now: otherYear);
    expect(withYear, '${local.day}. ${_stampMonth(local.month)} ${local.year}, $time');
    expect(withYear, isNot(contains('${utc.year},')));
  });

  testWidgets('main light and dark goldens', (tester) async {
    await mount(tester);
    expect(find.text('Glukose'), findsOneWidget);
    expect(find.text('5,2'), findsWidgets);
    expect(find.text('mmol/L'), findsWidgets);
    expect(find.text('Sensor-App · Apple Health'), findsOneWidget);
    expect(find.text('Synthetische Daten'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-light.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-dark.png'),
    );
  });

  testWidgets('source and history goldens, info copy, toggle and back', (
    tester,
  ) async {
    await mount(tester, height: 1400);
    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    expect(find.text('Quelle'), findsWidgets);
    expect(find.text('Verwenden'), findsOneWidget);
    expect(find.text('Jetzt lesen'), findsOneWidget);
    expect(find.text('15. Sep., 08:00'), findsOneWidget);
    expect(find.text('15. Sep., 09:40'), findsOneWidget);
    expect(find.text('15. Sep., 09:41'), findsOneWidget);
    await tester.tap(find.byTooltip('Glukosewerte'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Messwerte aus Apple Health, getrennt nach Quelle. OpenBand misst Glukose nicht.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Importiert 15'), findsNothing);
    expect(find.textContaining('Abgefragt 15'), findsNothing);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-source-light.png'),
    );

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
      isFalse,
    );
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Sensor-App · Ausgeblendet'), findsOneWidget);
    expect(find.text('5,2'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
      isTrue,
    );
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('5,2'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('glucose-messungen')));
    await tester.pumpAndSettle();
    expect(find.text('Messungen'), findsWidgets);
    expect(find.text('08:00'), findsWidgets);
    expect(find.text('5,2 mmol/L'), findsWidgets);
    expect(find.text('07:00'), findsWidgets);
    expect(find.text('5,0 mmol/L'), findsOneWidget);
    expect(find.text('07:25'), findsNothing);
    expect(find.text('07:30'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-history-light.png'),
    );
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Glukosewerte'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Messwerte aus Apple Health, getrennt nach Quelle. OpenBand misst Glukose nicht.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Wert und Einheit stammen aus dem gespeicherten Datensatz. Punkte sind einzelne Messungen; Lücken bleiben offen.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        '„Importiert“ bezeichnet das Speichern in OpenBand, „Abgefragt“ die letzte Health-Abfrage. Ein leeres Ergebnis bestätigt oder widerlegt keinen Lesezugriff.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Ausgeschlossene Quellen werden nicht angezeigt oder neu übernommen. Gespeicherte Messungen bleiben im Verlauf.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('source and history dark goldens', (tester) async {
    await mount(tester, brightness: Brightness.dark, height: 1400);
    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-source-dark.png'),
    );
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glucose-messungen')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-history-dark.png'),
    );
  });

  testWidgets('empty goldens', (tester) async {
    repo.clearGlucoseReadings();
    await mount(tester);
    expect(find.text('Keine Werte gespeichert'), findsOneWidget);
    expect(find.text('Jetzt lesen'), findsOneWidget);
    expect(find.text('Apple Health'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-empty-light.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-empty-dark.png'),
    );
  });

  testWidgets('failed-read goldens retain the hero', (tester) async {
    repo.failGlucoseImport = true;
    repo.glucoseImportFailureStatus = HealthMeasurementImportStatus.readFailed;
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
    expect(find.text('5,2'), findsWidgets);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-error-light.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-error-dark.png'),
    );
  });

  testWidgets('partial goldens', (tester) async {
    final partial = _GlucoseRepo()
      ..transform = (snap) => GlucoseSnapshot(
        selected: snap.selected,
        selectedExcluded: snap.selectedExcluded,
        sources: snap.sources,
        history: snap.history,
        series: snap.series,
        attempt: GlucoseAttempt(
          status: HealthMeasurementImportStatus.partial,
          attemptedAt: snap.attempt.attemptedAt,
          storedCount: snap.attempt.storedCount,
          invalidCount: 2,
          ignoredCount: 1,
        ),
        lastMeasuredAt: snap.lastMeasuredAt,
        lastImportedAt: snap.lastImportedAt,
        truncated: snap.truncated,
        unreadableCount: 1,
      );
    await mount(tester, repository: partial);
    expect(find.text('Teilweise lesbar'), findsOneWidget);
    expect(find.text('5,2'), findsWidgets);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-partial-light.png'),
    );
    await mount(tester, repository: partial, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-partial-dark.png'),
    );
  });

  testWidgets('excluded goldens keep time, source and history', (tester) async {
    await repo.setGlucoseSourceIncluded(
      SyntheticOpenBandRepository.glucoseFixtureSourceKey,
      included: false,
    );
    await mount(tester);
    expect(find.text('Sensor-App · Ausgeblendet'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('mmol/L'), findsOneWidget);
    expect(find.text('Verlauf'), findsNothing);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('Sensor-App · Apple Health'), findsNothing);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-excluded-light.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-excluded-dark.png'),
    );
  });

  testWidgets('375 2x source and main goldens', (tester) async {
    await mount(tester, width: 375, scale: 2, height: 1600);
    expect(find.text('Glukose'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-375-2x.png'),
    );
    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    expect(find.text('Quelle'), findsWidgets);
    expect(find.text('Glukose'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-source-375-2x.png'),
    );
  });

  testWidgets('store-read error is retryable and never empty', (tester) async {
    repo.failGlucoseReads = true;
    await mount(tester);
    expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
    expect(find.text('Keine Werte gespeichert'), findsNothing);
    expect(find.text('Erneut'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-store-error-light.png'),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-store-error-dark.png'),
    );
    repo.failGlucoseReads = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('5,2'), findsWidgets);
  });

  testWidgets('failed read keeps retained rows', (tester) async {
    repo.failGlucoseImport = true;
    repo.glucoseImportFailureStatus = HealthMeasurementImportStatus.readFailed;
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
    expect(find.text('5,2'), findsWidgets);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('Keine Werte gespeichert'), findsNothing);
  });

  testWidgets('persisted import failures keep hero and accurate status copy', (
    tester,
  ) async {
    const cases = [
      (
        HealthMeasurementImportStatus.authorizationDenied,
        'Kein Zugriff',
      ),
      (
        HealthMeasurementImportStatus.authorizationRequestFailed,
        'Freigabe fehlgeschlagen',
      ),
      (
        HealthMeasurementImportStatus.persistenceFailed,
        'Speichern fehlgeschlagen',
      ),
    ];
    for (final (status, message) in cases) {
      final failed = _GlucoseRepo()
        ..failGlucoseImport = true
        ..glucoseImportFailureStatus = status;
      await failed.importGlucose(now: DateTime(2026, 9, 15, 9, 41));
      await mount(tester, repository: failed);
      expect(find.text(message), findsOneWidget);
      expect(find.text('5,2'), findsWidgets);
      expect(find.text('Keine Werte gespeichert'), findsNothing);
      expect(find.text('Keine Werte gelesen'), findsNothing);
      expect(find.textContaining('Denied'), findsNothing);
      expect(find.textContaining('verweigert'), findsNothing);
      if (status != HealthMeasurementImportStatus.authorizationDenied) {
        expect(find.text('Kein Zugriff'), findsNothing);
      }
    }
  });

  testWidgets('successful empty query is not denied', (tester) async {
    repo.clearGlucoseReadings();
    repo.emptyGlucoseImport = true;
    await mount(tester);
    await tester.tap(find.text('Jetzt lesen'));
    await tester.pumpAndSettle();
    expect(find.text('Keine Werte gelesen'), findsOneWidget);
    expect(find.textContaining('verweigert'), findsNothing);
    expect(find.textContaining('Denied'), findsNothing);
    expect(find.textContaining('Kein Zugriff'), findsNothing);
  });

  testWidgets('unknown unit stays visible and is not plotted', (tester) async {
    repo.retagGlucoseUnit('glucose-fixture-0800', 'stones');
    await mount(tester);
    expect(find.text('5,2'), findsWidgets);
    expect(find.text('stones'), findsOneWidget);
    expect(find.text('Verlauf'), findsNothing);
  });

  testWidgets('failed toggle is not optimistic and retries', (tester) async {
    repo.failGlucoseExclusionWrite = true;
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
      isTrue,
    );
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    repo.failGlucoseExclusionWrite = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
      isFalse,
    );
  });

  testWidgets('multi-source picker uses keys, not display names', (
    tester,
  ) async {
    final multi = _GlucoseRepo();
    _seedOther(multi);
    await mount(tester, repository: multi);
    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    expect(find.text('Quelle'), findsWidgets);
    expect(find.textContaining('com.other.app'), findsOneWidget);
    expect(find.textContaining('synthetic:glucose-source'), findsOneWidget);
    await tester.tap(find.textContaining('synthetic:glucose-source'));
    await tester.pumpAndSettle();
    expect(find.text('Verwenden'), findsOneWidget);
    expect(find.text('Sensor-App'), findsWidgets);
  });

  testWidgets('stale source read cannot overwrite the new choice', (
    tester,
  ) async {
    final delayed = _GlucoseRepo();
    _seedOther(delayed);
    delayed.gate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: OpenBandGlucose(
          repository: delayed,
          sourceKey: _otherSource.key,
          synthetic: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: OpenBandGlucose(
          repository: delayed,
          sourceKey: SyntheticOpenBandRepository.glucoseFixtureSourceKey,
          synthetic: true,
        ),
      ),
    );
    await tester.pump();
    delayed.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('5,2'), findsWidgets);
    expect(find.text('6,1'), findsNothing);
  });

  testWidgets('unmounted load does not throw', (tester) async {
    final delayed = _GlucoseRepo();
    delayed.gate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: OpenBandGlucose(repository: delayed, synthetic: true),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    delayed.gate!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('history pages 200 then load more and retries a failed page', (
    tester,
  ) async {
    final paged = _GlucoseRepo();
    _seedPaged(paged, extra: 450);
    await mount(tester, repository: paged, height: 1600);
    expect(paged.lastLimit, kGlucoseHeroLimit);
    expect(find.text('461'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('glucose-messungen')));
    await tester.pumpAndSettle();
    expect(paged.lastLimit, kGlucoseHistoryPage);
    expect(find.text('08:00'), findsWidgets);
    expect(find.text('5,2 mmol/L'), findsWidgets);
    expect(find.text('7,7 mmol/L'), findsNothing);
    final scrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('glucose-mehr')),
      1200,
      scrollable: scrollable.first,
    );
    expect(find.byKey(const ValueKey('glucose-mehr')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('glucose-mehr')));
    await tester.pumpAndSettle();
    expect(paged.lastLimit, kGlucoseHistoryPage * 2);
    await tester.scrollUntilVisible(
      find.text('7,7 mmol/L'),
      1200,
      scrollable: scrollable.first,
    );
    expect(find.text('7,7 mmol/L'), findsOneWidget);
    paged.failNextRead = true;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('glucose-mehr')),
      1200,
      scrollable: scrollable.first,
    );
    await tester.tap(find.byKey(const ValueKey('glucose-mehr')));
    await tester.pumpAndSettle();
    expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
    expect(paged.lastLimit, kGlucoseHistoryPage * 3);
    await tester.ensureVisible(find.text('Erneut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Lesen fehlgeschlagen'), findsNothing);
    expect(paged.lastLimit, kGlucoseHistoryPage * 3);
    await tester.scrollUntilVisible(
      find.text('7,7 mmol/L'),
      -1200,
      scrollable: scrollable.first,
    );
    expect(find.text('7,7 mmol/L'), findsOneWidget);
  });

  testWidgets('health tab opens Glukose after Laborwerte', (tester) async {
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light).copyWith(
          platform: TargetPlatform.iOS,
        ),
        home: Scaffold(body: OpenBandHealth(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('glukose')),
      300,
      scrollable: scrollable.first,
    );
    expect(find.text('Laborwerte'), findsOneWidget);
    expect(find.text('Glukose'), findsOneWidget);
    final laborCard = find.ancestor(
      of: find.byKey(const ValueKey('laborwerte')),
      matching: find.byType(OBCard),
    );
    final glucoseCard = find.ancestor(
      of: find.byKey(const ValueKey('glukose')),
      matching: find.byType(OBCard),
    );
    expect(laborCard.evaluate().first, isNot(glucoseCard.evaluate().first));
    await tester.tap(find.byKey(const ValueKey('glukose')));
    await tester.pumpAndSettle();
    expect(find.text('5,2'), findsWidgets);
    expect(find.byKey(const ValueKey('glucose-quelle')), findsOneWidget);
  });

  test('source title keeps real names and unknown identity', () {
    expect(
      glucoseSourceTitle(
        const GlucoseSourceIdentity(
          key: 'apple:com.real.app',
          sourceName: 'Libre (synthetisch) via Apple Health',
          provenance: GlucoseSourceProvenance.apple,
        ),
      ),
      'Libre (synthetisch) via Apple Health',
    );
    expect(
      glucoseSourceTitle(
        const GlucoseSourceIdentity(
          key: 'synthetic:other',
          sourceName: 'Nightscout (synthetisch) via Apple Health',
          provenance: GlucoseSourceProvenance.synthetic,
        ),
      ),
      'Nightscout (synthetisch) via Apple Health',
    );
    expect(
      glucoseSourceTitle(
        const GlucoseSourceIdentity(
          key: SyntheticOpenBandRepository.glucoseFixtureSourceKey,
          sourceName: 'Sensor-App (synthetisch) via Apple Health',
          provenance: GlucoseSourceProvenance.synthetic,
        ),
      ),
      'Sensor-App',
    );
    expect(
      glucoseSourceTitle(
        const GlucoseSourceIdentity(
          key: kAppleUnknownSourceKey,
          sourceName: 'Unknown app',
          provenance: GlucoseSourceProvenance.unknown,
        ),
      ),
      'Unbekannte Quelle',
    );
  });

  testWidgets('saved import with refresh failure retains data and retries', (
    tester,
  ) async {
    final refresh = _GlucoseRepo()..failRefreshAfterImport = true;
    await mount(tester, repository: refresh, height: 1400);
    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
    await tester.pumpAndSettle();
    expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(find.text('15. Sep., 08:00'), findsOneWidget);
    expect(find.text('Verwenden'), findsOneWidget);
    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
      isTrue,
    );
    refresh.failRefreshAfterImport = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Lesen fehlgeschlagen'), findsNothing);
    expect(find.text('15. Sep., 08:00'), findsOneWidget);
    expect(find.text('Verwenden'), findsOneWidget);
  });

  testWidgets('selected source survives default snapshot and reread failure', (
    tester,
  ) async {
    final multi = _GlucoseRepo()..returnDefaultSnapshot = true;
    _seedOther(multi);
    await mount(
      tester,
      repository: multi,
      sourceKey: SyntheticOpenBandRepository.glucoseFixtureSourceKey,
      height: 1400,
    );
    expect(find.text('5,2'), findsWidgets);
    expect(find.text('6,1'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('synthetic:glucose-source'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
    await tester.pumpAndSettle();
    expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
    expect(find.text('15. Sep., 08:00'), findsOneWidget);
    expect(find.text('15. Sep., 10:00'), findsNothing);
    expect(find.text('Verwenden'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('5,2'), findsWidgets);
    expect(find.text('6,1'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('glucose-messungen')));
    await tester.pumpAndSettle();
    expect(find.text('5,2 mmol/L'), findsWidgets);
    expect(find.text('6,1 mmol/L'), findsNothing);
  });

  testWidgets('source identity replacement drops in-flight import flags', (
    tester,
  ) async {
    final first = _GlucoseRepo()..importGate = Completer<void>();
    final second = _GlucoseRepo();
    _seedOther(second);

    Future<void> pumpSource(_GlucoseRepo repo, String key) {
      return tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('de'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('de')],
          theme: openBandTheme(Brightness.light).copyWith(
            platform: TargetPlatform.iOS,
          ),
          home: OpenBandGlucoseSource(
            repository: repo,
            sourceKey: key,
            now: () => DateTime(2026, 9, 15, 9, 41),
            synthetic: true,
          ),
        ),
      );
    }

    await pumpSource(
      first,
      SyntheticOpenBandRepository.glucoseFixtureSourceKey,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
    await tester.pump();
    await pumpSource(second, _otherSource.key);
    await tester.pump();
    first.importGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('15. Sep., 10:00'), findsOneWidget);
    expect(find.text('15. Sep., 08:00'), findsNothing);
    expect(
      tester
          .widget<OBAction>(find.byKey(const ValueKey('glucose-lesen')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('successful source read clears stale import error on back', (
    tester,
  ) async {
    final failed = _GlucoseRepo()
      ..failGlucoseImport = true
      ..glucoseImportFailureStatus = HealthMeasurementImportStatus.readFailed;
    await mount(tester, repository: failed, height: 1400);
    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Lesen fehlgeschlagen'), findsOneWidget);
    failed.failGlucoseImport = false;
    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glucose-lesen')));
    await tester.pumpAndSettle();
    expect(find.text('Lesen fehlgeschlagen'), findsNothing);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Lesen fehlgeschlagen'), findsNothing);
    expect(find.text('5,2'), findsWidgets);
  });

  testWidgets('android empty uses Health Connect', (tester) async {
    repo.clearGlucoseReadings();
    await mount(tester, platform: TargetPlatform.android);
    expect(find.text('Health Connect'), findsOneWidget);
    expect(find.text('Apple Health'), findsNothing);
    await tester.tap(find.byTooltip('Glukosewerte'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Messwerte aus Health Connect, getrennt nach Quelle. OpenBand misst Glukose nicht.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('newest mmol leaves older mg to the contract series', (
    tester,
  ) async {
    final mixed = _GlucoseRepo();
    mixed.seedGlucoseReading(
      GlucoseReading(
        uuid: 'mg-old',
        measuredAt: DateTime(2026, 9, 15, 6, 0),
        value: 90,
        rawUnit: kGlucoseUnitMilligramPerDeciliter,
        unitKind: GlucoseUnitKind.milligramPerDeciliter,
        source: _fixtureSource,
        importedAt: DateTime(2026, 9, 15, 9, 40),
      ),
    );
    await mount(tester, repository: mixed);
    expect(find.text('5,2'), findsWidgets);
    expect(find.text('mmol/L'), findsWidgets);
    expect(find.text('90'), findsNothing);
    expect(find.text('mg/dL'), findsNothing);
    expect(find.text('Verlauf'), findsOneWidget);
  });

  test('glucoseValueLabel keeps ordinary figures and compact scientific extremes', () {
    expect(glucoseValueLabel(_labelReading(5.2)), '5,2');
    expect(glucoseValueLabel(_labelReading(5.0)), '5,0');
    expect(
      glucoseValueLabel(
        _labelReading(
          90,
          rawUnit: kGlucoseUnitMilligramPerDeciliter,
          unitKind: GlucoseUnitKind.milligramPerDeciliter,
        ),
      ),
      '90',
    );
    expect(glucoseValueLabel(_labelReading(1e308)), '1,0e308');
    expect(glucoseValueLabel(_labelReading(-1e308)), '-1,0e308');
    expect(glucoseValueLabel(_labelReading(1e-20)), '1,0e-20');
    expect(glucoseValueLabel(_labelReading(-1e-20)), '-1,0e-20');
    expect(glucoseValueLabel(_labelReading(1e308)).length, lessThan(12));
    expect(glucoseValueLabel(_labelReading(1e-20)), isNot('0,0'));
    expect(glucoseValueLabel(_labelReading(1e-20)), isNot('0'));
    expect(glucoseValueLabel(_labelReading(1e308)), isNot('—'));
  });

  testWidgets('375 2x extreme finite and long unknown unit/source do not overflow', (
    tester,
  ) async {
    final extreme = _GlucoseRepo()..clearGlucoseReadings();
    extreme.seedGlucoseReading(
      GlucoseReading(
        uuid: 'huge',
        measuredAt: DateTime(2026, 9, 15, 8, 5),
        value: 1e308,
        rawUnit: _longUnknownUnit,
        unitKind: GlucoseUnitKind.unknown,
        source: _longSource,
        importedAt: DateTime(2026, 9, 15, 9, 40),
      ),
    );
    await mount(
      tester,
      repository: extreme,
      width: 375,
      scale: 2,
      height: 1600,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('1,0e308'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.textContaining(_longUnknownUnit), findsWidgets);
    expect(find.textContaining(_longSource.sourceName), findsWidgets);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/glucose-extreme-375-2x.png'),
    );

    await tester.tap(find.byKey(const ValueKey('glucose-messungen')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('1,0e308'), findsWidgets);
    expect(find.textContaining(_longUnknownUnit), findsWidgets);
    expect(find.textContaining(_longSource.sourceName), findsWidgets);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Quelle'), findsWidgets);
    expect(find.textContaining(_longSource.sourceName), findsWidgets);
  });

  testWidgets('375 2x tiny finite value stays nonzero across hero and history', (
    tester,
  ) async {
    final tiny = _GlucoseRepo()..clearGlucoseReadings();
    tiny.seedGlucoseReading(
      GlucoseReading(
        uuid: 'tiny',
        measuredAt: DateTime(2026, 9, 15, 8, 5),
        value: 1e-20,
        rawUnit: kGlucoseUnitMillimolePerLiter,
        unitKind: GlucoseUnitKind.millimolePerLiter,
        source: _longSource,
        importedAt: DateTime(2026, 9, 15, 9, 40),
      ),
    );
    await mount(tester, repository: tiny, width: 375, scale: 2, height: 1600);
    expect(tester.takeException(), isNull);
    expect(find.text('1,0e-20'), findsOneWidget);
    expect(find.text('0,0'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(find.textContaining(_longSource.sourceName), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('glucose-messungen')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('1,0e-20'), findsWidgets);
    expect(find.text('0,0 mmol/L'), findsNothing);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining(_longSource.sourceName), findsWidgets);
  });

  testWidgets('previous-year stamps include year against current reference', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('15. September'), findsOneWidget);
    expect(find.textContaining('2025'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    expect(find.text('15. Sep., 08:00'), findsOneWidget);
    expect(find.text('15. Sep., 09:40'), findsOneWidget);
    expect(find.text('15. Sep., 09:41'), findsOneWidget);
    expect(find.textContaining('2025'), findsNothing);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glucose-messungen')));
    await tester.pumpAndSettle();
    expect(find.text('15. September'), findsOneWidget);
    expect(find.textContaining('2025'), findsNothing);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();

    final prior = _GlucoseRepo()..clearGlucoseReadings();
    prior.seedGlucoseReading(
      GlucoseReading(
        uuid: 'prior-year',
        measuredAt: DateTime(2025, 9, 15, 8, 0),
        value: 5.2,
        rawUnit: kGlucoseUnitMillimolePerLiter,
        unitKind: GlucoseUnitKind.millimolePerLiter,
        source: _fixtureSource,
        importedAt: DateTime(2025, 9, 15, 9, 40),
      ),
    );
    await prior.importGlucose(now: DateTime(2025, 9, 15, 9, 41));
    await mount(tester, repository: prior);
    expect(find.text('15. September 2025'), findsOneWidget);
    expect(find.text('15. September'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('glucose-quelle')));
    await tester.pumpAndSettle();
    expect(find.text('15. Sep. 2025, 08:00'), findsOneWidget);
    expect(find.text('15. Sep. 2025, 09:40'), findsOneWidget);
    expect(find.text('15. Sep. 2025, 09:41'), findsOneWidget);
    expect(find.text('15. Sep., 08:00'), findsNothing);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glucose-messungen')));
    await tester.pumpAndSettle();
    expect(find.text('15. September 2025'), findsOneWidget);
    expect(find.text('15. September'), findsNothing);
  });
}

const _longUnknownUnit =
    'international-arbitrary-glucose-unit-from-legacy-export';

const _longSource = GlucoseSourceIdentity(
  key: 'apple:com.hospital.campus.cgm.suedwest',
  sourceName: 'Krankenhaus-Campus-CGM-Geräteverbund-Südwest-Langname',
  provenance: GlucoseSourceProvenance.apple,
);

GlucoseReading _labelReading(
  double value, {
  String rawUnit = kGlucoseUnitMillimolePerLiter,
  GlucoseUnitKind unitKind = GlucoseUnitKind.millimolePerLiter,
}) => GlucoseReading(
  uuid: 'label',
  measuredAt: DateTime(2026, 9, 15, 8, 0),
  value: value,
  rawUnit: rawUnit,
  unitKind: unitKind,
  source: _fixtureSource,
  importedAt: DateTime(2026, 9, 15, 9, 40),
);

String _stampMonth(int month) => const [
  'Jan.',
  'Feb.',
  'März',
  'Apr.',
  'Mai',
  'Juni',
  'Juli',
  'Aug.',
  'Sep.',
  'Okt.',
  'Nov.',
  'Dez.',
][month - 1];
