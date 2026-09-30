// Route targets Heute opens. The metric detail is the existing
// OpenBandMetricDetail until the G3 Verlauf screens land.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../controller.dart';
import '../../domain.dart';
import '../../metric_detail.dart';

/// Opens the detail for a Heute value. Steps and sleep have their own
/// destinations and are not handled here.
// ponytail: G2 detail screen as the target until Verlauf ships its G3 detail;
// swap the push here, callers stay.
void openHeuteMetric(
  BuildContext context,
  OpenBandController controller,
  G3Metric metric,
) {
  final spec = switch (metric) {
    G3Metric.recovery => (
      MetricKey.recovery,
      'Erholung',
      'aus der Nacht',
      'von 100',
      LucideIcons.heartPulse,
      0,
    ),
    G3Metric.hrv => (
      MetricKey.hrv,
      'HRV',
      'Herzratenvariabilität',
      'ms',
      LucideIcons.activity,
      0,
    ),
    G3Metric.rhr => (
      MetricKey.restingHr,
      'Ruhepuls',
      'in der Nacht',
      '/min',
      LucideIcons.heart,
      0,
    ),
    G3Metric.respRate => (
      MetricKey.respiration,
      'Atmung',
      'Atemfrequenz',
      '/min',
      LucideIcons.wind,
      1,
    ),
    // Relative to the personal basis: no unit, never °C.
    G3Metric.skinTempZ => (
      MetricKey.skinTemperature,
      'Hauttemperatur',
      'Abweichung von deiner Basis',
      '',
      LucideIcons.thermometer,
      1,
    ),
    G3Metric.strain => (
      MetricKey.strain,
      'Belastung',
      'heute bis jetzt',
      'von 21',
      LucideIcons.flame,
      1,
    ),
    G3Metric.sleepMinutes || G3Metric.steps => null,
  };
  if (spec == null) return;
  final (key, label, subtitle, unit, icon, digits) = spec;
  OpenBandMetricDetail.push(
    context,
    backText: 'Heute',
    controller: controller,
    metricKey: key,
    label: label,
    subtitle: subtitle,
    unit: unit,
    icon: icon,
    digits: digits,
    color: (p) => p.ink,
    tint: (p) => p.line,
  );
}
