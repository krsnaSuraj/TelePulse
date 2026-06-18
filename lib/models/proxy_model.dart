enum ProxyProtocolType { plain, fakeTls, ddPadding }

class ProxyModel {
  final String server;
  final int port;
  final String secret;
  final String source;
  final int latencyMs;
  final bool isAlive;
  final DateTime? lastChecked;
  final bool isFavorite;
  final ProxyProtocolType protocolType;

  ProxyModel({
    required this.server,
    required this.port,
    required this.secret,
    this.source = 'unknown',
    this.latencyMs = -1,
    this.isAlive = false,
    this.lastChecked,
    this.isFavorite = false,
  }) : protocolType = ProxyModel._detectProtocol(secret);

  static ProxyProtocolType _detectProtocol(String secret) {
    if (secret.startsWith('ee')) return ProxyProtocolType.fakeTls;
    if (secret.startsWith('dd')) return ProxyProtocolType.ddPadding;
    return ProxyProtocolType.plain;
  }

  bool get isFakeTls => protocolType == ProxyProtocolType.fakeTls;

  ProxyModel copyWith({
    String? server,
    int? port,
    String? secret,
    String? source,
    int? latencyMs,
    bool? isAlive,
    DateTime? lastChecked,
    bool? isFavorite,
  }) {
    return ProxyModel(
      server: server ?? this.server,
      port: port ?? this.port,
      secret: secret ?? this.secret,
      source: source ?? this.source,
      latencyMs: latencyMs ?? this.latencyMs,
      isAlive: isAlive ?? this.isAlive,
      lastChecked: lastChecked ?? this.lastChecked,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  String get proxyLink =>
      'tg://proxy?server=${Uri.encodeComponent(server)}&port=$port&secret=${Uri.encodeComponent(secret)}';

  String get tmeLink =>
      'https://t.me/proxy?server=${Uri.encodeComponent(server)}&port=$port&secret=${Uri.encodeComponent(secret)}';

  String get displayServer {
    if (server.length > 24) return '${server.substring(0, 24)}.';
    return server;
  }

  Map<String, dynamic> toJson() => {
        'server': server,
        'port': port,
        'secret': secret,
        'source': source,
        'latencyMs': latencyMs,
        'isAlive': isAlive,
        'lastChecked': lastChecked?.toIso8601String(),
        'isFavorite': isFavorite,
      };

  factory ProxyModel.fromJson(Map<String, dynamic> json) => ProxyModel(
        server: json['server'] as String? ?? '',
        port: json['port'] is int
            ? json['port'] as int
            : int.tryParse('${json['port']}') ?? 0,
        secret: json['secret'] as String? ?? '',
        source: json['source'] as String? ?? 'unknown',
        latencyMs: json['latencyMs'] as int? ?? -1,
        isAlive: json['isAlive'] as bool? ?? false,
        lastChecked: _safeParseDateTime(json['lastChecked']),
        isFavorite: json['isFavorite'] as bool? ?? false,
      );

  static DateTime? _safeParseDateTime(dynamic value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value as String);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProxyModel &&
          runtimeType == other.runtimeType &&
          server == other.server &&
          port == other.port &&
          secret == other.secret;

  @override
  int get hashCode => Object.hash(server, port, secret);

  @override
  String toString() => 'ProxyModel($server:$port)';
}
