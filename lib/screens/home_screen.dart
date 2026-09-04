import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/haptics.dart';
import '../core/theme/app_theme.dart';
import '../models/proxy_model.dart';
import '../providers/proxy_list_provider.dart';
import '../widgets/animated_status_orb.dart';
import '../widgets/aurora_background.dart';
import '../widgets/brand_mark.dart';
import '../widgets/glass_card.dart';
import '../widgets/notice_banner.dart';
import '../widgets/proxy_tile.dart';
import '../widgets/radar_scope.dart';
import '../widgets/state_views.dart';
import '../widgets/tilt_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(proxyListProvider);
    final notifier = ref.read(proxyListProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(size: 22),
            SizedBox(width: 8),
            Text('TelePulse'),
          ],
        ),
        actions: [
          if (state.isFetching)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: AuroraBackground(
        child: switch (state.loadState) {
          ProxyLoadState.initial ||
          ProxyLoadState.loading => const LoadingView(),
          ProxyLoadState.error => StateMessage(
            icon: Icons.error_outline_rounded,
            iconColor: AppColors.dead,
            title: 'Something went wrong',
            message: state.errorMessage.isEmpty
                ? 'TelePulse could not complete the last action.'
                : state.errorMessage,
            actionLabel: 'Try again',
            onAction: () {
              AppHaptics.light();
              notifier.refreshProxies();
            },
          ),
          ProxyLoadState.noInternet => const StateMessage(
            icon: Icons.wifi_off_rounded,
            iconColor: AppColors.warn,
            title: 'You are offline',
            message:
                'Connect to the internet and TelePulse will start scanning automatically.',
          ),
          ProxyLoadState.noProxies => StateMessage(
            icon: Icons.search_rounded,
            iconColor: AppColors.signal,
            title: 'No proxies found',
            message:
                'All sources responded empty. Tap below to scan again, or add your own source in Settings.',
            actionLabel: 'Scan Now',
            onAction: () {
              AppHaptics.light();
              notifier.refreshProxies();
            },
          ),
          ProxyLoadState.ready || ProxyLoadState.testing => _Dashboard(state),
        },
      ),
    );
  }
}

class _Dashboard extends ConsumerStatefulWidget {
  final ProxyListState state;
  const _Dashboard(this.state);

  @override
  ConsumerState<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<_Dashboard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  int _blipLength = -1;
  String _blipEdgeKeys = '';
  List<RadarBlip> _blips = const [];

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  List<RadarBlip> _memoBlips(List<ProxyModel> proxies) {
    final edgeKeys = proxies.isEmpty
        ? ''
        : '${proxies.first.key}|${proxies.last.key}';
    if (_blipLength != proxies.length || _blipEdgeKeys != edgeKeys) {
      _blipLength = proxies.length;
      _blipEdgeKeys = edgeKeys;
      _blips = layoutRadarBlips(proxies);
    }
    return _blips;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final notifier = ref.read(proxyListProvider.notifier);
    final top = notifier.topProxies(count: 5);
    final proxies = state.proxies;

    if (proxies.isEmpty) {
      return const StateMessage(
        icon: Icons.search_rounded,
        iconColor: AppColors.signal,
        title: 'No proxies yet',
        message: 'Pull down to scan proxy sources.',
      );
    }

    var order = 0;
    var animated = 0;
    Widget step(Widget child) {
      if (animated >= 10) return child;
      animated++;
      return _Entrance(index: order++, animation: _entrance, child: child);
    }

    return RefreshIndicator(
      color: AppColors.signal,
      backgroundColor: AppColors.surfaceCard,
      onRefresh: () => notifier.refreshProxies(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: 4,
          bottom:
              16 +
              kBottomNavigationBarHeight +
              MediaQuery.of(context).padding.bottom,
        ),
        children: [
          for (final banner in _banners()) step(banner),
          step(_RadarHeroCard(state: state, blips: _memoBlips(proxies))),
          const SizedBox(height: 20),
          if (top.isNotEmpty) ...[
            step(
              _SectionHeader(
                icon: Icons.bolt_rounded,
                title: 'RECOMMENDED NOW',
                trailing: '${top.length} working picks',
              ),
            ),
            const SizedBox(height: 6),
            for (final p in top)
              step(ProxyTile(key: ValueKey(p.key), proxy: p)),
            const SizedBox(height: 20),
          ],
          ...(() {
            final topKeys = {for (final p in top) p.key};
            final rest = proxies
                .where((p) => !topKeys.contains(p.key))
                .take(10)
                .toList(growable: false);
            if (rest.isEmpty) return <Widget>[];
            return <Widget>[
              step(
                const _SectionHeader(
                  icon: Icons.list_rounded,
                  title: 'ALL PROXIES',
                ),
              ),
              const SizedBox(height: 6),
              for (final p in rest)
                step(ProxyTile(key: ValueKey('home-${p.key}'), proxy: p)),
              step(
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(currentTabProvider.notifier).state = 1,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text('View all ${proxies.length} proxies'),
                  ),
                ),
              ),
            ];
          })(),
        ],
      ),
    );
  }

  List<Widget> _banners() {
    switch (widget.state.notice) {
      case NoticeKind.offline:
        return const [
          NoticeBanner(
            message:
                'You are offline — showing last known results. Scanning resumes automatically.',
            icon: Icons.wifi_off_rounded,
            color: AppColors.warn,
          ),
        ];
      case NoticeKind.staleCache:
        return const [
          NoticeBanner(
            message:
                'Proxy sources are unreachable right now — showing cached results.',
            icon: Icons.history_rounded,
            color: AppColors.warn,
          ),
        ];
      case NoticeKind.refreshFailed:
        return const [
          NoticeBanner(
            message: 'Could not reach some sources. Pull down to retry.',
            icon: Icons.cloud_off_rounded,
            color: AppColors.warn,
          ),
        ];
      case NoticeKind.mobilePaused:
        return const [
          NoticeBanner(
            message:
                'Auto-scan is paused on mobile data. Pull down to scan now, or allow it in Settings.',
            icon: Icons.signal_cellular_alt_rounded,
            color: AppColors.signal,
          ),
        ];
      case NoticeKind.none:
        return const [];
    }
  }
}

class _Entrance extends StatelessWidget {
  final int index;
  final Animation<double> animation;
  final Widget child;

  const _Entrance({
    required this.index,
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.06).clamp(0.0, 0.6);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(
        start,
        (start + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, 22 * (1 - curved.value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _RadarHeroCard extends StatelessWidget {
  final ProxyListState state;
  final List<RadarBlip> blips;
  const _RadarHeroCard({required this.state, required this.blips});

  @override
  Widget build(BuildContext context) {
    final testing = state.isTesting;
    final alive = state.aliveCount;
    final total = state.proxies.length;

    final statusText = testing
        ? 'SCANNING'
        : alive > 0
        ? 'ONLINE'
        : total == 0
        ? 'IDLE'
        : 'NO PROXIES';
    final color = testing
        ? AppColors.signal
        : alive > 0
        ? AppColors.alive
        : AppColors.warn;

    return TiltCard(
      child: GlassCard(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        borderColor: color.withValues(alpha: 0.25),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                RadarScope(blips: blips, sweeping: testing, size: 148),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: color.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        testing
                            ? 'Testing ${state.testedCount}/${state.totalToTest}'
                            : '$alive working · $total found',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: color,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        testing
                            ? 'Validating proxies in parallel…'
                            : state.untestedCount > 0
                            ? '${state.untestedCount} waiting to be checked'
                            : _avgLine(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AnimatedStatusOrb(
                        isOnline: alive > 0,
                        isTesting: testing,
                        aliveCount: alive,
                        totalCount: total,
                        size: 34,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (testing) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: state.totalToTest == 0
                      ? null
                      : (state.testedCount / state.totalToTest).clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: AppColors.surfaceBorder,
                  color: AppColors.signal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _avgLine() {
    if (state.aliveCount == 0) return 'No working proxies yet';
    final avg = state.avgLatency;
    return avg > 0
        ? 'Average latency ${avg.toStringAsFixed(0)}ms'
        : 'Latency being measured…';
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Flexible(
              child: Text(
                trailing!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.alive,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
