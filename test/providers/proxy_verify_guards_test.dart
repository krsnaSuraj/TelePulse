import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/core/app_constants.dart';
import 'package:telepulse/providers/proxy_list_provider.dart';
import 'package:telepulse/services/mtproto_probe_service.dart';

import '../helpers/fakes.dart';

class _RiggedRandom implements Random {
  @override
  int nextInt(int max) {
    if (max == 256) return 0xef;
    return 0;
  }

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.0;
}

void main() {
  group('handshake edge cases', () {
    test('buildInit exhaustion returns null instead of hanging', () {
      expect(
        MtprotoProbeService.buildInit(random: _RiggedRandom()),
        isNull,
      );
    });

    test('verify() with broken RNG fails closed as dead', () async {
      final probe = MtprotoProbeService(random: _RiggedRandom());
      final result = await probe.verify(
        p('rigged', 443, 'A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6'),
      );
      expect(result.outcome, ProbeOutcome.dead);
    });

    test('verify() short-circuits unsupported secrets without sockets',
        () async {
      final probe = MtprotoProbeService();
      final result = await probe.verify(
        p('ee1', 443, 'eeA1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6'),
      );
      expect(result.outcome, ProbeOutcome.unsupported);
      expect(result.probeLatencyMs, -1);
    });
  });

  group('verifyTopCandidates guards', () {
    late FakeCache cache;
    late FakeConnectivity connectivity;
    late FakeFetcher fetcher;
    late FakeTester tester;
    late FakeProbe probe;

    setUp(() {
      cache = FakeCache();
      connectivity = FakeConnectivity();
      fetcher = FakeFetcher();
      tester = FakeTester();
      probe = FakeProbe();
    });

    ProxyListNotifier build() => ProxyListNotifier(
          fetcher: fetcher,
          tester: tester,
          probe: probe,
          cache: cache,
          connectivity: connectivity,
          autoInit: false,
        );

    test('metered connections cap verification at 10', () async {
      connectivity.fakeType = ConnectivityResult.mobile;
      final many = [
        for (var i = 0; i < 15; i++)
          p('met$i', 4000 + i, 'A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
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
      await pumpUntil(() => probe.verifiedKeys.isNotEmpty);

      expect(probe.verifiedKeys.length,
          lessThanOrEqualTo(AppConstants.mobileVerifyCap));
    });

    test('reverify quota bounds already-verified re-probes', () async {
      final many = [
        for (var i = 0; i < 8; i++)
          p('rv$i', 5000 + i, 'A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
              latencyMs: 20,
              isAlive: true,
              lastChecked: DateTime.now())
              .copyWith(mtpVerified: true),
      ];
      cache.primeTestedCache(many);
      for (final entry in many) {
        tester.outcomes[entry.key] = (alive: true, latency: 25);
        probe.verdicts[entry.key] = ProbeOutcome.verified;
      }

      final n = build();
      await n.init();
      await pumpUntil(() => !n.state.isTesting);
      await pumpUntil(() => probe.verifiedKeys.isNotEmpty);

      expect(probe.verifiedKeys.length,
          MtprotoProbeService.reverifyQuota);
    });

    test('stale verify pass aborts without touching new state', () async {
      final a = p('gen-a', 6001, 'A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6');
      cache.primeTestedCache([a]);
      tester.outcomes[a.key] = (alive: true, latency: 30);
      probe.verdicts[a.key] = ProbeOutcome.verified;
      probe.gate = Completer<void>();

      final n = build();
      await n.init();
      await pumpUntil(() =>
          n.state.loadState == ProxyLoadState.ready &&
          !n.state.isTesting &&
          tester.testedKeys.contains(a.key));
      await pumpUntil(() => probe.verifiedKeys.contains(a.key));

      fetcher.allSourcesResult = [
        p('gen-b', 6002, 'B1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6'),
      ];
      await n.refreshProxies();
      probe.gate!.complete();
      probe.gate = Completer<void>();

      await pumpUntil(() =>
          !n.state.isTesting &&
          n.state.proxies.any((e) => e.key.startsWith('gen-b:')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
          n.state.proxies
              .firstWhere((e) => e.key == a.key)
              .mtpVerified,
          isFalse,
          reason:
              'aborted generation must not resurrect verified flags');
    });

    test('unsupported outcomes leave the flag untouched', () async {
      final u = p('unsup', 443, 'A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
          latencyMs: 20, isAlive: true, lastChecked: DateTime.now());
      cache.primeTestedCache([u]);
      tester.outcomes[u.key] = (alive: true, latency: 20);
      probe.verdicts[u.key] = ProbeOutcome.unsupported;

      final n = build();
      await n.init();
      await pumpUntil(() =>
          !n.state.isTesting && probe.verifiedKeys.contains(u.key));

      expect(
        n.state.proxies.firstWhere((e) => e.key == u.key).mtpVerified,
        isFalse,
      );
    });
  });
}
