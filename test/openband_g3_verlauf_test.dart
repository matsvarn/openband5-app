import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/chrome.dart' show OBListRow;
import 'package:openstrap_edge/openband/g3/metrics.dart' show G3Scale;
import 'package:openstrap_edge/openband/g3/screens/verlauf.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

const _day = '2026-09-29';

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync())
      as Map,
);

SyntheticOpenBandRepository _repo(SyntheticScenario scenario) {
  return SyntheticOpenBandRepository.fromMaps(
    _fixture('day-summary.json'),
    _fixture('sleep-detail.json'),
    scenario: scenario,
  );
}

class _ControlledTrendRepository extends SyntheticOpenBandRepository {
  _ControlledTrendRepository({this.fail = false, this.partial = false})
    : super.fromMaps(
        _fixture('day-summary.json'),
        _fixture('sleep-detail.json'),
        scenario: SyntheticScenario.g3Sample,
      );
  final bool fail, partial;

  @override
  Future<G3Trend> readTrend(G3Metric metric, String endDay, int days) async {
    if (fail) throw StateError('unreadable trend');
    if (partial) {
      final labels = g3DaysEnding(endDay, days);
      return g3Trend(metric, [
        for (final day in labels)
          MetricPoint(day, day == endDay ? 99 : null, partial: day == endDay),
      ], await readPersonalRange(metric, endDay));
    }
    return super.readTrend(metric, endDay, days);
  }
}

class _BuildingBodyRepository extends SyntheticOpenBandRepository {
  _BuildingBodyRepository()
    : super.fromMaps(
        _fixture('day-summary.json'),
        _fixture('sleep-detail.json'),
        scenario: SyntheticScenario.g3Sample,
      );

  @override
  Future<G3Trend> readTrend(G3Metric metric, String endDay, int days) async =>
      g3Trend(
        metric,
        [
          for (final day in g3DaysEnding(endDay, days))
            MetricPoint(
              day,
              day == endDay
                  ? switch (metric) {
                      G3Metric.hrv => 73,
                      G3Metric.rhr => 51,
                      G3Metric.respRate => 14,
                      G3Metric.skinTempZ => -0.5,
                      _ => null,
                    }
                  : null,
            ),
        ],
        const G3Baseline(
          BaselineStatus(
            BaselinePhase.building,
            nightsHave: 9,
            nightsNeeded: 14,
          ),
        ),
      );

  @override
  Future<G3Baseline> readPersonalRange(G3Metric metric, String day) async =>
      const G3Baseline(
        BaselineStatus(BaselinePhase.building, nightsHave: 9, nightsNeeded: 14),
      );
}

class _UnknownWeightRepository extends SyntheticOpenBandRepository {
  _UnknownWeightRepository()
    : super.fromMaps(
        _fixture('day-summary.json'),
        _fixture('sleep-detail.json'),
        scenario: SyntheticScenario.g3Sample,
      );

  @override
  Future<G3Weight> readG3Weight(String endDay, int days) async => G3Weight(
    buildWeightHistory(
      endDay: endDay,
      days: days,
      rows: [WeightStoredRow(date: endDay, value: 78.4)],
    ),
    const {},
  );
}

Widget _app(Widget child) =>
    MaterialApp(theme: openBandTheme(Brightness.light), home: child);

void main() {
  setUpAll(() async => initializeDateFormatting('de_DE'));

  testWidgets('missing HRV refuses a value and names the missing input', (
    tester,
  ) async {
    final repo = _repo(SyntheticScenario.g3Building);
    await tester.pumpWidget(
      _app(
        G3MetricDetail(metric: G3Metric.hrv, repository: repo, endDay: _day),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('—'), findsWidgets);
    expect(find.text('Kein Messwert'), findsOneWidget);
    expect(find.text('48'), findsNothing);
  });

  testWidgets('partial values stay absent for every wave-1 trend', (
    tester,
  ) async {
    final repo = _ControlledTrendRepository(partial: true);
    for (final metric in [
      G3Metric.recovery,
      G3Metric.hrv,
      G3Metric.rhr,
      G3Metric.respRate,
      G3Metric.skinTempZ,
      G3Metric.sleepMinutes,
      G3Metric.steps,
    ]) {
      await tester.pumpWidget(
        _app(
          G3MetricDetail(
            key: ValueKey(metric),
            metric: metric,
            repository: repo,
            endDay: _day,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kein Messwert'), findsOneWidget, reason: '$metric');
      expect(find.text('99'), findsNothing, reason: '$metric');
      expect(
        find.text('0 Werte · Verlauf ab 7'),
        findsOneWidget,
        reason: '$metric',
      );
    }
  });

  testWidgets('read error is a retryable refusal', (tester) async {
    final repo = _ControlledTrendRepository(fail: true);
    await tester.pumpWidget(
      _app(
        G3MetricDetail(
          metric: G3Metric.recovery,
          repository: repo,
          endDay: _day,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Verlauf konnte nicht geladen werden'), findsOneWidget);
    expect(find.text('74'), findsNothing);
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('period switch reads the selected window', (tester) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    await tester.pumpWidget(
      _app(
        G3MetricDetail(
          metric: G3Metric.recovery,
          repository: repo,
          endDay: _day,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('74'), findsWidgets);
    await tester.tap(find.text('7 T').first);
    await tester.pumpAndSettle();
    expect(find.text('7 von 7 Tagen mit Wert'), findsOneWidget);
  });

  testWidgets('every body row opens its own trend', (tester) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    await tester.pumpWidget(_app(G3AllMetrics(repository: repo, endDay: _day)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ruhepuls').first);
    await tester.pumpAndSettle();
    expect(find.byType(G3MetricDetail), findsOneWidget);
    expect(
      tester.widget<G3MetricDetail>(find.byType(G3MetricDetail)).metric,
      G3Metric.rhr,
    );
  });

  testWidgets('body values with a building baseline remain recorded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(G3AllMetrics(repository: _BuildingBodyRepository(), endDay: _day)),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('HRV 73 ms'), findsOneWidget);
    expect(find.bySemanticsLabel('Ruhepuls 51 /min'), findsOneWidget);
    expect(find.text('nicht erfasst'), findsNothing);
    expect(find.text('Basis: noch 5 Werte'), findsNWidgets(3));
  });

  testWidgets('building HRV shows progress without a single-value scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        G3MetricDetail(
          metric: G3Metric.hrv,
          repository: _BuildingBodyRepository(),
          endDay: _day,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Basis: noch 5 Werte'), findsOneWidget);
    expect(find.byType(G3Scale), findsNothing);
    expect(find.text('Kein Messwert'), findsNothing);
  });

  testWidgets('an older stored band value includes its date', (tester) async {
    final stored = DateTime.now().subtract(const Duration(days: 3));
    await tester.pumpWidget(
      _app(
        G3AllMetrics(
          repository: _repo(SyntheticScenario.g3Sample),
          endDay: dayLabelOf(stored),
          band: BandSnapshot(
            connection: BandConnection.connected,
            latestStoredAt: stored,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Letzter Bandwert ${DateFormat('dd.MM').format(stored)}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('skin temperature stays relative without a temperature unit', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        G3MetricDetail(
          metric: G3Metric.skinTempZ,
          repository: _repo(SyntheticScenario.g3Sample),
          endDay: _day,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('°C'), findsNothing);
  });

  testWidgets('manual weight entry writes through the journal seam', (
    tester,
  ) async {
    final repo = _repo(SyntheticScenario.g3Sample);
    await tester.pumpWidget(
      _app(G3WeightDetail(repository: repo, endDay: _day)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Noch kein Gewicht'), findsOneWidget);
    await tester.tap(find.text('Gewicht eintragen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '78,45');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect((await repo.readG3Weight(_day, 7)).history.latest, isNull);
    expect(find.textContaining('0,1-kg-Schritten'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '78,4');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect((await repo.readG3Weight(_day, 7)).history.latest?.value, 78.4);
    expect(find.text('78,4 kg'), findsWidgets);
  });

  testWidgets('weight with unknown provenance cannot open the manual editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        G3WeightDetail(repository: _UnknownWeightRepository(), endDay: _day),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Quelle unbekannt'), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OBListRow));
    await tester.pumpAndSettle();
    expect(find.textContaining('nicht belegt'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('small phone with large text keeps the detail readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _repo(SyntheticScenario.g3Sample);
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: G3MetricDetail(
            metric: G3Metric.recovery,
            repository: repo,
            endDay: _day,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('ERHOLUNG'), findsWidgets);
  });
}
