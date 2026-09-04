import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/core/theme/app_theme.dart';
import 'package:telepulse/providers/proxy_list_provider.dart';
import 'package:telepulse/screens/home_screen.dart';
import 'package:telepulse/services/proxy_ranker_service.dart';
import 'package:telepulse/widgets/animated_status_orb.dart';
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
  n.state = n.state.copyWith(
    loadState: ProxyLoadState.ready,
    proxies: ProxyRankerService.rank([
      p('home-a', 443, 'aa',
          latencyMs: 40, isAlive: true, lastChecked: now),
      p('home-b', 8080, 'bb',
          latencyMs: 200, isAlive: true, lastChecked: now),
    ]),
  );
  return n;
}

Future<void> pumpHome(WidgetTester tester, ProxyListNotifier notifier) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        proxyListProvider.overrideWith((ref) => notifier),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
}

void main() {
  testWidgets(
      'REGRESSION: home dashboard renders without inherited-widget crash',
      (tester) async {
    await pumpHome(tester, seededNotifier());

    expect(find.byType(AnimatedStatusOrb), findsOneWidget);
    expect(find.text('home-a'), findsWidgets);
    expect(find.byType(ProxyTile), findsWidgets);
    expect(find.text('RECOMMENDED NOW'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home shows alive counts in the status header', (tester) async {
    await pumpHome(tester, seededNotifier());
    expect(find.text('2 working · 2 found'), findsOneWidget);
    expect(find.text('2 working picks'), findsOneWidget);
  });

  testWidgets('offline empty state renders a helpful message', (tester) async {
    final n = ProxyListNotifier(
      fetcher: FakeFetcher(),
      tester: FakeTester(), probe: FakeProbe(),
      cache: FakeCache(),
      connectivity: FakeConnectivity(),
      autoInit: false,
    );
    n.state = n.state.copyWith(loadState: ProxyLoadState.noInternet);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [proxyListProvider.overrideWith((ref) => n)],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('You are offline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('orb renders while a scan is in progress', (tester) async {
    final n = seededNotifier();
    n.state = n.state.copyWith(
      loadState: ProxyLoadState.testing,
      isTesting: true,
      testedCount: 1,
      totalToTest: 2,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [proxyListProvider.overrideWith((ref) => n)],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SCANNING'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

