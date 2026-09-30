import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/g3_data.dart';

typedef _Setenv = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _SetenvDart = int Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _Unsetenv = Int32 Function(Pointer<Utf8>);
typedef _UnsetenvDart = int Function(Pointer<Utf8>);
typedef _Tzset = Void Function();

void _timezone(String? value) {
  final libc = DynamicLibrary.process();
  final name = 'TZ'.toNativeUtf8();
  try {
    if (value == null) {
      libc.lookupFunction<_Unsetenv, _UnsetenvDart>('unsetenv')(name);
    } else {
      final zone = value.toNativeUtf8();
      try {
        libc.lookupFunction<_Setenv, _SetenvDart>('setenv')(name, zone, 1);
      } finally {
        calloc.free(zone);
      }
    }
    libc.lookupFunction<_Tzset, void Function()>('tzset')();
  } finally {
    calloc.free(name);
  }
}

void main() {
  final original = Platform.environment['TZ'];
  setUpAll(() {
    if (!Platform.isWindows) _timezone('Europe/Berlin');
  });
  tearDownAll(() {
    if (!Platform.isWindows) _timezone(original);
  });

  test('spring-forward week has seven distinct local days 23 through 29', () {
    final days = g3DaysEnding('2026-03-29', 7);
    expect(days, [
      '2026-03-23',
      '2026-03-24',
      '2026-03-25',
      '2026-03-26',
      '2026-03-27',
      '2026-03-28',
      '2026-03-29',
    ]);
    expect(days.toSet().length, 7);
    expect(DateTime(2026, 3, 30).difference(DateTime(2026, 3, 29)).inHours, 23);
  });
}
