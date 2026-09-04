import 'package:flutter/material.dart';

class TiltCard extends StatefulWidget {
  final Widget child;
  final double maxTilt;

  const TiltCard({super.key, required this.child, this.maxTilt = 0.09});

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard>
    with SingleTickerProviderStateMixin {
  double _rx = 0;
  double _ry = 0;
  double _fromX = 0;
  double _fromY = 0;
  late final AnimationController _spring;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..addListener(_onSpringTick);
  }

  void _onSpringTick() {
    if (!mounted) return;
    final t = Curves.easeOut.transform(_spring.value);
    setState(() {
      _rx = _fromX * (1 - t);
      _ry = _fromY * (1 - t);
    });
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _onHorizontalUpdate(DragUpdateDetails d, double width) {
    final nx = (d.delta.dx / width).clamp(-0.5, 0.5);
    _spring.stop();
    setState(() {
      _ry = (_ry + nx * 4 * widget.maxTilt)
          .clamp(-widget.maxTilt * 2, widget.maxTilt * 2);
      _rx = (_rx * 0.9).clamp(-widget.maxTilt, widget.maxTilt);
    });
  }

  bool _motionGated(BuildContext context) {
    return MediaQuery.of(context).disableAnimations ||
        !TickerMode.valuesOf(context).enabled;
  }

  void _onPanEnd() {
    if (!mounted) return;
    if (_motionGated(context)) {
      // Bounded spring would never tick while muted — snap back instantly
      // so the card can't get stuck tilted. No logic change, same gesture.
      _spring.stop();
      setState(() {
        _rx = 0;
        _ry = 0;
      });
      return;
    }
    _fromX = _rx;
    _fromY = _ry;
    _spring
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardSize =
            Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (d) =>
              _onHorizontalUpdate(d, cardSize.width),
          onHorizontalDragEnd: (_) => _onPanEnd(),
          onHorizontalDragCancel: _onPanEnd,
          child: RepaintBoundary(
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateX(_rx)
                ..rotateY(_ry),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

class Pressable extends StatefulWidget {
  final Widget child;
  final double pressedScale;

  const Pressable(
      {super.key, required this.child, this.pressedScale = 0.985});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _setDown(bool value) {
    if (_down == value || !mounted) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    // Listener (not GestureDetector) so press feedback never steals taps
    // from the wrapped button — same taps do the same things.
    // AnimatedScale is implicit and auto-skips when disableAnimations is on.
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setDown(true),
      onPointerUp: (_) => _setDown(false),
      onPointerCancel: (_) => _setDown(false),
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
