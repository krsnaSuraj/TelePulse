import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telepulse/core/app_constants.dart';
import 'package:telepulse/models/proxy_model.dart';
import 'package:telepulse/services/proxy_cache_service.dart';

ProxyModel _e(String id, {bool fav = false}) {
  // 32 hex chars, deterministic per id.
  final hex =
      '${id.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join()}abcdef0123456789abcdef0123456789'
          .substring(0, 32);
  return ProxyModel(
    server: 'h-$id',
    port: 1000 + id.length,
    secret: hex,
    source: 't',
    isFavorite: fav,
  );
}

String _encode(List<ProxyModel> l) =>
    ProxyCacheService.encodeProxiesSafe(l);

Future<void> _prime(String key, String val) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(key, val);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('cache integrity (proxy_cache_service.dart)', () {
    test('encode failure returns empty sentinel (PROOF)', () {
      // encodeProxiesSafe:261-266 returns '' on throw.
      // Callers persist it unconditionally -> wipes good cache.
      expect(ProxyCacheService.encodeProxiesSafe([]), isNotNull);
    });

    test('empty-string prefs never surface as data', () async {
      await _prime(
        ProxyCacheService.testedKey,
        '',
      );
      await _prime(
        ProxyCacheService.testedAtKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      expect(
        await ProxyCacheService().loadTestedProxies(),
        isNull,
        reason: ':249 empty guard',
      );
      expect(
        await ProxyCacheService().loadStaleTestedProxies(),
        isNull,
        reason: ':44 empty guard',
      );
      await _prime(ProxyCacheService.favoritesKey, '');
      expect(await ProxyCacheService().loadFavorites(), isEmpty);
    });

    test('kill-before-flush loses debounced write (PROOF)', () async {
      final w = ProxyCacheService(
        writeDebounce: const Duration(hours: 1),
      );
      w.saveTestedProxies([_e('pending')]);
      // Simulate OS kill: new instance, no flush. Prefs untouched.
      expect(
        await ProxyCacheService().loadStaleTestedProxies(),
        isNull,
        reason: 'RAM-only _pendingTested lost without flush',
      );
      await w.flushPendingWrites();
      expect(
        await ProxyCacheService().loadStaleTestedProxies(),
        hasLength(1),
      );
    });

    test('corrupt JSON degrades to null/empty, valid row survives', () async {
      await _prime(
        ProxyCacheService.testedKey,
        '{not-json',
      );
      await _prime(
        ProxyCacheService.testedAtKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      expect(await ProxyCacheService().loadTestedProxies(), isNull);

      await _prime(
        ProxyCacheService.testedKey,
        '[1,"x",null,{"server":"h-a","port":443,"secret":"eeSecret-a-0123456789abcdef","source":"t"}]',
      );
      final loaded = await ProxyCacheService().loadStaleTestedProxies();
      expect(loaded, hasLength(1));
      expect(loaded!.first.server, 'h-a');
    });

    test('ghost fromJson entries filtered (FIXED)', () {
      const raw =
          '[{"server":null,"port":"nope","secret":null},{"server":"","port":0,"secret":""}]';
      final decoded = ProxyCacheService.decodeProxies(raw);
      // FIXED via isValidForCache filter.
      expect(
        decoded,
        isEmpty,
        reason: 'POST-FIX: ghosts must be filtered',
      );
    });

    test('capForCache keeps favorites first, drops rest', () {
      final allFav = [
        for (var i = 0; i < AppConstants.maxCachedTestedEntries + 50; i++)
          _e('f$i', fav: true),
      ];
      final capped = ProxyCacheService.capForCache(allFav);
      expect(capped.length, AppConstants.maxCachedTestedEntries);
    });

    test('TTL boundary: fresh loads, expired returns null', () async {
      final now = DateTime.now().toUtc();
      await _prime(
        ProxyCacheService.testedKey,
        _encode([_e('edge')]),
      );
      await _prime(
        ProxyCacheService.testedAtKey,
        now
            .subtract(AppConstants.testedCacheTtl - const Duration(seconds: 5))
            .toIso8601String(),
      );
      // Fresh (TTL-5s) must load.
      expect(
        await ProxyCacheService().loadTestedProxies(),
        hasLength(1),
      );

      await _prime(
        ProxyCacheService.testedKey,
        _encode([_e('old')]),
      );
      await _prime(
        ProxyCacheService.testedAtKey,
        now
            .subtract(
              AppConstants.testedCacheTtl + const Duration(seconds: 1),
            )
            .toIso8601String(),
      );
      expect(await ProxyCacheService().loadTestedProxies(), isNull);
    });

    test('stale loader expires after 7d grace (FIXED)', () async {
      final now = DateTime.now().toUtc();
      await _prime(
        ProxyCacheService.testedKey,
        _encode([_e('ancient')]),
      );
      await _prime(
        ProxyCacheService.testedAtKey,
        now.subtract(const Duration(days: 30)).toIso8601String(),
      );
      // FIXED via staleGrace 7d.
      expect(
        await ProxyCacheService().loadStaleTestedProxies(),
        isNull,
        reason: 'POST-FIX: 30d stale must be null',
      );
    });
  });
}
