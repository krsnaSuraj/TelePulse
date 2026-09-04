import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/proxy_model.dart';

enum DeepLinkResult { opened, fallbackOpened, copiedToClipboard, failed }

class DeepLinkService {
  Future<DeepLinkResult> connectWithProxy(ProxyModel proxy) async {
    try {
      final tgUri = Uri.parse(proxy.proxyLink);
      if (await launchUrl(tgUri, mode: LaunchMode.externalApplication)) {
        return DeepLinkResult.opened;
      }
    } catch (_) {}

    try {
      final tmeUri = Uri.parse(proxy.tmeLink);
      if (await launchUrl(tmeUri, mode: LaunchMode.externalApplication)) {
        return DeepLinkResult.fallbackOpened;
      }
    } catch (_) {}

    final copied = await copyToClipboard(proxy.proxyLink);
    return copied ? DeepLinkResult.copiedToClipboard : DeepLinkResult.failed;
  }

  Future<bool> copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {
      return false;
    }
  }
}
