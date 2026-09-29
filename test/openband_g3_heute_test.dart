// G3 · Heute: every state renders its value or an honest refusal, the note
// action arms and cancels a reminder, the check-in and the activity
// suggestion write through the data layer. Goldens in openband_goldens/.
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
import 'package:openstrap_edge/openband/g3/screens/heute.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart' show openBandTheme;

Map _json(String name) =>
    jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync()) as Map;

const _day = '2026-09-29';
DateTime _now() => DateTime(2026, 9, 29, 9, 41);

/// Design repository, optionally without data for today (stale / never).
class _Repo extends SyntheticOpenBandRepository {
  _Repo(SyntheticScenario s, {this.empty = false})
    : super.fromMaps(_json('day-summary.json'), _json('sleep-detail.json'), scenario: s);
  final bool empty;
  @override
  Future<OpenBandDay> readDay(String day) async =>
      empty ? OpenBandDay(day: day, synthetic: true) : super.readDay(day);
  @override
  Future<List<G3Activity>> readActivities(String day) async => empty ? const [] : super.readActivities(day);
}

class _Harness {
  _Harness(this.repo, this.band, {MemoryHeuteReminder? reminder})
    : reminder = reminder ?? MemoryHeuteReminder(),
      controller = OpenBandController(repository: repo, initialDay: _day, band: band, now: _now);
  final _Repo repo;
  final BandSnapshot band;
  final MemoryHeuteReminder reminder;
  final OpenBandController controller;
  int connects = 0;
  final opened = <G3Metric>[];
}

final _connected = BandSnapshot(
  connection: BandConnection.connected,
  batteryPercent: 64,
  latestStoredAt: DateTime(2026, 9, 29, 9, 37),
  receivedAt: DateTime(2026, 9, 29, 9, 38),
);

Future<_Harness> _pump(
  WidgetTester tester,
  _Harness h, {
  bool dark = false,
  Size size = const Size(393, 852),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(h.controller.dispose);
  await h.controller.refresh();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('de'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('de')],
      theme: openBandTheme(dark ? Brightness.dark : Brightness.light),
      home: Scaffold(
        body: OpenBandHeute(
          controller: h.controller,
          reminder: h.reminder,
          onConnect: () => h.connects++,
          onOpenMetric: h.opened.add,
          onAddActivity: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

bool _hasText(WidgetTester tester, bool Function(String) test) => tester
    .widgetList<Text>(find.byType(Text))
    .any((t) => test(t.data ?? t.textSpan?.toPlainText() ?? ''));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
    ]) {
      await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())))).load();
    }
    await (FontLoader('packages/lucide_icons_flutter/Lucide')
          ..addFont(rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf')))
        .load();
  });

  testWidgets('trusted day: lead on the range, note with the sleep-plan bedtime, no °C', (tester) async {
    await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected), size: const Size(393, 3000));
    expect(find.text('Heute'), findsWidgets);
    expect(find.text('normal 58–80'), findsOneWidget);
    expect(find.text('über deinem Median 68'), findsOneWidget);
    expect(find.text('22:20 ins Bett'), findsOneWidget);
    expect(find.text('für 8h05 Schlafbedarf bis 06:54'), findsOneWidget);
    expect(find.text('Zonen nach Bestätigung'), findsOneWidget);
    expect(find.text('Daten bis 09:37 · Nacht lückenlos'), findsOneWidget);
    // The design day stores no stage timeline: totals only, no empty lanes.
    expect(find.text('ohne Verlauf'), findsOneWidget);
    expect(_hasText(tester, (s) => s.contains('°C')), isFalse);
    expect(find.text('zur Basis'), findsNothing, reason: 'unit is a span');
    expect(_hasText(tester, (s) => s.contains('+0,4')), isTrue);
  });

  testWidgets('building baseline: tiles instead of a score, week opens on Schlaf', (tester) async {
    await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Building), _connected), size: const Size(393, 3000));
    expect(find.text('Noch keine Erholung'), findsOneWidget);
    expect(find.text('11 von 14 Nächten'), findsOneWidget);
    expect(find.text('Basis: noch 3 Nächte'), findsWidgets);
    expect(find.text('Heute früher ins Bett.'), findsOneWidget);
    expect(find.text('Schlaf 27 Min. unter Ziel, Erholung ab Nacht 14'), findsOneWidget);
    expect(find.text('Erholung'), findsOneWidget, reason: 'offered but disabled');
    expect(find.text('Erholung: noch keine Werte'), findsOneWidget);
  });

  testWidgets('never connected: no value, one real connect action', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample, empty: true), const BandSnapshot()));
    expect(find.text('Noch kein Band verbunden'), findsOneWidget);
    expect(find.text('Noch keine Werte'), findsOneWidget);
    expect(find.text('ERHOLUNG'), findsOneWidget);
    expect(find.text('SCHLAF'), findsNothing);
    await tester.tap(find.text('WHOOP 5.0 verbinden'));
    expect(h.connects, 1);
  });

  testWidgets('stale band: last transfer named, dashes, no note', (tester) async {
    final h = await _pump(
      tester,
      _Harness(
        _Repo(SyntheticScenario.g3Sample, empty: true),
        BandSnapshot(batteryPercent: 64, latestStoredAt: DateTime(2026, 9, 28, 23, 10), receivedAt: DateTime(2026, 9, 28, 23, 10)),
      ),
    );
    expect(find.text('Getrennt · Daten bis gestern 23:10'), findsOneWidget);
    expect(find.text('Band nicht verbunden'), findsOneWidget);
    expect(find.text('Keine Erholung für heute'), findsOneWidget);
    expect(find.text('Heute keine Notiz'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('9,4'), findsNothing);
    await tester.tap(find.text('Verbinden'));
    expect(h.connects, 1);
  });

  testWidgets('Erinnern arms and cancels; a denied permission says so', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected));
    final remind = find.ancestor(of: find.text('Erinnern'), matching: find.byType(GestureDetector)).first;
    expect(tester.getSize(remind).height, greaterThanOrEqualTo(44));
    await tester.tap(remind);
    await tester.pumpAndSettle();
    expect(find.text('Erinnerung um 22:05'), findsOneWidget);
    expect(await h.reminder.armedAt(), DateTime(2026, 9, 29, 22, 5));
    await tester.tap(find.byIcon(LucideIcons.check).first);
    await tester.pumpAndSettle();
    expect(find.text('22:20 ins Bett'), findsOneWidget);
    expect(await h.reminder.armedAt(), isNull);

    h.reminder.allowed = false;
    await tester.tap(find.text('Erinnern'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mitteilungen sind aus'), findsOneWidget);
    expect(find.text('Erinnerung um 22:05'), findsNothing);
  });

  testWidgets('check-in answers through the data layer; Später parks it', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected), size: const Size(393, 3000));
    expect(find.text('2 von 4'), findsOneWidget);
    expect(find.text('Stimmung: 4 von 5'), findsOneWidget);
    expect(find.text('Wie hast du geschlafen?'), findsOneWidget);
    await tester.tap(find.text('3').first);
    await tester.pumpAndSettle();
    final ci = await h.repo.readCheckIn(_day);
    expect(ci.questions.firstWhere((q) => q.field.key == 'sleep_quality').value?.value, 3);
    expect(find.text('3 von 4'), findsOneWidget);
    await tester.tap(find.text('Später'));
    await tester.pumpAndSettle();
    expect(find.text('2 offen'), findsOneWidget);
  });

  testWidgets('an auto-detected run is confirmed from its sheet', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected), size: const Size(393, 3000));
    expect(find.text('auto-erkannt'), findsOneWidget);
    await tester.tap(find.textContaining('07:58–08:40'));
    await tester.pumpAndSettle();
    expect(find.text('Automatisch erkannt'), findsOneWidget);
    await tester.tap(find.text('Stimmt'));
    await tester.pumpAndSettle();
    final activities = await h.repo.readActivities(_day);
    expect(activities.single.confirmed, isTrue);
    expect(find.text('auto-erkannt'), findsNothing);
    expect(find.text('Zonen nach Bestätigung'), findsNothing);
  });

  testWidgets('a past day has no note, no check-in and says it is stored', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected), size: const Size(393, 3000));
    await h.controller.selectDay('2026-09-27');
    await tester.pumpAndSettle();
    expect(find.text('Sonntag'), findsOneWidget);
    expect(find.text('Gespeicherter Tag'), findsOneWidget);
    expect(find.text('FÜR HEUTE'), findsNothing);
    expect(find.text('CHECK-IN'), findsNothing);
    expect(find.text('Heute'), findsNothing, reason: 'no "Heute" week label on a past day');
  });

  testWidgets('the lead opens its detail', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected));
    await tester.tap(find.text('ERHOLUNG'));
    expect(h.opened, [G3Metric.recovery]);
  });

  testWidgets('Dynamic Type 200 %: Heute lays out without overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected), size: const Size(393, 6000));
    expect(tester.takeException(), isNull);
  });

  for (final (name, scenario, dark) in [
    ('heute-hell', SyntheticScenario.g3Sample, false),
    ('heute-dunkel', SyntheticScenario.g3Sample, true),
    ('heute-basis-hell', SyntheticScenario.g3Building, false),
  ]) {
    testWidgets('golden $name', (tester) async {
      await _pump(tester, _Harness(_Repo(scenario), _connected), dark: dark, size: const Size(393, 2600));
      await expectLater(find.byType(OpenBandHeute), matchesGoldenFile('openband_goldens/g3-$name.png'));
    }, tags: const ['golden']);
  }
  testWidgets('golden heute-getrennt-hell', (tester) async {
    await _pump(
      tester,
      _Harness(
        _Repo(SyntheticScenario.g3Sample, empty: true),
        BandSnapshot(batteryPercent: 64, latestStoredAt: DateTime(2026, 9, 28, 23, 10), receivedAt: DateTime(2026, 9, 28, 23, 10)),
      ),
    );
    await expectLater(find.byType(OpenBandHeute), matchesGoldenFile('openband_goldens/g3-heute-getrennt-hell.png'));
  }, tags: const ['golden']);
}
