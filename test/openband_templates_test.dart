import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/strength_live.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/template_editor.dart';
import 'package:openstrap_edge/openband/templates.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/openband/training.dart';

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

  late SyntheticOpenBandRepository repo;
  late OpenBandController controller;

  Future<WorkoutTemplate> active(String id) async =>
      (await repo.readTemplates()).firstWhere((t) => t.id == id);

  setUp(() {
    repo = SyntheticOpenBandRepository.fromMaps(
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
    controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 18, 9, 41),
    );
  });
  tearDown(() => controller.dispose());

  Future<void> pumpList(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    Future<void> Function(WorkoutTemplate)? onStart,
    Future<void> Function(WorkoutTemplate?)? onEdit,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, width == 375 ? 812 : 852);
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
        home: OpenBandTemplates(
          key: UniqueKey(),
          repository: repo,
          synthetic: true,
          onStartTemplate: onStart ?? (_) async {},
          onEditTemplate:
              onEdit ??
              (t) async {
                await Navigator.of(
                  tester.element(find.byType(OpenBandTemplates)),
                ).push(
                  MaterialPageRoute<WorkoutTemplate>(
                    builder: (_) =>
                        OpenBandTemplateEditor(repository: repo, template: t),
                  ),
                );
              },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('copy allocates independent uuid identities and a Kopie name', () {
    final source = WorkoutTemplate(
      id: 'tpl-src',
      name: 'Ganzkörper A',
      version: 4,
      exercises: [
        PlannedExercise(
          id: 'ex-1',
          exerciseKey: 'bench_press',
          name: 'Bankdrücken',
          sets: [
            PlannedSet(id: 'set-1', reps: 8, loadKg: 40),
            PlannedSet(id: 'set-2', reps: 8, loadKg: 40),
          ],
        ),
      ],
      updatedAt: DateTime(2026, 9, 1),
    );
    final copy = copyWorkoutTemplate(source, at: DateTime(2026, 9, 19));
    final other = copyWorkoutTemplate(source, at: DateTime(2026, 9, 19));
    expect(copy.id, isNot(source.id));
    expect(copy.id, isNot(other.id));
    expect(copy.name, 'Ganzkörper A · Kopie');
    expect(copy.version, 0);
    expect(copy.exercises.single.id, isNot(source.exercises.single.id));
    expect(copy.exercises.single.id, isNot(other.exercises.single.id));
    expect(copy.exercises.single.exerciseKey, 'bench_press');
    expect(copy.exercises.single.sets.map((s) => s.id).toSet().length, 2);
    expect(
      copy.exercises.single.sets.map((s) => s.id).toSet().intersection({
        'set-1',
        'set-2',
        other.exercises.single.sets.first.id,
      }),
      isEmpty,
    );
    expect(source.id, 'tpl-src');
    expect(source.exercises.single.id, 'ex-1');
    expect(source.exercises.single.sets.map((s) => s.id), ['set-1', 'set-2']);
  });

  test(
    'synthetic pin rejects archived or missing ids and keeps the pin',
    () async {
      await repo.pinTemplate('tpl-ganzkoerper-a');
      await repo.archiveTemplate('tpl-ganzkoerper-b');
      await expectLater(
        repo.pinTemplate('tpl-ganzkoerper-b'),
        throwsA(isA<StateError>()),
      );
      expect(await repo.readPinnedTemplateId(), 'tpl-ganzkoerper-a');
      await expectLater(
        repo.pinTemplate('tpl-gone'),
        throwsA(isA<StateError>()),
      );
      expect(await repo.readPinnedTemplateId(), 'tpl-ganzkoerper-a');
      await repo.pinTemplate(null);
      expect(await repo.readPinnedTemplateId(), isNull);
    },
  );

  test('featured template prefers a still-active pin', () async {
    final plans = await repo.readTemplates();
    expect(
      featuredTemplate(plans, 'tpl-ganzkoerper-b')?.id,
      'tpl-ganzkoerper-b',
    );
    expect(featuredTemplate(plans, 'gone')?.id, 'tpl-ganzkoerper-a');
    expect(featuredTemplate(const [], 'tpl-ganzkoerper-a'), isNull);
  });

  testWidgets('list renders light, dark, empty and error', (tester) async {
    await pumpList(tester);
    expect(find.text('Vorlagen'), findsOneWidget);
    expect(find.text('Ganzkörper A'), findsOneWidget);
    expect(find.text('Ganzkörper B'), findsOneWidget);
    expect(find.text('4 Übungen'), findsOneWidget);
    expect(find.text('5 Übungen'), findsOneWidget);
    expect(find.text('Als Nächstes'), findsNothing);
    expect(find.text('Arbeitssätze'), findsNothing);
    final name1x = tester.getRect(find.text('Ganzkörper A'));
    final start1x = tester.getRect(find.byType(FilledButton).first);
    expect(name1x.center.dy, closeTo(start1x.center.dy, 12));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/templates-light.png'),
    );
    await pumpList(tester, brightness: Brightness.dark);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/templates-dark.png'),
    );

    repo.clearTemplates();
    await pumpList(tester);
    expect(find.text('Keine Vorlagen'), findsOneWidget);
    expect(find.text('Vorlage erstellen'), findsOneWidget);
    expect(find.text('Ganzkörper A'), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/templates-empty.png'),
    );

    repo.failTemplateRead = true;
    await pumpList(tester);
    expect(find.text('Vorlagen konnten nicht geladen werden.'), findsOneWidget);
    expect(find.text('Keine Vorlagen'), findsNothing);
    expect(find.text('Ganzkörper A'), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/templates-error.png'),
    );
  }, tags: const ['golden']);

  testWidgets(
    'create opens the existing editor and list shows the saved plan',
    (tester) async {
      await pumpList(tester);
      await tester.tap(find.byTooltip('Neue Vorlage'));
      await tester.pumpAndSettle();
      expect(find.byType(OpenBandTemplateEditor), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Oberkörper');
      await tester.tap(find.text('Übung hinzufügen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bibliothek'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Auswahl Bankdrücken'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 Übung hinzufügen'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'Wdh.',
        ),
        '6',
      );
      await tester.tap(find.text('Vorlage speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Oberkörper'), findsOneWidget);
      expect(find.text('Ganzkörper A'), findsOneWidget);
      expect(find.textContaining('gespeichert'), findsNothing);
    },
  );

  testWidgets('edit, copy, pin, unpin and archive update the list', (
    tester,
  ) async {
    await pumpList(tester);
    await tester.tap(find.byTooltip('Aktionen').first);
    await tester.pumpAndSettle();
    expect(find.text('Bearbeiten'), findsOneWidget);
    expect(find.text('Duplizieren'), findsOneWidget);
    expect(find.text('Anheften'), findsOneWidget);
    expect(find.text('Archivieren'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/templates-menu.png'),
    );
    await pumpList(tester, brightness: Brightness.dark);
    await tester.tap(find.byTooltip('Aktionen').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/templates-menu-dark.png'),
    );

    await pumpList(tester);
    await tester.tap(find.byTooltip('Aktionen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.text('VORLAGE BEARBEITEN'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Ganzkörper A+');
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Ganzkörper A+'), findsOneWidget);

    await tester.tap(find.byTooltip('Aktionen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplizieren'));
    await tester.pumpAndSettle();
    expect(find.text('Ganzkörper A+'), findsOneWidget);
    expect(find.text('Ganzkörper A+ · Kopie'), findsOneWidget);
    expect(find.textContaining('Kopie erstellt'), findsNothing);
    final afterCopy = await repo.readTemplates();
    expect(afterCopy.length, 3);
    expect(
      afterCopy.map((t) => t.id).toSet().length,
      3,
      reason: 'copy has its own plan id',
    );
    final ids = afterCopy.expand((t) => t.exercises.map((e) => e.id)).toSet();
    expect(
      ids.length,
      afterCopy.fold<int>(0, (n, t) => n + t.exercises.length),
    );

    await tester.tap(find.byTooltip('Aktionen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anheften'));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.pin), findsOneWidget);
    expect(await repo.readPinnedTemplateId(), afterCopy.first.id);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/templates-pinned.png'),
    );

    await tester.tap(find.byTooltip('Aktionen').first);
    await tester.pumpAndSettle();
    expect(find.text('Nicht mehr anheften'), findsOneWidget);
    await tester.tap(find.text('Nicht mehr anheften'));
    await tester.pumpAndSettle();
    expect(await repo.readPinnedTemplateId(), isNull);

    await tester.tap(find.byTooltip('Aktionen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archivieren'));
    await tester.pumpAndSettle();
    expect(find.text('Ganzkörper A+'), findsOneWidget);
    expect((await repo.readTemplates()).length, 2);
  }, tags: const ['golden']);

  testWidgets('write failures stay retryable and keep the list', (
    tester,
  ) async {
    await pumpList(tester);
    repo.failTemplateWrite = true;
    await tester.tap(find.byTooltip('Aktionen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplizieren'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Ganzkörper A'), findsOneWidget);
    expect(find.text('Ganzkörper B'), findsOneWidget);
    expect((await repo.readTemplates()).length, 2);

    repo.failTemplateWrite = false;
    repo.failPin = true;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aktionen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anheften'));
    await tester.pumpAndSettle();
    expect(find.text('Anheften fehlgeschlagen'), findsOneWidget);
    expect(find.text('Ganzkörper A'), findsOneWidget);

    repo.failPin = false;
    repo.failTemplateWrite = true;
    await tester.tap(find.byTooltip('Aktionen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archivieren'));
    await tester.pumpAndSettle();
    expect(find.text('Archivieren fehlgeschlagen'), findsOneWidget);
    expect((await repo.readTemplates()).length, 2);
  });

  testWidgets('rapid start taps fire once and honor an active session', (
    tester,
  ) async {
    final gate = Completer<void>();
    var starts = 0;
    await pumpList(
      tester,
      onStart: (t) async {
        starts++;
        await gate.future;
      },
    );
    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
    expect(starts, 1);
    gate.complete();
    await tester.pumpAndSettle();

    final a = await active('tpl-ganzkoerper-a');
    await repo.startStrengthSession(a);
    await expectLater(
      repo.startStrengthSession(a),
      throwsA(isA<WorkoutBusy>()),
    );
  });

  testWidgets('start reaches the existing live UI', (tester) async {
    await pumpList(
      tester,
      onStart: (t) async {
        await Navigator.of(tester.element(find.byType(OpenBandTemplates))).push(
          MaterialPageRoute<void>(
            builder: (_) => OpenBandStrengthLive(repository: repo, template: t),
          ),
        );
      },
    );
    await tester.tap(find.text('Starten').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(OpenBandStrengthLive), findsOneWidget);
    expect(find.text('Bankdrücken'), findsOneWidget);
  });

  testWidgets('duplicating does not rewrite the source plan', (tester) async {
    final original = await active('tpl-ganzkoerper-a');
    await pumpList(tester);
    await tester.tap(find.byTooltip('Aktionen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplizieren'));
    await tester.pumpAndSettle();
    final source = await active('tpl-ganzkoerper-a');
    expect(
      source.exercises.map((e) => e.id),
      original.exercises.map((e) => e.id),
    );
    expect(source.name, 'Ganzkörper A');
    expect(find.text('Ganzkörper A · Kopie'), findsOneWidget);
  });

  testWidgets('2x text at 375 keeps full words above 44pt actions', (
    tester,
  ) async {
    final source = await active('tpl-ganzkoerper-a');
    await repo.saveTemplate(
      WorkoutTemplate(
        id: 'tpl-long',
        name: 'Ganzkörper Hypertrophy',
        version: 0,
        exercises: source.exercises,
        updatedAt: DateTime(2026, 9, 19),
      ),
    );
    await pumpList(tester, scale: 2, width: 375);
    expect(find.text('Ganzkörper Hypertrophy'), findsOneWidget);
    expect(find.text('Ganzkörper A'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final name = tester.getRect(find.text('Ganzkörper Hypertrophy'));
    final short = tester.getRect(find.text('Ganzkörper A'));
    final start = tester.getRect(find.byType(FilledButton).first);
    final startA = tester.getRect(find.byType(FilledButton).at(1));
    final more = tester.getRect(find.byTooltip('Aktionen').first);
    expect(find.text('Starten'), findsNWidgets(3));
    expect(name.overlaps(start), isFalse);
    expect(name.bottom, lessThanOrEqualTo(start.top + 2));
    expect(short.overlaps(startA), isFalse);
    expect(short.bottom, lessThanOrEqualTo(startA.top + 2));
    expect(start.height, greaterThanOrEqualTo(44));
    expect(more.width, greaterThanOrEqualTo(44));
    expect(more.height, greaterThanOrEqualTo(44));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('openband_goldens/templates-2x.png'),
    );
    await tester.tap(find.byTooltip('Aktionen').first);
    await tester.pumpAndSettle();
    expect(find.text('Bearbeiten'), findsOneWidget);
    expect(find.text('Duplizieren'), findsOneWidget);
    expect(find.text('Anheften'), findsOneWidget);
    expect(find.text('Archivieren'), findsOneWidget);
  }, tags: const ['golden']);

  testWidgets('hub shows the pin when valid, otherwise the newest plan', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await repo.pinTemplate('tpl-ganzkoerper-b');
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
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
        home: Scaffold(
          body: OpenBandTraining(
            controller: controller,
            onStart: (_) {},
            onStartTemplate: (_) async {},
            onOpenTemplates: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ganzkörper B'), findsOneWidget);
    expect(find.byIcon(LucideIcons.pin), findsOneWidget);
    expect(find.text('Als Nächstes'), findsNothing);
    await repo.archiveTemplate('tpl-ganzkoerper-b');
    controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Ganzkörper B'), findsNothing);
    expect(find.text('Ganzkörper A'), findsOneWidget);
    expect(await repo.readPinnedTemplateId(), isNull);
  });

  testWidgets('a failed pin read is a retryable load error', (tester) async {
    await repo.pinTemplate('tpl-ganzkoerper-b');
    repo.failPinRead = true;
    await pumpList(tester);
    expect(find.text('Vorlagen konnten nicht geladen werden.'), findsOneWidget);
    expect(find.text('Erneut laden'), findsOneWidget);
    expect(find.text('Ganzkörper A'), findsNothing);
    expect(find.text('Ganzkörper B'), findsNothing);
    expect(find.byIcon(LucideIcons.pin), findsNothing);

    repo.failPinRead = false;
    await tester.tap(find.text('Erneut laden'));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.pin), findsOneWidget);
    expect(find.text('Ganzkörper B'), findsOneWidget);

    repo.failPinRead = true;
    await tester.tap(find.byTooltip('Aktionen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplizieren'));
    await tester.pumpAndSettle();
    expect(find.text('Vorlagen konnten nicht geladen werden.'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('Ganzkörper B'), findsOneWidget);
    expect(find.byIcon(LucideIcons.pin), findsOneWidget);

    repo.failPinRead = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('Vorlagen konnten nicht geladen werden.'), findsNothing);
    expect(find.byIcon(LucideIcons.pin), findsOneWidget);
    expect(find.text('Ganzkörper B'), findsOneWidget);
  });

  testWidgets('hub pin-read failure is retryable and recovers the pin', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await repo.pinTemplate('tpl-ganzkoerper-b');
    repo.failPinRead = true;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
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
        home: Scaffold(
          body: OpenBandTraining(
            controller: controller,
            onStartTemplate: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Vorlagen konnten nicht geladen werden.'), findsOneWidget);
    expect(find.text('Erneut laden'), findsOneWidget);
    expect(find.text('Ganzkörper A'), findsNothing);
    expect(find.text('Ganzkörper B'), findsNothing);
    expect(find.byIcon(LucideIcons.pin), findsNothing);

    repo.failPinRead = false;
    await tester.tap(find.text('Erneut laden'));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.pin), findsOneWidget);
    expect(find.text('Ganzkörper B'), findsOneWidget);

    repo.failPinRead = true;
    controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Vorlagen konnten nicht geladen werden.'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('Ganzkörper B'), findsOneWidget);
    expect(find.byIcon(LucideIcons.pin), findsOneWidget);

    repo.failPinRead = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('Vorlagen konnten nicht geladen werden.'), findsNothing);
    expect(find.byIcon(LucideIcons.pin), findsOneWidget);
    expect(find.text('Ganzkörper B'), findsOneWidget);
  });

  Future<void> pumpHubToList(
    WidgetTester tester, {
    required double width,
    required double height,
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
        theme: openBandTheme(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: OpenBandTraining(
            controller: controller,
            onStart: (_) {},
            onStartTemplate: (_) async {},
            onOpenTemplates: () {
              Navigator.of(tester.element(find.byType(OpenBandTraining))).push(
                MaterialPageRoute<void>(
                  builder: (_) => OpenBandTemplates(
                    repository: repo,
                    synthetic: true,
                    onStartTemplate: (_) async {},
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hub then list at 2x does not overflow on 393 or 375', (
    tester,
  ) async {
    for (final size in const [Size(393, 852), Size(375, 812)]) {
      await pumpHubToList(tester, width: size.width, height: size.height);
      expect(tester.takeException(), isNull, reason: 'hub ${size.width}');
      expect(find.byType(OBTemplateRow), findsOneWidget);
      await tester.tap(find.byTooltip('Vorlagen'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'list ${size.width}');
      expect(find.text('Vorlagen'), findsOneWidget);
      expect(find.text('Ganzkörper A'), findsOneWidget);
      expect(find.text('Starten'), findsWidgets);
    }
  });
}
