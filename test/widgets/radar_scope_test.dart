import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/core/theme/app_theme.dart';
import 'package:telepulse/models/proxy_model.dart';
import 'package:telepulse/widgets/radar_scope.dart';

ProxyModel mk(String id,
    {bool alive = false, int latency = -1, DateTime? checked}) {
  return ProxyModel(
    server: 'srv-$id',
    port: 1000 + id.length,
    secret: 'secret$id',
    isAlive: alive,
    latencyMs: latency,
    lastChecked: checked,
  );
}

void main() {
  group('layoutRadarBlips', () {
    test('empty input yields no blips', () {
      expect(layoutRadarBlips([]), isEmpty);
    });

    test('layout is deterministic for identical input', () {
      final list = [mk('a'), mk('b', alive: true, latency: 40)];
      final first = layoutRadarBlips(list);
      final second = layoutRadarBlips(list);
      expect(first.length, second.length);
      for (var i = 0; i < first.length; i++) {
        expect(second[i].angle, first[i].angle);
        expect(second[i].radiusFraction, first[i].radiusFraction);
      }
    });

    test('respects the max cap', () {
      final list = [for (var i = 0; i < 100; i++) mk('s$i')];
      expect(layoutRadarBlips(list), hasLength(36));
      expect(layoutRadarBlips(list, max: 10), hasLength(10));
    });

    test('all blips land inside the disc', () {
      final list = [for (var i = 0; i < 60; i++) mk('n$i')];
      for (final b in layoutRadarBlips(list)) {
        expect(b.radiusFraction, inInclusiveRange(0.15, 0.92));
        expect(b.angle, inInclusiveRange(0.0, 360.0));
        expect(b.size, greaterThan(0));
        expect(b.semantic, isNotEmpty);
      }
    });

    test('fast proxies get the alive color and bigger dots', () {
      final blips = layoutRadarBlips([
        mk('fast', alive: true, latency: 40),
        mk('slow', alive: true, latency: 900),
        mk('dead', checked: DateTime.now()),
        mk('new'),
      ]);
      expect(blips[0].color, AppColors.alive);
      expect(blips[1].color, AppColors.slowAlive);
      expect(blips[2].color, AppColors.dead);
      expect(blips[3].color, AppColors.textMuted);
    });
  });

  group('RadarScope widget', () {
    testWidgets('renders blips without crashing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadarScope(
              blips: layoutRadarBlips([
                mk('a', alive: true, latency: 30),
                mk('b'),
              ]),
              sweeping: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(RadarScope), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('static mode renders a single frame cleanly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RadarScope(blips: [], sweeping: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
