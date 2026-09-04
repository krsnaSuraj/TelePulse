import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/models/proxy_model.dart';
import 'package:telepulse/providers/proxy_list_provider.dart';
import 'package:telepulse/services/mtproto_probe_service.dart';

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

  group('listener integrity', () {
    test('toggleFavorite emits a state change to listeners', () async {
      cache.primeTestedCache([p('fav1', 443, 'f1')]);
      final n = build();
      await n.init();
      await pumpUntil(() => n.state.proxies.isNotEmpty);

      var emissions = 0;
      final remove = n.addListener((ProxyListState _) => emissions++);
      await n.toggleFavorite(n.state.proxies.first);
      remove();

      expect(emissions, greaterThanOrEqualTo(1),
          reason:
              'ProxyModel equality must include behavioral fields or the '
              'StateNotifier swallows the emission and the star never moves');
    });
  });

  group('mid-sweep concurrency', () {
    test('refresh completing mid-sweep keeps fetched newcomers', () async {
      final a = p('alpha', 1, 'aa');
      cache.primeTestedCache([a]);
      tester.gate(a.key);
      tester.outcomes[a.key] = (alive: true, latency: 50);

      final n = build();
      await n.init();
      await pumpUntil(() => n.state.isTesting);

      fetcher.allSourcesResult = [p('bravo', 2, 'bb')];
      await n.refreshProxies();
      expect(
        n.state.proxies.any((e) => e.key == 'bravo:2:bb'),
        isTrue,
        reason: 'merge-not-replace must surface newcomers immediately',
      );

      tester.release(a.key);
      tester.outcomes['bravo:2:bb'] = (alive: true, latency: 60);
      await pumpUntil(() =>
          !n.state.isTesting &&
          n.state.untestedCount == 0 &&
          tester.testedKeys.contains('bravo:2:bb'));

      expect(n.state.proxies.any((e) => e.key == a.key), isTrue);
      expect(n.state.proxies.any((e) => e.key == 'bravo:2:bb'), isTrue);
      expect(
        cache.storedTested!.any((e) => e.key == 'bravo:2:bb'),
        isTrue,
        reason: 'persisted tested snapshot must include refreshed entries',
      );
    });

    test('multiple enqueues during one sweep union instead of displacing',
        () async {
      final a = p('gate-me', 1, 'g1');
      cache.primeTestedCache([a]);
      tester.gate(a.key);

      final n = build();
      await n.init();
      await pumpUntil(() => n.state.isTesting);

      enqueueLater(n, [p('first-q', 2, 'q1')]);
      enqueueLater(n, [p('second-q', 3, 'q2')]);

      tester.release(a.key);
      await pumpUntil(() =>
          !n.state.isTesting &&
          tester.testedKeys.contains('first-q:2:q1') &&
          tester.testedKeys.contains('second-q:3:q2'));

      expect(tester.testedKeys, containsAll(['gate-me:1:g1']));
    });

    test('favorite ON mid-sweep survives subsequent batch emissions',
        () async {
      final c = p('fav-on', 5, 'cc');
      cache.primeTestedCache([c]);
      tester.gate(c.key);
      tester.outcomes[c.key] = (alive: true, latency: 70);

      final n = build();
      await n.init();
      await pumpUntil(() => n.state.isTesting);

      await n.toggleFavorite(c.copyWith());
      expect(cache.favoritesPayload!.map((e) => e.key), contains(c.key));

      tester.release(c.key);
      await pumpUntil(() => !n.state.isTesting);

      expect(
        n.state.proxies.firstWhere((e) => e.key == c.key).isFavorite,
        isTrue,
      );
      expect(
        cache.storedTested!.firstWhere((e) => e.key == c.key).isFavorite,
        isTrue,
      );
    });

    test('favorite OFF mid-sweep survives subsequent batch emissions',
        () async {
      final d = p(
        'fav-off',
        6,
        'dd',
        isFavorite: true,
        isAlive: true,
        latencyMs: 80,
        lastChecked: DateTime.now(),
      );
      cache.primeTestedCache([d]);
      tester.gate(d.key);
      tester.outcomes[d.key] = (alive: true, latency: 80);

      final n = build();
      await n.init();
      await pumpUntil(() => n.state.isTesting);

      await n.toggleFavorite(d.copyWith(isFavorite: true));
      expect(cache.favoritesPayload, isEmpty);

      tester.release(d.key);
      await pumpUntil(() => !n.state.isTesting);

      expect(
        n.state.proxies.firstWhere((e) => e.key == d.key).isFavorite,
        isFalse,
      );
      expect(
        cache.storedTested!.firstWhere((e) => e.key == d.key).isFavorite,
        isFalse,
      );
    });
  });

  group('failure policy', () {
    test('tester throwing counts as inconclusive — no penalty applied',
        () async {
      final t = p('throwing', 9, 'tt', lastChecked: DateTime.now());
      cache.primeTestedCache([t]);
      tester.throwKeys.add(t.key);

      final n = build();
      await n.init();
      await pumpUntil(() => n.state.proxies.isNotEmpty);

      await n.retestSingle(t.copyWith());
      final entry =
          n.state.proxies.firstWhere((e) => e.key == t.key);
      expect(entry.connectionFailures, 0,
          reason: 'exceptions are not confirmations');
      expect(entry.isAlive, isFalse);
    });
  });

  group('persistence guards', () {
    test('all-dead sweep does not overwrite a previously-alive cache',
        () async {
      final w = p('was-alive', 7, 'ww',
          isAlive: true, latencyMs: 45, lastChecked: DateTime.now());
      cache.primeTestedCache([w]);
      tester.outcomes[w.key] = (alive: false, latency: -1);

      final n = build();
      await n.init();
      await pumpUntil(() =>
          !n.state.isTesting &&
          tester.testedKeys.contains(w.key) &&
          n.state.untestedCount == 0);

      expect(
        n.state.proxies.firstWhere((e) => e.key == w.key).isAlive,
        isFalse,
        reason: 'UI must reflect reality',
      );
      expect(cache.saveTestedCalls, 0,
          reason: 'cache must keep the last known-good results');
      expect(cache.storedTested!.first.isAlive, isTrue);
    });
  });

  group('handshake verification', () {
    test('verified proxies are flagged and re-ranked first', () async {
      final a = p('va', 443, 'A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
          latencyMs: 120, isAlive: true, lastChecked: DateTime.now());
      final b = p('vb', 443, 'B1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
          latencyMs: 30, isAlive: true, lastChecked: DateTime.now());
      cache.primeTestedCache([a, b]);
      tester.outcomes[a.key] = (alive: true, latency: 120);
      tester.outcomes[b.key] = (alive: true, latency: 30);
      probe.verdicts['vb:443:B1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6'] =
          ProbeOutcome.verified;

      final n = build();
      await n.init();
      await pumpUntil(() =>
          !n.state.isTesting &&
          n.state.proxies
              .any((e) => e.key == 'vb:443:B1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6' && e.mtpVerified));

      final ranked = n.state.proxies;
      expect(ranked.first.key,
          'vb:443:B1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6');
      expect(
          ranked.firstWhere((e) => e.key.startsWith('va:')).mtpVerified,
          isFalse);
    });

    test('verification is capped per sweep', () async {
      final many = [
        for (var i = 0; i < 45; i++)
          p('cap$i', 1000 + i, 'A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
              latencyMs: 20 + i,
              isAlive: true,
              lastChecked: DateTime.now()),
      ];
      cache.primeTestedCache(many);
      for (final entry in many) {
        tester.outcomes[entry.key] = (alive: true, latency: 25);
      }

      final n = build();
      await n.init();
      await pumpUntil(() => !n.state.isTesting);
      await pumpUntil(() => probe.verifiedKeys.length >= 40);

      expect(probe.verifiedKeys.length,
          MtprotoProbeService.maxCandidatesPerSweep);
    });

    test('verifiable secrets sort ahead of FakeTLS for the probe budget',
        () async {
      final entries = <ProxyModel>[
        for (var i = 0; i < 45; i++)
          p('tls$i', 2000 + i,
              'eeA1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
              latencyMs: 10 + i,
              isAlive: true,
              lastChecked: DateTime.now()),
        for (var i = 0; i < 5; i++)
          p('plain$i', 3000 + i, 'A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
              latencyMs: 500 + i,
              isAlive: true,
              lastChecked: DateTime.now()),
      ];
      cache.primeTestedCache(entries);
      for (final entry in entries) {
        tester.outcomes[entry.key] = (alive: true, latency: 25);
      }
      for (var i = 0; i < 5; i++) {
        probe.verdicts['plain$i:${3000 + i}:A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6'] =
            ProbeOutcome.verified;
      }

      final n = build();
      await n.init();
      await pumpUntil(() => !n.state.isTesting);
      await pumpUntil(() => probe.verifiedKeys.length >= 40);

      for (var i = 0; i < 5; i++) {
        expect(
          probe.verifiedKeys,
          contains('plain$i:${3000 + i}:A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6'),
          reason: 'verifiable entries must not starve behind FakeTLS',
        );
      }
    });

    test('stale favorite restore drops the verified flag', () async {
      final staleFav = p('stalefav', 443, 'A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
          isFavorite: true,
          isAlive: true,
          latencyMs: 60,
          lastChecked: DateTime.now());
      cache.primeTestedCache(
          [p('other', 80, 'zz', lastChecked: DateTime.now())]);
      cache.favoritesPayload = [
        staleFav.copyWith(mtpVerified: true),
      ];
      connectivity.fakeOnline = false;

      final n = build();
      await n.init();
      await pumpUntil(
          () => n.state.loadState == ProxyLoadState.ready);

      final restored = n.state.proxies
          .firstWhere((e) => e.key == staleFav.key);
      expect(restored.isFavorite, isTrue);
      expect(restored.mtpVerified, isFalse,
          reason: 'restored favorites must re-verify from scratch');
    });

    test('inconclusive retest preserves a hard-won verified flag', () async {
      final v = p('keepflag', 443, 'A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
          isAlive: true,
          latencyMs: 44,
          lastChecked: DateTime.now());
      cache.primeTestedCache([v]);
      tester.outcomes[v.key] = (alive: true, latency: 44);
      probe.verdicts[v.key] = ProbeOutcome.verified;

      final n = build();
      await n.init();
      await pumpUntil(() =>
          !n.state.isTesting &&
          n.state.proxies.any((e) => e.key == v.key && e.mtpVerified));

      tester.throwKeys.add(v.key);
      await n.retestSingle(v.copyWith());
      final entry =
          n.state.proxies.firstWhere((e) => e.key == v.key);
      expect(entry.mtpVerified, isTrue,
          reason: 'timeouts are inconclusive, not refutations');
    });

    test('dead probe outcome clears a stale verified flag', () async {      final v = p('clearflag', 443, 'C1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
          isAlive: true,
          latencyMs: 44,
          lastChecked: DateTime.now());
      cache.primeTestedCache([v.copyWith(mtpVerified: true)]);
      tester.outcomes[v.key] = (alive: true, latency: 44);
      probe.verdicts[v.key] = ProbeOutcome.dead;

      final n = build();
      await n.init();
      await pumpUntil(() =>
          !n.state.isTesting &&
          probe.verifiedKeys.contains(v.key));

      final entry =
          n.state.proxies.firstWhere((e) => e.key == v.key);
      expect(entry.isAlive, isTrue);
      expect(entry.mtpVerified, isFalse,
          reason: 'failed handshake must revoke the badge');
    });

    test('recheck quota reserves slots ahead of fresh overflow', () async {
      final entries = <ProxyModel>[
        for (var i = 0; i < 45; i++)
          p('overflow$i', 7000 + i, 'A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
              latencyMs: 20 + i,
              isAlive: true,
              lastChecked: DateTime.now()),
        for (var i = 0; i < 3; i++)
          p('recheck$i', 8000 + i, 'B1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
              latencyMs: 900 + i,
              isAlive: true,
              lastChecked: DateTime.now())
              .copyWith(mtpVerified: true),
      ];
      cache.primeTestedCache(entries);
      for (final entry in entries) {
        tester.outcomes[entry.key] = (alive: true, latency: 25);
        probe.verdicts[entry.key] = ProbeOutcome.verified;
      }

      final n = build();
      await n.init();
      await pumpUntil(() => !n.state.isTesting);
      await pumpUntil(() => probe.verifiedKeys.length >= 40);

      for (var i = 0; i < 3; i++) {
        expect(
          probe.verifiedKeys,
          contains(startsWith('recheck$i:')),
          reason: 'recheck quota must survive fresh overflow',
        );
      }
      expect(probe.verifiedKeys.length,
          MtprotoProbeService.maxCandidatesPerSweep);
    });
  });
}

void enqueueLater(ProxyListNotifier n, List<ProxyModel> list) {
  n.enqueueTest(list);
}
