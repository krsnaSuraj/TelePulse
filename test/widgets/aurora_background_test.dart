import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/widgets/aurora_background.dart';

void main() {
  group('AuroraBackground', () {
    testWidgets('renders child without exceptions (bounded pump, infinite)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuroraBackground(child: Text('aurora-child')),
          ),
        ),
      );
      // Bounded pump only — infinite ticker, never pumpAndSettle.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('aurora-child'), findsOneWidget);
      expect(find.byType(RepaintBoundary), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('respects disableAnimations (static frame, no crash)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: AuroraBackground(child: Text('static-aurora')),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('static-aurora'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pauses cleanly when TickerMode disabled', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TickerMode(
              enabled: false,
              child: AuroraBackground(child: Text('muted-aurora')),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('muted-aurora'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
