import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/substrate.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart' as proto;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _overlappingV20() {
  final inner = Uint8List(proto.kGen5V20InnerLen);
  final data = ByteData.sublistView(inner);
  inner[0] = 0x2f;
  inner[1] = 20;
  inner[2] = 0x81;
  data.setUint32(3, 1234, Endian.little);
  data.setUint32(7, 1784054004, Endian.little);
  data.setUint16(11, 12124, Endian.little);
  data.setUint16(15, 50, Endian.little);

  // Make the overlapping Gen4 best-effort offsets look physiologically valid.
  // This proves dispatch, rather than the Gen4 plausibility gate, refuses it.
  inner[17] = 60;
  data.setFloat32(36, 0, Endian.little);
  data.setFloat32(40, 0, Endian.little);
  data.setFloat32(44, 1, Endian.little);
  return inner;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async => LocalDb.close());

  test('identified Gen5 v20 never falls through to Gen4 replay', () async {
    final bytes = _overlappingV20();
    expect(proto.parseGen5Historical(bytes), isA<proto.Gen5OpticalBuffer>());
    final legacy = proto.FirmwareAwareR24Decoder().decode(bytes);
    expect(legacy, isNotNull, reason: 'fixture must exercise decoder overlap');
    expect(legacy!.hr, 60);

    expect(decodeSubstrate([_hex(bytes)]).length, 0);

    LocalDb.dbName = 'openband_gen5_dispatch_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/${LocalDb.dbName}');
    await LocalDb.insertRecord(
      RawRecord(
        counter: 1234,
        packetType: 47,
        hex: _hex(bytes),
        capturedAt: 1784055000000,
      ),
      null,
    );

    final db = await LocalDb.instance;
    final biometric = (await db.rawQuery(
      'SELECT COUNT(*) AS n FROM decoded_onehz',
    )).single['n'];
    expect(biometric, 0, reason: 'no fabricated biometric second');
    final archive = await db.query(
      'raw_archive',
      where: 'hex = ?',
      whereArgs: [_hex(bytes)],
    );
    expect(archive, hasLength(1), reason: 'original bytes remain replayable');
    expect(archive.single['rec_ts'], 1784054004);
  });
}
