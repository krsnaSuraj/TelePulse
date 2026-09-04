import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class AnimatedStatusOrb extends StatefulWidget {
  final bool isOnline;
  final bool isTesting;
  final int aliveCount;
  final int totalCount;
  final double size;

  const AnimatedStatusOrb({
    super.key,
    required this.isOnline,
    required this.isTesting,
    required this.aliveCount,
    required this.totalCount,
    this.size = 56,
  });

  @override
  State<AnimatedStatusOrb> createState() => _AnimatedStatusOrbState();
}

class _AnimatedStatusOrbState extends State<AnimatedStatusOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _animationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsEnabled =
        MediaQuery.of(context).disableAnimations == false;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(AnimatedStatusOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isTesting != widget.isTesting ||
        oldWidget.isOnline != widget.isOnline) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (!mounted) return;
    if (widget.isTesting && _animationsEnabled) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      if (_controller.isAnimating) _controller.stop();
      if (_controller.value != 0) _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _color => widget.isTesting
      ? AppColors.signal
      : widget.isOnline && widget.aliveCount > 0
          ? AppColors.alive
          : AppColors.warn;

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return RepaintBoundary(
      child: Semantics(
        label: widget.isTesting
            ? 'Scanning, ${widget.aliveCount} of ${widget.totalCount} working'
            : '${widget.aliveCount} of ${widget.totalCount} proxies working',
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  _pulseRing(color),
                  child!,
                  _dashRing(color),
                ],
              );
            },
            child: _centerCircle(color),
          ),
        ),
      ),
    );
  }

  Widget _pulseRing(Color color) {
    final t = _controller.value;
    final scale = 0.88 + 0.12 * ((math.sin(t * 2 * math.pi) + 1) / 2);
    return Transform.scale(
      scale: scale,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.07),
        ),
      ),
    );
  }

  Widget _centerCircle(Color color) {
    return Container(
      width: widget.size * 0.72,
      height: widget.size * 0.72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        color: color.withValues(alpha: 0.10),
      ),
      alignment: Alignment.center,
      child: Text(
        '${widget.aliveCount}',
        style: TextStyle(
          fontSize: widget.size * 0.26,
          fontWeight: FontWeight.w700,
          color: color,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _dashRing(Color color) {
    return Transform.rotate(
      angle: _controller.value * 2 * math.pi,
      child: SizedBox(
        width: widget.size * 0.94,
        height: widget.size * 0.94,
        child: CustomPaint(painter: _OrbPainter(color: color)),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final Color color;
  _OrbPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    const dashCount = 12;
    final dashAngle = 2 * math.pi / dashCount;
    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2;
    final inner = outer - 4;

    for (var i = 0; i < dashCount; i++) {
      final angle = dashAngle * i;
      canvas.drawLine(
        Offset(
          center.dx + inner * math.cos(angle),
          center.dy + inner * math.sin(angle),
        ),
        Offset(
          center.dx + outer * math.cos(angle),
          center.dy + outer * math.sin(angle),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) =>
      oldDelegate.color != color;
}
