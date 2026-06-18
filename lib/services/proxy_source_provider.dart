import 'dart:math';
import '../data/proxy_sources.dart';

class ProxySourceProvider {
  final Map<String, _SourceHealth> _health = {};
  static const _disableAfterFailures = 3;
  static const _recoveryDelay = Duration(minutes: 30);

  List<ProxySource> getActiveSources() {
    final now = DateTime.now();
    return ProxySources.sources.where((s) {
      final health = _health[s.name];
      if (health == null) return true;
      if (health.failures >= _disableAfterFailures) {
        if (now.difference(health.lastFailure) < _recoveryDelay) {
          return false;
        }
        _health.remove(s.name);
        return true;
      }
      return true;
    }).toList()
      ..shuffle(Random());
  }

  List<ProxySource> getFallbackSources() {
    return List.from(ProxySources.fallbackSources)..shuffle(Random());
  }

  List<ProxySource> getAllSources() {
    return [...getActiveSources(), ...getFallbackSources()];
  }

  void recordSuccess(String sourceName) {
    _health.remove(sourceName);
  }

  void recordFailure(String sourceName) {
    _health.putIfAbsent(sourceName, () => _SourceHealth());
    _health[sourceName]!.failures++;
    _health[sourceName]!.lastFailure = DateTime.now();
  }

  int getRetryDelayMs(int attempt) {
    return [1000, 2000, 4000, 8000, 15000]
        .elementAt(min(attempt, 4));
  }
}

class _SourceHealth {
  int failures = 0;
  DateTime lastFailure = DateTime.now();
}
