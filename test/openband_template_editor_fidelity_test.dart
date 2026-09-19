import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/template_editor.dart';
import 'package:openstrap_edge/openband/theme.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('de_DE'));

  late SyntheticOpenBandRepository repo;

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
  });

  WorkoutTemplate mixed({DateTime? updatedAt}) => WorkoutTemplate(
    id: 'tpl-mixed',
    name: 'Gemischt',
    version: 3,
    exercises: [
      PlannedExercise(
        id: 'ex-pull',
        exerciseKey: 'pull_up',
        name: 'Klimmzug',
        note: 'volle Amplitude',
        sets: [
          PlannedSet(id: 'set-wu', type: 'warmup', reps: 5, restSec: 45),
          PlannedSet(
            id: 'set-w1',
            type: 'work',
            reps: 8,
            loadKg: 20,
            restSec: 120,
          ),
          PlannedSet(
            id: 'set-w2',
            type: 'work',
            reps: 8,
            loadKg: 20,
            restSec: 120,
          ),
        ],
      ),
      PlannedExercise(
        id: 'ex-plank',
        exerciseKey: 'plank',
        name: 'Plank',
        note: 'Brett',
        sets: [PlannedSet(id: 'set-plank', seconds: 40, restSec: 60)],
      ),
      PlannedExercise(
        id: 'ex-chin',
        exerciseKey: 'chin_up',
        name: 'Klimmzug',
        sets: [PlannedSet(id: 'set-chin', reps: 6, restSec: 75)],
      ),
    ],
    updatedAt: updatedAt ?? DateTime(2026, 9, 1),
  );

  WorkoutTemplate precise() => WorkoutTemplate(
    id: 'tpl-precise',
    name: 'Präzise',
    version: 1,
    exercises: [
      PlannedExercise(
        id: 'ex-row',
        exerciseKey: 'row',
        name: 'Rudern',
        sets: [
          PlannedSet(id: 'set-a', reps: 8, loadKg: 2.75, restSec: 90),
          PlannedSet(id: 'set-b', reps: 8, loadKg: 62.55, restSec: 90),
          PlannedSet(id: 'set-c', reps: 8, restSec: 90),
        ],
      ),
    ],
    updatedAt: DateTime(2026, 9, 1),
  );

  Future<WorkoutTemplate> seed() => repo.saveTemplate(mixed());

  Future<WorkoutTemplate> stored(String id) async =>
      (await repo.readTemplates()).firstWhere((t) => t.id == id);

  Future<void> openEditor(
    WidgetTester tester, {
    WorkoutTemplate? template,
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
        theme: openBandTheme(Brightness.light),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute<WorkoutTemplate>(
                      builder: (_) => OpenBandTemplateEditor(
                        repository: repo,
                        template: template,
                      ),
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
  }

  testWidgets('name and load edits keep notes, rest, type and identities', (
    tester,
  ) async {
    final original = await seed();
    await openEditor(tester, template: original);
    await tester.enterText(find.widgetWithText(TextField, 'Gemischt'), 'Pull');
    await tester.enterText(
      find.widgetWithText(TextField, '20,0').first,
      '22,5',
    );
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();

    final saved = await stored('tpl-mixed');
    expect(saved.name, 'Pull');
    expect(saved.version, original.version + 1);
    expect(saved.exercises.map((e) => e.id), [
      'ex-pull',
      'ex-plank',
      'ex-chin',
    ]);
    expect(saved.exercises.map((e) => e.exerciseKey), [
      'pull_up',
      'plank',
      'chin_up',
    ]);
    expect(saved.exercises.map((e) => e.name), [
      'Klimmzug',
      'Plank',
      'Klimmzug',
    ]);
    expect(saved.exercises.map((e) => e.note), [
      'volle Amplitude',
      'Brett',
      '',
    ]);
    expect(saved.exercises.first.sets.map((s) => s.id), [
      'set-wu',
      'set-w1',
      'set-w2',
    ]);
    expect(saved.exercises.first.sets.map((s) => s.type), [
      'warmup',
      'work',
      'work',
    ]);
    expect(saved.exercises.first.sets.map((s) => s.restSec), [45, 120, 120]);
    expect(saved.exercises.first.sets.map((s) => s.loadKg), [null, 22.5, 20]);
    expect(saved.exercises[1].sets.single.seconds, 40);
    expect(saved.exercises[1].sets.single.restSec, 60);
    expect(saved.exercises[2].sets.single.loadKg, isNull);
    expect(saved.exercises[2].sets.single.restSec, 75);
  });

  testWidgets(
    'remove and add keep other rows and inherit the remaining planned set',
    (tester) async {
      final original = await seed();
      final sessionId = await repo.startStrengthSession(original);
      await repo.recordSet(
        sessionId,
        RecordedSet(
          exerciseKey: 'pull_up',
          setIndex: 2,
          reps: 8,
          loadKg: 99,
          at: DateTime(2026, 9, 19, 18),
          plannedSetId: 'set-w1',
          exerciseId: 'ex-pull',
          restSec: 30,
        ),
      );

      await openEditor(tester, template: original);
      await tester.tap(find.byTooltip('Satz 1 entfernen').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Satz hinzufügen').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Übung entfernen').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vorlage speichern'));
      await tester.pumpAndSettle();

      final saved = await stored('tpl-mixed');
      expect(saved.exercises.map((e) => e.id), ['ex-pull', 'ex-chin']);
      expect(saved.exercises.map((e) => e.exerciseKey), ['pull_up', 'chin_up']);
      expect(saved.exercises.map((e) => e.note), ['volle Amplitude', '']);
      expect(saved.exercises.first.sets.map((s) => s.id).take(2), [
        'set-w1',
        'set-w2',
      ]);
      final added = saved.exercises.first.sets.last;
      expect(added.id, isNot(anyOf('set-wu', 'set-w1', 'set-w2')));
      expect(added.id, matches(_uuid));
      expect(added.type, 'work');
      expect(added.restSec, 120);
      expect(added.loadKg, isNull);
      expect(added.reps, isNull);
      expect(saved.exercises.last.sets.single.id, 'set-chin');
      expect(saved.exercises.last.sets.single.loadKg, isNull);
      expect(saved.exercises.last.sets.single.restSec, 75);

      final live =
          await repo.readActiveStrengthSession() as ActiveStrengthSession;
      expect(live.sessionId, sessionId);
      expect(live.plan.name, 'Gemischt');
      expect(live.plan.version, original.version);
      expect(live.plan.exercises.map((e) => e.id), [
        'ex-pull',
        'ex-plank',
        'ex-chin',
      ]);
      expect(live.plan.exercises.first.sets.map((s) => s.id), [
        'set-wu',
        'set-w1',
        'set-w2',
      ]);
      expect(live.plan.exercises.first.sets.first.type, 'warmup');
      expect(live.recorded.single.loadKg, 99);
      expect(live.recorded.single.plannedSetId, 'set-w1');
    },
  );

  testWidgets('save failure keeps the entire draft for retry', (tester) async {
    final original = await seed();
    await openEditor(tester, template: original);
    await tester.enterText(find.widgetWithText(TextField, 'Gemischt'), 'Retry');
    await tester.enterText(find.widgetWithText(TextField, '20,0').first, '25');
    repo.failTemplateWrite = true;
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();
    expect(
      find.text('Speichern fehlgeschlagen.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'Retry'), findsOneWidget);
    expect(find.widgetWithText(TextField, '25'), findsOneWidget);
    expect((await stored('tpl-mixed')).name, 'Gemischt');
    expect((await stored('tpl-mixed')).exercises.first.sets[1].loadKg, 20);

    repo.failTemplateWrite = false;
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();
    final saved = await stored('tpl-mixed');
    expect(saved.name, 'Retry');
    expect(saved.exercises.first.sets[1].loadKg, 25);
    expect(saved.exercises.first.sets.first.type, 'warmup');
    expect(saved.exercises.first.note, 'volle Amplitude');
  });

  testWidgets('new plan identities are uuids and empty load stays absent', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'Oberkörper B');
    await tester.tap(find.text('Übung hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'Klimmzug');
    await tester.enterText(find.byType(TextField).at(3), '6');
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();

    final saved = (await repo.readTemplates()).firstWhere(
      (t) => t.name == 'Oberkörper B',
    );
    expect(saved.id, matches(_uuid));
    expect(saved.version, 1);
    expect(saved.exercises.single.id, matches(_uuid));
    expect(saved.exercises.single.exerciseKey, matches(_uuid));
    expect(saved.exercises.single.exerciseKey, isNot('klimmzug'));
    expect(
      saved.exercises.single.exerciseKey,
      isNot(saved.exercises.single.id),
    );
    expect(saved.exercises.single.sets, hasLength(3));
    expect(saved.exercises.single.sets.map((s) => s.id).toSet(), hasLength(3));
    expect(
      saved.exercises.single.sets.every((s) => _uuid.hasMatch(s.id)),
      isTrue,
    );
    expect(saved.exercises.single.sets.first.reps, 6);
    expect(saved.exercises.single.sets.first.loadKg, isNull);
    expect(saved.exercises.single.sets.first.loadKg, isNot(0));
  });

  Finder hinted(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint,
  );

  testWidgets('duplicate new labels keep distinct stable keys', (tester) async {
    await openEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'Doppel');
    await tester.tap(find.text('Übung hinzufügen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Übung hinzufügen'));
    await tester.tap(find.text('Übung hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(hinted('Übung').at(0), 'Klimmzug');
    await tester.enterText(hinted('Übung').at(1), 'Klimmzug');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();

    final saved = (await repo.readTemplates()).firstWhere(
      (t) => t.name == 'Doppel',
    );
    expect(saved.exercises, hasLength(2));
    expect(saved.exercises.map((e) => e.name), ['Klimmzug', 'Klimmzug']);
    expect(saved.exercises[0].exerciseKey, matches(_uuid));
    expect(saved.exercises[1].exerciseKey, matches(_uuid));
    expect(
      saved.exercises[0].exerciseKey,
      isNot(saved.exercises[1].exerciseKey),
    );
    expect(
      saved.exercises.map((e) => e.exerciseKey),
      isNot(contains('klimmzug')),
    );
    expect(saved.exercises[0].id, isNot(saved.exercises[1].id));
  });

  testWidgets('name-only save keeps fractional load and null', (tester) async {
    final original = await repo.saveTemplate(precise());
    await openEditor(tester, template: original);
    expect(find.widgetWithText(TextField, '2,75'), findsOneWidget);
    expect(find.widgetWithText(TextField, '62,55'), findsOneWidget);
    expect(find.widgetWithText(TextField, '2,8'), findsNothing);
    expect(find.widgetWithText(TextField, '62,6'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, 'Präzise'),
      'Präzise+',
    );
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();

    final saved = await stored('tpl-precise');
    expect(saved.name, 'Präzise+');
    expect(saved.exercises.single.sets.map((s) => s.id), [
      'set-a',
      'set-b',
      'set-c',
    ]);
    expect(saved.exercises.single.sets.map((s) => s.loadKg), [
      2.75,
      62.55,
      null,
    ]);
  });

  testWidgets('failed save retry keeps fractional load and null', (
    tester,
  ) async {
    final original = await repo.saveTemplate(precise());
    await openEditor(tester, template: original);
    await tester.enterText(find.widgetWithText(TextField, 'Präzise'), 'Retry');
    repo.failTemplateWrite = true;
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();
    expect(
      find.text('Speichern fehlgeschlagen.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'Retry'), findsOneWidget);
    expect(find.widgetWithText(TextField, '2,75'), findsOneWidget);
    expect(find.widgetWithText(TextField, '62,55'), findsOneWidget);
    expect(
      (await stored('tpl-precise')).exercises.single.sets.map((s) => s.loadKg),
      [2.75, 62.55, null],
    );

    repo.failTemplateWrite = false;
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();
    final saved = await stored('tpl-precise');
    expect(saved.name, 'Retry');
    expect(saved.exercises.single.sets.map((s) => s.loadKg), [
      2.75,
      62.55,
      null,
    ]);
  });

  testWidgets('blank timed duration cannot persist or reopen as reps', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'Halt');
    await tester.tap(find.text('Zeitübung hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(hinted('Übung'), 'Plank');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandTemplateEditor), findsOneWidget);
    expect(
      (await repo.readTemplates()).where((t) => t.name == 'Halt'),
      isEmpty,
    );

    for (var i = 0; i < 3; i++) {
      await tester.enterText(hinted('Sek.').at(i), '40');
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();

    final saved = (await repo.readTemplates()).firstWhere(
      (t) => t.name == 'Halt',
    );
    expect(saved.exercises.single.sets, hasLength(3));
    expect(
      saved.exercises.single.sets.every(
        (s) => s.seconds == 40 && s.reps == null,
      ),
      isTrue,
    );

    await openEditor(tester, template: saved);
    expect(hinted('Sek.'), findsNWidgets(3));
    expect(hinted('Wdh.'), findsNothing);
  });

  testWidgets('added timed set with 40 seconds roundtrips as timed', (
    tester,
  ) async {
    final original = await seed();
    await openEditor(tester, template: original);
    await tester.ensureVisible(find.text('Satz hinzufügen').at(1));
    await tester.tap(find.text('Satz hinzufügen').at(1));
    await tester.pumpAndSettle();
    await tester.enterText(hinted('Sek.').last, '40');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();

    final saved = await stored('tpl-mixed');
    final plank = saved.exercises.firstWhere((e) => e.id == 'ex-plank');
    expect(plank.sets, hasLength(2));
    expect(plank.sets.first.id, 'set-plank');
    expect(plank.sets.first.seconds, 40);
    expect(plank.sets.first.reps, isNull);
    expect(plank.sets.last.id, matches(_uuid));
    expect(plank.sets.last.seconds, 40);
    expect(plank.sets.last.reps, isNull);
  });

  testWidgets('malformed count or load refuses save and keeps the draft', (
    tester,
  ) async {
    final original = await seed();
    await openEditor(tester, template: original);
    await tester.enterText(find.widgetWithText(TextField, '20,0').first, 'xyz');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandTemplateEditor), findsOneWidget);
    expect(find.widgetWithText(TextField, 'xyz'), findsOneWidget);
    expect((await stored('tpl-mixed')).exercises.first.sets[1].loadKg, 20);

    await tester.enterText(find.widgetWithText(TextField, 'xyz'), '-1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandTemplateEditor), findsOneWidget);
    expect((await stored('tpl-mixed')).name, 'Gemischt');
    expect((await stored('tpl-mixed')).exercises.first.sets[1].loadKg, 20);

    await tester.enterText(find.widgetWithText(TextField, '8').first, 'abc');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenBandTemplateEditor), findsOneWidget);
    expect(find.widgetWithText(TextField, 'abc'), findsOneWidget);
    expect((await stored('tpl-mixed')).exercises.first.sets[1].reps, 8);
  });

  testWidgets('1000.25 name-only and grouped locale edit keep the load', (
    tester,
  ) async {
    final original = await repo.saveTemplate(
      WorkoutTemplate(
        id: 'tpl-heavy',
        name: 'Schwer',
        version: 1,
        exercises: [
          PlannedExercise(
            id: 'ex-row',
            exerciseKey: 'row',
            name: 'Rudern',
            sets: [
              PlannedSet(id: 'set-a', reps: 5, loadKg: 1000.25, restSec: 90),
              PlannedSet(id: 'set-b', reps: 5, loadKg: 1000, restSec: 90),
            ],
          ),
        ],
        updatedAt: DateTime(2026, 9, 1),
      ),
    );
    await openEditor(tester, template: original);
    expect(find.widgetWithText(TextField, '1000,25'), findsOneWidget);
    expect(find.widgetWithText(TextField, '1000,0'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Schwer'), 'Schwer+');
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();
    expect(
      (await stored('tpl-heavy')).exercises.single.sets.map((s) => s.loadKg),
      [1000.25, 1000],
    );

    await openEditor(tester, template: await stored('tpl-heavy'));
    await tester.enterText(
      find.widgetWithText(TextField, '1000,25'),
      '1.000,25',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vorlage speichern'));
    await tester.pumpAndSettle();
    final saved = await stored('tpl-heavy');
    expect(saved.name, 'Schwer+');
    expect(saved.exercises.single.sets.map((s) => s.loadKg), [1000.25, 1000]);
    expect(saved.exercises.single.sets.map((s) => s.reps), [5, 5]);
  });

  testWidgets(
    'dot and comma decimals parse; grouped 1.000,25; exponent and junk refuse',
    (tester) async {
      final original = await seed();
      await openEditor(tester, template: original);
      await tester.enterText(
        find.widgetWithText(TextField, '20,0').first,
        '22.5',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vorlage speichern'));
      await tester.pumpAndSettle();
      expect((await stored('tpl-mixed')).exercises.first.sets[1].loadKg, 22.5);

      await openEditor(tester, template: await stored('tpl-mixed'));
      await tester.enterText(
        find.widgetWithText(TextField, '22,5').first,
        '22,5',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vorlage speichern'));
      await tester.pumpAndSettle();
      expect((await stored('tpl-mixed')).exercises.first.sets[1].loadKg, 22.5);

      await openEditor(tester, template: await stored('tpl-mixed'));
      await tester.enterText(
        find.widgetWithText(TextField, '22,5').first,
        '1.000,25',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vorlage speichern'));
      await tester.pumpAndSettle();
      expect(
        (await stored('tpl-mixed')).exercises.first.sets[1].loadKg,
        1000.25,
      );

      await openEditor(tester, template: await stored('tpl-mixed'));
      await tester.enterText(
        find.widgetWithText(TextField, '1000,25').first,
        '1e2',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vorlage speichern'));
      await tester.pumpAndSettle();
      expect(find.byType(OpenBandTemplateEditor), findsOneWidget);
      expect(find.widgetWithText(TextField, '1e2'), findsOneWidget);
      expect(
        (await stored('tpl-mixed')).exercises.first.sets[1].loadKg,
        1000.25,
      );

      await tester.enterText(find.widgetWithText(TextField, '1e2'), '1.00,25');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vorlage speichern'));
      await tester.pumpAndSettle();
      expect(find.byType(OpenBandTemplateEditor), findsOneWidget);
      expect(find.widgetWithText(TextField, '1.00,25'), findsOneWidget);
      expect(
        (await stored('tpl-mixed')).exercises.first.sets[1].loadKg,
        1000.25,
      );
      expect((await stored('tpl-mixed')).exercises.first.sets[2].loadKg, 20);
    },
  );
}
