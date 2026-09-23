import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/day_label.dart';
import 'domain.dart';
import 'journal_controls.dart';
import 'scale.dart';
import 'settings_controls.dart';
import 'sleep_goal.dart';
import 'theme.dart';

class OpenBandSleepPlan extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final DateTime Function() now;
  final bool synthetic;
  const OpenBandSleepPlan({
    super.key,
    required this.repository,
    required this.day,
    this.now = DateTime.now,
    this.synthetic = false,
  });

  @override
  State<OpenBandSleepPlan> createState() => _OpenBandSleepPlanState();
}

class _OpenBandSleepPlanState extends State<OpenBandSleepPlan>
    with WidgetsBindingObserver {
  int _token = 0;
  SleepPlanSnapshot? _snap;
  int? _goalMinutes;
  bool _goalReadFailed = false;
  Object? _error;
  bool _loading = true;
  Timer? _deadline;

  bool get _tonight => widget.day == todayLabel(widget.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deadline?.cancel();
    _token++;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OpenBandSleepPlan oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day == widget.day &&
        identical(oldWidget.repository, widget.repository)) {
      return;
    }
    _snap = null;
    _error = null;
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  void _armDeadline() {
    _deadline?.cancel();
    final now = widget.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    var wait = next.difference(now);
    if (wait <= Duration.zero) wait = const Duration(milliseconds: 1);
    _deadline = Timer(wait, () {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    final token = ++_token;
    final repo = widget.repository;
    final day = widget.day;
    final now = widget.now();
    _armDeadline();
    setState(() {
      _loading = true;
      _error = null;
      _goalMinutes = null;
      _goalReadFailed = false;
    });
    unawaited(_loadGoal(token));
    try {
      final snap = await repo.readSleepPlan(day, now: now);
      if (!mounted || token != _token) return;
      setState(() {
        _snap = snap;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = 'load';
        _loading = false;
        _snap = null;
      });
    }
  }

  Future<void> _loadGoal(int token) async {
    try {
      final goal = await widget.repository.readSleepGoal(
        sleepPlanWakeDay(widget.day),
      );
      if (!mounted || token != _token) return;
      setState(() => _goalMinutes = goal.targetMinutes);
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() => _goalReadFailed = true);
    }
  }

  bool _withhold(SleepPlanSnapshot? snap) {
    if (!_tonight) return true;
    if (snap == null) return false;
    switch (snap.status) {
      case SleepPlanStatus.stale:
      case SleepPlanStatus.corrupt:
      case SleepPlanStatus.inconsistent:
        return true;
      default:
        break;
    }
    return snap.plan?.freshness == SleepPlanFreshness.staleInputs;
  }

  ComingNightSleepPlan? get _visiblePlan {
    final snap = _snap;
    if (snap == null || _error != null || _withhold(snap)) return null;
    switch (snap.status) {
      case SleepPlanStatus.available:
      case SleepPlanStatus.partial:
        return snap.plan;
      default:
        return null;
    }
  }

  String? _heroReason({required ComingNightSleepPlan? plan}) {
    if (_error != null) return 'Laden fehlgeschlagen';
    if (_loading && _snap == null) return null;
    if (!_tonight) return 'Keine gespeicherte Schätzung';
    final snap = _snap;
    if (snap == null) return 'Noch keine Schätzung';
    if (snap.status == SleepPlanStatus.stale ||
        snap.plan?.freshness == SleepPlanFreshness.staleInputs) {
      return 'Schätzung nicht aktuell';
    }
    if (snap.status == SleepPlanStatus.corrupt ||
        snap.status == SleepPlanStatus.inconsistent) {
      return 'Schätzung nicht lesbar';
    }
    if (plan == null) return 'Noch keine Schätzung';
    return null;
  }

  List<String> _heroNotes(ComingNightSleepPlan? plan) {
    final reason = _heroReason(plan: plan);
    if (reason != null) return [reason];
    if (plan == null) return const [];
    final notes = <String>[];
    if (plan.freshness == SleepPlanFreshness.unknown) {
      notes.add('Aktualität unbekannt');
    } else {
      notes.add('Stand ${sleepPlanTimeOfDay(plan.builtAtEpoch)}');
    }
    if (plan.strainBonusMin == null) notes.add('Belastung fehlt');
    if (plan.napCreditMin == null) notes.add('Nickerchen unvollständig');
    return notes;
  }

  void _openGoal() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => OpenBandSleepGoal(
              repository: widget.repository,
              day: sleepPlanWakeDay(widget.day),
              synthetic: widget.synthetic,
            ),
          ),
        )
        .then((_) {
          if (mounted) unawaited(_load());
        });
  }

  void _openInfo() {
    showOpenBandJournalInfo(
      context,
      title: 'Zur Schätzung',
      body: sleepPlanInfoBody(
        plan: _visiblePlan,
        withheld: _withhold(_snap) || _error != null || !_tonight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked = MediaQuery.textScalerOf(context).scale(15) > 20;
    final plan = _visiblePlan;
    final need = plan == null ? '—' : sleepPlanNeedLabel(plan.needSeconds);
    final bedtime = plan == null
        ? '—'
        : sleepPlanClockLabel(plan.bedtimeMinuteOfDay);
    final wake = plan == null ? '—' : sleepPlanClockLabel(plan.wakeMinuteOfDay);
    final timesMissing =
        plan != null &&
        (plan.bedtimeMinuteOfDay == null || plan.wakeMinuteOfDay == null);
    final notes = _heroNotes(plan);
    final scaleMax = math
        .max(
          10.0,
          math.max(
            plan?.needSeconds == null ? 0 : plan!.needSeconds / 3600,
            (_goalMinutes ?? 0) / 60,
          ),
        )
        .ceilToDouble();
    final heroScale = math.min(MediaQuery.textScalerOf(context).scale(1), 1.4);
    final goal = _goalReadFailed
        ? 'Nicht verfügbar'
        : _goalMinutes == null
        ? '—'
        : obDuration(_goalMinutes!);
    final waiting = _loading && _snap == null && _error == null;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(
              title: _tonight ? 'Heute Nacht' : 'Nacht',
              backText: 'Schlaf',
              subtitle: sleepPlanNightRangeLabel(widget.day),
              infoLabel: 'Zur Schätzung',
              onInfo: _openInfo,
            ),
            const SizedBox(height: 8),
            if (waiting)
              const Center(child: CircularProgressIndicator.adaptive())
            else ...[
              OBCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GESCHÄTZTER SCHLAFBEDARF',
                      style: p.label(size: 11).copyWith(height: 16 / 11),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      need,
                      textScaler: TextScaler.linear(heroScale),
                      style: p
                          .text(64, weight: FontWeight.w700, display: true)
                          .copyWith(height: 70 / 64, letterSpacing: -0.02 * 64),
                    ),
                    const SizedBox(height: 14),
                    OBScale(
                      min: 0,
                      max: scaleMax,
                      value: plan?.needSeconds == null
                          ? null
                          : plan!.needSeconds / 3600,
                      target: _goalMinutes == null ? null : _goalMinutes! / 60,
                      fill: p.ink,
                      mark: p.card,
                      markEdge: p.ink,
                      ticks: 2,
                      labels: ('0 h', null, '${scaleMax.toInt()} h'),
                      semanticsLabel: plan == null
                          ? 'Schlafbedarf nicht verfügbar'
                          : 'Geschätzter Schlafbedarf $need auf einer Skala von 0 bis ${scaleMax.toInt()} Stunden',
                    ),
                    const SizedBox(height: 16),
                    Divider(height: 1, color: p.line),
                    _PlanFact(
                      label: 'Eigenes Schlafziel',
                      value: goal,
                      known: _goalMinutes != null,
                      ink: p.ink,
                    ),
                    Divider(height: 1, color: p.line),
                    _PlanFact(
                      label: 'Belastung heute',
                      value: plan?.strainBonusMin == null
                          ? '—'
                          : '${_strainMinutes(plan!.strainBonusMin!)}.',
                      known: plan?.strainBonusMin != null,
                      ink: p.muted,
                    ),
                    Divider(height: 1, color: p.line),
                    _PlanFact(
                      label: 'Nickerchen',
                      value: plan?.napCreditMin == null
                          ? '—'
                          : '${_napCreditMinutes(plan!.napCreditMin!)}.',
                      known: plan?.napCreditMin != null,
                      ink: p.muted,
                    ),
                    for (final note in notes)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          note,
                          style: p
                              .text(12, color: p.muted)
                              .copyWith(height: 16 / 12),
                        ),
                      ),
                    if (_error != null)
                      OBAction(
                        'Erneut versuchen',
                        ink: true,
                        onPressed: _loading ? null : _load,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('ABENDPLANUNG', style: p.label(size: 11)),
              const SizedBox(height: 8),
              _TimesRow(stacked: stacked, bedtime: bedtime, wake: wake),
              if (timesMissing)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Zeitplanung unvollständig',
                    style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                plan == null
                    ? 'Die Abendplanung bleibt leer, bis eine Schätzung vorliegt.'
                    : 'Belastung und Nickerchen können die Schätzung bis zum Abend ändern.',
                style: p.text(13, color: p.muted).copyWith(height: 19 / 13),
              ),
              const SizedBox(height: 12),
              OBCard(
                padding: EdgeInsets.zero,
                child: OBSettingsValueRow(
                  label: 'Eigenes Schlafziel',
                  value: '',
                  comfortable: true,
                  chevron: true,
                  onTap: _openGoal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanFact extends StatelessWidget {
  final String label, value;
  final bool known;
  final Color ink;
  const _PlanFact({
    required this.label,
    required this.value,
    required this.known,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    final name = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: known ? ink : null,
            border: known ? null : Border.all(color: p.muted),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(child: Text(label, style: p.text(14))),
      ],
    );
    final reading = Text(value, style: p.text(14, weight: FontWeight.w700));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: large
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [name, const SizedBox(height: 4), reading],
            )
          : Row(
              children: [
                Expanded(child: name),
                reading,
              ],
            ),
    );
  }
}

class _TimesRow extends StatelessWidget {
  final bool stacked;
  final String bedtime;
  final String wake;
  const _TimesRow({
    required this.stacked,
    required this.bedtime,
    required this.wake,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    Widget column(String label, String value) => OBCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Text(label.toUpperCase(), style: p.label(size: 10)),
          Text(
            value,
            style: p
                .text(30, weight: FontWeight.w700, display: true)
                .copyWith(height: 36 / 30, letterSpacing: 0),
          ),
        ],
      ),
    );
    final bed = column('Ins Bett · geschätzt', bedtime);
    final rise = column('Aufstehen · typisch', wake);
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [bed, rise],
      );
    }
    return Row(
      spacing: 16,
      children: [
        Expanded(child: bed),
        Expanded(child: rise),
      ],
    );
  }
}

String sleepPlanNeedLabel(double? seconds) {
  if (seconds == null) return '—';
  final minutes = (seconds / 60).round();
  return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
}

String sleepPlanClockLabel(double? minuteOfDay) {
  if (minuteOfDay == null) return '—';
  var minute = minuteOfDay.round() % 1440;
  if (minute < 0) minute += 1440;
  final hour = minute ~/ 60;
  final min = minute % 60;
  return '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}

String sleepPlanTimeOfDay(int epochSeconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  return DateFormat('HH:mm', 'de_DE').format(time);
}

String sleepPlanNightRangeLabel(String startDay) {
  final parsed = DateTime.tryParse(startDay);
  if (parsed == null) return '';
  final start = DateTime(parsed.year, parsed.month, parsed.day);
  final end = DateTime(start.year, start.month, start.day + 1);
  final month = DateFormat('MMMM', 'de_DE');
  if (start.month == end.month && start.year == end.year) {
    return '${start.day}./${end.day}. ${month.format(start)}';
  }
  if (start.year == end.year) {
    return '${start.day}. ${month.format(start)}/${end.day}. ${month.format(end)}';
  }
  return '${start.day}. ${month.format(start)} ${start.year}/'
      '${end.day}. ${month.format(end)} ${end.year}';
}

String _strainMinutes(double minutes) {
  final value = minutes.round();
  if (value > 0) return '+$value Min';
  return '$value Min';
}

String _napCreditMinutes(double minutes) {
  final value = minutes.round();
  if (value > 0) return '-$value Min';
  return '$value Min';
}

String sleepPlanInfoBody({ComingNightSleepPlan? plan, bool withheld = false}) {
  final parts = <String>[
    'Aus gespeicherten Nächten, Belastung und Nickerchen. Kein gemessener persönlicher Schlafbedarf.',
    'Die Abendplanung nutzt typische Aufwachzeiten und Schlafeffizienz. Sie stellt keinen Wecker.',
  ];
  if (plan != null && !withheld) {
    final bits = <String>[
      plan.strainBonusMin == null
          ? 'Belastung fehlt'
          : 'Belastung ${_strainMinutes(plan.strainBonusMin!)}',
      plan.napCreditMin == null
          ? 'Nickerchen unvollständig'
          : 'Nickerchen ${_napCreditMinutes(plan.napCreditMin!)}',
    ];
    final built = DateTime.fromMillisecondsSinceEpoch(plan.builtAtEpoch * 1000);
    final stand = DateFormat('d. MMMM, HH:mm', 'de_DE').format(built);
    parts.add(
      'Berücksichtigt: ${bits.join(' · ')}. Stand $stand · Modell ${plan.algoVersion}.',
    );
  }
  if (plan == null || plan.limitations.sourceTimezoneUnknown) {
    parts.add('Die Zeitzone der Berechnung wurde nicht gespeichert.');
  }
  return parts.join('\n');
}
