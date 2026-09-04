import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_meta.dart';

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
  static const _repoOwner = 'krsnaSuraj';
  static const _repoName = 'TelePulse';
  static const _cacheKey = 'tp_v2_update_payload';
  static const _cacheTimestampKey = 'tp_v2_update_checked_at';
  static const _noUpdateVersionKey = 'tp_v2_update_uptodate_version';
  static const _skipVersionKey = 'tp_v2_update_skip_version';
  static const Duration _cacheDuration = Duration(hours: 1);

  final Dio _dio;
  final Future<String?> Function() _versionLoader;

  UpdateService({
    Dio? dio,
    Future<String?> Function()? versionLoader,
  })  : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            )),
        _versionLoader = versionLoader ?? (() async => AppMeta.version);

  Future<String?> get currentVersion => _versionLoader();

  Future<UpdateInfo?> checkForUpdate({bool force = false}) async {
    final version = await currentVersion;
    if (version == null || version.isEmpty) return null;

    if (!force) {
      final cached = await loadCachedUpdate();
      if (cached != null) {
        return compareVersions(cached.latestVersion, version) > 0
            ? cached
            : null;
      }
      if (await isUpToDateCached(version)) return null;
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest',
      );
      if ((response.statusCode ?? 0) != 200 || response.data == null) {
        return null;
      }
      final release = response.data!;
      final info = parseRelease(release, currentVersion: version);
      if (info == null) {
        await cacheUpToDate(version);
        return null;
      }
      await cacheUpdate(info);
      return info;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static UpdateInfo? parseRelease(
    Map<String, dynamic> release, {
    required String currentVersion,
  }) {
    final tagName = release['tag_name'];
    if (tagName is! String) return null;
    final latestVer = normalizeVersion(tagName);
    if (latestVer.isEmpty) return null;
    if (compareVersions(latestVer, currentVersion) <= 0) return null;

    var downloadUrl = trustedApkAssetUrl(release['assets']);
    downloadUrl ??= trustedPageUrl(release['html_url']) ??
        'https://github.com/$_repoOwner/$_repoName/releases/latest';

    return UpdateInfo(
      latestVersion: latestVer,
      downloadUrl: downloadUrl,
      releaseNotes:
          release['body'] is String ? release['body'] as String : null,
      releaseDate: release['published_at'] is String
          ? release['published_at'] as String
          : '',
    );
  }

  @visibleForTesting
  static String normalizeVersion(String tag) {
    var v = tag.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    final dash = v.indexOf('-');
    if (dash > 0) v = v.substring(0, dash);
    final plus = v.indexOf('+');
    if (plus > 0) v = v.substring(0, plus);
    return v;
  }

  @visibleForTesting
  static int compareVersions(String a, String b) {
    final aParts = _versionParts(a);
    final bParts = _versionParts(b);
    final len = aParts.length > bParts.length ? aParts.length : bParts.length;
    for (var i = 0; i < len; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av > bv) return 1;
      if (av < bv) return -1;
    }
    return 0;
  }

  static List<int> _versionParts(String v) {
    return v.split('.').map((e) {
      return int.tryParse(e.trim()) ?? 0;
    }).toList();
  }

  @visibleForTesting
  static bool isTrustedAssetHost(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'github.com' ||
        host == 'objects.githubusercontent.com' ||
        host.endsWith('.githubusercontent.com');
  }

  @visibleForTesting
  static bool isTrustedDownloadUrl(String url) {
    if (!isTrustedAssetHost(url)) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return _isOwnRepoPath(uri.path);
  }

  static bool _isOwnRepoPath(String path) {
    final segments =
        path.split('/').where((s) => s.isNotEmpty).toList(growable: false);
    return segments.length >= 2 &&
        segments[0] == _repoOwner &&
        segments[1] == _repoName;
  }

  /// Hardened single-URL check for release artifacts (APK assets + cache).
  ///
  /// Keeps [isTrustedAssetHost] allow-list, plus rejects userinfo
  /// (`user:pass@host`) smuggling and enforces own-repo
  /// (`krsnaSuraj/TelePulse`) for `*.githubusercontent.com` paths that
  /// embed `owner/repo` (e.g. `raw.githubusercontent.com/owner/repo/...`).
  /// `objects.githubusercontent.com` CDN URLs are opaque (hash, no
  /// owner/repo segments) and are allowed here — trust derives from the
  /// signed releases API response + HTTPS host check.
  @visibleForTesting
  static bool isTrustedArtifactUrl(String url) {
    if (!isTrustedAssetHost(url)) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.userInfo.isNotEmpty) return false;
    final host = uri.host.toLowerCase();
    if (host.endsWith('.githubusercontent.com') &&
        host != 'objects.githubusercontent.com') {
      return _isOwnRepoPath(uri.path);
    }
    return true;
  }

  static String? trustedApkAssetUrl(dynamic assets) {
    if (assets is! List) return null;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is String &&
          url is String &&
          name.toLowerCase().endsWith('.apk') &&
          !name.toLowerCase().contains('debug') &&
          isTrustedArtifactUrl(url)) {
        return url;
      }
    }
    return null;
  }

  static String? trustedPageUrl(dynamic url) {
    if (url is! String) return null;
    return isTrustedDownloadUrl(url) ? url : null;
  }

  Future<String?> get skippedVersion async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_skipVersionKey);
  }

  Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skipVersionKey, version);
  }

  Future<UpdateInfo?> loadCachedUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getString(_cacheTimestampKey);
      if (ts == null) return null;
      final cachedAt = DateTime.tryParse(ts);
      if (cachedAt == null) return null;
      if (DateTime.now().difference(cachedAt) > _cacheDuration) return null;
      final json = prefs.getString(_cacheKey);
      if (json == null || json.isEmpty) return null;
      final data = jsonDecode(json);
      if (data is! Map<String, dynamic>) return null;
      final latest = data['latestVersion'];
      final url = data['downloadUrl'];
      if (latest is! String || url is! String) return null;
      if (!isTrustedArtifactUrl(url)) return null;
      return UpdateInfo(
        latestVersion: latest,
        downloadUrl: url,
        releaseNotes: data['releaseNotes'] is String
            ? data['releaseNotes'] as String
            : null,
        releaseDate:
            data['releaseDate'] is String ? data['releaseDate'] as String : '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> isUpToDateCached(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getString(_cacheTimestampKey);
      if (ts == null) return false;
      final cachedAt = DateTime.tryParse(ts);
      if (cachedAt == null) return false;
      if (DateTime.now().difference(cachedAt) > _cacheDuration) return false;
      return prefs.getString(_noUpdateVersionKey) == version;
    } catch (_) {
      return false;
    }
  }

  Future<void> cacheUpdate(UpdateInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'latestVersion': info.latestVersion,
          'downloadUrl': info.downloadUrl,
          'releaseNotes': info.releaseNotes,
          'releaseDate': info.releaseDate,
        }),
      );
      await prefs.setString(_cacheTimestampKey, DateTime.now().toIso8601String());
      await prefs.remove(_noUpdateVersionKey);
    } catch (_) {}
  }

  Future<void> cacheUpToDate(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_noUpdateVersionKey, version);
      await prefs.setString(_cacheTimestampKey, DateTime.now().toIso8601String());
      await prefs.remove(_cacheKey);
    } catch (_) {}
  }
}
