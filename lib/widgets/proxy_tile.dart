import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/proxy_model.dart';
import '../providers/proxy_list_provider.dart';
import '../services/deep_link_service.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import 'status_badge.dart';

class ProxyTile extends ConsumerStatefulWidget {
  final ProxyModel proxy;

  const ProxyTile({super.key, required this.proxy});

  @override
  ConsumerState<ProxyTile> createState() => _ProxyTileState();
}

class _ProxyTileState extends ConsumerState<ProxyTile> {
  bool _isConnecting = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.proxy.isAlive
              ? AppColors.alive.withValues(alpha: 0.2)
              : AppColors.surfaceBorder,
          width: 0.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _onTap,
        onLongPress: _copyProxyLink,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _buildLeading(),
              const SizedBox(width: 12),
              Expanded(child: _buildInfo(theme)),
              const SizedBox(width: 8),
              StatusBadge(
                isAlive: widget.proxy.isAlive,
                latencyMs: widget.proxy.latencyMs,
              ),
              const SizedBox(width: 4),
              _buildFavoriteButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeading() {
    final alive = widget.proxy.isAlive;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: alive
            ? AppColors.alive.withValues(alpha: 0.1)
            : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: alive
            ? Border.all(
                color: AppColors.alive.withValues(alpha: 0.2), width: 0.5)
            : null,
      ),
      child: _isConnecting
          ? const Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            )
          : Icon(
              alive ? Icons.shield_rounded : Icons.shield_outlined,
              color: alive ? AppColors.alive : AppColors.textMuted,
              size: 20,
            ),
    );
  }

  Widget _buildInfo(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.proxy.displayServer,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          '${widget.proxy.port}  ·  ${widget.proxy.source}',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
            letterSpacing: 0.1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildFavoriteButton() {
    return IconButton(
      icon: Icon(
        widget.proxy.isFavorite
            ? Icons.star_rounded
            : Icons.star_outline_rounded,
        size: 18,
        color:
            widget.proxy.isFavorite ? AppColors.favorite : AppColors.textMuted,
      ),
      tooltip: widget.proxy.isFavorite
          ? 'Remove from favorites'
          : 'Add to favorites',
      onPressed: () {
        AppHaptics.selection();
        ref.read(proxyListProvider.notifier).toggleFavorite(widget.proxy);
      },
      visualDensity: VisualDensity.compact,
    );
  }

  void _copyProxyLink() {
    AppHaptics.light();
    Clipboard.setData(ClipboardData(text: widget.proxy.proxyLink));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied: ${widget.proxy.displayServer}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onTap() async {
    final notifier = ref.read(proxyListProvider.notifier);
    AppHaptics.light();

    await notifier.didTapProxy(widget.proxy);

    setState(() => _isConnecting = true);
    await notifier.testSingleProxy(widget.proxy);
    if (!mounted) return;
    setState(() => _isConnecting = false);

    final result = await notifier.connectToProxy(widget.proxy);
    if (!mounted) return;

    final (message, isSuccess) = switch (result) {
      DeepLinkResult.opened => ('Opening ${widget.proxy.displayServer}...', true),
      DeepLinkResult.appNotInstalled => (
        'Telegram not installed. Proxy copied to clipboard. Download from telegram.org',
        false,
      ),
      DeepLinkResult.webBlocked => (
        'Web Telegram may be restricted in your region',
        false,
      ),
      DeepLinkResult.failed => (
        'Could not open Telegram. Try installing it first',
        false,
      ),
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
