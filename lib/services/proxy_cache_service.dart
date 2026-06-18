import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/proxy_model.dart';

class ProxyCacheService {
  static const _fetchedKey = 'cached_proxies_fetched';
  static const _testedKey = 'cached_proxies_tested';
  static const _fetchedTimestampKey = 'cached_fetched_at';
  static const _testedTimestampKey = 'cached_tested_at';

  static const _fetchCacheDuration = Duration(hours: 1);
  static const _testCacheDuration = Duration(hours: 24);

  Future<void> saveFetchedProxies(List<ProxyModel> proxies) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(proxies.map((p) => p.toJson()).toList());
    await prefs.setString(_fetchedKey, json);
    await prefs.setString(
        _fetchedTimestampKey, DateTime.now().toIso8601String());
  }

  Future<void> saveTestedProxies(List<ProxyModel> proxies) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(proxies.map((p) => p.toJson()).toList());
    await prefs.setString(_testedKey, json);
    await prefs.setString(
        _testedTimestampKey, DateTime.now().toIso8601String());
  }

  Future<List<ProxyModel>?> loadFetchedProxies() async {
    return _loadWithExpiry(_fetchedKey, _fetchedTimestampKey, _fetchCacheDuration);
  }

  Future<List<ProxyModel>?> loadTestedProxies() async {
    return _loadWithExpiry(_testedKey, _testedTimestampKey, _testCacheDuration);
  }

  Future<List<ProxyModel>?> loadStaleTestedProxies() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_testedKey);
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json) as List;
      return decoded
          .map((e) => ProxyModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<ProxyModel>?> _loadWithExpiry(
      String dataKey, String tsKey, Duration maxAge) async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getString(tsKey);
    if (ts == null) return null;

    final cachedAt = DateTime.tryParse(ts);
    if (cachedAt == null) return null;
    if (DateTime.now().difference(cachedAt) > maxAge) return null;

    final json = prefs.getString(dataKey);
    if (json == null || json.isEmpty) return null;

    try {
      final decoded = jsonDecode(json) as List;
      return decoded
          .map((e) => ProxyModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_fetchedKey);
    await prefs.remove(_testedKey);
    await prefs.remove(_fetchedTimestampKey);
    await prefs.remove(_testedTimestampKey);
  }
}
