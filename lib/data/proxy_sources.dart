class ProxySource {
  final String name;
  final String url;
  final String format;
  final int weight;
  final bool isActive;

  const ProxySource({
    required this.name,
    required this.url,
    this.format = 'auto',
    this.weight = 1,
    this.isActive = true,
  });
}

class ProxySources {
  static const sources = [
    ProxySource(
      name: 'SoliSpirit',
      url: 'https://raw.githubusercontent.com/SoliSpirit/mtproto/master/all_proxies.txt',
      format: 'auto',
      weight: 5,
    ),
    ProxySource(
      name: 'kort0881-all',
      url: 'https://raw.githubusercontent.com/kort0881/telegram-proxy-collector/main/proxy_all.txt',
      format: 'auto',
      weight: 5,
    ),
    ProxySource(
      name: 'kort0881-eu',
      url: 'https://raw.githubusercontent.com/kort0881/telegram-proxy-collector/main/proxy_eu.txt',
      format: 'auto',
      weight: 4,
    ),
    ProxySource(
      name: 'kort0881-ru',
      url: 'https://raw.githubusercontent.com/kort0881/telegram-proxy-collector/main/proxy_ru.txt',
      format: 'auto',
      weight: 4,
    ),
    ProxySource(
      name: 'Grim1313',
      url: 'https://raw.githubusercontent.com/Grim1313/mtproto-for-telegram/master/all_proxies.txt',
      format: 'auto',
      weight: 5,
    ),
    ProxySource(
      name: 'iwh3n',
      url: 'https://raw.githubusercontent.com/iwh3n/tg-proxy/main/proxys/All_Proxys.txt',
      format: 'auto',
      weight: 3,
    ),
    ProxySource(
      name: 'ALIILAPRO',
      url: 'https://raw.githubusercontent.com/ALIILAPRO/MTProtoProxy/main/mtproto.txt',
      format: 'auto',
      weight: 3,
    ),
  ];

  static const List<ProxySource> fallbackSources = [
    ProxySource(
      name: 'SoliSpirit-mirror',
      url: 'https://cdn.jsdelivr.net/gh/SoliSpirit/mtproto@master/all_proxies.txt',
      format: 'auto',
      weight: 2,
    ),
    ProxySource(
      name: 'Grim1313-HTML',
      url: 'https://raw.githubusercontent.com/Grim1313/mtproto-for-telegram/master/all_proxies.html',
      format: 'html',
      weight: 2,
    ),
  ];
}
