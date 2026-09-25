import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/day_label.dart';
import 'controller.dart';
import 'domain.dart';
import 'health.dart';
import 'night_scalar_detail.dart';
import 'scale.dart';
import 'screens.dart';
import 'theme.dart';

bool _isNightScalar(MetricKey key) => switch (key) {
  MetricKey.hrv ||
  MetricKey.restingHr ||
  MetricKey.respiration ||
  MetricKey.skinTemperature => true,
  MetricKey.recovery || MetricKey.sleepDuration || MetricKey.strain => false,
};

/// Full-screen metric detail (Paper "Messwert-Detail"): hero, night-for-night
/// bars and the rows leading into sleep and the baseline explanation.
class OpenBandMetricDetail extends StatefulWidget {
  final OpenBandController controller;
  final MetricKey metricKey;
  final String label, subtitle, unit;
  final IconData icon;
  final Color Function(OB) color, tint;
  final int digits;

  /// The parent screen's title for the back pill.
  final String? backText;
  const OpenBandMetricDetail({
    super.key,
    required this.controller,
    required this.metricKey,
    required this.label,
    required this.subtitle,
    required this.unit,
    required this.icon,
    required this.color,
    required this.tint,
    this.digits = 0,
    this.backText,
  });

  static void push(
    BuildContext context, {
    required OpenBandController controller,
    required MetricKey metricKey,
    required String label,
    required String subtitle,
    required String unit,
    required IconData icon,
    required Color Function(OB) color,
    required Color Function(OB) tint,
    int digits = 0,
    String? backText,
  }) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => OpenBandMetricDetail(
        controller: controller,
        metricKey: metricKey,
        label: label,
        subtitle: subtitle,
        unit: unit,
        icon: icon,
        color: color,
        tint: tint,
        digits: digits,
        backText: backText,
      ),
    ),
  );

  @override
  State<OpenBandMetricDetail> createState() => _OpenBandMetricDetailState();
}

class _OpenBandMetricDetailState extends State<OpenBandMetricDetail> {
  // Paper G2: a fixed 30-night window, no range switch.
  final int _nights = 30;
  int _generation = 0;
  List<MetricPoint>? _points;
  bool _error = false;
  late String _heardDay;

  bool get _nightScalar => _isNightScalar(widget.metricKey);

  @override
  void initState() {
    super.initState();
    _heardDay = widget.controller.selectedDay;
    widget.controller.addListener(_onController);
    if (!_nightScalar) _load();
  }

  @override
  void didUpdateWidget(OpenBandMetricDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = !identical(
      oldWidget.controller,
      widget.controller,
    );
    if (controllerChanged) {
      oldWidget.controller.removeListener(_onController);
      _heardDay = widget.controller.selectedDay;
      widget.controller.addListener(_onController);
    }
    final wasNight = _isNightScalar(oldWidget.metricKey);
    if (wasNight && !_nightScalar) {
      _points = null;
      _error = false;
      _load();
      return;
    }
    if (!_nightScalar &&
        (oldWidget.metricKey != widget.metricKey || controllerChanged)) {
      _load();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _generation++;
    super.dispose();
  }

  void _onController() {
    final day = widget.controller.selectedDay;
    if (day == _heardDay) return;
    _heardDay = day;
    if (!_nightScalar) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final controller = widget.controller;
    final repository = controller.repository;
    final key = widget.metricKey;
    final day = controller.selectedDay;
    final nights = _nights;
    if (mounted) {
      setState(() {
        _points = null;
        _error = false;
      });
    }
    bool current() =>
        mounted &&
        generation == _generation &&
        identical(controller, widget.controller) &&
        identical(repository, widget.controller.repository) &&
        key == widget.metricKey &&
        day == widget.controller.selectedDay &&
        nights == _nights;
    try {
      final points = await repository.readMetricHistory(key, day, nights);
      if (!current()) return;
      setState(() {
        _points = points;
        _error = false;
      });
    } catch (_) {
      if (!current()) return;
      setState(() => _error = true);
    }
  }

  // Strain is scored per waking day, everything else per night; the copy and
  // the onward links follow that, and strain carries no baseline at all.
  bool get _nightly => widget.metricKey != MetricKey.strain;

  DayMetric _metric(OpenBandDay day) => switch (widget.metricKey) {
    MetricKey.hrv => day.hrv,
    MetricKey.restingHr => day.restingHr,
    MetricKey.respiration => day.respiration,
    MetricKey.skinTemperature => day.skinTemperature,
    MetricKey.recovery => day.recovery,
    MetricKey.sleepDuration => day.sleep.duration,
    MetricKey.strain => day.strain,
  };

  void _basis(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (c) {
      final p = OB.of(c);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'So entsteht die Basis',
                style: p.text(18, weight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                'Die Basis ist ein exponentiell gewichteter Mittelwert deiner '
                'letzten 30 Nächte mit Messung: neuere Nächte zählen stärker, '
                'Ausreißer werden gedämpft. Fehlende Nächte zählen nicht.',
              ),
              const SizedBox(height: 12),
              OBAction('Schließen', onPressed: () => Navigator.pop(c)),
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    if (_nightScalar) {
      return OpenBandNightScalarDetail(
        controller: widget.controller,
        metricKey: widget.metricKey,
        label: widget.label,
        unit: widget.unit,
        icon: widget.icon,
        color: widget.color,
        tint: widget.tint,
        digits: widget.digits,
        backText: widget.backText,
      );
    }
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final p = OB.of(context);
        final day = widget.controller.day;
        final metric = day == null ? const DayMetric.missing() : _metric(day);
        final strain = widget.metricKey == MetricKey.strain;
        final today =
            widget.controller.selectedDay ==
            todayLabel(widget.controller.now());
        final verdict = dayMetricVerdict(widget.metricKey, metric);
        final spread = metric.baselineSpread;
        final band = metric.baseline == null || spread == null
            ? null
            : (
                metric.baseline! - 1.253 * spread,
                metric.baseline! + 1.253 * spread,
              );
        final compared = metric.baseline != null && metric.value != null;
        final stored = widget.controller.band.latestStoredAt;
        final caption = p
            .text(10, weight: FontWeight.w500, color: p.muted)
            .copyWith(height: 12 / 10);
        String short(String d) =>
            DateFormat('dd.MM', 'de_DE').format(DateTime.parse(d));
        final status = !compared
            ? obMetricStatus(metric.value, metric.baseline)
            : obMetricComparisonStatus(
                metric.value!,
                metric.baseline!,
                digits: widget.digits,
              );
        final max = strain ? 21.0 : 100.0;
        return Scaffold(
          backgroundColor: p.canvas,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                OBPageHeader(
                  title: widget.label,
                  subtitle: widget.subtitle,
                  backText: widget.backText,
                  onInfo: _nightly ? () => _basis(context) : null,
                  infoLabel: 'So entsteht die Basis',
                ),
                // Paper G2 hero: label over the value, the comparison (or the
                // running-day pill) at the right, the scale with the range.
                OBCard(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 2,
                              children: [
                                Text(
                                  (today
                                          ? (_nightly
                                                ? 'Nacht auf heute'
                                                : stored == null
                                                ? 'Heute'
                                                : 'Heute · bis ${obTime(stored)}')
                                          : obDayTitle(
                                              widget.controller.selectedDay,
                                            ))
                                      .toUpperCase(),
                                  style: p.label().copyWith(height: 12 / 10),
                                ),
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  spacing: 6,
                                  children: [
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          obNumber(
                                            metric.value,
                                            digits: widget.digits,
                                          ),
                                          style: p
                                              .text(
                                                60,
                                                weight: FontWeight.w700,
                                                color: metric.value == null
                                                    ? p.gap
                                                    : p.ink,
                                              )
                                              .copyWith(
                                                height: 62 / 60,
                                                letterSpacing: -.04 * 60,
                                              ),
                                        ),
                                      ),
                                    ),
                                    if (metric.value != null)
                                      Text(
                                        widget.unit,
                                        style: p
                                            .text(14, color: p.muted)
                                            .copyWith(height: 18 / 14),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (strain && today && metric.value != null)
                            Container(
                              height: 26,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: p.insetDecoration(radius: 13),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 6,
                                children: [
                                  OBLed(on: true, color: p.ink, size: 6),
                                  Text(
                                    'läuft',
                                    style: p.text(12, weight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            )
                          else if (status.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 8,
                                bottom: 8,
                              ),
                              child: Text(
                                status,
                                style: p
                                    .text(
                                      13,
                                      weight:
                                          compared &&
                                              verdict != MetricVerdict.normal
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: compared
                                          ? obVerdictText(p, verdict) ?? p.ink
                                          : p.muted,
                                    )
                                    .copyWith(height: 16 / 13),
                              ),
                            ),
                        ],
                      ),
                      OBScale(
                        min: 0,
                        max: max,
                        value: metric.value,
                        target: band == null ? metric.baseline : null,
                        baseLow: band?.$1,
                        baseHigh: band?.$2,
                        fill: strain ? p.strain : p.ink,
                        ticks: 4,
                        captionGap: 10,
                        mark: obVerdictMark(p, verdict),
                        markEdge: obVerdictText(p, verdict),
                        labels: (
                          '0',
                          metric.baseline == null
                              ? null
                              : band == null
                              ? 'Basis ${obNumber(metric.baseline, digits: widget.digits)}'
                              : 'Basis ${obNumber(band.$1)}–${obNumber(band.$2)} · Ø ${obNumber(metric.baseline)}',
                          strain ? '21' : '100',
                        ),
                      ),
                      // A running day is counted up to the stored data.
                      if (strain && today && stored != null)
                        Text(
                          'Der Tag ist nicht vorbei. Gezählt wird nur, was '
                          'bis ${obTime(stored)} übertragen ist.',
                          style: p
                              .text(14, color: p.muted)
                              .copyWith(height: 20 / 14),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                OBCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _nightly ? 'NACHT FÜR NACHT' : 'TAG FÜR TAG',
                              style: p.label().copyWith(height: 12 / 10),
                            ),
                          ),
                          Text(
                            '${_points?.where((e) => e.value != null).length ?? 0} von $_nights ${_nightly ? 'Nächten' : 'Tagen'}',
                            style: caption,
                          ),
                        ],
                      ),
                      CustomPaint(
                        size: const Size.fromHeight(110),
                        painter: NightRangeBarsPainter(
                          p: p,
                          values: [
                            for (final pt in _points ?? const <MetricPoint>[])
                              pt.value,
                          ],
                          nights: _nights,
                          baseline: null,
                          band: band,
                          newest: obVerdictMark(p, verdict) ?? p.ink,
                          visible:
                              _points?.any((e) => e.value != null) ?? false,
                        ),
                      ),
                      if (_points?.isNotEmpty == true)
                        Row(
                          children: [
                            Text(short(_points!.first.day), style: caption),
                            Expanded(
                              child: Text(
                                band == null
                                    ? ''
                                    : 'grau = Basis · hohl = keine ${_nightly ? 'Nacht' : 'Messung'}',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: caption,
                              ),
                            ),
                            Text(short(_points!.last.day), style: caption),
                          ],
                        ),
                      if (_error)
                        Text(
                          'Verlauf konnte nicht geladen werden.',
                          style: p.text(13, color: p.danger),
                        ),
                    ],
                  ),
                ),
                if (_nightly) const SizedBox(height: 10),
                if (_nightly)
                  OBCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        _row(
                          p,
                          'Verlauf in der Nacht',
                          day?.sleep.onset != null && day?.sleep.wake != null
                              ? '${obTime(day!.sleep.onset)} – ${obTime(day.sleep.wake)}'
                              : '—',
                          () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  OpenBandSleep(controller: widget.controller),
                            ),
                          ),
                        ),
                        Container(height: 1, color: p.line),
                        _row(
                          p,
                          'So entsteht die Basis',
                          '30 Nächte',
                          () => _basis(context),
                        ),
                      ],
                    ),
                  ),
                if (day?.synthetic == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      'Synthetische Daten',
                      textAlign: TextAlign.center,
                      style: p
                          .text(11, weight: FontWeight.w500, color: p.muted)
                          .copyWith(height: 14 / 11, letterSpacing: .66),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Paper G2: text rows, value muted, a light "›".
  Widget _row(OB p, String label, String trailing, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: p
                      .text(15, weight: FontWeight.w500)
                      .copyWith(height: 18 / 15),
                ),
              ),
              Text(
                trailing,
                style: p.text(13, color: p.muted).copyWith(height: 16 / 13),
              ),
              ExcludeSemantics(
                child: Text(
                  '›',
                  style: p.text(16, color: p.gap).copyWith(height: 20 / 16),
                ),
              ),
            ],
          ),
        ),
      );
}
