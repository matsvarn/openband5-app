// Shell structure, tap targets and overflow sweeps for the ui2 grammar.
//
// The component goldens that used to live here compared against test/goldens/,
// whose masters were purged from history; the group had been permanently
// skipped since. The sweeps below still render every gallery case.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// The cases are the GALLERY's cases. One list, so the pictures in here and
// the screen a developer opens on a phone cannot describe two different
// design systems — and so a component added to one is added to both.
import 'package:openstrap_edge/ui2/profile/gallery.dart';
import 'package:openstrap_edge/openband/release_scope.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

/// The golden is the component, not the page: capturing this boundary means a
/// PNG the size of the thing under test, and a diff that points at the card
/// that changed rather than at a screenshot of everything.
final _shot = GlobalKey();

Widget _frame(Widget child, Brightness b, double scale) => MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(b),
        home: Builder(
          builder: (c) => Scaffold(
            backgroundColor: P.of(c).bg,
            // Top-aligned, not centred: a component that grows past the
            // viewport at 2x text should be tall in the golden, not clipped
            // in the middle.
            // A scroll view, because that is what every real screen is: it
            // hands the component an unbounded height, so a card shrink-wraps
            // its content here exactly as it does in the app.
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(S.x4),
                child: RepaintBoundary(key: _shot, child: child),
              ),
            ),
          ),
        ),
      ),
    );

/// Load the bundled type so the goldens show words instead of the test
/// harness's block glyphs. A golden nobody can read is a golden nobody
/// reviews, and an unreviewed golden gets `--update-goldens`-ed over the top
/// of the bug it was supposed to catch.
///
/// The gallery mixes design systems: ui2 cases resolve `.SF Pro Text`→Manrope
/// while the `alpin()` OpenBand cases set `AlpFont` (Inter / Inter Tight) and
/// Lucide icons. Without those faces the overflow sweep measures the harness's
/// fallback blocks and reports overflows the real fonts don't have (the
/// `day_energy_floor`/`meal_row` 3.0x failures on Linux CI).
Future<void> _loadType() async {
  final files = Directory('assets/fonts/Manrope')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.ttf'));
  // Registered under both names. `.SF Pro Text` does not exist off Apple
  // hardware, so on Android and in the test harness the type IS Manrope —
  // registering it under the primary name makes the goldens show what a
  // non-Apple user actually sees, rather than the harness's fallback blocks.
  for (final family in const ['Manrope', '.SF Pro Text']) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(f
          .readAsBytes()
          .then((b) => ByteData.sublistView(Uint8List.fromList(b))));
    }
    await loader.load();
  }
  await (FontLoader('Inter')
        ..addFont(Future.value(ByteData.sublistView(
          File('assets/fonts/Inter/Inter.ttf').readAsBytesSync(),
        ))))
      .load();
  await (FontLoader('Inter Tight')
        ..addFont(Future.value(ByteData.sublistView(
          File('assets/fonts/InterTight/InterTight[wght].ttf')
              .readAsBytesSync(),
        ))))
      .load();
  await (FontLoader('packages/lucide_icons_flutter/Lucide')
        ..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
      .load();
}

void main() {
  // Swept for overflow and tap size below: everything, painters included.
  final all = galleryCases();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadType();
  });

  testWidgets('development shell retains all five domains',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: AppShell(
        builder: (c, d) => Center(child: Text(d.label)),
      ),
    ));
    expect(ShellDomain.values, [
      ShellDomain.home,
      ShellDomain.health,
      ShellDomain.workout,
      ShellDomain.wellness,
      ShellDomain.sleep,
    ]);
    for (final d in ShellDomain.values) {
      expect(find.text(d.label), findsWidgets, reason: '${d.label} tab missing');
    }
  });

  testWidgets('release shell shows Heute, Schlaf, Training and Journal',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: openBandTheme(Brightness.light),
      home: AppShell(
        domains: kOpenBandReleaseDomains,
        releaseStyle: true,
        builder: (c, d) => Center(child: Text(d.label)),
      ),
    ));
    expect(kOpenBandReleaseDomains, [
      ShellDomain.home,
      ShellDomain.sleep,
      ShellDomain.workout,
      ShellDomain.wellness,
    ]);
    for (final d in kOpenBandReleaseDomains) {
      expect(find.byKey(ValueKey('ob-tab-${d.name}')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('ob-tab-health')), findsNothing);
  });

  testWidgets('every tap target in the shell clears 44 pt', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: AppShell(builder: (c, d) => const SizedBox.shrink()),
    ));
    for (final e in tester.widgetList<Pressable>(find.byType(Pressable))) {
      if (e.onTap == null) continue;
      final size = tester.getSize(find.byWidget(e));
      expect(size.height, greaterThanOrEqualTo(S.tap),
          reason: '${e.semanticLabel} is ${size.height} pt tall');
      expect(size.width, greaterThanOrEqualTo(S.tap),
          reason: '${e.semanticLabel} is ${size.width} pt wide');
    }
  });

  // ── the tiers the PNGs do not cover ────────────────────────────────────
  //
  // iOS reaches 3.1x with Larger Accessibility Sizes and Android about 2.6x
  // effective, so 2.0x is not the ceiling — but 174 more images per tier is
  // 174 more images nobody reviews, and an unreviewed golden records the bug.
  // These two sweeps run the SAME case list past the top of the range and
  // assert the two things a picture would only show if somebody looked.
  //
  // Both also cover 1.0x, because F-06 was a component clipped at 1.0x that
  // four goldens photographed and nobody noticed.
  group('past the golden ceiling', () {
    for (final scale in const [1.0, 1.4, 2.0, 3.0, 3.1]) {
      testWidgets('nothing overflows at ${scale}x', (tester) async {
        tester.view.physicalSize = const Size(390 * 3, 4000 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final broke = <String>[];
        for (final e in all.entries) {
          final errors = <String>[];
          final previous = FlutterError.onError;
          FlutterError.onError = (d) => errors.add(d.exceptionAsString());
          await tester.pumpWidget(_frame(e.value, Brightness.light, scale));
          await tester.pump();
          FlutterError.onError = previous;
          for (final err in errors) {
            if (err.contains('overflowed')) broke.add('${e.key}: $err');
          }
        }
        expect(broke, isEmpty,
            reason: 'a card that overflows at an accessibility text size is a '
                'measurement pushed off the screen:\n${broke.join('\n')}');
      });
    }

    testWidgets('every tap target in every case clears 44 pt', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 4000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final small = <String>[];
      for (final e in all.entries) {
        await tester.pumpWidget(_frame(e.value, Brightness.light, 1.0));
        await tester.pump();
        for (final w in tester.widgetList<Pressable>(find.byType(Pressable))) {
          if (w.onTap == null) continue;
          final s = tester.getSize(find.byWidget(w));
          if (s.height < S.tap || s.width < S.tap) {
            small.add('${e.key} · ${w.semanticLabel ?? 'unlabelled'} '
                'is ${s.width} × ${s.height}');
          }
        }
      }
      expect(small, isEmpty,
          reason: 'the 44 pt guarantee only held for the five shell tabs, '
              'which is how seven sub-44 controls shipped:\n${small.join('\n')}');
    });
  });
}
