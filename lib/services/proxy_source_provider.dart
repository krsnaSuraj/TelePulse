import 'dart:math';

import '../data/proxy_sources.dart';

class ProxySourceProvider {
  final Map<String, _SourceHealth> _health = {};
  final Random _random;
  static const int _disableAfterFailures = 3;
  static const Duration recoveryWindow = Duration(minutes: 30);

  ProxySourceProvider({Random? random}) : _random = random ?? Random();

  List<ProxySource> getActiveSources() {
    final now = DateTime.now();
    return ProxySources.primary.where((s) {
      final health = _health[s.name];
      if (health == null) return true;
      if (health.failures < _disableAfterFailures) return true;
      final sinceFailure = now.difference(health.lastFailure);
      if (sinceFailure >= recoveryWindow) {
        _health.remove(s.name);
        return true;
      }
      return false;
    }).toList()
      ..shuffle(_random);
  }

  List<ProxySource> getFallbackSources() {
    return [...ProxySources.fallback]..shuffle(_random);
  }

  void recordSuccess(String sourceName) {
    _health.remove(sourceName);
  }

  void recordFailure(String sourceName) {
    final health = _health.putIfAbsent(sourceName, () => _SourceHealth());
    health.failures++;
    health.lastFailure = DateTime.now();
  }

  int getRetryDelayMs(int attempt) {
    return switch (attempt.clamp(0, 4)) {
      0 => 1000,
      1 => 2000,
      2 => 4000,
      3 => 8000,
      _ => 15000,
    };
  }
}

class _SourceHealth {
  int failures = 0;
  DateTime lastFailure = DateTime.now();
}
