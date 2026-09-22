import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/daily_activity.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/nutrition_route.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/state/app_state.dart';

class _TrackedController extends OpenBandController {
  _TrackedController({required super.repository, super.initialDay});
  int disposeCalls = 0;
  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

SyntheticOpenBandRepository _repo() => SyntheticOpenBandRepository.fromMaps(
  jsonDecode(
        File(
          'docs/openband5/assets/fixtures/day-summary.json',
        ).readAsStringSync(),
      )
      as Map,
  jsonDecode(
        File(
          'docs/openband5/assets/fixtures/sleep-detail.json',
        ).readAsStringSync(),
      )
      as Map,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  testWidgets('a borrowed controller is never disposed by the route', (
    t,
  ) async {
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final controller = _TrackedController(
      repository: _repo(),
      initialDay: '2026-09-15',
    );

    await t.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: openBandTheme(Brightness.light),
          home: OpenBandNutritionRoute(controller: controller),
        ),
      ),
    );
    await t.pump();
    expect(controller.disposeCalls, 0);

    await t.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    await t.pump();
    expect(controller.disposeCalls, 0);
    controller.dispose();
  });

  testWidgets('changing borrowed controllers does not retire either one', (
    t,
  ) async {
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final first = _TrackedController(
      repository: _repo(),
      initialDay: '2026-09-14',
    );
    final second = _TrackedController(
      repository: _repo(),
      initialDay: '2026-09-15',
    );

    Widget host(OpenBandController controller) =>
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            theme: openBandTheme(Brightness.light),
            home: OpenBandNutritionRoute(controller: controller),
          ),
        );

    await t.pumpWidget(host(first));
    await t.pumpWidget(host(second));
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();

    expect(first.disposeCalls, 0);
    expect(second.disposeCalls, 0);
    first.dispose();
    second.dispose();
  });

  testWidgets('historical activity offers the nutrition route action', (
    t,
  ) async {
    var opened = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: openBandTheme(Brightness.light),
        home: Scaffold(
          body: StepsCard(
            day: const OpenBandDay(
              day: '2026-09-14',
              intake: DayIntake(kcal: 420, waterMl: 750, kcalIsFloor: true),
            ),
            now: DateTime.now,
            onNutrition: () => opened++,
          ),
        ),
      ),
    );

    await t.tap(find.text('Wasser'));
    await t.pumpAndSettle();
    expect(find.text('Teilweise'), findsOneWidget);
    expect(find.text('Ernährung öffnen'), findsOneWidget);

    await t.tap(find.text('Ernährung öffnen'));
    await t.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets(
    'gallery host does not require AppState for a borrowed controller',
    (t) async {
      final controller = OpenBandController(
        repository: _repo(),
        initialDay: '2026-09-15',
      );
      addTearDown(controller.dispose);

      await t.pumpWidget(
        MaterialApp(
          theme: openBandTheme(Brightness.light),
          home: OpenBandNutritionRoute(controller: controller),
        ),
      );
      await t.pump();
      expect(find.byType(OpenBandNutritionRoute), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
