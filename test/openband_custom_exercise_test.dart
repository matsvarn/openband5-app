import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/exercise_definition_editor.dart';
import 'package:openstrap_edge/openband/exercise_picker.dart';
import 'package:openstrap_edge/openband/settings_controls.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

Map _summary() =>
    jsonDecode(
          File(
            'docs/openband5/assets/fixtures/day-summary.json',
          ).readAsStringSync(),
        )
        as Map;

Map _detail() =>
    jsonDecode(
          File(
            'docs/openband5/assets/fixtures/sleep-detail.json',
          ).readAsStringSync(),
        )
        as Map;

ExerciseCatalogueEntry customCurl({String id = 'custom-curl'}) =>
    ExerciseCatalogueEntry(
      id: id,
      label: 'Kurzhantel-Curl',
      mode: ExerciseCaptureMode.repetitions,
      equipment: ExerciseEquipmentCategory.dumbbell,
      loadBasis: ExerciseLoadBasis.perDevice,
      deviceCount: 2,
      repetitionBasis: ExerciseRepetitionBasis.perSide,
      primaryMuscles: const ['biceps'],
      source: ExerciseDefinitionSource.stored,
      version: 1,
      retained: const {'custom': 1, 'source': 'custom'},
    );

class _Repo extends SyntheticOpenBandRepository {
  _Repo({
    this.failCreate = false,
    this.conflictCreate = false,
    this.conflictCurrent,
    this.createDelay,
    this.catalogue,
  }) : super.fromMaps(_summary(), _detail());

  bool failCreate;
  bool conflictCreate;
  bool failRead = false;
  ExerciseCatalogueEntry? conflictCurrent;
  Duration? createDelay;
  ExerciseCatalogue? catalogue;
  final created = <CustomExerciseDraft>[];

  @override
  Future<ExerciseCatalogue> readExerciseCatalogue() async {
    if (failRead) throw StateError('fail');
    if (catalogue != null) return catalogue!;
    return super.readExerciseCatalogue();
  }

  @override
  Future<CustomExerciseWriteResult> createCustomExercise(
    CustomExerciseDraft draft,
  ) async {
    created.add(draft);
    if (createDelay != null) await Future<void>.delayed(createDelay!);
    if (failCreate) throw StateError('fail');
    if (conflictCreate) {
      return CustomExerciseWriteResult.conflict(conflictCurrent);
    }
    return super.createCustomExercise(draft);
  }
}

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

  Future<void> pumpEditor(
    WidgetTester tester, {
    required _Repo repo,
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
    double dpr = 1,
    ExerciseCaptureMode? initialMode,
    ExerciseCatalogueEntry? copyFrom,
  }) async {
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = Size(width * dpr, height * dpr);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: OpenBandExerciseDefinitionEditor(
          repository: repo,
          initialMode: initialMode,
          copyFrom: copyFrom,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpPicker(
    WidgetTester tester, {
    required OpenBandRepository repo,
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
    bool createOnOpen = false,
    ExerciseCaptureMode? initialCreateMode,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: OpenBandExercisePicker(
          repository: repo,
          createOnOpen: createOnOpen,
          initialCreateMode: initialCreateMode,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillRequired(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('custom-exercise-name')),
      'Kurzhantel-Curl',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-equipment')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('custom-exercise-equipment-dumbbell')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-mode')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('custom-exercise-mode-repetitions')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-load')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('custom-exercise-load-perDevice')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-count')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settings-count-field')),
      '2',
    );
    await tester.pump();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-reps')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('custom-exercise-reps-perSide')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unfocus(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  }

  testWidgets('missing fields refuse save', (tester) async {
    final repo = _Repo();
    await pumpEditor(tester, repo: repo);
    final save = tester.widget<OBAction>(
      find.byKey(const ValueKey('custom-exercise-save')),
    );
    expect(save.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pump();
    expect(repo.created, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('custom-exercise-name')),
      'Curl',
    );
    await tester.pump();
    expect(
      tester
          .widget<OBAction>(find.byKey(const ValueKey('custom-exercise-save')))
          .onPressed,
      isNull,
    );
    expect(find.text('Gewichtsangabe'), findsNothing);
  });

  testWidgets('positive count only; cancel keeps prior', (tester) async {
    final repo = _Repo();
    await pumpEditor(tester, repo: repo);
    await fillRequired(tester);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-count')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settings-count-field')),
      '0',
    );
    await tester.pump();
    expect(
      tester
          .widget<OBAction>(find.widgetWithText(OBAction, 'Übernehmen'))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('settings-count-field')),
      '',
    );
    await tester.pump();
    expect(
      tester
          .widget<OBAction>(find.widgetWithText(OBAction, 'Übernehmen'))
          .onPressed,
      isNull,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('count clears when leaving per-device basis', (tester) async {
    final repo = _Repo();
    await pumpEditor(tester, repo: repo);
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-load')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-load-total')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('custom-exercise-count')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-load')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('custom-exercise-load-perDevice')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Auswählen'), findsWidgets);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('time clears repetition basis; reps requires a new choice', (
    tester,
  ) async {
    final repo = _Repo();
    await pumpEditor(tester, repo: repo);
    await fillRequired(tester);
    expect(find.text('Je Seite'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-mode-time')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('custom-exercise-reps')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-mode')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('custom-exercise-mode-repetitions')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Auswählen'), findsWidgets);
    expect(find.text('Je Seite'), findsNothing);
  });

  testWidgets('optional muscles stay disjoint', (tester) async {
    final repo = _Repo();
    await pumpEditor(tester, repo: repo);
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-primary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-muscle-biceps')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Bizeps'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-secondary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-muscle-biceps')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OBSettingsValueRow>(
            find.byKey(const ValueKey('custom-exercise-primary')),
          )
          .value,
      '—',
    );
    expect(
      tester
          .widget<OBSettingsValueRow>(
            find.byKey(const ValueKey('custom-exercise-secondary')),
          )
          .value,
      'Bizeps',
    );
  });

  testWidgets('cancel writes nothing', (tester) async {
    final repo = _Repo();
    await pumpPicker(tester, repo: repo);
    await tester.tap(find.byTooltip('Eigene Übung'));
    await tester.pumpAndSettle();
    await fillRequired(tester);
    await tester.tap(find.byTooltip('Zurück').last);
    await tester.pumpAndSettle();
    expect(repo.created, isEmpty);
    expect(find.byType(OpenBandExerciseDefinitionEditor), findsNothing);
    expect(find.byType(OpenBandExercisePicker), findsOneWidget);
  });

  testWidgets('busy save ignores a second tap', (tester) async {
    final repo = _Repo(createDelay: const Duration(milliseconds: 200));
    await pumpEditor(tester, repo: repo);
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pump();
    expect(repo.created, hasLength(1));
    await tester.pumpAndSettle();
    expect(repo.created, hasLength(1));
  });

  testWidgets('failed save keeps input and retries the same id', (
    tester,
  ) async {
    final repo = _Repo(failCreate: true);
    await pumpEditor(tester, repo: repo);
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut speichern'), findsOneWidget);
    expect(find.text('Kurzhantel-Curl'), findsOneWidget);
    expect(find.text('Je Hantel'), findsOneWidget);
    expect(repo.created, hasLength(1));
    final first = repo.created.single;
    repo.failCreate = false;
    await tester.tap(find.text('Erneut speichern'));
    await tester.pumpAndSettle();
    expect(repo.created, hasLength(2));
    expect(repo.created.last.id, first.id);
    expect(repo.created.last.label, first.label);
    expect(repo.created.last.deviceCount, 2);
    expect(repo.created.last.repetitionBasis, ExerciseRepetitionBasis.perSide);
    final stored = (await repo.readExerciseCatalogue()).byId(first.id!);
    expect(stored, isNotNull);
    expect(stored!.label, 'Kurzhantel-Curl');
  });

  testWidgets('conflict is distinct from success', (tester) async {
    final repo = _Repo(
      conflictCreate: true,
      conflictCurrent: customCurl(id: 'taken'),
    );
    await pumpEditor(tester, repo: repo);
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    expect(find.text('Konflikt: Kurzhantel-Curl'), findsOneWidget);
    expect(find.text('Neu laden'), findsNothing);
    expect(find.text('Zurück'), findsOneWidget);
    expect(find.byType(OpenBandExerciseDefinitionEditor), findsOneWidget);
    expect(find.text('Kurzhantel-Curl'), findsWidgets);
    await tester.tap(find.text('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandExerciseDefinitionEditor), findsNothing);
  });

  testWidgets('create roundtrip stays unselected in the library', (
    tester,
  ) async {
    final repo = _Repo();
    await pumpPicker(tester, repo: repo);
    await tester.tap(find.byTooltip('Eigene Übung'));
    await tester.pumpAndSettle();
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-primary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-muscle-biceps')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    expect(find.text('Kurzhantel-Curl'), findsOneWidget);
    expect(find.textContaining('2 Hanteln'), findsOneWidget);
    expect(find.textContaining('Wdh. je Seite'), findsOneWidget);
    expect(find.text('0 Übungen hinzufügen'), findsOneWidget);
    final add = tester.widget<OBAction>(
      find.widgetWithText(OBAction, '0 Übungen hinzufügen'),
    );
    expect(add.onPressed, isNull);
    expect(repo.created, hasLength(1));
    final id = repo.created.single.id!;
    final plus = tester.widget<IconButton>(
      find.byKey(ValueKey('exercise-select-$id')),
    );
    expect(plus.onPressed, isNotNull);
    final stored = (await repo.readExerciseCatalogue()).byId(id);
    expect(stored, isNotNull);
    expect(stored!.loadBasis, ExerciseLoadBasis.perDevice);
    expect(stored.deviceCount, 2);
    expect(stored.repetitionBasis, ExerciseRepetitionBasis.perSide);
  });

  testWidgets('query filters and selection stay put after save', (
    tester,
  ) async {
    final repo = _Repo();
    await pumpPicker(tester, repo: repo);
    await tester.tap(find.byKey(const ValueKey('exercise-select-bench_press')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('exercise-search')),
      'Bank',
    );
    await tester.pumpAndSettle();
    expect(find.text('Bankdrücken'), findsOneWidget);
    await tester.tap(find.byTooltip('Eigene Übung'));
    await tester.pumpAndSettle();
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(find.byKey(const ValueKey('custom-exercise-saved')), findsOneWidget);
    expect(find.text('Kurzhantel-Curl'), findsOneWidget);
    expect(find.text('Übung gespeichert'), findsNothing);
    expect(find.text('Anzeigen'), findsOneWidget);
    expect(find.text('1 Übung hinzufügen'), findsOneWidget);
    await tester.tap(find.text('Anzeigen'));
    await tester.pumpAndSettle();
    expect(find.text('Kurzhantel-Curl'), findsWidgets);
    expect(find.byKey(const ValueKey('custom-exercise-saved')), findsNothing);
    expect(find.text('Anzeigen'), findsNothing);
    expect(find.text('1 Übung · 1 Auswahl außerhalb'), findsOneWidget);
    expect(find.text('1 Übung hinzufügen'), findsOneWidget);
  });

  testWidgets('hidden create notice and add stay hittable at 393, 375 and 2x', (
    tester,
  ) async {
    FlutterErrorDetails? overflow;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) overflow = details;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    Future<void> hideCreated({
      double width = 393,
      double height = 852,
      double scale = 1,
    }) async {
      overflow = null;
      final repo = _Repo();
      await pumpPicker(
        tester,
        repo: repo,
        width: width,
        height: height,
        scale: scale,
      );
      await tester.tap(
        find.byKey(const ValueKey('exercise-select-bench_press')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('exercise-search')),
        'Bank',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Eigene Übung'));
      await tester.pumpAndSettle();
      await fillRequired(tester);
      await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Anzeigen'));
      await tester.ensureVisible(find.text('1 Übung hinzufügen'));
      expect(
        find.byKey(const ValueKey('custom-exercise-saved')),
        findsOneWidget,
      );
      expect(find.text('Kurzhantel-Curl'), findsOneWidget);
      expect(find.text('Anzeigen').hitTestable(), findsOneWidget);
      expect(find.text('1 Übung hinzufügen').hitTestable(), findsOneWidget);
      expect(find.text('1 Übung hinzufügen'), findsOneWidget);
      expect(overflow, isNull);
      expect(tester.takeException(), isNull);
      final id = repo.created.single.id!;
      await tester.tap(find.text('Anzeigen'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('custom-exercise-saved')), findsNothing);
      expect(find.text('Kurzhantel-Curl'), findsWidgets);
      expect(find.text('1 Übung hinzufügen'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(ValueKey('exercise-select-$id')))
            .onPressed,
        isNotNull,
      );
    }

    await hideCreated();
    await hideCreated(width: 375);
    await hideCreated(width: 375, height: 1600, scale: 2);
  });

  testWidgets('select then confirm stays a separate step', (tester) async {
    final repo = _Repo();
    List<ExerciseCatalogueEntry>? picked;
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
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => OpenBandExercisePicker(repository: repo),
                    ),
                  );
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
    await tester.tap(find.byTooltip('Eigene Übung'));
    await tester.pumpAndSettle();
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    final id = repo.created.single.id!;
    await tester.enterText(
      find.byKey(const ValueKey('exercise-search')),
      'Curl',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('exercise-select-$id')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('1 Übung hinzufügen'));
    await tester.tap(find.text('1 Übung hinzufügen'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.single.id, id);
  });

  testWidgets('375 2x does not overflow scrolled controls', (tester) async {
    FlutterErrorDetails? overflow;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) overflow = details;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
    final repo = _Repo();
    await pumpEditor(tester, repo: repo, scale: 2, width: 375, height: 1600);
    await fillRequired(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('custom-exercise-save')),
    );
    expect(overflow, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('goldens: empty light/dark', (tester) async {
    await pumpEditor(tester, repo: _Repo());
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/custom-exercise-empty.png'),
    );
    await pumpEditor(tester, repo: _Repo(), brightness: Brightness.dark);
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/custom-exercise-empty-dark.png'),
    );
  });

  testWidgets('goldens: filled light/dark', (tester) async {
    await pumpEditor(tester, repo: _Repo());
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-primary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-muscle-biceps')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await unfocus(tester);
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/custom-exercise-light.png'),
    );
    await pumpEditor(tester, repo: _Repo(), brightness: Brightness.dark);
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-primary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-muscle-biceps')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await unfocus(tester);
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/custom-exercise-dark.png'),
    );
  });

  testWidgets('goldens: error light/dark', (tester) async {
    await pumpEditor(tester, repo: _Repo(failCreate: true));
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    await unfocus(tester);
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/custom-exercise-error.png'),
    );
    await pumpEditor(
      tester,
      repo: _Repo(failCreate: true),
      brightness: Brightness.dark,
    );
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    await unfocus(tester);
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/custom-exercise-error-dark.png'),
    );
  });

  testWidgets('goldens: count light/dark and 375-2x', (tester) async {
    await pumpEditor(tester, repo: _Repo());
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-count')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/custom-exercise-count.png'),
    );
    await pumpEditor(tester, repo: _Repo(), brightness: Brightness.dark);
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-count')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/custom-exercise-count-dark.png'),
    );
    await pumpEditor(tester, repo: _Repo(), scale: 2, width: 375, height: 1600);
    await fillRequired(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('custom-exercise-secondary')),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/custom-exercise-375-2x.png'),
    );
  });

  testWidgets('goldens: saved library light/dark', (tester) async {
    final repo = _Repo();
    await repo.createCustomExercise(
      CustomExerciseDraft(
        id: 'custom-curl',
        label: 'Kurzhantel-Curl',
        mode: ExerciseCaptureMode.repetitions,
        equipment: ExerciseEquipmentCategory.dumbbell,
        loadBasis: ExerciseLoadBasis.perDevice,
        deviceCount: 2,
        repetitionBasis: ExerciseRepetitionBasis.perSide,
        primaryMuscles: const ['biceps'],
      ),
    );
    await pumpPicker(tester, repo: repo);
    await tester.enterText(
      find.byKey(const ValueKey('exercise-search')),
      'Curl',
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/custom-exercise-library.png'),
    );
    await pumpPicker(tester, repo: repo, brightness: Brightness.dark);
    await tester.enterText(
      find.byKey(const ValueKey('exercise-search')),
      'Curl',
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/custom-exercise-library-dark.png'),
    );
  });

  testWidgets('goldens: hidden created notice light/dark/2x', (tester) async {
    Future<void> hideCreated({
      Brightness brightness = Brightness.light,
      double scale = 1,
      double width = 393,
      double height = 852,
    }) async {
      await pumpPicker(
        tester,
        repo: _Repo(),
        brightness: brightness,
        scale: scale,
        width: width,
        height: height,
      );
      await tester.tap(
        find.byKey(const ValueKey('exercise-select-bench_press')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('exercise-search')),
        'Bank',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Eigene Übung'));
      await tester.pumpAndSettle();
      await fillRequired(tester);
      await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
      await tester.pumpAndSettle();
    }

    await hideCreated();
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/custom-exercise-hidden.png'),
    );
    await hideCreated(brightness: Brightness.dark);
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/custom-exercise-hidden-dark.png'),
    );
    await hideCreated(scale: 2, width: 375, height: 1600);
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/custom-exercise-hidden-2x.png'),
    );
  });

  test(
    'count parser rejects fraction, sign and non-digits without stripping',
    () {
      expect(parseOpenBandPositiveCount('2'), 2);
      expect(parseOpenBandPositiveCount(' 15 '), 15);
      expect(parseOpenBandPositiveCount('1.5'), isNull);
      expect(parseOpenBandPositiveCount('-1'), isNull);
      expect(parseOpenBandPositiveCount('+1'), isNull);
      expect(parseOpenBandPositiveCount('0'), isNull);
      expect(parseOpenBandPositiveCount(''), isNull);
      expect(parseOpenBandPositiveCount('1e2'), isNull);
    },
  );

  testWidgets('typed and pasted fraction or negative stay and refuse apply', (
    tester,
  ) async {
    await pumpEditor(tester, repo: _Repo());
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-count')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settings-count-field')),
      '1.5',
    );
    await tester.pump();
    expect(find.text('1.5'), findsOneWidget);
    expect(find.text('15'), findsNothing);
    expect(
      tester
          .widget<OBAction>(find.widgetWithText(OBAction, 'Übernehmen'))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('settings-count-field')),
      '-1',
    );
    await tester.pump();
    expect(find.text('-1'), findsOneWidget);
    expect(
      tester
          .widget<OBAction>(find.widgetWithText(OBAction, 'Übernehmen'))
          .onPressed,
      isNull,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('count sheet uses 20+34 footer inset when keyboard is hidden', (
    tester,
  ) async {
    await pumpEditor(tester, repo: _Repo());
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-count')));
    await tester.pumpAndSettle();
    final action = tester.getRect(find.widgetWithText(OBAction, 'Übernehmen'));
    expect(tester.getSize(find.byType(MaterialApp)).height - action.bottom, 54);
  });

  testWidgets('muscle page matches paper title, roles, nine chips and reset', (
    tester,
  ) async {
    await pumpEditor(tester, repo: _Repo());
    await tester.tap(find.byKey(const ValueKey('custom-exercise-primary')));
    await tester.pumpAndSettle();
    expect(find.text('Muskelgruppen'), findsWidgets);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('custom-muscle-role')))
          .data,
      'Primär',
    );
    expect(
      find.byKey(const ValueKey('custom-muscle-forearms')),
      findsOneWidget,
    );
    expect(find.text('Unterarm'), findsOneWidget);
    expect(find.text('Zurücksetzen'), findsOneWidget);
    for (final id in kExerciseMuscleIds) {
      expect(find.byKey(ValueKey('custom-muscle-$id')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('custom-muscle-biceps')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zurücksetzen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OBSettingsValueRow>(
            find.byKey(const ValueKey('custom-exercise-primary')),
          )
          .value,
      '—',
    );
    await tester.tap(find.byKey(const ValueKey('custom-exercise-secondary')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('custom-muscle-role')))
          .data,
      'Sekundär',
    );
    expect(
      find.byKey(const ValueKey('custom-muscle-forearms')),
      findsOneWidget,
    );
  });

  testWidgets('initialMode only applies when the caller set it', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      repo: _Repo(),
      initialMode: ExerciseCaptureMode.time,
    );
    expect(
      tester
          .widget<OBSettingsValueRow>(
            find.byKey(const ValueKey('custom-exercise-mode')),
          )
          .value,
      'Haltezeit',
    );
    expect(find.byKey(const ValueKey('custom-exercise-reps')), findsNothing);
    await pumpEditor(tester, repo: _Repo());
    expect(
      tester
          .widget<OBSettingsValueRow>(
            find.byKey(const ValueKey('custom-exercise-mode')),
          )
          .value,
      'Auswählen',
    );
  });

  Future<void> selectPrimaryMuscles(
    WidgetTester tester,
    Iterable<String> ids,
  ) async {
    await tester.tap(find.byKey(const ValueKey('custom-exercise-primary')));
    await tester.pumpAndSettle();
    for (final id in ids) {
      await tester.tap(find.byKey(ValueKey('custom-muscle-$id')));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
  }

  testWidgets('375 2x multi-muscle values wrap without overflow', (
    tester,
  ) async {
    FlutterErrorDetails? overflow;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) overflow = details;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
    await pumpEditor(tester, repo: _Repo(), scale: 2, width: 375, height: 1600);
    await selectPrimaryMuscles(tester, const ['chest', 'back', 'shoulders']);
    expect(find.text('Brust, Rücken, Schultern'), findsOneWidget);
    expect(overflow, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '393 and 375 scale1 all nine muscles wrap without squeezing label',
    (tester) async {
      FlutterErrorDetails? overflow;
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) overflow = details;
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);
      final joined = [
        for (final id in kExerciseMuscleIds) exerciseMuscleLabel(id),
      ].join(', ');
      Future<void> check(double width) async {
        overflow = null;
        await pumpEditor(tester, repo: _Repo(), width: width);
        await selectPrimaryMuscles(tester, kExerciseMuscleIds);
        expect(find.text(joined), findsOneWidget);
        final row = tester.getRect(
          find.byKey(const ValueKey('custom-exercise-primary')),
        );
        final label = tester.getRect(
          find.descendant(
            of: find.byKey(const ValueKey('custom-exercise-primary')),
            matching: find.text('Primär'),
          ),
        );
        final value = tester.getRect(find.text(joined));
        expect(label.width, greaterThan(40));
        expect(value.right, lessThanOrEqualTo(row.right + 0.5));
        expect(value.left, greaterThanOrEqualTo(label.right));
        expect(overflow, isNull);
        expect(tester.takeException(), isNull);
      }

      await check(393);
      await check(375);
    },
  );

  testWidgets('failed save then invalid edit keeps save disabled', (
    tester,
  ) async {
    final repo = _Repo(failCreate: true);
    await pumpEditor(tester, repo: repo);
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(
      tester
          .widget<OBAction>(find.byKey(const ValueKey('custom-exercise-save')))
          .onPressed,
      isNotNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('custom-exercise-name')),
      '',
    );
    await tester.pump();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(
      tester
          .widget<OBAction>(find.byKey(const ValueKey('custom-exercise-save')))
          .onPressed,
      isNull,
    );
    expect(repo.created, hasLength(1));
  });

  testWidgets(
    'create then catalogue read failure keeps the entry and retries',
    (tester) async {
      final repo = _Repo();
      await pumpPicker(tester, repo: repo);
      repo.failRead = true;
      await tester.tap(find.byTooltip('Eigene Übung'));
      await tester.pumpAndSettle();
      await fillRequired(tester);
      await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
      await tester.pumpAndSettle();
      expect(find.text('Kurzhantel-Curl'), findsOneWidget);
      expect(find.text('Aktualisieren fehlgeschlagen'), findsOneWidget);
      expect(find.text('0 Übungen hinzufügen'), findsOneWidget);
      repo.failRead = true;
      await tester.tap(find.text('Erneut laden'));
      await tester.pumpAndSettle();
      expect(find.text('Kurzhantel-Curl'), findsOneWidget);
      expect(find.text('Aktualisieren fehlgeschlagen'), findsOneWidget);
      repo.failRead = false;
      await tester.tap(find.text('Erneut laden'));
      await tester.pumpAndSettle();
      expect(find.text('Kurzhantel-Curl'), findsOneWidget);
      expect(find.text('Aktualisieren fehlgeschlagen'), findsNothing);
      expect(find.text('0 Übungen hinzufügen'), findsOneWidget);
    },
  );

  testWidgets('goldens: mode, reps, muscles, time bodyweight', (tester) async {
    await pumpEditor(tester, repo: _Repo());
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-mode')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/custom-exercise-mode.png'),
    );
    await pumpEditor(tester, repo: _Repo(), brightness: Brightness.dark);
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-mode')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/custom-exercise-mode-dark.png'),
    );

    await pumpEditor(tester, repo: _Repo());
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-reps')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/custom-exercise-rep.png'),
    );
    await pumpEditor(tester, repo: _Repo(), brightness: Brightness.dark);
    await fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-reps')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/custom-exercise-rep-dark.png'),
    );

    await pumpEditor(tester, repo: _Repo());
    await tester.tap(find.byKey(const ValueKey('custom-exercise-primary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-muscle-biceps')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/custom-exercise-muscles.png'),
    );
    await pumpEditor(tester, repo: _Repo(), brightness: Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-secondary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-muscle-forearms')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/custom-exercise-muscles-dark.png'),
    );

    Future<void> fillTime(WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const ValueKey('custom-exercise-name')),
        'Wandsitz',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('custom-exercise-equipment')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('custom-exercise-equipment-bodyweight')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('custom-exercise-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('custom-exercise-mode-time')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('custom-exercise-load')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('custom-exercise-load-bodyweight')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('custom-exercise-primary')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('custom-muscle-legs')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      await unfocus(tester);
    }

    await pumpEditor(tester, repo: _Repo());
    await fillTime(tester);
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/custom-exercise-time.png'),
    );
    await pumpEditor(tester, repo: _Repo(), brightness: Brightness.dark);
    await fillTime(tester);
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/custom-exercise-time-dark.png'),
    );
  });

  ExerciseCatalogueEntry completeCopySource({
    String id = 'custom-curl',
    String label = 'Kurzhantel-Curl',
    String? equipmentRef = 'db-curl',
  }) => ExerciseCatalogueEntry(
    id: id,
    label: label,
    mode: ExerciseCaptureMode.repetitions,
    equipment: ExerciseEquipmentCategory.dumbbell,
    equipmentRef: equipmentRef,
    loadBasis: ExerciseLoadBasis.perDevice,
    deviceCount: 2,
    repetitionBasis: ExerciseRepetitionBasis.perSide,
    primaryMuscles: const ['biceps', 'unknown-muscle', 'biceps'],
    secondaryMuscles: const ['forearms', 'biceps', 'not-a-muscle'],
    source: ExerciseDefinitionSource.stored,
    version: 4,
    loadIncrement: 2,
    aliases: const ['Curl'],
    retained: const {
      'custom': 1,
      'source': 'custom',
      'copiedFrom': 'import-x',
      'loadBasis': 'band',
    },
  );

  Future<void> fillCopyLoadAndReps(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('custom-exercise-load')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-load-total')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-reps')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-reps-total')));
    await tester.pumpAndSettle();
  }

  test('mapper copies known typed fields and drops unknown retained', () {
    final curl = completeCopySource();
    final seed = seedCopiedCustomExercise(curl);
    expect(seed.label, 'Kurzhantel-Curl · Kopie');
    expect(seed.mode, ExerciseCaptureMode.repetitions);
    expect(seed.equipment, ExerciseEquipmentCategory.dumbbell);
    expect(seed.equipmentRef, 'db-curl');
    expect(seed.loadBasis, ExerciseLoadBasis.perDevice);
    expect(seed.deviceCount, 2);
    expect(seed.repetitionBasis, ExerciseRepetitionBasis.perSide);
    expect(seed.primaryMuscles, ['biceps']);
    expect(seed.secondaryMuscles, ['forearms']);
    expect(seed.copiedFrom, 'custom-curl');

    final bench = exercisePresetById('bench_press')!.asEntry;
    final preset = seedCopiedCustomExercise(bench);
    expect(preset.label, 'Bankdrücken · Kopie');
    expect(preset.mode, ExerciseCaptureMode.repetitions);
    expect(preset.equipment, ExerciseEquipmentCategory.barbell);
    expect(preset.equipmentRef, isNull);
    expect(preset.loadBasis, isNull);
    expect(preset.deviceCount, isNull);
    expect(preset.repetitionBasis, isNull);
    expect(preset.primaryMuscles, ['chest']);
    expect(preset.secondaryMuscles, ['triceps', 'shoulders']);
    expect(preset.copiedFrom, 'bench_press');

    final bare = seedCopiedCustomExercise(
      exercisePresetById('hip_thrust')!.asEntry,
    );
    expect(bare.equipment, isNull);
    expect(bare.loadBasis, isNull);
    expect(bare.copiedFrom, 'hip_thrust');

    final time = seedCopiedCustomExercise(
      ExerciseCatalogueEntry(
        id: 'hold',
        label: '  ',
        mode: ExerciseCaptureMode.time,
        equipment: ExerciseEquipmentCategory.bodyweight,
        loadBasis: ExerciseLoadBasis.total,
        deviceCount: 2,
        repetitionBasis: ExerciseRepetitionBasis.perSide,
        primaryMuscles: const ['core'],
        source: ExerciseDefinitionSource.stored,
      ),
    );
    expect(time.label, isEmpty);
    expect(time.deviceCount, isNull);
    expect(time.repetitionBasis, isNull);
    expect(time.loadBasis, ExerciseLoadBasis.total);

    final unknown = seedCopiedCustomExercise(
      ExerciseCatalogueEntry(
        id: 'row',
        label: 'Rudern',
        equipment: ExerciseEquipmentCategory.machine,
        deviceCount: 0,
        source: ExerciseDefinitionSource.stored,
        retained: const {
          'loadBasis': 'band',
          'copiedFrom': 'import-x',
          'equipment': 'kettlebell',
        },
      ),
    );
    expect(unknown.mode, isNull);
    expect(unknown.loadBasis, isNull);
    expect(unknown.deviceCount, isNull);
    expect(unknown.copiedFrom, 'row');
    expect(unknown.equipment, ExerciseEquipmentCategory.machine);
  });

  testWidgets('copy roundtrip stays unselected and stores copiedFrom', (
    tester,
  ) async {
    final repo = _Repo();
    await pumpPicker(tester, repo: repo);
    await tester.tap(find.byKey(const ValueKey('exercise-open-bench_press')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Kopieren'), findsOneWidget);
    await tester.tap(find.byTooltip('Kopieren'));
    await tester.pumpAndSettle();
    expect(find.text('Eigene Übung'), findsWidgets);
    expect(find.text('Bankdrücken · Kopie'), findsOneWidget);
    expect(
      tester
          .widget<OBAction>(find.byKey(const ValueKey('custom-exercise-save')))
          .onPressed,
      isNull,
    );
    await fillCopyLoadAndReps(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandExerciseDefinitionEditor), findsNothing);
    expect(find.text('Übung'), findsNothing);
    expect(find.text('Bankdrücken · Kopie'), findsOneWidget);
    expect(find.text('0 Übungen hinzufügen'), findsOneWidget);
    expect(repo.created, hasLength(1));
    expect(repo.created.single.id, isNot('bench_press'));
    expect(repo.created.single.retained['copiedFrom'], 'bench_press');
    expect(
      (await repo.readExerciseCatalogue()).byId('bench_press')!.source,
      ExerciseDefinitionSource.preset,
    );
    final add = tester.widget<OBAction>(
      find.widgetWithText(OBAction, '0 Übungen hinzufügen'),
    );
    expect(add.onPressed, isNull);
  });

  testWidgets('copy cancel stays on source detail and writes nothing', (
    tester,
  ) async {
    final repo = _Repo();
    await pumpPicker(tester, repo: repo);
    await tester.tap(find.byKey(const ValueKey('exercise-open-bench_press')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kopieren'));
    await tester.pumpAndSettle();
    await fillCopyLoadAndReps(tester);
    await tester.tap(find.byTooltip('Zurück').last);
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandExerciseDefinitionEditor), findsNothing);
    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(find.text('Auswählen'), findsOneWidget);
    expect(repo.created, isEmpty);
    await tester.tap(find.byTooltip('Zurück').last);
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandExercisePicker), findsOneWidget);
    expect(find.text('0 Übungen hinzufügen'), findsOneWidget);
  });

  testWidgets('source already selected stays selected after copy', (
    tester,
  ) async {
    final repo = _Repo();
    await pumpPicker(tester, repo: repo);
    await tester.tap(find.byKey(const ValueKey('exercise-select-bench_press')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('exercise-open-bench_press')));
    await tester.pumpAndSettle();
    expect(find.text('Auswahl entfernen'), findsOneWidget);
    await tester.tap(find.byTooltip('Kopieren'));
    await tester.pumpAndSettle();
    await fillCopyLoadAndReps(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    expect(find.text('1 Übung hinzufügen'), findsOneWidget);
    expect(find.text('Bankdrücken · Kopie'), findsOneWidget);
    final copyId = repo.created.single.id!;
    final sourceSelect = tester.widget<IconButton>(
      find.byKey(const ValueKey('exercise-select-bench_press')),
    );
    final copySelect = tester.widget<IconButton>(
      find.byKey(ValueKey('exercise-select-$copyId')),
    );
    expect((sourceSelect.icon as Icon).icon, LucideIcons.check);
    expect((copySelect.icon as Icon).icon, LucideIcons.plus);
  });

  testWidgets('two copies allocate distinct ids; same form retries one id', (
    tester,
  ) async {
    final repo = _Repo();
    await pumpPicker(tester, repo: repo);
    Future<void> copyOnce() async {
      await tester.tap(find.byKey(const ValueKey('exercise-open-bench_press')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Kopieren'));
      await tester.pumpAndSettle();
      await fillCopyLoadAndReps(tester);
      await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
      await tester.pumpAndSettle();
    }

    await copyOnce();
    await copyOnce();
    expect(repo.created, hasLength(2));
    expect(repo.created[0].id, isNot(repo.created[1].id));
    expect(repo.created[0].retained['copiedFrom'], 'bench_press');
    expect(repo.created[1].retained['copiedFrom'], 'bench_press');

    final retry = _Repo(failCreate: true);
    await pumpEditor(
      tester,
      repo: retry,
      copyFrom: exercisePresetById('bench_press')!.asEntry,
    );
    await fillCopyLoadAndReps(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Bankdrücken · Kopie'), findsOneWidget);
    retry.failCreate = false;
    await tester.tap(find.text('Erneut speichern'));
    await tester.pumpAndSettle();
    expect(retry.created, hasLength(2));
    expect(retry.created.first.id, retry.created.last.id);
    expect(retry.created.last.retained['copiedFrom'], 'bench_press');

    final delayed = _Repo(createDelay: const Duration(milliseconds: 200));
    await pumpEditor(
      tester,
      repo: delayed,
      copyFrom: exercisePresetById('bench_press')!.asEntry,
    );
    await fillCopyLoadAndReps(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pump();
    expect(delayed.created, hasLength(1));
    await tester.pumpAndSettle();
    expect(delayed.created, hasLength(1));
  });

  testWidgets('copied equipmentRef clears after explicit category change', (
    tester,
  ) async {
    final repo = _Repo();
    await pumpEditor(tester, repo: repo, copyFrom: completeCopySource());
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    expect(repo.created, hasLength(1));
    expect(repo.created.single.equipmentRef, 'db-curl');
    expect(repo.created.single.retained.keys, ['copiedFrom']);
    expect(repo.created.single.retained['copiedFrom'], 'custom-curl');

    final changed = _Repo();
    await pumpEditor(tester, repo: changed, copyFrom: completeCopySource());
    await tester.tap(find.byKey(const ValueKey('custom-exercise-equipment')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('custom-exercise-equipment-barbell')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    expect(changed.created.single.equipment, ExerciseEquipmentCategory.barbell);
    expect(changed.created.single.equipmentRef, isNull);
    expect(changed.created.single.retained['copiedFrom'], 'custom-curl');
  });

  testWidgets('copy save then catalogue read failure keeps the entry', (
    tester,
  ) async {
    final repo = _Repo();
    await pumpPicker(tester, repo: repo);
    repo.failRead = true;
    await tester.tap(find.byKey(const ValueKey('exercise-open-bench_press')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kopieren'));
    await tester.pumpAndSettle();
    await fillCopyLoadAndReps(tester);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    expect(find.text('Bankdrücken · Kopie'), findsOneWidget);
    expect(find.text('Aktualisieren fehlgeschlagen'), findsOneWidget);
    expect(find.text('0 Übungen hinzufügen'), findsOneWidget);
    repo.failRead = false;
    await tester.tap(find.text('Erneut laden'));
    await tester.pumpAndSettle();
    expect(find.text('Bankdrücken · Kopie'), findsOneWidget);
    expect(find.text('Aktualisieren fehlgeschlagen'), findsNothing);
  });

  testWidgets('copy hidden by query recovers through Anzeigen', (tester) async {
    final repo = _Repo();
    await pumpPicker(tester, repo: repo);
    await tester.enterText(
      find.byKey(const ValueKey('exercise-search')),
      'Bank',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('exercise-open-bench_press')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kopieren'));
    await tester.pumpAndSettle();
    await fillCopyLoadAndReps(tester);
    await tester.enterText(
      find.byKey(const ValueKey('custom-exercise-name')),
      'Wandsitz',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('custom-exercise-saved')), findsOneWidget);
    expect(find.text('Anzeigen'), findsOneWidget);
    expect(find.text('1 Übung hinzufügen'), findsNothing);
    expect(find.text('0 Übungen hinzufügen'), findsOneWidget);
    await tester.tap(find.text('Anzeigen'));
    await tester.pumpAndSettle();
    expect(find.text('Wandsitz'), findsWidgets);
    expect(find.byKey(const ValueKey('custom-exercise-saved')), findsNothing);
  });

  testWidgets('goldens: copy source, preset, custom, retry, large, library', (
    tester,
  ) async {
    await pumpPicker(tester, repo: _Repo());
    await tester.tap(find.byKey(const ValueKey('exercise-open-bench_press')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/exercise-copy-source.png'),
    );
    await pumpPicker(tester, repo: _Repo(), brightness: Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('exercise-open-bench_press')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/exercise-copy-source-dark.png'),
    );

    await pumpEditor(
      tester,
      repo: _Repo(),
      copyFrom: exercisePresetById('bench_press')!.asEntry,
    );
    await unfocus(tester);
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/exercise-copy-preset.png'),
    );
    await pumpEditor(
      tester,
      repo: _Repo(),
      copyFrom: exercisePresetById('bench_press')!.asEntry,
      brightness: Brightness.dark,
    );
    await unfocus(tester);
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/exercise-copy-preset-dark.png'),
    );

    final custom = completeCopySource();
    await pumpEditor(tester, repo: _Repo(), copyFrom: custom);
    await unfocus(tester);
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/exercise-copy-custom.png'),
    );
    await pumpEditor(
      tester,
      repo: _Repo(),
      copyFrom: custom,
      brightness: Brightness.dark,
    );
    await unfocus(tester);
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/exercise-copy-custom-dark.png'),
    );

    await pumpEditor(tester, repo: _Repo(failCreate: true), copyFrom: custom);
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    await unfocus(tester);
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/exercise-copy-retry.png'),
    );
    await pumpEditor(
      tester,
      repo: _Repo(failCreate: true),
      copyFrom: custom,
      brightness: Brightness.dark,
    );
    await tester.tap(find.byKey(const ValueKey('custom-exercise-save')));
    await tester.pumpAndSettle();
    await unfocus(tester);
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/exercise-copy-retry-dark.png'),
    );

    await pumpEditor(
      tester,
      repo: _Repo(),
      copyFrom: completeCopySource(label: 'Curl'),
      scale: 2,
      width: 375,
      height: 1600,
    );
    await unfocus(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('custom-exercise-save')),
    );
    await expectLater(
      find.byType(OpenBandExerciseDefinitionEditor),
      matchesGoldenFile('openband_goldens/exercise-copy-375-2x.png'),
    );
  });

  testWidgets('goldens: copy library query Curl unselected', (tester) async {
    final library = _Repo(
      catalogue: ExerciseCatalogue(
        entries: [
          customCurl(),
          ExerciseCatalogueEntry(
            id: 'custom-curl-copy',
            label: 'Kurzhantel-Curl · Kopie',
            mode: ExerciseCaptureMode.repetitions,
            equipment: ExerciseEquipmentCategory.dumbbell,
            loadBasis: ExerciseLoadBasis.perDevice,
            deviceCount: 2,
            repetitionBasis: ExerciseRepetitionBasis.perSide,
            primaryMuscles: const ['biceps'],
            secondaryMuscles: const ['forearms'],
            source: ExerciseDefinitionSource.stored,
            version: 1,
            retained: const {
              'custom': 1,
              'source': 'custom',
              'copiedFrom': 'custom-curl',
            },
          ),
        ],
      ),
    );
    await pumpPicker(tester, repo: library);
    await tester.enterText(
      find.byKey(const ValueKey('exercise-search')),
      'Curl',
    );
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/exercise-copy-library.png'),
    );
    await pumpPicker(tester, repo: library, brightness: Brightness.dark);
    await tester.enterText(
      find.byKey(const ValueKey('exercise-search')),
      'Curl',
    );
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(OpenBandExercisePicker),
      matchesGoldenFile('openband_goldens/exercise-copy-library-dark.png'),
    );
  });
}
