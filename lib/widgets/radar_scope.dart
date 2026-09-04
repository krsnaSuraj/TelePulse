import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/proxy_model.dart';

class RadarBlip {
  final double angle;
  final double radiusFraction;
  final Color color;
  final double size;
  final String semantic;

  const RadarBlip({
    required this.angle,
    required this.radiusFraction,
    required this.color,
    required this.size,
    required this.semantic,
  });
}

List<RadarBlip> layoutRadarBlips(List<ProxyModel> proxies, {int max = 36}) {
  final blips = <RadarBlip>[];
  for (final p in proxies.take(max)) {
    final h1 = p.key.hashCode & 0x7fffffff;
    final h2 = (p.key.hashCode >> 7) & 0x7fffffff;
    final angle = (h1 % 3600) / 10.0;
    final radiusFraction = 0.22 + (h2 % 68) / 100.0;
    final (color, label) = _blipStyle(p);
    blips.add(RadarBlip(
      angle: angle,
      radiusFraction: radiusFraction.clamp(0.15, 0.92),
      color: color,
      size: p.isAlive ? (p.latencyMs < 150 ? 5.5 : 4.5) : 3.5,
      semantic: '${p.server} $label',
    ));
  }
  return blips;
}

(Color, String) _blipStyle(ProxyModel p) {
  if (!p.isAlive) {
    return p.isUntested
        ? (AppColors.textMuted, 'not tested')
        : (AppColors.dead, 'dead');
  }
  if (p.latencyMs < 150) return (AppColors.alive, 'fast');
  if (p.latencyMs < 400) return (AppColors.warn, 'okay');
  return (AppColors.slowAlive, 'slow');
}

class RadarScope extends StatefulWidget {
  final List<RadarBlip> blips;
  final bool sweeping;
  final double size;

  const RadarScope({
    super.key,
    required this.blips,
    required this.sweeping,
    this.size = 208,
  });

  @override
  State<RadarScope> createState() => _RadarScopeState();
}

class _RadarScopeState extends State<RadarScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _animationsEnabled = true;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsEnabled =
        MediaQuery.of(context).disableAnimations == false;
    // Explicit TickerMode gate: hidden tabs (IndexedStack) must not burn
    // frames on the sweep. vsync muting alone would freeze mid-cycle.
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(RadarScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sweeping != widget.sweeping) _sync();
  }

  void _sync() {
    if (!mounted) return;
    if (widget.sweeping && _animationsEnabled && _tickerEnabled) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  bool get _effectiveSweeping =>
      widget.sweeping && _animationsEnabled && _tickerEnabled;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // When animations are off, force a static disc (no frozen sweep trail).
    final bool sweeping = _effectiveSweeping;
    return RepaintBoundary(
      child: Semantics(
        label: widget.sweeping
            ? 'Scanning radar, ${widget.blips.length} signals plotted'
            : '${widget.blips.length} signals plotted on radar',
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _RadarPainter(
                blips: widget.blips,
                sweepAngle: _controller.value * 2 * math.pi,
                sweeping: sweeping,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<RadarBlip> blips;
  final double sweepAngle;
  final bool sweeping;

  static final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = AppColors.signal.withValues(alpha: 0.22);
  static final Paint _crossPaint = Paint()
    ..strokeWidth = 1
    ..color = AppColors.signal.withValues(alpha: 0.12);
  static final Paint _sweepLinePaint = Paint()
    ..strokeWidth = 2
    ..color = AppColors.signal.withValues(alpha: 0.85);
  static final Paint _centerPaint = Paint()..color = AppColors.signal;
  static final Paint _sweepSlicePaint = Paint();
  static final Map<Color, Paint> _blipPaints = {};
  static final Map<Color, Paint> _blipGlowPaints = {};
  static final Path _slicePath = Path();

  _RadarPainter({
    required this.blips,
    required this.sweepAngle,
    required this.sweeping,
  });

  static Paint _blipPaint(Color color) => _blipPaints.putIfAbsent(
      color, () => Paint()..color = color);
  static Paint _blipGlowPaint(Color color) => _blipGlowPaints.putIfAbsent(
      color, () => Paint()..color = color.withValues(alpha: 0.18));

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    for (final f in [1.0, 0.66, 0.33]) {
      canvas.drawCircle(center, radius * f, _ringPaint);
    }
    canvas.drawLine(
        Offset(center.dx - radius, center.dy),
        Offset(center.dx + radius, center.dy),
        _crossPaint);
    canvas.drawLine(
        Offset(center.dx, center.dy - radius),
        Offset(center.dx, center.dy + radius),
        _crossPaint);

    if (sweeping) {
      const slices = 28;
      for (var i = 0; i < slices; i++) {
        final start = sweepAngle - (i + 1) * 0.035;
        final fade = 1 - i / slices;
        _slicePath
          ..reset()
          ..moveTo(center.dx, center.dy)
          ..arcTo(Rect.fromCircle(center: center, radius: radius),
              start, 0.035, false)
          ..close();
        canvas.drawPath(
          _slicePath,
          _sweepSlicePaint
            ..color =
                AppColors.signal.withValues(alpha: 0.16 * fade * fade),
        );
      }
      canvas.drawLine(
        center,
        Offset(
          center.dx + radius * math.cos(sweepAngle),
          center.dy + radius * math.sin(sweepAngle),
        ),
        _sweepLinePaint,
      );
    }

    for (final blip in blips) {
      final rad = blip.angle * math.pi / 180;
      final r = radius * blip.radiusFraction;
      final pos = Offset(
        center.dx + r * math.cos(rad),
        center.dy + r * math.sin(rad),
      );
      // Micro-polish: blips just passed by the sweep glow briefly.
      // Cheap (angle math only) and only evaluated while sweeping.
      double glowBoost = 0;
      double sizeBoost = 0;
      if (sweeping) {
        double diff = (sweepAngle - rad) % (2 * math.pi);
        if (diff < 0) diff += 2 * math.pi;
        if (diff < 1.1) {
          final recency = 1 - diff / 1.1;
          glowBoost = recency;
          sizeBoost = recency * 1.2;
        }
      }
      if (glowBoost > 0) {
        canvas.drawCircle(
          pos,
          blip.size + 3.5 + sizeBoost,
          Paint()..color = blip.color.withValues(alpha: 0.18 + 0.30 * glowBoost),
        );
      } else {
        canvas.drawCircle(pos, blip.size + 3.5, _blipGlowPaint(blip.color));
      }
      canvas.drawCircle(pos, blip.size + sizeBoost, _blipPaint(blip.color));
    }

    canvas.drawCircle(center, 3, _centerPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.sweepAngle != sweepAngle ||
      oldDelegate.sweeping != sweeping ||
      !identical(oldDelegate.blips, blips);
}
