import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/journal.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';

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
    );
  });
  tearDown(() => controller.dispose());

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de')],
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: Scaffold(
            body: OpenBandJournal(controller: controller, onEdit: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('journal hub renders, mood answer persists', (tester) async {
    await mount(tester);
    expect(find.text('Journal'), findsOneWidget);
    expect(find.text('Noch keine Antwort'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('Ja'), findsNWidgets(3));
    expect(find.textContaining('Noch zu wenige'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-light.png'),
    );
    await tester.tap(find.bySemanticsLabel('Gut'));
    await tester.pumpAndSettle();
    expect(find.text('Gut'), findsOneWidget);
    expect(
      (await repo.readJournal('2026-09-15')).single,
      isA<JournalEntry>()
          .having((e) => e.key, 'key', 'mood')
          .having((e) => e.value, 'value', 4),
    );
    await mount(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-dark.png'),
    );
  });

  testWidgets('yes/no answers persist as 1/0; absence stays open', (
    tester,
  ) async {
    await repo.writeJournal('2026-09-15', 'caffeine_mg', 180);
    await mount(tester);
    expect(find.text('1 erfasst'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Koffein nach 14 Uhr: Ja'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Alkohol am Abend: Nein'));
    await tester.pumpAndSettle();
    final byKey = {
      for (final e in await repo.readJournal('2026-09-15')) e.key: e.value,
    };
    expect(byKey['caffeine_late'], 1);
    expect(byKey['alcohol_evening'], 0);
    expect(byKey.containsKey('read_before_bed'), isFalse);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-answered.png'),
    );
  });

  test('pattern pairs the answer day with the following night', () {
    final days = openBandDaysEnding('2026-09-05', 5);
    final s = summarizePattern(
      {'2026-09-01': 1, '2026-09-02': 0, '2026-09-03': 1, '2026-09-04': null},
      {'2026-09-02': 40, '2026-09-03': 50, '2026-09-04': 44, '2026-09-05': 99},
      days,
    );
    expect(s.yes.nights, 2);
    expect(s.yes.mean, 42);
    expect(s.no.nights, 1);
    expect(s.no.mean, 50);
  });

  testWidgets('pattern card stays open below three nights per side', (
    tester,
  ) async {
    for (var i = 1; i <= 8; i++) {
      await repo.writeJournal(
        '2026-09-${(i + 5).toString().padLeft(2, '0')}',
        'caffeine_late',
        i.isEven ? 1 : 0,
      );
    }
    await mount(tester);
    expect(find.textContaining('Noch zu wenige'), findsNothing);
    expect(find.textContaining('kein Beweis'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/journal-pattern.png'),
    );
    final thin = await repo.readPattern(
      'read_before_bed',
      MetricKey.hrv,
      '2026-09-15',
      30,
    );
    expect(thin.yes.nights, 0);
  });
}
