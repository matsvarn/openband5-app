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
import 'package:openstrap_edge/openband/g3/journal_parts.dart';
import 'package:openstrap_edge/openband/g3/metrics.dart' show OBMissingValue;
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

Widget _app(
  Widget child, {
  double scale = 1,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: openBandTheme(brightness),
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
      'review P1 sleep duration stays separate and footer reaches below text $scale',
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

    testWidgets(
      'review P1 zone minutes stay separate and Grundlage reaches below text $scale',
      (tester) async {
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
      },
    );

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

  for (final (values, below, above) in [
    ([65.0, 70.0], 0, 0),
    ([50.0, 51.0], 2, 0),
    ([90.0], 0, 1),
  ]) {
    testWidgets('review 1 recovery legend omits zero marks $below/$above', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          G3MetricDetail(
            metric: G3Metric.recovery,
            repository: _ReviewRepo(points: values),
            endDay: '2026-09-29',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final marks = tester
          .widgetList<G3Legend>(find.byType(G3Legend))
          .map((w) => w.text)
          .toList();
      expect(marks, isNot(contains('0 darüber')));
      expect(marks, isNot(contains('0 darunter')));
      if (below > 0) expect(marks, contains('$below darunter'));
      if (above > 0) expect(marks, contains('$above darüber'));
    });
  }

  testWidgets(
    'review 2 historical sleep week has weekday and no today emphasis',
    (tester) async {
      final c = await _controller(tester, _ReviewRepo(), day: '2026-09-27');
      await tester.pumpWidget(_app(G3SleepScreen(controller: c)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(OBWeekBars), 250);
      final bars = tester.widget<OBWeekBars>(find.byType(OBWeekBars));
      expect(bars.bars.last.day, 'So');
      expect(bars.bars.any((b) => b.today), isFalse);
    },
  );

  testWidgets('review 2 historical regularity window has weekday', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(G3SleepRegularity(repository: _ReviewRepo(), day: '2026-09-27')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(OBSleepWindows), 250);
    expect(
      tester
          .widget<OBSleepWindows>(find.byType(OBSleepWindows))
          .windows
          .last
          .day,
      'So',
    );
  });

  testWidgets('review 3 historical load has neutral date copy', (tester) async {
    final c = await _controller(tester, _ReviewRepo(), day: '2026-09-27');
    await tester.pumpWidget(
      _app(
        G3LoadScreen(
          controller: c,
          activity: null,
          weekly: const G3WeeklyLoad([]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('HEUTE BISHER').evaluate().isEmpty
          ? find.text('AKTIVITÄTEN')
          : find.text('HEUTE BISHER'),
      250,
    );
    expect(find.text('AKTIVITÄTEN'), findsOneWidget);
    expect(find.text('Keine Aktivität an diesem Tag.'), findsOneWidget);
    expect(find.text('heute läuft'), findsNothing);
  });

  testWidgets(
    'review 3 mounted load reloads activities after selected day changes',
    (tester) async {
      final c = await _controller(tester, _ReviewRepo());
      await tester.pumpWidget(
        _app(
          G3LoadScreen(
            controller: c,
            activity: null,
            weekly: const G3WeeklyLoad([]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lauf'), findsOneWidget);
      await c.selectDay('2026-09-27');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(OBTrainingLoad), 250);
      expect(find.text('Keine Aktivität an diesem Tag.'), findsOneWidget);
      expect(find.text('Lauf'), findsNothing);
    },
  );

  testWidgets(
    'review 4 night metric tiles are plain and header opens signals',
    (tester) async {
      final c = await _controller(tester, _ReviewRepo());
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _app(G3SleepScreen(controller: c, scrollController: scroll)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('HRV · ms'), 250);
      for (final label in ['HRV · ms', 'RUHEPULS', 'ATEMFREQUENZ']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.byType(G3SleepNightSignals), findsNothing);
      }
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('NACHT'));
      await tester.pumpAndSettle();
      expect(find.byType(G3SleepNightSignals), findsOneWidget);
      await tester.tap(find.text('HRV').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Atemfrequenz'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final invalid in [double.nan, double.infinity]) {
    testWidgets('review 5 nonfinite night metrics show missing $invalid', (
      tester,
    ) async {
      final c = await _controller(tester, _ReviewRepo(nightValue: invalid));
      await tester.pumpWidget(_app(G3SleepScreen(controller: c)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('HRV · ms'), 250);
      expect(find.textContaining('NaN'), findsNothing);
      expect(find.textContaining('Infinity'), findsNothing);
      final tiles = find.ancestor(
        of: find.text('HRV · ms'),
        matching: find.byType(OBPanel),
      );
      expect(
        find.descendant(of: tiles, matching: find.byType(OBMissingValue)),
        findsNWidgets(3),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('review 6 strain statistics discard only nonfinite points', (
    tester,
  ) async {
    final c = await _controller(
      tester,
      _ReviewRepo(points: [2, double.nan, 8]),
    );
    await tester.pumpWidget(
      _app(
        G3LoadScreen(
          controller: c,
          activity: null,
          weekly: const G3WeeklyLoad([]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ø 5,0 · 28 Tage ohne Belastungswert'), findsOneWidget);
    expect(find.text('2,0–8,0'), findsOneWidget);
    await tester.ensureVisible(find.text('MEDIAN'));
    expect(find.text('5,0'), findsNWidgets(2));
  });
  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('review 7 load labels fit and values align at 375 pt $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          _card(const OBTrainingLoad(load: G3WeeklyLoad([], atl: 64, ctl: 51))),
          scale: scale,
        ),
      );
      for (final label in ['AKUT · 7 TAGE', 'GEWOHNT · 6 WOCHEN']) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(
          paragraph.size.height,
          lessThanOrEqualTo(paragraph.preferredLineHeight * 1.2),
        );
      }
      expect(
        tester.getTopLeft(find.text('64')).dy,
        tester.getTopLeft(find.text('51')).dy,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('review 8 journal target glyph wraps with its label at 375 pt', (
    tester,
  ) async {
    final c = await _controller(tester, _ReviewRepo());
    await tester.pumpWidget(
      _app(G3JournalScreen(controller: c, onEdit: (_) {})),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(OBPatternCard), 250);
    final moon = find.descendant(
      of: find.byType(OBPatternCard),
      matching: find.byWidgetPredicate(
        (w) => w is Icon && w.icon == LucideIcons.moon,
      ),
    );
    expect(
      tester.getCenter(moon).dy,
      closeTo(tester.getCenter(find.text('Einschlafen')).dy, 1),
    );
  });

  testWidgets('review 8 journal zero pairs has no redundant third line', (
    tester,
  ) async {
    final c = await _controller(tester, _ReviewRepo());
    await tester.pumpWidget(
      _app(G3JournalScreen(controller: c, onEdit: (_) {})),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(OBPatternCard), 250);
    expect(find.text('Noch kein Vergleich · 0 von 8 Paaren'), findsOneWidget);
    expect(find.textContaining('0 Paare ·'), findsNothing);
  });
  for (final brightness in Brightness.values) {
    for (final screen in ['training-load', 'journal-pattern']) {
      testWidgets(
        'review small-phone $screen ${brightness.name} golden',
        (tester) async {
          final Widget page;
          if (screen == 'training-load') {
            page = _card(
              OBTrainingLoad(
                load: const G3WeeklyLoad([], atl: 64, ctl: 51),
                onMethod: () {},
              ),
            );
          } else {
            final c = await _controller(tester, _ReviewRepo());
            page = G3JournalScreen(controller: c, onEdit: (_) {});
          }
          await tester.pumpWidget(_app(page, brightness: brightness));
          await tester.pumpAndSettle();
          if (screen == 'journal-pattern') {
            await tester.scrollUntilVisible(find.byType(OBPatternCard), 250);
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              'openband_goldens/g31-review-$screen-375-${brightness.name}.png',
            ),
          );
        },
        tags: const ['golden'],
      );
    }
  }
}
