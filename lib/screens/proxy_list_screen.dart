import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/proxy_model.dart';
import '../providers/proxy_list_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/proxy_tile.dart';

class ProxyListScreen extends ConsumerStatefulWidget {
  const ProxyListScreen({super.key});

  @override
  ConsumerState<ProxyListScreen> createState() => _ProxyListScreenState();
}

class _ProxyListScreenState extends ConsumerState<ProxyListScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  Object? _lastDataId;

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
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final proxyAsync = ref.watch(proxyListProvider);
    final notifier = ref.read(proxyListProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_rounded, size: 18, color: AppColors.primary),
            SizedBox(width: 8),
            Text('All Proxies'),
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
          if (!notifier.isTesting && proxyAsync.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.replay_rounded, size: 20),
              tooltip: 'Re-test All',
              onPressed: () => notifier.testProxies(),
            ),
        ],
      ),
      body: proxyAsync.when(
        loading: () => const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
        error: (e, _) => _buildError(context, notifier, e),
        data: (proxies) {
          if (proxies.isEmpty) {
            return _buildEmpty(context, notifier);
          }

          final dataId = Object.hashAll(proxies.take(10).map((p) => p.hashCode));
          if (_lastDataId != dataId) {
            _lastDataId = dataId;
            _animCtrl.forward(from: 0);
          }

          return RefreshIndicator(
            onRefresh: () => notifier.refreshProxies(),
            color: AppColors.primary,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: _buildProxyList(proxies, notifier),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProxyList(List<ProxyModel> proxies, ProxyListNotifier notifier) {
    return Column(
      children: [
        if (notifier.isTesting)
          _TestingProgress(
            testedCount: notifier.testedCount,
            totalProxies: notifier.totalProxies,
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 12, bottom: 100),
            itemCount: proxies.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                final headerText = notifier.isTesting
                    ? 'Testing ${notifier.testedCount}/${notifier.totalProxies}\u2026'
                    : '${proxies.length} proxies \u00b7 ${notifier.aliveProxies.length} alive';
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          headerText,
                          style: TextStyle(
                            color: notifier.isTesting
                                ? AppColors.terminalGreen
                                : AppColors.textMuted,
                            fontSize: 12,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      if (notifier.isTesting)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.terminalGreen,
                          ),
                        ),
                    ],
                  ),
                );
              }
              return ProxyTile(proxy: proxies[index - 1]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context, ProxyListNotifier notifier) {
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
              'No Proxies Available',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try refreshing proxy sources.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => notifier.refreshProxies(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
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

  Widget _buildError(
      BuildContext context, ProxyListNotifier notifier, Object e) {
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
              'Something went wrong',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              e.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => notifier.refreshProxies(),
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

class _TestingProgress extends StatelessWidget {
  final int testedCount;
  final int totalProxies;

  const _TestingProgress({
    required this.testedCount,
    required this.totalProxies,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalProxies > 0 ? testedCount / totalProxies : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Container(
          height: 4,
          color: AppColors.surfaceBorder,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.terminalGreen.withValues(alpha: 0.4),
                    AppColors.terminalGreen,
                  ],
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
