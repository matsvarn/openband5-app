import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/health.dart';
import 'package:openstrap_edge/openband/theme.dart';

const _labels = ['Tag', 'Woche', 'Lebensmittel'];

/// Scales 14pt like 2x but leaves 18pt unscaled, so scale(18) would clip.
class _NonLinearScaler extends TextScaler {
  const _NonLinearScaler();
  @override
  double scale(double fontSize) => fontSize <= 14 ? fontSize * 2 : fontSize;
  @override
  double get textScaleFactor => 2;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
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
  });

  Finder well(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(InkWell));

  bool inside(Rect outer, Rect inner) =>
      outer.left <= inner.left + 0.5 &&
      outer.right >= inner.right - 0.5 &&
      outer.top <= inner.top + 0.5 &&
      outer.bottom >= inner.bottom - 0.5;

  Future<void> mount(
    WidgetTester tester, {
    required List<String> labels,
    int selected = 0,
    List<bool>? enabled,
    ValueChanged<int>? onChanged,
    bool compact = false,
    double scale = 1,
    TextScaler? scaler,
    double width = 393,
    double height = 852,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final p = OB(brightness == Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: openBandTheme(brightness).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: Size(width, height),
            textScaler: scaler ?? TextScaler.linear(scale),
            padding: EdgeInsets.zero,
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  key: const ValueKey('capture'),
                  child: Material(
                    color: p.canvas,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: compact
                            ? OBSegmented(
                                compact: true,
                                labels: labels,
                                selected: selected,
                                enabled: enabled,
                                onChanged: onChanged ?? (_) {},
                              )
                            : OBSegmented(
                                labels: labels,
                                selected: selected,
                                enabled: enabled,
                                onChanged: onChanged ?? (_) {},
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectHorizontal(WidgetTester tester, {required double contentWidth}) {
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(OBSegmented)).width, contentWidth);
    expect(tester.getSize(find.byType(OBSegmented)).height, 44);
    expect(tester.getSize(find.text('Tag')).height, 18);
    final tag = tester.getRect(well('Tag'));
    final woche = tester.getRect(well('Woche'));
    final food = tester.getRect(well('Lebensmittel'));
    expect(tag.height, greaterThanOrEqualTo(44));
    expect(woche.height, greaterThanOrEqualTo(44));
    expect(food.height, greaterThanOrEqualTo(44));
    expect(tag.top, closeTo(woche.top, 0.5));
    expect(woche.top, closeTo(food.top, 0.5));
    expect(inside(tag, tester.getRect(find.text('Tag'))), isTrue);
    expect(inside(woche, tester.getRect(find.text('Woche'))), isTrue);
    expect(inside(food, tester.getRect(find.text('Lebensmittel'))), isTrue);
  }

  void expectStacked52(WidgetTester tester, {required double contentWidth}) {
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(OBSegmented)).width, contentWidth);
    final tag = tester.getRect(well('Tag'));
    final woche = tester.getRect(well('Woche'));
    final food = tester.getRect(well('Lebensmittel'));
    expect(tag.height, 52);
    expect(woche.height, 52);
    expect(food.height, 52);
    expect(woche.top - tag.bottom, 2);
    expect(food.top - woche.bottom, 2);
    expect(tester.getSize(find.byType(OBSegmented)).height, 166);
    expect(tester.getSize(find.text('Tag')).height, 36);
    expect(tester.getSize(find.text('Lebensmittel')).height, 36);
    expect(inside(food, tester.getRect(find.text('Lebensmittel'))), isTrue);
  }

  testWidgets('393 device is 361 content and stays horizontal', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final taps = <int>[];
      await mount(tester, labels: _labels, selected: 1, onChanged: taps.add);
      expect(tester.getSize(find.byKey(const ValueKey('capture'))).width, 393);
      expectHorizontal(tester, contentWidth: 361);
      expect(
        tester
            .getSemantics(well('Woche'))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );
      expect(
        tester
            .getSemantics(well('Tag'))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isFalse,
      );
      await tester.tap(well('Lebensmittel'));
      await tester.pump();
      expect(taps, [2]);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/segmented-light.png'),
      );
    } finally {
      semantics.dispose();
    }
  }, tags: const ['golden']);

  testWidgets('dark 393 well uses card and inverse selected text', (
    tester,
  ) async {
    await mount(
      tester,
      labels: _labels,
      selected: 1,
      brightness: Brightness.dark,
    );
    expect(tester.getSize(find.byKey(const ValueKey('capture'))).width, 393);
    expectHorizontal(tester, contentWidth: 361);
    final chosen = tester.widget<Text>(find.text('Woche'));
    expect(chosen.style!.color, OB(true).canvas);
    expect(chosen.style!.fontWeight, FontWeight.w600);
    final idle = tester.widget<Text>(find.text('Tag'));
    expect(idle.style!.fontWeight, FontWeight.w500);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/segmented-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('375 nutrition stays horizontal at 343; weight does not flip', (
    tester,
  ) async {
    await mount(tester, labels: _labels, width: 375, height: 667, selected: 0);
    expectHorizontal(tester, contentWidth: 343);
    await mount(tester, labels: _labels, width: 375, height: 667, selected: 2);
    expectHorizontal(tester, contentWidth: 343);
    expect(tester.getSize(find.text('Lebensmittel')).height, 18);
  });

  testWidgets('375 at 2x stacks Paper 52pt rows without clipping', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester, labels: _labels, width: 375, height: 667, scale: 2);
      expect(tester.getSize(find.byKey(const ValueKey('capture'))).width, 375);
      expectStacked52(tester, contentWidth: 343);
      final style = tester.widget<Text>(find.text('Lebensmittel')).style!;
      expect(style.fontSize, 14);
      expect(style.height, 18 / 14);
      expect(tester.widget<Text>(find.text('Tag')).style!.color, Colors.white);
      expect(
        tester.widget<Text>(find.text('Tag')).style!.fontWeight,
        FontWeight.w600,
      );
      expect(
        tester
            .getSemantics(well('Tag'))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('openband_goldens/segmented-large.png'),
      );
    } finally {
      semantics.dispose();
    }
  }, tags: const ['golden']);

  testWidgets('375 dark 2x stacked goldens', (tester) async {
    await mount(
      tester,
      labels: _labels,
      width: 375,
      height: 667,
      scale: 2,
      brightness: Brightness.dark,
    );
    expect(tester.getSize(find.byKey(const ValueKey('capture'))).width, 375);
    expectStacked52(tester, contentWidth: 343);
    final chosen = tester.widget<Text>(find.text('Tag'));
    expect(chosen.style!.color, OB(true).canvas);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/segmented-large-dark.png'),
    );
  }, tags: const ['golden']);

  testWidgets('320 at 2x is 288 content, stacked, long labels unsplit', (
    tester,
  ) async {
    const long = 'Sehr langes Lebensmittel mit extra Text';
    await mount(
      tester,
      labels: const ['Tag', 'Woche', long],
      width: 320,
      height: 568,
      scale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(OBSegmented)).width, 288);
    expect(find.text(long), findsOneWidget);
    expect(find.textContaining('Lebensmit'), findsOneWidget);
    final food = tester.getRect(well(long));
    expect(food.height, greaterThanOrEqualTo(52));
    expect(inside(food, tester.getRect(find.text(long))), isTrue);
    expect(food.top, greaterThan(tester.getRect(well('Woche')).bottom));
  });

  testWidgets('nonlinear scaler uses font14 lineheight, not scale(18)', (
    tester,
  ) async {
    await mount(
      tester,
      labels: const ['Tag', 'OK'],
      scaler: const _NonLinearScaler(),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('Tag')).height, 36);
    final wellSize = tester.getSize(
      find
          .descendant(
            of: find.byType(IgnorePointer),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(wellSize.height, 42);
    expect(tester.getSize(find.byType(OBSegmented)).height, 44);
    expect(
      inside(tester.getRect(well('Tag')), tester.getRect(find.text('Tag'))),
      isTrue,
    );
  });

  testWidgets('disabled segments do not fire; enabled still do', (
    tester,
  ) async {
    final taps = <int>[];
    final semantics = tester.ensureSemantics();
    try {
      await mount(
        tester,
        labels: _labels,
        enabled: const [true, false, true],
        onChanged: taps.add,
      );
      await tester.tap(well('Woche'));
      await tester.pump();
      expect(taps, isEmpty);
      expect(
        tester
            .getSemantics(well('Woche'))
            .flagsCollection
            .isEnabled
            .toBoolOrNull(),
        isFalse,
      );
      await tester.tap(well('Lebensmittel'));
      await tester.pump();
      expect(taps, [2]);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('compact g/% geometry and 44pt taps stay accepted', (
    tester,
  ) async {
    var selected = 0;
    final taps = <int>[];
    final semantics = tester.ensureSemantics();
    try {
      Future<void> show({double scale = 1, List<bool>? enabled}) async {
        await mount(
          tester,
          compact: true,
          labels: const ['g', '%'],
          selected: selected,
          enabled: enabled,
          scale: scale,
          width: 393,
          onChanged: (i) {
            taps.add(i);
            selected = i;
          },
        );
      }

      await show();
      expect(tester.getSize(find.byType(OBSegmented)).width, 102);
      expect(tester.getSize(well('g')).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(well('%')).height, greaterThanOrEqualTo(44));
      await tester.tapAt(
        Offset(
          tester.getRect(well('%')).center.dx,
          tester.getRect(well('%')).top + 1,
        ),
      );
      await tester.pump();
      expect(selected, 1);
      expect(taps, [1]);

      taps.clear();
      await show(enabled: const [true, false]);
      await tester.tapAt(tester.getRect(well('%')).center);
      await tester.pump();
      expect(taps, isEmpty);
      expect(selected, 1);

      await show(scale: 2);
      expect(tester.getSize(find.byType(OBSegmented)).width, 146);
      expect(tester.getSize(well('g')).height, greaterThanOrEqualTo(44));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('empty and single label stay usable', (tester) async {
    await mount(tester, labels: const []);
    expect(tester.takeException(), isNull);
    expect(find.byType(OBSegmented), findsOneWidget);

    final taps = <int>[];
    await mount(tester, labels: const ['Nur'], onChanged: taps.add);
    expect(tester.takeException(), isNull);
    expect(find.text('Nur'), findsOneWidget);
    expect(tester.getSize(well('Nur')).height, greaterThanOrEqualTo(44));
    await tester.tap(well('Nur'));
    await tester.pump();
    expect(taps, [0]);
  });
}
