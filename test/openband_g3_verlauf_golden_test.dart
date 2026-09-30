import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/screens/verlauf.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

class _PaperRecoveryRepository extends SyntheticOpenBandRepository {
  _PaperRecoveryRepository(super.summary, super.detail)
    : super.fromMaps(scenario: SyntheticScenario.g3Sample);

  @override
  Future<G3Baseline> readPersonalRange(G3Metric metric, String day) async =>
      metric == G3Metric.recovery
      ? const G3Baseline(
          BaselineStatus(BaselinePhase.trusted),
          range: PersonalRange(58, 80, 68),
        )
      : super.readPersonalRange(metric, day);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });
  testWidgets('G3 recovery detail', (tester) async {
    Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(
      jsonDecode(
            File('docs/openband5/assets/fixtures/$name').readAsStringSync(),
          )
          as Map,
    );
    final repo = _PaperRecoveryRepository(
      fixture('day-summary.json'),
      fixture('sleep-detail.json'),
    );
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: G3MetricDetail(
          metric: G3Metric.recovery,
          repository: repo,
          endDay: '2026-09-29',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(G3MetricDetail),
      matchesGoldenFile('openband_goldens/g3-verlauf-recovery.png'),
    );
  }, tags: const ['golden']);

  testWidgets('G3 HRV detail at 375 pt', (tester) async {
    Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(
      jsonDecode(
            File('docs/openband5/assets/fixtures/$name').readAsStringSync(),
          )
          as Map,
    );
    final repo = SyntheticOpenBandRepository.fromMaps(
      fixture('day-summary.json'),
      fixture('sleep-detail.json'),
      scenario: SyntheticScenario.g3Sample,
    );
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: G3MetricDetail(
          metric: G3Metric.hrv,
          repository: repo,
          endDay: '2026-09-29',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(G3MetricDetail),
      matchesGoldenFile('openband_goldens/g3-verlauf-hrv-375.png'),
    );
  }, tags: const ['golden']);

  testWidgets('G3 recovery detail dark', (tester) async {
    Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(
      jsonDecode(
            File('docs/openband5/assets/fixtures/$name').readAsStringSync(),
          )
          as Map,
    );
    final repo = _PaperRecoveryRepository(
      fixture('day-summary.json'),
      fixture('sleep-detail.json'),
    );
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.dark),
        home: G3MetricDetail(
          metric: G3Metric.recovery,
          repository: repo,
          endDay: '2026-09-29',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(G3MetricDetail),
      matchesGoldenFile('openband_goldens/g3-verlauf-recovery-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('G3 HRV detail dark at 375 pt', (tester) async {
    Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(
      jsonDecode(
            File('docs/openband5/assets/fixtures/$name').readAsStringSync(),
          )
          as Map,
    );
    final repo = SyntheticOpenBandRepository.fromMaps(
      fixture('day-summary.json'),
      fixture('sleep-detail.json'),
      scenario: SyntheticScenario.g3Sample,
    );
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.dark),
        home: G3MetricDetail(
          metric: G3Metric.hrv,
          repository: repo,
          endDay: '2026-09-29',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(G3MetricDetail),
      matchesGoldenFile('openband_goldens/g3-verlauf-hrv-375-dark.png'),
    );
  }, tags: const ['golden']);
}
