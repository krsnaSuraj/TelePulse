import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telepulse/core/app_constants.dart';
import 'package:telepulse/models/proxy_model.dart';
import 'package:telepulse/services/proxy_cache_service.dart';

import '../helpers/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProxyModel entry(String id,
          {bool alive = false, bool favorite = false, int latency = -1}) =>
      p('srv-$id', 1000 + id.length, '0123456789abcdef0123456789abcdef',
          isAlive: alive, isFavorite: favorite, latencyMs: latency);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('tested cache round-trip', () {
    test('saves and loads within TTL via flushPendingWrites', () async {
      final cache = ProxyCacheService(writeDebounce: const Duration(hours: 1));
      final list = [entry('a'), entry('b')];
      cache.saveTestedProxies(list);
      await cache.flushPendingWrites();

      final loaded = await ProxyCacheService(
              writeDebounce: Duration.zero)
          .loadTestedProxies();
      expect(loaded, hasLength(2));
      expect(loaded![0].server, 'srv-a');
    });

    test('expired tested cache returns null from TTL loader', () async {
      await primePrefs({
        testedKey: encodeList([entry('x')]),
        testedAtKey:
            DateTime.now().subtract(AppConstants.testedCacheTtl * 2).toIso8601String(),
      });
      final cache = ProxyCacheService();
      expect(await cache.loadTestedProxies(), isNull);
      expect(await cache.loadStaleTestedProxies(), hasLength(1));
    });

    test('corrupt JSON yields null instead of crashing', () async {
      await primePrefs({
        testedKey: '{not-json-at-all',
        testedAtKey: DateTime.now().toIso8601String(),
      });
      final cache = ProxyCacheService();
      expect(await cache.loadTestedProxies(), isNull);
      expect(await cache.loadStaleTestedProxies(), isNull);
    });

    test('non-list JSON payload yields empty result safely', () async {
      await primePrefs({
        testedKey: '"just-a-string"',
        testedAtKey: DateTime.now().toIso8601String(),
      });
      final loaded =
          await ProxyCacheService().loadStaleTestedProxies();
      expect(loaded, isEmpty);
    });
  });

  group('fetched cache TTL', () {
    test('fresh fetched cache loads; expired does not', () async {
      final freshAt = DateTime.now().toIso8601String();
      await primePrefs({
        ProxyCacheService.fetchedKey: encodeList([entry('f')]),
        ProxyCacheService.fetchedAtKey: freshAt,
      });
      final cache = ProxyCacheService();
      expect(await cache.loadFetchedProxies(), hasLength(1));

      await primePrefs({
        ProxyCacheService.fetchedKey: encodeList([entry('f')]),
        ProxyCacheService.fetchedAtKey: DateTime.now()
            .subtract(AppConstants.fetchedCacheTtl * 3)
            .toIso8601String(),
      });
      expect(await cache.loadFetchedProxies(), isNull);
    });
  });

  group('cache cap', () {
    test('keeps favorites when capping oversized lists', () {
      final big = <ProxyModel>[
        for (var i = 0; i < AppConstants.maxCachedTestedEntries + 100; i++)
          entry('n$i'),
      ];
      final favorite = entry('fav', favorite: true);
      big.add(favorite);

      final capped = ProxyCacheService.capForCache(big);
      expect(capped.length, AppConstants.maxCachedTestedEntries);
      expect(capped.any((e) => e.key == favorite.key), isTrue);
    });

    test('never exceeds the cap even when favorites overflow it', () {
      final allFavorites = <ProxyModel>[
        for (var i = 0; i < AppConstants.maxCachedTestedEntries + 50; i++)
          entry('f$i', favorite: true),
      ];
      final capped = ProxyCacheService.capForCache(allFavorites);
      expect(capped.length, AppConstants.maxCachedTestedEntries);
    });
  });

  group('favorites + custom sources storage', () {
    test('favorites round-trip', () async {
      final cache = ProxyCacheService(writeDebounce: Duration.zero);
      final favorites = [entry('k9', favorite: true)];
      cache.saveFavorites(favorites);
      await cache.flushPendingWrites();

      final other = ProxyCacheService();
      final loaded = await other.loadFavorites();
      expect(loaded, hasLength(1));
      expect(loaded.first.server, 'srv-k9');
    });

    test('custom sources persist and clear works', () async {
      final cache = ProxyCacheService();
      expect(
        await cache.saveCustomSources(['https://a.example/l.txt']),
        isTrue,
      );
      expect(await cache.loadCustomSources(), ['https://a.example/l.txt']);

      await cache.clear();
      expect(await cache.loadStaleTestedProxies(), isNull);
      expect(
        await cache.loadCustomSources(),
        ['https://a.example/l.txt'],
        reason: 'clear() removes proxy caches only; sources are user config',
      );
    });
  });
}
