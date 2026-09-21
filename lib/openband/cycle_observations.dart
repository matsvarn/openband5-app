import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'cycle.dart';
import 'cycle_observations_data.dart';
import 'domain.dart';
import 'journal_controls.dart';
import 'settings_controls.dart';
import 'theme.dart';

const _kInfoTitle = 'Beobachtungen';
const _kInfoBody =
    'Gezählt werden nur Tage mit mindestens einer gespeicherten Beobachtung. '
    'Notizen allein und fehlende Einträge zählen nicht als symptomfreie Tage.\n\n'
    'Die Übersicht beginnt mit drei eingetragenen Zyklusbeginnen. '
    'Zyklustage zählen ab dem jeweils letzten eingetragenen Beginn. '
    'Der laufende Zyklus ist enthalten.';

class OpenBandCycleObservations extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final DateTime Function()? now;
  final bool synthetic;

  const OpenBandCycleObservations({
    super.key,
    required this.repository,
    required this.day,
    this.now,
    this.synthetic = false,
  });

  static Future<void> push(
    BuildContext context, {
    required OpenBandRepository repository,
    required String day,
    DateTime Function()? now,
    bool synthetic = false,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OpenBandCycleObservations(
          repository: repository,
          day: day,
          now: now,
          synthetic: synthetic,
        ),
      ),
    );
  }

  @override
  State<OpenBandCycleObservations> createState() =>
      _OpenBandCycleObservationsState();
}

class _OpenBandCycleObservationsState extends State<OpenBandCycleObservations> {
  int _gen = 0;
  int? _selectedFromDay;
  CycleObservationsSummary? _summary;
  bool _loading = true;
  bool _readError = false;

  OpenBandRepository get _repo => widget.repository;
  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(OpenBandCycleObservations oldWidget) {
    super.didUpdateWidget(oldWidget);
    final repoChanged = !identical(oldWidget.repository, widget.repository);
    final dayChanged = oldWidget.day != widget.day;
    if (repoChanged || dayChanged) {
      setState(() {
        _selectedFromDay = null;
        _summary = null;
        _readError = false;
        _loading = true;
      });
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final gen = ++_gen;
    final day = widget.day;
    final repo = _repo;
    setState(() {
      _loading = true;
      _readError = false;
      _summary = null;
    });
    try {
      final snap = await repo.readCycle(day, now: _now());
      if (!_same(gen, repo, day)) return;
      final summary = buildCycleObservationsSummary(snap);
      setState(() {
        _summary = summary;
        _loading = false;
        _readError = false;
        _selectedFromDay = _boundFromDay(summary);
      });
    } catch (_) {
      if (!_same(gen, repo, day)) return;
      setState(() {
        _loading = false;
        _readError = true;
        _summary = null;
      });
    }
  }

  bool _same(int gen, OpenBandRepository repo, String day) =>
      mounted &&
      gen == _gen &&
      identical(repo, _repo) &&
      widget.day == day;

  int? _boundFromDay(CycleObservationsSummary summary) {
    if (summary.weeks.isEmpty) return null;
    final selected = _selectedFromDay;
    if (selected != null &&
        summary.weeks.any((week) => week.fromCycleDay == selected)) {
      return selected;
    }
    return summary.weeks.first.fromCycleDay;
  }

  CycleObservationsWeek? _selectedWeek(CycleObservationsSummary summary) {
    final from = _selectedFromDay;
    if (from == null) return null;
    for (final week in summary.weeks) {
      if (week.fromCycleDay == from) return week;
    }
    return null;
  }

  void _info() => showOpenBandJournalInfo(
    context,
    title: _kInfoTitle,
    body: _kInfoBody,
  );

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OpenBandCycleSettings(
          repository: _repo,
          now: _now,
          synthetic: widget.synthetic,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _pickWeek({
    required List<CycleObservationsWeek> weeks,
    int? selected,
  }) async {
    if (weeks.isEmpty) return;
    final gen = _gen;
    final repo = _repo;
    final day = widget.day;
    final picked = await showOpenBandSettingsChoiceSheet<int>(
      context: context,
      title: 'Zyklustage',
      selected: selected,
      choices: [
        for (final week in weeks) (week.fromCycleDay, _weekLabel(week)),
      ],
      choiceKey: (from) => ValueKey('cycle-observations-week-$from'),
    );
    if (picked == null || !_same(gen, repo, day) || picked == _selectedFromDay) {
      return;
    }
    final summary = _summary;
    if (summary == null ||
        !summary.weeks.any((week) => week.fromCycleDay == picked)) {
      return;
    }
    setState(() => _selectedFromDay = picked);
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Scaffold(
      key: const ValueKey('cycle-observations'),
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(title: 'Beobachtungen', subtitle: '', onInfo: _info),
            ..._body(p),
            if (widget.synthetic) const _ObservationsSyntheticFooter(),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(OB p) {
    if (_readError) {
      return [
        OBSettingsErrorCard(
          message: 'Daten nicht geladen',
          retryLabel: 'Erneut versuchen',
          onRetry: _load,
        ),
      ];
    }
    if (_loading && _summary == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator.adaptive()),
        ),
      ];
    }
    final summary = _summary;
    if (summary == null) return const [];
    switch (summary.reason) {
      case CycleObservationsReason.trackingDisabled:
        return [
          _notice('Zyklus deaktiviert', 'Einstellungen', _openSettings),
        ];
      case CycleObservationsReason.insufficientStarts:
        return [
          _notice('Mindestens 3 Zyklusbeginne nötig', 'Zum Zyklus', () {
            Navigator.maybePop(context);
          }),
        ];
      case CycleObservationsReason.unreadableStarts:
        return [
          _notice(
            'Zyklusbeginn nicht lesbar',
            'Zum Zyklus',
            () {
              Navigator.maybePop(context);
            },
            danger: true,
          ),
        ];
      case CycleObservationsReason.available:
        return _counts(p, summary);
    }
  }

  List<Widget> _counts(OB p, CycleObservationsSummary summary) {
    final week = _selectedWeek(summary);
    final children = <Widget>[
      OBCard(
        padding: EdgeInsets.zero,
        child: KeyedSubtree(
          key: const ValueKey('cycle-observations-picker'),
          child: OBSettingsValueRow(
            label: 'Zyklustage',
            value: week == null ? '' : _weekLabel(week),
            chevron: true,
            mutedValue: true,
            onTap: summary.weeks.isEmpty
                ? null
                : () => _pickWeek(
                    weeks: summary.weeks,
                    selected: _selectedFromDay,
                  ),
          ),
        ),
      ),
    ];
    if (summary.partial) {
      children.addAll([
        const SizedBox(height: 12),
        _mutedNotice('Einträge teilweise lesbar'),
      ]);
    }
    children.addAll([
      const SizedBox(height: 12),
      if (week == null || week.taggedDays == 0)
        OBCard(
          child: Text(
            'Keine Einträge für diese Zyklustage',
            style: p.text(15, color: p.muted).copyWith(height: 20 / 15),
          ),
        )
      else
        _countCard(p, summary, week),
    ]);
    return children;
  }

  Widget _countCard(
    OB p,
    CycleObservationsSummary summary,
    CycleObservationsWeek week,
  ) {
    final first = summary.firstStartDay;
    final asOf = summary.asOfDay;
    final subtitle = first == null
        ? '${summary.cycleCount} Zyklen'
        : '${_spanLabel(first, asOf, _now())} · ${summary.cycleCount} Zyklen';
    return OBCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _daysTitle(week.taggedDays),
                  style: p
                      .text(15, weight: FontWeight.w600)
                      .copyWith(height: 20 / 15),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
                ),
              ],
            ),
          ),
          for (final row in week.counts)
            Semantics(
              container: true,
              label: _countSemantic(
                _tagLabel(row.tag),
                row.count,
                week.taggedDays,
              ),
              excludeSemantics: true,
              child: OBSettingsValueRow(
                label: _tagLabel(row.tag),
                value: '${row.count} von ${week.taggedDays}',
                interactive: false,
                mutedValue: true,
              ),
            ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _notice(
    String message,
    String action,
    VoidCallback onAction, {
    bool danger = false,
  }) {
    final p = OB.of(context);
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: p
                .text(14, color: danger ? p.danger : p.muted)
                .copyWith(height: 20 / 14),
          ),
          const SizedBox(height: 8),
          OBAction(action, secondary: true, ink: true, onPressed: onAction),
        ],
      ),
    );
  }

  Widget _mutedNotice(String message) {
    final p = OB.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        message,
        style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
      ),
    );
  }
}

class _ObservationsSyntheticFooter extends StatelessWidget {
  const _ObservationsSyntheticFooter();

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 12),
      child: Text(
        'Synthetische Daten',
        style: p.text(12, color: p.muted).copyWith(height: 18 / 12),
      ),
    );
  }
}

String _weekLabel(CycleObservationsWeek week) =>
    'Tag ${week.fromCycleDay}–${week.toCycleDay}';

String _daysTitle(int n) =>
    n == 1 ? '1 Tag mit Beobachtungen' : '$n Tage mit Beobachtungen';

String _tagLabel(String tag) => kCycleObservationLabels[tag] ?? tag;

String _countSemantic(String label, int count, int taggedDays) {
  final counted = count == 1 ? '1 Tag' : '$count Tage';
  final denom = taggedDays == 1 ? '1 Tag' : '$taggedDays Tagen';
  return '$label, $counted von $denom';
}

String _spanLabel(String fromDay, String asOfDay, DateTime now) {
  final from = DateTime.parse(fromDay);
  final to = DateTime.parse(asOfDay);
  final needYear =
      from.year != to.year || from.year != now.year || to.year != now.year;
  final fmt = needYear ? 'd. MMM y' : 'd. MMM';
  return '${DateFormat(fmt, 'de_DE').format(from)}–${DateFormat(fmt, 'de_DE').format(to)}';
}
