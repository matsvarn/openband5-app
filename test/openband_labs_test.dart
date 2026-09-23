import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/data/lab_catalogue.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/health.dart';
import 'package:openstrap_edge/openband/labs.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/ui2/profile/profile.dart' show SetRow;

SyntheticOpenBandRepository galleryRepo() =>
    SyntheticOpenBandRepository.fromMaps(
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
  setUp(() => repo = galleryRepo());

  Future<void> mountLabs(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    double width = 393,
    double height = 852,
    DateTime Function()? now,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
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
          child: RepaintBoundary(key: const ValueKey('capture'), child: child!),
        ),
        home: OpenBandLabs(
          repository: repo,
          now: now ?? () => DateTime(2026, 9, 18, 9, 41),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('comma and dot parse, mixed separators and non-finite refuse', () {
    expect(LabParse.of('52').value, 52);
    expect(LabParse.of('52,5').value, 52.5);
    expect(LabParse.of('52.5').value, 52.5);
    expect(LabParse.of('1.5,0').bad, isTrue);
    expect(LabParse.of('Infinity').bad, isTrue);
    expect(LabParse.of('').blank, isTrue);
    expect(labDayLabel('2026-09-15'), '15. September 2026');
    expect(labDayLabel('2026-06-12'), '12. Juni 2026');
    expect(labDayLabel('2026-03-04'), '4. März 2026');
    expect(labBoundsError(LabParse.of('30'), LabParse.of('400')), isNull);
    expect(labBoundsError(LabParse.of('400'), LabParse.of('30')), isNotNull);
    expect(labBoundsError(LabParse.of('30'), LabParse.of('')), isNull);
    expect(
      labFormatValue(
        const LabDraw(
          marker: 'alt',
          takenOn: '2026-09-15',
          value: double.nan,
          unit: 'U/L',
        ),
        null,
      ),
      '—',
    );
    expect(
      labReportText(
        const LabDraw(
          marker: 'vitamin_d',
          takenOn: '2026-09-15',
          value: 37,
          unit: 'ng/mL',
        ),
        null,
      ),
      '—',
    );
  });

  test('unknown sex abstains from ferritin catalogue range', () {
    expect(kLabMarkersByKey['ferritin']!.rangeFor(null), isNull);
    expect(kLabMarkersByKey['ferritin']!.inRange(52, sex: null), isNull);
  });

  test('synthetic snapshot matches the gallery figures', () async {
    final snap = await repo.readLabs();
    expect(snap.sex, isNull);
    final ferritin = snap.results.where((r) => r.marker == 'ferritin').toList();
    expect(ferritin.map((r) => r.value), [52, 46, 33]);
    expect(ferritin.first.reportLow, 30);
    expect(ferritin.first.reportHigh, 400);
    expect(
      snap.results.where((r) => r.marker == 'vitamin_d').single.reportLow,
      isNull,
    );
  });

  test('same-day save collides until explicitly replaced', () async {
    await expectLater(
      repo.saveLabDraw(
        const LabDraw(
          marker: 'ferritin',
          takenOn: '2026-09-15',
          value: 99,
          unit: 'ng/mL',
        ),
      ),
      throwsA(isA<LabDrawCollision>()),
    );
    await repo.saveLabDraw(
      const LabDraw(
        marker: 'ferritin',
        takenOn: '2026-09-15',
        value: 99,
        unit: 'ng/mL',
        reportLow: 30,
        reportHigh: 400,
      ),
      replaceExisting: true,
    );
    expect(
      (await repo.readLabs()).results
          .firstWhere(
            (r) => r.marker == 'ferritin' && r.takenOn == '2026-09-15',
          )
          .value,
      99,
    );
  });

  test('date move is atomic and keeps the source on collision', () async {
    await expectLater(
      repo.saveLabDraw(
        const LabDraw(
          marker: 'ferritin',
          takenOn: '2026-09-15',
          value: 33,
          unit: 'ng/mL',
        ),
        replacing: const LabDraw(
          marker: 'ferritin',
          takenOn: '2026-03-04',
          value: 33,
          unit: 'ng/mL',
        ),
      ),
      throwsA(isA<LabDrawCollision>()),
    );
    final snap = await repo.readLabs();
    expect(
      snap.results.any(
        (r) => r.marker == 'ferritin' && r.takenOn == '2026-03-04',
      ),
      isTrue,
    );
    await repo.saveLabDraw(
      const LabDraw(
        marker: 'ferritin',
        takenOn: '2026-04-01',
        value: 33,
        unit: 'ng/mL',
        reportLow: 30,
        reportHigh: 400,
      ),
      replacing: const LabDraw(
        marker: 'ferritin',
        takenOn: '2026-03-04',
        value: 33,
        unit: 'ng/mL',
      ),
    );
    final moved = await repo.readLabs();
    expect(
      moved.results.any(
        (r) => r.marker == 'ferritin' && r.takenOn == '2026-03-04',
      ),
      isFalse,
    );
    expect(
      moved.results.any(
        (r) => r.marker == 'ferritin' && r.takenOn == '2026-04-01',
      ),
      isTrue,
    );
  });

  test(
    'custom marker rename keeps the key and does not rewrite units',
    () async {
      await repo.saveLabMarkerDef(
        const LabMarkerDef(
          key: 'custom_kupfer',
          label: 'Kupfer',
          unit: 'µg/dL',
          category: 'other',
          decimals: 1,
        ),
      );
      await repo.saveLabDraw(
        const LabDraw(
          marker: 'custom_kupfer',
          takenOn: '2026-09-15',
          value: 90,
          unit: 'µg/dL',
        ),
      );
      await repo.saveLabMarkerDef(
        const LabMarkerDef(
          key: 'custom_kupfer',
          label: 'Kupfer (Serum)',
          unit: 'µmol/L',
          category: 'other',
          decimals: 1,
        ),
      );
      final snap = await repo.readLabs();
      expect(snap.custom.single.key, 'custom_kupfer');
      expect(snap.custom.single.label, 'Kupfer (Serum)');
      expect(
        snap.results.firstWhere((r) => r.marker == 'custom_kupfer').unit,
        'µg/dL',
      );
      await expectLater(
        repo.deleteLabMarkerDef('custom_kupfer'),
        throwsStateError,
      );
    },
  );

  test(
    'custom create refuses a slug collision and unique-ifies empty slugs',
    () async {
      expect(customLabMarkerKey('銅'), 'custom_');
      expect(allocateCustomLabMarkerKey('銅', const []), 'custom_1');
      expect(
        allocateCustomLabMarkerKey('Медь', const ['custom_1']),
        'custom_2',
      );
      await repo.saveLabMarkerDef(
        const LabMarkerDef(
          key: 'custom_kupfer',
          label: 'Kupfer',
          unit: 'µg/dL',
          category: 'other',
          decimals: 1,
        ),
        create: true,
      );
      await expectLater(
        repo.saveLabMarkerDef(
          const LabMarkerDef(
            key: 'custom_kupfer',
            label: 'Kupfer (Serum)',
            unit: 'µmol/L',
            category: 'other',
            decimals: 1,
          ),
          create: true,
        ),
        throwsA(isA<LabMarkerCollision>()),
      );
      expect((await repo.readLabs()).custom.single.label, 'Kupfer');
      expect((await repo.readLabs()).custom.single.unit, 'µg/dL');
    },
  );

  testWidgets('health hub reaches Laborwerte', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = OpenBandController(
      repository: repo,
      initialDay: '2026-09-15',
      band: repo.band,
      now: () => DateTime(2026, 9, 18, 9, 41),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
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
        home: Scaffold(body: OpenBandHealth(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    final labs = find.byKey(const ValueKey('laborwerte'));
    await tester.scrollUntilVisible(
      labs,
      200,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(labs, findsOneWidget);
    await tester.tap(labs);
    await tester.pumpAndSettle();
    expect(find.text('Vitamin B12'), findsOneWidget);
    expect(find.text('Vitamin D (25-OH)'), findsOneWidget);
    expect(find.text('Ferritin'), findsOneWidget);
  });

  testWidgets('SetRow stays 52px at 1x and grows for a wrapped 2x label', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> mount({
      required Size size,
      required double scale,
      required double width,
      required String label,
    }) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: openBandTheme(
            Brightness.light,
          ).copyWith(platform: TargetPlatform.iOS),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              children: [
                SizedBox(
                  width: width,
                  child: Builder(
                    builder: (context) {
                      final p = OB.of(context);
                      return SetRow(
                        LucideIcons.flaskConical,
                        p.muted,
                        label,
                        onTap: () {},
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await mount(
      size: const Size(393, 852),
      scale: 1,
      width: 333,
      label: 'Laborwerte',
    );
    expect(tester.takeException(), isNull);
    final paper = tester.getRect(find.byType(SetRow));
    expect(paper.height, 52);
    expect(paper.height, greaterThanOrEqualTo(44));

    await mount(
      size: const Size(320, 812),
      scale: 2,
      width: 240,
      label: 'Laborwerte mit einem sehr langen selbstgewählten Marker-Namen',
    );
    expect(tester.takeException(), isNull);
    final wrapped = tester.getRect(find.byType(SetRow));
    expect(wrapped.height, greaterThan(52));
    expect(wrapped.height, greaterThanOrEqualTo(44));
    expect(
      find.text(
        'Laborwerte mit einem sehr langen selbstgewählten Marker-Namen',
      ),
      findsOneWidget,
    );
  });

  testWidgets('list, detail, editor, keyboard', (tester) async {
    await mountLabs(tester);
    expect(find.text('Laborwerte'), findsOneWidget);
    expect(
      tester.getRect(find.text('Laborwerte')).top,
      greaterThanOrEqualTo(59),
    );
    expect(find.text('Vitamin B12'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/labs-list.png'),
    );

    await tester.tap(find.byKey(const ValueKey('lab-ferritin')));
    await tester.pumpAndSettle();
    expect(find.textContaining('30–400'), findsWidgets);
    expect(find.textContaining('52'), findsWidgets);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/labs-detail.png'),
    );

    await tester.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
    await tester.pumpAndSettle();
    expect(find.text('Wert bearbeiten'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/labs-editor.png'),
    );
    await tester.tap(find.byKey(const ValueKey('lab-value')));
    await tester.enterText(find.byKey(const ValueKey('lab-value')), '53');
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/labs-editor-keyboard.png'),
    );
  }, tags: const ['golden']);

  testWidgets('dark list, detail, editor', (tester) async {
    await mountLabs(tester, brightness: Brightness.dark);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/labs-list-dark.png'),
    );
    await tester.tap(find.byKey(const ValueKey('lab-ferritin')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/labs-detail-dark.png'),
    );
    await tester.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/labs-editor-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('save failure keeps the draft', (tester) async {
    await mountLabs(tester);
    await tester.tap(find.byKey(const ValueKey('lab-ferritin')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
    await tester.pumpAndSettle();
    repo.failLabWrites = true;
    await tester.enterText(find.byKey(const ValueKey('lab-value')), '53');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut speichern'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/labs-save-failure.png'),
    );
    repo.failLabWrites = false;
    await tester.tap(find.text('Erneut speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Wert bearbeiten'), findsNothing);
    expect(
      (await repo.readLabs()).results
          .firstWhere(
            (r) => r.marker == 'ferritin' && r.takenOn == '2026-09-15',
          )
          .value,
      53,
    );
  }, tags: const ['golden']);

  testWidgets('empty labs', (tester) async {
    for (final r in List.of((await repo.readLabs()).results)) {
      await repo.deleteLabDraw(r.marker, r.takenOn);
    }
    expect((await repo.readLabs()).results, isEmpty);
    await mountLabs(tester);
    expect(find.text('Keine Laborwerte'), findsOneWidget);
    expect(find.text('Keine Laborwerte.'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('lab-empty'))).height,
      greaterThanOrEqualTo(132),
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/labs-empty.png'),
    );
  }, tags: const ['golden']);

  testWidgets('Paper list has no row dividers; hero date sits in the card', (
    tester,
  ) async {
    await mountLabs(tester);
    expect(find.byType(Divider), findsNothing);

    await tester.tap(find.byKey(const ValueKey('lab-ferritin')));
    await tester.pumpAndSettle();
    expect(find.text('Ferritin'), findsWidgets);
    expect(find.text('15. September 2026'), findsOneWidget);
    expect(find.text('Befundbereich'), findsWidgets);
    expect(find.byType(Divider), findsNothing);
    final date = tester.getRect(find.text('15. September 2026'));
    final value = find
        .text('52')
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)))
        .reduce((a, b) => a.height >= b.height ? a : b);
    expect(date.bottom, lessThan(value.top));
    final unit = tester.getRect(find.text('ng/mL').first);
    expect((value.bottom - unit.bottom).abs(), lessThan(20));
    final befund = tester.getRect(find.text('Befundbereich').first);
    final range = tester.getRect(find.textContaining('30–400').first);
    expect((befund.center.dy - range.center.dy).abs(), lessThan(4));
  });

  testWidgets('editor Marker and Datum wells fill the card', (tester) async {
    await mountLabs(tester);
    await tester.tap(find.byKey(const ValueKey('lab-ferritin')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
    await tester.pumpAndSettle();
    final marker = tester.getSize(find.byKey(const ValueKey('lab-marker')));
    final taken = tester.getSize(find.byKey(const ValueKey('lab-date')));
    expect(marker.width, greaterThan(300));
    expect(taken.width, closeTo(marker.width, 1));
    final unit = tester.getSize(find.byKey(const ValueKey('lab-unit')));
    final value = tester.getSize(find.byKey(const ValueKey('lab-value')));
    expect(unit.width, closeTo(112, 1));
    expect(value.width, greaterThan(unit.width));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('lab-value')))
          .style
          ?.fontWeight,
      FontWeight.w400,
    );
  });

  testWidgets('missing report range stays unknown', (tester) async {
    await mountLabs(tester);
    await tester.tap(find.byKey(const ValueKey('lab-vitamin_d')));
    await tester.pumpAndSettle();
    expect(find.text('Befundbereich unbekannt'), findsNothing);
    expect(find.text('Befundbereich'), findsWidgets);
    expect(find.text('—'), findsWidgets);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/labs-bounds-missing.png'),
    );
  }, tags: const ['golden']);

  testWidgets('custom marker editor', (tester) async {
    await mountLabs(tester);
    await tester.tap(find.text('Eigene Marker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marker anlegen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lab-def-name')),
      'Kupfer',
    );
    await tester.enterText(find.byKey(const ValueKey('lab-def-unit')), 'µg/dL');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final decimals = tester.getRect(
      find.byKey(const ValueKey('lab-def-decimals')),
    );
    final unit = tester.getRect(find.byKey(const ValueKey('lab-def-unit')));
    expect((decimals.center.dy - unit.center.dy).abs(), lessThan(2));
    expect(unit.width, closeTo(112, 1));
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/labs-custom-marker.png'),
    );
  }, tags: const ['golden']);

  testWidgets('dark custom marker editor', (tester) async {
    await mountLabs(tester, brightness: Brightness.dark);
    await tester.tap(find.text('Eigene Marker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marker anlegen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lab-def-name')),
      'Kupfer',
    );
    await tester.enterText(find.byKey(const ValueKey('lab-def-unit')), 'µg/dL');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/labs-custom-marker-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('custom marker preflight read failure keeps the draft', (
    tester,
  ) async {
    await mountLabs(tester);
    await tester.tap(find.text('Eigene Marker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marker anlegen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lab-def-name')),
      'Kupfer',
    );
    await tester.enterText(find.byKey(const ValueKey('lab-def-unit')), 'µg/dL');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    repo.failLabReads = true;
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
    expect(find.text('Erneut speichern'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('lab-def-name')))
          .controller!
          .text,
      'Kupfer',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('lab-def-unit')))
          .controller!
          .text,
      'µg/dL',
    );
    repo.failLabReads = false;
    expect((await repo.readLabs()).custom, isEmpty);
    await tester.tap(find.text('Erneut speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Eigener Marker'), findsNothing);
    expect((await repo.readLabs()).custom.single.label, 'Kupfer');
  });

  testWidgets('custom marker save ignores a second tap', (tester) async {
    await mountLabs(tester);
    await tester.tap(find.text('Eigene Marker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marker anlegen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lab-def-name')),
      'Kupfer',
    );
    await tester.enterText(find.byKey(const ValueKey('lab-def-unit')), 'µg/dL');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    repo.beforeLabWrite = () => gate.future;
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    expect(repo.labWriteCount, 0);
    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.labWriteCount, 1);
    expect((await repo.readLabs()).custom, hasLength(1));
  });

  testWidgets('custom decimals and unit stack at large text', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
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
            textScaler: const TextScaler.linear(2),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: OpenBandLabMarkerEditor(repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    final decimals = tester.getRect(
      find.byKey(const ValueKey('lab-def-decimals')),
    );
    final unit = tester.getRect(find.byKey(const ValueKey('lab-def-unit')));
    expect(decimals.bottom, lessThanOrEqualTo(unit.top));
  });

  testWidgets('large text list, detail, editor', (tester) async {
    await mountLabs(tester, scale: 2, width: 375, height: 812);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/labs-list-large.png'),
    );
    await tester.tap(find.byKey(const ValueKey('lab-ferritin')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/labs-detail-large.png'),
    );
    await tester.tap(find.byKey(const ValueKey('lab-hist-2026-09-15')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/labs-editor-large.png'),
    );
  }, tags: const ['golden']);

  testWidgets('busy save does not double-write', (tester) async {
    await mountLabs(tester);
    await tester.tap(find.text('Wert hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('lab-search')), 'Ferr');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ferritin'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('lab-value')), '40');
    await tester.enterText(find.byKey(const ValueKey('lab-unit')), 'ng/mL');
    final gate = Completer<void>();
    repo.beforeLabWrite = () => gate.future;
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    expect(repo.labWriteCount, 0);
    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.labWriteCount, 1);
    expect(
      (await repo.readLabs()).results.where(
        (r) => r.marker == 'ferritin' && r.takenOn == '2026-09-18',
      ),
      hasLength(1),
    );
  });

  testWidgets('load error can retry', (tester) async {
    repo.failLabReads = true;
    await mountLabs(tester);
    expect(find.text('Laborwerte nicht geladen.'), findsOneWidget);
    repo.failLabReads = false;
    await tester.tap(find.text('Erneut laden'));
    await tester.pumpAndSettle();
    expect(find.text('Ferritin'), findsOneWidget);
  });

  testWidgets('same-day add asks before replacing', (tester) async {
    await mountLabs(tester, now: () => DateTime(2026, 9, 15, 9, 41));
    await tester.tap(find.text('Wert hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('lab-search')), 'Ferr');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ferritin'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('lab-value')), '40');
    await tester.enterText(find.byKey(const ValueKey('lab-unit')), 'ng/mL');
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Wert überschreiben?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.text('Wert hinzufügen'), findsOneWidget);
    expect(
      (await repo.readLabs()).results
          .firstWhere(
            (r) => r.marker == 'ferritin' && r.takenOn == '2026-09-15',
          )
          .value,
      52,
    );
  });

  testWidgets('unreadable rows stay explicit', (tester) async {
    repo.seedLabDraw(
      const LabDraw(
        marker: 'alt',
        takenOn: '2026-09-15',
        value: double.nan,
        unit: 'U/L',
      ),
    );
    await mountLabs(tester);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('unlesbar'), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'unlesbar')), findsOneWidget);
  });
}
