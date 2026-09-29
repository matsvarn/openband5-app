// G3 · Heute: every state renders its value or an honest refusal, the note
// action arms and cancels a reminder, the check-in and the activity
// suggestion write through the data layer. Goldens in openband_goldens/.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/notify/notification_center.dart' show BedtimeReminderResult;
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/metrics.dart' show OBBodyRow;
import 'package:openstrap_edge/openband/g3/screens/heute.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart' show openBandTheme;

Map _json(String name) =>
    jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync()) as Map;

const _day = '2026-09-29';

/// Design repository, optionally without data for today (stale / never).
class _Repo extends SyntheticOpenBandRepository {
  _Repo(SyntheticScenario s, {this.empty = false, this.noBaseline = false})
    : super.fromMaps(_json('day-summary.json'), _json('sleep-detail.json'), scenario: s);
  bool empty;

  /// Every personal range in phase none (no basis will be formed yet).
  final bool noBaseline;
  @override
  Future<G3Baseline> readPersonalRange(G3Metric metric, String day) async =>
      noBaseline ? const G3Baseline(BaselineStatus(BaselinePhase.none)) : super.readPersonalRange(metric, day);
  @override
  Future<OpenBandDay> readDay(String day) async =>
      empty ? OpenBandDay(day: day, synthetic: true) : super.readDay(day);
  @override
  Future<List<G3Activity>> readActivities(String day) async => empty ? const [] : super.readActivities(day);
}

class _Harness {
  _Harness(this.repo, this.band, {MemoryHeuteReminder? reminder}) : reminder = reminder ?? MemoryHeuteReminder();
  final _Repo repo;
  final BandSnapshot band;
  final MemoryHeuteReminder reminder;
  DateTime clock = DateTime(2026, 9, 29, 9, 41);
  late final controller = OpenBandController(repository: repo, initialDay: _day, band: band, now: () => clock);
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

/// Holds [armed] reads until [gate] completes, returning what was stored when
/// the read began: a load racing a cancel.
class _GatedReminder extends MemoryHeuteReminder {
  Completer<void>? gate;
  int waiting = 0;
  @override
  Future<ArmedBedtime?> armed() async {
    final v = await super.armed();
    final g = gate;
    if (g != null) {
      waiting++;
      await g.future;
    }
    return v;
  }
}

void _foreground(WidgetTester tester) => tester.binding
  ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
  ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);

bool _hasText(WidgetTester tester, bool Function(String) test) => tester
    .widgetList<Text>(find.byType(Text))
    .any((t) => test(t.data ?? t.textSpan?.toPlainText() ?? ''));

Finder _inBody(String text) => find.descendant(of: find.byType(OBBodyRow), matching: find.text(text));

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
    // HRV 48 without a basis: no scale invented from the value (36…60).
    expect(_hasText(tester, (s) => s == '48 ms'), isTrue);
    expect(find.text('36'), findsNothing);
    expect(find.text('60'), findsNothing);
    expect(_inBody('Basis: noch 3 Nächte'), findsNWidgets(3), reason: 'HRV, Ruhepuls, Atemfrequenz');
  });

  testWidgets('no basis at all: body values without a scale, "kein Normalbereich"', (tester) async {
    await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample, noBaseline: true), _connected), size: const Size(393, 3000));
    expect(_hasText(tester, (s) => s == '48 ms'), isTrue);
    expect(_inBody('kein Normalbereich'), findsNWidgets(3));
    for (final tick in ['36', '60', '38', '52']) {
      expect(find.text(tick), findsNothing, reason: 'no tick $tick without a basis');
    }
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

    h.reminder.result = BedtimeReminderResult.denied;
    await tester.tap(find.text('Erinnern'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mitteilungen sind aus'), findsOneWidget);
    expect(find.text('Erinnerung um 22:05'), findsNothing);
  });

  testWidgets('a passed reminder time says so, not "Mitteilungen sind aus"', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected));
    h.reminder.result = BedtimeReminderResult.passed;
    await tester.tap(find.text('Erinnern'));
    await tester.pumpAndSettle();
    expect(find.text('Keine Erinnerung gestellt: 22:05 ist schon vorbei.'), findsOneWidget);
    expect(find.textContaining('Mitteilungen sind aus'), findsNothing);
    expect(await h.reminder.armedAt(), isNull);
  });

  testWidgets('an armed reminder is cancelled when the note loses its action or time', (tester) async {
    final repo = _Repo(SyntheticScenario.g3Sample);
    final h = await _pump(tester, _Harness(repo, _connected));
    await tester.tap(find.text('Erinnern'));
    await tester.pumpAndSettle();
    expect(await h.reminder.armedAt(), DateTime(2026, 9, 29, 22, 5));
    expect(h.reminder.cancels, 0, reason: 'a matching reminder stays');
    repo.empty = true; // the night is gone: no note, no action
    await h.controller.refresh();
    await tester.pumpAndSettle();
    expect(await h.reminder.armedAt(), isNull);
    expect(h.reminder.cancels, 1);

    // Armed for another time than today's note shows.
    final other = await _pump(
      tester,
      _Harness(
        _Repo(SyntheticScenario.g3Sample),
        _connected,
        reminder: MemoryHeuteReminder(armed: (at: DateTime(2026, 9, 29, 21, 30), day: _day)),
      ),
    );
    expect(await other.reminder.armedAt(), isNull);
    expect(other.reminder.cancels, 1);
    expect(find.text('Erinnerung um 21:30'), findsNothing);
  });

  testWidgets('a reminder armed for a day that is over is cancelled on the next foreground', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected));
    await tester.tap(find.text('Erinnern'));
    await tester.pumpAndSettle();
    _foreground(tester);
    await tester.pumpAndSettle();
    expect(h.reminder.cancels, 0, reason: 'same day, same time: kept');
    h.clock = DateTime(2026, 9, 30, 0, 5);
    _foreground(tester);
    await tester.pumpAndSettle();
    expect(await h.reminder.armedAt(), isNull);
    expect(h.reminder.cancels, 1);

    // A bedtime after midnight is still ahead but belongs to the 29th.
    final late = _Harness(
      _Repo(SyntheticScenario.g3Sample),
      _connected,
      reminder: MemoryHeuteReminder(armed: (at: DateTime(2026, 9, 30, 0, 30), day: _day)),
    )..clock = DateTime(2026, 9, 30, 0, 5);
    await _pump(tester, late);
    expect(await late.reminder.armedAt(), isNull);
    expect(late.reminder.cancels, 1);
  });

  testWidgets('a load that read the reminder before a cancel does not re-arm the note', (tester) async {
    final r = _GatedReminder();
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected, reminder: r));
    await tester.tap(find.text('Erinnern'));
    await tester.pumpAndSettle();
    expect(find.text('Erinnerung um 22:05'), findsOneWidget);
    r.gate = Completer<void>();
    unawaited(h.controller.refresh());
    for (var i = 0; i < 10 && r.waiting == 0; i++) {
      await tester.pump();
    }
    expect(r.waiting, greaterThan(0), reason: 'the load is reading the reminder');
    await tester.tap(find.byIcon(LucideIcons.check).first);
    await tester.pump();
    r.gate!.complete();
    await tester.pumpAndSettle();
    expect(await r.armedAt(), isNull);
    expect(find.text('Erinnerung um 22:05'), findsNothing);
    expect(find.text('Erinnern'), findsOneWidget);
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
