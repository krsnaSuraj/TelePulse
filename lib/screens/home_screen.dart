import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../models/proxy_model.dart';
import '../providers/proxy_list_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_status_orb.dart';
import '../widgets/glass_card.dart';
import '../widgets/proxy_shimmer.dart';
import '../widgets/proxy_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyAsync = ref.watch(proxyListProvider);
    final notifier = ref.read(proxyListProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_rounded, size: 22, color: AppColors.primary),
            SizedBox(width: 8),
            Text('TelePulse'),
          ],
        ),
        actions: [
          if (notifier.isFetching)
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
      body: proxyAsync.when(
        loading: () => const ProxyShimmer(),
        error: (e, _) => _ErrorState(
          message: e.toString(),
          onRetry: () => notifier.refreshProxies(),
        ),
        data: (proxies) => _ContentState(
          proxies: proxies,
          notifier: notifier,
          isTesting: notifier.isTesting,
          testedCount: notifier.testedCount,
          totalProxies: notifier.totalProxies,
          onViewAll: () =>
              ref.read(currentTabProvider.notifier).state = 1,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.dead.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 32,
                color: AppColors.dead,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Connection Failed',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContentState extends StatefulWidget {
  final List<ProxyModel> proxies;
  final ProxyListNotifier notifier;
  final bool isTesting;
  final int testedCount;
  final int totalProxies;
  final VoidCallback onViewAll;

  const _ContentState({
    required this.proxies,
    required this.notifier,
    required this.isTesting,
    required this.testedCount,
    required this.totalProxies,
    required this.onViewAll,
  });

  @override
  State<_ContentState> createState() => _ContentStateState();
}

class _ContentStateState extends State<_ContentState>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOut,
    );
    _animCtrl.forward();
  }

  @override
  void didUpdateWidget(_ContentState old) {
    super.didUpdateWidget(old);
    if (old.proxies != widget.proxies) {
      _animCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.proxies.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.search_rounded,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No Proxies Found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pull down to refresh and scan\nproxy sources again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => widget.notifier.refreshProxies(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Scan Now'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final topProxies = widget.notifier.topProxies(count: 5);
    final aliveCount = widget.notifier.aliveProxies.length;
    final totalCount = widget.proxies.length;

    return FadeTransition(
      opacity: _fadeAnim,
      child: RefreshIndicator(
        onRefresh: () => widget.notifier.refreshProxies(),
        color: AppColors.primary,
        child: ListView(
          padding: const EdgeInsets.only(top: 12, bottom: 100),
          children: [
            _StatusHeader(
              alive: aliveCount,
              total: totalCount,
              isTesting: widget.isTesting,
              testedCount: widget.testedCount,
              totalProxies: widget.totalProxies,
            ),
            const SizedBox(height: 16),
            if (topProxies.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.speed_rounded,
                title: 'Fastest Proxies',
                count: '${topProxies.length} available',
                countColor: AppColors.alive,
              ),
              const SizedBox(height: 4),
              ...topProxies.map((p) => ProxyTile(proxy: p)),
            ],
            if (widget.proxies.length > topProxies.length) ...[
              const SizedBox(height: 16),
              _SectionHeader(
                icon: Icons.list_rounded,
                title: 'All Proxies',
                count: '$totalCount total',
                countColor: AppColors.textMuted,
              ),
              const SizedBox(height: 4),
              ...widget.proxies.take(15).map((p) => ProxyTile(proxy: p)),
              if (widget.proxies.length > 15)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton(
                    onPressed: widget.onViewAll,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.surfaceBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('View All Proxies'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final int alive;
  final int total;
  final bool isTesting;
  final int testedCount;
  final int totalProxies;

  const _StatusHeader({
    required this.alive,
    required this.total,
    required this.isTesting,
    required this.testedCount,
    required this.totalProxies,
  });

  @override
  Widget build(BuildContext context) {
    final isOnline = alive > 0;

    final statusText = isTesting
        ? 'SCANNING'
        : isOnline
            ? 'ONLINE'
            : 'OFFLINE';
    final statusColor = isTesting
        ? AppColors.terminalGreen
        : isOnline
            ? AppColors.alive
            : AppColors.warning;
    final bgColor = isTesting
        ? AppColors.terminalGreen.withValues(alpha: 0.12)
        : isOnline
            ? AppColors.alive.withValues(alpha: 0.12)
            : AppColors.warning.withValues(alpha: 0.12);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassCard(
        borderColor: isOnline
            ? AppColors.alive.withValues(alpha: 0.2)
            : AppColors.surfaceBorder,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            AnimatedStatusOrb(
              isOnline: isOnline || isTesting,
              aliveCount: alive,
              totalCount: total,
              isTesting: isTesting,
              size: 56,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Proxy Status',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isTesting
                        ? 'Testing $testedCount of $totalProxies\u2026'
                        : '$alive working \u00b7 $total total',
                    style: TextStyle(
                      color: isTesting
                          ? AppColors.terminalGreen
                          : AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String count;
  final Color countColor;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.countColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          Text(
            count,
            style: TextStyle(
              fontSize: 11,
              color: countColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
