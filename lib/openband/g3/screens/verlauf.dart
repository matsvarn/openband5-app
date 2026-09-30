import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../data/day_label.dart';
import '../../../data/journal_fields.dart';
import '../../../ui2/app_shell.dart' show pushInTab;
import '../../domain.dart';
import '../../tab_bar.dart' show kOBTabBarContentInset;
import '../charts.dart';
import '../chrome.dart' as chrome;
import '../count_copy.dart';
import '../day.dart' show G3Legend;
import '../g3_format.dart';
import '../g3_theme.dart';
import '../metrics.dart' as metrics;

const _bodyMetrics = [
  G3Metric.hrv,
  G3Metric.rhr,
  G3Metric.respRate,
  G3Metric.skinTempZ,
];

String g3MetricName(G3Metric metric) => switch (metric) {
  G3Metric.recovery => 'Erholung',
  G3Metric.hrv => 'HRV',
  G3Metric.rhr => 'Ruhepuls',
  G3Metric.respRate => 'Atemfrequenz',
  G3Metric.skinTempZ => 'Hauttemperatur',
  G3Metric.sleepMinutes => 'Schlaf-Dauer',
  G3Metric.strain => 'Belastung',
  G3Metric.steps => 'Schritte',
};

G3Domain g3MetricDomain(G3Metric metric) => switch (metric) {
  G3Metric.recovery ||
  G3Metric.hrv ||
  G3Metric.rhr ||
  G3Metric.respRate ||
  G3Metric.skinTempZ => G3Domain.recovery,
  G3Metric.sleepMinutes => G3Domain.sleep,
  G3Metric.strain || G3Metric.steps => G3Domain.load,
};

String _unit(G3Metric metric) => switch (metric) {
  G3Metric.recovery => '',
  G3Metric.hrv => 'ms',
  G3Metric.rhr || G3Metric.respRate => '/min',
  G3Metric.skinTempZ => '',
  G3Metric.sleepMinutes => '',
  G3Metric.strain => '',
  G3Metric.steps => '',
};

int _digits(G3Metric metric) => switch (metric) {
  G3Metric.respRate || G3Metric.skinTempZ || G3Metric.strain => 1,
  _ => 0,
};

String _number(double? value, G3Metric metric) {
  if (value == null || !value.isFinite) return '—';
  if (metric == G3Metric.sleepMinutes) return g3Duration(value.round());
  if (metric == G3Metric.steps) return g3Count(value.round());
  return metric == G3Metric.skinTempZ
      ? g3Signed(value, digits: _digits(metric))
      : g3Number(value, digits: _digits(metric));
}

String _date(String day) => g3DayShort(DateTime.parse(day));

String _longDate(String day) => g3DayLong(DateTime.parse(day));

String _endLabel(String day) =>
    day == todayLabel() ? 'heute' : g3DateShort(DateTime.parse(day));

String _bandStamp(BandSnapshot band, {DateTime? now}) =>
    g3DataThrough(band.latestStoredAt?.toLocal(), now: now ?? DateTime.now());

/// Shared section chrome already adds 24 pt; shift it out of detail content's gutter.
Widget _outsideGutter(Widget child) =>
    Transform.translate(offset: const Offset(-16, 0), child: child);

String _weightSourceLabel(G3WeightSource? source) => switch (source) {
  G3WeightSource.manual => 'manuell',
  G3WeightSource.imported => 'Apple Health',
  null => 'Quelle unbekannt',
};

String _baselineChip(G3Baseline? baseline) {
  final status = baseline?.status;
  if (status?.phase != BaselinePhase.building) return 'kein Normalbereich';
  final remaining = status?.remaining;
  if (remaining == null) return 'Basis im Aufbau';
  return 'Basis: noch $remaining ${g3CountNoun(remaining, 'Wert', 'Werte')}';
}

metrics.OBBodyRow _bodyRow(
  G3Metric metric,
  G3Trend trend, {
  required bool last,
  required VoidCallback onTap,
}) {
  final value = trend.points.isEmpty ? null : _usable(trend.points.last);
  final range = trend.baseline.status.phase == BaselinePhase.trusted
      ? trend.baseline.range
      : null;
  final bounds = range == null ? null : _personalBounds(range);
  return metrics.OBBodyRow(
    domain: g3MetricDomain(metric),
    state: metric == G3Metric.skinTempZ
        ? metrics.OBBodyState.deviation
        : value == null
        ? metrics.OBBodyState.missing
        : range == null
        ? metrics.OBBodyState.building
        : metrics.OBBodyState.range,
    name: g3MetricName(metric),
    value: value == null ? null : _number(value, metric),
    unit: _unit(metric).isEmpty ? null : _unit(metric),
    at: value,
    min: metric == G3Metric.skinTempZ ? -1 : bounds?.$1 ?? 0,
    max: metric == G3Metric.skinTempZ ? 1 : bounds?.$2 ?? 1,
    band: range == null ? null : (range.low, range.high),
    minLabel: range == null ? null : _number(range.low, metric),
    maxLabel: range == null ? null : _number(range.high, metric),
    note: _baselineChip(trend.baseline),
    last: last,
    onTap: onTap,
  );
}

double? _usable(MetricPoint point) =>
    point.partial || point.value?.isFinite != true ? null : point.value;

/// The shared entry point for Heute, Schlaf and Messwerte. The Training area
/// owns the Belastung detail and may reuse [G3MetricDetail] for its trend.
Future<void> openG3MetricDetail(
  BuildContext context,
  G3Metric metric, {
  required OpenBandRepository repository,
  required String endDay,
  String backLabel = 'Heute',
  BandSnapshot? band,
}) => pushInTab<void>(
  context,
  MaterialPageRoute(
    builder: (_) => G3MetricDetail(
      metric: metric,
      repository: repository,
      endDay: endDay,
      backLabel: backLabel,
      band: band,
    ),
  ),
);

class G3MetricDetail extends StatefulWidget {
  const G3MetricDetail({
    super.key,
    required this.metric,
    required this.repository,
    required this.endDay,
    this.backLabel = 'Heute',
    this.band,
    this.initialPeriod,
    this.showDailyValue = false,
    this.now,
  });
  final G3Metric metric;
  final OpenBandRepository repository;
  final String endDay, backLabel;
  final BandSnapshot? band;
  final OBTrendPeriod? initialPeriod;
  final bool showDailyValue;
  final DateTime Function()? now;

  @override
  State<G3MetricDetail> createState() => _G3MetricDetailState();
}

class _G3MetricDetailState extends State<G3MetricDetail> {
  late OBTrendPeriod _period =
      widget.initialPeriod ??
      (widget.metric == G3Metric.rhr ? OBTrendPeriod.d90 : OBTrendPeriod.d30);
  G3Trend? _trend;
  G3Baseline? _baseline;
  _MetricSummary? _summary;
  bool _synthetic = false;
  bool _loading = true, _error = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant G3MetricDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metric != widget.metric ||
        oldWidget.endDay != widget.endDay ||
        !identical(oldWidget.repository, widget.repository)) {
      _trend = null;
      _load();
    }
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = false;
      _trend = null;
    });
    try {
      final days = switch (_period) {
        OBTrendPeriod.d7 => 7,
        OBTrendPeriod.d30 => 30,
        OBTrendPeriod.d90 => 90,
      };
      final trend = await widget.repository.readTrend(
        widget.metric,
        widget.endDay,
        days,
      );
      final day = await widget.repository.readDay(widget.endDay);
      final baseline = await widget.repository.readPersonalRange(
        widget.metric,
        widget.endDay,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _trend = trend;
        _synthetic = day.synthetic;
        _baseline = baseline;
        _summary = _MetricSummary.from(
          trend.points,
          baseline.status.phase == BaselinePhase.trusted
              ? baseline.range
              : null,
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _changePeriod(OBTrendPeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final metric = widget.metric;
    final trend = _trend;
    final summary = _summary;
    final average = summary?.average;
    final recovery = metric == G3Metric.recovery && !widget.showDailyValue;
    final days = switch (_period) {
      OBTrendPeriod.d7 => 7,
      OBTrendPeriod.d30 => 30,
      OBTrendPeriod.d90 => 90,
    };
    final nights = _bodyMetrics.contains(metric);
    final points = trend?.points ?? const <MetricPoint>[];
    final value = points.isEmpty ? null : _usable(points.last);
    final valueCount = points.where((p) => _usable(p) != null).length;
    final range =
        metric != G3Metric.skinTempZ &&
            _baseline?.status.phase == BaselinePhase.trusted
        ? _baseline?.range
        : null;
    final outside = value == null || range == null || range.contains(value)
        ? null
        : (value < range.low ? -1 : 1);
    final better =
        outside != null &&
        ((metric == G3Metric.rhr && outside < 0) ||
            ((metric == G3Metric.recovery || metric == G3Metric.hrv) &&
                outside > 0));
    final mark = metric == G3Metric.skinTempZ ? null : outside;
    final title = g3MetricName(metric);
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        bottom: false,
        child: chrome.G3DetailPage(
          bottomInset: kOBTabBarContentInset,
          header: chrome.OBPageHeader.detail(
            title: title.toUpperCase(),
            domain: g3MetricDomain(metric),
            subtitle: recovery
                ? 'Verlauf · $days Tage'
                : _longDate(widget.endDay),
            backLabel: widget.backLabel,
            onBack: () => Navigator.of(context).pop(),
            onTrailing: () => _showExplanation(context, metric),
          ),
          children: [
            if (_error)
              chrome.OBErrorBlock(
                title: 'Verlauf konnte nicht geladen werden',
                reason:
                    'Deine gespeicherten Messwerte sind gerade nicht lesbar.',
                onRetry: _load,
              )
            else if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              if (recovery) ...[
                Align(
                  alignment: Alignment.center,
                  child: chrome.OBSegmented(
                    items: const ['7 Tage', '30 Tage', '90 Tage'],
                    selected: _period.index,
                    onChanged: (i) => _changePeriod(OBTrendPeriod.values[i]),
                  ),
                ),
                const SizedBox(height: 0),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _number(summary?.average, metric),
                        style: g.t(
                          64,
                          68,
                          weight: FontWeight.w700,
                          tracking: -.06,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ø $days Tage',
                              style: g.t(17, 21, weight: FontWeight.w700),
                            ),
                            Text(
                              average == null
                                  ? 'Keine Werte in diesem Zeitraum'
                                  : 'Median ${_number(summary?.median, metric)}${range == null
                                        ? ''
                                        : range.contains(average)
                                        ? ' · im Normalbereich'
                                        : average < range.low
                                        ? ' · unter Normalbereich'
                                        : ' · über Normalbereich'}',
                              style: g.t(14, 18, color: g.ink2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else
                chrome.OBPanel(
                  child: metrics.OBLeadMetric(
                    domain: g3MetricDomain(metric),
                    label: title.toUpperCase(),
                    glyph: switch (g3MetricDomain(metric)) {
                      G3Domain.sleep => LucideIcons.moon,
                      G3Domain.load =>
                        metric == G3Metric.steps
                            ? LucideIcons.footprints
                            : LucideIcons.flame,
                      _ => LucideIcons.heartPulse,
                    },
                    state: value == null
                        ? metrics.OBLeadState.missing
                        : metric == G3Metric.skinTempZ || range == null
                        ? metrics.OBLeadState.plain
                        : mark == null
                        ? metrics.OBLeadState.normal
                        : better
                        ? metrics.OBLeadState.better
                        : metrics.OBLeadState.worse,
                    value: value,
                    valueText:
                        metric == G3Metric.sleepMinutes ||
                            metric == G3Metric.steps
                        ? _number(value, metric)
                        : null,
                    digits: _digits(metric),
                    unit: null,
                    signed: metric == G3Metric.skinTempZ,
                    note: metric == G3Metric.skinTempZ
                        ? g3NightOf(DateTime.parse(widget.endDay))
                        : range == null
                        ? _baseline?.status.phase == BaselinePhase.building
                              ? 'Basis im Aufbau'
                              : 'kein Normalbereich'
                        : 'normal ${_number(range.low, metric)}–${_number(range.high, metric)} ${_unit(metric)}',
                    basisChip: metric == G3Metric.skinTempZ
                        ? 'keine Wertung'
                        : _baselineChip(_baseline),
                    delta: value == null || range == null
                        ? null
                        : _number((value - range.median).abs(), metric),
                    deltaUp:
                        value == null || range == null || value >= range.median,
                    deltaChipOnPage: false,
                    caption: metric == G3Metric.skinTempZ
                        ? 'Relative Abweichung von deiner Basis'
                        : range == null
                        ? _baseline?.status.nightsHave == null ||
                                  _baseline?.status.nightsNeeded == null
                              ? 'Ohne verlässlichen Normalbereich'
                              : '${_baseline!.status.nightsHave} von ${_baseline!.status.nightsNeeded} ${g3CountNoun(_baseline!.status.nightsNeeded!, 'Wert', 'Werten')} gespeichert'
                        : value == null
                        ? null
                        : '${value >= range.median ? 'über' : 'unter'} deinem Median ${_number(range.median, metric)}',
                    scale: value == null ? null : _scale(metric, range),
                    title: 'Kein Messwert',
                    reason: 'Für diesen Tag liegt kein verlässlicher Wert vor.',
                  ),
                ),
              const SizedBox(height: 12),
              OBTrendChart(
                domain: g3MetricDomain(metric),
                title: recovery
                    ? 'VERLAUF'
                    : metric == G3Metric.skinTempZ
                    ? 'RELATIV · $days TAGE'
                    : '${_unit(metric).isEmpty ? title.toUpperCase() : _unit(metric)} · $days TAGE',
                headerNote: recovery ? '$valueCount von $days Tagen' : null,
                showPeriod: !recovery,
                period: _period,
                compactGaps: true,
                plotHeight: 144,
                values: [for (final p in points) _usable(p)],
                marks: [for (final p in points) _pointMark(metric, p, range)],
                min: _chartBounds(metric, points, range).$1,
                max: _chartBounds(metric, points, range).$2,
                band: range == null ? null : (range.low, range.high),
                median: recovery ? range?.median : null,
                zero: metric == G3Metric.skinTempZ ? 0 : null,
                xLabels: _period == OBTrendPeriod.d7
                    ? [for (final p in points) g3Weekday(DateTime.parse(p.day))]
                    : points.isEmpty
                    ? const []
                    : [
                        g3DateShort(DateTime.parse(points.first.day)),
                        g3DateShort(
                          DateTime.parse(points[(points.length - 1) ~/ 2].day),
                        ),
                        widget.endDay ==
                                    dayLabelOf(
                                      widget.now?.call() ?? DateTime.now(),
                                    ) &&
                                widget.band?.latestStoredAt != null &&
                                dayLabelOf(widget.band!.latestStoredAt!) ==
                                    widget.endDay
                            ? 'heute'
                            : _endLabel(widget.endDay),
                      ],
                footLeft: valueCount < 7
                    ? '$valueCount ${g3CountNoun(valueCount, 'Wert', 'Werte')} · Verlauf ab 7'
                    : 'Ø ${_number(summary?.average, metric)}${summary?.below == null ? '' : ' · ${summary!.below} ${g3CountNoun(summary.below!, nights ? 'Nacht' : 'Tag', nights ? 'Nächte' : 'Tage')} darunter'}',
                footRight:
                    '$valueCount von $days ${nights ? 'Nächten' : 'Tagen'}',
                footer: !recovery
                    ? null
                    : Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          if (valueCount < 7)
                            Text(
                              '$valueCount ${g3CountNoun(valueCount, 'Wert', 'Werte')} · Verlauf ab 7',
                              style: g.t(12, 16, color: g.muted),
                            ),
                          if (range != null)
                            G3Legend.band(
                              'normal ${_number(range.low, metric)}–${_number(range.high, metric)}',
                              domain: g3MetricDomain(metric),
                            ),
                          if ((summary?.below ?? 0) > 0)
                            G3Legend.mark(
                              '${summary!.below} darunter',
                              G3Deviation.worse,
                            ),
                          if ((summary?.above ?? 0) > 0)
                            G3Legend.mark(
                              '${summary!.above} darüber',
                              G3Deviation.better,
                            ),
                        ],
                      ),
                onPeriod: _changePeriod,
              ),
              if (summary != null) ...[
                const SizedBox(height: 12),
                _Stats(metric: metric, summary: summary, days: days),
                if (nights || metric == G3Metric.recovery) ...[
                  _outsideGutter(
                    chrome.OBSectionHeader(nights ? 'NÄCHTE' : 'TAGE'),
                  ),
                  chrome.OBPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        for (final p in points.reversed.take(4).indexed)
                          metrics.OBDayValueRow(
                            domain: g3MetricDomain(metric),
                            showBar: metric != G3Metric.recovery,
                            deviation:
                                !recovery ||
                                    range == null ||
                                    _usable(p.$2) == null ||
                                    range.contains(_usable(p.$2)!)
                                ? null
                                : _usable(p.$2)! < range.low
                                ? G3Deviation.worse
                                : G3Deviation.better,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => G3MetricDetail(
                                  metric: metric,
                                  repository: widget.repository,
                                  endDay: p.$2.day,
                                  backLabel: title,
                                  band: widget.band,
                                  showDailyValue: true,
                                ),
                              ),
                            ),
                            date: _date(p.$2.day),
                            value: p.$2.partial || p.$2.value == null
                                ? null
                                : _number(p.$2.value, metric),
                            note: p.$2.partial
                                ? 'teilweise erfasst'
                                : !recovery ||
                                      range == null ||
                                      _usable(p.$2) == null ||
                                      range.contains(_usable(p.$2)!)
                                ? null
                                : _usable(p.$2)! < range.low
                                ? 'unter Normalbereich'
                                : 'über Normalbereich',
                            share: _usable(p.$2) == null
                                ? null
                                : ((p.$2.value! -
                                              _chartBounds(
                                                metric,
                                                points,
                                                range,
                                              ).$1) /
                                          (_chartBounds(
                                                metric,
                                                points,
                                                range,
                                              ).$2 -
                                              _chartBounds(
                                                metric,
                                                points,
                                                range,
                                              ).$1))
                                      .clamp(0, 1),
                            last: p.$1 == math.min(points.length, 4) - 1,
                          ),
                      ],
                    ),
                  ),
                ],
                if (metric == G3Metric.rhr && _gaps(points).isNotEmpty) ...[
                  _outsideGutter(const chrome.OBSectionHeader('LÜCKEN')),
                  chrome.OBPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final gap in _gaps(points))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              '${g3DateShort(DateTime.parse(gap.$1))}'
                              '${gap.$1 == gap.$2 ? '' : '–${g3DateShort(DateTime.parse(gap.$2))}'}'
                              ' · ${gap.$3} ${g3CountNoun(gap.$3, 'Tag', 'Tage')} ohne Messwert',
                              style: g.t(14, 18, color: g.ink2),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
              if (widget.band != null)
                chrome.OBFooterStamp(
                  _bandStamp(widget.band!, now: widget.now?.call()),
                  synthetic: _synthetic,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

List<(String, String, int)> _gaps(List<MetricPoint> points) {
  final gaps = <(String, String, int)>[];
  String? start, end;
  var count = 0;
  for (final point in points) {
    if (_usable(point) == null) {
      start ??= point.day;
      end = point.day;
      count++;
    } else if (start != null) {
      gaps.add((start, end!, count));
      start = null;
      count = 0;
    }
  }
  if (start != null) gaps.add((start, end!, count));
  return gaps;
}

/// Single-value scale endpoints come from a trusted range or a defined metric.
(double, double) _personalBounds(PersonalRange range) {
  final pad = (range.high - range.low) / 2;
  return (range.low - pad, range.high + pad);
}

metrics.G3Scale? _scale(G3Metric metric, PersonalRange? range) {
  final bounds = switch (metric) {
    G3Metric.recovery => (0.0, 100.0),
    G3Metric.strain => (0.0, 21.0),
    G3Metric.skinTempZ => (-1.0, 1.0),
    G3Metric.hrv =>
      range == null
          ? null
          : (
              (_personalBounds(range).$1 / 10).floor() * 10.0,
              (_personalBounds(range).$2 / 10).ceil() * 10.0,
            ),
    _ => range == null ? null : _personalBounds(range),
  };
  if (bounds == null) return null;
  final (lo, hi) = bounds;
  return metrics.G3Scale(
    min: lo,
    max: hi,
    band: range == null
        ? null
        : (range.low.clamp(lo, hi), range.high.clamp(lo, hi)),
    median: metric == G3Metric.skinTempZ ? 0 : range?.median,
    ticks: metric == G3Metric.skinTempZ
        ? const [
            metrics.G3Tick(-1, 'kühler'),
            metrics.G3Tick(0, 'normal'),
            metrics.G3Tick(1, 'wärmer'),
          ]
        : [
            metrics.G3Tick(lo, _number(lo, metric)),
            if (range != null) ...[
              metrics.G3Tick(
                range.low,
                _number(range.low, metric),
                strong: true,
              ),
              metrics.G3Tick(
                range.high,
                _number(range.high, metric),
                strong: true,
              ),
            ],
            metrics.G3Tick(
              hi,
              '${_number(hi, metric)}${_unit(metric).isEmpty ? '' : ' ${_unit(metric)}'}',
            ),
          ],
  );
}

(double, double) _chartBounds(
  G3Metric metric,
  List<MetricPoint> points,
  PersonalRange? range,
) {
  final values = [
    for (final p in points)
      if (!p.partial && p.value?.isFinite == true) p.value!,
    if (range != null) range.low,
    if (range != null) range.high,
  ];
  if (metric == G3Metric.skinTempZ) {
    values.addAll([-0.5, 0.5]);
  }
  if (values.isEmpty) {
    return metric == G3Metric.recovery ? (0, 100) : (0, 1);
  }
  final lo = values.reduce(math.min), hi = values.reduce(math.max);
  final pad = math.max(
    (hi - lo) * (metric == G3Metric.hrv ? .5 : .25),
    metric == G3Metric.skinTempZ ? .1 : 1,
  );
  return (lo - pad, hi + pad);
}

OBTrendMark _pointMark(
  G3Metric metric,
  MetricPoint point,
  PersonalRange? range,
) {
  final value = point.partial ? null : point.value;
  if (value == null ||
      !value.isFinite ||
      range == null ||
      range.contains(value)) {
    return OBTrendMark.none;
  }
  if (metric == G3Metric.skinTempZ) return OBTrendMark.none;
  if (metric == G3Metric.rhr) {
    return value < range.low ? OBTrendMark.better : OBTrendMark.worse;
  }
  if (metric == G3Metric.recovery || metric == G3Metric.hrv) {
    return value > range.high ? OBTrendMark.better : OBTrendMark.worse;
  }
  return OBTrendMark.worse;
}

class _MetricSummary {
  const _MetricSummary(
    this.average,
    this.median,
    this.low,
    this.high,
    this.below,
    this.above,
  );
  final double? average, median, low, high;
  final int? below, above;
  factory _MetricSummary.from(List<MetricPoint> points, PersonalRange? range) {
    final values = [
      for (final p in points)
        if (_usable(p) != null) _usable(p)!,
    ]..sort();
    if (values.isEmpty) {
      return const _MetricSummary(null, null, null, null, null, null);
    }
    final mid = values.length ~/ 2;
    return _MetricSummary(
      values.reduce((a, b) => a + b) / values.length,
      values.length.isOdd ? values[mid] : (values[mid - 1] + values[mid]) / 2,
      values.first,
      values.last,
      range == null ? null : values.where((v) => v < range.low).length,
      range == null ? null : values.where((v) => v > range.high).length,
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({
    required this.metric,
    required this.summary,
    required this.days,
  });
  final G3Metric metric;
  final _MetricSummary summary;
  final int days;
  @override
  Widget build(BuildContext context) => metrics.OBStatRow([
    (
      'Ø $days ${_bodyMetrics.contains(metric) ? 'NÄCHTE' : 'TAGE'}',
      summary.average == null ? null : _number(summary.average, metric),
      null,
    ),
    (
      'MEDIAN',
      summary.median == null ? null : _number(summary.median, metric),
      null,
    ),
    (
      'SPANNE',
      summary.low == null
          ? null
          : '${_number(summary.low, metric)}–${_number(summary.high, metric)}',
      null,
    ),
  ], domain: g3MetricDomain(metric));
}

void _showExplanation(
  BuildContext context,
  G3Metric metric,
) => chrome.showOBInfoSheet(
  context,
  title: g3MetricName(metric),
  paragraphs: [
    metric == G3Metric.skinTempZ
        ? 'Die Abweichung ist relativ zu deiner Basis. Sie zeigt keine Körpertemperatur. Tage ohne Messung bleiben leer.'
        : metric == G3Metric.steps
        ? 'Der Zähler im Band liefert die Schritte. Stunden ohne gespeicherte Messung bleiben leer.'
        : 'Dein Normalbereich stammt aus gespeicherten Messungen. Tage ohne Messung werden nicht geschätzt und zählen nicht zum Durchschnitt.',
  ],
);

void _showWeightInfo(BuildContext context) => chrome.showOBInfoSheet(
  context,
  title: 'Gewicht',
  paragraphs: const [
    'Der Verlauf zeigt deine datierten Einträge. Tage ohne Eintrag bleiben leer.',
  ],
);

/// Band-owned values plus the dated, manually recorded weight.
class G3AllMetrics extends StatefulWidget {
  const G3AllMetrics({
    super.key,
    required this.repository,
    required this.endDay,
    this.band,
  });
  final OpenBandRepository repository;
  final String endDay;
  final BandSnapshot? band;
  @override
  State<G3AllMetrics> createState() => _G3AllMetricsState();
}

class _G3AllMetricsState extends State<G3AllMetrics> {
  Map<G3Metric, G3Trend>? _trends;
  G3Weight? _weight;
  bool _error = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _trends = null;
      _error = false;
    });
    try {
      final trends = <G3Metric, G3Trend>{};
      for (final metric in _bodyMetrics) {
        trends[metric] = await widget.repository.readTrend(
          metric,
          widget.endDay,
          7,
        );
      }
      final weight = await widget.repository.readG3Weight(widget.endDay, 7);
      if (!mounted || request != _request) return;
      setState(() {
        _trends = trends;
        _weight = weight;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final trends = _trends;
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        bottom: false,
        child: chrome.G3DetailPage(
          bottomInset: kOBTabBarContentInset,
          header: chrome.OBPageHeader.detail(
            title: 'MESSWERTE',
            subtitle: g3NightOf(DateTime.parse(widget.endDay)),
            backLabel: 'Heute',
            onBack: () => Navigator.pop(context),
            onTrailing: () => chrome.showOBInfoSheet(
              context,
              title: 'Messwerte',
              paragraphs: const [
                'Strich: letzter Wert. Ein grauer Bereich zeigt deinen Normalbereich, sobald er verlässlich ist. Farbe nur außerhalb davon.',
              ],
            ),
          ),
          children: [
            if (_error)
              chrome.OBErrorBlock(
                title: 'Messwerte konnten nicht geladen werden',
                reason: 'Die gespeicherten Werte sind gerade nicht lesbar.',
                onRetry: _load,
              )
            else if (trends == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              chrome.OBPanel(
                hero: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('KÖRPER', style: g.caps()),
                    const SizedBox(height: 8),
                    for (final metric in _bodyMetrics)
                      _bodyRow(
                        metric,
                        trends[metric]!,
                        last: metric == _bodyMetrics.last,
                        onTap: () => openG3MetricDetail(
                          context,
                          metric,
                          repository: widget.repository,
                          endDay: widget.endDay,
                          backLabel: 'Messwerte',
                          band: widget.band,
                        ),
                      ),
                  ],
                ),
              ),
              _outsideGutter(const chrome.OBSectionHeader('EINGETRAGEN')),
              chrome.OBListRow(
                icon: LucideIcons.scale,
                title: 'Gewicht',
                subtitle: _weight?.history.latest == null
                    ? 'Noch kein Eintrag'
                    : _weightSourceLabel(
                        _weight!.sources[_weight!.history.latest!.day],
                      ),
                value: _weight?.history.latest == null
                    ? '—'
                    : '${g3Number(_weight!.history.latest!.value, digits: 1)} kg',
                onTap: () => pushInTab<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => G3WeightDetail(
                      repository: widget.repository,
                      endDay: widget.endDay,
                      band: widget.band,
                      backLabel: 'Messwerte',
                    ),
                  ),
                ),
              ),
              if (widget.band != null)
                chrome.OBFooterStamp(_bandStamp(widget.band!)),
            ],
          ],
        ),
      ),
    );
  }
}

class G3WeightDetail extends StatefulWidget {
  const G3WeightDetail({
    super.key,
    required this.repository,
    required this.endDay,
    this.band,
    this.backLabel = 'Heute',
  });
  final OpenBandRepository repository;
  final String endDay;
  final BandSnapshot? band;
  final String backLabel;
  @override
  State<G3WeightDetail> createState() => _G3WeightDetailState();
}

class _G3WeightDetailState extends State<G3WeightDetail> {
  OBTrendPeriod _period = OBTrendPeriod.d90;
  G3Weight? _weight;
  bool _error = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _weight = null;
      _error = false;
    });
    try {
      final weight = await widget.repository.readG3Weight(
        widget.endDay,
        switch (_period) {
          OBTrendPeriod.d7 => 7,
          OBTrendPeriod.d30 => 30,
          OBTrendPeriod.d90 => 90,
        },
      );
      if (!mounted || request != _request) return;
      setState(() => _weight = weight);
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final history = _weight?.history;
    final values =
        history?.entries
            .where((e) => e.usableForTrend)
            .map((e) => e.value)
            .toList() ??
        [];
    final lo = values.isEmpty ? 0.0 : values.reduce(math.min) - 2;
    final hi = values.isEmpty ? 100.0 : values.reduce(math.max) + 2;
    final latest = history?.latest;
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        bottom: false,
        child: chrome.G3DetailPage(
          bottomInset: kOBTabBarContentInset,
          header: chrome.OBPageHeader.detail(
            title: 'GEWICHT',
            subtitle: _longDate(widget.endDay),
            backLabel: widget.backLabel,
            onBack: () => Navigator.pop(context),
            onTrailing: () => _showWeightInfo(context),
          ),
          children: [
            if (_error)
              chrome.OBErrorBlock(
                title: 'Gewicht konnte nicht geladen werden',
                reason: 'Deine Einträge sind gerade nicht lesbar.',
                onRetry: _load,
              )
            else if (history == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              metrics.OBLeadMetric(
                label: '',
                state: metrics.OBLeadState.plain,
                value: latest?.value,
                digits: 1,
                unit: 'kg',
                basisChip: 'kein Ziel',
                note: latest == null
                    ? 'kein Eintrag'
                    : _weightSourceLabel(_weight!.sources[latest.day]),
                caption: latest != null && latest.day != widget.endDay
                    ? 'Eintrag vom ${_date(latest.day)}'
                    : null,
                title: 'Noch kein Gewicht',
                reason: 'Trage dein Gewicht ein, um einen Verlauf zu sehen.',
              ),
              const SizedBox(height: 10),
              OBTrendChart(
                title: 'GEWICHT · kg',
                period: _period,
                values: history.trend,
                sparse: true,
                min: lo,
                max: hi,
                xLabels: [
                  g3DateShort(
                    DateTime.parse(
                      g3DaysEnding(widget.endDay, history.days).first,
                    ),
                  ),
                  _endLabel(widget.endDay),
                ],
                footLeft: history.entries.isEmpty && latest != null
                    ? 'Keine Einträge im Zeitraum · letzter Eintrag ${_date(latest.day)}'
                    : '${history.entries.length} ${g3CountNoun(history.entries.length, 'Eintrag', 'Einträge')} · keine Tageswerte geschätzt',
                footRight: values.isEmpty
                    ? null
                    : '${_number(values.reduce(math.min), G3Metric.respRate)}–${_number(values.reduce(math.max), G3Metric.respRate)} kg',
                onPeriod: (period) {
                  setState(() => _period = period);
                  _load();
                },
              ),
              const SizedBox(height: 12),
              chrome.OBActionPrimary(
                'Gewicht eintragen',
                expand: true,
                onPressed: () async {
                  await openG3WeightEntry(
                    context,
                    widget.repository,
                    widget.endDay,
                  );
                  if (mounted) _load();
                },
              ),
              _outsideGutter(const chrome.OBSectionHeader('EINTRÄGE')),
              for (final entry in history.entries) ...[
                chrome.OBListRow(
                  icon: LucideIcons.scale,
                  title: _date(entry.day),
                  subtitle: _weightSourceLabel(_weight!.sources[entry.day]),
                  value: '${g3Number(entry.value, digits: 1)} kg',
                  onTap: _weight!.sources[entry.day] == G3WeightSource.manual
                      ? () async {
                          await openG3WeightEntry(
                            context,
                            widget.repository,
                            entry.day,
                          );
                          if (mounted) _load();
                        }
                      : () => _showWeightSourceInfo(
                          context,
                          imported:
                              _weight!.sources[entry.day] ==
                              G3WeightSource.imported,
                        ),
                ),
                const SizedBox(height: 6),
              ],
              if (widget.band != null)
                chrome.OBFooterStamp(_bandStamp(widget.band!)),
            ],
          ],
        ),
      ),
    );
  }
}

void _showWeightSourceInfo(
  BuildContext context, {
  required bool imported,
}) => chrome.showOBInfoSheet(
  context,
  title: imported ? 'Apple Health' : 'Quelle unbekannt',
  paragraphs: [
    imported
        ? 'Dieser Gewichtseintrag wurde aus Apple Health übernommen. Die Quelle bleibt am Eintrag sichtbar.'
        : 'Die Quelle dieses Gewichtseintrags ist nicht belegt. Er kann hier nicht als manueller Eintrag geändert werden.',
  ],
);

Future<void> openG3WeightEntry(
  BuildContext context,
  OpenBandRepository repository,
  String day,
) async {
  JournalDaySnapshot base;
  try {
    base = await repository.readJournalDay(day);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Eintrag konnte nicht geladen werden.')),
    );
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WeightEntrySheet(repository: repository, base: base),
  );
}

class _WeightEntrySheet extends StatefulWidget {
  const _WeightEntrySheet({required this.repository, required this.base});
  final OpenBandRepository repository;
  final JournalDaySnapshot base;
  @override
  State<_WeightEntrySheet> createState() => _WeightEntrySheetState();
}

class _WeightEntrySheetState extends State<_WeightEntrySheet> {
  late final TextEditingController _input = TextEditingController(
    text:
        widget.base.metrics[kWeightJournalField]?.value
            .toStringAsFixed(1)
            .replaceAll('.', ',') ??
        '',
  );
  late int? _minute = widget.base.metrics[kWeightJournalField]?.atMinuteOfDay;
  bool _saving = false, _conflicted = false;
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final input = _input.text.trim();
    final parsed = double.tryParse(input.replaceAll(',', '.'));
    final max = kJournalFieldsByKey[kWeightJournalField]!.max;
    if (!RegExp(r'^\d{1,3}(?:[,.]\d)?$').hasMatch(input) ||
        parsed == null ||
        !parsed.isFinite ||
        parsed <= 0 ||
        parsed > max) {
      setState(
        () => _error =
            'Gewicht zwischen 0 und ${max.toStringAsFixed(0)} kg in 0,1-kg-Schritten eingeben.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.patchJournalDay(
        JournalDayPatch.fromBase(
          widget.base,
          metrics: {
            kWeightJournalField: JournalMetricValue(
              parsed,
              atMinuteOfDay: _minute,
            ),
          },
        ),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on JournalConflict {
      if (mounted) {
        setState(() {
          _saving = false;
          _conflicted = true;
          _error = 'Eintrag wurde anderswo geändert. Bitte erneut öffnen.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Speichern fehlgeschlagen. Erneut versuchen.';
        });
      }
    }
  }

  Future<void> _chooseTime() async {
    final now = TimeOfDay.now();
    final chosen = await showTimePicker(
      context: context,
      initialTime: _minute == null
          ? now
          : TimeOfDay(hour: _minute! ~/ 60, minute: _minute! % 60),
    );
    if (!mounted || chosen == null) return;
    setState(() => _minute = chosen.hour * 60 + chosen.minute);
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final timeLabel = _minute == null
        ? 'ohne Uhrzeit'
        : g3Clock(DateTime(2000, 1, 1, _minute! ~/ 60, _minute! % 60));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: chrome.OBSheet(
        title: 'Gewicht eintragen',
        subtitle: 'Bleibt auf diesem iPhone. Quelle steht am Eintrag.',
        cancelLabel: 'Abbrechen',
        confirmLabel: _saving ? 'Speichert …' : 'Speichern',
        onCancel: _saving ? null : () => Navigator.pop(context),
        onConfirm: _saving || _conflicted ? null : _save,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: 'Quelle: Manuell',
              excludeSemantics: true,
              child: Container(
                height: 34,
                padding: const EdgeInsets.all(3),
                decoration: g.pressed(radius: 17),
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: g.raised(radius: 13),
                  child: Text(
                    'Manuell',
                    style: g.t(12, 14, weight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            chrome.OBFormField.number(
              label: 'GEWICHT',
              controller: _input,
              unit: 'kg',
              when: '${_date(widget.base.day)} · $timeLabel',
              onTime: _saving ? null : _chooseTime,
            ),
            if (_error != null)
              Text(_error!, style: g.t(13, 17, color: g.worseText)),
          ],
        ),
      ),
    );
  }
}
