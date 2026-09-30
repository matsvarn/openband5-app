import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain.dart';
import '../../time.dart';
import '../chrome.dart' as chrome;
import '../count_copy.dart';
import '../g3_theme.dart';
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
  });
  final OpenBandRepository repository;
  final String day;
  @override
  State<G3SleepNightSignals> createState() => _G3SleepNightSignalsState();
}

class _G3SleepNightSignalsState extends State<G3SleepNightSignals> {
  NightSignalKind _kind = NightSignalKind.pulse;
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 112),
          children: [
            chrome.OBPageHeader.detail(
              title: 'NACHTVERLAUF',
              subtitle:
                  'Nacht zu ${DateFormat('EE dd.MM', 'de_DE').format(DateTime.parse(widget.day)).replaceFirst('.', '')}',
              backLabel: 'Schlaf',
              onBack: () => Navigator.of(context).pop(),
              onTrailing: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Nachtverlauf'),
                  content: const Text(
                    'Gespeicherte Signale während der erkannten Nacht. Lücken bleiben leer; einzelne Werte werden nicht verbunden.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Schließen'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            chrome.OBSegmented(
              items: const ['Puls', 'HRV', 'Atmung'],
              selected: _kind.index,
              onChanged: _select,
              expand: true,
            ),
            const SizedBox(height: 14),
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

                  return chrome.OBPanel(
                    hero: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(switch (_kind) {
                              NightSignalKind.pulse => 'RUHEPULS',
                              NightSignalKind.hrv => 'HRV',
                              NightSignalKind.respiration => 'ATMUNG',
                            }, style: g.caps()),
                            const Spacer(),
                            Text(status(), style: g.t(12, 16, color: g.muted)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          metric?.value == null
                              ? '—'
                              : metric!.value!
                                    .toStringAsFixed(
                                      _kind == NightSignalKind.respiration
                                          ? 1
                                          : 0,
                                    )
                                    .replaceAll('.', ','),
                          style: g.t(72, 76, weight: FontWeight.w700),
                        ),
                        if (basis?.status.phase == BaselinePhase.trusted &&
                            basis?.range != null &&
                            metric?.value != null) ...[
                          Text(
                            'Normal ${basis!.range!.low.toStringAsFixed(_kind == NightSignalKind.respiration ? 1 : 0).replaceAll('.', ',')}–${basis.range!.high.toStringAsFixed(_kind == NightSignalKind.respiration ? 1 : 0).replaceAll('.', ',')}',
                            style: g.t(13, 17, color: g.ink2),
                          ),
                          const SizedBox(height: 14),
                          _trustedScale(g, basis.range!, metric!.value!),
                        ],
                      ],
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
                    series?.readings.where((r) => r.value != null).toList() ??
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
                      Row(
                        children: [
                          Text(
                            '${switch (_kind) {
                              NightSignalKind.pulse => 'PULS',
                              NightSignalKind.hrv => 'HRV',
                              NightSignalKind.respiration => 'ATMUNG',
                            }} · NACHT',
                            style: g.caps(),
                          ),
                          const Spacer(),
                          Text(
                            recorded.isEmpty
                                ? 'keine Daten'
                                : series != null &&
                                      window != null &&
                                      nightSignalHasUncoveredInterval(
                                        series,
                                        window,
                                      )
                                ? 'teilweise'
                                : 'gespeichert',
                            style: g.t(12, 16, color: g.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        lowest == null
                            ? '—'
                            : 'Tiefster Wert ${lowest.value!.toStringAsFixed(_kind == NightSignalKind.respiration ? 1 : 0).replaceAll('.', ',')} um ${obSleepClock(recordedTime(lowest.at, night?.recordingTimezone))}',
                        style: g.t(17, 22, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 18),
                      if (window != null &&
                          series != null &&
                          recorded.isNotEmpty)
                        OBNightTrace(
                          series: series,
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
                      const SizedBox(height: 14),
                      Divider(height: 1, color: g.line),
                      const SizedBox(height: 12),
                      Text(
                        'Signallücken bleiben leer. Nichts wird aufgefüllt.',
                        style: g.t(13, 17, color: g.ink2),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _trustedScale(G3 g, PersonalRange range, double value) {
    final width = range.high - range.low;
    if (width <= 0) return const SizedBox.shrink();
    final from = range.low - width;
    final to = range.high + width;
    final x = ((value - from) / (to - from)).clamp(0.0, 1.0);
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, box) => SizedBox(
            height: 25,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 8,
                  child: Container(height: 9, decoration: g.pressed(radius: 5)),
                ),
                Positioned(
                  left: box.maxWidth / 3,
                  width: box.maxWidth / 3,
                  top: 8,
                  child: Container(height: 9, color: g.bar),
                ),
                Positioned(
                  left: x * (box.maxWidth - 3),
                  child: Container(width: 3, height: 25, color: g.ink),
                ),
              ],
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final label in [from, range.low, range.high, to])
              Text(
                label
                    .toStringAsFixed(
                      _kind == NightSignalKind.respiration ? 1 : 0,
                    )
                    .replaceAll('.', ','),
                style: g.t(11, 15, color: g.muted),
              ),
          ],
        ),
      ],
    );
  }
}
