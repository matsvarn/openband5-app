import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/g3_theme.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep_goal.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep_night.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep_naps.dart';
import 'package:openstrap_edge/openband/g3/screens/sleep_reminder.dart';
import 'package:openstrap_edge/openband/naps.dart';
import 'package:openstrap_edge/openband/sleep_editor.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/tab_bar.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';

import 'env.dart';

List<NightSegment> _g31NightSegments(DateTime onset) {
  const stages = <(NightStage, int)>[
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
  final out = <NightSegment>[];
  var minute = 0;
  for (final (stage, length) in stages) {
    out.add(
      NightSegment(
        onset.add(Duration(minutes: minute)),
        onset.add(Duration(minutes: minute + length)),
        stage,
      ),
    );
    minute += length;
  }
  return out;
}

G3ScreenBuilder g31SleepBuilder(String legacyName) =>
    (env) => _PaperSleepFrame(legacyName, env, g31: true);

final Map<String, G3ScreenBuilder> schlafScreens = {
  for (final name in const [
    'schlaf-letzte-nacht-hell',
    'schlaf-letzte-nacht-dunkel',
    'schlaf-gescrollt-hell',
    'schlaf-teilnacht-mit-luecke-hell',
    'schlaf-keine-nacht-erkannt-hell',
    'schlaf-rhythmus-im-aufbau-hell',
    'schlaf-kein-schlafziel-hell',
    'schlaf-kein-schlafziel-dunkel',
    'schlaf-korrigierte-nacht-hell',
    'schlaf-nachtverlauf-puls-hell',
    'schlaf-nachtverlauf-puls-dunkel',
    'schlaf-regelmaessigkeit-hell',
    'schlaf-schlafschuld-hell',
    'schlaf-heute-nacht-hell',
    'schlaf-heute-nacht-noch-keine-freie-nacht-hell',
    'schlaf-heute-nacht-erinnerung-gesetzt-hell',
    'schlaf-schlafziel-hell',
    'schlaf-schlafziel-festlegen-noch-kein-ziel-hell',
    'schlaf-schlafzeiten-aendern-entwurf-hell',
    'schlaf-schlafzeiten-aendern-wird-ausgewertet-hell',
    'schlaf-schlafzeiten-aendern-speicherfehler-hell',
    'schlaf-nickerchen-hell',
    'schlaf-nickerchen-keine-hell',
    'schlaf-nickerchen-eintragen-hell',
    'schlaf-neue-bausteine-vorschlag-schlaf',
  ])
    name: (env) =>
        env.real && _fixtureOnly(name) ? null : _PaperSleepFrame(name, env),
};

bool _fixtureOnly(String name) =>
    name.contains('teilnacht') ||
    name.contains('keine-nacht') ||
    name.contains('noch-keine-freie-nacht') ||
    name.contains('rhythmus-im') ||
    name.contains('korrigierte') ||
    name.contains('erinnerung-gesetzt') ||
    name.contains('schlafzeiten') ||
    name.contains('nickerchen-keine') ||
    name.contains('nickerchen-eintragen') ||
    name.contains('neue-bausteine');

class _PaperRepo extends SyntheticOpenBandRepository {
  _PaperRepo(this.state, Map summary, Map detail, {this.g31 = false})
    : super.fromMaps(summary, detail, scenario: SyntheticScenario.g3Sample);
  final String state;
  final bool g31;
  static const selected = '2026-09-29';
  static DateTime at(int day, int hour, int minute) =>
      DateTime(2026, 9, day, hour, minute);

  @override
  Future<SleepDraft?> readDraft(String day) async {
    if (day == selected && state.startsWith('edit_')) {
      return SleepDraft(
        id: 'paper-draft',
        day: day,
        onset: at(28, 22, 40),
        wake: at(29, 6, 54),
      );
    }
    return super.readDraft(day);
  }

  @override
  Future<NapDay> readNaps(String day) async {
    if (state == 'no_naps') return NapDay(day: day, judged: true, totalMin: 0);
    if (day == '2026-09-27') {
      return NapDay(
        day: day,
        judged: true,
        totalMin: 38,
        sessions: [
          NapSession(
            start: at(27, 14, 10),
            end: at(27, 14, 52),
            source: NapSource.detected,
            durationMin: 38,
          ),
        ],
      );
    }
    if (day == '2026-09-26') {
      return NapDay(
        day: day,
        judged: true,
        totalMin: 25,
        sessions: [
          NapSession(
            start: at(26, 15, 5),
            end: at(26, 15, 30),
            source: NapSource.manual,
            durationMin: 25,
          ),
        ],
      );
    }
    return NapDay(day: day, judged: true, totalMin: 0);
  }

  @override
  Future<NightSignals> readNightSignals(String day) async {
    if (day != selected) return super.readNightSignals(day);
    final start = at(28, 23, 10);
    final end = at(29, 6, 54);
    final lowAt = at(29, 3, 48);
    final lowMinute = lowAt.difference(start).inMinutes;
    final readings = <NightSignalReading>[];
    for (var i = 0; i <= end.difference(start).inMinutes; i++) {
      final time = start.add(Duration(minutes: i));
      if (!time.isBefore(at(29, 4, 12)) && time.isBefore(at(29, 4, 18))) {
        readings.add(NightSignalReading(time, null));
        continue;
      }
      final trend = i <= lowMinute
          ? 68 - 19 * i / lowMinute
          : 49 +
                15 *
                    (i - lowMinute) /
                    (end.difference(start).inMinutes - lowMinute);
      final ripple = i == lowMinute
          ? 0.0
          : math.sin(i * .13) * 1.1 + math.sin(i * .47) * .5;
      readings.add(
        NightSignalReading(
          time,
          g31 && i != lowMinute
              ? math.max(49.1, trend + ripple)
              : math.max(49, trend + ripple),
        ),
      );
    }
    return NightSignals(
      day: day,
      window: (start: start, end: end),
      synthetic: true,
      series: {
        NightSignalKind.pulse: NightSignalSeries(
          readings: readings,
          maxConnectingGap: const Duration(minutes: 2),
        ),
      },
    );
  }

  @override
  Future<OpenBandDay> readDay(String day) async {
    if (day != selected) {
      const nights = <String, (int, int, int, int, double)>{
        '2026-09-12': (22, 50, 6, 55, 485),
        '2026-09-13': (23, 20, 7, 10, 470),
        '2026-09-19': (22, 45, 7, 0, 495),
        '2026-09-20': (23, 15, 6, 50, 455),
        '2026-09-23': (23, 25, 6, 52, 422),
        '2026-09-24': (23, 58, 6, 50, 391),
        '2026-09-25': (23, 5, 7, 10, 460),
        '2026-09-26': (0, 40, 9, 12, 485),
        '2026-09-27': (1, 30, 8, 5, 372),
        '2026-09-28': (23, 20, 7, 12, 445),
      };
      final n = nights[day];
      if (n == null ||
          state == 'building' &&
              const {
                '2026-09-23',
                '2026-09-24',
                '2026-09-26',
                '2026-09-27',
              }.contains(day)) {
        return OpenBandDay(day: day, synthetic: true);
      }
      final wake = DateTime.parse(day);
      final bedDate = n.$1 < 12 ? wake : wake.subtract(const Duration(days: 1));
      return OpenBandDay(
        day: day,
        synthetic: true,
        sleep: SleepNight(
          onset: DateTime(bedDate.year, bedDate.month, bedDate.day, n.$1, n.$2),
          wake: DateTime(wake.year, wake.month, wake.day, n.$3, n.$4),
          duration: DayMetric(n.$5),
        ),
      );
    }
    final missing = state == 'missing';
    final partial = state == 'partial';
    final corrected = state == 'corrected';
    final start = at(28, corrected ? 22 : 23, corrected ? 40 : 10);
    final end = at(29, 6, 54);
    final segments = g31 && !corrected && !partial
        ? _g31NightSegments(start)
        : <NightSegment>[
            NightSegment(start, at(29, 0, 10), NightStage.light),
            NightSegment(at(29, 0, 10), at(29, 1, 10), NightStage.deep),
            NightSegment(at(29, 1, 10), at(29, 2, 1), NightStage.light),
            NightSegment(
              at(29, 2, 1),
              at(29, 2, 49),
              partial ? null : NightStage.rem,
            ),
            NightSegment(at(29, 2, 49), at(29, 4, 30), NightStage.light),
            NightSegment(at(29, 4, 30), at(29, 5, 25), NightStage.rem),
            NightSegment(at(29, 5, 25), end, NightStage.light),
          ];
    return OpenBandDay(
      day: day,
      synthetic: true,
      calculatedAt: at(29, 9, 38),
      sleep: missing
          ? const SleepNight()
          : SleepNight(
              onset: start,
              wake: end,
              duration: DayMetric(
                (corrected
                        ? 459
                        : partial
                        ? 391
                        : 438)
                    .toDouble(),
              ),
              bedMinutes: corrected ? 494 : 464,
              awakeMinutes: corrected ? 35 : 26,
              deepMinutes: 68,
              lightMinutes: corrected ? 268 : 247,
              remMinutes: 123,
              unobservedMinutes: partial ? 48 : null,
              segments: segments,
            ),
      hrv: missing ? const DayMetric.missing() : const DayMetric(48),
      restingHr: missing
          ? const DayMetric.missing()
          : const DayMetric(54, baseline: 53, baselineSpread: 3),
      respiration: missing ? const DayMetric.missing() : const DayMetric(15.8),
      correction: corrected
          ? SleepCorrection(
              id: 'paper',
              day: day,
              onset: start,
              wake: end,
              savedAt: at(29, 9, 20),
              revision: 1,
              state: CorrectionState.complete,
            )
          : null,
    );
  }

  @override
  Future<G3Baseline> readPersonalRange(G3Metric metric, String day) async {
    if (g31 && metric == G3Metric.rhr) {
      return const G3Baseline(
        BaselineStatus(BaselinePhase.trusted),
        range: PersonalRange(52, 58, 53),
      );
    }
    return super.readPersonalRange(metric, day);
  }

  @override
  Future<SleepGoalSnapshot> readSleepGoal(String day) async =>
      state == 'no_goal' ? const SleepGoalSnapshot() : super.readSleepGoal(day);

  @override
  Future<G3SleepPlus> readSleepPlus(String day, {DateTime? now}) async {
    final building = state == 'building' || state == 'no_free';
    final noGoal = state == 'no_goal';
    return G3SleepPlus(
      regularity: G3AvailableValue(
        building ? null : 78,
        gate: building ? 'Braucht 7 bewertete Nächte, noch 4.' : null,
      ),
      socialJetlag: G3AvailableValue(
        building ? null : 1 + 40 / 60,
        gate: building ? 'Braucht freie und Arbeitstage.' : null,
      ),
      socialJetlagDetail: building
          ? null
          : const G3SocialJetlagDetail(signedHours: 1 + 40 / 60),
      sleepDebt: building
          ? const G3SleepDebt(
              habitualMedianHours: 7 + 25 / 60,
              hasFreeNight: false,
              refusalNote: 'Noch keine freie Nacht.',
            )
          : const G3SleepDebt(
              freeNightP75Hours: 7 + 31 / 60,
              habitualMedianHours: 7 + 18 / 60,
              debtHours: 13 / 60,
              hasFreeNight: true,
            ),
      bedtime: building ? null : at(29, 22, 19),
      wake: building ? null : at(30, 6, 54),
      needMinutes: building ? null : 484,
      goalMinutes: noGoal ? null : 465,
      baselineOsdMinutes: building ? null : 451,
      appliedDebtMinutes: building ? null : 13,
      strainBonusMinutes: building ? null : 20,
      napCreditMinutes: null,
      napsJudged: building ? null : false,
    );
  }

  @override
  Future<List<MetricPoint>> readMetricHistory(
    MetricKey key,
    String endDay,
    int nights,
  ) async {
    if (key != MetricKey.sleepDuration) {
      return super.readMetricHistory(key, endDay, nights);
    }
    const minutes = [422.0, 391.0, 460.0, 485.0, 372.0, 445.0, 438.0];
    return [
      for (var i = 0; i < 7; i++)
        MetricPoint(
          '2026-09-${(23 + i).toString().padLeft(2, '0')}',
          state == 'building' && const {0, 1, 3, 4}.contains(i)
              ? null
              : minutes[i],
        ),
    ];
  }
}

class _PaperSleepFrame extends StatefulWidget {
  const _PaperSleepFrame(this.name, this.env, {this.g31 = false});
  final String name;
  final G3Env env;
  final bool g31;
  @override
  State<_PaperSleepFrame> createState() => _PaperSleepFrameState();
}

class _PaperSleepFrameState extends State<_PaperSleepFrame> {
  late final String state;
  late final OpenBandRepository repo;
  late final OpenBandController controller;
  late final ScrollController scroll;
  late final MemorySleepBedtimeReminder reminder;

  @override
  void initState() {
    super.initState();
    final name = widget.name;
    reminder = MemorySleepBedtimeReminder();
    if (name.contains('erinnerung-gesetzt')) {
      reminder.current = (
        at: _PaperRepo.at(29, 22, 5),
        day: _PaperRepo.selected,
      );
    }
    state = name.contains('teilnacht')
        ? 'partial'
        : name.contains('noch-keine-freie-nacht')
        ? 'no_free'
        : name.contains('keine-nacht')
        ? 'missing'
        : name.contains('rhythmus-im')
        ? 'building'
        : name.contains('kein-schlafziel') || name.contains('noch-kein-ziel')
        ? 'no_goal'
        : name.contains('korrigierte')
        ? 'corrected'
        : name.contains('schlafzeiten-aendern-entwurf')
        ? 'edit_draft'
        : name.contains('schlafzeiten-aendern-wird-ausgewertet')
        ? 'edit_processing'
        : name.contains('schlafzeiten-aendern-speicherfehler')
        ? 'edit_error'
        : name.contains('nickerchen-keine')
        ? 'no_naps'
        : 'canonical';
    repo = widget.env.repository(() {
      final summary =
          jsonDecode(
                File(
                  'docs/openband5/assets/fixtures/day-summary.json',
                ).readAsStringSync(),
              )
              as Map;
      final detail =
          jsonDecode(
                File(
                  'docs/openband5/assets/fixtures/sleep-detail.json',
                ).readAsStringSync(),
              )
              as Map;
      return _PaperRepo(state, summary, detail, g31: widget.g31);
    });
    controller = OpenBandController(
      repository: repo,
      initialDay: widget.env.day(_PaperRepo.selected),
      now: widget.env.now(() => DateTime(2026, 9, 29, 9, 41)),
      band: widget.env.band(
        () => BandSnapshot(
          connection: BandConnection.connected,
          batteryPercent: 64,
          latestStoredAt: DateTime(2026, 9, 29, 9, widget.g31 ? 38 : 37),
        ),
      ),
    );
    scroll = ScrollController();
    controller.refresh();
    if (name.contains('gescrollt') || name.contains('rhythmus-im')) {
      _scrollToRhythm(6);
    }
    if (name == 'schlaf-schlafziel-hell' ||
        name == 'schlaf-schlafziel-festlegen-noch-kein-ziel-hell') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          G3SleepGoalSheet.show(context, repo, controller.selectedDay);
        }
      });
    }
    if (name == 'schlaf-nickerchen-eintragen-hell') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            barrierColor: Colors.black.withValues(alpha: .32),
            backgroundColor: Colors.transparent,
            builder: (_) =>
                OpenBandNapEditor(controller: controller, g3Sheet: true),
          );
        }
      });
    }
  }

  void _scrollToRhythm(int frames) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (scroll.hasClients) {
        final back = widget.name.contains('rhythmus-im') ? 180.0 : 0.0;
        scroll.jumpTo(
          (scroll.position.maxScrollExtent - back).clamp(
            0.0,
            scroll.position.maxScrollExtent,
          ),
        );
      }
      if (frames > 0) _scrollToRhythm(frames - 1);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    scroll.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    final content = name.contains('nachtverlauf')
        ? G3SleepNightSignals(
            repository: repo,
            day: controller.selectedDay,
            storedAt: controller.band.latestStoredAt,
            now: controller.now,
          )
        : name.contains('regelmaessigkeit')
        ? G3SleepRegularity(repository: repo, day: controller.selectedDay)
        : name.contains('schlafschuld')
        ? G3SleepDebtDetail(repository: repo, day: controller.selectedDay)
        : name.contains('heute-nacht')
        ? G3SleepTonight(
            repository: repo,
            day: controller.selectedDay,
            now: controller.now,
            reminder: reminder,
          )
        : name.contains('schlafzeiten')
        ? SleepEditor(
            controller: controller,
            g3: true,
            initialReceipt: state == 'edit_processing'
                ? SleepCorrection(
                    id: 'paper-correction',
                    day: controller.selectedDay,
                    onset: _PaperRepo.at(28, 22, 40),
                    wake: _PaperRepo.at(29, 6, 54),
                    savedAt: _PaperRepo.at(29, 9, 41),
                    revision: 1,
                    state: CorrectionState.pending,
                  )
                : null,
            initialSaveError: state == 'edit_error'
                ? 'Speichern fehlgeschlagen.'
                : null,
          )
        : name.contains('nickerchen-')
        ? G3SleepNaps(controller: controller)
        : G3SleepScreen(
            controller: controller,
            asTab: true,
            scrollController: scroll,
            reminder: reminder,
            onBand: widget.g31 ? () {} : null,
            onProfile: widget.g31 ? () {} : null,
            onDataStatus: widget.g31 ? () {} : null,
          );
    final g = G3.of(context);
    return Stack(
      children: [
        content,
        Positioned(
          left: 30,
          top: 19,
          child: Text('9:41', style: g.t(15, 19, weight: FontWeight.w700)),
        ),
        Positioned(
          right: 30,
          top: 19,
          child: widget.g31
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.signal, size: 16, color: g.ink),
                    const SizedBox(width: 7),
                    Icon(LucideIcons.wifi, size: 17, color: g.ink),
                    const SizedBox(width: 7),
                    Icon(LucideIcons.batteryFull, size: 20, color: g.ink),
                  ],
                )
              : Text('▮▮  ◕  ▰', style: g.t(14, 18, weight: FontWeight.w700)),
        ),
        if (!name.contains('schlafzeiten') &&
            !name.contains('schlafziel') &&
            !name.contains('nickerchen-eintragen'))
          Positioned(
            left: 20,
            right: 20,
            bottom: 22,
            child: OBTabBar(
              domains: const [
                ShellDomain.home,
                ShellDomain.sleep,
                ShellDomain.workout,
                ShellDomain.wellness,
              ],
              selected: ShellDomain.sleep,
              onSelect: (_) {},
            ),
          ),
        Positioned(
          left: 178,
          right: 178,
          bottom: 5,
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: g.ink,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ],
    );
  }
}
