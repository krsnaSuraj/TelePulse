import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../core/app_constants.dart';
import '../models/proxy_model.dart';
import 'host_filter.dart';

class ProxyTesterService {
  static const tcpConnectTimeout = AppConstants.tcpConnectTimeout;

  Future<ProxyModel> testProxy(ProxyModel proxy) async {
    final allowed = await HostFilter.resolveAllowed(proxy.server);
    if (allowed == null || allowed.isEmpty) {
      return proxy.withTestResult(alive: false, latency: -1);
    }

    Socket? socket;
    for (final address in allowed.take(3)) {
      final stopwatch = Stopwatch()..start();
      try {
        socket = await Socket.connect(
          address,
          proxy.port,
          timeout: tcpConnectTimeout,
        );
        stopwatch.stop();
        final result = proxy.withTestResult(
          alive: true,
          latency: max(1, stopwatch.elapsedMilliseconds),
        );
        try {
          await socket.close();
        } catch (_) {}
        socket = null;
        return result;
      } catch (_) {
        try {
          socket?.destroy();
        } catch (_) {}
        socket = null;
      }
    }
    return proxy.withTestResult(alive: false, latency: -1);
  }

  static int concurrencyFor(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.wifi:
      case ConnectivityResult.ethernet:
        return AppConstants.concurrencyWifi;
      case ConnectivityResult.mobile:
      case ConnectivityResult.vpn:
        return AppConstants.concurrencyMobile;
      case ConnectivityResult.bluetooth:
      case ConnectivityResult.none:
      case ConnectivityResult.other:
      case ConnectivityResult.satellite:
        return AppConstants.concurrencyMobile;
    }
  }
}
