// G3 heute screen builders for tool/g3_review_test.dart, keyed like
// docs/openband5/design/paper-g3/screens/heute.json. Contract: see the top of
// tool/g3_review_test.dart and tool/g3_screens/env.dart.
//
// The synthetic G3 scenarios cover 29.09 in the trusted and the building
// state. The other Paper states (a past day, never connected, a stale band,
// a night with a gap) and the night timeline are layered on here from the
// same Paper values; the app never reads this file.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/screens/heute.dart';
import 'package:openstrap_edge/openband/release_scope.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';

import 'env.dart';

Map _json(String name) =>
    jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync())
        as Map;

const _today = '2026-09-29';
DateTime _at(int d, int h, int m) => DateTime(2026, 9, d, h, m);

/// Paper's night (23:10–06:54): stage, minutes.
const _hyp = [
  (NightStage.awake, 5),
  (NightStage.light, 20),
  (NightStage.deep, 35),
  (NightStage.light, 40),
  (NightStage.rem, 15),
  (NightStage.light, 30),
  (NightStage.deep, 25),
  (NightStage.light, 35),
  (NightStage.awake, 4),
  (NightStage.rem, 25),
  (NightStage.light, 40),
  (NightStage.deep, 8),
  (NightStage.light, 30),
  (NightStage.rem, 30),
  (NightStage.awake, 6),
  (NightStage.light, 32),
  (NightStage.rem, 28),
  (NightStage.light, 20),
  (NightStage.rem, 25),
  (NightStage.awake, 11),
];

/// Segments from minute 0; a gap (from, to) is an unobserved interval.
List<NightSegment> _segments({(int, int)? gap}) {
  final onset = _at(28, 23, 10);
  final out = <NightSegment>[];
  var t = 0;
  for (final (stage, m) in _hyp) {
    final a = t, b = t + m;
    t = b;
    DateTime at(int x) => onset.add(Duration(minutes: x));
    if (gap != null && a < gap.$2 && b > gap.$1) {
      if (a < gap.$1) out.add(NightSegment(at(a), at(gap.$1), stage));
      if (b > gap.$2) out.add(NightSegment(at(gap.$2), at(b), stage));
      continue;
    }
    out.add(NightSegment(at(a), at(b), stage));
  }
  if (gap != null) {
    out
      ..add(
        NightSegment(
          onset.add(Duration(minutes: gap.$1)),
          onset.add(Duration(minutes: gap.$2)),
          null,
        ),
      )
      ..sort((x, y) => x.start.compareTo(y.start));
  }
  return out;
}

enum _State { canonical, building, past, never, stale, gap }

/// The design repository plus the Paper-only states.
class _HeuteFixture extends SyntheticOpenBandRepository {
  _HeuteFixture(this.state)
    : super.fromMaps(
        _json('day-summary.json'),
        _json('sleep-detail.json'),
        scenario: state == _State.building
            ? SyntheticScenario.g3Building
            : SyntheticScenario.g3Sample,
      );
  final _State state;

  @override
  Future<OpenBandDay> readDay(String day) async {
    if (state == _State.never || (state == _State.stale && day == _today)) {
      return OpenBandDay(day: day, synthetic: true);
    }
    if (state == _State.past && day == '2026-09-27') {
      return OpenBandDay(
        day: day,
        sleep: const SleepNight(
          duration: DayMetric(372),
          bedMinutes: 398,
          awakeMinutes: 26,
        ),
        recovery: const DayMetric(49),
        strain: const DayMetric(11.2),
        synthetic: true,
      );
    }
    final d = await super.readDay(day);
    if (day != _today) return d;
    final gap = state == _State.gap;
    return OpenBandDay(
      day: d.day,
      sleep: SleepNight(
        onset: _at(28, 23, 10),
        wake: _at(29, 6, 54),
        duration: DayMetric(gap ? 391 : d.sleep.duration.value),
        bedMinutes: 464,
        awakeMinutes: gap ? 25 : 26,
        deepMinutes: gap ? 55 : 68,
        lightMinutes: gap ? 225 : 247,
        remMinutes: gap ? 111 : 123,
        unobservedMinutes: gap ? 48 : null,
        segments: _segments(gap: gap ? (171, 219) : null),
      ),
      recovery: gap ? const DayMetric(69) : d.recovery,
      strain: d.strain,
      hrv: d.hrv,
      restingHr: d.restingHr,
      respiration: d.respiration,
      skinTemperature: d.skinTemperature,
      steps: d.steps,
      stepIntervals: d.stepIntervals,
      calculatedAt: d.calculatedAt,
      synthetic: true,
    );
  }

  @override
  Future<G3Baseline> readPersonalRange(G3Metric metric, String day) async {
    if (state == _State.past &&
        day == '2026-09-27' &&
        metric == G3Metric.recovery) {
      return const G3Baseline(
        BaselineStatus(BaselinePhase.trusted),
        range: PersonalRange(58, 80, 68),
      );
    }
    if (state == _State.never) {
      return const G3Baseline(BaselineStatus(BaselinePhase.none));
    }
    return super.readPersonalRange(metric, day);
  }

  /// Paper shows the 7h45 goal on every day; the design repository stores
  /// it from the design day only.
  @override
  Future<SleepGoalSnapshot> readSleepGoal(String day) =>
      super.readSleepGoal(_today);

  @override
  Future<List<G3Activity>> readActivities(String day) async =>
      state == _State.never || state == _State.stale
      ? const []
      : super.readActivities(day);

  @override
  Future<G3CheckIn> readCheckIn(String day) async =>
      state == _State.never ? G3CheckIn(day, const []) : super.readCheckIn(day);

  @override
  Future<G3WeekStrip> readWeekStrip(G3Metric metric, String endDay) async =>
      state == _State.never
      ? g3WeekStrip(metric, [
          for (final d in g3DaysEnding(endDay, 7)) MetricPoint(d, null),
        ])
      : super.readWeekStrip(metric, endDay);

  BandSnapshot get paperBand => switch (state) {
    _State.never => const BandSnapshot(),
    _State.stale => BandSnapshot(
      batteryPercent: 64,
      latestStoredAt: _at(28, 23, 10),
      receivedAt: _at(28, 23, 10),
    ),
    _ => BandSnapshot(
      connection: BandConnection.connected,
      batteryPercent: 64,
      latestStoredAt: _at(29, 9, 37),
      receivedAt: _at(29, 9, 38),
    ),
  };
}

class _NoReminder implements HeuteReminder {
  const _NoReminder();
  @override
  Future<DateTime?> armedAt() async => null;
  @override
  Future<bool> arm(DateTime at, String body) async => false;
  @override
  Future<void> cancel() async {}
}

class _HeuteFrame extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final DateTime Function() now;
  final BandSnapshot band;
  final HeuteAnchor? anchor;
  const _HeuteFrame(
    this.repository,
    this.day,
    this.now,
    this.band, {
    this.anchor,
  });
  @override
  State<_HeuteFrame> createState() => _HeuteFrameState();
}

class _HeuteFrameState extends State<_HeuteFrame> {
  late final controller = OpenBandController(
    repository: widget.repository,
    initialDay: widget.day,
    band: widget.band,
    now: widget.now,
  )..refresh();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppShell(
    domains: kOpenBandReleaseDomains,
    releaseStyle: true,
    builder: (_, d) => d == ShellDomain.home
        ? OpenBandHeute(
            controller: controller,
            initialAnchor: widget.anchor,
            reminder: const _NoReminder(),
            onProfile: () {},
            onBand: () {},
            onConnect: () {},
            onAddActivity: () {},
            onJournal: () {},
            onOpenMetric: (_) {},
            onOpenActivity: (_) {},
            onOpenSleep: () {},
          )
        : const SizedBox(),
  );
}

G3ScreenBuilder _frame(
  _State state, {
  String day = _today,
  HeuteAnchor? anchor,
  bool realToo = false,
}) => (env) {
  if (env.real && !realToo) return null;
  final fixture = _HeuteFixture(state);
  return _HeuteFrame(
    env.repository(() => fixture),
    env.day(day),
    env.now(() => _at(29, 9, 41)),
    env.band(() => fixture.paperBand),
    anchor: anchor,
  );
};

final Map<String, G3ScreenBuilder> heuteScreens = {
  'heute-hell': _frame(_State.canonical, realToo: true),
  'heute-dunkel': _frame(_State.canonical, realToo: true),
  'heute-gescrollt-hell': _frame(
    _State.canonical,
    anchor: HeuteAnchor.activity,
    realToo: true,
  ),
  'heute-basis-hell': _frame(_State.building),
  'heute-basis-dunkel': _frame(_State.building),
  'heute-vergangen-hell': _frame(_State.past, day: '2026-09-27'),
  'heute-kein-band-hell': _frame(_State.never),
  'heute-getrennt-hell': _frame(_State.stale),
  'heute-luecke-hell': _frame(_State.gap),
};
