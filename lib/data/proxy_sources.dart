class ProxySource {
  final String name;
  final String url;
  final String format;
  final int weight;

  const ProxySource({
    required this.name,
    required this.url,
    this.format = 'auto',
    this.weight = 1,
  });
}

class ProxySources {
  ProxySources._();

  static const List<ProxySource> primary = [
    ProxySource(
      name: 'SoliSpirit',
      url:
          'https://raw.githubusercontent.com/SoliSpirit/mtproto/master/all_proxies.txt',
      weight: 5,
    ),
    ProxySource(
      name: 'kort0881-all',
      url:
          'https://raw.githubusercontent.com/kort0881/telegram-proxy-collector/main/proxy_all.txt',
      weight: 5,
    ),
    ProxySource(
      name: 'kort0881-eu',
      url:
          'https://raw.githubusercontent.com/kort0881/telegram-proxy-collector/main/proxy_eu.txt',
      weight: 4,
    ),
    ProxySource(
      name: 'kort0881-ru',
      url:
          'https://raw.githubusercontent.com/kort0881/telegram-proxy-collector/main/proxy_ru.txt',
      weight: 4,
    ),
    ProxySource(
      name: 'Grim1313',
      url:
          'https://raw.githubusercontent.com/Grim1313/mtproto-for-telegram/master/all_proxies.txt',
      weight: 5,
    ),
    ProxySource(
      name: 'iwh3n',
      url:
          'https://raw.githubusercontent.com/iwh3n/tg-proxy/main/proxys/All_Proxys.txt',
      weight: 3,
    ),
    ProxySource(
      name: 'ALIILAPRO',
      url:
          'https://raw.githubusercontent.com/ALIILAPRO/MTProtoProxy/main/mtproto.txt',
      weight: 3,
    ),
  ];

  static const List<ProxySource> fallback = [
    ProxySource(
      name: 'SoliSpirit-mirror',
      url:
          'https://cdn.jsdelivr.net/gh/SoliSpirit/mtproto@master/all_proxies.txt',
      weight: 2,
    ),
    ProxySource(
      name: 'Grim1313-HTML',
      url:
          'https://raw.githubusercontent.com/Grim1313/mtproto-for-telegram/master/all_proxies.html',
      format: 'html',
      weight: 2,
    ),
  ];

  static List<ProxySource> get all => [...primary, ...fallback];

  static int trustBonusFor(String sourceName) {
    for (final s in all) {
      if (s.name == sourceName) return s.weight * 2;
    }
    return 0;
  }
}
