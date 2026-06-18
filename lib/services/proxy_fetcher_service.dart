import 'package:dio/dio.dart';
import '../models/proxy_model.dart';
import '../data/proxy_sources.dart';
import 'proxy_source_provider.dart';

class ProxyFetcherService {
  final Dio _dio;
  final ProxySourceProvider _sourceProvider;

  ProxyFetcherService({ProxySourceProvider? sourceProvider})
      : _sourceProvider = sourceProvider ?? ProxySourceProvider(),
        _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'User-Agent': 'TelePulse/1.0',
            'Accept': 'text/plain, text/html, */*',
          },
        ));

  Future<List<ProxyModel>> fetchFromSource(
    ProxySource source, {
    int attempt = 0,
  }) async {
    try {
      final response = await _dio.get(source.url).timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200 || response.data == null) {
        _sourceProvider.recordFailure(source.name);
        return [];
      }
      final rawText = response.data is String
          ? response.data as String
          : response.data.toString();
      final parsed = _parseProxies(rawText, source);
      if (parsed.isNotEmpty) {
        _sourceProvider.recordSuccess(source.name);
      } else {
        _sourceProvider.recordFailure(source.name);
      }
      return parsed;
    } on DioException catch (e) {
      _sourceProvider.recordFailure(source.name);
      if (attempt < 2 && _isRetryable(e)) {
        await Future.delayed(
          Duration(milliseconds: _sourceProvider.getRetryDelayMs(attempt)),
        );
        return fetchFromSource(source, attempt: attempt + 1);
      }
      return [];
    } catch (_) {
      _sourceProvider.recordFailure(source.name);
      return [];
    }
  }

  bool _isRetryable(DioException e) {
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError;
  }

  Future<List<ProxyModel>> fetchFromAllSources() async {
    final sources = _sourceProvider.getAllSources();
    final results = await Future.wait(
      sources.map(
        (s) => fetchFromSource(s).timeout(
          const Duration(seconds: 18),
          onTimeout: () {
            _sourceProvider.recordFailure(s.name);
            return <ProxyModel>[];
          },
        ),
      ),
    );
    final all = results.expand((list) => list).toList();
    return _deduplicate(all);
  }

  Future<List<ProxyModel>> fetchFromCustomUrl(String url) async {
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        !(parsed.scheme == 'http' || parsed.scheme == 'https')) {
      return [];
    }

    try {
      final response = await _dio.get(url).timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200 || response.data == null) {
        return [];
      }
      final rawText = response.data is String
          ? response.data as String
          : response.data.toString();
      return _parseProxies(
        rawText,
        ProxySource(name: url, url: url, format: 'auto'),
      );
    } catch (_) {
      return [];
    }
  }

  List<ProxyModel> _parseProxies(String text, ProxySource source) {
    final proxies = <ProxyModel>[];
    final lines = text.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      ProxyModel? proxy;

      proxy ??= _parseTgProxyLink(trimmed, source);
      proxy ??= _parseTmeLink(trimmed, source);

      if (proxy == null && source.format != 'html') {
        proxy = _parsePlainFormat(trimmed, source);
      }

      if (proxy != null && !_exists(proxies, proxy)) {
        proxies.add(proxy);
      }
    }

    if (proxies.isEmpty &&
        (source.format == 'html' || source.format == 'auto')) {
      return _parseHtmlPage(text, source);
    }

    return proxies;
  }

  List<ProxyModel> _parseHtmlPage(String html, ProxySource source) {
    final proxies = <ProxyModel>[];
    final htmlRegex = RegExp(
      r'server=([^&\s"]+)&(?:amp;)?port=(\d+)&(?:amp;)?secret=([^&\s"]+)',
      caseSensitive: false,
    );
    for (final match in htmlRegex.allMatches(html)) {
      final port = int.tryParse(match.group(2) ?? '');
      if (port == null) continue;
      final proxy = ProxyModel(
        server: match.group(1)!,
        port: port,
        secret: match.group(3)!,
        source: source.name,
      );
      if (!_exists(proxies, proxy)) {
        proxies.add(proxy);
      }
    }
    return proxies;
  }

  ProxyModel? _parseTgProxyLink(String line, ProxySource source) {
    final tgRegex = RegExp(
      r'tg:\/\/proxy\?server=([^&]+)&port=(\d+)&secret=([^&\s]+)',
      caseSensitive: false,
    );
    final match = tgRegex.firstMatch(line);
    if (match == null) return null;

    final port = int.tryParse(match.group(2) ?? '');
    if (port == null || port < 1 || port > 65535) return null;

    final server = Uri.decodeComponent(match.group(1)!);
    final secret = Uri.decodeComponent(match.group(3)!);

    if (server.isEmpty || secret.isEmpty) return null;

    return ProxyModel(
      server: server,
      port: port,
      secret: secret,
      source: source.name,
    );
  }

  ProxyModel? _parseTmeLink(String line, ProxySource source) {
    final tmeRegex = RegExp(
      r'https?:\/\/t\.me\/proxy\?server=([^&]+)&port=(\d+)&secret=([^&\s]+)',
      caseSensitive: false,
    );
    final match = tmeRegex.firstMatch(line);
    if (match == null) return null;

    final port = int.tryParse(match.group(2) ?? '');
    if (port == null || port < 1 || port > 65535) return null;

    final server = Uri.decodeComponent(match.group(1)!);
    final secret = Uri.decodeComponent(match.group(3)!);

    if (server.isEmpty || secret.isEmpty) return null;

    return ProxyModel(
      server: server,
      port: port,
      secret: secret,
      source: source.name,
    );
  }

  ProxyModel? _parsePlainFormat(String line, ProxySource source) {
    final parts = line.split(RegExp(r'[\s,:;]+'));
    if (parts.length < 3) return null;

    final server = parts[0].trim();
    final port = int.tryParse(parts[1].trim());
    final secret = parts[2].trim();

    if (server.isEmpty || port == null || secret.isEmpty) return null;
    if (port < 1 || port > 65535) return null;

    final isHost = RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(server) ||
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(server);
    final isSecret = RegExp(r'^[a-fA-F0-9]+$').hasMatch(secret);

    if (!isHost || !isSecret) return null;

    return ProxyModel(
      server: server,
      port: port,
      secret: secret,
      source: source.name,
    );
  }

  bool _exists(List<ProxyModel> proxies, ProxyModel proxy) {
    return proxies.any((p) =>
        p.server == proxy.server &&
        p.port == proxy.port &&
        p.secret == proxy.secret);
  }

  List<ProxyModel> _deduplicate(List<ProxyModel> proxies) {
    final seen = <String>{};
    final deduped = <ProxyModel>[];
    for (final proxy in proxies) {
      final key = '${proxy.server}:${proxy.port}:${proxy.secret}';
      if (seen.add(key)) {
        deduped.add(proxy);
      }
    }
    return deduped;
  }

  ProxySourceProvider get sourceProvider => _sourceProvider;
}
