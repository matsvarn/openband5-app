import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/health.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/openband/vo2.dart';

const _day = '2026-09-15';

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync())
      as Map,
);

class _Vo2UiRepository extends SyntheticOpenBandRepository {
  _Vo2UiRepository()
    : super.fromMaps(
        _fixture('day-summary.json'),
        _fixture('sleep-detail.json'),
      ) {
    vo2Now = () => DateTime(2026, 9, 15, 9, 40);
  }

  int listReads = 0;
  int creates = 0;
  int edits = 0;
  int removes = 0;
  int restores = 0;
  bool failOneListAfterCommit = false;
  bool loseNextCreateResponse = false;
  bool injectEditConflict = false;
  bool injectRemoteRemovalOnEdit = false;
  Vo2Detail? forcedDetail;
  final List<String> createIds = [];

  @override
  Future<Vo2List> readVo2Entries() async {
    listReads++;
    if (failOneListAfterCommit) {
      failOneListAfterCommit = false;
      throw StateError('one-shot post-commit read failure');
    }
    return super.readVo2Entries();
  }

  @override
  Future<Vo2WriteResult> createVo2Entry({
    required String id,
    required String measuredOn,
    required double valueMlKgMin,
    String? declaredMethod,
  }) async {
    creates++;
    createIds.add(id);
    final result = await super.createVo2Entry(
      id: id,
      measuredOn: measuredOn,
      valueMlKgMin: valueMlKgMin,
      declaredMethod: declaredMethod,
    );
    if (loseNextCreateResponse) {
      loseNextCreateResponse = false;
      throw StateError('synthetic lost create response');
    }
    return result;
  }

  @override
  Future<Vo2Detail> readVo2Entry(String id) async {
    if (forcedDetail case final detail? when detail.id == id) return detail;
    return super.readVo2Entry(id);
  }

  @override
  Future<Vo2WriteResult> editVo2Entry({
    required String id,
    required int expectedRevision,
    required String measuredOn,
    required double valueMlKgMin,
    String? declaredMethod,
  }) async {
    edits++;
    if (injectRemoteRemovalOnEdit) {
      injectRemoteRemovalOnEdit = false;
      final external = await super.removeVo2Entry(
        id: id,
        expectedRevision: expectedRevision,
      );
      return Vo2WriteConflict(
        head: external is Vo2Committed ? external.revision : null,
      );
    }
    if (injectEditConflict) {
      injectEditConflict = false;
      final external = await super.editVo2Entry(
        id: id,
        expectedRevision: expectedRevision,
        measuredOn: measuredOn,
        valueMlKgMin: 43,
        declaredMethod: 'Extern geändert',
      );
      return Vo2WriteConflict(
        head: external is Vo2Committed ? external.revision : null,
      );
    }
    return super.editVo2Entry(
      id: id,
      expectedRevision: expectedRevision,
      measuredOn: measuredOn,
      valueMlKgMin: valueMlKgMin,
      declaredMethod: declaredMethod,
    );
  }

  @override
  Future<Vo2WriteResult> removeVo2Entry({
    required String id,
    required int expectedRevision,
  }) async {
    removes++;
    return super.removeVo2Entry(id: id, expectedRevision: expectedRevision);
  }

  @override
  Future<Vo2WriteResult> restoreVo2Entry({
    required String id,
    required int expectedRevision,
  }) async {
    restores++;
    return super.restoreVo2Entry(id: id, expectedRevision: expectedRevision);
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

  late _Vo2UiRepository repo;

  setUp(() => repo = _Vo2UiRepository());

  Widget app({
    Brightness brightness = Brightness.light,
    double scale = 1,
    Size size = const Size(393, 852),
    Widget? home,
  }) => RepaintBoundary(
    key: const ValueKey('capture'),
    child: MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
      builder: (context, child) => MediaQuery(
        data: MediaQueryData(
          size: size,
          devicePixelRatio: 1,
          padding: const EdgeInsets.only(top: 59, bottom: 34),
          viewPadding: const EdgeInsets.only(top: 59, bottom: 34),
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home:
          home ??
          OpenBandVo2(
            key: UniqueKey(),
            repository: repo,
            endDay: _day,
            now: () => DateTime(2026, 9, 15, 9, 41),
          ),
    ),
  );

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    Size size = const Size(393, 852),
    Widget? home,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(brightness: brightness, scale: scale, size: size, home: home),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('vo2-hero-edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vo2-editor')), findsOneWidget);
  }

  Future<void> enterValue(WidgetTester tester, String value) async {
    final field = find.byKey(const ValueKey('vo2-value-input'));
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
  }

  Future<void> tapSave(WidgetTester tester) async {
    final save = find.byKey(const ValueKey('vo2-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
  }

  testWidgets('empty state is honest and read errors are not empty', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Noch keine Einträge'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('Fitness'), findsNothing);
    expect(find.textContaining('Schätzung'), findsNothing);

    repo.failVo2Read = true;
    await mount(tester);
    expect(find.text('Einträge konnten nicht geladen werden.'), findsOneWidget);
    expect(find.text('Noch keine Einträge'), findsNothing);
    repo.failVo2Read = false;
    await tester.tap(find.byKey(const ValueKey('vo2-read-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Noch keine Einträge'), findsOneWidget);
  });

  testWidgets(
    'create accepts comma decimal, trims method, and uses context day',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('vo2-add-empty')));
      await tester.pumpAndSettle();
      expect(find.text('15. September 2026'), findsOneWidget);
      await enterValue(tester, '42,5');
      await tester.enterText(
        find.byKey(const ValueKey('vo2-method-input')),
        '  Spiroergometrie  ',
      );
      await tapSave(tester);

      expect(repo.creates, 1);
      final list = await repo.readVo2Entries();
      final stored = list.entries.single.head!;
      expect(stored.id, repo.createIds.single);
      expect(stored.measuredOn, _day);
      expect(stored.valueMlKgMin, 42.5);
      expect(stored.declaredMethod, 'Spiroergometrie');
      expect(find.text('42,5'), findsWidgets);
    },
  );

  testWidgets('invalid or nonfinite input never writes', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('vo2-add-empty')));
    await tester.pumpAndSettle();
    for (final bad in ['0', '-1', 'NaN', 'Infinity']) {
      await enterValue(tester, bad);
      await tapSave(tester);
      expect(find.text('Wert muss eine positive Zahl sein.'), findsOneWidget);
      expect(repo.creates, 0);
    }
  });

  testWidgets('failed create keeps draft and retries the same stable id', (
    tester,
  ) async {
    repo.failVo2Write = true;
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('vo2-add-empty')));
    await tester.pumpAndSettle();
    await enterValue(tester, '180,5');
    await tester.enterText(
      find.byKey(const ValueKey('vo2-method-input')),
      'Feldtest',
    );
    await tapSave(tester);
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('vo2-value-input')))
          .controller
          ?.text,
      '180,5',
    );
    repo.failVo2Write = false;
    await tapSave(tester);
    expect(repo.creates, 2);
    expect(repo.createIds.toSet(), hasLength(1));
    expect(
      (await repo.readVo2Entries()).entries.single.head?.valueMlKgMin,
      180.5,
    );
  });

  testWidgets('calendar is capped and changing date retains the draft', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('vo2-add-empty')));
    await tester.pumpAndSettle();
    await enterValue(tester, '42.5');
    await tester.enterText(
      find.byKey(const ValueKey('vo2-method-input')),
      'Laufband',
    );
    await tester.tap(find.byKey(const ValueKey('vo2-date-input')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vo2-calendar')), findsOneWidget);
    final future = find.bySemanticsLabel('Mittwoch, 16. September 2026');
    expect(future, findsOneWidget);
    expect(tester.widget<Semantics>(future).properties.enabled, isFalse);
    await tester.tap(find.bySemanticsLabel('Montag, 14. September 2026'));
    await tester.pump();
    expect(
      tester
          .widget<Semantics>(
            find.bySemanticsLabel('Montag, 14. September 2026'),
          )
          .properties
          .selected,
      isTrue,
    );
    expect(find.text('14. September übernehmen'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vo2-date-apply')));
    await tester.pumpAndSettle();
    expect(find.text('14. September 2026'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('vo2-value-input')))
          .controller
          ?.text,
      '42.5',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('vo2-method-input')))
          .controller
          ?.text,
      'Laufband',
    );
    await tapSave(tester);
    expect(
      (await repo.readVo2Entries()).entries.single.head?.measuredOn,
      '2026-09-14',
    );
  });

  testWidgets(
    'edit conflict keeps draft and reload replaces it only after read',
    (tester) async {
      repo.seedVo2Paper();
      repo.injectEditConflict = true;
      await mount(tester);
      await openEditor(tester);
      await enterValue(tester, '42,5');
      await tapSave(tester);
      expect(find.text('Eintrag wurde geändert'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('vo2-value-input')))
            .controller
            ?.text,
        '42,5',
      );
      repo.failVo2Read = true;
      await tapSave(tester);
      expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('vo2-value-input')))
            .controller
            ?.text,
        '42,5',
      );
      repo.failVo2Read = false;
      await tapSave(tester);
      expect(find.text('Eintrag wurde geändert'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('vo2-value-input')))
            .controller
            ?.text,
        '43',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('vo2-method-input')))
            .controller
            ?.text,
        'Extern geändert',
      );
      await tester.tap(find.byTooltip('Schließen'));
      await tester.pumpAndSettle();
      expect(find.text('43,0'), findsWidgets);
    },
  );

  testWidgets(
    'lost create response conflicts after draft change then reloads stable id',
    (tester) async {
      repo.loseNextCreateResponse = true;
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('vo2-add-empty')));
      await tester.pumpAndSettle();
      await enterValue(tester, '42');
      await tester.enterText(
        find.byKey(const ValueKey('vo2-method-input')),
        'Spiroergometrie',
      );
      await tapSave(tester);
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);

      await enterValue(tester, '43');
      await tapSave(tester);
      expect(find.text('Eintrag wurde geändert'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('vo2-value-input')))
            .controller
            ?.text,
        '43',
      );
      expect(repo.createIds.toSet(), hasLength(1));
      expect((await repo.readVo2Entries()).entries, hasLength(1));

      await tapSave(tester);
      expect(find.text('Eintrag wurde geändert'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('vo2-value-input')))
            .controller
            ?.text,
        '42',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('vo2-method-input')))
            .controller
            ?.text,
        'Spiroergometrie',
      );

      await enterValue(tester, '44');
      await tapSave(tester);
      final id = repo.createIds.first;
      final detail = await repo.readVo2Entry(id);
      expect(detail.revisions, hasLength(2));
      expect(detail.head?.valueMlKgMin, 44);
      expect((await repo.readVo2Entries()).entries.single.id, id);
    },
  );

  testWidgets(
    'conflict reload reconciles remotely removed edit with root list',
    (tester) async {
      repo.seedVo2Paper();
      repo.injectRemoteRemovalOnEdit = true;
      await mount(tester);
      await openEditor(tester);
      await enterValue(tester, '42,5');
      await tapSave(tester);
      expect(find.text('Eintrag wurde geändert'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('vo2-value-input')))
            .controller
            ?.text,
        '42,5',
      );

      await tapSave(tester);
      expect(find.byKey(const ValueKey('vo2-editor')), findsNothing);
      expect(find.text('Laden fehlgeschlagen'), findsNothing);
      expect(
        find.byKey(const ValueKey('vo2-removed-vo2-paper')),
        findsOneWidget,
      );
      expect(
        (await repo.readVo2Entry(kSyntheticVo2PaperId)).head?.deleted,
        isTrue,
      );
    },
  );

  testWidgets('editor reload distinguishes missing and corrupt heads', (
    tester,
  ) async {
    repo.seedVo2Paper();
    repo.injectEditConflict = true;
    await mount(tester);
    await openEditor(tester);
    await enterValue(tester, '42,5');
    await tapSave(tester);
    expect(find.text('Eintrag wurde geändert'), findsOneWidget);

    repo.forcedDetail = const Vo2Detail(
      id: kSyntheticVo2PaperId,
      head: null,
      missing: true,
      headCorrupt: false,
      revisions: [],
      corruptRevisionCount: 0,
    );
    await tapSave(tester);
    expect(find.text('Eintrag nicht gefunden'), findsOneWidget);
    expect(find.text('Laden fehlgeschlagen'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('vo2-value-input')))
          .controller
          ?.text,
      '42,5',
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('vo2-remove')))
          .onPressed,
      isNull,
    );

    repo.forcedDetail = const Vo2Detail(
      id: kSyntheticVo2PaperId,
      head: null,
      missing: false,
      headCorrupt: true,
      revisions: [],
      corruptRevisionCount: 1,
    );
    await tapSave(tester);
    expect(find.text('Eintrag nicht lesbar'), findsOneWidget);
    expect(find.text('Eintrag nicht gefunden'), findsNothing);
    expect(repo.edits, 1);
  });

  testWidgets('removed detail distinguishes unavailable heads and retries', (
    tester,
  ) async {
    repo.seedVo2Paper();
    await repo.removeVo2Entry(id: kSyntheticVo2PaperId, expectedRevision: 1);
    await mount(tester);
    repo.forcedDetail = const Vo2Detail(
      id: kSyntheticVo2PaperId,
      head: null,
      missing: true,
      headCorrupt: false,
      revisions: [],
      corruptRevisionCount: 0,
    );
    await tester.tap(find.byKey(const ValueKey('vo2-removed-vo2-paper')));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag nicht gefunden'), findsOneWidget);
    expect(find.byKey(const ValueKey('vo2-restore')), findsNothing);

    repo.forcedDetail = const Vo2Detail(
      id: kSyntheticVo2PaperId,
      head: null,
      missing: false,
      headCorrupt: true,
      revisions: [],
      corruptRevisionCount: 1,
    );
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag nicht lesbar'), findsOneWidget);
    expect(find.text('Eintrag nicht gefunden'), findsNothing);
    expect(find.byKey(const ValueKey('vo2-restore')), findsNothing);

    repo.forcedDetail = null;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vo2-restore')), findsOneWidget);
    expect(find.text('Entfernt'), findsOneWidget);

    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    repo.failVo2Read = true;
    await tester.tap(find.byKey(const ValueKey('vo2-removed-vo2-paper')));
    await tester.pumpAndSettle();
    expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
    expect(find.byKey(const ValueKey('vo2-restore')), findsNothing);
    repo.failVo2Read = false;
    await tester.tap(find.text('Erneut'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vo2-restore')), findsOneWidget);
  });

  testWidgets(
    'history return keeps draft and shows same-value method revisions',
    (tester) async {
      repo.seedVo2Paper();
      await repo.editVo2Entry(
        id: kSyntheticVo2PaperId,
        expectedRevision: 1,
        measuredOn: kSyntheticVo2PaperDay,
        valueMlKgMin: 42,
        declaredMethod: 'Laufband',
      );
      await mount(tester);
      await openEditor(tester);
      await enterValue(tester, '42,7');
      await tester.tap(find.byKey(const ValueKey('vo2-history')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vo2-history-page')), findsOneWidget);
      expect(find.text('42,0'), findsNWidgets(2));
      expect(find.textContaining('Spiroergometrie'), findsOneWidget);
      expect(find.textContaining('Laufband'), findsOneWidget);
      await tester.tap(find.byTooltip('Über VO₂max'));
      await tester.pumpAndSettle();
      expect(find.text('Quelle: Eigener Eintrag · ml/kg/min'), findsOneWidget);
      expect(
        find.text('Einordnung: kein Referenzbereich hinterlegt.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('vo2-value-input')))
            .controller
            ?.text,
        '42,7',
      );
    },
  );

  testWidgets('remove and restore append revisions under the same id', (
    tester,
  ) async {
    repo.seedVo2Paper();
    await mount(tester);
    await openEditor(tester);
    await tester.tap(find.byKey(const ValueKey('vo2-remove')));
    await tester.pumpAndSettle();
    expect(repo.removes, 1);
    expect(find.text('Entfernt'), findsOneWidget);
    expect(find.byKey(const ValueKey('vo2-removed-vo2-paper')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('vo2-removed-vo2-paper')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vo2-restore')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vo2-restore')));
    await tester.pumpAndSettle();
    expect(repo.restores, 1);
    final detail = await repo.readVo2Entry(kSyntheticVo2PaperId);
    expect(detail.head?.deleted, isFalse);
    expect(detail.revisions, hasLength(3));
  });

  testWidgets('method-only edit preserves stored 42.05 precision', (
    tester,
  ) async {
    await repo.createVo2Entry(
      id: 'precise',
      measuredOn: kSyntheticVo2PaperDay,
      valueMlKgMin: 42.05,
      declaredMethod: 'Spiroergometrie',
    );
    await mount(tester);
    await openEditor(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('vo2-value-input')))
          .controller
          ?.text,
      '42,05',
    );
    await tester.enterText(
      find.byKey(const ValueKey('vo2-method-input')),
      'Laufband',
    );
    await tapSave(tester);
    final detail = await repo.readVo2Entry('precise');
    expect(detail.head?.valueMlKgMin, 42.05);
    expect(detail.head?.declaredMethod, 'Laufband');
  });

  testWidgets('history keeps readable value when signed-64 time is unknown', (
    tester,
  ) async {
    repo.seedVo2Paper();
    final revision = Vo2Revision(
      id: kSyntheticVo2PaperId,
      revision: 1,
      measuredOn: kSyntheticVo2PaperDay,
      valueMlKgMin: 42,
      declaredMethod: kSyntheticVo2PaperMethod,
      createdAt: 1,
      updatedAt: 9223372036854775807,
      deleted: false,
    );
    repo.forcedDetail = Vo2Detail(
      id: revision.id,
      head: revision,
      missing: false,
      headCorrupt: false,
      revisions: [
        Vo2RevisionSlot(revision: 1, value: revision, corrupt: false),
      ],
      corruptRevisionCount: 0,
    );
    await mount(tester);
    await openEditor(tester);
    await tester.tap(find.byKey(const ValueKey('vo2-history')));
    await tester.pumpAndSettle();
    expect(find.text('—'), findsOneWidget);
    expect(find.text('42,0'), findsOneWidget);
    expect(find.text(kVo2Unit), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long finite readings fit main, history, and removed detail', (
    tester,
  ) async {
    const value = 1234567890.1;
    await repo.createVo2Entry(
      id: 'active-long',
      measuredOn: kSyntheticVo2PaperDay,
      valueMlKgMin: value,
      declaredMethod: 'Feldtest',
    );
    await repo.createVo2Entry(
      id: 'removed-long',
      measuredOn: '2026-09-13',
      valueMlKgMin: value,
    );
    await repo.removeVo2Entry(id: 'removed-long', expectedRevision: 1);
    await mount(tester, size: const Size(320, 852));
    expect(find.text('1.234.567.890,1'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('vo2-removed-removed-long')),
      180,
    );
    await tester.tap(find.byKey(const ValueKey('vo2-removed-removed-long')));
    await tester.pumpAndSettle();
    expect(find.text('1.234.567.890,1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('vo2-removed-history')));
    await tester.pumpAndSettle();
    expect(find.text('1.234.567.890,1'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'committed write receipt withholds headline and retry only reads',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('vo2-add-empty')));
      await tester.pumpAndSettle();
      await enterValue(tester, '42');
      repo.failOneListAfterCommit = true;
      await tapSave(tester);
      expect(
        find.text('Gespeichert. Einträge konnten nicht aktualisiert werden.'),
        findsOneWidget,
      );
      expect(find.text('42,0'), findsNothing);
      expect(repo.creates, 1);
      await tester.tap(find.byKey(const ValueKey('vo2-read-retry')));
      await tester.pumpAndSettle();
      expect(find.text('42,0'), findsWidgets);
      expect(repo.creates, 1);
    },
  );

  testWidgets(
    'same-day ids stay distinct, future entries are filtered, ids tie-break',
    (tester) async {
      await repo.createVo2Entry(
        id: 'b',
        measuredOn: '2026-09-14',
        valueMlKgMin: 42,
      );
      await repo.createVo2Entry(
        id: 'a',
        measuredOn: '2026-09-14',
        valueMlKgMin: 41,
      );
      await repo.createVo2Entry(
        id: 'future',
        measuredOn: '2026-09-16',
        valueMlKgMin: 99,
      );
      await mount(tester);
      expect(find.byKey(const ValueKey('vo2-entry-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('vo2-entry-b')), findsOneWidget);
      expect(find.byKey(const ValueKey('vo2-entry-future')), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('vo2-entry-a'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('vo2-entry-b'))).dy,
        ),
      );
    },
  );

  testWidgets(
    'corrupt heads never fall back and partial count keeps good rows',
    (tester) async {
      repo.seedVo2Paper(corruptHead: true);
      await mount(tester);
      expect(find.text('Eintrag nicht lesbar'), findsOneWidget);
      expect(find.text('42,0'), findsNothing);

      repo = _Vo2UiRepository()..seedVo2Paper(corruptHead: true);
      await repo.createVo2Entry(
        id: 'good',
        measuredOn: '2026-09-13',
        valueMlKgMin: 38,
      );
      await mount(tester);
      expect(find.byKey(const ValueKey('vo2-entry-good')), findsOneWidget);
      expect(find.text('1 Eintrag nicht lesbar'), findsOneWidget);
      expect(find.text('42,0'), findsNothing);
    },
  );

  testWidgets(
    'Health row uses actual entry and drops stale value on refresh error',
    (tester) async {
      repo.seedVo2Paper();
      final controller = OpenBandController(
        repository: repo,
        initialDay: _day,
        now: () => DateTime(2026, 9, 15, 9, 41),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await mount(
        tester,
        home: Scaffold(body: OpenBandHealth(controller: controller)),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('vo2-health-row')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vo2-health-row')), findsOneWidget);
      expect(find.text('Eingetragen · 14. Sept.'), findsOneWidget);
      expect(find.text('42,0 ml/kg/min'), findsOneWidget);

      repo.failVo2Read = true;
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
      expect(find.text('42,0 ml/kg/min'), findsNothing);
    },
  );

  testWidgets('Health row distinguishes unreadable storage from empty', (
    tester,
  ) async {
    repo.seedVo2Paper(corruptHead: true);
    final controller = OpenBandController(
      repository: repo,
      initialDay: _day,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await mount(
      tester,
      home: Scaffold(body: OpenBandHealth(controller: controller)),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('vo2-health-row')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Eintrag nicht lesbar'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('Eingetragen'), findsNothing);
  });

  testWidgets('Health row labels readable data with corrupt heads as partial', (
    tester,
  ) async {
    repo.seedVo2Paper(corruptHead: true);
    await repo.createVo2Entry(
      id: 'good',
      measuredOn: kSyntheticVo2PaperDay,
      valueMlKgMin: 38,
    );
    final controller = OpenBandController(
      repository: repo,
      initialDay: _day,
      now: () => DateTime(2026, 9, 15, 9, 41),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await mount(
      tester,
      home: Scaffold(body: OpenBandHealth(controller: controller)),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('vo2-health-row')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Eingetragen · 14. Sept.\nTeilweise lesbar'),
      findsOneWidget,
    );
    expect(find.text('38,0 ml/kg/min'), findsOneWidget);

    repo.failVo2Read = true;
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
    expect(find.text('38,0 ml/kg/min'), findsNothing);
  });

  testWidgets('small and 2x layouts keep primary hit regions usable', (
    tester,
  ) async {
    repo.seedVo2Paper();
    await mount(tester, size: const Size(320, 900));
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('vo2-add'))).shortestSide,
      44,
    );

    await mount(tester, scale: 2, size: const Size(375, 812));
    expect(tester.takeException(), isNull);
    final valueBottom = tester
        .getRect(find.byKey(const ValueKey('vo2-hero-value')))
        .bottom;
    final unitTop = tester
        .getRect(find.byKey(const ValueKey('vo2-hero-unit')))
        .top;
    expect(unitTop, greaterThanOrEqualTo(valueBottom));
    final row = find.byKey(const ValueKey('vo2-entry-vo2-paper'));
    final rowDate = find.descendant(
      of: row,
      matching: find.text('14. September'),
    );
    final rowValue = find.descendant(of: row, matching: find.text('42,0'));
    expect(
      tester.getTopLeft(rowValue).dy,
      greaterThan(tester.getBottomLeft(rowDate).dy),
    );
    await openEditor(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('vo2-save')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('vo2-save'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Paper VO2 variants match representative goldens', (
    tester,
  ) async {
    Future<void> capture(String name) => expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/$name.png'),
    );

    repo.seedVo2Paper();
    await mount(tester, size: const Size(393, 852));
    await capture('vo2_overview_light');

    repo = _Vo2UiRepository()..seedVo2Paper();
    await mount(
      tester,
      brightness: Brightness.dark,
      size: const Size(393, 852),
    );
    await capture('vo2_overview_dark');

    repo = _Vo2UiRepository()..seedVo2Paper();
    await mount(tester, scale: 2, size: const Size(375, 812));
    await capture('vo2_main_375_2x');

    repo = _Vo2UiRepository()..seedVo2Paper();
    await mount(tester, size: const Size(393, 852));
    await openEditor(tester);
    await capture('vo2_editor');

    repo = _Vo2UiRepository();
    repo.vo2Now = () => DateTime(2026, 9, 15, 9, 40);
    await repo.createVo2Entry(
      id: kSyntheticVo2PaperId,
      measuredOn: kSyntheticVo2PaperDay,
      valueMlKgMin: kSyntheticVo2PaperValue,
    );
    repo.vo2Now = () => DateTime(2026, 9, 15, 9, 41);
    await repo.editVo2Entry(
      id: kSyntheticVo2PaperId,
      expectedRevision: 1,
      measuredOn: kSyntheticVo2PaperDay,
      valueMlKgMin: kSyntheticVo2PaperValue,
      declaredMethod: kSyntheticVo2PaperMethod,
    );
    await mount(tester, size: const Size(393, 852));
    await openEditor(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('vo2-history')));
    await tester.tap(find.byKey(const ValueKey('vo2-history')));
    await tester.pumpAndSettle();
    await capture('vo2_history');
  });
}
