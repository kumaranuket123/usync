import 'package:flutter/material.dart';

/// Draws a single expanding ring — scale driven externally.
class GlowRingPainter extends CustomPainter {
  const GlowRingPainter({required this.progress, required this.color});

  final double progress; // 0.0 – 1.0 from AnimationController
  final Color  color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) * (0.8 + progress * 1.2);
    final opacity = (1.0 - progress).clamp(0.0, 1.0);

    final paint = Paint()
      ..color = color.withOpacity(opacity * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(GlowRingPainter old) => old.progress != progress;
}
