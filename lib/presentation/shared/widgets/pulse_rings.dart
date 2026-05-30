import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../painters/glow_ring_painter.dart';

class PulseRings extends StatefulWidget {
  const PulseRings({
    super.key,
    this.color      = AppColors.pink,
    this.count      = 3,
    this.size       = 200.0,
    this.cycleDuration = const Duration(milliseconds: 3000),
    this.staggerMs  = 1000,
  });

  final Color    color;
  final int      count;
  final double   size;
  final Duration cycleDuration;
  final int      staggerMs;

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings> with TickerProviderStateMixin {
  final List<AnimationController> _ctrls = [];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.count; i++) {
      final ctrl = AnimationController(vsync: this, duration: widget.cycleDuration);
      _ctrls.add(ctrl);
      Future.delayed(Duration(milliseconds: i * widget.staggerMs), () {
        if (mounted) ctrl.repeat();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: _ctrls.map((ctrl) {
          return AnimatedBuilder(
            animation: ctrl,
            builder: (_, __) => CustomPaint(
              size: Size(widget.size, widget.size),
              painter: GlowRingPainter(progress: ctrl.value, color: widget.color),
            ),
          );
        }).toList(),
      ),
    );
  }
}
