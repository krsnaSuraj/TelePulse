import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class BrandMark extends StatelessWidget {
  final double size;

  const BrandMark({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'TelePulse logo',
      // Small painter — RepaintBoundary isolates it per 60fps-budget rules.
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(size, size),
          painter: _BrandMarkPainter(),
        ),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  static const _bolt = [
    (0.10, -0.34),
    (-0.16, 0.06),
    (-0.05, 0.06),
    (-0.10, 0.34),
    (0.16, -0.08),
    (0.05, -0.08),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const amber = AppColors.signal;

    // Outer full ring — always fully visible (was partial arc, looked clipped).
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round
      ..color = amber;
    canvas.drawCircle(center, radius * 0.78, outer);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.035
      ..color = amber.withValues(alpha: 0.35);
    canvas.drawCircle(center, radius * 0.62, ring);

    final s = size.width * 0.62;
    final path = Path()
      ..moveTo(
          center.dx + _bolt[0].$1 * s, center.dy + _bolt[0].$2 * s);
    for (var i = 1; i < _bolt.length; i++) {
      path.lineTo(
          center.dx + _bolt[i].$1 * s, center.dy + _bolt[i].$2 * s);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = amber);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Subtle animated brand variant: a slow 1→1.05 breathe + glow pulse.
///
/// Small (default 24px) and cheap — the only infinite ticker here besides
/// the radar sweep, gated by [TickerMode] + [MediaQuery.disableAnimations].
/// Pass [active]: false (or rely on disableAnimations) in tests that use
/// pumpAndSettle; otherwise pump bounded durations only.
class AnimatedBrandMark extends StatefulWidget {
  final double size;
  final bool active;

  const AnimatedBrandMark({super.key, this.size = 24, this.active = true});

  @override
  State<AnimatedBrandMark> createState() => _AnimatedBrandMarkState();
}

class _AnimatedBrandMarkState extends State<AnimatedBrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(AnimatedBrandMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  void _sync() {
    if (!mounted) return;
    final bool want = widget.active &&
        _tickerEnabled &&
        MediaQuery.of(context).disableAnimations == false;
    if (want) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      if (_controller.value != 0) _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || MediaQuery.of(context).disableAnimations) {
      return BrandMark(size: widget.size);
    }
    return RepaintBoundary(
      child: Semantics(
        label: 'TelePulse logo',
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final double phase = _controller.value * 2 * math.pi;
            final double scale = 1 + 0.035 * ((math.sin(phase) + 1) / 2);
            return Transform.scale(scale: scale, child: child);
          },
          child: BrandMark(size: widget.size),
        ),
      ),
    );
  }
}
