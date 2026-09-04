import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/app_constants.dart';
import '../core/app_meta.dart';
import '../data/proxy_sources.dart';
import '../models/proxy_model.dart';
import 'host_filter.dart';
import 'proxy_parser.dart';
import 'proxy_source_provider.dart';

class ProxyFetcherService {
  ProxyFetcherService({
    Dio? dio,
    ProxySourceProvider? sourceProvider,
  })  : _dio = dio ?? _buildDio(),
        _sourceProvider = sourceProvider ?? ProxySourceProvider();

  final Dio _dio;
  final ProxySourceProvider _sourceProvider;

  static Dio _buildDio() => Dio(BaseOptions(
        connectTimeout: AppConstants.sourceConnectTimeout,
        receiveTimeout: AppConstants.sourceReceiveTimeout,
        responseType: ResponseType.stream,
        followRedirects: false,
        validateStatus: (code) => code != null && code < 400,
        headers: {
          'User-Agent': AppMeta.userAgent,
          'Accept': 'text/plain, text/html, */*',
        },
      ));

  static const _maxRedirectHops = 3;

  Future<String?> _fetchBody(
    String url, {
    bool enforceHttpsHosts = false,
    CancelToken? token,
  }) async {
    var current = url;
    for (var hop = 0; hop <= _maxRedirectHops; hop++) {
      final uri = Uri.tryParse(current);
      if (uri == null || uri.scheme != 'https') return null;
      if (enforceHttpsHosts &&
          !ProxyParser.isValidCustomSourceUrl(current)) {
        return null;
      }
      if (await HostFilter.resolveAllowed(uri.host) == null) return null;
      final response = await _dio.get<ResponseBody>(
        current,
        cancelToken: token,
        options: Options(responseType: ResponseType.stream),
      );
      final status = response.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        final location = response.headers.value('location');
        if (location == null) return null;
        current = uri.resolve(location).toString();
        continue;
      }
      if (status != 200) return null;

      final declaredLength =
          int.tryParse(response.headers.value('content-length') ?? '');
      if (declaredLength != null &&
          declaredLength > AppConstants.maxSourceBodyBytes) {
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      var totalBytes = 0;
      final bodyStream = response.data;
      if (bodyStream == null) return null;
      await bodyStream.stream.forEach((chunk) {
        totalBytes += chunk.length;
        if (totalBytes > AppConstants.maxSourceBodyBytes) {
          throw _TooLargeException();
        }
        bytes.add(chunk);
      });
      return utf8.decode(bytes.toBytes(), allowMalformed: true);
    }
    return null;
  }

  ProxySourceProvider get sourceProvider => _sourceProvider;

  Future<List<ProxyModel>> fetchFromSource(
    ProxySource source, {
    int attempt = 0,
    CancelToken? token,
  }) async {
    final effectiveToken = token ?? CancelToken();
    try {
      final body =
          await _fetchBody(source.url, token: effectiveToken);
      if (body == null) {
        _sourceProvider.recordFailure(source.name);
        return [];
      }
      final parsed = await Isolate.run(
        () => ProxyParser.parse(
          body,
          sourceName: source.name,
          format: source.format,
        ),
      );
      if (parsed.isNotEmpty) {
        _sourceProvider.recordSuccess(source.name);
      } else {
        _sourceProvider.recordFailure(source.name);
      }
      return parsed;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return [];
      _sourceProvider.recordFailure(source.name);
      if (attempt < 2 && _isRetryable(e)) {
        final baseMs = _sourceProvider.getRetryDelayMs(attempt);
        final retryAfterMs = _retryAfterMs(e.response);
        final delayMs = (retryAfterMs ?? baseMs) + Random().nextInt(750);
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        return fetchFromSource(source,
            attempt: attempt + 1, token: effectiveToken);
      }
      return [];
    } on _TooLargeException {
      _sourceProvider.recordFailure(source.name);
      return [];
    } catch (_) {
      _sourceProvider.recordFailure(source.name);
      return [];
    }
  }

  bool _isRetryable(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return true;
    }
    // Retry rate-limit / transient server errors only. Never retry
    // 400/401/403/404/501 (client errors / unimplemented).
    if (e.type == DioExceptionType.badResponse) {
      final code = e.response?.statusCode;
      return code == 429 ||
          code == 500 ||
          code == 502 ||
          code == 503 ||
          code == 504;
    }
    return false;
  }

  /// Parses `Retry-After` (seconds) clamped to 0-15s. Returns null when
  /// absent/unparseable so caller falls back to exponential base delay.
  int? _retryAfterMs(Response? response) {
    final raw = response?.headers.value('retry-after')?.trim();
    if (raw == null || raw.isEmpty) return null;
    final secs = int.tryParse(raw);
    if (secs == null) return null;
    return secs.clamp(0, 15) * 1000;
  }

  Future<List<ProxyModel>> fetchFromAllSources() async {
    final sources = [
      ..._sourceProvider.getActiveSources(),
      ..._sourceProvider.getFallbackSources(),
    ];
    return _fetchFromSources(sources);
  }

  Future<List<ProxyModel>> _fetchFromSources(
      List<ProxySource> sources) async {
    if (sources.isEmpty) return const [];
    try {
      final results = await Future.wait(
        sources.map((s) {
          final token = CancelToken();
          return fetchFromSource(s, token: token).timeout(
            AppConstants.sourceEnvelopeTimeout,
            onTimeout: () {
              token.cancel();
              return <ProxyModel>[];
            },
          );
        }),
      );
      return _deduplicate(results.expand((l) => l));
    } catch (_) {
      return const [];
    }
  }

  Future<List<ProxyModel>> fetchOnlyCustomUrl(String url) async {
    if (!ProxyParser.isValidCustomSourceUrl(url)) return [];
    final token = CancelToken();
    try {
      final body = await _fetchBody(url,
              enforceHttpsHosts: true, token: token)
          .timeout(
        AppConstants.sourceEnvelopeTimeout,
        onTimeout: () {
          token.cancel();
          return null;
        },
      );
      if (body == null) return [];
      return await Isolate.run(() => ProxyParser.parse(body, sourceName: url));
    } on _TooLargeException {
      return [];
    } catch (_) {
      return [];
    }
  }

  List<ProxyModel> _deduplicate(Iterable<ProxyModel> proxies) {
    final seen = <String>{};
    final out = <ProxyModel>[];
    for (final p in proxies) {
      if (seen.add(p.key)) out.add(p);
    }
    return out;
  }
}

class _TooLargeException implements Exception {}
