import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_constants.dart';
import '../models/proxy_model.dart';

class ProxyCacheService {
  static const String fetchedKey = 'tp_v2_fetched_proxies';
  static const String fetchedAtKey = 'tp_v2_fetched_at';
  static const String testedKey = 'tp_v2_tested_proxies';
  static const String testedAtKey = 'tp_v2_tested_at';
  static const String favoritesKey = 'tp_v2_favorites';
  static const String customSourcesKey = 'tp_v2_custom_sources';
  static const String wifiOnlyKey = 'tp_v2_wifi_only';
  static const String autoScanKey = 'tp_v2_autoscan';
  static const staleGrace = Duration(days: 7);

  final Duration writeDebounce;

  Timer? _testedTimer;
  Timer? _fetchedTimer;
  List<ProxyModel>? _pendingTested;
  List<ProxyModel>? _pendingFetched;
  Future<void> _lastWrite = Future.value();
  int _generation = 0;

  ProxyCacheService({
    this.writeDebounce = AppConstants.cacheWriteDebounce,
  });

  Future<List<ProxyModel>?> loadTestedProxies() =>
      _loadWithExpiry(testedKey, testedAtKey, AppConstants.testedCacheTtl);

  Future<List<ProxyModel>?> loadFetchedProxies() =>
      _loadWithExpiry(fetchedKey, fetchedAtKey, AppConstants.fetchedCacheTtl);

  Future<List<ProxyModel>?> loadStaleTestedProxies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(testedKey);
      if (json == null || json.isEmpty) return null;
      final ts = prefs.getString(testedAtKey);
      if (ts != null) {
        final parsed = DateTime.tryParse(ts);
        if (parsed != null) {
          if (DateTime.now().toUtc().difference(parsed.toUtc()) > staleGrace) {
            return null;
          }
        }
      }
      return await Isolate.run(() => decodeProxies(json));
    } catch (_) {
      return null;
    }
  }

  Future<List<ProxyModel>> loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(favoritesKey);
      if (json == null || json.isEmpty) return const [];
      return await Isolate.run(() => decodeProxies(json));
    } catch (_) {
      return const [];
    }
  }

  Future<bool> loadWifiOnlyAutoScan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(wifiOnlyKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> saveWifiOnlyAutoScan(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(wifiOnlyKey, value);
    } catch (_) {}
  }

  Future<bool> loadAutoScanOnReconnect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(autoScanKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> saveAutoScanOnReconnect(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(autoScanKey, value);
    } catch (_) {}
  }

  Future<List<String>> loadCustomSources() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(customSourcesKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> saveCustomSources(List<String> urls) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(customSourcesKey, jsonEncode(urls));
      return true;
    } catch (_) {
      return false;
    }
  }

  void saveFavorites(List<ProxyModel> favorites) {
    final gen = _generation;
    _chainWrite(_writeRaw(favoritesKey, encodeProxiesSafe(favorites), gen));
  }

  void _chainWrite(Future<void> write) {
    _lastWrite = _lastWrite.then((_) => write).catchError((_) {});
  }

  void saveTestedProxies(List<ProxyModel> proxies) {
    _pendingTested = capForCache(proxies);
    _testedTimer?.cancel();
    _testedTimer = Timer(writeDebounce, () {
      final list = _pendingTested;
      _pendingTested = null;
      if (list != null) {
        _chainWrite(_writePair(
          dataJson: encodeProxiesSafe(list),
          dataKey: testedKey,
          tsKey: testedAtKey,
        ));
      }
    });
  }

  void saveFetchedProxies(List<ProxyModel> proxies) {
    _pendingFetched = capForCache(proxies);
    _fetchedTimer?.cancel();
    _fetchedTimer = Timer(writeDebounce, () {
      final list = _pendingFetched;
      _pendingFetched = null;
      if (list != null) {
        _chainWrite(_writePair(
          dataJson: encodeProxiesSafe(list),
          dataKey: fetchedKey,
          tsKey: fetchedAtKey,
        ));
      }
    });
  }

  static List<ProxyModel> capForCache(List<ProxyModel> proxies) {
    if (proxies.length <= AppConstants.maxCachedTestedEntries) return proxies;
    final favorites = proxies.where((p) => p.isFavorite).toList();
    final room = AppConstants.maxCachedTestedEntries - favorites.length;
    final rest = proxies
        .where((p) => !p.isFavorite)
        .take(room < 0 ? 0 : room)
        .toList();
    return [...favorites.take(AppConstants.maxCachedTestedEntries), ...rest];
  }

  Future<void> clear() async {
    _testedTimer?.cancel();
    _fetchedTimer?.cancel();
    _pendingTested = null;
    _pendingFetched = null;
    _generation++;
    final gen = _generation;
    try {
      await _lastWrite;
    } catch (_) {}
    if (gen != _generation) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(fetchedKey);
      await prefs.remove(fetchedAtKey);
      await prefs.remove(testedKey);
      await prefs.remove(testedAtKey);
    } catch (_) {}
  }

  /// Wipes all locally persisted app data (every `tp_v2_*` key).
  ///
  /// Covers proxy caches + timestamps, favorites, custom sources,
  /// settings toggles, and update-service keys
  /// (`tp_v2_update_payload`, `tp_v2_update_checked_at`,
  /// `tp_v2_update_uptodate_version`, `tp_v2_update_skip_version`).
  Future<void> deleteAllData() async {
    _testedTimer?.cancel();
    _fetchedTimer?.cancel();
    _pendingTested = null;
    _pendingFetched = null;
    _generation++;
    final gen = _generation;
    try {
      await _lastWrite;
    } catch (_) {}
    if (gen != _generation) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(fetchedKey);
      await prefs.remove(fetchedAtKey);
      await prefs.remove(testedKey);
      await prefs.remove(testedAtKey);
      await prefs.remove(favoritesKey);
      await prefs.remove(customSourcesKey);
      await prefs.remove(wifiOnlyKey);
      await prefs.remove(autoScanKey);
      await prefs.remove('tp_v2_update_payload');
      await prefs.remove('tp_v2_update_checked_at');
      await prefs.remove('tp_v2_update_uptodate_version');
      await prefs.remove('tp_v2_update_skip_version');
    } catch (_) {}
  }

  Future<void> flushPendingWrites() async {
    _testedTimer?.cancel();
    _fetchedTimer?.cancel();
    final t = _pendingTested;
    final f = _pendingFetched;
    _pendingTested = null;
    _pendingFetched = null;
    if (t != null) {
      _chainWrite(_writePair(
        dataJson: encodeProxiesSafe(t),
        dataKey: testedKey,
        tsKey: testedAtKey,
      ));
    }
    if (f != null) {
      _chainWrite(_writePair(
        dataJson: encodeProxiesSafe(f),
        dataKey: fetchedKey,
        tsKey: fetchedAtKey,
      ));
    }
    await _lastWrite;
  }

  Future<void> _writeRaw(String key, String json, [int? gen]) async {
    if (json.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (gen != null && gen != _generation) return;
      await prefs.setString(key, json);
    } catch (_) {}
  }

  Future<void> _writePair({
    required String dataJson,
    required String dataKey,
    required String tsKey,
  }) async {
    if (dataJson.isEmpty) return;
    final gen = _generation;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (gen != _generation) return;
      await prefs.setString(dataKey, dataJson);
      if (gen != _generation) return;
      await prefs.setString(tsKey, DateTime.now().toUtc().toIso8601String());
    } catch (_) {}
  }

  Future<List<ProxyModel>?> _loadWithExpiry(
    String dataKey,
    String tsKey,
    Duration maxAge,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getString(tsKey);
      if (ts == null) return null;
      final parsed = DateTime.tryParse(ts);
      if (parsed == null) return null;
      final cachedAt = parsed.toUtc();
      if (DateTime.now().toUtc().difference(cachedAt) > maxAge) return null;
      final json = prefs.getString(dataKey);
      if (json == null || json.isEmpty) return null;
      return await Isolate.run(() => decodeProxies(json));
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static String encodeProxies(List<ProxyModel> proxies) =>
      jsonEncode(proxies.map((p) => p.toJson()).toList());

  @visibleForTesting
  static String encodeProxiesSafe(List<ProxyModel> proxies) {
    try {
      return encodeProxies(proxies);
    } catch (_) {
      return '';
    }
  }

  @visibleForTesting
  static List<ProxyModel> decodeProxies(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    final result = <ProxyModel>[];
    for (final entry in decoded.whereType<Map>()) {
      try {
        final m = ProxyModel.fromJson(Map<String, dynamic>.from(entry));
        if (m.isValidForCache) result.add(m);
      } catch (_) {
        continue;
      }
    }
    return result;
  }
}
