import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/core/theme/app_theme.dart';
import 'package:telepulse/providers/proxy_list_provider.dart';
import 'package:telepulse/screens/proxies_screen.dart';
import 'package:telepulse/services/proxy_ranker_service.dart';
import 'package:telepulse/widgets/proxy_tile.dart';

import '../helpers/fakes.dart';

ProxyListNotifier seededNotifier() {
  final n = ProxyListNotifier(
    fetcher: FakeFetcher(),
    tester: FakeTester(), probe: FakeProbe(),
    cache: FakeCache(),
    connectivity: FakeConnectivity(),
    autoInit: false,
  );
  final now = DateTime.now();
  n.state = const ProxyListState(loadState: ProxyLoadState.ready);
  n.state = n.state.copyWith(
    proxies: ProxyRankerService.rank([
      p('alpha-srv', 443, 'aa',
          latencyMs: 40,
          isAlive: true,
          lastChecked: now,
          isFavorite: true),
      p('beta-srv', 8080, 'bb', latencyMs: 300,
          isAlive: true, lastChecked: now),
      p('gamma-srv', 80, 'cc', lastChecked: now),
    ]),
  );
  return n;
}

void main() {
  testWidgets('Proxies screen renders tiles and filters by search query',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          proxyListProvider.overrideWith((ref) => seededNotifier()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const ProxiesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProxyTile), findsNWidgets(3));
    expect(find.text('alpha-srv'), findsOneWidget);
    expect(find.textContaining('Working (2)'), findsOneWidget);
    expect(find.textContaining('Saved (1)'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), 'beta');
    await tester.pumpAndSettle();

    expect(find.byType(ProxyTile), findsOneWidget);
    expect(find.text('beta-srv'), findsOneWidget);
  });

  testWidgets('Working segment shows only alive proxies', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          proxyListProvider.overrideWith((ref) => seededNotifier()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const ProxiesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Working'));
    await tester.pumpAndSettle();

    expect(find.byType(ProxyTile), findsNWidgets(2));
    expect(find.text('gamma-srv'), findsNothing);
  });

  testWidgets('Favorites segment shows saved proxy only', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          proxyListProvider.overrideWith((ref) => seededNotifier()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const ProxiesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Saved'));
    await tester.pumpAndSettle();

    expect(find.byType(ProxyTile), findsOneWidget);
    expect(find.text('alpha-srv'), findsOneWidget);
  });
}

