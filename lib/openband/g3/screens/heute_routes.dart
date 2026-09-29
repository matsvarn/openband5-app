// Route targets Heute opens.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../controller.dart';
import '../../domain.dart';
import '../../metric_detail.dart';
import 'verlauf.dart';

/// Opens the detail for a Heute value.
void openHeuteMetric(
  BuildContext context,
  OpenBandController controller,
  G3Metric metric,
) {
  if (metric != G3Metric.strain) {
    openG3MetricDetail(
      context,
      metric,
      repository: controller.repository,
      endDay: controller.selectedDay,
      band: controller.band,
    );
    return;
  }

  // Training owns the Belastung detail; retain its current route until then.
  OpenBandMetricDetail.push(
    context,
    backText: 'Heute',
    controller: controller,
    metricKey: MetricKey.strain,
    label: 'Belastung',
    subtitle: 'heute bis jetzt',
    unit: 'von 21',
    icon: LucideIcons.flame,
    digits: 1,
    color: (p) => p.ink,
    tint: (p) => p.line,
  );
}
