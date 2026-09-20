import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';
import 'package:openstrap_edge/ui2/grammar.dart';

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

  for (final width in const [320.0, 375.0, 393.0]) {
    for (final scale in const [1.0, 2.0]) {
      final tag = scale == 1.0 ? '1x' : '2x';
      testWidgets('AppShell tabs at ${width.toInt()} · $tag', (tester) async {
        await _pumpShell(tester, width: width, scale: scale);

        _expectLabelsSingleLineInBounds(tester);
        _expectHitTargets(tester);
        if (scale == 2.0) {
          expect(
            tester
                .renderObject<RenderParagraph>(find.text('page:home'))
                .textScaler
                .scale(10),
            20,
          );
          expect(
            tester
                .renderObject<RenderParagraph>(
                  find.text(ShellDomain.home.label),
                )
                .textScaler
                .scale(10),
            10,
          );
        }

        for (final domain in ShellDomain.values) {
          await tester.tap(find.bySemanticsLabel(domain.label));
          await tester.pumpAndSettle();
          _expectSelected(tester, domain);
          expect(find.text('page:${domain.name}'), findsOneWidget);
        }

        if (scale == 2.0) {
          expect(
            tester
                .renderObject<RenderParagraph>(find.text('page:wellness'))
                .textScaler
                .scale(10),
            20,
          );
        }
      });
    }
  }
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required double width,
  required double scale,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 852);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('de'),
      debugShowCheckedModeBanner: false,
      theme: openBandTheme(
        Brightness.light,
      ).copyWith(platform: TargetPlatform.iOS),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(top: 59, bottom: 34),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: AppShell(
        builder: (_, domain) => Center(
          child: Text(
            'page:${domain.name}',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              height: 1,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectLabelsSingleLineInBounds(WidgetTester tester) {
  final shell = tester.getRect(find.byType(AppShell));
  final widths = <double>[];
  for (final domain in ShellDomain.values) {
    final label = find.text(domain.label);
    expect(label, findsOneWidget, reason: '${domain.label} missing');
    final paragraph = tester.renderObject<RenderParagraph>(label);
    expect(
      paragraph.size.height,
      lessThanOrEqualTo(14),
      reason:
          '${domain.label} must stay on one line (h=${paragraph.size.height})',
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    final labelRect = tester.getRect(label);
    final tabRect = tester.getRect(find.bySemanticsLabel(domain.label));
    expect(
      shell.inflate(0.5).overlaps(labelRect) &&
          shell.left - 0.5 <= labelRect.left &&
          labelRect.right <= shell.right + 0.5 &&
          shell.top - 0.5 <= labelRect.top &&
          labelRect.bottom <= shell.bottom + 0.5,
      isTrue,
      reason: '${domain.label} $labelRect outside shell $shell',
    );
    expect(
      labelRect.left + 0.5 >= tabRect.left &&
          labelRect.right - 0.5 <= tabRect.right &&
          labelRect.top + 0.5 >= tabRect.top &&
          labelRect.bottom - 0.5 <= tabRect.bottom,
      isTrue,
      reason: '${domain.label} $labelRect outside tab $tabRect',
    );
    widths.add(tabRect.width);
  }
  expect(widths.toSet(), hasLength(1), reason: 'tabs must share equal width');
}

void _expectHitTargets(WidgetTester tester) {
  for (final domain in ShellDomain.values) {
    final rect = tester.getRect(find.bySemanticsLabel(domain.label));
    expect(
      rect.height,
      greaterThanOrEqualTo(44),
      reason: '${domain.label} hit height ${rect.height}',
    );
    expect(
      rect.width,
      greaterThanOrEqualTo(44),
      reason: '${domain.label} hit width ${rect.width}',
    );
  }
  for (final pressable in tester.widgetList<Pressable>(
    find.byType(Pressable),
  )) {
    final size = tester.getSize(find.byWidget(pressable));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
  }
}

void _expectSelected(WidgetTester tester, ShellDomain current) {
  for (final domain in ShellDomain.values) {
    final flags = tester
        .getSemantics(find.bySemanticsLabel(domain.label))
        .flagsCollection;
    expect(flags.isButton, isTrue, reason: domain.label);
    expect(
      flags.isSelected.toBoolOrNull(),
      domain == current,
      reason: '${domain.label} selected=${domain == current}',
    );
  }
}
