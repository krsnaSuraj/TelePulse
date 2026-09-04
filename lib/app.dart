import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import 'core/theme/app_theme.dart';
import 'providers/proxy_list_provider.dart';
import 'screens/home_screen.dart';
import 'screens/proxies_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/launch_intro.dart';

final currentTabProvider = StateProvider<int>((ref) => 0);

class TelePulseApp extends StatelessWidget {
  const TelePulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TelePulse',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const LaunchIntro(
          child: _FlushOnBackground(child: MainShell())),
    );
  }
}

class _FlushOnBackground extends ConsumerStatefulWidget {
  final Widget child;
  const _FlushOnBackground({required this.child});

  @override
  ConsumerState<_FlushOnBackground> createState() =>
      _FlushOnBackgroundState();
}

class _FlushOnBackgroundState extends ConsumerState<_FlushOnBackground>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(ref.read(proxyListProvider.notifier).flushCache());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(currentTabProvider);

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: [
          TickerMode(enabled: currentIndex == 0, child: const HomeScreen()),
          TickerMode(
              enabled: currentIndex == 1, child: const ProxiesScreen()),
          TickerMode(
              enabled: currentIndex == 2, child: const SettingsScreen()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) =>
            ref.read(currentTabProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns_rounded),
            label: 'Proxies',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
