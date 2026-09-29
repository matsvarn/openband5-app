import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/app.dart' show screenForRoute;
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/screens/journal_screen.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

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
)..failCaffeineSleepPattern = true;

class _ReadFailsAfterWrite extends SyntheticOpenBandRepository {
  _ReadFailsAfterWrite()
    : super.fromMaps(
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

  @override
  Future<void> patchJournalDay(JournalDayPatch patch) async {
    await super.patchJournalDay(patch);
    failJournalRead = true;
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
  late SyntheticOpenBandRepository repo;
  late OpenBandController controller;
  setUp(() {
    repo = _repo();
    controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      now: () => DateTime(2026, 9, 15),
    );
  });
  tearDown(() => controller.dispose());

  test('journal compose deep link opens the G3 editor route', () {
    expect(
      screenForRoute('/journal/compose', repository: repo),
      isA<G3JournalComposeRoute>(),
    );
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
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
        home: Scaffold(
          body: G3JournalScreen(controller: controller, onEdit: (_) {}),
        ),
      ),
    );
    await tester.pump();
    final pending = repo.caffeineSleepPatternPending;
    if (pending != null) {
      await tester.runAsync(() async {
        try {
          await pending;
        } on Object {
          // The screen renders the repository failure.
        }
      });
    }
    await tester.pumpAndSettle();
  }

  testWidgets('Journal remains usable at 320 pt with larger text', (
    tester,
  ) async {
    await mount(tester);
    tester.view.physicalSize = const Size(320, 852);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Gestern Abend Alkohol?'), findsOneWidget);
  });

  testWidgets(
    'missing answers stay open and a saved answer advances the check-in',
    (tester) async {
      await mount(tester);
      expect(find.text('Gestern Abend Alkohol?'), findsOneWidget);
      expect(
        find.text('Noch nichts beantwortet. Auslassen kostet nichts.'),
        findsOneWidget,
      );
      expect(
        (await repo.readJournalDay('2026-09-15')).metrics['alcohol_evening'],
        isNull,
      );
      await tester.tap(find.text('Ja').first);
      await tester.pumpAndSettle();
      expect(
        (await repo.readJournalDay(
          '2026-09-15',
        )).metrics['alcohol_evening']?.value,
        1,
      );
      expect(find.text('Koffein nach 14 Uhr?'), findsOneWidget);
      expect(find.text('1 von 4'), findsWidgets);
    },
  );

  testWidgets('failed save retains the chosen answer and can retry', (
    tester,
  ) async {
    repo.failJournalPatch = true;
    await mount(tester);
    await tester.tap(find.text('Nein').first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Deine Auswahl bleibt erhalten'),
      findsOneWidget,
    );
    expect(
      (await repo.readJournalDay('2026-09-15')).metrics['alcohol_evening'],
      isNull,
    );
    repo.failJournalPatch = false;
    await tester.tap(find.text('Erneut speichern'));
    await tester.pumpAndSettle();
    expect(
      (await repo.readJournalDay(
        '2026-09-15',
      )).metrics['alcohol_evening']?.value,
      0,
    );
  });

  testWidgets(
    'successful write with failed refresh offers reload, not another save',
    (tester) async {
      repo = _ReadFailsAfterWrite()..failCaffeineSleepPattern = true;
      controller.dispose();
      controller = OpenBandController(
        repository: repo,
        initialDay: '2026-09-15',
        now: () => DateTime(2026, 9, 15),
      );
      await mount(tester);
      await tester.tap(find.text('Nein').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Antwort gespeichert.'), findsOneWidget);
      expect(find.text('Neu laden'), findsOneWidget);
      expect(find.text('Erneut speichern'), findsNothing);
      repo.failJournalRead = false;
      await tester.tap(find.text('Neu laden'));
      await tester.pumpAndSettle();
      expect(
        (await repo.readJournalDay(
          '2026-09-15',
        )).metrics['alcohol_evening']?.value,
        0,
      );
    },
  );

  testWidgets(
    'a saved custom question joins the check-in and keeps its own field',
    (tester) async {
      await repo.createJournalField(
        const JournalFieldSpec(
          key: 'custom_evening_walk',
          label: 'Abends draußen?',
          kind: JournalFieldKind.yesNo,
          unit: '',
          max: 1,
          step: 1,
          custom: true,
        ),
      );
      await mount(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Später'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Abends draußen?'), findsOneWidget);
      await tester.tap(find.text('Ja').first);
      await tester.pumpAndSettle();
      expect(
        (await repo.readJournalDay(
          '2026-09-15',
        )).metrics['custom_evening_walk']?.value,
        1,
      );
    },
  );

  testWidgets(
    'editing a saved answer keeps the sheet draft after a failed save',
    (tester) async {
      repo.seedJournalEditor(
        day: '2026-09-15',
        metrics: {'alcohol_evening': const JournalMetricValue(0)},
      );
      await mount(tester);
      await tester.tap(find.byTooltip('Alkohol ändern'));
      await tester.pumpAndSettle();
      expect(find.text('vorher: Nein'), findsOneWidget);
      await tester.tap(find.text('Ja').last);
      await tester.pump();
      repo.failJournalPatch = true;
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Deine Auswahl bleibt erhalten'),
        findsOneWidget,
      );
      expect(
        (await repo.readJournalDay(
          '2026-09-15',
        )).metrics['alcohol_evening']?.value,
        0,
      );
      repo.failJournalPatch = false;
      await tester.tap(find.text('Erneut speichern').last);
      await tester.pumpAndSettle();
      expect(
        (await repo.readJournalDay(
          '2026-09-15',
        )).metrics['alcohol_evening']?.value,
        1,
      );
      expect(find.text('vorher: Nein'), findsNothing);
    },
  );

  testWidgets('pattern refusal shows the repository minimum and paired count', (
    tester,
  ) async {
    repo.failCaffeineSleepPattern = false;
    repo.seedCaffeineSleepPattern(
      '2026-09-15',
      seed: SyntheticCaffeineSleepSeed.insufficient,
    );
    await mount(tester);
    await tester.ensureVisible(find.text('Noch zu wenige Nächte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Noch zu wenige Nächte'));
    await tester.pumpAndSettle();
    expect(find.text('5 von 8 Paaren · noch 3'), findsOneWidget);
    expect(find.textContaining('ms'), findsNothing);
  });

  testWidgets(
    'per-side refusal counts remain unknown until the repository supplies them',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const model = CaffeineSleepPattern(
        kind: CaffeineSleepPatternKind.insufficient,
        pairedN: 8,
        endDay: '2026-09-15',
        startDay: '2026-08-17',
        nights: 30,
        algoVersion: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: openBandTheme(Brightness.light),
          home: const G3JournalPatternScreen(
            pattern: G3JournalPattern(model, pairedMinimum: 8),
          ),
        ),
      );
      expect(find.text('8 Paare · Ja — · Nein —'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      expect(find.textContaining('von 3 nötig'), findsNothing);
    },
  );

  testWidgets(
    'known per-side refusal counts use the supplied producer threshold',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const model = CaffeineSleepPattern(
        kind: CaffeineSleepPatternKind.insufficient,
        pairedN: 8,
        yesNights: 1,
        noNights: 7,
        endDay: '2026-09-15',
        startDay: '2026-08-17',
        nights: 30,
        algoVersion: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: openBandTheme(Brightness.light),
          home: const G3JournalPatternScreen(
            pattern: G3JournalPattern(model, pairedMinimum: 8),
            perSideMinimum: 3,
          ),
        ),
      );
      expect(
        find.text('8 Paare · Ja 1 von 3 nötig · Nein 7 vorhanden'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Journal tab light', (tester) async {
    repo.seedJournalEditor(
      day: '2026-09-15',
      metrics: {
        'alcohol_evening': const JournalMetricValue(0),
        'caffeine_late': const JournalMetricValue(1),
      },
    );
    await mount(tester);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('openband_goldens/g3-journal-tab-light.png'),
    );
  }, tags: const ['golden']);
}
