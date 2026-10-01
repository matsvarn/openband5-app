import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Frame _framed(Uint8List inner) {
  final frame = parseFrame(
    buildFrame(inner, profile: BandProfile.gen5),
    profile: BandProfile.gen5,
  )!;
  expect(frame.decodable, isTrue);
  return frame;
}

List<Frame> _liveFrames(int ts) {
  final hr = Uint8List(20);
  hr[0] = PacketType.realtimeData;
  hr[1] = 1;
  final h = ByteData.sublistView(hr);
  h.setUint32(2, ts, Endian.little);
  hr[8] = 64;
  hr[9] = 1;
  h.setInt16(10, 938, Endian.little);
  hr[18] = 1;
  expect(parseRealtimeHr(hr), isNotNull);

  final raw = Uint8List(kGen5V21InnerLen);
  raw[0] = PacketType.realtimeRawData;
  raw[1] = 21;
  raw[2] = 0x80;
  final r = ByteData.sublistView(raw);
  r.setUint32(3, 101, Endian.little);
  r.setUint32(7, ts, Endian.little);
  r.setUint16(14, 100, Endian.little); // accel capacity
  r.setUint16(16, 1, Endian.little); // one valid accel sample
  raw[18] = 3;
  r.setInt16(420, 4096, Endian.little); // accel z = 1 g
  r.setUint16(620, 100, Endian.little); // gyro capacity
  r.setUint16(622, 1, Endian.little);
  raw[624] = 5;
  expect(frameAccelGen5Live(_hex(raw)), isNotNull);

  final imu = Uint8List(84);
  imu[0] = PacketType.realtimeImuStream;
  final i = ByteData.sublistView(imu);
  i.setUint32(4, ts, Endian.little);
  i.setUint16(14, 1, Endian.little);
  for (var sample = 0; sample < 10; sample++) {
    i.setInt16(64 + 2 * sample, 4096, Endian.little);
  }
  expect(frameAccel(_hex(imu)), isNotNull);

  return [
    for (final inner in [hr, raw, imu]) _framed(inner),
  ];
}

Frame _historicalFrame(int ts) {
  final inner = Uint8List(kGen5V18InnerLen);
  inner[0] = PacketType.historicalData;
  inner[1] = 18;
  inner[2] = 0x80;
  final v = ByteData.sublistView(inner);
  v.setUint32(3, 102, Endian.little);
  v.setUint32(7, ts, Endian.little);
  inner[14] = 64;
  v.setFloat32(33, 0.5, Endian.little);
  v.setFloat32(45, 1.0, Endian.little);
  expect(sampleFromGen5Historical(parseGen5Historical(inner)), isNotNull);
  return _framed(inner);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String databasePath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('ob5_live_streams_');
    LocalDb.dbName = p.join(directory.path, 'live_streams.db');
    databasePath = p.join(
      await databaseFactory.getDatabasesPath(),
      LocalDb.dbName,
    );
  });

  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(databasePath);
    await directory.delete(recursive: true);
  });

  test(
    'live streams stay RAM-only while historical offload persists',
    () async {
      final db = await LocalDb.instance;
      final persistenceCalls = <String>[];
      final writes = <Future<void>>[];
      final live = <({int packetType, String hex})>[];
      final records = <RawRecord>[];
      final engine = BleEngine(
        adapterStateStream: () => const Stream.empty(),
        onState: (_) {},
        onLiveFrame: (packetType, hex, _) =>
            live.add((packetType: packetType, hex: hex)),
        onRecord: (sample, raw) {
          persistenceCalls.add('onRecord');
          records.add(raw);
          final write = LocalDb.insertRecord(raw, sample).then<void>((_) {});
          writes.add(write);
          return write;
        },
        onRecordsBatch: (raws, samples) {
          persistenceCalls.add('onRecordsBatch');
          final write = LocalDb.insertRecordsBatch(raws, samples);
          writes.add(write);
          return write;
        },
        onCommitBatch: (raws, samples, token, {archives, deviceFamily}) {
          persistenceCalls.add('onCommitBatch');
          final write = LocalDb.commitSyncBatch(
            raws,
            samples,
            trimToken: token,
            archives: archives,
            deviceFamily: deviceFamily,
          );
          writes.add(write);
          return write;
        },
        onArchiveRecord: (archive) {
          persistenceCalls.add('onArchiveRecord');
          final write = LocalDb.archiveRawRecord(archive);
          writes.add(write);
          return write;
        },
        onEvent: (id, ts, hex) {
          persistenceCalls.add('onEvent');
          writes.add(
            LocalDb.insertEvent(
              id,
              ts,
              hex,
              deviceId: LocalDb.kPrimaryDeviceId,
              profile: BandProfile.gen5,
            ),
          );
        },
      );
      engine.debugDeviceDisconnect = ({bool queue = true}) async {};
      addTearDown(() async {
        await engine.disconnect();
        engine.dispose();
      });
      // No commit sink on the fake drain: the historical control stores via
      // onRecord without a HISTORY_END or any ACK/command write.
      engine.debugInstallFakeLink(
        band: BandProfile.gen5,
        onWrite: (_) async => fail('frame ingestion must not write a command'),
        onArchive: engine.onArchiveRecord,
      );
      engine.debugReceiveFrame(
        _framed(
          Uint8List.fromList([PacketType.metadata, 1, SyncMeta.historyStart]),
        ),
      );
      await pumpEventQueue();
      expect(engine.offloadActive, isTrue);

      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600;
      final frames = _liveFrames(ts);
      for (final frame in frames) {
        engine.debugReceiveFrame(frame);
        await pumpEventQueue();
        await Future.wait(writes);
        expect(
          live.where((entry) => entry.packetType == frame.packetType),
          hasLength(1),
        );
        expect(live.last.hex, _hex(frame.inner));
        expect(
          persistenceCalls,
          isEmpty,
          reason: 'live 0x${frame.packetType.toRadixString(16)} is RAM-only',
        );
        for (final table in [
          'raw_records',
          'decoded_onehz',
          'raw_archive',
          'raw_blob',
        ]) {
          expect(await db.query(table), isEmpty, reason: table);
        }
      }
      expect(live.map((entry) => entry.packetType), [0x28, 0x2B, 0x33]);

      final historical = _historicalFrame(ts);
      engine.debugReceiveFrame(historical);
      await pumpEventQueue();
      await Future.wait(writes);
      expect(persistenceCalls, ['onRecord']);
      expect(records.single.packetType, 0x2F);
      expect(records.single.hex, _hex(historical.inner));
      expect(live, hasLength(3));
      final rows = await db.query('decoded_onehz');
      expect(rows, hasLength(1));
      expect(rows.single['rec_ts'], ts);
      expect(rows.single['hr'], 64);
    },
  );
}
