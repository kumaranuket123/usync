import 'package:flutter/material.dart';

/// Fade + slide-up entrance with a configurable [delay].
class StaggerAnimation extends StatefulWidget {
  const StaggerAnimation({
    super.key,
    required this.child,
    this.delay       = Duration.zero,
    this.duration    = const Duration(milliseconds: 400),
    this.slideOffset = 24.0,
  });

  final Widget   child;
  final Duration delay;
  final Duration duration;
  final double   slideOffset;

  @override
  State<StaggerAnimation> createState() => _StaggerAnimationState();
}

class _StaggerAnimationState extends State<StaggerAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _opacity;
  late final Animation<Offset>   _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide   = Tween<Offset>(
      begin: Offset(0, widget.slideOffset / 100),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
