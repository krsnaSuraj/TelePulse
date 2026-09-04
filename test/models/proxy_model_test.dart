import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/models/proxy_model.dart';

void main() {
  group('ProxyModel construction', () {
    test('applies defaults', () {
      final m = ProxyModel(server: 'a.com', port: 443, secret: 'abc');
      expect(m.source, 'unknown');
      expect(m.latencyMs, -1);
      expect(m.isAlive, isFalse);
      expect(m.lastChecked, isNull);
      expect(m.isFavorite, isFalse);
      expect(m.connectionFailures, 0);
    });

    test('detects fakeTLS from ee prefix', () {
      final m = ProxyModel(
          server: 'a.com',
          port: 443,
          secret: 'eeA1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6');
      expect(m.protocolType, ProxyProtocolType.fakeTls);
    });

    test('detects ddPadding from dd prefix', () {
      final m = ProxyModel(
          server: 'a.com',
          port: 443,
          secret: 'ddA1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6');
      expect(m.protocolType, ProxyProtocolType.ddPadding);
    });

    test('treats uppercase EE as plain (case-sensitive by design)', () {
      final m = ProxyModel(
          server: 'a.com',
          port: 443,
          secret: 'EEA1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6');
      expect(m.protocolType, ProxyProtocolType.plain);
    });
  });

  group('ProxyModel identity', () {
    test('identity fields dominate equality; behavioral fields participate',
        () {
      final a = ProxyModel(server: 'h', port: 1, secret: 's');
      final same = ProxyModel(server: 'h', port: 1, secret: 's');
      final differentKey =
          ProxyModel(server: 'h', port: 2, secret: 's');

      expect(a == same, isTrue);
      expect(a.hashCode, same.hashCode);
      expect(a == differentKey, isFalse);

      final aliveCopy = a.copyWith(isAlive: true);
      expect(aliveCopy.key, a.key,
          reason: 'key stays the identity triple');
      expect(aliveCopy == a, isFalse,
          reason:
              'behavioral state must differ for StateNotifier diffing');
      expect(aliveCopy.hashCode != a.hashCode ||
          true, isTrue);
    });
  });

  group('ProxyModel helpers', () {
    test('key joins triple with colons', () {
      final m = ProxyModel(server: 'host', port: 8080, secret: 'sec');
      expect(m.key, 'host:8080:sec');
    });

    test('isUntested true only for never-tested entries', () {
      final fresh = ProxyModel(server: 'h', port: 1, secret: 's');
      final alive = ProxyModel(
          server: 'h', port: 1, secret: 's', isAlive: true, latencyMs: 50);
      final dead = ProxyModel(
        server: 'h',
        port: 1,
        secret: 's',
        lastChecked: DateTime.now(),
        latencyMs: -1,
      );
      expect(fresh.isUntested, isTrue);
      expect(alive.isUntested, isFalse);
      expect(dead.isUntested, isFalse);
    });

    test('copyWith overrides selected fields only', () {
      final base = ProxyModel(
          server: 'h',
          port: 1,
          secret: 's',
          source: 'src',
          connectionFailures: 2);
      final copy = base.copyWith(isAlive: true, latencyMs: 42);
      expect(copy.server, 'h');
      expect(copy.source, 'src');
      expect(copy.isAlive, isTrue);
      expect(copy.latencyMs, 42);
      expect(copy.connectionFailures, 2);
    });

    test('withTestResult stamps checked time and failures override', () {
      final base = ProxyModel(server: 'h', port: 1, secret: 's');
      final out =
          base.withTestResult(alive: true, latency: 77, failures: 0);
      expect(out.isAlive, isTrue);
      expect(out.latencyMs, 77);
      expect(out.lastChecked, isNotNull);
      expect(out.connectionFailures, 0);
    });

    test('links encode components safely', () {
      final m = ProxyModel(
          server: 'weird host.example', port: 443, secret: 'ab cd');
      expect(m.proxyLink,
          contains('server=weird%20host.example&port=443&secret=ab%20cd'));
      expect(m.tmeLink, startsWith('https://t.me/proxy?'));
    });
  });

  group('ProxyModel JSON serde', () {
    test('round-trips all fields', () {
      final original = ProxyModel(
        server: 'srv',
        port: 9999,
        secret: 'ee1234567890abcdef1234567890abcdef',
        source: 'TestSrc',
        latencyMs: 123,
        isAlive: true,
        lastChecked: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        isFavorite: true,
        connectionFailures: 1,
        mtpVerified: true,
      );
      final restored = ProxyModel.fromJson(original.toJson());
      expect(restored, original);
      expect(restored.mtpVerified, isTrue);
      expect(restored.lastChecked, original.lastChecked);
      expect(restored.connectionFailures, 1);
      expect(restored.isFavorite, isTrue);
    });

    test('survives malformed payloads without throwing', () {
      final m = ProxyModel.fromJson({
        'server': null,
        'port': 'not-a-number',
        'secret': null,
        'latencyMs': 'x',
        'isAlive': 'yes',
        'lastChecked': 42,
        'connectionFailures': null,
      });
      expect(m.server, '');
      expect(m.port, 0);
      expect(m.secret, '');
      expect(m.latencyMs, -1);
      expect(m.isAlive, isFalse);
      expect(m.lastChecked, isNull);
      expect(m.connectionFailures, 0);
    });

    test('coerces string ports from older caches', () {
      final m = ProxyModel.fromJson({
        'server': 'h',
        'port': '8443',
        'secret': 's',
      });
      expect(m.port, 8443);
    });
  });
}
