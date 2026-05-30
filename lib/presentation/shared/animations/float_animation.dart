import 'package:flutter/material.dart';

import '../../../core/theme/app_animations.dart';

/// Floats [child] upward on a looping animation, fading in at start
/// and fading out at end. Used for floating emoji reactions.
class FloatAnimation extends StatefulWidget {
  const FloatAnimation({
    super.key,
    required this.child,
    this.duration = AppAnimations.floatUp,
    this.delay    = Duration.zero,
    this.distance = 800.0,
  });

  final Widget   child;
  final Duration duration;
  final Duration delay;
  final double   distance;

  @override
  State<FloatAnimation> createState() => _FloatAnimationState();
}

class _FloatAnimationState extends State<FloatAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _y;
  late final Animation<double>   _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);

    _y = Tween<double>(begin: 0, end: -widget.distance).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.linear),
    );

    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1),         weight: 80),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 10),
    ]).animate(_ctrl);

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _y.value),
        child: Opacity(opacity: _opacity.value, child: child),
      ),
      child: widget.child,
    );
  }
}
