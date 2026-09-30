// G3 Paper diff harness. Run through `python3 tool/g3_review.py`, which
// provides the Helvetica Neue faces; not part of the regular test suite.
//
// Components come from docs/openband5/design/paper-g3/frames.json and are
// rendered by `g3Specimens` (lib/openband/g3/specimens.dart) with the same
// synthetic content as Paper.
//
// SCREEN BUILDER CONTRACT (every area)
//   Frames:   docs/openband5/design/paper-g3/screens/<area>.json
//             {"<name>": {"page": "<pageId>", "node": "<artboardId>", "mode": "light"|"dark"}}
//   Builders: tool/g3_screens/<area>.dart exports
//             `final Map<String, G3ScreenBuilder> <area>Screens`, keyed like the json.
//   A builder is `Widget? Function(G3Env env)` (tool/g3_screens/env.dart):
//     - read data ONLY through `env.repository(() => <your synthetic repo>)`,
//       with `env.day(...)`, `env.now(...)` and `env.band(...)` wrapped the same
//       way. In Paper mode each returns your fallback; under --real they return
//       a LocalOpenBandRepository over a COPY of the pulled phone database, its
//       latest stored day (or --day), the wall clock, and a connected band
//       with the last stored sample.
//     - return null under `env.real` for frames that only a fixture can show
//       (never connected, a chosen past day, an injected gap…); they are
//       skipped rather than faked.
//     - return the whole screen as the app shows it (inside AppShell when the
//       tab bar is part of the frame). The harness supplies MaterialApp, theme,
//       the 62/34 pt safe areas and the fonts; it settles real I/O itself.
//   Screens are scored below Paper's 54 pt status bar.
//
// Real mode (`python3 tool/g3_review.py --real [DOCUMENTS] [--day YYYY-MM-DD]`):
// only screens render, to G3_OUT (OpenBand5Lab/ui-review-real/<stamp>/), never
// to the repository, and nothing is compared with Paper.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/g3_theme.dart';
import 'package:openstrap_edge/openband/g3/specimens.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'g3_screens/band.dart';
import 'g3_screens/env.dart';
import 'g3_screens/heute.dart';
import 'g3_screens/journal.dart';
import 'g3_screens/schlaf.dart';
import 'g3_screens/training.dart';
import 'g3_screens/verlauf.dart';
import 'g3_screens/widgets.dart';

/// Full G3 screens, keyed by their registered name.
final Map<String, G3ScreenBuilder> g3ScreenBuilders = {
  ...heuteScreens,
  ...schlafScreens,
  ...trainingScreens,
  ...journalScreens,
  ...verlaufScreens,
  ...bandScreens,
  ...widgetScreens,
};

const _frameWidth = 393.0;
const _statusBar = 54.0;
const _realHeight = 2400.0;

/// Lets real (FFI) database reads complete; `pumpAndSettle` alone never
/// advances real I/O inside the test's fake async zone.
Future<void> _settleReal(WidgetTester tester) async {
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final only = (env['G3_NAMES'] ?? '').split(',').where((s) => s.isNotEmpty).toList();
  final modes = (env['G3_MODES'] ?? 'light,dark').split(',');
  final reg = jsonDecode(File('docs/openband5/design/paper-g3/frames.json').readAsStringSync()) as Map;
  final scale = (reg['scale'] as num).toDouble();
  final realDocs = env['G3_REAL_DOCS'];
  final real = realDocs != null;
  // Personal renders: resolve and check the target before anything runs.
  final realOut = real ? g3RealOut(env) : null;
  G3Env screenEnv = const G3Env.paper();
  AppState? realApp;

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    final fonts = env['G2_FONTS'];
    if (fonts == null) throw StateError('Run via python3 tool/g3_review.py');
    final helvetica = FontLoader('Helvetica Neue');
    for (final face in ['', '-Medium', '-Bold']) {
      final bytes = File('$fonts/HelveticaNeue$face.ttf').readAsBytesSync();
      helvetica.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await helvetica.load();
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
    ]) {
      await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())))).load();
    }
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
    if (!real) return;
    // Work on a throwaway copy: opening runs schema repair, and the pulled
    // copy in OpenBand5Lab must stay exactly as it came off the phone.
    final tmp = Directory.systemTemp.createTempSync('g3-real-');
    for (final name in ['openstrap.db', 'openstrap.db-wal', 'openstrap.db-shm']) {
      final f = File('$realDocs/$name');
      if (f.existsSync()) f.copySync('${tmp.path}/$name');
    }
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(tmp.path);
    LocalDb.dbName = 'openstrap.db';
    final db = await LocalDb.instance;
    final day = env['G3_REAL_DAY'] ??
        (await db.rawQuery('SELECT MAX(day_id) AS d FROM day_result')).first['d'] as String?;
    if (day == null) throw StateError('No day_result in $realDocs');
    final hi = (await db.rawQuery('SELECT MAX(rec_ts) AS t FROM decoded_onehz')).first['t'];
    final stored = hi is num ? DateTime.fromMillisecondsSinceEpoch(hi.toInt() * 1000) : null;
    // This harness runs under `flutter test`; it lives in tool/ only so the
    // regular suite does not pick it up.
    // ignore: invalid_use_of_visible_for_testing_member
    final app = realApp = AppState.forTesting();
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    final today = day == todayLabel(DateTime.now());
    screenEnv = G3Env.real(
      repository: LocalOpenBandRepository(app),
      day: day,
      now: today ? DateTime.now : () => DateTime.parse(day).add(const Duration(hours: 12)),
      band: BandSnapshot(connection: BandConnection.connected, latestStoredAt: stored, receivedAt: stored),
    );
  });
  tearDownAll(() => realApp?.dispose());

  final frames = <(String, String, String?, bool)>[];
  if (!real) {
    for (final MapEntry(key: name, value: entry) in (reg['components'] as Map).entries) {
      for (final mode in ['light', 'dark']) {
        frames.add((name as String, mode, (entry as Map)['background'] as String?, false));
      }
    }
  }
  final screens = <String, dynamic>{...(reg['screens'] as Map? ?? {})};
  final areas = Directory('docs/openband5/design/paper-g3/screens').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in areas) {
    screens.addAll(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
  }
  for (final MapEntry(key: name, value: entry) in screens.entries) {
    frames.add((name, (entry as Map)['mode'] as String, 'page', true));
  }

  for (final (name, mode, background, isScreen) in frames) {
    if (only.isNotEmpty && !only.any(name.contains)) continue;
    if (!modes.contains(mode)) continue;
    final ref = File('docs/openband5/design/paper-g3/$mode/$name.png');
    final component = isScreen ? null : g3Specimens[name];
    final screen = isScreen ? g3ScreenBuilders[name] : null;
    if ((!real && !ref.existsSync()) || (component == null && screen == null)) {
      test('$mode/$name', () {
        // ignore: avoid_print
        print('G3SCORE $mode/$name skipped (${component == null && screen == null ? 'no builder' : 'no reference'})');
      });
      continue;
    }
    testWidgets('$mode/$name', (tester) async {
      final refImage = real ? null : (await tester.runAsync(() => _decode(ref)))!;
      final dpr = real ? 2.0 : scale;
      final size = real
          ? const Size(_frameWidth, _realHeight)
          : Size(refImage!.width / scale, refImage.height / scale);
      final Widget? child = component != null ? component() : screen!(screenEnv);
      if (child == null) {
        // ignore: avoid_print
        print('G3SCORE ${real ? 'real ' : ''}$mode/$name skipped (fixture-only state)');
        return;
      }
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = size * dpr;
      addTearDown(tester.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final dark = mode == 'dark';
      final g = G3(dark);
      final bg = background == 'canvas' ? g.canvas : g.page;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('de'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('de')],
            theme: openBandTheme(dark ? Brightness.dark : Brightness.light).copyWith(platform: TargetPlatform.iOS),
            builder: (context, c) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                // Paper's mock status bar is 62 pt; the home indicator 34 pt.
                padding: isScreen ? const EdgeInsets.only(top: 62, bottom: 34) : EdgeInsets.zero,
                viewPadding: isScreen ? const EdgeInsets.only(top: 62, bottom: 34) : EdgeInsets.zero,
              ),
              child: c!,
            ),
            home: Material(
              color: bg,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: size.width, height: size.height, child: child),
              ),
            ),
          ),
        ),
      );
      if (real) {
        await _settleReal(tester);
      } else {
        await tester.pumpAndSettle();
      }
      debugDefaultTargetPlatformOverride = null;
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('capture')));
      final app = await boundary.toImage(pixelRatio: dpr);
      if (real) {
        final out = realOut!;
        await tester.runAsync(() async {
          final png = await app.toByteData(format: ui.ImageByteFormat.png);
          File('$out/$mode/$name.png')
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(png!.buffer.asUint8List());
        });
        // ignore: avoid_print
        print('G3SCORE real $mode/$name');
        return;
      }
      final score = (await tester.runAsync(
        () => _writeReport(refImage!, app, bg, 'build/g3-review/$mode/$name.png', top: isScreen ? (_statusBar * dpr).round() : 0),
      ))!;
      // ignore: avoid_print
      print('G3SCORE $mode/$name ${(score * 100).toStringAsFixed(2)}%');
    });
  }
}

Future<ui.Image> _decode(File file) async {
  final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

Future<Uint8List> _rgba(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();

/// Writes [Paper | app | onion | diff] and returns the differing-pixel share
/// (any channel off by more than 24). Paper's transparent node export is put
/// on [bg] first.
Future<double> _writeReport(ui.Image refRaw, ui.Image app, Color bg, String path, {int top = 0}) async {
  final w = refRaw.width, h = refRaw.height;
  final flat = ui.PictureRecorder();
  Canvas(flat)
    ..drawColor(bg, BlendMode.src)
    ..drawImage(refRaw, Offset.zero, Paint());
  final ref = await flat.endRecording().toImage(w, h);
  final a = await _rgba(ref);
  final b = await _rgba(app);
  final diff = Uint8List(w * h * 4);
  var differing = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final inApp = x < app.width && y < app.height;
      final j = (y * app.width + x) * 4;
      var delta = 255;
      if (inApp) {
        delta = 0;
        for (var c = 0; c < 3; c++) {
          delta = math.max(delta, (a[i + c] - b[j + c]).abs());
        }
      }
      final grey = (a[i] + a[i + 1] + a[i + 2]) ~/ 3;
      if (delta > 24) {
        if (y >= top) differing++;
        diff.setAll(i, [255, 40, 40, 255]);
      } else {
        final faded = 200 + grey * 55 ~/ 255;
        diff.setAll(i, [faded, faded, faded, 255]);
      }
    }
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(diff, w, h, ui.PixelFormat.rgba8888, done.complete);
  final diffImage = await done.future;
  const gap = 16.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(const Color(0xFF808080), BlendMode.src);
  final panel = w + gap;
  canvas
    ..drawImage(ref, Offset.zero, Paint())
    ..drawImage(app, Offset(panel, 0), Paint())
    ..drawImage(ref, Offset(panel * 2, 0), Paint())
    ..drawImage(app, Offset(panel * 2, 0), Paint()..color = const Color(0x80000000))
    ..drawImage(diffImage, Offset(panel * 3, 0), Paint());
  final sheet = await recorder.endRecording().toImage((panel * 4 - gap).round(), math.max(h, app.height));
  final png = await sheet.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
  return differing / (w * (h - top));
}
