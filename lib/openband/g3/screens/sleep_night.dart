import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain.dart';
import '../../tab_bar.dart' show kOBTabBarContentInset;
import '../../time.dart';
import '../chrome.dart' as chrome;
import '../count_copy.dart';
import '../g3_format.dart';
import '../g3_theme.dart';
import '../metrics.dart'
    show G3LabelRow, G3Scale, G3Tick, OBLeadMetric, OBLeadState;
import '../sleep_parts.dart';

bool nightSignalHasUncoveredInterval(
  NightSignalSeries series,
  ({DateTime start, DateTime end}) window,
) {
  final maxGap = series.maxConnectingGap;
  final readings =
      series.readings
          .where(
            (r) => !r.at.isBefore(window.start) && !r.at.isAfter(window.end),
          )
          .toList()
        ..sort((a, b) => a.at.compareTo(b.at));
  if (readings.any((r) => r.value == null)) return true;
  final valid = readings.where((r) => r.value != null).toList();
  if (valid.isEmpty || maxGap == null) return false;
  if (valid.first.at.difference(window.start) > maxGap ||
      window.end.difference(valid.last.at) > maxGap) {
    return true;
  }
  for (var i = 1; i < valid.length; i++) {
    if (valid[i].at.difference(valid[i - 1].at) > maxGap) return true;
  }
  return false;
}

class G3SleepNightSignals extends StatefulWidget {
  const G3SleepNightSignals({
    super.key,
    required this.repository,
    required this.day,
    this.initialKind = NightSignalKind.pulse,
    this.storedAt,
    this.now,
  });
  final OpenBandRepository repository;
  final String day;
  final NightSignalKind initialKind;
  final DateTime? storedAt;
  final DateTime Function()? now;
  @override
  State<G3SleepNightSignals> createState() => _G3SleepNightSignalsState();
}

class _G3SleepNightSignalsState extends State<G3SleepNightSignals> {
  late NightSignalKind _kind = widget.initialKind;
  late Future<NightSignals> _night = widget.repository.readNightSignals(
    widget.day,
  );
  late Future<OpenBandDay> _day = widget.repository.readDay(widget.day);
  late Future<G3Baseline> _baseline = _range();

  Future<G3Baseline> _range() =>
      widget.repository.readPersonalRange(switch (_kind) {
        NightSignalKind.pulse => G3Metric.rhr,
        NightSignalKind.hrv => G3Metric.hrv,
        NightSignalKind.respiration => G3Metric.respRate,
      }, widget.day);

  void _select(int index) => setState(() {
    _kind = NightSignalKind.values[index];
    _baseline = _range();
  });

  void _retry() => setState(() {
    _night = widget.repository.readNightSignals(widget.day);
    _day = widget.repository.readDay(widget.day);
    _baseline = _range();
  });

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
            title: 'NACHTVERLAUF',
            domain: G3Domain.sleep,
            subtitle: g3NightOf(DateTime.parse(widget.day)),
            backLabel: 'Schlaf',
            onBack: () => Navigator.of(context).pop(),
            onTrailing: () => chrome.showOBInfoSheet(
              context,
              title: 'Nachtverlauf',
              paragraphs: const [
                'Gespeicherte Signale während der erkannten Nacht. Lücken bleiben leer; einzelne Werte werden nicht verbunden.',
              ],
            ),
          ),
          children: [
            chrome.OBSegmented(
              items: const ['Puls', 'HRV', 'Atemfrequenz'],
              selected: _kind.index,
              onChanged: _select,
              expand: true,
            ),
            const SizedBox(height: 12),
            FutureBuilder<OpenBandDay>(
              future: _day,
              builder: (context, daySnap) => FutureBuilder<G3Baseline>(
                future: _baseline,
                builder: (context, baselineSnap) {
                  final metric = switch (_kind) {
                    NightSignalKind.pulse => daySnap.data?.restingHr,
                    NightSignalKind.hrv => daySnap.data?.hrv,
                    NightSignalKind.respiration => daySnap.data?.respiration,
                  };
                  final basis = baselineSnap.data;
                  String status() {
                    if (basis == null) {
                      return baselineSnap.hasError
                          ? 'Basis nicht verfügbar'
                          : 'Basis wird geladen';
                    }
                    return switch (basis.status.phase) {
                      BaselinePhase.trusted =>
                        basis.range == null
                            ? 'kein Normalbereich'
                            : 'eigener Normalbereich',
                      BaselinePhase.building =>
                        basis.status.remaining == null
                            ? 'Basis im Aufbau'
                            : 'noch ${basis.status.remaining} ${g3CountNoun(basis.status.remaining!, 'Nacht', 'Nächte')}',
                      BaselinePhase.none => 'kein Normalbereich',
                    };
                  }

                  final range = basis?.status.phase == BaselinePhase.trusted
                      ? basis?.range
                      : null;
                  final value = metric?.value;
                  final delta = value == null || range == null
                      ? null
                      : value - range.median;
                  return chrome.OBPanel(
                    hero: true,
                    child: OBLeadMetric(
                      label: switch (_kind) {
                        NightSignalKind.pulse => 'RUHEPULS',
                        NightSignalKind.hrv => 'HRV',
                        NightSignalKind.respiration => 'ATEMFREQUENZ',
                      },
                      domain: G3Domain.recovery,
                      glyph: LucideIcons.heartPulse,
                      state: value == null
                          ? OBLeadState.missing
                          : OBLeadState.normal,
                      value: value,
                      digits: _digits,
                      note: range == null
                          ? status()
                          : 'normal ${_number(range.low)}–${_number(range.high)} $_unit',
                      delta: delta == null ? null : _number(delta.abs()),
                      deltaUp: delta == null || delta >= 0,
                      caption: range == null || delta == null
                          ? null
                          : '${delta == 0
                                ? 'auf'
                                : delta > 0
                                ? 'über'
                                : 'unter'} deinem Median ${_number(range.median)}',
                      scale: range == null ? null : _trustedScale(range),
                      title: 'Keine Daten',
                      reason:
                          metric?.reason ??
                          'Keine gespeicherten Werte für diese Nacht.',
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<NightSignals>(
              future: _night,
              builder: (context, snapshot) {
                final night = snapshot.data;
                if (snapshot.hasError) {
                  return chrome.OBErrorBlock(
                    title: 'Nachtverlauf nicht geladen',
                    reason: 'Bitte erneut versuchen.',
                    onRetry: _retry,
                  );
                }
                final window = night?.window;
                final series = night?.signal(_kind);
                final recorded =
                    series?.readings
                        .where(
                          (r) =>
                              r.value != null &&
                              window != null &&
                              !r.at.isBefore(window.start) &&
                              !r.at.isAfter(window.end),
                        )
                        .toList() ??
                    const <NightSignalReading>[];
                NightSignalReading? lowest;
                for (final reading in recorded) {
                  if (lowest == null || reading.value! < lowest.value!) {
                    lowest = reading;
                  }
                }
                return chrome.OBPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      G3LabelRow(
                        '${switch (_kind) {
                          NightSignalKind.pulse => 'PULS',
                          NightSignalKind.hrv => 'HRV',
                          NightSignalKind.respiration => 'ATEMFREQUENZ',
                        }} · NACHT',
                        domain: G3Domain.recovery,
                        glyph: LucideIcons.heartPulse,
                        note: _unit,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        lowest == null
                            ? 'tiefster —'
                            : 'tiefster ${_number(lowest.value!)} um ${obSleepClock(recordedTime(lowest.at, night?.recordingTimezone))}',
                        style: g.t(15, 20),
                      ),
                      const SizedBox(height: 12),
                      if (window != null &&
                          series != null &&
                          recorded.isNotEmpty)
                        OBNightTrace(
                          domain: G3Domain.recovery,
                          series: series,
                          gaps: night?.unobservedGaps,
                          start: recordedTime(
                            window.start,
                            night?.recordingTimezone,
                          ),
                          end: recordedTime(
                            window.end,
                            night?.recordingTimezone,
                          ),
                        )
                      else
                        G3Dashed(
                          height: 180,
                          child: Center(
                            child: Text(
                              night?.processing == true
                                  ? 'Wird neu ausgewertet'
                                  : series?.reason ??
                                        'Keine gespeicherten Werte',
                              style: g.t(13, 17, color: g.ink2),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            FutureBuilder<OpenBandDay>(
              future: _day,
              builder: (context, snapshot) => chrome.OBFooterStamp(
                g3DataThrough(
                  widget.storedAt,
                  now: widget.now?.call() ?? DateTime.now(),
                ),
                synthetic: snapshot.data?.synthetic == true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  int get _digits => _kind == NightSignalKind.respiration ? 1 : 0;
  String get _unit => _kind == NightSignalKind.hrv ? 'ms' : '/min';
  String _number(double value) => g3Number(value, digits: _digits);

  G3Scale? _trustedScale(PersonalRange range) {
    final width = range.high - range.low;
    if (width <= 0) return null;
    final from = _kind == NightSignalKind.pulse
        ? ((range.low - width) / 5).floor() * 5.0
        : range.low - width;
    final to = _kind == NightSignalKind.pulse
        ? ((range.high + width) / 5).ceil() * 5.0
        : range.high + width;
    return G3Scale(
      domain: G3Domain.recovery,
      min: from,
      max: to,
      band: (range.low, range.high),
      median: range.median,
      ticks: [
        G3Tick(from, _number(from)),
        G3Tick(range.low, _number(range.low), strong: true),
        G3Tick(range.high, _number(range.high), strong: true),
        G3Tick(to, '${_number(to)} $_unit'),
      ],
    );
  }
}
