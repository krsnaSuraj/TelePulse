import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/widgets/radar_scope.dart';

import 'radar_scope_test.dart' show mk;

void main() {
  group('RadarScope motion gates', () {
    testWidgets('sweeping renders highlight without crashing (bounded)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadarScope(
              blips: layoutRadarBlips([
                mk('a', alive: true, latency: 30),
                mk('b', alive: true, latency: 900),
              ]),
              sweeping: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(RadarScope), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disableAnimations forces static disc (no frozen sweep)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: RadarScope(
                blips: layoutRadarBlips([mk('a', alive: true, latency: 30)]),
                sweeping: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(RadarScope), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TickerMode disabled renders statically', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TickerMode(
              enabled: false,
              child: RadarScope(
                blips: layoutRadarBlips([mk('a')]),
                sweeping: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(RadarScope), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
