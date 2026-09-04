import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/services/mtproto_probe_service.dart';

void main() {
  group('decodeProxySecret', () {
    test('accepts 16-byte hex secrets', () {
      final out = MtprotoProbeService.decodeProxySecret(
          'A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6');
      expect(out, hasLength(16));
      expect(out![0], 0xA1);
    });

    test('strips dd transport flag from 17-byte secrets', () {
      final out = MtprotoProbeService.decodeProxySecret(
          'ddA1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6');
      expect(out, hasLength(16));
      expect(out![0], 0xA1);
    });

    test('rejects ee FakeTLS secrets as unsupported', () {
      expect(
          MtprotoProbeService.decodeProxySecret(
              'eeA1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6'),
          isNull);
    });

    test('rejects malformed secrets', () {
      expect(MtprotoProbeService.decodeProxySecret('abc'), isNull);
      expect(MtprotoProbeService.decodeProxySecret('zzzz'), isNull);
      expect(
          MtprotoProbeService.decodeProxySecret('A1b2C3d4E5f6'),
          isNull);
      expect(MtprotoProbeService.decodeProxySecret(''), isNull);
    });
  });

  group('buildInit', () {
    test('produces spec-shaped 64-byte payloads', () {
      final rng = Random(1234);
      for (var i = 0; i < 50; i++) {
        final init =
            MtprotoProbeService.buildInit(random: rng)!;
        expect(init, hasLength(64));
        expect(init[0] != 0xef, isTrue);
        final view = ByteData.sublistView(init);
        expect(view.getUint32(56, Endian.little), 0xdddddddd);
        expect(view.getUint16(60, Endian.little),
            MtprotoProbeService.dcId);
        expect(view.getUint32(0, Endian.little),
            isNot(anyOf(0x44414548, 0x54534f50, 0x20544547, 0x4954504f,
                0x02010316, 0xdddddddd, 0xeeeeeeee)));
        expect(view.getUint32(4, Endian.little), isNot(0));
      }
    });
  });

  group('obfuscation round-trip', () {
    test('decrypt(encrypt(x)) recovers handshake bytes', () {
      final rng = Random(99);
      final init = MtprotoProbeService.buildInit(random: rng)!;
      final secret = MtprotoProbeService.decodeProxySecret(
          '00112233445566778899aabbccddeeff')!;
      final recovered = MtprotoProbeService.obfuscationRoundTrip(
          init, secret, Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(recovered, [1, 2, 3, 4, 5]);
    });

    test('wrong secret does not recover plaintext', () {
      final rng = Random(7);
      final init = MtprotoProbeService.buildInit(random: rng)!;
      final good = MtprotoProbeService.decodeProxySecret(
          '00112233445566778899aabbccddeeff')!;
      final bad = MtprotoProbeService.decodeProxySecret(
          'ffeeddccbbaa99887766554433221100')!;
      final recovered = MtprotoProbeService.obfuscationRoundTripWith(
          init, good, bad, Uint8List.fromList([9, 9, 9]));
      expect(recovered, isNot([9, 9, 9]));
    });
  });

  group('req_pq framing', () {
    test('buildReqPq emits ctor + nonce', () {
      final nonce =
          Uint8List.fromList(List.generate(16, (i) => i));
      final frame = MtprotoProbeService.buildReqPq(nonce);
      expect(frame, hasLength(20));
      expect(
          ByteData.sublistView(frame).getUint32(0, Endian.little),
          0xbe7e8ef1);
      expect(frame.sublist(4, 20), nonce);
    });

    test('parseResPq accepts matching resPQ, rejects impostors', () {
      final nonce =
          Uint8List.fromList(List.generate(16, (i) => 255 - i));
      final good = Uint8List(32);
      ByteData.sublistView(good).setUint32(0, 0x05162463, Endian.little);
      good.setRange(4, 20, nonce);
      expect(MtprotoProbeService.parseResPq(good, nonce), isTrue);

      final badCtor = Uint8List.fromList(good)..[0] = 0x00;
      expect(MtprotoProbeService.parseResPq(badCtor, nonce), isFalse);

      final badNonce = Uint8List.fromList(good)..[5] ^= 0xFF;
      expect(MtprotoProbeService.parseResPq(badNonce, nonce), isFalse);

      expect(MtprotoProbeService.parseResPq(Uint8List(10), nonce),
          isFalse);
    });
  });

  group('socket reading over loopback', () {
    late ServerSocket server;
    late List<Socket> openSockets;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      openSockets = [];
    });

    tearDown(() async {
      for (final s in openSockets) {
        try {
          s.destroy();
        } catch (_) {}
      }
      try {
        await server.close();
      } catch (_) {}
    });

    Future<Socket> connect() async {
      final pending = server.first;
      final client =
          await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      openSockets.add(client);
      final serverSide = await pending;
      openSockets.add(serverSide);
      return client;
    }

    test('coalesced write serves split reads from pushback', () async {
      final client = await connect();
      final serverSide =
          openSockets.lastWhere((s) => s != client);
      serverSide.add([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      await serverSide.flush();

      final reader = MtprotoProbeService.openReader(client);
      final first = await reader.readExactly(4);
      expect(first, [1, 2, 3, 4]);
      final second = await reader.readExactly(6);
      expect(second, [5, 6, 7, 8, 9, 10]);
      await reader.cancel();
    });

    test('closed peer surfaces SocketException', () async {
      final client = await connect();
      final serverSide =
          openSockets.lastWhere((s) => s != client);
      await serverSide.close();

      final reader = MtprotoProbeService.openReader(client);
      await expectLater(
        reader.readExactly(4),
        throwsA(isA<SocketException>()),
      );
    });

    test('silent peer trips the read deadline', () async {
      final client = await connect();
      final reader = MtprotoProbeService.openReader(
        client,
        const Duration(milliseconds: 300),
      );
      await expectLater(
        reader.readExactly(4),
        throwsA(isA<TimeoutException>()),
      );
      await reader.cancel();
    });
  });
}
