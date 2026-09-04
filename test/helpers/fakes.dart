import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telepulse/models/proxy_model.dart';
import 'package:telepulse/services/connectivity_service.dart';
import 'package:telepulse/services/mtproto_probe_service.dart';
import 'package:telepulse/services/proxy_cache_service.dart';
import 'package:telepulse/services/proxy_fetcher_service.dart';
import 'package:telepulse/services/proxy_tester_service.dart';

class FakeCache extends ProxyCacheService {
  List<ProxyModel>? storedTested;
  List<ProxyModel>? storedFetched;
  List<ProxyModel>? stalePayload;
  List<ProxyModel>? favoritesPayload;
  List<String> savedCustomUrls = [];
  List<String>? customUrlStorage;
  bool wifiOnlyStorage = false;
  bool autoscanStorage = true;
  int clearCount = 0;
  int saveTestedCalls = 0;

  FakeCache() : super(writeDebounce: Duration.zero);

  @override
  Future<List<ProxyModel>?> loadTestedProxies() async => storedTested;

  @override
  Future<List<ProxyModel>?> loadFetchedProxies() async => storedFetched;

  @override
  Future<List<ProxyModel>?> loadStaleTestedProxies() async => stalePayload;

  @override
  Future<List<ProxyModel>> loadFavorites() async =>
      favoritesPayload ?? const [];

  @override
  Future<List<String>> loadCustomSources() async =>
      customUrlStorage ?? const [];

  @override
  Future<bool> saveCustomSources(List<String> urls) async {
    savedCustomUrls = urls;
    customUrlStorage = urls;
    return true;
  }

  @override
  Future<bool> loadWifiOnlyAutoScan() async => wifiOnlyStorage;

  @override
  Future<void> saveWifiOnlyAutoScan(bool value) async {
    wifiOnlyStorage = value;
  }

  @override
  Future<bool> loadAutoScanOnReconnect() async => autoscanStorage;

  @override
  Future<void> saveAutoScanOnReconnect(bool value) async {
    autoscanStorage = value;
  }

  @override
  void saveFavorites(List<ProxyModel> favorites) {
    favoritesPayload = favorites;
  }

  @override
  void saveTestedProxies(List<ProxyModel> proxies) {
    saveTestedCalls++;
    storedTested = proxies;
  }

  @override
  void saveFetchedProxies(List<ProxyModel> proxies) {
    storedFetched = proxies;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    storedTested = null;
    storedFetched = null;
  }

  void primeTestedCache(List<ProxyModel> proxies) {
    storedTested = proxies;
    stalePayload = proxies;
  }
}

class FakeConnectivity extends ConnectivityService {
  bool fakeOnline;
  ConnectivityResult fakeType;
  int checkCalls = 0;

  FakeConnectivity(
      {this.fakeOnline = true,
      this.fakeType = ConnectivityResult.wifi})
      : super(stabilityWindow: Duration.zero);

  @override
  Future<bool> checkNow() async {
    checkCalls++;
    return fakeOnline;
  }

  @override
  void startMonitoring() {}

  @override
  Future<ConnectivityResult> currentConnectionType() async => fakeType;

  @override
  void debugEmitChange(bool online) {
    fakeOnline = online;
    super.debugEmitChange(online);
  }

  void goOffline() => debugEmitChange(false);

  void goOnline() => debugEmitChange(true);
}

class FakeFetcher extends ProxyFetcherService {
  List<ProxyModel> allSourcesResult;
  final Map<String, List<ProxyModel>> customResults;
  int fetchAllCalls = 0;

  FakeFetcher({
    this.allSourcesResult = const [],
    Map<String, List<ProxyModel>>? customResults,
  }) : customResults =
            customResults ?? <String, List<ProxyModel>>{};

  @override
  Future<List<ProxyModel>> fetchFromAllSources() async {
    fetchAllCalls++;
    return allSourcesResult;
  }

  @override
  Future<List<ProxyModel>> fetchOnlyCustomUrl(String url) async {
    return customResults[url] ?? const [];
  }
}

class FakeTester extends ProxyTesterService {
  final Map<String, ({bool alive, int latency})> outcomes;
  final Set<String> throwKeys;
  final Map<String, Completer<void>> gates = {};
  final List<String> testedKeys = [];

  FakeTester({
    Map<String, ({bool alive, int latency})>? outcomes,
    Set<String>? throwKeys,
  })  : outcomes = outcomes ??
            <String, ({bool alive, int latency})>{},
        throwKeys = throwKeys ?? <String>{};

  void gate(String key) {
    gates[key] ??= Completer<void>();
  }

  void release(String key) {
    gates[key]?.complete();
  }

  @override
  Future<ProxyModel> testProxy(ProxyModel proxy) async {
    testedKeys.add(proxy.key);
    if (throwKeys.contains(proxy.key)) {
      throw StateError('injected tester failure');
    }
    final gateC = gates[proxy.key];
    if (gateC != null && !gateC.isCompleted) {
      await gateC.future;
    }
    final outcome = outcomes[proxy.key];
    if (outcome == null) {
      return proxy.withTestResult(alive: false, latency: -1);
    }
    return proxy.withTestResult(
        alive: outcome.alive, latency: outcome.latency);
  }
}

class FakeProbe extends MtprotoProbeService {
  final Map<String, ProbeOutcome> verdicts;
  final List<String> verifiedKeys = [];
  Completer<void>? gate;

  FakeProbe({Map<String, ProbeOutcome>? verdicts})
      : verdicts = verdicts ?? {};

  @override
  Future<ProbeResult> verify(ProxyModel proxy) async {
    verifiedKeys.add(proxy.key);
    if (gate != null) await gate!.future;
    final outcome = verdicts[proxy.key] ?? ProbeOutcome.dead;
    return ProbeResult(proxy.key, outcome, 10);
  }
}

ProxyModel p(
  String server,
  int port,
  String secret, {
  String source = 'SoliSpirit',
  int latencyMs = -1,
  bool isAlive = false,
  DateTime? lastChecked,
  bool isFavorite = false,
  int connectionFailures = 0,
}) {
  return ProxyModel(
    server: server,
    port: port,
    secret: secret,
    source: source,
    latencyMs: latencyMs,
    isAlive: isAlive,
    lastChecked: lastChecked,
    isFavorite: isFavorite,
    connectionFailures: connectionFailures,
  );
}

Future<void> pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration step = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within timeout');
    }
    await Future<void>.delayed(step);
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> primePrefs(Map<String, Object> extra) async {
  SharedPreferences.setMockInitialValues(<String, Object>{...extra});
}

String encodeList(List<ProxyModel> list) =>
    ProxyCacheService.encodeProxies(list);

const testedKey = ProxyCacheService.testedKey;
const testedAtKey = ProxyCacheService.testedAtKey;
