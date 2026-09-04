import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/haptics.dart';
import '../core/theme/app_theme.dart';
import '../models/proxy_model.dart';
import '../models/proxy_view.dart';
import '../providers/proxy_list_provider.dart';
import '../widgets/notice_banner.dart';
import '../widgets/proxy_shimmer.dart';
import '../widgets/proxy_tile.dart';

class ProxiesScreen extends ConsumerStatefulWidget {
  const ProxiesScreen({super.key});

  @override
  ConsumerState<ProxiesScreen> createState() => _ProxiesScreenState();
}

class _ProxiesScreenState extends ConsumerState<ProxiesScreen>
    with SingleTickerProviderStateMixin {
  ProxyFilter _filter = ProxyFilter.all;
  ProxySort _sort = ProxySort.rank;
  String _query = '';
  bool _searchVisible = false;
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    // Single shared bounded controller (home pattern): first ~10 rows only.
    // Muted while this tab is hidden (TickerMode) — resumes on show.
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  List<ProxyModel> _applyView(ProxyListState state) {
    return applyProxyView(
      state.proxies,
      filter: _filter,
      sort: _sort,
      query: _query,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(proxyListProvider);
    final notifier = ref.read(proxyListProvider.notifier);

    final body = switch (state.loadState) {
      ProxyLoadState.initial || ProxyLoadState.loading => const ProxyShimmer(),
      ProxyLoadState.error => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              state.errorMessage.isEmpty
                  ? 'Something went wrong.'
                  : state.errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
      ProxyLoadState.noInternet => _message(
        Icons.wifi_off_rounded,
        'You are offline',
        'Reconnect and the scan will resume automatically.',
      ),
      ProxyLoadState.noProxies => _message(
        Icons.inbox_rounded,
        'Nothing here yet',
        'Pull down or open Home to scan for proxies.',
      ),
      ProxyLoadState.ready ||
      ProxyLoadState.testing => _buildList(context, state, notifier),
    };

    return PopScope(
      canPop: !_searchVisible,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _searchVisible) {
          setState(() {
            _searchVisible = false;
            _query = '';
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Proxies'),
          actions: [
            IconButton(
              // Micro-interaction: icon cross-fades/scales on toggle.
              // Same tap, same state change — pure motion.
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  _searchVisible
                      ? Icons.search_off_rounded
                      : Icons.search_rounded,
                  key: ValueKey<bool>(_searchVisible),
                ),
              ),
              tooltip: 'Search',
              onPressed: () {
                AppHaptics.selection();
                setState(() {
                  _searchVisible = !_searchVisible;
                  if (!_searchVisible) _query = '';
                });
              },
            ),
            PopupMenuButton<ProxySort>(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.sort_rounded),
                  if (_sort != ProxySort.rank)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.signal,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              tooltip: 'Sort by',
              onSelected: (s) {
                AppHaptics.selection();
                setState(() => _sort = s);
              },
              itemBuilder: (_) => [
                for (final s in ProxySort.values)
                  PopupMenuItem(
                    value: s,
                    child: Row(
                      children: [
                        Icon(
                          s == _sort
                              ? Icons.check_rounded
                              : Icons.circle_outlined,
                          size: 16,
                          color: s == _sort
                              ? AppColors.signal
                              : AppColors.textFaint,
                        ),
                        const SizedBox(width: 10),
                        Text(s.label),
                      ],
                    ),
                  ),
              ],
            ),
            if (!state.isTesting)
              IconButton(
                icon: const Icon(Icons.replay_rounded),
                tooltip: 'Re-test all',
                onPressed: () {
                  AppHaptics.light();
                  notifier.enqueueTest(state.proxies);
                },
              ),
          ],
          bottom: _searchVisible
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(56),
                  // Entrance motion on expand (mounts once per toggle).
                  child: _SearchEntrance(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: TextField(
                        autofocus: false,
                        textInputAction: TextInputAction.search,
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        onChanged: (v) => setState(() => _query = v.trim()),
                        decoration: InputDecoration(
                          hintText: 'Search server, port or source…',
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 20,
                          ),
                          isDense: true,
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () => setState(() => _query = ''),
                                ),
                        ),
                      ),
                    ),
                  ),
                )
              : null,
        ),
        body: RefreshIndicator(
          color: AppColors.signal,
          backgroundColor: AppColors.surfaceCard,
          displacement: 48,
          strokeWidth: 2.5,
          onRefresh: () => notifier.refreshProxies(),
          child: Column(
            children: [
              if (state.notice == NoticeKind.mobilePaused)
                const _FadeSlideIn(
                  child: NoticeBanner(
                    message:
                        'Auto-scan is paused on mobile data. Pull down to scan now.',
                    icon: Icons.signal_cellular_alt_rounded,
                    color: AppColors.signal,
                  ),
                ),
              if (state.notice == NoticeKind.offline)
                const _FadeSlideIn(
                  child: NoticeBanner(
                    message: 'You are offline — showing last known results.',
                    icon: Icons.wifi_off_rounded,
                    color: AppColors.warn,
                  ),
                ),
              if (state.notice == NoticeKind.staleCache)
                const _FadeSlideIn(
                  child: NoticeBanner(
                    message:
                        'Sources are unreachable — showing cached results.',
                    icon: Icons.history_rounded,
                    color: AppColors.warn,
                  ),
                ),
              if (state.notice == NoticeKind.refreshFailed)
                const _FadeSlideIn(
                  child: NoticeBanner(
                    message: 'Some sources failed. Pull down to retry.',
                    icon: Icons.cloud_off_rounded,
                    color: AppColors.warn,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<ProxyFilter>(
                    segments: [
                      ButtonSegment(
                        value: ProxyFilter.all,
                        label: Text(
                          'All (${state.proxies.length})',
                          overflow: TextOverflow.ellipsis,
                        ),
                        icon: const Icon(Icons.list_rounded, size: 15),
                      ),
                      ButtonSegment(
                        value: ProxyFilter.working,
                        label: Text(
                          'Working (${state.aliveCount})',
                          overflow: TextOverflow.ellipsis,
                        ),
                        icon: const Icon(Icons.bolt_rounded, size: 15),
                      ),
                      ButtonSegment(
                        value: ProxyFilter.favorites,
                        label: Text(
                          'Saved (${state.favoriteCount})',
                          overflow: TextOverflow.ellipsis,
                        ),
                        icon: const Icon(Icons.star_rounded, size: 15),
                      ),
                    ],
                    selected: {_filter},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      AppHaptics.selection();
                      setState(() => _filter = selection.first);
                    },
                  ),
                ),
              ),
              if (state.isTesting)
                _FadeSlideIn(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: state.totalToTest == 0
                                  ? null
                                  : (state.testedCount / state.totalToTest)
                                        .clamp(0.0, 1.0),
                              minHeight: 3,
                              backgroundColor: AppColors.surfaceBorder,
                              color: AppColors.signal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${state.testedCount}/${state.totalToTest}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            color: AppColors.signal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Segment/sort changes cross-fade (keyed without _query so
              // typing stays jank-free). Same list, same taps — pure motion.
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeOut,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: KeyedSubtree(
                    key: ValueKey<String>(
                      '${_filter.name}-${_sort.name}-${state.loadState.name}',
                    ),
                    child: body,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    ProxyListState state,
    ProxyListNotifier notifier,
  ) {
    final view = _applyView(state);

    if (view.isEmpty) {
      final emptyText = switch (_filter) {
        ProxyFilter.working =>
          'No working proxies yet. Wait for the scan to finish or refresh.',
        ProxyFilter.favorites =>
          'No saved proxies. Tap the star on any proxy to pin it here.',
        ProxyFilter.all =>
          _query.isEmpty
              ? 'No proxies loaded yet.'
              : 'No results for “$_query”.',
      };
      return _FadeSlideIn(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Icon(
              _filter == ProxyFilter.favorites
                  ? Icons.star_outline_rounded
                  : Icons.dns_outlined,
              size: 44,
              color: AppColors.textFaint,
            ),
            const SizedBox(height: 14),
            Text(
              emptyText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    // Staggered entrance: header + first ~10 rows share one bounded
    // controller (home pattern). Beyond 10, rows render statically.
    var order = 0;
    var animated = 0;
    Widget step(Widget child) {
      if (animated >= 10) return child;
      animated++;
      return _Stagger(index: order++, animation: _entrance, child: child);
    }

    return ListView.builder(
      padding: EdgeInsets.only(
        top: 8,
        bottom:
            16 +
            kBottomNavigationBarHeight +
            MediaQuery.of(context).padding.bottom,
      ),
      itemCount: view.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return step(
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
              child: Text(
                _headerLine(state, view.length),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11.5,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          );
        }
        final int row = i - 1;
        if (row >= 10) {
          return ProxyTile(key: ValueKey(view[row].key), proxy: view[row]);
        }
        return step(ProxyTile(key: ValueKey(view[row].key), proxy: view[row]));
      },
    );
  }

  String _headerLine(ProxyListState state, int visibleCount) {
    return describeView(
      visible: visibleCount,
      tested: state.proxies.length - state.untestedCount,
      working: state.aliveCount,
      sort: _sort,
      query: _query,
    );
  }

  Widget _message(IconData icon, String title, String subtitle) {
    return _FadeSlideIn(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          Icon(icon, size: 44, color: AppColors.textFaint),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared-controller stagger (mirrors home `_Entrance`): bounded, first ~10.
/// Skips instantly when reduced motion is on so content is never hidden.
class _Stagger extends StatelessWidget {
  final int index;
  final Animation<double> animation;
  final Widget child;

  const _Stagger({
    required this.index,
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final double start = (index * 0.06).clamp(0.0, 0.6);
    final CurvedAnimation curved = CurvedAnimation(
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

/// Bounded 200ms fade+slide for banners, progress, search expand, empties.
/// Mount-only entrance (no exit) keeps pull-to-refresh and tab switches cheap.
class _FadeSlideIn extends StatefulWidget {
  final Widget child;

  const _FadeSlideIn({required this.child});

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double t = Curves.easeOut.transform(
          _controller.value.clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Bounded search-bar expand: 220ms fade + 12px slide on mount.
class _SearchEntrance extends StatefulWidget {
  final Widget child;

  const _SearchEntrance({required this.child});

  @override
  State<_SearchEntrance> createState() => _SearchEntranceState();
}

class _SearchEntranceState extends State<_SearchEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double t = Curves.easeOutCubic.transform(
          _controller.value.clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, -12 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
