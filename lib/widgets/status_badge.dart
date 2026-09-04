import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/formatters.dart';
import '../models/proxy_model.dart';

class StatusBadge extends StatelessWidget {
  final ProxyModel proxy;

  const StatusBadge({super.key, required this.proxy});

  @override
  Widget build(BuildContext context) {
    final (color, label) = _resolve();
    final shownLabel =
        proxy.mtpVerified && proxy.isAlive ? '✓ $label' : label;
    return Semantics(
      label: proxy.mtpVerified && proxy.isAlive
          ? 'Status: verified working, $label'
          : 'Status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.30), width: 1),
        ),
        child: Text(
          shownLabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.3,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  (Color, String) _resolve() {
    if (proxy.isUntested) {
      return (AppColors.textMuted, 'NEW');
    }
    if (!proxy.isAlive) {
      return (AppColors.dead, 'DEAD');
    }
    const slowAlive = AppColors.slowAlive;
    final l = proxy.latencyMs;
    if (l < 150) return (AppColors.alive, formatLatency(l));
    if (l < 400) return (AppColors.warn, formatLatency(l));
    return (slowAlive, formatLatency(l));
  }
}

class ProtocolChip extends StatelessWidget {
  final ProxyProtocolType type;

  const ProtocolChip({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case ProxyProtocolType.fakeTls:
        return _chip('TLS', AppColors.alive, 'FakeTLS disguise supported');
      case ProxyProtocolType.ddPadding:
        return _chip('DD', AppColors.warn, 'Padded transport');
      case ProxyProtocolType.plain:
        return const SizedBox.shrink();
    }
  }

  Widget _chip(String label, Color color, String semantic) {
    return Semantics(
      label: semantic,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: color,
          ),
        ),
      ),
    );
  }
}
