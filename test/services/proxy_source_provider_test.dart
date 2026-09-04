import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/services/proxy_source_provider.dart';

void main() {
  group('ProxySourceProvider health', () {
    test('all primaries active initially', () {
      final provider = ProxySourceProvider(random: Random(42));
      final names =
          provider.getActiveSources().map((s) => s.name).toSet();
      expect(
        names,
        containsAll([
          'SoliSpirit',
          'kort0881-all',
          'Grim1313',
        ]),
      );
    });

    test('success clears recorded failures', () {
      final provider = ProxySourceProvider(random: Random(1));
      provider.recordFailure('SoliSpirit');
      provider.recordFailure('SoliSpirit');
      provider.recordSuccess('SoliSpirit');
      expect(
        provider.getActiveSources().map((s) => s.name),
        contains('SoliSpirit'),
      );
    });

    test('three failures disable until the recovery window passes', () {
      final provider = ProxySourceProvider(random: Random(7));
      provider.recordFailure('Grim1313');
      provider.recordFailure('Grim1313');
      expect(
        provider.getActiveSources().map((s) => s.name),
        contains('Grim1313'),
      );
      provider.recordFailure('Grim1313');
      expect(
        provider.getActiveSources().map((s) => s.name),
        isNot(contains('Grim1313')),
      );
    });

    test('retry delays follow the documented backoff table', () {
      final provider = ProxySourceProvider();
      expect(provider.getRetryDelayMs(0), 1000);
      expect(provider.getRetryDelayMs(1), 2000);
      expect(provider.getRetryDelayMs(2), 4000);
      expect(provider.getRetryDelayMs(3), 8000);
      expect(provider.getRetryDelayMs(9), 15000);
      expect(provider.getRetryDelayMs(-4), 1000);
    });
  });
}
