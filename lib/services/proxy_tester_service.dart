import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../models/proxy_model.dart';

class ProxyTesterService {
  static const connectTimeout = Duration(milliseconds: 1500);
  static const handshakeTimeout = Duration(seconds: 1);
  static const perProxyTimeout = Duration(seconds: 4);
  static const maxParallel = 50;
  static const minParallel = 8;

  Future<ProxyModel> testProxy(ProxyModel proxy) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;

    try {
      socket = await Socket.connect(
        proxy.server,
        proxy.port,
        timeout: connectTimeout,
      );
      stopwatch.stop();

      final verified = await _verifyProxy(proxy, socket);

      return proxy.copyWith(
        isAlive: verified,
        latencyMs: verified ? max(1, stopwatch.elapsedMilliseconds) : -1,
        lastChecked: DateTime.now(),
      );
    } on SocketException catch (_) {
      stopwatch.stop();
      return proxy.copyWith(isAlive: false, latencyMs: -1, lastChecked: DateTime.now());
    } catch (_) {
      stopwatch.stop();
      return proxy.copyWith(isAlive: false, latencyMs: -1, lastChecked: DateTime.now());
    } finally {
      try { socket?.destroy(); } catch (_) {}
    }
  }

  Future<bool> _verifyProxy(ProxyModel proxy, Socket socket) async {
    try {
      final packet = proxy.protocolType == ProxyProtocolType.fakeTls
          ? _buildClientHello()
          : _buildObfuscationPacket();
      socket.add(packet);

      final response = await socket.first.timeout(handshakeTimeout);
      return response.length >= 32;
    } on TimeoutException {
      return false;
    } on StateError {
      return false;
    } catch (_) {
      return false;
    }
  }

  List<int> _buildClientHello() {
    final random = Random();
    final bytes = <int>[];
    bytes.addAll([0x16, 0x03, 0x01]);
    final length = 200 + random.nextInt(100);
    bytes.addAll([
      ((length + 4) >> 8) & 0xff,
      (length + 4) & 0xff,
      0x01,
      0x00,
      (length >> 8) & 0xff,
      length & 0xff,
    ]);
    final targetSize = 9 + length;
    for (var i = bytes.length; i < targetSize; i++) {
      bytes.add(random.nextInt(256));
    }
    return bytes;
  }

  List<int> _buildObfuscationPacket() {
    final random = Random();
    final bytes = List<int>.generate(64, (_) => random.nextInt(256));
    bytes[0] = 0xEF;
    return bytes;
  }
}
