import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/providers/proxy_list_provider.dart';
import 'package:telepulse/services/deep_link_service.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeCache cache;
  late FakeConnectivity connectivity;
  late FakeFetcher fetcher;
  late FakeTester tester;
  late FakeProbe probe;

  ProxyListNotifier build() {
    return ProxyListNotifier(
      fetcher: fetcher,
      tester: tester,
      probe: probe,
      deepLink: DeepLinkService(),
      cache: cache,
      connectivity: connectivity,
      autoInit: false,
    );
  }

  setUp(() {
    cache = FakeCache();
    connectivity = FakeConnectivity();
    fetcher = FakeFetcher();
    tester = FakeTester();
    probe = FakeProbe();
  });

  group('startup', () {
    test(
        'offline launch with cache shows results without testing or overwriting',
        () async {
      cache.primeTestedCache([
        p('cached1', 443, 's1',
            latencyMs: 90, isAlive: true, lastChecked: DateTime.now()),
        p('cached2', 443, 's2', lastChecked: DateTime.now()),
      ]);
      connectivity.fakeOnline = false;

      final n = build();
      await n.init();
      await pumpUntil(() => n.state.loadState == ProxyLoadState.ready);

      expect(n.state.notice, NoticeKind.offline);
      expect(n.state.aliveCount, 1);
      expect(tester.testedKeys, isEmpty);
      expect(cache.saveTestedCalls, 0);
    });

    test('offline launch without cache lands in noInternet', () async {
      connectivity.fakeOnline = false;
      final n = build();
      await n.init();
      await pumpUntil(
          () => n.state.loadState == ProxyLoadState.noInternet);
      expect(n.state.proxies, isEmpty);
    });

    test('online cold start fetches, tests and persists', () async {
      fetcher.allSourcesResult = [p('live', 443, 'k1'), p('gone', 443, 'k2')];
      tester.outcomes['live:443:k1'] = (alive: true, latency: 85);

      final n = build();
      await n.init();
      await pumpUntil(() =>
          n.state.loadState == ProxyLoadState.ready &&
          !n.state.isTesting &&
          n.state.untestedCount == 0);

      expect(n.state.aliveCount, 1);
      expect(tester.testedKeys,
          containsAll(['live:443:k1', 'gone:443:k2']));
      expect(cache.saveTestedCalls, greaterThanOrEqualTo(1));
    });

    test('reconnect after offline triggers a fresh scan', () async {
      connectivity.fakeOnline = false;
      final n = build();
      await n.init();
      await pumpUntil(
          () => n.state.loadState == ProxyLoadState.noInternet);

      fetcher.allSourcesResult = [p('after-net', 80, 'zz')];
      connectivity.goOnline();

      await pumpUntil(() =>
          n.state.loadState == ProxyLoadState.ready &&
          !n.state.isTesting);
      expect(fetcher.fetchAllCalls, greaterThanOrEqualTo(1));
      expect(n.state.aliveCount, isZero);
    });
  });

  group('failure accounting', () {
    test(
        'REGRESSION: successful re-test resets connectionFailures to zero',
        () async {
      final healed = p('healed', 443, 'hh',
          connectionFailures: appMaxFailures);
      cache.primeTestedCache([healed]);
      tester.outcomes['healed:443:hh'] = (alive: true, latency: 60);

      final n = build();
      await n.init();
      await pumpUntil(() =>
          n.state.loadState == ProxyLoadState.ready &&
          !n.state.isTesting &&
          n.state.untestedCount == 0);

      final after =
          n.state.proxies.firstWhere((e) => e.key == 'healed:443:hh');
      expect(after.connectionFailures, 0);
      expect(after.isAlive, isTrue);
    });

    test('confirmed dead re-test increments failures by one', () async {
      cache.primeTestedCache([
        p('dying', 80, 'dd', lastChecked: DateTime.now()),
      ]);

      final n = build();
      await n.init();
      await pumpUntil(() => n.state.proxies.isNotEmpty);

      await n.retestSingle(
          p('dying', 80, 'dd'));

      final entry =
          n.state.proxies.firstWhere((e) => e.key == 'dying:80:dd');
      expect(entry.connectionFailures, 1);
      expect(entry.isAlive, isFalse);
    });

    test('alive re-test clears prior penalties', () async {
      cache.primeTestedCache([
        p('recover', 443, 'rr',
            connectionFailures: 2, lastChecked: DateTime.now()),
      ]);
      tester.outcomes['recover:443:rr'] = (alive: true, latency: 40);

      final n = build();
      await n.init();
      await pumpUntil(() => n.state.proxies.isNotEmpty);

      await n.retestSingle(p('recover', 443, 'rr'));
      final entry = n
          .state.proxies
          .firstWhere((e) => e.key == 'recover:443:rr');
      expect(entry.connectionFailures, 0);
    });
  });

  group('favorites', () {
    test('survive a refresh even when absent from fetched sources',
        () async {
      final fav = p('favhost', 443, 'ff', isFavorite: true,
          latencyMs: 70, isAlive: true, lastChecked: DateTime.now());
      cache.primeTestedCache([fav]);

      final n = build();
      await n.init();
      await pumpUntil(() =>
          n.state.loadState == ProxyLoadState.ready &&
          !n.state.isTesting);

      fetcher.allSourcesResult = [
        p('brand-new', 9999, 'nn'),
      ];
      await n.refreshProxies();
      await pumpUntil(() =>
          n.state.loadState == ProxyLoadState.ready &&
          !n.state.isTesting);

      expect(
        n.state.proxies.any((e) => e.key == fav.key && e.isFavorite),
        isTrue,
      );
      expect(
        n.state.proxies.any((e) => e.key == 'brand-new:9999:nn'),
        isTrue,
      );
    });

    test('toggleFavorite flips flag and persists snapshot', () async {
      cache.primeTestedCache([p('togg', 443, 'tt')]);
      final n = build();
      await n.init();
      await pumpUntil(() => n.state.proxies.isNotEmpty);

      final target = n.state.proxies.first;
      await n.toggleFavorite(target);

      expect(n.state.proxies.first.isFavorite, isTrue);
      expect(cache.favoritesPayload, hasLength(1));

      await n.toggleFavorite(n.state.proxies.first);
      expect(n.state.proxies.first.isFavorite, isFalse);
    });
  });

  group('custom sources', () {
    test('rejects insecure http scheme without touching network', () async {
      final n = build();
      await n.init();
      await pumpUntil(() => n.state.loadState != ProxyLoadState.loading);
      final callsBefore = fetcher.fetchAllCalls;

      final result = await n.addCustomSource('http://example.com/list.txt');
      expect(result, CustomSourceResult.insecureScheme);
      expect(cache.savedCustomUrls, isEmpty);
      expect(fetcher.fetchAllCalls, callsBefore);
    });

    test('rejects malformed URLs', () async {
      final n = build();
      await n.init();
      expect(await n.addCustomSource('notaurl'),
          CustomSourceResult.invalidUrl);
      expect(await n.addCustomSource('ftp://x.com/f'),
          CustomSourceResult.invalidUrl);
    });

    test('reports empty sources and does not persist them', () async {
      final n = build();
      await n.init();
      fetcher.customResults['https://empty.example/l.txt'] = const [];

      final result =
          await n.addCustomSource('https://empty.example/l.txt');
      expect(result, CustomSourceResult.noProxiesFound);
      expect(cache.savedCustomUrls, isEmpty);
    });

    test('adds, merges and persists a working custom source', () async {
      final n = build();
      await n.init();
      fetcher.customResults['https://good.example/l.txt'] = [
        p('from-custom', 7000, 'cc'),
      ];

      final result =
          await n.addCustomSource('https://good.example/l.txt');
      expect(result, CustomSourceResult.added);
      expect(cache.savedCustomUrls, ['https://good.example/l.txt']);
      expect(n.state.customSources, contains('https://good.example/l.txt'));
      expect(
        n.state.proxies.any((e) => e.server == 'from-custom'),
        isTrue,
      );

      final dup = await n.addCustomSource('https://good.example/l.txt');
      expect(dup, CustomSourceResult.duplicate);
    });

    test('removeCustomSource updates state and storage', () async {
      final n = build();
      await n.init();
      await n.removeCustomSource('https://gone.example/x');
      expect(n.state.customSources, isEmpty);
      expect(cache.savedCustomUrls, isEmpty);
    });

    test('refreshProxies re-fetches saved custom sources', () async {
      cache.customUrlStorage = ['https://c.example/l.txt'];
      fetcher.allSourcesResult = [p('built', 443, 'bb')];
      fetcher.customResults['https://c.example/l.txt'] = [
        p('from-custom-refresh', 7000, 'cc'),
      ];
      tester.outcomes['built:443:bb'] = (alive: true, latency: 50);
      tester.outcomes['from-custom-refresh:7000:cc'] =
          (alive: true, latency: 60);

      final n = build();
      await n.init();
      await pumpUntil(
        () => n.state.proxies.any((e) => e.server == 'from-custom-refresh'),
      );

      expect(
        n.state.proxies.any((e) => e.server == 'from-custom-refresh'),
        isTrue,
      );
      expect(n.state.customSources, contains('https://c.example/l.txt'));
    });
  });

  group('merge semantics', () {
    test('mergePreservingExisting keeps results and appends newcomers',
        () {
      final existing = [
        p('keep', 1, 'a', isAlive: true, latencyMs: 55),
        p('stale-only', 2, 'b'),
      ];
      final incoming = [
        p('keep', 1, 'a'),
        p('newcomer', 3, 'c'),
      ];
      final merged =
          ProxyListNotifier.mergePreservingExisting(existing, incoming);

      expect(merged, hasLength(3));
      final kept = merged.firstWhere((e) => e.key == 'keep:1:a');
      expect(kept.latencyMs, 55);
      expect(merged.any((e) => e.key == 'newcomer:3:c'), isTrue);
    });

    test('refresh failure keeps existing list and raises soft notice',
        () async {
      cache.primeTestedCache([
        p('solid', 443, 'ss',
            isAlive: true,
            latencyMs: 33,
            lastChecked: DateTime.now()),
      ]);
      final n = build();
      await n.init();
      await pumpUntil(() => n.state.proxies.isNotEmpty);

      fetcher.allSourcesResult = const [];
      await n.refreshProxies();
      await pumpUntil(() => n.state.notice == NoticeKind.refreshFailed);

      expect(n.state.proxies, hasLength(1));
      expect(n.state.loadState, ProxyLoadState.ready);
    });
  });

  group('clearCachedData', () {
    test('wipes proxies but retains custom source configuration',
        () async {
      cache.primeTestedCache([p('wipe-me', 1, 'ww')]);
      final n = build();
      await n.init();
      await pumpUntil(() => n.state.proxies.isNotEmpty);

      await n.clearCachedData();
      expect(n.state.proxies, isEmpty);
      expect(n.state.loadState, ProxyLoadState.initial);
      expect(cache.clearCount, 1);
    });

    test('deleteAllData wipes proxies, sources and preferences', () async {
      cache.customUrlStorage = ['https://x.example/l'];
      cache.wifiOnlyStorage = true;
      cache.autoscanStorage = false;
      cache.primeTestedCache([
        p('gone', 1, 'aa', isAlive: true, latencyMs: 10,
            lastChecked: DateTime.now()),
      ]);
      final n = build();
      await n.init();
      await pumpUntil(() => n.state.proxies.isNotEmpty);

      await n.deleteAllData();
      await pumpUntil(() => !n.state.isTesting);

      expect(n.state.proxies, isEmpty);
      expect(n.state.customSources, isEmpty);
      expect(n.state.wifiOnlyAutoScan, isFalse);
      expect(n.state.autoScanOnReconnect, isTrue);
    });
  });

  group('scan preferences', () {
    test('wifi-only blocks auto-sweep on mobile with a paused notice',
        () async {
      cache.primeTestedCache([
        p('m1', 443, 'mm', lastChecked: DateTime.now()),
      ]);
      cache.wifiOnlyStorage = true;
      connectivity.fakeType = ConnectivityResult.mobile;

      final n = build();
      await n.init();
      await pumpUntil(() => n.state.loadState == ProxyLoadState.ready);

      expect(n.state.wifiOnlyAutoScan, isTrue);
      expect(n.state.notice, NoticeKind.mobilePaused);
      expect(tester.testedKeys, isEmpty,
          reason: 'no background sweep may run on mobile data');
    });

    test('manual refresh still scans on mobile when wifi-only is set',
        () async {
      cache.primeTestedCache([
        p('m2', 443, 'mm', lastChecked: DateTime.now()),
      ]);
      cache.wifiOnlyStorage = true;
      connectivity.fakeType = ConnectivityResult.mobile;
      tester.outcomes['m2:443:mm'] = (alive: true, latency: 50);

      final n = build();
      await n.init();
      await pumpUntil(() => n.state.loadState == ProxyLoadState.ready);

      fetcher.allSourcesResult = [p('m2', 443, 'mm')];
      await n.refreshProxies();
      await pumpUntil(() =>
          !n.state.isTesting && tester.testedKeys.contains('m2:443:mm'));

      final entry =
          n.state.proxies.firstWhere((e) => e.key == 'm2:443:mm');
      expect(entry.isAlive, isTrue);
    });

    test('toggles persist across restarts', () async {
      final n = build();
      await n.init();
      await pumpUntil(
          () => n.state.loadState != ProxyLoadState.initial);

      await n.setWifiOnlyAutoScan(true);
      await n.setAutoScanOnReconnect(false);
      expect(n.state.wifiOnlyAutoScan, isTrue);
      expect(n.state.autoScanOnReconnect, isFalse);
      expect(cache.wifiOnlyStorage, isTrue);
      expect(cache.autoscanStorage, isFalse);
    });

    test('disabled auto-scan skips reconnect refresh', () async {
      connectivity.fakeOnline = false;
      cache.autoscanStorage = false;
      final n = build();
      await n.init();
      await pumpUntil(
          () => n.state.loadState == ProxyLoadState.noInternet);

      fetcher.allSourcesResult = [p('nope', 1, 'nn')];
      connectivity.goOnline();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(fetcher.fetchAllCalls, 0,
          reason: 'reconnect must not trigger a scan when disabled');
    });
  });
}

const appMaxFailures = 3;

