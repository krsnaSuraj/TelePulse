import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final String? releaseNotes;
  final String releaseDate;

  const UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    this.releaseNotes,
    required this.releaseDate,
  });
}

class UpdateService {
  final Dio _dio;
  static const _repoOwner = 'krsnaSuraj';
  static const _repoName = 'TelePulse';
  static const _cacheKey = 'update_check_cache';
  static const _cacheTimestampKey = 'update_check_cache_at';
  static const _noUpdateVersionKey = 'update_no_update_version';
  static const _skipVersionKey = 'update_skip_version';
  static const _cacheDuration = Duration(hours: 1);

  UpdateService({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ));

  String? _currentVersion;

  Future<String?> get currentVersion async {
    if (_currentVersion != null) return _currentVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
      return _currentVersion;
    } catch (_) {
      return null;
    }
  }

  Future<UpdateInfo?> checkForUpdate({bool force = false}) async {
    final version = await currentVersion;
    if (version == null) return null;

    if (!force) {
      final cached = await _loadCached();
      if (cached != null) {
        if (_compareVersions(cached.latestVersion, version) > 0) {
          return cached;
        }
        return null;
      }
      if (await _isUpToDateCached(version)) return null;
    }

    try {
      final response = await _dio.get(
        'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest',
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200 || response.data == null) return null;

      final release = response.data as Map<String, dynamic>;
      final tagName = release['tag_name'] as String? ?? '';
      final latestVer = tagName.startsWith('v') ? tagName.substring(1) : tagName;

      if (latestVer.isEmpty) return null;
      if (_compareVersions(latestVer, version) <= 0) {
        await _cacheUpToDate(version);
        return null;
      }

      final assets = release['assets'] as List? ?? [];
      String? downloadUrl;
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk') && !name.contains('debug')) {
          downloadUrl = asset['browser_download_url'] as String?;
          break;
        }
      }
      downloadUrl ??= release['html_url'] as String? ??
          'https://github.com/$_repoOwner/$_repoName/releases/latest';

      final info = UpdateInfo(
        latestVersion: latestVer,
        downloadUrl: downloadUrl,
        releaseNotes: release['body'] as String?,
        releaseDate: release['published_at'] as String? ?? '',
      );

      await _cacheResult(info);
      return info;
    } on DioException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> get skippedVersion async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_skipVersionKey);
  }

  Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skipVersionKey, version);
  }

  int _compareVersions(String a, String b) {
    final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final len = aParts.length > bParts.length ? aParts.length : bParts.length;
    for (var i = 0; i < len; i++) {
      final aVal = i < aParts.length ? aParts[i] : 0;
      final bVal = i < bParts.length ? bParts[i] : 0;
      if (aVal > bVal) return 1;
      if (aVal < bVal) return -1;
    }
    return 0;
  }

  Future<UpdateInfo?> _loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getString(_cacheTimestampKey);
      if (ts == null) return null;

      final cachedAt = DateTime.tryParse(ts);
      if (cachedAt == null) return null;
      if (DateTime.now().difference(cachedAt) > _cacheDuration) return null;

      final json = prefs.getString(_cacheKey);
      if (json == null || json.isEmpty) return null;

      final data = jsonDecode(json) as Map<String, dynamic>;
      return UpdateInfo(
        latestVersion: data['latestVersion'] as String,
        downloadUrl: data['downloadUrl'] as String,
        releaseNotes: data['releaseNotes'] as String?,
        releaseDate: data['releaseDate'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isUpToDateCached(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getString(_cacheTimestampKey);
      if (ts == null) return false;

      final cachedAt = DateTime.tryParse(ts);
      if (cachedAt == null) return false;
      if (DateTime.now().difference(cachedAt) > _cacheDuration) return false;

      final cached = prefs.getString(_noUpdateVersionKey);
      return cached == version;
    } catch (_) {
      return false;
    }
  }

  Future<void> _cacheResult(UpdateInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode({
        'latestVersion': info.latestVersion,
        'downloadUrl': info.downloadUrl,
        'releaseNotes': info.releaseNotes,
        'releaseDate': info.releaseDate,
      }));
      await prefs.setString(
          _cacheTimestampKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  Future<void> _cacheUpToDate(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_noUpdateVersionKey, version);
      await prefs.setString(
          _cacheTimestampKey, DateTime.now().toIso8601String());
      await prefs.remove(_cacheKey);
    } catch (_) {}
  }
}
