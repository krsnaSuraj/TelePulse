import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters.dart';
import '../core/haptics.dart';
import '../core/theme/app_theme.dart';
import '../models/proxy_model.dart';
import '../providers/proxy_list_provider.dart';
import '../services/deep_link_service.dart';
import 'proxy_actions.dart';
import 'status_badge.dart';
import 'tilt_card.dart';

class ProxyTile extends ConsumerStatefulWidget {
  final ProxyModel proxy;

  const ProxyTile({super.key, required this.proxy});

  @override
  ConsumerState<ProxyTile> createState() => _ProxyTileState();
}

class _ProxyTileState extends ConsumerState<ProxyTile> {
  bool _launching = false;

  ProxyModel get _proxy => widget.proxy;

  Future<void> _onTap() async {
    if (_launching) return;
    final proxy = widget.proxy;
    // Gate dead/untested taps: firing tg:// on a dead proxy makes
    // Telegram hang on "Connecting..." — the #1 1-star generator.
    if (mounted && (proxy.isUntested || !proxy.isAlive)) {
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(proxy.isUntested ? 'Not tested yet' : 'Not responding'),
          content: Text(
            proxy.isUntested
                ? 'This proxy has never been tested. Connect anyway or test first?'
                : 'This proxy failed the last check and will likely hang on "Connecting..." in Telegram. Test again or connect anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'test'),
              child: const Text('Test'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'connect'),
              child: const Text('Connect anyway'),
            ),
          ],
        ),
      );
      if (action == null || action == 'cancel') return;
      if (action == 'test') {
        if (!mounted) return;
        try {
          AppHaptics.light();
        } catch (_) {}
        _showSnack('Testing ${proxy.server}…');
        await ref.read(proxyListProvider.notifier).retestSingle(proxy);
        return;
      }
      // 'connect' falls through to launch below.
    }
    _launching = true;
    try {
      AppHaptics.light();

      final notifier = ref.read(proxyListProvider.notifier);
      final result = await notifier.connectToProxy(proxy);

      if (!mounted) return;

      switch (result) {
        case DeepLinkResult.opened:
          AppHaptics.success();
          _showSnack(
            proxy.mtpVerified
                ? 'Opening ${proxy.server} in Telegram…'
                : 'Opening ${proxy.server} in Telegram… (TCP-only, not handshake-verified)',
          );
          break;
        case DeepLinkResult.fallbackOpened:
          _showSnack('Opened via t.me link — tap "Connect" in Telegram.');
          break;
        case DeepLinkResult.copiedToClipboard:
          AppHaptics.error();
          _showSnack('Telegram not found. Link copied to clipboard.');
          break;
        case DeepLinkResult.failed:
          AppHaptics.error();
          _showSnackWithCopy('Could not open Telegram.', proxy);
          break;
      }

      unawaited(Future<void>(() => notifier.retestSingle(proxy)));
    } finally {
      _launching = false;
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ));
  }

  void _showSnackWithCopy(String message, ProxyModel proxy) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Copy link',
          onPressed: () async {
            await ref
                .read(proxyListProvider.notifier)
                .deepLink
                .copyToClipboard(proxy.proxyLink);
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final alive = _proxy.isAlive;

    return Pressable(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: alive
                ? [
                    AppColors.alive.withValues(alpha: 0.10),
                    AppColors.surfaceCard,
                    AppColors.surfaceCard,
                  ]
                : [
                    AppColors.surfaceCard,
                    AppColors.surfaceCard,
                  ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: alive
                ? AppColors.alive.withValues(alpha: 0.25)
                : AppColors.surfaceBorder,
            width: 1,
          ),
          boxShadow: alive
              ? [
                  BoxShadow(
                    color: AppColors.alive.withValues(alpha: 0.08),
                    blurRadius: 18,
                    spreadRadius: -6,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _onTap,
            onLongPress: () => showProxyActions(context, ref, _proxy),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _buildLeading(alive),
                  const SizedBox(width: 12),
                  Expanded(child: _buildInfo()),
                  const SizedBox(width: 8),
                  StatusBadge(proxy: _proxy),
                  _buildFavoriteButton(),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, size: 18),
                    tooltip: 'More actions',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showProxyActions(context, ref, _proxy),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeading(bool alive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: alive
            ? AppColors.alive.withValues(alpha: 0.12)
            : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: alive
            ? Border.all(color: AppColors.alive.withValues(alpha: 0.25))
            : null,
      ),
      child: Icon(
        alive ? Icons.shield_rounded : Icons.shield_outlined,
        color: alive ? AppColors.alive : AppColors.textMuted,
        size: 20,
      ),
    );
  }

  Widget _buildInfo() {
    final region = regionFromSource(_proxy.source);
    final age = timeAgoShort(_proxy.lastChecked);
    return Semantics(
      container: true,
      label:
          'Proxy ${_proxy.server} port ${_proxy.port}, ${aliveDescription()}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  _proxy.server,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              ProtocolChip(type: _proxy.protocolType),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            [
              ':${_proxy.port}',
              if (region.isNotEmpty) region,
              'checked $age',
              _proxy.source,
            ].where((s) => s.isNotEmpty).join('  ·  '),
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textMuted,
              letterSpacing: 0.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String aliveDescription() {
    if (_proxy.isUntested) return 'not tested yet';
    if (!_proxy.isAlive) return 'not responding';
    return '${_proxy.latencyMs} milliseconds latency';
  }

  Widget _buildFavoriteButton() {
    return IconButton(
      icon: Icon(
        _proxy.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
        size: 22,
        color: _proxy.isFavorite ? AppColors.favorite : AppColors.textMuted,
      ),
      tooltip:
          _proxy.isFavorite ? 'Remove from favorites' : 'Add to favorites',
      visualDensity: VisualDensity.standard,
      onPressed: () {
        AppHaptics.selection();
        ref.read(proxyListProvider.notifier).toggleFavorite(_proxy);
      },
    );
  }
}
