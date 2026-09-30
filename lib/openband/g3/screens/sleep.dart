import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../data/day_label.dart';
import '../../controller.dart';
import '../../day_picker.dart';
import '../../domain.dart';
import '../../naps.dart' show OpenBandNapEditor;
import '../../sleep_editor.dart';
import '../../tab_bar.dart';
import '../../today_note.dart';
import '../../../notify/notification_center.dart';
import '../../../ui2/app_shell.dart' show pushFullScreen;
import '../chrome.dart' as chrome;
import '../count_copy.dart';
import '../day.dart' as day_parts;
import '../g3_format.dart';
import '../g3_theme.dart';
import '../metrics.dart' show OBMissingValue;
import '../sleep_parts.dart';
import 'sleep_goal.dart';
import 'sleep_night.dart';
import 'sleep_naps.dart';
import 'sleep_reminder.dart';

class G3SleepScreen extends StatefulWidget {
  const G3SleepScreen({
    super.key,
    required this.controller,
    this.asTab = false,
    this.scrollController,
    this.reminder,
    this.onProfile,
    this.onBand,
  });
  final OpenBandController controller;
  final bool asTab;
  final ScrollController? scrollController;
  final SleepBedtimeReminder? reminder;
  final VoidCallback? onProfile, onBand;
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
      baselines = Future.wait([
        controller.repository.readPersonalRange(
          G3Metric.hrv,
          controller.selectedDay,
        ),
        controller.repository.readPersonalRange(
          G3Metric.rhr,
          controller.selectedDay,
        ),
        controller.repository.readPersonalRange(
          G3Metric.respRate,
          controller.selectedDay,
        ),
      ]),
      windows = _windows(controller.repository, controller.selectedDay),
      naps = controller.repository.readNaps(controller.selectedDay);
  final String selectedDay;
  final OpenBandDay? day;
  final Future<G3SleepPlus> plus;
  final Future<SleepGoalSnapshot> goal;
  final Future<List<MetricPoint>> history;
  final Future<List<G3Baseline>> baselines;
  final Future<List<OBSleepWindow>> windows;
  final Future<NapDay> naps;

  static Future<List<OBSleepWindow>> _windows(
    OpenBandRepository repo,
    String endDay,
  ) {
    final date = DateTime.parse(endDay);
    Future<OBSleepWindow> read(int i) async {
      final day = dayLabelOf(DateTime(date.year, date.month, date.day - i));
      final label = i == 0
          ? 'Heute'
          : g3DayShort(DateTime.parse(day)).split(' ').first;
      try {
        final night = (await repo.readDay(day)).sleep;
        return (
          day: label,
          start: night.onset,
          end: night.wake,
          minutes: night.duration.value,
        );
      } catch (_) {
        return (day: label, start: null, end: null, minutes: null);
      }
    }

    return Future.wait([for (var i = 6; i >= 0; i--) read(i)]);
  }
}

class _G3SleepScreenState extends State<G3SleepScreen>
    with WidgetsBindingObserver {
  _SleepReads? _reads;
  Timer? _dayTimer;
  int _reminderGen = 0;
  late final ScrollController _ownedScroll = ScrollController();
  ScrollController get _scroll => widget.scrollController ?? _ownedScroll;
  bool _compact = false;
  OpenBandController get controller => widget.controller;
  late final SleepBedtimeReminder reminder =
      widget.reminder ?? NotificationSleepBedtimeReminder();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    _armDayRollover();
    unawaited(_reconcileDay());
  }

  @override
  void dispose() {
    _reminderGen++;
    WidgetsBinding.instance.removeObserver(this);
    _dayTimer?.cancel();
    _scroll.removeListener(_onScroll);
    _ownedScroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !_scroll.hasClients) return;
    final compact = _scroll.offset > 80;
    if (compact != _compact) setState(() => _compact = compact);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _armDayRollover();
      unawaited(_reconcileDay());
    }
  }

  void _armDayRollover() {
    _dayTimer?.cancel();
    final now = controller.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final delay = midnight.difference(now);
    _dayTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!mounted) return;
      unawaited(_reconcileDay());
      _armDayRollover();
    });
  }

  Future<void> _reconcileDay() async {
    if (controller.day?.synthetic == true) return;
    final generation = ++_reminderGen;
    if (!mounted || generation != _reminderGen) return;
    await reminder.reconcile(
      today: todayLabel(controller.now()),
      planLoaded: false,
      active: () => mounted && generation == _reminderGen,
    );
  }

  _SleepReads get reads {
    final previous = _reads;
    if (previous == null ||
        previous.selectedDay != controller.selectedDay ||
        !identical(previous.day, controller.day)) {
      final next = _reads = _SleepReads(controller);
      if (controller.day?.synthetic != true &&
          controller.selectedDay == todayLabel(controller.now())) {
        final generation = ++_reminderGen;
        unawaited(
          next.plus
              .then((plan) async {
                if (mounted &&
                    generation == _reminderGen &&
                    controller.selectedDay == next.selectedDay) {
                  await reminder.reconcile(
                    today: todayLabel(controller.now()),
                    planLoaded: true,
                    bedtime: plan.bedtime,
                    active: () => mounted && generation == _reminderGen,
                  );
                }
              })
              .catchError((Object _) {}),
        );
      }
      return next;
    }
    return previous;
  }

  void _push(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));
  void _editSleep() => unawaited(
    pushFullScreen<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SleepEditor(controller: controller, g3: true),
      ),
    ),
  );
  void _goal() =>
      G3SleepGoalSheet.show(
        context,
        controller.repository,
        controller.selectedDay,
      ).then((_) {
        if (mounted) setState(() => _reads = null);
      });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final g = G3.of(context);
      final selected = controller.selectedDay;
      final night = controller.day?.sleep ?? const SleepNight();
      final closed =
          selected != todayLabel(controller.now()) ||
          controller.day?.calculatedAt != null;
      final corrected =
          controller.day?.correction?.state == CorrectionState.complete;
      final dataThrough = g3DataThrough(
        controller.band.latestStoredAt,
        now: controller.now(),
      );
      final current = reads;
      return Scaffold(
        key: const ValueKey('g3-sleep'),
        backgroundColor: g.page,
        body: SafeArea(
          child: Stack(
            children: [
              ListView(
                controller: _scroll,
                key: PageStorageKey('g3.sleep.$selected'),
                padding: EdgeInsets.only(
                  bottom: widget.asTab ? kOBTabBarContentInset + 60 : 84,
                ),
                children: [
                  const SizedBox(height: 6),
                  chrome.OBPageHeader.hub(
                    title: 'Schlaf',
                    subtitle: g3NightOf(DateTime.parse(selected)),
                    band: chrome.OBBandCapsule(
                      state:
                          controller.band.connection == BandConnection.connected
                          ? chrome.OBBandState.live
                          : chrome.OBBandState.off,
                      battery: controller.band.batteryPercent,
                      onTap: widget.onBand,
                    ),
                    onTitle: () => chooseOpenBandDay(context, controller),
                    onProfile: widget.onProfile,
                  ),
                  chrome.OBSyncState(
                    kind:
                        night.unobservedMinutes != null &&
                            night.unobservedMinutes! >=
                                kSleepGapSignificantMinutes
                        ? chrome.OBSyncKind.partial
                        : chrome.OBSyncKind.past,
                    text: controller.loadError != null
                        ? 'Daten konnten nicht geladen werden'
                        : corrected
                        ? '$dataThrough · Nacht korrigiert'
                        : night.unobservedMinutes != null &&
                              night.unobservedMinutes! >=
                                  kSleepGapSignificantMinutes
                        ? '$dataThrough · Nacht mit Lücke'
                        : '$dataThrough · Nacht ${night.duration.value == null
                              ? closed
                                    ? 'keine Nacht'
                                    : 'noch offen'
                              : 'lückenlos'}',
                    synthetic: controller.day?.synthetic == true,
                    onTap:
                        widget.onBand ??
                        (controller.loadError == null
                            ? null
                            : controller.refresh),
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
                      Column(
                        children: [
                          OBSleepLead(
                            minutes: controller.day == null
                                ? null
                                : night.duration.value,
                            goalMinutes: goal.hasError
                                ? null
                                : goal.data?.targetMinutes,
                            bedMinutes: night.bedMinutes,
                            onGoal: goal.hasError ? null : _goal,
                          ),
                          if (goal.hasError) ...[
                            const SizedBox(height: 8),
                            chrome.OBErrorBlock(
                              title: 'Schlafziel nicht geladen',
                              reason: 'Bitte erneut versuchen.',
                              onRetry: () => setState(() => _reads = null),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (corrected ||
                      controller.calculating ||
                      controller.day?.correction?.state ==
                          CorrectionState.failed) ...[
                    _inset(
                      OBInlineNotice(
                        text: corrected
                            ? 'Von dir korrigiert'
                            : controller.calculating
                            ? 'Wird neu ausgewertet'
                            : 'Auswertung pausiert',
                        subtitle: corrected
                            ? 'Im Bett ab ${obSleepClock(controller.day?.correction?.onset)}'
                            : null,
                        icon: corrected ? LucideIcons.pencil : null,
                        action: corrected
                            ? 'Rückgängig'
                            : controller.day?.correction?.state ==
                                  CorrectionState.failed
                            ? 'Erneut auswerten'
                            : null,
                        onAction: corrected
                            ? () async {
                                await restoreAutomaticSleep(
                                  context,
                                  controller,
                                  selected,
                                  g3: true,
                                );
                              }
                            : controller.day?.correction == null
                            ? null
                            : () => controller.calculate(
                                controller.day!.correction!,
                              ),
                        actionChevron: false,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _inset(
                    _night(
                      context,
                      night,
                      closed: closed,
                      corrected: corrected,
                    ),
                  ),
                  if (closed && night.duration.value == null) ...[
                    const SizedBox(height: 12),
                    _inset(
                      chrome.OBEmptyState(
                        title: 'Doch geschlafen?',
                        reason:
                            'Trag Beginn und Ende ein. Die Nacht wird dann aus den Banddaten ausgewertet.',
                        action: 'Schlafzeiten eintragen',
                        onAction: _editSleep,
                      ),
                    ),
                  ],
                  const chrome.OBSectionHeader('IN DER NACHT'),
                  _inset(_nightFacts(controller.day, current.baselines)),
                  const SizedBox(height: 8),
                  _inset(
                    chrome.OBListRow(
                      icon: LucideIcons.heart,
                      title: 'Nachtverlauf Puls',
                      subtitle: 'Puls · HRV · Atmung',
                      onTap: () => _push(
                        G3SleepNightSignals(
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
                      onTap: _editSleep,
                    ),
                  ),
                  const chrome.OBSectionHeader('RHYTHMUS · 7 NÄCHTE'),
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
                                    (plusSnap.hasError
                                        ? 'Nicht verfügbar'
                                        : null),
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
                              minutes:
                                  plus?.socialJetlagDetail?.signedHours == null
                                  ? null
                                  : plus!.socialJetlagDetail!.signedHours! * 60,
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
                              freeMinutes:
                                  plus?.sleepDebt.freeNightP75Hours == null
                                  ? null
                                  : plus!.sleepDebt.freeNightP75Hours! * 60,
                              usualMinutes:
                                  plus?.sleepDebt.habitualMedianHours == null
                                  ? null
                                  : plus!.sleepDebt.habitualMedianHours! * 60,
                              gate: plus?.sleepDebt.debtHours == null
                                  ? plus?.sleepDebt.refusalNote
                                  : null,
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
                                lastOnset: night.onset,
                                error: plusSnap.hasError,
                                onTap: () => _push(
                                  G3SleepTonight(
                                    repository: controller.repository,
                                    day: selected,
                                    now: controller.now,
                                    reminder:
                                        widget.reminder ??
                                        (controller.day?.synthetic == true
                                            ? MemorySleepBedtimeReminder()
                                            : NotificationSleepBedtimeReminder()),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  chrome.OBSectionHeader(
                    'NICKERCHEN',
                    action: 'Eintragen',
                    onAction: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => OpenBandNapEditor(
                        controller: controller,
                        g3Sheet: true,
                      ),
                    ),
                  ),
                  FutureBuilder<NapDay>(
                    future: current.naps,
                    builder: (context, naps) => _inset(
                      chrome.OBListRow(
                        icon: LucideIcons.moon,
                        title: naps.data?.sessions.isEmpty == true
                            ? selected == todayLabel(controller.now())
                                  ? 'Heute noch keins'
                                  : 'Keins erkannt'
                            : 'Nickerchen',
                        subtitle: naps.data?.sessions.isEmpty == true
                            ? 'Noch keins erkannt'
                            : 'Erkannte und eingetragene Ruhezeiten',
                        onTap: () => _push(G3SleepNaps(controller: controller)),
                      ),
                    ),
                  ),
                  const chrome.OBSectionHeader('LETZTE 7 NÄCHTE'),
                  FutureBuilder<List<MetricPoint>>(
                    future: current.history,
                    builder: (context, history) =>
                        FutureBuilder<SleepGoalSnapshot>(
                          future: current.goal,
                          builder: (context, goal) => _inset(
                            _week(
                              context,
                              history.data,
                              goal.data?.targetMinutes,
                            ),
                          ),
                        ),
                  ),
                ],
              ),
              if (_compact)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: ColoredBox(
                    color: g.page.withValues(alpha: .95),
                    child: chrome.OBPageHeader.compact(
                      title: 'Schlaf',
                      subtitle:
                          '${g3NightOf(DateTime.parse(selected))}${controller.day?.synthetic == true ? ' · Synthetische Daten' : ''}',
                      band: chrome.OBBandCapsule(
                        state:
                            controller.band.connection ==
                                BandConnection.connected
                            ? chrome.OBBandState.live
                            : chrome.OBBandState.off,
                        battery: controller.band.batteryPercent,
                        small: true,
                        onTap: widget.onBand,
                      ),
                      onProfile: widget.onProfile,
                    ),
                  ),
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
  Widget _night(
    BuildContext context,
    SleepNight night, {
    required bool closed,
    required bool corrected,
  }) {
    final g = G3.of(context);
    final duration = night.duration.value;
    final total =
        night.bedMinutes ??
        (night.onset != null && night.wake != null
            ? night.wake!.difference(night.onset!).inMinutes.toDouble()
            : null);
    final segments = <day_parts.OBStageSegment>[];
    final gaps = <(double, double)>[];
    double? stagedMinutes(NightStage stage) => night.segments.isEmpty
        ? switch (stage) {
            NightStage.deep => night.deepMinutes,
            NightStage.light => night.lightMinutes,
            NightStage.rem => night.remMinutes,
            NightStage.awake => night.awakeMinutes,
          }
        : night.segments
              .where((s) => s.stage == stage)
              .fold<double>(
                0,
                (sum, s) => sum + s.end.difference(s.start).inSeconds / 60,
              );
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
    final gapCaption = [
      for (final (start, end) in gaps)
        '${obSleepClock(night.onset?.add(Duration(minutes: start.round())))}–${obSleepClock(night.onset?.add(Duration(minutes: end.round())))} ohne Daten',
    ].join(' · ');
    return chrome.OBPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('NACHT', style: g.caps()),
              if (duration == null ||
                  corrected ||
                  (night.unobservedMinutes != null &&
                      night.unobservedMinutes! >=
                          kSleepGapSignificantMinutes)) ...[
                const Spacer(),
                Text(
                  duration == null
                      ? closed
                            ? 'Band getragen'
                            : 'noch offen'
                      : corrected
                      ? 'korrigiert'
                      : night.unobservedMinutes != null &&
                            night.unobservedMinutes! >=
                                kSleepGapSignificantMinutes
                      ? '${obSleepDuration(night.unobservedMinutes)} Lücke'
                      : '',
                  style: g.t(12, 16, color: g.muted),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              night.onset == null || night.wake == null
                  ? const OBMissingValue(size: 34, lineHeight: 39)
                  : Text(
                      '${obSleepClock(night.onset)}–${obSleepClock(night.wake)}',
                      style: g.t(
                        34,
                        39,
                        weight: FontWeight.w700,
                        tracking: -.04,
                      ),
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
                  closed ? 'Keine Nacht erkannt' : 'Nacht noch offen',
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
          if (duration != null) ...[
            if (gaps.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '$gapCaption · nicht aufgefüllt',
                textAlign: TextAlign.center,
                style: g.t(12, 16, color: g.ink2),
              ),
            ],
            const SizedBox(height: 12),
            Divider(height: 1, color: g.line),
            const SizedBox(height: 12),
            day_parts.OBStageLegend([
              (
                'Tief',
                obSleepDuration(stagedMinutes(NightStage.deep)),
                g.stageDeep,
              ),
              (
                'Leicht',
                obSleepDuration(stagedMinutes(NightStage.light)),
                g.stageLight,
              ),
              (
                'REM',
                obSleepDuration(stagedMinutes(NightStage.rem)),
                g.stageRem,
              ),
              (
                'Wach',
                obSleepDuration(stagedMinutes(NightStage.awake)),
                g.wake,
              ),
            ]),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: chrome.OBLink(
                'Methode',
                onTap: () => _showSleepMethod(
                  context,
                  'Schlafphasen',
                  'Phasen aus Puls und Bewegung geschätzt. Tief ist am unsichersten. Fehlende Daten werden nicht aufgefüllt.',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _nightFacts(OpenBandDay? day, Future<List<G3Baseline>> baselines) {
    return FutureBuilder<List<G3Baseline>>(
      future: baselines,
      builder: (context, snapshot) {
        final g = G3.of(context);
        final values = [
          ('HRV · ms', day?.hrv.value, 0),
          ('RUHEPULS', day?.restingHr.value, 0),
          ('ATEMFREQUENZ', day?.respiration.value, 1),
        ];
        String basis(int index) {
          final baseline = snapshot.data?.elementAtOrNull(index);
          if (baseline == null) {
            return snapshot.hasError
                ? 'Basis nicht verfügbar'
                : 'Basis wird geladen';
          }
          return switch (baseline.status.phase) {
            BaselinePhase.trusted =>
              baseline.range == null
                  ? 'kein Normalbereich'
                  : 'eigener Normalbereich',
            BaselinePhase.building =>
              baseline.status.remaining == null
                  ? 'Basis im Aufbau'
                  : 'noch ${baseline.status.remaining} ${g3CountNoun(baseline.status.remaining!, 'Nacht', 'Nächte')}',
            BaselinePhase.none => 'kein Normalbereich',
          };
        }

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
                        value.$2 == null
                            ? const OBMissingValue(size: 22, lineHeight: 27)
                            : Text(
                                value.$2!
                                    .toStringAsFixed(value.$3)
                                    .replaceAll('.', ','),
                                style: g.t(22, 27, weight: FontWeight.w700),
                              ),
                        Text(
                          value.$2 == null ? 'keine Daten' : basis(i),
                          style: g.t(10, 14, color: g.muted),
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
    DateTime? lastOnset,
    required bool error,
    required VoidCallback onTap,
  }) {
    final g = G3.of(context);
    if (!error && plus?.bedtime == null) {
      return chrome.OBEmptyState(
        title: 'Heute Nacht: kein Vorschlag',
        reason: plus?.sleepDebt.hasFreeNight == false
            ? 'Noch keine freie Nacht für einen persönlichen Schlafbedarf.'
            : 'Kein gespeicherter Bedarf und keine Bettzeit für diesen Tag.',
      );
    }
    final shown = roundedSleepBedtime(plus?.bedtime);
    final difference = shown == null || lastOnset == null
        ? null
        : ((lastOnset.hour * 60 +
                      lastOnset.minute -
                      shown.hour * 60 -
                      shown.minute +
                      720) %
                  1440) -
              720;
    final headline = error
        ? 'Plan nicht geladen'
        : difference == null
        ? '${obSleepClock(shown)} ins Bett'
        : '${obSleepDuration(difference.abs())} ${difference >= 0 ? 'früher' : 'später'} ins Bett.';
    return GestureDetector(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Heute Nacht öffnen',
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 18, 14),
          decoration: BoxDecoration(
            color: g.note,
            borderRadius: BorderRadius.circular(22),
            boxShadow: g.noteShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('HEUTE NACHT', style: g.caps(color: g.noteMuted)),
              const SizedBox(height: 5),
              Text(
                headline,
                style: g.t(21, 25, weight: FontWeight.w700, color: g.noteInk),
              ),
              const SizedBox(height: 5),
              Text(
                error
                    ? 'Bitte erneut versuchen.'
                    : plus?.bedtime == null
                    ? plus?.sleepDebt.hasFreeNight == false
                          ? 'Noch keine freie Nacht für einen persönlichen Schlafbedarf.'
                          : 'Kein gespeicherter Schlafbedarf für diesen Tag.'
                    : 'Geschätzter Bedarf ${obSleepDuration(plus!.needMinutes)}. Belastung kann bis zum Abend steigen.',
                style: g.t(13, 17, color: g.noteInk2),
              ),
              if (shown != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: g.noteInset,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.moon, size: 18, color: g.noteInk),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${obSleepClock(shown)} ins Bett',
                              style: g.t(
                                14,
                                18,
                                weight: FontWeight.w700,
                                color: g.noteInk,
                              ),
                            ),
                            Text(
                              'für ${obSleepDuration(plus?.needMinutes)} Schlafbedarf bis ${obSleepClock(plus?.wake)}',
                              style: g.t(11, 15, color: g.noteInk2),
                            ),
                          ],
                        ),
                      ),
                      chrome.OBPillButton('Ansehen', onPressed: onTap),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _week(
    BuildContext context,
    List<MetricPoint>? points,
    int? goalMinutes,
  ) {
    final values = points ?? const <MetricPoint>[];
    final measured = values.where((point) => point.value != null).toList();
    final average = measured.length == 7
        ? measured.map((point) => point.value!).reduce((a, b) => a + b) / 7
        : null;
    return day_parts.OBWeekBars(
      bars: [
        for (final point in values)
          day_parts.OBWeekBar(
            point == values.last
                ? 'Heute'
                : g3DayShort(DateTime.parse(point.day)).split(' ').first,
            point.value,
            label: obSleepDuration(point.value),
            today: point == values.last,
          ),
      ],
      max: 600,
      goal: goalMinutes?.toDouble(),
      labelsBelow: true,
      footer: [
        goalMinutes == null
            ? const day_parts.G3Legend.text('kein Ziel gesetzt')
            : day_parts.G3Legend.goal('Ziel ${obSleepDuration(goalMinutes)}'),
        day_parts.G3Legend.text(
          average == null ? 'Ø —' : 'Ø ${obSleepDuration(average)}',
        ),
      ],
    );
  }
}

class G3SleepRegularity extends StatefulWidget {
  const G3SleepRegularity({
    super.key,
    required this.repository,
    required this.day,
  });
  final OpenBandRepository repository;
  final String day;
  @override
  State<G3SleepRegularity> createState() => _G3SleepRegularityState();
}

class _G3SleepRegularityState extends State<G3SleepRegularity> {
  late final Future<G3SleepPlus> _plus = widget.repository.readSleepPlus(
    widget.day,
  );
  late final Future<List<OBSleepWindow>> _windows = _SleepReads._windows(
    widget.repository,
    widget.day,
  );

  @override
  Widget build(BuildContext context) => _SleepDetail(
    title: 'REGELMÄSSIGKEIT',
    subtitle: 'letzte 7 Nächte',
    onInfo: () => _showSleepMethod(
      context,
      'Regelmäßigkeit',
      'Der Schlafregelmäßigkeitsindex vergleicht Schlaf und Wachsein Minute für Minute über aufeinanderfolgende Tage. Dafür braucht es sieben bewertete Nächte. Die soziale Zeitverschiebung vergleicht die Schlafmitte an Arbeitstagen und freien Tagen.',
    ),
    child: FutureBuilder<G3SleepPlus>(
      future: _plus,
      builder: (context, snap) {
        final plus = snap.data;
        return Column(
          children: [
            OBSriLead(
              value: plus?.regularity.value,
              gate:
                  plus?.regularity.gate ??
                  (snap.hasError ? 'Nicht verfügbar' : null),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<OBSleepWindow>>(
              future: _windows,
              builder: (context, windows) => OBSleepWindows(
                windows: windows.data ?? const [],
                regularity: plus?.regularity.value,
                gate:
                    plus?.regularity.gate ??
                    (snap.hasError ? 'Nicht verfügbar' : null),
                detail: true,
              ),
            ),
            const SizedBox(height: 12),
            OBSocialJetlag(
              minutes: plus?.socialJetlagDetail?.signedHours == null
                  ? null
                  : plus!.socialJetlagDetail!.signedHours! * 60,
              gate: plus?.socialJetlag.gate,
            ),
            const SizedBox(height: 12),
            chrome.OBEmptyState(
              title: 'So wird gerechnet',
              reason:
                  'SRI nach Phillips: Wie oft du an zwei Tagen hintereinander zur selben Minute im selben Zustand warst, schlafend oder wach. Braucht 7 bewertete Nächte.',
              action: 'Methode',
              onAction: () => _showSleepMethod(
                context,
                'Regelmäßigkeit',
                'Der Schlafregelmäßigkeitsindex vergleicht Schlaf und Wachsein Minute für Minute über aufeinanderfolgende Tage. Dafür braucht es sieben bewertete Nächte.',
              ),
            ),
          ],
        );
      },
    ),
  );
}

class G3SleepDebtDetail extends StatefulWidget {
  const G3SleepDebtDetail({
    super.key,
    required this.repository,
    required this.day,
  });
  final OpenBandRepository repository;
  final String day;
  @override
  State<G3SleepDebtDetail> createState() => _G3SleepDebtDetailState();
}

class _G3SleepDebtDetailState extends State<G3SleepDebtDetail> {
  late final Future<G3SleepPlus> _plus = widget.repository.readSleepPlus(
    widget.day,
  );
  late final Future<List<(String, double?)>> _freeNights = _readFreeNights();

  Future<List<(String, double?)>> _readFreeNights() {
    final date = DateTime.parse(widget.day);
    final days =
        [
          for (var i = 0; i < 21; i++)
            DateTime(date.year, date.month, date.day - i),
        ].where(
          (d) => d.weekday == DateTime.saturday || d.weekday == DateTime.sunday,
        );
    return Future.wait([
      for (final date in days)
        () async {
          final label = dayLabelOf(date);
          final stored = await widget.repository.readDay(label);
          return (label, stored.sleep.duration.value);
        }(),
    ]);
  }

  @override
  Widget build(BuildContext context) => _SleepDetail(
    title: 'SCHLAFSCHULD',
    subtitle: 'frei gegen üblich',
    onInfo: () => _showSleepMethod(
      context,
      'Schlafschuld',
      'Verglichen werden das 75. Perzentil der freien Nächte und der Median der letzten sieben Nächte. Die angezeigten Wochenendnächte können von der Auswertung ausgeschlossen sein.',
    ),
    child: FutureBuilder<G3SleepPlus>(
      future: _plus,
      builder: (context, snap) {
        final debt = snap.data?.sleepDebt;
        final minutes = debt?.debtHours == null ? null : debt!.debtHours! * 60;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OBSleepDebtLead(minutes: minutes),
            const SizedBox(height: 12),
            OBSleepDebt(
              minutes: minutes,
              freeMinutes: debt?.freeNightP75Hours == null
                  ? null
                  : debt!.freeNightP75Hours! * 60,
              usualMinutes: debt?.habitualMedianHours == null
                  ? null
                  : debt!.habitualMedianHours! * 60,
              gate: debt?.debtHours == null
                  ? debt?.refusalNote ??
                        (snap.hasError ? 'Nicht verfügbar' : null)
                  : null,
              detail: true,
            ),
            const SizedBox(height: 12),
            Text(
              'FREIE NÄCHTE · SA UND SO',
              style: G3.of(context).caps(color: G3.of(context).muted),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<(String, double?)>>(
              future: _freeNights,
              builder: (context, nights) {
                if (nights.hasError) {
                  return const OBInlineNotice(
                    text: 'Freie Nächte nicht geladen.',
                  );
                }
                if (nights.data == null) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }
                return chrome.OBPanel(
                  child: Column(
                    children: [
                      for (final (label, value) in nights.data!) ...[
                        Row(
                          children: [
                            SizedBox(
                              width: 68,
                              child: Text(
                                g3DayShort(DateTime.parse(label)),
                                style: G3.of(context).t(12, 16),
                              ),
                            ),
                            Expanded(
                              child: value == null
                                  ? const G3Dashed(height: 9)
                                  : LinearProgressIndicator(
                                      value: (value / 600).clamp(0.0, 1.0),
                                      minHeight: 9,
                                      borderRadius: BorderRadius.circular(5),
                                      color: G3.of(context).bar,
                                      backgroundColor: G3.of(context).track,
                                    ),
                            ),
                            SizedBox(
                              width: 57,
                              child: Text(
                                obSleepDuration(value),
                                textAlign: TextAlign.end,
                                style: G3
                                    .of(context)
                                    .t(12, 16, weight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        'Aufgezeichnete Wochenendnächte; die Schätzung kann Nächte ausschließen.',
                        style: G3
                            .of(context)
                            .t(11, 15, color: G3.of(context).muted),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            chrome.OBEmptyState(
              title: 'So wird gerechnet',
              reason:
                  '75. Perzentil deiner freien Nächte minus deine übliche Nacht. Frei = Sa und So, ohne Kalender. Ein Perzentil freien Schlafs, kein gemessener Bedarf.',
              action: 'Methode',
              onAction: () => _showSleepMethod(
                context,
                'Schlafschuld',
                'Verglichen werden das 75. Perzentil der freien Nächte und der Median der letzten sieben Nächte. Die angezeigten Wochenendnächte können von der Auswertung ausgeschlossen sein.',
              ),
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
    this.reminder,
  });
  final OpenBandRepository repository;
  final String day;
  final DateTime Function() now;
  final SleepBedtimeReminder? reminder;
  @override
  State<G3SleepTonight> createState() => _G3SleepTonightState();
}

class _G3SleepTonightState extends State<G3SleepTonight>
    with WidgetsBindingObserver {
  DateTime get _followingDay {
    final day = DateTime.parse(widget.day);
    return DateTime(day.year, day.month, day.day + 1);
  }

  late final SleepBedtimeReminder reminder =
      widget.reminder ?? NotificationSleepBedtimeReminder();
  int _reminderGen = 0;
  late Future<G3SleepPlus> plus = widget.repository.readSleepPlus(
    widget.day,
    now: widget.now(),
  );
  TodayNoteAction? _action;
  SleepNight? _lastNight;
  DateTime? _armedAt;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadReminder());
  }

  @override
  void dispose() {
    _reminderGen++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_loadReminder());
  }

  Future<void> _loadReminder() async {
    final generation = ++_reminderGen;
    try {
      final plan = await plus;
      if (!mounted || generation != _reminderGen) return;
      final today = todayLabel(widget.now());
      await reminder.reconcile(
        today: today,
        planLoaded: widget.day == today,
        bedtime: widget.day == today ? plan.bedtime : null,
        active: () => mounted && generation == _reminderGen,
      );
      if (!mounted || generation != _reminderGen) return;
      final day = await widget.repository.readDay(widget.day);
      final shown = roundedSleepBedtime(plan.bedtime);
      final action =
          widget.day == today &&
              shown != null &&
              plan.needMinutes != null &&
              plan.wake != null
          ? TodayNoteAction(
              '${obSleepClock(shown)} ins Bett',
              'für ${obSleepDuration(plan.needMinutes)} Schlafbedarf bis ${obSleepClock(plan.wake)}',
              sleepReminderAt(plan.bedtime!),
            )
          : null;
      final armed = await reminder.armed();
      if (!mounted || generation != _reminderGen) return;
      setState(() {
        _action = action;
        _lastNight = day.sleep;
        _armedAt = armed?.day == today ? armed?.at : null;
      });
    } catch (_) {
      if (mounted && generation == _reminderGen) {
        setState(() => _message = 'Erinnerung nicht verfügbar.');
      }
    }
  }

  Future<void> _toggleReminder() async {
    final action = _action;
    if (action == null || _busy) return;
    ++_reminderGen;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_armedAt == action.reminderAt) {
        await reminder.cancel();
        if (mounted) setState(() => _armedAt = null);
      } else {
        final result = await reminder.arm(
          action.reminderAt,
          widget.day,
          '${action.label} · ${action.sub}',
        );
        if (!mounted) return;
        setState(() {
          _armedAt = result == BedtimeReminderResult.scheduled
              ? action.reminderAt
              : null;
          _message = switch (result) {
            BedtimeReminderResult.scheduled => null,
            BedtimeReminderResult.passed =>
              'Keine Erinnerung gestellt: Die Zeit ist vorbei.',
            BedtimeReminderResult.denied =>
              'Mitteilungen sind aus. In den iOS-Einstellungen erlauben.',
            BedtimeReminderResult.failed =>
              'Erinnerung konnte nicht gestellt werden. Bitte erneut versuchen.',
          };
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Erinnerung nicht verfügbar.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SleepDetail(
    title: 'HEUTE NACHT',
    onInfo: () => _showSleepMethod(
      context,
      'Schlafbedarf',
      'Der persönliche Schlafbedarf beginnt mit dem 75. Perzentil deiner freien Nächte. Positive Schlafschuld und Belastung erhöhen ihn; Nickerchen senken ihn. Das Schlafziel gehört nicht zur Rechnung.',
    ),
    subtitle:
        '${g3DayShort(DateTime.parse(widget.day)).split(' ').first} → ${g3DayShort(_followingDay)}',
    child: FutureBuilder<G3SleepPlus>(
      future: plus,
      builder: (context, snap) {
        if (snap.hasError) {
          return chrome.OBErrorBlock(
            title: 'Plan nicht geladen',
            reason: 'Bitte erneut versuchen.',
            onRetry: () {
              setState(() {
                plus = widget.repository.readSleepPlus(
                  widget.day,
                  now: widget.now(),
                );
                _message = null;
              });
              unawaited(_loadReminder());
            },
          );
        }
        final value = snap.data;
        final g = G3.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OBBedtimeLead(
              bedtime: value?.bedtime,
              wake: value?.wake,
              lastOnset: _lastNight?.onset,
              lastWake: _lastNight?.wake,
              strainOpen: widget.day == todayLabel(widget.now()),
              noFreeNight: value?.sleepDebt.hasFreeNight == false,
            ),
            const SizedBox(height: 12),
            if (value?.sleepDebt.hasFreeNight == false)
              chrome.OBEmptyState(
                title: 'Woher der Bedarf kommt',
                reason:
                    'Aus deinen freien Nächten (Sa, So), plus Schlafschuld und Belastung, minus Nickerchen. Nach der ersten freien Nacht mit Band gibt es eine Bettzeit. Dein Ziel ändert daran nichts.',
                action: 'Methode',
                onAction: () => _showSleepMethod(
                  context,
                  'Schlafbedarf',
                  'Der persönliche Schlafbedarf beginnt mit dem 75. Perzentil deiner freien Nächte. Positive Schlafschuld und Belastung erhöhen ihn; Nickerchen senken ihn. Das Schlafziel gehört nicht zur Rechnung.',
                ),
              )
            else
              OBPlanBreakdown(
                baseline: value?.baselineOsdMinutes,
                debt: value?.appliedDebtMinutes,
                needClamp: value?.needClamp,
                bonus: value?.strainBonusMinutes,
                napCredit: value?.napCreditMinutes,
                napsIncomplete: value?.napsJudged == false,
                strainOpen: widget.day == todayLabel(widget.now()),
                need: value?.needMinutes,
                efficiency: value?.typicalEfficiency,
                wake: value?.wake,
                bedtime: value?.bedtime,
              ),
            const SizedBox(height: 12),
            if (_action != null &&
                _action!.reminderAt.isAfter(widget.now())) ...[
              if (_armedAt == _action!.reminderAt)
                OBInlineNotice(
                  text: 'Erinnerung um ${obSleepClock(_armedAt)}',
                  subtitle:
                      'heute, 15 Min. vor ${obSleepClock(roundedSleepBedtime(value?.bedtime))}',
                  icon: LucideIcons.bell,
                  action: 'Abbestellen',
                  onAction: _busy ? null : _toggleReminder,
                  actionChevron: false,
                )
              else
                chrome.OBActionPrimary(
                  'Um ${obSleepClock(_action!.reminderAt)} erinnern',
                  expand: true,
                  onPressed: _busy ? null : _toggleReminder,
                ),
              const SizedBox(height: 12),
            ],
            if (_message != null) ...[
              OBInlineNotice(text: _message!),
              const SizedBox(height: 12),
            ],
            Text(
              value?.bedtime == null
                  ? value?.sleepDebt.hasFreeNight == false
                        ? 'Noch keine freie Nacht für einen persönlichen Schlafbedarf.'
                        : 'Kein gespeicherter Schlafbedarf für diesen Tag.'
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
  const _SleepDetail({
    required this.title,
    required this.child,
    this.subtitle,
    this.onInfo,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onInfo;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        bottom: false,
        child: chrome.G3DetailPage(
          bottomInset: kOBTabBarContentInset,
          header: chrome.OBPageHeader.detail(
            title: title,
            subtitle: subtitle,
            backLabel: 'Schlaf',
            onBack: () => Navigator.of(context).pop(),
            onTrailing: onInfo,
          ),
          children: [child],
        ),
      ),
    );
  }
}

void _showSleepMethod(BuildContext context, String title, String text) {
  chrome.showOBInfoSheet(context, title: title, paragraphs: [text]);
}
