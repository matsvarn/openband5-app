import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'domain.dart';
import 'health.dart' show OBSegmented;
import 'theme.dart';
import 'time.dart';

extension on NightSignalKind {
  String get label => switch (this) {
    NightSignalKind.pulse => 'Puls',
    NightSignalKind.hrv => 'HRV',
    NightSignalKind.respiration => 'Atmung',
  };
  String get unit => switch (this) {
    NightSignalKind.pulse => 'bpm',
    NightSignalKind.hrv => 'ms',
    NightSignalKind.respiration => '/min',
  };
  int get digits => this == NightSignalKind.respiration ? 1 : 0;
  Color color(OB p) => switch (this) {
    NightSignalKind.pulse => p.pulse,
    NightSignalKind.hrv => p.ink,
    NightSignalKind.respiration => p.sleep,
  };
}

class OpenBandNightSignals extends StatefulWidget {
  final OpenBandRepository repository;
  final String day;
  final NightSignalKind initial;
  const OpenBandNightSignals({
    super.key,
    required this.repository,
    required this.day,
    this.initial = NightSignalKind.pulse,
  });
  @override
  State<OpenBandNightSignals> createState() => _OpenBandNightSignalsState();
}

class _OpenBandNightSignalsState extends State<OpenBandNightSignals> {
  late NightSignalKind _kind = widget.initial;
  late Future<NightSignals> _data = widget.repository.readNightSignals(
    widget.day,
  );

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: FutureBuilder<NightSignals>(
          future: _data,
          builder: (context, snapshot) {
            final night = snapshot.data;
            final start = night?.window?.start;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                IconButtonTheme(
                  data: IconButtonThemeData(
                    style: IconButton.styleFrom(
                      backgroundColor: p.card,
                      foregroundColor: p.ink,
                      minimumSize: const Size(44, 44),
                      shape: const CircleBorder(),
                    ),
                  ),
                  child: OBPageHeader(
                    title: 'Nachtverlauf',
                    subtitle:
                        '${start == null ? '' : '${recordedTime(start, night?.recordingTimezone).day}./'}${obDate(widget.day)}',
                    infoLabel: 'Nachtverlauf: Quelle und Darstellung',
                    onInfo: night == null ? null : () => _info(night),
                  ),
                ),
                if (snapshot.hasError)
                  OBAction(
                    'Erneut laden',
                    onPressed: () => setState(() {
                      _data = widget.repository.readNightSignals(widget.day);
                    }),
                  )
                else if (night == null)
                  const Center(child: CircularProgressIndicator.adaptive())
                else ...[
                  OBSegmented(
                    labels: [
                      for (final kind in NightSignalKind.values) kind.label,
                    ],
                    selected: _kind.index,
                    onChanged: (i) =>
                        setState(() => _kind = NightSignalKind.values[i]),
                  ),
                  const SizedBox(height: 12),
                  OBNightSignalChart(
                    key: ValueKey(_kind),
                    night: night,
                    kind: _kind,
                  ),
                  if (night.synthetic) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Synthetische Daten',
                      style: p.text(12, color: p.muted),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  void _info(NightSignals night) {
    final series = night.signal(_kind);
    final known = series.readings.where((r) => r.value != null).length;
    final gaps = series.readings.length - known;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OB.of(context).card,
      builder: (context) {
        final p = OB.of(context);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Text(
                  '${_kind.label} · Nachtverlauf',
                  style: p.text(22, weight: FontWeight.w700),
                ),
                Text(
                  '$known Messpunkte · $gaps fehlende Werte',
                  style: p.text(14),
                ),
                Text(
                  _kind == NightSignalKind.hrv
                      ? 'Gespeicherte HRV-Abschnitte mit ihrem Unsicherheitsbereich. Die Zeit bezeichnet den Beginn des Abschnitts.'
                      : 'Gespeicherte Werte aus den Tagesauswertungen dieser Nacht.',
                  style: p.text(14),
                ),
                Text('Lücken bleiben offen.', style: p.text(14)),
                Text(
                  night.recordingTimezone == null
                      ? 'Zeiten in der Zeitzone dieses Telefons.'
                      : 'Zeiten: ${night.recordingTimezone}',
                  style: p.text(14, color: p.muted),
                ),
                OBAction('Schließen', onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class OBNightSignalChart extends StatefulWidget {
  final NightSignals night;
  final NightSignalKind kind;
  const OBNightSignalChart({
    super.key,
    required this.night,
    required this.kind,
  });
  @override
  State<OBNightSignalChart> createState() => _OBNightSignalChartState();
}

class _OBNightSignalChartState extends State<OBNightSignalChart> {
  int _selected = 0;
  @override
  void didUpdateWidget(OBNightSignalChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.night != widget.night || oldWidget.kind != widget.kind) {
      _selected = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final kind = widget.kind;
    final series = widget.night.signal(kind);
    final points = series.readings;
    final reading = points.isEmpty ? null : points[_selected];
    final window = widget.night.window;
    String time(DateTime? at) => at == null
        ? '—'
        : obTime(recordedTime(at, widget.night.recordingTimezone));
    final label = reading == null
        ? (widget.night.processing
              ? 'Wird neu berechnet'
              : 'Keine ${kind.label}-Werte')
        : time(reading.at);
    void select(int i) => setState(() => _selected = i);
    final value = obNumber(reading?.value, digits: kind.digits);
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Voriger Messpunkt',
          onPressed: _selected > 0 ? () => select(_selected - 1) : null,
          icon: Icon(
            LucideIcons.chevronLeft,
            color: _selected > 0 ? p.ink : p.line,
            size: 20,
          ),
        ),
        IconButton(
          tooltip: 'Nächster Messpunkt',
          onPressed: _selected + 1 < points.length
              ? () => select(_selected + 1)
              : null,
          icon: Icon(
            LucideIcons.chevronRight,
            color: _selected + 1 < points.length ? p.ink : p.line,
            size: 20,
          ),
        ),
      ],
    );
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label:
                      '${kind.label}, $value ${kind.unit}, $label${reading?.value == null ? ', Keine Daten' : ''}',
                  child: ExcludeSemantics(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 6,
                      children: [
                        Text(
                          value,
                          style: p.text(
                            44,
                            weight: FontWeight.w800,
                            display: true,
                          ),
                        ),
                        Text(kind.unit, style: p.text(14, color: p.muted)),
                      ],
                    ),
                  ),
                ),
              ),
              if (points.isNotEmpty) controls,
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(label, style: p.text(13, color: p.muted)),
              ),
              if (points.isNotEmpty && series.partial)
                Text('Teilweise', style: p.text(12, color: p.muted)),
            ],
          ),
          Container(
            padding: EdgeInsets.zero,
            child: Column(
              spacing: 4,
              children: [
                if (window == null || points.isEmpty)
                  SizedBox(
                    height: 200,
                    child: Center(
                      child: Text('—', style: p.text(34, color: p.muted)),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final plot = OBNightSignalPlot(
                        p: p,
                        kind: kind,
                        points: points,
                        maxConnectingGap: series.maxConnectingGap,
                        start: window.start,
                        end: window.end,
                        selected: _selected,
                        textScaler: MediaQuery.textScalerOf(context),
                      );
                      return Semantics(
                        label:
                            '${kind.label}, ${points.length} gespeicherte Zeitpunkte. Messpunkte mit den Pfeiltasten auswählen.',
                        child: GestureDetector(
                          onTapDown: (d) => select(
                            plot.nearest(
                              d.localPosition.dx,
                              constraints.maxWidth,
                            ),
                          ),
                          onHorizontalDragUpdate: (d) => select(
                            plot.nearest(
                              d.localPosition.dx,
                              constraints.maxWidth,
                            ),
                          ),
                          child: RepaintBoundary(
                            child: CustomPaint(
                              size: Size(constraints.maxWidth, 200),
                              painter: plot,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      time(window?.start),
                      style: p.text(12, color: p.muted),
                    ),
                    Text(time(window?.end), style: p.text(12, color: p.muted)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OBNightSignalPlot extends CustomPainter {
  final OB p;
  final NightSignalKind kind;
  final List<NightSignalReading> points;
  final DateTime start, end;
  final int selected;
  final Duration? maxConnectingGap;
  final TextScaler textScaler;
  OBNightSignalPlot({
    required this.p,
    required this.kind,
    required this.points,
    required this.start,
    required this.end,
    required this.selected,
    required this.textScaler,
    this.maxConnectingGap,
  });

  double get left => textScaler.scale(kind.digits == 1 ? 36 : 30);
  double x(DateTime at, double width) =>
      left +
      at.difference(start).inMilliseconds /
          end.difference(start).inMilliseconds *
          (width - left);
  int nearest(double dx, double width) {
    var best = 0;
    for (var i = 1; i < points.length; i++) {
      if ((x(points[i].at, width) - dx).abs() <
          (x(points[best].at, width) - dx).abs()) {
        best = i;
      }
    }
    return best;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final values = [
      for (final point in points)
        if (point.value != null) ...[
          point.bounds?.lower ?? point.value!,
          point.bounds?.upper ?? point.value!,
        ],
    ];
    if (values.isEmpty) return;
    final low = values.reduce(math.min), high = values.reduce(math.max);
    double y(double v) =>
        low == high ? 98 : 170 - (v - low) / (high - low) * 144;
    void tick(double value, double top) {
      final tp = TextPainter(
        text: TextSpan(
          text: obNumber(value, digits: kind.digits),
          style: p.text(12, color: p.muted),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      tp.paint(canvas, Offset(0, top - tp.height / 2));
      canvas.drawLine(
        Offset(left, top),
        Offset(size.width, top),
        Paint()..color = p.line.withValues(alpha: .55),
      );
    }

    if (low == high) {
      tick(low, 98);
    } else {
      tick(high, 26);
      tick(low, 170);
    }
    final color = kind.color(p);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    bool joins(int i, int j) =>
        i >= 0 &&
        j < points.length &&
        points[i].value != null &&
        points[j].value != null &&
        maxConnectingGap != null &&
        points[j].at.difference(points[i].at) <= maxConnectingGap!;
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      if (point.value == null) continue;
      final here = Offset(x(point.at, size.width), y(point.value!));
      final bound = point.bounds;
      if (joins(i - 1, i)) {
        final previous = points[i - 1];
        final before = Offset(x(previous.at, size.width), y(previous.value!));
        final previousBound = previous.bounds;
        if (bound != null && previousBound != null) {
          final band = Path()
            ..moveTo(before.dx, y(previousBound.lower))
            ..lineTo(here.dx, y(bound.lower))
            ..lineTo(here.dx, y(bound.upper))
            ..lineTo(before.dx, y(previousBound.upper))
            ..close();
          canvas.drawPath(band, Paint()..color = color.withValues(alpha: .18));
        }
        canvas.drawLine(before, here, stroke);
      }
      if (!joins(i - 1, i) && !joins(i, i + 1)) {
        if (bound != null) {
          canvas.drawLine(
            Offset(here.dx, y(bound.lower)),
            Offset(here.dx, y(bound.upper)),
            Paint()
              ..color = color.withValues(alpha: .3)
              ..strokeWidth = 5
              ..strokeCap = StrokeCap.round,
          );
        }
        canvas.drawCircle(here, 2.5, Paint()..color = color);
      }
      if (i == selected) {
        canvas.drawCircle(here, 6, Paint()..color = p.card);
        canvas.drawCircle(here, 4, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(OBNightSignalPlot old) =>
      old.points != points ||
      old.selected != selected ||
      old.kind != kind ||
      old.p.dark != p.dark ||
      old.start != start ||
      old.end != end ||
      old.maxConnectingGap != maxConnectingGap ||
      old.textScaler != textScaler;
}
