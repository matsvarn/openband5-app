import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/theme.dart';

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
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await icons.load();
  });

  Future<void> mount(
    WidgetTester tester, {
    String title = 'Medikamente',
    String subtitle = '',
    VoidCallback? onBack,
    VoidCallback? onInfo,
    VoidCallback? onDate,
    double scale = 1,
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
            textScaler: TextScaler.linear(scale),
            padding: EdgeInsets.zero,
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: RepaintBoundary(
              key: const ValueKey('capture'),
              child: Material(
                color: p.canvas,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OBPageHeader(
                    title: title,
                    subtitle: subtitle,
                    onBack: onBack,
                    onInfo: onInfo,
                    onDate: onDate,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('393 keeps heading between controls and fires callbacks', (
    tester,
  ) async {
    var backs = 0;
    var infos = 0;
    var dates = 0;
    await mount(
      tester,
      subtitle: 'Heute',
      onBack: () => backs++,
      onInfo: () => infos++,
      onDate: () => dates++,
    );
    final header = tester.getRect(find.byType(OBPageHeader));
    final back = tester.getRect(find.byTooltip('Zurück'));
    final info = tester.getRect(find.byTooltip('Information'));
    final title = tester.getRect(find.text('Medikamente'));
    expect(header.width, 361);
    expect(back.size, const Size(44, 44));
    expect(info.size, const Size(44, 44));
    expect(back.top, closeTo(info.top, 0.5));
    expect(title.left, greaterThan(back.right));
    expect(title.right, lessThan(info.left));
    expect(title.top, greaterThanOrEqualTo(back.top - 0.5));
    expect(title.bottom, lessThanOrEqualTo(back.bottom + 0.5));
    expect(title.height, 24);
    expect(
      tester.getRect(find.text('Heute')).top,
      closeTo(title.bottom + 2, 0.5),
    );
    await tester.tap(find.byTooltip('Zurück'));
    await tester.tap(find.byTooltip('Information'));
    await tester.tap(find.text('Medikamente'));
    expect(backs, 1);
    expect(infos, 1);
    expect(dates, 1);
  });

  testWidgets('375 2x places long heading below 44pt controls', (tester) async {
    var backs = 0;
    var infos = 0;
    var dates = 0;
    await mount(
      tester,
      width: 375,
      height: 667,
      scale: 2,
      subtitle: 'Heute',
      onBack: () => backs++,
      onInfo: () => infos++,
      onDate: () => dates++,
    );
    final header = tester.getRect(find.byType(OBPageHeader));
    final back = tester.getRect(find.byTooltip('Zurück'));
    final info = tester.getRect(find.byTooltip('Information'));
    final title = tester.getRect(find.text('Medikamente'));
    final subtitle = tester.getRect(find.text('Heute'));
    expect(header.width, 343);
    expect(back.size, const Size(44, 44));
    expect(info.size, const Size(44, 44));
    expect(back.top, closeTo(info.top, 0.5));
    expect(info.right, closeTo(header.right, 0.5));
    expect(title.top, closeTo(back.bottom + 8, 0.5));
    expect(title.height, 48);
    final lane = tester.getRect(
      find.descendant(
        of: find.byType(OBPageHeader),
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == double.infinity,
        ),
      ),
    );
    expect(lane.left, closeTo(header.left, 0.5));
    expect(lane.right, closeTo(header.right, 0.5));
    expect(lane.width, closeTo(header.width, 0.5));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Medikamente'),
    );
    expect(paragraph.constraints.maxWidth, closeTo(header.width, 0.5));
    expect(title.left, greaterThanOrEqualTo(header.left - 0.5));
    expect(title.right, lessThanOrEqualTo(header.right + 0.5));
    expect(title.width, lessThan(header.width));
    expect(
      (title.left + title.right) / 2,
      closeTo((header.left + header.right) / 2, 1),
    );
    expect(subtitle.top, closeTo(title.bottom + 2, 0.5));
    await tester.tap(find.byTooltip('Zurück'));
    await tester.tap(find.byTooltip('Information'));
    await tester.tap(find.text('Medikamente'));
    expect(backs, 1);
    expect(infos, 1);
    expect(dates, 1);
  });

  testWidgets('375 2x light golden', (tester) async {
    await mount(
      tester,
      width: 375,
      height: 667,
      scale: 2,
      onBack: () {},
      onInfo: () {},
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/header-large-light.png'),
    );
  }, tags: const ['golden']);

  testWidgets('375 2x dark golden', (tester) async {
    await mount(
      tester,
      width: 375,
      height: 667,
      scale: 2,
      brightness: Brightness.dark,
      onBack: () {},
      onInfo: () {},
    );
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('openband_goldens/header-large-dark.png'),
    );
  }, tags: const ['golden']);
}
