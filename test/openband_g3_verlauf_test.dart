import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/charts.dart';
import 'package:openstrap_edge/openband/g3/chrome.dart' show OBListRow;
import 'package:openstrap_edge/openband/g3/chrome.dart' show OBFormField;
import 'package:openstrap_edge/openband/g3/metrics.dart'
    show G3Scale, OBBodyRow, OBBodyState, OBLeadMetric, OBLeadState;
import 'package:openstrap_edge/openband/g3/screens/heute_routes.dart';
import 'package:openstrap_edge/openband/g3/screens/verlauf.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/tab_bar.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';

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

class _ValuesRepository extends SyntheticOpenBandRepository {
  _ValuesRepository(this.value, this.baseline, {this.presentDays = 1})
    : super.fromMaps(
        _fixture('day-summary.json'),
        _fixture('sleep-detail.json'),
        scenario: SyntheticScenario.g3Sample,
      );
  final double value;
  final G3Baseline baseline;
  final int presentDays;

  @override
  Future<G3Trend> readTrend(G3Metric metric, String endDay, int days) async =>
      g3Trend(metric, [
        for (final (index, day) in g3DaysEnding(endDay, days).indexed)
          MetricPoint(day, index >= days - presentDays ? value : null),
      ], baseline);

  @override
  Future<G3Baseline> readPersonalRange(G3Metric metric, String day) async =>
      baseline;
}

class _WeightRowsRepository extends SyntheticOpenBandRepository {
  _WeightRowsRepository(this.rows)
    : super.fromMaps(
        _fixture('day-summary.json'),
        _fixture('sleep-detail.json'),
        scenario: SyntheticScenario.g3Sample,
      );
  final List<WeightStoredRow> rows;

  @override
  Future<G3Weight> readG3Weight(String endDay, int days) async => G3Weight(
    buildWeightHistory(endDay: endDay, days: days, rows: rows),
    {for (final row in rows) row.date as String: G3WeightSource.manual},
  );
}

Widget _app(Widget child) =>
    MaterialApp(theme: openBandTheme(Brightness.light), home: child);

void main() {
  setUpAll(() async => initializeDateFormatting('de_DE'));

  testWidgets('Heute HRV chevron opens G3 detail inside the Heute tab', (
    tester,
  ) async {
    final controller = OpenBandController(
      repository: _repo(SyntheticScenario.g3Sample),
      initialDay: _day,
      now: () => DateTime(2026, 9, 29, 9, 41),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: AppShell(
          releaseStyle: true,
          domains: const [ShellDomain.home, ShellDomain.sleep],
          builder: (context, domain) => domain == ShellDomain.home
              ? Scaffold(
                  body: OBBodyRow(
                    state: OBBodyState.building,
                    name: 'HRV',
                    value: '48',
                    unit: 'ms',
                    onTap: () =>
                        openHeuteMetric(context, controller, G3Metric.hrv),
                  ),
                )
              : const Scaffold(body: Text('Schlaf tab')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final hrv = find.byWidgetPredicate(
      (widget) => widget is OBBodyRow && widget.name == 'HRV',
    );
    await tester.tap(
      find.descendant(of: hrv, matching: find.byType(OBChevron)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(G3MetricDetail), findsOneWidget);
    expect(
      tester.widget<G3MetricDetail>(find.byType(G3MetricDetail)).metric,
      G3Metric.hrv,
    );
    expect(find.byType(OBTabBar), findsOneWidget);
    expect(
      tester.widget<OBTabBar>(find.byType(OBTabBar)).selected,
      ShellDomain.home,
    );
  });

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

  testWidgets('one HRV value uses the singular trend footer', (tester) async {
    await tester.pumpWidget(
      _app(
        G3MetricDetail(
          metric: G3Metric.hrv,
          repository: _ValuesRepository(
            48,
            const G3Baseline(BaselineStatus(BaselinePhase.none)),
          ),
          endDay: _day,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 Wert · Verlauf ab 7'), findsOneWidget);
    expect(find.text('1 Werte · Verlauf ab 7'), findsNothing);
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

  testWidgets('sleep duration and steps format the lead value', (tester) async {
    for (final (metric, value, text) in [
      (G3Metric.sleepMinutes, 438.0, '7h18'),
      (G3Metric.steps, 6480.0, '6.480'),
    ]) {
      await tester.pumpWidget(
        _app(
          G3MetricDetail(
            key: ValueKey(metric),
            metric: metric,
            repository: _repo(SyntheticScenario.g3Sample),
            endDay: _day,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(text), findsWidgets, reason: '$metric');
      expect(find.text(value.toStringAsFixed(0)), findsNothing);
    }
  });

  testWidgets('average labels the count of usable days', (tester) async {
    await tester.pumpWidget(
      _app(
        G3MetricDetail(
          metric: G3Metric.hrv,
          repository: _ValuesRepository(
            48,
            const G3Baseline(BaselineStatus(BaselinePhase.none)),
            presentDays: 27,
          ),
          endDay: _day,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ø 27 von 30 Tagen'), findsOneWidget);
    expect(find.text('Ø 30 Tage'), findsNothing);
  });

  testWidgets('HRV endpoint stays inside the chart card at 375 pt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        G3MetricDetail(
          metric: G3Metric.hrv,
          repository: _ValuesRepository(
            48,
            const G3Baseline(BaselineStatus(BaselinePhase.none)),
          ),
          endDay: _day,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chart = find.byType(OBTrendChart);
    final values = tester.widget<OBTrendChart>(chart).values;
    expect(values, hasLength(30));
    expect(values.last, 48);
    final plot = find.descendant(
      of: chart,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter?.runtimeType.toString() == '_TrendPainter',
      ),
    );
    expect(
      tester.getRect(plot).right + 5.5,
      lessThan(tester.getRect(chart).right),
    );
  });

  testWidgets('out-of-range colour follows each metric direction', (
    tester,
  ) async {
    for (final (metric, value, range, expected) in [
      (G3Metric.rhr, 48.0, const PersonalRange(52, 58, 55), OBLeadState.better),
      (G3Metric.rhr, 62.0, const PersonalRange(52, 58, 55), OBLeadState.worse),
      (G3Metric.hrv, 62.0, const PersonalRange(38, 52, 45), OBLeadState.better),
      (
        G3Metric.recovery,
        85.0,
        const PersonalRange(58, 80, 68),
        OBLeadState.better,
      ),
      (
        G3Metric.respRate,
        12.0,
        const PersonalRange(14, 17, 15),
        OBLeadState.worse,
      ),
      (
        G3Metric.respRate,
        19.0,
        const PersonalRange(14, 17, 15),
        OBLeadState.worse,
      ),
      (
        G3Metric.skinTempZ,
        1.6,
        const PersonalRange(-0.5, 0.5, 0),
        OBLeadState.plain,
      ),
    ]) {
      final repo = _ValuesRepository(
        value,
        G3Baseline(const BaselineStatus(BaselinePhase.trusted), range: range),
      );
      await tester.pumpWidget(
        _app(
          G3MetricDetail(
            key: ValueKey('$metric$value'),
            metric: metric,
            repository: repo,
            endDay: _day,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<OBLeadMetric>(find.byType(OBLeadMetric)).state,
        expected,
        reason: '$metric $value',
      );
      final mark = tester
          .widget<OBTrendChart>(find.byType(OBTrendChart))
          .marks!
          .last;
      expect(mark, switch (expected) {
        OBLeadState.better => OBTrendMark.better,
        OBLeadState.worse => OBTrendMark.worse,
        _ => OBTrendMark.none,
      }, reason: '$metric $value');
    }
    for (final metric in [G3Metric.sleepMinutes, G3Metric.steps]) {
      await tester.pumpWidget(
        _app(
          G3MetricDetail(
            key: ValueKey(metric),
            metric: metric,
            repository: _ValuesRepository(
              100,
              const G3Baseline(BaselineStatus(BaselinePhase.none)),
            ),
            endDay: _day,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<OBLeadMetric>(find.byType(OBLeadMetric)).state,
        OBLeadState.plain,
      );
      expect(
        tester.widget<OBTrendChart>(find.byType(OBTrendChart)).marks!.last,
        OBTrendMark.none,
      );
    }
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
    expect(find.byType(OBFormField), findsOneWidget);
    expect(find.text('Manuell'), findsOneWidget);
    expect(find.text('Zeit ändern'), findsOneWidget);
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
    expect(find.textContaining('1 Eintrag ·'), findsOneWidget);
  });

  testWidgets('weight chart leaves gaps and lists every visible entry', (
    tester,
  ) async {
    final days = g3DaysEnding(_day, 90);
    final rows = [
      for (var i = 0; i < 5; i++)
        WeightStoredRow(date: days[81 + i * 2], value: 77 + i / 10),
    ];
    await tester.pumpWidget(
      _app(
        G3WeightDetail(repository: _WeightRowsRepository(rows), endDay: _day),
      ),
    );
    await tester.pumpAndSettle();
    final chart = tester.widget<OBTrendChart>(find.byType(OBTrendChart));
    expect(chart.sparse, isTrue);
    expect(chart.values, hasLength(90));
    expect(chart.values.whereType<double>(), hasLength(5));
    for (var i = 1; i < chart.values.length; i++) {
      expect(chart.values[i] != null && chart.values[i - 1] != null, isFalse);
    }
    await tester.scrollUntilVisible(find.text('77,0 kg'), 200);
    expect(find.text('77,0 kg'), findsOneWidget);
  });

  testWidgets('seven consecutive weights occupy seven day slots', (
    tester,
  ) async {
    final days = g3DaysEnding(_day, 7);
    final rows = [
      for (final (index, day) in days.indexed)
        WeightStoredRow(date: day, value: 77 + index / 10),
    ];
    await tester.pumpWidget(
      _app(
        G3WeightDetail(repository: _WeightRowsRepository(rows), endDay: _day),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 T'));
    await tester.pumpAndSettle();
    final chart = tester.widget<OBTrendChart>(find.byType(OBTrendChart));
    expect(chart.period, OBTrendPeriod.d7);
    expect(chart.values, hasLength(7));
    expect(chart.values, everyElement(isNotNull));
  });

  testWidgets(
    'older weight is dated without a zero-entry claim or hero scale',
    (tester) async {
      await tester.pumpWidget(
        _app(
          G3WeightDetail(
            repository: _WeightRowsRepository([
              const WeightStoredRow(date: '2026-06-01', value: 77),
            ]),
            endDay: _day,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Eintrag vom'), findsOneWidget);
      expect(find.textContaining('Keine Einträge im Zeitraum'), findsOneWidget);
      expect(find.textContaining('0 Einträge'), findsNothing);
      expect(find.byType(G3Scale), findsNothing);
    },
  );

  testWidgets('weight detail keeps the Messwerte back label', (tester) async {
    await tester.pumpWidget(
      _app(
        G3AllMetrics(
          repository: _repo(SyntheticScenario.g3Sample),
          endDay: _day,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gewicht').first);
    await tester.pumpAndSettle();
    expect(find.byType(G3WeightDetail), findsOneWidget);
    expect(find.bySemanticsLabel('Zurück zu Messwerte'), findsOneWidget);
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
