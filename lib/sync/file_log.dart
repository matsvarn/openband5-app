// Simple append-only file logger for field debugging.
//
// Writes to the app's external files dir on Android so it can be pulled with a
// plain `adb pull` (no run-as needed):
//   /storage/emulated/0/Android/data/wtf.openstrap.openstrap_edge/files/openstrap_sync.log
//
// Bounded: rotates to a single .1 sibling at [_maxBytes] so a 24/7 headless
// process can't grow it without limit, and appends WITHOUT a per-line fsync —
// AppState routes every log line here, so `flush: true` was a full
// open→write→fsync→close flash cycle per line, around the clock. The page
// cache still lands the line on process crash; only a hard power loss can drop
// the last few lines of a diagnostics log, which is an acceptable trade.

import 'dart:io';
import 'package:path_provider/path_provider.dart';

class FileLog {
  static File? _file;
  static bool _init = false;

  static const int _maxBytes = 2 * 1024 * 1024;
  // ponytail: the size check stats the file only once every 128 writes, so the
  // log can overshoot _maxBytes by a burst's worth of lines before rotating.
  static const int _sizeCheckEvery = 128;
  static int _writesSinceCheck = 0;

  static Future<void> _ensure() async {
    if (_init) return;
    _init = true;
    try {
      // getExternalStorageDirectory() is Android-only and THROWS on iOS, which
      // used to land in the catch below and disable the log on iPhone
      // entirely. Documents is pulled with the rest of the app container.
      Directory? dir;
      if (Platform.isAndroid) {
        try {
          dir = await getExternalStorageDirectory();
        } catch (_) {}
      }
      dir ??= await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/openstrap_sync.log');
    } catch (_) {
      _file = null;
    }
  }

  // Appends run one at a time. Unserialised, two in-flight appends each open
  // the file at the same end offset and overwrite each other's line.
  static Future<void> _tail = Future<void>.value();

  static Future<void> write(String line) {
    // Stamp at call time: the queue below can delay the write.
    final at = DateTime.now().toIso8601String();
    return _tail = _tail.then((_) => _append('$at $line\n'));
  }

  static Future<void> _append(String text) async {
    await _ensure();
    final f = _file;
    if (f == null) return;
    try {
      if (_writesSinceCheck++ % _sizeCheckEvery == 0) {
        await _rotateIfNeeded(f);
      }
      await f.writeAsString(text, mode: FileMode.append);
    } catch (_) {}
  }

  /// One-file rotation: current → .1 (replacing any previous .1), and the next
  /// append recreates the live file. Keeps at most ~2×[_maxBytes] on disk.
  static Future<void> _rotateIfNeeded(File f) async {
    try {
      if (!await f.exists() || await f.length() < _maxBytes) return;
      final old = File('${f.path}.1');
      if (await old.exists()) await old.delete();
      await f.rename('${f.path}.1');
    } catch (_) {}
  }

  static Future<String?> path() async {
    await _ensure();
    return _file?.path;
  }

  static Future<void> clear() async {
    await _ensure();
    try {
      await _file?.writeAsString('');
      final f = _file;
      if (f != null) {
        final old = File('${f.path}.1');
        if (await old.exists()) await old.delete();
      }
    } catch (_) {}
  }
}
