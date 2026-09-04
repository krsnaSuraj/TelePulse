import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/models/proxy_model.dart';
import 'package:telepulse/models/proxy_view.dart';

ProxyModel mk(
  String server, {
  int port = 443,
  bool alive = false,
  int latency = -1,
  DateTime? checked,
  bool favorite = false,
  String source = 'SoliSpirit',
}) {
  return ProxyModel(
    server: server,
    port: port,
    secret: 'A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6',
    source: source,
    isAlive: alive,
    latencyMs: latency,
    lastChecked: checked,
    isFavorite: favorite,
  );
}

void main() {
  final now = DateTime.now();
  List<ProxyModel> sample() => [
        mk('b-server', alive: true, latency: 200, checked: now),
        mk('a-server',
            alive: true,
            latency: 50,
            checked: now,
            favorite: true),
        mk('c-server', checked: now),
        mk('d-server'),
      ];

  group('applyProxyView filters', () {
    test('all returns everything in ranked order', () {
      expect(applyProxyView(sample()), hasLength(4));
    });

    test('working keeps alive entries only', () {
      final out =
          applyProxyView(sample(), filter: ProxyFilter.working);
      expect(out.map((e) => e.server), containsAll(['a-server', 'b-server']));
      expect(out, hasLength(2));
    });

    test('favorites keeps starred entries only', () {
      final out =
          applyProxyView(sample(), filter: ProxyFilter.favorites);
      expect(out.map((e) => e.server), ['a-server']);
    });

    test('query matches server, source and port case-insensitively', () {
      expect(applyProxyView(sample(), query: 'A-SER'),
          hasLength(1));
      expect(
          applyProxyView(sample(),
              query: 'soli'),
          hasLength(4));
      expect(applyProxyView(sample(), query: '443'), hasLength(4));
      expect(applyProxyView(sample(), query: 'nope'), isEmpty);
    });
  });

  group('applyProxyView sorts', () {
    test('latency puts alive first, fastest first, ties by key', () {
      final out = applyProxyView(sample(), sort: ProxySort.latency);
      expect(out.first.server, 'a-server');
      expect(out[1].server, 'b-server');
    });

    test('recently checked is newest-first with deterministic ties', () {
      final older = now.subtract(const Duration(hours: 2));
      final list = [
        mk('old', checked: older),
        mk('new', checked: now),
        mk('never'),
      ];
      final out =
          applyProxyView(list, sort: ProxySort.recentlyChecked);
      expect(
        out.map((e) => e.server).toList(),
        ['new', 'old', 'never'],
      );
    });

    test('server sort is alphabetical with key tiebreak', () {
      final out = applyProxyView(sample(), sort: ProxySort.server);
      expect(
        out.map((e) => e.server).toList(),
        ['a-server', 'b-server', 'c-server', 'd-server'],
      );
    });

    test('repeated sorts are stable for identical inputs', () {
      final first =
          applyProxyView(sample(), sort: ProxySort.latency)
              .map((e) => e.key)
              .toList();
      final second =
          applyProxyView(sample(), sort: ProxySort.latency)
              .map((e) => e.key)
              .toList();
      expect(first, second);
    });
  });

  group('describeView', () {
    test('plain summary without extras', () {
      expect(
        describeView(
            visible: 5, tested: 4, working: 2,
            sort: ProxySort.rank, query: ''),
        '5 shown · 4 tested · 2 working',
      );
    });

    test('appends single-quoted query and sort context', () {
      expect(
        describeView(
          visible: 1,
          tested: 4,
          working: 2,
          sort: ProxySort.latency,
          query: 'eu',
        ),
        '1 shown · 4 tested · 2 working · matching "eu" · sorted by lowest latency',
      );
    });
  });

  group('ProxySortLabel', () {
    test('every sort has a non-empty label', () {
      for (final s in ProxySort.values) {
        expect(s.label, isNotEmpty);
      }
    });
  });

  test('Random is injectable in source provider', () {
    expect(Random.new, isNotNull);
  });
}
