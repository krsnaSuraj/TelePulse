import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  final bool isAlive;
  final int latencyMs;

  const StatusBadge({
    super.key,
    required this.isAlive,
    this.latencyMs = -1,
  });

  @override
  Widget build(BuildContext context) {
    if (!isAlive) {
      return _Badge(
        color: AppColors.dead,
        label: 'OFFLINE',
      );
    }

    final (color, label) = switch (latencyMs) {
      >= 0 && < 150 => (AppColors.alive, '${latencyMs}ms'),
      >= 150 && < 400 => (AppColors.warning, '${latencyMs}ms'),
      >= 400 => (AppColors.dead, '${latencyMs}ms'),
      _ => (AppColors.alive, 'ALIVE'),
    };

    return _Badge(color: color, label: label);
  }
}

class _Badge extends StatelessWidget {
  final Color color;
  final String label;

  const _Badge({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
