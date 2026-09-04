import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/widgets/brand_mark.dart';

void main() {
  group('BrandMark', () {
    testWidgets('renders without exceptions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BrandMark(size: 24)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.byType(RepaintBoundary), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('AnimatedBrandMark', () {
    testWidgets('active pulse renders (bounded pump, infinite ticker)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedBrandMark(size: 24)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(AnimatedBrandMark), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('inactive renders static BrandMark', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
              body: AnimatedBrandMark(size: 24, active: false)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(BrandMark), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('respects disableAnimations', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: AnimatedBrandMark(size: 24),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(BrandMark), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
