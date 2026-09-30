import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/onboarding/first_sync.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late LocalOpenBandRepository repository;
  const day = '2026-09-15';
  const dbName = 'openband_first_sync_eval_test.db';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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

  setUp(() async {
    await LocalDb.close();
    LocalDb.dbName = dbName;
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/$dbName');
    app = AppState.forTesting();
    repository = LocalOpenBandRepository(app);
  });

  tearDown(() async {
    app.dispose();
    await LocalDb.close();
  });

  Future<void> putResult({
    String dayId = day,
    int? algo,
    bool skipped = false,
    bool partial = false,
    String payload = '{}',
  }) => LocalDb.putDayResult(
    dayId: dayId,
    algoVersion: algo ?? kAlgoVersion,
    payloadJson: payload,
    windowJson: '{}',
    skipped: skipped,
    partial: partial,
  );

  group('readSetupEvaluation', () {
    test('current complete row is complete and uses computed_at', () async {
      await putResult();
      final row = await LocalDb.dayResult(day);
      final eval = await repository.readSetupEvaluation(day);
      expect(eval.day, day);
      expect(eval.currentAlgo, kAlgoVersion);
      expect(eval.storedAlgo, kAlgoVersion);
      expect(eval.state, SetupEvalState.complete);
      expect(eval.computedAt, isNotNull);
      expect(
        eval.computedAt!.millisecondsSinceEpoch,
        (row!['computed_at'] as num).toInt(),
      );
    });

    test('older algo is stale, never complete', () async {
      await putResult(algo: kAlgoVersion - 1);
      final eval = await repository.readSetupEvaluation(day);
      expect(eval.state, SetupEvalState.stale);
      expect(eval.storedAlgo, kAlgoVersion - 1);
      expect(eval.computedAt, isNull);
    });

    test('skipped current row is unavailable', () async {
      await putResult(skipped: true);
      expect(
        (await repository.readSetupEvaluation(day)).state,
        SetupEvalState.unavailable,
      );
    });

    test('partial current row is partial', () async {
      await putResult(partial: true);
      expect(
        (await repository.readSetupEvaluation(day)).state,
        SetupEvalState.partial,
      );
    });

    test('corrupt current payload throws instead of missing', () async {
      await putResult();
      final db = await LocalDb.instance;
      await db.update(
        'day_result',
        {'payload_json': 'not-json'},
        where: 'day_id = ?',
        whereArgs: [day],
      );
      await expectLater(
        repository.readSetupEvaluation(day),
        throwsA(isA<FormatException>()),
      );
    });

    test('no row is missing even with a stored cursor', () async {
      await LocalDb.setCursor('rec_ts_hw', '1757913240');
      final eval = await repository.readSetupEvaluation(day);
      expect(eval.state, SetupEvalState.missing);
      expect(eval.storedAlgo, isNull);
      expect(eval.computedAt, isNull);
      expect(await LocalDb.getCursorInt('rec_ts_hw'), 1757913240);
    });

    test('newer pending sleep job blocks an old complete row', () async {
      await LocalDb.putOpenBandSleepDraft(
        dayId: day,
        draftId: 'draft',
        onsetMs: DateTime(2026, 9, 14, 23).millisecondsSinceEpoch,
        wakeMs: DateTime(2026, 9, 15, 7).millisecondsSinceEpoch,
      );
      await LocalDb.commitOpenBandSleepCorrection(
        dayId: day,
        draftId: 'draft',
        onsetMs: DateTime(2026, 9, 14, 23).millisecondsSinceEpoch,
        wakeMs: DateTime(2026, 9, 15, 7).millisecondsSinceEpoch,
      );
      await putResult();
      final computed = ((await LocalDb.dayResult(day))!['computed_at'] as num)
          .toInt();
      final db = await LocalDb.instance;
      await db.update(
        'openband_calculation_job',
        {'requested_at': computed + 5000, 'status': 'pending'},
        where: 'day_id = ?',
        whereArgs: [day],
      );
      expect(
        (await repository.readSetupEvaluation(day)).state,
        SetupEvalState.pending,
      );
    });

    test('newer failed nap job blocks an old complete row', () async {
      await putResult();
      final computed = ((await LocalDb.dayResult(day))!['computed_at'] as num)
          .toInt();
      final db = await LocalDb.instance;
      await db.insert('nap_recalc_job', {
        'day_id': day,
        'revision': 1,
        'status': 'failed',
        'requested_at': computed + 1000,
        'updated_at': computed + 1000,
        'error': 'failed',
      });
      expect(
        (await repository.readSetupEvaluation(day)).state,
        SetupEvalState.failed,
      );
    });

    test(
      'unrelated putDayResult after a pending sleep job stays pending',
      () async {
        await LocalDb.putOpenBandSleepDraft(
          dayId: day,
          draftId: 'draft',
          onsetMs: DateTime(2026, 9, 14, 23).millisecondsSinceEpoch,
          wakeMs: DateTime(2026, 9, 15, 7).millisecondsSinceEpoch,
        );
        await LocalDb.commitOpenBandSleepCorrection(
          dayId: day,
          draftId: 'draft',
          onsetMs: DateTime(2026, 9, 14, 23).millisecondsSinceEpoch,
          wakeMs: DateTime(2026, 9, 15, 7).millisecondsSinceEpoch,
        );
        await putResult();
        final job = await LocalDb.openBandSleepCorrection(day);
        expect(job!['status'], 'pending');
        expect(job['result_computed_at'], isNull);
        expect(
          (await repository.readSetupEvaluation(day)).state,
          SetupEvalState.pending,
        );
      },
    );

    test(
      'unrelated putDayResult after a failed nap job stays failed',
      () async {
        final revision = await LocalDb.commitNapLedger(
          dayId: day,
          puts: [
            (
              startTs: 1000,
              endTs: 2800,
              source: 'manual',
              originStartTs: null,
              originEndTs: null,
            ),
          ],
        );
        expect(
          await LocalDb.updateNapRecalcJob(
            dayId: day,
            revision: revision,
            status: 'failed',
            error: 'failed',
            fromStatuses: const {'pending'},
          ),
          isTrue,
        );
        await putResult();
        final job = await LocalDb.napRecalcJob(day);
        expect(job!['status'], 'failed');
        expect(job['result_computed_at'], isNull);
        expect(
          (await repository.readSetupEvaluation(day)).state,
          SetupEvalState.failed,
        );
      },
    );

    test('complete job result metadata lets the current row stand', () async {
      await LocalDb.putOpenBandSleepDraft(
        dayId: day,
        draftId: 'draft',
        onsetMs: DateTime(2026, 9, 14, 23).millisecondsSinceEpoch,
        wakeMs: DateTime(2026, 9, 15, 7).millisecondsSinceEpoch,
      );
      await LocalDb.commitOpenBandSleepCorrection(
        dayId: day,
        draftId: 'draft',
        onsetMs: DateTime(2026, 9, 14, 23).millisecondsSinceEpoch,
        wakeMs: DateTime(2026, 9, 15, 7).millisecondsSinceEpoch,
      );
      await putResult();
      final computed = ((await LocalDb.dayResult(day))!['computed_at'] as num)
          .toInt();
      final current = await LocalDb.openBandSleepCorrection(day);
      expect(
        await LocalDb.updateOpenBandCalculationJob(
          dayId: day,
          correctionId: current!['correction_id'] as String,
          revision: (current['revision'] as num).toInt(),
          status: 'complete',
          resultAlgoVersion: kAlgoVersion,
          resultComputedAt: computed,
          fromStatuses: const {'pending'},
        ),
        isTrue,
      );
      final job = await LocalDb.openBandSleepCorrection(day);
      expect(job!['status'], 'complete');
      expect(job['result_algo_version'], kAlgoVersion);
      expect(job['result_computed_at'], computed);
      expect(
        (await repository.readSetupEvaluation(day)).state,
        SetupEvalState.complete,
      );
    });

    test('failed sleep job wins over a pending nap job', () async {
      await putResult();
      final napRevision = await LocalDb.commitNapLedger(
        dayId: day,
        puts: [
          (
            startTs: 1000,
            endTs: 2800,
            source: 'manual',
            originStartTs: null,
            originEndTs: null,
          ),
        ],
      );
      await LocalDb.putOpenBandSleepDraft(
        dayId: day,
        draftId: 'draft-fail',
        onsetMs: DateTime(2026, 9, 14, 23).millisecondsSinceEpoch,
        wakeMs: DateTime(2026, 9, 15, 7).millisecondsSinceEpoch,
      );
      await LocalDb.commitOpenBandSleepCorrection(
        dayId: day,
        draftId: 'draft-fail',
        onsetMs: DateTime(2026, 9, 14, 23).millisecondsSinceEpoch,
        wakeMs: DateTime(2026, 9, 15, 7).millisecondsSinceEpoch,
      );
      final sleep = await LocalDb.openBandSleepCorrection(day);
      expect(
        await LocalDb.updateOpenBandCalculationJob(
          dayId: day,
          correctionId: sleep!['correction_id'] as String,
          revision: (sleep['revision'] as num).toInt(),
          status: 'failed',
          error: 'failed',
          fromStatuses: const {'pending'},
        ),
        isTrue,
      );
      expect((await LocalDb.napRecalcJob(day))!['revision'], napRevision);
      expect((await LocalDb.napRecalcJob(day))!['status'], 'pending');
      expect(
        (await repository.readSetupEvaluation(day)).state,
        SetupEvalState.failed,
      );
    });

    test('failed nap job wins over a pending sleep job', () async {
      await putResult();
      await LocalDb.putOpenBandSleepDraft(
        dayId: day,
        draftId: 'draft-pending',
        onsetMs: DateTime(2026, 9, 14, 23).millisecondsSinceEpoch,
        wakeMs: DateTime(2026, 9, 15, 7).millisecondsSinceEpoch,
      );
      await LocalDb.commitOpenBandSleepCorrection(
        dayId: day,
        draftId: 'draft-pending',
        onsetMs: DateTime(2026, 9, 14, 23).millisecondsSinceEpoch,
        wakeMs: DateTime(2026, 9, 15, 7).millisecondsSinceEpoch,
      );
      final napRevision = await LocalDb.commitNapLedger(
        dayId: day,
        puts: [
          (
            startTs: 4000,
            endTs: 5800,
            source: 'manual',
            originStartTs: null,
            originEndTs: null,
          ),
        ],
      );
      expect(
        await LocalDb.updateNapRecalcJob(
          dayId: day,
          revision: napRevision,
          status: 'failed',
          error: 'failed',
          fromStatuses: const {'pending'},
        ),
        isTrue,
      );
      expect(
        (await LocalDb.openBandSleepCorrection(day))!['status'],
        'pending',
      );
      expect(
        (await repository.readSetupEvaluation(day)).state,
        SetupEvalState.failed,
      );
    });

    test('global deriving is not consulted', () async {
      expect(
        (await repository.readSetupEvaluation(day)).state,
        SetupEvalState.missing,
      );
      expect(app.deriving, isFalse);
    });
  });

  final now = DateTime(2026, 9, 15, 9, 41);
  final stored = DateTime(2026, 9, 15, 6, 54);
  final computed = DateTime(2026, 9, 15, 7, 12);
  final receiving = BandSnapshot(
    connection: BandConnection.connected,
    transfer: TransferState.receiving,
    latestStoredAt: stored,
  );

  SetupEvaluation eval(SetupEvalState state) => SetupEvaluation(
    day: day,
    currentAlgo: kAlgoVersion,
    storedAlgo: state == SetupEvalState.missing ? null : kAlgoVersion,
    computedAt: state == SetupEvalState.complete ? computed : null,
    state: state,
  );

  Future<void> pumpPaper(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double width = 393,
    double height = 852,
    double scale = 1,
    BandSnapshot? band,
    SetupEvaluation? evaluation,
    bool evalError = false,
    bool bandError = false,
    bool receivingTransfer = true,
    SetupEvalState state = SetupEvalState.missing,
    VoidCallback? onResume,
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
        darkTheme: openBandTheme(
          Brightness.dark,
        ).copyWith(platform: TargetPlatform.iOS),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: Theme(
            data: openBandTheme(
              brightness,
            ).copyWith(platform: TargetPlatform.iOS),
            child: FirstSyncView(
              now: now,
              onDone: () {},
              onResume: onResume,
              synthetic: true,
              band:
                  band ??
                  (receivingTransfer
                      ? receiving
                      : BandSnapshot(
                          connection: BandConnection.connected,
                          latestStoredAt: stored,
                        )),
              evaluation: evaluation ?? eval(state),
              evalError: evalError,
              bandError: bandError,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Paper interrupted first-sync frames', (tester) async {
    final interrupted = BandSnapshot(
      connection: BandConnection.connected,
      transfer: TransferState.interrupted,
      latestStoredAt: DateTime(2026, 9, 15, 2, 10),
    );
    await pumpPaper(tester, band: interrupted, onResume: () {});
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/first-sync-interrupted-light.png'),
    );
    await pumpPaper(
      tester,
      brightness: Brightness.dark,
      band: interrupted,
      onResume: () {},
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/first-sync-interrupted-dark.png'),
    );
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Fortsetzen')).height,
      greaterThanOrEqualTo(44),
    );
    expect(find.text('bis 02:10'), findsOneWidget);
  });

  testWidgets('Paper first-sync frames', (tester) async {
    await pumpPaper(tester);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/first-sync-light.png'),
    );
    await pumpPaper(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/first-sync-dark.png'),
    );
    await pumpPaper(
      tester,
      receivingTransfer: false,
      state: SetupEvalState.complete,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/first-sync-complete.png'),
    );
    await pumpPaper(
      tester,
      brightness: Brightness.dark,
      state: SetupEvalState.partial,
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/first-sync-partial-dark.png'),
    );
    await pumpPaper(tester, evalError: true);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/first-sync-read-error.png'),
    );
    await pumpPaper(tester, width: 375, height: 812, scale: 2);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/first-sync-375-2x.png'),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Auswertung heute'), findsOneWidget);
    expect(tester.getSize(find.byTooltip('Information')).height, 44);
    expect(find.byTooltip('Zurück'), findsNothing);
  });
}
