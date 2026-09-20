import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/meal_entry.dart';
import 'package:openstrap_edge/openband/nutrition.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

class _DraftRepo extends SyntheticOpenBandRepository {
  _DraftRepo(super.summary, super.detail) : super.fromMaps();

  int commits = 0;
  int reads = 0;
  int restores = 0;
  bool failRead = false;
  bool failDayRead = false;
  Completer<void>? readGate;
  Completer<void>? mealsGate;
  Completer<void>? restoreGate;

  @override
  Future<OpenBandDay> readDay(String day) {
    if (failDayRead) {
      return Future.error(StateError('synthetic day read failure'));
    }
    return super.readDay(day);
  }

  @override
  Future<MealDraft?> readMealDraft(String day, String meal) async {
    reads++;
    final gate = readGate;
    if (gate != null) await gate.future;
    if (failRead) throw StateError('synthetic meal draft read failure');
    return super.readMealDraft(day, meal);
  }

  @override
  Future<MealDraftCommitResult> commitMealDraft(MealDraft draft) async {
    commits++;
    return super.commitMealDraft(draft);
  }

  @override
  Future<DayMeals> readMeals(String day) async {
    final gate = mealsGate;
    if (gate != null) await gate.future;
    return super.readMeals(day);
  }

  @override
  Future<FoodSnapshotResult> restoreFoodEntry(FoodEntry snapshot) async {
    restores++;
    final gate = restoreGate;
    if (gate != null) await gate.future;
    return super.restoreFoodEntry(snapshot);
  }
}

class _RefreshThrowController extends OpenBandController {
  _RefreshThrowController({
    required super.repository,
    required super.initialDay,
    required super.band,
    required super.now,
  });
  bool throwRefresh = false;
  @override
  Future<void> refresh() async {
    await super.refresh();
    if (throwRefresh) throw StateError('synthetic refresh failure');
  }
}

_DraftRepo _galleryRepo() => _DraftRepo(
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

MealDraft draft({
  String id = 'd-dinner',
  String label = 'Reis',
  String entryId = 'e-rice',
  double kcal = 300,
}) => MealDraft(
  id: id,
  day: '2026-09-15',
  meal: 'dinner',
  entries: [MealDraftEntry(id: entryId, label: label, kcal: kcal)],
  updatedAt: DateTime(2026, 9, 15, 19),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
    ]) {
      final loader = FontLoader(family)
        ..addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        );
      await loader.load();
    }
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await icons.load();
  });

  late _DraftRepo repo;
  setUp(() => repo = _galleryRepo());

  Future<Future<bool?>> openSheet(
    WidgetTester tester,
    MealDraft shown, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    late Future<bool?> popped;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        debugShowCheckedModeBanner: false,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: padding,
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () {
                  popped = showOpenBandMealDraft(ctx, repo, shown);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return popped;
  }

  testWidgets('successful save pops true and drops the retained draft', (
    tester,
  ) async {
    final shown = draft();
    await repo.saveMealDraft(shown);
    final result = await openSheet(tester, shown);
    expect(find.byTooltip('Schließen'), findsOneWidget);
    expect(find.text('Schließen'), findsNothing);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(find.byType(OBMealDraftSheet), findsNothing);
    expect(await repo.readMealDraft('2026-09-15', 'dinner'), isNull);
    expect((await repo.readFoodEntry('e-rice')).current?.kcal, 300);
    expect(find.textContaining('bleibt erhalten'), findsNothing);
  });

  testWidgets('conflict stays open without implying saved', (tester) async {
    final shown = draft();
    await repo.saveMealDraft(shown);
    await repo.discardMealDraft(shown.id);
    final result = await openSheet(tester, shown);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.byType(OBMealDraftSheet), findsOneWidget);
    expect(find.text('Entwurf nicht gespeichert'), findsOneWidget);
    expect(find.text('Speichern'), findsNothing);
    expect(find.text('Entwurf behalten'), findsNothing);
    expect(find.textContaining('bleibt erhalten'), findsNothing);
    expect(find.textContaining('Dein Eintrag'), findsNothing);
    expect((await repo.readFoodEntry('e-rice')).missing, isTrue);
    expect(await repo.readMealDraft('2026-09-15', 'dinner'), isNull);
    expect(find.text('Schließen'), findsNothing);
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
    expect((await repo.readFoodEntry('e-rice')).missing, isTrue);
  });

  testWidgets('write exception keeps the draft and allows retry', (
    tester,
  ) async {
    final shown = draft();
    await repo.saveMealDraft(shown);
    repo.failFoodWrite = true;
    final result = await openSheet(tester, shown);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('Speichern'), findsNothing);
    expect(find.text('Schließen'), findsNothing);
    expect(find.text('Entwurf behalten'), findsNothing);
    expect(find.textContaining('bleibt erhalten'), findsNothing);
    expect(await repo.readMealDraft('2026-09-15', 'dinner'), isNotNull);
    expect((await repo.readFoodEntry('e-rice')).missing, isTrue);
    repo.failFoodWrite = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect((await repo.readFoodEntry('e-rice')).current?.kcal, 300);
  });

  testWidgets('Neu laden replaces the sheet with the retained draft', (
    tester,
  ) async {
    final shown = draft();
    await repo.saveMealDraft(shown);
    final current = draft(
      id: 'd-now',
      label: 'Tofu',
      entryId: 'e-tofu',
      kcal: 180,
    );
    await repo.saveMealDraft(current);
    await openSheet(tester, shown);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Entwurf nicht gespeichert'), findsOneWidget);
    expect(find.text('Reis'), findsOneWidget);
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(find.text('Tofu'), findsOneWidget);
    expect(find.text('180 kcal'), findsOneWidget);
    expect(find.text('Reis'), findsNothing);
    expect(find.text('Speichern'), findsOneWidget);
    expect(find.text('Entwurf nicht gespeichert'), findsNothing);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.byType(OBMealDraftSheet), findsNothing);
    expect((await repo.readFoodEntry('e-tofu')).current?.kcal, 180);
    expect((await repo.readFoodEntry('e-rice')).missing, isTrue);
  });

  testWidgets('missing retained draft offers Close and never recreates', (
    tester,
  ) async {
    final shown = draft();
    await repo.saveMealDraft(shown);
    await repo.discardMealDraft(shown.id);
    final result = await openSheet(tester, shown);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(find.text('Entwurf nicht gefunden'), findsOneWidget);
    expect(find.text('Reis'), findsNothing);
    expect(find.text('Neu laden'), findsNothing);
    expect(find.text('Speichern'), findsNothing);
    expect(await repo.readMealDraft('2026-09-15', 'dinner'), isNull);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
    expect(await repo.readMealDraft('2026-09-15', 'dinner'), isNull);
    expect((await repo.readFoodEntry('e-rice')).missing, isTrue);
  });

  testWidgets('read failure retries only that read', (tester) async {
    final shown = draft();
    await repo.saveMealDraft(shown);
    await repo.discardMealDraft(shown.id);
    await repo.saveMealDraft(
      draft(id: 'd-now', label: 'Tofu', entryId: 'e-tofu', kcal: 180),
    );
    await openSheet(tester, shown);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    repo.failRead = true;
    final commitsBefore = repo.commits;
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(find.text('Entwurf nicht geladen'), findsOneWidget);
    expect(find.text('Entwurf nicht gespeichert'), findsNothing);
    expect(find.text('Neu laden'), findsOneWidget);
    expect(find.text('Speichern'), findsNothing);
    expect(find.text('Tofu'), findsNothing);
    expect(find.text('Reis'), findsNothing);
    expect(repo.commits, commitsBefore);
    repo.failRead = false;
    await tester.tap(find.text('Neu laden'));
    await tester.pumpAndSettle();
    expect(find.text('Tofu'), findsOneWidget);
    expect(find.text('Speichern'), findsOneWidget);
    expect(repo.commits, commitsBefore);
  });

  testWidgets('busy save and reload ignore extra taps', (tester) async {
    final shown = draft();
    await repo.saveMealDraft(shown);
    final saveGate = Completer<void>();
    repo.foodWriteBarrier = saveGate.future;
    final result = await openSheet(tester, shown);
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    expect(find.text('Wird gespeichert…'), findsOneWidget);
    expect(
      tester
          .widget<OBAction>(find.widgetWithText(OBAction, 'Wird gespeichert…'))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Wird gespeichert…'));
    await tester.tap(find.byTooltip('Schließen'));
    await tester.tapAt(const Offset(8, 8));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(OBMealDraftSheet), findsOneWidget);
    await tester.pump();
    expect(repo.commits, 1);
    saveGate.complete();
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(repo.commits, 1);

    final other = draft(
      id: 'd-busy',
      entryId: 'e-busy',
      label: 'Tofu',
      kcal: 180,
    );
    await repo.saveMealDraft(other);
    await repo.discardMealDraft(other.id);
    await openSheet(tester, other);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final readGate = Completer<void>();
    repo.readGate = readGate;
    await tester.tap(find.text('Neu laden'));
    await tester.pump();
    expect(
      tester
          .widget<OBAction>(find.widgetWithText(OBAction, 'Neu laden'))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Neu laden'));
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pump();
    expect(repo.reads, 1);
    readGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Entwurf nicht gefunden'), findsOneWidget);
    expect(repo.reads, 1);
  });

  testWidgets('long 2x host keeps pinned controls inside both safe areas', (
    tester,
  ) async {
    final many = MealDraft(
      id: 'd-safe-host',
      day: '2026-09-15',
      meal: 'breakfast',
      entries: [
        for (var i = 1; i <= 8; i++)
          MealDraftEntry(
            id: 'e-safe-$i',
            label: 'Sehr langes Lebensmittel $i mit extra Text',
            kcal: 100.0 * i,
          ),
      ],
      updatedAt: DateTime(2026, 9, 15, 8),
    );

    for (final (width, height) in [(393.0, 852.0), (375.0, 812.0)]) {
      await openSheet(
        tester,
        many,
        scale: 2,
        width: width,
        height: height,
        padding: const EdgeInsets.only(top: 59, bottom: 34),
      );
      final header = find.text('Frühstück');
      final close = find.byTooltip('Schließen');
      final footer = find.widgetWithText(OBAction, 'Speichern');
      final headerBefore = tester.getRect(header);
      final closeBefore = tester.getRect(close);
      final footerBefore = tester.getRect(footer);
      expect(headerBefore.top, greaterThanOrEqualTo(59));
      expect(closeBefore.top, greaterThanOrEqualTo(59));
      expect(footerBefore.bottom, lessThanOrEqualTo(height - 34 + 0.5));

      final last = find.text('Sehr langes Lebensmittel 8 mit extra Text');
      await tester.scrollUntilVisible(
        last,
        240,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(header), headerBefore);
      expect(tester.getRect(close), closeBefore);
      expect(tester.getRect(footer), footerBefore);
      final lastRect = tester.getRect(last);
      expect(lastRect.top, greaterThanOrEqualTo(headerBefore.bottom));
      expect(lastRect.bottom, lessThanOrEqualTo(footerBefore.top));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('late completion after close does not pop saved or crash', (
    tester,
  ) async {
    final shown = draft();
    await repo.saveMealDraft(shown);
    final gate = Completer<void>();
    repo.foodWriteBarrier = gate.future;
    final result = await openSheet(tester, shown);
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    Navigator.of(tester.element(find.byType(OBMealDraftSheet))).pop(false);
    await tester.pumpAndSettle();
    expect(await result, isFalse);
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(OBMealDraftSheet), findsNothing);
    expect((await repo.readFoodEntry('e-rice')).current?.kcal, 300);
  });

  FoodEntry unknownSnack() => const FoodEntry(
    id: 'unk-1',
    date: '2026-09-15',
    meal: 'snack',
    label: 'Guess',
    kcal: 200,
    fibreG: 8.1,
    sodiumMg: 12,
    source: FoodSource.unknown,
    sourceCode: 'crowd-guess',
    confirmed: true,
    atTs: 123,
    createdAt: 50,
    updatedAt: 50,
  );

  Future<OpenBandController> mountDay(
    WidgetTester tester, {
    FutureOr<void> Function(String meal)? onAdd,
    double scale = 1,
    double width = 393,
    double height = 852,
    OpenBandController? existing,
  }) async {
    final controller =
        existing ??
        OpenBandController(
          repository: repo,
          initialDay: '2026-09-15',
          band: repo.band,
          now: () => DateTime(2026, 9, 15, 9, 41),
        );
    if (existing == null) addTearDown(controller.dispose);
    await controller.refresh();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        debugShowCheckedModeBanner: false,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: OpenBandNutrition(controller: controller, onAdd: onAdd),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> pumpShown(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapSnackAction(WidgetTester tester, String label) async {
    final inBar = find.descendant(
      of: find.byType(SnackBar),
      matching: find.widgetWithText(TextButton, label),
    );
    await tester.tap(inBar.evaluate().isEmpty ? find.widgetWithText(TextButton, label) : inBar);
  }

  Future<void> tapDayFood(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final list = find.byType(ListView).first;
    final item = tester.getRect(finder);
    final view = tester.getRect(list);
    if (item.bottom > view.bottom - 24) {
      await tester.drag(list, Offset(0, view.bottom - 24 - item.bottom));
      await tester.pumpAndSettle();
    }
    await tester.tap(finder);
  }

  testWidgets('row opens food entry; add stays on add', (tester) async {
    var added = 0;
    await mountDay(tester, onAdd: (_) async => added++);
    await tester.tap(find.text('Haferflocken mit Milch'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandFoodEntry), findsOneWidget);
    expect(added, 0);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Frühstück ergänzen'));
    await tester.pumpAndSettle();
    expect(added, 1);
    expect(find.byType(OpenBandFoodEntry), findsNothing);
  });

  testWidgets('edit returns updates the captured day', (tester) async {
    await mountDay(tester);
    await tester.tap(find.text('Haferflocken mit Milch'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bearbeiten'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('food-entry-name')),
      'Hafer neu',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('food-entry-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Hafer neu'), findsOneWidget);
    expect(find.text('Haferflocken mit Milch'), findsNothing);
    expect((await repo.readFoodEntry('m1')).current?.label, 'Hafer neu');
  });

  testWidgets(
    'cross-day leaf delete offers Undo on captured parent day',
    (tester) async {
      final controller = await mountDay(tester);
      await tester.tap(find.text('Haferflocken mit Milch'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bearbeiten'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Datum'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsLabel('Mittwoch, 16. September 2026'),
      );
      await tester.pump();
      await tester.tap(find.textContaining('übernehmen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('food-entry-save')));
      await tester.pumpAndSettle();

      final saved = (await repo.readFoodEntry('m1')).current!;
      expect(saved.date, '2026-09-16');
      await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
      await pumpShown(tester);

      expect(controller.selectedDay, '2026-09-15');
      expect((await repo.readFoodEntry('m1')).missing, isTrue);
      expect(find.text('Eintrag entfernt'), findsOneWidget);
      expect(find.text('Rückgängig'), findsOneWidget);
      await tapSnackAction(tester, 'Rückgängig');
      await pumpShown(tester);

      final restored = (await repo.readFoodEntry('m1')).current!;
      expect(controller.selectedDay, '2026-09-15');
      expect(restored.date, '2026-09-16');
      expect(restored.source, saved.source);
      expect(restored.sourceCode, saved.sourceCode);
      expect(restored.atTs, saved.atTs);
      expect(restored.createdAt, saved.createdAt);
      expect(restored.updatedAt, saved.updatedAt);
      expect(repo.restores, 1);
    },
  );

  testWidgets('remove Undo restores exact unknown source nutrients stamps', (
    tester,
  ) async {
    repo.seedFoodEntry(unknownSnack());
    await mountDay(tester);
    await tapDayFood(tester, 'Guess');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
    await pumpShown(tester);
    expect(find.byType(OpenBandFoodEntry), findsNothing);
    expect(find.text('Guess'), findsNothing);
    expect(find.text('Eintrag entfernt'), findsOneWidget);
    expect(find.text('Rückgängig'), findsOneWidget);
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.behavior, SnackBarBehavior.floating);
    final margin = bar.margin! as EdgeInsets;
    expect(margin.left, 16);
    expect(margin.right, 16);
    expect(bar.shape, isA<RoundedRectangleBorder>());
    expect(
      (bar.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(16),
    );
    expect(
      tester.getSize(find.text('Rückgängig')).height,
      greaterThanOrEqualTo(20),
    );
    final action = tester.getRect(
      find.widgetWithText(TextButton, 'Rückgängig'),
    );
    expect(action.height, greaterThanOrEqualTo(44));
    expect(action.right, closeTo(369, 0.5));
    expect(tester.getRect(find.text('Rückgängig')).right, closeTo(361, 0.5));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      tester.getSize(find.byType(SnackBar)).height - margin.bottom,
      closeTo(56, 0.5),
    );
    await tapSnackAction(tester, 'Rückgängig');
    await pumpShown(tester);
    final restored = (await repo.readFoodEntry('unk-1')).current!;
    expect(restored.source, FoodSource.unknown);
    expect(restored.sourceCode, 'crowd-guess');
    expect(restored.fibreG, 8.1);
    expect(restored.sodiumMg, 12);
    expect(restored.kcal, 200);
    expect(restored.atTs, 123);
    expect(restored.createdAt, 50);
    expect(restored.updatedAt, 50);
    expect(find.text('Guess'), findsOneWidget);
    expect(repo.restores, 1);
  });

  testWidgets('restore exception retries without losing the receipt', (
    tester,
  ) async {
    repo.seedFoodEntry(unknownSnack());
    await mountDay(tester);
    await tapDayFood(tester, 'Guess');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
    await pumpShown(tester);
    repo.failFoodWrite = true;
    await tapSnackAction(tester, 'Rückgängig');
    await pumpShown(tester);
    expect(find.text('Wiederherstellen fehlgeschlagen'), findsOneWidget);
    expect((await repo.readFoodEntry('unk-1')).missing, isTrue);
    expect(repo.restores, 1);
    repo.failFoodWrite = false;
    await tapSnackAction(tester, 'Erneut');
    await pumpShown(tester);
    expect((await repo.readFoodEntry('unk-1')).current?.fibreG, 8.1);
    expect(find.text('Guess'), findsOneWidget);
    expect(repo.restores, 2);
  });

  testWidgets('restore conflict does not overwrite a different current row', (
    tester,
  ) async {
    repo.seedFoodEntry(unknownSnack());
    await mountDay(tester);
    await tapDayFood(tester, 'Guess');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
    await pumpShown(tester);
    repo.seedFoodEntry(
      const FoodEntry(
        id: 'unk-1',
        date: '2026-09-15',
        meal: 'snack',
        label: 'Other',
        kcal: 90,
        createdAt: 9,
        updatedAt: 9,
      ),
    );
    await tapSnackAction(tester, 'Rückgängig');
    await tapSnackAction(tester, 'Rückgängig');
    await pumpShown(tester);
    final current = (await repo.readFoodEntry('unk-1')).current!;
    expect(current.label, 'Other');
    expect(current.kcal, 90);
    expect(current.fibreG, isNull);
    expect(find.text('Eintrag wurde geändert'), findsOneWidget);
    expect(find.text('Neu laden'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Schließen'), findsOneWidget);
    expect(find.text('Wiederherstellen fehlgeschlagen'), findsNothing);
    expect(repo.restores, 1);
    await tapSnackAction(tester, 'Neu laden');
    await pumpShown(tester);
    expect(repo.restores, 1);
    expect((await repo.readFoodEntry('unk-1')).current?.label, 'Other');
  });

  testWidgets('2x conflict snack keeps both actions readable at 375', (
    tester,
  ) async {
    repo.seedFoodEntry(unknownSnack());
    await mountDay(tester, scale: 2, width: 375, height: 1600);
    await tapDayFood(tester, 'Guess');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('food-entry-remove')));
    await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('ob-confirm-yes')));
    await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
    await pumpShown(tester);
    repo.seedFoodEntry(
      const FoodEntry(
        id: 'unk-1',
        date: '2026-09-15',
        meal: 'snack',
        label: 'Other',
        kcal: 90,
        createdAt: 9,
        updatedAt: 9,
      ),
    );
    tester.view.physicalSize = const Size(375, 812);
    await tester.pumpAndSettle();
    await tapSnackAction(tester, 'Rückgängig');
    await pumpShown(tester);

    expect(find.text('Eintrag wurde geändert'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Neu laden'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Schließen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.margin, const EdgeInsets.fromLTRB(16, 0, 16, 50));
    final bar = tester.getRect(find.byType(SnackBar));
    expect(bar.left, greaterThanOrEqualTo(0));
    expect(bar.right, lessThanOrEqualTo(375 + 0.5));
    for (final label in ['Neu laden', 'Schließen']) {
      final action = tester.getRect(find.widgetWithText(TextButton, label));
      expect(action.height, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.text(label)).height, lessThanOrEqualTo(40.5));
      expect(action.left, greaterThanOrEqualTo(bar.left));
      expect(action.right, lessThanOrEqualTo(bar.right));
    }
  });

  testWidgets('restore then meals read failure retries read only', (
    tester,
  ) async {
    repo.seedFoodEntry(unknownSnack());
    await mountDay(tester);
    await tapDayFood(tester, 'Guess');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
    await pumpShown(tester);
    repo.failMealsRead = true;
    await tapSnackAction(tester, 'Rückgängig');
    await pumpShown(tester);
    expect((await repo.readFoodEntry('unk-1')).current?.fibreG, 8.1);
    expect(repo.restores, 1);
    expect(find.text('Einträge konnten nicht geladen werden.'), findsWidgets);
    repo.failMealsRead = false;
    await tapSnackAction(tester, 'Erneut');
    await pumpShown(tester);
    await tester.scrollUntilVisible(
      find.text('Guess'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Guess'), findsOneWidget);
    expect(repo.restores, 1);
  });

  testWidgets('day change while route open does not apply the prior day', (
    tester,
  ) async {
    final controller = await mountDay(tester);
    await tester.tap(find.text('Haferflocken mit Milch'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => controller.selectDay('2026-09-14'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(controller.selectedDay, '2026-09-14');
    expect(find.text('Haferflocken mit Milch'), findsNothing);
    expect(find.byType(OpenBandFoodEntry), findsNothing);
  });

  testWidgets('day change during restore does not display the old day', (
    tester,
  ) async {
    repo.seedFoodEntry(unknownSnack());
    final controller = await mountDay(tester);
    await tapDayFood(tester, 'Guess');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
    await pumpShown(tester);
    final gate = Completer<void>();
    repo.foodWriteBarrier = gate.future;
    await tapSnackAction(tester, 'Rückgängig');
    await tester.pump();
    await tester.runAsync(() => controller.selectDay('2026-09-14'));
    await tester.pump();
    gate.complete();
    await pumpShown(tester);
    expect(controller.selectedDay, '2026-09-14');
    expect(find.text('Guess'), findsNothing);
    expect((await repo.readFoodEntry('unk-1')).current?.date, '2026-09-15');
    expect((await repo.readFoodEntry('unk-1')).current?.fibreG, 8.1);
    expect(repo.restores, 1);
  });

  testWidgets(
    'repository change while route open does not write the new repo',
    (tester) async {
      final first = repo;
      first.seedFoodEntry(unknownSnack());
      final c1 = OpenBandController(
        repository: first,
        initialDay: '2026-09-15',
        band: first.band,
        now: () => DateTime(2026, 9, 15, 9, 41),
      );
      addTearDown(c1.dispose);
      final second = _galleryRepo();
      final c2 = OpenBandController(
        repository: second,
        initialDay: '2026-09-15',
        band: second.band,
        now: () => DateTime(2026, 9, 15, 9, 41),
      );
      addTearDown(c2.dispose);
      await c1.refresh();
      await c2.refresh();
      late StateSetter setHost;
      var current = c1;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('de')],
          theme: openBandTheme(Brightness.light),
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
              return OpenBandNutrition(controller: current);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapDayFood(tester, 'Guess');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
      await tester.pumpAndSettle();
      setHost(() => current = c2);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
      await pumpShown(tester);
      expect((await first.readFoodEntry('unk-1')).missing, isTrue);
      expect((await second.readFoodEntry('unk-1')).missing, isTrue);
      expect(find.text('Rückgängig'), findsNothing);
      expect(find.text('Eintrag entfernt'), findsNothing);
      expect(first.restores, 0);
      expect(second.restores, 0);
    },
  );

  testWidgets(
    'two removals keep the later undo while the first restore is late',
    (tester) async {
      repo.seedFoodEntry(unknownSnack());
      await mountDay(tester);
      await tapDayFood(tester, 'Guess');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
      await pumpShown(tester);
      final gate = Completer<void>();
      repo.restoreGate = gate;
      await tapSnackAction(tester, 'Rückgängig');
      await tester.pump();
      await tester.tap(find.text('Haferflocken mit Milch'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
      await pumpShown(tester);
      expect(find.text('Eintrag entfernt'), findsOneWidget);
      expect(find.text('Rückgängig'), findsOneWidget);
      gate.complete();
      await pumpShown(tester);
      expect((await repo.readFoodEntry('unk-1')).current?.label, 'Guess');
      expect((await repo.readFoodEntry('m1')).missing, isTrue);
      expect(find.text('Eintrag entfernt'), findsOneWidget);
      expect(find.text('Rückgängig'), findsOneWidget);
      expect(find.text('Guess'), findsOneWidget);
      expect(find.text('Haferflocken mit Milch'), findsNothing);
      await tapSnackAction(tester, 'Rückgängig');
      await pumpShown(tester);
      expect(
        (await repo.readFoodEntry('m1')).current?.label,
        'Haferflocken mit Milch',
      );
      expect(find.text('Haferflocken mit Milch'), findsOneWidget);
      expect(repo.restores, 2);
    },
  );

  testWidgets(
    'production controller readDay failure after restore retries read only',
    (tester) async {
      repo.seedFoodEntry(unknownSnack());
      final controller = await mountDay(tester);
      await tapDayFood(tester, 'Guess');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
      await pumpShown(tester);

      repo.failDayRead = true;
      await tapSnackAction(tester, 'Rückgängig');
      await pumpShown(tester);

      expect(controller.loadError, isA<StateError>());
      expect((await repo.readFoodEntry('unk-1')).current?.fibreG, 8.1);
      expect(repo.restores, 1);
      expect(find.text('Einträge konnten nicht geladen werden.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Erneut'), findsOneWidget);

      repo.failDayRead = false;
      await tapSnackAction(tester, 'Erneut');
      await pumpShown(tester);

      expect(controller.loadError, isNull);
      expect(find.text('Einträge konnten nicht geladen werden.'), findsNothing);
      expect(find.text('Guess'), findsOneWidget);
      expect(repo.restores, 1);
    },
  );

  testWidgets('same-day revision keeps Undo and does not drop the receipt', (
    tester,
  ) async {
    repo.seedFoodEntry(unknownSnack());
    var revision = 0;
    late StateSetter setHost;
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
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
    await tapDayFood(tester, 'Guess');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
    await pumpShown(tester);
    expect(find.text('Eintrag entfernt'), findsOneWidget);
    expect(find.text('Rückgängig'), findsOneWidget);
    setHost(() => revision += 1);
    await tester.pumpAndSettle();
    expect(find.text('Eintrag entfernt'), findsOneWidget);
    expect(find.text('Rückgängig'), findsOneWidget);
    await tapSnackAction(tester, 'Rückgängig');
    await pumpShown(tester);
    expect((await repo.readFoodEntry('unk-1')).current?.fibreG, 8.1);
    expect(find.text('Guess'), findsOneWidget);
    expect(repo.restores, 1);
  });

  testWidgets('refresh throw after restore retries read only', (tester) async {
    repo.seedFoodEntry(unknownSnack());
    final controller = _RefreshThrowController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
    addTearDown(controller.dispose);
    await mountDay(tester, existing: controller);
    await tapDayFood(tester, 'Guess');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
    await pumpShown(tester);
    controller.throwRefresh = true;
    await tapSnackAction(tester, 'Rückgängig');
    await pumpShown(tester);
    expect((await repo.readFoodEntry('unk-1')).current?.fibreG, 8.1);
    expect(repo.restores, 1);
    expect(find.text('Wiederherstellen fehlgeschlagen'), findsNothing);
    expect(find.text('Einträge konnten nicht geladen werden.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Erneut'), findsOneWidget);
    controller.throwRefresh = false;
    await tapSnackAction(tester, 'Erneut');
    await pumpShown(tester);
    expect(find.text('Einträge konnten nicht geladen werden.'), findsNothing);
    expect(find.text('Guess'), findsOneWidget);
    expect(repo.restores, 1);
  });

  testWidgets('delete snack is installed even if reload refresh throws', (
    tester,
  ) async {
    repo.seedFoodEntry(unknownSnack());
    final controller = _RefreshThrowController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
    addTearDown(controller.dispose);
    await mountDay(tester, existing: controller);
    await tapDayFood(tester, 'Guess');
    await tester.pumpAndSettle();
    controller.throwRefresh = true;
    await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
    await pumpShown(tester);
    expect(find.text('Eintrag entfernt'), findsOneWidget);
    expect(find.text('Rückgängig'), findsOneWidget);
    expect((await repo.readFoodEntry('unk-1')).missing, isTrue);
    expect(repo.restores, 0);
    controller.throwRefresh = false;
    await tapSnackAction(tester, 'Rückgängig');
    await pumpShown(tester);
    expect((await repo.readFoodEntry('unk-1')).current?.fibreG, 8.1);
    expect(find.text('Guess'), findsOneWidget);
    expect(repo.restores, 1);
  });

  testWidgets('2x undo action does not overflow', (tester) async {
    await mountDay(tester, scale: 2);
    tester.view.physicalSize = const Size(393, 2000);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Haferflocken mit Milch'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('food-entry-remove')));
    await tester.tap(find.byKey(const ValueKey('food-entry-remove')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('ob-confirm-yes')));
    await tester.tap(find.byKey(const ValueKey('ob-confirm-yes')));
    await pumpShown(tester);
    expect(find.text('Eintrag entfernt'), findsOneWidget);
    expect(find.text('Rückgängig'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final action = tester.getRect(
      find.widgetWithText(TextButton, 'Rückgängig'),
    );
    expect(action.height, greaterThanOrEqualTo(44));
    expect(
      tester.getSize(find.text('Rückgängig')).height,
      lessThanOrEqualTo(40.5),
    );
    final bar = tester.getRect(find.byType(SnackBar));
    expect(bar.right, lessThanOrEqualTo(393 + 0.5));
  });

  Future<void> captureDraft(
    WidgetTester tester,
    String name, {
    required MealDraft shown,
    Brightness brightness = Brightness.light,
    double scale = 1,
    Future<void> Function()? beforeCapture,
  }) async {
    await openSheet(
      tester,
      shown,
      brightness: brightness,
      scale: scale,
      padding: const EdgeInsets.only(top: 59, bottom: 34),
    );
    if (beforeCapture != null) await beforeCapture();
    await tester.pumpAndSettle();
    expect(find.byType(OBMealDraftSheet), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/$name.png'),
    );
  }

  testWidgets('meal draft goldens cover overlay states', (tester) async {
    final shown = draft();
    await repo.saveMealDraft(
      MealDraft(
        id: shown.id,
        day: shown.day,
        meal: 'breakfast',
        entries: const [
          MealDraftEntry(
            id: 'e-oats',
            label: 'Haferflocken mit Milch',
            kcal: 380,
          ),
          MealDraftEntry(id: 'e-coffee', label: 'Kaffee'),
        ],
        updatedAt: DateTime(2026, 9, 15, 8),
      ),
    );
    final breakfast = MealDraft(
      id: shown.id,
      day: shown.day,
      meal: 'breakfast',
      entries: const [
        MealDraftEntry(
          id: 'e-oats',
          label: 'Haferflocken mit Milch',
          kcal: 380,
        ),
        MealDraftEntry(id: 'e-coffee', label: 'Kaffee'),
      ],
      updatedAt: DateTime(2026, 9, 15, 8),
    );
    await captureDraft(tester, 'meal-draft-normal', shown: breakfast);

    await captureDraft(
      tester,
      'meal-draft-dark',
      shown: breakfast,
      brightness: Brightness.dark,
    );

    await repo.discardMealDraft(breakfast.id);
    await captureDraft(
      tester,
      'meal-draft-conflict',
      shown: breakfast,
      beforeCapture: () async {
        await tester.tap(find.text('Speichern'));
        await tester.pumpAndSettle();
        expect(find.text('Entwurf nicht gespeichert'), findsOneWidget);
      },
    );

    await repo.saveMealDraft(breakfast);
    repo.failFoodWrite = true;
    await captureDraft(
      tester,
      'meal-draft-error',
      shown: breakfast,
      beforeCapture: () async {
        await tester.tap(find.text('Speichern'));
        await tester.pumpAndSettle();
        expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      },
    );
    repo.failFoodWrite = false;

    await repo.discardMealDraft(breakfast.id);
    await captureDraft(
      tester,
      'meal-draft-missing',
      shown: breakfast,
      beforeCapture: () async {
        await tester.tap(find.text('Speichern'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Neu laden'));
        await tester.pumpAndSettle();
        expect(find.text('Entwurf nicht gefunden'), findsOneWidget);
        expect(find.text('Haferflocken mit Milch'), findsNothing);
      },
    );

    await repo.saveMealDraft(breakfast);
    await repo.discardMealDraft(breakfast.id);
    await repo.saveMealDraft(
      MealDraft(
        id: 'd-now',
        day: breakfast.day,
        meal: breakfast.meal,
        entries: breakfast.entries,
        updatedAt: DateTime(2026, 9, 15, 9),
      ),
    );
    await captureDraft(
      tester,
      'meal-draft-read-error',
      shown: breakfast,
      beforeCapture: () async {
        await tester.tap(find.text('Speichern'));
        await tester.pumpAndSettle();
        repo.failRead = true;
        await tester.tap(find.text('Neu laden'));
        await tester.pumpAndSettle();
        expect(find.text('Entwurf nicht geladen'), findsOneWidget);
      },
    );
    repo.failRead = false;

    final many = MealDraft(
      id: 'd-many',
      day: '2026-09-15',
      meal: 'breakfast',
      entries: [
        for (var i = 1; i <= 8; i++)
          MealDraftEntry(
            id: 'e-$i',
            label: 'Sehr langes Lebensmittel $i mit extra Text',
            kcal: 100.0 * i,
          ),
      ],
      updatedAt: DateTime(2026, 9, 15, 8),
    );
    await repo.saveMealDraft(many);
    await captureDraft(tester, 'meal-draft-2x', shown: many, scale: 2);
  });
}
