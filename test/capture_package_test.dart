// Capture-package regressions: archive reason labels, gen5 event persist.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart' as proto;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _le32(int v) => [
      v & 0xff,
      (v >> 8) & 0xff,
      (v >> 16) & 0xff,
      (v >> 24) & 0xff,
    ];

Uint8List _eventEnvelope(int id, List<int> body, {int unix = 1786000000}) =>
    Uint8List.fromList([
      0x30,
      0x05,
      ..._le16(id),
      ..._le32(unix),
      ..._le16(0),
      ..._le16(body.length),
      ...body,
    ]);

String _hex(Uint8List b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('identified Gen5 buffers are not labelled undecodable', () {
    expect(archiveReasonForHistoricalVersion(26), 'identified_unmapped_v26');
    expect(archiveReasonForHistoricalVersion(20), 'identified_unmapped_v20');
    expect(archiveReasonForHistoricalVersion(21), 'identified_unmapped_v21');
    expect(archiveReasonForHistoricalVersion(22), 'identified_unmapped_v22');
    expect(archiveReasonForHistoricalVersion(18), 'undecodable_rec_v18');
    expect(archiveReasonForHistoricalVersion(99), 'undecodable_rec_v99');
  });

  group('insertEvent parses gen5-scoped bodies', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    tearDown(() async {
      await LocalDb.close();
    });

    test('STRAP_CONDITION_REPORT lands named with payload, not EVENT_29 {}',
        () async {
      LocalDb.dbName = 'capture_package_event.db';
      await LocalDb.close();
      final db = await LocalDb.instance;
      await db.delete('band_events');

      final body = <int>[
        ..._le32(1234),
        ..._le16(456),
        ..._le16(872),
        3,
        1,
        2,
      ];
      final hex = _hex(
        _eventEnvelope(proto.EventId.strapConditionReport, body),
      );
      await LocalDb.insertEvent(
        proto.EventId.strapConditionReport,
        1786000000,
        hex,
        deviceId: LocalDb.kPrimaryDeviceId,
      );

      final rows = await db.query('band_events');
      expect(rows, hasLength(1));
      expect(rows.single['name'], 'STRAP_CONDITION_REPORT');
      final payload = rows.single['payload_json'] as String;
      expect(payload, isNot('{}'));
      expect(payload, contains('condition_pages_behind'));
    });
  });
}
