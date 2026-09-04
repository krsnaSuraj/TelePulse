import '../models/proxy_model.dart';

enum ProxyFilter { all, working, favorites }

enum ProxySort { rank, latency, recentlyChecked, server }

extension ProxySortLabel on ProxySort {
  String get label => switch (this) {
        ProxySort.rank => 'Best first',
        ProxySort.latency => 'Lowest latency',
        ProxySort.recentlyChecked => 'Recently checked',
        ProxySort.server => 'Server name',
      };
}

List<ProxyModel> applyProxyView(
  List<ProxyModel> source, {
  ProxyFilter filter = ProxyFilter.all,
  ProxySort sort = ProxySort.rank,
  String query = '',
}) {
  Iterable<ProxyModel> list = source;
  switch (filter) {
    case ProxyFilter.all:
      break;
    case ProxyFilter.working:
      list = list.where((p) => p.isAlive);
      break;
    case ProxyFilter.favorites:
      list = list.where((p) => p.isFavorite);
      break;
  }
  final q = query.trim().toLowerCase();  if (q.isNotEmpty) {
    list = list.where((p) =>
        p.server.toLowerCase().contains(q) ||
        p.source.toLowerCase().contains(q) ||
        p.port.toString().contains(q));
  }
  final result = list.toList(growable: false);
  switch (sort) {
    case ProxySort.rank:
      break;
    case ProxySort.latency:
      result.sort((a, b) {
        if (a.isAlive != b.isAlive) return a.isAlive ? -1 : 1;
        final c = a.latencyMs.compareTo(b.latencyMs);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
      break;
    case ProxySort.recentlyChecked:
      result.sort((a, b) {
        final at = a.lastChecked?.millisecondsSinceEpoch ?? -1;
        final bt = b.lastChecked?.millisecondsSinceEpoch ?? -1;
        final c = bt.compareTo(at);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
      break;
    case ProxySort.server:
      result.sort((a, b) {
        final c = a.server.compareTo(b.server);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
      break;
  }
  return result;
}

String describeView({
  required int visible,
  required int tested,
  required int working,
  required ProxySort sort,
  required String query,
}) {
  final base = '$visible shown · $tested tested · $working working';
  final trimmed = query.trim();
  final extras = <String>[
    if (trimmed.isNotEmpty) 'matching "$trimmed"',
    if (sort != ProxySort.rank) 'sorted by ${sort.label.toLowerCase()}',
  ];
  return extras.isEmpty ? base : '$base · ${extras.join(' · ')}';
}
