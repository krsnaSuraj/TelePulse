import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class AuroraBackground extends StatefulWidget {
  final Widget child;

  const AuroraBackground({super.key, required this.child});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Explicit TickerMode dependency so tab switches re-sync (muted tickers
    // alone would freeze mid-cycle without ever stopping the controller).
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (MediaQuery.of(context).disableAnimations || !_tickerEnabled) {
      _controller.stop();
      _controller.value = 0.25;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Perf budget: this CustomPaint is full-screen, so it must NOT repaint
    // at 60fps. Blobs are low-spatial-frequency, so quantizing t to 48 steps
    // (~2.7 repaints/sec) keeps the drift invisible while shouldRepaint
    // skips every in-between vsync. Radar sweep (small, bounded) is the only
    // allowed full-screen-rate animation.
    final bool willChange =
        _tickerEnabled && !MediaQuery.of(context).disableAnimations;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final double t =
              (_controller.value * 48).roundToDouble() / 48;
          return CustomPaint(
            isComplex: true,
            willChange: willChange,
            painter: _AuroraPainter(t: t),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  _AuroraPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    _blob(
      canvas,
      Offset(
        w * (0.5 + 0.38 * math.cos(t * 2 * math.pi)),
        h * (0.16 + 0.05 * math.sin(t * 4 * math.pi)),
      ),
      w * 0.75,
      AppColors.signal.withValues(alpha: 0.05),
    );
    _blob(
      canvas,
      Offset(
        w * (0.5 + 0.42 * math.cos(t * 2 * math.pi + 2.4)),
        h * (0.72 + 0.06 * math.sin(t * 4 * math.pi + 1.1)),
      ),
      w * 0.85,
      AppColors.alive.withValues(alpha: 0.035),
    );
  }

  void _blob(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()..color = color;
    const rings = 3;
    for (var i = rings; i >= 1; i--) {
      canvas.drawCircle(
        center,
        radius * i / rings,
        paint
          ..color = color.withValues(
              alpha: (color.a * (1 - i / (rings + 1))).clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) =>
      oldDelegate.t != t;
}
