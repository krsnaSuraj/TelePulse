import '../core/app_constants.dart';
import '../models/proxy_model.dart';
import 'host_filter.dart';

class ProxyParser {
  ProxyParser._();

  static final RegExp _tgRegex = RegExp(
    r'tg://proxy\?server=([^&\s]+)&port=(\d+)&secret=([^&\s]+)',
    caseSensitive: false,
  );

  static final RegExp _tmeRegex = RegExp(
    r'https?://t\.me/proxy\?server=([^&\s]+)&port=(\d+)&secret=([^&\s]+)',
    caseSensitive: false,
  );

  static final RegExp _htmlRegex = RegExp(
    r'server=([^&\s"<>]+)&(?:amp;)?port=(\d+)&(?:amp;)?secret=([^&\s"<>]+)',
    caseSensitive: false,
  );

  static final RegExp _hostCharset = RegExp(r'^[a-zA-Z0-9._-]+$');
  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
  static final RegExp _hex = RegExp(r'^[a-fA-F0-9]+$');
  static const String _bom = '\uFEFF';

  static List<ProxyModel> parse(
    String text, {
    required String sourceName,
    String format = 'auto',
  }) {
    if (text.startsWith(_bom)) text = text.substring(1);
    final proxies = <ProxyModel>[];
    final seen = <String>{};

    for (final rawLine in text.split('\n')) {
      var line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.contains('&amp;')) {
        line = line.replaceAll('&amp;', '&');
      }

      ProxyModel? proxy;
      try {
        proxy ??= _fromMatch(_tgRegex.firstMatch(line), sourceName);
        proxy ??= _fromMatch(_tmeRegex.firstMatch(line), sourceName);
        if (proxy == null && format != 'html') {
          proxy = _parsePlainLine(line, sourceName);
        }
      } on ArgumentError {
        proxy = null;
      } catch (_) {
        proxy = null;
      }

      if (proxy != null && seen.add(proxy.key)) {
        proxies.add(proxy);
      }
    }

    if (proxies.isEmpty && (format == 'html' || format == 'auto')) {
      return _parseHtml(text, sourceName, seen);
    }
    return proxies;
  }

  static List<ProxyModel> _parseHtml(
    String html,
    String sourceName,
    Set<String> seen,
  ) {
    final proxies = <ProxyModel>[];
    for (final match in _htmlRegex.allMatches(html)) {
      ProxyModel? proxy;
      try {
        proxy = _build(
          server: match.group(1)!,
          portStr: match.group(2)!,
          secret: match.group(3)!,
          sourceName: sourceName,
        );
      } catch (_) {
        proxy = null;
      }
      if (proxy != null && seen.add(proxy.key)) {
        proxies.add(proxy);
      }
    }
    return proxies;
  }

  static ProxyModel? _fromMatch(RegExpMatch? match, String sourceName) {
    if (match == null) return null;
    return _build(
      server: match.group(1)!,
      portStr: match.group(2)!,
      secret: match.group(3)!,
      sourceName: sourceName,
    );
  }

  static ProxyModel? _parsePlainLine(String line, String sourceName) {
    final parts = line.split(RegExp(r'[\s,:;|]+'));
    if (parts.length < 3) return null;
    return _build(
      server: parts[0],
      portStr: parts[1],
      secret: parts[2],
      sourceName: sourceName,
    );
  }

  static ProxyModel? _build({
    required String server,
    required String portStr,
    required String secret,
    required String sourceName,
  }) {
    var host = _safeDecode(server).trim();
    var sec = _safeDecode(secret).trim();

    if (host.isEmpty || sec.isEmpty) return null;
    if (host.length > AppConstants.maxHostLength) return null;
    if (sec.length < AppConstants.minSecretLength ||
        sec.length > AppConstants.maxSecretLength) {
      return null;
    }
    if (!_hostCharset.hasMatch(host)) return null;
    if (host.toLowerCase() == 'localhost') return null;
    final numericDotted =
        host.contains('.') && RegExp(r'^[\d.]+$').hasMatch(host);
    if (numericDotted &&
        (!_ipv4.hasMatch(host) || !_isValidIpv4Octets(host))) {
      return null;
    }
    if (!_hex.hasMatch(sec)) return null;
    if (HostFilter.isDisallowedLiteral(host)) return null;

    final port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) return null;

    return ProxyModel(server: host, port: port, secret: sec, source: sourceName);
  }

  static bool _isValidIpv4Octets(String host) {
    final octets = host.split('.');
    for (final o in octets) {
      final v = int.tryParse(o);
      if (v == null || v > 255) return false;
    }
    return true;
  }

  static String _safeDecode(String value) {
    if (!value.contains('%')) return value;
    try {
      return Uri.decodeComponent(value);
    } on ArgumentError {
      return value;
    }
  }

  static bool isValidCustomSourceUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme != 'https') return false;
    if (uri.userInfo.isNotEmpty) return false;
    var host = uri.host;
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    if (host.isEmpty || host.length > AppConstants.maxHostLength) return false;
    if (host.toLowerCase() == 'localhost') return false;
    if (HostFilter.isDisallowedLiteral(host)) return false;
    return true;
  }
}
