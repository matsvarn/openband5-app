// What a G3 screen builder gets from tool/g3_review_test.dart.
//
// Paper mode: every getter returns the builder's own synthetic fallback, so
// the frame renders exactly the Paper state it is registered for.
//
// Real mode (`python3 tool/g3_review.py --real`): the repository reads a COPY
// of the newest pulled phone database, the day is the latest stored day (or
// --day), the clock is "now" for today and noon for a past day, and the band
// is connected with its last stored sample. Personal data: renders go to
// OpenBand5Lab/ui-review-real/<stamp>/ only and are never compared with Paper.
import 'package:flutter/widgets.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:path/path.dart' as p;

class G3Env {
  const G3Env._({
    required this.real,
    OpenBandRepository? repository,
    String? day,
    DateTime Function()? now,
    BandSnapshot? band,
  }) : _repository = repository,
       _day = day,
       _now = now,
       _band = band;

  const G3Env.paper() : this._(real: false);

  const G3Env.real({
    required OpenBandRepository repository,
    required String day,
    required DateTime Function() now,
    required BandSnapshot band,
  }) : this._(
         real: true,
         repository: repository,
         day: day,
         now: now,
         band: band,
       );

  /// True under --real. A builder for a state that only a fixture can show
  /// (never connected, a chosen past day…) returns null then and is skipped.
  final bool real;
  final OpenBandRepository? _repository;
  final String? _day;
  final DateTime Function()? _now;
  final BandSnapshot? _band;

  OpenBandRepository repository(OpenBandRepository Function() synthetic) =>
      _repository ?? synthetic();
  String day(String synthetic) => _day ?? synthetic;
  DateTime Function() now(DateTime Function() synthetic) => _now ?? synthetic;
  BandSnapshot band(BandSnapshot Function() synthetic) => _band ?? synthetic();
}

/// Builder contract for every area file in tool/g3_screens/: return the
/// screen for a registered frame, or null to skip it (only under --real).
typedef G3ScreenBuilder = Widget? Function(G3Env env);

/// The --real output directory: G3_OUT, required, and strictly inside
/// ~/Library/Application Support/OpenBand5Lab/ui-review-real/. Real renders
/// show personal data; any other target (the repo, build/, a typo) throws
/// before anything is rendered.
String g3RealOut(Map<String, String> env) {
  final home = env['HOME'];
  final out = env['G3_OUT'];
  if (home == null || home.isEmpty) throw StateError('--real: HOME is not set');
  final root = p.join(home, 'Library', 'Application Support', 'OpenBand5Lab', 'ui-review-real');
  if (out == null || out.isEmpty) {
    throw StateError('--real: G3_OUT is required (a folder under $root)');
  }
  final dir = p.normalize(p.absolute(out));
  if (!p.isWithin(root, dir)) {
    throw StateError('--real: G3_OUT must be under $root, not $dir');
  }
  return dir;
}
