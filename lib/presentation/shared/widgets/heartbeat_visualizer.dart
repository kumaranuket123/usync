import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../painters/heartbeat_painter.dart';

class HeartbeatVisualizer extends StatefulWidget {
  const HeartbeatVisualizer({
    super.key,
    this.color  = AppColors.pinkLight,
    this.width  = 270.0,
    this.height = 48.0,
  });

  final Color  color;
  final double width;
  final double height;

  @override
  State<HeartbeatVisualizer> createState() => _HeartbeatVisualizerState();
}

class _HeartbeatVisualizerState extends State<HeartbeatVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
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
      builder: (_, __) => CustomPaint(
        size: Size(widget.width, widget.height),
        painter: HeartbeatPainter(
          scanProgress: _ctrl.value,
          color:        widget.color,
        ),
      ),
    );
  }
}
