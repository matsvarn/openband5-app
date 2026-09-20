import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/nutrition.dart';
import 'package:openstrap_edge/openband/nutrition_goals.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

class _CallerRepo extends SyntheticOpenBandRepository {
  _CallerRepo(super.summary, super.detail) : super.fromMaps();

  final targetGates = <String, Completer<void>>{};
  final targetReads = <String>[];
  int targetWrites = 0;
  bool failMeals = false;

  Completer<void> gateTargets(String day) =>
      targetGates.putIfAbsent(day, Completer<void>.new);

  @override
  Future<DayMeals> readMeals(String day) async {
    if (failMeals) throw StateError('synthetic meal read failure');
    return super.readMeals(day);
  }

  @override
  Future<NutritionTargetSnapshot> readNutritionTargets(String day) async {
    targetReads.add(day);
    final gate = targetGates[day];
    if (gate != null) await gate.future;
    return super.readNutritionTargets(day);
  }

  @override
  Future<NutritionTargetWriteResult> saveNutritionTargets(
    String day,
    NutritionTargetValues values, {
    int? expectedRevision,
  }) async {
    targetWrites++;
    return super.saveNutritionTargets(
      day,
      values,
      expectedRevision: expectedRevision,
    );
  }

  @override
  Future<NutritionTargetWriteResult> clearNutritionTargets(
    String day, {
    int? expectedRevision,
  }) async {
    targetWrites++;
    return super.clearNutritionTargets(day, expectedRevision: expectedRevision);
  }
}

_CallerRepo _galleryRepo() => _CallerRepo(
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

  late _CallerRepo repo;
  late OpenBandController controller;

  setUp(() {
    repo = _galleryRepo();
    controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
  });
  tearDown(() {
    for (final gate in repo.targetGates.values) {
      if (!gate.isCompleted) gate.complete();
    }
    controller.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    FutureOr<void> Function(String meal)? onAdd,
    int revision = 0,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(Brightness.light).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: OpenBandNutrition(
          controller: controller,
          onAdd: onAdd,
          revision: revision,
        ),
      ),
    );
  }

  testWidgets('saved dated target shows snapshot values', (tester) async {
    await repo.seedNutritionGoals(withFuture: false);
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('Haferflocken mit Milch'), findsOneWidget);
    expect(find.text('Kein Ziel'), findsNothing);
    expect(find.text('Ziel 2.000'), findsOneWidget);
    expect(find.text('26 / 125 g'), findsOneWidget);
    expect(find.text('15 / 60 g'), findsOneWidget);
    expect(find.text('88 / 240 g'), findsOneWidget);
  });

  testWidgets('absent energy and zero protein stay distinct', (tester) async {
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('Kein Ziel'), findsOneWidget);
    expect(find.text('Ziel —'), findsNothing);
    expect(find.text('26 g'), findsOneWidget);
    expect(find.text('26 / 0 g'), findsNothing);

    await repo.saveNutritionTargets(
      '2026-09-15',
      const NutritionTargetValues(proteinG: 0),
    );
    await tester.tap(find.byTooltip('Ernährungsziele'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Kein Ziel'), findsOneWidget);
    expect(find.text('26 / 0 g'), findsOneWidget);
    expect(find.text('26 g'), findsNothing);
    expect(find.text('Ziel —'), findsNothing);
  });

  testWidgets('target read failure keeps meals and retry only rereads', (
    tester,
  ) async {
    await repo.seedNutritionGoals(withFuture: false);
    repo.failNutritionTargetRead = true;
    final writes = repo.targetWrites;
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('Haferflocken mit Milch'), findsOneWidget);
    expect(find.text('620'), findsOneWidget);
    expect(find.text('Noch nichts erfasst'), findsNothing);
    expect(find.textContaining('Teilweise'), findsOneWidget);
    expect(find.text('Kein Ziel'), findsNothing);
    expect(find.text('Ziel 2.000'), findsNothing);
    expect(find.text('Ziel —'), findsOneWidget);
    expect(find.text('Erneut'), findsOneWidget);
    expect(find.text('Einträge konnten nicht geladen werden.'), findsNothing);
    expect(repo.targetWrites, writes);

    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Haferflocken mit Milch'), findsOneWidget);
    expect(find.text('Ziel —'), findsOneWidget);
    expect(repo.targetWrites, writes);

    repo.failNutritionTargetRead = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Ziel 2.000'), findsOneWidget);
    expect(find.text('26 / 125 g'), findsOneWidget);
    expect(find.text('Erneut'), findsNothing);
    expect(repo.targetWrites, writes);
  });

  testWidgets('meal read failure stays distinct from target failure', (
    tester,
  ) async {
    await repo.seedNutritionGoals(withFuture: false);
    repo.failMeals = true;
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('Einträge konnten nicht geladen werden.'), findsOneWidget);
    expect(find.text('Haferflocken mit Milch'), findsNothing);
    expect(find.text('Kein Ziel'), findsNothing);
    expect(find.text('Ziel —'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Erneut'), findsOneWidget);
  });

  testWidgets('late prior-day target read cannot replace the selected day', (
    tester,
  ) async {
    await repo.saveNutritionTargets(
      '2026-09-15',
      const NutritionTargetValues(energyKcal: 2000, proteinG: 125),
    );
    await repo.saveNutritionTargets(
      '2026-09-14',
      const NutritionTargetValues(energyKcal: 1800, proteinG: 90),
    );
    repo.gateTargets('2026-09-15');
    await mount(tester);
    await tester.pump();
    await tester.pump();
    expect(find.text('Haferflocken mit Milch'), findsOneWidget);
    expect(find.text('Kein Ziel'), findsNothing);
    expect(find.text('Ziel 2.000'), findsNothing);
    expect(find.text('Ziel —'), findsNothing);

    await tester.runAsync(() => controller.selectDay('2026-09-14'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Ziel 1.800'), findsOneWidget);
    expect(find.text('Ziel 2.000'), findsNothing);

    repo.gateTargets('2026-09-15').complete();
    await tester.pump();
    await tester.pump();
    expect(controller.selectedDay, '2026-09-14');
    expect(find.text('Ziel 1.800'), findsOneWidget);
    expect(find.text('Ziel 2.000'), findsNothing);
    expect(find.text('Kein Ziel'), findsNothing);
  });

  testWidgets('return from goals rereads the captured day behind a barrier', (
    tester,
  ) async {
    await repo.seedNutritionGoals(withFuture: false);
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('Ziel 2.000'), findsOneWidget);

    await tester.tap(find.byTooltip('Ernährungsziele'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandNutritionGoals), findsOneWidget);
    await repo.saveNutritionTargets(
      '2026-09-15',
      const NutritionTargetValues(energyKcal: 1800, proteinG: 110),
      expectedRevision: 1,
    );
    repo.targetGates.remove('2026-09-15');
    final held = repo.gateTargets('2026-09-15');
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(OpenBandNutrition), findsOneWidget);
    expect(find.text('Ziel 2.000'), findsOneWidget);
    expect(find.text('Kein Ziel'), findsNothing);
    expect(find.text('Ziel 1.800'), findsNothing);

    held.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Ziel 1.800'), findsOneWidget);
    expect(find.text('26 / 110 g'), findsOneWidget);
    expect(find.text('Ziel 2.000'), findsNothing);
  });

  testWidgets('return after a day change does not apply the prior-day reread', (
    tester,
  ) async {
    await repo.saveNutritionTargets(
      '2026-09-15',
      const NutritionTargetValues(energyKcal: 2000, proteinG: 125),
    );
    await repo.saveNutritionTargets(
      '2026-09-14',
      const NutritionTargetValues(energyKcal: 1600, proteinG: 80),
    );
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ernährungsziele'));
    await tester.pumpAndSettle();

    repo.targetGates.remove('2026-09-15');
    final stale = repo.gateTargets('2026-09-15');
    await tester.runAsync(() => controller.selectDay('2026-09-14'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Ziel 1.600'), findsOneWidget);
    expect(find.text('Ziel 2.000'), findsNothing);

    await repo.saveNutritionTargets(
      '2026-09-15',
      const NutritionTargetValues(energyKcal: 2100, proteinG: 130),
      expectedRevision: 1,
    );
    stale.complete();
    await tester.pump();
    await tester.pump();
    expect(controller.selectedDay, '2026-09-14');
    expect(find.text('Ziel 1.600'), findsOneWidget);
    expect(find.text('Ziel 2.100'), findsNothing);
    expect(find.text('Ziel 2.000'), findsNothing);
  });

  testWidgets('awaited onAdd reloads same-day meals', (tester) async {
    await mount(
      tester,
      onAdd: (meal) async {
        final draft = MealDraft(
          id: 'd-dinner',
          day: '2026-09-15',
          meal: meal,
          entries: const [
            MealDraftEntry(id: 'e-rice', label: 'Reis', kcal: 300, carbsG: 65),
          ],
          updatedAt: DateTime(2026, 9, 15, 19),
        );
        await repo.saveMealDraft(draft);
        await repo.commitMealDraft(draft);
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Reis'), findsNothing);
    final dinnerAdd = find.byTooltip('Abend ergänzen');
    await tester.scrollUntilVisible(
      dinnerAdd,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final list = find.byType(ListView).first;
    final item = tester.getRect(dinnerAdd);
    final view = tester.getRect(list);
    if (item.bottom > view.bottom - 24) {
      await tester.drag(list, Offset(0, view.bottom - 24 - item.bottom));
      await tester.pumpAndSettle();
    }
    await tester.tap(dinnerAdd);
    await tester.pumpAndSettle();
    expect(find.text('Reis'), findsOneWidget);
    expect(find.text('300 kcal'), findsWidgets);
  });

  testWidgets('same-day revision rereads targets without a controller notify', (
    tester,
  ) async {
    await repo.seedNutritionGoals(withFuture: false);
    var revision = 0;
    late StateSetter setHost;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: StatefulBuilder(
          builder: (context, setState) {
            setHost = setState;
            return OpenBandNutrition(
              controller: controller,
              revision: revision,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ziel 2.000'), findsOneWidget);
    final reads = repo.targetReads.length;
    controller.updateBand(controller.band);
    await tester.pump();
    expect(repo.targetReads.length, reads);

    await repo.saveNutritionTargets(
      '2026-09-15',
      const NutritionTargetValues(energyKcal: 1800, proteinG: 110),
      expectedRevision: 1,
    );
    setHost(() => revision += 1);
    await tester.pumpAndSettle();
    expect(find.text('Ziel 1.800'), findsOneWidget);
    expect(find.text('26 / 110 g'), findsOneWidget);
    expect(find.text('Ziel 2.000'), findsNothing);
    expect(repo.targetReads.length, greaterThan(reads));
  });
}
