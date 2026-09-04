import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/core/theme/app_theme.dart';
import 'package:telepulse/providers/proxy_list_provider.dart';
import 'package:telepulse/screens/proxies_screen.dart';
import 'package:telepulse/services/proxy_ranker_service.dart';
import 'package:telepulse/widgets/proxy_tile.dart';

import '../helpers/fakes.dart';

ProxyListNotifier motionNotifier() {
  final n = ProxyListNotifier(
    fetcher: FakeFetcher(),
    tester: FakeTester(),
    cache: FakeCache(),
    connectivity: FakeConnectivity(),
    autoInit: false,
  );
  final now = DateTime.now();
  n.state = const ProxyListState(loadState: ProxyLoadState.ready);
  n.state = n.state.copyWith(
    proxies: ProxyRankerService.rank([
      p('motion-a', 443, 'aa',
          latencyMs: 40, isAlive: true, lastChecked: now),
      p('motion-b', 8080, 'bb',
          latencyMs: 300, isAlive: true, lastChecked: now),
      p('motion-c', 80, 'cc', lastChecked: now),
    ]),
  );
  return n;
}

Future<void> pumpProxies(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        proxyListProvider.overrideWith((ref) => motionNotifier()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const ProxiesScreen(),
      ),
    ),
  );
  // Bounded: entrance 650ms + switchers ~180ms. No infinite tickers here.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  group('ProxiesScreen motion', () {
    testWidgets('staggered entrance renders all tiles (bounded pumps)',
        (tester) async {
      await pumpProxies(tester);
      expect(find.byType(ProxyTile), findsNWidgets(3));
      expect(find.text('motion-a'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('search toggle still filters (same taps)', (tester) async {
      await pumpProxies(tester);
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'motion-b');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      // Query text lives in the TextField too, so assert via tile widgets.
      expect(find.byType(ProxyTile), findsOneWidget);
      expect(find.widgetWithText(ProxyTile, 'motion-b'), findsOneWidget);
      expect(find.widgetWithText(ProxyTile, 'motion-a'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('segment change still filters (same taps)', (tester) async {
      await pumpProxies(tester);
      await tester.tap(find.textContaining('Working'));
      // AnimatedSwitcher cross-fade keeps old+new lists for 180ms — pump
      // twice so the outgoing list disposes before asserting.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ProxyTile), findsNWidgets(2));
      expect(find.text('motion-c'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders under disableAnimations', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            proxyListProvider.overrideWith((ref) => motionNotifier()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(disableAnimations: true),
                child: ProxiesScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ProxyTile), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  });
}
