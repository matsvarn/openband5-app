import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../data/day_label.dart';
import '../../controller.dart';
import '../../day_picker.dart';
import '../../domain.dart';
import '../../naps.dart';
import '../../night_signals.dart';
import '../../sleep_editor.dart';
import '../../sleep_goal.dart';
import '../../tab_bar.dart';
import '../chrome.dart' as chrome;
import '../day.dart' as day_parts;
import '../g3_theme.dart';
import '../sleep_parts.dart';

class G3SleepScreen extends StatefulWidget {
  const G3SleepScreen({
    super.key,
    required this.controller,
    this.asTab = false,
    this.scrollController,
  });
  final OpenBandController controller;
  final bool asTab;
  final ScrollController? scrollController;
  @override
  State<G3SleepScreen> createState() => _G3SleepScreenState();
}

class _SleepReads {
  _SleepReads(OpenBandController controller)
    : selectedDay = controller.selectedDay,
      day = controller.day,
      plus = controller.repository.readSleepPlus(
        controller.selectedDay,
        now: controller.now(),
      ),
      goal = controller.repository.readSleepGoal(controller.selectedDay),
      history = controller.repository.readMetricHistory(
        MetricKey.sleepDuration,
        controller.selectedDay,
        7,
      ),
      windows = _windows(controller.repository, controller.selectedDay);
  final String selectedDay;
  final OpenBandDay? day;
  final Future<G3SleepPlus> plus;
  final Future<SleepGoalSnapshot> goal;
  final Future<List<MetricPoint>> history;
  final Future<List<OBSleepWindow>> windows;

  static Future<List<OBSleepWindow>> _windows(
    OpenBandRepository repo,
    String endDay,
  ) async {
    final date = DateTime.parse(endDay);
    final result = <OBSleepWindow>[];
    for (var i = 6; i >= 0; i--) {
      final day = dayLabelOf(DateTime(date.year, date.month, date.day - i));
      try {
        final night = (await repo.readDay(day)).sleep;
        result.add((
          day: i == 0
              ? 'Heute'
              : DateFormat('EE', 'de_DE').format(DateTime.parse(day)),
          start: night.onset,
          end: night.wake,
          minutes: night.duration.value,
        ));
      } catch (_) {
        result.add((
          day: i == 0
              ? 'Heute'
              : DateFormat('EE', 'de_DE').format(DateTime.parse(day)),
          start: null,
          end: null,
          minutes: null,
        ));
      }
    }
    return result;
  }
}

class _G3SleepScreenState extends State<G3SleepScreen> {
  _SleepReads? _reads;
  OpenBandController get controller => widget.controller;

  _SleepReads get reads {
    final previous = _reads;
    if (previous == null ||
        previous.selectedDay != controller.selectedDay ||
        !identical(previous.day, controller.day)) {
      return _reads = _SleepReads(controller);
    }
    return previous;
  }

  void _push(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));
  void _goal() => Navigator.of(context)
      .push(
        MaterialPageRoute<void>(
          builder: (_) => OpenBandSleepGoal(
            repository: controller.repository,
            day: controller.selectedDay,
            synthetic: controller.day?.synthetic == true,
          ),
        ),
      )
      .then((_) {
        if (mounted) setState(() => _reads = null);
      });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final g = G3.of(context);
      final selected = controller.selectedDay;
      final night = controller.day?.sleep ?? const SleepNight();
      final current = reads;
      return Scaffold(
        key: const ValueKey('g3-sleep'),
        backgroundColor: g.page,
        body: SafeArea(
          child: ListView(
            controller: widget.scrollController,
            key: PageStorageKey('g3.sleep.$selected'),
            padding: EdgeInsets.only(
              bottom: widget.asTab ? kOBTabBarContentInset : 24,
            ),
            children: [
              const SizedBox(height: 6),
              chrome.OBPageHeader.hub(
                title: 'Schlaf',
                subtitle:
                    'Nacht zu ${DateFormat('EEEE, dd.MM', 'de_DE').format(DateTime.parse(selected))}',
                band: chrome.OBBandCapsule(
                  state: controller.band.connection == BandConnection.connected
                      ? chrome.OBBandState.live
                      : chrome.OBBandState.off,
                  battery: controller.band.batteryPercent,
                ),
                onTitle: () => chooseOpenBandDay(context, controller),
              ),
              chrome.OBSyncState(
                kind:
                    night.unobservedMinutes != null &&
                        night.unobservedMinutes! >= kSleepGapSignificantMinutes
                    ? chrome.OBSyncKind.partial
                    : chrome.OBSyncKind.past,
                text: controller.loadError != null
                    ? 'Daten konnten nicht geladen werden'
                    : night.unobservedMinutes != null &&
                          night.unobservedMinutes! >=
                              kSleepGapSignificantMinutes
                    ? 'Nacht mit Lücke'
                    : 'Nacht ${night.duration.value == null ? 'noch offen' : 'lückenlos'}',
                synthetic: controller.day?.synthetic == true,
                onTap: controller.loadError == null ? null : controller.refresh,
              ),
              const SizedBox(height: 14),
              if (controller.loadError != null)
                _inset(
                  chrome.OBErrorBlock(
                    title: 'Daten konnten nicht geladen werden',
                    reason: 'Bitte erneut versuchen.',
                    retryLabel: 'Erneut laden',
                    onRetry: controller.refresh,
                  ),
                ),
              if (controller.loading && controller.day == null)
                const Center(child: CircularProgressIndicator.adaptive()),
              FutureBuilder<SleepGoalSnapshot>(
                future: current.goal,
                builder: (context, goal) => _inset(
                  OBSleepLead(
                    minutes: controller.day == null
                        ? null
                        : night.duration.value,
                    goalMinutes: goal.hasError
                        ? null
                        : goal.data?.targetMinutes,
                    onGoal: _goal,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _inset(_night(context, night)),
              if (controller.day?.correction != null ||
                  controller.calculating) ...[
                const SizedBox(height: 12),
                _inset(
                  OBInlineNotice(
                    text: controller.calculating
                        ? 'Schlafzeiten gespeichert · wird neu ausgewertet'
                        : controller.day?.correction?.state ==
                              CorrectionState.complete
                        ? 'Von dir korrigiert'
                        : 'Auswertung pausiert',
                    action:
                        controller.day?.correction?.state ==
                            CorrectionState.failed
                        ? 'Erneut auswerten'
                        : null,
                    onAction: controller.day?.correction == null
                        ? null
                        : () =>
                              controller.calculate(controller.day!.correction!),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _section('IN DER NACHT'),
              _inset(_nightFacts(controller.day)),
              const SizedBox(height: 8),
              _inset(
                chrome.OBListRow(
                  icon: LucideIcons.heart,
                  title: 'Nachtverlauf Puls',
                  subtitle: 'Puls · HRV · Atmung',
                  onTap: () => _push(
                    OpenBandNightSignals(
                      repository: controller.repository,
                      day: selected,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _inset(
                chrome.OBListRow(
                  icon: LucideIcons.pencil,
                  title: 'Schlafzeiten ändern',
                  subtitle: 'Wenn Beginn oder Ende nicht stimmen',
                  onTap: () => _push(SleepEditor(controller: controller)),
                ),
              ),
              const SizedBox(height: 18),
              _section('RHYTHMUS · 7 NÄCHTE'),
              FutureBuilder<G3SleepPlus>(
                future: current.plus,
                builder: (context, plusSnap) {
                  final plus = plusSnap.hasError ? null : plusSnap.data;
                  return Column(
                    children: [
                      FutureBuilder<List<OBSleepWindow>>(
                        future: current.windows,
                        builder: (context, windows) => _inset(
                          OBSleepWindows(
                            windows: windows.data ?? const [],
                            regularity: plus?.regularity.value,
                            gate:
                                plus?.regularity.gate ??
                                (plusSnap.hasError ? 'Nicht verfügbar' : null),
                            onTap: () => _push(
                              G3SleepRegularity(
                                repository: controller.repository,
                                day: selected,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _inset(
                        OBSocialJetlag(
                          minutes: plus?.socialJetlag.value == null
                              ? null
                              : plus!.socialJetlag.value! * 60,
                          gate: plus?.socialJetlag.gate,
                          onTap: () => _push(
                            G3SleepRegularity(
                              repository: controller.repository,
                              day: selected,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _inset(
                        OBSleepDebt(
                          minutes: plus?.sleepDebt.debtHours == null
                              ? null
                              : plus!.sleepDebt.debtHours! * 60,
                          freeMinutes: plus?.sleepDebt.freeNightP75Hours == null
                              ? null
                              : plus!.sleepDebt.freeNightP75Hours! * 60,
                          usualMinutes:
                              plus?.sleepDebt.habitualMedianHours == null
                              ? null
                              : plus!.sleepDebt.habitualMedianHours! * 60,
                          gate: plus?.sleepDebt.refusalNote,
                          onTap: () => _push(
                            G3SleepDebtDetail(
                              repository: controller.repository,
                              day: selected,
                            ),
                          ),
                        ),
                      ),
                      if (selected == todayLabel(controller.now())) ...[
                        const SizedBox(height: 10),
                        _inset(
                          _tonight(
                            context,
                            plus,
                            onTap: () => _push(
                              G3SleepTonight(
                                repository: controller.repository,
                                day: selected,
                                now: controller.now,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              _section('NICKERCHEN'),
              _inset(
                chrome.OBListRow(
                  icon: LucideIcons.moon,
                  title: 'Nickerchen',
                  subtitle: 'Erkannte und eingetragene Ruhezeiten',
                  onTap: () => _push(OpenBandNaps(controller: controller)),
                ),
              ),
              const SizedBox(height: 18),
              _section('LETZTE 7 NÄCHTE'),
              FutureBuilder<List<MetricPoint>>(
                future: current.history,
                builder: (context, history) =>
                    _inset(_week(context, history.data)),
              ),
              chrome.OBFooterStamp(
                'Letzter Bandwert ${obSleepClock(controller.band.latestStoredAt)}',
                synthetic: controller.day?.synthetic == true,
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _inset(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: child,
  );
  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
    child: Builder(
      builder: (context) =>
          Text(title, style: G3.of(context).caps(color: G3.of(context).muted)),
    ),
  );

  Widget _night(BuildContext context, SleepNight night) {
    final g = G3.of(context);
    final duration = night.duration.value;
    final total =
        night.bedMinutes ??
        (night.onset != null && night.wake != null
            ? night.wake!.difference(night.onset!).inMinutes.toDouble()
            : null);
    final segments = <day_parts.OBStageSegment>[];
    final gaps = <(double, double)>[];
    if (night.onset != null && total != null && total > 0) {
      for (final segment in night.segments) {
        final start = segment.start.difference(night.onset!).inSeconds / 60;
        final end = segment.end.difference(night.onset!).inSeconds / 60;
        if (segment.stage == null) {
          gaps.add((start, end));
        } else {
          segments.add(
            day_parts.OBStageSegment(
              switch (segment.stage!) {
                NightStage.awake => day_parts.OBStage.wake,
                NightStage.rem => day_parts.OBStage.rem,
                NightStage.light => day_parts.OBStage.light,
                NightStage.deep => day_parts.OBStage.deep,
              },
              start,
              end,
            ),
          );
        }
      }
    }
    return chrome.OBPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('NACHT', style: g.caps()),
              const Spacer(),
              Text(
                duration == null
                    ? 'keine Nacht erkannt'
                    : night.unobservedMinutes != null &&
                          night.unobservedMinutes! >=
                              kSleepGapSignificantMinutes
                    ? '${obSleepDuration(night.unobservedMinutes)} Lücke'
                    : 'lückenlos',
                style: g.t(12, 16, color: g.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text(
                night.onset == null || night.wake == null
                    ? '—'
                    : '${obSleepClock(night.onset)}–${obSleepClock(night.wake)}',
                style: g.t(34, 39, weight: FontWeight.w700, tracking: -.04),
              ),
              if (total != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${obSleepDuration(total)} im Bett',
                    style: g.t(12, 16, color: g.ink2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (duration != null && total != null && segments.isNotEmpty)
            RepaintBoundary(
              child: day_parts.OBHypnogram(
                segments: segments,
                totalMinutes: total,
                gaps: gaps,
              ),
            )
          else
            G3Dashed(
              height: 84,
              child: Center(
                child: Text(
                  'Keine Schlafphasen vorhanden',
                  style: g.t(12, 16, color: g.muted),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final time in [
                night.onset,
                night.onset == null || night.wake == null
                    ? null
                    : night.onset!.add(
                        night.wake!.difference(night.onset!) ~/ 2,
                      ),
                night.wake,
              ])
                Text(obSleepClock(time), style: g.t(11, 15, color: g.muted)),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: g.line),
          const SizedBox(height: 12),
          day_parts.OBStageLegend([
            (
              'Tief',
              duration == null ? null : obSleepDuration(night.deepMinutes),
              g.stageDeep,
            ),
            (
              'Leicht',
              duration == null ? null : obSleepDuration(night.lightMinutes),
              g.stageLight,
            ),
            (
              'REM',
              duration == null ? null : obSleepDuration(night.remMinutes),
              g.stageRem,
            ),
            (
              'Wach',
              duration == null ? null : obSleepDuration(night.awakeMinutes),
              g.wake,
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            'Phasen aus Puls und Bewegung geschätzt. Tief ist am unsichersten.',
            style: g.t(12, 16, color: g.muted),
          ),
        ],
      ),
    );
  }

  Widget _nightFacts(OpenBandDay? day) {
    return Builder(
      builder: (context) {
        final g = G3.of(context);
        final values = [
          ('HRV · MS', day?.hrv.value, 0),
          ('RUHEPULS', day?.restingHr.value, 0),
          ('ATMUNG', day?.respiration.value, 1),
        ];
        return chrome.OBPanel(
          child: Row(
            children: [
              for (final (i, value) in values.indexed) ...[
                if (i > 0) Container(width: 1, height: 38, color: g.line),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value.$1,
                          style: g.t(
                            10,
                            14,
                            weight: FontWeight.w700,
                            color: g.muted,
                          ),
                        ),
                        Text(
                          value.$2 == null
                              ? '—'
                              : value.$2!
                                    .toStringAsFixed(value.$3)
                                    .replaceAll('.', ','),
                          style: g.t(22, 27, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _tonight(
    BuildContext context,
    G3SleepPlus? plus, {
    required VoidCallback onTap,
  }) {
    final g = G3.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Heute Nacht öffnen',
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: g.note,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('HEUTE NACHT', style: g.caps(color: g.noteMuted)),
              const SizedBox(height: 5),
              Text(
                plus?.bedtime == null
                    ? 'Kein Vorschlag'
                    : '${obSleepClock(plus!.bedtime)} ins Bett',
                style: g.t(21, 25, weight: FontWeight.w700, color: g.noteInk),
              ),
              const SizedBox(height: 5),
              Text(
                plus?.bedtime == null
                    ? 'Ohne Schlafziel oder belastbare Schätzung keine Bettzeit.'
                    : 'Geschätzter Bedarf ${obSleepDuration(plus!.needMinutes)}. Kann bis zum Abend steigen.',
                style: g.t(13, 17, color: g.noteInk2),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Plan ansehen  ›',
                  style: g.t(13, 17, weight: FontWeight.w700, color: g.noteInk),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _week(BuildContext context, List<MetricPoint>? points) {
    final g = G3.of(context);
    final values = points ?? const <MetricPoint>[];
    return chrome.OBPanel(
      child: SizedBox(
        height: 130,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final point in values)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    point.value == null
                        ? const G3Dashed(height: 60)
                        : Container(
                            height: (point.value! / 600 * 70).clamp(8, 70),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: point == values.last ? g.ink : g.bar,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat(
                        'EE',
                        'de_DE',
                      ).format(DateTime.parse(point.day)),
                      style: g.t(11, 15, color: g.muted),
                    ),
                    Text(
                      obSleepDuration(point.value),
                      style: g.t(11, 15, weight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class G3SleepRegularity extends StatelessWidget {
  const G3SleepRegularity({
    super.key,
    required this.repository,
    required this.day,
  });
  final OpenBandRepository repository;
  final String day;
  @override
  Widget build(BuildContext context) => _SleepDetail(
    title: 'REGELMÄSSIGKEIT',
    child: FutureBuilder<G3SleepPlus>(
      future: repository.readSleepPlus(day),
      builder: (context, snap) {
        final plus = snap.data;
        return Column(
          children: [
            OBSleepWindows(
              windows: const [],
              regularity: plus?.regularity.value,
              gate:
                  plus?.regularity.gate ??
                  (snap.hasError ? 'Nicht verfügbar' : null),
            ),
            const SizedBox(height: 12),
            OBSocialJetlag(
              minutes: plus?.socialJetlag.value == null
                  ? null
                  : plus!.socialJetlag.value! * 60,
              gate: plus?.socialJetlag.gate,
            ),
            const SizedBox(height: 12),
            Text(
              'Der SRI vergleicht Schlaf und Wachsein Minute für Minute über sieben bewertete Nächte.',
              style: G3.of(context).t(13, 18, color: G3.of(context).ink2),
            ),
          ],
        );
      },
    ),
  );
}

class G3SleepDebtDetail extends StatelessWidget {
  const G3SleepDebtDetail({
    super.key,
    required this.repository,
    required this.day,
  });
  final OpenBandRepository repository;
  final String day;
  @override
  Widget build(BuildContext context) => _SleepDetail(
    title: 'SCHLAFSCHULD',
    child: FutureBuilder<G3SleepPlus>(
      future: repository.readSleepPlus(day),
      builder: (context, snap) {
        final debt = snap.data?.sleepDebt;
        return Column(
          children: [
            OBSleepDebt(
              minutes: debt?.debtHours == null ? null : debt!.debtHours! * 60,
              freeMinutes: debt?.freeNightP75Hours == null
                  ? null
                  : debt!.freeNightP75Hours! * 60,
              usualMinutes: debt?.habitualMedianHours == null
                  ? null
                  : debt!.habitualMedianHours! * 60,
              gate:
                  debt?.refusalNote ??
                  (snap.hasError ? 'Nicht verfügbar' : null),
            ),
            const SizedBox(height: 12),
            Text(
              '75. Perzentil freier Nächte minus Median der letzten sieben Nächte. Kein gemessener Schlafbedarf.',
              style: G3.of(context).t(13, 18, color: G3.of(context).ink2),
            ),
          ],
        );
      },
    ),
  );
}

class G3SleepTonight extends StatefulWidget {
  const G3SleepTonight({
    super.key,
    required this.repository,
    required this.day,
    required this.now,
  });
  final OpenBandRepository repository;
  final String day;
  final DateTime Function() now;
  @override
  State<G3SleepTonight> createState() => _G3SleepTonightState();
}

class _G3SleepTonightState extends State<G3SleepTonight> {
  late Future<G3SleepPlus> plus = widget.repository.readSleepPlus(
    widget.day,
    now: widget.now(),
  );
  @override
  Widget build(BuildContext context) => _SleepDetail(
    title: 'HEUTE NACHT',
    child: FutureBuilder<G3SleepPlus>(
      future: plus,
      builder: (context, snap) {
        final value = snap.data;
        final g = G3.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            chrome.OBPanel(
              hero: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('INS BETT', style: g.caps()),
                  const SizedBox(height: 8),
                  Text(
                    obSleepClock(value?.bedtime),
                    style: g.t(
                      68,
                      74,
                      weight: FontWeight.w700,
                      tracking: -.045,
                    ),
                  ),
                  Text(
                    value?.bedtime == null
                        ? 'Kein Vorschlag'
                        : 'Schätzung · Belastung läuft',
                    style: g.t(13, 17, color: g.ink2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OBPlanBreakdown(
              goal: value?.goalMinutes,
              bonus: value?.strainBonusMinutes,
              napCredit: value?.napCreditMinutes,
              napsIncomplete: value?.napsIncomplete == true,
              need: value?.needMinutes,
              efficiency: value?.typicalEfficiency,
              wake: value?.wake,
              bedtime: value?.bedtime,
            ),
            const SizedBox(height: 12),
            Text(
              value?.bedtime == null
                  ? 'Ohne Schlafziel und aktuelle Schätzung keine Bettzeit.'
                  : 'Schätzung, kann sich bis zum Abend ändern.',
              style: g.t(13, 17, color: g.ink2),
            ),
          ],
        );
      },
    ),
  );
}

class _SleepDetail extends StatelessWidget {
  const _SleepDetail({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
          children: [
            chrome.OBPageHeader.detail(
              title: title,
              backLabel: 'Schlaf',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}
