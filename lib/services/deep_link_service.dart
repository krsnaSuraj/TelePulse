import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/proxy_model.dart';

enum DeepLinkResult { opened, appNotInstalled, webBlocked, failed }

class DeepLinkService {
  Future<DeepLinkResult> connectWithProxy(ProxyModel proxy) async {
    final tgUri = _buildProxyUri(proxy);

    if (tgUri != null) {
      try {
        final launched =
            await launchUrl(tgUri, mode: LaunchMode.externalApplication);
        if (launched) return DeepLinkResult.opened;
      } catch (_) {}
    }

    try {
      final tmeUri = Uri.parse(proxy.tmeLink);
      final launched =
          await launchUrl(tmeUri, mode: LaunchMode.externalApplication);
      if (launched) return DeepLinkResult.opened;
    } catch (_) {}

    try {
      final webUri = Uri.parse('https://web.telegram.org');
      if (await launchUrl(webUri, mode: LaunchMode.externalApplication)) {
        return DeepLinkResult.webBlocked;
      }
    } catch (_) {}

    await _copyToClipboard(proxy);
    return DeepLinkResult.appNotInstalled;
  }

  Future<void> _copyToClipboard(ProxyModel proxy) async {
    try {
      await Clipboard.setData(ClipboardData(
        text: proxy.proxyLink,
      ));
    } catch (_) {}
  }

  Uri? _buildProxyUri(ProxyModel proxy) {
    try {
      return Uri.parse(proxy.proxyLink);
    } catch (_) {
      return null;
    }
  }

}
