import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/charts.dart';
import 'package:openstrap_edge/openband/g3/chrome.dart';
import 'package:openstrap_edge/openband/g3/day.dart';
import 'package:openstrap_edge/openband/g3/g3_format.dart';
import 'package:openstrap_edge/openband/g3/journal_parts.dart';
import 'package:openstrap_edge/openband/g3/screens/journal_screen.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep_night.dart';
import 'package:openstrap_edge/openband/g3/screens/training_screen.dart';
import 'package:openstrap_edge/openband/g3/screens/verlauf.dart';
import 'package:openstrap_edge/openband/g3/sleep_parts.dart';
import 'package:openstrap_edge/openband/g3/training_parts.dart';
import 'package:openstrap_edge/openband/sleep_editor.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

Map _fixture(String name) =>
    jsonDecode(
          File('docs/openband5/assets/fixtures/$name.json').readAsStringSync(),
        )
        as Map;

class _ReviewRepo extends SyntheticOpenBandRepository {
  _ReviewRepo({this.points, this.nightValue})
    : super.fromMaps(
        _fixture('day-summary'),
        _fixture('sleep-detail'),
        scenario: SyntheticScenario.g3Sample,
      );
  final List<double?>? points;
  final double? nightValue;

  @override
  Future<OpenBandDay> readDay(String day) async {
    final stored = await super.readDay(day);
    return nightValue == null
        ? stored
        : OpenBandDay(
            day: day,
            sleep: stored.sleep,
            synthetic: true,
            hrv: DayMetric(nightValue),
            restingHr: DayMetric(nightValue),
            respiration: DayMetric(nightValue),
          );
  }

  @override
  Future<G3Trend> readTrend(G3Metric metric, String endDay, int days) async {
    if (points == null) return super.readTrend(metric, endDay, days);
    final labels = g3DaysEnding(endDay, days);
    return g3Trend(metric, [
      for (final (i, day) in labels.indexed)
        MetricPoint(
          day,
          i < days - points!.length
              ? null
              : points![i - (days - points!.length)],
        ),
    ], await readPersonalRange(metric, endDay));
  }

  @override
  Future<List<G3Activity>> readActivities(String day) async =>
      day == '2026-09-29' ? super.readActivities(day) : const [];

  @override
  Future<G3JournalPattern> readJournalPattern(
    String endDay,
    int nights,
  ) async => G3JournalPattern(
    CaffeineSleepPattern(
      kind: CaffeineSleepPatternKind.unavailable,
      pairedN: 0,
      endDay: endDay,
      startDay: endDay,
      nights: nights,
      algoVersion: 1,
    ),
  );
}

Widget _app(Widget child, {double scale = 1}) => MaterialApp(
  theme: openBandTheme(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);

Widget _card(Widget child) => SingleChildScrollView(
  child: Padding(padding: const EdgeInsets.all(16), child: child),
);

Future<OpenBandController> _controller(
  WidgetTester tester,
  _ReviewRepo repo, {
  String day = '2026-09-29',
}) async {
  final controller = OpenBandController(
    repository: repo,
    initialDay: day,
    band: repo.band,
    now: () => DateTime(2026, 9, 29, 10),
  );
  addTearDown(controller.dispose);
  await controller.refresh();
  return controller;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(375, 812);
    view.devicePixelRatio = 1;
    addTearDown(view.reset);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets(
      'review P1 sleep stage duration is not a footer target $scale',
      (tester) async {
        final c = await _controller(tester, _ReviewRepo());
        await tester.pumpWidget(
          _app(G3SleepScreen(controller: c), scale: scale),
        );
        await tester.pumpAndSettle();
        final duration = find.descendant(
          of: find.byType(OBStageLegend),
          matching: find.text(
            tester
                .widget<OBStageLegend>(find.byType(OBStageLegend))
                .items
                .firstWhere((i) => i.$1 == 'Tief')
                .$2!,
          ),
        );
        await tester.ensureVisible(duration);
        await tester.tapAt(tester.getCenter(duration));
        await tester.pumpAndSettle();
        expect(find.byType(SleepEditor), findsNothing);
        final link = find.text('Zeiten ändern');
        await tester.ensureVisible(link);
        final rect = tester.getRect(link);
        await tester.tapAt(Offset(rect.center.dx, rect.bottom + 10));
        await tester.pumpAndSettle();
        expect(find.byType(SleepEditor), findsOneWidget);
      },
    );

    testWidgets('review P1 load sentence does not open Methode $scale', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          _card(
            OBTrainingLoad(
              load: const G3WeeklyLoad([], atl: 64, ctl: 51),
              onMethod: () => taps++,
            ),
          ),
          scale: scale,
        ),
      );
      final sentence = tester.getRect(
        find.text('Letzte Woche mehr als gewohnt.'),
      );
      for (final x in [
        sentence.left + 2,
        sentence.center.dx,
        sentence.right - 2,
      ]) {
        await tester.tapAt(Offset(x, sentence.bottom - 2));
        expect(taps, 0);
      }
      final link = tester.getRect(find.text('Methode'));
      await tester.tapAt(link.center);
      await tester.tapAt(Offset(link.center.dx, link.bottom + 10));
      expect(taps, 2);
    });

    testWidgets('review P1 last zone minutes are not Grundlage $scale', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          _card(
            OBZoneRows(
              zones: const [OBZone(2, '', 9), OBZone(1, '', 3)],
              source: 'HFmax 186 · geschätzt aus Alter',
              onBasis: () => taps++,
            ),
          ),
          scale: scale,
        ),
      );
      final minutes = tester.getRect(find.text('3 Min.'));
      await tester.tapAt(Offset(minutes.center.dx, minutes.bottom - 1));
      expect(taps, 0);
      final link = tester.getRect(find.text('Grundlage'));
      await tester.tapAt(link.center);
      await tester.tapAt(Offset(link.center.dx, link.bottom + 10));
      expect(taps, 2);
    });

    testWidgets('review P1 a footer with no gap shrinks its target $scale', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          _card(
            OBPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Inhalt direkt über dem Link'),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OBLink('Methode', onTap: () => taps++),
                  ),
                ],
              ),
            ),
          ),
          scale: scale,
        ),
      );
      final text = tester.getRect(find.text('Inhalt direkt über dem Link'));
      final link = tester.getRect(find.text('Methode'));
      await tester.tapAt(Offset(link.center.dx, text.bottom - 1));
      expect(taps, 0);
      await tester.tapAt(Offset(link.center.dx, link.bottom + 10));
      expect(taps, 1);
    });
  }
}
