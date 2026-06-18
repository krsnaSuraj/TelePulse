import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:telepulse/app.dart';

void main() {
  testWidgets('TelePulse app renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: TelePulseApp(),
      ),
    );
    expect(find.text('TelePulse'), findsOneWidget);
  });
}
