String formatLatency(int latencyMs) {
  if (latencyMs < 0) return '--';
  return '${latencyMs}ms';
}

String timeAgoShort(DateTime? time, {DateTime? now}) {
  if (time == null) return 'never';
  final ref = now ?? DateTime.now();
  var delta = ref.difference(time).inSeconds;
  if (delta < 0) delta = 0;
  if (delta < 60) return 'just now';
  final minutes = delta ~/ 60;
  if (minutes < 60) return '${minutes}m ago';
  final hours = minutes ~/ 60;
  if (hours < 24) return '${hours}h ago';
  final days = hours ~/ 24;
  return '${days}d ago';
}

String regionFromSource(String source) {
  final lower = source.toLowerCase();
  if (lower.contains('-eu')) return 'EU';
  if (lower.contains('-ru')) return 'RU';
  if (lower.contains('-us')) return 'US';
  if (lower.contains('-asia')) return 'ASIA';
  return '';
}
