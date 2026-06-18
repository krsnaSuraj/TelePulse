import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/proxy_model.dart';
import '../services/proxy_fetcher_service.dart';
import '../services/proxy_tester_service.dart';
import '../services/proxy_ranker_service.dart';
import '../services/deep_link_service.dart';
import '../services/proxy_cache_service.dart';
import '../services/connectivity_service.dart';

enum ProxyLoadState {
  initial,
  loading,
  testing,
  ready,
  error,
  noProxies,
  noInternet,
}

class ProxyListNotifier extends StateNotifier<AsyncValue<List<ProxyModel>>> {
  final ProxyFetcherService _fetcher;
  final ProxyTesterService _tester;
  final ProxyRankerService _ranker;
  final DeepLinkService _deepLink;
  final ProxyCacheService _cache;
  final ConnectivityService _connectivity;

  ProxyLoadState _loadState = ProxyLoadState.initial;
  bool _isFetching = false;
  bool _isTesting = false;
  bool _disposed = false;
  int _totalProxies = 0;
  int _testedCount = 0;

  ProxyListNotifier({
    ProxyFetcherService? fetcher,
    ProxyTesterService? tester,
    ProxyRankerService? ranker,
    DeepLinkService? deepLink,
    ProxyCacheService? cache,
    ConnectivityService? connectivity,
  })  : _fetcher = fetcher ?? ProxyFetcherService(),
        _tester = tester ?? ProxyTesterService(),
        _ranker = ranker ?? ProxyRankerService(),
        _deepLink = deepLink ?? DeepLinkService(),
        _cache = cache ?? ProxyCacheService(),
        _connectivity = connectivity ?? ConnectivityService(),
        super(const AsyncValue.data([]));

  bool get isFetching => _isFetching;
  bool get isTesting => _isTesting;
  ProxyLoadState get loadState => _loadState;
  int get totalProxies => _totalProxies;
  int get testedCount => _testedCount;

  int get aliveCount => aliveProxies.length;
  int get favoriteCount => favoriteProxies.length;

  double get alivePercent {
    final current = state.valueOrNull ?? [];
    if (current.isEmpty) return 0;
    return aliveProxies.length / current.length;
  }

  double get avgLatency {
    final alive = aliveProxies.where((p) => p.latencyMs > 0).toList();
    if (alive.isEmpty) return 0;
    return alive.fold<int>(0, (s, p) => s + p.latencyMs) / alive.length;
  }

  @override
  void dispose() {
    _disposed = true;
    _connectivity.dispose();
    super.dispose();
  }

  Future<void> init() async {
    _connectivity.onConnectivityChanged = (isOnline) {
      if (_disposed) return;
      if (_isTesting) return;
      if (isOnline) {
        unawaited(refreshProxies());
      } else {
        _loadState = ProxyLoadState.noInternet;
      }
    };
    _connectivity.startMonitoring();
    final online = await _connectivity.checkConnectivity();

    if (!online) {
      _loadState = ProxyLoadState.noInternet;
    }

    var cached = await _cache.loadTestedProxies();
    if (cached != null && cached.isNotEmpty) {
      state = AsyncValue.data(cached);
      _loadState = ProxyLoadState.ready;
    } else {
      final stale = await _cache.loadStaleTestedProxies();
      if (stale != null && stale.isNotEmpty) {
        state = AsyncValue.data(stale);
        _loadState = ProxyLoadState.ready;
      }
    }

    if (_connectivity.isOnline) {
      refreshProxies();
    } else {
      _loadState = ProxyLoadState.noInternet;
      if (state.valueOrNull?.isEmpty ?? true) {
        state = const AsyncValue.data([]);
      }
    }
  }

  Future<void> refreshProxies() async {
    if (_isFetching || _disposed) return;
    _isFetching = true;
    _loadState = ProxyLoadState.loading;

    try {
      final currentState = state.valueOrNull;
      if (currentState == null || currentState.isEmpty) {
        state = const AsyncValue.loading();
      }

      final proxies = await _fetcher
          .fetchFromAllSources()
          .timeout(const Duration(seconds: 60), onTimeout: () => <ProxyModel>[]);
      if (_disposed) return;

      if (proxies.isEmpty) {
        final stale = await _cache.loadStaleTestedProxies();
        if (stale != null && stale.isNotEmpty) {
          state = AsyncValue.data(stale);
          _loadState = ProxyLoadState.ready;
          return;
        }
        state = const AsyncValue.data([]);
        _loadState = ProxyLoadState.noProxies;
        return;
      }

      await _cache.saveFetchedProxies(proxies);

      state = AsyncValue.data(proxies);
      _loadState = ProxyLoadState.ready;
      _totalProxies = proxies.length;
      _testedCount = 0;

      unawaited(testProxies(proxyList: proxies));
    } catch (e, st) {
      if (_disposed) return;
      final stale = await _cache.loadStaleTestedProxies();
      if (stale != null && stale.isNotEmpty) {
        state = AsyncValue.data(stale);
        _loadState = ProxyLoadState.ready;
        return;
      }
      _loadState = ProxyLoadState.error;
      state = AsyncValue.error(e, st);
    } finally {
      _isFetching = false;
    }
  }

  Future<void> testProxies({int? parallel, List<ProxyModel>? proxyList}) async {
    final testProxies = proxyList ?? state.valueOrNull;
    if (testProxies == null || testProxies.isEmpty || _disposed) return;
    if (_isTesting) return;
    _isTesting = true;

    _loadState = ProxyLoadState.testing;
    _totalProxies = testProxies.length;
    _testedCount = 0;
    state = AsyncValue.data(state.valueOrNull ?? []);

    try {
      final batchSize = parallel ?? ProxyTesterService.maxParallel;
      final perProxyTimeout = ProxyTesterService.perProxyTimeout;
      final batches = _batch(testProxies, batchSize);
      final testedMap = <String, ProxyModel>{};
      var batchCount = 0;

      for (final batch in batches) {
        if (_disposed) return;
        final batchResults = await Future.wait(batch.map(
          (p) => _tester.testProxy(p).timeout(
            perProxyTimeout,
            onTimeout: () => p.copyWith(
              isAlive: false,
              latencyMs: -1,
              lastChecked: DateTime.now(),
            ),
          ),
        ));

        if (_disposed) return;

        for (final result in batchResults) {
          testedMap['${result.server}:${result.port}:${result.secret}'] = result;
        }

        _testedCount += batchResults.length;
        batchCount++;

        if (batchCount % 3 == 0 || batchCount == batches.length) {
          final merged = _mergeResults(testedMap);
          final ranked = _ranker.rank(merged);
          final withFavorites = await _restoreFavorites(ranked);
          if (_disposed) return;
          await _cache.saveTestedProxies(withFavorites);
          state = AsyncValue.data(withFavorites);
        }
      }

      _loadState = ProxyLoadState.ready;
    } catch (e, st) {
      if (_disposed) return;
      _loadState = ProxyLoadState.ready;
      state = AsyncValue.error(e, st);
    } finally {
      _isTesting = false;
    }
  }

  List<ProxyModel> _mergeResults(Map<String, ProxyModel> testedMap) {
    final currentState = state.valueOrNull ?? [];
    final existingKeys = currentState
        .map((p) => '${p.server}:${p.port}:${p.secret}')
        .toSet();
    final merged = currentState.map((proxy) {
      final key = '${proxy.server}:${proxy.port}:${proxy.secret}';
      return testedMap[key] ?? proxy;
    }).toList();
    for (final entry in testedMap.entries) {
      if (!existingKeys.contains(entry.key)) {
        merged.add(entry.value);
      }
    }
    return merged;
  }

  List<List<ProxyModel>> _batch(List<ProxyModel> items, int size) {
    final batches = <List<ProxyModel>>[];
    for (var i = 0; i < items.length; i += size) {
      final end = i + size;
      batches.add(items.sublist(i, end > items.length ? items.length : end));
    }
    return batches;
  }

  Future<void> testSingleProxy(ProxyModel proxy) async {
    try {
      final result = await _tester.testProxy(proxy);
      final current = state.valueOrNull ?? [];
      final updated = current.map((p) => p == proxy ? result : p).toList();
      final ranked = _ranker.rank(updated);
      state = AsyncValue.data(ranked);
    } catch (e) {
      debugPrint('testSingleProxy failed: $e');
    }
  }

  Future<DeepLinkResult> connectToProxy(ProxyModel proxy) async {
    return _deepLink.connectWithProxy(proxy);
  }

  Future<void> toggleFavorite(ProxyModel proxy) async {
    final current = state.valueOrNull ?? [];
    final updated = current.map((p) {
      if (p == proxy) return p.copyWith(isFavorite: !p.isFavorite);
      return p;
    }).toList();
    state = AsyncValue.data(updated);
    unawaited(_saveFavorites(updated));
  }

  List<ProxyModel> get aliveProxies {
    final current = state.valueOrNull ?? [];
    return current.where((p) => p.isAlive).toList();
  }

  List<ProxyModel> get favoriteProxies {
    final current = state.valueOrNull ?? [];
    return current.where((p) => p.isFavorite).toList();
  }

  List<ProxyModel> topProxies({int count = 5}) {
    final alive = aliveProxies;
    if (alive.isEmpty) return [];
    return _ranker.topProxies(alive, count: count);
  }

  Future<bool> addCustomSource(String url) async {
    if (url.trim().isEmpty) return false;
    final proxies = await _fetcher.fetchFromCustomUrl(url.trim());
    if (proxies.isEmpty) return false;

    final current = state.valueOrNull ?? [];
    final merged = [...current];
    for (final proxy in proxies) {
      if (!merged.any((p) =>
          p.server == proxy.server &&
          p.port == proxy.port &&
          p.secret == proxy.secret)) {
        merged.add(proxy);
      }
    }
    state = AsyncValue.data(merged);
    return true;
  }

  Future<void> _saveFavorites(List<ProxyModel> proxies) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites = proxies.where((p) => p.isFavorite).toList();
      final json = jsonEncode(favorites.map((p) => p.toJson()).toList());
      await prefs.setString('favorites', json);
    } catch (e) {
      debugPrint('Failed to save favorites: $e');
    }
  }

  Future<List<ProxyModel>> _restoreFavorites(List<ProxyModel> proxies) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('favorites');
      if (json == null || json.isEmpty) return proxies;

      final saved = (jsonDecode(json) as List)
          .map((e) => ProxyModel.fromJson(e as Map<String, dynamic>))
          .toList();

      return proxies.map((p) {
        final match = saved.any(
          (s) =>
              s.server == p.server &&
              s.port == p.port &&
              s.secret == p.secret,
        );
        return match ? p.copyWith(isFavorite: true) : p;
      }).toList();
    } catch (_) {
      return proxies;
    }
  }
}

final proxyListProvider =
    StateNotifierProvider<ProxyListNotifier, AsyncValue<List<ProxyModel>>>(
        (ref) {
  final notifier = ProxyListNotifier();
  notifier.init();
  return notifier;
});
