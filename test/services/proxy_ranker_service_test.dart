import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/models/proxy_model.dart';
import 'package:telepulse/services/proxy_ranker_service.dart';

ProxyModel mk({
  String server = 'h',
  int port = 443,
  String secret = 'A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
  String source = 'unknown',
  bool alive = false,
  int latency = -1,
  DateTime? checked,
  int failures = 0,
}) {
  return ProxyModel(
    server: server,
    port: port,
    secret: secret,
    source: source,
    isAlive: alive,
    latencyMs: latency,
    lastChecked: checked,
    connectionFailures: failures,
  );
}

void main() {
  group('tier ordering', () {
    test('verified alive outranks plain alive', () {
      final verified = mk(server: 'v', alive: true, latency: 400);
      final plain = mk(server: 'p', alive: true, latency: 20);
      final ranked = ProxyRankerService.rank([
        plain,
        verified.copyWith(mtpVerified: true),
      ]);
      expect(ranked.first.server, 'v');
      expect(ProxyRankerService.tierOf(ranked.first), 3);
    });

    test('alive ranks above untested regardless of bonuses', () {
      final untestedRich = mk(source: 'SoliSpirit', secret: 'ee' * 16);
      final plainAlive =
          mk(alive: true, latency: 500, source: 'iwh3n');
      final ranked = ProxyRankerService.rank([untestedRich, plainAlive]);
      expect(ranked.first.isAlive, isTrue);
    });

    test('untested ranks above confirmed-dead', () {
      final deadTrusted =
          mk(source: 'SoliSpirit', checked: DateTime.now(), port: 443);
      final untestedPlain = mk();
      final ranked = ProxyRankerService.rank([deadTrusted, untestedPlain]);
      expect(ranked.first.isUntested, isTrue);
    });
  });

  group('latency tiers', () {
    ({double score}) scoreFor(int ms) => (
          score: ProxyRankerService.scoreOf(mk(alive: true, latency: ms)),
        );

    test('boundaries map to expected bonuses', () {
      final base = ProxyRankerService.scoreOf(mk(alive: true, latency: -1));
      expect(scoreFor(99).score - base, 50);
      expect(scoreFor(100).score - base, 40);
      expect(scoreFor(299).score - base, 40);
      expect(scoreFor(300).score - base, 25);
      expect(scoreFor(499).score - base, 25);
      expect(scoreFor(500).score - base, 10);
      expect(scoreFor(999).score - base, 10);
      expect(scoreFor(1000).score - base, 0);
    });

    test('zero or negative latency earns no bonus but stays alive-based',
        () {
      final s = ProxyRankerService.scoreOf(mk(alive: true, latency: 0));
      expect(s, greaterThan(90));
    });
  });

  group('score composition', () {
    test('perfect fakeTLS proxy on trusted source and port 443', () {
      final m = ProxyModel(
        server: 'h',
        port: 443,
        secret: 'eeA1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
        source: 'SoliSpirit',
        isAlive: true,
        latencyMs: 50,
        mtpVerified: true,
      );
      expect(ProxyRankerService.scoreOf(m), 100 + 50 + 10 + 15 + 8);
    });

    test('unverified FakeTLS earns no disguise bonus', () {
      final m = ProxyModel(
        server: 'h',
        port: 443,
        secret: 'eeA1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
        source: 'SoliSpirit',
        isAlive: true,
        latencyMs: 50,
      );
      expect(ProxyRankerService.scoreOf(m), 100 + 50 + 10 + 0 + 8);
    });

    test('weight drives trust bonus per source definition', () {
      expect(
        ProxyRankerService.scoreOf(mk(alive: true, latency: 10, source: 'SoliSpirit')) -
            ProxyRankerService.scoreOf(
                mk(alive: true, latency: 10, source: 'unknown')),
        10,
      );
      expect(
        ProxyRankerService.scoreOf(mk(
                alive: false,
                source: 'Grim1313-HTML',
                checked: DateTime.now())) -
            ProxyRankerService.scoreOf(
                mk(alive: false, source: 'unknown', checked: DateTime.now())),
        4,
      );
    });

    test('failures subtract 50 each up to the clamp', () {
      expect(
        ProxyRankerService.scoreOf(mk(failures: 2)) -
            ProxyRankerService.scoreOf(mk(failures: 0)),
        -100,
      );
      expect(
        ProxyRankerService.scoreOf(mk(failures: 99)) -
            ProxyRankerService.scoreOf(mk(failures: 0)),
        -500,
      );
    });
  });

  group('topProxies', () {
    test('excludes dead and heavily-penalized proxies', () {
      final good = mk(server: 'good', alive: true, latency: 30);
      final penalized =
          mk(server: 'bad', alive: true, latency: 10, failures: 3);
      final dead = mk(server: 'dead', checked: DateTime.now());
      final top = ProxyRankerService.topProxies([penalized, dead, good]);
      expect(top.map((e) => e.server), ['good']);
    });

    test('respects count limit', () {
      final list = List.generate(
        8,
        (i) => mk(server: 's$i', alive: true, latency: 20 + i),
      );
      expect(ProxyRankerService.topProxies(list, count: 5), hasLength(5));
    });
  });

  group('deterministic ordering', () {
    test('same tier and score breaks ties by lower latency first', () {
      final a = mk(server: 'a', alive: true, latency: 200);
      final b = mk(server: 'b', alive: true, latency: 100);
      final ranked = ProxyRankerService.rank([a, b]);
      expect(ranked.first.server, 'b');
    });
  });
}
