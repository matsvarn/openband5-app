import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'cycle.dart';
import 'domain.dart';
import 'journal_controls.dart';
import 'settings_controls.dart';
import 'theme.dart';

const _kInfoTitle = 'Vergleich';
const _kInfoIntro =
    'Verglichen wird die letzte gespeicherte Nacht je Messwert. '
    'Die Differenz bezieht sich auf den Mittelwert der genannten Nächte.';
const _kInfoRules =
    '21 Tage davor: mindestens zwei Nächte. Gleicher Zyklustag: mindestens '
    'drei frühere Zyklen im gewählten Zeitraum. Abstände über 60 Tage werden '
    'nicht zugeordnet.';
const _kZDisclaimer =
    'z beschreibt die Abweichung vom Mittelwert in Standardabweichungen. '
    'Keine Aussage über Ursache oder Zyklusphase.';
const _kEnDash = '\u2013';

class OpenBandCycleComparison extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final DateTime Function()? now;
  final bool synthetic;

  const OpenBandCycleComparison({
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
        builder: (_) => OpenBandCycleComparison(
          repository: repository,
          day: day,
          now: now,
          synthetic: synthetic,
        ),
      ),
    );
  }

  @override
  State<OpenBandCycleComparison> createState() =>
      _OpenBandCycleComparisonState();
}

class _OpenBandCycleComparisonState extends State<OpenBandCycleComparison> {
  int _gen = 0;
  late String _anchorEnd;
  int _page = 0;
  CycleComparisonSnapshot? _snapshot;
  bool _loading = true;
  bool _readError = false;

  OpenBandRepository get _repo => widget.repository;
  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _anchorEnd = _clampAnchor(widget.day, _now());
    unawaited(_load());
  }

  @override
  void didUpdateWidget(OpenBandCycleComparison oldWidget) {
    super.didUpdateWidget(oldWidget);
    final repoChanged = !identical(oldWidget.repository, widget.repository);
    final dayChanged = oldWidget.day != widget.day;
    if (repoChanged || dayChanged) {
      setState(() {
        _anchorEnd = _clampAnchor(widget.day, _now());
        _page = 0;
        _snapshot = null;
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
    final anchor = _anchorEnd;
    final page = _page;
    setState(() {
      _loading = true;
      _readError = false;
      _snapshot = null;
    });
    try {
      final snap = await repo.readCycleComparison(
        anchor,
        pageOffset: page,
        now: _now(),
      );
      if (!_same(gen, repo, day, anchor, page)) return;
      setState(() {
        _snapshot = snap;
        _loading = false;
        _readError = false;
      });
    } catch (_) {
      if (!_same(gen, repo, day, anchor, page)) return;
      setState(() {
        _loading = false;
        _readError = true;
        _snapshot = null;
      });
    }
  }

  bool _same(
    int gen,
    OpenBandRepository repo,
    String day,
    String anchor,
    int page,
  ) =>
      mounted &&
      gen == _gen &&
      identical(repo, _repo) &&
      widget.day == day &&
      _anchorEnd == anchor &&
      _page == page;

  CycleMedianWindow? _safeWindow({String? anchor, int? page}) {
    try {
      return cycleMedianWindow(
        anchorEnd: anchor ?? _anchorEnd,
        pageOffset: page ?? _page,
      );
    } on ArgumentError {
      return null;
    }
  }

  bool _canAcceptAnchor(String day) =>
      _safeWindow(anchor: day, page: 0) != null;

  bool _canPage(int page) {
    if (page < 0) return false;
    return _safeWindow(page: page) != null;
  }

  void _pageBy(int delta) {
    final next = _page + delta;
    if (next < 0 || !_canPage(next)) return;
    setState(() => _page = next);
    unawaited(_load());
  }

  Future<void> _pickEnd() async {
    final gen = _gen;
    final repo = _repo;
    final day = widget.day;
    final current = _anchorEnd;
    final page = _page;
    final picked = await pickOpenBandCycleDay(
      context,
      selected: _anchorEnd,
      now: _now(),
      synthetic: widget.synthetic,
      title: 'Enddatum',
    );
    if (picked == null || !_same(gen, repo, day, current, page)) return;
    if (!_canAcceptAnchor(picked)) return;
    if (picked == _anchorEnd && _page == 0) return;
    setState(() {
      _anchorEnd = picked;
      _page = 0;
    });
    await _load();
  }

  Future<void> _info() async {
    final gen = _gen;
    final repo = _repo;
    final day = widget.day;
    final anchor = _anchorEnd;
    final page = _page;
    final snap = _snapshot;
    final result = await showOpenBandJournalInfo(
      context,
      title: _kInfoTitle,
      body: _methodBody(snap),
      actions: [
        if (_hasSource(snap?.rhr))
          const OBInfoSheetAction(id: 'rhr', label: 'Ruhepuls · Quellen'),
        if (_hasSource(snap?.hrv))
          const OBInfoSheetAction(id: 'hrv', label: 'HRV · Quellen'),
      ],
    );
    if (result == null || !_same(gen, repo, day, anchor, page)) return;
    if (!mounted) return;
    final source = snap;
    if (source == null) return;
    if (result == 'rhr' && _hasSource(source.rhr)) {
      await showOpenBandJournalInfo(
        context,
        title: 'Ruhepuls',
        body: comparisonSourceBody(source.rhr, 'bpm', source.window.endDay),
      );
    } else if (result == 'hrv' && _hasSource(source.hrv)) {
      await showOpenBandJournalInfo(
        context,
        title: 'HRV',
        body: comparisonSourceBody(source.hrv, 'ms', source.window.endDay),
      );
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Scaffold(
      key: const ValueKey('cycle-comparison'),
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            OBPageHeader(title: 'Vergleich', subtitle: '', onInfo: _info),
            ..._body(p),
            if (widget.synthetic) const _ComparisonSyntheticFooter(),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(OB p) {
    final window = _snapshot?.window ?? _safeWindow();
    final children = <Widget>[
      if (window != null)
        OBWindowPager(
          startLabel: _windowDay(window.startDay),
          endLabel: _windowDay(window.endDay),
          earlierEnabled: _canPage(_page + 1),
          laterEnabled: _page > 0,
          onEarlier: () => _pageBy(1),
          onLater: () => _pageBy(-1),
          onCenter: _pickEnd,
          earlierKey: const ValueKey('cycle-comparison-earlier'),
          laterKey: const ValueKey('cycle-comparison-later'),
          centerKey: const ValueKey('cycle-comparison-window'),
        ),
    ];
    if (_readError) {
      children.addAll([
        const SizedBox(height: 12),
        OBSettingsErrorCard(
          message: 'Daten nicht geladen',
          retryLabel: 'Erneut versuchen',
          onRetry: _load,
        ),
      ]);
      return children;
    }
    if (_loading && _snapshot == null) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator.adaptive()),
        ),
      );
      return children;
    }
    final snap = _snapshot;
    if (snap == null) return children;
    if (snap.reason == CycleComparisonReason.trackingDisabled) {
      children.addAll([
        const SizedBox(height: 12),
        _notice('Zyklustracking aus', 'Einstellungen', _openSettings),
      ]);
      return children;
    }
    if (snap.partial) {
      children.addAll([
        const SizedBox(height: 12),
        _mutedNotice('Teilweise ausgewertet'),
      ]);
    }
    children.addAll([
      const SizedBox(height: 12),
      OBNightComparisonCard(
        key: const ValueKey('cycle-comparison-rhr'),
        label: 'Ruhepuls',
        unit: 'bpm',
        iconColor: p.pulse,
        metric: snap.rhr,
      ),
      const SizedBox(height: 12),
      OBNightComparisonCard(
        key: const ValueKey('cycle-comparison-hrv'),
        label: 'HRV',
        unit: 'ms',
        iconColor: p.recovery,
        metric: snap.hrv,
      ),
    ]);
    return children;
  }

  Widget _notice(String message, String action, VoidCallback onAction) {
    final p = OB.of(context);
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: p.text(14, color: p.muted).copyWith(height: 18.2 / 14),
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

class _ComparisonSyntheticFooter extends StatelessWidget {
  const _ComparisonSyntheticFooter();

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

/// Latest-night comparison card. Shared so 2x stacking stays in one place.
class OBNightComparisonCard extends StatelessWidget {
  final String label;
  final String unit;
  final Color iconColor;
  final CycleMetricComparison metric;

  const OBNightComparisonCard({
    super.key,
    required this.label,
    required this.unit,
    required this.iconColor,
    required this.metric,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked = _stackComparison(context);
    final latest = metric.latest;
    final available = _latestAvailable(metric);
    final date = available && latest != null ? _cardDay(latest.nightDay) : null;
    final valueText = available && latest != null
        ? obNumber(latest.metric.value)
        : '—';
    final caption = switch (metric.latestReason) {
      CycleComparisonLatestReason.missing => 'Keine Nacht',
      CycleComparisonLatestReason.unavailable ||
      CycleComparisonLatestReason.unreadable => 'Nicht auswertbar',
      CycleComparisonLatestReason.available => _nightCaption(metric),
    };
    final showRefs = available;

    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _labelRow(p),
                    if (date != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        date,
                        style: p
                            .text(13, color: p.muted)
                            .copyWith(height: 18 / 13),
                      ),
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _labelRow(p)),
                    if (date != null)
                      Text(
                        date,
                        style: p
                            .text(13, color: p.muted)
                            .copyWith(height: 18 / 13),
                      ),
                  ],
                ),
          const SizedBox(height: 12),
          stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _valueUnit(p, valueText),
                    const SizedBox(height: 8),
                    Text(
                      caption,
                      style: p
                          .text(13, weight: FontWeight.w500, color: p.muted)
                          .copyWith(height: 18 / 13),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      valueText,
                      style: p
                          .text(28, weight: FontWeight.w700, display: true)
                          .copyWith(height: 34 / 28),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      unit,
                      style: p
                          .text(14, color: p.muted)
                          .copyWith(height: 18 / 14),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        caption,
                        style: p
                            .text(13, weight: FontWeight.w500, color: p.muted)
                            .copyWith(height: 18 / 13),
                      ),
                    ),
                  ],
                ),
          if (showRefs) ...[
            const SizedBox(height: 12),
            Text(
              'Gegenüber dem Mittelwert',
              style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
            ),
            const SizedBox(height: 4),
            _refRow(
              p,
              stacked: stacked,
              label: '21 Tage davor',
              detail: _prior21Detail(metric.prior21),
              delta: _formatDelta(metric.prior21.delta, unit),
              divided: false,
            ),
            _refRow(
              p,
              stacked: stacked,
              label: 'Gleicher Zyklustag',
              detail: _sameDayDetail(metric.sameDay),
              delta: _formatDelta(metric.sameDay.delta, unit),
              divided: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _labelRow(OB p) {
    return Row(
      children: [
        Icon(LucideIcons.activity, size: 16, color: iconColor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: p
                .text(15, weight: FontWeight.w600, color: p.muted)
                .copyWith(height: 20 / 15),
          ),
        ),
      ],
    );
  }

  Widget _valueUnit(OB p, String valueText) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          valueText,
          style: p
              .text(28, weight: FontWeight.w700, display: true)
              .copyWith(height: 34 / 28),
        ),
        const SizedBox(width: 8),
        Text(
          unit,
          style: p.text(14, color: p.muted).copyWith(height: 18 / 14),
        ),
      ],
    );
  }

  Widget _refRow(
    OB p, {
    required bool stacked,
    required String label,
    required String detail,
    required String delta,
    required bool divided,
  }) {
    final labels = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: p.text(15, weight: FontWeight.w500).copyWith(height: 20 / 15),
        ),
        const SizedBox(height: 4),
        Text(
          detail,
          style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
        ),
      ],
    );
    final deltaStyle = p
        .text(17, weight: FontWeight.w600)
        .copyWith(height: 22 / 17);
    final body = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labels,
              const SizedBox(height: 8),
              Text(delta, style: deltaStyle),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: labels),
              const SizedBox(width: 12),
              SizedBox(
                width: 92,
                child: Text(
                  delta,
                  textAlign: TextAlign.right,
                  style: deltaStyle,
                ),
              ),
            ],
          );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: divided
          ? BoxDecoration(
              border: Border(top: BorderSide(color: p.line)),
            )
          : null,
      child: body,
    );
  }
}

bool _stackComparison(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(15) > 20 ||
    MediaQuery.sizeOf(context).width < 360;

bool _latestAvailable(CycleMetricComparison metric) =>
    metric.latestReason == CycleComparisonLatestReason.available &&
    metric.latest != null;

bool _hasSource(CycleMetricComparison? metric) =>
    metric != null && _latestAvailable(metric);

bool _showCycleTag(CycleMetricComparison metric) {
  if (metric.latest?.cycleDay == null) return false;
  switch (metric.sameDay.reason) {
    case CycleComparisonSameDayReason.longLatestPeriod:
    case CycleComparisonSameDayReason.unreadableStarts:
    case CycleComparisonSameDayReason.emptyStarts:
    case CycleComparisonSameDayReason.unassignedLatest:
      return false;
    case CycleComparisonSameDayReason.available:
    case CycleComparisonSameDayReason.insufficientPeriods:
    case CycleComparisonSameDayReason.noLatest:
      return true;
  }
}

String _methodBody(CycleComparisonSnapshot? snap) {
  final parts = <String>[_kInfoIntro, _kInfoRules];
  final coverage = snap == null ? null : comparisonCoverageBody(snap);
  if (coverage != null) parts.add(coverage);
  return parts.join('\n\n');
}

String? comparisonCoverageBody(CycleComparisonSnapshot snap) {
  final clauses = <String>[];
  if (snap.unreadableNightCount > 0) {
    clauses.add(_unreadableClause(snap.unreadableNightCount));
  }
  if (snap.excludedNightCount > 0) {
    clauses.add(_excludedClause(snap.excludedNightCount));
  }
  if (clauses.isEmpty) return null;
  return 'Gewähltes Jahr und 21-Tage-Vergleiche: ${clauses.join(', ')}.';
}

String _unreadableClause(int n) => n == 1
    ? '1 Nacht mit nicht lesbaren Daten'
    : '$n Nächte mit nicht lesbaren Daten';

String _excludedClause(int n) => n == 1
    ? '1 Nacht mit nicht auswertbarem Ergebnis'
    : '$n Nächte mit nicht auswertbarem Ergebnis';

String _clampAnchor(String day, DateTime now) =>
    cycleDateIsAfterToday(day, now) ? cycleTodayLabel(now) : day;

String _windowDay(String day) =>
    DateFormat('d. MMM y', 'de_DE').format(DateTime.parse(day));

String _cardDay(String day) =>
    DateFormat('d. MMM y', 'de_DE').format(DateTime.parse(day));

String _nightCaption(CycleMetricComparison metric) {
  if (!_showCycleTag(metric)) return 'Nacht';
  return 'Nacht · Tag ${metric.latest!.cycleDay}';
}

String _prior21Detail(CycleComparisonPrior21 prior) {
  return _nightCount(prior.count);
}

String _sameDayDetail(CycleComparisonSameDay sameDay) {
  switch (sameDay.reason) {
    case CycleComparisonSameDayReason.emptyStarts:
      return 'Kein Zyklusbeginn';
    case CycleComparisonSameDayReason.unreadableStarts:
      return 'Beginn nicht lesbar';
    case CycleComparisonSameDayReason.longLatestPeriod:
      return 'Abstand über 60 Tage';
    case CycleComparisonSameDayReason.unassignedLatest:
      return 'Nicht zugeordnet';
    case CycleComparisonSameDayReason.insufficientPeriods:
    case CycleComparisonSameDayReason.available:
      return _cycleCount(sameDay.count);
    case CycleComparisonSameDayReason.noLatest:
      return '—';
  }
}

String _nightCount(int n) => n == 1 ? '1 Nacht' : '$n Nächte';

String _cycleCount(int n) =>
    n == 1 ? '1 früherer Zyklus' : '$n frühere Zyklen';

String _formatSigned(double value, {required int digits}) {
  final scale = digits == 0 ? 1 : List.filled(digits, 10).fold(1, (a, b) => a * b);
  var rounded = (value * scale).roundToDouble() / scale;
  if (rounded == 0) rounded = 0;
  final abs = obNumber(rounded.abs(), digits: digits);
  if (rounded > 0) return '+$abs';
  if (rounded < 0) return '−$abs';
  return abs;
}

String _formatDelta(double? delta, String unit) {
  if (delta == null || !delta.isFinite) return '—';
  return '${_formatSigned(delta, digits: 1)} $unit';
}

String _formatMean(double? mean) {
  if (mean == null || !mean.isFinite) return '—';
  return obNumber(mean, digits: 1);
}

String _formatZ(double? z) {
  if (z == null || !z.isFinite) return '—';
  return _formatSigned(z, digits: 2);
}

String _civilDay(String day, String asOfDay) {
  final date = DateTime.parse(day);
  final asOf = DateTime.parse(asOfDay);
  final fmt = date.year == asOf.year ? 'd. MMM' : 'd. MMM y';
  return DateFormat(fmt, 'de_DE').format(date);
}

String _range(String start, String end, String asOfDay) {
  final startDate = DateTime.parse(start);
  final endDate = DateTime.parse(end);
  final asOf = DateTime.parse(asOfDay);
  if (startDate.year == endDate.year && endDate.year == asOf.year) {
    return '${DateFormat('d. MMM', 'de_DE').format(startDate)}'
        '$_kEnDash'
        '${DateFormat('d. MMM y', 'de_DE').format(endDate)}';
  }
  return '${DateFormat('d. MMM y', 'de_DE').format(startDate)}'
      '$_kEnDash'
      '${DateFormat('d. MMM y', 'de_DE').format(endDate)}';
}

String _quality(CycleNightMetric metric) {
  if (metric.confidenceUnreadable) return 'Qualitätswert —';
  final confidence = metric.confidence;
  if (confidence == null || !confidence.isFinite) return 'Qualitätswert —';
  final digits = confidence == confidence.roundToDouble() ? 0 : 2;
  return 'Qualitätswert ${obNumber(confidence, digits: digits)} / 1';
}

String _hhmm(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

String? _windowBis(DateTime? start, DateTime? end, String asOfDay) {
  if (start == null || end == null || !end.isAfter(start)) return null;
  final from = start.toUtc();
  final to = end.toUtc();
  final asOfYear = DateTime.parse(asOfDay).year;
  final needYear =
      from.year != to.year || from.year != asOfYear || to.year != asOfYear;
  String stamp(DateTime at) {
    final date = DateTime(at.year, at.month, at.day);
    final day = DateFormat(
      needYear ? 'd. MMM y' : 'd. MMM',
      'de_DE',
    ).format(date);
    return '$day, ${_hhmm(at)}';
  }

  return '${stamp(from)} bis ${stamp(to)} UTC';
}

String _inputLabel(String key) => switch (key) {
  'hr_1hz' => 'Puls (1 Hz)',
  'sleep_window' => 'Schlaffenster',
  'rr_sleep_window' => 'RR-Intervalle im Schlaffenster',
  _ => key,
};

String? _sleepLabel(String? source) {
  final value = source?.trim();
  if (value == null || value.isEmpty) return null;
  return switch (value) {
    'auto' => 'Schlaf automatisch',
    'manual' => 'Schlaf manuell',
    'confirmed' => 'Schlaf bestätigt',
    _ => 'Schlafquelle: $value',
  };
}

List<String> _envelopeBits(CycleComparisonNight night) {
  final bits = <String>[];
  final sleep = _sleepLabel(night.sleepSource);
  if (sleep != null) bits.add(sleep);
  final note = night.metric.note?.trim();
  if (note != null && note.isNotEmpty) bits.add('Hinweis: $note');
  final tier = night.metric.tier?.trim();
  if (tier != null && tier.isNotEmpty) bits.add('Stufe $tier');
  if (night.metric.inputsUsed.isNotEmpty) {
    bits.add(
      'Eingaben ${[for (final key in night.metric.inputsUsed) _inputLabel(key)].join(', ')}',
    );
  }
  return bits;
}

(int, int, int, int)? _relativeWindow(CycleComparisonNight night) {
  final start = night.sleepStart?.toUtc();
  final end = night.sleepEnd?.toUtc();
  if (start == null || end == null || !end.isAfter(start)) return null;
  final named = DateTime.utc(
    int.parse(night.nightDay.substring(0, 4)),
    int.parse(night.nightDay.substring(5, 7)),
    int.parse(night.nightDay.substring(8, 10)),
  );
  return (
    start.difference(named).inMinutes,
    start.hour * 60 + start.minute,
    end.difference(named).inMinutes,
    end.hour * 60 + end.minute,
  );
}

(String, String)? _vortagClock(CycleComparisonNight night) {
  final start = night.sleepStart?.toUtc();
  final end = night.sleepEnd?.toUtc();
  if (start == null || end == null) return null;
  final named = DateTime.utc(
    int.parse(night.nightDay.substring(0, 4)),
    int.parse(night.nightDay.substring(5, 7)),
    int.parse(night.nightDay.substring(8, 10)),
  );
  final prev = named.subtract(const Duration(days: 1));
  if (start.year != prev.year ||
      start.month != prev.month ||
      start.day != prev.day) {
    return null;
  }
  if (end.year != named.year ||
      end.month != named.month ||
      end.day != named.day) {
    return null;
  }
  return (_hhmm(start), _hhmm(end));
}

bool _sharedRelativeWindow(List<CycleComparisonNight> nights) {
  if (nights.isEmpty) return false;
  final first = _relativeWindow(nights.first);
  if (first == null) return false;
  for (final night in nights.skip(1)) {
    if (_relativeWindow(night) != first) return false;
  }
  return true;
}

String _metaKey(CycleComparisonNight night) => [
  _quality(night.metric),
  night.algoVersion.toString(),
  ..._envelopeBits(night),
].join('\u0001');

bool _sharedMetadata(List<CycleComparisonNight> nights) {
  if (nights.isEmpty) return false;
  final first = _metaKey(nights.first);
  return nights.every((n) => _metaKey(n) == first);
}

List<CycleComparisonNight> _printedNights(CycleMetricComparison metric) {
  final nights = <CycleComparisonNight>[
    if (metric.latest != null) metric.latest!,
    ...metric.prior21.contributors,
    ...metric.sameDay.contributors,
  ];
  return nights;
}

bool _canGroupCover(List<CycleComparisonNight> nights) {
  if (nights.isEmpty) return false;
  if (!_sharedRelativeWindow(nights) || !_sharedMetadata(nights)) {
    return false;
  }
  return _vortagClock(nights.first) != null;
}

String comparisonSourceBody(
  CycleMetricComparison metric,
  String unit,
  String asOfDay,
) {
  final latest = metric.latest;
  if (latest == null) return _kZDisclaimer;
  final printed = _printedNights(metric);
  final canCover = _canGroupCover(printed);
  final parts = <String>[
    _latestParagraph(
      latest,
      unit,
      asOfDay,
      showTag: _showCycleTag(metric),
      includeEnvelope: !canCover,
    ),
  ];

  if (metric.prior21.reason != CycleComparisonPrior21Reason.noLatest) {
    parts.add(_prior21Paragraph(metric.prior21, unit, asOfDay));
    if (metric.prior21.contributors.isNotEmpty) {
      parts.add(
        canCover
            ? _prior21Values(metric.prior21.contributors, unit, asOfDay)
            : _mixedNights(metric.prior21.contributors, unit, asOfDay),
      );
    }
  }

  if (metric.sameDay.reason != CycleComparisonSameDayReason.noLatest) {
    parts.add(_sameDayParagraph(metric.sameDay, unit));
    if (metric.sameDay.contributors.isNotEmpty) {
      parts.add(
        canCover
            ? _sameDayValues(metric.sameDay.contributors, unit, asOfDay)
            : _mixedSameDay(metric.sameDay.contributors, unit, asOfDay),
      );
    }
  }

  if (canCover) {
    final cover = _coverParagraph(printed);
    if (cover != null) parts.add(cover);
  }
  if (metric.unreadableCount > 0) {
    parts.add('${_unreadableClause(metric.unreadableCount)}.');
  }
  if (metric.rejectedCount > 0) {
    parts.add('${_excludedClause(metric.rejectedCount)}.');
  }

  parts.add(_kZDisclaimer);
  return parts.join('\n\n');
}

String _latestParagraph(
  CycleComparisonNight latest,
  String unit,
  String asOfDay, {
  required bool showTag,
  required bool includeEnvelope,
}) {
  final buf = StringBuffer(
    '${_cardDay(latest.nightDay)} · '
    '${obNumber(latest.metric.value)} $unit',
  );
  if (showTag) buf.write(' · Tag ${latest.cycleDay}');
  buf.write('. ${_quality(latest.metric)}.');
  final window = _windowBis(latest.sleepStart, latest.sleepEnd, asOfDay);
  if (window != null) buf.write(' Nacht: $window.');
  if (includeEnvelope) {
    final extra = [
      ..._envelopeBits(latest),
      'Algorithmus ${latest.algoVersion}',
    ];
    if (extra.isNotEmpty) buf.write(' ${extra.join(' · ')}.');
  }
  return buf.toString();
}

String _prior21Paragraph(
  CycleComparisonPrior21 prior,
  String unit,
  String asOfDay,
) {
  final buf = StringBuffer('21 Tage davor');
  if (prior.startDay != null && prior.endDay != null) {
    buf.write(' · ${_range(prior.startDay!, prior.endDay!, asOfDay)}');
  }
  buf.write('. ${_nightCount(prior.count)}');
  if (prior.reason == CycleComparisonPrior21Reason.available) {
    buf.write(
      ' · Mittelwert ${_formatMean(prior.mean)} $unit · z ${_formatZ(prior.z)}',
    );
  }
  buf.write('.');
  return buf.toString();
}

String _prior21Values(
  List<CycleComparisonNight> nights,
  String unit,
  String asOfDay,
) {
  final ordered = [...nights]
    ..sort((a, b) => a.nightDay.compareTo(b.nightDay));
  final bits = [
    for (final night in ordered)
      '${_civilDay(night.nightDay, asOfDay)}: ${obNumber(night.metric.value)}',
  ];
  return '${bits.join(' · ')} $unit.';
}

String _sameDayParagraph(CycleComparisonSameDay sameDay, String unit) {
  switch (sameDay.reason) {
    case CycleComparisonSameDayReason.available:
      final tag = sameDay.cycleDay == null ? '' : ' · Tag ${sameDay.cycleDay}';
      return 'Gleicher Zyklustag$tag. ${_cycleCount(sameDay.count)} · '
          'Mittelwert ${_formatMean(sameDay.mean)} $unit · '
          'z ${_formatZ(sameDay.z)}.';
    case CycleComparisonSameDayReason.insufficientPeriods:
      final tag = sameDay.cycleDay == null ? '' : ' · Tag ${sameDay.cycleDay}';
      return 'Gleicher Zyklustag$tag. ${_cycleCount(sameDay.count)}.';
    case CycleComparisonSameDayReason.emptyStarts:
      return 'Gleicher Zyklustag. Kein Zyklusbeginn.';
    case CycleComparisonSameDayReason.unreadableStarts:
      return 'Gleicher Zyklustag. Beginn nicht lesbar.';
    case CycleComparisonSameDayReason.longLatestPeriod:
      return 'Gleicher Zyklustag. Abstand über 60 Tage.';
    case CycleComparisonSameDayReason.unassignedLatest:
      return 'Gleicher Zyklustag. Nicht zugeordnet.';
    case CycleComparisonSameDayReason.noLatest:
      return 'Gleicher Zyklustag.';
  }
}

String _sameDayValues(
  List<CycleComparisonNight> nights,
  String unit,
  String asOfDay,
) {
  final ordered = [...nights]
    ..sort((a, b) => a.nightDay.compareTo(b.nightDay));
  final bits = [
    for (final night in ordered)
      '${_civilDay(night.nightDay, asOfDay)}: '
          '${obNumber(night.metric.value)} $unit'
          '${night.startDay == null ? '' : ' · Beginn ${_civilDay(night.startDay!, asOfDay)}'}',
  ];
  return '${bits.join('. ')}.';
}

String _mixedNights(
  List<CycleComparisonNight> nights,
  String unit,
  String asOfDay,
) {
  final ordered = [...nights]
    ..sort((a, b) => a.nightDay.compareTo(b.nightDay));
  return [
    for (final night in ordered) _mixedNightLine(night, unit, asOfDay),
  ].join(' ');
}

String _mixedSameDay(
  List<CycleComparisonNight> nights,
  String unit,
  String asOfDay,
) {
  final ordered = [...nights]
    ..sort((a, b) => a.nightDay.compareTo(b.nightDay));
  return [
    for (final night in ordered)
      '${_mixedNightLine(night, unit, asOfDay)}'
          '${night.startDay == null ? '' : ' Beginn ${_civilDay(night.startDay!, asOfDay)}. '}',
  ].join();
}

String _mixedNightLine(
  CycleComparisonNight night,
  String unit,
  String asOfDay,
) {
  final bits = <String>[
    '${_civilDay(night.nightDay, asOfDay)}: ${obNumber(night.metric.value)} $unit',
  ];
  final window = _windowBis(night.sleepStart, night.sleepEnd, asOfDay);
  if (window != null) bits.add(window);
  bits.addAll(_envelopeBits(night));
  bits.add(_quality(night.metric));
  bits.add('Algorithmus ${night.algoVersion}');
  return '${bits.join(' · ')}.';
}

String? _coverParagraph(List<CycleComparisonNight> nights) {
  if (nights.isEmpty) return null;
  final times = _vortagClock(nights.first);
  if (times == null || !_sharedRelativeWindow(nights)) return null;
  final first = nights.first;
  final rest = [
    'Algorithmus ${first.algoVersion}',
    _quality(first.metric),
    ..._envelopeBits(first),
  ];
  return 'Alle genannten Nächte: Vortag ${times.$1} bis zum genannten Datum '
      '${times.$2} UTC. ${rest.join(' · ')}.';
}
