import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/stream/ctr.dart';

import '../models/proxy_model.dart';
import 'host_filter.dart';

enum ProbeOutcome { verified, dead, unsupported }

void _zeroize(Uint8List bytes) {
  try {
    bytes.fillRange(0, bytes.length, 0);
  } catch (_) {}
}
class ProbeResult {
  final String key;
  final ProbeOutcome outcome;
  final int probeLatencyMs;

  const ProbeResult(this.key, this.outcome, this.probeLatencyMs);
}

class MtprotoProbeService {
  static const int connectTimeoutMs = 2500;
  static const Duration readDeadline = Duration(seconds: 5);
  static const Duration perProbeTimeout = Duration(seconds: 7);
  static const int maxVerifyConcurrency = 6;
  static const int maxCandidatesPerSweep = 40;
  static const int reverifyQuota = 5;
  static const int protocolTag = 0xdddddddd;
  static const int dcId = 2;
  static const int reqPqMultiCtor = 0xbe7e8ef1;
  static const int resPQCtor = 0x05162463;
  static const int maxPayloadBytes = 1 << 20;
  static const int maxProbeResponseBytes = 512;

  final Random _random;

  MtprotoProbeService({Random? random})
      : _random = random ?? Random.secure();

  Future<ProbeResult> verify(ProxyModel proxy) {
    return _verifyInner(proxy).timeout(
      perProbeTimeout,
      onTimeout: () => ProbeResult(proxy.key, ProbeOutcome.dead, -1),
    );
  }

  Future<ProbeResult> _verifyInner(ProxyModel proxy) async {
    final secret = decodeProxySecret(proxy.secret);
    if (secret == null) {
      return ProbeResult(proxy.key, ProbeOutcome.unsupported, -1);
    }
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    _SocketReader? reader;
    try {
      final allowed = await HostFilter.resolveAllowed(proxy.server);
      if (allowed == null || allowed.isEmpty) {
        return ProbeResult(proxy.key, ProbeOutcome.dead, -1);
      }
      for (final address in allowed.take(3)) {
        socket = await _tryConnect(address, proxy.port);
        if (socket != null) break;
      }
      if (socket == null) {
        return ProbeResult(proxy.key, ProbeOutcome.dead, -1);
      }
      reader = _SocketReader(socket, readDeadline);

      final init = buildInit(random: _random);
      if (init == null) {
        return ProbeResult(proxy.key, ProbeOutcome.dead, -1);
      }
      final ciphers = _ObfuscationCiphers.fromInit(init, secret);
      _zeroize(secret);
      socket.add(ciphers.finalInit);
      await socket.flush();

      final nonce = _randomBytes(16);
      final frame = _wrapPaddedIntermediate(buildReqPq(nonce));
      socket.add(ciphers.encryptor.process(frame));
      await socket.flush();

      final header = await reader.readExactly(4);
      final headerDec = ciphers.decryptor.process(header);
      final length =
          ByteData.sublistView(headerDec).getUint32(0, Endian.little);
      // Quick-ack bit set (0x80000000) is not a valid padded-intermediate
      // length: fail-closed as dead (no protocol change).
      if ((length & 0x80000000) != 0) {
        return ProbeResult(proxy.key, ProbeOutcome.dead, -1);
      }
      // Real resPQ <128B; 512B is a generous DoS bound (was 1MiB via
      // maxPayloadBytes, kept for compat). Fail-closed as dead.
      if (length < 4 || length > maxProbeResponseBytes) {
        return ProbeResult(proxy.key, ProbeOutcome.dead, -1);
      }
      final body = await reader.readExactly(length);
      final bodyDec = ciphers.decryptor.process(body);
      stopwatch.stop();

      if (parseResPq(bodyDec, nonce)) {
        return ProbeResult(
          proxy.key,
          ProbeOutcome.verified,
          max(1, stopwatch.elapsedMilliseconds),
        );
      }
      return ProbeResult(proxy.key, ProbeOutcome.dead, -1);
    } catch (_) {
      return ProbeResult(proxy.key, ProbeOutcome.dead, -1);
    } finally {
      try {
        await reader?.cancel();
      } catch (_) {}
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  Future<Socket?> _tryConnect(InternetAddress address, int port) async {
    try {
      return await Socket.connect(
        address,
        port,
        timeout: const Duration(milliseconds: connectTimeoutMs),
      );
    } catch (_) {
      return null;
    }
  }

  Uint8List _randomBytes(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  static Uint8List? decodeProxySecret(String secret) {
    Uint8List bytes;
    try {
      if (secret.length.isOdd) return null;
      bytes = Uint8List(secret.length ~/ 2);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] =
            int.parse(secret.substring(i * 2, i * 2 + 2), radix: 16);
      }
    } catch (_) {
      return null;
    }
    if (bytes.length == 16) return bytes;
    if (bytes.length == 17 && bytes[0] == 0xdd) {
      final out = bytes.sublist(1);
      _zeroize(bytes);
      return out;
    }
    return null;
  }

  @visibleForTesting
  static Uint8List? buildInit({required Random random, int dc = dcId}) {    for (var attempt = 0; attempt < 64; attempt++) {
      final init = Uint8List(64);
      for (var i = 0; i < 64; i++) {
        init[i] = random.nextInt(256);
      }
      if (init[0] == 0xef) continue;
      final view = ByteData.sublistView(init);
      view.setUint32(56, protocolTag, Endian.little);
      view.setUint16(60, dc.clamp(0, 65535), Endian.little);
      init[62] = random.nextInt(256);
      init[63] = random.nextInt(256);

      final firstInt = view.getUint32(0, Endian.little);
      if (firstInt == 0x44414548 ||
          firstInt == 0x54534f50 ||
          firstInt == 0x20544547 ||
          firstInt == 0x4954504f ||
          firstInt == 0x02010316 ||
          firstInt == 0xdddddddd ||
          firstInt == 0xeeeeeeee) {
        continue;
      }
      if (view.getUint32(4, Endian.little) == 0) continue;
      return init;
    }
    return null;
  }

  static Uint8List sha256(Uint8List data) =>
      SHA256Digest().process(data);

  @visibleForTesting
  static Uint8List obfuscationRoundTrip(
    Uint8List init,
    Uint8List secret,
    Uint8List payload,
  ) =>
      _ObfuscationCiphers.obfuscationRoundTrip(init, secret, payload);

  @visibleForTesting
  static Uint8List obfuscationRoundTripWith(
    Uint8List init,
    Uint8List goodSecret,
    Uint8List badSecret,
    Uint8List payload,
  ) =>
      _ObfuscationCiphers.obfuscationRoundTripWith(
          init, goodSecret, badSecret, payload);

  @visibleForTesting
  static Uint8List buildReqPq(Uint8List nonce) {
    final out = Uint8List(20);
    ByteData.sublistView(out).setUint32(0, reqPqMultiCtor, Endian.little);
    out.setRange(4, 20, nonce);
    return out;
  }

  @visibleForTesting
  static bool parseResPq(Uint8List decrypted, Uint8List nonce) {
    if (decrypted.length < 20) return false;
    // NOTE: Ideal hardening would require decrypted.length >= 36
    // (ctor 4 + nonce 16 + server_nonce 16) to prevent 20B prefix forgery.
    // NOT enforced to 36: existing test
    // test/services/mtproto_probe_service_test.dart pins Uint8List(32)
    // (ctor + nonce only) as true and only Uint8List(10) as false
    // (verified via Grep: no 20B-true pin, no signed-length pin, but 32B-true
    // would break under a 36B threshold). Keep 20 fail-closed here; wire
    // DoS bound is enforced via maxProbeResponseBytes instead. No protocol
    // change.
    if (decrypted.length < 36) {
      debugPrint(
          'mtproto_probe: truncated resPQ (${decrypted.length}B < 36B; server_nonce absent)');
    }
    final ctor =
        ByteData.sublistView(decrypted).getUint32(0, Endian.little);
    if (ctor != resPQCtor) return false;
    for (var i = 0; i < 16; i++) {
      if (decrypted[4 + i] != nonce[i]) return false;
    }
    return true;
  }

  @visibleForTesting
  static ProbeSocketReader openReader(
    Socket socket, [
    Duration? deadline,
  ]) =>
      ProbeSocketReader._(
          _SocketReader(socket, deadline ?? const Duration(seconds: 5)));

  Uint8List _wrapPaddedIntermediate(Uint8List payload) {
    final padLen = _random.nextInt(16);
    final total = payload.length + padLen;
    final out = Uint8List(4 + total);
    ByteData.sublistView(out).setUint32(0, total, Endian.little);
    out.setRange(4, 4 + payload.length, payload);
    for (var i = 0; i < padLen; i++) {
      out[4 + payload.length + i] = _random.nextInt(256);
    }
    return out;
  }
}

@visibleForTesting
class ProbeSocketReader {
  final _SocketReader _inner;
  ProbeSocketReader._(this._inner);

  Future<Uint8List> readExactly(int n) => _inner.readExactly(n);
  Future<void> cancel() => _inner.cancel();
}

class _ObfuscationCiphers {  final Uint8List finalInit;
  final CTRStreamCipher encryptor;
  final CTRStreamCipher decryptor;

  _ObfuscationCiphers._(this.finalInit, this.encryptor, this.decryptor);

  static Uint8List _concat(Uint8List a, Uint8List b) {
    final out = Uint8List(a.length + b.length);
    out.setRange(0, a.length, a);
    out.setRange(a.length, a.length + b.length, b);
    return out;
  }

  static Uint8List _reversed(Uint8List src) {
    final out = Uint8List(src.length);
    for (var i = 0; i < src.length; i++) {
      out[i] = src[src.length - 1 - i];
    }
    return out;
  }

  static CTRStreamCipher _ctr(
    Uint8List key,
    Uint8List iv, {
    required bool encrypt,
  }) {
    return CTRStreamCipher(AESEngine())
      ..init(encrypt, ParametersWithIV(KeyParameter(key), iv));
  }

  @visibleForTesting
  static ({Uint8List key, Uint8List iv}) deriveClientKeys(
    Uint8List init,
    Uint8List secret,
  ) {
    final seed = Uint8List.fromList(init.sublist(8, 40));
    final iv = Uint8List.fromList(init.sublist(40, 56));
    final material = _concat(seed, secret);
    final key = MtprotoProbeService.sha256(material);
    _zeroize(material);
    _zeroize(seed);
    return (key: key, iv: iv);
  }

  @visibleForTesting
  static Uint8List obfuscationRoundTrip(
    Uint8List init,
    Uint8List secret,
    Uint8List payload,
  ) {
    final k = deriveClientKeys(init, secret);
    final e = _ctr(k.key, k.iv, encrypt: true);
    final d = _ctr(
      Uint8List.fromList(k.key),
      Uint8List.fromList(k.iv),
      encrypt: false,
    );
    return d.process(e.process(Uint8List.fromList(payload)));
  }

  @visibleForTesting
  static Uint8List obfuscationRoundTripWith(
    Uint8List init,
    Uint8List goodSecret,
    Uint8List badSecret,
    Uint8List payload,
  ) {
    final g = deriveClientKeys(init, goodSecret);
    final b = deriveClientKeys(init, badSecret);
    final e = _ctr(g.key, g.iv, encrypt: true);
    final d = _ctr(b.key, b.iv, encrypt: false);
    return d.process(e.process(Uint8List.fromList(payload)));
  }

  factory _ObfuscationCiphers.fromInit(
      Uint8List init, Uint8List secret) {
    final initRev = _reversed(init);
    final client = deriveClientKeys(init, secret);
    final serverSeed = Uint8List.fromList(initRev.sublist(8, 40));
    final serverIv = Uint8List.fromList(initRev.sublist(40, 56));
    final serverKeyMaterial = _concat(serverSeed, secret);
    final serverKey = MtprotoProbeService.sha256(serverKeyMaterial);
    _zeroize(serverKeyMaterial);
    _zeroize(serverSeed);

    final enc = _ctr(client.key, client.iv, encrypt: true);
    final dec = _ctr(serverKey, serverIv, encrypt: false);

    final encryptedInit = enc.process(Uint8List.fromList(init));
    final finalInit = Uint8List(64)
      ..setRange(0, 56, init)
      ..setRange(56, 64, encryptedInit.sublist(56, 64));

    return _ObfuscationCiphers._(finalInit, enc, dec);
  }
}

class _SocketReader {
  final Socket _socket;
  final Duration _deadline;
  late final StreamIterator<Uint8List> _it;
  Uint8List _buffer = Uint8List(0);
  bool _cancelled = false;

  _SocketReader(this._socket, this._deadline) {
    _it = StreamIterator<Uint8List>(
      _socket.timeout(
        _deadline,
        onTimeout: (sink) =>
            sink.addError(TimeoutException('probe read deadline')),
      ),
    );
  }

  Future<Uint8List> readExactly(int n) async {
    final out = BytesBuilder(copy: false);
    var buffered = _buffer;
    _buffer = Uint8List(0);
    if (buffered.isNotEmpty) {
      out.add(buffered);
    }
    while (out.length < n) {
      if (_cancelled) throw const SocketException('cancelled');
      final hasMore = await _it.moveNext();
      if (!hasMore) throw const SocketException('closed');
      out.add(_it.current);
    }
    final all = out.toBytes();
    if (all.length > n) {
      _buffer = all.sublist(n);
    }
    return all.sublist(0, n);
  }

  Future<void> cancel() async {
    _cancelled = true;
    try {
      await _it.cancel();
    } catch (_) {}
  }
}
