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
import 'package:openstrap_edge/data/journal_fields.dart' show kJournalFields;
import 'package:openstrap_edge/main_gallery.dart';
import 'package:openstrap_edge/notify/notification_center.dart' show BedtimeReminderResult;
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/chrome.dart' show OBBandCapsule, OBCardHeader, OBPageHeader, OBSegmented, OBSyncState;
import 'package:openstrap_edge/openband/g3/day.dart' show OBActivityRow, OBNightCard, OBStepsCard, OBWeekBars;
import 'package:openstrap_edge/openband/g3/g3_theme.dart' show G3Domain;
import 'package:openstrap_edge/openband/g3/metrics.dart' show OBBodyRow, OBLeadMetric, OBSecondaryMetric;
import 'package:openstrap_edge/openband/g3/screens/heute.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart' show OBChevron, openBandTheme;

Map _json(String name) =>
    jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync()) as Map;

const _day = '2026-09-29';

/// Design repository, optionally without data for today (stale / never).
class _Repo extends SyntheticOpenBandRepository {
  _Repo(SyntheticScenario s, {this.empty = false, this.noBaseline = false})
    : super.fromMaps(_json('day-summary.json'), _json('sleep-detail.json'), scenario: s);
  bool empty;

  /// Last stored band sample per day (past days read it from here).
  final lastSamples = <String, DateTime>{};
  @override
  Future<DateTime?> readLastBandSampleAt(String day) async => lastSamples[day] ?? await super.readLastBandSampleAt(day);

  /// The sleep plan read throws (a transient failure).
  bool planThrows = false;
  @override
  Future<G3SleepPlus> readSleepPlus(String day, {DateTime? now}) async =>
      planThrows ? throw StateError('transient') : super.readSleepPlus(day, now: now);

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

/// A day that stores only the given step spans.
class _StepsRepo extends _Repo {
  _StepsRepo(this.spans) : super(SyntheticScenario.g3Sample);
  final List<StepInterval> spans;
  @override
  Future<OpenBandDay> readDay(String day) async => OpenBandDay(
    day: day,
    steps: DayMetric(spans.fold<double>(0, (a, s) => a + s.steps)),
    stepIntervals: spans,
    synthetic: true,
  );
}

/// A check-in with a today rating and a yesterday count: the kinds the
/// synthetic journal does not ask.
class _TypedCheckInRepo extends _Repo {
  _TypedCheckInRepo() : super(SyntheticScenario.g3Sample);
  final written = <(String, String, G3CheckInAnswer)>[];
  @override
  Future<G3CheckIn> readCheckIn(String day) async {
    G3CheckInAnswer? of(String key) => written.where((w) => w.$2 == key).lastOrNull?.$3;
    final spec = {for (final f in kJournalFields) f.key: f};
    return G3CheckIn(day, [
      G3CheckInQuestion(key: 'mood', label: 'Mood', targetDay: day, kind: G3CheckInKind.rating, answer: of('mood'), field: spec['mood']),
      G3CheckInQuestion(
        key: 'alcohol_units',
        label: 'Alcohol',
        targetDay: g3DaysEnding(day, 2).first,
        kind: G3CheckInKind.quantity,
        answer: of('alcohol_units'),
        field: spec['alcohol_units'],
      ),
    ]);
  }

  @override
  Future<void> answerCheckIn(String day, String key, G3CheckInAnswer answer) async => written.add((day, key, answer));
}

/// The fixture's own day: the only one the partial and failed scenarios affect.
const _fixtureDay = '2026-09-15';

class _Harness {
  _Harness(this.repo, this.band, {MemoryHeuteReminder? reminder, this.day = _day}) : reminder = reminder ?? MemoryHeuteReminder();
  final _Repo repo;
  final BandSnapshot band;
  final MemoryHeuteReminder reminder;
  DateTime clock = DateTime(2026, 9, 29, 9, 41);
  final String day;
  late final controller = OpenBandController(repository: repo, initialDay: day, band: band, now: () => clock);
  int connects = 0;
  final journalDays = <String>[];
  final opened = <G3Metric>[];
  int allMetricsOpens = 0;
  int bandOpens = 0;
  int dataStatusOpens = 0;
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
          onBand: () => h.bandOpens++,
          onDataStatus: () => h.dataStatusOpens++,
          onOpenMetric: h.opened.add,
          onOpenAllMetrics: () => h.allMetricsOpens++,
          onJournalDay: h.journalDays.add,
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

  for (final dark in [false, true]) {
    testWidgets('Heute has no overflow at 375 × 812, dark: $dark', (
      tester,
    ) async {
      await _pump(
        tester,
        _Harness(_Repo(SyntheticScenario.g3Sample), _connected),
        dark: dark,
        size: const Size(375, 812),
      );
      for (final offset in [0.0, 500.0, 1000.0, 1500.0]) {
        final scroll = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        scroll.jumpTo(offset.clamp(0.0, scroll.maxScrollExtent));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('a failed night calculation is not shown as missing data', (tester) async {
    await _pump(tester, _Harness(_Repo(SyntheticScenario.calculationFailure), _connected, day: _fixtureDay), size: const Size(393, 3000));
    expect(find.bySemanticsLabel('HRV Auswertung fehlgeschlagen'), findsOneWidget);
    expect(find.bySemanticsLabel('Ruhepuls Auswertung fehlgeschlagen'), findsOneWidget);
    expect(find.bySemanticsLabel('HRV nicht erfasst'), findsNothing);
  });

  testWidgets('a partial night keeps its value and says so, without a range', (tester) async {
    await _pump(tester, _Harness(_Repo(SyntheticScenario.partial), _connected, day: _fixtureDay), size: const Size(393, 3000));
    expect(find.bySemanticsLabel(RegExp(r'^HRV \d+ ms, Unvollständige Nacht$')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Ruhepuls \d+ /min, Unvollständige Nacht$')), findsOneWidget);
  });

  testWidgets('trusted day: lead on the range, note with the sleep-plan bedtime, no °C', (tester) async {
    await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected), size: const Size(393, 3000));
    expect(find.text('Heute'), findsWidgets);
    expect(find.text('normal 58–78'), findsOneWidget);
    expect(find.text('über deinem Median 68'), findsOneWidget);
    expect(find.text('22:20 ins Bett'), findsOneWidget);
    expect(find.text('Bedarf 8h05 · bis 06:54'), findsOneWidget);
    expect(find.text('Zonen nach Bestätigung'), findsNothing);
    expect(tester.widget<OBSyncState>(find.byType(OBSyncState)).text, 'Daten bis 09:37 · Nacht lückenlos');
    expect(find.textContaining('Letzter Bandwert'), findsNothing);
    expect(find.text('lückenlos'), findsNothing);
    expect(find.text('SYNTHETISCHE DATEN'), findsOneWidget);
    expect(tester.widget<OBStepsCard>(find.byType(OBStepsCard)).note, startsWith('bis '));
    // The design day stores its stage timeline: no totals-only fallback.
    expect(find.text('ohne Verlauf'), findsNothing);
    expect(_hasText(tester, (s) => s.contains('°C')), isFalse);
    expect(find.text('zur Basis'), findsNothing, reason: 'unit is a span');
    expect(_hasText(tester, (s) => s.contains('+0,4')), isTrue);
  });

  testWidgets('Heute keeps each metric in its domain and freshness in the header', (tester) async {
    await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected), size: const Size(393, 3000));
    expect(tester.widget<OBLeadMetric>(find.byType(OBLeadMetric)).domain, G3Domain.recovery);
    final secondary = tester.widgetList<OBSecondaryMetric>(find.byType(OBSecondaryMetric)).toList();
    expect(secondary.map((metric) => metric.domain), [G3Domain.sleep, G3Domain.load]);
    expect(tester.widget<OBActivityRow>(find.byType(OBActivityRow)).domain, G3Domain.load);
    expect(tester.widget<OBNightCard>(find.byType(OBNightCard)).domain, G3Domain.sleep);
    expect(tester.widgetList<OBBodyRow>(find.byType(OBBodyRow)).every((row) => row.domain == G3Domain.recovery), isTrue);
    expect(tester.widget<OBStepsCard>(find.byType(OBStepsCard)).domain, G3Domain.load);
    expect(tester.widget<OBSyncState>(find.byType(OBSyncState)).synthetic, isTrue);
    expect(find.text('SYNTHETISCHE DATEN'), findsOneWidget);

    final week = find.byType(OBWeekBars);
    expect(tester.widget<OBWeekBars>(week).domain, G3Domain.recovery);
    final selector = tester.widget<OBSegmented>(find.byType(OBSegmented));
    selector.onChanged!(1);
    await tester.pump();
    expect(tester.widget<OBWeekBars>(week).domain, G3Domain.sleep);
    selector.onChanged!(2);
    await tester.pump();
    expect(tester.widget<OBWeekBars>(week).domain, G3Domain.load);
  });

  testWidgets('Körper header opens Messwerte; absent recovery has no chevron', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected), size: const Size(393, 3000));
    final bodyHeader = find.byWidgetPredicate((widget) => widget is OBCardHeader && widget.label == 'KÖRPER');
    await tester.tap(find.descendant(of: bodyHeader, matching: find.text('KÖRPER')));
    expect(h.allMetricsOpens, 1);

    await _pump(tester, _Harness(
      _Repo(SyntheticScenario.g3Sample, empty: true),
      const BandSnapshot(connection: BandConnection.disconnected),
    ));
    expect(find.descendant(of: find.byType(OBLeadMetric), matching: find.byType(OBChevron)), findsNothing);
  });

  testWidgets('band capsule and sync line use separate callbacks', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected));
    await tester.tap(find.byType(OBBandCapsule).first);
    await tester.tap(find.byType(OBSyncState));
    expect(h.bandOpens, 1);
    expect(h.dataStatusOpens, 1);
  });

  testWidgets('building baseline: tiles instead of a score, week opens on Schlaf', (tester) async {
    await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Building), _connected), size: const Size(393, 3000));
    expect(find.text('Noch keine Erholung'), findsOneWidget);
    expect(find.text('11 von 14 Nächten'), findsOneWidget);
    expect(find.text('Basis: noch 3 Nächte'), findsNWidgets(4));
    expect(find.text('Basis im Aufbau'), findsNothing);
    expect(find.textContaining('Sie braucht 14 Nächte'), findsNothing);
    expect(find.text('vergangene Nacht'), findsOneWidget);
    expect(find.text('Heute früher ins Bett.'), findsOneWidget);
    expect(find.text('Schlaf 27 Min. unter Ziel, Erholung ab Nacht 14.'), findsOneWidget);
    expect(find.text('Erholung'), findsOneWidget, reason: 'offered but disabled');
    expect(find.text('Erholung: noch keine Werte'), findsNothing);
    // HRV 48 without a basis: no scale invented from the value (36…60).
    expect(_hasText(tester, (s) => s == '48 ms'), isTrue);
    expect(find.text('36'), findsNothing);
    expect(find.text('60'), findsNothing);
    expect(_inBody('Basis: noch 3 Nächte'), findsNWidgets(3), reason: 'HRV, Ruhepuls, Atemfrequenz');
  });

  testWidgets('week footer keeps legends and omits overview explanations', (tester) async {
    await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected), size: const Size(393, 3000));
    final segments = find.byType(OBSegmented);
    expect(find.textContaining('dein Normalbereich'), findsWidgets);
    await tester.ensureVisible(segments);
    await tester.tap(find.descendant(of: segments, matching: find.text('Belastung')));
    await tester.pumpAndSettle();
    expect(find.text('Skala 0–21 · kein Normalbereich'), findsNothing);
    await tester.tap(find.descendant(of: segments, matching: find.text('Schlaf')));
    await tester.pumpAndSettle();
    expect(find.text('Ziel 7h45'), findsWidgets);
    expect(find.text('Erholung: noch keine Werte'), findsNothing);
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
    expect(tester.widget<OBSyncState>(find.byType(OBSyncState)).text, 'Noch kein Band verbunden');
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
    expect(tester.widget<OBSyncState>(find.byType(OBSyncState)).text, 'Getrennt · Daten bis gestern 23:10');
    expect(find.text('Band nicht verbunden'), findsOneWidget);
    expect(find.text('Keine Erholung für heute'), findsOneWidget);
    expect(find.text('Heute keine Notiz'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('9,4'), findsNothing);
    expect(find.text('Noch keine Aktivität heute'), findsNothing, reason: 'not transferred is not none');
    expect(find.text('AKTIVITÄT'), findsNothing);
    await tester.tap(find.text('Verbinden'));
    expect(h.connects, 1);
  });

  testWidgets('stale band: activities stored before the gap still show', (tester) async {
    await _pump(
      tester,
      _Harness(
        _Repo(SyntheticScenario.g3Sample),
        BandSnapshot(batteryPercent: 64, latestStoredAt: DateTime(2026, 9, 28, 23, 10), receivedAt: DateTime(2026, 9, 28, 23, 10)),
      ),
      size: const Size(393, 3000),
    );
    expect(find.text('Band nicht verbunden'), findsOneWidget);
    expect(find.text('AKTIVITÄT'), findsOneWidget);
    expect(find.textContaining('07:58–08:40'), findsOneWidget);
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

  testWidgets('a failed sleep-plan read keeps the armed reminder', (tester) async {
    final repo = _Repo(SyntheticScenario.g3Sample);
    final h = await _pump(tester, _Harness(repo, _connected));
    await tester.tap(find.text('Erinnern'));
    await tester.pumpAndSettle();
    repo.planThrows = true;
    await h.controller.refresh();
    await tester.pumpAndSettle();
    expect(await h.reminder.armedAt(), DateTime(2026, 9, 29, 22, 5));
    expect(h.reminder.cancels, 0);
    // The read works again and today's plan still has the action: kept.
    repo.planThrows = false;
    await h.controller.refresh();
    await tester.pumpAndSettle();
    expect(h.reminder.cancels, 0);
    expect(find.text('Erinnerung um 22:05'), findsOneWidget);
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

  testWidgets('check-in: yesterday questions say so and write to yesterday; Später parks it', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected), size: const Size(393, 3000));
    expect(find.text('2 von 4'), findsOneWidget);
    expect(find.text('zu gestern'), findsOneWidget);
    expect(find.text('Stimmung: 4 von 5'), findsOneWidget, reason: 'mood belongs to today');
    expect(find.text('Alkohol am Abend?'), findsOneWidget);
    await tester.tap(find.text('Nein'));
    await tester.pumpAndSettle();
    expect((await h.repo.readJournalDay('2026-09-28')).metrics['alcohol_evening']?.value, 0);
    expect((await h.repo.readJournalDay(_day)).metrics['alcohol_evening'], isNull);
    expect(find.text('3 von 4'), findsOneWidget);
    expect(find.text('zu gestern'), findsOneWidget);
    expect(find.text('Alkohol am Abend: Nein'), findsOneWidget);
    expect(find.text('Koffein nach 14 Uhr?'), findsOneWidget);
    await tester.tap(find.text('Später'));
    await tester.pumpAndSettle();
    expect(find.text('Für später gemerkt. Kein Nachteil, wenn du es auslässt.'), findsOneWidget);
    expect(find.text('Jetzt'), findsOneWidget);
  });

  testWidgets('check-in: Ändern opens the journal on the answer\'s own day', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected), size: const Size(393, 3000));
    // Mood belongs to today.
    expect(find.text('Stimmung: 4 von 5'), findsOneWidget);
    await tester.tap(find.text('Ändern'));
    expect(h.journalDays, [_day]);
    // Alcohol in the evening belongs to yesterday: edit 28.09, not today.
    await tester.tap(find.text('Nein'));
    await tester.pumpAndSettle();
    expect(find.text('Alkohol am Abend: Nein'), findsOneWidget);
    await tester.tap(find.text('Ändern'));
    expect(h.journalDays, [_day, '2026-09-28']);
  });

  testWidgets('check-in: the note is saved to yesterday and completes the card', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected), size: const Size(393, 3000));
    await tester.tap(find.text('Ja'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nein'));
    await tester.pumpAndSettle();
    expect(find.text('4 von 4'), findsOneWidget);
    expect(find.text('zu gestern'), findsOneWidget);
    expect(find.text('Noch etwas zum Tag?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Spät gegessen');
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect((await h.repo.readJournalDay('2026-09-28')).note, 'Spät gegessen');
    expect((await h.repo.readJournalDay('2026-09-28')).metrics['alcohol_evening']?.value, 1);
    expect(find.text('CHECK-IN'), findsNothing, reason: 'all four answered');
  });

  testWidgets('check-in: a rating and a count with an explicit "Keins"', (tester) async {
    final h = await _pump(tester, _Harness(_TypedCheckInRepo(), _connected), size: const Size(393, 3000));
    final repo = h.repo as _TypedCheckInRepo;
    expect(find.text('1 von 2'), findsOneWidget);
    expect(find.text('zu gestern'), findsNothing, reason: 'mood is today: no target shown');
    expect(find.text('Wie ist deine Stimmung?'), findsOneWidget);
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();
    expect(repo.written.single.$2, 'mood');
    expect((repo.written.single.$3 as G3RatingAnswer).value, 4);

    expect(find.text('2 von 2'), findsOneWidget);
    expect(find.text('zu gestern'), findsOneWidget);
    expect(find.text('Stimmung: 4 von 5'), findsOneWidget);
    expect(find.text('Wie viel Alkohol?'), findsOneWidget);
    expect(find.text('—'), findsWidgets, reason: 'unanswered, not zero');
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pump();
    expect(find.text('Keins'), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final (day, key, answer) = repo.written.last;
    expect((day, key), (_day, 'alcohol_units'));
    expect((answer as G3QuantityAnswer).value, 0);
    expect(find.text('CHECK-IN'), findsNothing);
  });

  testWidgets('an auto-detected run is confirmed from its sheet', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected), size: const Size(393, 3000));
    expect(find.text('auto-erkannt'), findsOneWidget);
    expect(find.text('Lauf'), findsOneWidget, reason: 'the name Training uses');
    expect(find.text('Laufen'), findsNothing);
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

  testWidgets('Ändern stores the sport; a reopened sheet and Stimmt keep it', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected), size: const Size(393, 3000));
    await tester.tap(find.textContaining('07:58–08:40'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Ändern')));
    await tester.pumpAndSettle();
    // Training's sport picker, in its order.
    final picker = find.descendant(of: find.byType(BottomSheet).last, matching: find.byType(Text));
    final labels = tester.widgetList<Text>(picker).map((t) => t.data).whereType<String>().toList();
    const training = ['Lauf', 'Rad', 'Gehen', 'Wandern', 'Kraft', 'Schwimmen', 'Yoga', 'Tennis', 'Sonstiges'];
    expect(labels.where(training.contains).toList(), training);
    await tester.tap(find.text('Rad'));
    await tester.pumpAndSettle();
    expect((await h.repo.readActivities(_day)).single.sport, 'cycling');
    // Close without confirming, then reopen from the refreshed list.
    Navigator.of(tester.element(find.text('Automatisch erkannt'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('07:58–08:40'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('Rad')), findsOneWidget);
    await tester.tap(find.text('Stimmt'));
    await tester.pumpAndSettle();
    final a = (await h.repo.readActivities(_day)).single;
    expect(a.confirmed, isTrue);
    expect(a.sport, 'cycling');
  });

  testWidgets('a past day has no note, no check-in and says it is stored', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected), size: const Size(393, 3000));
    await h.controller.selectDay('2026-09-27');
    await tester.pumpAndSettle();
    expect(find.text('Sonntag'), findsOneWidget);
    expect(tester.widget<OBSyncState>(find.byType(OBSyncState)).text, 'Gespeicherter Tag');
    expect(find.text('FÜR HEUTE'), findsNothing);
    expect(find.text('CHECK-IN'), findsNothing);
    expect(find.text('Heute'), findsNothing, reason: 'no "Heute" week label on a past day');
  });

  testWidgets('"vor N Tagen" counts calendar days across the DST change (29.03.2026)', (tester) async {
    // Meaningful in a zone with DST on 29.03 (Europe/Berlin on the dev
    // machine): a local 30.03−28.03 span is 47 h there.
    final h = _Harness(_Repo(SyntheticScenario.g3Sample), _connected)..clock = DateTime(2026, 3, 30, 9, 41);
    await _pump(tester, h);
    await h.controller.selectDay('2026-03-28');
    await tester.pumpAndSettle();
    expect(find.text('28. März · vor 2 Tagen'), findsOneWidget);
    await h.controller.selectDay('2026-03-29');
    await tester.pumpAndSettle();
    expect(find.text('29. März · gestern'), findsOneWidget);
  });

  testWidgets('steps: stored spans only, split across hours, no zero fill', (tester) async {
    DateTime at(int h, [int m = 0]) => DateTime(2026, 9, 29, h, m);
    await _pump(
      tester,
      _Harness(
        _StepsRepo([
          StepInterval(at(8), at(9), 600),
          StepInterval(at(9, 30), at(10, 30), 400), // crosses 10:00
          StepInterval(at(12), at(13), 0), // a stored zero
        ]),
        _connected,
      ),
      size: const Size(393, 3000),
    );
    final hourly = tester.widget<OBStepsCard>(find.byType(OBStepsCard)).hourly;
    expect(hourly[8], 600);
    expect(hourly[9], 200);
    expect(hourly[10], 200);
    expect(hourly[12], 0);
    for (final h in [0, 7, 11, 13, 23]) {
      expect(h < hourly.length ? hourly[h] : null, isNull, reason: 'no span stored for $h:00');
    }
  });

  testWidgets('a past day keeps its stored timestamp in the sync line', (tester) async {
    final repo = _Repo(SyntheticScenario.g3Sample)..lastSamples['2026-09-27'] = DateTime(2026, 9, 27, 23, 58);
    final h = await _pump(tester, _Harness(repo, _connected));
    await h.controller.selectDay('2026-09-27');
    await tester.pumpAndSettle();
    expect(tester.widget<OBSyncState>(find.byType(OBSyncState)).text, 'Gespeicherter Tag · Daten bis So 27.09 23:58');
    expect(find.textContaining('Letzter Bandwert'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('So 27.09'), findsOneWidget);
    expect(find.text('vor 2 Tagen · SYNTHETISCHE DATEN'), findsOneWidget);
  });

  testWidgets('scrolled: the compact header is opaque, content does not show through', (tester) async {
    await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected));
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    final header = find.byType(OBPageHeader);
    expect(header, findsOneWidget, reason: 'the compact header replaces the hub');
    // The header's own surface (its root container), not a capsule inside it.
    final surface = tester.widget<Container>(find.descendant(of: header, matching: find.byType(Container)).first);
    final fill = (surface.decoration as BoxDecoration?)?.color;
    expect(fill, isNotNull);
    expect(fill!.a, 1.0);
  });

  testWidgets('the lead opens its detail', (tester) async {
    final h = await _pump(tester, _Harness(_Repo(SyntheticScenario.g3Sample), _connected));
    await tester.tap(find.text('ERHOLUNG'));
    expect(h.opened, [G3Metric.recovery]);
  });

  testWidgets('gallery: a G3 scenario opens Heute on 29.09 with note and check-in', (tester) async {
    tester.view.physicalSize = const Size(393, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = (await tester.runAsync(loadGalleryRepository))!;
    await tester.pumpWidget(OpenBandGallery(repository: repository));
    await tester.pumpAndSettle();
    expect(find.text('FÜR HEUTE'), findsNothing, reason: 'the 18.09 gallery clock has no G3 day');
    await tester.tap(find.text('Synthetische Galerie'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('G3 · Tagesblatt'));
    await tester.pumpAndSettle();
    expect(find.text('Dienstag, 29. September'), findsOneWidget);
    expect(find.text('FÜR HEUTE'), findsOneWidget);
    expect(find.text('Gut erholt.'), findsOneWidget);
    expect(find.text('CHECK-IN'), findsOneWidget);
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
