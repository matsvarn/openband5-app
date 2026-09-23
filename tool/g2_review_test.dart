// G2 Paper diff harness. Run through `python3 tool/g2_review.py`, which
// provides the Helvetica Neue faces; not part of the regular test suite.
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
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/health.dart';
import 'package:openstrap_edge/openband/local_repository.dart';
import 'package:openstrap_edge/openband/metric_detail.dart';
import 'package:openstrap_edge/openband/release_scope.dart';
import 'package:openstrap_edge/openband/screens.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Every G2 frame is 393 pt wide; a reference's pixel width gives its scale.
const _frameWidth = 393.0;
const _statusBar = 54.0;

Map _json(String name) =>
    jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync())
        as Map;

/// Paper frame slug (docs/openband5/design/paper-g2/MODE/SLUG.png) →
/// screen pushed over Heute, as the app does; null is Heute itself.
final Map<String, Widget Function(OpenBandController)?> _frames = {
  '01-heute': null,
  '02-schlaf': (c) => OpenBandSleep(controller: c),
  '03-hrv-detail': (c) => OpenBandMetricDetail(
    controller: c,
    metricKey: MetricKey.hrv,
    label: 'HRV',
    subtitle: 'Herzratenvariabilität',
    unit: 'ms',
    icon: LucideIcons.activity,
    color: (p) => p.ink,
    tint: (p) => p.line,
    backText: 'Heute',
  ),
  '05-messwerte': (c) => OpenBandHealth(controller: c, bandMetricsOnly: true),
  '13-erholung': (c) => OpenBandMetricDetail(
    controller: c,
    metricKey: MetricKey.recovery,
    label: 'Erholung',
    subtitle: 'aus der Nacht',
    unit: 'von 100',
    icon: LucideIcons.heartPulse,
    color: (p) => p.ink,
    tint: (p) => p.line,
    backText: 'Heute',
  ),
};

/// Real-data mode (`g2_review.py --real`): the frames render from a COPY of
/// a pulled phone database. Private data — renders go to G2_OUT (outside Git)
/// and nothing is compared with Paper.
const _realHeight = 1700.0;

/// Lets real (FFI) database reads complete between frames; `pumpAndSettle`
/// alone never advances real I/O inside the test's fake async zone.
Future<void> _settleReal(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final only = (env['G2_FRAMES'] ?? '').split(',').where((s) => s.isNotEmpty);
  final modes = (env['G2_MODES'] ?? 'light,dark').split(',');
  final realDocs = env['G2_REAL_DOCS'];
  final real = realDocs != null;
  String? realDay;
  DateTime? realStored;

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    final fonts = env['G2_FONTS'];
    if (fonts == null) throw StateError('Run via python3 tool/g2_review.py');
    final helvetica = FontLoader('Helvetica Neue');
    for (final face in ['', '-Medium', '-Bold']) {
      final bytes = File('$fonts/HelveticaNeue$face.ttf').readAsBytesSync();
      helvetica.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await helvetica.load();
    // Some chart captions still name the bundled Inter families.
    for (final (family, path) in [
      ('Inter', 'assets/fonts/Inter/Inter.ttf'),
      ('Inter Tight', 'assets/fonts/InterTight/InterTight[wght].ttf'),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
    if (real) {
      // Work on a throwaway copy: opening runs schema repair, and the pulled
      // copy in OpenBand5Lab must stay exactly as it came off the phone.
      final tmp = Directory.systemTemp.createTempSync('g2-real-');
      for (final name in [
        'openstrap.db',
        'openstrap.db-wal',
        'openstrap.db-shm',
      ]) {
        final f = File('$realDocs/$name');
        if (f.existsSync()) f.copySync('${tmp.path}/$name');
      }
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath(tmp.path);
      LocalDb.dbName = 'openstrap.db';
      final db = await LocalDb.instance;
      realDay =
          env['G2_REAL_DAY'] ??
          (await db.rawQuery(
                'SELECT MAX(day_id) AS d FROM day_result',
              )).first['d']
              as String?;
      final hi = (await db.rawQuery(
        'SELECT MAX(rec_ts) AS t FROM decoded_onehz',
      )).first['t'];
      if (hi is num) {
        realStored = DateTime.fromMillisecondsSinceEpoch(hi.toInt() * 1000);
      }
    }
  });

  for (final MapEntry(key: slug, value: build) in _frames.entries) {
    if (only.isNotEmpty && !only.contains(slug.substring(0, 2))) continue;
    for (final mode in modes) {
      final ref = File('docs/openband5/design/paper-g2/$mode/$slug.png');
      if (!real && !ref.existsSync()) continue;
      testWidgets('$mode/$slug', (tester) async {
        final refImage = real
            ? null
            : (await tester.runAsync(() => _decode(ref)))!;
        final scale = real ? 2.0 : refImage!.width / _frameWidth;
        tester.view.devicePixelRatio = scale;
        tester.view.physicalSize = real
            ? const Size(_frameWidth * 2, _realHeight * 2)
            : Size(refImage!.width.toDouble(), refImage.height.toDouble());
        addTearDown(tester.view.reset);
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

        final OpenBandController controller;
        AppState? app;
        if (real) {
          final day = realDay;
          if (day == null) throw StateError('No day_result in $realDocs');
          // This harness runs under `flutter test`; it lives in tool/ only so
          // the regular suite does not pick it up.
          // ignore: invalid_use_of_visible_for_testing_member
          app = AppState.forTesting();
          app.repo = LocalRepositoryImpl(getProfileMap: () => app!.user);
          final today = day == todayLabel(DateTime.now());
          controller = OpenBandController(
            repository: LocalOpenBandRepository(app),
            initialDay: day,
            band: BandSnapshot(
              connection: BandConnection.connected,
              latestStoredAt: realStored,
            ),
            now: today
                ? DateTime.now
                : () => DateTime.parse(day).add(const Duration(hours: 12)),
          );
          await tester.runAsync(controller.refresh);
        } else {
          final repo = SyntheticOpenBandRepository.fromMaps(
            _json('day-summary.json'),
            _json('sleep-detail.json'),
            activity: _json('additional-flows.json'),
          );
          controller = OpenBandController(
            repository: repo,
            initialDay: '2026-09-15',
            band: repo.band,
            now: () => DateTime(2026, 9, 15, 9, 41),
          );
          // Paper's state has a 7h45 sleep goal set.
          await repo.saveSleepGoal('2026-09-01', 7 * 60 + 45);
          await controller.refresh();
        }
        addTearDown(controller.dispose);
        if (app != null) addTearDown(app.dispose);
        Future<void> settle() =>
            real ? _settleReal(tester) : tester.pumpAndSettle();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('de'),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('de')],
              theme: openBandTheme(
                mode == 'dark' ? Brightness.dark : Brightness.light,
              ).copyWith(platform: TargetPlatform.iOS),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  // Paper's mock status bar is 62 pt; the device inset is 59.
                  padding: const EdgeInsets.only(top: 62, bottom: 34),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: AppShell(
                domains: kOpenBandReleaseDomains,
                builder: (_, _) => OpenBandOverview(
                  controller: controller,
                  reduced: true,
                  onProfile: () {},
                  onSync: () {},
                ),
              ),
            ),
          ),
        );
        await settle();
        if (build != null) {
          Navigator.of(
            tester.element(find.byType(OpenBandOverview)),
          ).push(MaterialPageRoute<void>(builder: (_) => build(controller)));
          await settle();
        }
        debugDefaultTargetPlatformOverride = null;
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        final image = await boundary.toImage(pixelRatio: scale);
        if (real) {
          final out = env['G2_OUT'] ?? 'build/g2-review-real';
          await tester.runAsync(() async {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File('$out/$mode/$slug.png')
              ..parent.createSync(recursive: true)
              ..writeAsBytesSync(png!.buffer.asUint8List());
          });
          // ignore: avoid_print
          print('G2SCORE real $mode/$slug (day $realDay)');
          return;
        }
        final score = (await tester.runAsync(
          () => _writeReport(
            refImage!,
            image,
            scale,
            'build/g2-review/$mode/$slug.png',
          ),
        ))!;
        // ignore: avoid_print
        print('G2SCORE $mode/$slug ${(score * 100).toStringAsFixed(2)}%');
      });
    }
  }
}

Future<ui.Image> _decode(File file) async {
  final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

Future<Uint8List> _rgba(ui.Image image) async => (await image.toByteData(
  format: ui.ImageByteFormat.rawRgba,
))!.buffer.asUint8List();

/// Writes [Paper | app | onion | diff] and returns the differing-pixel share
/// below the status bar (a pixel differs when any channel moves by > 24).
Future<double> _writeReport(
  ui.Image ref,
  ui.Image app,
  double scale,
  String path,
) async {
  final w = ref.width, h = ref.height;
  final a = await _rgba(ref);
  final b = await _rgba(app);
  final diff = Uint8List(w * h * 4);
  final top = (_statusBar * scale).round();
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
  final diffImage = await _fromPixels(diff, w, h);
  const gap = 16.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawColor(const Color(0xFF808080), BlendMode.src);
  final panel = w + gap;
  canvas.drawImage(ref, Offset.zero, Paint());
  canvas.drawImage(app, Offset(panel, 0), Paint());
  canvas.drawImage(ref, Offset(panel * 2, 0), Paint());
  canvas.drawImage(
    app,
    Offset(panel * 2, 0),
    Paint()..color = const Color(0x80000000),
  );
  canvas.drawImage(diffImage, Offset(panel * 3, 0), Paint());
  final sheet = await recorder.endRecording().toImage(
    (panel * 4 - gap).round(),
    math.max(h, app.height),
  );
  final png = await sheet.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
  return differing / (w * (h - top));
}

Future<ui.Image> _fromPixels(Uint8List pixels, int w, int h) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    w,
    h,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}
