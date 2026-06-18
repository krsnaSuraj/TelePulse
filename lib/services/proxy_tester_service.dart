import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../models/proxy_model.dart';

class ProxyTesterService {
  static const connectTimeout = Duration(milliseconds: 2000);
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

      await socket.close();

      return proxy.copyWith(
        isAlive: true,
        latencyMs: max(1, stopwatch.elapsedMilliseconds),
        lastChecked: DateTime.now(),
      );
    } on SocketException catch (_) {
      return proxy.copyWith(isAlive: false, latencyMs: -1, lastChecked: DateTime.now());
    } catch (_) {
      return proxy.copyWith(isAlive: false, latencyMs: -1, lastChecked: DateTime.now());
    } finally {
      try { socket?.destroy(); } catch (_) {}
    }
  }
}
