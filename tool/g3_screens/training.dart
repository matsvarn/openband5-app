// G3 training frames, keyed by the Paper registry for tool/g3_review_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/manual_session.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/g3_theme.dart';
import 'package:openstrap_edge/openband/g3/charts.dart' show OBTrendPeriod;
import 'package:openstrap_edge/openband/g3/screens/training_live.dart';
import 'package:openstrap_edge/openband/g3/screens/training_manual.dart';
import 'package:openstrap_edge/openband/g3/screens/training_screen.dart';
import 'package:openstrap_edge/openband/g3/training_parts.dart';
import 'package:openstrap_edge/openband/run_live.dart';
import 'package:openstrap_edge/openband/screens.dart' show OpenBandOverview;
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/tab_bar.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';
import 'env.dart';

final Map<String, G3ScreenBuilder> trainingScreens = {
  for (final name
      in (jsonDecode(
                File(
                  'docs/openband5/design/paper-g3/screens/training.json',
                ).readAsStringSync(),
              )
              as Map)
          .keys
          .cast<String>())
    name: (env) =>
        env.real &&
            !(name.contains('wurzel-hell') ||
                name.contains('wurzel-dunkel') ||
                name.contains('wurzel-gescrollt') ||
                name.contains('lauf-ergebnis') ||
                name.contains('belastung-'))
        ? null
        : _TrainingFrame(name, env),
};

G3ScreenBuilder g31TrainingBuilder(String legacyName) =>
    (env) => _TrainingFrame(legacyName, env, g31: true);

class _TrainingFrame extends StatefulWidget {
  final String name;
  final G3Env env;
  final bool g31;
  const _TrainingFrame(this.name, this.env, {this.g31 = false});

  @override
  State<_TrainingFrame> createState() => _TrainingFrameState();
}

class _TrainingFrameState extends State<_TrainingFrame> {
  late final Future<void> ready = initializeDateFormatting('de_DE');
  final scrolled = ScrollController(initialScrollOffset: 655);
  final detailScrolled = ScrollController(initialScrollOffset: 700);
  final savedScrolled = ScrollController(initialScrollOffset: 1050);
  late final SyntheticOpenBandRepository fixtureRepo =
      widget.name.contains('noch-keine-aktivitaet')
      ? _FirstUseRepo(_fixture('day-summary'), _fixture('sleep-detail'))
      : _TrainingFixtureRepo(
          _fixture('day-summary'),
          _fixture('sleep-detail'),
          scenario: widget.name.contains('im-aufbau')
              ? SyntheticScenario.g3Building
              : SyntheticScenario.g3Sample,
          savedYoga: widget.name.contains('nachtragen-gespeichert'),
          g31: widget.g31,
        );
  late final OpenBandRepository repo = widget.env.repository(() => fixtureRepo);
  late final OpenBandController controller = OpenBandController(
    repository: repo,
    initialDay: widget.env.day('2026-09-29'),
    band: widget.env.band(() => fixtureRepo.band),
    now: widget.env.now(() => DateTime(2026, 9, 29, 9, 41)),
  );

  @override
  void initState() {
    super.initState();
    controller.refresh();
  }

  @override
  void dispose() {
    controller.dispose();
    scrolled.dispose();
    detailScrolled.dispose();
    savedScrolled.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: ready,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return const SizedBox.shrink();
      }
      final name = widget.name;
      if (name.contains('nachtragen-gespeichert')) {
        return _wrap(
          context,
          G3TrainingScreen(
            controller: controller,
            scrollController: savedScrolled,
            onBand: widget.g31 ? () {} : null,
            onProfile: widget.g31 ? () {} : null,
            onDataStatus: widget.g31 ? () {} : null,
          ),
          toast: 'Yoga nachgetragen · Mo 28.09',
          onToast: () async {
            final all = await repo.readActivities('2026-09-28');
            final yoga = all.where((a) => a.sport == 'yoga').firstOrNull;
            if (yoga != null && context.mounted) {
              await Navigator.of(
                context,
              ).push(g3ActivityResultRoute(repository: repo, activity: yoga));
            }
          },
        );
      }
      if (name.contains('live-gespeichert')) {
        return FutureBuilder<List<G3Activity>>(
          future: repo.readActivities(widget.env.day('2026-09-29')),
          builder: (context, snap) {
            if (!snap.hasData || snap.data!.isEmpty) {
              return const SizedBox.shrink();
            }
            final base = snap.data!.first;
            return _wrap(
              context,
              G3ActivityScreen(
                repository: repo,
                activity: G3Activity(
                  id: 'saved-ride',
                  sport: 'cycling',
                  source: G3ActivitySource.live,
                  confirmed: true,
                  start: DateTime(2026, 9, 29, 17, 40),
                  end: DateTime(2026, 9, 29, 18, 14),
                  strain: 3.8,
                  avgHr: 136,
                  maxHr: 158,
                  zoneMinutes: const [3, 8, 16, 7, 0],
                  zoneBasis: base.zoneBasis,
                  hrTrace: [
                    for (final point in base.hrTrace.take(68))
                      G3HrPoint(
                        DateTime(
                          2026,
                          9,
                          29,
                          17,
                          40,
                        ).add(point.at.difference(base.start)),
                        point.meanBpm,
                      ),
                  ],
                  opticalShare: 1,
                ),
              ),
            );
          },
        );
      }
      if (name.contains('live-') || name.contains('laeuft-leiste')) {
        if (name.contains('laeuft-leiste')) {
          return _wrap(
            context,
            OpenBandOverview(controller: controller, reduced: true),
            liveBar: true,
            statusTime: '18:12',
          );
        }
        final strength = name.contains('kraft');
        final paused = name.contains('pausiert');
        final finishing =
            name.contains('beenden') ||
            name.contains('wird-gespeichert') ||
            name.contains('speichern-fehlgeschlagen');
        final run = ValueNotifier(
          LiveRun(
            elapsedSec: strength
                ? 1450
                : finishing
                ? 2040
                : 1925,
            heartRate: name.contains('signal-schwach')
                ? null
                : strength
                ? 124
                : paused
                ? 118
                : 141,
            zone: name.contains('signal-schwach')
                ? null
                : strength
                ? 2
                : paused
                ? null
                : 3,
            zoneSet: ana.HeartRateZones.zonesFromMaxHr(186, source: 'tanaka'),
            strain: strength
                ? 1.9
                : name.contains('signal-schwach')
                ? 3.6
                : 3.8,
            maxHrSeen: strength ? 131 : 158,
            averageHr: strength ? 118 : 136,
            startedAt: DateTime(2026, 9, 29, 17, strength ? 48 : 40),
            paused: paused,
          ),
        );
        return _wrap(
          context,
          G3LiveRun(
            run: run,
            sport: strength ? 'strength' : 'cycling',
            onPause: () {},
            onResume: () {},
            onFinish: () async {},
            initiallyFinishing: finishing,
            initiallySaving: name.contains('wird-gespeichert'),
            initiallyFailed: name.contains('speichern-fehlgeschlagen'),
          ),
          tabs: false,
          statusTime: finishing ? '18:14' : '18:12',
        );
      }
      if (name.contains('nachtragen-') && !name.contains('schwimmen')) {
        final overlap = name.contains('ueberschneidung');
        final start = overlap
            ? DateTime(2026, 9, 29, 7, 50)
            : DateTime(2026, 9, 28, 20);
        final end = overlap
            ? DateTime(2026, 9, 29, 8, 35)
            : DateTime(2026, 9, 28, 20, 40);
        return _wrap(
          context,
          G3ManualFlow(
            recentRepository: repo,
            now: () => DateTime(2026, 9, 29, 9, 41),
            initialStep: name.contains('pruefen') || overlap
                ? 2
                : name.contains('zeitraum')
                ? 1
                : 0,
            initialStart: start,
            initialEnd: end,
            initialSpans: overlap
                ? [
                    SessionSpan(
                      'run',
                      DateTime(2026, 9, 29, 7, 58).millisecondsSinceEpoch ~/
                          1000,
                      DateTime(2026, 9, 29, 8, 40).millisecondsSinceEpoch ~/
                          1000,
                    ),
                  ]
                : const [],
          ),
          tabs: false,
        );
      }
      if (name.contains('belastung-')) {
        return FutureBuilder<(List<G3Activity>, G3WeeklyLoad)>(
          future: (() async => (
            await repo.readActivities(widget.env.day('2026-09-29')),
            await repo.readWeeklyLoad(widget.env.day('2026-09-29')),
          ))(),
          builder: (context, snap) => !snap.hasData
              ? const SizedBox.shrink()
              : _wrap(
                  context,
                  G3LoadScreen(
                    controller: controller,
                    activity: snap.data!.$1.firstOrNull,
                    weekly: snap.data!.$2,
                    initialPeriod: name.contains('7-tage')
                        ? OBTrendPeriod.d7
                        : OBTrendPeriod.d30,
                  ),
                ),
        );
      }
      if (name.contains('ergebnis') ||
          name.contains('zonen-abgelehnt') ||
          name.contains('pulsreserve') ||
          name.contains('kein-training') ||
          name.contains('pulserholung') ||
          name.contains('bandpuls') ||
          name.contains('sportart-geaendert') ||
          name.contains('sportart-aendern')) {
        return FutureBuilder<List<G3Activity>>(
          future: repo.readActivities(widget.env.day('2026-09-29')),
          builder: (context, snap) {
            if (!snap.hasData || snap.data!.isEmpty) {
              return const SizedBox.shrink();
            }
            final base = snap.data!.first;
            if (widget.env.real) {
              return _wrap(
                context,
                G3ActivityScreen(repository: repo, activity: base),
              );
            }
            final manual = name.contains('bandpuls');
            final reserve = name.contains('pulsreserve');
            final changed = name.contains('sportart-geaendert');
            final refused = name.contains('zonen-abgelehnt');
            final noRecovery = name.contains('pulserholung');
            final start = reserve
                ? DateTime(2026, 9, 28, 17, 35)
                : refused
                ? DateTime(2026, 9, 26, 16)
                : manual
                ? DateTime(2026, 9, 25, 7, 10)
                : base.start;
            final end = reserve
                ? DateTime(2026, 9, 28, 18, 20)
                : refused
                ? DateTime(2026, 9, 26, 17, 25)
                : manual
                ? DateTime(2026, 9, 25, 7, 55)
                : base.end;
            return _wrap(
              context,
              G3ActivityScreen(
                repository: repo,
                latestStoredAt: widget.g31
                    ? DateTime(2026, 9, 29, 9, 38)
                    : null,
                now: widget.g31 ? DateTime(2026, 9, 29, 9, 41) : null,
                initialSheet: name.contains('sportart-aendern')
                    ? 'sport'
                    : name.contains('kein-training')
                    ? 'dismiss'
                    : null,
                initialSportSelection: name.contains('sportart-aendern')
                    ? 'cycling'
                    : null,
                scrollController: name.contains('gescrollt')
                    ? detailScrolled
                    : null,
                activity: G3Activity(
                  id: base.id,
                  sport: reserve
                      ? 'cycling'
                      : manual
                      ? 'swimming'
                      : refused
                      ? 'tennis'
                      : changed || noRecovery
                      ? 'cycling'
                      : base.sport,
                  source: manual ? G3ActivitySource.manual : base.source,
                  confirmed:
                      (widget.g31 && name.contains('lauf-ergebnis')) ||
                      reserve ||
                      manual ||
                      changed ||
                      noRecovery ||
                      refused,
                  start: start,
                  end: end,
                  strain: refused || manual ? null : base.strain,
                  avgHr: manual
                      ? null
                      : refused
                      ? 139
                      : base.avgHr,
                  maxHr: manual
                      ? null
                      : refused
                      ? 149
                      : base.maxHr,
                  zoneMinutes: widget.g31 && name.contains('lauf-ergebnis')
                      ? const [3, 9, 17, 11, 2]
                      : refused || manual
                      ? null
                      : reserve
                      ? const [14, 17, 10, 3, 0]
                      : changed
                      ? const [0, 4, 19, 16, 3]
                      : base.zoneMinutes,
                  zoneBasis: widget.g31 && name.contains('lauf-ergebnis')
                      ? const G3ZoneBasis(G3ZoneBasisKind.hfmaxEstimated, 186)
                      : reserve
                      ? const G3ZoneBasis(G3ZoneBasisKind.heartRateReserve, 191)
                      : base.zoneBasis,
                  hrTrace: manual
                      ? const []
                      : refused
                      ? _tennisTrace(start)
                      : reserve
                      ? [
                          for (final point in base.hrTrace)
                            G3HrPoint(
                              start.add(point.at.difference(base.start)),
                              point.meanBpm,
                            ),
                        ]
                      : base.hrTrace,
                  signalGaps: refused
                      ? _tennisGaps(start)
                      : reserve
                      ? [
                          for (final gap in base.signalGaps)
                            G3SignalGap(
                              start.add(gap.start.difference(base.start)),
                              start.add(gap.end.difference(base.start)),
                            ),
                        ]
                      : base.signalGaps,
                  opticalShare: refused
                      ? .41
                      : manual
                      ? null
                      : base.opticalShare,
                  hrRecoveryOneMinute: noRecovery || manual
                      ? null
                      : base.hrRecoveryOneMinute,
                  priorHrrCount: widget.g31 ? base.priorHrrCount : null,
                ),
              ),
            );
          },
        );
      }
      return _wrap(
        context,
        G3TrainingScreen(
          controller: controller,
          scrollController: name.contains('gescrollt') ? scrolled : null,
          onBand: widget.g31 ? () {} : null,
          onProfile: widget.g31 ? () {} : null,
          onDataStatus: widget.g31 ? () {} : null,
        ),
      );
    },
  );
}

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(
        File('docs/openband5/assets/fixtures/$name.json').readAsStringSync(),
      )
      as Map,
);

const _tennisSegments = [9, 5, 6, 7, 4, 9, 7, 11, 4, 8, 5, 10];

List<G3SignalGap> _tennisGaps(DateTime start) {
  final gaps = <G3SignalGap>[];
  var elapsed = 0;
  for (final (index, length) in _tennisSegments.indexed) {
    if (index.isOdd) {
      gaps.add(
        G3SignalGap(
          start.add(Duration(minutes: elapsed)),
          start.add(Duration(minutes: elapsed + length)),
        ),
      );
    }
    elapsed += length;
  }
  return gaps;
}

List<G3HrPoint> _tennisTrace(DateTime start) {
  final points = <G3HrPoint>[];
  var elapsed = 0;
  for (final (index, length) in _tennisSegments.indexed) {
    if (index.isEven) {
      for (var minute = 0; minute < length; minute++) {
        final t = elapsed + minute;
        points.add(
          G3HrPoint(
            start.add(Duration(minutes: t)),
            (133 + (t * 3) % 17).toDouble(),
          ),
        );
      }
    }
    elapsed += length;
  }
  return points;
}

class _TrainingFixtureRepo extends SyntheticOpenBandRepository {
  final bool savedYoga;
  final bool g31;
  _TrainingFixtureRepo(
    super.summary,
    super.detail, {
    required super.scenario,
    this.savedYoga = false,
    this.g31 = false,
  }) : super.fromMaps();

  @override
  Future<G3Trend> readTrend(G3Metric metric, String endDay, int days) async {
    if (g31 && metric == G3Metric.strain && days == 30) {
      final labels = g3DaysEnding(endDay, days);
      const values = <double?>[
        9.2,
        10.1,
        11.8,
        null,
        9.0,
        11.3,
        7.9,
        10.0,
        12.5,
        9.8,
        7.3,
        11.8,
        9.9,
        8.6,
        10.9,
        13.5,
        3.9,
        9.6,
        10.6,
        11.7,
        8.9,
        15.2,
        10.2,
        8.5,
        12.0,
        10.3,
        null,
        4.3,
        11.0,
        9.4,
      ];
      return g3Trend(metric, [
        for (var i = 0; i < days; i++) MetricPoint(labels[i], values[i]),
      ], const G3Baseline(BaselineStatus(BaselinePhase.none)));
    }
    if (metric == G3Metric.strain &&
        days == 7 &&
        scenario != SyntheticScenario.g3Building) {
      final labels = g3DaysEnding(endDay, 7);
      final values = g31
          ? const <double?>[8.2, 12.6, 10.1, null, 4.3, 11.0, 9.4]
          : const <double?>[8.6, 12.4, 6.1, 13.8, 11.2, 7.3, 9.4];
      return g3Trend(metric, [
        for (var i = 0; i < 7; i++) MetricPoint(labels[i], values[i]),
      ], const G3Baseline(BaselineStatus(BaselinePhase.none)));
    }
    return super.readTrend(metric, endDay, days);
  }

  @override
  Future<G3WeeklyLoad> readWeeklyLoad(String endDay) async {
    final dates = g3DaysEnding(endDay, 7);
    final values = scenario == SyntheticScenario.g3Building
        ? const <double?>[null, null, null, null, null, null, 9.4]
        : g31
        ? const <double?>[8.2, 12.6, 10.1, null, 4.3, 11.0, 9.4]
        : const <double?>[8.6, 12.4, 6.1, 13.8, 11.2, 7.3, 9.4];
    final days = [for (var i = 0; i < 7; i++) MetricPoint(dates[i], values[i])];
    if (scenario == SyntheticScenario.g3Building) {
      return G3WeeklyLoad(
        days,
        refusalNote: 'need_baseline:have=11,need=14',
        daysHave: 11,
        daysNeed: 14,
      );
    }
    return G3WeeklyLoad(days, atl: 64, ctl: 51);
  }

  @override
  Future<List<G3Activity>> readActivities(String day) async {
    final activities = await super.readActivities(day);
    if (day != '2026-09-29') {
      final prior = g31
          ? switch (day) {
              '2026-09-28' => ('cycling', 20, 9, 55, 8.4),
              '2026-09-25' => ('strength', 8, 0, 42, 4.9),
              _ => null,
            }
          : switch (day) {
              '2026-09-28' => ('cycling', 17, 35, 45, 4.2),
              '2026-09-27' => ('hiking', 10, 20, 90, 8.4),
              '2026-09-26' => ('tennis', 16, 0, 85, null),
              '2026-09-25' => ('swimming', 7, 10, 45, null),
              '2026-09-24' => ('running', 8, 0, 45, 7.0),
              _ => null,
            };
      if (prior == null) return activities;
      final start = DateTime(
        int.parse(day.substring(0, 4)),
        int.parse(day.substring(5, 7)),
        int.parse(day.substring(8, 10)),
        prior.$2,
        prior.$3,
      );
      return [
        if (savedYoga && day == '2026-09-28')
          G3Activity(
            id: 'saved-yoga',
            sport: 'yoga',
            source: G3ActivitySource.manual,
            confirmed: true,
            start: DateTime(2026, 9, 28, 20),
            end: DateTime(2026, 9, 28, 20, 40),
            strain: 1.1,
          ),
        G3Activity(
          id: 'fixture-$day',
          sport: prior.$1,
          source: prior.$1 == 'swimming'
              ? G3ActivitySource.manual
              : G3ActivitySource.live,
          confirmed: true,
          start: start,
          end: start.add(Duration(minutes: prior.$4)),
          strain: prior.$5,
          zoneMinutes: g31
              ? day == '2026-09-28'
                    ? const [4, 7, 19, 19, 6]
                    : const [1, 5, 17, 16, 3]
              : null,
          opticalShare: prior.$1 == 'tennis' ? .41 : null,
        ),
      ];
    }
    final values =
        (jsonDecode(
                  File(
                    'docs/openband5/assets/fixtures/training-hr.json',
                  ).readAsStringSync(),
                )
                as List)
            .cast<List>();
    return [
      for (final a in activities)
        G3Activity(
          id: a.id,
          sport: a.sport,
          source: a.source,
          confirmed: a.confirmed,
          start: a.start,
          end: a.end,
          strain: a.strain,
          avgHr: a.avgHr,
          maxHr: a.maxHr,
          zoneMinutes: a.zoneMinutes,
          zoneBasis: a.zoneBasis,
          hrTrace: [
            for (final pair in values)
              G3HrPoint(
                a.start.add(
                  Duration(
                    milliseconds: ((pair[0] as num).toDouble() * 60000).round(),
                  ),
                ),
                (pair[1] as num).toDouble(),
              ),
          ],
          signalGaps: a.signalGaps,
          opticalShare: a.opticalShare,
          hrRecoveryOneMinute: a.hrRecoveryOneMinute,
          priorHrrCount: a.priorHrrCount,
        ),
    ];
  }
}

class _FirstUseRepo extends SyntheticOpenBandRepository {
  _FirstUseRepo(super.summary, super.detail)
    : super.fromMaps(scenario: SyntheticScenario.g3Sample);

  @override
  Future<List<G3Activity>> readActivities(String day) async => const [];

  @override
  Future<G3WeeklyLoad> readWeeklyLoad(String endDay) async => G3WeeklyLoad([
    for (final (index, day) in g3DaysEnding(endDay, 7).indexed)
      MetricPoint(day, const [6.2, 7.9, 5.1, 8.4, 4.7, 6.6, 2.8][index]),
  ]);

  @override
  Future<OpenBandDay> readDay(String day) async => OpenBandDay(
    day: day,
    strain: const DayMetric(2.8),
    synthetic: true,
    calculatedAt: DateTime(2026, 9, 29, 9, 38),
  );
}

Widget _wrap(
  BuildContext context,
  Widget screen, {
  bool tabs = true,
  bool liveBar = false,
  String statusTime = '9:41',
  String? toast,
  VoidCallback? onToast,
}) {
  final g = G3.of(context);
  return ColoredBox(
    color: g.page,
    child: Column(
      children: [
        SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(36, 16, 28, 0),
            child: Row(
              children: [
                Text(statusTime, style: g.t(16, 20, weight: FontWeight.w700)),
                const Spacer(),
                Icon(LucideIcons.signal, size: 16, color: g.ink),
                const SizedBox(width: 7),
                Icon(LucideIcons.wifi, size: 17, color: g.ink),
                const SizedBox(width: 7),
                Icon(LucideIcons.batteryFull, size: 20, color: g.ink),
              ],
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: screen,
                ),
              ),
              if (tabs)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 24,
                  child: OBTabBar(
                    domains: const [
                      ShellDomain.home,
                      ShellDomain.sleep,
                      ShellDomain.workout,
                      ShellDomain.wellness,
                    ],
                    selected: liveBar ? ShellDomain.home : ShellDomain.workout,
                    onSelect: (_) {},
                  ),
                ),
              if (liveBar)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 105,
                  child: OBSessionMiniBar(
                    sport: 'cycling',
                    elapsed: '32:05',
                    heartRate: 141,
                    zone: 3,
                    onTap: () {},
                  ),
                ),
              if (toast != null)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 105,
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: g.ink,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.check, size: 18, color: g.page),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(toast, style: g.t(14, 18, color: g.page)),
                        ),
                        TextButton(
                          onPressed: onToast,
                          child: Text(
                            'Ansehen',
                            style: g.t(
                              14,
                              18,
                              color: g.page,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 142,
                right: 142,
                bottom: 6,
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: g.ink,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
