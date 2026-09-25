// The Heute vital tiles read their 7-night history per day RESULT, not only
// per selected day: after a sync or a re-derivation the history changes under
// the same day, and a once-read list kept its gaps until the day changed.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/screens.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

class _CountingRepository extends SyntheticOpenBandRepository {
  _CountingRepository(super.summary, super.detail) : super.fromMaps();
  int hrvReads = 0;

  @override
  Future<List<MetricPoint>> readMetricHistory(
    MetricKey key,
    String endDay,
    int nights,
  ) {
    if (key == MetricKey.hrv) hrvReads++;
    return super.readMetricHistory(key, endDay, nights);
  }
}

Map _json(String name) =>
    jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync())
        as Map;

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('a new day result re-reads the history', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 1400);
    addTearDown(tester.view.reset);
    final repo = _CountingRepository(
      _json('day-summary.json'),
      _json('sleep-detail.json'),
    );
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: OpenBandOverview(controller: controller, onSync: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = repo.hrvReads;
    expect(first, greaterThan(0));

    // Same selected day, fresh result (what a finished re-derive delivers).
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(repo.hrvReads, greaterThan(first));

    // A rebuild without a new result does not read again.
    final settled = repo.hrvReads;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: OpenBandOverview(controller: controller, onSync: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.hrvReads, settled);
  });
}
