// Shared test bootstrap: pin the process timezone for every test file.
//
// The committed fixtures and golden images model a phone in Europe/Berlin —
// `docs/openband5/assets/fixtures/*.json` declare `"timezone": "Europe/Berlin"`
// and carry +02:00 instants, and `test/openband_goldens/` was rendered on a
// Berlin host. Dart's `DateTime` reads the C library's local time, so without
// a pinned zone the same fixture lands on a different civil day under a UTC
// runner (the cause of the Ubuntu CI sleep-editor failures) and snapshot
// tests of local-day bucketing (e.g. two_device_fixture_test) can never be
// host-independent.
//
// `OPENBAND_TEST_TZ=<zone>` pins a different zone; `OPENBAND_TEST_TZ=host`
// disables the pin, which is how fixture timezone independence stays
// verifiable. POSIX only — Windows keeps the host zone.
// `OPENBAND_TEST_LANE=behavior` runs every test body while accepting image
// comparisons on hosts that cannot reproduce the committed golden pixels.
//
// Same mechanism as test/day_window_dst_test.dart: libc setenv("TZ")+tzset()
// genuinely re-homes the local calendar for this process.

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _SetenvNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _SetenvDart = int Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _UnsetenvNative = Int32 Function(Pointer<Utf8>);
typedef _UnsetenvDart = int Function(Pointer<Utf8>);
typedef _TzsetNative = Void Function();
typedef _TzsetDart = void Function();

void _setProcessTz(String? tz) {
  final lib = DynamicLibrary.process();
  final key = 'TZ'.toNativeUtf8();
  try {
    if (tz == null) {
      lib.lookupFunction<_UnsetenvNative, _UnsetenvDart>('unsetenv')(key);
    } else {
      final value = tz.toNativeUtf8();
      lib.lookupFunction<_SetenvNative, _SetenvDart>('setenv')(key, value, 1);
      calloc.free(value);
    }
    lib.lookupFunction<_TzsetNative, _TzsetDart>('tzset')();
  } finally {
    calloc.free(key);
  }
}

const _pinnedZone = 'Europe/Berlin';

// Ubuntu still executes the whole test body, including assertions after a
// screenshot. Pixel equality is checked by the strict local golden lane.
class _BehavioralGoldenComparator extends GoldenFileComparator {
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async => true;

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) =>
      throw UnsupportedError('The behavioral lane cannot update goldens.');
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (!Platform.isWindows) {
    final requested = Platform.environment['OPENBAND_TEST_TZ'];
    if (requested != 'host') {
      _setProcessTz(
        requested == null || requested.isEmpty ? _pinnedZone : requested,
      );
    }
  }
  if (Platform.environment['OPENBAND_TEST_LANE'] == 'behavior') {
    goldenFileComparator = _BehavioralGoldenComparator();
  }
  await testMain();
}
