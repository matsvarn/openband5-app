import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'cycle.dart';
import 'domain.dart';
import 'health.dart';
import 'journal_controls.dart';
import 'settings_controls.dart';
import 'theme.dart';

const _kInfoTitle = 'Messwerte';
const _kInfoBody =
    'Ruhepuls und HRV stammen aus gespeicherten Nächten. '
    'Das Datum gehört zur jeweiligen Nacht.\n\n'
    'Die HRV zeigt die RMSSD der Schlafsitzung. '
    'Fehlende oder neu zu berechnende Werte bleiben als Lücke sichtbar.\n\n'
    'Die Werte bestimmen weder eine Zyklusphase noch einen Eisprung.';

class OpenBandCycleMeasurements extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final DateTime Function()? now;
  final bool synthetic;

  const OpenBandCycleMeasurements({
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
        builder: (_) => OpenBandCycleMeasurements(
          repository: repository,
          day: day,
          now: now,
          synthetic: synthetic,
        ),
      ),
    );
  }

  @override
  State<OpenBandCycleMeasurements> createState() =>
      _OpenBandCycleMeasurementsState();
}

class _OpenBandCycleMeasurementsState extends State<OpenBandCycleMeasurements> {
  int _gen = 0;
  String? _selectedStartDay;
  CycleMeasurementsSnapshot? _snapshot;
  bool _loading = true;
  bool _readError = false;
  int? _rhrSlot;
  int? _hrvSlot;

  OpenBandRepository get _repo => widget.repository;
  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(OpenBandCycleMeasurements oldWidget) {
    super.didUpdateWidget(oldWidget);
    final repoChanged = !identical(oldWidget.repository, widget.repository);
    final dayChanged = oldWidget.day != widget.day;
    if (repoChanged || dayChanged) {
      setState(() {
        _selectedStartDay = null;
        _snapshot = null;
        _rhrSlot = null;
        _hrvSlot = null;
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
    final start = _selectedStartDay;
    setState(() {
      _loading = true;
      _readError = false;
      _snapshot = null;
      _rhrSlot = null;
      _hrvSlot = null;
    });
    try {
      final snap = await repo.readCycleMeasurements(
        day,
        cycleStartDay: start,
      );
      if (!_same(gen, repo, day)) return;
      setState(() {
        _snapshot = snap;
        _loading = false;
        _readError = false;
        _rhrSlot = null;
        _hrvSlot = null;
        if (snap.reason == CycleMeasurementsReason.available ||
            snap.reason == CycleMeasurementsReason.metricUnavailable) {
          _selectedStartDay = snap.selectedStartDay ?? _selectedStartDay;
        }
      });
    } catch (_) {
      if (!_same(gen, repo, day)) return;
      setState(() {
        _loading = false;
        _readError = true;
        _snapshot = null;
        _rhrSlot = null;
        _hrvSlot = null;
      });
    }
  }

  bool _same(int gen, OpenBandRepository repo, String day) =>
      mounted &&
      gen == _gen &&
      identical(repo, _repo) &&
      widget.day == day;

  void _info() => showOpenBandJournalInfo(
    context,
    title: _kInfoTitle,
    body: _infoBody(_snapshot, _rhrSlot, _hrvSlot),
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

  Future<void> _pickPeriod({
    required List<CycleMeasurementPeriod> periods,
    String? selected,
  }) async {
    if (periods.isEmpty) return;
    final gen = _gen;
    final repo = _repo;
    final day = widget.day;
    final newestFirst = [...periods].reversed.toList();
    final asOf = _snapshot?.asOfDay ?? day;
    final picked = await showOpenBandSettingsChoiceSheet<String>(
      context: context,
      title: 'Zyklus',
      selected: selected,
      choices: [
        for (final period in newestFirst)
          (period.startDay, _periodLabel(period, asOf)),
      ],
    );
    if (picked == null || !_same(gen, repo, day) || picked == _selectedStartDay) {
      return;
    }
    setState(() {
      _selectedStartDay = picked;
      _rhrSlot = null;
      _hrvSlot = null;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Scaffold(
      key: const ValueKey('cycle-measurements'),
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(title: 'Messwerte', subtitle: '', onInfo: _info),
            ..._body(p),
            if (widget.synthetic) const _MeasurementsSyntheticFooter(),
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
    if (_loading && _snapshot == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator.adaptive()),
        ),
      ];
    }
    final snap = _snapshot;
    if (snap == null) return const [];
    switch (snap.reason) {
      case CycleMeasurementsReason.trackingDisabled:
        return [
          _notice(
            'Zyklus deaktiviert',
            'Einstellungen',
            _openSettings,
          ),
        ];
      case CycleMeasurementsReason.emptyStarts:
        return [
          _notice('Kein Zyklusbeginn', 'Zum Zyklus', () {
            Navigator.maybePop(context);
          }),
        ];
      case CycleMeasurementsReason.unreadableStarts:
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
      case CycleMeasurementsReason.selectedStartMissing:
        if (snap.periods.isEmpty) {
          return [
            _notice('Zyklus nicht mehr vorhanden', 'Zum Zyklus', () {
              Navigator.maybePop(context);
            }),
          ];
        }
        return [
          _notice('Zyklus nicht mehr vorhanden', 'Zyklus wählen', () {
            unawaited(
              _pickPeriod(periods: snap.periods, selected: _selectedStartDay),
            );
          }),
        ];
      case CycleMeasurementsReason.available:
      case CycleMeasurementsReason.metricUnavailable:
        return _measured(p, snap);
    }
  }

  List<Widget> _measured(OB p, CycleMeasurementsSnapshot snap) {
    final asOf = snap.asOfDay;
    final selected = snap.selected;
    final periodLabel = selected == null ? '' : _periodLabel(selected, asOf);
    final rhrPoints = [
      for (final night in snap.nights)
        MetricPoint(night.day, _finiteMetric(night.rhr?.value)),
    ];
    final hrvPoints = [
      for (final night in snap.nights)
        MetricPoint(night.day, _finiteMetric(night.hrv?.value)),
    ];
    final rhrIndex = _rhrSlot ?? _latestFinite(rhrPoints);
    final hrvIndex = _hrvSlot ?? _latestFinite(hrvPoints);
    final lastCycleDay = snap.nights.isEmpty
        ? snap.firstCycleDay
        : snap.nights.last.cycleDay;
    final axisStart = 'Tag ${snap.firstCycleDay}';
    final axisEnd = 'Tag $lastCycleDay';
    final children = <Widget>[
      OBCard(
        padding: EdgeInsets.zero,
        child: KeyedSubtree(
          key: const ValueKey('cycle-measurements-picker'),
          child: OBSettingsValueRow(
            label: 'Zyklus',
            value: periodLabel,
            chevron: true,
            mutedValue: true,
            onTap: snap.periods.isEmpty
                ? null
                : () => _pickPeriod(
                    periods: snap.periods,
                    selected: snap.selectedStartDay,
                  ),
          ),
        ),
      ),
    ];
    if (snap.unreadableCount > 0) {
      children.addAll([
        const SizedBox(height: 12),
        _mutedNotice('Daten teilweise lesbar'),
      ]);
    }
    if (snap.truncated) {
      children.addAll([
        const SizedBox(height: 12),
        _mutedNotice('Letzte 120 Nächte'),
      ]);
    }
    children.addAll([
      const SizedBox(height: 12),
      OBTrendCard.sourced(
        label: 'Ruhepuls',
        unit: 'bpm',
        icon: LucideIcons.activity,
        color: p.pulse,
        tint: p.pulseTint,
        points: rhrPoints,
        coverage: _coverage(rhrPoints, snap.visibleNights),
        axisStart: axisStart,
        axisEnd: axisEnd,
        selectedIndex: rhrIndex,
        plotKey: const ValueKey('cycle-measurements-rhr-plot'),
        onSelect: (i) => setState(() => _rhrSlot = i),
      ),
      const SizedBox(height: 12),
      OBTrendCard.sourced(
        label: 'HRV',
        unit: 'ms',
        icon: LucideIcons.activity,
        color: p.recovery,
        tint: p.recoveryTint,
        points: hrvPoints,
        coverage: _coverage(hrvPoints, snap.visibleNights),
        axisStart: axisStart,
        axisEnd: axisEnd,
        selectedIndex: hrvIndex,
        plotKey: const ValueKey('cycle-measurements-hrv-plot'),
        onSelect: (i) => setState(() => _hrvSlot = i),
      ),
    ]);
    return children;
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
                .copyWith(height: 18.2 / 14),
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

class _MeasurementsSyntheticFooter extends StatelessWidget {
  const _MeasurementsSyntheticFooter();

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

double? _finiteMetric(double? value) =>
    value != null && value.isFinite ? value : null;

int? _latestFinite(List<MetricPoint> points) {
  for (var i = points.length - 1; i >= 0; i--) {
    final value = points[i].value;
    if (value != null && value.isFinite) return i;
  }
  return null;
}

String _coverage(List<MetricPoint> points, int visible) {
  final available = [
    for (final point in points)
      if (point.value != null && point.value!.isFinite) point,
  ].length;
  return '$available von $visible Nächten';
}

String _periodLabel(CycleMeasurementPeriod period, String asOfDay) {
  final from = DateTime.parse(period.startDay);
  final to = DateTime.parse(period.endDay);
  final asOf = DateTime.parse(asOfDay);
  final needYear =
      from.year != to.year || from.year != asOf.year || to.year != asOf.year;
  if (from.year == to.year && from.month == to.month) {
    final end = DateFormat(needYear ? 'd. MMM y' : 'd. MMM', 'de_DE').format(to);
    return '${from.day}.–$end';
  }
  final fmt = needYear ? 'd. MMM y' : 'd. MMM';
  return '${DateFormat(fmt, 'de_DE').format(from)}–${DateFormat(fmt, 'de_DE').format(to)}';
}

const _kLineSep = '\u2028';

String _infoBody(
  CycleMeasurementsSnapshot? snap,
  int? rhrSlot,
  int? hrvSlot,
) {
  if (snap == null || snap.nights.isEmpty) return _kInfoBody;
  final sources = <String>[
    if (_nightMetric(snap, rhrSlot, rhr: true) case final selected?)
      _sourceParagraph('Ruhepuls', selected.night, selected.metric, snap.asOfDay),
    if (_nightMetric(snap, hrvSlot, rhr: false) case final selected?)
      _sourceParagraph('HRV', selected.night, selected.metric, snap.asOfDay),
  ];
  if (sources.isEmpty) return _kInfoBody;
  return '$_kInfoBody\n\n${sources.join('\n\n')}\n\n'
      'Qualitätswerte sind gespeicherte Scores, keine Fehlerspannen.';
}

({CycleNightMeasurement night, CycleNightMetric metric})? _nightMetric(
  CycleMeasurementsSnapshot snap,
  int? slot, {
  required bool rhr,
}) {
  final nights = snap.nights;
  if (nights.isEmpty) return null;
  var index = slot;
  if (index == null) {
    for (var i = nights.length - 1; i >= 0; i--) {
      final metric = rhr ? nights[i].rhr : nights[i].hrv;
      final value = metric?.value;
      if (value != null && value.isFinite) {
        index = i;
        break;
      }
    }
  }
  if (index == null || index < 0 || index >= nights.length) return null;
  final night = nights[index];
  final metric = rhr ? night.rhr : night.hrv;
  final value = metric?.value;
  if (metric == null || value == null || !value.isFinite) return null;
  return (night: night, metric: metric);
}

String _sourceParagraph(
  String label,
  CycleNightMeasurement night,
  CycleNightMetric metric,
  String asOfDay,
) {
  final lines = <String>['$label · ${_civilDay(night.day, asOfDay)}'];
  final window = _windowUtc(night.windowStart, night.windowEnd, asOfDay);
  if (window != null) lines.add(window);
  lines.add(_qualityLine(metric));
  return lines.join(_kLineSep);
}

String _civilDay(String day, String asOfDay) {
  final date = DateTime.parse(day);
  final asOf = DateTime.parse(asOfDay);
  final fmt = date.year == asOf.year ? 'd. MMM' : 'd. MMM y';
  return DateFormat(fmt, 'de_DE').format(date);
}

String? _windowUtc(DateTime? start, DateTime? end, String asOfDay) {
  if (start == null || end == null || !end.isAfter(start)) return null;
  final from = start.toUtc();
  final to = end.toUtc();
  final asOfYear = DateTime.parse(asOfDay).year;
  final needYear =
      from.year != to.year || from.year != asOfYear || to.year != asOfYear;
  String stamp(DateTime at) {
    final date = DateTime(at.year, at.month, at.day);
    final day = DateFormat(needYear ? 'd. MMM y' : 'd. MMM', 'de_DE').format(date);
    final time =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return '$day, $time';
  }

  if (from.year == to.year && from.month == to.month && from.day == to.day) {
    return '${stamp(from)}–${to.hour.toString().padLeft(2, '0')}:${to.minute.toString().padLeft(2, '0')} UTC';
  }
  return '${stamp(from)}–${stamp(to)} UTC';
}

String _qualityLine(CycleNightMetric metric) {
  if (metric.confidenceUnreadable) return 'Qualitätswert —';
  final confidence = metric.confidence;
  if (confidence == null || !confidence.isFinite) return 'Qualitätswert —';
  final digits = confidence == confidence.roundToDouble() ? 0 : 2;
  return 'Qualitätswert ${obNumber(confidence, digits: digits)} / 1';
}
