import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AnimatedStatusOrb extends StatefulWidget {
  final bool isOnline;
  final int aliveCount;
  final int totalCount;
  final bool isTesting;
  final double size;

  const AnimatedStatusOrb({
    super.key,
    required this.isOnline,
    required this.aliveCount,
    required this.totalCount,
    this.isTesting = false,
    this.size = 100,
  });

  @override
  State<AnimatedStatusOrb> createState() => _AnimatedStatusOrbState();
}

class _AnimatedStatusOrbState extends State<AnimatedStatusOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isTesting
        ? AppColors.terminalGreen
        : widget.isOnline
            ? AppColors.alive
            : AppColors.warning;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _pulseRing(color),
              _centerCircle(color),
              _dashRing(color),
            ],
          ),
        );
      },
    );
  }

  Widget _pulseRing(Color color) {
    final scale = 0.85 + 0.15 * _pulseValue();
    return Transform.scale(
      scale: scale,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.08),
        ),
      ),
    );
  }

  Widget _centerCircle(Color color) {
    return Container(
      width: widget.size * 0.75,
      height: widget.size * 0.75,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(widget.size * 0.15),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '${widget.aliveCount}',
              style: TextStyle(
                fontSize: widget.size * 0.22,
                fontWeight: FontWeight.w700,
                color: color,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashRing(Color color) {
    final angle = _controller.value * 2 * math.pi;
    return Transform.rotate(
      angle: angle,
      child: SizedBox(
        width: widget.isTesting ? widget.size * 0.92 : widget.size * 0.9,
        height: widget.isTesting ? widget.size * 0.92 : widget.size * 0.9,
        child: CustomPaint(
          painter: widget.isTesting
              ? _ScanPainter(color: color)
              : _OrbPainter(color: color),
        ),
      ),
    );
  }

  double _pulseValue() {
    return (math.sin(_controller.value * 2 * math.pi) + 1) / 2;
  }
}

class _OrbPainter extends CustomPainter {
  final Color color;
  _OrbPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    const dashCount = 12;
    final dashAngle = 2 * math.pi / dashCount;

    for (var i = 0; i < dashCount; i++) {
      final angle = dashAngle * i;
      final x1 = size.width / 2 + (size.width / 2 - 4) * math.cos(angle);
      final y1 = size.height / 2 + (size.height / 2 - 4) * math.sin(angle);
      final x2 = size.width / 2 + (size.width / 2) * math.cos(angle);
      final y2 = size.height / 2 + (size.height / 2) * math.sin(angle);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ScanPainter extends CustomPainter {
  final Color color;
  _ScanPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final sweepPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final arcPath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 1.2,
        true,
      )
      ..close();
    canvas.drawPath(arcPath, sweepPaint);

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      Offset(
        center.dx + radius * math.cos(-math.pi / 2 + math.pi * 1.2),
        center.dy + radius * math.sin(-math.pi / 2 + math.pi * 1.2),
      ),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanPainter oldDelegate) =>
      oldDelegate.color != color;
}
