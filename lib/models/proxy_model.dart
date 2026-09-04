import '../core/app_constants.dart';

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
  final int connectionFailures;
  final bool mtpVerified;
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
    this.connectionFailures = 0,
    this.mtpVerified = false,
  }) : protocolType = ProxyModel._detectProtocol(secret);

  static ProxyProtocolType _detectProtocol(String secret) {
    if (secret.startsWith('ee')) return ProxyProtocolType.fakeTls;
    if (secret.startsWith('dd')) return ProxyProtocolType.ddPadding;
    return ProxyProtocolType.plain;
  }

  bool get isUntested => !isAlive && lastChecked == null && latencyMs < 0;

  bool get isValidForCache =>
      server.isNotEmpty &&
      port >= 1 &&
      port <= 65535 &&
      secret.length >= AppConstants.minSecretLength;

  String get key => '$server:$port:$secret';

  ProxyModel copyWith({
    String? server,
    int? port,
    String? secret,
    String? source,
    int? latencyMs,
    bool? isAlive,
    DateTime? lastChecked,
    bool? isFavorite,
    int? connectionFailures,
    bool? mtpVerified,
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
      connectionFailures: connectionFailures ?? this.connectionFailures,
      mtpVerified: mtpVerified ?? this.mtpVerified,
    );
  }

  ProxyModel withTestResult({
    required bool alive,
    required int latency,
    DateTime? checkedAt,
    int? failures,
  }) {
    return copyWith(
      isAlive: alive,
      latencyMs: latency,
      lastChecked: checkedAt ?? DateTime.now(),
      connectionFailures: failures ?? connectionFailures,
    );
  }

  String get proxyLink =>
      'tg://proxy?server=${Uri.encodeComponent(server)}&port=$port&secret=${Uri.encodeComponent(secret)}';

  String get tmeLink =>
      'https://t.me/proxy?server=${Uri.encodeComponent(server)}&port=$port&secret=${Uri.encodeComponent(secret)}';

  Map<String, dynamic> toJson() => {
        'server': server,
        'port': port,
        'secret': secret,
        'source': source,
        'latencyMs': latencyMs,
        'isAlive': isAlive,
        'lastChecked': lastChecked?.toIso8601String(),
        'isFavorite': isFavorite,
        'connectionFailures': connectionFailures,
        'mtpVerified': mtpVerified,
      };

  factory ProxyModel.fromJson(Map<String, dynamic> json) {
    final server = json['server'];
    final secret = json['secret'];
    return ProxyModel(
      server: server is String ? server : '',
      port: _parsePort(json['port']),
      secret: secret is String ? secret : '',
      source: json['source'] is String
          ? json['source'] as String
          : 'unknown',
      latencyMs: json['latencyMs'] is int ? json['latencyMs'] as int : -1,
      isAlive: json['isAlive'] == true,
      lastChecked: _safeParseDateTime(json['lastChecked']),
      isFavorite: json['isFavorite'] == true,
      connectionFailures:
          json['connectionFailures'] is int
              ? json['connectionFailures'] as int
              : 0,
      mtpVerified: json['mtpVerified'] == true,
    );
  }

  static int _parsePort(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? _safeParseDateTime(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } on FormatException {
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
          secret == other.secret &&
          source == other.source &&
          latencyMs == other.latencyMs &&
          isAlive == other.isAlive &&
          lastChecked == other.lastChecked &&
          isFavorite == other.isFavorite &&
          mtpVerified == other.mtpVerified &&
          connectionFailures == other.connectionFailures;

  @override
  int get hashCode => Object.hash(server, port, secret, source, latencyMs,
      isAlive, lastChecked, isFavorite, mtpVerified, connectionFailures);

  @override
  String toString() => 'ProxyModel($server:$port)';
}
