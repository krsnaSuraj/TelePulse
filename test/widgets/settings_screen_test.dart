import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/core/theme/app_theme.dart';
import 'package:telepulse/providers/proxy_list_provider.dart';
import 'package:telepulse/screens/settings_screen.dart';
import 'package:telepulse/services/proxy_ranker_service.dart';

import '../helpers/fakes.dart';

ProxyListNotifier settingsNotifier() {
  final n = ProxyListNotifier(
    fetcher: FakeFetcher(),
    tester: FakeTester(),
    cache: FakeCache(),
    connectivity: FakeConnectivity(),
    autoInit: false,
  );
  final now = DateTime.now();
  n.state = n.state.copyWith(
    loadState: ProxyLoadState.ready,
    proxies: ProxyRankerService.rank([
      p('set-a', 443, 'aa',
          latencyMs: 40, isAlive: true, lastChecked: now),
    ]),
  );
  return n;
}

Future<void> pumpSettings(WidgetTester tester, ProxyListNotifier n) async {
  // Tall viewport so all sections build without scrolling (ListView lazily
  // builds only visible children).
  tester.view.physicalSize = const Size(800, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [proxyListProvider.overrideWith((ref) => n)],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const SettingsScreen(),
      ),
    ),
  );
  // Bounded: entrance 700ms + switchers ~150-220ms. No infinite tickers.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  group('SettingsScreen motion (no logic changes)', () {
    testWidgets('renders all sections without exceptions', (tester) async {
      await pumpSettings(tester, settingsNotifier());
      expect(find.text('CONNECTION'), findsOneWidget);
      expect(find.text('Auto-scan on reconnect'), findsOneWidget);
      expect(find.text('SOURCES'), findsOneWidget);
      expect(find.text('DATA'), findsOneWidget);
      expect(find.text('UPDATES'), findsOneWidget);
      expect(find.text('Check for updates'), findsOneWidget);
      expect(find.text('ABOUT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switch toggle still flips provider state (same taps)',
        (tester) async {
      final n = settingsNotifier();
      expect(n.state.autoScanOnReconnect, isTrue);
      await pumpSettings(tester, n);
      // Toggle off via the first SwitchListTile.
      await tester.tap(find.byType(Switch).first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(n.state.autoScanOnReconnect, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders under disableAnimations', (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            proxyListProvider.overrideWith((ref) => settingsNotifier())
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(disableAnimations: true),
                child: SettingsScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('CONNECTION'), findsOneWidget);
      expect(find.text('Check for updates'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SettingsScreen about section', () {
    Future<void> pumpTallAbout(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            proxyListProvider.overrideWith((ref) => settingsNotifier())
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 800));
    }

    testWidgets('privacy dialog renders its content', (tester) async {
      await pumpTallAbout(tester);
      await tester.tap(find.text('Privacy'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Privacy at a glance'), findsOneWidget);
      expect(find.textContaining('no analytics, no accounts'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('security and licenses rows removed (v0.1.0 cleanup)',
        (tester) async {
      await pumpTallAbout(tester);
      expect(find.text('Security'), findsNothing);
      expect(find.text('Open-source licenses'), findsNothing);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Open source (MIT)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('failed external link shows a snackbar', (tester) async {
      const channel =
          MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => false,
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      await pumpTallAbout(tester);
      await tester.tap(find.text('Open source (MIT)'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Could not open the link.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('licenses row removed', (tester) async {
      await pumpSettings(tester, settingsNotifier());
      expect(find.text('Open-source licenses'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
