import '../models/proxy_model.dart';

class ProxyRankerService {
  static const _aliveScore = 100.0;
  static const _trustedSourceScore = 10.0;
  static const _eeSecretScore = 15.0;
  static const _ddSecretScore = 5.0;
  static const _port443Bonus = 8.0;
  static const _failurePenalty = 50.0;
  static const _maxFailures = 3;

  static const _trustedSources = {'SoliSpirit', 'kort0881-all', 'kort0881-eu', 'kort0881-ru', 'Grim1313'};

  List<ProxyModel> rank(List<ProxyModel> proxies) {
    final scored = proxies
        .map((p) => _RankedProxy(p, _calculateScore(p)))
        .toList();
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((r) => r.proxy).toList();
  }

  List<ProxyModel> topProxies(List<ProxyModel> proxies, {int count = 5}) {
    final ranked = rank(proxies);
    final alive = ranked.where((p) => p.isAlive && p.connectionFailures < _maxFailures).toList();
    return alive.take(count).toList();
  }

  double _calculateScore(ProxyModel proxy) {
    var score = 0.0;

    if (proxy.isAlive && proxy.connectionFailures < _maxFailures) {
      score += _aliveScore;
      if (proxy.latencyMs > 0) {
        score += _latencyScore(proxy.latencyMs);
      }
    }

    if (_trustedSources.contains(proxy.source)) {
      score += _trustedSourceScore;
    }

    if (proxy.secret.startsWith('ee')) {
      score += _eeSecretScore;
    } else if (proxy.secret.startsWith('dd')) {
      score += _ddSecretScore;
    }

    if (proxy.port == 443) {
      score += _port443Bonus;
    }

    score -= proxy.connectionFailures * _failurePenalty;

    return score;
  }

  double _latencyScore(int latencyMs) {
    if (latencyMs < 100) return 50;
    if (latencyMs < 300) return 40;
    if (latencyMs < 500) return 25;
    if (latencyMs < 1000) return 10;
    return 0;
  }
}

class _RankedProxy {
  final ProxyModel proxy;
  final double score;
  const _RankedProxy(this.proxy, this.score);
}
