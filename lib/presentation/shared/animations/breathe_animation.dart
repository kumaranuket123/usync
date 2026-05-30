import 'package:flutter/material.dart';

import '../../../core/theme/app_animations.dart';

/// Wraps [child] in a looping gentle scale + opacity breath animation.
class BreatheAnimation extends StatefulWidget {
  const BreatheAnimation({
    super.key,
    required this.child,
    this.duration = AppAnimations.breathe,
    this.minScale = 1.0,
    this.maxScale = 1.07,
    this.delay    = Duration.zero,
  });

  final Widget   child;
  final Duration duration;
  final double   minScale;
  final double   maxScale;
  final Duration delay;

  @override
  State<BreatheAnimation> createState() => _BreatheAnimationState();
}

class _BreatheAnimationState extends State<BreatheAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _scale = Tween<double>(begin: widget.minScale, end: widget.maxScale).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}
