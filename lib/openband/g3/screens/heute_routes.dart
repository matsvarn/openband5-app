// Route targets Heute opens.
import 'package:flutter/material.dart';

import '../../../ui2/app_shell.dart' show pushInTab;
import '../../controller.dart';
import '../../domain.dart';
import 'training_screen.dart';
import 'verlauf.dart';

Future<void> openHeuteActivity(
  BuildContext context,
  OpenBandController controller,
  G3Activity activity,
) => pushInTab<void>(
  context,
  g3ActivityResultRoute(
    repository: controller.repository,
    activity: activity,
    onChanged: controller.refresh,
  ),
);

/// Opens the detail for a Heute value.
Future<void> openHeuteMetric(
  BuildContext context,
  OpenBandController controller,
  G3Metric metric,
) async {
  if (metric != G3Metric.strain) {
    await openG3MetricDetail(
      context,
      metric,
      repository: controller.repository,
      endDay: controller.selectedDay,
      band: controller.band,
    );
    return;
  }

  final day = controller.selectedDay;
  final repo = controller.repository;
  try {
    final weekly = await repo.readWeeklyLoad(day);
    final activities = [...await repo.readActivities(day)]
      ..sort((a, b) => b.start.compareTo(a.start));
    if (!context.mounted || controller.selectedDay != day) return;
    await pushInTab<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => G3LoadScreen(
          controller: controller,
          activity: activities.firstOrNull,
          weekly: weekly,
        ),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Belastung konnte nicht geladen werden.')),
      );
    }
  }
}
