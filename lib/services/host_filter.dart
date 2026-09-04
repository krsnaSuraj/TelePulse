import 'dart:io';

class HostFilter {
  HostFilter._();

  static bool isPrivateOrReservedAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      if (bytes.length != 4) return true;
      return _isPrivateIpv4(bytes[0], bytes[1], bytes[2]);
    }
    if (address.type == InternetAddressType.IPv6) {
      if (bytes.length != 16) return true;
      if (_isMappedIpv4(bytes)) {
        return _isPrivateIpv4(bytes[12], bytes[13], bytes[14]);
      }
      return _isPrivateIpv6(bytes);
    }
    return true;
  }

  static bool _isPrivateIpv4(int o1, int o2, [int o3 = -1]) {
    if (o1 == 0 || o1 == 10 || o1 == 127) return true;
    if (o1 == 100 && o2 >= 64 && o2 <= 127) return true;
    if (o1 == 169 && o2 == 254) return true;
    if (o1 == 172 && o2 >= 16 && o2 <= 31) return true;
    if (o1 == 192 && o2 == 168) return true;
    if (o1 == 192 && o2 == 0) return true;
    if (o1 == 198 && (o2 == 18 || o2 == 19)) return true;
    if (o1 == 198 && o2 == 51 && o3 == 100) return true;
    if (o1 == 203 && o2 == 0 && o3 == 113) return true;
    if (o1 >= 224) return true;
    return false;
  }

  static bool _isMappedIpv4(List<int> b) {
    for (var i = 0; i < 10; i++) {
      if (b[i] != 0) return false;
    }
    return b[10] == 0xff && b[11] == 0xff;
  }

  static bool _isPrivateIpv6(List<int> b) {
    final allZero = b.every((x) => x == 0);
    if (allZero) return true;
    final loopbackOnly = b[15] == 1 && b.take(15).every((x) => x == 0);
    if (loopbackOnly) return true;
    if (b[0] == 0xfe) return true;
    if ((b[0] & 0xfe) == 0xfc) return true;
    if (b[0] == 0xff) return true;
    if (b[0] == 0x20 &&
        b[1] == 0x01 &&
        b[2] == 0x0d &&
        b[3] == 0xb8) {
      return true;
    }
    if (b[0] == 0x20 && b[1] == 0x02) return true;
    if (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x00 && b[3] == 0x00) {
      return true;
    }
    if (b[0] == 0x00) return true;
    if (b[0] == 0x64 &&
        b[1] == 0xff &&
        b[2] == 0x9b &&
        b.sublist(3, 6).every((x) => x == 0)) {
      return true;
    }
    if (b[0] == 0x01 && b[1] == 0x00) return true;
    return false;
  }

  static InternetAddress? tryParseLiteral(String host) {
    final cleaned = _stripBrackets(host);
    if (!cleaned.contains(':') &&
        !RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(cleaned)) {
      return null;
    }
    try {
      return InternetAddress.tryParse(cleaned);
    } catch (_) {
      return null;
    }
  }

  static bool isDisallowedLiteral(String host) {
    final parsed = tryParseLiteral(host);
    if (parsed == null) return false;
    return isPrivateOrReservedAddress(parsed);
  }

  static const lookupTimeout = Duration(seconds: 5);

  static final Map<String, ({List<InternetAddress> addrs, DateTime exp, bool blocked})>
      _dnsCache = {};

  static void clearDnsCacheForTesting() => _dnsCache.clear();

  static Future<List<InternetAddress>?> resolveAllowed(String host) async {
    final literal = tryParseLiteral(host);
    if (literal != null) {
      return isPrivateOrReservedAddress(literal) ? null : [literal];
    }
    final cached = _dnsCache[host];
    if (cached != null) {
      if (DateTime.now().isBefore(cached.exp)) {
        return cached.blocked ? null : cached.addrs;
      }
      _dnsCache.remove(host);
    }
    try {
      final addresses = await InternetAddress.lookup(host).timeout(
        lookupTimeout,
        onTimeout: () => const <InternetAddress>[],
      );
      if (addresses.isEmpty) {
        _dnsCache[host] = (
          addrs: const <InternetAddress>[],
          exp: DateTime.now().add(const Duration(seconds: 60)),
          blocked: true,
        );
        return null;
      }
      for (final a in addresses) {
        if (isPrivateOrReservedAddress(a)) {
          _dnsCache[host] = (
            addrs: const <InternetAddress>[],
            exp: DateTime.now().add(const Duration(seconds: 60)),
            blocked: true,
          );
          return null;
        }
      }
      _dnsCache[host] = (
        addrs: addresses,
        exp: DateTime.now().add(const Duration(seconds: 60)),
        blocked: false,
      );
      return addresses;
    } on SocketException {
      _dnsCache[host] = (
        addrs: const <InternetAddress>[],
        exp: DateTime.now().add(const Duration(seconds: 10)),
        blocked: true,
      );
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _stripBrackets(String host) {
    if (host.startsWith('[') && host.endsWith(']')) {
      return host.substring(1, host.length - 1);
    }
    return host;
  }
}
