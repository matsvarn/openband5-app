// G3 Paper diff harness. Run through `python3 tool/g3_review.py`, which
// provides the Helvetica Neue faces; not part of the regular test suite.
//
// Components come from docs/openband5/design/paper-g3/frames.json and are
// rendered by `g3Specimens` (lib/openband/g3/specimens.dart) with the same
// synthetic content as Paper. Screens are registered in frames.json
// ("screens") with a builder of the same name in [g3ScreenBuilders].
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/g3/g3_theme.dart';
import 'package:openstrap_edge/openband/g3/specimens.dart';
import 'package:openstrap_edge/openband/theme.dart';

import 'g3_screens/band.dart';
import 'g3_screens/heute.dart';
import 'g3_screens/journal.dart';
import 'g3_screens/schlaf.dart';
import 'g3_screens/training.dart';
import 'g3_screens/verlauf.dart';
import 'g3_screens/widgets.dart';

/// Full G3 screens, keyed by their registered name. Each area keeps its
/// frames in docs/openband5/design/paper-g3/screens/<area>.json and its
/// builders in tool/g3_screens/<area>.dart.
final Map<String, Widget Function()> g3ScreenBuilders = {
  ...heuteScreens,
  ...schlafScreens,
  ...trainingScreens,
  ...journalScreens,
  ...verlaufScreens,
  ...bandScreens,
  ...widgetScreens,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final only = (env['G3_NAMES'] ?? '').split(',').where((s) => s.isNotEmpty).toList();
  final modes = (env['G3_MODES'] ?? 'light,dark').split(',');
  final reg = jsonDecode(File('docs/openband5/design/paper-g3/frames.json').readAsStringSync()) as Map;
  final scale = (reg['scale'] as num).toDouble();

  setUpAll(() async {
    final fonts = env['G2_FONTS'];
    if (fonts == null) throw StateError('Run via python3 tool/g3_review.py');
    final helvetica = FontLoader('Helvetica Neue');
    for (final face in ['', '-Medium', '-Bold']) {
      final bytes = File('$fonts/HelveticaNeue$face.ttf').readAsBytesSync();
      helvetica.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await helvetica.load();
    await (FontLoader('Inter')..addFont(
          Future.value(ByteData.sublistView(File('assets/fonts/Inter/Inter.ttf').readAsBytesSync())),
        ))
        .load();
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });

  final frames = <(String, String, String?)>[];
  for (final MapEntry(key: name, value: entry) in (reg['components'] as Map).entries) {
    for (final mode in ['light', 'dark']) {
      frames.add((name as String, mode, (entry as Map)['background'] as String?));
    }
  }
  final screens = <String, dynamic>{...(reg['screens'] as Map? ?? {})};
  final areas = Directory('docs/openband5/design/paper-g3/screens').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in areas) {
    screens.addAll(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
  }
  for (final MapEntry(key: name, value: entry) in screens.entries) {
    frames.add((name, (entry as Map)['mode'] as String, 'page'));
  }

  for (final (name, mode, background) in frames) {
    if (only.isNotEmpty && !only.any(name.contains)) continue;
    if (!modes.contains(mode)) continue;
    final ref = File('docs/openband5/design/paper-g3/$mode/$name.png');
    final build = g3Specimens[name] ?? g3ScreenBuilders[name];
    if (!ref.existsSync() || build == null) {
      test('$mode/$name', () {
        // ignore: avoid_print
        print('G3SCORE $mode/$name skipped (${build == null ? 'no builder' : 'no reference'})');
      });
      continue;
    }
    testWidgets('$mode/$name', (tester) async {
      final refImage = (await tester.runAsync(() => _decode(ref)))!;
      final size = Size(refImage.width / scale, refImage.height / scale);
      tester.view.devicePixelRatio = scale;
      tester.view.physicalSize = Size(refImage.width.toDouble(), refImage.height.toDouble());
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
            theme: openBandTheme(dark ? Brightness.dark : Brightness.light).copyWith(platform: TargetPlatform.iOS),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Material(
              color: bg,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: size.width, height: size.height, child: build()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('capture')));
      final app = await boundary.toImage(pixelRatio: scale);
      final score = (await tester.runAsync(
        () => _writeReport(refImage, app, bg, 'build/g3-review/$mode/$name.png'),
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
Future<double> _writeReport(ui.Image refRaw, ui.Image app, Color bg, String path) async {
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
        differing++;
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
  return differing / (w * h);
}
