import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'cycle.dart';
import 'cycle_gaps_data.dart';
import 'domain.dart';
import 'health.dart';
import 'journal_controls.dart';
import 'settings_controls.dart';
import 'theme.dart';

const _kInfoTitle = 'Abstände';
const _kInfoBody =
    'Abstände zählen die Kalendertage zwischen zwei eingetragenen Beginnen. '
    'Der laufende Zyklus ist noch nicht enthalten.\n\n'
    'Die Ansicht ist optional und benötigt zwölf Abstände. '
    'Bei mehr als 60 Tagen oder einem nicht lesbaren Beginn bleibt sie offen. '
    'Ein fehlender Beginn lässt sich nicht von einem längeren Zyklus unterscheiden.';

class OpenBandCycleGaps extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final DateTime Function()? now;
  final bool synthetic;

  const OpenBandCycleGaps({
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
        builder: (_) => OpenBandCycleGaps(
          repository: repository,
          day: day,
          now: now,
          synthetic: synthetic,
        ),
      ),
    );
  }

  @override
  State<OpenBandCycleGaps> createState() => _OpenBandCycleGapsState();
}

class _OpenBandCycleGapsState extends State<OpenBandCycleGaps> {
  int _gen = 0;
  CycleObservedGap? _selectedGap;
  CycleGapsSummary? _summary;
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
  void didUpdateWidget(OpenBandCycleGaps oldWidget) {
    super.didUpdateWidget(oldWidget);
    final repoChanged = !identical(oldWidget.repository, widget.repository);
    final dayChanged = oldWidget.day != widget.day;
    if (repoChanged || dayChanged) {
      setState(() {
        _selectedGap = null;
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
      final summary = buildCycleGapsSummary(snap);
      setState(() {
        _summary = summary;
        _loading = false;
        _readError = false;
        _selectedGap = _boundGap(summary);
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
      mounted && gen == _gen && identical(repo, _repo) && widget.day == day;

  CycleObservedGap? _boundGap(CycleGapsSummary summary) {
    final groups = partitionCycleGaps(summary.gaps);
    if (groups.isEmpty) return null;
    final selected = _selectedGap;
    if (selected != null) {
      for (final group in groups) {
        for (final gap in group) {
          if (gap == selected) return selected;
        }
      }
    }
    return groups.first.last;
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

  Future<void> _pickGroup({
    required List<List<CycleObservedGap>> groups,
    required int selected,
  }) async {
    if (groups.isEmpty) return;
    final gen = _gen;
    final repo = _repo;
    final day = widget.day;
    final picked = await showOpenBandSettingsChoiceSheet<int>(
      context: context,
      title: 'Zeitraum',
      selected: selected,
      choices: [
        for (var i = 0; i < groups.length; i++)
          (i, cycleGapsGroupLabel(groups[i])),
      ],
      choiceKey: (i) => ValueKey('cycle-gaps-group-$i'),
    );
    if (picked == null || !_same(gen, repo, day) || picked == selected) {
      return;
    }
    final summary = _summary;
    if (summary == null) return;
    final latest = partitionCycleGaps(summary.gaps);
    if (picked < 0 || picked >= latest.length) return;
    setState(() => _selectedGap = latest[picked].last);
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Scaffold(
      key: const ValueKey('cycle-gaps'),
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(title: 'Abstände', subtitle: '', onInfo: _info),
            ..._body(p),
            if (widget.synthetic) const _GapsSyntheticFooter(),
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
      case CycleGapsReason.displayDisabled:
        return [
          _notice('Abstände ausgeblendet', 'Einstellungen', _openSettings),
        ];
      case CycleGapsReason.trackingDisabled:
        return [
          _notice('Zyklus deaktiviert', 'Einstellungen', _openSettings),
        ];
      case CycleGapsReason.insufficientGaps:
        return [
          _notice('Mindestens 12 Abstände nötig', 'Zum Zyklus', () {
            Navigator.maybePop(context);
          }),
        ];
      case CycleGapsReason.unreadableStarts:
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
      case CycleGapsReason.longGap:
        return [
          _notice('Abstand über 60 Tage', 'Zum Zyklus', () {
            Navigator.maybePop(context);
          }),
        ];
      case CycleGapsReason.available:
        return _chart(p, summary);
    }
  }

  List<Widget> _chart(OB p, CycleGapsSummary summary) {
    final groups = partitionCycleGaps(summary.gaps);
    if (groups.isEmpty) return const [];
    var groupIndex = 0;
    final selected = _selectedGap;
    if (selected != null) {
      for (var i = 0; i < groups.length; i++) {
        if (groups[i].any((gap) => gap == selected)) {
          groupIndex = i;
          break;
        }
      }
    }
    final group = groups[groupIndex];
    final shown = selected != null && group.any((gap) => gap == selected)
        ? selected
        : group.last;
    final selectedIndex = group.indexOf(shown);
    final points = [
      for (final gap in group) MetricPoint(gap.nextStart, gap.days.toDouble()),
    ];
    final asOfYear = DateTime.parse(summary.asOfDay).year;
    final firstDay = DateTime.parse(points.first.day);
    final lastDay = DateTime.parse(points.last.day);
    final axisYear =
        firstDay.year != lastDay.year ||
        firstDay.year != asOfYear ||
        lastDay.year != asOfYear;
    return [
      OBCard(
        padding: EdgeInsets.zero,
        child: KeyedSubtree(
          key: const ValueKey('cycle-gaps-picker'),
          child: OBSettingsValueRow(
            label: 'Zeitraum',
            value: cycleGapsGroupLabel(group),
            chevron: true,
            mutedValue: true,
            onTap: () => _pickGroup(groups: groups, selected: groupIndex),
          ),
        ),
      ),
      const SizedBox(height: 12),
      OBTrendCard.sourced(
        label: 'Zwischen Beginnen',
        icon: LucideIcons.ruler,
        color: p.ink,
        tint: p.muted,
        points: points,
        coverage: cycleGapsCoverage(group.length, summary.gaps.length),
        axisStart: _axisDay(points.first.day, withYear: axisYear),
        axisEnd: _axisDay(points.last.day, withYear: axisYear),
        selectedIndex: selectedIndex < 0 ? group.length - 1 : selectedIndex,
        plotKey: const ValueKey('cycle-gaps-plot'),
        bars: true,
        unit: shown.days == 1 ? 'Tag' : 'Tage',
        pointCaption: (pt) {
          for (final gap in group) {
            if (gap.nextStart == pt.day) return cycleGapsRangeLabel(gap);
          }
          return DateFormat('d. MMM', 'de_DE').format(DateTime.parse(pt.day));
        },
        onSelect: (i) {
          if (i < 0 || i >= group.length) return;
          setState(() => _selectedGap = group[i]);
        },
      ),
    ];
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
}

class _GapsSyntheticFooter extends StatelessWidget {
  const _GapsSyntheticFooter();

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

List<List<CycleObservedGap>> partitionCycleGaps(List<CycleObservedGap> gaps) {
  if (gaps.isEmpty) return const [];
  final groups = <List<CycleObservedGap>>[];
  var end = gaps.length;
  while (end > 0) {
    final start = end > kCycleGapsDisplayMinimum
        ? end - kCycleGapsDisplayMinimum
        : 0;
    groups.add(List.unmodifiable(gaps.sublist(start, end)));
    end = start;
  }
  return groups;
}

String cycleGapsGroupLabel(List<CycleObservedGap> group) {
  final from = DateTime.parse(group.first.previousStart);
  final to = DateTime.parse(group.last.nextStart);
  final fromMonth = _monthToken(from);
  final toMonth = _monthToken(to);
  if (from.year == to.year && from.month == to.month) {
    return '${from.day}.–${to.day}. $fromMonth ${from.year}';
  }
  if (from.year == to.year) {
    return '$fromMonth–$toMonth ${from.year}';
  }
  return '$fromMonth ${from.year}–$toMonth ${to.year}';
}

String _monthToken(DateTime day) {
  final labeled = DateFormat('d. MMM', 'de_DE').format(day);
  final space = labeled.lastIndexOf(' ');
  return space < 0 ? labeled : labeled.substring(space + 1);
}

String cycleGapsCoverage(int shown, int total) {
  if (shown == total) {
    return shown == 1 ? '1 Abstand' : '$shown Abstände';
  }
  return '$shown von $total Abständen';
}

String cycleGapsRangeLabel(CycleObservedGap gap) {
  final from = DateTime.parse(gap.previousStart);
  final to = DateTime.parse(gap.nextStart);
  final fmt = from.year != to.year ? 'd. MMM y' : 'd. MMM';
  return '${DateFormat(fmt, 'de_DE').format(from)}–${DateFormat(fmt, 'de_DE').format(to)}';
}

String _axisDay(String day, {required bool withYear}) {
  return DateFormat(
    withYear ? 'd. MMM y' : 'd. MMM',
    'de_DE',
  ).format(DateTime.parse(day));
}
