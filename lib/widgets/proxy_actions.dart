import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/haptics.dart';
import '../core/theme/app_theme.dart';
import '../models/proxy_model.dart';
import '../providers/proxy_list_provider.dart';
import '../services/deep_link_service.dart';

Future<void> showProxyActions(
  BuildContext context,
  WidgetRef ref,
  ProxyModel proxy,
) async {
  AppHaptics.selection();
  final notifier = ref.read(proxyListProvider.notifier);
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surfaceOverlay,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${proxy.server}:${proxy.port}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _ActionTile(
              icon: Icons.open_in_new_rounded,
              label: 'Open in Telegram',
              onTap: () => Navigator.pop(sheetContext, 'open'),
            ),
            _ActionTile(
              icon: Icons.copy_rounded,
              label: 'Copy proxy link',
              onTap: () => Navigator.pop(sheetContext, 'copy'),
            ),
            _ActionTile(
              icon: Icons.speed_rounded,
              label: 'Test again',
              onTap: () => Navigator.pop(sheetContext, 'test'),
            ),
            _ActionTile(
              icon: proxy.isFavorite
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              label: proxy.isFavorite
                  ? 'Remove from favorites'
                  : 'Add to favorites',
              color: proxy.isFavorite
                  ? AppColors.favorite
                  : AppColors.textPrimary,
              onTap: () => Navigator.pop(sheetContext, 'favorite'),
            ),
          ],
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'open':
      await _openFromSheet(context, ref, proxy);
      break;
      case 'copy':
        final copied =
            await notifier.deepLink.copyToClipboard(proxy.proxyLink);
        if (!context.mounted) return;
        _snack(
            context,
            copied
                ? 'Link copied to clipboard'
                : 'Copy failed — open this menu again to retry');
        break;
    case 'test':
      unawaited(notifier.retestSingle(proxy));
      _snack(context, 'Testing ${proxy.server}…');
      break;
    case 'favorite':
      unawaited(notifier.toggleFavorite(proxy));
      break;
    default:
      _snack(context, 'Unknown action.');
      break;
  }
}

Future<void> _openFromSheet(
  BuildContext context,
  WidgetRef ref,
  ProxyModel proxy,
) async {
  final notifier = ref.read(proxyListProvider.notifier);
  final result = await notifier.connectToProxy(proxy);
  unawaited(notifier.retestSingle(proxy));
  if (!context.mounted) return;
  switch (result) {
    case DeepLinkResult.opened:
      _snack(context, 'Opening ${proxy.server} in Telegram…');
      break;
    case DeepLinkResult.fallbackOpened:
      _snack(context, 'Opened via t.me link — tap "Connect" in Telegram.');
      break;
    case DeepLinkResult.copiedToClipboard:
      _snack(context, 'Telegram not found. Link copied to clipboard.');
      break;
    case DeepLinkResult.failed:
      _snack(context, 'Could not open Telegram.');
      break;
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
    ));
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20, color: color),
      title: Text(label, style: TextStyle(fontSize: 14, color: color)),
      onTap: onTap,
    );
  }
}
