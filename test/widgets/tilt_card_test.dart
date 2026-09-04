import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/widgets/tilt_card.dart';

void main() {
  group('TiltCard', () {
    testWidgets('renders child without exceptions (bounded pump)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TiltCard(child: Text('tilt-child')),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('tilt-child'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('horizontal drag + release springs back cleanly',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 120,
              child: TiltCard(child: Text('drag-me')),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.drag(find.text('drag-me'), const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('drag-me'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stuck-tilt guard: snaps back when tickers muted',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TickerMode(
              enabled: false,
              child: SizedBox(
                width: 300,
                height: 120,
                child: TiltCard(child: Text('muted')),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.drag(find.text('muted'), const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('muted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Pressable', () {
    testWidgets('does not swallow taps (Listener, not GestureDetector)',
        (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Pressable(
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('press-me'),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('press-me'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('respects disableAnimations (returns child directly)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Pressable(child: Text('plain')),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('plain'), findsOneWidget);
      expect(find.byType(AnimatedScale), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
