import '../core/app_constants.dart';
import '../data/proxy_sources.dart';
import '../models/proxy_model.dart';

class ProxyRankerService {
  ProxyRankerService._();

  static const double _aliveScore = 100;
  static const double _fakeTlsBonus = 15;
  static const double _ddPaddingBonus = 5;
  static const double _port443Bonus = 8;
  static const double _failurePenalty = 50;

  static int tierOf(ProxyModel p) {
    if (p.isAlive && p.mtpVerified) return 3;
    if (p.isAlive) return 2;
    if (p.isUntested) return 1;
    return 0;
  }

  static double scoreOf(ProxyModel p) {
    var score = 0.0;
    if (p.isAlive) {
      score += _aliveScore;
      if (p.latencyMs > 0) score += _latencyScore(p.latencyMs);
    }
    score += ProxySources.trustBonusFor(p.source).toDouble();
    if (p.protocolType == ProxyProtocolType.fakeTls && p.mtpVerified) {
      score += _fakeTlsBonus;
    }
    if (p.protocolType == ProxyProtocolType.ddPadding) score += _ddPaddingBonus;
    if (p.port == 443) score += _port443Bonus;
    final failures = p.connectionFailures.clamp(
      0,
      AppConstants.maxTrackedFailures,
    );
    score -= failures * _failurePenalty;
    return score;
  }

  static double _latencyScore(int latencyMs) {
    if (latencyMs < 100) return 50;
    if (latencyMs < 300) return 40;
    if (latencyMs < 500) return 25;
    if (latencyMs < 1000) return 10;
    return 0;
  }

  static int compare(ProxyModel a, ProxyModel b) {
    final tier = tierOf(b).compareTo(tierOf(a));
    if (tier != 0) return tier;
    final score = scoreOf(b).compareTo(scoreOf(a));
    if (score != 0) return score;
    final la = a.latencyMs <= 0 ? 1 << 30 : a.latencyMs;
    final lb = b.latencyMs <= 0 ? 1 << 30 : b.latencyMs;
    final lat = la.compareTo(lb);
    if (lat != 0) return lat;
    return a.key.compareTo(b.key);
  }

  static List<ProxyModel> rank(List<ProxyModel> proxies) {
    final sorted = [...proxies]..sort(compare);
    return sorted;
  }

  static List<ProxyModel> topProxies(
    List<ProxyModel> proxies, {
    int count = 5,
  }) {
    return rank(proxies)
        .where((p) =>
            p.isAlive &&
            p.connectionFailures < AppConstants.maxFailuresBeforeExclusion)
        .take(count)
        .toList();
  }
}
