import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/widgets/launch_intro.dart';

void main() {
  group('LaunchIntro', () {
    testWidgets('renders child immediately underneath (never blocks)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LaunchIntro(
            bootDuration: const Duration(milliseconds: 300),
            fadeDuration: const Duration(milliseconds: 100),
            child: Scaffold(
              body: TextButton(
                onPressed: () {},
                child: const Text('underlying-app'),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      // Both overlay branding and underlying child exist on first paint.
      expect(find.text('TelePulse'), findsWidgets);
      expect(find.text('underlying-app'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tap skips instantly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LaunchIntro(
            bootDuration: const Duration(milliseconds: 900),
            fadeDuration: const Duration(milliseconds: 250),
            child: const Scaffold(body: Text('app-home')),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('FIND SIGNAL ANYWHERE'), findsOneWidget);

      await tester.tap(find.text('FIND SIGNAL ANYWHERE'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('FIND SIGNAL ANYWHERE'), findsNothing);
      expect(find.text('app-home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('auto-dismisses after boot + fade (bounded pumps)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LaunchIntro(
            bootDuration: const Duration(milliseconds: 200),
            fadeDuration: const Duration(milliseconds: 100),
            child: const Scaffold(body: Text('ready-app')),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('FIND SIGNAL ANYWHERE'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 100));
      // Allow the delayed removal to fire.
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('FIND SIGNAL ANYWHERE'), findsNothing);
      expect(find.text('ready-app'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('respects disableAnimations (skips instantly)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: LaunchIntro(child: Text('instant-app')),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('FIND SIGNAL ANYWHERE'), findsNothing);
      expect(find.text('instant-app'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('zero boot duration skips (test fast-path)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LaunchIntro(
            bootDuration: Duration.zero,
            fadeDuration: const Duration(milliseconds: 50),
            child: const Scaffold(body: Text('zero-app')),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('FIND SIGNAL ANYWHERE'), findsNothing);
      expect(find.text('zero-app'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
