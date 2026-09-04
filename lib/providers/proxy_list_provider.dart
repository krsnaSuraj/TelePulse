import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_constants.dart';
import '../models/proxy_model.dart';
import '../services/connectivity_service.dart';
import '../services/deep_link_service.dart';
import '../services/mtproto_probe_service.dart';
import '../services/proxy_cache_service.dart';
import '../services/proxy_fetcher_service.dart';
import '../services/proxy_parser.dart';
import '../services/proxy_ranker_service.dart';
import '../services/proxy_tester_service.dart';

enum ProxyLoadState {
  initial,
  loading,
  ready,
  testing,
  error,
  noProxies,
  noInternet,
}

enum NoticeKind { none, offline, staleCache, refreshFailed, mobilePaused }

class ProxyListState {
  final ProxyLoadState loadState;
  final List<ProxyModel> proxies;
  final String errorMessage;
  final NoticeKind notice;
  final bool isFetching;
  final bool isTesting;
  final int testedCount;
  final int totalToTest;
  final DateTime? lastUpdated;
  final List<String> customSources;
  final bool wifiOnlyAutoScan;
  final bool autoScanOnReconnect;

  const ProxyListState({
    this.loadState = ProxyLoadState.initial,
    this.proxies = const [],
    this.errorMessage = '',
    this.notice = NoticeKind.none,
    this.isFetching = false,
    this.isTesting = false,
    this.testedCount = 0,
    this.totalToTest = 0,
    this.lastUpdated,
    this.customSources = const [],
    this.wifiOnlyAutoScan = false,
    this.autoScanOnReconnect = true,
  });

  int get aliveCount => proxies.where((p) => p.isAlive).length;
  int get untestedCount => proxies.where((p) => p.isUntested).length;
  int get favoriteCount => proxies.where((p) => p.isFavorite).length;

  double get avgLatency {
    final latencies =
        proxies.where((p) => p.isAlive && p.latencyMs > 0).map((p) => p.latencyMs);
    var sum = 0;
    var n = 0;
    for (final l in latencies) {
      sum += l;
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  ProxyListState copyWith({
    ProxyLoadState? loadState,
    List<ProxyModel>? proxies,
    String? errorMessage,
    NoticeKind? notice,
    bool? isFetching,
    bool? isTesting,
    int? testedCount,
    int? totalToTest,
    DateTime? lastUpdated,
    List<String>? customSources,
    bool? wifiOnlyAutoScan,
    bool? autoScanOnReconnect,
  }) {
    return ProxyListState(
      loadState: loadState ?? this.loadState,
      proxies: proxies ?? this.proxies,
      errorMessage: errorMessage ?? this.errorMessage,
      notice: notice ?? this.notice,
      isFetching: isFetching ?? this.isFetching,
      isTesting: isTesting ?? this.isTesting,
      testedCount: testedCount ?? this.testedCount,
      totalToTest: totalToTest ?? this.totalToTest,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      customSources: customSources ?? this.customSources,
      wifiOnlyAutoScan: wifiOnlyAutoScan ?? this.wifiOnlyAutoScan,
      autoScanOnReconnect:
          autoScanOnReconnect ?? this.autoScanOnReconnect,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProxyListState &&
          runtimeType == other.runtimeType &&
          loadState == other.loadState &&
          isFetching == other.isFetching &&
          isTesting == other.isTesting &&
          testedCount == other.testedCount &&
          totalToTest == other.totalToTest &&
          notice == other.notice &&
          errorMessage == other.errorMessage &&
          lastUpdated == other.lastUpdated &&
          wifiOnlyAutoScan == other.wifiOnlyAutoScan &&
          autoScanOnReconnect == other.autoScanOnReconnect &&
          customSources.equals(other.customSources) &&
          proxies.equals(other.proxies);

  @override
  int get hashCode => Object.hash(
        loadState,
        isFetching,
        isTesting,
        testedCount,
        totalToTest,
        notice,
        errorMessage,
        lastUpdated,
        wifiOnlyAutoScan,
        autoScanOnReconnect,
        Object.hashAll(customSources),
        Object.hashAll(proxies),
      );
}

extension _ListEq<T> on List<T> {
  bool equals(List<T> other) {
    if (identical(this, other)) return true;
    if (length != other.length) return false;
    for (var i = 0; i < length; i++) {
      if (this[i] != other[i]) return false;
    }
    return true;
  }
}

enum CustomSourceResult {
  added,
  duplicate,
  invalidUrl,
  insecureScheme,
  noProxiesFound,
}

class ProxyListNotifier extends StateNotifier<ProxyListState> {
  final ProxyFetcherService _fetcher;
  final ProxyTesterService _tester;
  final MtprotoProbeService _probe;
  final DeepLinkService _deepLink;
  final ProxyCacheService _cache;
  final ConnectivityService _connectivity;
  final Random _random;

  StreamSubscription<bool>? _connectivitySub;
  final Map<String, ProxyModel> _pendingTests = <String, ProxyModel>{};
  bool _isRunningTest = false;
  bool _isVerifying = false;
  bool _pendingRefresh = false;
  bool _pendingReconnect = false;
  bool _disposed = false;
  bool _initialized = false;
  int _sweepGen = 0;
  int _verifyGen = 0;
  Set<String> _favoriteKeys = <String>{};
  final Completer<void> _initCompleter = Completer<void>();

  ProxyListNotifier({
    ProxyFetcherService? fetcher,
    ProxyTesterService? tester,
    MtprotoProbeService? probe,
    DeepLinkService? deepLink,
    ProxyCacheService? cache,
    ConnectivityService? connectivity,
    Random? random,
    bool autoInit = true,
  })  : _fetcher = fetcher ?? ProxyFetcherService(),
        _tester = tester ?? ProxyTesterService(),
        _probe = probe ?? MtprotoProbeService(),
        _deepLink = deepLink ?? DeepLinkService(),
        _cache = cache ?? ProxyCacheService(),
        _connectivity = connectivity ?? ConnectivityService(),
        _random = random ?? Random(),
        super(const ProxyListState()) {
    if (autoInit) {
      unawaited(init());
    }
  }

  @visibleForTesting
  Future<void> get initialized => _initCompleter.future;

  DeepLinkService get deepLink => _deepLink;

  List<ProxyModel> topProxies({int count = 5}) =>
      ProxyRankerService.topProxies(state.proxies, count: count);

  @override
  void dispose() {
    _disposed = true;
    try {
      _connectivitySub?.cancel().catchError((_) {});
    } catch (_) {}
    _connectivity.dispose();
    unawaited(_cache.flushPendingWrites());
    if (!_initCompleter.isCompleted) {
      _initCompleter.complete();
    }
    super.dispose();
  }

  Future<void> init() async {
    if (_initialized || _disposed) {
      if (!_initCompleter.isCompleted) _initCompleter.complete();
      return;
    }
    _initialized = true;

    try {
      final customUrls = await _cache.loadCustomSources();
      if (_disposed) return;
      final wifiOnly = await _cache.loadWifiOnlyAutoScan();
      if (_disposed) return;
      final autoScan = await _cache.loadAutoScanOnReconnect();
      if (_disposed) return;
      state = state.copyWith(
        customSources: customUrls,
        wifiOnlyAutoScan: wifiOnly,
        autoScanOnReconnect: autoScan,
      );

      _connectivitySub = _connectivity.changes.listen(_onConnectivityChanged);
      _connectivity.startMonitoring();
      final online = await _connectivity.checkNow();

      var cached = await _cache.loadTestedProxies();
      cached ??= await _cache.loadFetchedProxies();
      var usedStale = false;
      if (cached == null) {
        cached = await _cache.loadStaleTestedProxies();
        usedStale = cached != null && cached.isNotEmpty;
      }

      if (cached != null && cached.isNotEmpty) {
        final favorites = await _cache.loadFavorites();
        final seeded = _seedFavorites(cached, favorites);
        final ranked = ProxyRankerService.rank(seeded);
        state = state.copyWith(
          proxies: ranked,
          loadState: ProxyLoadState.ready,
          notice: !online
              ? NoticeKind.offline
              : (usedStale ? NoticeKind.staleCache : NoticeKind.none),
          lastUpdated: usedStale ? null : DateTime.now(),
        );
        if (online && await _shouldAutoScan()) {
          enqueueTest(ranked);
        } else if (online) {
          state = state.copyWith(notice: NoticeKind.mobilePaused);
        }
      } else if (online) {
        state = state.copyWith(loadState: ProxyLoadState.loading);
        if (await _shouldAutoScan()) {
          await refreshProxies();
        } else {
          state = state.copyWith(
            loadState: ProxyLoadState.ready,
            notice: NoticeKind.mobilePaused,
          );
        }
      } else {
        state = state.copyWith(loadState: ProxyLoadState.noInternet);
      }
    } catch (_) {
      if (!_disposed) {
        state = state.copyWith(
          loadState: ProxyLoadState.error,
          errorMessage: 'Something went wrong while starting TelePulse.',
        );
      }
    } finally {
      if (!_initCompleter.isCompleted) _initCompleter.complete();
    }
  }

  void _onConnectivityChanged(bool online) {
    if (_disposed) return;
    if (_isRunningTest) {
      _pendingReconnect = true;
      return;
    }
    if (online) {
      unawaited(_autoRefreshOnReconnect());
    } else {
      state = state.copyWith(notice: NoticeKind.offline);
    }
  }

  Future<void> _autoRefreshOnReconnect() async {
    if (!state.autoScanOnReconnect) return;
    if (!await _shouldAutoScan()) {
      if (!_disposed) {
        state = state.copyWith(notice: NoticeKind.mobilePaused);
      }
      return;
    }
    await refreshProxies();
  }

  Future<bool> _shouldAutoScan() async {
    if (!state.wifiOnlyAutoScan) return true;
    final type = await _connectivity.currentConnectionType();
    return type == ConnectivityResult.wifi ||
        type == ConnectivityResult.ethernet;
  }

  Future<void> setWifiOnlyAutoScan(bool value) async {
    if (_disposed) return;
    await _cache.saveWifiOnlyAutoScan(value);
    if (_disposed) return;
    state = state.copyWith(wifiOnlyAutoScan: value);
  }

  Future<void> setAutoScanOnReconnect(bool value) async {
    if (_disposed) return;
    await _cache.saveAutoScanOnReconnect(value);
    if (_disposed) return;
    state = state.copyWith(autoScanOnReconnect: value);
  }

  Future<void> refreshProxies() async {
    if (_disposed) return;
    if (state.isFetching) {
      _pendingRefresh = true;
      return;
    }
    state = state.copyWith(isFetching: true);
    try {
      final builtinFuture = _fetcher.fetchFromAllSources();
      final customUrls = List<String>.from(state.customSources);
      final customFutures =
          customUrls.map(_fetcher.fetchOnlyCustomUrl).toList();
      final results = await Future.wait([
        builtinFuture,
        ...customFutures,
      ]).timeout(
        const Duration(seconds: 60),
        onTimeout: () => <List<ProxyModel>>[],
      );
      final fetched = results.expand((l) => l).toList();
      if (_disposed) return;
      if (fetched.isEmpty) {
        _handleFetchFailure();
        return;
      }
      _verifyGen++;
      _applyFetchResult(fetched);
    } catch (_) {
      if (_disposed) return;
      _handleFetchFailure();
    } finally {
      if (!_disposed) {
        state = state.copyWith(isFetching: false);
        if (_pendingRefresh && !_disposed) {
          _pendingRefresh = false;
          unawaited(refreshProxies());
        }
      }
    }
  }

  void _applyFetchResult(List<ProxyModel> fetched) {
    if (fetched.isEmpty) {
      _handleFetchFailure();
      return;
    }
    final merged = mergePreservingExisting(state.proxies, fetched);
    _cache.saveFetchedProxies(fetched);
    final ranked = ProxyRankerService.rank(merged);
    state = state.copyWith(
      proxies: ranked,
      loadState: _isRunningTest ? null : ProxyLoadState.ready,
      notice: NoticeKind.none,
      errorMessage: '',
      lastUpdated: DateTime.now(),
    );
    enqueueTest(ranked);
  }

  void _handleFetchFailure() {
    if (state.proxies.isNotEmpty) {
      state = state.copyWith(
        notice: NoticeKind.refreshFailed,
        loadState: ProxyLoadState.ready,
      );
      return;
    }
    unawaited(() async {
      final stale = await _cache.loadStaleTestedProxies();
      if (_disposed) return;
      if (stale != null && stale.isNotEmpty) {
        final favorites = await _cache.loadFavorites();
        final seeded = _seedFavorites(stale, favorites);
        state = state.copyWith(
          proxies: ProxyRankerService.rank(seeded),
          loadState: ProxyLoadState.ready,
          notice: NoticeKind.staleCache,
        );
      } else {
        state = state.copyWith(loadState: ProxyLoadState.noProxies);
      }
    }());
  }

  @visibleForTesting
  static List<ProxyModel> mergePreservingExisting(
    List<ProxyModel> existing,
    List<ProxyModel> incoming,
  ) {
    final byKey = <String, ProxyModel>{
      for (final p in existing) p.key: p,
    };
    for (final p in incoming) {
      byKey.putIfAbsent(p.key, () => p);
    }
    return byKey.values.toList(growable: false);
  }

  List<ProxyModel> _seedFavorites(
    List<ProxyModel> base,
    List<ProxyModel> favorites,
  ) {
    final byKey = <String, ProxyModel>{
      for (final p in base) p.key: p,
    };
    for (final f in favorites) {
      final existing = byKey[f.key];
      byKey[f.key] = existing == null
          ? f.copyWith(isFavorite: true, mtpVerified: false)
          : existing.copyWith(isFavorite: true);
    }
    return byKey.values.toList(growable: false);
  }

  void enqueueTest(List<ProxyModel> list) {
    if (_disposed || list.isEmpty) return;
    if (_isRunningTest) {
      for (final p in list) {
        _pendingTests[p.key] = p;
      }
      return;
    }
    unawaited(_runTest(list));
  }

  Future<void> _runTest(List<ProxyModel> list) async {
    if (_disposed || list.isEmpty || _isRunningTest) return;
    _isRunningTest = true;
    try {
      _verifyGen++;
      final gen = _sweepGen;

    List<ProxyModel> favorites = const [];
    try {
      favorites = await _cache.loadFavorites();
    } catch (_) {
      favorites = const [];
    }
    _favoriteKeys = {
      ...favorites.map((f) => f.key),
      for (final p in state.proxies.where((e) => e.isFavorite)) p.key,
      for (final p in list.where((e) => e.isFavorite)) p.key,
    };

    final seededState = _seedFavorites(state.proxies, favorites);
    final seededList = _seedFavorites(list, favorites);
    final working = mergePreservingExisting(seededState, seededList);
    final hadAliveBefore =
        list.any((p) => p.isAlive) || working.any((p) => p.isAlive);
    final shuffled = [...working]..shuffle(_random);

    if (_disposed || gen != _sweepGen) return;
    state = state.copyWith(
      proxies: ProxyRankerService.rank(working),
      loadState: ProxyLoadState.testing,
      isTesting: true,
      testedCount: 0,
      totalToTest: shuffled.length,
    );

    final concurrency = await _resolveConcurrency();
    if (_disposed || gen != _sweepGen) return;
    final results = <String, ProxyModel>{};
    final batches = _batches(shuffled, concurrency);

    try {
      for (final batch in batches) {
        if (_disposed || gen != _sweepGen) return;
        final batchResults = await Future.wait(
          [for (var i = 0; i < batch.length; i++) _testWithGuards(batch[i], i)],
        );
        for (final r in batchResults) {
          results[r.key] = r;
        }
        if (_disposed || gen != _sweepGen) return;

        final base = state.proxies;
        final updated = _applyResults(base, results);
        state = state.copyWith(
          proxies: ProxyRankerService.rank(updated),
          testedCount: results.length,
        );
      }

      if (_disposed || gen != _sweepGen) return;
      final current = state.proxies;
      final anyAlive = current.any((p) => p.isAlive);
      if (!(anyAlive == false && hadAliveBefore)) {
        _cache.saveTestedProxies(ProxyRankerService.rank(current));
      }
      state = state.copyWith(
        loadState: ProxyLoadState.ready,
        isTesting: false,
        lastUpdated: DateTime.now(),
      );
    } catch (_) {
      if (_disposed || gen != _sweepGen) return;
      state = state.copyWith(
        loadState: ProxyLoadState.ready,
        isTesting: false,
        notice: NoticeKind.refreshFailed,
      );
    } finally {
      _isRunningTest = false;
    }

    if (!_disposed && _pendingTests.isNotEmpty) {
      final next = _pendingTests.values.toList(growable: false);
      _pendingTests.clear();
      await _runTest(next);
    }
    if (!_disposed && _pendingRefresh) {
      _pendingRefresh = false;
      await refreshProxies();
    }
    if (!_disposed && _pendingReconnect) {
      _pendingReconnect = false;
      await _autoRefreshOnReconnect();
    }
    if (!_disposed) {
      unawaited(_verifyTopCandidates());
    }
    } finally {
      // Outer guard: early returns at gen-checks (clearCachedData path)
      // must not leak _isRunningTest=true (deadlock fix).
      _isRunningTest = false;
    }
  }

  Future<void> _verifyTopCandidates() async {
    if (_disposed || _isVerifying) return;
    final metered = await _isMeteredConnection();
    final cap = metered
        ? AppConstants.mobileVerifyCap
        : MtprotoProbeService.maxCandidatesPerSweep;
    final recheckQuota =
        metered ? 2 : MtprotoProbeService.reverifyQuota;
    final alive =
        state.proxies.where((p) => p.isAlive).toList(growable: false);
    final recheck =
        alive.where((p) => p.mtpVerified).take(recheckQuota).toList();
    final fresh = alive.where((p) => !p.mtpVerified).toList()
      ..sort((a, b) {
        final va =
            MtprotoProbeService.decodeProxySecret(a.secret) != null ? 0 : 1;
        final vb =
            MtprotoProbeService.decodeProxySecret(b.secret) != null ? 0 : 1;
        if (va != vb) return va.compareTo(vb);
        return a.latencyMs.compareTo(b.latencyMs);
      });
    final candidates =
        [...recheck, ...fresh.take(cap - recheck.length)].toList();
    if (candidates.isEmpty) return;
    _isVerifying = true;
    final gen = _verifyGen;
    try {
      final shortlist = candidates.take(cap);
      final batches = _batches(
        shortlist.toList(growable: false),
        MtprotoProbeService.maxVerifyConcurrency,
      );
      for (final batch in batches) {
        if (_disposed || gen != _verifyGen) return;
        final results = await Future.wait(
          batch.map((p) => _probe.verify(p)),
        );
        if (_disposed || gen != _verifyGen) return;
        var changed = false;
        final updated = state.proxies.map((p) {
          for (final r in results) {
            if (r.key != p.key) continue;
            if (r.outcome == ProbeOutcome.verified &&
                p.isAlive &&
                !p.mtpVerified) {
              changed = true;
              return p.copyWith(mtpVerified: true);
            }
            if (r.outcome == ProbeOutcome.dead && p.mtpVerified) {
              changed = true;
              return p.copyWith(mtpVerified: false);
            }
          }
          return p;
        }).toList();
        if (changed) {
          state = state.copyWith(
            proxies: ProxyRankerService.rank(updated),
          );
        }
      }
      if (gen != _verifyGen) return;
      _cache.saveTestedProxies(state.proxies);
    } catch (_) {
    } finally {
      _isVerifying = false;
    }
  }

  Future<bool> _isMeteredConnection() async {
    final type = await _connectivity.currentConnectionType();
    return type != ConnectivityResult.wifi &&
        type != ConnectivityResult.ethernet;
  }

  Future<ProxyModel> _testWithGuards(ProxyModel proxy, int indexInBatch) async {
    final staggerMs = AppConstants.openStaggerBase.inMilliseconds * indexInBatch +
        _random.nextInt(AppConstants.openStaggerJitterMaxMs + 1);
    if (staggerMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: staggerMs));
    }
    try {
      return await _tester
          .testProxy(proxy)
          .timeout(AppConstants.perProxyEnvelopeTimeout,
              onTimeout: () => proxy.withTestResult(alive: false, latency: -1));
    } catch (_) {
      return proxy.withTestResult(alive: false, latency: -1);
    }
  }

  Future<int> _resolveConcurrency() async {
    final type = await _connectivity.currentConnectionType();
    return ProxyTesterService.concurrencyFor(type);
  }

  List<ProxyModel> _applyResults(
    List<ProxyModel> current,
    Map<String, ProxyModel> results,
  ) {
    final out = <ProxyModel>[];
    for (final p in current) {
      final shouldFavorite = p.isFavorite || _favoriteKeys.contains(p.key);
      final r = results[p.key];
      if (r == null) {
        out.add(shouldFavorite ? p.copyWith(isFavorite: true) : p);
        continue;
      }
      out.add(
        p.copyWith(
          isAlive: r.isAlive,
          latencyMs: r.latencyMs,
          lastChecked: r.lastChecked,
          connectionFailures: r.isAlive ? 0 : p.connectionFailures,
          isFavorite: shouldFavorite,
          mtpVerified: r.isAlive && p.mtpVerified,
        ),
      );
    }
    return out;
  }

  List<List<ProxyModel>> _batches(List<ProxyModel> items, int size) {
    final effectiveSize = size < 1 ? AppConstants.concurrencyMobile : size;
    final batches = <List<ProxyModel>>[];
    for (var i = 0; i < items.length; i += effectiveSize) {
      final end = i + effectiveSize > items.length ? items.length : i + effectiveSize;
      batches.add(items.sublist(i, end));
    }
    return batches;
  }

  Future<void> retestSingle(ProxyModel proxy) async {
    if (_disposed) return;
    var conclusive = true;
    ProxyModel result;
    try {
      result = await _tester
          .testProxy(proxy)
          .timeout(AppConstants.perProxyEnvelopeTimeout, onTimeout: () {
        conclusive = false;
        return proxy.withTestResult(alive: false, latency: -1);
      });
    } catch (_) {
      conclusive = false;
      result = proxy.withTestResult(alive: false, latency: -1);
    }
    if (_disposed) return;
    _updateSingle(
      proxy,
      result,
      countFailure: conclusive && !result.isAlive,
    );
  }

  void _updateSingle(
    ProxyModel target,
    ProxyModel result, {
    required bool countFailure,
  }) {
    final updated = state.proxies.map((p) {
      if (p.key != target.key) return p;
      final nextFailures = countFailure
          ? (p.connectionFailures + 1)
              .clamp(0, AppConstants.maxTrackedFailures)
          : (result.isAlive ? 0 : p.connectionFailures);
      return p.copyWith(
        isAlive: result.isAlive,
        latencyMs: result.latencyMs,
        lastChecked: result.lastChecked,
        connectionFailures: nextFailures,
        mtpVerified: countFailure
            ? (result.isAlive && p.mtpVerified)
            : p.mtpVerified,
      );
    }).toList();
    final ranked = ProxyRankerService.rank(updated);
    state = state.copyWith(proxies: ranked);
    _cache.saveTestedProxies(ranked);
  }

  Future<void> toggleFavorite(ProxyModel proxy) async {
    if (_disposed) return;
    final updatedList = <ProxyModel>[];
    ProxyModel? toggled;
    for (final p in state.proxies) {
      if (p.key == proxy.key) {
        toggled = p.copyWith(isFavorite: !p.isFavorite);
        updatedList.add(toggled);
      } else {
        updatedList.add(p);
      }
    }
    if (toggled == null) return;
    if (toggled.isFavorite) {
      _favoriteKeys.add(toggled.key);
    } else {
      _favoriteKeys.remove(toggled.key);
    }
    state = state.copyWith(proxies: updatedList);
    _cache.saveFavorites(
      updatedList.where((p) => p.isFavorite).toList(growable: false),
    );
  }

  Future<CustomSourceResult> addCustomSource(String rawUrl) async {
    if (_disposed) return CustomSourceResult.invalidUrl;
    final url = rawUrl.trim();
    if (url.startsWith('http://')) return CustomSourceResult.insecureScheme;
    final parsedUri = Uri.tryParse(url);
    if (parsedUri == null ||
        !parsedUri.hasScheme ||
        !ProxyParser.isValidCustomSourceUrl(url)) {
      return CustomSourceResult.invalidUrl;
    }
    if (state.customSources.contains(url)) {
      return CustomSourceResult.duplicate;
    }
    final parsed = await _fetcher.fetchOnlyCustomUrl(url);
    if (_disposed) return CustomSourceResult.invalidUrl;
    if (parsed.isEmpty) return CustomSourceResult.noProxiesFound;

    final newUrls = [...state.customSources, url];
    await _cache.saveCustomSources(newUrls);

    final preMergeKeys = {for (final p in state.proxies) p.key};
    final merged = mergePreservingExisting(state.proxies, parsed);
    final ranked = ProxyRankerService.rank(merged);
    state = state.copyWith(
      proxies: ranked,
      customSources: newUrls,
      loadState: ProxyLoadState.ready,
      notice: NoticeKind.none,
    );
    final freshNewcomers =
        parsed.where((p) => !preMergeKeys.contains(p.key)).toList();
    if (freshNewcomers.isNotEmpty) {
      enqueueTest(freshNewcomers);
    }
    return CustomSourceResult.added;
  }

  Future<void> removeCustomSource(String url) async {
    if (_disposed) return;
    final newUrls = state.customSources.where((u) => u != url).toList();
    await _cache.saveCustomSources(newUrls);
    state = state.copyWith(customSources: newUrls);
  }

  Future<void> clearCachedData() async {
    if (_disposed) return;
    _sweepGen++;
    _verifyGen++;
    await _cache.clear();
    if (_disposed) return;
    _favoriteKeys = <String>{};
    _pendingTests.clear();
    _pendingRefresh = false;
    _pendingReconnect = false;
    state = ProxyListState(
      customSources: state.customSources,
      wifiOnlyAutoScan: state.wifiOnlyAutoScan,
      autoScanOnReconnect: state.autoScanOnReconnect,
    );
  }

  /// Full wipe: caches, favorites, custom sources, toggles, update state.
  /// Unlike [clearCachedData], nothing is preserved.
  Future<void> deleteAllData() async {
    if (_disposed) return;
    _sweepGen++;
    _verifyGen++;
    await _cache.deleteAllData();
    if (_disposed) return;
    _favoriteKeys = <String>{};
    _pendingTests.clear();
    _pendingRefresh = false;
    _pendingReconnect = false;
    state = const ProxyListState();
  }

  Future<DeepLinkResult> connectToProxy(ProxyModel proxy) =>
      _deepLink.connectWithProxy(proxy);

  Future<void> flushCache() => _cache.flushPendingWrites();
}

final proxyListProvider =
    StateNotifierProvider<ProxyListNotifier, ProxyListState>((ref) {
  return ProxyListNotifier();
});
