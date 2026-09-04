import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'brand_mark.dart';

// OWNER INTEGRATION (app.dart is owned elsewhere — one line, no logic change):
//   home: LaunchIntro(child: const _FlushOnBackground(child: MainShell())),
// Widget-layer only: [child] builds immediately underneath so provider init
// and first paint are never blocked. The overlay is purely visual, plays a
// ~900ms emblem + single radar sweep boot, then fades (250ms). Tap skips.

class LaunchIntro extends StatefulWidget {
  final Widget child;
  final Duration bootDuration;
  final Duration fadeDuration;

  const LaunchIntro({
    super.key,
    required this.child,
    this.bootDuration = const Duration(milliseconds: 900),
    this.fadeDuration = const Duration(milliseconds: 250),
  });

  @override
  State<LaunchIntro> createState() => _LaunchIntroState();
}

class _LaunchIntroState extends State<LaunchIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _boot;
  bool _fading = false;
  bool _gone = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _boot = AnimationController(vsync: this, duration: widget.bootDuration)
      ..addStatusListener(_onBootStatus);
  }

  void _onBootStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && !_gone) {
      setState(() => _fading = true);
      unawaited(Future<void>.delayed(widget.fadeDuration).then((_) {
        if (mounted && !_gone) setState(() => _gone = true);
      }));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Instant skip: reduced motion, muted tickers, or zero test durations.
    if (MediaQuery.of(context).disableAnimations ||
        !TickerMode.valuesOf(context).enabled ||
        widget.bootDuration == Duration.zero) {
      _boot.stop();
      _gone = true;
      return;
    }
    _boot.forward();
  }

  @override
  void didUpdateWidget(LaunchIntro oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bootDuration != widget.bootDuration) {
      _boot.duration = widget.bootDuration;
    }
  }

  @override
  void dispose() {
    _boot.removeStatusListener(_onBootStatus);
    _boot.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_gone || !mounted) return;
    _boot.stop();
    setState(() => _gone = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return widget.child;
    return Stack(
      children: [
        widget.child,
        // Tap anywhere skips; overlay never blocks child init.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _dismiss,
          child: AnimatedOpacity(
            opacity: _fading ? 0 : 1,
            duration: widget.fadeDuration,
            child: Container(
              color: AppColors.surface,
              alignment: Alignment.center,
              child: AnimatedBuilder(
                animation: _boot,
                builder: (context, _) {
                  final double t = Curves.easeOutCubic
                      .transform(_boot.value.clamp(0.0, 1.0));
                  return Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.82 + 0.18 * t,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RepaintBoundary(
                            child: CustomPaint(
                              size: const Size(120, 120),
                              painter: _BootRadarPainter(
                                sweep: _boot.value * 2 * math.pi,
                                emblemT: t,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const BrandMark(size: 40),
                          const SizedBox(height: 12),
                          const Text(
                            'TelePulse',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.5,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'FIND SIGNAL ANYWHERE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 3.5,
                              color: AppColors.signal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BootRadarPainter extends CustomPainter {
  final double sweep;
  final double emblemT;

  _BootRadarPainter({required this.sweep, required this.emblemT});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2;

    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.signal.withValues(alpha: 0.30 * emblemT + 0.05);
    for (final double f in const [1.0, 0.66, 0.33]) {
      canvas.drawCircle(center, radius * f, ring);
    }

    // Single bounded sweep (not an infinite ticker).
    final Path slice = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        sweep - 0.9,
        0.9,
        false,
      )
      ..close();
    canvas.drawPath(
      slice,
      Paint()..color = AppColors.signal.withValues(alpha: 0.18 * emblemT),
    );
    canvas.drawLine(
      center,
      Offset(
        center.dx + radius * math.cos(sweep),
        center.dy + radius * math.sin(sweep),
      ),
      Paint()
        ..strokeWidth = 2
        ..color = AppColors.signal.withValues(alpha: 0.9 * emblemT),
    );
    canvas.drawCircle(center, 3, Paint()..color = AppColors.signal);
  }

  @override
  bool shouldRepaint(covariant _BootRadarPainter oldDelegate) =>
      oldDelegate.sweep != sweep || oldDelegate.emblemT != emblemT;
}
